# Cambio: Refactor MP credentials — mp_connections → nv_accounts

- **Autor:** agente-copilot
- **Fecha:** 2025-07-24
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Commit:** `ca37246`
- **Archivos modificados:**
  - `src/worker/provisioning-worker.service.ts`
  - `src/mp-oauth/mp-oauth.service.ts`
  - `src/workers/mp-token-refresh.worker.ts`

---

## Resumen

Refactor completo de toda la capa de lectura de credenciales de Mercado Pago. El sistema tenía una inconsistencia crítica:

- **Write path** (`saveConnection()`): Ya escribía tokens encriptados a columnas de `nv_accounts` (tabla real en producción).
- **Read path** (checkout, refresh, status, revoke): Seguía leyendo de `mp_connections` — una tabla que **nunca existió en producción** (la migración `20250102000000_add_mp_oauth_v1.1.sql` nunca fue aplicada).

Esto causaba:
1. **Error 409 al aprobar clientes** — El provisioning worker hacía SELECT de columnas inexistentes (`mp_access_token`, `mp_public_key`, etc.) en `nv_accounts`. PostgREST devolvía error, el código lo interpretaba como "Account not found".
2. **Checkout roto para todas las tiendas** — `getClientCredentials()` leía de `mp_connections` que no existe → nunca obtenía tokens → preferencias de MP nunca se creaban con credenciales reales.
3. **Token refresh cron inoperante** — Los 2 cron jobs del worker leían/escribían `mp_connections` → fallaban silenciosamente cada 12h y cada día a las 2AM.

---

## Cambios detallados

### 1. `provisioning-worker.service.ts`

| Cambio | Antes | Después |
|--------|-------|---------|
| SELECT L660 | `mp_access_token, mp_public_key, mp_refresh_token, mp_user_id, mp_live_mode, mp_expires_in` | `mp_connected, mp_user_id` |
| MP check L918 | `if (account.mp_access_token)` | `if (account.mp_connected)` |
| Completion L1752 | `!!account.mp_access_token && !!account.mp_public_key` | `account.mp_connected` |
| Error handling | Sin captura de error en SELECT | Captura `accountError` con log explícito |

### 2. `mp-oauth.service.ts`

**`getClientCredentials(clientId)`** — Ahora lee `mp_access_token_encrypted`, `mp_public_key`, `mp_connected` de `nv_accounts`. Verifica `mp_connected === true` y existencia de token antes de desencriptar.

**`refreshTokenForAccount(accountId)`** — Ahora lee `mp_refresh_token` de `nv_accounts`, llama al endpoint OAuth de MP, y escribe `mp_access_token_encrypted`, `mp_refresh_token`, `mp_expires_in`, `mp_connected_at` actualizado de vuelta a `nv_accounts`. En error, marca `mp_connection_status = 'error'`.

**`getConnectionStatus(clientId)`** — Ahora lee `mp_connected`, `mp_live_mode`, `mp_expires_in`, `mp_connection_status`, `mp_user_id`, `mp_connected_at` de `nv_accounts`. Calcula `expires_at` derivado: `mp_connected_at + mp_expires_in * 1000`.

**`revokeConnection(clientId)`** — Ahora limpia tokens y flags en `nv_accounts` directamente (eliminó dual-write a `mp_connections` + `nv_accounts`).

### 3. `mp-token-refresh.worker.ts`

Reescritura completa de ambos cron jobs:

**`refreshExpiringTokens()` (cada 12h):**
- Antes: `SELECT FROM mp_connections WHERE status='connected' AND expires_at < threshold` → fallaba.
- Ahora: `SELECT FROM nv_accounts WHERE mp_connected=true AND mp_access_token_encrypted IS NOT NULL AND mp_refresh_token IS NOT NULL`, filtra en JS por `mp_connected_at + mp_expires_in < now + 24h`.

**`markExpiredConnections()` (diario 2AM):**
- Antes: `UPDATE mp_connections SET status='expired'` → fallaba.
- Ahora: `SELECT FROM nv_accounts WHERE mp_connected=true`, filtra expirados en JS, luego `UPDATE nv_accounts SET mp_connected=false, mp_connection_status='expired'`.

---

## Columnas reales de nv_accounts (verificado en producción)

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `mp_access_token_encrypted` | text | Token encriptado (AES-256-GCM) |
| `mp_refresh_token` | text | Refresh token |
| `mp_public_key` | text | Public key de MP |
| `mp_connected` | boolean | Flag de conexión activa |
| `mp_connected_at` | timestamptz | Timestamp de conexión |
| `mp_connection_status` | text | Estado: connected/error/expired/revoked |
| `mp_expires_in` | integer | Segundos hasta expiración desde grant |
| `mp_live_mode` | boolean | true = producción, false = sandbox |
| `mp_user_id` | varchar | ID de usuario en MP |
| `mp_validated_at` | timestamptz | Última validación |

---

## Flujo de checkout corregido

```
Frontend (checkout) 
  → POST /payments/create-preference
    → MercadoPagoService.getClientMpConfig(clientId)
      → MpOauthService.getClientCredentials(clientId)
        → getAccountForClient(clientId)
          → Backend DB: clients WHERE id = clientId → slug
          → Admin DB: nv_accounts WHERE slug = slug → account
        → Verifica: account.mp_connected === true
        → Verifica: account.mp_access_token_encrypted !== null
        → Desencripta con AES-256-GCM (MP_TOKEN_ENCRYPTION_KEY)
        → Retorna { accessToken, publicKey }
    → Crea preferencia de MP con token real
    → Retorna init_point al frontend
```

---

## Cómo probar

### Aprobar cliente (fix del 409)
1. En admin dashboard, aprobar un cliente con MP configurado
2. Verificar que no aparece error 409 / "Account not found"
3. El provisioning debe completar correctamente

### Checkout multi-tenant
1. Ingresar a una tienda con MP configurado (ej: slug=`test`)
2. Agregar producto al carrito → Checkout
3. Verificar que se crea la preferencia de MP con `init_point` válido
4. Completar pago en sandbox/producción

### Token refresh
1. Verificar logs del worker cada 12h: `Starting MP token refresh worker...`
2. Si hay tokens por expirar en 24h, debe logear `Found N tokens to refresh`
3. No deben aparecer errores de `mp_connections`

---

## Riesgos y mitigación

| Riesgo | Mitigación |
|--------|------------|
| Token desencriptación falla si `MP_TOKEN_ENCRYPTION_KEY` no está configurado | Ya manejado por try/catch existente en `decryptToken()` |
| Tokens ya expirados sin `mp_connected_at` stored | El worker filtra `if (!a.mp_connected_at)` → skip |
| Race conditions en refresh concurrente | Distributed lock via Redis (`mp:refresh:lock:${accountId}`, TTL 30s) ya implementado en `refreshTokenForAccount()` |

---

## Notas de seguridad

- No se modificó la lógica de encriptación/desencriptación de tokens
- No se exponen tokens en logs (se loguean IDs y estados, no valores)
- `SERVICE_ROLE_KEY` sigue siendo server-side only
- RLS no aplica (el backend usa service_role para queries admin)

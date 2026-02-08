# Cambio: Sync de credenciales MP a Backend DB (clients) — Arquitectura dual-DB

- **Autor:** agente-copilot
- **Fecha:** 2025-07-25
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Commits:** `ca37246` (refactor mp_connections → nv_accounts), `450a1e5` (sync a clients + fast-path checkout)

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/mp-oauth/mp-oauth.service.ts` | Nuevo método `syncMpCredentialsToBackend()`, sync en `saveConnection()`, `refreshTokenForAccount()`, `revokeConnection()` |
| `src/tenant-payments/mercadopago.service.ts` | `getClientMpConfig()` reescrito con fast-path desde `clients` |
| `src/worker/provisioning-worker.service.ts` | Step 7.1: sync tokens MP al aprobar cliente |
| `src/worker/worker.module.ts` | Import de `MpOauthModule` |
| `src/workers/mp-token-refresh.worker.ts` | Refactored de `mp_connections` → `nv_accounts` (commit ca37246) |

## Problema detectado

### 1. Tabla `mp_connections` inexistente
Todos los servicios de lectura MP (`getClientCredentials`, `refreshTokenForAccount`, `getConnectionStatus`, `revokeConnection`) consultaban una tabla `mp_connections` que **nunca existió** en producción (migración no aplicada).

### 2. Tokens MP no sincronizados a Backend DB
La tabla `clients` en Backend DB tiene columnas `mp_access_token` y `mp_public_key` pero estaban **siempre en NULL** porque el provisioning worker nunca las copiaba desde Admin DB.

Consecuencia: checkout en tiempo real hacía **cross-database query** a Admin DB para obtener tokens, con latencia adicional y dependencia innecesaria.

## Solución implementada

### Arquitectura dual-DB

```
┌─────────────────────────────────────────────────────────────┐
│ Admin DB (nv_accounts) — ENCRYPTED MASTER                    │
│ ─ mp_access_token_encrypted (AES-256-GCM)                   │
│ ─ mp_public_key                                              │
│ ─ mp_refresh_token (encrypted)                               │
│ ─ mp_connected, mp_user_id, mp_expires_in, etc              │
└───────────────┬─────────────────────────────────────────────┘
                │ sync (decrypt → plain text)
                │ Triggers: provisioning, OAuth save, token refresh, revoke
                ▼
┌─────────────────────────────────────────────────────────────┐
│ Backend DB (clients) — PLAIN-TEXT RUNTIME CACHE              │
│ ─ mp_access_token (text)                                     │
│ ─ mp_public_key (text)                                       │
│ ← checkout lee de aquí (fast path, misma DB)                │
└─────────────────────────────────────────────────────────────┘
```

### Puntos de sincronización

| Evento | Método | Sync |
|--------|--------|------|
| Cliente aprobado (provisioning) | `provisionStep7_1` | `syncMpCredentialsToBackend(accountId, clientId)` |
| OAuth callback (MP conectado) | `saveConnection()` | `syncMpCredentialsToBackend(accountId, clientId)` |
| Token refresh automático | `refreshTokenForAccount()` | UPDATE `clients SET mp_access_token, mp_public_key` |
| Revocación de conexión | `revokeConnection()` | UPDATE `clients SET mp_access_token = NULL, mp_public_key = NULL` |

### Lectura en checkout

`getClientMpConfig(clientId)`:
1. **Fast path**: lee `mp_access_token` y `mp_public_key` de `clients` (Backend DB, misma DB = 0 latencia extra)
2. **Fallback**: si `clients` tiene NULL → lee de `nv_accounts` vía `MpOauthService.getClientCredentials()` (cross-DB, desencripta)
3. Log `warn` cuando usa fallback para monitorear

### Método `syncMpCredentialsToBackend(accountId, clientId)`

```typescript
// 1. Lee nv_accounts (Admin DB) — obtiene token encriptado + public_key
// 2. Desencripta access_token con AES-256-GCM
// 3. Escribe plain text en clients (Backend DB)
// 4. Retorna boolean success
```

## Cómo probar

### Pre-requisito: verificar estado actual
```sql
-- Backend DB: verificar que clients tiene NULL tokens
SELECT id, mp_access_token IS NOT NULL as has_token, mp_public_key 
FROM clients;
```

### Test 1: Provisioning nuevo cliente
1. Crear cuenta con MP conectado en Admin
2. Aprobar cliente → ver logs "✅ Step 7.1: MP credentials synced to Backend DB"
3. Verificar `clients.mp_access_token` IS NOT NULL

### Test 2: Checkout existente
1. Con cliente que tiene tokens sincronizados → checkout debería funcionar sin fallback
2. Verificar logs NO muestran "⚠️ Fast-path miss"

### Test 3: Token refresh  
1. Esperar cron de refresh (o forzar)
2. Verificar que `clients.mp_access_token` se actualiza junto con `nv_accounts`

### Test 4: Revocación
1. Revocar conexión MP
2. Verificar `clients.mp_access_token = NULL`

## Notas de seguridad

- **Admin DB** almacena tokens **encriptados** (AES-256-GCM) — es el master
- **Backend DB** almacena tokens en **plain text** — es cache de runtime
- La `SERVICE_ROLE_KEY` del backend tiene acceso a ambas DBs
- El fallback al Admin DB garantiza que el checkout funciona incluso si el sync falló

## Backfill pendiente

Los 4 clientes existentes en producción tienen `mp_access_token = NULL` en `clients`. Se necesita un backfill manual o script que ejecute `syncMpCredentialsToBackend()` para cada cuenta con `mp_connected = true`.

## Riesgos / Rollback

- **Riesgo bajo**: el fallback garantiza que si el sync falla, el checkout sigue funcionando via Admin DB
- **Rollback**: si se necesita revertir, el checkout simplemente usará siempre el fallback (comportamiento anterior)
- **Monitoreo**: buscar logs `⚠️ Fast-path miss` para detectar desincronizaciones

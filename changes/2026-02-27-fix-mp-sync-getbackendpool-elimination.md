# Fix: Eliminación de getBackendPool — MP sync y operaciones Backend

- **Autor:** agente-copilot  
- **Fecha:** 2026-02-27  
- **Rama:** feature/automatic-multiclient-onboarding  
- **Severidad:** P0 (bug en producción — sync de credenciales MP silenciosamente roto)

---

## Resumen

Se eliminó completamente el stub `getBackendPool()` de `DbRouterService` y se migraron **todos** sus callers (9 call sites en 4 archivos) a `getBackendClient().from()` (Supabase JS query builder).

### Problema raíz

`getBackendPool()` era un wrapper de backward-compatibility que **siempre lanzaba** `Error('Direct SQL queries not supported with Supabase JS')`. Todos los callers atrapaban la excepción o la propagaban, resultando en:

1. **Credenciales MP nunca se sincronizaban** de Admin DB → Backend DB  
2. **`clients.mp_access_token` = NULL** en Backend para tiendas nuevas  
3. **Checkout roto** para cualquier tienda provisionada vía onboarding  

## Archivos modificados

| Archivo | Cambios |
|---------|---------|
| `src/mp-oauth/mp-oauth.service.ts` | 6 call sites migrados, `getAccountForClient` enriquecido con `nv_account_id` fast-path y `backend_cluster_id` |
| `src/worker/provisioning-worker.service.ts` | 2 call sites: MP sync cambiado de warn-on-failure a **hard fail** (throw) |
| `src/admin/admin-client.controller.ts` | 2 call sites: delete y toggle status migrados a Supabase JS |
| `src/plans/services/usage-reset.service.ts` | 1 call site: RPC call migrado a Supabase JS |
| `src/db/db-router.service.ts` | `getBackendPool()` y `getAdminPool()` eliminados |

## Detalle por función corregida

### 1. `syncMpCredentialsToBackend(accountId, clientId)` — mp-oauth.service.ts
- **Antes:** `getBackendPool('cluster_shared_01').query('UPDATE clients SET ...')` → siempre fallaba silenciosamente, retornaba `false`
- **Después:** Lee `backend_cluster_id` de `nv_accounts`, usa `getBackendClient(clusterId).from('clients').update(...)`. Verifica `updateError` y retorna `false` solo si hay error real de DB.

### 2. `getAccountForClient(clientId)` — mp-oauth.service.ts
- **Antes:** `getBackendPool('cluster_shared_01').query('SELECT slug FROM clients WHERE id = $1')` → siempre lanzaba `NotFoundException`
- **Después:** `getBackendClient().from('clients').select('slug, nv_account_id').eq('id', clientId).maybeSingle()`. Fast-path por `nv_account_id` si está disponible, fallback por slug. Retorna `{ id, slug, backend_cluster_id }`.

### 3. `refreshTokenForAccount(accountId)` — mp-oauth.service.ts
- **Antes:** Tras refresh exitoso de tokens con MP API, intentaba sincronizar al Backend con `getBackendPool` → fallaba silenciosamente
- **Después:** Lee `backend_cluster_id` del account (agregado al select), usa `getBackendClient(clusterId)` para SELECT + UPDATE en `clients`.

### 4. `revokeConnection(clientId)` — mp-oauth.service.ts
- **Antes:** `getBackendPool('cluster_shared_01').query('UPDATE clients SET mp_access_token = NULL ...')` → fallaba silenciosamente, tokens en Backend DB quedaban sin limpiar
- **Después:** Usa `account.backend_cluster_id` (del `getAccountForClient` enriquecido), `getBackendClient(clusterId).from('clients').update(...)`.

### 5. `validateOnboardingOwnership(token)` — mp-oauth.service.ts
- **Antes:** `getBackendPool(account.backend_cluster_id || 'cluster_shared_01').query(...)` → fallaba, ownership check roto
- **Después:** `getBackendClient(clusterId).from('clients').select('id').eq('slug', slug).maybeSingle()`

### 6. `validateBuilderToken(token)` — mp-oauth.service.ts
- **Antes:** Mismo patrón, pero con try/catch que seteaba `clientId = null` — menos crítico pero igualmente roto
- **Después:** `getBackendClient(clusterId).from('clients').select('id').eq('slug', slug).maybeSingle()`

### 7. Provisioning Worker — HARD FAIL
- **Antes:** Si `syncMpCredentialsToBackend` retornaba `false`, solo logueaba warning. El provisioning continuaba como "exitoso".
- **Después:** Si `mp_connected=true` y sync retorna `false`, lanza `Error` que aborta el provisioning. Mensaje: "Provisioning aborted to prevent store going live without payment."

### 8. `deleteClient` / `toggleClientStatus` — admin-client.controller.ts
- Migrados de `getBackendPool().query('DELETE/UPDATE ...')` a `getBackendClient().from('clients').delete()/update(...)`.

### 9. `resetMonthlyUsage` — usage-reset.service.ts
- Migrado de `getBackendPool().query('SELECT reset_monthly_usage()')` a `getBackendClient().rpc('reset_monthly_usage')`.

### 10. getBackendPool / getAdminPool — ELIMINADOS
- Ambos stubs removidos de `db-router.service.ts`. Comentario indicando que todos los callers fueron migrados.

## Por qué se hizo

El stub `getBackendPool` fue una medida temporal durante la migración de `pg.Pool` a Supabase JS. Nunca fue funcional — siempre lanzaba error. Todos los call sites que lo usaban estaban rotos en producción, con la consecuencia más grave siendo que las credenciales de Mercado Pago nunca llegaban a la tabla `clients` en Backend DB, dejando el checkout inoperativo para tiendas nuevas.

## Cómo probar

### Pre-requisito
```bash
cd apps/api
npm run lint     # 0 errors
npm run typecheck # 0 errors
npm run build    # exitoso, dist/main.js existe
```

### Test funcional (requiere entorno con DBs)
1. **Provisioning con MP:** Crear cuenta con `mp_connected=true` → provisionar → verificar que `clients.mp_access_token` NO sea NULL en Backend DB
2. **Provisioning sin MP:** Crear cuenta sin MP → provisionar → debe completar normalmente
3. **Provisioning con MP pero fallo forzado:** Simular fallo en Backend update → debe abortar provisioning (no marcar como completed)
4. **Token refresh:** Disparar refresh → verificar que `clients.mp_access_token` se actualice en Backend
5. **Revoke:** Desconectar MP → verificar que `clients.mp_access_token` quede NULL en Backend
6. **Delete client:** Eliminar desde admin → verificar que se borre de Backend DB
7. **Toggle status:** Activar/desactivar → verificar que `is_active` se actualice en Backend

### Validación de datos existentes
```sql
-- En Backend DB: buscar tiendas con mp_access_token NULL que deberían tenerlo
SELECT c.id, c.slug, c.mp_access_token IS NULL as missing_token, a.mp_connected
FROM clients c
LEFT JOIN nv_accounts a ON a.slug = c.slug  -- cross-DB check manual
WHERE a.mp_connected = true
  AND c.mp_access_token IS NULL;
```

## Notas de seguridad

- Los tokens MP se decryptan con AES-256-GCM en el backend y se escriben en plain-text al Backend DB. Este es el diseño intencional (checkout necesita leer sin decryption).
- `getBackendClient()` usa `SERVICE_ROLE_KEY` — bypasea RLS. El scope por `client_id` se mantiene en los filtros `.eq()`.

## Riesgos

- **Bajo:** Las funciones de sync en `refreshTokenForAccount` y `revokeConnection` siguen siendo best-effort (catch silencioso). Decisión: mantener así porque el token refresh tiene su propio retry, y revoke puede tolerar inconsistencia temporal.
- **Medio:** El hard-fail en provisioning significa que si Backend DB está caído, el provisioning se aborta. Esto es intencional — mejor abortar que dejar una tienda sin pagos.
- **Bajo:** `getAccountForClient` queries the default cluster for the client lookup. En un futuro multi-cluster real, necesitaría un índice central o broadcast a todos los clusters.

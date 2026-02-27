# Cross-DB Consistency Audit — Fixes Implementados

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Repo:** `EliasPiscitelli/templatetwobe` (API)
- **Ref:** `novavision-docs/audit/2026-02-27-cross-db-clusters-provisioning-audit.md`

---

## Resumen

Se implementaron **20+ fixes** identificados en la auditoría de consistencia cross-DB, distribuidos en 5 commits:

| Commit | Hash | Contenido |
|--------|------|-----------|
| Batch 1 | `d1b1aed` | P0: Migración de 9 callers `getBackendPool()` a Supabase JS |
| Batch 2 | `b8c265a` | F0.7 campos faltantes + F0.8 legacy eliminado + F1.1 outbox expandido |
| Batch 3 | `84befb0` | F1.2 handler MP real + F1.4-F1.5 checks recon + F1.6 addons + C18 fix |
| Batch 4 | `5111eee` | D8 MP creds auto-fix + F2.5 cluster status filter + manual recon endpoint |
| Batch 5 | `0c9231e` | F1.3 cron 6h + MP outbox emit on saveConnection + F2.6 cache TTL |

---

## Detalle por Fix

### Fase 0 — Stop the Bleed (P0)

| Fix | Estado | Detalle |
|-----|--------|---------|
| **F0.1** | ✅ | `syncMpCredentialsToBackend()` migrado de `getBackendPool().query()` a `dbRouter.getBackendClient().from().update()` |
| **F0.2** | ✅ | `getAccountForClient()` migrado a Supabase JS |
| **F0.3** | ✅ | `refreshTokenForAccount()` sync migrado a Supabase JS |
| **F0.4** | ✅ | `revokeConnection()` cleanup migrado a Supabase JS |
| **F0.5** | ✅ | `getBackendPool()` + `getAdminPool()` stubs eliminados de `db-router.service.ts` |
| **F0.6** | ✅ | Cubierto por `POST /admin/reconcile-cross-db` (D8 check) + cron cada 6h |
| **F0.7** | ✅ | `PROVISION_CLIENT_FROM_ONBOARDING` ahora escribe: `plan_key`, `billing_period`, `publication_status`, `locale`, `timezone` |
| **F0.8** | ✅ | `PROVISION_CLIENT` legacy eliminado completamente (~461 líneas) |

### Fase 1 — Outbox + Reconciliación (P1)

| Fix | Estado | Detalle |
|-----|--------|---------|
| **F1.1** | ✅ | Outbox `account.updated` handler expandido de 5→16 campos (billing_email, phone, phone_full, country, persona_type, legal_name, fiscal_id, fiscal_id_type, fiscal_category, fiscal_address, subdivision_code) |
| **F1.2** | ✅ | `mp_credentials.synced` handler implementado: descifra y escribe tokens al cluster correcto vía `mpOauthService.syncMpCredentialsToBackend()` |
| **F1.3** | ✅ | `reconcileCrossDb` cron cambiado de `'15 6 * * *'` (diario) a `'15 */6 * * *'` (cada 6h: 0:15, 6:15, 12:15, 18:15) |
| **F1.4** | ✅ | Check D5 (MP credentials drift) agregado en `getAccount360` |
| **F1.5** | ✅ | Check D7 (plan_key mismatch) agregado en `getAccount360` |
| **F1.6** | ✅ | `calculateEntitlements()` usado en provisioning FROM_ONBOARDING (incluye addons) |

### Fase 2 — Routing + Hardening

| Fix | Estado | Detalle |
|-----|--------|---------|
| **F2.5** | ✅ | `chooseBackendCluster()` filtra clusters con `status === 'ready'` (fallback a todos si ninguno ready). Status cargado de tabla `backend_clusters`. |
| **F2.6** | ✅ | Cache TTL de 5 min: `getBackendClient()` hace refresh fire-and-forget si stale; `chooseBackendCluster()` hace refresh bloqueante si stale. |

### Otros

| Fix | Estado | Detalle |
|-----|--------|---------|
| **C18** | ✅ | `syncEntitlements()` cambiado de lookup por `slug` a lookup por `nv_account_id` (robust contra cambios de slug) |
| **D8** | ✅ | Check de MP credentials en `reconcileCrossDb`: si `mp_connected=true` pero `mp_access_token` null en backend → emit outbox `mp_credentials.synced` para auto-fix |
| **Manual recon** | ✅ | `POST /admin/reconcile-cross-db` endpoint (SuperAdmin) que invoca `reconcileCrossDb('manual')` |
| **MP emit** | ✅ | `saveConnection()` en `MpOauthService` ahora emite outbox `mp_credentials.synced` después de guardar credenciales (auditabilidad + retry) |

---

## Archivos Modificados (acumulado de 5 batches)

### Modificados
- `src/mp-oauth/mp-oauth.service.ts` — 9 callers migrados de getBackendPool a Supabase JS + OutboxService inyectado + emit en saveConnection
- `src/mp-oauth/mp-oauth.module.ts` — OutboxModule importado
- `src/admin/admin-client.controller.ts` — callers migrados a Supabase JS
- `src/admin/admin.controller.ts` — endpoint manual reconciliación + SubscriptionsService inyectado
- `src/admin/admin.service.ts` — D5+D7 checks en getAccount360
- `src/cron/usage-reset.service.ts` — caller migrado a Supabase JS
- `src/db/db-router.service.ts` — getBackendPool/getAdminPool eliminados + cluster status filter + cache TTL 5min
- `src/worker/provisioning-worker.service.ts` — campos faltantes + legacy eliminado + calculateEntitlements + nv_account_id fix
- `src/outbox/outbox-worker.service.ts` — account.updated 16 campos + mp_credentials.synced handler real
- `src/outbox/outbox.module.ts` — MpOauthModule importado
- `src/subscriptions/subscriptions.service.ts` — D8 check en reconcileCrossDb + cron cada 6h

---

## Lo que queda pendiente (Fase 2-3)

| Fix | Prioridad | Esfuerzo | Detalle |
|-----|-----------|----------|---------|
| **F2.1** | P0 latente | 4h | Propagar `backendClient` desde TenantContextGuard al request + decorador `@BackendClient()` |
| **F2.2-F2.3** | P0 latente | ~28h | Migrar 40 servicios legacy de `SUPABASE_ADMIN_CLIENT` estático a cluster dinámico |
| **F2.4** | P0 latente | 2h | Eliminar `SUPABASE_ADMIN_CLIENT` del SupabaseModule |
| **F3.1** | P2 | 8h | Compensating actions en saga de provisioning |
| **F3.2-F3.3** | P2 | 9h | Dashboard de health por cluster + alertas |
| **F3.4-F3.5** | P2 | 6h | DLQ UI + audit log para cambios de cluster |

> **Nota:** F2.1-F2.4 (routing real) solo importa al agregar un segundo cluster. Con un solo cluster, el token estático `SUPABASE_ADMIN_CLIENT` funciona correctamente.

---

## Cómo probar

1. **Reconciliación manual:**
   ```bash
   curl -X POST https://<api>/admin/reconcile-cross-db \
     -H "Authorization: Bearer <JWT_SUPER_ADMIN>" \
     -H "x-client-id: <ANY_CLIENT_UUID>"
   ```
   → Debe retornar `{ total, desyncs, fixed, errors, details }`.

2. **Cron automático:** Verificar logs a las :15 de cada 6h (0:15, 6:15, 12:15, 18:15) buscando `[reconcileCrossDb]`.

3. **MP OAuth flow:** Conectar MP en wizard → verificar que `mp_credentials.synced` aparece en `account_sync_outbox`.

4. **Cluster cache:** Modificar un cluster en Admin UI → verificar que se recarga en <5 min sin restart.

---

## Notas de seguridad

- El endpoint de reconciliación está protegido por `SuperAdminGuard`.
- Los tokens MP se descifran con AES-256-GCM (key en env `MP_TOKEN_ENCRYPTION_KEY`).
- El cache TTL de clusters usa fire-and-forget para no bloquear requests (en `getBackendClient`), pero bloqueante en `chooseBackendCluster` para garantizar datos frescos al asignar nuevos tenants.

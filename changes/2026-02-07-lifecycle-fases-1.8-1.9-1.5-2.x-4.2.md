# Cambio: Fases 1.8, 1.9, 1.5, 2.x, 4.2 — Lifecycle Fixes

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** `feature/automatic-multiclient-onboarding`

---

## Archivos modificados

### Código (apps/api)

| Archivo | Cambio |
|---------|--------|
| `src/subscriptions/subscriptions.service.ts` | Health checks en pause/unpause (1.8), atomic WHERE en unpause (4.2), removed unused `count` |
| `src/worker/provisioning-worker.service.ts` | mp_connections upsert → deprecation comment (2.2) |
| `src/mp-oauth/mp-oauth.service.ts` | mp_connections upsert → deprecation comment, removed unused `expiresAt` (2.2) |
| `src/workers/mp-token-refresh.worker.ts` | Deprecation header added (2.2) |

### Tests nuevos (apps/api)

| Archivo | Tests | Estado |
|---------|-------|--------|
| `test/subscriptions-lifecycle.spec.ts` | 9 tests (unpause 4, pause 3, sync 2) | ✅ 9/9 |
| `test/admin-approve-idempotency.spec.ts` | 3 tests (approved, live, not found) | ✅ 3/3 |

### Migraciones SQL (apps/api/migrations)

| Archivo | DB | Descripción |
|---------|----|-------------|
| `migrations/admin/20260207_check_constraints_subscription_status.sql` | Admin | CHECK en `nv_accounts.subscription_status` y `subscriptions.status` |
| `migrations/backend/20260207_check_constraint_publication_status.sql` | Multicliente | CHECK en `clients.publication_status` |
| `migrations/admin/20260207_partial_unique_one_active_subscription.sql` | Admin | Partial UNIQUE: 1 subscription activa por account |
| `migrations/backend/20260207_drop_global_categories_name_key.sql` | Multicliente | Drop constraint global `categories_name_key` si existe |

### Documentación

| Archivo | Tipo |
|---------|------|
| `novavision-docs/runbooks/emergency-unpause-store.md` | Runbook de emergencia |
| `novavision-docs/LIFECYCLE_FIX_PLAN.md` | Actualización de estados (v2 → v2.1) |

---

## Resumen de cambios

### Fase 1.8 — Health checks en pause/unpause
- `pauseStoreIfNeeded()`: Verifica `{ error }` de ambos UPDATEs (backend + admin), emite `console.error` con tag `[HEALTH-CHECK]`
- `unpauseStoreIfReactivated()`: Ídem, con logging de éxito y contexto completo

### Fase 1.9 — Tests backend
- 12 tests unitarios cubriendo los flows críticos del lifecycle
- `subscriptions-lifecycle.spec.ts`: unpause condicional, pause por status, integración sync
- `admin-approve-idempotency.spec.ts`: idempotencia de approve

### Fase 1.5.1 — Runbook
- Procedimiento de 5 pasos para recuperar tiendas pausadas incorrectamente
- Queries diagnósticas para detectar desync entre DBs

### Fase 1.5.2 — Crons
- Verificado: `ScheduleModule` importado, 19 `@Cron` activos, logging `[Reconcile:cron]` presente
- Pendiente: verificar ejecución real en logs de Railway

### Fase 2.2 — mp_connections cleanup
- Upserts eliminados en 3 archivos (write operations que fallaban silenciosamente)
- Read operations (`getClientCredentials`, `refreshTokenForAccount`) diferidas a Fase 3

### Fase 2.3 — CHECK constraints
- 3 migraciones SQL con CHECK para `subscription_status`, `subscriptions.status`, `publication_status`
- Valores corregidos incluyendo `purged`, `authorized` y los reales de `clients.publication_status`

### Fase 2.4 — Partial UNIQUE
- Previene doble subscription activa por account a nivel DB

### Fase 2.1 — Categories UNIQUE
- Migración para dropear `categories_name_key` global si existe (safe: IF EXISTS)

### Fase 4.2 — Atomic WHERE en unpause
- UPDATE incluye `.eq('publication_status', 'paused').like('paused_reason', 'subscription_%')` 
- Previene race condition donde admin pausa manualmente y el auto-unpause la revierte

---

## Validaciones ejecutadas

| Validación | Resultado |
|-----------|-----------|
| `npx tsc --noEmit` | ✅ Sin errores |
| `npx jest test/subscriptions-lifecycle.spec.ts test/admin-approve-idempotency.spec.ts` | ✅ 12/12 pass |
| Suite completa (`npx jest --no-coverage`) | 11 pass, 36 fail (pre-existentes) — nuestros 2 archivos pasan |

---

## Pendientes / Próximos pasos

1. **Aplicar migraciones SQL** — requiere ejecutar DISTINCT previo y confirmación del TL
2. **Tests frontend** (Fase 1.9 FE) — `BillingPage` y `SubscriptionExpiredBanner`
3. **Verificar crons en Railway** (Fase 1.5.2) — requiere acceso a logs de producción
4. **Fase 3** — Saga para `approveClient()`, observabilidad, locks, cross-DB consistency

---

## Notas de seguridad

- Las migraciones de CHECK constraints requieren ejecutar `SELECT DISTINCT` previo contra la DB real antes de aplicar
- La migración de partial UNIQUE requiere verificar que no hay duplicados activos antes de aplicar
- El cleanup de `mp_connections` es backwards-compatible: los tokens ya funcionan desde `nv_accounts`

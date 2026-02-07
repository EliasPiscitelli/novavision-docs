# Cambio: Lifecycle Fases 3.1, 3.2, 3.3, 4.1 — Observabilidad, locks, compensación y guard

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos creados

| Archivo | Descripción |
|---------|-------------|
| `src/common/lifecycle-events.service.ts` | Servicio fire-and-forget para emitir eventos a `lifecycle_events` table (Admin DB) |
| `migrations/admin/20260207_lifecycle_events_table.sql` | Tabla + 3 índices + RLS para auditoría de lifecycle |
| `migrations/admin/20260207_subscription_locks_table.sql` | Tabla + 3 funciones RPC para locks distribuidos |

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/common/common.module.ts` | Registrado `LifecycleEventsService` en providers + exports (global) |
| `src/subscriptions/subscriptions.service.ts` | (1) Inyectar LifecycleEventsService, (2) emitir eventos en sync/pause/unpause, (3) reemplazar Map in-memory con RPC try_lock/release |
| `src/admin/admin.service.ts` | (1) Inyectar LifecycleEventsService, (2) emitir evento en approveClient, (3) compensación cross-DB si Admin DB falla post-publish, (4) guard draft expirado |
| `test/subscriptions-lifecycle.spec.ts` | Agregar mock lifecycleEvents como 8° arg del constructor |
| `test/admin-approve-idempotency.spec.ts` | Agregar mock lifecycleEvents como 6° arg del constructor |
| `novavision-docs/LIFECYCLE_FIX_PLAN.md` | Actualizar tracker: puntos 2, 13, 17, 18 marcados como ✅ |

## Migraciones aplicadas a DB en vivo

| Migración | DB | Resultado |
|-----------|-----|-----------|
| `20260207_lifecycle_events_table.sql` | Admin | ✅ CREATE TABLE + 3 INDEX + RLS |
| `20260207_subscription_locks_table.sql` | Admin | ✅ CREATE TABLE + RLS + 3 FUNCTIONS |

## Resumen de cambios

### Fase 3.2 — lifecycle_events (Observabilidad)
- Tabla `lifecycle_events` en Admin DB con campos: account_id, event_type, old_value/new_value (JSONB), source, correlation_id, metadata, created_by
- `LifecycleEventsService` en `src/common/` — fire-and-forget (errores se loguean, nunca bloquean)
- Integrado en: `syncAccountSubscriptionStatus`, `pauseStoreIfNeeded`, `unpauseStoreIfReactivated`, `approveClient`

### Fase 3.3 — Distributed Locks (reemplaza Map in-memory)
- Tabla `subscription_locks` con funciones RPC:
  - `try_lock_subscription(account_id, ttl_seconds)` → INSERT/upsert con expiración
  - `release_subscription_lock(account_id)` → DELETE
  - `cleanup_stale_subscription_locks(max_age_seconds)` → limpieza para cron
- Fail-open: si el RPC falla, la operación procede (no bloquear por error de lock)
- Funciona con múltiples instancias Railway (vs Map que no sobrevive restart ni escala)

### Fase 3.1 — approveClient compensation
- Si el update a Backend DB (`clients.publication_status = 'published'`) funciona pero el update a Admin DB (`nv_accounts.status = 'approved'`) falla:
  - Compensación: revierte backend a `publication_status: 'draft'`, `is_published: false`
  - Emite lifecycle event `approval_failed_compensated` para traza
  - Si la compensación misma falla, loguea CRITICAL para intervención manual

### Fase 4.1 — Guard draft expirado
- Si `nv_accounts.draft_expires_at` < now(), rechaza la aprobación con `ConflictException` código `DRAFT_EXPIRED`
- Ubicado justo después del idempotency guard, antes de cualquier write

## Cómo probar

```bash
cd apps/api
npx tsc --noEmit                                    # 0 errores
npx jest test/subscriptions-lifecycle.spec.ts \
          test/admin-approve-idempotency.spec.ts \
          --no-coverage                              # 12/12 PASS
```

## Notas de seguridad

- `subscription_locks` tiene RLS con server_bypass (solo service_role)
- `lifecycle_events` tiene RLS con server_bypass (solo service_role)
- Las funciones RPC son `SECURITY DEFINER` — ejecutan como owner de la función
- Fire-and-forget en lifecycle events: si la DB falla, el flujo principal no se bloquea

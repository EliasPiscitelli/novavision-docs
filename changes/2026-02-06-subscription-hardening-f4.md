# Cambio: F4 — Reconciliación robusta contra MercadoPago API

- **Autor:** agente-copilot
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Fase del plan:** F4 (de subscription-hardening-plan.md)

## Archivos modificados

| Archivo | Acción | Descripción |
|---|---|---|
| `apps/api/src/subscriptions/subscriptions.service.ts` | MODIFIED | Nuevo cron `reconcileWithMercadoPago()` (~170 líneas), deprecación del `@Cron` en `reconcileSubscriptions()` legacy |
| `apps/api/src/subscriptions/subscriptions.controller.ts` | MODIFIED | Endpoint `POST /subscriptions/reconcile` rewired → `reconcileWithMercadoPago('manual')`, devuelve reporte detallado |
| `apps/api/src/billing/billing.service.ts` | MODIFIED | `CreateBillingEventDto.eventType` extendido con `'reconcile_report'`, `status` con `'completed' | 'partial'` |
| `apps/api/migrations/admin/20260206_add_last_mp_synced_at.sql` | NEW | Columna `last_mp_synced_at TIMESTAMPTZ` + `last_reconcile_source TEXT` + índice parcial |
| `novavision-docs/architecture/subscription-hardening-plan.md` | MODIFIED | Estado → F0-F4 implementados, entregables F4 marcados [x] |

## Resumen del cambio

### Nuevo cron `reconcileWithMercadoPago()`
- **Horario:** `@Cron('0 6 * * *')` — 6AM diario (después de price-sync a 2AM y grace-check a 3AM)
- **Lógica:**
  1. Query subscriptions con status `active|past_due|grace|grace_period` Y `mp_preapproval_id != null`
  2. Para cada sub: llama `PlatformMercadoPagoService.getSubscription(preapprovalId)` (SDK v2)
  3. Mapea status MP → interno: `authorized→active`, `paused→past_due`, `cancelled→canceled`
  4. Si difiere: actualiza subscription, `syncAccountSubscriptionStatus()`, `pauseStoreIfNeeded()` y/o `markCancelScheduled()` según corresponda
  5. Marca `last_mp_synced_at` y `last_reconcile_source` en cada sub procesada
  6. Log del reporte en `nv_billing_events` con metadata `{type:'reconcile_report', ...}`
- **Rate limiting:** Batches de 10 con 1s delay entre batches (~10 req/s, bien bajo el límite de 20 req/s de MP)
- **Invocable manualmente:** `POST /subscriptions/reconcile` → `reconcileWithMercadoPago('manual')`

### Deprecación del legacy
- `reconcileSubscriptions()` pierde su `@Cron('0 3 * * *')` — ya no corre automáticamente
- Se mantiene como método por backward-compat pero marcado `@deprecated`
- El cron de grace-expired se absorbe conceptualmente en el nuevo (el nuevo cubre el mismo scope + más)

### DTO extendido
- `CreateBillingEventDto.eventType` ahora acepta `'reconcile_report'`
- `CreateBillingEventDto.status` ahora acepta `'completed' | 'partial'`

## Por qué

El cron legacy `reconcileSubscriptions()` solo verificaba expiración de grace period → suspend. **No comparaba contra MP API.** El legacy en `MercadoPagoService.reconcileSubscriptions()` sí lo hacía pero usaba el linkage viejo por `nv_accounts.subscription_id` (no la tabla `subscriptions`).

El nuevo cron unifica ambas funcionalidades usando la tabla `subscriptions` como SoT y el SDK de MP (no axios directo).

## Cómo probar

1. **Typecheck:** `cd apps/api && npx tsc -p tsconfig.json --noEmit` → 0 errores
2. **Manual endpoint:** `POST /subscriptions/reconcile` con Bearer token de Super Admin → devuelve `{ok, total, synced, errors, details[]}`
3. **Migración:** Ejecutar `20260206_add_last_mp_synced_at.sql` en Admin DB antes del deploy
4. **Logs:** Verificar en consola mensajes `[Reconcile:cron]` a las 6AM o `[Reconcile:manual]` al trigger manual

## Notas de seguridad

- El cron usa `SERVICE_ROLE_KEY` (server-side, nunca expuesto)
- Rate limiting protege contra throttling de MP API
- Eventos de reconciliación quedan auditados en `nv_billing_events`
- El accountId del evento de reporte es `00000000-0000-0000-0000-000000000000` (evento de sistema, no de cuenta específica)

## Pendiente

- [ ] Test unitario con mock de `PlatformMercadoPagoService.getSubscription()` para validar mapping de status y handling de errores

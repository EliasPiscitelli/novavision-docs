# Fase 4: Comisión GMV + Overages + Billing

- **Autor:** agente-copilot
- **Fecha:** 2026-02-24
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Fase del Plan Maestro:** §4 (semana 4-5)

## Archivos modificados

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/metrics/usage-recorder.service.ts` | MODIFICADO | Agregado metric `'gmv'`, método `recordOrderGmv()` con conversión FX, helper `currencyToCountry()` |
| `src/tenant-payments/mercadopago.module.ts` | MODIFICADO | Agregado `MetricsModule` a imports |
| `src/tenant-payments/mercadopago.service.ts` | MODIFICADO | Inyectado `UsageRecorderService`, hook GMV en `confirmPayment()` |
| `src/billing/billing.service.ts` | MODIFICADO | Inyectado `DbRouterService`, métodos: `chargeAdjustment()`, `processAdjustmentPayment()`, `chargeAllPendingAutoCharge()`, `waiveAdjustment()` |
| `src/billing/billing.module.ts` | MODIFICADO | Registrados `GmvCommissionCron`, `OverageService`, `CostRollupCron` como providers; `OverageService` exportado |
| `src/admin/admin.module.ts` | MODIFICADO | Registrado `AdminAdjustmentsController` |
| `src/guards/quota-check.guard.ts` | MODIFICADO | Fix: inyección directa de `DbRouterService` (eliminado hack `as any`) |

## Archivos creados

| Archivo | Descripción |
|---------|-------------|
| `src/billing/gmv-commission.cron.ts` | Cron mensual (día 2, 06:00 UTC) — calcula comisiones GMV > threshold y genera `billing_adjustments` |
| `src/billing/overage.service.ts` | Cron mensual (día 2, 06:30 UTC) — calcula overages por dimensión (orders, egress) y genera `billing_adjustments` |
| `src/billing/cost-rollup.cron.ts` | Cron mensual (día 3, 06:00 UTC) — calcula COGS por tenant y upsertea `cost_rollups_monthly` |
| `src/admin/admin-adjustments.controller.ts` | Controller admin: CRUD billing_adjustments, charge, waive, bulk-charge, recalculate |

## Resumen de cambios

### Task 4.1 — Metric `gmv` en UsageRecorderService
- Añadido `'gmv'` al union type de métricas
- Nuevo método `recordOrderGmv({ clientId, orderId, totalAmount, currency })` que:
  - Convierte moneda local → USD via `FxService.getRate(countryId)`
  - Enqueue metric `gmv` con quantity = amount_usd
- Helper `currencyToCountry()` mapea ARS→AR, CLP→CL, MXN→MX, etc.

### Task 4.2 — Hook en webhook MP
- `MercadoPagoModule` ahora importa `MetricsModule`
- `MercadoPagoService` inyecta `UsageRecorderService`
- En `confirmPayment()`, después de sincronizar la orden, llama a `recordOrderGmv()` (non-blocking, try/catch)

### Task 4.3 — GmvCommissionCron
- Cron `@Cron('0 6 2 * *')` — día 2 del mes a las 06:00 UTC
- Batch-fetch: accounts + plans (gmv_threshold, gmv_commission_pct) + usage_rollups_monthly
- Para cada tenant elegible (commission > 0): si GMV > threshold → `billing_adjustments` type='gmv_commission'
- Idempotencia: pre-check de adjustments existentes + manejo de unique constraint (23505)

### Task 4.4 — OverageService
- Cron `@Cron('30 6 2 * *')` — día 2 a las 06:30 UTC
- Calcula overages por dimensión:
  - Orders: excess × $0.015/unidad (Growth)
  - Egress: excess GB × $0.08/GB (Growth)
- Starter: hard limit (no overages). Enterprise: rates custom (skip).
- Genera `billing_adjustments` type='overage_orders' / 'overage_egress'
- API pública: `calculateOveragesForPeriod(periodStart)` para recalcular on-demand

### Task 4.5 — Auto-charge en BillingService
- `chargeAdjustment(id)`: lee adjustment → crea billing event → crea MP preference → retorna init_point
- `processAdjustmentPayment(eventId)`: cuando el MP webhook confirma pago → marca adjustment como 'charged'
- `chargeAllPendingAutoCharge()`: bulk charge para tenants con `subscriptions.auto_charge=true`
- `waiveAdjustment(id, note?)`: admin exenta un adjustment (status='waived')

### Task 4.6 — AdminAdjustmentsController
- `GET /admin/adjustments` — listado con filtros (status, type, tenant_id, period) + paginación
- `GET /admin/adjustments/:id` — detalle de un adjustment con datos de cuenta
- `POST /admin/adjustments/:id/charge` — cobra un adjustment pendiente via MP
- `POST /admin/adjustments/:id/waive` — exenta un adjustment
- `POST /admin/adjustments/bulk-charge` — cobra todos los pendientes de cuentas auto_charge
- `POST /admin/adjustments/recalculate` — recalcula overages para un período

### Task 4.7 — CostRollupCron
- Cron `@Cron('0 6 3 * *')` — día 3 a las 06:00 UTC
- Fórmula COGS (Plan Maestro §10.2):
  - `MP_fee (5.4%) × plan_price + $0.01/order + $0.20/1M API calls + $0.021/GB storage + $0.078/GB egress`
- Bulk upsert en `cost_rollups_monthly` (batches de 500)

### Fix Fase 3 — QuotaCheckGuard
- Eliminado hack `(this.quotaService as any).dbRouter`
- Inyección directa de `DbRouterService` en el constructor del guard

## Cronograma de crons (resumen)

| Cron | Horario | Tabla destino |
|------|---------|---------------|
| UsageConsolidationCron | 02:30 UTC diario | `usage_rollups_monthly` |
| QuotaEnforcementService | 03:00 UTC diario | `quota_state` |
| GmvCommissionCron | 06:00 UTC día 2/mes | `billing_adjustments` |
| OverageService | 06:30 UTC día 2/mes | `billing_adjustments` |
| CostRollupCron | 06:00 UTC día 3/mes | `cost_rollups_monthly` |

## Cómo probar

```bash
# 1. Build validation
cd apps/api
npm run lint      # 0 errores
npm run typecheck # sin errores (npx tsc --noEmit)
npm run build     # exitoso, dist/main.js existe

# 2. Dev server
npm run start:dev

# 3. Tests manuales (admin endpoints)
# Listar adjustments
curl -H "Authorization: Bearer <SA_JWT>" http://localhost:3000/admin/adjustments

# Recalcular overages para un período
curl -X POST -H "Authorization: Bearer <SA_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"period_start":"2026-01-01"}' \
  http://localhost:3000/admin/adjustments/recalculate
```

## Notas de seguridad

- Todos los endpoints admin protegidos con `SuperAdminGuard` + `@AllowNoTenant()`
- Auto-charge solo opera sobre `billing_adjustments.status='pending'` (idempotente)
- GMV recording es non-blocking (try/catch warn-level) para no afectar flujo de pago
- Webhook MP hook no modifica el flujo existente de confirmación de órdenes

## Riesgos y mitigación

| Riesgo | Mitigación |
|--------|------------|
| Cron corre 2 veces en el mismo mes | Idempotencia via pre-check de adjustments existentes + unique constraint PK |
| FxService falla al convertir moneda | Fallback a USD 1:1 (logs warning, no bloquea order) |
| MP preference creation falla | Error logged, adjustment queda pending para retry manual |
| Enterprise plans sin rates definidos | Skippeados por default (rates custom via fee_schedule_lines - futuro) |

# Downgrade Alternative — Check de elegibilidad antes de cancelar

**Fecha:** 2026-03-26
**Plan:** `PLAN_CHURN_LIFECYCLE.md` Fase 2 — alternativa de downgrade
**Estado:** Implementado + testeado

---

## Problema

Cuando un usuario quiere cancelar su suscripción, no se ofrecía la alternativa de bajar a un plan inferior. La cancelación era todo-o-nada. Regla de negocio: solo ofrecer downgrade si el uso actual no excede los límites del plan destino.

## Solución

### Nuevo método: `PlansService.checkDowngradeEligibility(clientId)`

- Obtiene el plan actual del tenant
- Identifica el plan inferior (enterprise→growth, growth→starter)
- Si es starter, retorna `eligible=false` (no hay plan inferior)
- Consulta entitlements del plan destino en tabla `plans`
- Compara 6 métricas de uso actual vs límites del destino:
  - `products`, `banners`, `coupons`, `faqs`, `services`, `storage_gb`
- Solo retorna `eligible=true` si **todas** las métricas están dentro de límites
- Retorna detalle de exceedances: `{ field, currentUsage, targetLimit }`

### Nuevos endpoints

| Ruta | Guard | Propósito |
|------|-------|-----------|
| `GET /subscriptions/manage/downgrade-check` | BuilderSessionGuard | Para el builder dashboard |
| `GET /subscriptions/client/manage/downgrade-check` | ClientDashboardGuard | Para el client dashboard |

### Método helper: `resolveClientIdFromRequest()`

Nuevo método público en `SubscriptionsService` que resuelve el `client_id_backend` desde el request context, para que el controller pueda llamar a `PlansService`.

### Archivos modificados

- `api/src/plans/plans.service.ts` — `checkDowngradeEligibility()`, `getDowngradeTarget()`, interfaces `DowngradeEligibility`, `DowngradeExceedance`
- `api/src/subscriptions/subscriptions.controller.ts` — 2 endpoints GET, inyección de `PlansService`
- `api/src/subscriptions/subscriptions.service.ts` — `resolveClientIdFromRequest()`
- `api/src/subscriptions/subscriptions.module.ts` — import `PlansModule`

### Tests creados

- `api/src/plans/__tests__/downgrade-eligibility.spec.ts` — 6 tests:
  - growth→starter eligible (uso dentro de límites)
  - growth→starter no eligible (excede productos)
  - Múltiples exceedances (productos + banners + storage + faqs)
  - starter sin plan inferior
  - enterprise→growth eligible
  - Plan destino no encontrado

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 109/109 suites, 1063/1065 tests OK (2 skipped preexistentes)

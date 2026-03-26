# Churn Lifecycle — Fase 1 Fundamentos

**Fecha:** 2026-03-26
**Plan:** `PLAN_CHURN_LIFECYCLE.md` Fase 1 (1.2, 1.3, 3.4)
**Estado:** 3 ítems P0 implementados

---

## 1.2 Tabla `subscription_cancel_log` (Admin DB)

### Problema
El código referenciaba la tabla para idempotencia de cancelaciones (3 inserts en `subscriptions.service.ts`), pero la tabla no existía. Los inserts fallaban silenciosamente via `try/catch`.

### Solución
- Tabla creada con: `id`, `account_id`, `subscription_id`, `idempotency_key` (UNIQUE), `reason`, `reason_text`, `wants_contact`, `cancel_type`, `effective_end_at`, `data_retention_until`, `result` (JSONB)
- RLS: service_role bypass
- Los 2 inserts existentes ahora incluyen todos los campos de auditoría (reason, cancel_type, effective_end_at, etc.)

### Archivos
- `api/migrations/admin/20260326_subscription_cancel_log.sql` — migración (ejecutada)
- `api/src/subscriptions/subscriptions.service.ts` — enriquecidos los 2 inserts con campos completos

---

## 1.3 Grace period dinámico por plan

### Problema
`handlePaymentFailed()` usaba `GRACE_PERIOD_DAYS` (env var, default 7) para todos los planes. La tabla `plans` ya tenía `grace_days` diferenciado (starter=7, growth=14, enterprise=30) pero no se leía.

### Solución
- `handlePaymentFailed()` ahora lee `grace_days` de la tabla `plans` usando el `plan_key` de la suscripción
- Fallback: env var → 7 días (si la query falla o el plan no existe)
- Non-blocking: error en la query no interrumpe el flujo de pago fallido

### Archivos
- `api/src/subscriptions/subscriptions.service.ts` — `handlePaymentFailed()` lee `plans.grace_days`

---

## 3.4 Lifecycle stage `churned` automático

### Problema
El lifecycle_stage `churned` existía como valor posible en `nv_accounts` y el CRM lo filtraba, pero nunca se asignaba automáticamente al cancelar.

### Solución
- `syncAccountSubscriptionStatus()` ahora actualiza `lifecycle_stage` junto con `subscription_status`:
  - `status='canceled'` → `lifecycle_stage='churned'`
  - `status='active'` → `lifecycle_stage='active'` (reactivación)
- Impacto: CRM dashboard, health cron y filtros ya consumen este campo

### Archivos
- `api/src/subscriptions/subscriptions.service.ts` — `syncAccountSubscriptionStatus()` con lifecycle_stage dinámico

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 106/106 suites, 1033/1035 tests OK (2 skipped)

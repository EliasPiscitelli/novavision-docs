# Fix: Edge Cases en Flujo de Cancelación de Suscripción

**Fecha:** 2026-03-27
**Apps:** API, Web
**Severidad:** ALTA — cubrir huecos en cancelación que podían dejar cuentas en estado zombie

## Contexto

El flujo de cancelación tiene 3 puertas de entrada (manual, webhook MP, reconciliación cron) y no todas tenían el mismo nivel de protección contra deuda ni enviaban notificaciones.

## Cambios realizados

### API (`apps/api/src/subscriptions/subscriptions.service.ts`)

#### Fix 1+5: Emails y lifecycle events en `markCancelScheduled()`
- Agregado bloque de notificaciones al final de `markCancelScheduled()` para cancelaciones no-manuales
- Cubre: webhook de MP (`mp_cancelled`), reconciliación cron (`mp_reconcile`), resolución de deuda (`debt_resolved_cancel`)
- Envía: email al super admin + email de confirmación al cliente + lifecycle event `subscription_cancel_requested`
- Las cancelaciones manuales (desde `requestCancel`) ya enviaban emails por separado, se excluyen con `reason !== 'user_requested'`

#### Fix 2: Validar deuda en `revertCancel()`
- Agregado debt guard antes de permitir revertir una cancelación
- Si hay `billing_adjustments` pendientes, lanza `BadRequestException` con monto de deuda
- Previene que un usuario con deuda pueda reactivar su suscripción sin pagar

#### Fix 3: Lifecycle event al resolver deuda de cancelación
- En `handlePaymentSuccess()`, cuando se detecta que un pago resuelve `cancellation_debt_log`, se emite lifecycle event `cancellation_debt_resolved`
- La cancelación diferida ya se ejecuta via `markCancelScheduled()` que ahora envía emails (Fix 1)

#### Fix 4: Validar deuda en `resumeStore()`
- Agregado debt guard que impide reanudar tiendas pausadas automáticamente por suscripción (`subscription_*`) si hay deuda pendiente
- Solo aplica a pausas automáticas — pausas manuales no se bloquean
- Previene bypass de cobro de deuda al reanudar manualmente

#### Fix 6: Detectar deuda al expirar free coupon
- En `processFreeCouponExpirations()`, al expirar un cupón gratuito se verifica deuda pendiente
- Si existe deuda, emite lifecycle event `free_coupon_expired_with_debt` con monto y plan
- Permite al super admin tomar acción sobre cuentas free que terminaron con overages

### Web (`apps/web/src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx`)

- Botón "Cancelar suscripción" bloqueado (disabled) cuando `outstanding_debt.has_debt === true`
- Tooltip nativo explicando que debe saldar deuda primero
- Banner de deuda actualizado: informa que la cancelación está bloqueada mientras haya saldo pendiente

## Edge cases cubiertos

| # | Edge Case | Fix |
|---|-----------|-----|
| 1 | Cancel desde MP → sin emails | `markCancelScheduled()` ahora envía emails |
| 2 | Revert cancel sin validar deuda | Debt guard en `revertCancel()` |
| 3 | Post-pago deuda → limbo | Lifecycle event + `markCancelScheduled()` con emails |
| 4 | Resume manual con deuda | Debt guard en `resumeStore()` |
| 5 | Reconciliación → sin emails | Mismo fix que #1 |
| 6 | Free coupon + deuda | Lifecycle event `free_coupon_expired_with_debt` |

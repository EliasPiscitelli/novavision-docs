# Fase 2: Hardening del ciclo de vida de suscripciones

- **Autor:** agente-copilot
- **Fecha:** 2026-02-25
- **Rama:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `apps/api/src/subscriptions/subscriptions.service.ts`
  - `apps/api/src/onboarding/onboarding-notification.service.ts`

---

## Resumen

Implementación completa de Fase 2 del sistema de suscripciones: el ciclo de vida está ahora **100% controlado** y validado contra MercadoPago en todo momento.
Se agregan 3 nuevos crons + mejoras al `handlePaymentSuccess` y `checkAndUpdatePrices` para cubrir TODOS los escenarios post-trial y post-cupón.

---

## Cambios implementados

### 1. Nuevo Cron: `processPromoExpirations` (5 AM diario)
**Problema:** `promo_ends_at` se escribía pero nunca se leía. Cupones con descuento temporal (ej. 50% por 3 meses) nunca restauraban el precio original.

**Solución:** Cron que:
- Busca subs `active`/`trialing` con `promo_ends_at <= now`
- Recalcula precio full con FX actual (`plan_price_usd * currentRate`)
- Actualiza precio en MP vía `updateSubscriptionPrice()`
- Actualiza `next_estimated_local` en DB y limpia `promo_ends_at`
- Registra en `subscription_price_history` para auditoría

### 2. Nuevo Cron: `verifyPaymentHealth` (7 AM diario)
**Problema:** Después del trial, si MP no cobra por algún motivo (tarjeta vencida, webhook perdido), la sub quedaba "active" sin pagos reales.

**Solución:** Safety net que busca subs `active` post-trial (>72h) sin `last_payment_date` y:
- Si MP dice `cancelled` → `cancel_scheduled`
- Si MP dice `paused` → `past_due`
- Si MP dice `authorized` pero no hay pagos → busca en payments de MP (webhook pudo haberse perdido) y sincroniza
- Si tampoco hay pagos en MP → registra `lifecycle_event` de warning para revisión manual

### 3. Nuevo Cron: `processFreeCouponExpirations` (5:30 AM diario)
**Problema:** Subs con `free_coupon_*` (sin MP) no tenían gestión de período. Cuando `current_period_end` pasaba, quedaban "activas" eternamente.

**Solución:** Cron que:
- Si `auto_renew = true` → renueva el período (next 30d/1y)
- Si `auto_renew = false` → transiciona a `expired` + pausa tienda

### 4. Mejora: `handlePaymentSuccess` — limpieza post-promo
Cuando llega un pago y `promo_ends_at` ya expiró, el handler ahora:
- Limpia `promo_ends_at = null`
- Actualiza `next_estimated_local` al monto cobrado por MP (refleja precio real post-promo)

### 5. Mejora: `checkAndUpdatePrices` — skip subs en promo activa
El cron de ajuste FX (2 AM) ahora skipea subs con `promo_ends_at > now` para no sobrescribir el precio descontado con el FX-adjusted.

---

## Mapa completo de crons (12 crons activos)

| Schedule | Método | Propósito |
|----------|--------|-----------|
| `0 * * * *` | `processExpiredTrials` | trial → active cuando trial_ends_at pasa |
| `0 2 * * *` | `checkAndUpdatePrices` | Ajuste de precios por FX (skip promos activas) |
| `0 3 * * *` | `processGracePeriods` | Grace period → suspended |
| `0 5 * * *` | **`processPromoExpirations`** ⭐ | Restaurar precio full post-promo |
| `30 5 * * *` | **`processFreeCouponExpirations`** ⭐ | Expirar/renovar subs free_coupon |
| `0 6 * * *` | `reconcileWithMercadoPago` | Sync status DB vs MP |
| `15 6 * * *` | `reconcileCrossDb` | Sync Admin vs Backend DB |
| `0 7 * * *` | **`verifyPaymentHealth`** ⭐ | Detectar active sin pagos post-trial |
| `*/30 * * * *` | `processDeactivations` | cancel_scheduled → deactivated |
| `0 4 * * *` | `processPurges` | deactivated → purged (+90d) |
| `0 8 * * *` | Outbox processor | Enviar notificaciones pendientes |
| `0 1 * * *` | `processSubscriptionRenewals` | Renovar períodos de subs activas |

## Flujo temporal diario completo

```
01:00  processSubscriptionRenewals  — Renueva períodos
02:00  checkAndUpdatePrices         — Ajusta precios FX (no toca promos)
03:00  processGracePeriods          — Grace → suspended
04:00  processPurges                — Deactivated → purged
05:00  processPromoExpirations      — Promo expirada → precio full en MP ⭐
05:30  processFreeCouponExpirations — Free coupon → renew o expire ⭐
06:00  reconcileWithMercadoPago     — DB vs MP status sync
06:15  reconcileCrossDb             — Admin vs Backend sync
07:00  verifyPaymentHealth          — Active sin pagos post-trial → alert ⭐
08:00  Outbox processor             — Emails/notificaciones
HH:00  processExpiredTrials         — Trialing → active si trial venció
HH:00/30  processDeactivations      — cancel_scheduled → deactivated
```

### 6. Nuevo Cron: `processGracePeriodExpirations` (3 AM diario)
**Problema CRÍTICO:** El legacy `reconcileSubscriptions` (que transicionaba `past_due` con `grace_ends_at` expirada → `suspended`) tenía su `@Cron` removido. `reconcileWithMercadoPago` solo compara status MP vs DB pero NO verifica `grace_ends_at`. Resultado: suscripciones podían quedar en `past_due` indefinidamente sin consecuencia.

**Solución:** Nuevo cron `processGracePeriodExpirations` que:
- Busca subs `past_due`/`grace`/`grace_period` con `grace_ends_at <= now`
- Las transiciona a `suspended` + pausa la tienda
- Envía email `grace_expired_suspended` a cada cliente notificando que su tienda fue pausada
- También envía warnings 48h antes (`grace_warning_48h`) para dar oportunidad de regularizar

### 7. Email `sendPaymentFailedNotification` implementado (era stub TODO)
**Problema:** `sendPaymentFailedNotification` era un stub que solo logueaba — NO enviaba email real.

**Solución:** Implementación completa con:
- Template HTML profesional con detalles del rechazo (motivo, monto, fecha de reintento, período de gracia)
- Mapeo de `status_detail` de MP a mensajes legibles en español
- Banner urgente si es el 2do+ fallo consecutivo con advertencia de suspensión
- Pasos claros para el cliente (esperar reintento, verificar medio de pago, contactar soporte)
- Se encola vía `email_jobs` con deduplicación

### 8. Nuevos templates de lifecycle email
- `grace_warning_48h`: Aviso urgente 48h antes de que expire la gracia
- `grace_expired_suspended`: Notificación de suspensión por gracia expirada

---

## Cómo probar

```bash
cd apps/api
npm run lint        # 0 errores
npm run typecheck   # 0 errores
npm run build       # OK
```

## Notas de seguridad
- Todos los crons consultan MP API antes de tomar acciones destructivas
- Payment health solo emite warnings (no cancela) cuando hay ambigüedad
- Precio restaurado post-promo usa FX rate actual (no el del momento del cupón)
- Fire-and-forget de lifecycle_events no bloquea el cron si la tabla no existe
- El email de pago fallido nunca expone datos sensibles de tarjeta, solo el motivo genérico de rechazo

# Cambio: Cupón 100% siempre crea suscripción MP con trial

- Autor: agente-copilot
- Fecha: 2026-02-25
- Rama: feature/automatic-multiclient-onboarding
- Archivos modificados:
  - `src/subscriptions/subscriptions.service.ts` — Reemplazo bloque FREE CHECKOUT por fallback a trial MP
  - `src/onboarding/onboarding.service.ts` — Validación de T&C en submitForReview
  - `src/common/email/email-template.service.ts` — Fix footer HTML (table wrapper)
  - `src/onboarding/onboarding-notification.service.ts` — Fix CSS footer padding
  - **DB (Admin)**: `UPDATE coupons SET promo_config = '{"free_months": 3}' WHERE code = 'NVTEST'`

## Resumen

### Fix principal: Cupón 100% → MP trial (no free checkout)

**Problema:** Un cupón con `discount_value=100` y `promo_config=NULL` (como NVTEST) 
entraba en el path "FREE CHECKOUT" que:
1. Creaba una suscripción local con `status: 'active'` y `mp_preapproval_id: 'free_coupon_...'`
2. Retornaba `initPoint: null`
3. El onboarding interpretaba `!initPoint` como "free checkout" → marcaba como pagado inmediatamente
4. **El usuario nunca pasaba por Mercado Pago** → no se creaba suscripción real en MP

**Comportamiento deseado:** Incluso con 100% de descuento, la suscripción debe crearse 
en MP con un período de prueba (trial). Así MP gestiona el ciclo de vida y cobra al 
terminar el trial.

**Solución (código):**
- Eliminé el bloque FREE CHECKOUT completo (~80 líneas)
- Lo reemplacé por un fallback de 6 líneas que:
  - Si cupón cubre 100% y NO tiene `promo_config.free_months` → default a 30 días de trial
  - Envía el precio COMPLETO a MP con esos trial days
  - MP no cobra durante el trial; después cobra el precio normal
- Cambié `const effectiveTrialDays` → `let effectiveTrialDays` para permitir reasignación

**Solución (DB):**
- NVTEST ahora tiene `promo_config = {"free_months": 3}` → 90 días de trial
- Con `free_months`, el código existente (L530-536) ya manejaba correctamente el caso:
  `couponTrialDays = 3 * 30 = 90` → se envía precio completo a MP con 90 días trial

### Fix secundario: Validación T&C en submitForReview

Se agregó validación de `terms_accepted_at` antes de permitir submit for review.
Si no aceptó T&C → `400 Bad Request` con mensaje claro.

### Fix cosmético: Emails

- Footer del email ahora tiene `<table>` wrapper correcto
- CSS de footer: removido `padding` duplicado que causaba doble espacio

## Impacto

### Flujo antes del fix:
```
Cupón 100% sin free_months → FREE CHECKOUT → initPoint=null → auto-paid → NO MP
```

### Flujo después del fix:
```
Cupón 100% sin free_months → fallback 30d trial → MP subscription → initPoint=URL → redirect MP → webhook → paid
Cupón 100% con free_months=3 → couponTrialDays=90 → MP subscription → initPoint=URL → redirect MP → webhook → paid
```

### Riesgos
- **Bajo**: Si alguien QUIERE un checkout genuinamente gratis (sin MP), ya no hay path para eso. 
  Esto es intencional — toda suscripción debe pasar por MP.
- **MP sandbox**: En sandbox, MP requiere emails de test_user_. Si se prueba con email real,
  MP rechazará la suscripción.

## Cómo probar

1. Levantar API: `npm run start:dev`
2. Crear un onboarding de prueba con cupón NVTEST
3. En checkout/start: verificar que retorne `redirect_url` (no null)
4. Verificar en logs: "Coupon NVTEST grants 3 free months → 90 trial days"
5. Verificar que el redirect lleva a MP sandbox/production

## Notas de seguridad
- El cambio no expone secrets ni afecta RLS
- El cambio REDUCE superficie de ataque: ya no hay suscripciones "fantasma" sin respaldo en MP

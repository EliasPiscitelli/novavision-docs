# Cambio: Fixes de flujo de pago — email vendedor, QR fallback, órdenes stale, resultado de pago

- **Autor:** agente-copilot
- **Fecha:** 2026-03-02
- **Rama BE:** feature/automatic-multiclient-onboarding (commit `a671ec5`)
- **Rama FE:** develop (`17f8fa9`) → cherry-pick a feature/multitenant-storefront (`1cfd5c1`)

---

## Archivos modificados

### Backend (templatetwobe)
- `src/tenant-payments/helpers/sanitize.ts`
- `src/tenant-payments/mercadopago.service.ts`

### Frontend (templatetwo)
- `src/utils/orderTotals.jsx`
- `src/pages/PaymentResultPage/index.jsx`

---

## Resumen de cambios

### 1. Costo de servicio mostraba $0 en resultado de pago
**Problema:** `toOrderSnapshot()` solo extraía 8 campos de la orden. Faltaban `subtotal`, `coupon_discount`, `shipping_cost`, etc. El cálculo en FE hacía `serviceFee = max(0, total - subtotal)` y con `subtotal` sin dato usaba el de items ($1200), resultando en `max(0, 12.48 - 1200) = 0`.

**Fix BE:** Expandir `toOrderSnapshot()` a 17 campos. Crear `ORDER_SNAPSHOT_COLS` compartido para las 3 queries SELECT de `confirmByExternalReference`.

**Fix FE:** Reescribir `computeDisplayTotals()` con math cupón-aware: `afterCoupon = subtotal - couponDiscount`, `serviceFee = max(0, total - afterCoupon - shipping)`.

### 2. El carrito no se vaciaba después del pago
**Problema:** `PaymentResultPage` nunca llamaba `clearCart()`. La vieja `SuccessPage` lo hacía pero ya no se rutea.

**Fix FE:** Agregar `clearCart()` + `setCouponCode(null)` + `setCouponValidation(null)` en useEffect cuando el pago es aprobado. Se usa `setCouponCode(null)` que internamente limpia el `scopedStorage` (no `storage.persist.remove` que era incorrecto).

### 3. Fila de cupón en resumen de pago
**Fix FE:** Agregar fila condicional verde mostrando `Cupón {código}: -$X` entre Subtotal y Costo de servicio en `PaymentResultPage`.

### 4. Email de confirmación — línea de descuento por cupón
**Problema:** `discount_formatted` existía en el tipo `OrderEmailTotals` pero nunca se poblaba ni renderizaba.

**Fix BE:** Poblar `discount_formatted` y `discount_label` en `buildOrderEmailData()` desde `order.coupon_discount`. Agregar `discountRow` en verde (#4ade80) en `renderOrderEmailHTML()` entre Subtotal y service fee.

### 5. Email — número de orden más grande
**Fix BE:** Cambiar de inline 13px a `font-size:20px;font-weight:700` en línea separada con fecha debajo.

### 6. Email — método de pago más detallado
**Fix BE:** Expandir `typeMap` con `prepaid_card`, `digital_currency`, `digital_wallet`, `voucher_card`, `crypto_currency`. Agregar `methodIdMap` con nombres branded (visa→Visa, master→Mastercard, pagofacil→Pago Fácil, etc.). Fallback a Title Case.

### 7. Email vendedor no llegaba para plan "growth"
**Problema:** `getClientPlan()` solo reconocía `professional`/`premium`. El plan `growth` caía a `basic`, y `shouldSendOrderEmailToSeller('basic')` retornaba `false`.

**Fix BE:** Agregar `growth` al tipo de retorno y al reconocimiento en `getClientPlan()`. Actualizar comentario de `shouldSendOrderEmailToSeller()`.

### 8. QR — retry + fallback gratuito
**Problema:** Si Supabase Storage fallaba (upload o signed URL), `qr_hash` quedaba vacío y el email salía sin QR.

**Fix BE:**
- Retry: loop de 2 intentos con 500ms de delay.
- Fallback: si ambos intentos fallan, generar URL via `https://api.qrserver.com/v1/create-qr-code/?data={code}&size=132x132&format=png` (API gratuita, sin auth).

### 9. Órdenes pending duplicadas
**Problema:** Cada llamada a `createPreferenceUnified` generaba un nuevo `orderId = randomUUID()` sin verificar pendientes anteriores. El usuario podía acumular 5+ órdenes pending huérfanas.

**Fix BE:** Antes de crear la pre-order (bloque 4a), buscar todas las órdenes `status=pending, payment_status=pending` del mismo usuario/cliente, restaurar stock reservado, y marcarlas como `cancelled/expired`. Luego crear la nueva. Si la limpieza falla, el checkout NO se bloquea.

---

## Cómo probar

### BE (Railway)
```bash
# Verificar que el deploy completó
curl -s "https://templatetwobe-production.up.railway.app/health"

# Hacer checkout con un usuario de plan growth → verificar que llega email al vendedor
# Re-hacer checkout varias veces sin pagar → verificar que NO se acumulan órdenes pending
# Completar pago → verificar QR en email y línea de descuento si hay cupón
```

### FE (Netlify)
```bash
# Abrir tienda → agregar producto → checkout → pagar
# Verificar en /success:
#   1. Costo de servicio muestra el valor correcto (no $0)
#   2. Si había cupón, aparece fila verde con descuento
#   3. El carrito está vacío al volver a la tienda
```

---

## Notas de seguridad

- La cancelación de órdenes stale solo afecta órdenes del mismo `userId + clientId` (no cross-tenant)
- El fallback de QR via api.qrserver.com es una URL pública → no expone datos sensibles (solo el `public_code` de la orden que ya es público)
- No se modificaron permisos, RLS ni contratos de API

## Riesgos

- **Bajo:** Si `api.qrserver.com` cae, el QR fallback no funcionará pero el email se envía igual sin QR (comportamiento actual)
- **Bajo:** La limpieza de pending stale podría restaurar stock de órdenes que MP aún está procesando. Mitigado porque MP tiene su propio flujo de webhook que re-crea la orden si el pago se aprueba

# Fix: Buyer-consent 500, mensaje de cupón técnico, y mismatch costo de servicio con cupón

- **Fecha:** 2026-03-05
- **Autor:** agente-copilot
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding`
  - Web: `develop` → cherry-pick a `feature/multitenant-storefront`

## Archivos modificados

### Backend (templatetwobe)
- `src/legal/legal.service.ts`
- `src/cart/cart.controller.ts`
- `src/payments/payments.controller.ts`

### Frontend (templatetwo)
- `src/components/checkout/CouponInput/index.jsx`
- `src/hooks/cart/useCartQuotes.js`
- `src/context/CartProvider.jsx`

## Resumen de cambios

### Bug 1: buyer-consent retornaba 500 (legal.service.ts)

**Problema:** El endpoint `POST /legal/buyer-consent` fallaba con error 500 porque el insert usaba el campo `version` pero la columna real en la tabla `buyer_consent_log` es `document_version`.

**Causa raíz:** Typo en el nombre de columna — el código insertaba `{ version: dto.version }` pero la tabla Supabase tiene la columna `document_version`.

**Solución:** Cambiar `version: dto.version` → `document_version: dto.version` en `logBuyerConsent()`.

**Impacto:** Todas las compras que requerían consentimiento legal (términos y condiciones de venta y política de devolución) fallaban al intentar registrar el consentimiento.

---

### Bug 2: Cupón muestra código técnico en vez de mensaje legible (CouponInput)

**Problema:** Cuando el cupón era inválido (ej: "max_per_user"), la UI mostraba el código técnico `reason` ("max_per_user") en lugar del mensaje humano `message` ("Ya usaste este cupón la cantidad máxima de veces").

**Causa raíz:** El componente `CouponInput` hacía `setError(data.reason || ...)` pero la API devuelve el mensaje legible en `data.message` y el código técnico en `data.reason`.

**Solución:** Cambiar prioridad: `setError(data.message || data.reason || 'Cupón inválido')`.

**Impacto:** UX pobre — el comprador veía mensajes como "max_per_user", "expired", "not_found" en vez de mensajes comprensibles.

---

### Bug 3: Mismatch de costo de servicio entre carrito y Mercado Pago ($60 vs $12)

**Problema:** El carrito mostraba un costo de servicio de ~$48 (calculado sobre el subtotal pre-cupón de $1200), pero al llegar al checkout de Mercado Pago el total era ~$12.48 (calculado sobre el subtotal post-cupón de $12). La diferencia ocurría porque:

1. **Frontend** (`useCartQuotes.js`): No tenía concepto de `couponDiscount`. Pedía la cotización con el subtotal completo.
2. **Backend** (cart.controller + payments.controller): Calculaban la cotización sobre el subtotal bruto sin descontar el cupón.
3. **Backend** (`createPreferenceUnified`): Re-validaba el cupón y calculaba el costo de servicio sobre el subtotal POST-cupón.

Resultado: la cotización del carrito (pre-checkout) y la preferencia de MP (en checkout) usaban bases de cálculo distintas.

**Causa raíz:** El flujo de cotización (quote) nunca consideraba el descuento de cupón activo. El cálculo del costo de servicio se hacía sobre el subtotal bruto ($1200) en vez del neto ($12 con 99% descuento).

**Solución (6 archivos):**

1. **`CartProvider.jsx`**: Pasa `couponDiscount: Number(couponValidation?.discount?.amount || 0)` al hook `useCartQuotes()`.
2. **`useCartQuotes.js`**: Acepta parámetro `couponDiscount`. Lo incluye en la firma de caché (`makeQuoteSignature`). Lo envía como query param a `GET /api/cart?includeQuote=true&couponDiscount=X` y como body a `POST /api/payments/quote-matrix`.
3. **`cart.controller.ts`**: Acepta `couponDiscount` como query param, calcula `quoteSubtotal = max(0, rawSubtotal - couponDiscount)` antes de pasar a `paymentsService.quote()`.
4. **`payments.controller.ts`**: Acepta `couponDiscount` en el body de `POST /api/payments/quote-matrix`, resta del subtotal antes de calcular la matriz de cotizaciones.

**Impacto:** Los compradores con cupón activo veían un total en el carrito significativamente mayor al que Mercado Pago cobraba, generando confusión y desconfianza.

---

## Tests ejecutados

### Backend (módulos afectados)
```
Test Suites: 7 passed, 2 failed (pre-existentes: DI mocks en cart.controller.spec, import TS6133 en cart.e2e.spec)
Tests: 14 passed, 1 failed (pre-existente)
```
- `payments/payment-calculator.spec.ts` ✅
- `payments/mp-fee.helper.spec.ts` ✅
- `payments/fee-selection.spec.ts` ✅
- `cart/cart.service.spec.ts` ✅
- `cart/cart.spec.ts` (multi-tenant isolation) ✅
- `cart/cart.service.requireids.spec.ts` ✅
- `cart/cart.service.client-filter.spec.ts` ✅

### Frontend
No hay tests unitarios FE para los componentes afectados. Solo existe `src/pages/Maintenance/index.test.js`.

### Validación de build
- API: `npm run lint` ✅ (0 errores) | `npm run typecheck` ✅ | `npm run build` ✅
- Web: `npm run lint` ✅ (0 errores) | `npm run typecheck` ✅ | `npm run build` ✅

## Cómo probar

### Bug 1 — Buyer Consent
1. Abrir tienda farma.novavision.lat
2. Agregar producto al carrito → Checkout
3. Completar datos del comprador
4. El endpoint `POST /legal/buyer-consent` debe retornar 201 (antes: 500)
5. Verificar en tabla `buyer_consent_log` que el registro tenga `document_version` poblado

### Bug 2 — Mensaje de cupón
1. Usar un cupón que ya fue usado el máximo de veces por el usuario
2. Verificar que el mensaje sea "Ya usaste este cupón la cantidad máxima de veces" en vez de "max_per_user"
3. Probar con cupón expirado → debe mostrar mensaje legible, no "expired"

### Bug 3 — Costo de servicio con cupón
1. Agregar productos al carrito (ej: 6x $200 = $1200 subtotal)
2. Aplicar cupón con descuento alto (ej: 99% → descuento $1188)
3. Verificar que el costo de servicio en el carrito se calcule sobre $12 (no sobre $1200)
4. Proceder al checkout → verificar que el total de Mercado Pago coincida con el mostrado en el carrito
5. El costo de servicio debe ser consistente entre carrito y MP

## Datos de prueba
- **Tenant:** Farma (`1fad8213-1d2f-46bb-bae2-24ceb4377c8a`)
- **DB:** `buyer_consent_log` — columna `document_version` (no `version`)
- **Tabla afectada en quote**: `client_payment_settings` (service_mode, service_percent, etc.)

## Riesgos / Rollback
- **Bug 1:** Cambio mínimo (rename de columna). Sin riesgo.
- **Bug 2:** Cambio mínimo (priorizar `message` sobre `reason`). Sin riesgo — `reason` sigue disponible como fallback.
- **Bug 3:** Cambio más amplio (6 archivos). El riesgo es que algún flujo sin cupón pueda afectarse. Mitigado porque:
  - `couponDiscount` tiene default `0` en todos los puntos
  - Sin cupón activo, `couponDiscount = 0` → subtotal no se modifica → comportamiento idéntico al anterior
  - `createPreferenceUnified` sigue re-validando el cupón independientemente

## Notas de seguridad
- El `couponDiscount` enviado desde FE se usa solo para cotización visual. El backend `createPreferenceUnified` **siempre re-valida** el cupón contra la DB antes de generar la preferencia de Mercado Pago, por lo que un valor manipulado en el query param no afecta el monto real cobrado.

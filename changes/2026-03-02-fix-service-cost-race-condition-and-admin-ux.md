# Fix: Race condition en costo de servicio + Mejoras UX admin pagos

- **Fecha:** 2026-03-02
- **Autor:** agente-copilot
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` (commit `dab705e`)
  - Web: `develop` (commit `8367219`) → cherry-pick a `feature/multitenant-storefront` (`aa29fb0`)

## Archivos modificados

### Backend (templatetwobe)
- `src/payments/payments.service.ts`
- `src/payments/admin-payments.controller.ts`

### Frontend (templatetwo)
- `src/hooks/cart/useCartQuotes.js`
- `src/components/admin/PaymentsConfig/index.jsx`

## Resumen de cambios

### 1. Race condition en costo de servicio (useCartQuotes.js)
**Problema:** Cuando `paymentSettings` llegaba (null → objeto), la identidad de `quoteCart` cambiaba → el efecto auto-quote se re-ejecutaba → el cleanup cancelaba el timeout de 300ms → la key era la misma → skip → la cotización nunca se ejecutaba → "Costo del Servicio" no aparecía en el resumen.

**Solución:**
- Patrón `quoteCartStableRef`: ref que siempre apunta a la última versión de `quoteCart`, evitando que el efecto dependa de su identidad.
- Efecto safety-net: detecta transición `paymentSettings: null → object`, resetea `lastMainQuoteKeyRef.current = ''` para forzar re-cotización, y dispara `quoteCartStableRef.current?.()` directamente.

### 2. Defaults completos en getEffectiveConfig (payments.service.ts)
**Problema:** Cuando no existía fila en `client_payment_settings`, el fallback retornaba solo campos básicos, omitiendo `fee_routing`, `service_mode`, `service_percent`, `service_fixed`, `service_label`, `pay_with_debit`, `excluded_payment_types`, `excluded_payment_methods`.

**Solución:** Se agregaron todos los defaults faltantes al objeto fallback.

### 3. Audit trail updated_by (admin-payments.controller.ts)
**Problema:** Los cambios de configuración de pagos no registraban quién los hizo.

**Solución:** Se extrae `adminUserId` del JWT (`req.user.id || req.user.sub`) y se incluye `updated_by: adminUserId` en el payload de upsert.

### 4. Fix validación y label en PaymentsConfig (index.jsx)
**Problema A:** La validación usaba `surchargeOk` (legacy `surchargeMode/surchargePercent`) que siempre pasaba, en vez de validar los campos activos (`serviceMode/servicePercent/serviceFixed`).

**Solución:** Nueva validación `serviceOk` que valida según el `serviceMode` activo.

**Problema B:** El preview de label usaba `form.surchargeLabel` (siempre vacío) en vez de `form.serviceLabel`.

**Solución:** Reemplazado por `form.serviceLabel`.

### 5. Mejoras UX en PaymentsConfig
| Elemento | Antes | Después |
|----------|-------|---------|
| Modo servicio | `"Usar tarifa MP (mp_fee)"` | `"Tarifa de Mercado Pago (automático)"` |
| Fee routing | `"Fee routing"` + `"Vendedor absorbido"` | `"¿Quién paga el costo del servicio?"` + `"El vendedor absorbe el costo"` |
| Modo mp_fee activo | Sin feedback visual | Texto: "El costo se calcula automáticamente según la tarifa vigente de MP..." |
| Acreditación | "Se usa para simulación y reportes" | "Días que tarda MP en depositar en tu cuenta. No afecta al comprador..." |
| Toggle Débito | "Débito (1 Cuota)" | "Débito (1 cuota) por defecto" con tooltip |

## Cómo probar

### Race condition (costo de servicio)
1. Ir a farma.novavision.lat
2. Agregar producto al carrito → ir a /cart
3. Verificar que "Costo del Servicio" aparece en el resumen lateral
4. Seleccionar diferentes medios de pago → el costo se actualiza
5. Abrir "Ver estimación por medio de pago" → muestra tabla comparativa

### Admin UX
1. Ir al dashboard admin → Configuración de Pagos
2. Verificar labels en español comprensible (no códigos técnicos)
3. Seleccionar modo "Tarifa de Mercado Pago" → ver texto informativo
4. Verificar que "¿Quién paga el costo del servicio?" tiene opciones claras
5. Guardar configuración → verificar que `updated_by` se persiste en DB

## Notas de seguridad
- `updated_by` se extrae del JWT server-side, no del body del request
- No se exponen SERVICE_ROLE_KEY ni claves sensibles

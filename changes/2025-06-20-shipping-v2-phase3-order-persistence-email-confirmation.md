# Cambio: Shipping V2 – Fase 3: Persistencia en orden, email y confirmación

- **Autor:** agente-copilot
- **Fecha:** 2025-06-20
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

---

## Archivos modificados

### Backend (API)
- `src/tenant-payments/mercadopago.dto.ts` — Nuevos DTOs: `ShippingAddressInputDto`, `DeliveryPayloadDto`; campo `delivery` en `CreatePrefForPlanDto`
- `src/tenant-payments/mercadopago.controller.ts` — Pasar `delivery` del body al servicio
- `src/tenant-payments/mercadopago.service.ts` — Múltiples cambios:
  - Tipos `OrderEmailData` ampliados con campos shipping
  - `createPreferenceUnified`: lógica de resolución de delivery (address, pickup, arrange), MP item de envío, persistencia en pre-orden
  - `buildOrderEmailData`: `shipping_formatted` en totals, campos `delivery_method`, `shipping_cost`, `shipping_label`
  - `renderOrderEmailHTML`: `deliveryBlock` reescrito como switch por `delivery_method`, nueva fila `shippingRow` en tfoot

### Frontend (Web)
- `src/hooks/cart/useCheckout.js` — Acepta `deliveryPayload`, `selectedAddress`, `saveAddress`; construye objeto `delivery` en payload de checkout
- `src/context/CartProvider.jsx` — Reordena hooks (shipping antes de checkout); pasa `deliveryPayload` y `selectedAddress` a `useCheckout`
- `src/pages/PaymentResultPage/index.jsx` — Sección "Datos de envío" nueva; fila de envío en totales
- `src/components/OrderDetail/index.jsx` — Sección de método de envío en accordion "Entrega y seguimiento"; fila de costo de envío en "Detalle de costos"; nuevos propTypes

---

## Resumen

Fase 3 del Shipping V2: la orden ahora persiste datos de envío (delivery_method, shipping_cost, shipping_label, shipping_address, delivery_address, pickup_info, estimated_delivery_min/max). El email de confirmación muestra información diferenciada por método (domicilio/retiro/coordinar) y una fila de costo de envío. Las vistas de PaymentResultPage y OrderDetail muestran la información de envío y el costo discriminado.

## Por qué

Completar el flujo de checkout end-to-end: el comprador elige método de envío en el carrito (Fase 2), el backend persiste esa elección en la orden y la refleja en email + vistas de confirmación (Fase 3).

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Web: `npm run dev` (terminal front)
3. Configurar envío en admin (Fase 1 ya implementada)
4. Como comprador:
   - Agregar productos al carrito
   - Seleccionar método de envío (delivery con CP, pickup, o coordinar)
   - Completar checkout → verificar redirect a MP
   - Al aprobar pago → verificar:
     - Email muestra sección de envío correcta y fila de costo
     - PaymentResultPage muestra "Datos de envío" y costo en totales
     - OrderDetail (mis pedidos) muestra envío en accordion y costo en detalle

## Notas de seguridad

- El backend revalida shipping_cost del quote (no confía en el monto que envía el front)
- La dirección se resuelve de `user_addresses` (si `address_id`) o se recibe inline con validación class-validator
- `save_address` solo opera si no existe `address_id` (evita duplicados)
- RLS de `user_addresses` filtra por `user_id` + `client_id`

## Migraciones

No se requieren nuevas migraciones — todas las columnas de shipping fueron creadas en Fase 1 (`20260211_shipping_settings_zones.sql` sección 5) y Fase 2 (`20260211_user_addresses.sql`).

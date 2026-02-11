# Shipping V2 — Phase 2: Quote Service + Addresses + Checkout Integration

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

## Resumen

Implementación completa de Phase 2 del Shipping V2: servicio de cotización,
módulo CRUD de direcciones, y componentes de checkout para seleccionar método de
envío, ingresar dirección y ver el costo de envío en el resumen del carrito.

## Archivos Backend (API)

### Nuevos
- `migrations/backend/20260211_user_addresses.sql` — Migración: tabla `user_addresses` con RLS (6 políticas), trigger updated_at, índices, + columna `shipping_label` en `orders`
- `src/addresses/dto/address.dto.ts` — DTOs: CreateAddressDto (7 required, 5 optional), UpdateAddressDto (all optional)
- `src/addresses/addresses.service.ts` — CRUD con ownership, límite 10 addresses/user, auto-default primera dirección
- `src/addresses/addresses.controller.ts` — 5 endpoints bajo ClientContextGuard: GET /, GET /:id, POST /, PUT /:id, DELETE /:id
- `src/addresses/addresses.module.ts` — Importa CommonModule, provee/exporta AddressesService
- `src/shipping/shipping-quote.service.ts` — Servicio de cotización: zone matching (OR con prioridad CP > provincia > position), quote_id + valid_until (30min TTL), free shipping calculation, in-memory cache con cleanup periódico
- `src/shipping/dto/shipping-quote.dto.ts` — DTOs: ShippingQuoteDto (delivery_method, zip_code, province, subtotal), RevalidateQuoteDto

### Modificados
- `src/app.module.ts` — Registra AddressesModule
- `src/shipping/shipping.module.ts` — Registra ShippingQuoteService
- `src/shipping/shipping.controller.ts` — 3 nuevos endpoints: POST /shipping/quote, POST /shipping/quote/revalidate, GET /shipping/quote/:quoteId

## Archivos Frontend (Web)

### Nuevos
- `src/hooks/cart/useShipping.js` — Hook: fetch settings, método seleccionado, CP input, request quote, free shipping info, delivery payload para checkout
- `src/hooks/cart/useAddresses.js` — Hook: CRUD de direcciones, auto-select default, selectedAddress
- `src/components/checkout/ShippingSection/index.jsx` — Componente principal: cards de método, input CP, resultado de cotización, selector de direcciones con formulario inline, banners de envío gratis, info de pickup/arrange
- `src/components/checkout/ShippingSection/style.jsx` — 25+ styled-components con CSS custom properties (`--nv-ship-*`), siguiendo el patrón del CartPage

### Modificados
- `src/hooks/cart/index.js` — Barrel exports: agregados useShipping, useAddresses
- `src/context/CartProvider.jsx` — Instancia useShipping + useAddresses, expone en contexto
- `src/pages/CartPage/index.jsx` — Integra ShippingSection antes de PlanSelector, agrega línea de envío en resumen de precios, shippingCost sumado al total

## Endpoints nuevos

| Método | Ruta | Descripción |
|--------|------|-------------|
| POST | `/shipping/quote` | Cotizar envío (delivery_method, zip_code, subtotal) → quote_id + cost |
| POST | `/shipping/quote/revalidate` | Revalidar quote (expired? price changed?) |
| GET | `/shipping/quote/:quoteId` | Obtener quote cacheado |
| GET | `/addresses` | Listar direcciones del usuario |
| GET | `/addresses/:id` | Obtener dirección por ID |
| POST | `/addresses` | Crear dirección (max 10) |
| PUT | `/addresses/:id` | Actualizar dirección |
| DELETE | `/addresses/:id` | Eliminar dirección |

## Algoritmo de zone matching

**OR con prioridad (confirmado por TL):**
1. Ordenar zonas por `position ASC`
2. Buscar match exacto de CP entre `zipCodes[]` de cada zona
3. Si no hubo match, buscar match de provincia
4. Si ninguna zona matchea → error `NO_ZONE_MATCH`
5. Free shipping: si `subtotal >= threshold` → cost = 0

## Cómo probar

### Backend
```bash
cd apps/api
npm run start:dev
# POST /shipping/quote con body:
# { "delivery_method": "delivery", "zip_code": "C1043", "subtotal": 5000 }
# GET /addresses (requiere auth)
# POST /addresses con body de dirección
```

### Frontend
```bash
cd apps/web
npm run dev
# Abrir /cart con productos
# Debería aparecer sección de Envío antes de Plan de Pago
# Seleccionar método → ingresar CP → ver cotización
# Agregar dirección → ver en listado
```

### Migración
Ejecutar en Supabase SQL Editor:
- `migrations/backend/20260211_user_addresses.sql`

## Notas de seguridad
- Las direcciones están protegidas por RLS: cada usuario solo ve/edita las suyas
- El admin puede ver direcciones de su tenant (para gestión de pedidos)
- Los quotes son in-memory con TTL 30min — no persisten datos sensibles
- No se exponen tokens ni claves en el frontend

## Riesgos
- La migración debe ejecutarse manualmente en Supabase antes de usar los endpoints
- El quote_id no se envía aún al checkout (será integrado en Phase 3 con delivery payload en create-preference)
- Los componentes de checkout son nuevos y necesitan testing visual con clientes reales

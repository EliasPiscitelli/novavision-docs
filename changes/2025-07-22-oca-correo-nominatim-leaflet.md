# Cambio: Providers OCA/Correo Argentino + Nominatim/Leaflet verificación de dirección

- **Autor:** agente-copilot
- **Fecha:** 2025-07-22
- **Rama API:** `feature/automatic-multiclient-onboarding` (commit `cb538a1`)
- **Rama Web:** `feature/multitenant-storefront` (commit `df03a1e`)

## Archivos modificados/creados

### Backend (API)
- `src/shipping/providers/oca.provider.ts` — **NUEVO** (~400 líneas)
- `src/shipping/providers/correo-argentino.provider.ts` — **NUEVO** (~370 líneas)
- `src/shipping/providers/index.ts` — Agregados exports de OCA y CorreoArgentino
- `src/shipping/shipping.service.ts` — Registrados nuevos providers en constructor

### Frontend (Web)
- `src/hooks/useNominatim.js` — **NUEVO** (~105 líneas)
- `src/components/checkout/ShippingSection/AddressVerifyMap.jsx` — **NUEVO** (~230 líneas)
- `src/components/checkout/ShippingSection/index.jsx` — Integración lazy del mapa
- `package.json` / `package-lock.json` — Dependencias: leaflet, react-leaflet

## Resumen de cambios

### 1. OCA Provider (SOAP)
- Usa la API ePak/OCA via SOAP (XML envelopes custom, sin librería SOAP externa)
- Soporta: `testConnection`, `quoteRates` (Tarifar_Envio_Corporativo), `createShipment` (IngresoOR), `getTracking` (Tracking_Pieza), `handleWebhook`
- Credenciales: CUIT, operativa domicilio/sucursal, usuario, password, environment
- Mapeo de 15+ estados OCA → `ShipmentStatus` enum
- Soporta cotización a domicilio y a sucursal (dos operativas)

### 2. Correo Argentino Provider (REST)
- API MiCorreo REST con Bearer token
- Soporta: `testConnection`, `quoteRates` (cotizador/precio), `createShipment` (envios), `getTracking` (envios/{code}/trazas), `handleWebhook`
- Credenciales: api_token, customer_code, contract_number, environment
- Mapeo de 20+ estados Correo → `ShipmentStatus` enum
- Response parsing flexible (array de tarifas, objeto único, o precio en root)

### 3. Nominatim Geocoding Hook
- `useNominatim`: geocodifica direcciones via OpenStreetMap Nominatim (gratis, sin API key)
- Rate limit respetado (1 req/segundo)
- Devuelve: lat, lng, displayName, boundingBox, address details
- Diseñado para botón "Verificar dirección" (no autocomplete, per decisión TL)

### 4. Leaflet Address Verification Map
- `AddressVerifyMap`: componente de mapa con marker draggable
- Lazy-loaded via `React.lazy` + `Suspense` (no impacta bundle inicial)
- Se muestra solo cuando el usuario hace click en "Verificar dirección"
- OpenStreetMap tiles (gratis, no requiere API key)
- Fix de iconos Leaflet para Vite (usa CDN unpkg)
- Integrado en ShippingSection dentro del formulario de dirección

## Por qué

Estos ítems estaban marcados como "deferred" en fases anteriores del shipping V2. El TL indicó completar todo sin dejar pendientes. Los providers OCA y Correo Argentino completan la suite de transportistas argentinos (manual, Andreani, OCA, Correo). La verificación de dirección mejora la precisión del envío.

## Cómo probar

### Backend
```bash
cd apps/api
npx tsc --noEmit  # 0 errores
npx eslint src/shipping/providers/oca.provider.ts src/shipping/providers/correo-argentino.provider.ts  # solo warnings de any
```

### Frontend
```bash
cd apps/web
npm run dev
# 1. Ir al carrito con productos
# 2. Seleccionar método "Delivery"
# 3. Agregar dirección → completar calle y ciudad
# 4. Aparece botón "Verificar dirección"
# 5. Click → muestra mapa con pin
# 6. Pin es draggable para ajustar posición
```

## Notas de seguridad

- Nominatim: no envía datos sensibles (solo dirección pública para geocoding)
- Leaflet tiles: OpenStreetMap (servicio público sin autenticación)
- Providers: credenciales se almacenan en `shipping_integrations.credentials` (JSONB en DB, server-side only)
- Los providers no se activan hasta que el admin configure credenciales válidas

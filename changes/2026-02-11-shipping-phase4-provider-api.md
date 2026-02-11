# Cambio: Shipping V2 — Phase 4: Provider API Quote Flow + UI

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Web:** `feature/multitenant-storefront`
- **Commits:** API `43a1434`, Web `317b9b6`

---

## Resumen

Implementación de la Fase 4 del sistema de envíos V2: **cotización real vía provider API** (Andreani y futuros proveedores). Incluye migración de DB, flujo BE completo de cotización por proveedor, campo de peso en productos, configuración de dirección de origen en admin, y wiring del carrito para pasar items al quote endpoint.

## Archivos Modificados

### Backend (API)

| Archivo | Cambio |
|---------|--------|
| `migrations/backend/20260211_shipping_phase4_provider_api.sql` | **NUEVO** — `weight_grams INT` en products + `origin_address JSONB` en client_shipping_settings |
| `src/shipping/shipping-quote.service.ts` | `calculateProviderApiCost()` (~130 líneas): valida items/zip/integración/provider/origen, busca pesos, llama `provider.quoteRates()`, retorna tarifa más barata |
| `src/shipping/shipping.service.ts` | Nuevos métodos públicos: `getActiveIntegrationForQuote()`, `getProviderByName()` |
| `src/shipping/shipping-settings.service.ts` | Campo `originAddress` en type, defaults y mapper |
| `src/shipping/dto/shipping-quote.dto.ts` | `QuoteItemDto` (product_id + quantity), campo `items` opcional en ShippingQuoteDto |
| `src/products/products.service.ts` | `weight_grams` en ALLOWED_FIELDS, mapping camelCase↔snake_case, alias en 4 response mappers |

### Frontend (Web)

| Archivo | Cambio |
|---------|--------|
| `src/components/ProductModal/index.jsx` | Campo "Peso (gramos)" en formulario de producto |
| `src/components/ProductModal/productFieldHelp.jsx` | Help text para weightGrams |
| `src/components/admin/ShippingPanel/ShippingConfig.jsx` | Radio `provider_api`, formulario de dirección de origen (6 campos), validación |
| `src/hooks/cart/useShipping.js` | Param `cartItems`, items en body de `/shipping/quote` para modo provider_api |
| `src/context/CartProvider.jsx` | Pasa `cartItems` al hook useShipping |

## Por qué

La Fase 4 habilita cotización real con transportistas (Andreani, OCA futuro) en lugar de tarifas fijas/por zona. Los clientes con plan `growth+` pueden configurar una integración activa y dirección de origen para que el sistema calcule automáticamente el costo de envío usando las APIs de los proveedores.

## Flujo end-to-end

1. **Admin** configura modo "Cotización automática" en ShippingConfig → guarda origin_address
2. **Admin** carga peso en cada producto desde ProductModal
3. **Admin** configura integración con Andreani (ya existente de Fase 1)
4. **Comprador** agrega productos al carrito → ingresa CP destino → useShipping envía items al quote endpoint
5. **Backend** resuelve integración activa → busca pesos de productos → llama `provider.quoteRates()` → retorna tarifa más barata
6. **Comprador** ve costo real de envío en el carrito

## Cómo probar

### Backend
```bash
cd apps/api
npx tsc --noEmit          # 0 errores
npx eslint src/shipping/  # solo warnings pre-existentes
npm run start:dev
```

### Frontend
```bash
cd apps/web
npm run dev
```

### Test manual
1. Admin → Productos → editar producto → completar "Peso (gramos)" → guardar
2. Admin → Configuración → Envíos → seleccionar "Cotización automática" → completar dirección de origen → guardar
3. Admin → Integraciones → Andreani → debe estar activa y default
4. Storefront → agregar producto al carrito → ingresar CP → verificar que la cotización usa la API real

## Notas de seguridad

- Las credenciales de integración se desencriptan server-side con EncryptionService (AES-256-GCM)
- Plan gating: `provider_api` requiere plan `growth+` (validado en `FEATURE_CATALOG`)
- Pesos por defecto (500g) si un producto no tiene weight_grams configurado
- El origin_address se valida en admin antes de guardar

## Pendientes opcionales (Phase 4+)

- Nominatim + Leaflet para verificación de dirección (deferred — no bloquea el flujo)
- OCA/Correo Argentino providers (interfaces listas, implementación futura)

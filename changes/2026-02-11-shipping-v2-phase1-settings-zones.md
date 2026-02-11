# Shipping V2 — Phase 1: Settings + Zones + Admin Config UI

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Web:** `feature/multitenant-storefront`

## Archivos creados/modificados

### Backend (API)
| Archivo | Tipo |
|---------|------|
| `migrations/backend/20260211_shipping_settings_zones.sql` | Nuevo — Migración SQL |
| `src/shipping/dto/shipping-settings.dto.ts` | Nuevo — DTOs |
| `src/shipping/shipping-settings.service.ts` | Nuevo — Service con CRUD + cache |
| `src/shipping/shipping.controller.ts` | Modificado — 7 endpoints nuevos |
| `src/shipping/shipping.module.ts` | Modificado — provider nuevo |

### Frontend (Web)
| Archivo | Tipo |
|---------|------|
| `src/components/admin/ShippingPanel/ShippingConfig.jsx` | Nuevo — Config UI |
| `src/components/admin/ShippingPanel/configStyle.jsx` | Nuevo — Styled-components |
| `src/components/admin/ShippingPanel/index.jsx` | Modificado — Tab "Configuración" |

## Resumen

### Migración SQL
- ENUM `shipping_pricing_mode` (zone, flat, provider_api)
- Tabla `client_shipping_settings`: 1 row por tenant, métodos de envío (delivery/pickup/arrange), pricing_mode, free_shipping, labels, estimated delivery
- Tabla `shipping_zones`: múltiples por tenant, provinces (text[]), zip_codes (text[]), cost, position, estimated_delivery
- RLS: `server_bypass` + `tenant_select` + `admin_write`
- Columnas nuevas en `orders`: delivery_method, shipping_cost, shipping_address (JSONB), pickup_info (JSONB), estimated_delivery_min/max
- Trigger `update_updated_at` para timestamps automáticos

### Backend Service
- `ShippingSettingsService` con patrón idéntico a `ClientPaymentSettingsService`
- Cache en memoria con TTL 5min, invalidación en writes
- snake_case (DB) → camelCase (API) mapping
- DEFAULTS fallback para settings sin configurar
- Validaciones: free_shipping threshold > 0, pickup requiere address

### Endpoints (7 nuevos)
- `GET /shipping/settings` — Obtener config
- `PUT /shipping/settings` — Crear/actualizar config
- `GET /shipping/zones` — Listar zonas
- `GET /shipping/zones/:id` — Detalle zona
- `POST /shipping/zones` — Crear zona
- `PUT /shipping/zones/:id` — Actualizar zona
- `DELETE /shipping/zones/:id` — Eliminar zona

### Frontend Config UI
- Tab "Configuración" como primera pestaña del ShippingPanel
- 3 métodos de envío (delivery, pickup, arrange) con cards colapsables
- Delivery: radio zone/flat, inline zone CRUD
- Pickup: dirección, instrucciones, horarios
- Arrange: WhatsApp, mensaje personalizado
- Free shipping: toggle + threshold
- Preview "Así lo verá tu comprador"
- Zone modal: 24 provincias AR como tags, CP CSV, costo, prioridad, días estimados

## Por qué
Implementación de Phase 1 del plan Shipping V2 (Bloques 1 + 5) según análisis completo aprobado por TL. Decisiones confirmadas: solo usuarios logueados, zone match OR con prioridad.

## Cómo probar
1. Ejecutar migración SQL contra Supabase backend
2. Levantar API: `npm run start:dev` (terminal back)
3. Levantar Web: `npm run dev` (terminal front)
4. Ir a Admin Dashboard > Envíos > tab Configuración
5. Habilitar método "Envío a domicilio", elegir pricing por zona, crear zona
6. Verificar endpoints con cURL:
   ```bash
   curl -H "x-client-id: <UUID>" -H "Authorization: Bearer <JWT>" \
     http://localhost:3000/shipping/settings
   ```

## Notas de seguridad
- Todos los endpoints protegidos por `ClientContextGuard` + `PlanAccessGuard`
- `@PlanFeature('commerce.shipping')` en el controller
- RLS con `server_bypass` para service_role + políticas por tenant
- No se exponen secrets ni SERVICE_ROLE_KEY en frontend

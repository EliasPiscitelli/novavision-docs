# Cambio: PR5 — ShippingPanel Admin + Shipment Tokens + OrderDetail Timeline

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama Web:** `feature/multitenant-storefront` (commit `60ebb90`), cherry-picked a `develop` (`2ab18be`) y `feature/onboarding-preview-stable` (`5d7771c`)

## Archivos modificados / creados

### Nuevos
| Archivo | Propósito |
|---------|-----------|
| `apps/web/src/components/admin/ShippingPanel/index.jsx` | Componente CRUD de integraciones de envío |
| `apps/web/src/components/admin/ShippingPanel/style.jsx` | Styled components del panel |

### Modificados
| Archivo | Cambio |
|---------|--------|
| `apps/web/src/pages/AdminDashboard/index.jsx` | Nueva sección "shipping" (VALID_SECTIONS, SECTION_DETAILS, DEFAULT_SECTIONS_ORDER, SECTION_FEATURES, switch case) |
| `apps/web/src/utils/statusTokens.js` | `SHIPMENT_STATUS_LABELS` (10 estados granulares) + `getShipmentStatusToken()` |
| `apps/web/src/components/OrderDetail/index.jsx` | Carga shipment data, muestra timeline de eventos (admin) |

## Resumen de cambios

### ShippingPanel (nuevo)
- CRUD completo de integraciones de envío vía `/shipping/integrations`
- Grid de tarjetas con toggle activo/inactivo, badge "Default", acciones (editar, probar conexión, eliminar)
- Modal crear/editar con campos de credenciales dinámicos por proveedor:
  - `manual`: sin credenciales
  - `andreani`: API Key, Contrato, Código remitente
  - `oca`: Usuario, Contraseña, CUIT, Cuenta
  - `correo_argentino`: Usuario, Contraseña, ID contrato
  - `custom`: URL Base, API Key
- Estado vacío con guía para crear primera integración
- Test de conexión con resultado inline

### AdminDashboard
- Sección "shipping" → "Envíos" con descripción y feature gating (`dashboard.shipping`)
- Posicionada después de "payments" en el orden de secciones

### statusTokens.js
- 10 estados granulares de shipment: `pending`, `label_created`, `picked_up`, `in_transit`, `out_for_delivery`, `delivered`, `attempted_delivery`, `returned_to_sender`, `exception`, `cancelled`
- Función `getShipmentStatusToken(theme, status)` para UI

### OrderDetail
- Al abrir como admin, carga datos del shipment (`GET /shipping/orders/:orderId`)
- Si hay eventos (`shipment.events`), muestra timeline con timestamp + status + description
- Silencia 404 cuando no hay shipment (esperado)

## Motivo

PR5 del plan de shipping/tracking. Se necesitaba un panel admin para que los dueños de tienda configuren sus proveedores de envío (desde el simple "manual" hasta integración por API). El OrderDetail se mejoró para mostrar el historial de eventos del shipment cuando existe.

## Cómo probar

1. Levantar API: `cd apps/api && npm run start:dev`
2. Levantar Web: `cd apps/web && npm run dev`
3. Login como admin → Admin Dashboard → sección "Envíos"
4. Crear integración Manual → verificar que aparece como card
5. Probar conexión → debe mostrar "Conexión OK"
6. Editar → cambiar nombre → guardar
7. En Órdenes → abrir una orden → accordion "Entrega y seguimiento" debe cargar shipment data si existe

## Notas de seguridad

- Credenciales nunca se pre-llenan al editar (se envían vacías para no exponer)
- Las credenciales se encriptan server-side vía `EncryptionService` (AES-256-GCM)
- Solo admins acceden a los endpoints de integraciones (validado server-side por RLS + ClientContextGuard)

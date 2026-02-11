# Fix: Eliminación de leak cross-tenant por RLS en endpoints públicos y de pago

- **Autor:** agente-copilot
- **Fecha:** 2025-07-14
- **Rama BE:** feature/automatic-multiclient-onboarding (commit `2d91944`)
- **Rama FE:** feature/multitenant-storefront (commit `a6792fb`)

## Archivos modificados

### Backend (templatetwobe)
- `src/products/products.controller.ts` — 4 usages de `makeRequestSupabaseClient` → `this.adminClient`
- `src/social-links/social-links.service.ts` — 1 usage removido
- `src/tenant-payments/mercadopago.controller.ts` — 5 usages → `this.adminClient`
- `src/payments/payments.controller.ts` — 2 usages → `this.adminClient`, agregado `@Inject('SUPABASE_ADMIN_CLIENT')`

### Frontend (templatetwo)
- `src/services/homeData/useFetchHomeData.base.jsx` — Cache keys incluyen tenant slug
- `src/services/homeData/homeService.jsx` — Cache key incluye tenant slug

## Resumen del cambio

### Problema (CRÍTICO)
`makeRequestSupabaseClient(req)` crea un cliente Supabase con el JWT del usuario + anon_key. Las políticas RLS evalúan `current_client_id()` desde el JWT, que resuelve al tenant **del usuario autenticado** — NO al tenant **que está visitando**. Cuando un usuario de Tenant A visita la tienda de Tenant B:
- Los productos de Tenant B NO aparecían (RLS los filtraba)
- La config de Tenant A se mostraba en la tienda de Tenant B
- Los pagos podían fallar silenciosamente

### Solución
- **Endpoints públicos y de pago**: usan `this.adminClient` (service_role, bypassea RLS) + filtro manual `.eq('client_id', clientId)` donde `clientId` proviene del `TenantContextGuard` (header `x-tenant-slug`)
- **Endpoints de usuario (cart/favorites)**: mantienen `makeRequestSupabaseClient` correctamente — operan sobre datos del usuario autenticado, inherentemente scopeados a su tenant

### Frontend
- Cache keys de `rawStorage` ahora incluyen el slug del tenant para evitar contaminación entre pestañas en desarrollo (en producción, cada subdominio es un origin diferente)

## Por qué
Un usuario autenticado en Tenant A que navega a Tenant B veía la config, productos y temas de Tenant A. Esto es un bug crítico de aislamiento multi-tenant.

## Cómo probar
1. Iniciar sesión como usuario de Tenant A (ej: `tienda-a.novavision.lat`)
2. Abrir en nueva pestaña Tenant B (ej: `tienda-b.novavision.lat`)
3. Verificar que:
   - Template/palette de Tenant B se muestra correctamente
   - Productos de Tenant B aparecen (no los de A)
   - El checkout funciona con los productos de Tenant B
4. Abrir ambas tiendas simultáneamente y verificar que no se mezclan datos

## Endpoints auditados (clasificación completa)

| Endpoint | Antes | Después | Motivo |
|---|---|---|---|
| GET /home/data | makeRequestSupabaseClient | adminClient | Público (fix previo commit 60bd800) |
| GET /home/navigation | makeRequestSupabaseClient | adminClient | Público (fix previo) |
| GET /products | makeRequestSupabaseClient | adminClient | Catálogo público |
| GET /products/search | makeRequestSupabaseClient | adminClient | Búsqueda pública |
| GET /products/:id | makeRequestSupabaseClient | adminClient | Detalle público |
| DELETE /products/:id/images | makeRequestSupabaseClient | adminClient | Admin pero necesita tenant correcto |
| GET /social-links | makeRequestSupabaseClient | adminClient | Público |
| POST /mercadopago/* (5) | makeRequestSupabaseClient | adminClient | Pagos deben operar sobre tenant visitado |
| POST /payments/checkout (2) | makeRequestSupabaseClient | adminClient | Pagos deben operar sobre tenant visitado |
| Cart endpoints (4) | makeRequestSupabaseClient | **Sin cambio** | Correcto: datos del usuario |
| Favorites endpoints (4) | makeRequestSupabaseClient | **Sin cambio** | Correcto: datos del usuario |
| Auth middleware (1) | makeRequestSupabaseClient | **Sin cambio** | Correcto: validación JWT |

## Notas de seguridad
- `adminClient` usa `SERVICE_ROLE_KEY` (bypassea RLS) → el filtro `.eq('client_id', clientId)` es **obligatorio** en cada query
- El `clientId` proviene del `TenantContextGuard` que lo resuelve por `x-tenant-slug` header, no del JWT
- Cart y favorites mantienen JWT-scoped access para garantizar que un usuario solo vea sus propios datos

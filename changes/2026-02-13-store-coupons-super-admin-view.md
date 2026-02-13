# Cambio: Visibilidad cross-tenant de cupones de tienda en Super Admin Dashboard

- **Autor:** agente-copilot
- **Fecha:** 2026-02-13
- **Rama:** feature/automatic-multiclient-onboarding (API + Admin)

## Archivos modificados

### API (templatetwobe)
- `src/store-coupons/admin-store-coupons.controller.ts` — **NUEVO** — Controlador para `GET /admin/store-coupons` y `GET /admin/store-coupons/stats`
- `src/store-coupons/store-coupons.service.ts` — Métodos `listCrossTenant()` y `crossTenantStats()`
- `src/store-coupons/store-coupons.module.ts` — Registro del nuevo controlador + imports DbModule/JwtModule
- `src/plans/plans-admin.controller.ts` — Mejora de error handling (HTTP exceptions)

### Admin (novavision)
- `src/pages/AdminDashboard/StoreCouponsView.jsx` — **NUEVO** — Vista cross-tenant de cupones de tienda
- `src/pages/AdminDashboard/index.jsx` — Nuevo nav item "Cupones de Tienda" en categoría billing (superOnly)
- `src/App.jsx` — Ruta `/dashboard/store-coupons`

## Resumen

El Super Admin Dashboard (apps/admin) ahora incluye una sección "Cupones de Tienda" que permite a los super admins ver todos los cupones creados por cada tienda multitenant, sin necesidad de acceder a cada una individualmente.

### Endpoint API
- `GET /admin/store-coupons?page=0&pageSize=25&clientId=&status=&search=` — Lista paginada con filtros
- `GET /admin/store-coupons/stats` — Métricas rápidas (total, activos, archivados, tenants con cupones, redenciones)
- Protegido por `SuperAdminGuard` + `@AllowNoTenant()`

### Vista Admin
- Stats bar con 5 métricas
- Tabla con columnas: Tienda, Código, Tipo, Valor, Usos, Vigencia, Estado, Target
- Filtros por estado, tienda (dropdown) y búsqueda por código
- Paginación
- Dark theme (Slate palette) consistente con el resto del dashboard

## Por qué

El usuario reportó que en el super admin dashboard solo veía cupones de suscripción (tabla `coupons` en Admin DB), pero no los cupones de tienda (`store_coupons` en Backend/Multicliente DB). Se necesitaba visibilidad cross-tenant para monitoreo y supervisión.

## Cómo probar

1. Levantar API: `cd apps/api && npm run start:dev`
2. Levantar Admin: `cd apps/admin && npm run dev`
3. Acceder como super admin a `/dashboard`
4. En la categoría "Facturación y Planes", buscar "Cupones de Tienda"
5. Verificar que se cargan las estadísticas y la tabla con cupones de todas las tiendas
6. Probar filtros por estado, tienda y búsqueda por código

### cURL de prueba
```bash
curl -H "Authorization: Bearer <JWT>" \
     -H "x-internal-key: rol-admin:novavision_39628997_2025" \
     https://novavision-production.up.railway.app/admin/store-coupons?page=0&pageSize=10

curl -H "Authorization: Bearer <JWT>" \
     -H "x-internal-key: rol-admin:novavision_39628997_2025" \
     https://novavision-production.up.railway.app/admin/store-coupons/stats
```

## Notas de seguridad

- Endpoint protegido por `SuperAdminGuard` (valida email en tabla `super_admins` + `INTERNAL_ACCESS_KEY`)
- Vista admin marcada como `superOnly: true` (no visible para admins normales)
- Queries usan service_role (bypass RLS) — esto es esperado para operaciones cross-tenant de super admin
- Solo lectura (no hay endpoints de escritura cross-tenant)

## Builds validados

- API: lint ✓ (0 errors), typecheck ✓, build ✓
- Admin: lint ✓, typecheck ✓, build ✓

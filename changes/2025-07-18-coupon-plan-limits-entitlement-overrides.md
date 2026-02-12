# Cambio: Límites de cupones por plan + entitlement overrides por cliente

- **Autor:** agente-copilot
- **Fecha:** 2025-07-18
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` (commit `3dbb878`)
  - Admin: `feature/automatic-multiclient-onboarding` (commit `76e44a2`)
  - Web: `feature/multitenant-storefront` (commit `56a8bc8`)

---

## Archivos modificados

### API (templatetwobe)
- `migrations/backend/BACKEND_044_coupon_limits.sql` — nueva migración
- `src/plans/plans.service.ts` — entitlements + usage + create_coupon validation + override merge
- `src/plans/plans-admin.controller.ts` — DTO + admin endpoints entitlements
- `src/store-coupons/store-coupons.controller.ts` — PlanLimitsGuard + PlanAction

### Admin (novavision)
- `src/pages/ClientDetails/hooks/useClientEntitlementOverrides.js` — nuevo hook
- `src/pages/ClientDetails/index.jsx` — sección "Límites del plan" con overrides

### Web (templatetwo)
- `src/components/admin/PlanLimitBanner/index.jsx` — nuevo componente reutilizable
- `src/components/admin/CouponDashboard/index.jsx` — banner de uso, botón deshabilitado, manejo 403

---

## Resumen del cambio

### 1. Límites de cupones activos por plan
- `coupons_active_limit` agregado a la interfaz `Entitlements`
- Valores configurados en Admin DB: starter=0 (gated), growth=10, enterprise=0 (ilimitado)
- `PlanLimitsGuard` + `@PlanAction('create_coupon')` en `StoreCouponsController.create()`

### 2. Contador automático en DB
- Migración BACKEND_044: columna `active_coupons_count` en `client_usage`
- Trigger `trg_coupons_usage` en `store_coupons` (INSERT/UPDATE OF is_active,archived_at/DELETE)
- Función `fn_update_coupons_usage()` cuenta cupones donde `is_active = true AND archived_at IS NULL`

### 3. Entitlement overrides por cliente
- Columna `entitlement_overrides` JSONB en `clients` (ya existía de BACKEND_043)
- `getClientEntitlements()` ahora mergea overrides sobre defaults del plan
- Endpoints admin: `GET/PATCH /admin/plans/clients/:id/entitlements`
- Whitelist de keys: products_limit, images_per_product, banners_active_limit, coupons_active_limit, storage_gb_quota, egress_gb_quota, max_monthly_orders

### 4. Admin UI
- Hook `useClientEntitlementOverrides` para gestionar overrides
- Sección en ClientDetails con inputs numéricos por campo, indicador de override, botón "limpiar"

### 5. Web Storefront (multitenant)
- `PlanLimitBanner`: barra de progreso con colores por umbral (info/warning/error)
- CouponDashboard: banner de uso de cupones, botón "Crear cupón" deshabilitado al llegar al límite
- Manejo de 403 `Plan Limit Exceeded` en create → toast con sugerencia de upgrade
- Manejo de 403 `FEATURE_GATED` en fetch → toast "cupones no disponibles en tu plan"

---

## Por qué se hizo

Para completar el sistema de gating de cupones:
1. Los planes controlan cuántos cupones activos puede tener cada tienda
2. Super admins pueden hacer override individual por cliente
3. La UI del storefront muestra el estado claramente y previene acciones bloqueadas
4. Los errores 403 del backend se manejan gracefully en lugar de mostrar errores genéricos

---

## Cómo probar

### Backend
```bash
cd apps/api && npm run start:dev
# Crear cupón como tienda growth (debería funcionar hasta 10)
# Intentar crear el #11 → 403 Plan Limit Exceeded
# Como super_admin, hacer override: PATCH /admin/plans/clients/:id/entitlements { key: 'coupons_active_limit', value: 20 }
# Ahora puede crear hasta 20
```

### Admin
```bash
cd apps/admin && npm run dev
# Ir a ClientDetails de cualquier cliente
# Sección "Límites del plan" muestra campos con defaults del plan
# Cambiar valor → se guarda automáticamente → indicador "override" aparece
# Click "limpiar" → vuelve al default del plan
```

### Web Storefront
```bash
cd apps/web && npm run dev
# Login como admin de tienda growth
# Ir a CouponDashboard → ver banner "X / 10 cupones activos"
# Al llegar a 10 → botón "Crear cupón" grisado
# Como tienda starter (sin feature) → toast "cupones no disponibles en tu plan"
```

---

## Migración ejecutada

BACKEND_044 ejecutada en backend DB (`ulndkhijxtxvpmbbfrgp`):
- ALTER TABLE client_usage ADD active_coupons_count ✅
- Backfill UPDATE ✅ (0 rows, no existing coupons)
- CREATE FUNCTION fn_update_coupons_usage() ✅
- CREATE TRIGGER trg_coupons_usage ✅
- entitlement_overrides ya existía de BACKEND_043 ✅

Planes configurados en Admin DB (`erbfzlsznqsmwmjugspo`):
- starter/starter_annual: coupons_active_limit = 0
- growth/growth_annual: coupons_active_limit = 10
- enterprise/enterprise_annual: coupons_active_limit = 0 (ilimitado)

---

## Notas de seguridad
- PlanLimitsGuard valida server-side antes de crear cupón (no solo UI)
- Entitlement overrides solo accesibles por super_admin via endpoints admin
- Trigger DB asegura conteo siempre consistente independiente del backend
- RLS existente cubre la nueva columna `active_coupons_count`

## Riesgos / Rollback
- **Bajo riesgo:** cambios aditivos, no rompen funcionalidad existente
- **Rollback DB:** DROP TRIGGER, DROP FUNCTION, ALTER TABLE DROP COLUMN
- **Rollback código:** revert commits en cada rama

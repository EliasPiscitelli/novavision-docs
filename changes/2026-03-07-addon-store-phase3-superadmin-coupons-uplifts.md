# Cambio: Addon Store Phase 3 - super admin, cupones scoped y uplifts recurrentes

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront

## Archivos modificados

- apps/api/migrations/admin/20260306_addon_store_purchases_and_fulfillment.sql
- apps/api/src/addons/addons.admin.controller.ts
- apps/api/src/addons/addons.controller.ts
- apps/api/src/addons/addons.module.ts
- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts
- apps/api/src/coupons/coupons.service.ts
- apps/api/src/coupons/dto/validate-coupon.dto.ts
- apps/api/src/seo-ai-billing/seo-ai-billing.module.ts
- apps/api/src/seo-ai-billing/seo-ai-purchase.service.ts
- apps/admin/src/App.jsx
- apps/admin/src/pages/AdminDashboard/index.jsx
- apps/admin/src/pages/AdminDashboard/CouponsView.jsx
- apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx
- apps/admin/src/__tests__/AddonPurchasesView.test.tsx
- apps/web/src/components/admin/AddonStoreDashboard/index.jsx

## Resumen

Se completó la fase operativa del addon store para que deje de depender de endpoints manuales. La API ahora soporta compras de addons con cupón scoped, catálogo admin para super admin, y activación de uplifts recurrentes reutilizando `account_addons` y `clients.entitlement_overrides`. En admin se agregó una vista global de compras y fulfillment, y la pantalla de cupones ahora puede crear promociones aplicables a onboarding y addon store/SEO mediante `promo_config`. En web se incorporó el envío de `coupon_code` desde el dashboard tenant y se expone el cupón aplicado en el historial.

## Por qué

La fase anterior ya tenía catálogo tenant y purchases básicas, pero faltaba operación real sobre Admin DB, una UI usable para super admin y una manera unificada de reutilizar cupones y entitlement overrides sin introducir una segunda fuente de verdad. La solución adoptada aprovecha estructuras existentes del dominio (`addon_catalog`, `account_addons`, `promo_config`, `entitlement_overrides`) para reducir complejidad y evitar desalineación entre billing y límites efectivos.

## Cómo probar

### API

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm run test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build
```

### Admin

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npx vitest run src/__tests__/AddonPurchasesView.test.tsx
```

Nota: `npm run typecheck` en admin sigue fallando por un conflicto previo de tipos React cruzados con `apps/web/src/registry/sectionComponents.tsx`, ajeno a esta tanda del addon store.

### Web

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web
npm run typecheck
npm run build
```

### Base de datos admin

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
psql "$ADMIN_DB_URL" -f migrations/admin/20260306_addon_store_purchases_and_fulfillment.sql
```

Verificar luego la existencia de:

- `public.account_addon_purchases`
- `public.account_addon_fulfillments`
- índices `idx_account_addon_purchases_account_created`, `idx_account_addon_purchases_status`, `idx_account_addon_purchases_billing_event_unique`

## Notas de seguridad

- No se agregaron credenciales nuevas ni exposición de service keys en frontend.
- Los cupones scoped se resuelven del lado servidor; el frontend sólo envía `coupon_code`.
- La activación de uplifts actualiza `account_addons` y luego sincroniza `clients.entitlement_overrides`, manteniendo una única fuente efectiva de enforcement en runtime.

## Riesgos y observaciones

- El uplift recurrente queda activado y sincronizado al aprobarse el pago, pero la renovación automática mensual todavía requiere una fase posterior si se quiere un ciclo de cobro recurrente completo.
- El `eventType` usado para el billing event del uplift quedó como `one_time_service` por las restricciones actuales del typing del billing service; la semántica de recurrencia se conserva en metadata.
- El workspace tiene otros cambios previos no relacionados en API, admin y web; este documento sólo cubre la tanda del addon store.
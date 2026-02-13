# PR3: SEO AI Billing Schema + Pricing UI

- **Autor:** agente-copilot
- **Fecha:** 2025-02-13
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding

## Archivos creados/modificados

### API (templatetwobe)
- `migrations/admin/20260213_seo_ai_billing.sql` — **(nuevo)** Migración Admin DB
  - CREATE TABLE `seo_ai_credits` (ledger de créditos con balance denormalizado)
  - INSERT 3 packs SEO AI en `addon_catalog` (site $49, 500 $149, 2000 $299)
  - Índices en `account_id + created_at DESC` y `reason`
  - RLS: service_role only
  - Función helper `seo_ai_balance(account_id)` para queries rápidas
- `src/seo-ai-billing/seo-ai-billing.module.ts` — **(nuevo)** Module NestJS
- `src/seo-ai-billing/seo-ai-billing.service.ts` — **(nuevo)** Service con:
  - `getPackCatalog()` — lista packs SEO AI del addon_catalog
  - `updatePackPrice()` — actualiza precio de un pack
  - `getBalance()` — saldo actual de créditos
  - `getCreditHistory()` — historial paginado del ledger
  - `addCredits()` — agrega movimiento (compra/consumo/ajuste manual)
- `src/seo-ai-billing/seo-ai-billing-admin.controller.ts` — **(nuevo)** Controller SuperAdmin
  - `GET /admin/seo-ai-billing/packs` — listar packs
  - `PATCH /admin/seo-ai-billing/packs/:addonKey` — actualizar precio/activo
  - `GET /admin/seo-ai-billing/credits/:accountId` — historial + saldo
  - `GET /admin/seo-ai-billing/credits/:accountId/balance` — solo saldo
  - `PATCH /admin/seo-ai-billing/credits/:accountId` — ajuste manual
- `src/app.module.ts` — registro de SeoAiBillingModule

### Admin (novavision)
- `src/pages/AdminDashboard/SeoAiPricingView.jsx` — **(nuevo)** Vista de pricing:
  - Tab "Packs & Precios": tabla con CRUD inline de precios + toggle activo/inactivo
  - Tab "Créditos por Cliente": búsqueda por slug/ID, saldo, historial, ajuste manual
- `src/pages/AdminDashboard/index.jsx` — nav item "SEO AI Pricing" (billing category, superOnly)
- `src/App.jsx` — ruta `/dashboard/seo-ai-pricing`

## Migración ejecutada

```
Admin DB: seo_ai_credits tabla + 3 packs addon_catalog + RLS + función helper
Resultado: CREATE TABLE, CREATE INDEX ×2, ALTER TABLE, CREATE POLICY, INSERT 0 3, CREATE FUNCTION
```

## Cómo probar

1. API: `npm run start:dev` → `GET /admin/seo-ai-billing/packs` (con JWT super admin + x-internal-key)
2. Admin: `npm run dev` → Dashboard → "SEO AI Pricing" (categoría Facturación y Planes)
3. Verificar que los 3 packs aparecen con precios editables
4. Buscar una cuenta por slug → verificar saldo 0 y historial vacío
5. Hacer ajuste manual (+10 créditos) → verificar que aparece en historial

## Notas de seguridad

- Endpoints protegidos por `SuperAdminGuard` + `AllowNoTenant()`
- RLS en `seo_ai_credits`: solo service_role puede leer/escribir
- El controller valida que solo se pueden modificar packs con prefijo `seo_ai_pack_`
- Los precios están en centavos ARS (e.g., 4900 = $49)

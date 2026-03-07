# Addon store phase 1 tenant catalog

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Repos afectados: API (templatetwobe), Web (templatetwo), Docs
- Ramas: `feature/automatic-multiclient-onboarding`, `feature/multitenant-storefront`, `main`

## Resumen

Se inició el desarrollo de la Fase 1 del tenant addon store con un corte mínimo y reutilizable:

1. fachada API genérica `/addons/catalog` y `/addons/purchase`;
2. delegación al flujo existente de SEO AI packs para el primer vertical productivo;
3. nueva sección `Addon Store` en el dashboard tenant.

## Archivos modificados

### Docs

- `plans/PLAN_TENANT_ADDON_STORE_PHASED_BACKLOG.md`

### API

- `src/addons/addons.module.ts`
- `src/addons/addons.service.ts`
- `src/addons/addons.controller.ts`
- `src/seo-ai-billing/seo-ai-billing.module.ts`
- `src/seo-ai-billing/seo-ai-purchase.controller.ts`
- `src/seo-ai-billing/seo-ai-purchase.service.ts`
- `src/app.module.ts`

### Web

- `src/components/admin/AddonStoreDashboard/index.jsx`
- `src/pages/AdminDashboard/index.jsx`

## Decisiones implementadas

- No se generalizó todavía el motor completo de provisión.
- La Fase 1 solo publica catálogo consumible y compra delegada a SEO AI.
- El retorno de Mercado Pago puede volver a `addonStore` o a `seoAutopilot` según el flujo invocante.
- La experiencia existente de SEO AI no se rompe; sigue operando con su endpoint actual.

## Por qué este corte

Permite empezar el desarrollo real del store sin introducir todavía migraciones de billing recurrente ni recomputación de `entitlement_overrides`. Eso queda para la fase de uplifts mensuales.
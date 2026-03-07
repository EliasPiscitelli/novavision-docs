# Cambio: Addon Store Phase 4 - smoke QA, admin typecheck y billing mensual de uplifts

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront

## Archivos modificados

- apps/admin/tsconfig.typecheck.json
- apps/admin/src/mocks/webSectionRenderer.tsx
- apps/admin/src/mocks/webThemeProvider.tsx
- apps/admin/src/mocks/webDemoData.ts
- apps/api/src/addons/addons.module.ts
- apps/api/src/addons/addon-recurring-billing.cron.ts
- apps/api/src/addons/addons.admin.controller.ts
- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts
- apps/api/migrations/admin/20260307_addon_subscription_billing_adjustments.sql
- novavision-docs/runbooks/addon-store-smoke-qa.md

## Resumen

Se completó una subfase operativa del addon store con tres objetivos: dejar un smoke QA reusable del flujo completo, destrabar el `typecheck` del admin que caía por imports cross-repo hacia `apps/web`, y agregar la primera versión real del cobro mensual de uplifts reutilizando `billing_adjustments` y el pipeline existente de auto-charge.

## Por qué

El estado previo tenía el addon store funcional a nivel de purchases y fulfillment, pero seguía faltando una forma repetible de validarlo extremo a extremo, un cierre limpio de la validación técnica del admin y un puente real entre uplifts mensuales y billing recurrente. En vez de crear un sistema paralelo, se montó el cobro mensual sobre la infraestructura ya usada por overages y comisiones.

## Qué se implementó

- `apps/admin` ahora usa shims locales sólo para `tsconfig.typecheck`, evitando que el chequeo de tipos dependa de módulos reales de `apps/web` compilados con otra versión de React.
- Se agregó el runbook `addon-store-smoke-qa.md` con pasos concretos para validar compra, historial, fulfillment, uplift y cargo mensual.
- La API ahora expone generación manual de ajustes recurrentes desde `POST /admin/addons/recurring/billing-adjustments`.
- Se agregó el cron `AddonRecurringBillingCron` para crear `billing_adjustments` mensuales de tipo `addon_subscription`.
- El método `createMonthlyRecurringAddonAdjustments()` evita duplicar el mes de alta del uplift y deja trazabilidad en `account_addons.metadata`.
- Se agregó migración para habilitar `addon_subscription` en `billing_adjustments` y asegurar unicidad por tenant/período/recurso.

## Cómo probar

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npm run typecheck
npx vitest run src/__tests__/AddonPurchasesView.test.tsx
npm run build

cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm run test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build
```

Para smoke QA funcional, seguir:

- `novavision-docs/runbooks/addon-store-smoke-qa.md`

Para habilitar el tipo nuevo en Admin DB:

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
psql "$ADMIN_DB_URL" -f migrations/admin/20260307_addon_subscription_billing_adjustments.sql
```

## Notas de seguridad

- El fix de typecheck no cambia aliases de runtime ni comportamiento de producción; sólo desacopla TypeScript en admin.
- El cargo mensual de uplifts se apoya en `billing_adjustments`, por lo que sigue el mismo pipeline ya auditado para auto-charge y deuda.
- No se agregaron secretos ni credenciales nuevas.

## Riesgos y próximos pasos

- Esta fase crea el cargo mensual del uplift, pero todavía no revoca automáticamente el addon si la deuda queda impaga; eso debe decidirse explícitamente en una fase posterior.
- La migración nueva debe aplicarse antes de usar `addon_subscription` en producción.
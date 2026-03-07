# Cambio: hardening de Step 4 preview y correcciones de addon ops

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront

## Archivos modificados

- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts
- apps/api/src/onboarding/onboarding.service.ts
- apps/admin/src/pages/AdminDashboard/index.jsx
- apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx
- apps/admin/src/__tests__/AddonPurchasesView.test.tsx
- apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx
- apps/admin/src/pages/BuilderWizard/utils/planGating.ts
- apps/web/src/pages/PreviewHost/index.tsx
- apps/web/src/preview/previewUtils.ts

## Resumen

Se corrigieron dos problemas productivos y tres brechas funcionales del Step 4 del builder.

1. El endpoint admin de uplifts recurrentes dejó de depender de columnas opcionales de `billing_adjustments` que no son necesarias para la vista y podían romper el listado con `500`.
2. El shell de `AdminDashboard` pasó a cargar `IdentityModal` en lazy para cortar un ciclo de imports que podía terminar en TDZ runtime al abrir `addon-purchases`.
3. La vista de super-admin del addon store ahora muestra también el catálogo activo, no sólo compras y recurrentes, y deja explicación explícita de qué hace cada botón operativo.
4. El Step 4 ahora recompone sus selecciones reales del wizard cuando el usuario cambia template, vuelve a una paleta estándar, elimina una paleta custom o revierte estructura. Esto evita que `minRequiredPlan` quede pegado en Growth/Enterprise por selecciones viejas.
5. El backend endurece `submitForReview` mediante `validatePlanLimits` usando también `wizard_selections` persistidas y `themeOverride`, para bloquear envíos fuera de plan aunque el front haya quedado desincronizado.
6. `PreviewHost` ahora valida origen del `postMessage`, existencia/expiración/formato del token y coherencia básica entre token y `clientSlug` antes de aceptar render.

## Por qué

- El panel de recurrentes solo muestra cantidad y períodos vencidos. Pedir columnas adicionales (`amount_usd`, `notes`) aumentaba acoplamiento innecesario con el esquema y volvía frágil el endpoint.
- El crash `Cannot access 'l' before initialization` era consistente con un ciclo de evaluación en el shell del dashboard, no con la pantalla de addons en sí. Lazy-loading del modal saca ese módulo de la ruta crítica inicial.
- En el dashboard había una brecha de producto clara: API ya exponía `/admin/addons/catalog`, pero la UI no lo consumía. Por eso el super-admin veía sólo operación histórica y no qué items componían realmente la tienda de addons.
- El bug de Step 4 no era de render sino de estado derivado: se agregaban selecciones de upgrade pero no se recalculaban al revertir decisiones. El problema real era “estado stale”, no falta de copy ni de UI.
- El backend solo validaba parte del gating. Si el front persistía una selección vieja o si se forzaba un payload fuera de plan, el submit podía avanzar más de lo que debía.
- El preview recibía mensajes de cualquier origen y no usaba el token que ya estaba en la URL. Eso dejaba un hueco innecesario para render arbitrario en el iframe.

## Cómo probar

### API

1. `cd apps/api && npm test -- --runInBand src/addons/addons.service.spec.ts`
2. `cd apps/api && npm run typecheck`
3. `cd apps/api && npm run build`

### Admin

1. `cd apps/admin && npm test -- src/__tests__/AddonPurchasesView.test.tsx`
2. `cd apps/admin && npm run lint`
3. `cd apps/admin && npm run typecheck && npm run build`

### Web

1. `cd apps/web && npm run ci:onboarding`

## Resultados verificados

- Spec de addons: verde, incluyendo caso nuevo para recurrentes sin columnas opcionales.
- Test del dashboard `AddonPurchasesView`: verde.
- API: `typecheck` y `build` verdes.
- Admin: `lint`, `typecheck` y `build` verdes.
- Web: `ci:onboarding` verde. El lint de web mantiene warnings históricos no relacionados, pero sin errores.

## Notas de seguridad

- El hardening del preview es defensivo del lado cliente. No reemplaza la validación criptográfica server-side del preview token en Store API; la complementa.
- El bloqueo de plan en backend ahora depende también del estado persistido del wizard, reduciendo el riesgo de submit inconsistentes por desincronización entre UI y API.
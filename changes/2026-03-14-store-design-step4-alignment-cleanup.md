# Cambio: limpieza inicial y alineación visual de Store Design con Step 4

- Autor: agente-copilot
- Fecha: 2026-03-14
- Rama: feature/multitenant-storefront / feature/automatic-multiclient-onboarding
- Archivos: apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx, apps/web/src/components/admin/StoreDesignSection/Step4TemplateSelector.tsx, apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx, apps/web/src/components/admin/StoreDesignSection/resolvePreviewSections.js, apps/web/src/components/admin/StoreDesignSection/index.jsx, apps/web/src/__tests__/store-design-section.test.jsx, plans/PLAN_STORE_DESIGN_STEP4_ALIGNMENT_EXECUTION.md

Resumen: se aplicó la primera limpieza técnica para reducir deriva entre Step 4 y Store Design y además se alineó la superficie visual principal de `DesignStudio` con el lenguaje de Step 4. Se alineó el `PreviewFrame` del dashboard con el contrato operativo del onboarding, se eliminó el fork huérfano de `Step4TemplateSelector`, se consolidó la fuente canónica de secciones publicadas, se movieron las reglas/constraints estructurales duplicadas a `designSystem` como fuente única, se centralizó también la evaluación de tiers sobre `planGating` y se limpió el test de Store Design para no dejar warnings evitables en el archivo tocado.

Por qué: el usuario pidió avanzar en la unificación de familiaridad UX/UI entre Step 4 y Diseño de Tienda, sin mezclar reglas de onboarding con reglas comerciales del dashboard. La limpieza inicial apunta a bajar el costo de mantenimiento y reducir riesgo de cross-config antes de tocar la persistencia y el editor principal. En esta fase también se removió una vía legacy de resolución de secciones para que el dashboard trabaje con una sola fuente canónica publicada (`/home/sections`) y fallback controlado a runtime, se dejó aplicada la misma capa visual en un worktree de `feature/onboarding-preview-stable` para no reabrir deriva entre ramas, se eliminó duplicación local de reglas estructurales dentro de `DesignStudio` para que el editor consuma `SECTION_CONSTRAINTS` y `STRUCTURE_RULES` desde el módulo compartido `designSystem`, y se terminó de sacar la comparación de planes local para usar el helper compartido de `planGating`.

Cómo probar:

```bash
cd apps/web
npx vitest run src/__tests__/store-design-section.test.jsx src/__tests__/preview-host.test.jsx src/templates/eighth/pages/HomePageLumina/index.test.jsx
npm run typecheck
```

Validación adicional de esta fase:

```bash
cd apps/web
npx vitest run src/__tests__/store-design-section.test.jsx

# worktree temporal onboarding-preview-stable usando las mismas dependencias locales
ln -sfn /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/node_modules /tmp/nv-onboarding-web/node_modules
cd /tmp/nv-onboarding-web
/Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/node_modules/.bin/tsc -p tsconfig.typecheck.json
```

Validación final luego de consolidar helpers:

```bash
cd apps/web
npx vitest run src/__tests__/store-design-section.test.jsx --reporter=verbose
npm run typecheck

cd /tmp/nv-onboarding-web
/Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/node_modules/.bin/tsc -p tsconfig.typecheck.json
```

Higiene final de archivos tocados:

```bash
cd apps/web
npm run lint -- src/__tests__/store-design-section.test.jsx src/components/admin/StoreDesignSection/DesignStudio.jsx
```

Notas de seguridad: sin impacto sobre credenciales o políticas. El cambio es de arquitectura frontend y mantenimiento de preview.
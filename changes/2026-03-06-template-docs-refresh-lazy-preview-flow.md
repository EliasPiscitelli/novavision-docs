# Cambio: actualizacion de documentacion de templates, preview y render lazy

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama: docs / cambios sin commit
- Archivos:
  - `architecture/add_templates/ADDING_TEMPLATES_AND_COMPONENTS.md`
  - `architecture/add_templates/TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md`

## Resumen

Se actualizo la documentacion tecnica para reflejar la arquitectura real vigente de templates en NovaVision:

- `templatesMap.ts` con lazy loading
- diferencia entre preview del builder y tienda publicada
- uso de `PreviewHost` por `postMessage`
- registro runtime de secciones en `sectionComponents.tsx`
- re-exports por template en `sectionComponentTemplates/*`
- fallback server-side de `client_home_settings` -> `clients.template_id` -> `template_1`

## Por que

La guia anterior seguia describiendo un modelo mas viejo:

- asumia registros no lazy
- mezclaba aliases legacy con claves canonicas como si ambas fueran obligatorias en `templatesMap.ts`
- no explicaba la cadena completa builder -> preview -> publish -> render
- no mencionaba que agregar un template nuevo con secciones dinamicas requiere registrar `componentKey` en el runtime del web

## Como probar

1. Revisar `architecture/add_templates/ADDING_TEMPLATES_AND_COMPONENTS.md` y verificar que el flujo coincida con:
   - `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
   - `apps/web/src/pages/PreviewHost/index.tsx`
   - `apps/web/src/routes/HomeRouter.jsx`
   - `apps/web/src/registry/templatesMap.ts`
   - `apps/web/src/registry/sectionComponents.tsx`
2. Revisar `architecture/add_templates/TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md` y confirmar que la seccion 14 ya no describe solo el registro clasico del template sino tambien el runtime de secciones dinamicas.

## Riesgos

- La documentacion ahora esta alineada con el codigo actual, pero si cambia el flujo de onboarding o preview en el futuro habra que volver a sincronizar esta guia.
- No se hicieron cambios de codigo de aplicacion en esta actualizacion, solo documentacion.

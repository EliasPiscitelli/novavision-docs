# Plan: Ejecución de Alineación Step 4 ↔ Store Design

- Fecha: 2026-03-14
- Autor: GitHub Copilot
- Repos: novavision, templatetwo, novavision-docs
- Estado: auditoría completada, limpieza inicial aplicada, fases siguientes definidas

## Objetivo

Mantener la misma familiaridad de UX/UI y utilidad de Step 4 en el editor de Diseño de Tienda, sin mezclar contextos de persistencia ni reglas comerciales. La meta no es fusionar onboarding y dashboard en un único flujo, sino separar responsabilidades y unificar contrato visual/técnico.

## Decisión arquitectónica

### Se mantiene separado

- `Step4TemplateSelector` del onboarding: editor de sesión de onboarding, persistencia en `updatePreferences` + `updateProgress`.
- `DesignStudio` del dashboard: editor post-provisión con reglas de `addon store`, créditos y guardado incremental sobre identidad/home sections.

### Se unifica

- Contrato de preview (`PreviewFrame` + `PreviewHost` + payload `nv:preview:render`)
- Reglas puras de estructura (`constraints`, `validateInsert`, compatibilidad)
- Resolución visual base y comportamiento UX de edición
- Criterio de fuente de verdad para la estructura publicada

## Hallazgos que gobiernan la implementación

1. El onboarding es más cohesivo: maneja una sola fuente `designConfig`.
2. El dashboard mezcla `structureSections`, `settings.sections` y `homeData.config.sections`, lo que abre cross-config.
3. El dashboard mantenía un fork huérfano de `Step4TemplateSelector` en Web, sin uso productivo.
4. El dashboard tenía un `PreviewFrame` propio, separado del contrato ya consolidado en onboarding.

## Ejecución aprobada

### Fase 1. Limpieza mínima ya aplicada

- Alinear `apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx` con el contrato operativo del preview usado en onboarding.
- Eliminar el fork no usado `apps/web/src/components/admin/StoreDesignSection/Step4TemplateSelector.tsx`.

### Fase 2. Alineación funcional sin fusionar flujos

- Mantener `DesignStudio` como shell del dashboard.
- Reemplazar la resolución de secciones publicadas por una sola fuente prioritaria:
  1. draft local
  2. estructura publicada persistida
  3. preset del template
- Evitar mezclar en runtime `settings.sections` y `homeData.config.sections` si ya existe estructura persistida canónica.

### Fase 3. UX/UI familiar a Step 4

- Mantener layout, copy y affordances de Step 4 como referencia visual.
- Conservar en dashboard los elementos comerciales propios:
  - créditos
  - addon store
  - warnings de compatibilidad
  - CTA de compra/upgrade

### Fase 4. Núcleo compartido por contrato

- Consolidar como piezas puras equivalentes:
  - `designSystem`
  - `planGating`
  - helpers de compatibilidad
  - resolución de preview
- Si no se puede compartir por repo, mantener copias espejo controladas y mínimas, no forks divergentes.

## Archivos que conviene mantener alineados entre ramas Web

- `src/pages/PreviewHost/index.tsx`
- `src/registry/templatesMap.ts`
- `src/components/admin/StoreDesignSection/PreviewFrame.jsx`
- `src/templates/eighth/pages/HomePageLumina/index.jsx`

## Criterio operativo

- Misma UX/UI que Step 4: sí.
- Mismo flujo de persistencia que Step 4: no.
- Mismo contrato técnico de preview y estructura: sí.
- Misma lógica comercial del dashboard: sí.

## Siguiente implementación recomendada

1. Simplificar `DesignStudio` para que la estructura publicada salga de una sola fuente canónica.
2. Extraer/normalizar utilidades puras duplicadas entre onboarding y dashboard.
3. Auditar y bajar los fixes de preview/template desde `feature/multitenant-storefront` hacia `feature/onboarding-preview-stable` en los archivos listados.
# Cambio: Dev Portal — Section Builder (PR-1 a PR-8)

- **Autor:** agente-copilot
- **Fecha:** 2025-07-14
- **Rama:** develop (merges de 8 feature branches)
- **Archivos nuevos:**
  - `src/__dev/pages/SectionBuilderPage/index.jsx`
  - `src/__dev/pages/SectionBuilderPage/LayoutCanvas.jsx`
  - `src/__dev/components/ClientSelector.jsx`
  - `src/__dev/components/SectionFormRenderer.jsx`
  - `src/__dev/components/SectionPreview.jsx`
  - `src/__dev/components/SuggestionChips.jsx`
  - `src/__dev/hooks/useTenantData.ts`
  - `src/__dev/hooks/useAiSuggestions.ts`
  - `src/__dev/schemas/faqSchema.ts`
  - `src/__dev/schemas/bannerSchema.ts`
  - `src/__dev/schemas/carouselSchema.ts`
  - `src/__dev/schemas/heroSchema.ts`
  - `src/__dev/schemas/testimonialsSchema.ts`
  - `src/__dev/schemas/index.ts`
  - `src/__dev/schemas/__tests__/schemas.test.ts`
- **Archivos modificados:**
  - `src/__dev/DevPortalRouter.jsx` — ruta `/__dev/sections`
  - `src/__dev/components/DevPortalLayout.jsx` — 8° nav item + shortcuts
  - `src/__dev/context/DevPortalContext.tsx` — SectionBuilder state slice
  - `src/__dev/pages/IndexPage/index.jsx` — card del Section Builder

## Resumen

Se creó el **Constructor de Secciones** para el Dev Portal, una herramienta completa para
diseñar secciones de página (FAQ, banners, carouseles, hero, testimonios) con datos reales
del tenant, validación Zod y preview en tiempo real.

### Features principales:
1. **Wizard de 3 pasos:** Conectar tenant → Elegir tipo → Editar con preview
2. **Schemas Zod (5 tipos)** con validación contract-first y `safeParse()`
3. **ClientSelector** que obtiene categorías reales via API con `x-tenant-slug`
4. **Formularios dinámicos** por tipo con validación inline en real-time
5. **AI Autocomplete** (sugerencias locales por tipo de sección y campo)
6. **Live Preview CSS** con controles de viewport, tema y zoom
7. **Layout Canvas** con drag & drop nativo HTML5, full-page preview y export JSON
8. **28 tests unitarios** para los schemas Zod

## Por qué

El Dev Portal necesitaba una herramienta para que desarrolladores externos puedan construir
y previsualizar secciones de página sin acceso al código fuente del storefront. El Section
Builder permite iterar rápidamente sobre el contenido y layout de las páginas.

## Decisiones técnicas

- **Sin librerías de DnD** — HTML5 Drag and Drop API nativa para evitar dependencias
- **Mockups CSS puro** — Los previews no importan componentes del storefront (bundle size)
- **Zod v4.3.6** — Ya instalada en el proyecto, usada para contract-first validation
- **localStorage** — Persistencia offline de todo el estado del builder
- **`x-tenant-slug`** header — Siguiendo el patrón del storefront (no `x-client-id`)

## Cómo probar

1. `cd apps/web && npm run dev`
2. Navegar a `http://localhost:5173/__dev/sections`
3. Step 1: Ingresar slug de un tenant existente (ej: `novavision`) → Conectar
4. Step 2: Seleccionar tipo de sección (ej: FAQ)
5. Step 3: Completar formulario → verificar preview a la derecha
6. Guardar → Ir a tab "Layout" → verificar sección en la lista
7. Drag & drop para reordenar → Export JSON

Tests de schemas:
```bash
cd apps/web && npx vitest run src/__dev/schemas/__tests__/schemas.test.ts
```

## Notas de seguridad

- Solo toca `src/__dev/` — sin impacto en producción (código lazy-loaded en dev only)
- No se exponen SERVICE_ROLE_KEY ni tokens de servicio
- Fetch con timeout de 8 segundos y fallback offline
- Validación Zod obligatoria antes de persistir cualquier dato

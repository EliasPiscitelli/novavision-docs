# Fix: 5 Bugs del Admin Dashboard — DesignStudio

**Fecha:** 2026-03-20
**Módulo:** Web — Admin Dashboard — Store Design Section
**Rama:** develop
**Cherry-pick:** `feature/multitenant-storefront`, `feature/onboarding-preview-stable`

## Archivos modificados

- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- `apps/web/src/components/admin/StoreDesignSection/CssOverrideEditor.jsx`

## Cambios

### Bug 1+2 — Preview no refleja cambios de template ni palette (CRÍTICO)

- **Root cause:** `previewSections` useMemo priorizaba `publishedSections` (siempre presente en tenants publicados) sobre el template seleccionado. `paletteVars` priorizaba la paleta guardada sobre la seleccionada.
- **Fix:** Reescrito `previewSections` para considerar `activeTab` y comparar `selectedTemplate` vs `currentTemplate`. Invertida la prioridad de `paletteVars` para que la paleta seleccionada tenga precedencia.
- Agregada variable derivada `isTemplatePreviewMode`.

### Bug 3 — Modal de Props siempre abierto

- **Root cause:** Auto-selección incondicional de la primera sección + fallback a `sections[0]` hacía que el drawer estuviera siempre abierto.
- **Fix:** Auto-select condicionado al tab `customize`. Removido fallback a `sections[0]`. Agregado `useEffect` para limpiar selección al cambiar a tab `presets`.

### Bug 4 — Template cards inconsistentes con onboarding

- **Root cause:** `TEMPLATE_PERSONALITY` asignaba labels genéricos que no correspondían al API. Thumbnails eran placeholders sin representación visual real.
- **Fix:** Eliminados `TEMPLATE_PERSONALITY`, `<img>` de thumbnail y bloque de personality. Cards ahora usan `t.name` + `t.description` del API, unificadas con onboarding.

### Bug 5 — CSS textarea UX

- **Fix:** Agregados `maxHeight: 400` y `overflowY: 'auto'` al textarea. Mejorado hint de scope mencionando `.nv-store` y ejemplos de variables CSS. El botón "Guardar CSS" ya tenía `disabled={saving || validCount === 0}`.

### Fix 6 — Templates cortados (solo 6 visibles) + preview height inconsistente

- **Root cause:** `ds-main-grid` usaba `gridTemplateRows` implícito (`auto`), haciendo que la fila se expandiera al tamaño del contenido. Combinado con `overflow: hidden` en el padre, los templates 7 y 8 (Vanguard y Lumina) quedaban clipeados. Además, `col-preview` tenía `height: 100vh` forzando el viewport completo en vez de respetar la cadena de alturas del grid.
- **Fix:**
  - Agregado `gridTemplateRows: 'minmax(0, 1fr)'` a `ds-main-grid` para constrainar la fila al alto disponible.
  - Agregado `height: '100%'` y `minHeight: 0` a `ds-main-panel` para habilitar scroll interno.
  - Cambiado `col-preview` de `height: '100vh', overflow: 'auto', position: 'sticky'` a `height: '100%', minHeight: 0, position: 'relative'` — alineado con el comportamiento del admin Step4 onboarding.

## Verificación

- `npm run typecheck` ✓
- `npm run build` ✓

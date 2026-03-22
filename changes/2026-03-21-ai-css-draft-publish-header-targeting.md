# AI CSS Draft/Publish + Header Targeting

**Fecha:** 2026-03-21
**Commit:** `afb9642`
**Ramas:** develop, feature/multitenant-storefront, feature/onboarding-preview-stable
**Módulo:** Web (DesignStudio / PreviewHost)

## Resumen

Implementación de flujo draft/publish para CSS generado por IA en DesignStudio, eliminación de re-renders innecesarios, y soporte para targeting de header via `data-nv-slot`.

## Cambios

### Fase 1 — Preview de CSS draft sin guardar en DB

- **PreviewHost** (`index.tsx`): Nuevo handler `nv:preview:inject-css` que inyecta/remueve un `<style id="nv-draft-css">` en el head del iframe. Tipo `Incoming` actualizado como union discriminada.
- **PreviewFrame** (`PreviewFrame.jsx`): Convertido a `forwardRef` con `useImperativeHandle` que expone `sendCss(cssString)` — envía `postMessage` ligero al iframe.
- **AiDesignTab** (`AiDesignTab.jsx`):
  - `onCssGenerated` reemplazado por `onPreviewCss(css: string)` — inyecta CSS en iframe sin persistir.
  - Helper `buildPreviewCss(properties, targetSlot)` scoped a `.nv-preview-scope`.
  - "Aplicar" → "Publicar": solo persiste en DB al confirmar.
  - "Descartar": limpia CSS del iframe enviando string vacío.
  - Sugerencias ahora son preview-first: click previsualiza, botón "Publicar" persiste.
  - Badge "draft" visible cuando hay CSS sin publicar.
- **DesignStudio** (`DesignStudio.jsx`): Nuevo `previewRef` pasado a `<PreviewFrame ref={previewRef}>`, `onPreviewCss` callback conecta AiDesignTab → PreviewFrame.

### Fase 2 — Header targeting

- **DynamicHeader** (`DynamicHeader.jsx`): Agregado `data-nv-slot="header"` al wrapper div.
- **AiDesignTab**: Nota informativa cuando el slot seleccionado (header/footer) no se renderiza en el iframe preview.

### Fase 3 — Eliminación de re-renders

- `onCssGenerated` eliminado — ya no modifica `previewRequestIdRef`, no recalcula `previewPayload`, no re-envía seed/sections al iframe.
- `onRefreshOverrides` solo se llama al publicar (POST exitoso a `/design-overrides`).

## Tests

- Tests de `ai-design-tab.test.jsx` actualizados para nuevo flujo: `onPreviewCss`, "Publicar"/"Descartar", sugerencias preview-first.
- 375 tests passed, 8 failed (pre-existentes en store-design-section).

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/pages/PreviewHost/index.tsx` | Handler `nv:preview:inject-css` |
| `src/components/admin/StoreDesignSection/PreviewFrame.jsx` | `forwardRef` + `sendCss()` |
| `src/components/admin/StoreDesignSection/AiDesignTab.jsx` | Draft/publish flow |
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | `previewRef` pipe |
| `src/components/DynamicHeader.jsx` | `data-nv-slot="header"` |
| `src/__tests__/ai-design-tab.test.jsx` | Tests actualizados |

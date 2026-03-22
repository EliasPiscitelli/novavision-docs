# Design Studio — Fases A, B y C completadas

**Fecha:** 2026-03-21
**Repos:** web, admin, api
**Ramas:** web/develop + cherry-picks, admin+api/feature/automatic-multiclient-onboarding

## Fase A — Fix fonts en templates 1, 2, 5

Templates 1 (first), 2 (second) y 5 (fifth) hardcodeaban `font-family` ignorando `var(--nv-font)`. Se reemplazaron 5 líneas de CSS para usar la variable con fallback al valor original.

**Archivos:** `templates/{first,second,fifth}/**/style.jsx`

## Fase B — FontSelector en onboarding wizard (admin)

Nuevo selector de tipografías en Step4 del wizard de onboarding (admin).

- `fontCatalog.ts` — catálogo de 10 fonts con gating por plan
- `FontSelector.tsx` — componente TypeScript con grid por categoría y badges de plan
- `Step4TemplateSelector.tsx` — integración del FontSelector con PaletteSelector existente
- `WizardContext.tsx` — nuevo campo `fontKey` en estado del wizard
- `api.ts` — envío de `fontKey` a la API

## Fase C — Tab "Editar con IA" en DesignStudio

Nueva pestaña en DesignStudio con 3 modos de edición CSS asistida por IA.

### Frontend (web)
- `AiDesignTab.jsx` — componente con Modo A (template completo), Modo B (por sección con `data-nv-slot`), Modo C (sugerencias)
- `DesignStudio.jsx` — integración de tab con badge "Nuevo"
- `SectionRenderer.tsx` — atributo `data-nv-slot` para CSS scoping per-section
- `CssOverrideEditor.jsx` — eliminación de UI de IA duplicada (ahora solo editor manual)
- `step4TourConfig.ts` — pasos del tour para la nueva tab
- `addons.js` — extensión de API cliente con `targetSlot` y endpoint de sugerencias

### Backend (api)
- `ai-generation.controller.ts` — `targetSlot`/`targetSectionName` + endpoint `/ai-suggestions`
- `ai-generation.service.ts` — soporte para slot y generación de sugerencias
- `css-generate.ts` — prompts extendidos para CSS scoped y sugerencias
- `design-overrides.controller.ts` — parámetro `targetSlot`
- `design-overrides.service.ts` — wrapping CSS con scope a `data-nv-slot`
- `css.validator.ts` — función `scopeCssToSlot()`
- `onboarding.controller.ts` + `onboarding.service.ts` — persistencia de `fontKey`
- Migración: `custom_css`, `ai_generated_css` en CHECK constraint de `override_type`

## Mejoras de UX

- **Debounce 300ms** en PreviewFrame para evitar recargas constantes al cambiar tema/font/template
- **React.memo** en MemoizedSections para evitar re-renders innecesarios
- **Transición CSS** suave en altura del iframe

## Tests

43 tests nuevos (4 archivos):
- `ai-design-tab.test.jsx` (16 tests)
- `css-override-editor.test.jsx` (8 tests)
- `preview-frame-debounce.test.jsx` (6 tests)
- `step4-tour-config.test.ts` (9 tests)

Todos pasan. Suite total: 373/381 (8 fallos pre-existentes no relacionados).

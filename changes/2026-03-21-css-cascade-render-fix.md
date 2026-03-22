# CSS Variable Cascading + Render Cascade Fix + Discard Confirmation

**Fecha:** 2026-03-21
**Commits:** `f4dc496` (web), `8a15f96` (api)
**Ramas:** develop, feature/multitenant-storefront, feature/onboarding-preview-stable, feature/automatic-multiclient-onboarding
**Módulo:** Web (DesignStudio, ToastProvider, useNotifications) + API (design-overrides, css.validator)

## Resumen

Tres fixes críticos para el flujo de CSS generado por IA:

1. **CSS no cascadeaba al header**: Las propiedades CSS directas (`background-color`, `color`) no afectaban styled-components internos del header que usan `var(--nv-bg)`, `var(--nv-text)`. Ahora se emiten variables `--nv-*` junto con las propiedades directas.

2. **Re-fetch masivo (~45 GETs por generación)**: `showToast` en ToastProvider no estaba memoizado, causando que cada toast disparara un re-render en DesignStudio que re-ejecutaba el useEffect de data loading (15+ endpoints x3 repeticiones).

3. **Sin confirmación al descartar CSS draft**: El usuario podía perder CSS generado sin aviso al cambiar de modo o descartar.

## Causa raíz del render cascade

```
AI genera CSS → showToast() → setToasts() en ToastProvider
→ ToastProvider re-render → showToast nueva referencia (no useCallback)
→ value={{ showToast }} nuevo objeto cada render
→ useContext(ToastContext) detecta cambio → DesignStudio re-render
→ useEffect([showToast, retryKey]) ve nuevo showToast → RE-EJECUTA DATA LOADING
→ 15+ GETs (settings, templates, palettes, home/data, sections, registry, etc.)
→ 8s después toast se auto-remueve → setToasts() → CICLO SE REPITE
```

## Cambios

### Web — Frontend

| Archivo | Cambio |
|---------|--------|
| `src/context/ToastProvider.jsx` | `showToast` → `useCallback`, `removeToast` → `useCallback`, `value` → `useMemo` |
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | `showToast` → `showToastRef`, removido de deps del `useEffect` principal |
| `src/hooks/useNotifications.js` | `showToast` → `showToastRef`, removido de deps de `fetchUnreadCount` |
| `src/components/admin/StoreDesignSection/AiDesignTab.jsx` | `buildNvVarMappings()` + `buildPreviewCss()` emite `--nv-*` vars; `handleDiscard`/`handleModeChange` con `window.confirm` |
| `src/__tests__/ai-design-tab.test.jsx` | Mock de `window.confirm` en setup |

### API — Backend

| Archivo | Cambio |
|---------|--------|
| `src/common/validators/css.validator.ts` | `--nv-*` props pasan allowlist; nueva `buildNvVarMappings()` exportada |
| `src/common/validators/index.ts` | Export de `buildNvVarMappings` |
| `src/design-overrides/design-overrides.service.ts` | `createCustomCss`/`updateCustomCss` incluyen `--nv-*` mappings; `getActiveCss` fallback usa `scopeCssToSlot()` cuando `target_slot` presente |

### Mapeo CSS → Variables

| Propiedad CSS | Variable `--nv-*` |
|--------------|-------------------|
| `background-color` | `--nv-bg` |
| `background` (sin gradient/url) | `--nv-bg` |
| `color` | `--nv-text` |
| `border-color` | `--nv-border` |
| `box-shadow` | `--nv-shadow` |
| `font-family` | `--nv-font` |

## Tests

- 19 tests en `ai-design-tab.test.jsx` pasando
- 378 tests totales pasando, 8 fallidos pre-existentes en `store-design-section.test.jsx`
- Build web y API exitosos
- Lint, typecheck OK en ambos repos

## Ejemplo de CSS generado

```css
/* ANTES (no cascadeaba a styled-components) */
.nv-store-{clientId} [data-nv-slot="header"] {
  background-color: #1a1a2e;
  color: #fff;
}

/* DESPUÉS (cascadea via var() inheritance) */
.nv-store-{clientId} [data-nv-slot="header"] {
  background-color: #1a1a2e;
  color: #fff;
  --nv-bg: #1a1a2e;
  --nv-text: #fff;
}
```

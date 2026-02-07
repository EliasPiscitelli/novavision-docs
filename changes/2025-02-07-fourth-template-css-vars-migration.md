# Cambio: Migración completa fourth template a CSS vars + fix preview body background

- **Autor:** agente-copilot
- **Fecha:** 2025-02-07
- **Rama:** feature/automatic-multiclient-onboarding (web)
- **Commit:** `0cee4d5` + cherry-picks a develop (`7ae110f`), multitenant (`55b3e27`), onboarding (`86dbc95`)

## Archivos Modificados

### Web (templatetwo)
- `src/pages/PreviewHost/index.tsx` — Inyección `:root` CSS vars + body background
- `src/templates/fourth/components/SortBar.jsx` — 14 refs migradas
- `src/templates/fourth/components/UI/Button.jsx` — 8 refs migradas
- `src/templates/fourth/components/FiltersPanel.jsx` — 10 refs migradas
- `src/templates/fourth/components/UI/Skeleton.jsx` — 1 ref migrada

## Resumen del Cambio

### Problema
El preview del template FOURTH con palette `starter_elegant` (dark) mostraba fondos blancos entre secciones y en componentes. Causa raíz:
1. `body` y `html` no tenían `background-color` en la ruta de preview (no se renderiza `GlobalStyle`)
2. Las CSS vars (`--nv-bg`, `--nv-surface`, etc.) solo se definían en el inner `div.nv-preview-scope`, fuera del alcance de `body`
3. Múltiples componentes aún usaban `theme.colors.*` de styled-components en vez de CSS vars

### Solución
1. **PreviewHost**: Se importa `paletteToCssVars` y se genera un bloque `:root { ... }` dinámico en el `<style>` tag, propagando las 27 CSS vars de la palette a todo el documento
2. **PreviewHost**: `body` recibe `background-color: var(--nv-bg, #111827)` — ahora resuelve contra el `:root` real
3. **PreviewHost**: Outer wrapper `div.nv-preview-scope` también recibe `backgroundColor: "var(--nv-bg)"`
4. **Componentes**: Se eliminaron TODAS las referencias directas a `theme.colors.*` en SortBar (14), Button (8), FiltersPanel (10), Skeleton (1) reemplazándolas por CSS vars

### Estado final
- **0 referencias directas** a `theme.colors.*` en todo el template fourth
- **1 referencia indirecta** en Header.jsx (`useTheme().colors.surface` para detección dark/light del logo) — tiene safe-check y no se rompe

## Cómo Probar
1. Levantar admin (`npm run dev` en terminal admin)
2. Levantar web (`npm run dev` en terminal web)
3. Ir a Builder → Template FOURTH + Palette `starter_elegant`
4. Verificar que:
   - No hay fondos blancos entre secciones
   - El body completo tiene fondo dark (`#111827`)
   - SortBar, botones, filtros, footer, servicios — todos usan colores dark
   - Los badges de producto mantienen colores correctos

## Notas de Seguridad
- Sin impacto en seguridad
- Sin cambios en DB ni endpoints
- Solo cambios de UI en el preview rendering pipeline

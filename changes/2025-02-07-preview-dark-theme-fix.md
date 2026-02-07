# Fix: Preview dark theme inconsistency + missing section data

- **Autor:** agente-copilot
- **Fecha:** 2025-02-07
- **Rama:** feature/automatic-multiclient-onboarding (cherry-picked a develop, multitenant, onboarding)

## Archivos modificados

### Web (templatetwo)
- `src/theme/palettes.ts` — Rewrite de `paletteToCssVars()`
- `src/theme/tokens.js` — Fix definición `starter_elegant`
- `src/pages/PreviewHost/index.tsx` — Pass data prop a SectionRenderer

### API (templatetwobe)
- `packages/nv-theme/src/tokens.js` — Fix definición `starter_elegant`

## Resumen de cambios

### Bug 1: CSS vars incompletas en preview (paletteToCssVars)
`paletteToCssVars()` solo producía **13 CSS vars** de las 27 del contrato. Los tokens faltantes (ej: `--nv-navbar-bg`, `--nv-shadow`, `--nv-muted`, `--nv-footer-bg`, etc.) no se seteaban en el scope del preview, por lo que caían al `:root` donde ThemeProvider inyectaba valores incorrectos.

**Fix:** Reescritura completa de `paletteToCssVars()`:
- 13 → **30 CSS vars** (27 tokens canónicos + 3 aliases de backward compat)
- Agrega helpers: `isDarkHex()` (detección dark por luminancia), `adjustHex()` (ajuste de brillo), `rgbaFrom()` (hex→rgba)
- Auto-detección dark/light desde luminancia del `bg`
- Aliases: `--nv-surface-fg`, `--nv-bg-fg`, `--nv-input`

### Bug 2: tokens.js definía starter_elegant como LIGHT
`tokens.js` (tanto web como API nv-theme) tenía `starter_elegant` con colores LIGHT (`bg: #FAFAF9`, `surface: #FFFFFF`), mientras que `palettes.ts` y la tabla `palette_catalog` en DB lo definían como DARK (`bg: #111827`, `surface: #1F2937`).

Esto causaba que ThemeProvider (que lee de `tokens.js`) inyectara un theme LIGHT en `:root`, conflictuando con el scope DARK del preview.

**Fix:** Corregido `starter_elegant` en ambos `tokens.js` para que coincida con `palettes.ts` y DB (DARK).

### Bug 3: SectionRenderer sin datos en preview
`PreviewHost` renderizaba `<SectionRenderer>` **sin prop `data`**. `SectionRenderer` resuelve datos desde su prop `data` (no desde `useBuilderData` context), por lo que todas las secciones recibían `undefined` → 0 productos, 0 servicios, 0 FAQs.

**Fix:** Agregado `data={normalizedSeed}` al `<SectionRenderer>` en PreviewHost.

### Bug 4: var(--nv-input) indefinida
7 lugares en templates FIRST/THIRD/FOURTH usan `var(--nv-input)` pero no estaba en el contrato de 27 tokens.

**Fix:** Agregado como alias en `paletteToCssVars` apuntando al mismo valor que `--nv-input-bg`.

## Por qué

El usuario reportó que el preview con template FOURTH + palette `starter_elegant`:
- Mostraba header blanco y cards de contacto blancas sobre fondo oscuro (#111827)
- Textos oscuros sobre fondos oscuros (violando contraste)
- 0 productos, servicios vacíos, FAQs vacías

## Cómo probar

1. Levantar Admin (`npm run dev` en admin) + Web (`npm run dev` en web)
2. Ir al Builder → elegir template FOURTH + palette `starter_elegant`
3. Verificar en el preview:
   - Header, cards, footer usan colores oscuros consistentes
   - Textos claros sobre fondos oscuros
   - Productos, servicios y FAQs muestran datos (demo si no hay del cliente)
4. Probar con otras palettes dark (midnight_noir, deep_ocean, etc.) → misma consistencia

## Commits y propagación

| Repo | Rama | Hash |
|------|------|------|
| Web | feature/automatic-multiclient-onboarding | `6afcb88` |
| Web | develop | `9b5fb92` |
| Web | feature/multitenant-storefront | `db984db` |
| Web | feature/onboarding-preview-stable | `49a76a6` |
| API | feature/automatic-multiclient-onboarding | `62c2521` |
| API | develop | `4f274ff` |

## Notas de seguridad

Sin impacto en seguridad. Cambios puramente visuales/de datos en preview.

## Riesgos

- Si algún cliente tiene un palette custom con campo `bg` que no sea hex válido (ej: rgb(), hsl()), `isDarkHex()` retornará false (asume light). Bajo riesgo: todos los palettes en DB usan hex.
- `adjustHex()` es simplificado (ajuste lineal de brillo). Para palettes extremos podría no ser ideal, pero cubre el 95% de casos.

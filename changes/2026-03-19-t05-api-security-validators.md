# T0.5-API — Security Validators (CSS, Color, String)

**Fecha:** 2026-03-19
**Tipo:** Security hardening
**Impacto:** API — palettes.service, design-overrides.service

## Resumen

Implementa la capa API de T0.5 (Security & Performance Hardening) con tres validadores nuevos en `src/common/validators/`:

## Archivos nuevos

| Archivo | Funciones principales |
|---------|----------------------|
| `color.validator.ts` | `isValidCssColor()`, `validateColorTokens()`, `contrastRatio()`, `meetsWcagAA()`, `validatePaletteContrast()` |
| `string.validator.ts` | `isSimpleString()`, `sanitizeLabel()`, `escapeHtml()`, `validateLabels()` |
| `css.validator.ts` | `sanitizeCssOverrides()`, `hasBlockedSelectors()`, `scopeCssToTenant()` |
| `index.ts` | Barrel export |

## Integración en servicios

### palettes.service.ts
- `createCustomPalette()`: valida formato de color con `validateColorTokens()` (bloquea si inválido), loguea warnings de contraste WCAG AA
- `updateCustomPalette()`: misma validación

### design-overrides.service.ts
- `applyOverride()`: sanitiza `applied_value` con `sanitizeCssOverrides()` cuando `isVisualOnly=true`. Propiedades fuera del allowlist se rechazan y se loguean.

## Detalles de seguridad

### CSS Allowlist (~55 propiedades)
Colores, tipografía, spacing, borders, visual, layout seguro, flex, transitions.

### CSS Blocklist
`url()`, `expression()`, `behavior:`, `@import`, `@keyframes`, `@font-face`, `javascript:`, `-moz-binding`, selectores globales (`body`, `html`, `*`).

### Color validation
Acepta: `#RGB`, `#RRGGBB`, `#RRGGBBAA`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, `transparent`, `currentColor`, `inherit`.

### WCAG AA
Contraste ≥ 4.5:1 para text/bg, primary-fg/primary, accent-fg/accent, input-text/input-bg. Warnings (no bloquea).

## Validación
- Lint: 0 errores
- Typecheck: limpio
- Build: exitoso
- Commit: `7d62d45`

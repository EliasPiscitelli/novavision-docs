# 2026-03-19 — Template Unification: T0.5 + T0 Setup

## Repo: `@nv/web` (branch: `develop`)

## Resumen

Implementación de los tickets T0.5 (Security & Performance Hardening — partes web) y T0 (Setup — infraestructura base) del plan de unificación de componentes de templates.

## Cambios

### T0.5-web: Palette Color Validation

**Archivo:** `src/theme/palettes.ts`

- Nuevo: `isValidCssColor()` — valida hex, rgb, rgba, hsl, hsla, transparent; rechaza CSS injection
- Nuevo: `sanitizePalette()` — reemplaza valores inválidos con defaults seguros
- Modificado: `paletteFromVars()` — ahora sanitiza automáticamente paletas de fuentes externas
- Modificado: `paletteToCssVars()` — defensa en profundidad: sanitiza `overridePalette`
- Test: `src/__tests__/palette-color-validation.test.ts` (39 tests)

### T0.5-web: Lighthouse Performance Budgets

- Nuevo: `lighthouse-budgets.json` — budgets de Lighthouse (FCP <1800ms, LCP <2500ms, CLS <0.1)
- Nuevo: `scripts/check-bundle-size.mjs` — CI gate para verificar tamaño de chunks post-build
- Modificado: `package.json` — agregado `check:bundle` y integrado en `ci:storefront`

### T0.5-web: font-display:swap + preconnect

- Ya implementado: `index.html` ya tenía preconnect + display=swap. Verificado, sin cambios necesarios.

### T0: Theme Contract

- Nuevo: `src/components/storefront/theme-contract.ts` — contrato único de tokens CSS (27 color + spacing + radius + shadow + transition + z-index + layout). Define tipos de variantes para cada componente unificado y reglas obligatorias.

### T0: normalizeProduct Utility

- Nuevo: `src/utils/normalizeProduct.ts` — normaliza productos de cualquier template a formato canónico. Resuelve 5+ nombres de campo de stock, 3 formatos de imagen, 6+ alternativas de precio, 2 estructuras de categoría.
- Test: `src/__tests__/normalize-product.test.ts` (33 tests)

### T0: Reconciliación Sections/Variants

- Nuevo: `src/registry/variantMap.ts` — mapa completo de 50+ componentKeys → { unifiedType, variant }. Bridge entre el registry actual y la arquitectura unificada.
- Modificado: `src/registry/sectionCatalog.ts` — campo `variant?: string` agregado a `SectionMetadata`
- Modificado: `src/components/SectionRenderer.tsx` — inyecta `variant` prop desde `variantMap` al componente resuelto (sin override si ya existe `variant` o `layoutVariant`)

## Validación

- `typecheck`: 0 errores
- `lint`: 0 errores (54 warnings preexistentes)
- `build`: exitoso (6.8s)
- `test:unit`: 179/179 tests pasan
- `ensure-no-mocks`: OK
- `check:bundle`: todos los chunks dentro del budget

## Archivos nuevos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/components/storefront/theme-contract.ts` | 172 | Contrato de tokens CSS |
| `src/utils/normalizeProduct.ts` | 175 | Normalización de productos |
| `src/registry/variantMap.ts` | 140 | Mapa componentKey → variant |
| `src/__tests__/palette-color-validation.test.ts` | 111 | Tests de validación CSS |
| `src/__tests__/normalize-product.test.ts` | 220 | Tests de normalización |
| `scripts/check-bundle-size.mjs` | 97 | CI gate de bundle size |
| `lighthouse-budgets.json` | 17 | Budgets de Lighthouse |

## Próximos pasos

- T1: ProductCard unificado (depende de este T0 completado)
- D3-D7: Fixes de API (en paralelo, otro repo)
- T0 restante: Visual regression baselines (depende de D3)

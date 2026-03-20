# T14 — Spacing tokens generalization + density presets

**Fecha:** 2026-03-20
**Módulo:** Web (Storefront)
**Commits:** `58a150b` (develop) → `77445c4` (multitenant-storefront) → `fd72ab8` (onboarding-preview-stable)

## Cambios

### Fundación (3 archivos)
- **theme-contract.ts**: Agregó 8 tokens semánticos `--nv-spacing-*` con valores, 3 density presets (compact/normal/relaxed), tipo `DensityPreset`, `MIN_TOUCH_TARGET`. Incluidos en `ALL_TOKEN_NAMES` y `TokenName`.
- **variables.css**: Defaults estáticos para los 8 tokens + `--nv-min-touch-target` (44px)
- **palettes.ts**: `paletteToCssVars()` ahora retorna 35 tokens (27 color + 8 spacing)

### Migración de componentes (18 archivos)
Todos los componentes unificados migrados de `--nv-space-N` (escala numérica) a `--nv-spacing-*` (semánticos):

| Componente | Archivos migrados |
|---|---|
| ServicesSection | Grid, Cards, List, Skeleton |
| ProductCarousel | Basic, Featured, Hero, Skeleton |
| ContactSection | Cards, Minimal, TwoColumn, Skeleton + ContactInfoCard |
| Footer | Stacked, Columns, Branded, Skeleton |
| FAQSection | Masonry |

### Gaps hardcodeados reemplazados
- `Hero.tsx`: `'0.5rem'` → `var(--nv-spacing-element-gap)`
- `ContactInfoCard.tsx`: `'1rem'` → `var(--nv-spacing-card-padding)`
- `Branded.tsx`: `'0.5rem'` → `var(--nv-spacing-element-gap)`

## Arquitectura

```
Escala numérica (--nv-space-N)     ← foundation, siempre disponible
       ↓
Tokens semánticos (--nv-spacing-*) ← density layer, overridable per-tenant
       ↓
Componentes unificados             ← consumers, density-responsive
```

Los 3 presets de densidad:
- **compact**: Secciones 3rem, gaps 1rem — para contenido denso
- **normal**: Secciones 4rem, gaps 1.5rem — default actual
- **relaxed**: Secciones 6rem, gaps 2rem — para storefronts premium/luxury

## Pendiente (futuro)
- DesignStudio UI: control de densidad visual (Admin-side, fuera de scope T14)
- Persistencia: `theme_config.custom_vars` ya acepta overrides pero no hay UI

## Validación
- TypeScript: 0 errores
- Build: OK (6.76s)
- Tests: 333/341 pass (8 pre-existentes)
- Pre-push: 6/6 checks en las 3 ramas
- Dev-only file (.claude/rules/ai-async-plan.md) correctamente excluido de prod

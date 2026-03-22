# Deployment Log — Template Component Unification T0.5-T6

**Fecha:** 2026-03-19
**Autor:** develop → cherry-pick

## Commits por rama

| Rama | Commit | Estado | Pre-push |
|------|--------|--------|----------|
| `develop` | `04cfffd` | pushed | lint ✓ typecheck ✓ build ✓ no-mocks ✓ |
| `feature/multitenant-storefront` | `3bb2f08` (cherry-pick) | pushed | lint ✓ typecheck ✓ build ✓ no-mocks ✓ |
| `feature/onboarding-preview-stable` | `9365fa3` (cherry-pick) | pushed | lint ✓ typecheck ✓ build ✓ no-mocks ✓ |

## Justificación de branching

Todos los archivos del commit van a **ambas ramas de prod**:

| Categoría | Archivos | multitenant | onboarding | Razón |
|-----------|----------|:-----------:|:----------:|-------|
| Storefront components | `src/components/storefront/*` (50+ files) | ✓ | ✓ | Componentes de tienda usados en ambos contextos |
| SectionRenderer | `src/components/SectionRenderer.tsx` | ✓ | ✓ | Core de rendering compartido |
| Registry | `src/registry/variantMap.ts`, `sectionCatalog.ts` | ✓ | ✓ | Mapeos y catálogo de secciones |
| Theme/Palette | `src/theme/palettes.ts`, `theme-contract.ts` | ✓ | ✓ | Tokens y sanitización compartidos |
| Utils | `src/utils/normalizeProduct.ts` | ✓ | ✓ | Normalización de datos |
| Tests | `src/__tests__/*.test.ts` (8 files) | ✓ | ✓ | CI validation |
| Build scripts | `scripts/check-bundle-size.mjs`, `lighthouse-budgets.json` | ✓ | ✓ | Build validation (no runtime) |

## Archivos dev-only excluidos (no en este commit)

- `.claude/` — reglas de agentes
- `src/__dev/` — Dev Portal
- `CLAUDE.md` — instrucciones de proyecto
- `scripts/audit-css-contrast.mjs` — auditoría CSS

## Verificación post-deploy

Diff de archivos productivos entre develop y ramas prod: solo diferencias pre-existentes (17 files, no relacionadas con este commit).

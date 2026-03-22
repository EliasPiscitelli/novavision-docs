# T16: Barrel cleanup + template scaffold script

**Fecha:** 2026-03-19
**Commit:** `5e38df5` (develop) → `698f6f3` (multitenant) → `040e8ad` (onboarding)
**Repo:** `apps/web`
**Ticket:** T16 — Actualizar proceso de generación de templates

## Cambios

### Barrel cleanup (8 archivos)

Eliminados 37 exports muertos de los 8 barrel files en `src/registry/sectionComponentTemplates/`.
Los componentes unificados (T2-T6) reemplazan las implementaciones per-template de FAQ, Contact, Footer, Services y ProductCarousel.

| Barrel | Antes | Después | Eliminados |
|--------|-------|---------|-----------|
| first.tsx | 7 exports | 2 (Header, Collections) | 5 |
| second.tsx | 5 exports | 2 (Header, BannerHome) | 3 |
| third.tsx | 7 exports | 3 (Header, Collections, CategoriesCarousel) | 4 |
| fourth.tsx | 7 exports | 3 (Header, Hero, Grid) | 4 |
| fifth.tsx | 9 exports | 3 (Header, Banner, Grid) | 6 |
| sixth.tsx | 8 exports | 3 (Hero, Testimonials, Marquee) | 5 |
| seventh.tsx | 7 exports | 2 (Hero, Testimonials) | 5 |
| eighth.tsx | 8 exports | 3 (Hero, Testimonials, Newsletter) | 5 |
| **Total** | **58** | **21** | **37** |

### Template scaffold script

Nuevo `scripts/new-template.mjs` que genera la estructura de un template nuevo:

```
src/templates/{name}/
├── config.js                         ← variant selections + metadata
├── components/HeroSection/index.jsx  ← placeholder Hero
└── pages/HomePage{Name}/index.jsx    ← entry point genérico

src/registry/sectionComponentTemplates/{name}.tsx  ← barrel file
```

Además imprime instrucciones exactas (copy-paste) para registrar el template en los 7 archivos del pipeline + SQL seeds.

## Validación

- typecheck: 0 errores
- build: 6.30s
- tests: 341/341
- ensure-no-mocks: OK
- pre-push hooks: passed en las 3 ramas

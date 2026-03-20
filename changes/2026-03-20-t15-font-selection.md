# T15 — Font Selection Catalog + UI

**Fecha:** 2026-03-20
**Tickets:** T15
**Ramas:** API `feature/automatic-multiclient-onboarding` (1cda7a0), Web `develop` (fb6b546) → cherry-pick a `feature/multitenant-storefront` (8e11987) + `feature/onboarding-preview-stable` (e97527a)

## Resumen

Implementación completa del sistema de selección de tipografías para tiendas multi-tenant. Los administradores de tienda pueden elegir entre 10 Google Fonts desde el DesignStudio, con gating por plan (starter: 3 fonts, growth+: 10).

## Archivos nuevos (Web)

| Archivo | Descripción |
|---------|-------------|
| `src/theme/fontCatalog.ts` | Catálogo de 10 Google Fonts con plan gating, helpers `resolveFontFamily()`, `canAccessFont()`, `buildGoogleFontsUrl()` |
| `src/components/storefront/FontLoader.tsx` | Componente renderless que inyecta `<link>` de Google Fonts dinámicamente con preconnect y cleanup |
| `src/components/admin/StoreDesignSection/FontSelector.jsx` | Grid UI categorizado (sans/serif/mono) con live preview de cada font en su propia tipografía |

## Archivos modificados (Web)

| Archivo | Cambio |
|---------|--------|
| `src/App.jsx` | Resuelve `font_key` desde `themeConfig`, inyecta `--nv-font` CSS var, monta `FontLoader` |
| `src/pages/PreviewHost/index.tsx` | `fontKey` en `PreviewPayload`, resuelve `fontFamily` para preview iframe |
| `src/theme/palettes.ts` | `fontFamily` parámetro en `paletteToCssVars()` para `--nv-font` dinámico |
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | Estado `selectedFont`, carga/guardado, preview payload con fontKey, UI FontSelector en panel presets |
| `src/services/identity.js` | `fontKey` en `updateVisualSettings()` |

## Archivos modificados (API)

| Archivo | Cambio |
|---------|--------|
| `src/home/home-settings.controller.ts` | `@Body('fontKey')` parámetro en `PUT /settings/home` |
| `src/home/home-settings.service.ts` | `fontKey` parámetro en `upsertTemplate()`, merge en `theme_config` JSONB |

## Flujo end-to-end

1. Admin selecciona font en DesignStudio → preview se actualiza en iframe
2. Al guardar, `fontKey` se envía al API → se mergea en `theme_config.font_key` JSONB
3. Storefront lee `themeConfig.font_key` → resuelve familia con plan gating → inyecta `--nv-font` CSS var
4. `FontLoader` carga la Google Font dinámicamente con `font-display: swap`

## Validación

- API: typecheck OK, build OK, pipeline 7 checks passed
- Web: typecheck OK, build OK (6.84s), tests 333/341 (8 pre-existentes), pipeline 6 checks passed x3 ramas

# T9 — Custom CSS Overrides (Manual)

**Fecha:** 2026-03-20
**Tickets:** T9
**Ramas:** API `feature/automatic-multiclient-onboarding` (4cb05c1), Web `develop` (cff2b1f) → cherry-pick a `feature/multitenant-storefront` (991557a) + `feature/onboarding-preview-stable` (0318729)

## Resumen

Implementación completa del sistema de CSS personalizado para tiendas multi-tenant. Los administradores pueden agregar propiedades CSS desde un editor property/value en el DesignStudio. El CSS se sanitiza server-side, se scopa al contenedor del tenant, y se inyecta dinámicamente en el storefront.

## Archivos nuevos

| Archivo | Repo | Descripción |
|---------|------|-------------|
| `src/components/admin/StoreDesignSection/CssOverrideEditor.jsx` | Web | Editor property/value con dropdown de ~19 propiedades comunes, create/update/delete |
| `src/hooks/useDesignOverrides.js` | Web | Hook que fetch CSS activo y lo inyecta como `<style id="nv-design-overrides">` |

## Archivos modificados

| Archivo | Repo | Cambio |
|---------|------|--------|
| `src/design-overrides/design-overrides.controller.ts` | API | +POST (create), +PATCH /:id (update), +DELETE /:id (revoke), +GET /active-css (public) |
| `src/design-overrides/design-overrides.service.ts` | API | +createCustomCss, +updateCustomCss, +revokeOverride, +getActiveCss methods |
| `src/api/addons.js` | Web | +createDesignOverride, +updateDesignOverride, +deleteDesignOverride, +getActiveCss |
| `src/App.jsx` | Web | Import + mount `useDesignOverrides()` hook |
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | Web | Import CssOverrideEditor, +refreshOverrides callback, CSS Editor panel en tab presets |

## Flujo end-to-end

1. Admin abre DesignStudio → panel "CSS Personalizado" muestra grid de propiedades
2. Selecciona propiedad del dropdown, escribe valor, guarda
3. POST /design-overrides envía `{ cssProperties: { "color": "#fff", ... } }`
4. Backend sanitiza via `sanitizeCssOverrides()` (allowlist ~55 props), scopa con `scopeCssToTenant()`
5. Respuesta incluye rejected properties si alguna fue filtrada
6. Storefront: `useDesignOverrides()` fetches `GET /active-css` → inyecta `<style>` en `<head>`
7. CSS scoped: `.nv-store-{clientId} { color: #fff; ... }`

## Seguridad

- Sanitización allowlist: ~55 propiedades CSS permitidas
- Bloqueo de: `url()`, `expression()`, `@import`, `@keyframes`, `@font-face`, `javascript:`, `-moz-binding`
- Solo variables `--nv-*` permitidas
- `display` restringido a: block, inline-block, flex, grid, none
- Valores limitados a 500 chars
- CSS scoped a contenedor del tenant (multi-tenant isolation)
- RLS: admin solo puede modificar overrides de su propio client_id

## Validación

- API: typecheck OK, build OK, pipeline 7 checks passed
- Web: typecheck OK, build OK (6.59s), tests 333/341 (8 pre-existentes), pipeline 6 checks passed x3 ramas

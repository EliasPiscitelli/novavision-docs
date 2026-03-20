# D6 — Custom Palette CRUD en Web (identity.js + DesignStudio)

**Fecha:** 2026-03-19
**Tipo:** Bug fix
**Impacto:** Web — DesignStudio admin panel
**Commits:** `b84045a` (develop), `2fa478f` (multitenant-storefront), `76df579` (onboarding-preview-stable)

## Problema

El DesignStudio (Web) llamaba a `identityService.createCustomPalette()`, `updateCustomPalette()`, y `deleteCustomPalette()` pero estos metodos no existian en `identity.js`. Las operaciones fallaban silenciosamente. Ademas, las paletas custom existentes no se cargaban al inicializar el studio.

**Backend API:** Completamente implementado (POST/PUT/DELETE `/palettes/custom` + validacion WCAG + plan limits).
**Admin dashboard:** Funcional (usa React Query hooks).
**Web DesignStudio:** Roto — faltaban los metodos en el service layer.

## Cambios

### `src/services/identity.js`
- `getAllPalettes()` — GET `/palettes` — retorna `{ catalog, customs? }`
- `createCustomPalette(data)` — POST `/palettes/custom`
- `updateCustomPalette(id, data)` — PUT `/palettes/custom/:id`
- `deleteCustomPalette(id)` — DELETE `/palettes/custom/:id`

### `src/components/admin/StoreDesignSection/DesignStudio.jsx`
- **Carga inicial:** Cambiado de `getCatalogPalettes()` a `getAllPalettes()` con fallback a `getCatalogPalettes()`. Ahora carga tanto paletas de catalogo como custom del tenant.
- **handleDeletePalette:** Ahora llama a `identityService.deleteCustomPalette()` antes de limpiar el estado local. Error handling graceful (warn + continua).

## Validacion

- TypeScript: 0 errores
- Build: OK (6.53s)
- Lint: 0 errores
- Pre-push: paso en las 3 ramas

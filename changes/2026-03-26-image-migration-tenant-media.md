# Migración de imágenes a tenant_media

**Fecha:** 2026-03-26
**Plan:** `PLAN_AI_PRODUCT_FULL_GENERATION.md` Bloque 3A
**Estado:** Implementado + testeado

---

## Problema

Las imágenes de productos se almacenan como URLs directas en `products.imageUrl` (tipo ARRAY). Esto impide gestionar la media library de forma centralizada, rastrear uso, generar variantes y aplicar cuotas de storage por tenant.

## Solución

### Método de migración: `migrateExistingProductImages()`

- **Ubicación**: `media-library.service.ts:777`
- Lee todos los productos con `imageUrl` no nulo
- Para cada imagen:
  - Filtra solo URLs de Supabase storage (`supabase.co/storage/`)
  - Extrae `storage_key` de la URL pública
  - Si ya existe en `tenant_media` (por `storage_key + client_id`), reutiliza el ID existente (idempotente)
  - Si no existe, inserta en `tenant_media` con filename, mime_type, variants
  - Upsert en `product_media` con `onConflict: 'product_id,media_id'`
- Retorna contadores: `productsProcessed`, `imagesRegistered`, `imagesLinked`, `skipped`, `errors`

### Endpoint admin

- **Ruta**: `POST /admin/media/migrate-product-images`
- **Guard**: `SuperAdminGuard` + `@AllowNoTenant()`
- **Controller**: `media-admin.controller.ts`

### Archivos modificados

- `api/src/media-library/media-library.service.ts` — `migrateExistingProductImages()`, `extractStorageKeyFromUrl()`, `inferMimeType()`
- `api/src/admin/media-admin.controller.ts` — constructor con `MediaLibraryService`, endpoint POST

### Tests creados

- `api/src/media-library/__tests__/media-library.service.spec.ts` — 7 tests nuevos:
  - Migración de URLs Supabase → tenant_media + product_media
  - Skip de URLs externas/placeholders
  - Idempotencia (skip existentes)
  - Sin productos con imágenes
  - Error de conexión
  - Errores parciales sin detener migración
  - Formato string (URL plana)
- `api/src/admin/__tests__/media-admin.controller.spec.ts` — 5 tests nuevos:
  - Delegación a service
  - Propagación de errores
  - Dry-run de bulk delete
  - Validación de clientId
  - Bulk delete real

## Datos de producción

- 58 productos total, 23 con imágenes
- 4 imágenes reales de Supabase storage (3 productos, 1 tenant)
- 0 registros previos en tenant_media

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Lint: 0 errores
- Tests: 107/107 suites, 1045/1047 tests OK (2 skipped preexistentes)

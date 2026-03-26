# 2026-03-24 — Registro unificado de imágenes en banco de imágenes (tenant_media)

## Problema
Las imágenes subidas al crear o editar productos NO se registraban en `tenant_media` (banco de imágenes). Solo las subidas desde la Media Library quedaban disponibles para reutilización. Además, varias operaciones de media carecían de validación de tenant (cross-tenant data leak).

## Cambios

### Migraciones ejecutadas
- `20260316_create_tenant_media.sql` — Tablas `tenant_media` + `product_media` con RLS, índices y triggers
- `20260316_create_media_upload_jobs.sql` — Tablas `media_upload_batches` + `media_upload_jobs` para bulk upload async

### API — Nuevos métodos en MediaLibraryService
- `registerAndLink()` — Procesa imagen con variantes (webp/avif), registra en `tenant_media` y vincula a producto via `product_media`
- `registerExistingImage()` — Registra una imagen ya procesada (con variantes) en el banco sin re-procesar

### API — Flujo único de producto (sin doble escritura)
- `ProductsService.createProduct()` — Acepta `mediaIds` (banco) + `files` (nuevos uploads). Usa `attach()` para vincular media existentes y `registerAndLink()` para archivos nuevos. `rebuildProductImages()` reconstruye `imageUrl` desde `product_media` como fuente única de verdad.
- `ProductsService.updateProduct()` — Sincroniza `product_media` con `mediaIds` del frontend (maneja reorden/eliminación). Archivos nuevos pasan por `registerAndLink()`. Rebuild final.
- `ProductsController.uploadOptimizedImage()` — Registra en `tenant_media` + `product_media` y hace rebuild (síncrono, no fire-and-forget).

### API — Hardening de seguridad multi-tenant
- `delete()` — Scope de affected products por `client_id` via join con `products`. Borrado de junction rows individual por `product_id` (no bulk sin filtro).
- `rebuildProductImages()` — Validación de product ownership antes de operar. Query de `tenant_media` filtrada por `client_id`.
- `refreshUsageCounts()` — Recibe `clientId`, cuenta solo products del tenant, actualiza solo media del tenant.
- Mensaje de error genérico (sin revelar conteo de uso cross-tenant).

### Limpieza de código muerto
- Eliminado `src/common/utils/storage-path.helper.ts` (`buildStorageObjectPath`)
- Eliminado `updateImageVariants()` de `ProductsService`
- Eliminado `rebuildProductImagesPublic()` wrapper (método ahora es público directo)
- `imageUrl` removido de `ALLOWED_FIELDS` — `product_media` es la fuente única

### Tests actualizados
- `products.service.spec.ts` — Mock de `MediaLibraryService` agregado
- `products.controller.spec.ts` — Mock de `MediaLibraryService` agregado
- `media-library.service.spec.ts` — Tests de delete actualizados para nueva query con join

### Plan documentado
- `novavision-docs/plans/PLAN_UNIFIED_MEDIA_REGISTRATION.md`

## Validación
- `npm run typecheck` — sin errores
- `npm run build` — exitoso
- `npm run test` — 104/106 suites pasan, 1028/1035 tests (2 fallos pre-existentes en home module)
- `npm run test -- --testPathPattern='products|media'` — 21/21 tests pasando

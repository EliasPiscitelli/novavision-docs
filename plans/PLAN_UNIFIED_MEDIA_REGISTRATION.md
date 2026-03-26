# Plan: Registro unificado de imágenes en tenant_media

## Problema

Actualmente existen 3 flujos independientes de upload de imágenes de productos:

| Flujo | Archivo | Procesa variantes | Registra en `tenant_media` | Crea `product_media` junction |
|-------|---------|:-:|:-:|:-:|
| Create/Update product | `products.service.ts` L602-783 | NO | NO | NO |
| Upload optimized (single) | `products.controller.ts` L720-745 | SI | NO | NO |
| Media Library | `media-library.service.ts` L64-121 | SI | SI | SI (via attach) |

**Resultado**: Las imágenes subidas durante la creación/edición de productos NO aparecen en el "banco de imágenes" (`tenant_media`), lo que impide reutilizarlas entre productos.

## Estado actual de la BD

- **Tablas `tenant_media` y `product_media` NO EXISTEN** en producción
- Migraciones preparadas pero no ejecutadas: `migrations/20260316_create_tenant_media.sql`
- La tabla `products` tiene: `imageUrl` (ARRAY de `{url, order}`), `image_variants` (JSONB)

## Objetivo

Que **toda imagen** subida a un producto — ya sea al crear, editar o subir individualmente — se registre automáticamente en `tenant_media` y se vincule al producto via `product_media`. El "banco de imágenes" refleja TODAS las imágenes del tenant.

---

## Fase 1: Ejecutar migraciones pendientes

### 1.1 Crear tablas `tenant_media` + `product_media`

Ejecutar migración existente: `migrations/20260316_create_tenant_media.sql`

Crea:
- `tenant_media`: id, client_id, filename, original_name, mime_type, size_bytes, width, height, storage_key, variants (JSONB), tags, usage_count, created_at, updated_at
- `product_media`: product_id, media_id, order, is_main (junction con FK a ambas tablas)
- RLS: tenant isolation + service_role bypass
- Índices: client_id, client_id+created_at DESC, product_id, media_id
- Trigger: updated_at automático

### 1.2 Crear tablas `media_upload_batches` + `media_upload_jobs`

Ejecutar: `migrations/20260316_create_media_upload_jobs.sql`

Necesarias para el bulk upload async (ya referenciado en `MediaLibraryService.enqueueBulkUpload`).

---

## Fase 2: Método helper en MediaLibraryService

### 2.1 Nuevo método público `registerAndLink`

**Archivo**: `apps/api/src/media-library/media-library.service.ts`

```ts
async registerAndLink(params: {
  file: Express.Multer.File;
  clientId: string;
  productId: string;
  order: number;
  isMain: boolean;
}): Promise<TenantMedia>
```

Este método:
1. Llama a `ImageService.processAndUpload()` para generar variantes webp/avif (thumb, md, lg)
2. Inserta en `tenant_media` con metadata completa
3. Inserta en `product_media` (junction) con order + is_main
4. Incrementa `usage_count`
5. Retorna el `TenantMedia` creado

Es un método "fire-and-link" que combina upload + registro + vinculación en una sola operación atómica para el llamador.

### 2.2 Nuevo método público `registerExistingImage`

**Archivo**: `apps/api/src/media-library/media-library.service.ts`

```ts
async registerExistingImage(params: {
  storageKey: string;
  variants: Record<string, unknown>;
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  width: number | null;
  height: number | null;
  clientId: string;
  productId: string;
  order: number;
  isMain: boolean;
}): Promise<TenantMedia>
```

Para el caso de `uploadOptimizedImage` donde la imagen ya fue procesada por `ImageService`. Solo registra en `tenant_media` + `product_media` sin re-procesar.

---

## Fase 3: Integrar en flujos de producto

### 3.1 Modificar `ProductsService.createProduct`

**Archivo**: `apps/api/src/products/products.service.ts` — método `createProduct` (L602-692)

Cambio:
1. **ANTES**: Upload directo a storage → URL pública → `products.imageUrl[]`
2. **DESPUÉS**: Crear producto sin imágenes → Para cada file: llamar `mediaLibraryService.registerAndLink()` → Rebuild `products.imageUrl` + `image_variants` desde `product_media`

Flujo nuevo:
```
1. Insert producto (sin imageUrl)
2. Para cada file:
   a. mediaLibraryService.registerAndLink({ file, clientId, productId, order, isMain })
3. rebuildProductImages(productId, clientId)  // reconstruye imageUrl + image_variants
4. Retornar producto con imágenes
```

### 3.2 Modificar `ProductsService.updateProduct`

**Archivo**: `apps/api/src/products/products.service.ts` — método `updateProduct` (L695-783)

Cambio análogo:
1. Mantener imágenes existentes (que ya tienen `product_media` entries)
2. Solo las imágenes NUEVAS (files del request) pasan por `registerAndLink()`
3. Rebuild final

### 3.3 Modificar `ProductsController.uploadOptimizedImage`

**Archivo**: `apps/api/src/products/products.controller.ts` — L720-745

Después de `ImageService.processAndUpload()`, agregar llamada a `mediaLibraryService.registerExistingImage()` para registrar la imagen ya procesada en `tenant_media` + `product_media`.

### 3.4 Inyectar `MediaLibraryService` en `ProductsModule`

**Archivo**: `apps/api/src/products/products.module.ts`

Agregar `MediaLibraryModule` a imports. Inyectar `MediaLibraryService` en `ProductsService` y `ProductsController`.

---

## Fase 4: Backwards compatibility

### 4.1 Doble escritura

El sistema mantiene **doble escritura**:
- `products.imageUrl` (ARRAY): URLs públicas para el storefront (compatibilidad)
- `products.image_variants` (JSONB): Variantes optimizadas
- `tenant_media` + `product_media`: Fuente de verdad del banco de imágenes

`rebuildProductImages()` de `MediaLibraryService` ya reconstruye `imageUrl` e `image_variants` desde `product_media` → `tenant_media`, lo que garantiza consistencia.

### 4.2 Imágenes existentes (productos ya creados)

Los productos creados ANTES de este cambio tienen imágenes en storage pero SIN registros en `tenant_media`. Esto es aceptable por ahora — el banco de imágenes mostrará solo las nuevas. Una migración de datos retroactiva se puede planificar por separado si es necesario.

---

## Archivos a modificar

| Archivo | Acción |
|---------|--------|
| `apps/api/src/media-library/media-library.service.ts` | Agregar `registerAndLink()` + `registerExistingImage()` |
| `apps/api/src/products/products.service.ts` | Modificar `createProduct()` + `updateProduct()` |
| `apps/api/src/products/products.controller.ts` | Modificar `uploadOptimizedImage()` |
| `apps/api/src/products/products.module.ts` | Agregar `MediaLibraryModule` a imports |

## Migraciones a ejecutar

| Migración | Tablas |
|-----------|--------|
| `20260316_create_tenant_media.sql` | `tenant_media`, `product_media` + RLS + índices |
| `20260316_create_media_upload_jobs.sql` | `media_upload_batches`, `media_upload_jobs` |

## Verificación

1. Crear producto con imagen → verificar que aparece en `tenant_media` y en el listado de media library
2. Editar producto agregando imagen → verificar registro en `tenant_media`
3. Upload optimized (single image) → verificar registro en `tenant_media`
4. Verificar que `products.imageUrl` sigue funcionando correctamente para el storefront
5. `npm run lint && npm run typecheck && npm run build`

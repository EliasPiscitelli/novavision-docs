# Storage Multi-Cliente - NovaVision

## Resumen

Implementación de media storage segmentado por cliente usando Supabase Storage con estructura de carpetas `clients/{client_id}/category/...` y políticas RLS para aislamiento completo entre tenants.

## Estructura de Carpetas

```
clients/{client_id}/
  branding/
    logo/{timestamp}.{ext}
    favicon/{timestamp}.{ext}
  banners/
    {banner_id}/
      desktop/original.{ext}
      mobile/original.{ext}
  products/
    {product_id}/
      original/{uuid}.{ext}
      thumb/{uuid}.{ext}
      medium/{uuid}.{ext}
  orders/
    {order_id}/proofs/{uuid}.{ext}
  services/
    {service_id}/{uuid}.{ext}
  pages/
    {page_key}/{uuid}.{ext}
```

## Servicios y Utilidades

### Path Builders (`src/common/storage/path-builder.ts`)

```typescript
import { productImagePath, bannerImagePath, logoPath } from '@/common/storage/path-builder';

// Ejemplo de uso
const path = productImagePath('client-123', 'product-456', 'image.jpg', 'original');
// Resultado: "clients/client-123/products/product-456/original/image.jpg"
```

### StorageService (`src/common/storage/storage.service.ts`)

Servicio centralizado para operaciones de storage:

```typescript
import { StorageService } from '@/common/storage/storage.service';

// Subir archivo
const result = await storageService.upload(
  buffer,
  'clients/client-123/products/product-456/original/image.jpg',
  'image/jpeg'
);

// Obtener URL pública
const publicUrl = storageService.getPublicUrl(path);

// Obtener URL firmada
const signedUrl = await storageService.getSignedUrl(path, 3600);

// Eliminar archivos
await storageService.remove(['path1', 'path2']);
```

## Migración

### 1. Aplicar migración SQL

```bash
# Aplicar políticas RLS
psql -d database_url -f migrations/20251014_multiclient_storage.sql
```

### 2. Migrar archivos existentes

```bash
# Dry run para ver qué se migrará
npm run migration:storage -- --dry-run

# Ejecutar migración real
npm run migration:storage -- --execute --batch-size=50
```

## Endpoints de Administración

### Borrado masivo por cliente

```bash
# Ver qué se eliminaría (dry run)
DELETE /admin/media/clients/{clientId}?dryRun=true

# Eliminar realmente
DELETE /admin/media/clients/{clientId}?dryRun=false&limit=1000
```

### Estadísticas de storage

```bash
GET /admin/media/clients/{clientId}/stats
```

Respuesta:
```json
{
  "clientId": "uuid",
  "bucket": "product-images", 
  "fileCount": 150,
  "totalBytes": 25600000,
  "categories": {
    "products": { "count": 120, "bytes": 20000000 },
    "banners": { "count": 20, "bytes": 4000000 },
    "branding": { "count": 10, "bytes": 1600000 }
  }
}
```

## Políticas de Seguridad

### RLS en storage.objects

1. **Lectura pública**: Solo archivos bajo `clients/{su_client_id}/`
2. **Escritura**: Solo usuarios autenticados pueden subir bajo su prefijo
3. **Eliminación**: Solo usuarios pueden eliminar sus propios archivos
4. **Service role bypass**: Backend puede hacer todas las operaciones

### Validación en backend

- Todos los uploads validan que el path empiece con `clients/{client_id}/`
- JWT debe contener `client_id` válido
- Validación de MIME types y tamaños

## Uso en Frontend

### URLs de imágenes

```typescript
// En lugar de guardar URLs absolutas, guardar paths relativos en BD
const imagePath = 'clients/client-123/products/product-456/original/image.jpg';

// Resolver URL en runtime
const publicUrl = supabase.storage
  .from('product-images')
  .getPublicUrl(imagePath).data.publicUrl;
```

### Subida de archivos

```typescript
// Usar endpoint del backend que valida y construye paths
const formData = new FormData();
formData.append('file', file);
formData.append('clientId', clientId);

const response = await fetch('/api/products/upload-image', {
  method: 'POST',
  body: formData
});
```

## Testing

### Casos de prueba clave

1. **Aislamiento**: Usuario de cliente A no puede ver archivos de cliente B
2. **Upload**: Archivos se guardan en estructura correcta
3. **RLS**: Políticas funcionan correctamente
4. **Migración**: Archivos se mueven sin pérdida
5. **Borrado masivo**: Funciona con dry-run y ejecución real

### Scripts de verificación

```bash
# Verificar estructura de archivos
SELECT name FROM storage.objects 
WHERE bucket_id = 'product-images' 
AND name LIKE 'clients/%' 
LIMIT 10;

# Verificar políticas RLS
SELECT policyname, cmd, qual 
FROM pg_policies 
WHERE schemaname = 'storage' 
AND tablename = 'objects';
```

## Rollback de Emergencia

```sql
-- Deshabilitar RLS temporalmente
ALTER TABLE storage.objects DISABLE ROW LEVEL SECURITY;

-- Eliminar políticas específicas
DROP POLICY IF EXISTS public_read_client_media ON storage.objects;
DROP POLICY IF EXISTS client_media_insert ON storage.objects;
DROP POLICY IF EXISTS client_media_update ON storage.objects;
DROP POLICY IF EXISTS client_media_delete ON storage.objects;
DROP POLICY IF EXISTS service_role_bypass ON storage.objects;
```

## Monitoreo

### Métricas importantes

- Tamaño total por cliente
- Archivos huérfanos (no referenciados en BD)
- Fallos de upload por políticas RLS
- Tiempo de respuesta de operaciones de storage

### Logs estructurados

Todos los servicios logean con:
```json
{
  "clientId": "uuid",
  "operation": "upload|delete|copy",
  "path": "clients/...",
  "bytes": 1234,
  "contentType": "image/jpeg"
}
```

## Configuración

### Variables de entorno

```bash
SUPABASE_URL=https://xxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=xxx
STORAGE_BUCKET=product-images  # bucket por defecto
```

### Buckets requeridos

- `product-images` (o `media`) - público con CDN habilitado
- Políticas RLS habilitadas
- CORS configurado para dominios del frontend

## Próximos pasos

1. **Optimización de imágenes**: Generar variantes automáticamente (webp, diferentes tamaños)
2. **CDN**: Configurar CloudFlare o similar para cache agresivo
3. **Limpieza automática**: Job cron para eliminar archivos huérfanos
4. **Métricas**: Dashboard de uso de storage por cliente
5. **Backup**: Estrategia de respaldo automático por cliente
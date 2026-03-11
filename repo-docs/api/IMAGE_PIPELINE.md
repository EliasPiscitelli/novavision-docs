# Pipeline de Imágenes Optimizado

Implementado: módulo `ImageProcessingModule`, servicio `ImageService`, endpoint `/products/:id/image` y refactors para `banners`, `services`, `logos`.

## Flujo
1. Upload en memoria (Multer memoryStorage)
2. Validaciones: mimetype permitido, tamaño <=2MB, probe real con `file-type`, dimensiones y píxeles <=40MP.
3. Generación de variantes según `kind` usando `sharp`:
  - products: 320 / 800 / 1600 (thumb, md, lg)
  - banners: 1280 / 1920 / 2560 (md, lg, xl)
  - services: 320 / 800 / 1600 (thumb, md, lg)
  - logos: 512 / 1024 (md, lg)
4. Formatos: WebP (q80) y AVIF (q32 effort4)
5. Path: `<clientId>/<kind>/<entityId>/<base>-<size>.<ext>`
6. Cache: `public, max-age=31536000, immutable`
7. Persistencia:
  - products.image_variants (JSONB) + imageUrl principal
  - banners.image_variants (JSONB) + url principal (webp grande)
  - services.image_variants (JSONB) + image_url principal
  - logos.image_variants (JSONB) + url principal

## JSON ejemplo (`variants`)
```json
{
  "lg": {
    "w": 1600,
    "webp": { "key": "<client>/products/<id>/base-lg.webp", "bytes": 123456 },
    "avif": { "key": "<client>/products/<id>/base-lg.avif", "bytes": 98765 }
  },
  "md": { ... },
  "thumb": { ... }
}
```

## Notas de Migración
- Añadir columnas JSONB si no existen: `ALTER TABLE banners ADD COLUMN image_variants JSONB;` etc.
- Migrar registros existentes opcionalmente generando variantes retroactivas.

## Próximos pasos sugeridos
- Migrar imágenes existentes a la nueva estructura (jobs batch).
- Agregar limpieza de variantes huérfanas.
- Añadir soporte avatars si aplica.
- Tests e2e de endpoints de carga por entidad.

---

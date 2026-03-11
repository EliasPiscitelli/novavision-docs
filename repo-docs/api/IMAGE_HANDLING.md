# Rastreo de Procesamiento de Imágenes / Archivos (Storage Supabase)

Fecha original: 2025-08-15  
Última actualización: 2025-08-15 (post implementación de pipeline de optimización)  
Rama: `multiclient`

## Objetivo
Inventario de todos los puntos del backend que:
- Reciben archivos/imágenes (upload)
- Generan imágenes (QR)
- Obtienen URL públicas
- Eliminan archivos del storage
- Manipulan arrays de imágenes asociadas a entidades

## Bucket principal utilizado
`product-images` (centraliza logos, productos, banners, servicios, códigos QR, etc.) — considerar segmentar por bucket para aplicar políticas diferentes.

---
## 1. Products (`products.service.ts` + `products.controller.ts` + `image-processing/image.service.ts`)
**Ubicación principal:** `src/products/*` y servicio central `src/image-processing/image.service.ts`

### Situación Actual (Optimizada)
- Flujo legacy continúa para arrays `imageUrl` (backward compatible) pero ahora existe endpoint dedicado `POST /products/:id/image` que:
  - Usa Multer (memoria) + `ImageService.processAndUpload`.
  - Genera variantes (AVIF y WebP) en distintos tamaños configurados para `kind = products` (ej: sm, md, lg, xl según mapa interno).
  - Persiste en columna JSONB `image_variants` con estructura por tamaño y formato.
  - Selecciona como principal (`imageUrl` simple) la variante mayor disponible en orden preferente AVIF > WebP.
- Nombre de archivo interno ahora es hash del contenido + sufijos de tamaño y formato: `products/<hash>_<size>.<ext>` para asegurar deduplicación implícita.
- Validación de tipo/dimensiones implementada en `ImageService` (usa `file-type` + `sharp`).

### Flujo Legacy (Aún presente)
- Métodos `createProduct`, `updateProduct`, `uploadImages` siguen subiendo originales y almacenando array `{ url, order }` (sin variantes) → Pendiente de migrar o deprecarlos.

### Eliminaciones
- `removeImage` y `deleteProduct` todavía dependen de extraer el último segmento de la URL (Riesgo heredado). Necesario migrar a guardar siempre `file_path` de cada variante y principal.

### Recomendado Próximo Paso
- Backfill opcional: construir `image_variants.legacy` a partir de la primera imagen del array para productos antiguos (script comentado en migración).
- Refactor eliminación para usar metadata de `image_variants` en lugar de `split('/')`.

---
## 2. Banners (`banner.service.ts` + `image-processing/image.service.ts`)
**Estado Actual:** Refactorizado para pipeline de variantes.

### Subidas (Optimizado)
- `updateBanners(files, type, clientId)` ahora:
  - Pasa cada buffer a `ImageService` con `kind = banners` generando variantes múltiples (ej: md, lg, xl según configuración).
  - Inserta fila por imagen con campos: `url` (principal derivada), `image_variants` (JSONB), `file_path` (principal) y `client_id`.
  - Selección de principal: prioriza variante `xl` luego `lg` luego la primera disponible.

### Orden
- Sigue cálculo por `MAX(order)+1` → riesgo de condición de carrera permanece (no resuelto aún).

### Eliminación
- `deleteBanner` no limpia actualmente todas las variantes (solo principal si usa `file_path`). Necesario extender para listar y borrar cada `key` dentro de `image_variants`.

### Validación
- Ya validado tipo/dimensiones vía `ImageService` (cubre mejora previa faltante).

---
## 3. Services (`service.service.ts` + `image-processing/image.service.ts`)
**Estado Actual:** Refactorizado a variantes.

### Subidas
- `createService` / `updateService` usan `ImageService` (`kind = services`).
- Persisten `image_variants` + `image_url` principal (derivada de la variante más grande AVIF/WebP disponible).

### Actualizaciones
- En `updateService` se elimina el archivo principal anterior pero aún no se eliminan todas las variantes antiguas (debe ampliarse para usar el listado de claves en JSONB).

### Validación
- Cubierta por `ImageService`.

---
## 4. Logo (`logo.service.ts` + `image-processing/image.service.ts`)
**Estado Actual:** Variantes implementadas.

### Subida / Actualización
- `updateLogo` procesa variantes (`kind = logos`), persiste `image_variants`, selecciona principal (prefiere mayor AVIF/WebP) y desactiva anteriores (`show_logo = false`).
- Aún no elimina archivos de variantes históricos (riesgo residual de acumulación). Se necesita tarea de limpieza.

### Eliminación
- `deleteLogo` no garantiza remover todas las variantes previas si solo conoce un `file_path` → pendiente migrar a una rutina que itere JSONB.

---
## 5. Mercado Pago (`mercadopago.service.ts`)
**Ubicación:** `src/mercadopago/mercadopago.service.ts`

### Generación de Código QR
- Método: `generateQrCode(orderId)`
  - Genera PNG en memoria (`QRCode.toDataURL`) → buffer → sube a `orders/qr_<orderId>.png` con `upsert: true`.
  - Obtiene URL pública y la devuelve.

### Observaciones
- No hay expiración / limpieza programada de QR antiguos.
- Recomendado: almacenar TTL o campo `created_at` y job de limpieza.

---
## 6. Otros hallazgos (Actualizados)
- Validación central de tipo/dimensiones implementada parcialmente (solo vía nuevo camino con `ImageService`). Flujos legacy aún sin límites de tamaño explícitos.
- Bucket único `product-images` continúa para TODO (recomendación de segmentar vigente).
- Hashing de contenido ahora sí se usa implícitamente (nombres basados en hash) → reduce duplicados.
- Eliminación de productos y variantes aún no unificada (riesgo persistente en legacy y limpieza incompleta en variantes).
- Sin tests automatizados que cubran: generación de variantes, idempotencia de uploads, selección de imagen principal.

---
## 7. Riesgos Transversales (Re-evaluados)
| Riesgo | Estado | Impacto | Mitigación Propuesta |
|--------|--------|---------|----------------------|
| Validación tipo/dimensiones incompleta en legacy | Parcialmente mitigado (nuevo flujo OK) | Seguridad / costo | Unificar todos los endpoints a `ImageService` + límites Multer |
| Limpieza de variantes históricas | Persistente | Storage cost | Implementar GC que recorra image_variants y compare con Storage |
| Bucket monolítico | Persistente | Políticas/granularidad | Segmentar por dominio lógico (products, banners, services, logos, qr) |
| Eliminación basada en `split('/')` | Persistente en legacy | Fugas / fallos delete | Guardar siempre `file_path` y usarlo para remover todas las variantes |
| Race orden banners | Persistente | Orden inconsistente | Transacción + lock fila counter / secuencia dedicada |
| Falta de tests de pipeline | Nuevo riesgo | Regressions silenciosas | Añadir unit + e2e para `ImageService` y endpoints |
| Faltan índices sobre consultas futuras a `image_variants` | Latente | Rendimiento potencial | Agregar GIN condicional cuando se consulten atributos internos |

---
## 8. Recomendaciones Técnicas (Actualizadas / Priorizadas)
1. Unificar TODOS los puntos de subida legacy para que llamen a `ImageService` (eliminar lógica duplicada).
2. Incluir `file_path` de cada variante y principal en DB donde falte (products legacy array).
3. Refactor delete (products, banners, services, logos) para borrar TODAS las variantes listadas en JSONB, no solo principal.
4. Añadir límites Multer globales (ej: 2–3 MB) y whitelist de mimetypes en middleware común.
5. Implementar GC (cron) de imágenes huérfanas: (a) listar objetos bucket, (b) construir set de claves válidas desde DB (`image_variants.*.key`), (c) eliminar sobrantes.
6. Segmentar buckets o, mínimo, aplicar prefijos fuertes y políticas de cache diferenciadas (CDN headers por tipo).
7. Exponer en API metadata (width, height, bytes) ya calculada para que el frontend pueda elegir variante óptima (LCP performance).
8. Agregar índice GIN opcional cuando surja una query que filtre por campos internos (esperar evidencia de necesidad).
9. Tests: unit `ImageService` (generación de variantes, mime inválido) + e2e endpoint `/products/:id/image` (status, estructura JSONB persistida).
10. Script backfill para productos legacy (reutilizar snippet en migración) y cleanup de endpoints antiguos tras adopción frontend.

---
## 9. Checklist Evolución (Estado)
- [x] Optimización y generación de variantes (AVIF/WebP) automática para products, banners, services, logos.
- [x] Servicio central (`ImageService`) para procesar y subir variantes.
- [ ] Unificar endpoints legacy de products (arrays) al nuevo flujo.
- [ ] Añadir validación mimetype / tamaño en todos los endpoints legacy.
- [ ] Extender `products.imageUrl` (array legacy) para incluir `file_path` y plan de deprecación.
- [ ] Refactor eliminación (todas las entidades) usando claves de `image_variants`.
- [ ] GC huérfanos (cron) + logging/auditoría.
- [ ] Segmentar buckets o reforzar prefijos y políticas.
- [ ] Tests unitarios `ImageService` y e2e endpoints de imagen.
- [ ] Backfill `image_variants` para productos antiguos (snippet en migración) si el frontend lo requiere.
- [ ] Migrar QR a bucket dedicado con TTL.
- [ ] Índice GIN (solo si aparecen queries internas sobre JSONB).

---
## 10. Resumen Ejecutivo (Actualizado)
Se avanzó de un esquema disperso y sin validaciones a un pipeline centralizado que genera variantes optimizadas (AVIF/WebP) con nombres hash y metadatos básicos. La columna `image_variants` habilita estrategias responsive y futuras mejoras (LCP, bandwidth). Aún resta consolidar la migración completa de flujos legacy, robustecer eliminación y limpieza de huérfanos, y formalizar métricas/tests para prevenir regresiones. Priorizar unificación de endpoints y GC asegurará control de costos y simplicidad operativa.

---
Documento generado automáticamente.

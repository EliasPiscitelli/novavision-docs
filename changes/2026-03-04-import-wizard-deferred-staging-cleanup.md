# Cambio: Fix import wizard — retry duplica productos y pierde imágenes

- Autor: agente-copilot
- Fecha: 2026-03-04
- Rama: feature/automatic-multiclient-onboarding
- Archivos:
  - `apps/api/src/import-wizard/import-wizard.worker.ts`
  - `apps/api/src/import-wizard/import-wizard.service.ts`

## Resumen

Se corrigieron múltiples bugs en el flujo de retry del import-wizard que causaban:

1. **Staging files eliminados prematuramente**: Los archivos staging se borraban del storage **antes** de confirmar que el `imageUrl` se guardó → en reintentos las imágenes se perdían.
2. **`result_product_id` no persistido tempranamente**: Si creación de producto exitosa pero categorías/imágenes fallaban, el ID no se guardaba.
3. **`retryFailedItems` borraba orphans y limpiaba `result_product_id`**: Esto hacía que el worker no pudiera encontrar productos ya creados → INSERT creaba duplicados, e imágenes ya procesadas se perdían junto con el producto borrado.
4. **Sin fallback por SKU**: Si `result_product_id` no estaba disponible, no había forma de detectar que el producto ya existía → duplicados con SKU auto-renombrado (`SKU-2`).

## Causa raíz

### Bug 1 — Staging cleanup prematuro
1. **Primera ejecución del batch**: Staging files descargados, procesados a webp/avif, y eliminados inmediatamente dentro del loop. Imágenes subidas bajo product IDs originales.
2. **Cleanup de Phase 24**: Productos duplicados eliminados (IDs originales ya no existen).
3. **Retry post-Phase 24**: Worker creó nuevos productos con nuevos UUIDs. Al intentar procesar imágenes, los staging files ya estaban eliminados → downloads fallaron silenciosamente → `processedImages` vacío → `imageUrl` nunca actualizado.

### Bug 2 — `result_product_id` perdido en fallo parcial
1. En `processItem`, `result_product_id` solo se guardaba al final del flujo exitoso (después de producto + categorías + imágenes).
2. Si el producto se creaba pero las categorías o imágenes fallaban → `result_product_id` nunca persistido en DB.
3. Además, el catch block en `processBatch` seteaba `result_product_id: null`, borrando cualquier referencia guardada.
4. `retryFailedItems` consulta `result_product_id` para limpiar huérfanos → sin ese dato, crea duplicados.

## Cambios

### Fix 1: `processItemImages` — Deferred staging cleanup

1. **Deferred staging cleanup**: Los staging files ya NO se eliminan dentro del loop de procesamiento. Se acumulan en `stagingPathsToCleanup` y se eliminan DESPUÉS de confirmar que el `imageUrl` del producto se actualizó correctamente.

2. **Error handling en imageUrl update**: Se agrega manejo de error para el UPDATE del producto. Si falla, los staging files se preservan para un retry posterior.

3. **Warning mejorado**: Cuando 0 de N imágenes staged producen resultados (ej: staging files ya consumidos), se loguea un warning descriptivo.

4. **Fix select column name**: Se corrigió `.select('"imageUrl"')` a `.select('imageUrl')` (sin comillas dobles internas).

5. **Logging de éxito**: Se agrega log informativo cuando las imágenes se guardan exitosamente.

### Fix 2: `processItem` + `processBatch` — Early `result_product_id` persistence

1. **Early save**: Inmediatamente después de crear/actualizar el producto (INSERT o UPDATE), se persiste `result_product_id` en `import_batch_items` ANTES de procesar categorías e imágenes.

2. **Catch block preserva referencia**: Se eliminó `result_product_id: null` del update en el catch block de `processBatch`. Solo se setea `process_status: 'failed'` y `process_error`.

### Fix 3: `retryFailedItems` — Reuse-first strategy (NO delete orphans)

**Cambio de filosofía**: En vez de "borrar orphan + crear de nuevo", el retry ahora "**reusa y completa**":

1. **Eliminado orphan cleanup completo**: Ya no se borran productos de la tabla `products` ni `product_categories` durante retry. Los productos parcialmente creados se preservan.

2. **`result_product_id` preservado**: Ya NO se setea `result_product_id: null` en el reset. El worker usa esta referencia para encontrar y UPDATE el producto existente en lugar de INSERT uno nuevo.

3. **Solo se resetea status y error**: Cada item queda con `process_status: 'pending'`, `process_error: null`, payload limpio, pero conservando `result_product_id`.

### Fix 4: `processItem` — SKU-based fallback + skip images si ya existen

1. **Lookup por SKU**: Si `result_product_id` es null o apunta a un producto que ya no existe, se busca el producto por SKU + `client_id`. Si se encuentra, se reutiliza (UPDATE en vez de INSERT).

2. **Skip imágenes si ya existen**: Antes de procesar staging images, se verifica si el producto ya tiene `imageUrl` con imágenes. Si ya las tiene (de un run anterior), se salta el procesamiento de staging. Esto evita el problema de staging files ya consumidos.

## Recuperación de datos

Se ejecutó un script SQL one-time para recuperar 16 imágenes procesadas que estaban en storage bajo product IDs viejos (eliminados) y asociarlas a los productos nuevos:

| Producto | Imágenes recuperadas |
|----------|---------------------|
| Paracetamol 500mg | 3 |
| Ibuprofeno 400mg | 2 |
| Antiácido menta | 1 |
| Jarabe tos | 2 |
| Alcohol gel | 2 |
| Apósitos | 2 |
| Protector solar | 2 |
| Crema humectante | 2 |

## Cómo probar

### Fix 1 — Staging cleanup
1. Crear un batch de importación con imágenes
2. Procesar el batch (queued → processing → completed)
3. Verificar que los productos tengan `imageUrl` con las imágenes procesadas

### Fix 2 — Early result_product_id
1. Crear un batch con un item que tenga categorías inválidas (forzar fallo parcial)
2. Verificar que `result_product_id` se persiste en `import_batch_items` aunque el item falle

### Fix 3+4 — Retry sin duplicados ni pérdida de imágenes
1. Procesar un batch → obtener productos con imágenes
2. Marcar algunos items como 'failed' manualmente
3. Llamar a `retry-failed`
4. Verificar:
   - NO se crean productos nuevos — los existentes se actualizan (UPDATE)
   - Las imágenes ya existentes se preservan (no se re-procesan staging files)
   - Los logs dicen "reusing existing product" (por result_product_id o SKU)
   - NO aparecen productos con SKU `-2`, `-3`

### Validación
- 3 suites de tests: 88/88 passing
- `npm run lint` → 0 errores
- `npm run typecheck` → sin errores
- `npm run build` → exitoso

## Notas de seguridad

- No se exponen credenciales
- Los cambios son scope al worker de import-wizard
- No hay impacto en multi-tenant (client_id siempre filtrado)

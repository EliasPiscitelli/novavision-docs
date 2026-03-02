# Cambio: Import Wizard — Retry-safe product reuse + orphan cleanup fix

- **Autor:** agente-copilot
- **Fecha:** 2026-03-02
- **Rama:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `apps/api/src/import-wizard/import-wizard.worker.ts`
  - `apps/api/src/import-wizard/import-wizard.service.ts`

---

## Resumen

Se corrigieron dos bugs críticos en el flujo de retry del Import Wizard que causaban:
1. **Duplicación de productos** en cada reintento
2. **Eliminación accidental de productos legítimos** durante la limpieza de huérfanos

## Bug 1 — `processItem` no reutilizaba productos existentes en retry

### Problema
Cuando un item del batch fallaba parcialmente (el producto se creaba pero las categorías o imágenes fallaban), el `result_product_id` quedaba apuntando al producto existente. Sin embargo, al reintentar, `processItem` siempre generaba un nuevo UUID y hacía INSERT, ignorando el producto ya creado. Esto causaba:

- Error de SKU duplicado (el producto anterior seguía existiendo con ese SKU)
- Si `insertWithUniqueSku` asignaba un sufijo nuevo, se creaba OTRO producto con el mismo nombre pero SKU diferente

### Solución
En `processItem`, se agregó verificación al inicio del path "create": si `item.result_product_id` está presente y el producto existe en la DB, se reutiliza (UPDATE) en vez de crear uno nuevo (INSERT). También se limpia product_categories previas al reasignar.

## Bug 2 — Orphan cleanup por SKU eliminaba productos legítimos

### Problema
`retryFailedItems` tenía una limpieza de huérfanos "2-prong": por `result_product_id` Y por SKU. La rama de SKU buscaba CUALQUIER producto del tenant con SKU coincidente, no solo los creados por el batch. Esto borró productos legítimos que coincidían en SKU con items del batch.

### Solución
Se eliminó la limpieza por SKU (demasiado agresiva). Se mantiene solo la limpieza por `result_product_id`, que es segura y scoped al batch. Con el fix del Bug 1, los `result_product_id` se mantienen correctamente, eliminando la necesidad del fallback por SKU.

## Limpieza de datos (DB)

Se eliminaron 4 productos huérfanos duplicados por nombre:
- `d7d82a77` (ANTIAC-MEN-5) — huérfano no referenciado por batch items
- `afd3f22d` (CREMA-HUM-400-4) — huérfano no referenciado por batch items
- `438bd10a` (PARA-500-3) — huérfano no referenciado por batch items
- `728a868f` (SOLAR-FPS50-4) — huérfano no referenciado por batch items

Resultado: 19 productos, 0 duplicados por nombre.

## Cómo probar

1. Crear un lote de importación con productos nuevos
2. Forzar fallo parcial (ej: imagen inválida) para que el producto se cree pero el item quede "failed"
3. Reintentar el lote → debe reutilizar el producto existente (UPDATE) en vez de crear uno nuevo
4. Verificar que no se crearon duplicados ni se eliminaron productos legítimos
5. Logs del worker deben mostrar: `"Item {id}: reusing existing product {productId} from previous attempt"`

## Riesgo

- **Bajo.** El fix reduce el impacto del retry (UPDATE en vez de INSERT). El orphan cleanup queda más conservador (solo borra productos explícitamente rastreados por el batch).
- Si un producto huérfano no tiene `result_product_id` rastreado, no será limpiado automáticamente. Esto es preferible a borrar productos legítimos.

## Validación

```bash
npm run lint    # 0 errores (solo warnings)
npm run typecheck  # OK
npm run build      # OK
```

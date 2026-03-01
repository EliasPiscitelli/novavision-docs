# Cambio: Validación de nombre duplicado en Import Wizard + limpieza DB

- **Autor:** agente-copilot
- **Fecha:** 2026-03-02
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** develop → cherry-pick a feature/multitenant-storefront

## Archivos modificados

### Backend (API)
- `src/import-wizard/import-wizard.service.ts` — nuevo método `loadExistingNames()`, se pasa `existingNames` a `validateBatchCross`
- `src/import-wizard/import-wizard.validators.ts` — nuevo parámetro `existingNames` en `validateBatchCross`, nuevos códigos `NAME_EXISTS` y `DUPLICATE_NAME_IN_BATCH`

### Frontend (Web)
- `src/components/admin/ImportWizard/index.jsx` — banner de alerta por nombres duplicados, ícono ⚠️ en fila, botón "Omitir duplicado" en detalle expandido

### Base de datos
- Limpieza directa: eliminados 29 productos duplicados (de 48 → 19 únicos) para client `1fad8213-1d2f-46bb-bae2-24ceb4377c8a`

## Resumen del cambio

### Problema
Los productos se importaban repetidamente sin validación de nombre, generando duplicados (mismo nombre, distintos SKUs auto-generados). El cliente Farma terminó con 48 productos cuando solo debería tener 19.

### Solución

1. **Validación backend (`validateBatchCross`)**:
   - `NAME_EXISTS` (warning): detecta si ya existe un producto con el mismo nombre en la DB del tenant. Solo aplica a action `create`.
   - `DUPLICATE_NAME_IN_BATCH` (warning): detecta nombres duplicados dentro del mismo lote.
   - Ambos son **warnings** (no errors), permitiendo al usuario decidir si importar o no.

2. **UI frontend (Review step)**:
   - Banner amarillo de alerta cuando hay nombres duplicados
   - Ícono ⚠️ junto al nombre del producto duplicado
   - Botón "Omitir duplicado" en el detalle expandido de cada error de nombre, que elimina el item del lote

3. **Limpieza DB**:
   - Eliminados 29 productos duplicados (+ 32 product_categories huérfanos)
   - Se mantuvo el más reciente por nombre (DISTINCT ON name ORDER BY created_at DESC)

## Por qué

El usuario importó el mismo set de productos múltiples veces durante testing. El auto-SKU generaba SKUs sufijados (-2, -3, -4) evitando el constraint único de SKU, pero creando productos con nombres idénticos. Sin validación de nombre, no había forma de detectar ni prevenir esto.

## Cómo probar

1. Levantar API (`npm run start:dev`) + Web (`npm run dev`)
2. Ir al Import Wizard, subir un JSON con productos que ya existen por nombre
3. En el paso de Revisión: debe aparecer banner amarillo, ícono ⚠️ en cada duplicado
4. Expandir detalle → ver warning `NAME_EXISTS` con botón "Omitir duplicado"
5. Click "Omitir duplicado" → elimina el item del lote
6. Si se deja el duplicado y se encola → se importa normalmente (es un warning, no bloquea)

## Notas de seguridad

- `loadExistingNames` filtra por `client_id` (aislamiento multi-tenant)
- La limpieza de DB fue por transacción atómica con cleanup de FKs (product_categories, order_items, cart_items, favorites)

# Cambio: Reviews solo compradores + Filtros opciones usadas + PDP opciones + Rating badge real

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama API:** feature/automatic-multiclient-onboarding (commit `67f7d89`)
- **Rama Web:** feature/multitenant-storefront (commit `48aa1e4`), cherry-pick a develop (`6f533e9`)

## Archivos modificados

### API (templatetwobe)
- `src/products/products.service.ts` — `getAvailableFilters()`
- `src/reviews/reviews.service.ts` — `createReview()`
- `migrations/20260218_review_aggregates_count_all.sql` (nueva)

### Web (templatetwo)
- `src/pages/ProductPage/index.jsx` — PDP opciones + rating badge
- `src/components/product/ProductReviews.jsx` — form solo compradores (solo storefront)

## Resumen de cambios

### 1. Reviews solo para compradores verificados
- **Backend:** `createReview()` ahora lanza `ForbiddenException` si el usuario no compró el producto. Antes solo marcaba `verified_purchase` como flag cosmético.
- **Frontend:** El formulario de review ahora usa `userReview.can_review` del API:
  - No logueado → "Iniciá sesión para dejar tu opinión"
  - Ya dejó review → "¡Gracias! Ya dejaste una review"
  - `can_review === true` → muestra formulario
  - No compró → "Comprá este producto para poder dejar tu opinión"

### 2. Rating persiste aunque admin oculte review
- **Migración SQL:** Trigger `update_review_aggregates()` ya NO filtra por `moderation_status = 'published'`. El rating de un review oculto sigue contando en el promedio del producto.
- **Migración ejecutada en:** BACKEND_DB (multicliente)

### 3. Filtros de búsqueda: solo opciones usadas
- `getAvailableFilters()` ahora cruza `selected_item_ids` de todos los productos con sus `option_set_items`. Solo muestra opciones realmente seleccionadas por al menos un producto.
- Option sets sin items usados se excluyen.

### 4. PDP: opciones se renderizan sin depender de option_mode
- Eliminada la condición `data.option_mode === 'option_set'`. Ahora usa `resolved_options.source === 'option_set'` que el backend calcula correctamente.
- Size guide también se muestra si existe `option_set_id`, sin requerir `option_mode`.

### 5. Rating badge con datos reales
- `socialProof` se obtiene de `GET /products/:id/social-proof`.
- Badge solo visible cuando `avg_rating >= 3.0 AND review_count > 0`.
- Pluralización correcta: "opinión" vs "opiniones".

## Por qué
- Reviews abiertas a cualquiera generarían datos falsos y manipulación de ratings.
- Filtros mostraban opciones que ningún producto tenía asignado.
- PDP no mostraba opciones si el admin no había seteado `option_mode` explícitamente.
- Rating badge hardcodeado a 4.8 (0 opiniones) era engañoso.

## Cómo probar
1. **Reviews:** Loguearse como usuario sin compra → no debe verse el formulario, solo "Comprá para opinar". Con compra verificada → muestra form.
2. **Admin moderation:** Desde admin, ocultar una review → el texto desaparece del listado público pero el rating promedio del producto no cambia.
3. **Filtros:** Ir a búsqueda/PLP → los filtros de opciones solo muestran valores usados por productos activos.
4. **PDP opciones:** Abrir un producto con option_set configurado → las opciones (talles, colores) deben renderizarse.
5. **Rating badge:** Solo aparece si hay al menos 1 review con avg >= 3.0.

## Notas de seguridad
- La validación de compra es doble: backend (`ForbiddenException`) + frontend (oculta form).
- El trigger SQL sigue siendo `SECURITY DEFINER` (sin cambio de privilegios).

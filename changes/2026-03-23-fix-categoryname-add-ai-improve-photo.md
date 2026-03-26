# Fix categoryName 404 + AI Improve include_photo

**Fecha:** 2026-03-23
**Apps:** API, Web
**Ramas:** API `feature/automatic-multiclient-onboarding`, Web `develop` → cherry-pick a ambas prod

## Bug fix: categoryName inexistente en tabla products

### Problema
Todas las queries de IA a la tabla `products` usaban `.select('... categoryName ...')`, pero esa columna **no existe**. La columna real es `categories` (vacía) y los nombres de categoría vienen de `product_categories` JOIN `categories`.

PostgREST retornaba error PGRST204 (column not found), que el servicio capturaba como `if (error || !product)` y lanzaba un genérico `NotFoundException("Product X not found")`.

### Solución
- Agregados helpers `resolveProductCategoryNames()` y `resolveBatchCategoryNames()` en `ai-generation.service.ts`
- Consultan `product_categories → categories(name)` via Supabase relationships (FK existentes)
- Arreglados 4 métodos: `generateProductDescription`, `generateFaqsForProducts`, `aiProductImprove`, `generatePhotoForProduct`
- Category name se resuelve en paralelo con `storeDNA` via `Promise.all`

## Feature: include_photo en ai-improve

### Backend (API)
- `POST /products/:id/ai-improve` ahora acepta `include_photo` y `photo_style` en el body
- Cuando `include_photo=true`: valida créditos de `ai_photo_product`, genera imagen marketing con `callOpenAIImageGeneration`, sube a temp storage, consume crédito extra
- Respuesta incluye `photo: { temp_url, temp_key }` cuando se genera foto

### Frontend (Web)
- Nuevo checkbox "Incluir foto e-commerce (+X cr)" debajo del botón "Mejorar con IA" en ProductModal
- Handler envía `include_photo` al backend, captura `temp_url` de la foto
- `AiProductFillPreview` ahora recibe `photoUrl` en modo "improve"
- `handleAcceptAiImprove` agrega la foto a la galería del producto

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `apps/api/src/ai-generation/ai-generation.service.ts` | Helpers de categoría + includePhoto en aiProductImprove |
| `apps/api/src/ai-generation/ai-generation.controller.ts` | include_photo handling + photo upload + credit consumption |
| `apps/web/src/components/ProductModal/index.jsx` | Toggle checkbox + photo handling en improve flow |

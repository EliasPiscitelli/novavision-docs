# AI Photo Auto-Save en todos los endpoints + SEO Settings Dedup

**Fecha:** 2026-03-27
**Apps:** API, Web

## Cambios

### API (`apps/api`)
- **ai-fill, ai-improve, ai-from-photo**: Migrados de almacenamiento temporal (`clientId/temp/...`) a guardado permanente en `tenant_media` con variantes procesadas por `imageService.processAndUpload()`
- **ai-photo (producto existente)**: Agregado `rebuildProductImages()` después de insertar en `product_media` para que las fotos aparezcan inmediatamente en el storefront
- **MediaLibraryModule**: Importado en `AiGenerationModule` para inyectar `MediaLibraryService`
- **Tests**: Mock de `MediaLibraryService` agregado en `ai-generation.e2e.spec.ts` y `ai-jobs.e2e.spec.ts`

### Web (`apps/web`)
- **ProductModal**: Consume `public_url`/`media_id` en vez de `temp_url`/`temp_key` para ai-fill, ai-improve, ai-from-photo
- **ProductModal UX**: Overlay AI full-modal, filtros/material opcionales, presets de peso (25g-1kg)
- **useSeoSettings**: Cache singleton a nivel de módulo — elimina spam de requests a `/seo/settings` (de ~9 requests por navegación a 1 por sesión)
- Cherry-pick a `feature/multitenant-storefront` y `feature/onboarding-preview-stable`

## Impacto
- Las fotos AI generadas ahora aparecen inmediatamente en el Banco de Imágenes
- Al vincular fotos AI a productos, aparecen correctamente en cards, PDP y search del storefront
- Reducción significativa de requests HTTP en el storefront (eliminado spam de `/seo/settings`)

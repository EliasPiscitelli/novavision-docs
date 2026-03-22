# AI Brand Colors — Mejora de Calidad de Imágenes IA

**Fecha:** 2026-03-22
**Tipo:** Feature
**Impacto:** API (ai-credits, ai-generation)

## Resumen

Las imágenes generadas por IA (banners, fotos de producto, logos) ahora respetan la paleta de colores real de la tienda. Se resuelve `palette_key → hex colors` desde `palette_catalog.preview` y se inyectan colores concretos en cada prompt de generación de imagen.

## Problema

- `Store DNA` recopilaba `palette_key` como string pero nunca resolvía los colores hex reales
- Los prompt builders usaban style maps genéricos ("gradient colors") sin colores concretos
- Resultado: imágenes genéricas, clipart, desconectadas de la identidad visual de la tienda

## Cambios

### `store-context.service.ts`

- **Nuevo type** `BrandColors`: primary, accent, background, text, surface, font
- **Nuevo campo** `brand_colors: BrandColors | null` en `StoreContext`
- **Resolución palette**: `palette_key` → `palette_catalog.preview` (Admin DB) → 6 tokens hex
- **Método público** `getBrandColors(clientId, accountId)`: primero intenta cache DNA, luego resuelve directo
- **DNA prompt actualizado**: incluye colores de marca y tipografía en el user message + identidad visual en system prompt

### `prompts/index.ts`

- `BannerPromptInput.brandColors`: inyecta hex codes como "brand guideline constraint, not a suggestion"
- `ProductPhotoInput.brandColors`: agrega contexto de marca para props/backgrounds/accents
- **BANNER_STYLE_MAP reescrito completo**: de frases genéricas ("geometric shapes, gradient colors") a dirección artística real ("contemporary editorial design... think Apple or Shopify hero sections")
- **PHOTO_STYLE_MAP reescrito completo**: de descripciones básicas a lenguaje de fotografía comercial real ("shallow depth of field f/2.8, hero shot, medium format camera")
- **Requirements de banner**: "Must look like it was produced by a creative agency, NOT generic stock imagery"
- **Requirements de foto**: "8K quality, professional commercial e-commerce photography, NOT a 3D render, NOT stock photo"

### `prompts/logo-generate.ts`

- `buildLogoPrompt` acepta `brandColors`: inyecta colores primario/acento como restricción de marca
- **LOGO_STYLE_MAP reescrito completo**: referencias concretas a identidades de marca reales ("Think Stripe, Notion, or Linear", "Think Chanel, Aesop")
- **Requirements mejorados**: "Single cohesive symbol, vector-clean edges, scalable from favicon to billboard"

### `ai-generation.service.ts`

- 5 métodos actualizados: `generateBanner`, `generateProductPhoto`, `generatePhotoFromContent`, `generateLogo`, `aiProductFill`
- Cada uno resuelve `brandColors` en paralelo con `storeDNA` via `Promise.all`

### `ai-generation.service.spec.ts`

- Mock de `getBrandColors` agregado al mock de `StoreContextService`

## Fallback

- Tiendas sin paleta configurada → `brandColors = null` → prompts funcionan exactamente como antes
- Cache DNA existente sin `brand_colors` → se resuelve directo desde DB → se incluirá en próxima regeneración de DNA (TTL 24h)

## Verificación

- `npm run typecheck` → OK
- `npm run build` → OK
- `npm run test` (ai-generation) → 72/72 tests passing

# AI Image Features — Backend

**Fecha:** 2026-03-18
**Repo:** API (`@nv/api`)
**Branch:** `feature/automatic-multiclient-onboarding`

## Resumen

Implementación de 4 endpoints de generación de imágenes IA + 1 endpoint de confirmación, extendiendo el sistema de AI Credits existente.

## Endpoints nuevos

| Método | Ruta | Propósito | Action Code |
|--------|------|-----------|-------------|
| POST | `/products/ai-fill` | Descripción + foto opcional | `ai_product_description` + `ai_photo_product` |
| POST | `/products/:id/ai-photo` | Generar imagen de producto | `ai_photo_product` |
| POST | `/products/ai-from-photo` | Vision: foto real → ficha completa | `ai_photo_product` |
| POST | `/banners/ai-generate` | Banner IA | `ai_banner_generation` |
| POST | `/products/:id/confirm-ai-image` | Confirmar imagen temporal | Sin créditos |

## Archivos modificados

- `src/ai-credits/ai-credits.service.ts` — +1 action code (`ai_banner_generation`)
- `src/common/utils/upload-filters.ts` — +`visionImageFileFilter` (JPEG, PNG, WebP, HEIC/HEIF)
- `src/ai-generation/prompts/index.ts` — +3 prompt builders (photo, banner, vision) + tipos
- `src/ai-generation/ai-generation.service.ts` — +6 métodos privados + 4 métodos públicos + generating locks
- `src/ai-generation/ai-generation.controller.ts` — +5 endpoints
- `src/ai-generation/ai-generation.module.ts` — +4 imports (ImageProcessing, Storage, Plans, Supabase)
- `src/ai-generation/ai-generation.service.spec.ts` — 46 tests (14 originales + 32 nuevos)
- `test/ai-generation.e2e.spec.ts` — 26 tests (10 originales + 16 nuevos)

## Archivos creados

- `src/ai-generation/dto/ai-fill.dto.ts`
- `src/ai-generation/dto/ai-photo.dto.ts`
- `src/ai-generation/dto/ai-banner.dto.ts`
- `src/ai-generation/dto/confirm-image.dto.ts`
- `src/ai-generation/ai-temp-cleanup.service.ts` — Cron cada 30min, limpia `/temp/` >2h

## Decisiones técnicas

- **Generating locks in-memory** con TTL 60s para evitar generaciones duplicadas
- **Discriminated returns** (`{ buffer }` | `{ error, errorCode }`) para no consumir créditos en fallo
- **compressAiBuffer** reduce a <2MB antes de pasar a ImageService (hard limit línea 48)
- **Graceful degradation** en ai-fill: si foto falla, retorna solo descripción
- **Multi-tenant security** en confirm: valida que `temp_key` empiece con `{clientId}/temp/`
- **NON_RETRYABLE_ERRORS**: `content_policy_violation`, `billing_hard_limit_exceeded` no reintentan

## Tests

- **72 tests totales** (46 unit + 26 E2E) — todos pasando
- Build exitoso, 0 errores TypeScript, 0 errores lint

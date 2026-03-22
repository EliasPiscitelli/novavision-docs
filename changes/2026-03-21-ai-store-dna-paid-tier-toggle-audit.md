# Store DNA pago con tiers + Auditoría AiTierToggle

**Fecha:** 2026-03-21
**Repos:** API, Web
**Rama:** develop

## Resumen

Store DNA regeneration pasa de feature gratuita a feature paga con soporte Normal/Pro (gpt-4o-mini vs gpt-4o). Se corrige bug de AiTierToggle en Footer Links y se auditan los 14 puntos de consumo IA.

## Cambios

### Backend (API)

#### Migración SQL (`migrations/admin/20260321_ai_store_dna_pricing.sql`)
- `ai_feature_pricing`: 2 rows — normal (1 crédito, gpt-4o-mini) y pro (2 créditos, gpt-4o)
- `ai_welcome_credit_config`: starter=1, growth=3, enterprise=5 créditos de bienvenida
- `addon_catalog`: 2 packs comprables — `ai_dna_pack_5` ($14.90) y `ai_dna_pack_15` ($29.90)
- Migración idempotente (ON CONFLICT en las 3 tablas)
- Ejecutada en Admin DB en producción

#### `ai-credits.service.ts`
- Agregado `'ai_store_dna'` a `AI_ACTION_CODES` (ahora 7 action codes)
- `getAllAiBalances` y `getCreditHistory` incluyen automáticamente el nuevo code

#### `ai-credits.controller.ts`
- Endpoint `POST /ai-credits/store-dna/regenerate`:
  - Agregado `AiCreditsGuard` + `@RequireAiCredits('ai_store_dna')`
  - Resuelve `modelId` desde `req.aiPricing.model_id`
  - Llama `consumeCredit()` tras generación exitosa
  - Retorna `credits_consumed` y `tier` en response
  - Pasa `throwOnError=true` para no cobrar si OpenAI falla

#### `store-context.service.ts`
- `generateStoreDNA()` ahora acepta `throwOnError` (default: `false`)
- Path pago (regeneración manual): propaga error → no se cobra
- Path gratuito (provisioning): fallback silencioso → tienda no se queda sin contexto

#### `ai-credits.service.spec.ts`
- Actualizado `toHaveLength(6)` → `toHaveLength(7)` para reflejar nuevo action code
- 49/49 tests pasan

### Frontend (Web)

#### `IdentityConfigSection/index.jsx`
- **Nuevo Card:** "🧠 Contexto de tienda (Store DNA)" en tab footer
  - `AiButton` con `balance={getBalance('ai_store_dna')}`
  - `AiTierToggle` con `actionCode="ai_store_dna"`
  - Función `handleRegenerateStoreDNA()` con `{ ai_tier }` en body
  - Hint explicativo sobre regeneración automática cada 24hs
- **Fix AiTierToggle Footer Links:** `tier`/`onChange` → `actionCode="ai_faq_generation"` / `onSelect` / `disabled`

### Auditoría AiTierToggle (14 instancias verificadas)

| Componente | Estado |
|------------|--------|
| ReviewsDashboard | OK |
| ServiceSection (crear/mejorar) | OK |
| BannerSection | OK |
| LogoSection | OK |
| QADashboard | OK |
| FaqSection (generar/mejorar) | OK |
| ProductModal (5 ops) | OK |
| AiCatalogWizard | OK |
| ImportWizard | OK |
| IdentityConfig (Store DNA) | OK (nuevo) |
| IdentityConfig (footer links) | OK (corregido) |

## Notas técnicas

- La generación inicial durante provisioning sigue gratuita (llama `generateStoreDNA()` directamente sin guard)
- El guard valida tier estrictamente: solo acepta `'normal'` o `'pro'` (HTTP 400 para otros valores)
- El interceptor global 402 maneja créditos insuficientes en el frontend
- Los packs se integran automáticamente al Addon Store vía `family='ai'` + `commercial_model='consumable_action'`

## Verificación

- [x] API build OK
- [x] Web build OK
- [x] Migración ejecutada en Admin DB
- [x] Idempotencia verificada (re-run sin errores)
- [x] 49/49 tests pasan (unit + e2e)
- [x] QA audit: 24/24 checks pass

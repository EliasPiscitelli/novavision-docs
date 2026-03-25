# Sprint 3 AI Pro — M7 + M8

**Fecha:** 2026-03-25
**Plan:** `PLAN_AI_PRO.md` Sprint 3
**Estado:** Implementado

---

## M7: AnthropicProvider para AI general (tier Pro)

### Problema
Todas las features de AI text (descripciones, FAQs, Q&A, catálogos, CSS, etc.) usaban exclusivamente OpenAI, incluso en tier Pro. No había forma de usar modelos Anthropic para mejor calidad en español.

### Solución
1. **Dual provider en `callOpenAI()`**: Detecta si `model_id` empieza con `claude-` y rutea automáticamente a Anthropic SDK.
2. **Anthropic client** inicializado en constructor vía `ANTHROPIC_API_KEY` (ConfigService).
3. **Fallback**: Si Anthropic falla tras reintentos → fallback a OpenAI `gpt-4o-mini`.
4. **JSON handling**: Strip de markdown code blocks en respuestas Anthropic (mismo patrón que SeoAiService).
5. **Migración**: 8 filas Pro de texto en `ai_feature_pricing` cambiadas de `gpt-4o` a `claude-sonnet-4-6`. Las 2 filas de imagen (`gpt-image-1`) no se tocaron.

### Archivos modificados
- `api/src/ai-generation/ai-generation.service.ts` — import Anthropic, constructor con ConfigService, métodos `callAnthropic()` y `callOpenAIProvider()`
- `api/src/ai-generation/ai-generation.service.spec.ts` — mock ConfigService
- `api/migrations/admin/20260325_m7_ai_pro_anthropic.sql`

---

## M8: Cost tracking USD por invocación AI

### Problema
No había tracking del costo real en USD de cada invocación AI. Los créditos son una abstracción para el cliente, pero el negocio necesita saber cuánto cuesta cada operación.

### Solución
1. **Columnas nuevas en ledger**: `cost_usd` (numeric 10,6), `tokens_input` (int), `tokens_output` (int) en `account_action_credit_ledger`.
2. **Token tracking**: `callOpenAI()` y `callAnthropic()` guardan tokens reales en `_lastUsage` (input, output, modelId).
3. **Tabla de precios USD**: `MODEL_USD_PRICING` con rates por 1M tokens para gpt-4o-mini, gpt-4o, claude-sonnet-4-6, claude-haiku-4-5.
4. **Cálculo automático**: `calculateCostUsd()` exportada, usada por `getCostParams()` en el controller.
5. **19 endpoints actualizados**: Todos los `consumeCredit()` en `ai-generation.controller.ts` ahora pasan `...this.getCostParams()`.
6. **Índice para reporting**: `idx_ledger_cost_by_action` para queries eficientes del super-admin.

### Fórmula
```
cost_usd = (input_tokens × input_price_per_1M / 1_000_000) + (output_tokens × output_price_per_1M / 1_000_000)
```

### Archivos modificados
- `api/src/ai-generation/ai-generation.service.ts` — `AiCallResult`, `MODEL_USD_PRICING`, `calculateCostUsd()`, `_lastUsage` getter
- `api/src/ai-generation/ai-generation.controller.ts` — `getCostParams()` helper, 19 `consumeCredit` calls actualizados
- `api/src/ai-credits/ai-credits.service.ts` — `consumeCredit` acepta `tokensInput`, `tokensOutput`, `costUsd`
- `api/migrations/admin/20260325_m8_cost_usd_tracking.sql`

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 123/123 (ai-generation + ai-credits suites) OK

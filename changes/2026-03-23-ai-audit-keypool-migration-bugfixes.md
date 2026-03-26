# Auditoría AI completa: Key Pool migration + bugfixes críticos

**Fecha:** 2026-03-23
**Apps:** API
**Rama:** `feature/automatic-multiclient-onboarding`

## Bug fix: Cobro doble en catálogo async (CRÍTICO)

### Problema
En `ai-generation.worker.ts`, al completar un job de catálogo, se llamaba a `consumeCredit()` además de la reserva previa hecha con `reserveCredits()`. Esto generaba un **cobro 2x** al usuario por cada generación de catálogo.

### Solución
Eliminado `consumeCredit` del path de éxito del worker. La reserva (`reserveCredits`) YA es el débito definitivo en el flujo async. Solo se ejecuta `refundReservedCredits` si el job falla.

**Archivo:** `src/ai-generation/ai-generation.worker.ts`

---

## Bug fix: Consume-before-AI en column mapping (MEDIO)

### Problema
En `import-mapping.service.ts`, `consumeCredit()` se ejecutaba ANTES de la llamada a `suggestMappingWithAI()`. Si la IA fallaba, el crédito ya estaba consumido sin retorno.

### Solución
Reordenado: `assertAvailable` (pre-check sin débito) → llamada IA → `consumeCredit` (post-éxito).

**Archivo:** `src/import-wizard/import-mapping.service.ts`

---

## Mejora: humanReadableError expandido y seguro

### Problema
`humanReadableError()` solo cubría `content_policy_violation` y `billing_hard_limit_exceeded`. El default filtraba el mensaje interno de OpenAI al usuario, potencial riesgo de seguridad (fragmentos de API key, errores internos).

### Solución
Agregados 6 códigos nuevos: `insufficient_quota`, `invalid_api_key`, `model_not_found`, `rate_limit_exceeded`, `server_error`, `service_unavailable`. El default ahora devuelve un mensaje genérico seguro.

**Archivo:** `src/ai-generation/ai-generation.service.ts`

---

## Feature: Migración de 6 servicios a OpenAI Key Pool

### Contexto
6 servicios creaban su propia instancia de `OpenAI` con una sola key, sin soporte multi-key, sin rate limit handling, sin concurrency control.

### Solución

1. **Nuevo módulo `OpenAiKeyPoolModule`** — módulo independiente que exporta `OpenAiKeyPool`. Resuelve la dependencia circular entre `AiGenerationModule` y `AiCreditsModule`.

2. **6 servicios migrados** al patrón `acquire() → try/catch → markRateLimited(429) → finally release()`:

| Servicio | Módulo |
|----------|--------|
| `import-mapping.service.ts` | ImportWizardModule |
| `store-context.service.ts` | AiCreditsModule |
| `seo-ai.service.ts` | SeoAiModule |
| `audience-intel.service.ts` | MarketingModule |
| `campaign-advisor.service.ts` | MarketingModule |
| `creative-studio.service.ts` | MarketingModule |

3. **4 módulos actualizados** para importar `OpenAiKeyPoolModule`: AiCreditsModule, SeoAiModule, MarketingModule, ImportWizardModule.

4. **Tests actualizados**: `seo-ai.service.spec.ts` y `store-context.service.spec.ts` reescritos con mock de `KeyPool` (acquire/release/markRateLimited).

### Archivos creados
- `src/ai-generation/openai-key-pool.module.ts`

### Archivos modificados
- `src/ai-generation/ai-generation.module.ts`
- `src/ai-credits/ai-credits.module.ts`
- `src/ai-credits/store-context.service.ts`
- `src/ai-credits/store-context.service.spec.ts`
- `src/seo-ai/seo-ai.module.ts`
- `src/seo-ai/seo-ai.service.ts`
- `src/seo-ai/seo-ai.service.spec.ts`
- `src/marketing/marketing.module.ts`
- `src/marketing/audience-intel.service.ts`
- `src/marketing/campaign-advisor.service.ts`
- `src/marketing/creative-studio.service.ts`
- `src/import-wizard/import-wizard.module.ts`
- `src/import-wizard/import-mapping.service.ts`

---

## Verificación: Banner mobile

Se confirmó que la generación de banners mobile **ya funciona** end-to-end. El tipo `'desktop' | 'mobile'` está soportado en DTO, servicio, prompt y frontend. No requirió cambios.

---

## Validación

- TypeScript: 0 errores
- Lint: 0 errores
- Build: exitoso
- Tests AI: 46/46 passed (ai-credits.service, ai-credits.guard, store-context.service, seo-ai.service)
- Tests totales: 1006/1016 passed (10 failures en 3 suites pre-existentes, confirmado con git stash)

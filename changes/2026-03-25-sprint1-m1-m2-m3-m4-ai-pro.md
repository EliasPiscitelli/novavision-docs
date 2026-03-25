# Sprint 1 AI Pro — M1 + M2 + M3 + M4

**Fecha:** 2026-03-25
**Plan:** `PLAN_AI_PRO.md` Sprint 1
**Estado:** Implementado

---

## M3: Validar límites operativos del tenant antes de cada acción IA

### Problema
Si el tenant alcanzó el máximo de productos/banners/FAQs/servicios de su plan, la IA generaba contenido que no se podía guardar → el seller perdía créditos.

### Solución
Agregado `PlanLimitsGuard` + `@PlanAction()` a 6 endpoints de AI generation que crean entidades:

| Endpoint | PlanAction |
|----------|-----------|
| `POST faqs/ai-generate` | `create_faq` |
| `POST products/ai-fill` | `create_product` |
| `POST products/ai-from-photo` | `create_product` |
| `POST banners/ai-generate` | `create_banner` |
| `POST services/ai-create` | `create_service` |
| `POST products/ai-catalog` | `create_product` |

**Cadena de guards:** `ClientDashboardGuard → PlanLimitsGuard → AiCreditsGuard`

Eliminado check manual inline en `banners/ai-generate` (redundante con el guard).

### Archivos modificados
- `api/src/ai-generation/ai-generation.controller.ts`

---

## M1: Welcome credits automáticos en provisioning

### Problema
El step 12 solo ejecutaba dentro del path con `jobId` (saga). El path directo `provisionClientFromOnboardingNow()` nunca otorgaba welcome credits ni Store DNA. 3 cuentas activas con 0 créditos AI.

### Solución
1. Agregado branch `else` en step 12 para provisioning directo
2. Migración de backfill para cuentas existentes (e2e-alpha=15, e2e-beta=50, farma=50)

### Archivos modificados
- `api/src/worker/provisioning-worker.service.ts`
- `api/migrations/admin/20260325_backfill_welcome_ai_credits.sql`

---

## M2: Campos industry/brand_tone en onboarding

### Problema
Las columnas `industry` y `brand_tone` existen en `nv_accounts` (migración 2026-03-18) y Store DNA ya las lee, pero el endpoint `POST /onboarding/business-info` no las aceptaba. Resultado: todas las cuentas con estos campos NULL → Store DNA genérico.

### Solución
Agregados `industry` y `brand_tone` como campos opcionales al endpoint de business-info:
- Controller: acepta los campos en el body
- Service: los persiste en `nv_accounts` via `saveBusinessInfo()`

Opciones de industry: indumentaria, accesorios, deco, tech, alimentos, servicios, otro
Opciones de brand_tone: casual, profesional, técnico, premium, juvenil

### Archivos modificados
- `api/src/onboarding/onboarding.controller.ts` — body type + passthrough
- `api/src/onboarding/onboarding.service.ts` — cleanStr + update object

---

## M4: SEO AI con modelo configurable + soporte Anthropic

### Problema
`SeoAiService` tenía `gpt-4o-mini` hardcodeado. No había forma de usar un modelo premium para SEO sin cambiar código.

### Solución
1. **Migración**: Agregadas columnas `provider`, `model_id`, `temperature`, `max_tokens` a `seo_ai_entity_pricing` (Admin DB). Default: `openai` / `gpt-4o-mini`.
2. **SeoAiService refactorizado**:
   - Acepta `SeoModelConfig` como parámetro opcional
   - Soporta provider `openai` (existente) y `anthropic` (nuevo)
   - Anthropic client inicializado desde `ANTHROPIC_API_KEY` vía ConfigService
   - Maneja JSON wrapping en markdown code blocks de Anthropic
3. **SeoAiBillingService**: Cache extendido para incluir config de modelo completa
4. **Worker**: Lee config de modelo desde pricing table y la pasa al service

Para cambiar el modelo SEO a Claude Sonnet, solo se necesita un UPDATE en Admin DB:
```sql
UPDATE seo_ai_entity_pricing
SET provider = 'anthropic', model_id = 'claude-sonnet-4-6'
WHERE entity_type = 'product';
```

### Archivos modificados
- `api/src/seo-ai/seo-ai.service.ts` — refactor completo, dual provider
- `api/src/seo-ai/seo-ai.service.spec.ts` — mock ConfigService
- `api/src/seo-ai/seo-ai-worker.service.ts` — pasar modelConfig
- `api/src/seo-ai-billing/seo-ai-billing.service.ts` — EntityPricing extendido + getEntityConfig()
- `api/migrations/admin/20260325_seo_ai_model_config.sql`

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 106/106 suites, 1033/1035 tests OK

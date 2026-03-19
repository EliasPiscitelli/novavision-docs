# Plan: Endpoints de Generación IA — 5 Features AI con Store DNA

## Context

La infraestructura de AI Credits (créditos, guard, pricing, Store DNA, UI) está completa y deployeada. Los botones IA del frontend ya existen y llaman a endpoints que **todavía no tienen handler backend**. Este plan implementa los 5 servicios de generación IA que faltan, más el form de Settings para editar el perfil IA de la tienda.

**Endpoints que el frontend ya llama:**
- `POST /products/:id/ai-description` → genera descripción de producto
- `POST /questions/:id/ai-suggest` → sugiere respuesta a pregunta Q&A
- `POST /reviews/:id/ai-suggest` → sugiere respuesta a review
- `POST /faqs/ai-generate` → genera FAQs desde productos seleccionados
- `POST /faqs/:id/ai-enhance` → mejora una FAQ individual

---

## Arquitectura

### Módulo nuevo: `ai-generation`

Un solo módulo centralizado con un service y un controller, separado de `ai-credits` (infraestructura).

```
src/ai-generation/
  ai-generation.module.ts          ← imports AiCreditsModule, DbModule
  ai-generation.controller.ts      ← 5 endpoints, guards + decorators
  ai-generation.service.ts         ← lógica OpenAI con retry + Store DNA
  prompts/
    product-description.prompt.ts
    qa-answer.prompt.ts
    review-reply.prompt.ts
    faq-generation.prompt.ts
    faq-enhance.prompt.ts
```

### Patrón por endpoint (replicado 5 veces)

```
1. Guard valida créditos (AiCreditsGuard + @RequireAiCredits)
   → req.aiPricing = { model_id, temperature, max_tokens, credit_cost }
   → req.aiTier = 'normal' | 'pro'
2. Controller extrae datos (product_id, question_id, etc.)
3. Service hace:
   a. Query a Backend DB para obtener datos de la entidad
   b. getOrGenerateStoreDNA() para contexto de tienda
   c. Llama OpenAI con model_id/temperature/max_tokens del pricing
   d. Parsea respuesta JSON
4. Controller consume créditos via aiCreditsService.consumeCredit()
5. Retorna resultado al frontend
```

**Clave:** Los créditos se consumen SOLO si la generación fue exitosa. Si OpenAI falla, no se cobra.

---

## Endpoints detallados

### 1. `POST /products/:id/ai-description`

**Action code:** `ai_product_description`

**Datos de entrada (Backend DB):**
- `products` → `name`, `description`, `originalPrice`, `categoryName`
- Store DNA del tenant

**System prompt:**
```
{storeDNA}

Sos un copywriter de e-commerce. Generá una descripción de producto persuasiva y optimizada para conversión.

REGLAS:
- Máximo 300 palabras
- Incluir beneficio principal al inicio
- Usar lenguaje natural, NO marketing genérico
- NO inventar datos que no estén en el input
- Si hay descripción actual, mejorarla (no reescribir desde cero)
- Español rioplatense natural
- Respondé SOLO con JSON: { "description": "..." }
```

**Request:** `{ ai_tier: 'normal'|'pro', current_description?: string }`
**Response:** `{ description: string, credits_consumed: number, tier: string }`

### 2. `POST /questions/:id/ai-suggest`

**Action code:** `ai_qa_answer`

**Datos de entrada (Backend DB):**
- `product_questions` → `body` (la pregunta), `product_id`
- `products` → `name`, `description`, `originalPrice` (contexto del producto)
- Store DNA

**System prompt:**
```
{storeDNA}

Sos el asistente de atención al cliente de esta tienda. Sugerí una respuesta profesional a la pregunta del comprador.

REGLAS:
- Respuesta directa y útil (máximo 150 palabras)
- NO inventar datos de stock, envío ni disponibilidad
- Si no sabés algo, sugerí que el comprador consulte por WhatsApp
- Tono amigable pero profesional
- Respondé SOLO con JSON: { "suggestion": "..." }
```

**Request:** `{ ai_tier: 'normal'|'pro' }`
**Response:** `{ suggestion: string, credits_consumed: number, tier: string }`

### 3. `POST /reviews/:id/ai-suggest`

**Action code:** `ai_qa_answer` (comparte pool con Q&A)

**Datos de entrada (Backend DB):**
- `product_reviews` → `rating`, `title`, `body` (la review)
- `products` → `name` (contexto)
- Store DNA

**System prompt:**
```
{storeDNA}

Sos el encargado de reputación online de esta tienda. Sugerí una respuesta profesional a esta reseña de un cliente.

REGLAS:
- Si la reseña es positiva: agradecer genuinamente, sin sonar genérico
- Si es negativa: empatizar, ofrecer solución, NO ponerse a la defensiva
- Si es neutra: agradecer y ofrecer ayuda adicional
- Máximo 100 palabras
- NO mencionar compensaciones sin que el admin lo autorice
- Respondé SOLO con JSON: { "suggestion": "..." }
```

**Request:** `{ ai_tier: 'normal'|'pro' }`
**Response:** `{ suggestion: string, credits_consumed: number, tier: string }`

### 4. `POST /faqs/ai-generate`

**Action code:** `ai_faq_generation`

**Datos de entrada (Backend DB):**
- `products` → nombre, descripción, precio, categoría de cada producto seleccionado
- Store DNA

**System prompt:**
```
{storeDNA}

Generá preguntas frecuentes relevantes basadas en estos productos de e-commerce.

REGLAS:
- Entre 3 y 5 preguntas por producto
- Preguntas que un comprador real haría (talle, material, envío, cuidado, compatibilidad)
- Respuestas útiles y concisas (máximo 80 palabras cada una)
- NO inventar datos técnicos específicos que no estén en la descripción
- Las preguntas deben ser diferentes entre sí
- Respondé SOLO con JSON: { "faqs": [{ "question": "...", "answer": "..." }] }
```

**Request:** `{ product_ids: string[], ai_tier: 'normal'|'pro' }`
**Response:** `{ faqs: Array<{ question: string, answer: string }>, credits_consumed: number, tier: string }`

**Nota:** Se consume 1 crédito por invocación (no por producto). El pricing ya lo define.

### 5. `POST /faqs/:id/ai-enhance`

**Action code:** `ai_faq_generation` (comparte pool con FAQ generation)

**Datos de entrada:**
- La FAQ actual (`question`, `answer`) viene en el body
- Store DNA

**System prompt:**
```
{storeDNA}

Mejorá esta pregunta frecuente de e-commerce. Hacela más clara, profesional y útil.

REGLAS:
- Mantener la esencia de la pregunta y respuesta original
- Mejorar claridad, gramática y persuasión
- Respuesta máximo 100 palabras
- NO cambiar datos factuales
- Respondé SOLO con JSON: { "question": "...", "answer": "..." }
```

**Request:** `{ ai_tier: 'normal'|'pro', question: string, answer: string }`
**Response:** `{ question: string, answer: string, credits_consumed: number, tier: string }`

---

## Archivos a crear (5)

| # | Archivo | Propósito |
|---|---------|-----------|
| 1 | `api/src/ai-generation/ai-generation.module.ts` | Módulo NestJS |
| 2 | `api/src/ai-generation/ai-generation.service.ts` | Lógica OpenAI + retry |
| 3 | `api/src/ai-generation/ai-generation.controller.ts` | 5 endpoints |
| 4 | `api/src/ai-generation/prompts/index.ts` | System prompts + builders |
| 5 | `api/src/ai-generation/ai-generation.service.spec.ts` | Tests unitarios |

## Archivos a modificar (1)

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `api/src/app.module.ts` | Import AiGenerationModule |

## Archivos de referencia

| Archivo | Patrón a copiar |
|---------|----------------|
| `api/src/seo-ai/seo-ai.service.ts` | OpenAI call con retry exponencial |
| `api/src/seo-ai/prompts/system.prompt.ts` | Estructura de prompts |
| `api/src/ai-credits/ai-credits.guard.ts` | Guard que valida + attach pricing |
| `api/src/ai-credits/ai-credits.service.ts` | `consumeCredit()`, `getPricingForTier()` |
| `api/src/ai-credits/store-context.service.ts` | `getOrGenerateStoreDNA()` |
| `api/src/products/products.controller.ts` | `getClientId(req)`, DB patterns |
| `api/src/questions/questions.controller.ts` | Questions data structure |
| `api/src/reviews/reviews.controller.ts` | Reviews data structure |
| `api/src/faq/faq.controller.ts` | FAQs data structure |

---

## Detalle de implementación

### ai-generation.module.ts

```typescript
@Module({
  imports: [ConfigModule, DbModule, AiCreditsModule],
  controllers: [AiGenerationController],
  providers: [AiGenerationService],
  exports: [AiGenerationService],
})
```

### ai-generation.controller.ts

- `@Controller()` sin prefix (las rutas son explícitas: `/products/:id/ai-description`, etc.)
- Cada endpoint usa: `@UseGuards(ClientDashboardGuard, AiCreditsGuard)` + `@RequireAiCredits('action_code')`
- Extrae: `accountId = req.account_id`, `clientId = req.headers['x-client-id'] || req.client_id`
- Consume créditos SOLO después de generación exitosa
- Response incluye `credits_consumed` y `tier` para feedback UX

### ai-generation.service.ts

**Constructor:**
- Inyecta `ConfigService` → init OpenAI client
- Inyecta `AiCreditsService` → lookup pricing para model_id/temp/tokens
- Inyecta `StoreContextService` → Store DNA
- Inyecta `DbRouterService` → queries Backend DB

**Métodos:**
```
generateProductDescription(clientId, accountId, productId, tier, currentDescription?) → { description }
suggestQaAnswer(clientId, accountId, questionId, tier) → { suggestion }
suggestReviewReply(clientId, accountId, reviewId, tier) → { suggestion }
generateFaqs(clientId, accountId, productIds[], tier) → { faqs[] }
enhanceFaq(clientId, accountId, question, answer, tier) → { question, answer }
```

**Método privado compartido:**
```
private callOpenAI(params: {
  actionCode: string,
  tier: 'normal'|'pro',
  systemPrompt: string,
  userPrompt: string,
  storeDNA: string,
  retries?: number
}) → Promise<string>
```

Este método:
1. Obtiene pricing via `getPricingForTier(actionCode, tier)`
2. Usa `pricing.model_id`, `pricing.temperature`, `pricing.max_tokens`
3. Prepend Store DNA al system prompt
4. Llama OpenAI con `response_format: { type: 'json_object' }`
5. Retry con backoff exponencial (2s, 4s, 6s) hasta `retries` veces
6. Retorna raw JSON string o null si falla

---

## Tests

### Tests unitarios (`ai-generation.service.spec.ts`)

| # | Test | Qué valida |
|---|------|-----------|
| 1 | generateProductDescription retorna descripción válida | Mock OpenAI → parse correcto |
| 2 | generateProductDescription con producto inexistente → error | Valida 404 |
| 3 | suggestQaAnswer retorna sugerencia | Mock OpenAI + pregunta de BD |
| 4 | suggestQaAnswer con pregunta inexistente → error | Valida 404 |
| 5 | suggestReviewReply retorna sugerencia | Mock OpenAI + review de BD |
| 6 | suggestReviewReply con review inexistente → error | Valida 404 |
| 7 | generateFaqs retorna array de FAQs | Mock OpenAI con múltiples productos |
| 8 | generateFaqs con product_ids vacío → error | Valida input |
| 9 | enhanceFaq retorna question + answer mejorados | Mock OpenAI |
| 10 | callOpenAI reintenta con backoff en error 429 | Simula rate limit |
| 11 | callOpenAI retorna null después de agotar reintentos | Simula fallo total |
| 12 | Store DNA se inyecta en system prompt | Verifica que el prompt incluye DNA |
| 13 | Si OpenAI no configurado → error graceful | Sin API key |
| 14 | Pricing configura model_id correcto por tier | Normal→gpt-4o-mini, Pro→gpt-4o |

### Tests E2E (`test/ai-generation.e2e.spec.ts`)

| # | Test | Qué valida |
|---|------|-----------|
| 1 | POST /products/:id/ai-description sin auth → 401 | Guard |
| 2 | POST /products/:id/ai-description sin créditos → 402 | Credit check |
| 3 | POST /products/:id/ai-description con créditos → 200 | Happy path (mock OpenAI) |
| 4 | POST /questions/:id/ai-suggest → 200 | Happy path |
| 5 | POST /reviews/:id/ai-suggest → 200 | Happy path |
| 6 | POST /faqs/ai-generate con product_ids → 200 | Happy path |
| 7 | POST /faqs/:id/ai-enhance → 200 | Happy path |
| 8 | Todos consumen créditos en respuesta exitosa | Ledger entry creada |
| 9 | Fallo OpenAI → NO consume créditos | Ledger sin entry |
| 10 | ai_tier=pro usa modelo correcto | gpt-4o en metadata |

---

## Orden de implementación

1. **Prompts** (`prompts/index.ts`) — system prompts + interfaces + builders
2. **Service** (`ai-generation.service.ts`) — lógica OpenAI con `callOpenAI()` + 5 métodos
3. **Controller** (`ai-generation.controller.ts`) — 5 endpoints con guards
4. **Module** (`ai-generation.module.ts`) — registro + import en AppModule
5. **Tests unitarios** (`ai-generation.service.spec.ts`) — 14 tests
6. **Tests E2E** (`test/ai-generation.e2e.spec.ts`) — 10 tests
7. **Validación** — lint + typecheck + build

## Verificación

1. `npm run lint` — 0 errores
2. `npm run typecheck` — 0 errores
3. `npm run build && ls dist/main.js` — build exitoso
4. `npm run test -- --testPathPattern=ai-generation` — 14 tests pasan
5. `npm run test:e2e -- --testPathPattern=ai-generation` — 10 tests pasan

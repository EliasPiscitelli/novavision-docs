# Plan AI Pro — Mejoras sobre la Auditoría IA 2026-03-25

> **Fecha:** 2026-03-25
> **Estado:** PLAN — No ejecutar sin aprobación del TL
> **Base:** `audits/ai-audit-2026-03-25.md` — cada mejora referencia un hallazgo real
> **Principio:** Mejorar lo que existe, no inventar features nuevas

---

## Filosofía: Normal vs Pro

| Aspecto | Normal (incluido / plan base) | Pro (plan superior / add-on pago) |
|---------|-------------------------------|-----------------------------------|
| **API Key** | `OPENAI_API_KEY` (gpt-4o-mini) | `ANTHROPIC_API_KEY` (Claude Sonnet/Haiku) |
| **Calidad** | Buena — resuelve el 80% de los casos | Superior — tono más natural, mejor razonamiento, multilingüe nativo |
| **Costo por invocación** | ~USD 0.0003-0.001 (gpt-4o-mini) | ~USD 0.001-0.005 (Claude Sonnet 4.6) |
| **Target** | Todos los planes (Starter, Growth, Enterprise) | Todos los planes (consume más créditos = más revenue) |
| **Propósito** | Adopción masiva, retención, diferenciación básica vs TN | Monetización, margen, calidad premium |

---

## Modelo de negocio

### Costo estimado IA por tenant/mes (uso promedio proyectado)

| Plan | Invocaciones/mes estimadas | Costo Normal (OpenAI) | Costo Pro (Anthropic) | Total estimado |
|------|--------------------------|----------------------|----------------------|---------------|
| Starter | 15-30 | USD 0.01-0.03 | USD 0 (sin acceso) | **USD 0.03** |
| Growth | 50-150 | USD 0.05-0.15 | USD 0.10-0.50 (opcional) | **USD 0.65** |
| Enterprise | 200-500 | USD 0.20-0.50 | USD 0.50-2.50 (incluido) | **USD 3.00** |

### Ingreso estimado por IA

| Fuente | Ingreso/mes estimado | Margen |
|--------|---------------------|--------|
| Packs universales (ARS ~10-50 c/u) | USD 0.10-0.50/tenant | ~95% (texto), ~70% (imágenes) |
| Upgrade driver Starter→Growth | Atribuible parcialmente | Diff USD 40/mes |
| Welcome credits como trial | USD 0 (costo: ~USD 0.02/tenant) | Inversión en adopción |

**Margen objetivo IA**: ≥85% para texto, ≥60% para imágenes. El costo de IA es marginal comparado con el pricing de planes.

---

## Roadmap de mejoras (ordenado por impacto)

### Sprint 1 — Encender lo que existe (1-2 semanas)

> **Objetivo:** Pasar de adopción 2/10 a 5/10 sin escribir código nuevo

#### M1: Activar welcome credits automáticos en provisioning
**Resuelve:** GAP G4 (welcome credits no se otorgan automáticamente)
**Afecta:** API (`provisioning-worker.service.ts`)
**Plan mínimo:** Todos

**Acción:** Verificar que el step `GRANT_WELCOME_AI_CREDITS` en provisioning realmente ejecuta `grantWelcomeCredits()` con los configs `ai_universal` activos. Si no se ejecuta, debuggear por qué. Los welcome credits son la puerta de entrada a la IA — si el tenant no los tiene, nunca descubre las features.

**Métrica de éxito:** Cada nueva cuenta recibe 15/50/150 créditos universales según plan.

#### M2: Poblar campos de personalización durante onboarding
**Resuelve:** GAP G3 (campos industry/brand_tone/target_audience vacíos)
**Afecta:** API (onboarding flow), Web (onboarding wizard)
**Plan mínimo:** Todos

**Acción:** Agregar 2-3 campos simples al flow de onboarding existente:
- "¿De qué es tu tienda?" (select: Indumentaria, Accesorios, Deco, Tech, Alimentos, Servicios, Otro)
- "¿Cómo preferís comunicarte?" (select: Casual, Profesional, Técnico, Premium)

Esto alimenta `nv_accounts.industry` y `nv_accounts.brand_tone`, que a su vez alimenta el Store DNA de calidad.

**Métrica de éxito:** ≥70% de nuevas cuentas con `industry` y `brand_tone` poblados.

#### M3: Validar límites operativos del tenant antes de cada acción IA
**Resuelve:** GAP G8b (no se validan límites operativos antes de IA)
**Afecta:** API (guards), Web (UI de botones IA)
**Plan mínimo:** Todos

**Problema:** Si el tenant alcanzó el máximo de productos (50/50 en Starter), el botón "Crear catálogo con IA" debería deshabilitarse mostrando la razón. Hoy se puede generar con IA algo que no se puede guardar → el seller pierde créditos.

**Acción:**
1. Crear un guard o interceptor `TenantCapacityCheck` que valide antes de cada acción IA:
   - `ai_product_description` / `ai_product_full` / `ai_photo_product` / `ai_catalog_generation` → verificar `products_count < products_limit`
   - `ai_faq_generation` → verificar `faqs_count < faqs_limit` (si existe límite)
   - `ai_banner_generation` → verificar `banners_count < banners_limit` (si existe límite)
   - `ai_css_generation` → verificar capacidad de componentes
2. Retornar HTTP 403 con mensaje descriptivo:
```json
{
  "error": "tenant_capacity_reached",
  "resource": "products",
  "current": 50,
  "limit": 50,
  "message": "Alcanzaste el máximo de productos de tu plan (50/50). Upgradeá para agregar más.",
  "upgrade_url": "/settings/billing"
}
```
3. En el frontend, deshabilitar botones IA con tooltip que muestre la razón

**Métrica de éxito:** 0 créditos desperdiciados por límites operativos alcanzados.

#### M4: Potenciar SEO AI con modelo premium + tracking per-tenant
**Resuelve:** Mejora sobre sistema SEO separado (decisión de mantenerlo independiente)
**Afecta:** API (`seo-ai/`), Admin DB
**Plan mínimo:** Todos (SEO tiene su propio pricing)

**Acción:**
1. Evaluar migrar SEO AI de `gpt-4o-mini` a un modelo más potente (ej: `gpt-4o` o `claude-sonnet-4-6`) para mejorar calidad de meta-tags
2. Ajustar pricing de créditos SEO acorde al costo del modelo premium
3. Incorporar tracking real per-tenant: campos para Google Search Console API key, tracking de rankings, métricas de indexación
4. El pricing independiente de SEO permite cobrar más por un servicio de mayor valor sin afectar los créditos IA generales

---

### Sprint 2 — Onboarding Coach + Adopción (2-3 semanas)

> **Objetivo:** Implementar la feature #1 de la Corrida 1 y acelerar adopción de IA

#### M5: Implementar AI Onboarding Coach
**Resuelve:** GAP G12 (feature #1 no implementada, score 25/25 en Corrida 1)
**Afecta:** API (nuevo endpoint), Web (dashboard principal)

**Diseño:**
- Endpoint: `GET /dashboard/ai-coach` (síncrono, <2s)
- Input: Estado de completitud de la tienda (productos count, MP conectado, logo, envíos, SEO)
- Output: Siguiente paso concreto + motivación + link a la sección relevante
- Modelo: gpt-4o-mini (Normal) o Claude Haiku (Pro — primer uso de Anthropic)
- Cache: 1 hora por tenant (Redis o in-memory)
- **NO consume créditos** — es herramienta de retención, no monetización

**Por qué es prioritario:** Reduce churn en los primeros 7 días. Un seller que no sabe qué hacer abandona. El coach le dice exactamente qué hacer y por qué.

**Diferenciación Normal/Pro:** Con Claude Haiku, el coach es más natural y contextual. Con gpt-4o-mini, es funcional pero más genérico.

#### M6: Mejorar discoverability de features IA existentes
**Resuelve:** GAP G8 (5 de 8 features IA nunca consumidas)
**Afecta:** Web (UI)

**Acción:** Las features existen pero el seller no las descubre. Mejorar visibilidad:
1. **Empty states con sugerencia IA**: Cuando el seller tiene 0 FAQs → "Generá FAQs automáticas con IA". 0 descripciones → "Mejorá tus descripciones con IA"
2. **Notificación post-onboarding**: "Tenés X créditos IA de bienvenida. Probá generar tu primera descripción con IA"
3. **Badge de créditos en header**: Recordar constantemente que tienen créditos disponibles

---

### Sprint 3 — Tier Pro con Anthropic (2-3 semanas)

> **Objetivo:** Activar `ANTHROPIC_API_KEY` y crear diferenciación real Normal vs Pro

#### M7: Implementar AnthropicProvider como alternativa Pro
**Resuelve:** GAP G7 (ANTHROPIC_API_KEY sin uso)
**Afecta:** API (`ai-generation/`)
**Acceso:** Todos los planes (Pro consume más créditos, que es la monetización)

**Diseño:**
- Nuevo provider: `anthropic-provider.ts` (junto a `openai-key-pool.ts`)
- Modelo Pro: Claude Sonnet 4.6 para texto, Claude Haiku 4.5 para coach/respuestas rápidas
- `ai_feature_pricing` tier=pro → `model_id` cambia de `gpt-4o` a `claude-sonnet-4-6`
- Fallback: Si Anthropic falla, fallback a gpt-4o (no dejar al tenant sin servicio)

**Por qué Anthropic para Pro:**
- Mejor razonamiento en español (tono más natural para rioplatense)
- Mejor seguimiento de instrucciones complejas (Store DNA + prompt + contexto)
- Diferenciación real vs competidores que solo usan OpenAI
- Costo similar o menor que gpt-4o para calidad equivalente o superior

**Pricing sugerido Pro:**

| Action Code | Modelo Pro actual (OpenAI) | Modelo Pro nuevo (Anthropic) | Créditos |
|-------------|---------------------------|------------------------------|----------|
| `ai_product_description` | gpt-4o / 3 cr | claude-sonnet-4-6 / 3 cr | Sin cambio |
| `ai_qa_answer` | gpt-4o / 2 cr | claude-haiku-4-5 / 2 cr | Sin cambio |
| `ai_faq_generation` | gpt-4o / 4 cr | claude-sonnet-4-6 / 4 cr | Sin cambio |
| `ai_product_full` | gpt-4o / 5 cr | claude-sonnet-4-6 / 5 cr | Sin cambio |

> Nota: `ai_photo_product` y `ai_banner_generation` siguen con `gpt-image-1` (Anthropic no tiene generación de imágenes).

#### M8: Agregar tracking de costo USD por invocación
**Resuelve:** GAP G10 (no hay tracking de costo real)
**Afecta:** API (`ai-generation/`, `ai-credits/`)
**Plan mínimo:** Interno (super-admin)

**Acción:** Agregar campo `cost_usd` al `account_action_credit_ledger` (o tabla nueva `ai_cost_log`). Calcular costo basado en tokens × precio por token del modelo. Mostrar en dashboard super-admin.

**Fórmula:**
```
cost_usd = (input_tokens × input_price_per_1M / 1_000_000) + (output_tokens × output_price_per_1M / 1_000_000)
```

**Pricing de referencia (2026-03):**
| Modelo | Input/1M tokens | Output/1M tokens |
|--------|----------------|-----------------|
| gpt-4o-mini | USD 0.15 | USD 0.60 |
| gpt-4o | USD 2.50 | USD 10.00 |
| claude-sonnet-4-6 | USD 3.00 | USD 15.00 |
| claude-haiku-4-5 | USD 0.80 | USD 4.00 |
| gpt-image-1 | ~USD 0.04/imagen | — |

---

### Sprint 4 — Localización + n8n (1-2 semanas)

> **Objetivo:** Preparar para expansión LATAM y activar workflows

#### M9: Parametrizar idioma en prompts
**Resuelve:** GAP G6 (locale no se usa en prompts)
**Afecta:** API (`ai-generation/prompts/`)
**Plan mínimo:** Todos

**Acción:** Leer `clients.locale` y/o `nv_accounts.country` al construir prompts. Agregar al Store DNA: `"Idioma: {locale}"`. Mapeo: `es-AR` → español rioplatense, `pt-BR` → portugués brasileiro, `es-MX` → español mexicano, etc.

**Impacto:** Bajo esfuerzo, alto valor para internacionalización futura.

#### M10: Activar y asegurar workflows n8n de reporting
**Resuelve:** GAP G9 (workflows inactivos) + GAP G11 (output sin validación)
**Afecta:** n8n workflows
**Plan mínimo:** Interno

**Acción:**
1. Agregar nodo de validación post-IA en cada workflow (regex para precios, claims)
2. Agregar nodo de fallback si OpenAI falla (enviar "Reporte no disponible hoy")
3. Activar selectivamente (empezar por Weekly AI Report que tiene más valor)
4. Revisar que las credenciales OpenAI en n8n estén actualizadas

---

### Sprint 5 — Mejorar FAQ AI + AI Closer productivo (2 semanas)

#### M11: Mejorar prompt de AI FAQ con contexto completo de tienda
**Resuelve:** FAQs son preguntas generales de la tienda, no de productos individuales
**Afecta:** API (`ai-generation/prompts/`)

**Problema actual:** El prompt de `ai_faq_generation` genera FAQs desde datos de productos. Pero las FAQs reales de una tienda son preguntas generales: "¿Cuánto cuesta el envío?", "¿Qué materiales usan?", "¿Cómo hago un cambio?", "¿Aceptan MercadoPago?". Son preguntas del rubro/tienda, no de un producto.

**Acción:** Reescribir el prompt para que tome contexto completo:
- **Store DNA** (ya se inyecta)
- **Métodos de envío** configurados (`shipping_methods`)
- **Medios de pago** activos (MercadoPago, transferencia, etc.)
- **Políticas de cambio/devolución** (si existen)
- **Rubro/industria** (`nv_accounts.industry`)
- **Categorías de productos** (para saber qué vende)
- **Ubicación/zona** de envío

**Prompt mejorado (concepto):**
```
{storeDNA}

Generá preguntas frecuentes típicas para esta tienda de e-commerce argentina.
Las FAQs deben ser preguntas GENERALES que los compradores hacen recurrentemente:
- Envío: costos, tiempos, zonas de cobertura
- Pagos: medios aceptados, cuotas, facturación
- Cambios y devoluciones: política, plazos
- Productos: materiales, cuidado, garantía (según rubro)
- Compra: cómo comprar, seguimiento de pedido, horarios de atención

Contexto adicional:
- Envíos: {shipping_methods}
- Pagos: {payment_methods}
- Rubro: {industry}
- Categorías: {categories}

Generá entre 5 y 10 preguntas con respuestas concretas.
NO inventes datos que no estén en el contexto.
Si no tenés datos de envío/pagos, generá preguntas genéricas del rubro.
```

**Resultado:** FAQs útiles y reales que ahorran consultas al seller.

#### M12: Implementar AI Closer en producción
**Resuelve:** GAP G9 (AI Closer solo en spec)
**Afecta:** n8n, API (outreach)
**Plan mínimo:** Interno NV

**Acción:** Implementar `wf-inbound-v2.json` en producción con:
- Playbook poblado (ya hay 33 entries en `nv_playbook`)
- Modelo `gpt-4.1-mini` → evaluar migrar a `claude-haiku-4-5` (Pro interno)
- Guardrails completos (HMAC, dedup, opt-out, JSON validation)
- Métricas: reply rate, engagement delta, conversion to demo

---

## Resumen de impacto por sprint

| Sprint | Mejoras | Impacto principal | Esfuerzo |
|--------|---------|-------------------|----------|
| **S1** | M1-M4 | Encender adopción + validar límites + potenciar SEO | Bajo-Medio |
| **S2** | M5-M6 | Retención (coach) + discoverability de features | Medio |
| **S3** | M7-M8 | Monetización Pro con Anthropic + cost tracking | Alto |
| **S4** | M9-M10 | Preparar internacionalización + activar n8n reporting | Bajo-Medio |
| **S5** | M11-M12 | FAQs por producto + AI Closer productivo | Medio |

---

## Decisiones pendientes para el TL

| # | Decisión | Opciones | Recomendación |
|---|----------|---------|---------------|
| ~~D1~~ | ~~Packs per-feature o universales~~ | — | **RESUELTO**: Solo universales. Correcto por diseño |
| D2 | ¿Onboarding Coach consume créditos? | A) Gratis (retención) B) 1 crédito | **A** — cuesta USD 0.0003, genera retención |
| D3 | ¿Anthropic para Pro o seguir con gpt-4o? | A) Anthropic B) gpt-4o C) Ambos configurable | **C** — configurable en `ai_feature_pricing.model_id` |
| ~~D4~~ | ~~Gateo por plan~~ | — | **RESUELTO**: NO gatear IA por plan. Créditos = único limitador. Revenue directo |
| ~~D5~~ | ~~SEO AI Credits separado~~ | — | **RESUELTO**: Mantener separado. Permite pricing independiente + modelo potente + tracking per-tenant |
| D6 | ¿Activar workflows n8n reporting? | A) Sí, todos B) Solo Weekly C) No por ahora | **B** — empezar con el de mayor valor |
| D7 | ¿AI Closer con gpt-4.1-mini o migrar a Claude? | A) Mantener OpenAI B) Claude Haiku C) Test A/B | **C** — medir calidad de respuesta |
| D8 | ¿Qué modelo premium para SEO AI? | A) gpt-4o B) claude-sonnet-4-6 C) Mantener gpt-4o-mini | Depende del margen target para créditos SEO |
| D9 | ¿Qué límites operativos valida M3? | Verificar qué recursos tienen límite real por plan (productos, FAQs, banners, servicios, etc.) | Consultar `plans.entitlements` |

---

*Este documento es un plan basado exclusivamente en hallazgos reales de la auditoría `ai-audit-2026-03-25.md`. No se proponen features nuevas — solo mejoras sobre lo existente.*

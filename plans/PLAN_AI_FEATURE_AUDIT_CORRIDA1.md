# AI Feature Audit — NovaVision — Corrida 1 de 3

> **Fecha**: 2026-03-17
> **Autor**: Product Architect + AI FinOps audit
> **Objetivo**: Inventario priorizado de features IA candidatas para el admin dashboard del tenant
> **Siguiente**: Corrida 2 — Spec técnica + costeo detallado del Top 5

---

## Tabla de contenidos

1. [Verificación del sistema real](#1-verificación-del-sistema-real)
2. [Inventario de candidatas (16)](#2-inventario-de-candidatas)
3. [Priorización LATAM — 5 ejes](#3-priorización-latam)
4. [Top 5 para Corrida 2](#4-top-5-para-corrida-2)
5. [Anti-humo](#5-anti-humo)
6. [Preguntas bloqueantes para Corrida 2](#6-preguntas-bloqueantes)
7. [Supuestos base para costeo](#7-supuestos-base-para-costeo)

---

## 1. Verificación del sistema real

### IA que ya existe (NO proponer como nueva)

| Feature existente | Modelo | Billing | Infra | Estado |
|---|---|---|---|---|
| **SEO AI Autopilot** | `gpt-4o-mini`, T=0.3, max_tokens=500 | Créditos consumibles (`seo_ai_credits` ledger inmutable). Packs: Sitio (50 cr, $4900 ARS), 500 ($14900 ARS), 2000 ($29900 ARS). Pricing por entidad: product=3, category=2, site_field=1 | Polling worker 10s, chunks de 25, max 1 job concurrente/tenant, 5 jobs/día | VERIFICADO — activo en producción |
| **AI Import Wizard** | Validación local + n8n externo para enriquecimiento | Incluido por plan (Starter: 5/batch 1/día, Growth: 50/batch 5/día, Enterprise: 200/batch 20/día) | Batch processor, tablas `import_batches` + `import_batch_items` | VERIFICADO — activo |
| **AI Closer (n8n)** | GPT-4.1-mini vía n8n (externo) | Interno NV, no facturado a tenant | Outreach state machine (NEW→WON), endpoints HMAC-protected, claim/commit atómico | VERIFICADO — interno NV, no es feature de admin |
| **Marketing AI Suite** (Campaign Advisor, Audience Intel, Creative Studio) | `gpt-4o`, T=0.4-0.7 | No facturado (super-admin only) | n8n webhooks, `campaign_registry`, `ad_assets`, `ad_performance_daily`, `content_calendar` | VERIFICADO — super-admin only, NO tenant-facing |

### Infraestructura de billing verificada

| Componente | Estado | Detalle |
|---|---|---|
| `subscriptions` + `plans` + `account_entitlements` | VERIFICADO | Lifecycle completo con MP preapproval, estados, reconciliación |
| `nv_billing_events` | VERIFICADO | Eventos con idempotencia, estados pending→paid→failed |
| `seo_ai_credits` (patrón de créditos consumibles) | VERIFICADO | Ledger inmutable, running balance, delta ±N, reason, metadata |
| `addon_catalog` + `account_addons` | VERIFICADO | Familias: seo_ai, services, capacity, content, media. Tipos: consumable, service, uplift |
| `usage_ledger` → `usage_daily` → `usage_rollups_monthly` | VERIFICADO — PARCIAL | Recording y daily aggregation funcionan. Consolidación mensual tiene bug conocido (lee de BD incorrecta) |
| QuotaCheckGuard | VERIFICADO — DESHABILITADO | Existe y funciona, pero `ENABLE_QUOTA_ENFORCEMENT=false` por defecto |
| TenantRateLimitGuard | VERIFICADO | Starter: 5 RPS, Growth: 15 RPS, Enterprise: 60 RPS. Usa Redis con fallback in-memory |
| PlanAccessGuard + PlanLimitsGuard | VERIFICADO | `@PlanFeature()` para tier mínimo, `@PlanAction()` para soft limits |
| Redis | VERIFICADO CON CAVEAT | `RedisService` con fallback automático a `Map` in-memory. No confirmado si Railway tiene instancia activa |

### Planes actuales verificados

| Plan | Monthly fee | Productos | Órdenes/mes | Storage | Custom domain | Tiendas |
|---|---|---|---|---|---|---|
| Starter | USD 20 | 50 | 100 (soft) | 1 GB | No | 1 |
| Growth | USD 60 | 2,000 | 5,000 | 50 GB | Sí | 5 |
| Enterprise | USD 390 | 50,000 | Negociable | Negociable | Sí | Ilimitado |

### Módulos tenant-facing donde pueden vivir features IA

| Módulo | Entidad/tabla | Gating actual |
|---|---|---|
| Productos (editor) | `products` — name, description, meta_title, meta_description, images | Todos los planes |
| QA Manager | Q&A de compradores sobre productos | Growth+ |
| Reviews Manager | Reviews/opiniones de compradores | Growth+ |
| FAQs | `faqs` — preguntas frecuentes de la tienda | Todos los planes |
| Media Library | Imágenes en lote, vinculación a productos | Todos los planes |
| Size Guides | `size_guides` — guías de talles por rubro | Todos los planes |
| Banners | `banners` — banners promocionales | Todos los planes |
| Coupons | `coupons` — cupones de descuento | Todos los planes |
| Analytics | KPIs, ventas, conversión, tráfico | Growth+ |
| SEO Autopilot | Ya existe — meta/desc AI | Growth+ (audit free en Starter) |
| Import Wizard | Ya existe — importación batch | Todos los planes (limits por tier) |
| Dashboard principal | Vista post-login del seller | Todos los planes |

---

## 2. Inventario de candidatas

### 16 features evaluadas

| # | Nombre | Módulo | Problema concreto del seller | Infra existente vs nueva | Tipo de venta | Clasificación |
|---|--------|--------|------------------------------|--------------------------|---------------|---------------|
| 1 | **AI Onboarding Coach** | Dashboard principal | Seller no sabe qué hacer después de crear la tienda → abandona antes de la primera venta | **Existente**: estado de tienda, productos, pagos, envíos ya consultables. Requiere: servicio nuevo liviano, prompt con contexto de completitud | Incluida en todos los planes | **LANZAR YA** |
| 2 | **AI Descripción de Producto** | Productos (editor) | Seller escribe "remera negra talle M" y pierde SEO + conversión. Dolor #1 del vendedor chico argentino | **Existente**: OpenAI integrado, producto tiene `description`, `meta_title`, `meta_description`. Requiere: botón "Mejorar con IA" + servicio similar a SEO Autopilot | Consumible (créditos, reutilizar patrón `seo_ai_credits`) | **LANZAR YA** |
| 3 | **AI Respuesta a Preguntas de Compradores** | QA Manager | Comprador pregunta, seller tarda 3 días → compra en otro lado. Pregunta sin respuesta = venta perdida | **Existente**: tabla Q&A, contexto del producto disponible. Requiere: botón "Sugerir respuesta" + llamada OpenAI con contexto de producto | Incluida en Growth / consumible en Starter | **LANZAR YA** |
| 4 | **AI FAQ desde Descripción de Producto** | FAQs | Página de FAQ vacía → comprador con dudas no compra. El seller no sabe qué preguntas anticipar | **Existente**: entidad `faqs`, `products` con descripción. Requiere: generador batch liviano | Incluida en Growth / consumible en Starter | **LANZAR YA** |
| 5 | **AI desde Foto → Ficha de Producto** | Productos / Import Wizard | Vendedor artesanal tiene fotos en el celular pero odia escribir fichas. Barrera de onboarding #1 | **Parcial**: Import Wizard existe. Requiere: Vision API (`gpt-4o`), nuevo endpoint, parsing de imagen a campos estructurados | Consumible (créditos premium por uso de Vision) | **DISEÑAR Y VALIDAR** |
| 6 | **AI Alt Text Masivo** | Media Library / Productos | Imágenes sin alt text → invisible para Google Images y accessibility. Complementa SEO Autopilot | **Existente**: Media Library, relación producto-imágenes. Requiere: Vision API batch, extensión del sistema de créditos | Consumible (extensión de packs SEO) | **DISEÑAR Y VALIDAR** |
| 7 | **AI Guías de Talles Automáticas** | Size Guides | Indumentaria sin guía de talles → dudas → no compra o devuelve. Dolor real del fashion seller AR | **Existente**: entidad `size_guides`, `option_sets`. Requiere: templates por rubro + generación IA desde categoría | Incluida en Growth | **DISEÑAR Y VALIDAR** |
| 8 | **AI Copy para Banners/Promos** | Banners / Coupons | Seller crea cupón "VERANO20" pero no sabe qué texto poner en el banner | **Existente**: entidad `banners`, `coupons`. Requiere: generador de copy corto contextualizado | Incluida en Growth | **DISEÑAR Y VALIDAR** |
| 9 | **AI Respuesta a Reviews Negativos** | Reviews Manager | Review negativo sin respuesta profesional daña la tienda | **Existente**: Reviews Manager, contexto de producto/orden. Requiere: prompt con tono profesional rioplatense | Incluida en Growth | **DEJAR PARA DESPUÉS** |
| 10 | **AI Analytics Digest Semanal** | Analytics / Email | Seller no entiende métricas → no toma acción | **Parcial**: `usage_daily` y analytics existen. Requiere: aggregation + narrativa + email semanal | Incluida en Growth | **DEJAR PARA DESPUÉS** |
| 11 | **AI Campaign Kit (fechas AR)** | Marketing (nuevo módulo tenant) | Seller no sabe qué publicar para Hot Sale / CyberMonday AR | **Parcial**: Creative Studio existe super-admin only. Requiere: adaptación a tenant + calendario AR | Addon mensual | **DEJAR PARA DESPUÉS** |
| 12 | **AI Price Advisor con Inflación** | Productos | Pricing en contexto inflacionario es difícil | **No existe**: necesita datos de mercado (scraping/API), FX real-time, índice inflación | Addon mensual | **NO VENDER** |
| 13 | **AI Buyer Support WA (per tenant)** | Orders / Soporte | Comprador manda WA, seller no responde rápido | **Parcial**: outreach WA existe para NV. Requiere: WA Business API per-tenant, n8n per-tenant | Addon premium | **NO VENDER** |
| 14 | **Búsqueda Semántica en Storefront** | Storefront (invisible) | Búsqueda texto exacto falla con sinónimos ("campera" vs "abrigo") | **No existe**: necesita embeddings, vector DB, indexación continua | Invisible, no vendible | **DEJAR PARA DESPUÉS** |
| 15 | **AI Fraud Scoring por Orden** | Orders (invisible) | Fraude en e-commerce AR (chargebacks) | **No existe**: necesita historial de órdenes con volumen | Invisible, incluida | **DEJAR PARA DESPUÉS** |
| 16 | **AI Recomendaciones Cross-sell/Upsell** | Storefront checkout | Bajo AOV, seller no configura relacionados | **No existe**: necesita datos de co-purchase, embeddings | Growth feature | **DEJAR PARA DESPUÉS** |

### Resumen por clasificación

| Clasificación | Cantidad | Features |
|---|---|---|
| LANZAR YA | 4 | #1 Onboarding Coach, #2 Descripción Producto, #3 Respuesta Q&A, #4 FAQ desde Producto |
| DISEÑAR Y VALIDAR | 4 | #5 Foto→Producto, #6 Alt Text, #7 Guías Talles, #8 Copy Banners |
| DEJAR PARA DESPUÉS | 6 | #9 Reviews, #10 Analytics Digest, #11 Campaign Kit, #14 Búsqueda Semántica, #15 Fraud, #16 Cross-sell |
| NO VENDER | 2 | #12 Price Advisor, #13 Buyer WA |

---

## 3. Priorización LATAM

### 5 ejes de evaluación

1. **Dolor AR**: ¿Resuelve un dolor real del seller argentino (no genérico)?
2. **Ventaja competitiva**: ¿Ventaja sobre Tienda Nube o WooCommerce en Argentina?
3. **Costo sostenible**: ¿Se puede sostener con el costo de inferencia dado el precio en ARS/USD?
4. **Infra existente**: ¿Aprovecha infraestructura ya construida?
5. **Upgrade driver**: ¿Empuja upgrade Starter→Growth o activa adopción?

### Evaluación Top 8

| # | Candidata | Dolor AR | Ventaja vs TN/Woo | Costo sostenible | Infra existente | Upgrade driver | **Total** |
|---|-----------|----------|-------------------|-----------------|----------------|---------------|-----------|
| 1 | AI Onboarding Coach | ALTO | ALTO | ALTO | ALTO | ALTO | **25/25** |
| 2 | AI Descripción Producto | ALTO | ALTO | ALTO | ALTO | ALTO | **25/25** |
| 3 | AI Respuesta Q&A | ALTO | ALTO | ALTO | ALTO | MEDIO | **23/25** |
| 5 | AI Foto → Producto | ALTO | ALTO | MEDIO | MEDIO | ALTO | **22/25** |
| 4 | AI FAQ desde Producto | MEDIO | MEDIO | ALTO | ALTO | MEDIO | **21/25** |
| 8 | AI Copy Banners | MEDIO | BAJO | ALTO | ALTO | MEDIO | **18/25** |
| 6 | AI Alt Text Masivo | BAJO | MEDIO | ALTO | ALTO | BAJO | **17/25** |
| 7 | AI Guías de Talles | MEDIO | MEDIO | ALTO | MEDIO | BAJO | **17/25** |

---

## 4. Top 5 para Corrida 2

### 4.1 — AI Onboarding Coach (Score: 25/25)

**Justificación**: Feature más alineada con el north star (primera venta). Un seller que recién crea su tienda no sabe qué hacer después — el coach analiza el estado actual (¿tiene productos? ¿configuró pagos? ¿tiene logo?) y da el siguiente paso concreto. Reduce churn en los primeros 7 días, que es donde se pierde al 80% de los sellers LATAM.

| Aspecto | Detalle |
|---------|---------|
| **Modelo sugerido** | `gpt-4.1-mini` (alternativa más barata: `gpt-4o-mini` ya integrado) |
| **Modo** | **Síncrono** — respuesta en <2s al abrir dashboard. 1 llamada por sesión, cacheable 1h |
| **Dependencias críticas** | Ninguna nueva. Necesita: endpoint que agregue estado de completitud (productos count, MP conectado, logo, envíos) — datos ya disponibles en servicios existentes |
| **Riesgo principal** | Que las recomendaciones sean genéricas y el seller las ignore. Mitigación: prompt fuertemente contextualizado con datos reales de la tienda |

### 4.2 — AI Descripción de Producto con tono rioplatense (Score: 25/25)

**Justificación**: Complemento natural de SEO Autopilot. SEO genera meta-tags; esto genera la descripción larga visible al comprador. El seller AR promedio escribe "Remera algodón" — la IA genera una descripción persuasiva en tono rioplatense que convierte. Reutiliza el 90% de la infra de SEO (créditos, polling, OpenAI).

| Aspecto | Detalle |
|---------|---------|
| **Modelo sugerido** | `gpt-4.1-mini` (alternativa: `gpt-4o-mini`, ya probado en SEO) |
| **Modo** | **Batch** para múltiples productos (reutilizar cola SEO). **Síncrono** para botón "Mejorar" en editor individual |
| **Dependencias críticas** | Extender `seo_ai_credits` para cubrir descripción (nuevo `entity_type: 'product_description'`). Prompt nuevo con tono rioplatense y datos del producto (nombre, categoría, precio, imágenes si hay) |
| **Riesgo principal** | Canibalizar SEO Autopilot si el seller confunde ambas features. Mitigación: UX clara — "SEO optimiza para Google, Descripción optimiza para tu cliente" |

### 4.3 — AI Respuesta Sugerida a Preguntas de Compradores (Score: 23/25)

**Justificación**: Pregunta sin respuesta = venta perdida. El seller AR recibe preguntas a las 23h y responde al mediodía siguiente (si responde). Un botón "Sugerir respuesta" con contexto del producto genera una respuesta profesional en 1 segundo que el seller solo tiene que aprobar. Impacto directo en conversión.

| Aspecto | Detalle |
|---------|---------|
| **Modelo sugerido** | `gpt-4.1-mini` (alternativa: `gpt-4o-mini`) |
| **Modo** | **Síncrono** — respuesta inmediata al hacer click en "Sugerir". Un solo prompt por pregunta |
| **Dependencias críticas** | QA Manager ya existe con tabla de preguntas. Necesita: contexto del producto (nombre, descripción, precio, variantes) inyectado en el prompt. Endpoint nuevo ligero |
| **Riesgo principal** | Respuesta IA incorrecta sobre stock/disponibilidad/envío (datos dinámicos). Mitigación: prompt que instruya "no afirmar stock ni plazos, solo responder sobre el producto" + disclaimer visible |

### 4.4 — AI FAQ desde Descripción de Producto (Score: 21/25)

**Justificación**: Tienda nueva = 0 FAQs = comprador con dudas que no compra. Generar 5-8 preguntas frecuentes desde la descripción del producto llena la tienda de contenido útil en segundos. Costo ínfimo, impacto en SEO (contenido indexable) y en conversión (dudas resueltas preemptivamente).

| Aspecto | Detalle |
|---------|---------|
| **Modelo sugerido** | `gpt-4.1-mini` (alternativa: `gpt-4o-mini`) |
| **Modo** | **Batch** — generar FAQs para múltiples productos en un job. Reutilizar patrón polling de SEO |
| **Dependencias críticas** | Tabla `faqs` ya existe. **PENDIENTE verificar**: si FAQs están vinculadas a producto o son solo globales de la tienda. Si son globales, necesita migración para vincular FAQ→Producto |
| **Riesgo principal** | FAQs genéricas que no aportan valor ("¿Qué es este producto?"). Mitigación: prompt que exija preguntas específicas basadas en atributos reales del producto |

### 4.5 — AI desde Foto → Ficha de Producto (Score: 22/25)

**Justificación**: El seller artesanal/fashion argentino tiene fotos en el celular y cero ganas de escribir. Subir una foto y que la IA genere nombre, descripción, categoría sugerida y precio sugerido por rango elimina la barrera de onboarding más grande. Es el "wow moment" que diferencia NV de TiendaNube.

| Aspecto | Detalle |
|---------|---------|
| **Modelo sugerido** | `gpt-4o` con Vision (alternativa: `gpt-4.1-mini` si soporta vision — verificar) |
| **Modo** | **Síncrono** para 1 foto, **batch** para múltiples. Queue para lotes >5 |
| **Dependencias críticas** | Vision API no integrada hoy (solo text en OpenAI). Necesita: nuevo servicio de procesamiento de imagen, upload temporal, parsing de respuesta estructurada a campos de producto |
| **Riesgo principal** | **Costo**: Vision API ~10-20x más caro que text. A ~USD 0.01-0.03/imagen, batch de 50 = USD 0.50-1.50. Debe ser consumible con pricing claro. Segundo riesgo: calidad variable con fotos de baja calidad (común en celulares AR) |

---

## 5. Anti-humo

### Features que suenan bien pero NO van

| Feature | Razón de rechazo | Veredicto |
|---------|------------------|-----------|
| **AI Price Advisor con Inflación** | **No hay datos de mercado.** NV no tiene precios de competencia, índices de inflación en tiempo real, ni datos de elasticidad de precios. Requeriría scraping de MercadoLibre/TiendaNube (legal y técnicamente inviable) o API de precios que no existe para retail AR. Una recomendación de precio sin datos es peor que ninguna. | **NO VENDER** |
| **AI Buyer Support WA (per tenant)** | **Costo de infra insostenible.** WA Business API requiere número verificado por tenant, approval de Meta, n8n flow por tenant. NV atendería incidentes de bots respondiendo mal a compradores. El seller AR paga USD 20-60/mes — no puede costear un bot WA premium. TN tampoco lo tiene por la misma razón. | **NO VENDER** |
| **AI Fraud Scoring** | **No hay volumen de datos.** Con 2 tiendas activas, cualquier modelo de fraud sería puro ruido. Se necesitan miles de órdenes con etiquetas de chargeback. MP ya tiene su propio fraud scoring. Prematura por 12-18 meses mínimo. | **DEJAR PARA DESPUÉS** |
| **Búsqueda Semántica Storefront** | **Infraestructura desproporcionada.** Vector DB, pipeline de embeddings, indexación continua. Para catálogos de 50-2000 productos, búsqueda full-text con `pg_trgm` + diccionario español da el 90% del valor al 5% del costo. | **DEJAR PARA DESPUÉS** |
| **AI Cross-sell/Upsell** | **No hay datos de co-purchase.** Sin volumen de órdenes, las recomendaciones serían aleatorias. Modelos colaborativos necesitan N>1000 órdenes. "Productos relacionados" manual por categoría cubre el 80%. | **DEJAR PARA DESPUÉS** |
| **AI Campaign Kit** | **El seller necesita producto y primera venta, no marketing automation.** Creative Studio ya existe para super-admin. Migrar a tenant antes de tener sellers activos = feature que nadie usará 6+ meses. Canva gratis resuelve el 80% para el seller chico. | **DEJAR PARA DESPUÉS** |
| **AI Analytics Digest** | **No hay datos que digerir.** Un digest de "0 ventas, 3 visitas" aporta frustración, no valor. Tiene sentido cuando el seller vende >10 órdenes/semana. Prematura 6+ meses post-lanzamiento. | **DEJAR PARA DESPUÉS** |
| **AI Clasificación de Tickets** | **Feature interna disfrazada de producto.** Optimiza operaciones de NV, no del seller. No es vendible ni monetizable. Si se implementa, va como mejora interna. | **NO VENDER** |

---

## 6. Preguntas bloqueantes

### Para responder ANTES de Corrida 2

| # | Pregunta | Bloquea a | Urgencia |
|---|----------|-----------|----------|
| Q1 | **¿Cuál es el pricing actual de `gpt-4.1-mini` y `gpt-4.1`?** SEO Autopilot usa `gpt-4o-mini`. ¿Hay razón para migrar? ¿Pricing confirmado? | Costeo de todas las features | **ALTA** |
| Q2 | **¿Redis está activo en Railway o corre todo en fallback in-memory?** Rate limiting por tenant y caching de respuestas IA dependen de esto | Features síncronas (#1 Coach, #3 Q&A) | **ALTA** |
| Q3 | **¿Las FAQs están vinculadas a producto o son solo globales de la tienda?** Si son globales, necesitamos migración para vincular FAQ→Producto | Feature #4 (AI FAQ) | **MEDIA** |
| Q4 | **¿Qué FX reference se usa para pricing de créditos en ARS?** Los packs SEO ya están en ARS cents pero el tipo de cambio de referencia no está documentado | Pricing de créditos descripción + Vision | **ALTA** |
| Q5 | **¿El seller ya ve el QA Manager en producción?** La tabla existe pero necesito confirmar que el frontend está habilitado y que hay preguntas reales | Feature #3 (AI Respuesta Q&A) | **MEDIA** |
| Q6 | **¿El Import Wizard soporta imagen como input o solo JSON/Excel?** Si acepta imágenes, #5 podría montarse ahí | Feature #5 (AI Foto→Producto) | **MEDIA** |
| Q7 | **¿Cuántas preguntas y reviews hay en producción en las 2 tiendas activas?** Si es 0, las features #3 y #9 no tienen sobre qué operar | Features de Q&A y Reviews | **MEDIA** |
| Q8 | **¿El Marketing AI Suite se va a exponer a tenants en algún momento?** | Priorización de Campaign Kit | **BAJA** |

---

## 7. Supuestos base para costeo (Corrida 2)

| Supuesto | Valor | Estado |
|----------|-------|--------|
| Modelo base de texto | `gpt-4.1-mini` o `gpt-4o-mini` | **PENDIENTE Q1** — verificar pricing y disponibilidad |
| Modelo premium de texto | `gpt-4.1` | **PENDIENTE Q1** |
| Modelo vision | `gpt-4o` con vision | **PENDIENTE** — verificar si `gpt-4.1-mini` soporta vision |
| Tokens promedio por descripción simple | ~800 input / ~300 output | INFERIDO |
| Tokens promedio por análisis imagen | ~1500 input / ~400 output | INFERIDO |
| Tokens promedio por respuesta Q&A | ~600 input / ~150 output | INFERIDO |
| Tokens promedio por FAQ batch (5 preguntas) | ~800 input / ~500 output | INFERIDO |
| Tokens promedio por onboarding coach | ~1200 input / ~300 output | INFERIDO |
| Fee MP en suscripciones NV | ~3.5-5% | **PENDIENTE** |
| Tipo de cambio ARS/USD para pricing | Pendiente FX_ref (ver Plans doc) | **PENDIENTE Q4** |
| Redis disponible en Railway | Sin confirmar | **PENDIENTE Q2** |
| Costo estimado por invocación gpt-4o-mini | ~USD 0.0003-0.0008 | **PENDIENTE** verificar pricing actual |
| Costo estimado por invocación vision | ~USD 0.01-0.03 | **PENDIENTE** verificar pricing actual |

---

## Patrón reutilizable descubierto

> **Blueprint SEO Autopilot**: El flujo SEO Autopilot → créditos → MercadoPago → ledger inmutable es el patrón probado para features IA monetizables. Cualquier feature nueva que siga este patrón se implementa en ~40% del tiempo. Las features del Top 5 fueron seleccionadas en parte por su capacidad de reutilizar este blueprint.

> **Propiedad económica del Top 3**: Las features #1 (Coach), #3 (Q&A), #4 (FAQ) cuestan <$0.001/invocación con gpt-4o-mini. Pueden ser incluidas en el plan sin riesgo de pérdida → armas de retención y diferenciación, no necesitan monetización individual.

---

## Próximos pasos — Corrida 2

La Corrida 2 debe producir para cada feature del Top 5:

1. **Spec técnica**: endpoints, DTOs, tablas/migraciones necesarias
2. **Prompts**: system prompt + user prompt template con variables
3. **Costeo detallado**: costo por invocación con pricing verificado, costo mensual proyectado por tier
4. **Estructura de créditos/monetización**: pricing en ARS, packs, inclusión por plan
5. **Estimación de esfuerzo**: días de desarrollo, dependencias entre features
6. **Orden de implementación**: cuál primero, cuál después, por qué

### Responder antes de iniciar Corrida 2:
- Q1, Q2, Q4 (urgencia ALTA)
- Q3, Q5, Q6, Q7 (urgencia MEDIA — pueden responderse durante la corrida)

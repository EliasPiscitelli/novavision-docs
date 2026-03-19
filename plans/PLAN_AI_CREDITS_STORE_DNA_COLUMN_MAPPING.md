# Plan: Sistema de AI Credits + Store DNA + Column Mapping + Admin Pricing

## Context

NovaVision necesita un sistema integral de IA monetizable para el admin dashboard del tenant. Esto incluye:
1. **AI Credits por feature** con tiers Normal/Pro vendidos en Addon Store
2. **Store DNA** — analisis IA de la tienda que genera una instruccion general, usada como contexto base por todas las features IA
3. **AI Column Mapping** — mapeo inteligente de columnas para migracion de catalogo desde otras plataformas
4. **Super Admin AI Pricing** — dashboard dinamico para ajustar precios, modelos, y creditos de bienvenida
5. **UX/UI completa** — modales, botones, interceptores, widgets en TODOS los screens impactados

**Decisiones del usuario:**
- Creditos por funcionalidad (un pool por cada feature IA)
- SEO AI credits se mantienen separados
- Welcome credits de bienvenida: Starter pocos, Growth mas (tambien usables como promo)
- Column mapping generico + deteccion automatica de plataformas conocidas
- Tiers de calidad: Normal (modelo barato) y Pro (modelo potente, mas creditos)
- Store DNA: la IA analiza la tienda y genera una instruccion general que alimenta todas las demas features

---

## Validacion contra BD real (2026-03-17)

| Tabla/Vista | DB | Existe | Notas |
|---|---|---|---|
| `account_action_credit_ledger` | Admin | si | 15 cols, `expires_at`, `action_code`, `credits_delta` |
| `account_action_credit_balance_view` | Admin | si | Agrupa `(account_id, action_code, addon_key)`, filtra expirados |
| `addon_catalog` | Admin | si | 25 cols, families: capacity/content/media/services. **Falta `ai`** |
| `seo_ai_credits` | Admin | si | 9 cols. Se mantiene separado |
| `products` | Backend | si | 42 cols incl. description, meta_title, seo_* |
| `product_questions` | Backend | si | 15 cols. Tiene `product_id`, `body`, `parent_id` (threaded) |
| `product_reviews` | Backend | si | 18 cols. Tiene `admin_reply`, `admin_reply_by` |
| `faqs` | Backend | si | **5 cols: id, question, answer, number, client_id. NO product_id** |
| `seo_settings` | Backend | si | `site_title`, `site_description`, `brand_name` |
| `nv_accounts` | Admin | si | **NO tiene `industry`, `brand_tone`, `target_audience`** |
| `client_home_settings` | Backend | si | `palette_key`, `template_key`, `identity_config` |
| `contact_info` | Backend | si | Direccion, telefono, email, WhatsApp |
| `social_links` | Backend | si | Facebook, Instagram, etc. |

**Hallazgo SEO packs**: Usan `commercial_model='permanent'` y `grants_credits=0`. Nuestros packs AI usaran `consumable_action` con grant automatico via `grantConsumableCredits()`.

---

## PARTE 1 — Store DNA (Contexto IA dinamico de tienda)

### 1.1 Concepto

Antes de que cualquier feature IA genere contenido, necesita entender **quien es esta tienda**. El Store DNA es un analisis IA que:
1. Agrega datos reales de la tienda (nombre, productos, categorias, precios, tono, audiencia)
2. Genera una **instruccion maestra** en lenguaje natural: "Sos el copywriter de [Tienda X], una marca de [rubro] con estilo [tono], dirigida a [audiencia], con precios en rango [X-Y ARS]..."
3. Esta instruccion se cachea y se inyecta como **system prompt base** en TODAS las llamadas IA
4. Se regenera cuando cambian datos clave de la tienda (nuevo producto, cambio de categoria, etc.)

### 1.2 Datos que alimentan el Store DNA

**Datos ya disponibles (sin migracion):**
| Dato | Fuente | Campo |
|------|--------|-------|
| Nombre de tienda | `nv_accounts` / `seo_settings` | `store_name`, `brand_name` |
| Pais | `nv_accounts` | `country` |
| Plan | `clients` | `plan_key` |
| Categorias | `categories` (Backend) | Todas las categorias activas |
| Rango de precios | `products` (Backend) | MIN/MAX de `originalPrice` |
| Productos top | `products` (Backend) | `featured=true` o top 5 por precio |
| Descripcion de tienda | `seo_settings` | `site_description` |
| Titulo del sitio | `seo_settings` | `site_title` |
| Logo | `logos` | existencia |
| Redes sociales | `social_links` | plataformas activas |
| Paleta de colores | `client_home_settings` | `palette_key` |
| Template | `client_home_settings` | `template_key` |

**Datos nuevos (migracion simple):**
| Dato | Tabla | Campo nuevo | Tipo |
|------|-------|-------------|------|
| Rubro/industria | `nv_accounts` | `industry` | `TEXT` nullable |
| Tono de marca | `nv_accounts` | `brand_tone` | `TEXT` nullable |
| Audiencia objetivo | `nv_accounts` | `target_audience` | `TEXT` nullable |
| Propuesta de valor | `nv_accounts` | `value_proposition` | `TEXT` nullable |

Estos 4 campos pueden ser:
- Completados manualmente por el seller en settings
- **O generados por IA** en la primera ejecucion del Store DNA (el seller confirma/edita)

### 1.3 Servicio StoreContextService

**Archivo nuevo:** `apps/api/src/ai-credits/store-context.service.ts`

```
class StoreContextService {
  async buildStoreContext(clientId: string): Promise<StoreContext>
    // 1. Agrega datos de nv_accounts, seo_settings, products, categories
    // 2. Retorna objeto estructurado

  async generateStoreDNA(clientId: string, tier: 'normal'|'pro'): Promise<string>
    // 1. buildStoreContext()
    // 2. Llama OpenAI con prompt de analisis
    // 3. Genera instruccion maestra en lenguaje natural
    // 4. Guarda en cache (Redis o tabla) con TTL 24h
    // 5. Retorna instruccion

  async getOrGenerateStoreDNA(clientId: string): Promise<string>
    // 1. Busca en cache
    // 2. Si no existe o expirado -> regenera
    // 3. Retorna instruccion

  async invalidateStoreDNA(clientId: string): void
    // Invalida cache cuando cambian datos clave
}
```

**Tabla de cache** (Admin DB): `store_dna_cache`
```sql
CREATE TABLE store_dna_cache (
  client_id UUID PRIMARY KEY,
  account_id UUID NOT NULL,
  store_context JSONB NOT NULL,          -- datos estructurados
  dna_instruction TEXT NOT NULL,          -- instruccion generada por IA
  model_used TEXT NOT NULL,               -- 'gpt-4o-mini' o 'gpt-4o'
  tokens_used INT,
  generated_at TIMESTAMPTZ NOT NULL,
  expires_at TIMESTAMPTZ NOT NULL,        -- generated_at + 24h
  invalidated_at TIMESTAMPTZ              -- NULL si valido
);
```

**Prompt de generacion del Store DNA:**
```
Analiza esta tienda de e-commerce argentina y genera una instruccion concisa (max 200 palabras)
que sirva como contexto base para un asistente IA. La instruccion debe capturar:
- Quien es la tienda (nombre, rubro, posicionamiento)
- A quien le vende (audiencia, segmento)
- Como habla (tono: formal/casual/juvenil/premium/tecnico)
- Rango de precios y nivel del mercado
- Diferenciadores o propuesta de valor si los hay

Datos de la tienda:
- Nombre: {store_name}
- Descripcion: {site_description}
- Pais: {country}
- Categorias: {categories}
- Rango de precios: {price_min} - {price_max} {currency}
- Productos destacados: {featured_products}
- Redes activas: {social_links}
- Industria: {industry || "no especificada"}
- Tono de marca: {brand_tone || "no especificado"}
- Audiencia: {target_audience || "no especificada"}

Responde SOLO con la instruccion, sin formato ni markdown. Usa espanol rioplatense.
```

**Resultado ejemplo:**
> "Sos el asistente de Luna Textil, una tienda de indumentaria femenina casual-chic para mujeres de 25 a 40 anios en Argentina. La marca tiene un tono calido y cercano, con precios en rango medio ($15.000 - $45.000 ARS). Se enfoca en algodon premium y disenio propio. Comunicate como una amiga que sabe de moda, no como vendedora. Evita lenguaje tecnico. Usa espanol rioplatense."

### 1.4 Integracion del Store DNA en features IA

Cada servicio IA inyecta el Store DNA como prefijo del system prompt:

```typescript
// Ejemplo: AI Product Description
const storeDNA = await storeContext.getOrGenerateStoreDNA(clientId);
const systemPrompt = `${storeDNA}\n\n${PRODUCT_DESCRIPTION_SYSTEM_PROMPT}`;
```

Esto hace que TODAS las respuestas IA sean coherentes con la identidad de la tienda.

### 1.5 Store DNA NO consume creditos

La generacion/regeneracion del Store DNA es **gratuita** — es infraestructura que mejora todas las features. Se regenera:
- Al crear la tienda (provisioning)
- Cada 24h (TTL)
- Cuando el seller cambia datos clave (categorias, SEO settings, nuevo campo industry/tone)
- Manualmente desde un boton "Regenerar perfil IA" en settings

---

## PARTE 2 — Sistema de AI Credits por Feature con Tiers

### 2.1 Tiers Normal / Pro

| Tier | Modelo | Consumo | UX |
|------|--------|---------|-----|
| **Normal** | `gpt-4o-mini` | 1x base | Toggle por defecto |
| **Pro** | `gpt-4o` | 2-5x base (segun feature) | Toggle premium con indicador de creditos |

El seller elige tier con un toggle en cada boton IA. El costo se muestra en tiempo real: "Normal: 1 credito / Pro: 3 creditos".

### 2.2 Tablas nuevas (Admin DB)

**`ai_feature_pricing`** — configurable desde super-admin:
```sql
CREATE TABLE ai_feature_pricing (
  action_code TEXT NOT NULL,
  tier TEXT NOT NULL DEFAULT 'normal',
  credit_cost INT NOT NULL,
  model_id TEXT NOT NULL,
  temperature NUMERIC(2,1) DEFAULT 0.4,
  max_tokens INT DEFAULT 500,
  label TEXT NOT NULL,
  description TEXT,
  is_active BOOLEAN DEFAULT true,
  PRIMARY KEY (action_code, tier)
);
```

| action_code | tier | credit_cost | model_id | label |
|---|---|---|---|---|
| `ai_product_description` | normal | 1 | gpt-4o-mini | Descripcion Normal |
| `ai_product_description` | pro | 3 | gpt-4o | Descripcion Pro |
| `ai_qa_answer` | normal | 1 | gpt-4o-mini | Respuesta Normal |
| `ai_qa_answer` | pro | 2 | gpt-4o | Respuesta Pro |
| `ai_faq_generation` | normal | 1 | gpt-4o-mini | FAQ Normal |
| `ai_faq_generation` | pro | 3 | gpt-4o | FAQ Pro |
| `ai_photo_product` | normal | 3 | gpt-4o-mini | Foto Normal |
| `ai_photo_product` | pro | 5 | gpt-4o | Foto Pro |
| `ai_column_mapping` | normal | 1 | gpt-4o-mini | Mapeo Normal |
| `ai_column_mapping` | pro | 2 | gpt-4o | Mapeo Pro |

**`ai_welcome_credit_config`** — configurable desde super-admin:
```sql
CREATE TABLE ai_welcome_credit_config (
  plan_key TEXT NOT NULL,
  action_code TEXT NOT NULL,
  credits INT NOT NULL,
  expires_days INT DEFAULT 90,
  is_active BOOLEAN DEFAULT true,
  PRIMARY KEY (plan_key, action_code)
);
```

| plan_key | action_code | credits | expires_days |
|---|---|---|---|
| starter | ai_product_description | 5 | 90 |
| starter | ai_qa_answer | 10 | 90 |
| starter | ai_faq_generation | 3 | 90 |
| starter | ai_photo_product | 3 | 90 |
| starter | ai_column_mapping | 2 | 90 |
| growth | ai_product_description | 20 | 120 |
| growth | ai_qa_answer | 50 | 120 |
| growth | ai_faq_generation | 15 | 120 |
| growth | ai_photo_product | 10 | 120 |
| growth | ai_column_mapping | 5 | 120 |
| enterprise | ai_product_description | 50 | 180 |
| enterprise | ai_qa_answer | 200 | 180 |
| enterprise | ai_faq_generation | 50 | 180 |
| enterprise | ai_photo_product | 30 | 180 |
| enterprise | ai_column_mapping | 10 | 180 |

### 2.3 Addon catalog entries (familia `ai`)

| addon_key | display_name | action_code | grants_credits | price_cents |
|---|---|---|---|---|
| `ai_desc_pack_10` | AI — 10 Descripciones | `ai_product_description` | 10 | 2990 |
| `ai_desc_pack_50` | AI — 50 Descripciones | `ai_product_description` | 50 | 9990 |
| `ai_qa_pack_20` | AI — 20 Respuestas Q&A | `ai_qa_answer` | 20 | 1990 |
| `ai_qa_pack_100` | AI — 100 Respuestas Q&A | `ai_qa_answer` | 100 | 5990 |
| `ai_faq_pack_10` | AI — FAQs para 10 Productos | `ai_faq_generation` | 10 | 3990 |
| `ai_faq_pack_50` | AI — FAQs para 50 Productos | `ai_faq_generation` | 50 | 12990 |
| `ai_photo_pack_10` | AI — 10 Fichas desde Foto | `ai_photo_product` | 10 | 6990 |
| `ai_photo_pack_50` | AI — 50 Fichas desde Foto | `ai_photo_product` | 50 | 24990 |
| `ai_mapping_pack_5` | AI — 5 Analisis de Archivo | `ai_column_mapping` | 5 | 2990 |
| `ai_mapping_pack_15` | AI — 15 Analisis de Archivo | `ai_column_mapping` | 15 | 6990 |

Todos con: `addon_type='consumable'`, `billing_mode='one_time'`, `family='ai'`, `commercial_model='consumable_action'`, `is_active=true`, `allowed_plans='["starter","growth","enterprise"]'`

### 2.4 Modulo ai-credits (backend)

**Ubicacion:** `apps/api/src/ai-credits/`

| Archivo | Responsabilidad |
|---|---|
| `ai-credits.module.ts` | Registra providers, exporta servicio y guard |
| `ai-credits.service.ts` | Balance, consumo, grant, pricing lookup |
| `ai-credits.controller.ts` | Endpoints tenant: balances, pricing, historial |
| `ai-credits.admin.controller.ts` | Endpoints super-admin: CRUD pricing, welcome config, grant promo |
| `ai-credits.guard.ts` | Guard que valida creditos antes de accion |
| `ai-credits.decorator.ts` | `@RequireAiCredits(actionCode)` |
| `store-context.service.ts` | Store DNA: build, generate, cache, invalidate |

**AiCreditsService — metodos:**
```
getBalance(accountId, actionCode) -> number
getAllAiBalances(accountId) -> { action_code, available }[]
getFeaturePricing(actionCode?) -> { action_code, tier, credit_cost, model_id, label }[]
consumeCredit(accountId, clientId, actionCode, tier, metadata?) -> void
assertAvailable(accountId, actionCode, tier) -> void | throw 402
grantWelcomeCredits(accountId, planKey) -> void
grantPromoCredits(accountId, actionCode, amount, expiresDays?) -> void
```

**AiCreditsGuard + @RequireAiCredits(actionCode):**
- Lee `tier` de `req.body.ai_tier || 'normal'`
- Lee `credit_cost` de `ai_feature_pricing`
- Si insuficiente -> HTTP 402:
```json
{
  "error": "insufficient_ai_credits",
  "action_code": "ai_product_description",
  "tier": "pro",
  "required": 3,
  "available": 1,
  "feature_label": "Descripcion de Producto",
  "addon_store_url": "/admin-dashboard?addonStore&family=ai"
}
```

### 2.5 Endpoints tenant

```
GET  /ai-credits/balances          -> todos los balances AI
GET  /ai-credits/pricing           -> pricing por feature (normal + pro)
GET  /ai-credits/history           -> historial (paginado, filtrable por action_code)
GET  /ai-credits/store-dna         -> Store DNA actual + datos del contexto
POST /ai-credits/store-dna/regenerate -> Forzar regeneracion
```

### 2.6 Endpoints super-admin

```
-- Feature Pricing CRUD
GET    /admin/ai-credits/pricing                -> todas las features con tiers
PATCH  /admin/ai-credits/pricing/:actionCode    -> editar pricing (credit_cost, model_id, temperature, etc.)
POST   /admin/ai-credits/pricing                -> crear nueva feature

-- Welcome Credits CRUD
GET    /admin/ai-credits/welcome-config         -> config actual por plan
PATCH  /admin/ai-credits/welcome-config         -> editar credits/expires por plan

-- Addon Packs (reusa /admin/addons pattern)
GET    /admin/ai-credits/packs                  -> packs AI del addon_catalog
PATCH  /admin/ai-credits/packs/:addonKey        -> editar precio/credits/active

-- Client Credits
GET    /admin/ai-credits/clients/:accountId/balances   -> balances de un cliente
POST   /admin/ai-credits/clients/:accountId/adjust     -> grant/revoke manual
GET    /admin/ai-credits/clients/:accountId/history     -> historial de un cliente
GET    /admin/ai-credits/clients/:accountId/store-dna   -> Store DNA de un cliente
```

### 2.7 Integracion provisioning (welcome credits)

**Archivo:** `apps/api/src/provisioning/provisioning-worker.service.ts`

Nuevo step `GRANT_WELCOME_AI_CREDITS` despues de `PROVISION_CLIENT`:
1. Lee `ai_welcome_credit_config WHERE plan_key AND is_active`
2. Para cada row -> INSERT grant en `account_action_credit_ledger`
3. Genera Store DNA inicial (background, no bloquea)
4. Emite `lifecycle_event: 'welcome_ai_credits_granted'`

---

## PARTE 3 — AI Column Mapping para Import

### 3.1 Flujo completo

```
1. Seller entra a "Importar" -> ve opcion "Subir archivo Excel/CSV"
2. Sube archivo (max 5MB, max 500 filas)
3. Backend parsea headers + 3 filas de muestra
4. Detecta plataforma conocida:
   -> TiendaNube/WooCommerce/MercadoLibre -> mapeo directo SIN credito
   -> Desconocido -> consume 1 credito ai_column_mapping (tier elegido)
5. Frontend muestra tabla de mapeo interactiva:
   | Columna archivo | -> Campo NV (dropdown) | Confianza | Muestra |
   | "Nombre"        | name                   | Auto      | "Zapatilla Nike" |
   | "$ Venta"       | originalPrice          | 92%       | "$15.990" |
   | "Cod.Barra"     | sku                    | 88%       | "7891234" |
   | "Talle"         | tags                   | 45%       | "M" |
6. Seller ajusta dropdowns y confirma
7. Backend transforma -> validateAndCreateBatch() -> flujo normal Import Wizard
```

### 3.2 Platform signatures (sin IA)

**Archivo:** `apps/api/src/import-wizard/platform-signatures.ts`

| Plataforma | Headers firma (>=3 match) |
|---|---|
| TiendaNube | `Identificador de URL`, `Nombre del Producto`, `Categoria`, `Precio`, `Variante1` |
| WooCommerce | `post_title`, `regular_price`, `_sku`, `tax:product_cat`, `post_content` |
| MercadoLibre | `Titulo de publicacion`, `Precio`, `SKU del vendedor`, `Categoria` |

Complementa con `excelProductParser.ts` existente (30+ aliases de columnas con fuzzy matching).

### 3.3 Nuevos endpoints

**Archivo:** `apps/api/src/import-wizard/import-wizard.controller.ts`

```
POST /import-wizard/analyze-file
  Guard: ClientDashboardGuard
  Input: multipart file + { ai_tier?: 'normal'|'pro' }
  Output: { file_key, platform_detected, headers, sample_rows, total_rows,
            mapping_suggestions: [{ source, target, confidence, source_type }],
            credit_consumed, tier_used }

POST /import-wizard/apply-mapping
  Guard: ClientDashboardGuard
  Input: { file_key, mapping: [{ source, target }] }
  Output: batch (respuesta de validateAndCreateBatch)
```

### 3.4 Servicio ImportMappingService

**Archivo:** `apps/api/src/import-wizard/import-mapping.service.ts`

```
parseFile(buffer, mimetype) -> { headers, sampleRows, totalRows }
detectPlatform(headers) -> { platform, mapping } | null
suggestMappingWithAI(headers, sampleRows, tier, storeDNA?) -> ColumnMapping[]
applyMappingToFile(buffer, mimetype, mapping) -> ProductImportV1[]
```

---

## PARTE 4 — Super Admin: AI Pricing Dashboard

### 4.1 Nueva vista: AiCreditsPricingView

**Archivo:** `apps/admin/src/pages/AdminDashboard/AiCreditsPricingView.jsx`

Sigue patron de `SeoAiPricingView.jsx` (3 tabs, inline editing, toast feedback).

**Tab 1: Features & Pricing**
- Tabla: action_code | Label | Normal (cost, model) | Pro (cost, model) | Active | Acciones
- Inline edit: cambiar credit_cost, model_id, temperature, max_tokens por tier
- Toggle is_active por feature
- API: GET/PATCH `/admin/ai-credits/pricing`

**Tab 2: Packs de Creditos**
- Tabla: addon_key | Display Name | Action Code | Credits | Price (ARS) | Active | Acciones
- Inline edit: precio, grants_credits, is_active
- API: GET/PATCH `/admin/ai-credits/packs`

**Tab 3: Welcome Credits**
- Tabla agrupada por plan: plan_key | Action Code | Credits | Expires (dias) | Active
- Inline edit: credits, expires_days, is_active
- API: GET/PATCH `/admin/ai-credits/welcome-config`

**Tab 4: Creditos por Cliente**
- Buscador por slug/email
- Tarjeta de balance por feature: { action_code: balance }
- Historial de movimientos (grant, consume, expire, promo)
- Boton "Otorgar creditos" -> modal con action_code, amount, reason, expires_days
- Boton "Ver Store DNA" -> muestra instruccion generada + datos del contexto
- API: GET/POST `/admin/ai-credits/clients/:accountId/*`

### 4.2 Nav item

**Archivo:** `apps/admin/src/pages/AdminDashboard/index.jsx` (NAV_ITEMS)

```javascript
{
  key: 'ai-credits-pricing',
  label: 'AI Credits & Pricing',
  icon: 'robot-icon',
  category: 'billing',
  superOnly: true,
  component: lazy(() => import('./AiCreditsPricingView')),
}
```

Se ubica en categoria "Facturacion y Planes" junto a "SEO AI Pricing".

### 4.3 Client Details integration

**Archivo:** `apps/admin/src/pages/ClientDetails/` + hook `useClientConsumables.js`

En la ficha del cliente agregar seccion "AI Credits":
- Balance por feature IA (tabla)
- Store DNA actual (collapsible)
- Boton "Regenerar Store DNA"
- Boton "Otorgar creditos promo"

---

## PARTE 5 — Mapa completo de impacto UX/UI

### 5.1 Screens del TENANT DASHBOARD impactados

#### A. Product Editor (`ProductModal` en ProductDashboard)
**Archivo:** `apps/web/src/components/admin/ProductDashboard/`
- **Nuevo boton** "Mejorar descripcion con IA" debajo del campo `description`
- **Toggle** Normal / Pro con indicador de creditos: "1 cr" / "3 cr"
- **Flujo**: Click -> loading spinner -> textarea se rellena con descripcion generada
- **Si 0 creditos**: Boton disabled + tooltip "Sin creditos — Compra en Addon Store"
- **Endpoint**: POST `/products/:id/ai-description` con `{ ai_tier, current_description? }`

#### B. QA Manager (`QADashboard` -> `ThreadPanel`)
**Archivo:** `apps/web/src/components/admin/QADashboard/index.jsx`
- **Nuevo boton** "Sugerir respuesta" en `ActionsRow` del ThreadPanel
- **Toggle** Normal / Pro
- **Flujo**: Click -> llamada API -> `ReplyTextarea` se rellena con sugerencia
- **Label**: "Respuesta sugerida por IA — edita antes de enviar"
- **Endpoint**: POST `/questions/:id/ai-suggest` con `{ ai_tier }`

#### C. Reviews Manager (`ReviewsDashboard` -> `ReplyForm`)
**Archivo:** `apps/web/src/components/admin/ReviewsDashboard/index.jsx`
- **Nuevo boton** "Sugerir respuesta" en `ActionsRow`
- **Flujo**: Click -> abre `ReplyForm` con texto prellenado
- **Endpoint**: POST `/reviews/:id/ai-suggest` con `{ ai_tier }`

#### D. FAQ Manager (`FaqSection`)
**Archivo:** `apps/web/src/components/admin/FaqSection/index.jsx`
- **Nuevo boton** "Generar desde productos" en `createCtn` (header)
- **Modal**: Selector de productos (checkboxes) + toggle Normal/Pro + indicador "X creditos"
- **Flujo**: Selecciona productos -> genera FAQs -> muestra preview -> confirma -> inserta
- **Nuevo boton** "Mejorar" en modal de edicion de FAQ individual
- **Endpoint**: POST `/faqs/ai-generate` con `{ product_ids[], ai_tier }`
- **Endpoint**: POST `/faqs/:id/ai-enhance` con `{ ai_tier }`

#### E. Import Wizard (paso nuevo)
**Archivo:** `apps/web/src/components/admin/ImportWizard/index.jsx`
- **Nuevo Step 0**: "Subir archivo" con DropZone para Excel/CSV
- **Pantalla de mapeo**: Tabla con columnas del archivo -> dropdowns de campos NV
- **Indicadores**: "Detectamos formato TiendaNube" o "Mapeo sugerido por IA (1 credito)"
- **Boton**: "Confirmar mapeo y continuar" -> transforma -> pasa al Step 1 existente

#### F. Addon Store (`AddonStoreDashboard`)
**Archivo:** `apps/web/src/components/admin/AddonStoreDashboard/index.jsx`
- **Nueva familia "ai"** con monograma y label "Inteligencia Artificial"
- **Filtro por familia**: Agregar "IA" a los tabs/filtros
- **Cards de packs AI**: Misma estructura que packs SEO pero con action_code diferente
- **Tab "Mis consumibles"**: Mostrar balances de `ai_*` action_codes con labels descriptivos

#### G. Usage Dashboard (`UsageDashboard`)
**Archivo:** `apps/web/src/components/admin/UsageDashboard/`
- **Nueva seccion** "Creditos IA" con barras de progreso por feature
- **Cada feature**: nombre + barra + "X disponibles" + boton "Recargar"

#### H. Header Bar (global)
**Archivo:** `apps/web/src/pages/AdminDashboard/index.jsx` (`HeaderActions`)
- **Nuevo widget** "AI" badge con total de creditos sumados
- **Tooltip**: Desglose por feature
- **Click**: Navega a Addon Store filtrado por AI

#### I. Settings / Store Identity (nuevo sub-panel)
**Archivo:** `apps/web/src/components/admin/IdentitySection/` (o nuevo)
- **Seccion "Perfil IA de tu tienda"** en settings
- **Muestra**: Store DNA generado (read-only, resumen en lenguaje natural)
- **Campos editables**: Rubro, Tono de marca, Audiencia objetivo, Propuesta de valor
- **Boton**: "Regenerar perfil IA" -> invalida cache -> regenera

### 5.2 Modales nuevos

| Modal | Trigger | Contenido | Acciones |
|---|---|---|---|
| **CreditInsufficientModal** | HTTP 402 interceptor | "Te quedaste sin creditos de [feature]. Necesitas X, tenes Y." | "Ir al Addon Store" / "Cancelar" |
| **AiResultPreviewModal** | Despues de generar descripcion/FAQ | Muestra resultado generado, diff con original si aplica | "Usar" / "Editar" / "Regenerar" / "Cancelar" |
| **ColumnMappingModal** | Despues de analizar archivo | Tabla de mapeo interactivo | "Confirmar" / "Cancelar" |
| **ProductSelectorModal** | Generate FAQs from products | Checkboxes de productos + count + cost | "Generar" / "Cancelar" |
| **StoreDNAPreviewModal** | Settings o super-admin | Store DNA texto + datos usados | "Regenerar" / "Cerrar" |
| **TierSelectorInline** | Cada boton IA | Toggle Normal/Pro con costo | Integrado en boton |

### 5.3 Interceptor HTTP 402 (global)

**Archivo:** `apps/web/src/api/client.ts`

```typescript
// Agregar al response interceptor existente:
if (error.response?.status === 402 && error.response.data?.error === 'insufficient_ai_credits') {
  window.dispatchEvent(new CustomEvent('ai-credits-insufficient', {
    detail: error.response.data
  }));
}
```

**Listener en AdminDashboard:**
```typescript
useEffect(() => {
  const handler = (e) => setInsufficientCreditsData(e.detail);
  window.addEventListener('ai-credits-insufficient', handler);
  return () => window.removeEventListener('ai-credits-insufficient', handler);
}, []);
// Renderiza <CreditInsufficientModal> cuando insufficientCreditsData !== null
```

### 5.4 Componentes compartidos nuevos

| Componente | Uso | Props |
|---|---|---|
| `AiTierToggle` | En cada boton IA | `{ actionCode, onSelect, disabled }` |
| `AiCreditsBadge` | Header + inline | `{ actionCode, balance }` |
| `AiButton` | Wrapper standard para botones IA | `{ actionCode, tier, onClick, label, icon }` |
| `CreditInsufficientModal` | Global | `{ data, onClose, onGoToStore }` |
| `AiResultPreview` | Post-generation | `{ result, original?, onAccept, onRegenerate }` |

---

## PARTE 6 — Migraciones SQL

### Migracion Admin DB: `20260318_ai_credits_system.sql`
```sql
-- 1. Nuevos campos en nv_accounts
ALTER TABLE nv_accounts ADD COLUMN industry TEXT;
ALTER TABLE nv_accounts ADD COLUMN brand_tone TEXT;
ALTER TABLE nv_accounts ADD COLUMN target_audience TEXT;
ALTER TABLE nv_accounts ADD COLUMN value_proposition TEXT;

-- 2. Tabla ai_feature_pricing
CREATE TABLE ai_feature_pricing (...);  -- ver seccion 2.2

-- 3. Tabla ai_welcome_credit_config
CREATE TABLE ai_welcome_credit_config (...);  -- ver seccion 2.2

-- 4. Tabla store_dna_cache
CREATE TABLE store_dna_cache (...);  -- ver seccion 1.3

-- 5. Inserts addon_catalog (10 packs AI)
INSERT INTO addon_catalog (...) VALUES ...;  -- ver seccion 2.3

-- 6. Inserts ai_feature_pricing (10 rows)
INSERT INTO ai_feature_pricing VALUES ...;  -- ver seccion 2.2

-- 7. Inserts ai_welcome_credit_config (15 rows)
INSERT INTO ai_welcome_credit_config VALUES ...;  -- ver seccion 2.2
```

### Migracion Backend DB: `20260318_faqs_add_product_id.sql`
```sql
ALTER TABLE faqs ADD COLUMN product_id UUID REFERENCES products(id) ON DELETE CASCADE;
CREATE INDEX idx_faqs_product_id ON faqs(product_id) WHERE product_id IS NOT NULL;
```

---

## PARTE 7 — Archivos a crear/modificar

### Archivos NUEVOS (12):
| # | Archivo | Proposito |
|---|---------|-----------|
| 1 | `api/src/ai-credits/ai-credits.module.ts` | Modulo NestJS |
| 2 | `api/src/ai-credits/ai-credits.service.ts` | Balance, consumo, grant |
| 3 | `api/src/ai-credits/ai-credits.controller.ts` | Endpoints tenant |
| 4 | `api/src/ai-credits/ai-credits.admin.controller.ts` | Endpoints super-admin |
| 5 | `api/src/ai-credits/ai-credits.guard.ts` | Guard de creditos |
| 6 | `api/src/ai-credits/ai-credits.decorator.ts` | `@RequireAiCredits` |
| 7 | `api/src/ai-credits/store-context.service.ts` | Store DNA |
| 8 | `api/src/import-wizard/import-mapping.service.ts` | Parseo y mapeo AI |
| 9 | `api/src/import-wizard/platform-signatures.ts` | Deteccion TN/Woo/ML |
| 10 | `api/migrations/admin/20260318_ai_credits_system.sql` | Migracion Admin |
| 11 | `api/migrations/backend/20260318_faqs_add_product_id.sql` | Migracion Backend |
| 12 | `admin/src/pages/AdminDashboard/AiCreditsPricingView.jsx` | Super-admin dashboard |

### Archivos a MODIFICAR (15):
| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `api/src/app.module.ts` | Import AiCreditsModule |
| 2 | `api/src/worker/provisioning-worker.service.ts` | Step welcome credits + Store DNA |
| 3 | `api/src/import-wizard/import-wizard.controller.ts` | 2 endpoints nuevos |
| 4 | `api/src/import-wizard/import-wizard.module.ts` | Import services |
| 5 | `web/src/api/client.ts` | Interceptor 402 |
| 6 | `web/src/components/admin/ProductDashboard/` | Boton IA en editor |
| 7 | `web/src/components/admin/QADashboard/index.jsx` | Boton sugerir en ThreadPanel |
| 8 | `web/src/components/admin/ReviewsDashboard/index.jsx` | Boton sugerir en ReplyForm |
| 9 | `web/src/components/admin/FaqSection/index.jsx` | Boton generar + mejorar |
| 10 | `web/src/components/admin/ImportWizard/index.jsx` | Step 0 de mapeo |
| 11 | `web/src/components/admin/AddonStoreDashboard/index.jsx` | Familia AI |
| 12 | `web/src/pages/AdminDashboard/index.jsx` | Widget header + nav item settings IA |
| 13 | `admin/src/pages/AdminDashboard/index.jsx` | Nav item AI Credits Pricing |
| 14 | `admin/src/services/adminApi.js` | Metodos admin AI credits |
| 15 | `admin/src/pages/ClientDetails/hooks/useClientConsumables.js` | AI balances + Store DNA |

### Archivos de REFERENCIA:
| Archivo | Patron a copiar |
|---|---|
| `api/src/storefront-actions/storefront-action-credits.service.ts` | Consumo por action_code |
| `api/src/addons/addons.service.ts` (L2074-2099) | Grant de creditos consumibles |
| `api/src/seo-ai-billing/seo-ai-billing.service.ts` | Balance + ledger |
| `api/src/seo-ai/seo-ai.service.ts` | OpenAI call con retry |
| `api/src/seo-ai/prompts/system.prompt.ts` | System prompt pattern |
| `admin/src/pages/AdminDashboard/SeoAiPricingView.jsx` | Admin CRUD 3-tab pattern |
| `web/src/components/admin/SeoAutopilotDashboard/` | Credit indicator + cost estimation |
| `web/src/components/admin/AddonStoreDashboard/index.jsx` | Addon store card pattern |
| `web/src/components/admin/_shared/AdminModal.jsx` | Modal base pattern |

---

## PARTE 8 — Orden de implementacion (6 fases)

### Fase 1: Migraciones + Core service
1. SQL Admin: tablas + inserts
2. SQL Backend: faqs.product_id
3. `AiCreditsService` (balance, consume, grant, pricing)
4. `AiCreditsGuard` + decorator
5. `AiCreditsController` (tenant endpoints)
6. `AiCreditsAdminController` (super-admin endpoints)
7. Registrar en AppModule

### Fase 2: Store DNA
1. `StoreContextService` (build, generate, cache)
2. Endpoint tenant: get/regenerate Store DNA
3. Endpoint admin: view client Store DNA
4. Integracion en provisioning (generacion inicial)

### Fase 3: Welcome Credits + Provisioning
1. Step `GRANT_WELCOME_AI_CREDITS` en ProvisioningWorkerService
2. Endpoint admin grant manual (promo)
3. Migracion: campos industry/brand_tone en nv_accounts

### Fase 4: AI Column Mapping
1. `platform-signatures.ts`
2. `ImportMappingService`
3. Endpoints analyze-file + apply-mapping
4. Integracion de creditos

### Fase 5: Super Admin Dashboard
1. `AiCreditsPricingView.jsx` (4 tabs)
2. Nav item en admin dashboard
3. Client Details: seccion AI Credits + Store DNA
4. `adminApi.js` metodos

### Fase 6: Frontend Tenant
1. Interceptor 402 + `CreditInsufficientModal`
2. Componentes compartidos: `AiTierToggle`, `AiButton`, `AiCreditsBadge`
3. Product Editor: boton descripcion
4. QA Manager: boton sugerir
5. Reviews Manager: boton sugerir
6. FAQ Manager: boton generar + mejorar
7. Import Wizard: step mapeo columnas
8. Addon Store: familia AI
9. Header widget
10. Settings: perfil IA de tienda

---

## PARTE 9 — Guias de ayuda contextual para el Tenant (Seller)

Cada componente IA incluye copy educativo que explica que hace, por que sirve, y como usarlo. Esto es critico porque el seller argentino promedio NO sabe que es IA ni por que la necesita.

### 9.1 Copy por feature (in-app)

#### Product Description AI
**Ubicacion:** Tooltip/helper junto al boton "Mejorar descripcion"
```
Para que sirve?
La IA analiza tu producto y genera una descripcion profesional que:
- Atrae mas compradores con un texto persuasivo
- Mejora tu posicion en Google (SEO)
- Usa el tono de tu marca automaticamente

Normal: descripcion clara y efectiva (1 credito)
Pro: descripcion premium con mas detalle y persuasion (3 creditos)

Tip: Siempre podes editar el resultado antes de guardar.
```

#### QA Suggest Answer
**Ubicacion:** Tooltip junto a "Sugerir respuesta" en el panel de preguntas
```
Para que sirve?
La IA lee la pregunta del cliente, analiza tu producto, y te sugiere
una respuesta profesional lista para enviar. Vos solo la revisas y listo.

- Responder rapido = mas chances de vender
- El tono se adapta a tu marca
- No inventa datos sobre stock ni envio

Normal: respuesta concisa y directa (1 credito)
Pro: respuesta mas empatica y detallada (2 creditos)
```

#### FAQ Generation
**Ubicacion:** Helper en modal "Generar FAQs desde productos"
```
Para que sirve?
Genera preguntas frecuentes automaticas basadas en tus productos.
Las FAQs:
- Resuelven dudas antes de que el cliente pregunte
- Mejoran tu SEO (Google indexa las preguntas)
- Reducen consultas repetitivas

Selecciona los productos y la IA genera 5-8 preguntas relevantes
para cada uno.

Normal: preguntas estandar (1 credito por producto)
Pro: preguntas mas especificas y detalladas (3 creditos por producto)
```

#### Reviews Suggest Reply
**Ubicacion:** Tooltip junto a "Sugerir respuesta" en reviews
```
Para que sirve?
La IA te sugiere una respuesta profesional para la opinion del cliente.
Especialmente util para reviews negativos donde el tono importa mucho.

- Respuesta respetuosa y constructiva
- Adaptada al contenido especifico de la opinion
- Mantiene la reputacion de tu marca

Normal: respuesta directa (1 credito)
Pro: respuesta mas empatica y elaborada (2 creditos)
```

#### Photo to Product
**Ubicacion:** Helper en step de "Crear desde foto"
```
Para que sirve?
Subi una foto de tu producto y la IA genera automaticamente:
- Nombre del producto
- Descripcion completa
- Categoria sugerida
- Tags relevantes

Ideal para: cargar catalogo rapido desde fotos del celular.

Normal: ficha basica (3 creditos)
Pro: ficha completa con descripcion larga y SEO (5 creditos)
```

#### Column Mapping (Import)
**Ubicacion:** Helper en step de "Subir archivo"
```
Para que sirve?
Venis de TiendaNube, WooCommerce u otra plataforma?
Subi tu archivo de productos y la IA identifica automaticamente
que columna es el nombre, cual es el precio, cual el stock, etc.

- Si reconocemos tu plataforma, el mapeo es instantaneo y gratis
- Si no, la IA analiza las columnas (1 credito)
- Siempre podes ajustar el mapeo antes de confirmar
```

#### Store DNA / Perfil IA
**Ubicacion:** Settings -> "Perfil IA de tu tienda"
```
Para que sirve?
Tu perfil IA es como un briefing para todas las funciones de inteligencia
artificial de tu tienda. La IA analiza tu marca, productos y estilo,
y genera una instruccion que hace que TODO el contenido generado
suene coherente con tu identidad.

- Se actualiza automaticamente cada 24 horas
- Podes editarlo manualmente si queres ajustar el tono
- Es gratis — no consume creditos

Campos que podes personalizar:
- Rubro: De que es tu tienda? (moda, deco, tecnologia...)
- Tono de marca: Como hablas? (casual, premium, tecnico...)
- Audiencia: A quien le vendes? (jovenes, profesionales, familias...)
- Propuesta de valor: Que te hace diferente?
```

#### Addon Store — Seccion AI
**Ubicacion:** Banner superior en la seccion "Inteligencia Artificial" del Addon Store
```
Potencia tu tienda con IA

Las herramientas de inteligencia artificial te ayudan a:
- Escribir descripciones que venden
- Responder preguntas en segundos
- Generar FAQs automaticas
- Crear fichas desde fotos
- Migrar catalogos facilmente

Cada pack te da creditos para usar cuando quieras. No vencen*
mientras tu cuenta este activa.

* Los creditos de bienvenida vencen a los 90 dias.
```

### 9.2 Empty states educativos

Cuando el seller no tiene creditos y ve un boton IA deshabilitado:

**Estado: Sin creditos**
```
Sin creditos de [feature]. Compra un pack en el Addon Store
para usar esta funcion. [Ir al Addon Store ->]
```

**Estado: Welcome credits disponibles**
```
Tenes X creditos de bienvenida! Proba la IA gratis.
Los creditos de cortesia vencen en Y dias. [Usar ahora ->]
```

**Estado: Primer uso**
```
Primera vez usando IA! Tu perfil de tienda se esta generando...
Esto tarda unos segundos y solo pasa la primera vez.
```

### 9.3 Tooltips en toggles Normal/Pro

**Toggle Normal (seleccionado por defecto):**
```
IA Normal — Rapida y efectiva. Usa {X} credito(s).
Ideal para uso diario.
```

**Toggle Pro:**
```
IA Pro — Mas detallada y creativa. Usa {X} creditos.
Recomendada para productos estrella o contenido importante.
```

---

## PARTE 10 — Guias de impacto en Super Admin Dashboard

Cada configuracion en el dashboard de super-admin incluye una descripcion del impacto real que tiene cambiarla. Esto evita que un admin cambie un precio sin entender las consecuencias.

### 10.1 Tab "Features & Pricing" — Tooltips de impacto

| Campo | Tooltip de impacto |
|---|---|
| **credit_cost (Normal)** | "Cuantos creditos se descuentan al usar esta feature en modo Normal. Reducirlo incentiva uso pero reduce ingresos por credito. Aumentarlo desincentiva uso pero protege margen." |
| **credit_cost (Pro)** | "Cuantos creditos se descuentan en modo Pro. Debe ser mayor que Normal para justificar el modelo mas caro. Ratio recomendado: 2-3x Normal." |
| **model_id** | "Modelo de OpenAI usado. gpt-4o-mini: mas barato (~$0.15/1M tokens), buena calidad. gpt-4o: mas caro (~$2.50/1M tokens), mejor calidad. Cambiar modelo afecta costo operativo Y calidad de output." |
| **temperature** | "Creatividad del modelo. 0.2-0.3: factual, consistente. 0.5-0.7: mas creativo, mas variado. Para SEO y datos, preferir bajo. Para copy y descripciones, preferir medio." |
| **max_tokens** | "Largo maximo de la respuesta. 300: respuestas cortas (Q&A). 600: descripciones normales. 1200: contenido largo (Pro). Mas tokens = mas costo por invocacion." |
| **is_active** | "Desactivar una feature la oculta para TODOS los tenants inmediatamente. Los creditos existentes se mantienen pero no se pueden usar hasta reactivar." |

### 10.2 Tab "Packs de Creditos" — Tooltips de impacto

| Campo | Tooltip de impacto |
|---|---|
| **price_cents** | "Precio en ARS centavos que paga el seller via MercadoPago. Cambiar esto afecta todos los purchases FUTUROS. Purchases ya realizados mantienen el precio original." |
| **grants_credits** | "Cuantos creditos otorga este pack al comprarse. Cambiar NO afecta compras pasadas (los creditos ya otorgados se mantienen). Solo afecta compras nuevas." |
| **is_active** | "Desactivar oculta el pack del Addon Store. Los creditos ya comprados siguen disponibles para el seller." |

### 10.3 Tab "Welcome Credits" — Tooltips de impacto

| Campo | Tooltip de impacto |
|---|---|
| **credits** | "Creditos gratuitos que recibe cada cuenta nueva de este plan. Aumentar incentiva adopcion de IA pero tiene costo operativo (inferencia)." |
| **expires_days** | "Dias hasta que vencen los creditos de bienvenida. Menor = mas urgencia de uso. Mayor = mas tiempo para probar. Recomendado: 90 dias para Starter, 120 para Growth." |
| **is_active** | "Desactivar impide que nuevas cuentas de este plan reciban welcome credits. Cuentas ya creadas mantienen sus creditos." |

### 10.4 Tab "Creditos por Cliente" — Guia operativa

**Header del tab:**
```
Gestion manual de creditos IA por cliente

Usa esta seccion para:
- Ver el balance actual de un seller por cada feature IA
- Otorgar creditos promocionales (ej: compensar un issue, promo especial)
- Revocar creditos otorgados por error
- Ver el Store DNA del seller (perfil IA generado)
- Ver historial completo de movimientos (grants, consumos, expiracion)

Los ajustes manuales quedan registrados en el historial con tu usuario.
```

---

## Verificacion

1. **Migracion**: Ejecutar SQL en ambas BDs -> verificar tablas/columnas/data
2. **Store DNA**: Crear tienda test -> verificar que se genera DNA -> verificar cache
3. **Credits flow**: Grant welcome -> verificar balance -> consumir -> verificar decrement -> 0 -> verificar 402
4. **Tier test**: Normal consume X creditos, Pro consume Y del mismo pool
5. **Addon purchase**: Comprar pack via MP mock -> webhook -> grant -> balance
6. **Column mapping**: Upload TN export -> detecta plataforma -> mapeo directo
7. **Column mapping AI**: Upload generico -> consume credito -> sugerencias -> transform -> batch
8. **Admin pricing**: Cambiar credit_cost -> verificar que proxima invocacion usa nuevo costo
9. **Admin grant**: Otorgar creditos promo -> verificar balance del cliente
10. **Frontend 402**: Intentar accion sin creditos -> modal aparece -> navega a store -> compra -> retry
11. **Expiration**: Welcome credits expiran -> balance refleja 0 despues de N dias
12. **Store DNA invalidation**: Cambiar categorias -> DNA se regenera en proxima llamada

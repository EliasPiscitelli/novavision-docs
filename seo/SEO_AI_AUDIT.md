# NovaVision — Auditoría SEO & Propuesta de Arquitectura AI SEO

> **Fecha:** 2026-02-13  
> **Autor:** Copilot Staff Engineer  
> **Estado:** Fase A completa → Esperando aprobación para implementar

---

## Índice

1. [Auditoría del Estado Actual](#1-auditoría-del-estado-actual)
2. [Gaps y Riesgos P0/P1](#2-gaps-y-riesgos)
3. [Propuesta de Arquitectura](#3-propuesta-de-arquitectura)
4. [Modelo de Datos](#4-modelo-de-datos)
5. [Diseño Funcional](#5-diseño-funcional)
6. [Arquitectura AI](#6-arquitectura-ai)
7. [Cobros y Consumo](#7-cobros-y-consumo)
8. [Plan de PRs](#8-plan-de-prs)
9. [Riesgos y Mitigaciones](#9-riesgos-y-mitigaciones)

---

## 1. Auditoría del Estado Actual

### 1.1 SEO Backend (API — NestJS)

**Módulo:** `src/seo/` — 6 archivos, 12 endpoints, servicio completo.

| Tabla/Recurso | Estado | Columnas |
|---|---|---|
| `seo_settings` | ✅ Live | `site_title`, `site_description`, `brand_name`, `og_image_default`, `favicon_url`, `ga4_measurement_id`, `gtm_container_id`, `search_console_token`, `product_url_pattern`, `robots_txt`, `custom_meta` (JSONB) |
| `seo_redirects` | ✅ Live | `from_path`, `to_url`, `redirect_type` (301/302), `active`, `hit_count` — con índice parcial para lookups activos |
| `products` (SEO cols) | ✅ Live | `slug`, `meta_title`, `meta_description`, `noindex` |
| `categories` (SEO cols) | ⚠️ Parcial | `meta_title`, `meta_description`, `noindex` — **SIN `slug` persistido** |

**Endpoints:**

| Método | Path | Auth | Plan Gate |
|---|---|---|---|
| GET | `/seo/settings` | tenant | `seo.settings` (Growth+) |
| PUT | `/seo/settings` | admin | `seo.settings` |
| GET | `/seo/meta/:entity/:id` | tenant | `seo.entity_meta` (Growth+) |
| PUT | `/seo/meta/:entity/:id` | admin | `seo.entity_meta` |
| GET | `/seo/sitemap.xml` | público | **sin gate** |
| GET | `/seo/og?path=` | público | **sin gate** |
| GET | `/seo/redirects` | admin | `seo.redirects` (Enterprise) |
| POST | `/seo/redirects` | admin | `seo.redirects` |
| PUT | `/seo/redirects/:id` | admin | `seo.redirects` |
| DELETE | `/seo/redirects/:id` | admin | `seo.redirects` |
| GET | `/seo/redirects/resolve?path=` | público | sin gate |

**Feature Catalog (6 features, todas `live`):**

| Feature | Starter | Growth | Enterprise |
|---|---|---|---|
| `seo.settings` | ❌ | ✅ | ✅ |
| `seo.entity_meta` | ❌ | ✅ | ✅ |
| `seo.sitemap` | ❌ | ✅ | ✅ |
| `seo.schema` | ❌ | ✅ | ✅ |
| `seo.analytics` | ❌ | ✅ | ✅ |
| `seo.redirects` | ❌ | ❌ | ✅ |

### 1.2 SEO Frontend (Web — React)

**Componentes SEO:**

| Componente | Archivo | Función |
|---|---|---|
| `SEOHead` | `src/components/SEOHead/index.jsx` | Global: `<title>`, meta description, OG, Twitter, favicon, GA4, GTM, OrganizationJsonLd |
| `ProductSEO` | `src/components/SEOHead/ProductSEO.jsx` | Per-product: title, description, canonical, robots, OG product tags |
| `SearchSEO` | `src/components/SEOHead/SearchSEO.jsx` | Búsqueda/categoría: noindex si query, título dinámico |
| `ProductJsonLd` | `src/components/SEOHead/JsonLd.jsx` | JSON-LD Product + Offer |
| `OrganizationJsonLd` | `src/components/SEOHead/JsonLd.jsx` | JSON-LD Organization |
| `BreadcrumbJsonLd` | `src/components/SEOHead/JsonLd.jsx` | JSON-LD BreadcrumbList |

**Hook:** `useSeoSettings` — fetch + cache de settings por tenant.

**Edge Functions (Netlify, Deno):**

| # | Función | Path | Propósito |
|---|---|---|---|
| 1 | `maintenance.ts` | `/*` | Health check backend → 503 si down |
| 2 | `seo-redirects.ts` | `/*` | 301/302 desde DB → `GET /seo/redirects/resolve` |
| 3 | `og-inject.ts` | `/*` | Pre-render OG para social bots → `GET /seo/og` |
| 4 | `seo-robots.ts` | `/robots.txt` | robots.txt dinámico desde settings |

### 1.3 Admin SEO (Panel Super Admin)

**`SeoView.jsx`** — 1022 líneas, 8 secciones:

1. Selector de cliente (dropdown por slug)
2. Marca y títulos (site_title, brand_name, site_description)
3. Imagen OG y favicon
4. Analytics (GA4, GTM, Search Console)
5. Avanzado (product_url_pattern, robots_txt)
6. Meta por entidad (búsqueda producto/categoría → edit meta)
7. Redirecciones 301/302 (CRUD completo)
8. Botón Guardar

### 1.4 Infraestructura de Jobs

**`@nestjs/schedule` activo** con ~12 crons existentes:

- `OutboxWorkerService` (30s + diario)
- `TtlCleanupService` (diario 3AM)
- `PaymentReconciliationService` (diario 3AM)
- `UsageResetService` (1ro de mes)
- `ManagedDomainCron` (cada 6h)
- `MetricsCron` (diario)

**No hay Bull/Redis.** Todo corre en el proceso NestJS de Railway.

→ Se puede agregar un `SeoAiWorkerService` con `@Cron` o `@Interval` sin deps extras.

### 1.5 Billing Infrastructure (Admin DB)

**Tablas existentes relevantes:**

| Tabla | Propósito |
|---|---|
| `addon_catalog` | Catálogo de addons (`addon_key`, `display_name`, `delta_entitlements` JSONB, `price_cents`, `is_active`) |
| `account_addons` | Addons comprados (`account_id`, `addon_key`, `status`, `purchased_at`, `metadata` JSONB) |
| `nv_billing_events` | Eventos de facturación con MP integration |
| `subscriptions` | Suscripciones de plan (para MRR futuro) |
| `plans` | Catálogo de planes con entitlements JSONB |

**Patrón MP existente:**
- `MercadoPagoController` en `src/tenant-payments/`
- Idempotencia via `mp_idempotency`
- Webhooks: HMAC + payment verification
- Preferencias: create-preference, confirm-payment

### 1.6 Columnas SEO Faltantes para AI

| Columna | products | categories | Necesaria para AI |
|---|---|---|---|
| `slug` | ✅ | ❌ | Sí (canonical URLs) |
| `meta_title` | ✅ | ✅ | Base OK |
| `meta_description` | ✅ | ✅ | Base OK |
| `noindex` | ✅ | ✅ | Base OK |
| `seo_source` | ❌ | ❌ | **Nuevo** — `manual`/`ai`/`template` |
| `seo_locked` | ❌ | ❌ | **Nuevo** — AI no pisa |
| `seo_needs_refresh` | ❌ | ❌ | **Nuevo** — flag refresh |
| `seo_last_generated_at` | ❌ | ❌ | **Nuevo** — timestamp gen AI |
| `seo_keywords` | ❌ | ❌ | Opcional (Google ignora, pero útil interno) |
| `seo_og_image_url` | ❌ | ❌ | Opcional |

---

## 2. Gaps y Riesgos

### P0 (Crítico — bloqueante)

| # | Gap | Impacto | Acción |
|---|---|---|---|
| P0-1 | **12+ páginas sin `noindex`** | Cart, Login, Dashboard, Payment results, etc. son indexados por Google como contenido válido | Agregar `<meta name="robots" content="noindex">` en todas las páginas non-indexable |
| P0-2 | **categories sin `slug` persistido** | Sitemap genera slugs on-the-fly → URLs cambian si renombran categoría → links rotos | Agregar `slug` a `categories`, backfill, y persistir |
| P0-3 | **Canonical URL con query params** | `window.location.href` incluye `?tenant=`, `?preview=`, etc. → Google indexa duplicados | Normalizar canonical sin params no-SEO |

### P1 (Importante — pre-AI)

| # | Gap | Impacto | Acción |
|---|---|---|---|
| P1-1 | **Sitemap sin gate pero catálogo dice Growth+** | Inconsistencia: Starter genera sitemap "gratis" | Decidir: ¿es público (correcto) o gated? |
| P1-2 | **OG data no resuelve categorías** | Social shares de categorías usan fallback genérico | Ampliar `getOgData()` para categorías |
| P1-3 | **Template "fourth" usa DOM directo** | Conflicto con react-helmet-async | Migrar a Helmet |
| P1-4 | **Sin ItemList JSON-LD para PLPs** | Pierde rich results en búsquedas de categoría | Agregar `ItemList` en SearchPage |
| P1-5 | **Sin WebSite+SearchAction JSON-LD** | Sin sitelink search box en Google | Agregar schema WebSite |

### P2 (Nice-to-have)

| # | Gap |
|---|---|
| P2-1 | Sin `image:image` en sitemap |
| P2-2 | Sin `FAQPage` JSON-LD |
| P2-3 | Sin `hreflang` (OK por ahora, solo español) |

---

## 3. Propuesta de Arquitectura

### 3.1 Diagrama de alto nivel

```
┌───────────────────────────────────────────────────────────────────────┐
│                        STORE ADMIN (Growth+)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌───────────────────────────┐   │
│  │ SEO Settings │  │ Entity Meta  │  │  AI SEO Autopilot (add-on)│   │
│  │  (sin IA)    │  │  (sin IA)    │  │  - Generar sitio          │   │
│  │ + Validación │  │ + Preview    │  │  - Generar productos      │   │
│  │ + Prompt     │  │ + Lock       │  │  - Generar categorías     │   │
│  │   copiable   │  │              │  │  - Auditoría SEO          │   │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬───────────────┘   │
└─────────┼──────────────────┼─────────────────────┼───────────────────┘
          │                  │                     │
          ▼                  ▼                     ▼
┌───────────────────────────────────────────────────────────────────────┐
│                    BACKEND (NestJS / Railway)                         │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────────────────┐    │
│  │ SeoModule    │  │ SeoAiModule  │  │ SeoAiBillingModule       │    │
│  │ (existente)  │  │ (NUEVO)      │  │ (NUEVO)                  │    │
│  │ settings,    │  │ AIService    │  │ CreditService            │    │
│  │ redirects,   │  │ JobService   │  │ PurchaseService          │    │
│  │ sitemap, OG  │  │ WorkerCron   │  │ MP preference+webhook    │    │
│  └──────┬───────┘  └──────┬───────┘  └───────────┬──────────────┘    │
│         │                 │                      │                   │
│         ▼                 ▼                      ▼                   │
│  ┌─────────────┐  ┌──────────────┐       ┌──────────────┐           │
│  │Backend DB   │  │Backend DB    │       │Admin DB      │           │
│  │seo_settings │  │seo_ai_jobs   │       │seo_pricing   │           │
│  │products     │  │(cola interna)│       │seo_purchases │           │
│  │categories   │  │              │       │seo_credits   │           │
│  │seo_redirects│  │OpenAI API    │       │              │           │
│  └─────────────┘  └──────────────┘       └──────────────┘           │
└───────────────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────────────┐
│                     SUPER ADMIN (novavision)                         │
│  ┌──────────────────────────┐  ┌────────────────────────────┐        │
│  │ SEO AI Pricing Config    │  │ SEO AI Dashboard           │        │
│  │ - Editar precios packs   │  │ - Compras por tenant       │        │
│  │ - Feature toggles        │  │ - Consumo/créditos         │        │
│  │                          │  │ - Jobs (progreso, errores)  │        │
│  │                          │  │ - Auditoría cross-tenant    │        │
│  └──────────────────────────┘  └────────────────────────────┘        │
└───────────────────────────────────────────────────────────────────────┘
```

### 3.2 Decisiones de arquitectura

| Decisión | Elección | Motivo |
|---|---|---|
| **Dónde corren jobs** | Worker `@Cron` en NestJS (tabla `seo_ai_jobs` como cola) | Ya hay 12 crons; no necesitamos Redis/Bull; Railway soporta el patrón |
| **LLM provider** | OpenAI `gpt-4o-mini` | Costo bajo (~$0.15/1M input, $0.60/1M output), suficiente para meta tags, batch-friendly |
| **Dónde viven créditos/pricing** | Admin DB | Patrón existente: `addon_catalog` + `account_addons` + `nv_billing_events`. Se extiende, no se reinventa |
| **Dónde vive `seo_ai_jobs`** | Backend DB (multitenant) | Scopeado por `client_id`, close-to-data (accede products/categories directamente) |
| **Feature flag para AI** | `seo.ai_autopilot` en feature catalog + `addon_catalog` | Consistente con `PlanFeature`/`PlanAccessGuard`. No incluido en ningún plan, se habilita via addon purchase |
| **Pagos de packs AI** | Mercado Pago one-shot (no suscripción) | Patrón existente: `create-preference` → webhook → acreditar. Sin MRR en V1 |
| **API Key OpenAI** | `OPENAI_API_KEY` en Railway env | Nunca en frontend ni Admin. Solo backend |

---

## 4. Modelo de Datos

### 4.1 Cambios en Backend DB (multitenant)

#### ALTER TABLE `products` — Columnas AI SEO

```sql
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS seo_source TEXT DEFAULT 'manual'
    CHECK (seo_source IN ('manual', 'ai', 'template')),
  ADD COLUMN IF NOT EXISTS seo_locked BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS seo_needs_refresh BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS seo_last_generated_at TIMESTAMPTZ;

COMMENT ON COLUMN products.seo_source IS 'Quién generó el SEO: manual (user), ai (autopilot), template (fallback)';
COMMENT ON COLUMN products.seo_locked IS 'Si true, AI no puede sobrescribir este SEO';
COMMENT ON COLUMN products.seo_needs_refresh IS 'Flag: producto cambió y SEO podría estar desactualizado';
```

#### ALTER TABLE `categories` — Columnas AI SEO + slug

```sql
ALTER TABLE categories
  ADD COLUMN IF NOT EXISTS slug TEXT,
  ADD COLUMN IF NOT EXISTS seo_source TEXT DEFAULT 'manual'
    CHECK (seo_source IN ('manual', 'ai', 'template')),
  ADD COLUMN IF NOT EXISTS seo_locked BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS seo_needs_refresh BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS seo_last_generated_at TIMESTAMPTZ;

-- Backfill slugs
UPDATE categories SET slug = lower(regexp_replace(trim(name), '[^a-zA-Z0-9]+', '-', 'g'))
  WHERE slug IS NULL;

-- Index
CREATE UNIQUE INDEX IF NOT EXISTS idx_categories_client_slug
  ON categories(client_id, slug) WHERE slug IS NOT NULL;
```

#### CREATE TABLE `seo_ai_jobs` (cola interna)

```sql
CREATE TABLE seo_ai_jobs (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id       UUID NOT NULL REFERENCES clients(id),
  requested_by    UUID NOT NULL,  -- user_id del admin que lo pidió
  job_type        TEXT NOT NULL CHECK (job_type IN ('site', 'categories', 'products', 'audit')),
  scope           JSONB NOT NULL DEFAULT '{}',
  -- scope examples: {"product_ids": [...]} o {"all": true} o {"category_ids": [...]}
  status          TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'cancelled')),
  progress        JSONB NOT NULL DEFAULT '{"total": 0, "done": 0, "errors": 0}',
  mode            TEXT NOT NULL DEFAULT 'update_missing'
    CHECK (mode IN ('create', 'update_missing', 'refresh')),
  cost_estimated  INTEGER DEFAULT 0,   -- créditos estimados
  cost_actual     INTEGER DEFAULT 0,   -- créditos consumidos
  tokens_input    INTEGER DEFAULT 0,
  tokens_output   INTEGER DEFAULT 0,
  error           TEXT,
  result          JSONB,  -- resultado de auditoría o estadísticas
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_seo_ai_jobs_client ON seo_ai_jobs(client_id);
CREATE INDEX idx_seo_ai_jobs_pending ON seo_ai_jobs(status) WHERE status IN ('pending', 'processing');

-- RLS
ALTER TABLE seo_ai_jobs ENABLE ROW LEVEL SECURITY;
CREATE POLICY seo_ai_jobs_server_bypass ON seo_ai_jobs FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
```

#### CREATE TABLE `seo_ai_log` (auditoría de cambios AI)

```sql
CREATE TABLE seo_ai_log (
  id            UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id     UUID NOT NULL REFERENCES clients(id),
  job_id        UUID REFERENCES seo_ai_jobs(id),
  entity_type   TEXT NOT NULL CHECK (entity_type IN ('product', 'category', 'site')),
  entity_id     UUID,
  field_name    TEXT NOT NULL,      -- 'meta_title', 'meta_description', etc.
  old_value     TEXT,
  new_value     TEXT,
  tokens_used   INTEGER DEFAULT 0,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_seo_ai_log_client ON seo_ai_log(client_id);
CREATE INDEX idx_seo_ai_log_job ON seo_ai_log(job_id);

ALTER TABLE seo_ai_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY seo_ai_log_server_bypass ON seo_ai_log FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
```

### 4.2 Cambios en Admin DB (control plane)

#### INSERT en `addon_catalog`

```sql
INSERT INTO addon_catalog (addon_key, display_name, delta_entitlements, price_cents, is_active) VALUES
  ('seo_ai_pack_site',    'AI SEO – Pack Sitio',             '{"seo_ai_credits": 10}',   490000, true),
  ('seo_ai_pack_500',     'AI SEO – Catálogo 500 productos', '{"seo_ai_credits": 550}', 1490000, true),
  ('seo_ai_pack_2000',    'AI SEO – Catálogo 2000 productos','{"seo_ai_credits": 2100}',2990000, true)
ON CONFLICT (addon_key) DO NOTHING;
```

> Precios en centavos ARS: 490000 = $4.900, 1490000 = $14.900, 2990000 = $29.900

#### CREATE TABLE `seo_ai_credits` (ledger)

```sql
CREATE TABLE seo_ai_credits (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   UUID NOT NULL REFERENCES nv_accounts(id),
  delta        INTEGER NOT NULL,     -- positivo = acredita, negativo = consume
  balance_after INTEGER NOT NULL,    -- balance resultante
  reason       TEXT NOT NULL,        -- 'purchase:seo_ai_pack_500', 'consume:job:<uuid>', 'refund:job:<uuid>'
  job_id       TEXT,                 -- referencia al job (si aplica)
  purchase_id  UUID,                 -- referencia al account_addons.id (si aplica)
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_seo_ai_credits_account ON seo_ai_credits(account_id);

ALTER TABLE seo_ai_credits ENABLE ROW LEVEL SECURITY;
-- Super admin y service_role
CREATE POLICY seo_ai_credits_service ON seo_ai_credits FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
CREATE POLICY seo_ai_credits_super ON seo_ai_credits FOR SELECT
  USING ((auth.jwt() -> 'app_metadata' ->> 'is_super_admin')::boolean = true);
```

### 4.3 Feature Catalog (nuevo entry)

```typescript
// En featureCatalog.ts
{
  id: 'seo.ai_autopilot',
  title: 'AI SEO Autopilot',
  description: 'Generación automática de SEO con IA para productos, categorías y sitio',
  category: 'seo',
  status: 'live',
  plans: { starter: false, growth: false, enterprise: false },
  // Habilitado SOLO via addon purchase → feature_overrides[client_id]
  addons: ['seo_ai_pack_site', 'seo_ai_pack_500', 'seo_ai_pack_2000'],
}
```

---

## 5. Diseño Funcional

### 5.1 SEO sin IA (Growth) — Mejoras sobre lo existente

**A. Validaciones en UI (SeoView.jsx):**

- Preview SERP (Google-like snippet) para title + description
- Contador de caracteres con colores (verde/amarillo/rojo)
- Detección de faltantes ("No tenés meta description en 34 productos")
- Ícono de warning en entity meta editor si title > 60 o description > 160

**B. Prompt copiable:**

- Botón "Generar con ChatGPT" que abre modal con prompt pre-llenado con datos de la tienda
- Variables auto-reemplazadas: `{NOMBRE_TIENDA}`, `{RUBRO}`, `{CATEGORIAS}`, etc.
- Copy-to-clipboard

**C. Templates de fallback (ya funcionan parcialmente):**

- `ProductSEO` ya usa `meta_title || formateo(name)` 
- Reforzar: usar `seo_settings.title_template` si existe

### 5.2 AI SEO Autopilot (add-on)

**Flujo del Store Admin:**

```
1. Abre tab "AI Autopilot" en panel SEO
2. Ve estado de créditos (X disponibles)
3. Si no tiene → "Comprar pack" → selecciona → MP checkout → webhook → créditos
4. Elige acción:
   a) "Generar SEO del sitio" (≈1 crédito)
   b) "Generar SEO de categorías" (≈1 crédito por categoría)
   c) "Generar SEO de productos" (≈1 crédito por producto)
   d) "Auditoría SEO" (≈5 créditos)
5. Confirma modo: "Solo faltantes" / "Regenerar todo" / "Solo seleccionados"
6. Estimación: "Esto va a consumir ~45 créditos. ¿Continuar?"
7. Crea job → status "pending"
8. Worker procesa en background (chunks de 25-50)
9. UI muestra progreso en tiempo real (polling cada 5s)
10. Al terminar → "Completado: 45/50 productos, 0 errores"
11. Puede ver cambios aplicados en log y revertir individuales
```

**Reglas de precedencia (obligatorias):**

```
1. Manual (seo_locked=true)  → NUNCA se pisa
2. AI generado               → Se pisa solo con "refresh" explícito
3. Template/fallback          → Se pisa siempre
4. Defaults del sistema       → Se pisa siempre
```

### 5.3 Super Admin

**Panel "SEO AI Billing":**

- Config de precios (editar `addon_catalog` entries de `seo_ai_*`)
- Vista de compras por tenant (filtra `account_addons` por `addon_key LIKE 'seo_ai_%'`)
- Vista de consumo/créditos por tenant (`seo_ai_credits` agrupado por account)
- Vista de jobs (status, progreso, errores)
- Toggle feature override per-client (ya existente, se reutiliza)

---

## 6. Arquitectura AI

### 6.1 AIService (backend)

```typescript
// src/seo-ai/services/ai.service.ts
@Injectable()
export class SeoAiService {
  private client: OpenAI;

  constructor() {
    this.client = new OpenAI({ apiKey: process.env.OPENAI_API_KEY });
  }

  async generateEntitySeo(input: EntitySeoInput): Promise<EntitySeoOutput> {
    const response = await this.client.chat.completions.create({
      model: 'gpt-4o-mini',
      temperature: 0.3,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: SYSTEM_PROMPT },
        { role: 'user', content: buildEntityPrompt(input) }
      ],
      max_tokens: 500,
    });
    return parseAndValidate(response);
  }
}
```

### 6.2 Modelo y costos

| Modelo | Input $/1M tok | Output $/1M tok | Tokens por producto | Costo por 2000 productos |
|---|---|---|---|---|
| `gpt-4o-mini` | $0.15 | $0.60 | ~300 in + ~200 out | ~$0.33 USD |

**Margen:** Pack 2000 = ARS 29.900 (~USD 23) vs costo tokens ~USD 0.33 → **70x margen** (margen en producto/infra/valor, no en tokens).

### 6.3 Guardrails

| Guardrail | Valor | Implementación |
|---|---|---|
| Max tokens por request | 500 | `max_tokens` en API call |
| Title max chars | 65 | Validación post-AI, truncar si necesario |
| Description max chars | 160 | Idem |
| Rate limit por tenant/día | 5 jobs | Contador en `seo_ai_jobs` por `client_id` + fecha |
| Jobs simultáneos max | 1 por tenant | Check en job creation |
| Chunk size | 25 items | Worker procesa de a 25 |
| Timeout por chunk | 30s | AbortController en fetch |
| Retry on failure | 2 retries con backoff | En worker |
| No pisar seo_locked | — | Check antes de write |

### 6.4 Observabilidad

Cada llamada AI registra en `seo_ai_log`:
- `tokens_used` (input + output del response)
- `old_value` / `new_value` por campo
- `job_id` para correlación

El job acumula `tokens_input`, `tokens_output`, `cost_actual`.

---

## 7. Cobros y Consumo

### 7.1 Flujo de compra

```
Store Admin → "Comprar Pack 500" → 
  Backend crea MP preference (amount=14900, item="AI SEO Pack 500") →
  Redirect a MP →
  Usuario paga →
  Webhook POST /seo-ai/webhook →
    Verifica firma + idempotencia →
    Inserta account_addons →
    Inserta seo_ai_credits (delta=+550) →
    Feature override: feature_overrides['seo.ai_autopilot'] = true →
  Admin ve créditos disponibles
```

### 7.2 Flujo de consumo

```
Store Admin → "Generar SEO productos (45 seleccionados)" →
  Confirma estimación (45 créditos) →
  Backend:
    1. Verifica balance >= 45
    2. Crea seo_ai_jobs (status=pending, cost_estimated=45)
    3. Responde 201 con job_id
  Worker (cada 10s):
    1. Toma job pending más antiguo del tenant
    2. Cambia status → processing
    3. Por chunk (25 items):
       a. Consulta products con client_id
       b. Filtra seo_locked=true → skip
       c. Llama AI para cada item
       d. Update product con nuevo SEO
       e. Inserta en seo_ai_log
       f. Actualiza progress
       g. Descuenta crédito (1 insert en seo_ai_credits por chunk)
    4. Al finalizar: status → completed/failed
    5. Si error en chunk: retry 2x, si falla → marca error en progress, no descuenta crédito por esos items
```

### 7.3 Anti-abuso

| Control | Implementación |
|---|---|
| Rate limit | Max 5 jobs/día por tenant (query count en seo_ai_jobs WHERE created_at > today) |
| Concurrent limit | Max 1 job processing por tenant |
| Balance check | `SELECT COALESCE(SUM(delta), 0) FROM seo_ai_credits WHERE account_id = $1` antes de crear job |
| Refund on failure | Si un item falla tras retries → no descuenta crédito de ese item |

---

## 8. Plan de PRs

### PR1: SEO Hardening (P0 fixes, sin IA)
**Scope:** Web + API  
**Feature flag:** Ninguno (fixes directos)

- P0-1: `noindex` en ~15 páginas (Cart, Login, Dashboard, etc.)
- P0-2: Persistir `slug` en `categories` + migración + backfill
- P0-3: Normalizar canonical (strip query params non-SEO)
- P1-2: OG data para categorías
- P1-4: `ItemList` JSON-LD en SearchPage
- P1-5: `WebSite` + `SearchAction` JSON-LD
- Tests: verificar meta tags en edge functions

### PR2: Modelo AI en productos/categorías + migraciones
**Scope:** API (solo backend)  
**Feature flag:** Columnas inactivas hasta PR5

- ALTER TABLE: `seo_source`, `seo_locked`, `seo_needs_refresh`, `seo_last_generated_at` en products + categories
- CREATE TABLE: `seo_ai_jobs`, `seo_ai_log`
- RLS policies
- DTOs actualizados para incluir nuevos campos en entity_meta
- Feature catalog: agregar `seo.ai_autopilot`
- **No hay UI ni worker aún — solo schema**

### PR3: Admin DB billing schema + pricing config UI
**Scope:** API + Admin  
**Feature flag:** Datos en DB, UI visible solo para super admin

- INSERT `addon_catalog` entries para SEO AI packs
- CREATE TABLE `seo_ai_credits` en Admin DB
- UI Super Admin: tab "SEO AI Pricing" en admin dashboard
  - CRUD precios de packs
  - Vista de créditos por tenant
- Tests: RLS, queries

### PR4: Integración MP para packs AI + webhook + ledger
**Scope:** API + Web (Store Admin)  
**Feature flag:** `seo.ai_autopilot` OFF por defecto

- Endpoint `POST /seo-ai/purchase` → crea preferencia MP
- Webhook `POST /seo-ai/webhook` → idempotente, acredita créditos
- `SeoAiBillingService` → balance, debit, credit
- UI Store Admin: tab "AI Autopilot" con selector de pack y botón "Comprar"
- Vista de créditos y compras
- Tests: webhook idempotencia, balance check

### PR5: AIService + jobs + worker + ejecución por lotes
**Scope:** API  
**Feature flag:** `seo.ai_autopilot` (gated)

- `SeoAiService` → OpenAI integration con `gpt-4o-mini`
- `SeoAiJobService` → CRUD jobs + status
- `SeoAiWorkerService` → `@Interval(10000)` polling, chunks de 25
- Prompts: site, category, product (JSON estricto)
- Guardrails: rate limit, concurrent limit, max tokens
- Log de cambios con diff
- UI Store Admin: lanzar job, ver progreso, ver log
- Tests: mock OpenAI, verify precedencia, verify locked skip

### PR6: Auditoría SEO + prompt copiable + SERP preview
**Scope:** API + Web + Admin  
**Feature flag:** Auditoría AI gated, auditoría sin-IA libre en Growth

- Auditoría sin IA: endpoint que escanea faltantes/duplicados/largos
- Auditoría con IA: job type `audit` → prompt de auditoría → reporte
- SERP preview en entity meta editor (Google-like snippet)
- Prompt copiable "Generar con ChatGPT" en Growth (sin consumir créditos)
- Contadores y warnings en SeoView
- UI Super Admin: vista de jobs con errores, reintentos

### PR7: Hardening final + docs + tests
**Scope:** Todos  
**Feature flag:** — (estabilización)

- Tests E2E: cross-tenant isolation (user A no ve jobs de user B)
- Tests: webhook doble, balance insuficiente, locked skip
- Rate limit ajustado
- Runbook de incidentes (`docs/runbooks/seo-ai-incident.md`)
- Docs completa (`docs/seo/SEO_AI_GUIDE.md`)
- Verificación de seguridad: API key nunca expuesta

---

## 9. Riesgos y Mitigaciones

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|---|---|---|---|
| 1 | **API OpenAI down** | Media | Worker falla | Retry 2x + backoff 30s. Job queda en `failed` con error claro. Tenant puede reintentar. No descuenta créditos. |
| 2 | **Output AI inválido** | Baja | Campo mal formado | JSON schema validation strict. Si parse falla → skip item, log error. |
| 3 | **Cross-tenant data leak** | Muy baja | Crítico | Toda query scopeada por `client_id`. RLS como segunda defensa. Test E2E obligatorio. |
| 4 | **Abuso de créditos** | Baja | Pérdida financiera | Balance check pre-job + rate limit + concurrent limit. |
| 5 | **Worker bloquea el proceso NestJS** | Baja | Degradación general | Chunks chicos (25), delays entre chunks, no bloquea event loop (await entre items). |
| 6 | **MP webhook no llega** | Baja | Tenant pagó pero sin créditos | Reconciliación diaria (cron): consulta pagos approved sin créditos asociados. |
| 7 | **Cambio de precios OpenAI** | Media | Margen afectado | Margen 70x; incluso 10x de aumento sería absorbible. Monitorear con alertas. |
| 8 | **Rollback de SEO** | — | — | `seo_ai_log` tiene `old_value`. Endpoint de revert por entity + campo. |

---

## Definición de Done

- [ ] Un tenant Growth puede configurar SEO sin IA y no rompe checkout/compra
- [ ] Un tenant puede comprar pack AI, correr job sobre 2000 productos, ver progreso, y revertir
- [ ] Super admin puede editar precios y ver pagos+consumo+auditorías
- [ ] No hay cross-tenant leaks (test E2E)
- [ ] P0 fixes (noindex, slug categories, canonical) resueltos
- [ ] Docs completas + runbook

---

## Próximos pasos

**Esperando aprobación del TL para:**

1. Empezar PR1 (P0 fixes — sin IA, sin riesgo)
2. Confirmar precios de packs propuestos
3. Confirmar que `gpt-4o-mini` es aceptable como modelo default
4. Confirmar prioridad: ¿PR1 primero o PR1+PR2 en paralelo?

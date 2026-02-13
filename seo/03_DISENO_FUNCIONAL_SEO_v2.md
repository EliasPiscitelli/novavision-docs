# Diseño Funcional SEO — NovaVision (v2 enriquecido)

**Fecha:** 2026-02-12 (rev. v2)  
**Autor:** Agente Copilot  
**Revisión:** Modelo de datos enriquecido, separación Super Admin vs Admin Client, política canonical, QA checklist, propuesta de servicio con tiers.

---

## Índice
1. [Propuesta de Servicio SEO (tiers)](#1-propuesta-de-servicio-seo-tiers)
2. [Separación Super Admin vs Admin Client](#2-separación-super-admin-vs-admin-client)
3. [Modelo de Datos Completo](#3-modelo-de-datos-completo)
4. [API Contracts](#4-api-contracts)
5. [Política de Canonical + Custom Domains](#5-política-de-canonical--custom-domains)
6. [Wireframes Funcionales (Admin Client)](#6-wireframes-funcionales-admin-client)
7. [Wireframes Funcionales (Super Admin)](#7-wireframes-funcionales-super-admin)
8. [Reglas de Negocio SEO](#8-reglas-de-negocio-seo)
9. [GA4 + Search Console — Diseño Operativo](#9-ga4--search-console--diseño-operativo)
10. [QA Checklist SEO Completo](#10-qa-checklist-seo-completo)
11. [Entitlements por Plan](#11-entitlements-por-plan)

---

## 1. Propuesta de Servicio SEO (tiers)

### Tier: Gratis (todos los planes)

| Feature | Detalle | Motivo |
|---------|---------|--------|
| `noindex` en preview/staging | X-Robots-Tag en branch/deploy previews | Higiene — indexar drafts es un bug |
| robots.txt con Disallow de rutas privadas | `/admin-dashboard`, `/cart`, `/profile`, `/login` | Higiene |
| Canonical link en `<head>` | Apunta a canonical_domain + path | Evita duplicados |
| 301 redirect subdomain ↔ custom domain | Solo el canónico sirve contenido | Anti-duplicado |
| Sitemap vacío válido | No romper Search Console con HTML en `/sitemap.xml` | Higiene |
| Soft 404 fix | Retornar 404 real para rutas inexistentes (donde Netlify lo permita) | Crawl budget |

> **Principio:** Lo que protege de daño no se cobra. Cobrar noindex sería como cobrar por no romper cosas.

### Tier: Growth SEO (~$X/mes adicional)

| Feature | Detalle |
|---------|---------|
| **Head dinámico** | Titles/meta/canonical personalizados por página (Helmet) |
| **Sitemap XML por tenant** | Generado, cacheado, con imágenes |
| **robots.txt dinámico** | Con Sitemap directive del canonical del tenant |
| **Social previews** (OG/Twitter) | Edge function para crawlers sociales |
| **Admin UI SEO** | Editar site_title, site_description, meta por producto |
| **Product slugs** | URL `/p/:id/:slug` semánticas |
| **GA4 per tenant** | Measurement ID configurable + enhanced e-commerce events |
| **Search Console token** | Verificación de propiedad vía meta tag |
| **SEO Report básico** | Dashboard con: páginas indexadas estimadas, errores de schema |

### Tier: Enterprise SEO (~$Y/mes adicional)

| Feature | Detalle |
|---------|---------|
| Todo Growth SEO | ✅ |
| **Structured Data (JSON-LD)** | Product, Organization, BreadcrumbList, FAQ |
| **Rich Snippets** | Precios, stock, reviews en SERPs |
| **Schema validation** | Validador en admin + CI que alerta schema inválido |
| **Custom meta por entidad** | meta_title, meta_description por producto y categoría |
| **URL redirects manager** | Admin puede crear 301 redirects custom |
| **SEO Score per product** | Indicador de completitud SEO (título, descripción, imagen, slug) |
| **Soporte dedicado SEO** | Onboarding con configuración inicial incluída |

---

## 2. Separación Super Admin vs Admin Client

### Super Admin (NovaVision — app Admin)

| Capacidad | Scope |
|-----------|-------|
| Ver estado SEO de todos los tenants | Dashboard global |
| Override `noindex` por tenant (forzar) | Ej: tenant en deuda → forzar noindex |
| **Activar/desactivar features SEO por cliente** | Override individual, independiente del plan |
| Gestionar planes + entitlements SEO | Plans table + feature flags |
| Regenerar sitemaps masivamente | Endpoint admin `/seo/regenerate-all` |
| Ver métricas SEO agregadas | Total páginas indexadas, errores, etc. |
| Configurar defaults globales | Default OG image, default robots rules |
| Auditar schema emission | Ver qué tenants emiten JSON-LD y cuáles no |

### Admin Client (Tenant — dentro del storefront admin)

| Capacidad | Plan requerido | Override per-client | Scope |
|-----------|---------------|---------------------|-------|
| Ver estado SEO de SU tienda | Growth+ | ✅ Activable | Su tenant |
| Editar `site_title`, `site_description` | Growth+ | ✅ Activable | Su tenant |
| Editar meta por producto/categoría | Enterprise | ✅ Activable | Su tenant |
| Ver preview OG/Google | Growth+ | ✅ Activable | Su tenant |
| Configurar GA4 measurement ID | Growth+ | ✅ Activable | Su tenant |
| Configurar Search Console token | Growth+ | ✅ Activable | Su tenant |
| Crear URL redirects | Enterprise | ✅ Activable | Su tenant |
| Ver SEO Score por producto | Enterprise | ✅ Activable | Su tenant |

> **Columna "Override per-client":** El Super Admin puede activar cualquiera de estas features para un cliente específico **independientemente de su plan**, usando el sistema de `feature_overrides` existente. Ej: un cliente Starter puede tener `seo.settings: true` sin necesidad de upgrade a Growth.

---

### 2.1 Activación per-client via Feature Overrides (sistema existente)

NovaVision ya tiene un sistema robusto de overrides per-client que se reutiliza tal cual.

**Cómo funciona hoy:**

```
Cliente con plan "starter" → plan dice seo.settings = false
  ↓
Super Admin activa override: feature_overrides = { "seo.settings": true }
  ↓
PlanAccessGuard evalúa:
  1. ¿Hay override? → SÍ (true) → PERMITIR ✅
  2. Si no hay override → usar valor del plan → DENEGAR ❌
```

**Implementación técnica — ya existe, solo se agregan entradas al catálogo:**

1. **Tabla `clients` (Backend DB)** — columna `feature_overrides JSONB`:
   ```json
   // Ejemplo: cliente starter con SEO settings y sitemap activados por override
   {
     "seo.settings": true,
     "seo.sitemap": true,
     "seo.analytics": true
   }
   ```

2. **Guard existente `PlanAccessGuard`** (`src/plans/guards/plan-access.guard.ts`):
   ```typescript
   // YA implementado — cadena de resolución:
   // 1. Leer feature_overrides[featureId] del cliente
   // 2. Si es boolean → usar ese valor (OVERRIDE GANA)
   // 3. Si no → usar FEATURE_CATALOG[featureId].plans[planKey]
   ```

3. **Admin UI existente** (`apps/admin/src/pages/ClientDetails/hooks/useClientFeatureOverrides.js`):
   ```
   GET  /admin/plans/clients/:clientId/features → lista features con { plan_default, override, effective }
   PATCH /admin/plans/clients/:clientId/features → body { feature_id: "seo.settings", enabled: true|false|null }
   ```
   - `true` → forzar activación (aunque el plan no lo incluya)
   - `false` → forzar desactivación (aunque el plan sí lo incluya)
   - `null` → usar valor default del plan

**Lo único que se necesita agregar: entradas en `FEATURE_CATALOG`** (ver sección 2.2).

### 2.2 Features SEO para el Catálogo (`featureCatalog.ts`)

```typescript
// ─── SEO ──────────────────────────────────────────────────────
{
  id: 'seo.settings',
  title: 'SEO: Configuración general',
  category: 'storefront',
  surfaces: ['client_dashboard', 'storefront', 'api_only'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/seo/settings', note: 'Lectura pública (cacheado)' },
    { type: 'endpoint', method: 'PUT', path: '/seo/settings', note: 'Editar site_title, description, OG, etc.' },
  ],
},
{
  id: 'seo.entity_meta',
  title: 'SEO: Meta por producto/categoría',
  category: 'storefront',
  surfaces: ['client_dashboard', 'api_only'],
  plans: { starter: false, growth: false, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'PUT', path: '/seo/product-meta/:id', note: 'Editar meta_title, meta_description por producto' },
  ],
},
{
  id: 'seo.sitemap',
  title: 'SEO: Sitemap XML por tienda',
  category: 'storefront',
  surfaces: ['storefront', 'api_only'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/seo/sitemap.xml', note: 'Sitemap cacheado del tenant' },
    { type: 'endpoint', method: 'POST', path: '/seo/sitemap/regenerate', note: 'Regenerar sitemap (admin)' },
  ],
},
{
  id: 'seo.schema',
  title: 'SEO: Structured Data (JSON-LD)',
  category: 'storefront',
  surfaces: ['storefront'],
  plans: { starter: false, growth: false, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/seo/meta/product/:id', note: 'Incluye jsonld si válido' },
  ],
},
{
  id: 'seo.analytics',
  title: 'SEO: GA4 + Search Console per tenant',
  category: 'analytics',
  surfaces: ['client_dashboard', 'storefront'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'PUT', path: '/seo/settings', note: 'Campos ga4_measurement_id, search_console_token' },
  ],
},
{
  id: 'seo.redirects',
  title: 'SEO: Redirects manager (301)',
  category: 'storefront',
  surfaces: ['client_dashboard', 'api_only'],
  plans: { starter: false, growth: false, enterprise: true },
  status: 'planned',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/seo/redirects', note: 'Listar redirects del tenant' },
    { type: 'endpoint', method: 'POST', path: '/seo/redirects', note: 'Crear redirect' },
  ],
},
```

### 2.3 Escenarios de Activación por Cliente

| Escenario | Plan | Override | Resultado |
|-----------|------|----------|-----------|
| Cliente Growth, sin override | growth | `null` | `seo.settings` = ✅ (plan lo incluye) |
| Cliente Starter, sin override | starter | `null` | `seo.settings` = ❌ (plan no lo incluye) |
| Cliente Starter, **override activado** | starter | `{ "seo.settings": true }` | `seo.settings` = ✅ **Override gana** |
| Cliente Growth, **override desactivado** | growth | `{ "seo.settings": false }` | `seo.settings` = ❌ **Override gana** |
| Cliente Enterprise, sin override | enterprise | `null` | Todas las SEO features = ✅ |
| Cliente Starter con **SEO completo gratis** (promo) | starter | `{ "seo.settings": true, "seo.sitemap": true, "seo.analytics": true, "seo.entity_meta": true, "seo.schema": true }` | Todo activado sin cambiar plan |

### 2.4 Wireframe Super Admin — Feature Overrides para SEO

Esta UI **ya existe** en `ClientDetails` del Admin Dashboard. Al agregar las features al catálogo, aparecen automáticamente. Así se ve:

```
┌─────────────────────────────────────────────────────────────────┐
│ 👤 Cliente: ModaFit  │  Plan: starter  │  Estado: activo        │
├─────────────┬───────────────────────────────────────────────────┤
│ Info │ Plan │ Features │ Entitlements │ Pagos │ Notas           │
│             ▲                                                   │
│ ────────────┴───────────────────────────────────────────────────│
│                                                                 │
│  📂 storefront                                                  │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Feature                        │ Plan │ Override │ Efect.│   │
│  ├────────────────────────────────┼──────┼──────────┼───────┤   │
│  │ Home dinámico con secciones    │  ✅  │   —      │  ✅   │   │
│  │ Selector de templates          │  ✅  │   —      │  ✅   │   │
│  │ SEO: Configuración general     │  ❌  │  [✅]    │  ✅   │ ← override │
│  │ SEO: Meta por producto/categ.  │  ❌  │  [✅]    │  ✅   │ ← override │
│  │ SEO: Sitemap XML por tienda    │  ❌  │  [✅]    │  ✅   │ ← override │
│  │ SEO: Structured Data (JSON-LD) │  ❌  │   —      │  ❌   │   │
│  │ SEO: Redirects manager (301)   │  ❌  │   —      │  ❌   │   │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  📂 analytics                                                   │
│  ┌──────────────────────────────────────────────────────────┐   │
│  │ Analytics por rango            │  ❌  │   —      │  ❌   │   │
│  │ SEO: GA4 + Search Console      │  ❌  │  [✅]    │  ✅   │ ← override │
│  └──────────────────────────────────────────────────────────┘   │
│                                                                 │
│  ℹ️ Override: ✅ = forzar ON │ ❌ = forzar OFF │ — = usar plan  │
│                                                                 │
│  💾 Los cambios se aplican al instante vía PATCH               │
│     /admin/plans/clients/:clientId/features                     │
└─────────────────────────────────────────────────────────────────┘
```

**Acción del Super Admin:** Click en el toggle de Override de la feature SEO → `PATCH /admin/plans/clients/:clientId/features` → `{ feature_id: "seo.settings", enabled: true }` → el cliente Starter ahora tiene SEO settings activado.

### 2.5 Casos de uso de negocio para overrides

| Caso de uso | Override |
|-------------|----------|
| **Promoción:** "Te regalamos 3 meses de SEO" | Activar features SEO en el Starter, desactivar después |
| **Onboarding premium:** cliente que va a migrar a Growth | Pre-activar SEO para que configure antes del upgrade |
| **Cliente VIP:** paga Starter pero tiene acuerdo especial | Override permanente de features seleccionadas |
| **Penalización:** cliente con contenido spam | `seo_settings.force_noindex = true` + override `seo.settings: false` |
| **Demo/prueba:** cliente quiere probar antes de comprar | Activar por 15 días, luego resetear a `null` |
| **Partner/afiliado:** acceso completo sin pagar Enterprise | Override de todas las features SEO |

### API Guard por Entitlement (actualizado)

```typescript
// En el endpoint PUT /seo/settings
// Usa PlanAccessGuard que ya soporta overrides per-client
@UseGuards(TenantContextGuard, PlanAccessGuard)
@PlanFeature('seo.settings') // Growth+ por plan, o activado por override
@Put('settings')
async updateSeoSettings(@Body() dto: UpdateSeoSettingsDto) { ... }

// En el endpoint PUT /seo/product-meta/:id
@UseGuards(TenantContextGuard, PlanAccessGuard)
@PlanFeature('seo.entity_meta') // Enterprise por plan, o activado por override
@Put('product-meta/:id')
async updateProductMeta(@Param('id') id: string, @Body() dto: UpdateProductMetaDto) { ... }

// En el endpoint GET /seo/sitemap.xml
@UseGuards(TenantContextGuard, PlanAccessGuard)
@PlanFeature('seo.sitemap') // Growth+ por plan, o activado por override
@Get('sitemap.xml')
async getSitemap() { ... }

// En el endpoint GET /seo/meta/product/:id (JSON-LD)
@UseGuards(TenantContextGuard, PlanAccessGuard)
@PlanFeature('seo.schema') // Enterprise por plan, o activado por override
@Get('meta/product/:id')
async getProductMeta(@Param('id') id: string) { ... }
```

**Cadena de resolución completa (ya implementada en `PlanAccessGuard`):**
```
Request → PlanAccessGuard
  ├── Lee @PlanFeature('seo.settings') del decorador
  ├── Busca client.feature_overrides['seo.settings']
  │   ├── Si es true → PERMITIR ✅ (override forzado)
  │   ├── Si es false → DENEGAR ❌ (override forzado)
  │   └── Si es null/undefined → continuar ↓
  ├── Busca FEATURE_CATALOG['seo.settings'].plans[client.plan_key]
  │   ├── Si true → PERMITIR ✅ (plan lo incluye)
  │   └── Si false → DENEGAR ❌ → 403 FEATURE_GATED
  └── Response 403: { code: 'FEATURE_GATED', required_plan: 'growth' }
```

---

## 3. Modelo de Datos Completo

### 3.1 Tabla: `seo_settings`

```sql
CREATE TABLE seo_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL UNIQUE REFERENCES clients(id) ON DELETE CASCADE,

  -- Identidad
  site_title TEXT,                     -- "Mi Tienda Online" (max 60)
  site_description TEXT,               -- "Los mejores productos..." (max 160)
  brand_name TEXT,                     -- "MiMarca" — usado en schema, breadcrumbs
  
  -- OG defaults
  og_image_default TEXT,               -- URL imagen OG fallback
  
  -- Favicon / PWA
  favicon_url TEXT,
  pwa_name TEXT,                       -- nombre largo en manifest
  pwa_short_name TEXT,                 -- nombre corto
  pwa_theme_color TEXT,                -- hex color
  
  -- Analytics
  ga4_measurement_id TEXT,             -- "G-XXXXXXXXXX"
  gtm_container_id TEXT,               -- "GTM-XXXXXXX"
  
  -- Search Console
  search_console_token TEXT,           -- verificación meta tag
  
  -- Canonical policy
  canonical_domain TEXT,               -- "mitienda.com" o "slug.novavision.lat" (derivado auto)
  force_noindex BOOLEAN DEFAULT false, -- Super Admin override (ej: tienda suspendida)
  
  -- Social links (para schema:Organization sameAs)
  social_instagram TEXT,
  social_facebook TEXT,
  social_tiktok TEXT,
  social_twitter TEXT,
  social_youtube TEXT,
  social_whatsapp TEXT,                -- "+54 9 11 1234-5678"
  
  -- URL config
  product_url_pattern TEXT DEFAULT '/p/:id/:slug',
  
  -- Extensibilidad
  custom_meta JSONB DEFAULT '{}',      -- meta tags custom (ej: google-site-verification extra)
  
  -- Audit
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID
);

-- Índices
CREATE INDEX idx_seo_settings_client ON seo_settings(client_id);

-- RLS (sama patrón que todas las tablas multi-tenant)
ALTER TABLE seo_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seo_select_tenant" ON seo_settings FOR SELECT
USING (client_id = current_client_id());

CREATE POLICY "seo_write_admin" ON seo_settings FOR ALL
USING (client_id = current_client_id() AND is_admin())
WITH CHECK (client_id = current_client_id() AND is_admin());

CREATE POLICY "server_bypass" ON seo_settings FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

### 3.2 Columnas nuevas en `products`

```sql
ALTER TABLE products ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS meta_title TEXT;         -- max 60
ALTER TABLE products ADD COLUMN IF NOT EXISTS meta_description TEXT;   -- max 160
ALTER TABLE products ADD COLUMN IF NOT EXISTS noindex BOOLEAN DEFAULT false;
ALTER TABLE products ADD COLUMN IF NOT EXISTS canonical_override TEXT; -- URL override

CREATE UNIQUE INDEX idx_products_slug_unique ON products(client_id, slug);
CREATE INDEX idx_products_active_noindex ON products(client_id, active, noindex);
```

### 3.3 Columnas nuevas en `categories`

```sql
ALTER TABLE categories ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS meta_title TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS meta_description TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS noindex BOOLEAN DEFAULT false;

CREATE UNIQUE INDEX idx_categories_slug_unique ON categories(client_id, slug);
```

### 3.4 Tabla: `seo_sitemaps` (cache de sitemaps)

```sql
CREATE TABLE seo_sitemaps (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL UNIQUE REFERENCES clients(id) ON DELETE CASCADE,
  xml_content TEXT NOT NULL,            -- XML completo del sitemap
  urls_count INTEGER DEFAULT 0,         -- métricas
  generated_at TIMESTAMPTZ DEFAULT now(),
  generation_trigger TEXT,              -- 'product_change', 'cron', 'manual'
  generation_duration_ms INTEGER        -- performance tracking
);

ALTER TABLE seo_sitemaps ENABLE ROW LEVEL SECURITY;

-- Solo server bypass (no necesita acceso de usuario)
CREATE POLICY "server_bypass" ON seo_sitemaps FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

### 3.5 Tabla: `seo_redirects` (Enterprise)

```sql
CREATE TABLE seo_redirects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  from_path TEXT NOT NULL,              -- "/vieja-url"
  to_path TEXT NOT NULL,                -- "/nueva-url" o URL absoluta
  status_code INTEGER DEFAULT 301,      -- 301 o 302
  active BOOLEAN DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID,
  
  UNIQUE(client_id, from_path)
);

ALTER TABLE seo_redirects ENABLE ROW LEVEL SECURITY;

CREATE POLICY "redirects_select_tenant" ON seo_redirects FOR SELECT
USING (client_id = current_client_id());

CREATE POLICY "redirects_write_admin" ON seo_redirects FOR ALL
USING (client_id = current_client_id() AND is_admin())
WITH CHECK (client_id = current_client_id() AND is_admin());

CREATE POLICY "server_bypass" ON seo_redirects FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

### 3.6 Entitlements: Features SEO en `plans`

```json
{
  "starter": {
    "seo_basic": true,        // noindex, canonical, robots — GRATIS
    "seo_settings": false,
    "seo_entity_meta": false,
    "seo_sitemap": false,
    "seo_schema": false,
    "seo_redirects": false,
    "seo_analytics": false
  },
  "growth": {
    "seo_basic": true,
    "seo_settings": true,      // site_title, description, OG
    "seo_entity_meta": false,  // meta por producto → Enterprise
    "seo_sitemap": true,       // sitemap XML
    "seo_schema": false,       // JSON-LD → Enterprise
    "seo_redirects": false,    // redirects manager → Enterprise
    "seo_analytics": true      // GA4 + GSC
  },
  "enterprise": {
    "seo_basic": true,
    "seo_settings": true,
    "seo_entity_meta": true,
    "seo_sitemap": true,
    "seo_schema": true,
    "seo_redirects": true,
    "seo_analytics": true
  }
}
```

---

## 4. API Contracts

### 4.1 GET `/seo/settings` (público, cacheado)

**Headers:** `x-tenant-slug` (requerido)  
**Auth:** No requerido (público)  
**Cache:** 5 minutos, Vary: x-tenant-slug

**Response 200:**
```json
{
  "site_title": "ModaFit",
  "site_description": "Ropa deportiva de diseño argentino",
  "brand_name": "ModaFit",
  "og_image_default": "https://storage.../default-og.webp",
  "favicon_url": "https://storage.../favicon.ico",
  "canonical_domain": "modafit.com",
  "social_instagram": "https://instagram.com/modafit",
  "social_whatsapp": "+5491112345678",
  "ga4_measurement_id": "G-ABC123",
  "search_console_token": "verificacion123",
  "product_url_pattern": "/p/:id/:slug"
}
```

**Nota:** `force_noindex`, `gtm_container_id` y campos sensibles NO se exponen en la respuesta pública. Se envían solo a admin.

### 4.2 PUT `/seo/settings` (admin, Growth+)

**Headers:** `Authorization: Bearer <jwt>`, `x-tenant-slug`  
**Guard:** `TenantContextGuard` + `PlanEntitlementGuard('seo_settings')`

**Request body:**
```json
{
  "site_title": "ModaFit",
  "site_description": "Ropa deportiva...",
  "brand_name": "ModaFit",
  "og_image_default": "https://...",
  "ga4_measurement_id": "G-ABC123",
  "search_console_token": "abc",
  "social_instagram": "https://instagram.com/modafit"
}
```

**Validaciones:**
- `site_title`: max 60 chars
- `site_description`: max 160 chars
- `ga4_measurement_id`: regex `/^G-[A-Z0-9]+$/`
- `social_*`: URL válida o vacío

### 4.3 GET `/seo/meta/product/:id` (público, cacheado)

**Uso:** Edge function de social crawlers + frontend Helmet.

**Response 200:**
```json
{
  "title": "Zapatillas Running Nike — ModaFit",
  "description": "Las mejores zapatillas para correr...",
  "canonical": "https://modafit.com/p/abc123/zapatillas-running-nike",
  "og_title": "Zapatillas Running Nike",
  "og_description": "Las mejores zapatillas...",
  "og_image": "https://storage.../product-lg.webp",
  "og_type": "product",
  "og_url": "https://modafit.com/p/abc123/zapatillas-running-nike",
  "twitter_card": "summary_large_image",
  "robots": "index, follow",
  "jsonld": { ... },
  "breadcrumbs": [
    {"name": "ModaFit", "url": "/"},
    {"name": "Running", "url": "/search?category=running"},
    {"name": "Zapatillas Running Nike", "url": "/p/abc123/zapatillas-running-nike"}
  ]
}
```

**Lógica de fallback:**
1. Si producto tiene `meta_title` → usar
2. Si no → `"{product.name} — {seo_settings.brand_name || seo_settings.site_title}"`
3. Si no hay `og_image` override → usar primera imagen del producto
4. Si producto tiene `noindex: true` → `"robots": "noindex, nofollow"`

### 4.4 POST `/seo/sitemap/regenerate` (admin, Growth+)

**Trigger:** Puede ser llamado manualmente o por eventos internos.

**Response 200:**
```json
{
  "status": "regenerated",
  "urls_count": 142,
  "duration_ms": 350,
  "generated_at": "2026-02-12T15:30:00Z"
}
```

### 4.5 GET `/seo/sitemap.xml` (público)

**Response 200:** XML válido (leer de `seo_sitemaps` cache)  
**Content-Type:** `application/xml`  
**Cache:** `public, max-age=3600`

### 4.6 GET `/seo/robots.txt` (público)

**Response 200:** robots.txt personalizado  
**Content-Type:** `text/plain`  
**Cache:** `public, max-age=86400`

---

## 5. Política de Canonical + Custom Domains

### Regla general

```
SI tenant tiene custom_domain configurado Y activo:
  → canonical_domain = custom_domain (ej: "modafit.com")
  → subdomain redirect: slug.novavision.lat/* → 301 → modafit.com/*
  
SI tenant NO tiene custom_domain:
  → canonical_domain = slug.novavision.lat
  → Sin redirect
```

### Derivación automática de `canonical_domain`

```typescript
// Al cambiar custom_domain en nv_accounts → actualizar seo_settings.canonical_domain
function deriveCanonicalDomain(account: NvAccount): string {
  if (account.custom_domain && account.custom_domain_status === 'active') {
    return account.custom_domain;
  }
  return `${account.slug}.novavision.lat`;
}
```

### Implementación de redirect 301 (edge function)

```typescript
// netlify/edge-functions/canonical-redirect.ts
export default async (req: Request, context: Context) => {
  const hostname = new URL(req.url).hostname;
  
  // No redirect para assets, API calls, etc.
  if (isStaticAsset(req.url) || isApiCall(req.url)) {
    return context.next();
  }
  
  // Buscar canonical_domain del tenant
  const tenantSlug = extractSlug(hostname);
  const canonical = await fetchCanonicalDomain(tenantSlug);
  
  if (canonical && hostname !== canonical) {
    const newUrl = new URL(req.url);
    newUrl.hostname = canonical;
    return Response.redirect(newUrl.toString(), 301);
  }
  
  return context.next();
};
```

### CORs y cookies post-redirect

Después del 301, el browser está en `modafit.com`. El API está en `railway.app`. CORS debe incluir el custom domain.

**Checklist:**
- [ ] CORS origin incluye custom domains activos
- [ ] Cookies de auth funcionan post-redirect (SameSite, domain)
- [ ] OAuth callbacks apuntan al canonical domain

---

## 6. Wireframes Funcionales (Admin Client)

### SEO Settings — General

```
┌─────────────────────────────────────────────────────────┐
│ ⚙️ SEO — Configuración General                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Título del sitio *           [ModaFit________________] │
│  (60 caracteres máx.)         50/60                     │
│                                                         │
│  Descripción *                [Ropa deportiva de diseño │
│  (160 caracteres máx.)         argentino para...______] │
│                                 89/160                  │
│                                                         │
│  Nombre de marca              [ModaFit________________] │
│  (para Google y redes)                                  │
│                                                         │
│  Imagen OG por defecto        [📎 Subir imagen]        │
│  (1200x630 px recomendado)    [preview: █████████████]  │
│                                                         │
│  ─── Vista previa Google ─────────────────────────────  │
│  │ ModaFit — modafit.com                              │ │
│  │ Ropa deportiva de diseño argentino para...         │ │
│  ──────────────────────────────────────────────────────  │
│                                                         │
│  ─── Vista previa WhatsApp ───────────────────────────  │
│  │ [🖼️ og_image]                                      │ │
│  │ ModaFit                                            │ │
│  │ Ropa deportiva de diseño argentino                 │ │
│  ──────────────────────────────────────────────────────  │
│                                                         │
│                              [Cancelar]  [💾 Guardar]   │
└─────────────────────────────────────────────────────────┘
```

### SEO Settings — Redes Sociales

```
┌─────────────────────────────────────────────────────────┐
│ 🔗 SEO — Redes Sociales                                 │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Instagram   [https://instagram.com/modafit___________] │
│  Facebook    [https://facebook.com/modafit____________] │
│  TikTok      [_______________________________________]  │
│  Twitter/X   [_______________________________________]  │
│  YouTube     [_______________________________________]  │
│  WhatsApp    [+54 9 11 1234-5678_____________________]  │
│                                                         │
│  ℹ️ Estos links aparecen en el schema de Google         │
│  (Organization.sameAs) y en el pie de la tienda.        │
│                                                         │
│                              [Cancelar]  [💾 Guardar]   │
└─────────────────────────────────────────────────────────┘
```

### SEO Settings — Analytics

```
┌─────────────────────────────────────────────────────────┐
│ 📊 SEO — Analytics                                       │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Google Analytics 4                                     │
│  Measurement ID      [G-________________]              │
│  ℹ️ Obtené tu ID en analytics.google.com > Admin >      │
│     Flujos de datos > Tu web                            │
│                                                         │
│  ─────────────────────────────────────────────────────  │
│                                                         │
│  Google Search Console                                  │
│  Token de verificación  [________________________________]│
│  ℹ️ Pasos:                                              │
│  1. Ir a search.google.com/search-console               │
│  2. Agregar propiedad: https://modafit.com              │
│  3. Método: Meta tag HTML                               │
│  4. Copiar el contenido del meta tag acá                │
│                                                         │
│  Estado: ✅ Verificado (o ❌ Pendiente de verificación)  │
│                                                         │
│                              [Cancelar]  [💾 Guardar]   │
└─────────────────────────────────────────────────────────┘
```

### SEO por Producto (Enterprise — en vista de edición)

```
┌─────────────────────────────────────────────────────────┐
│ 📝 Editar Producto — Zapatillas Running                  │
├─────────────────────────────────────────────────────────┤
│ [Info] [Imágenes] [Stock] [SEO 🔎]                      │
│                                                         │
│  ─── Tab: SEO ────────────────────────────────────────  │
│                                                         │
│  Slug URL             [zapatillas-running-nike_________] │
│  URL final: modafit.com/p/abc123/zapatillas-running-nk  │
│                                                         │
│  Meta título          [Zapatillas Running Nike — Modaf] │
│  (auto: nombre + marca)  46/60                          │
│                                                         │
│  Meta descripción     [Las mejores zapatillas para cor] │
│  (auto: descripción)     78/160                         │
│                                                         │
│  Ocultar de buscadores  [ ] No indexar este producto    │
│                                                         │
│  ─── SEO Score: ████████░░ 80% ───────────────────────  │
│  ✅ Tiene título (46 chars)                              │
│  ✅ Tiene descripción (78 chars)                         │
│  ✅ Tiene imagen principal                               │
│  ✅ Tiene precio                                         │
│  ⚠️ Slug podría ser más corto                           │
│  ❌ Sin imagen OG específica                             │
│                                                         │
│  ─── Vista previa Google ─────────────────────────────  │
│  │ Zapatillas Running Nike — ModaFit                  │ │
│  │ modafit.com › p › abc123 › zapatillas-running-nike │ │
│  │ Las mejores zapatillas para correr con...          │ │
│  ──────────────────────────────────────────────────────  │
│                                                         │
│                              [Cancelar]  [💾 Guardar]   │
└─────────────────────────────────────────────────────────┘
```

---

## 7. Wireframes Funcionales (Super Admin)

### SEO Dashboard Global

```
┌─────────────────────────────────────────────────────────┐
│ 🔎 SEO — Overview (Super Admin)                          │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Resumen                                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐   │
│  │ 47       │ │ 12       │ │ 35       │ │ 8        │   │
│  │ Tenants  │ │ Growth+  │ │ Sitemaps │ │ Con GA4  │   │
│  │ activos  │ │ con SEO  │ │ generados│ │ activo   │   │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘   │
│                                                         │
│  Tenants sin configurar SEO (Growth+)                   │
│  ┌────────────────────────────────────────────────────┐ │
│  │ Tenant         │ Plan     │ SEO Config │ Sitemap  │ │
│  ├────────────────┼──────────┼────────────┼──────────┤ │
│  │ modafit        │ growth   │ ⚠️ parcial │ ✅ OK    │ │
│  │ deportemax     │ growth   │ ❌ vacío   │ ❌ No    │ │
│  │ elegante       │ enterp.  │ ✅ completo│ ✅ OK    │ │
│  │ tecnostore     │ growth   │ ❌ vacío   │ ❌ No    │ │
│  └────────────────────────────────────────────────────┘ │
│                                                         │
│  Acciones:                                              │
│  [🔄 Regenerar todos los sitemaps]                      │
│  [📊 Exportar reporte SEO]                              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

### Force noindex (Super Admin)

```
┌─────────────────────────────────────────────────────────┐
│ ⚠️ Control de Indexación — modafit                        │
├─────────────────────────────────────────────────────────┤
│                                                         │
│  Estado actual: ✅ Indexable                              │
│                                                         │
│  [🔴 Forzar noindex]                                    │
│                                                         │
│  Motivos posibles:                                      │
│  ○ Cuenta suspendida                                    │
│  ○ Contenido inapropiado/spam                           │
│  ○ Solicitud del cliente                                │
│  ○ Otro: [_________]                                    │
│                                                         │
│  ℹ️ Forzar noindex agrega X-Robots-Tag: noindex a       │
│  TODAS las páginas de esta tienda. El admin del tenant  │
│  NO puede revertirlo.                                   │
│                                                         │
│                              [Cancelar]  [⚠️ Confirmar] │
└─────────────────────────────────────────────────────────┘
```

---

## 8. Reglas de Negocio SEO

### 8.1 Generación de Slugs

```
Input: "Zapatillas Running Nike Air Max 90"
Output: "zapatillas-running-nike-air-max-90"

Reglas:
1. slugify(name): lowercase, reemplazar espacios con -, strip acentos y chars especiales
2. Max 80 caracteres (truncar en word boundary)
3. Collision: slug-1, slug-2 (scoped por client_id)
4. Inmutable una vez creado (cambio manual requiere 301 redirect)
5. Backfill: migration genera slugs para productos existentes
```

### 8.2 Meta Tags Fallback Chain

```
title:        meta_title → "{product.name} — {brand_name}" → "{product.name} — {site_title}"
description:  meta_description → truncate(product.description, 160)
og_image:     product.image → seo_settings.og_image_default → logo_url
canonical:    canonical_override → "{canonical_domain}/{path}"
```

### 8.3 JSON-LD Emission Rules

```
Product schema: EMITIR solo si:
  ✅ product.name existe
  ✅ product.price > 0
  ✅ product.imageUrl existe
  ✅ product.active === true
  ✅ product.noindex !== true

Organization schema: EMITIR solo si:
  ✅ seo_settings.brand_name O site_title existe

BreadcrumbList: EMITIR siempre (con fallback a "Home" → "Producto")

FAQ schema: EMITIR solo si:
  ✅ tenant tiene FAQs activas (count > 0)
```

### 8.4 Sitemap Inclusion Rules

```
Incluir en sitemap:
  ✅ URLs de productos: active: true AND noindex: false
  ✅ URLs de categorías: con al menos 1 producto activo AND noindex: false
  ✅ Homepage: siempre
  ✅ /search: si tiene productos

Excluir:
  ❌ Productos inactivos
  ❌ Productos/categorías con noindex: true
  ❌ Rutas privadas (/cart, /profile, /login, etc.)
```

### 8.5 Canonical Policy Rules

```
IF tenant.custom_domain AND custom_domain_status === 'active':
  canonical_domain = custom_domain
  301: slug.novavision.lat/* → custom_domain/*
ELSE:
  canonical_domain = slug.novavision.lat
  NO redirect

Canonical URL format:
  https://{canonical_domain}{pathname}
  
  Ejemplo:
  Page: /p/abc123/zapatillas-running-nike
  Canonical: https://modafit.com/p/abc123/zapatillas-running-nike
```

---

## 9. GA4 + Search Console — Diseño Operativo

### GA4 per tenant (recomendado)

**Motivo:** Cada tienda es un negocio independiente. El admin quiere ver SU tráfico, no datos agregados de NovaVision.

**Flujo:**
1. Admin configura `ga4_measurement_id` en SEO Settings
2. Frontend carga `gtag.js` dinámicamente solo si existe el ID
3. Enhanced e-commerce events se envían automáticamente:

| Evento | Trigger | Datos |
|--------|---------|-------|
| `page_view` | Cada navegación (router change) | title, path, canonical |
| `view_item` | PDP load | product_id, name, price, category |
| `view_item_list` | PLP load | items[], list_name |
| `add_to_cart` | Click "Agregar" | product_id, quantity, price |
| `remove_from_cart` | Click "Eliminar" | product_id, quantity |
| `begin_checkout` | Click "Finalizar compra" | items[], total |
| `purchase` | Redirect post-pago (status=approved) | transaction_id, revenue, items[] |

### GA4 global NovaVision (separado)

NovaVision puede tener su PROPIO GA4 para medir el uso de la plataforma:
- Total de pageviews agregado
- Tenants más activos
- Funnel de onboarding
- NO interfiere con el GA4 del tenant

### Search Console

**Flujo de verificación:**
1. Admin ingresa URL canónica de su tienda en GSC
2. GSC devuelve token de verificación (meta tag)
3. Admin pega el token en SEO Settings
4. Frontend inyecta `<meta name="google-site-verification" content="{token}" />`
5. Admin vuelve a GSC y confirma verificación

**Limitación:** Solo 1 propiedad por tenant (el canonical_domain). Si cambia de custom domain → re-verificar.

---

## 10. QA Checklist SEO Completo

### Pre-Launch (Fase 0)

| # | Check | Cómo verificar | Criterio de aceptación |
|---|-------|-----------------|------------------------|
| 1 | Custom domains resuelven correctamente | `curl -I https://mitienda.com` | 200 + HTML de la tienda correcta |
| 2 | Branch deploys tienen noindex | `curl -I https://branch--site.netlify.app` | Header `X-Robots-Tag: noindex` |
| 3 | Tiendas no publicadas tienen noindex | Visitar tienda con `published: false` | Meta o header noindex presente |
| 4 | `/sitemap.xml` NO retorna HTML | `curl -I https://tenant.novavision.lat/sitemap.xml` | Content-Type ≠ text/html |
| 5 | `/robots.txt` tiene Disallow para rutas privadas | `curl https://tenant.novavision.lat/robots.txt` | Contiene `Disallow: /admin-dashboard` |
| 6 | Canonical link presente | Inspeccionar `<head>` | `<link rel="canonical">` con URL correcta |
| 7 | 301 redirect subdomain → custom domain | `curl -I https://slug.novavision.lat` (si tiene custom domain) | 301 Location: https://custom.domain |
| 8 | Sin 301 loop | `curl -L --max-redirs 3 https://slug.novavision.lat` | Máximo 1 redirect |

### Post Fase 1 (Head dinámico)

| # | Check | Criterio |
|---|-------|----------|
| 9 | document.title cambia en cada página | Navegar Home → PLP → PDP → ver title diferente |
| 10 | OG tags se actualizan | Inspeccionar meta tags en cada página |
| 11 | Title incluye nombre de tienda (no "NovaVision") | No contiene la palabra "NovaVision" |
| 12 | rutas privadas tienen robots noindex | `/cart`, `/login` → meta robots noindex |
| 13 | SEO Settings CRUD funcional | Crear, leer, actualizar settings |
| 14 | Plan gating funciona | Starter NO puede acceder a `/seo/settings` PUT |

### Post Fase 2 (Discovery)

| # | Check | Criterio |
|---|-------|----------|
| 15 | Sitemap XML válido | Parsea sin errores, contiene URLs del tenant correcto |
| 16 | Sitemap no incluye productos inactivos | Producto borrado/inactivo no aparece |
| 17 | Sitemap canonical correcto | URLs en sitemap usan canonical_domain |
| 18 | robots.txt incluye Sitemap directive | Contiene `Sitemap: https://{canonical}/sitemap.xml` |
| 19 | URL `/p/:id` redirige a `/p/:id/:slug` | Status 301 |
| 20 | Cross-tenant isolation en sitemap | Sitemap de tenant A no contiene URLs de tenant B |

### Post Fase 3 (Rich Results)

| # | Check | Criterio |
|---|-------|----------|
| 21 | JSON-LD Product válido | Rich Results Test: 0 errores |
| 22 | JSON-LD NO emitido si faltan campos | Producto sin precio → no hay `<script type="application/ld+json">` |
| 23 | Organization schema presente en home | Incluye name, url, logo |
| 24 | BreadcrumbList correcto | Home → Categoría → Producto (3 niveles) |
| 25 | Precios en moneda correcta | ARS para Argentina |

### Post Fase 4 (Performance + Analytics)

| # | Check | Criterio |
|---|-------|----------|
| 26 | GA4 carga solo si configurado | Sin ga4_measurement_id → no carga gtag.js |
| 27 | E-commerce events correctos | view_item, add_to_cart, purchase con datos reales |
| 28 | Cache headers en assets | `/assets/*` → `immutable, max-age=31536000` |
| 29 | LCP image tiene fetchpriority | `<img fetchpriority="high">` en hero |
| 30 | Lighthouse SEO score > 90 | Correr audit en PDP |

### Seguridad Multi-tenant

| # | Check | Criterio |
|---|-------|----------|
| 31 | Edge meta injection: contenido coincide con SPA | Mismo title/description en HTML estático y post-render |
| 32 | Cache no leakea entre tenants | 2 requests a tenants diferentes → HTML diferente |
| 33 | seo_settings scoped por client_id | Admin A no puede leer/escribir settings de Admin B |
| 34 | force_noindex no editable por admin tenant | Solo super_admin puede setear force_noindex |
| 35 | sitemap regeneration rate limited | Endpoint no permite > 1 regeneración cada 5 minutos por tenant |

---

## 11. Entitlements por Plan + Override per-client (resumen)

### Matriz Plan (default)

```
┌──────────────────────┬─────────┬────────┬────────────┬────────────────────┐
│ Feature              │ Starter │ Growth │ Enterprise │ Feature ID         │
├──────────────────────┼─────────┼────────┼────────────┼────────────────────┤
│ noindex preview      │   ✅    │   ✅   │     ✅     │ (no gated — free)  │
│ robots.txt básico    │   ✅    │   ✅   │     ✅     │ (no gated — free)  │
│ Canonical links      │   ✅    │   ✅   │     ✅     │ (no gated — free)  │
│ 301 redirects auto   │   ✅    │   ✅   │     ✅     │ (no gated — free)  │
│ ─────────────────────┼─────────┼────────┼────────────┼────────────────────┤
│ Head dinámico        │   ❌    │   ✅   │     ✅     │ seo.settings       │
│ SEO Settings admin   │   ❌    │   ✅   │     ✅     │ seo.settings       │
│ Sitemap XML          │   ❌    │   ✅   │     ✅     │ seo.sitemap        │
│ robots.txt dinámico  │   ❌    │   ✅   │     ✅     │ seo.sitemap        │
│ Social previews (OG) │   ❌    │   ✅   │     ✅     │ seo.settings       │
│ GA4 per tenant       │   ❌    │   ✅   │     ✅     │ seo.analytics      │
│ Search Console       │   ❌    │   ✅   │     ✅     │ seo.analytics      │
│ Product slugs        │   ❌    │   ✅   │     ✅     │ seo.settings       │
│ ─────────────────────┼─────────┼────────┼────────────┼────────────────────┤
│ Meta por entidad     │   ❌    │   ❌   │     ✅     │ seo.entity_meta    │
│ JSON-LD schemas      │   ❌    │   ❌   │     ✅     │ seo.schema         │
│ URL redirects mgr    │   ❌    │   ❌   │     ✅     │ seo.redirects      │
│ SEO Score/auditor    │   ❌    │   ❌   │     ✅     │ seo.entity_meta    │
│ FAQ schema           │   ❌    │   ❌   │     ✅     │ seo.schema         │
│ Breadcrumbs schema   │   ❌    │   ❌   │     ✅     │ seo.schema         │
└──────────────────────┴─────────┴────────┴────────────┴────────────────────┘
```

### Override per-client (Super Admin)

**Cualquier celda ❌ puede convertirse en ✅ para un cliente específico** via `feature_overrides`.

```
Ejemplo: Cliente "ModaFit" (plan: starter)

clients.feature_overrides = {
  "seo.settings": true,      // ❌→✅ Puede editar site_title, OG, social previews
  "seo.sitemap": true,       // ❌→✅ Tiene sitemap XML
  "seo.analytics": true      // ❌→✅ Puede configurar GA4 + GSC
  // seo.entity_meta → null (usa plan default = ❌)
  // seo.schema → null (usa plan default = ❌)
  // seo.redirects → null (usa plan default = ❌)
}

Resultado efectivo para ModaFit:
┌──────────────────────┬─────────┬──────────┬──────────┐
│ Feature              │ Plan    │ Override │ Efectivo │
├──────────────────────┼─────────┼──────────┼──────────┤
│ SEO: Config general  │   ❌    │   ✅     │    ✅    │
│ SEO: Sitemap XML     │   ❌    │   ✅     │    ✅    │
│ SEO: GA4 + GSC       │   ❌    │   ✅     │    ✅    │
│ SEO: Meta por entidad│   ❌    │   —      │    ❌    │
│ SEO: JSON-LD         │   ❌    │   —      │    ❌    │
│ SEO: Redirects       │   ❌    │   —      │    ❌    │
└──────────────────────┴─────────┴──────────┴──────────┘
```

### Implementación: cero código nuevo

El sistema de overrides **ya está implementado** en:

| Componente | Archivo | Función |
|------------|---------|--------|
| Guard (backend) | `src/plans/guards/plan-access.guard.ts` | Evalúa override > plan default |
| Decorador | `src/plans/decorators/plan-feature.decorator.ts` | `@PlanFeature('seo.settings')` |
| Admin API | `PlansAdminController` | `PATCH /admin/plans/clients/:id/features` |
| Admin UI | `ClientDetails` → `useClientFeatureOverrides.js` | Toggle 3-estados por feature |
| Catálogo | `src/plans/featureCatalog.ts` | **← Solo agregar 6 entradas SEO** |
| Admin catálogo | `src/utils/featureCatalog.ts` | Se sincroniza via `GET /plans/catalog` |

**Lo único que se necesita hacer:**
1. Agregar 6 entradas SEO al `FEATURE_CATALOG` en el backend (ver sección 2.2)
2. Decorar los controllers SEO con `@PlanFeature('seo.*')`
3. **La UI del Super Admin detecta las features nuevas automáticamente** porque lee el catálogo via API

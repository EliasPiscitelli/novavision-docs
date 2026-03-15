# Auditoría SEO / Tracking / Growth — Full Stack por Tenant

**Fecha**: 2026-03-15
**Auditor**: Claude Opus 4.6 — 4 agentes paralelos + verificación SQL directa
**Repos**: API, Web, Admin, Migraciones SQL, BD en producción
**Estado**: COMPLETA

---

## 1. Resumen Ejecutivo

### El sistema de SEO técnico está bien implementado. Lo que falta es tracking de eventos, Meta Pixel, y guiado al usuario.

**Lo que funciona bien (VERIFICADO):**
- SEO técnico sólido: `seo_settings` por tenant con 15 campos, sitemap dinámico, robots.txt custom, canonical URLs, noindex flags, JSON-LD (5 schemas), OG tags completos
- SEO AI con guardrails: GPT-4o-mini con límites de chars, dedup de slugs, locks manuales, auditoría gratuita, sistema de créditos por ledger
- GA4/GTM injection per-tenant: Scripts inyectados en `<head>` si IDs están configurados
- Product SEO completo: 8 columnas SEO en products (meta_title, meta_description, slug, noindex, seo_source, seo_locked, seo_needs_refresh, seo_last_generated_at)

**Lo que falta o está roto (gaps críticos):**
- **Meta Pixel**: NO existe campo, NO se inyecta script, NO se envían eventos del buyer
- **Eventos ecommerce**: CERO eventos GA4 del lado del comprador (no hay add_to_cart, begin_checkout, purchase)
- **CTAs sin tracking**: WhatsApp, tel, mailto son `<a href>` planos — sin event tracking
- **Meta CAPI**: Solo envía Purchase/Subscribe a nivel **plataforma** (NV como negocio), NO por tenant
- **Health checks**: GA4/GTM IDs se guardan sin validación de formato ni test de conexión
- **Guiado al usuario**: No hay checklist, wizard, ni feedback de "qué te falta conectar"

### Tabla de estado por capa

| Capa | Estado | Confianza | Riesgo |
|------|--------|-----------|--------|
| SEO técnico (meta, canonical, sitemap, robots, JSON-LD) | SANO | Alta | Bajo |
| SEO contenido (AI, audit, locks, scoring) | FUNCIONAL | Alta | Bajo |
| SEO plan gating | CORRECTO | Alta | Bajo |
| Medición GA4/GTM (injection) | PARCIAL — scripts sí, eventos no | Media | **Alto** |
| Medición eventos ecommerce | **NO EXISTE** | N/A | **P0** |
| Meta Pixel / CAPI por tenant | **NO EXISTE** | N/A | **P0** |
| CTA tracking (WhatsApp, tel, email) | **NO EXISTE** | N/A | **P1** |
| KPIs por tenant (dashboard SEO) | **NO EXISTE** (solo revenue/orders) | N/A | **P1** |
| Search Console | PLACEHOLDER — token guardado, sin integración | Baja | **P1** |
| Google Ads | **NO EXISTE** | N/A | **P2** |
| UX/Guiado del panel | **INEXISTENTE** — inputs sueltos sin contexto | N/A | **P1** |

---

## 2. Mapa de Arquitectura Funcional

### Capa 1 — SEO Técnico (VERIFICADO - SANO)

| Componente | Datos | Storage | Consumidor | Estado |
|------------|-------|---------|------------|--------|
| `<title>` | `seo_settings.site_title` / `product.meta_title` | Backend DB `seo_settings` + `products` | SEOHead.jsx / ProductSEO.jsx | VERIFICADO |
| `<meta description>` | `seo_settings.site_description` / `product.meta_description` | Backend DB | SEOHead.jsx / ProductSEO.jsx | VERIFICADO |
| `<link canonical>` | Generado dinámicamente | Computed | SEOHead.jsx | VERIFICADO |
| `<meta robots>` | `product.noindex` flag | Backend DB `products.noindex` | ProductSEO.jsx / NoIndexMeta.jsx | VERIFICADO |
| robots.txt | `seo_settings.robots_txt` | Backend DB | GET /seo/sitemap.xml proxy | VERIFICADO |
| sitemap.xml | Generado desde products + categories activas | Backend DB query | GET /seo/sitemap.xml | VERIFICADO |
| OG tags | `seo_settings.og_image_default` + per-product | Backend DB | SEOHead.jsx | VERIFICADO |
| JSON-LD | Organization, WebSite, Product, Breadcrumb, ItemList | Computed from DB | JsonLd.jsx | VERIFICADO |
| favicon | `seo_settings.favicon_url` | Backend DB | SEOHead.jsx `<link rel="icon">` | VERIFICADO |
| Slugs | `products.slug`, `categories.slug` | Backend DB (UNIQUE per client) | Routing + canonical + sitemap | VERIFICADO |
| Redirects 301/302 | `seo_redirects` table | Backend DB | Edge function resolve | VERIFICADO (Enterprise) |

### Capa 2 — SEO Contenido / AI (VERIFICADO - FUNCIONAL)

| Componente | Datos | Storage | Consumidor | Estado |
|------------|-------|---------|------------|--------|
| AI generation | GPT-4o-mini, temp 0.3 | N/A (external API) | seo-ai-worker | VERIFICADO |
| Job tracking | `seo_ai_jobs` (status, progress, cost) | Backend DB | SeoAutopilotDashboard | VERIFICADO |
| Audit log | `seo_ai_log` (old/new values per field) | Backend DB | Job detail view | VERIFICADO |
| Credits ledger | `seo_ai_credits` (Admin DB) | Admin DB | Balance endpoint | VERIFICADO |
| Scoring/Audit | Missing titles/descriptions, too-long, duplicates | Computed | GET /seo-ai/audit | VERIFICADO |
| Manual locks | `products.seo_locked` boolean | Backend DB | AI worker skips locked | VERIFICADO |
| Source tracking | `products.seo_source` ('manual'/'ai'/'template') | Backend DB | Audit display | VERIFICADO |

### Capa 3 — Medición (PARCIAL)

| Componente | Datos | Storage | Consumidor | Estado |
|------------|-------|---------|------------|--------|
| GA4 script injection | `seo_settings.ga4_measurement_id` | Backend DB | SEOHead.jsx `<script>` | VERIFICADO |
| GTM script injection | `seo_settings.gtm_container_id` | Backend DB | SEOHead.jsx `<script>` | VERIFICADO |
| Search Console token | `seo_settings.search_console_token` | Backend DB | SEOHead.jsx `<meta>` | VERIFICADO (placeholder) |
| Ecommerce events (add_to_cart, purchase, etc.) | — | — | — | **NO EXISTE** |
| Page view tracking | — | — | Relies on GA4 auto-tracking | PARCIAL |
| CTA click events | — | — | — | **NO EXISTE** |
| Meta Pixel injection | — | — | — | **NO EXISTE** |
| Meta CAPI (tenant) | — | — | — | **NO EXISTE** (solo plataforma) |

### Capa 4 — Activación Comercial (NO IMPLEMENTADA)

| Componente | Estado |
|------------|--------|
| Meta Pixel per tenant | NO EXISTE — no hay campo ni injection |
| Meta CAPI per tenant | NO EXISTE — CAPI actual es para NV como negocio |
| Google Ads per tenant | NO EXISTE |
| Merchant Center | NO EXISTE |
| Domain verification | Solo Search Console token |
| Remarketing audiences | NO EXISTE |

---

## 3. Matriz Maestra de Datos e Integraciones

| Concepto | Campo/Input | Tabla.Columna | Source of Truth | Consumidor Final | Integración Externa | Estado |
|----------|-------------|---------------|-----------------|------------------|---------------------|--------|
| Site title | Input text (70ch) | seo_settings.site_title | Backend DB | `<title>` en SEOHead | Google SERP | VERIFICADO |
| Site description | Textarea (160ch) | seo_settings.site_description | Backend DB | `<meta description>` | Google SERP | VERIFICADO |
| Brand name | Input text (100ch) | seo_settings.brand_name | Backend DB | JSON-LD Organization, og:site_name | Social shares | VERIFICADO |
| OG image default | URL input | seo_settings.og_image_default | Backend DB | `<meta og:image>` | Facebook/Twitter | VERIFICADO |
| Favicon | URL input | seo_settings.favicon_url | Backend DB | `<link rel="icon">` | Browser tab | VERIFICADO |
| Product meta_title | Input (70ch) | products.meta_title | Backend DB | ProductSEO.jsx `<title>` | Google SERP | VERIFICADO |
| Product meta_description | Textarea (160ch) | products.meta_description | Backend DB | ProductSEO.jsx `<meta>` | Google SERP | VERIFICADO |
| Product slug | Input | products.slug | Backend DB | Canonical + sitemap + routing | Crawlers | VERIFICADO |
| Product noindex | Checkbox | products.noindex | Backend DB | `<meta robots noindex>` | Crawlers | VERIFICADO |
| GA4 ID | Input (20ch) | seo_settings.ga4_measurement_id | Backend DB | `<script gtag.js>` | Google Analytics | VERIFICADO — sin health check |
| GTM ID | Input (20ch) | seo_settings.gtm_container_id | Backend DB | `<script gtm.js>` | Google Tag Manager | VERIFICADO — sin health check |
| Search Console token | Input | seo_settings.search_console_token | Backend DB | `<meta google-site-verification>` | Google Search Console | VERIFICADO — placeholder |
| robots.txt | Textarea | seo_settings.robots_txt | Backend DB | /robots.txt proxy | Crawlers | VERIFICADO |
| Product URL pattern | Input | seo_settings.product_url_pattern | Backend DB | Sitemap + canonical generation | Crawlers | VERIFICADO |
| Meta Pixel ID | **NO EXISTE** | — | — | — | Meta Ads | **NO IMPLEMENTADO** |
| CAPI access token (tenant) | **NO EXISTE** | — | — | — | Meta Conversions API | **NO IMPLEMENTADO** |
| Google Ads ID | **NO EXISTE** | — | — | — | Google Ads | **NO IMPLEMENTADO** |

---

## 4. Matriz de Eventos y CTAs

| Evento/CTA | Dónde ocurre | Nombre técnico | Tenant-aware | Se persiste | Se envía a GA4 | Se envía a Meta | Dashboard | Estado |
|------------|-------------|----------------|:---:|:---:|:---:|:---:|:---:|--------|
| page_view | Todas las páginas | Auto (GA4 enhanced measurement) | Sí (si GA4 ID set) | No | Sí (auto) | No | No | PARCIAL |
| product_view / view_item | ProductPage | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| search | SearchPage | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| category_view | SearchPage (?category=) | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| add_to_cart | CartProvider.addItem | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| begin_checkout | CheckoutStepper mount | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| purchase | PaymentResultPage (approved) | — | — | Sí (orders table) | **NO** | **NO** | Sí (revenue) | **PARCIAL** (sin evento GA4) |
| WhatsApp click | Footer + ProductPage | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| Phone click | Footer | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| Email click | Footer | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| CTA hero banner | HomePage | — | — | — | **NO** | **NO** | — | **NO EXISTE** |
| Form submit | ContactPage (si existe) | — | — | — | **NO** | **NO** | — | **NO EXISTE** |

---

## 5. Matriz de KPIs por Tenant

| KPI | Definición Actual | Fuente | Cálculo | Vista | Por Tenant | Confiable | Gap |
|-----|-------------------|--------|---------|-------|:---:|:---:|-----|
| Órdenes totales | count(orders) | Backend DB | analytics.service | Admin dashboard | Sí | Sí | OK |
| Revenue | sum(orders.total_amount) | Backend DB | analytics.service | Admin dashboard | Sí | Sí | OK |
| Top products | orders × products join | Backend DB | analytics.service | Admin dashboard | Sí | Sí | OK |
| Payment methods | orders groupby method | Backend DB | analytics.service | Admin dashboard | Sí | Sí | OK |
| Sesiones | — | — | — | — | — | — | **NO EXISTE** (depende de GA4 del tenant) |
| Usuarios únicos | — | — | — | — | — | — | **NO EXISTE** |
| CTR orgánico | — | — | — | — | — | — | **NO EXISTE** (Search Console) |
| Páginas indexadas | — | — | — | — | — | — | **NO EXISTE** |
| Cobertura SEO catálogo | missing meta / total entities | Backend DB | /seo-ai/audit | API response | Sí | Sí | OK (free endpoint) |
| % con meta completa | count(meta_title IS NOT NULL) | Backend DB | /seo-ai/audit | API response | Sí | Sí | OK |
| add_to_cart rate | — | — | — | — | — | — | **NO EXISTE** |
| Checkout start rate | — | — | — | — | — | — | **NO EXISTE** |
| Conversion rate | — | — | — | — | — | — | **NO EXISTE** (sin sesiones no se puede calcular) |
| ROAS | — | — | — | — | — | — | **NO EXISTE** |
| Storage usado | client_usage.storage_bytes_used | Backend DB | usage-recorder | MetricsPanel | Sí | Sí | OK |

---

## 6. Lista de Inconsistencias y Problemas

### P0 — Críticos

| # | Problema | Impacto | Evidencia |
|---|---------|---------|-----------|
| 1 | **Cero eventos ecommerce GA4** — no hay view_item, add_to_cart, begin_checkout, purchase | Tenant con GA4 configurado no puede medir conversiones | ProductPage, CartPage, CheckoutStepper — sin gtag() calls |
| 2 | **Meta Pixel no existe** — no hay campo, no hay script, no hay evento | Tenants no pueden hacer remarketing con Meta Ads | Grep fbq/pixel en Web — 0 resultados |
| 3 | **Tablas SEO sin migración tracked** — seo_settings, seo_redirects, seo_ai_jobs, seo_ai_log existen en prod pero no en migrations/ | No reproducible en nuevo cluster | SELECT from information_schema confirma existencia |

### P1 — Importantes

| # | Problema | Impacto |
|---|---------|---------|
| 4 | **CTAs sin tracking** — WhatsApp, tel, mailto son links planos | No se puede medir engagement por canal |
| 5 | **GA4/GTM sin validación de formato** — se acepta cualquier string | Tenants pueden escribir IDs inválidos sin feedback |
| 6 | **Search Console es placeholder** — token se guarda y renderiza pero no hay verificación real ni importación de datos | Tenant cree que está "conectado" pero no recibe datos |
| 7 | **No hay checklist ni guiado** — usuario ve inputs sueltos sin saber qué hacer primero | Fricción alta, adopción baja |
| 8 | **Score SEO solo mide completitud** — no detecta problemas técnicos (render, crawlability, performance) | Score alto no implica SEO sano |
| 9 | **Meta CAPI a nivel plataforma** — solo mide Purchase/Subscribe de NV, no del tenant | Confusión conceptual si se muestra al tenant |
| 10 | **Legacy duplicación** — `identity_config.integrations.google_analytics` coexiste con `seo_settings.ga4_measurement_id` | Fuentes de verdad duplicadas |

### P2 — Deuda técnica

| # | Problema |
|---|---------|
| 11 | Google Ads conversion tracking no existe |
| 12 | Merchant Center integration no existe |
| 13 | No hay domain verification wizard |
| 14 | Sitemap no se auto-submitea a Search Console |
| 15 | No hay AB testing de meta titles |

---

## 7. Propuesta de Rediseño de Producto

### Arquitectura de módulos propuesta

```
┌─────────────────────────────────────────────────────────┐
│              VISIBILIDAD Y CRECIMIENTO                  │
│          (reemplaza el actual "SEO" suelto)             │
├─────────────┬──────────────┬──────────────┬─────────────┤
│  Contenido  │  Técnico     │  Medición    │  Campañas   │
│  SEO        │  SEO         │  y Eventos   │  y Ads      │
├─────────────┼──────────────┼──────────────┼─────────────┤
│ Meta titles │ Sitemap      │ GA4          │ Meta Pixel  │
│ Descriptions│ Robots.txt   │ GTM          │ Meta CAPI   │
│ AI generate │ Canonical    │ Eventos      │ Google Ads  │
│ Audit score │ Slugs        │ Conversiones │ Remarketing │
│ Locks       │ Redirects    │ CTAs         │ Audiences   │
│ Bulk edit   │ Indexación   │ Dashboards   │ ROAS        │
└─────────────┴──────────────┴──────────────┴─────────────┘

┌─────────────────────────────────────────────────────────┐
│           CHECKLIST DE ACTIVACIÓN                       │
│  (tarjetas con estado: Pendiente / Conectado / Error)   │
├─────────────────────────────────────────────────────────┤
│ □ Completá metadata de tu catálogo (12/300 productos)   │
│ ✓ Sitemap activo — 315 URLs                            │
│ □ Conectá Google Analytics → [Configurar]               │
│ □ Conectá Meta Pixel → [Configurar]                    │
│ ✓ Search Console verificado                            │
│ □ Activá eventos de compra → [Ver guía]                │
│ □ Revisá slugs duplicados (3 encontrados)              │
└─────────────────────────────────────────────────────────┘
```

### Centro de Conexiones — tarjetas con estado

Cada conexión debería tener:
- **Ícono + nombre** (Google Analytics, Meta Pixel, etc.)
- **Estado**: No configurado / Configurado / Error / Verificado
- **Valor actual**: "G-AB1234CDEF" (masked)
- **Qué hace**: "Mide visitas, conversiones y revenue de tu tienda"
- **Qué necesitás**: "Tu Measurement ID de GA4 (empieza con G-)"
- **Test de conexión**: Botón que verifica que el ID es válido
- **Siguiente paso**: "Ahora activá eventos de compra"

---

## 8. Plan de Implementación por Fases

### Phase 0 — Bugs y Riesgos Críticos

| Fix | Archivos | Complejidad | Riesgo |
|-----|---------|-------------|--------|
| **Agregar eventos ecommerce GA4** (view_item, add_to_cart, begin_checkout, purchase) | Web: ProductPage, CartProvider, CheckoutStepper, PaymentResultPage | Media | Bajo |
| **Agregar Meta Pixel field** a seo_settings + injection en SEOHead | API: seo.service, Web: SEOHead, Admin: SeoEditTab | Media | Bajo |
| **Crear migraciones tracked** para seo_settings, seo_redirects, seo_ai_jobs, seo_ai_log | migrations/backend/ | Baja | Bajo |

### Phase 1 — Modelo de Datos

| Fix | Archivos | Complejidad |
|-----|---------|-------------|
| Agregar `meta_pixel_id` a seo_settings | Migration SQL + seo.service.ts | Baja |
| Agregar validación de formato para GA4 (G-XXXXXXXXXX) y GTM (GTM-XXXXXXX) | Web: SeoEditTab | Baja |
| Eliminar legacy `identity_config.integrations.google_analytics` | API: identity-config.dto.ts | Baja |
| Agregar `seo_settings.meta_pixel_id` | Migration SQL | Baja |

### Phase 2 — Eventos y Tracking

| Fix | Archivos | Complejidad |
|-----|---------|-------------|
| Crear `useEcommerceTracking()` hook en Web | Nuevo hook | Media |
| Implementar view_item en ProductPage | ProductPage.jsx | Baja |
| Implementar add_to_cart en CartProvider | CartProvider.jsx | Baja |
| Implementar begin_checkout en CheckoutStepper | CheckoutStepper.jsx | Baja |
| Implementar purchase en PaymentResultPage | PaymentResultPage.jsx | Baja |
| Implementar CTA tracking (WhatsApp, tel, email) | Footer, ProductPage | Baja |
| Meta Pixel pageview + ViewContent + AddToCart + Purchase | SEOHead + hook | Media |

### Phase 3 — UX y Guiado

| Fix | Archivos | Complejidad |
|-----|---------|-------------|
| Checklist de activación SEO/Tracking | Nuevo componente admin | Media |
| Centro de Conexiones con estados | Nuevo componente admin | Alta |
| Health checks para GA4/GTM/Pixel | Nuevo endpoint API | Media |
| Wizard de configuración paso a paso | Nuevo flujo admin | Alta |

### Phase 4 — Integraciones Avanzadas

| Fix | Archivos | Complejidad |
|-----|---------|-------------|
| Meta CAPI per tenant (server-side events) | meta-capi.service.ts refactor | Alta |
| Search Console API integration | Nuevo módulo API | Alta |
| Google Ads conversion tracking | Nuevo campo + injection | Media |
| Merchant Center product feed | Nuevo endpoint | Alta |

---

## Fuentes

### Código Verificado
- `apps/web/src/components/SEOHead/index.jsx` — Meta tags, GA4/GTM injection, canonical
- `apps/web/src/components/SEOHead/ProductSEO.jsx` — Product meta, noindex, OG
- `apps/web/src/components/SEOHead/SearchSEO.jsx` — Search/category meta, noindex logic
- `apps/web/src/components/SEOHead/JsonLd.jsx` — 5 structured data schemas
- `apps/web/src/components/SEOHead/NoIndexMeta.jsx` — noindex for auth/checkout/admin
- `apps/api/src/seo/seo.service.ts` — CRUD, sitemap, OG, redirects
- `apps/api/src/seo-ai/seo-ai-worker.service.ts` — AI generation pipeline
- `apps/api/src/seo-ai/seo-ai-job.service.ts` — Job lifecycle, credits
- `apps/api/src/meta-capi/meta-capi.service.ts` — Platform-level CAPI (no tenant)
- `apps/admin/src/pages/AdminDashboard/SeoView.jsx` — Admin SEO panel (1022 lines)

### Base de Datos (producción verificada)
- `seo_settings` — 15 columnas (site_title, ga4, gtm, robots, etc.)
- `seo_redirects` — 9 columnas (from_path, to_url, hit_count)
- `seo_ai_jobs` — 16 columnas (job lifecycle)
- `seo_ai_log` — 10 columnas (audit trail)
- `products` — 8 columnas SEO (meta_title, slug, noindex, seo_locked, etc.)

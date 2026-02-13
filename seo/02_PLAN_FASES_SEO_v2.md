# Plan de Fases SEO — NovaVision (v2 reordenado)

**Fecha:** 2026-02-12 (rev. v2)  
**Autor:** Agente Copilot  
**Revisión:** Reordenado según feedback TL: seguridad primero → producto → discovery → rich results → performance. Noindex es higiene global, no upsell.

---

## Índice
1. [Principios de Diseño del Roadmap](#principios-de-diseño-del-roadmap)
2. [Fase 0 — Higiene e Integridad (Global, gratis, obligatorio)](#fase-0--higiene-e-integridad)
3. [Fase 1 — SEO Producto (Growth/Enterprise)](#fase-1--seo-producto)
4. [Fase 2 — Discovery e Infraestructura (Growth/Enterprise)](#fase-2--discovery-e-infraestructura)
5. [Fase 3 — Rich Results + Schema (Enterprise)](#fase-3--rich-results--schema)
6. [Fase 4 — Performance, CWV y Reporting](#fase-4--performance-cwv-y-reporting)
7. [QA Automatizado (transversal)](#qa-automatizado-transversal)
8. [Cronograma Consolidado](#cronograma-consolidado)
9. [Riesgos Cruzados del Roadmap](#riesgos-cruzados-del-roadmap)

---

## Principios de Diseño del Roadmap

### Lo que cambió respecto a v1

| v1 (incorrecto) | v2 (corregido) | Motivo |
|------------------|-----------------|--------|
| "noindex para preview" era Growth+ | **noindex es GLOBAL, gratuito** | Es higiene básica, no upsell — indexar previews es un bug |
| SSR/prerender era Fase 1 | **SSR descartado** — Helmet + edge solo para social crawlers | Google renderiza JS; el problema real es descubrimiento + head dinámico |
| Sitemap runtime en Fase 1 | **Sitemap cached/incremental en Fase 2** | Runtime = riesgo DDoS; necesita invalidación por evento |
| Structured data era Fase 2 | **Fase 3 con validación estricta** | No emitir JSON-LD si faltan campos (precio/stock/img) — schema.org invalid es peor que nada |
| URL migration no mencionada | **URL `/p/:id/:slug` en Fase 2** | `/p/:id` funciona para Google pero pierde señal semántica en SERP |

### Criterio de ordenamiento

```
Fase 0: ¿Puede causar daño hoy? → Arreglar ya (higiene)
Fase 1: ¿Podemos vender esto? → Funcionalidad admin SEO (producto)
Fase 2: ¿Google puede descubrirnos? → Infraestructura de descubrimiento
Fase 3: ¿Google nos muestra bonito? → Rich results
Fase 4: ¿Somos rápidos y medibles? → Performance + analytics
```

---

## Fase 0 — Higiene e Integridad

**Scope:** Todo el sistema. Todos los planes. No es feature — es corrección de bugs e higiene.  
**Duración estimada:** 1-2 sprints  
**PRs estimados:** 4-6

### PR 0.1 — Fix custom domains en frontend

**Cambios:**
- `tenantResolver.js` → soporte para hostnames sin subdominio (2 partes)
- `tenantScope.js` → cuando no se puede resolver por subdomain, pasar el hostname completo como fallback
- `TenantProvider.jsx` → antes de abortar con `NO_SLUG`, intentar resolución via API con `x-forwarded-host: <hostname>`
- `axiosConfig.jsx` → enviar `x-forwarded-host: window.location.hostname` en TODOS los requests si no se pudo resolver slug localmente
- Alternativa: Netlify edge function que lee el Host y lo mapea a slug (evita roundtrip al backend)

**DoD:**
- [ ] `mitienda.com` carga la tienda correcta
- [ ] `mitienda.novavision.lat` sigue funcionando
- [ ] Error handling para custom domain no registrado (403 o redirect a NovaVision)
- [ ] Test manual con al menos 1 custom domain real

**Riesgos:**
- Si no hay custom domain real configurado en Netlify, no se puede testear end-to-end
- DNS propagation delays

### PR 0.2 — Control de indexación (global)

**robots.txt dinámico (edge function o pre-build):**
```
User-agent: *
Disallow: /admin-dashboard
Disallow: /cart
Disallow: /profile
Disallow: /login
Disallow: /register
Disallow: /complete

Sitemap: https://{hostname}/sitemap.xml
```

**[context.deploy-preview] + [context.branch-deploy] en `netlify.toml`:**
```toml
[context.deploy-preview.environment]
  VITE_NOINDEX = "true"

[context.deploy-preview]
  [[context.deploy-preview.headers]]
    for = "/*"
    [context.deploy-preview.headers.values]
      X-Robots-Tag = "noindex, nofollow"

[context.branch-deploy]
  [[context.branch-deploy.headers]]
    for = "/*"
    [context.branch-deploy.headers.values]
      X-Robots-Tag = "noindex, nofollow"
```

**Onboarding preview:** Tiendas no publicadas (`published: false`) deben tener `noindex` vía meta tag o header en la respuesta de bootstrap.

**DoD:**
- [ ] Branch deploys retornan `X-Robots-Tag: noindex, nofollow`
- [ ] `/robots.txt` incluye Disallow para rutas privadas
- [ ] `/sitemap.xml` retorna 404 o vacío (no `index.html`) → resuelto con `_redirects` override:
  ```
  /sitemap.xml   /404.html   404
  /robots.txt    /robots.txt 200
  /*             /index.html 200
  ```
- [ ] Tiendas con `published: false` sirven noindex

### PR 0.3 — Canonical policy

**Decisión:** Custom domain es el dominio canónico (opción recomendada).

**Implementación:**
1. `nv_accounts` ya tiene `custom_domain` → la API de bootstrap lo incluye en la respuesta
2. Frontend (vía Helmet en Fase 1, o meta tag inyectado): `<link rel="canonical" href="https://{canonical_domain}/{path}" />`
3. Redirect 301 del dominio secundario al primario:
   - Si tenant tiene custom domain → `slug.novavision.lat/*` → 301 a `custom.domain/*`
   - Si tenant NO tiene custom domain → `slug.novavision.lat` es canónico, sin redirect
4. Implementar via Netlify edge function (lee bootstrap, decide redirect)

**Riesgos:**
- 301 loop si la lógica de detección falla
- Redirect debe excluir API calls, assets, webhooks

**DoD:**
- [ ] `slug.novavision.lat/p/123` retorna 301 a `mitienda.com/p/123` (si tiene custom domain)
- [ ] `mitienda.com/p/123` tiene `<link rel="canonical" href="https://mitienda.com/p/123">`
- [ ] Sin redirect loops

### PR 0.4 — Fix `/sitemap.xml` y 404 handling

**`_redirects` actualizado (orden importa en Netlify):**
```
/robots.txt    /robots.txt    200
/sitemap.xml   /404.html      404
/*             /index.html    200
```

Esto evita que `/sitemap.xml` retorne la SPA como HTML.

Alternativa: crear `public/sitemap.xml` vacío:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
</urlset>
```

---

## Fase 1 — SEO Producto

**Scope:** Growth y Enterprise **por plan**, o **cualquier cliente activado por override** desde el Super Admin.  
**Modelo de activación dual:** Features SEO se habilitan por plan (default) O por override per-client (Super Admin). El sistema existente de `feature_overrides` + `PlanAccessGuard` ya lo soporta — solo se agregan entradas al catálogo.  
**Duración estimada:** 2-3 sprints  
**PRs estimados:** 5-7

### PR 1.1 — Head dinámico con react-helmet-async

**Dependencia:** Ninguna (se puede hacer sin esperar Fase 0)

**Scope:**
- Instalar `react-helmet-async` en `apps/web`
- Crear `<SEOHead>` component que recibe `title`, `description`, `canonical`, `og_*`, `robots`
- Integrar en:
  - **Home** → título de la tienda + descripción del negocio
  - **PLP (Search)** → "Categoría X | NombreTienda"
  - **PDP (Producto)** → "Producto Y | NombreTienda" + OG con imagen del producto
  - **404** → title "Página no encontrada"
- Datos vienen de `tenant_bootstrap` (tienda) y endpoint de producto (PDP)

**DoD:**
- [ ] `document.title` cambia en cada página
- [ ] OG tags se actualizan en cada navegación (verificar con React DevTools)
- [ ] Canonical dinámico incluye canonical_domain + path
- [ ] noindex en página de login, carrito, perfil (via Helmet meta)

### PR 1.2 — Data model SEO en backend

**Tabla nueva: `seo_settings` (en Multicliente DB):**

```sql
CREATE TABLE seo_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL REFERENCES clients(id),
  
  -- Global (tienda)
  site_title TEXT,              -- "Mi Tienda Online"
  site_description TEXT,         -- "Los mejores productos de..."
  brand_name TEXT,               -- "MiMarca" (para BreadcrumbList, schema)
  og_image_default TEXT,         -- URL imagen default para OG
  favicon_url TEXT,
  
  -- Social / Search Console
  ga4_measurement_id TEXT,       -- "G-XXXXXXXXXX"
  gtm_container_id TEXT,         -- "GTM-XXXXXXX"
  search_console_token TEXT,     -- para verificación DNS/meta
  
  -- Slugs config
  product_url_pattern TEXT DEFAULT '/p/:id/:slug',  -- futuro
  
  -- JSON override (para extensibilidad)
  custom_meta JSONB DEFAULT '{}',
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  UNIQUE(client_id)
);

-- RLS
ALTER TABLE seo_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY "seo_settings_select_tenant" ON seo_settings
FOR SELECT USING (client_id = current_client_id());

CREATE POLICY "seo_settings_write_admin" ON seo_settings
FOR ALL USING (client_id = current_client_id() AND is_admin())
WITH CHECK (client_id = current_client_id() AND is_admin());

CREATE POLICY "server_bypass" ON seo_settings
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

**Campos por entidad (en tablas existentes):**

```sql
-- products
ALTER TABLE products ADD COLUMN IF NOT EXISTS slug TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS meta_title TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS meta_description TEXT;
ALTER TABLE products ADD COLUMN IF NOT EXISTS noindex BOOLEAN DEFAULT false;

-- categories
ALTER TABLE categories ADD COLUMN IF NOT EXISTS meta_title TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS meta_description TEXT;
ALTER TABLE categories ADD COLUMN IF NOT EXISTS noindex BOOLEAN DEFAULT false;

-- Índices
CREATE INDEX IF NOT EXISTS idx_products_slug ON products(client_id, slug);
```

**Generación automática de slug:**
- Al crear/actualizar producto: `slugify(product.name)` → guardar en `slug`
- Collision handling: `slug-1`, `slug-2` (scoped por `client_id`)

**Endpoint nuevo:**
- `GET /seo/settings` → devuelve `seo_settings` del tenant (público, cacheado 5min)
- `PUT /seo/settings` → actualiza (admin)
- `GET /seo/meta/:entity/:id` → devuelve meta para una entidad específica (producto, categoría)

**Feature catalog entries (activación dual plan + override):**

Como parte de esta PR, se agregan 6 entradas al `FEATURE_CATALOG` en `apps/api/src/plans/featureCatalog.ts`:

| Feature ID | Starter | Growth | Enterprise | Descripción |
|---|---|---|---|---|
| `seo.settings` | ❌ | ✅ | ✅ | CRUD de `seo_settings` |
| `seo.entity_meta` | ❌ | ✅ | ✅ | Meta title/desc por producto/categoría |
| `seo.sitemap` | ❌ | ✅ | ✅ | Sitemap XML generado |
| `seo.schema` | ❌ | ❌ | ✅ | JSON-LD structured data |
| `seo.analytics` | ❌ | ✅ | ✅ | GA4/GTM tag injection |
| `seo.redirects` | ❌ | ❌ | ✅ | 301 redirect manager |

El Super Admin puede activar cualquiera de estas features individualmente por cliente
vía el sistema de `feature_overrides` existente (UI ya disponible en `ClientDetails`).
**Cero código nuevo para la UI de overrides.**

**DoD:**
- [ ] Migración aplicada
- [ ] CRUD funcional
- [ ] Bootstrap incluye `seo_settings` en payload (o endpoint separado)
- [ ] Slug generado automáticamente para productos existentes (backfill migration)
- [ ] 6 entradas SEO en `FEATURE_CATALOG` + decoradores `@PlanFeature('seo.*')` en controllers
- [ ] Overrides visibles y funcionales desde Super Admin > ClientDetails

### PR 1.3 — Admin UI para SEO settings

**En Admin Dashboard del tenant** (no Super Admin):
- Sección "SEO" con tabs: General / Producto / Categorías / Analytics
- **General:** site_title, site_description, brand_name, og_image_default
- **Por producto (en vista de edición de producto):** meta_title, meta_description, preview OG
- **Analytics:** GA4 measurement ID, GTM container ID
- **Preview:** Vista previa de cómo se ve en Google (snippet preview)

**DoD:**
- [ ] Admin puede editar SEO de su tienda
- [ ] Preview SERP funcional
- [ ] Validaciones (max length title: 60, description: 160)

### PR 1.4 — Social crawlers (edge function para OG)

**Contexto del riesgo:** Los bots de Facebook, Twitter, WhatsApp NO ejecutan JS. Si no hacemos nada, comparten "NovaVision | Tiendas Online" con imagen genérica.

**Edge function `seo-meta-injector`:**
1. Detecta User-Agent de social crawlers (FB, Twitter, WhatsApp, Telegram, LinkedIn)
2. Para esos bots: fetch a `/seo/meta/:entity/:id` → inyecta OG/Twitter meta en `<head>` del HTML
3. Para usuarios normales: passthrough (SPA normal con Helmet)

**Seguridad:**
- **Este NO es cloaking** si y solo si los meta tags inyectados coinciden con lo que la SPA renderiza
- Cache: **DEBE** variar por `Host` + `pathname` + `user-agent-category` (bot vs human)
- TTL: 5 minutos (consistente con API cache)
- **Si la API devuelve error → passthrough sin inyección** (fail open, no romper la página)

**DoD:**
- [ ] Link de producto compartido en WhatsApp muestra: imagen, título, precio
- [ ] Link compartido en Facebook muestra OG image + title correctos
- [ ] Verificar con Facebook Sharing Debugger
- [ ] Cache no leakea entre tenants (test: 2 tenants diferentes)

---

## Fase 2 — Discovery e Infraestructura

**Scope:** Growth y Enterprise (o clientes con override `seo.sitemap` / `seo.analytics` activado). Infraestructura para que Google descubra las tiendas.  
**Duración estimada:** 2 sprints  
**PRs estimados:** 4-5

### PR 2.1 — Sitemap XML por tenant

**Arquitectura (cached, NO runtime):**
```
            ┌─────────────────────────────────────────┐
            │  Supabase: seo_sitemaps table            │
            │  (client_id, xml_content, generated_at)  │
            └─────────────────┬───────────────────────┘
                              │ generado por:
                              │
  ┌───────────────────────────┴────────────────────────┐
  │  Event triggers:                                    │
  │  - product.created/updated/deleted → regenerar     │
  │  - category.created/updated/deleted → regenerar    │
  │  - bulk import → regenerar (debounced)             │
  │  - cron: regenerar todos los sitemaps cada 24h     │
  └────────────────────────────────────────────────────┘
                              │
  ┌───────────────────────────┴────────────────────────┐
  │  GET /sitemap.xml (Netlify edge fn o API endpoint)  │
  │  1. Lee x-tenant-slug (o Host)                     │
  │  2. Fetch seo_sitemaps WHERE client_id = X          │
  │  3. Si existe y < 24h → servir XML                 │
  │  4. Si no → servir sitemap vacío (no romper)       │
  │  5. Headers: Content-Type: application/xml          │
  │             Cache-Control: public, max-age=3600    │
  └────────────────────────────────────────────────────┘
```

**Por qué NO runtime:**
- Un bot malicioso puede hacer 10,000 requests/s a `/sitemap.xml`
- Si cada request consulta la DB y genera XML → DDoS
- Con sitemap pre-generado y stored: el edge solo sirve un blob → CDN cachea

**Formato del sitemap:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"
        xmlns:image="http://www.google.com/schemas/sitemap-image/1.1">
  <url>
    <loc>https://{canonical_domain}/</loc>
    <changefreq>daily</changefreq>
    <priority>1.0</priority>
  </url>
  <url>
    <loc>https://{canonical_domain}/p/{id}/{slug}</loc>
    <lastmod>{product.updated_at}</lastmod>
    <changefreq>weekly</changefreq>
    <priority>0.8</priority>
    <image:image>
      <image:loc>{product.image_url}</image:loc>
      <image:title>{product.name}</image:title>
    </image:image>
  </url>
  <!-- solo productos con noindex: false y active: true -->
</urlset>
```

**Paginación:** Si tienda tiene > 50,000 URLs → Sitemap Index con sub-sitemaps.

**DoD:**
- [ ] `/sitemap.xml` retorna XML válido con URLs del tenant
- [ ] Incluye solo productos activos y no-noindex
- [ ] canonical_domain correcto (custom domain o subdominio)
- [ ] `lastmod` refleja última actualización real
- [ ] Stress test: 100 requests/s → responde < 50ms (desde cache)
- [ ] `robots.txt` incluye `Sitemap: https://{canonical}/sitemap.xml`

### PR 2.2 — robots.txt dinámico por tenant

**Edge function o API que sirve robots.txt personalizado:**
```
User-agent: *
Disallow: /admin-dashboard
Disallow: /cart
Disallow: /profile
Disallow: /login
Disallow: /register
Disallow: /complete

Sitemap: https://{canonical_domain}/sitemap.xml
```

**`_redirects` update:**
```
/robots.txt    /.netlify/edge-functions/seo-robots  200
/sitemap.xml   /.netlify/edge-functions/seo-sitemap 200
/*             /index.html                          200
```

O servir via API: `/robots.txt` → edge function → proxy a API `/seo/robots`.

**DoD:**
- [ ] `/robots.txt` incluye `Sitemap:` con domain canónico del tenant
- [ ] Rutas privadas bloqueadas
- [ ] Tiendas no publicadas tienen `Disallow: /` (bloquea todo)

### PR 2.3 — URL migration: `/p/:id` → `/p/:id/:slug`

**Estrategia:**
1. Agregar ruta `/p/:id/:slug` que coexiste con `/p/:id`
2. `/p/:id` sin slug → 301 redirect a `/p/:id/:slug` (server-side o edge)
3. Todos los links internos usan nuevo formato
4. Sitemap usa nuevo formato

**Riesgos:**
- Links compartidos viejos (`/p/123`) siguen funcionando vía 301
- Google descubre el nuevo formato gradualmente

**DoD:**
- [ ] `/p/123` redirige a `/p/123/zapatillas-running-nike`
- [ ] Todos los `<Link>` internos usan `/p/:id/:slug`
- [ ] Sitemap usa formato nuevo
- [ ] 301 status code (no 302)

### PR 2.4 — Search Console verification per tenant

**Opciones de verificación:**
1. **Meta tag** (más simple): `<meta name="google-site-verification" content="{token}" />`
   - Token guardado en `seo_settings.search_console_token`
   - Helmet lo inyecta
2. **DNS TXT record** → requiere acceso al DNS del tenant

**Admin UI:**
- Campo para pegar el token de verificación
- Instrucciones paso a paso para registrar en GSC

**DoD:**
- [ ] Admin puede agregar token de verificación
- [ ] Meta tag aparece en <head>
- [ ] Instrucciones claras en admin

---

## Fase 3 — Rich Results + Schema

**Scope:** Enterprise (o clientes con override `seo.schema` activado). Structured data para rich snippets.  
**Duración estimada:** 2 sprints  
**PRs estimados:** 3-4

### PR 3.1 — JSON-LD: Product + Organization + Website

**Regla de oro:** No emitir JSON-LD si faltan campos required.

```javascript
// ❌ NUNCA: emitir sin price
{ "@type": "Product", "name": "Zapatillas", "offers": { "price": undefined } }

// ✅ CORRECTO: validar antes de emitir
const canEmitProduct = product.price > 0 && product.name && product.imageUrl;
if (canEmitProduct) {
  return <script type="application/ld+json">{jsonld}</script>;
}
// Si no puede → no emitir nada (es mejor que schema inválido)
```

**Product schema (cuando es válido):**
```json
{
  "@context": "https://schema.org",
  "@type": "Product",
  "name": "Zapatillas Running Nike",
  "description": "Las mejores zapatillas...",
  "image": ["https://storage.../product.webp"],
  "sku": "ZAP-001",
  "brand": {
    "@type": "Brand",
    "name": "{brand_name || site_title}"
  },
  "offers": {
    "@type": "Offer",
    "url": "https://{canonical}/p/123/zapatillas-running-nike",
    "priceCurrency": "ARS",
    "price": "15999",
    "availability": "https://schema.org/InStock",
    "seller": {
      "@type": "Organization",
      "name": "{brand_name}"
    }
  }
}
```

**Organization (en homepage):**
```json
{
  "@context": "https://schema.org",
  "@type": "Organization",
  "name": "{brand_name}",
  "url": "https://{canonical_domain}",
  "logo": "{logo_url}",
  "sameAs": ["{instagram}", "{facebook}", "{tiktok}"]
}
```

**DoD:**
- [ ] Rich Results Test de Google: sin errores ni warnings
- [ ] JSON-LD NO se emite si faltan campos obligatorios
- [ ] Precios en moneda correcta (ARS/USD según tenant)

### PR 3.2 — BreadcrumbList + FAQ schema

**Breadcrumbs:**
```
Home > Categoría > Producto
```

**FAQ schema (si tienda tiene FAQs):**
- Ya existe tabla `faqs` en Multicliente
- Emitir FAQPage schema solo si hay FAQs activas

**DoD:**
- [ ] Breadcrumbs visibles en la UI Y en JSON-LD
- [ ] FAQ schema solo cuando hay data real

---

## Fase 4 — Performance, CWV y Reporting

**Scope:** Todos los planes (performance es core). Analytics es Growth/Enterprise.  
**Duración estimada:** 2 sprints  
**PRs estimados:** 4-6

### PR 4.1 — GA4 per tenant

**Decisión de arquitectura:** GA4 per tenant (no global NovaVision).

**Motivo:**
- Cada tienda es un negocio independiente
- El admin del tenant quiere ver SU analytics, no datos agregados
- NovaVision puede tener su PROPIO GA4 global (separado) para producto

**Implementación:**
```javascript
// En App.jsx o SEOHead component
const { seoSettings } = useTenantConfig();

useEffect(() => {
  if (seoSettings?.ga4_measurement_id) {
    // Inyectar gtag.js dinámicamente
    loadGA4(seoSettings.ga4_measurement_id);
  }
}, [seoSettings]);
```

**E-commerce events (enhanced):**
- `view_item` (PDP)
- `view_item_list` (PLP)
- `add_to_cart`
- `begin_checkout`
- `purchase` (post-pago)

**DoD:**
- [ ] GA4 carga solo si el tenant lo configuró
- [ ] Eventos e-commerce enviados correctamente
- [ ] No afecta performance si no hay GA4 configurado (no carga el script)

### PR 4.2 — Cache headers

```toml
# netlify.toml
[[headers]]
  for = "/assets/*"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[headers]]
  for = "/*.js"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"

[[headers]]
  for = "/*.css"
  [headers.values]
    Cache-Control = "public, max-age=31536000, immutable"
```

**Nota:** Los assets de Vite ya tienen hash en el nombre → `immutable` es seguro.

### PR 4.3 — Image optimization (CWV)

- `loading="lazy"` en todas las imágenes below fold
- `fetchpriority="high"` en LCP image (hero/producto principal)
- `sizes` attribute en `<img>` con breakpoints reales
- Preload de fuentes: `<link rel="preload" as="font" crossorigin>`

### PR 4.4 — Manifest PWA per tenant

```javascript
// Edge function o script inline que genera manifest dinámico
{
  "name": "{site_title}",
  "short_name": "{brand_name}",
  "start_url": "/",
  "display": "standalone",
  "theme_color": "{theme.primary}",
  "background_color": "{theme.background}",
  "icons": [
    { "src": "{logo_192}", "sizes": "192x192", "type": "image/png" },
    { "src": "{logo_512}", "sizes": "512x512", "type": "image/png" }
  ]
}
```

---

## QA Automatizado (transversal)

### Tests Playwright en CI (e2e repo)

```typescript
// tests/seo/meta-tags.spec.ts
test.describe('SEO Meta Tags', () => {
  test('homepage has tenant-specific title', async ({ page }) => {
    await page.goto(`https://${TENANT_SLUG}.novavision.lat`);
    const title = await page.title();
    expect(title).not.toContain('NovaVision');
    expect(title).toContain(EXPECTED_STORE_NAME);
  });

  test('product page has OG meta', async ({ page }) => {
    await page.goto(`https://${TENANT_SLUG}.novavision.lat/p/${PRODUCT_ID}`);
    const ogTitle = await page.$eval('meta[property="og:title"]', el => el.content);
    expect(ogTitle).toContain(EXPECTED_PRODUCT_NAME);
  });

  test('canonical points to correct domain', async ({ page }) => {
    await page.goto(`https://${TENANT_SLUG}.novavision.lat/p/${PRODUCT_ID}`);
    const canonical = await page.$eval('link[rel="canonical"]', el => el.href);
    expect(canonical).toMatch(/^https:\/\/(custom\.domain|slug\.novavision\.lat)/);
  });

  test('private routes have noindex', async ({ page }) => {
    for (const route of ['/cart', '/profile', '/admin-dashboard', '/login']) {
      await page.goto(`https://${TENANT_SLUG}.novavision.lat${route}`);
      const robots = await page.$eval('meta[name="robots"]', el => el.content).catch(() => null);
      expect(robots).toContain('noindex');
    }
  });

  test('/sitemap.xml returns valid XML', async ({ request }) => {
    const resp = await request.get(`https://${TENANT_SLUG}.novavision.lat/sitemap.xml`);
    expect(resp.headers()['content-type']).toContain('xml');
    expect(resp.status()).toBe(200);
    const body = await resp.text();
    expect(body).toContain('<urlset');
    expect(body).not.toContain('<html');
  });

  test('/robots.txt has Sitemap directive', async ({ request }) => {
    const resp = await request.get(`https://${TENANT_SLUG}.novavision.lat/robots.txt`);
    const body = await resp.text();
    expect(body).toContain('Sitemap:');
    expect(body).toContain('Disallow: /admin-dashboard');
  });
});
```

### Tests de Schema Validation

```typescript
// tests/seo/structured-data.spec.ts
test('product page has valid Product schema', async ({ page }) => {
  await page.goto(`https://${TENANT_SLUG}.novavision.lat/p/${PRODUCT_ID}`);
  const jsonld = await page.$$eval('script[type="application/ld+json"]', scripts =>
    scripts.map(s => JSON.parse(s.textContent))
  );
  const productSchema = jsonld.find(s => s['@type'] === 'Product');
  
  if (productSchema) {
    expect(productSchema.name).toBeTruthy();
    expect(productSchema.offers.price).toBeTruthy();
    expect(parseFloat(productSchema.offers.price)).toBeGreaterThan(0);
    expect(productSchema.image).toBeTruthy();
  }
  // Si no hay schema, no es error — puede ser producto sin price
});
```

### Tests de Cross-Tenant Isolation

```typescript
test('cache does not leak between tenants', async ({ request }) => {
  const resp1 = await request.get(`https://tenant-a.novavision.lat/sitemap.xml`);
  const resp2 = await request.get(`https://tenant-b.novavision.lat/sitemap.xml`);
  
  const body1 = await resp1.text();
  const body2 = await resp2.text();
  
  // Sitemap de tenant A NO debe contener URLs de tenant B
  expect(body1).not.toContain('tenant-b');
  expect(body2).not.toContain('tenant-a');
});
```

---

## Cronograma Consolidado

```
Sprint 1-2:  ┌─ Fase 0: Higiene (custom domains, noindex, canonical, sitemap fix)
             │  PR 0.1: Fix custom domains
             │  PR 0.2: Control indexación
             │  PR 0.3: Canonical policy
             └  PR 0.4: Fix sitemap.xml

Sprint 3-5:  ┌─ Fase 1: SEO Producto (Growth/Enterprise)
             │  PR 1.1: react-helmet-async
             │  PR 1.2: Data model + API
             │  PR 1.3: Admin UI
             └  PR 1.4: Edge fn social crawlers

Sprint 6-7:  ┌─ Fase 2: Discovery (Growth/Enterprise)
             │  PR 2.1: Sitemap cached
             │  PR 2.2: robots.txt dinámico
             │  PR 2.3: URL migration
             └  PR 2.4: Search Console

Sprint 8-9:  ┌─ Fase 3: Rich Results (Enterprise)
             │  PR 3.1: JSON-LD Product/Org
             └  PR 3.2: Breadcrumbs + FAQ

Sprint 10-11: ┌─ Fase 4: Performance + Analytics
              │  PR 4.1: GA4 per tenant
              │  PR 4.2: Cache headers
              │  PR 4.3: Image CWV
              └  PR 4.4: Manifest PWA

Transversal:  QA Tests (se agregan con cada Fase)
```

---

## Riesgos Cruzados del Roadmap

| Riesgo | Mitigación |
|--------|-----------|
| Edge function de meta injection → cloaking | Solo inyectar meta tags que coinciden con lo que la SPA renderiza; Google NO recibe HTML diferente |
| Cache multi-tenant → cross-tenant leak | Cache key: `Host + pathname`; purge on deploy; test de isolación en CI |
| Sitemap runtime → DDoS | Sitemap pre-generado y cacheado; regeneración por eventos; rate limit |
| URL migration `/p/:id` → `/p/:id/:slug` → links rotos | 301 redirect permanente de formato viejo a nuevo |
| JSON-LD con datos incompletos → schema inválido | Validar campos required ANTES de emitir; si falta algo → no emitir |
| robots.txt dinámico → 500 error bloquea crawler | Fallback a robots.txt estático genérico si la función falla |
| GA4 script → impacto en LCP | Cargar GA4 con `async` + defer; medir impacto CWV antes/después |
| Custom domain 301 loops | Edge function check: si ya estoy en canonical domain → no redirect; max redirect count |

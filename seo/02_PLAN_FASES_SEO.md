# Plan por Fases SEO — NovaVision Multi-Tenant

**Fecha:** 2026-02-12  
**Autor:** Agente Copilot  
**Prerequisito:** Leer `01_AUDIT_SEO_NOVAVISION.md` antes de este documento.

---

## Fase 0 — Baseline & Safety (Sprint 1: ~1 semana)

**Objetivo:** Medir estado actual, proteger ambientes no-productivos de indexación, y sanar configs básicas.

### PR 0.1 — `noindex` para preview/staging + robots.txt mejorado
**Archivos:**
- `apps/web/public/robots.txt` → Agregar `Disallow` para rutas privadas
- `apps/web/netlify/edge-functions/seo-robots.ts` → **NUEVO** — Edge function que genera `robots.txt` dinámico por tenant:
  - Si el host es preview/staging → `Disallow: /`
  - Si la tienda está en estado `draft`/`pending_approval` → `Disallow: /`
  - Si es tienda activa → robots normal con `Sitemap:` apuntando al sitemap del tenant
- `apps/web/netlify.toml` → Registrar nueva edge function en path `/robots.txt`
- `apps/web/public/_redirects` → Asegurar que `/robots.txt` NO sea capturado por el catch-all

**DoD:**
- [ ] `curl https://preview-slug.novavision.lat/robots.txt` muestra `Disallow: /`
- [ ] `curl https://tienda-activa.novavision.lat/robots.txt` muestra robots permitido + `Sitemap:` link
- [ ] `/admin-dashboard`, `/profile`, `/cart`, `/login`, `/oauth/callback` bloqueados en robots
- [ ] Ambientes de branch deploy (onboarding-preview-stable) devuelven `Disallow: /`

**Riesgos:** Edge function incorrecta podría bloquear indexación de tiendas activas.  
**Rollback:** Revertir edge function → vuelve al robots.txt estático que permite todo.

---

### PR 0.2 — Analytics base (GA4 + Search Console verification)
**Archivos:**
- `apps/web/index.html` → Agregar snippet GA4 con `gtag('config', ...)` — **condicional por tenant** (el measurement ID vendrá del backend)
- `apps/api/src/tenant/tenant.service.ts` → Agregar campo `ga_measurement_id` al bootstrap response
- Migración DB: `ALTER TABLE settings ADD COLUMN ga_measurement_id TEXT`
- Migración DB: `ALTER TABLE settings ADD COLUMN search_console_verification TEXT`
- `apps/web/src/components/AnalyticsProvider.jsx` → **NUEVO** — Componente que inyecta GA4 script con el measurement ID del tenant

**DoD:**
- [ ] Tenant con `ga_measurement_id` configurado → GA4 trackea pageviews
- [ ] Tenant sin `ga_measurement_id` → No se inyecta nada (zero overhead)
- [ ] No hay cross-tenant contamination (cada tenant trackea por separado)
- [ ] Search Console puede verificarse via meta tag

**Riesgos:** Tracking cross-tenant si se comparten cookies/storage. Mitigación: GA4 por defecto aísla por dominio.  
**Rollback:** Remover `AnalyticsProvider` del árbol React.

---

### PR 0.3 — Baseline Lighthouse + documentar métricas
**Archivos:**
- `novavision-docs/seo/baseline/` → **NUEVO** — Reports Lighthouse de 3-5 tenants activos
- Script: `scripts/lighthouse-audit.sh` → Automatiza auditoría Lighthouse para URLs dadas

**DoD:**
- [ ] Baseline documentado con scores Mobile + Desktop para: Performance, Accessibility, Best Practices, SEO
- [ ] Métricas CWV capturadas: LCP, INP, CLS, TTFB
- [ ] Documento de referencia creado con targets por fase

**Riesgos:** Ninguno (read-only).

---

## Fase 1 — Technical SEO Mínimo Viable (Sprint 2-3: ~2 semanas)

**Objetivo:** Meta tags dinámicos por tenant/página, canonical, sitemap por tenant, schema base.

### PR 1.1 — Head Manager dinámico (react-helmet-async)
**Archivos:**
- `apps/web/package.json` → Agregar `react-helmet-async`
- `apps/web/src/components/SEO/SEOHead.jsx` → **NUEVO** — Componente reutilizable:
  ```jsx
  <SEOHead
    title="Nombre Producto - Nombre Tienda"
    description="Descripción del producto..."
    canonical="https://tienda.novavision.lat/p/123"
    ogImage="https://storage.supabase.co/.../product-lg.webp"
    ogType="product"
    noindex={false}
  />
  ```
- `apps/web/src/pages/ProductPage/index.jsx` → Integrar `<SEOHead>` con datos del producto
- `apps/web/src/routes/HomeRouter.jsx` → Integrar `<SEOHead>` con datos del tenant
- `apps/web/src/pages/SearchPage/` → Integrar `<SEOHead>` para categoría/búsqueda
- `apps/web/src/components/NotFoundFallback/` → Integrar `<SEOHead noindex={true}>`
- `apps/web/index.html` → Cambiar title fallback a template dinámico, quitar meta hardcodeados

**DoD:**
- [ ] `document.title` cambia dinámicamente en cada page (Home, Producto, Búsqueda, 404)
- [ ] `<meta name="description">` refleja contenido del tenant/producto
- [ ] `<meta property="og:*">` refleja datos del tenant (imagen, nombre, URL)
- [ ] `<meta name="robots" content="noindex">` en páginas privadas (cart, profile, admin)
- [ ] `<link rel="canonical">` presente en cada página con URL correcta del tenant
- [ ] Custom domain (`mitienda.com`) usa canonical con SU dominio, no `novavision.lat`

**Riesgos:** Helmet puede generar duplicados si no se limpia el index.html estático. Mitigación: remover meta estáticos del HTML.  
**Rollback:** Removiendo Helmet vuelve al estado anterior (hardcodeado).

---

### PR 1.2 — Sitemap dinámico por tenant
**Archivos:**
- `apps/api/src/seo/seo.module.ts` → **NUEVO** módulo
- `apps/api/src/seo/seo.controller.ts` → **NUEVO** — Endpoint `GET /seo/sitemap.xml`:
  - Recibe `x-tenant-slug` → genera XML con:
    - Home: `https://{domain}/`
    - Productos activos: `https://{domain}/p/{id}` con `<lastmod>` del `updated_at`
    - Categorías: `https://{domain}/search?categoryIds={id}`
  - Cache: 1 hora con ETag
  - Content-Type: `application/xml`
- `apps/web/netlify/edge-functions/seo-sitemap.ts` → **NUEVO** — Proxy que intercepta `/sitemap.xml` y lo redirige al endpoint del API con el slug del tenant
- `apps/web/netlify.toml` → Registrar edge function para `/sitemap.xml`

**DoD:**
- [ ] `curl https://tienda.novavision.lat/sitemap.xml` retorna XML válido con URLs del tenant
- [ ] Sitemap incluye solo productos activos con `<lastmod>`
- [ ] Sitemap no incluye productos de otros tenants (zero cross-tenant)
- [ ] robots.txt del tenant apunta al sitemap correcto
- [ ] Sitemap respeta custom domain si existe

**Riesgos:** Cross-tenant si el slug no se valida correctamente en el proxy.  
**Rollback:** Remover edge function → `/sitemap.xml` devuelve 200 con `index.html` (sin funcionalidad, pero sin daño).

---

### PR 1.3 — Structured Data base (Product + Organization + BreadcrumbList)
**Archivos:**
- `apps/web/src/components/SEO/JsonLd.jsx` → **NUEVO** — Componente genérico para inyectar `<script type="application/ld+json">`
- `apps/web/src/components/SEO/ProductSchema.jsx` → **NUEVO** — Schema `Product` con:
  - `name`, `description`, `image`, `sku`
  - `offers`: `price`, `priceCurrency`, `availability`, `url`
  - `brand`: nombre del tenant como marca
- `apps/web/src/components/SEO/OrganizationSchema.jsx` → **NUEVO** — Schema `Organization` con datos del tenant
- `apps/web/src/components/SEO/BreadcrumbSchema.jsx` → **NUEVO** — Schema `BreadcrumbList`
- `apps/web/src/pages/ProductPage/index.jsx` → Integrar schemas
- `apps/web/src/routes/HomeRouter.jsx` → Integrar `OrganizationSchema`

**DoD:**
- [ ] Rich Results Test de Google valida Product schema en página de producto
- [ ] Organization schema presente en home con datos del tenant (no NovaVision)
- [ ] BreadcrumbList en producto (Home → Categoría → Producto)
- [ ] Cada schema solo contiene datos del tenant actual (zero cross-tenant)

**Riesgos:** Schema incorrecto puede generar penalización manual de Google. Mitigación: validar con herramienta oficial antes de deploy.  
**Rollback:** Remover componentes Schema → sin rich snippets pero sin penalización.

---

### PR 1.4 — Breadcrumbs visibles + headings consistentes
**Archivos:**
- `apps/web/src/components/Breadcrumbs/` → **NUEVO** — Componente visual de breadcrumbs
- `apps/web/src/pages/ProductPage/index.jsx` → Integrar breadcrumbs arriba del producto
- Auditoría de H1/H2 en cada template de Home → Ajustar si hay inconsistencias

**DoD:**
- [ ] Breadcrumb visual y schema coinciden
- [ ] Cada página tiene exactamente 1 `<h1>`
- [ ] H2-H6 siguen jerarquía lógica

**Riesgos:** Bajo — solo UI.  
**Rollback:** Remover componente.

---

## Fase 2 — Performance + Core Web Vitals (Sprint 4-5: ~2 semanas)

### PR 2.1 — Imágenes: lazy loading + sizes + fetchpriority
**Archivos:**
- `apps/web/src/templates/fifth/utils/mappers.js` → `toPictureSources()` agregar `sizes` attribute
- Componentes de imagen (`ProductGallery`, `BannerSlider`, etc.):
  - Primera imagen visible: `loading="eager"` + `fetchpriority="high"`
  - Resto: `loading="lazy"`
  - Agregar `width` + `height` para evitar CLS
  - Agregar `decoding="async"` en imágenes below-the-fold

**DoD:**
- [ ] LCP image tiene `fetchpriority="high"` y `loading="eager"`
- [ ] Imágenes below-the-fold tienen `loading="lazy"`
- [ ] CLS ≤ 0.1 en mobile (sin layout shifts por imágenes)
- [ ] Todas las `<img>` tienen `width` y `height` (o aspect-ratio CSS)

**Riesgos:** Lazy loading agresivo puede retrasar LCP. Mitigación: primera imagen siempre eager.  
**Rollback:** Remover atributos → sin lazy pero funcional.

---

### PR 2.2 — Cache headers + asset fingerprinting
**Archivos:**
- `apps/web/netlify.toml` → Agregar headers por pattern:
  ```toml
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

  [[headers]]
  for = "/index.html"
    [headers.values]
    Cache-Control = "public, max-age=0, must-revalidate"
  ```

**DoD:**
- [ ] Assets con hash en nombre → `Cache-Control: immutable, 1 year`
- [ ] `index.html` → `must-revalidate` (siempre fresco)
- [ ] TTFB mejora para repeat visits
- [ ] Verificado con `curl -I` en producción

**Riesgos:** Bajo.  
**Rollback:** Remover headers → cache default de Netlify.

---

### PR 2.3 — Font preload + Code splitting
**Archivos:**
- `apps/web/index.html` → `<link rel="preload" as="font" ...>` para fuentes principales
- `apps/web/vite.config.js` → Configurar `rollupOptions.output.manualChunks`:
  - Vendor: react, react-dom, react-router
  - MP: @mercadopago/sdk-react (lazy load)
  - Charts: recharts (lazy load)
  - Admin: admin-dashboard (lazy load)
- `apps/web/src/routes/AppRoutes.jsx` → `React.lazy()` para rutas pesadas (AdminDashboard, UserDashboard, SearchPage)

**DoD:**
- [ ] Bundle principal < 200KB gzipped
- [ ] Fuentes preloadeadas → sin FOIT
- [ ] Admin dashboard NO se carga en storefront público
- [ ] Mejora en Lighthouse Performance score

**Riesgos:** Lazy loading de rutas puede causar flash si no hay Suspense fallback.  
**Rollback:** Revertir manualChunks y lazy imports.

---

### PR 2.4 — Edge Function: Meta Injection para Social Crawlers (Opción D de SSR/Prerender)
**Archivos:**
- `apps/web/netlify/edge-functions/seo-meta-injector.ts` → **NUEVO** — Edge function que:
  1. Detecta User-Agent de bots (facebookexternalhit, Twitterbot, LinkedInBot, WhatsApp, Googlebot optionally)
  2. Parsea la URL para determinar tipo de página (home, producto `/p/:id`, búsqueda)
  3. Consulta al API (`GET /seo/meta?slug=X&type=product&id=Y`) para obtener meta dinámicos
  4. Lee el `index.html` del build y reemplaza los meta tags estáticos por los dinámicos
  5. Sirve el HTML modificado al bot
  6. Usuarios normales → passthrough sin modificar
- `apps/api/src/seo/seo.controller.ts` → Agregar endpoint `GET /seo/meta`:
  - Input: `type` (home/product/search), `id` (si aplica)
  - Output: `{ title, description, ogTitle, ogDescription, ogImage, ogUrl, canonical }`
  - Resuelve datos del tenant + entidad → genera meta optimizados
- `apps/web/netlify.toml` → Registrar edge function con prioridad antes de maintenance

**DoD:**
- [ ] Facebook Sharing Debugger muestra título/imagen del producto/tienda (no "NovaVision")
- [ ] Twitter Card Validator muestra preview correcto
- [ ] WhatsApp muestra preview con imagen y título del producto
- [ ] Googlebot recibe HTML con meta correctos
- [ ] Usuarios normales no ven diferencia (passthrough)
- [ ] Latencia de edge function < 200ms (con cache)
- [ ] Zero cross-tenant (meta siempre del tenant del request)

**Riesgos:** Edge function falla → usuarios ven la app normal (failsafe). Cache de meta puede servir datos desactualizados.  
**Rollback:** Desactivar edge function → vuelve a meta genéricos.

---

## Fase 3 — Contenido & Landings (Sprint 6-8: ~3 semanas)

### PR 3.1 — Módulo de Blog/Recursos (API + Frontend)
**Archivos:**
- Migración DB: tabla `blog_posts` (`id`, `client_id`, `title`, `slug`, `content` markdown/HTML, `excerpt`, `featured_image`, `meta_title`, `meta_description`, `status` draft/published, `published_at`, timestamps)
- Migración DB: tabla `blog_categories` + `blog_post_categories` (M:N)
- `apps/api/src/blog/` → **NUEVO** módulo CRUD con endpoints públicos (GET) y admin (POST/PUT/DELETE)
- `apps/web/src/pages/BlogPage/` → **NUEVO** — Listado de posts
- `apps/web/src/pages/BlogPostPage/` → **NUEVO** — Post individual con SEOHead + ArticleSchema
- `apps/web/src/routes/AppRoutes.jsx` → Agregar `/blog` y `/blog/:slug`
- Edge function: agregar rutas de blog al meta injector

**DoD:**
- [ ] Admin puede crear/editar/publicar posts
- [ ] Posts tienen meta tags SEO independientes
- [ ] Sitemap incluye posts publicados
- [ ] Schema `Article` en cada post
- [ ] Solo posts del tenant actual visibles

**Riesgos:** Nuevo módulo completo — más testing. Sin impacto en checkout/órdenes.  
**Rollback:** Remover módulo blog.

---

### PR 3.2 — Páginas estáticas gestionables (Sobre Nosotros, Políticas, etc.)
**Archivos:**
- Migración DB: tabla `static_pages` (`id`, `client_id`, `slug`, `title`, `content`, `meta_title`, `meta_description`, `published`)
- `apps/api/src/static-pages/` → CRUD
- `apps/web/src/pages/StaticPage/` → Render genérico
- `apps/web/src/routes/AppRoutes.jsx` → Ruta dinámica `/page/:slug`

**DoD:**
- [ ] Tenant admin puede crear "Sobre Nosotros", "FAQ", "Políticas de Envío"
- [ ] Páginas indexables con meta y canonical propios
- [ ] Incluidas en sitemap

---

### PR 3.3 — Mejoras de internal linking
**Archivos:**
- Componentes de producto: agregar "Productos Relacionados" como links (no solo visual)
- Componentes de categoría: links a categorías hermanas
- Footer: links a categorías principales, blog, páginas estáticas

**DoD:**
- [ ] Cada producto tiene al menos 3 links internos indexables
- [ ] Footer tiene estructura de navegación crawlable

---

## Fase 4 — Automatización & Operación (Sprint 9-10: ~2 semanas)

### PR 4.1 — Dashboard SEO Health (en Admin Cliente)
**Archivos:**
- `apps/web/src/components/admin/SEOHealth/` → **NUEVO** — Widget en admin dashboard del tenant:
  - Resumen: páginas indexables, sitemap status, robots status
  - CWV últimos 28 días (si tiene GA4)
  - Checklist: "✅ Sitemap activo", "⚠️ 3 productos sin descripción", etc.
- `apps/api/src/seo/seo.service.ts` → Endpoint `GET /seo/health` que recopila:
  - Conteo de productos sin meta description
  - Conteo de imágenes sin alt text
  - Status del sitemap
  - Últimas URLs crawleadas (si se integra GSC API)

**DoD:**
- [ ] Widget visible solo para tenants Growth/Enterprise
- [ ] Muestra status real del SEO del tenant
- [ ] Acciones sugeridas con links a la sección correspondiente

---

### PR 4.2 — Panel SEO en Super Admin
**Archivos:**
- `apps/admin/src/pages/ClientDetails/tabs/SEOTab.jsx` → **NUEVO** — Tab en vista de cliente:
  - Estado SEO del tenant (scores, issues, entregables)
  - Checklist de entregables del servicio SEO
  - Historial de auditorías
  - Settings globales: templates de meta, defaults de schema
- Migración DB admin: tabla `seo_service_log` (account_id, action, data, timestamp) para tracking del servicio

**DoD:**
- [ ] Super admin puede ver estado SEO de cada tenant
- [ ] Puede marcar entregables como completados
- [ ] Historial auditable

---

### PR 4.3 — Reports automáticos mensuales
**Archivos:**
- `apps/api/src/seo/seo-report.service.ts` → **NUEVO** — Genera report mensual:
  - Páginas indexadas (GSC API si disponible)
  - Impresiones y clicks top
  - CWV promedio
  - Issues detectados
  - Cambios vs mes anterior
- Email template: `email_templates/seo-monthly-report.hbs`
- Cron job o invocación manual desde admin

**DoD:**
- [ ] Report generado y enviado automáticamente al admin del tenant
- [ ] Disponible en dashboard SEO del super admin
- [ ] Solo para tenants con servicio SEO activo (Growth/Enterprise)

---

### PR 4.4 — Alertas SEO
**Archivos:**
- `apps/api/src/seo/seo-alerts.service.ts` → Monitoreo:
  - Caída > 30% en páginas indexadas
  - Errores de crawl nuevos
  - CWV que cruzan umbral (LCP > 2.5s, CLS > 0.1, INP > 200ms)
  - Sitemap inaccesible
- Notificación via email y/o Slack webhook

**DoD:**
- [ ] Alerta disparada dentro de 24h de detectar issue
- [ ] Alerta incluye contexto y acción sugerida

---

## Resumen Timeline

```
Semana 1     │ Fase 0: Baseline, noindex, robots, analytics
Semanas 2-3  │ Fase 1: Head manager, sitemap, schema, canonical, breadcrumbs
Semanas 4-5  │ Fase 2: Imágenes, cache, fonts, code splitting, edge meta injection
Semanas 6-8  │ Fase 3: Blog, static pages, internal linking
Semanas 9-10 │ Fase 4: Dashboard SEO, reports, alertas
```

**Total estimado:** ~10 semanas (2.5 meses) para la implementación completa.

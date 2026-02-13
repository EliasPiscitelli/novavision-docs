# SEO Fase 2 — P0-1 custom domain fix + Dynamic sitemap + JSON-LD

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` → commit `ea09822`
  - Web: `feature/multitenant-storefront` → commit `eefff57`
  - Develop (cherry-pick): API `0361394`, Web `cbe5d24`

---

## Resumen

Tres features implementadas en esta sesión:

1. **P0-1 Custom domain resolution** — Fix crítico para que storefronts con dominio propio resuelvan su tenant correctamente.
2. **Dynamic sitemap.xml** — Sitemap XML dinámico per-tenant generado por el backend, proxyado via Netlify.
3. **JSON-LD structured data** — Schema.org markup para Product, Organization y Breadcrumb.

---

## Archivos modificados

### API (templatetwobe)
| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/tenant/tenant.controller.ts` | MOD | Nuevo endpoint `GET /tenant/resolve-host?domain=xxx` con `@AllowNoTenant()` |
| `src/tenant/tenant.service.ts` | MOD | Nuevo método `resolveHostToSlug(domain)` — consulta `nv_accounts.custom_domain` en Admin DB |
| `src/seo/seo.controller.ts` | MOD | Nuevo endpoint `GET /seo/sitemap.xml` — devuelve XML con Content-Type y Cache-Control |
| `src/seo/seo.service.ts` | MOD | Nuevo método `generateSitemapXml(clientId)` + helpers `sitemapUrl`, `escapeXml`, `slugify` |
| `src/app.module.ts` | MOD | Auth excludes para `tenant/resolve-host` y `seo/sitemap.xml` |
| `src/plans/featureCatalog.ts` | MOD | `seo.sitemap` → live, `seo.schema` → live + growth: true |

### Web (templatetwo)
| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/utils/tenantResolver.js` | MOD | Nueva función `isLikelyCustomDomain(hostname)` exportada |
| `src/context/TenantProvider.jsx` | MOD | Flujo async de resolución de custom domain antes del bootstrap |
| `src/components/SEOHead/JsonLd.jsx` | NEW | `ProductJsonLd`, `OrganizationJsonLd`, `BreadcrumbJsonLd` |
| `src/components/SEOHead/index.jsx` | MOD | Integra `OrganizationJsonLd` (schema.org Organization) |
| `src/pages/ProductPage/index.jsx` | MOD | Integra `ProductJsonLd` (schema.org Product + Offer) |
| `public/_redirects` | MOD | Proxy `/sitemap.xml` → backend API en lugar de 404 |
| `public/robots.txt` | MOD | Directiva `Sitemap: /sitemap.xml` |

---

## Detalle técnico

### P0-1: Custom domain resolution

**Problema:** `tenantResolver.js` devolvía `null` para hostnames con 2 partes (ej: `tiendapepe.com`), haciendo que storefronts con dominio propio no funcionaran.

**Solución (3 piezas):**

1. **Backend** — `GET /tenant/resolve-host?domain=tiendapepe.com` 
   - `@AllowNoTenant()` (no requiere `x-client-id` ni JWT)
   - Normaliza dominio, busca en `nv_accounts.custom_domain` donde `custom_domain_status = 'active'`
   - Retorna `{ slug: "pepe" }` o 404
   - Solo expone el slug público, sin datos sensibles

2. **Frontend `tenantResolver.js`** — `isLikelyCustomDomain(hostname)`:
   - Detecta hostnames que NO son localhost, *.novavision.lat, *.netlify.app, *.ngrok-free.app
   - Tienen ≥2 partes (no es solo "localhost")

3. **Frontend `TenantProvider.jsx`** — Resolución async:
   - Cuando `getTenantSlug()` retorna unknown/null Y `isLikelyCustomDomain()` es true
   - Llama a `GET /tenant/resolve-host?domain=hostname`
   - Cachea el slug resuelto en `window.__NV_TENANT_SLUG__`
   - Continúa con el flujo normal de bootstrap

**Seguridad:** El endpoint solo devuelve slug público. No se habilita `x-tenant-host` en producción (riesgo de tenant impersonation). El cache en `window.__NV_TENANT_SLUG__` persiste por duración de la tab.

### Dynamic Sitemap XML

**Backend (`seo.service.ts`):**
- `generateSitemapXml(clientId)` genera XML compliant con sitemaps.org spec
- Determina URL base: prefiere `custom_domain` → `base_url` → `{slug}.novavision.lat`
- Incluye: homepage (priority 1.0, daily), products activos no-noindex (0.8, weekly, lastmod), categories activas no-noindex (0.6, weekly)
- Limit: 50,000 URLs (spec máximo)
- `escapeXml()` previene XML injection en URLs/nombres

**Proxy via Netlify (_redirects):**
```
/sitemap.xml https://novavision-production.up.railway.app/seo/sitemap.xml 200
```
- Netlify pasa `x-forwarded-host` automáticamente → backend resuelve tenant

**Cache:** `Cache-Control: public, max-age=3600` (1 hora)

### JSON-LD Structured Data

**`JsonLd.jsx` — 3 componentes:**

1. `ProductJsonLd` — `@type: Product` con `Offer` embebido
   - Precio (`price`), moneda (`ARS`), disponibilidad (InStock/OutOfStock)
   - Imagen, SKU, descripción
   
2. `OrganizationJsonLd` — `@type: Organization`
   - Nombre del sitio (de seoSettings o tenantConfig)
   - Logo URL

3. `BreadcrumbJsonLd` — `@type: BreadcrumbList`
   - Lista de items con position, name, URL
   - Reutilizable en cualquier página

**Integración:**
- SEOHead (todas las páginas) → `OrganizationJsonLd`
- ProductPage → `ProductJsonLd`

---

## Cómo probar

### P0-1 Custom domain
```bash
# Backend (requiere DB con nv_accounts que tenga custom_domain activo)
curl http://localhost:3000/tenant/resolve-host?domain=tiendaejemplo.com
# → { "slug": "ejemplo" }

# Frontend
# Configurar host local apuntando a localhost:5173
# (o probar en producción una vez que un cliente tenga custom_domain = 'active')
```

### Sitemap
```bash
# Via proxy Netlify (producción)
curl https://<tienda>.novavision.lat/sitemap.xml

# Directo al backend
curl -H "x-forwarded-host: <tienda>.novavision.lat" \
     http://localhost:3000/seo/sitemap.xml
```

### JSON-LD
```bash
cd apps/web && npm run dev
# Abrir http://localhost:5173?tenant=<slug>
# Inspeccionar <head> → buscar <script type="application/ld+json">
# Homepage → Organization schema
# Producto → Product schema con Offer
```

### Validadores externos
- Google Rich Results Test: https://search.google.com/test/rich-results
- Schema.org Validator: https://validator.schema.org/
- Google Search Console → Sitemaps → Submit `/sitemap.xml`

---

## Notas de seguridad

- `/tenant/resolve-host` es público con `@AllowNoTenant()` — solo retorna slug, sin datos sensibles
- Sitemap excluye productos/categorías con `noindex = true`
- No se expone SERVICE_ROLE_KEY en ningún flujo
- JSON-LD usa datos ya públicos (nombre, precio, imagen) — no expone datos privados
- `escapeXml()` previene inyección de XML en sitemap

---

## Feature catalog actualizado

| Feature | Estado anterior | Estado actual |
|---------|----------------|---------------|
| `seo.sitemap` | planned | **live** |
| `seo.schema` | planned (growth: false) | **live** (growth: true) |

---

## Pendiente (Fase 2 restante)

- Admin SEO settings panel (UI para configurar SEO desde dashboard)
- Edge function para OG injection (social crawlers: Facebook/WhatsApp/Twitter no ejecutan JS)
- Redirects manager (`seo.redirects` — aún `planned`)
- robots.txt dinámico per-tenant

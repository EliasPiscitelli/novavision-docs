# Auditoría SEO — NovaVision Multi-Tenant SaaS

**Fecha:** 2026-02-12  
**Autor:** Agente Copilot (Principal SEO Architect + Staff Engineer + Security Auditor)  
**Versión:** 1.0  
**Ramas auditadas:** `feature/multitenant-storefront` (web), `feature/automatic-multiclient-onboarding` (api/admin)

---

## Índice
1. [Arquitectura del Sistema](#1-arquitectura-del-sistema)
2. [Estado Actual SEO — Hallazgos con Evidencia](#2-estado-actual-seo--hallazgos-con-evidencia)
3. [Hallazgos Priorizados (P0/P1/P2)](#3-hallazgos-priorizados-p0p1p2)
4. [Matriz Riesgo vs Impacto](#4-matriz-riesgo-vs-impacto)
5. [Análisis por Dominio SEO](#5-análisis-por-dominio-seo)
6. [Recomendación SSR/SSG/Prerender](#6-recomendación-ssrssgprerender)
7. [Supuestos y Evidencia Pendiente](#7-supuestos-y-evidencia-pendiente)

---

## 1. Arquitectura del Sistema

### 1.1 Apps del Monorepo

| App | Repo | Framework | Deploy | Propósito |
|-----|------|-----------|--------|-----------|
| **Web (Storefront)** | `templatetwo` | Vite + React 18 + Styled Components | Netlify | Tienda pública multi-tenant — **lo que Google indexa** |
| **API (Backend)** | `templatetwobe` | NestJS + Supabase | Railway | Backend multi-tenant (REST API) |
| **Admin (Super Admin)** | `novavision` | Vite + React 19 + MUI | Netlify | Dashboard interno NovaVision (gestión de clientes) |
| **Onboarding Preview** | Rama en `templatetwo` | Misma app web | Netlify (branch deploy) | Preview de tiendas no publicadas |

### 1.2 Hosting y Netlify — Evidencia del Repo

**Web Storefront** (`apps/web/netlify.toml`):
```toml
[[edge_functions]]
function = "maintenance"
path = "/*"

[build.environment]
NODE_VERSION = "20.11.1"

[[headers]]
for = "/*"
  [headers.values]
  Cross-Origin-Opener-Policy = "same-origin-allow-popups"
  # CSP con sdk.mercadopago, gtm, supabase, railway, etc.
```

**`apps/web/public/_redirects`:**
```
/*    /index.html   200
```

> **⚠️ Hallazgo P0:** El catch-all `/* → /index.html  200` significa que **toda request** (incluyendo `/robots.txt`, `/sitemap.xml`, cualquier URL no existente) devuelve `index.html` con status **200**. Excepto que los archivos estáticos en `public/` tomen precedencia, lo cual en Netlify SÍ ocurre para archivos existentes. Pero `/sitemap.xml` **no existe** → devuelve `index.html` con 200.

**Admin** (`apps/admin/netlify.toml`):
```toml
[build]
  command = "npm run build"
  publish = "dist"
[[redirects]]
  from = "/*"
  to = "/index.html"
  status = 200
```

### 1.3 Resolución de Tenant (Multi-Tenant)

**Frontend** (`src/utils/tenantResolver.js`):
```javascript
// Dev: ?tenant=xxx o ?slug=xxx
// Prod: {slug}.novavision.lat → extrae primer subdominio
const parts = hostname.split('.');
if (parts.length >= 3) return parts[0]; // slug
```

**Backend** (`src/guards/tenant-context.guard.ts`):
1. Header `x-tenant-slug` → busca en `nv_accounts` por slug
2. Header `x-forwarded-host` → busca en `nv_accounts.custom_domain`
3. Subdominio del host → extrae slug

**Custom Domains** (Growth/Enterprise):
- Columnas en `nv_accounts`: `custom_domain`, `custom_domain_status` (`pending_dns`/`active`/`error`)
- Resolución: el guard busca `custom_domain` en `nv_accounts` cuando el host no es `*.novavision.lat`
- **⚠️ Supuesto:** Los custom domains se configuran como dominios adicionales en Netlify (mismos site). Necesito confirmación de si es 1 sitio Netlify para todas las tiendas o varios.

### 1.4 Ambientes y Ramas

| Rama | Entorno | Notas |
|------|---------|-------|
| `feature/multitenant-storefront` | **Producción storefront** | Tiendas activas |
| `feature/onboarding-preview-stable` | **Preview onboarding** | Tiendas en setup (⚠️ NO debe indexarse) |
| `develop` | Integración | Cambios shared |
| `main` | Base | Deploys validados |

> **⚠️ Hallazgo P0:** No hay mecanismo de `noindex` para preview/onboarding. Un bot podría indexar tiendas no publicadas.

---

## 2. Estado Actual SEO — Hallazgos con Evidencia

### 2.1 `robots.txt` — DEFICIENTE

**Archivo:** `apps/web/public/robots.txt`
```
# https://www.robotstxt.org/robotstxt.html
User-agent: *
Disallow:
```

**Problemas:**
- ❌ Sin directiva `Sitemap:` → Google no descubre el sitemap
- ❌ Estático y genérico → **idéntico para TODOS los tenants**
- ❌ No bloquea `/admin-dashboard`, `/profile`, `/cart`, `/login`, `/oauth/callback`
- ❌ No hay robots.txt diferenciado por ambiente (preview indexable)

### 2.2 Sitemap — NO EXISTE

**Verificación:** Buscado en `public/`, edge functions, API endpoints, y scripts. **Resultado: cero**.

- ❌ No hay `sitemap.xml` estático ni dinámico
- ❌ No hay endpoint API que genere sitemaps
- ❌ No hay edge function para sitemap
- ❌ Google no tiene forma de descubrir las páginas de los tenants

### 2.3 Meta Tags — HARDCODEADOS (GENÉRICOS)

**Archivo:** `apps/web/index.html`
```html
<title>NovaVision | Tiendas Online para Pymes y Emprendedores</title>
<meta name="description" content="Lanzá tu tienda online con NovaVision..." />
<meta property="og:title" content="NovaVision | Tiendas Online para Pymes y Emprendedores" />
<meta property="og:url" content="https://novavision.lat/" />
<meta property="og:image" content="/logo/logo-titulo.png" />
```

**Problemas:**
- ❌ **Cada tienda** (ej: `mitienda.novavision.lat`) muestra "NovaVision" como título
- ❌ **Cada producto** (`/p/:id`) muestra el mismo meta genérico
- ❌ OG URL apunta a `novavision.lat`, no al dominio del tenant
- ❌ OG image es el logo de NovaVision, no del tenant/producto
- ❌ No hay `react-helmet` ni ninguna gestión dinámica de `<head>`
- ❌ No se cambia `document.title` en ningún componente

### 2.4 Canonical Links — NO EXISTE

- ❌ No hay `<link rel="canonical">` en `index.html`
- ❌ No se genera dinámicamente en ninguna página
- ❌ Riesgo de duplicate content entre `slug.novavision.lat` y custom domain

### 2.5 Structured Data (JSON-LD) — NO EXISTE

- ❌ Cero presencia de `application/ld+json` en todo el codebase
- ❌ No hay schema `Product`, `Organization`, `Website`, `BreadcrumbList`, `FAQ`
- ❌ Ningún rich snippet posible en SERPs

### 2.6 Rendering (CSR puro) — CRÍTICO PARA SEO

**Evidencia:**  
- `apps/web/vite.config.js`: SPA build estándar, sin SSR plugins
- `apps/web/index.html`: `<div id="root"></div>` → HTML vacío
- No hay prerender, no hay SSR, no hay ISR
- La edge function `maintenance.ts` solo maneja availabilidad, no rendering

**Impacto:** Googlebot **sí** ejecuta JavaScript, pero:
1. Depende de la cola de rendering de Google (delay de días a semanas)
2. Budget de crawl desperdiciado en rendering
3. Redes sociales (Facebook, Twitter, WhatsApp) **NO ejecutan JS** → OG tags siempre genéricos
4. Lighthouse SEO score penalizado

### 2.7 Performance e Imágenes

**Pipeline de imágenes (API):** ✅ Existe y es bueno
- `sharp` genera webp + avif en múltiples sizes (320→2560px)
- `image_variants` JSONB guardado en DB
- Frontend: `toPictureSources()` genera `<picture>` con `<source>` por formato/size

**Gaps de performance:**
- ❌ No hay `loading="lazy"` explícito en imágenes
- ❌ No hay `sizes` attribute en `<img>` tags
- ❌ No hay `fetchpriority="high"` para LCP image
- ❌ No hay critical CSS extraction
- ❌ No hay font preload strategy (fonts cargadas por styled-components)
- ❌ Vite build sin manual chunk splitting configurado
- ❌ Cache headers en Netlify solo para `maintenance.html` (`no-store`)
- ❌ No hay `Cache-Control` optimizados para assets estáticos

### 2.8 Analytics / Tracking — NO EXISTE

- ❌ No hay GA4, GTM, ni ningún tracker
- ❌ No hay eventos e-commerce
- ❌ No hay Search Console verification tag
- ❌ Imposible medir impacto SEO sin analytics

### 2.9 Contenido y Blog — NO EXISTE

- ❌ No hay módulo de blog/CMS ni en API ni en frontend
- ❌ No hay páginas estáticas ("sobre nosotros", "políticas", etc.) gestionables
- ❌ Solo existe: Home, búsqueda, producto, carrito, checkout, admin

### 2.10 Manifest PWA — GENÉRICO

```json
{
  "short_name": "NovaVision",
  "name": "NovaVision - Tienda Online"
}
```
- ❌ No dinámico por tenant

---

## 3. Hallazgos Priorizados (P0/P1/P2)

### P0 — Críticos (bloquean indexación / causan daño)

| # | Hallazgo | Impacto | Evidencia |
|---|----------|---------|-----------|
| P0-1 | **SPA sin prerender**: Google ve HTML vacío; redes sociales muestran "NovaVision" genérico | Indexación nula/degradada, 0 rich snippets en social | `index.html` → `<div id="root"></div>` |
| P0-2 | **Meta tags hardcodeados**: Todo tenant muestra "NovaVision" como title/description | Cada tienda pierde identidad en SERPs y social sharing | `index.html` lines 6-20 |
| P0-3 | **Sitemap inexistente**: Google no puede descubrir páginas de ningún tenant | Crawl discovery = 0 | `find . -name "sitemap*"` → vacío |
| P0-4 | **Canonical inexistente**: Duplicate content entre subdomain y custom domain | Dilución de autoridad, indexación errática | `grep -r "canonical"` → vacío |
| P0-5 | **Preview/onboarding sin noindex**: Tiendas no publicadas indexables | Contenido draft en SERPs, mala experiencia usuario | Sin meta robots, sin robots.txt blocking |
| P0-6 | **Analytics inexistente**: No se puede medir nada | Cero visibilidad de performance SEO | `grep -r "gtag\|analytics\|dataLayer"` → vacío |

### P1 — Alto Impacto (mejoras significativas)

| # | Hallazgo | Impacto |
|---|----------|---------|
| P1-1 | **Structured Data (JSON-LD) inexistente** | Sin rich snippets (precio, rating, stock) en SERPs |
| P1-2 | **robots.txt genérico** sin Sitemap, sin Disallow de rutas privadas | Crawl budget desperdiciado |
| P1-3 | **No hay breadcrumbs** indexables | Estructura de navegación invisible para Google |
| P1-4 | **Imágenes sin lazy/sizes/fetchpriority** | CWV penalizado (LCP, CLS) |
| P1-5 | **Cache headers no optimizados** | TTFB alto, assets no cacheados en CDN |
| P1-6 | **Manifest PWA genérico** | Install prompt muestra "NovaVision" en vez del tenant |

### P2 — Mejora Continua

| # | Hallazgo | Impacto |
|---|----------|---------|
| P2-1 | **Blog/CMS inexistente** | Sin páginas de contenido para SEO de long tail |
| P2-2 | **Paginación sin prev/next** | Google puede no conectar páginas de categoría |
| P2-3 | **H1/H2 no validados** por template | Posible headings inconsistentes |
| P2-4 | **Internal linking débil** | Sin "productos relacionados" indexables |
| P2-5 | **Multi-idioma inexistente** (si llega a ser necesario) | Sin hreflang |
| P2-6 | **Font loading no optimizado** | CLS por FOIT/FOUT |

---

## 4. Matriz Riesgo vs Impacto

```
IMPACTO SEO →
  ▲ ALTO │ P0-1(prerender)  P0-2(meta)  P0-3(sitemap)
         │ P1-1(schema)     P0-6(analytics)
         │
  MEDIO  │ P0-4(canonical)  P1-2(robots)  P1-4(images)
         │ P1-5(cache)      P2-1(blog)
         │
  BAJO   │ P1-6(manifest)   P2-2(paginación)  P2-5(i18n)
         │ P2-3(headings)   P2-6(fonts)
         └───────────────────────────────────────────────→
           BAJO             MEDIO              ALTO
                     ← RIESGO DE IMPLEMENTACIÓN
```

**Lectura:**
- **Cuadrante HIGH impact / LOW risk:** Meta tags, robots.txt, canonical, analytics → **Hacer PRIMERO**
- **Cuadrante HIGH impact / HIGH risk:** Prerender/SSR → **Hacer con plan incremental**
- **Cuadrante LOW impact / LOW risk:** Manifest, fonts → **Quick wins**

---

## 5. Análisis por Dominio SEO

### 5.1 Indexación y Rastreo

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| `robots.txt` | ⚠️ Deficiente | Existe pero genérico, sin Sitemap, sin Disallow |
| `sitemap.xml` | ❌ No existe | Ni estático ni dinámico |
| Canonical | ❌ No existe | Riesgo duplicate content subdomain/custom domain |
| 404 handling | ⚠️ Parcial | `NotFoundFallback` en React pero devuelve 200 (SPA) |
| `noindex` en preview | ❌ No existe | Tiendas en onboarding indexables |
| Redirects SPA | ⚠️ Riesgoso | `/* → /index.html 200` atrapa todo |

### 5.2 Rendering

| Aspecto | Estado |
|---------|--------|
| Tipo | CSR puro (SPA React) |
| HTML inicial | `<div id="root"></div>` — vacío |
| SSR/SSG/prerender | No existe |
| Helmet/head manager | No existe |
| Social previews | Genéricos "NovaVision" siempre |

### 5.3 Structured Data

| Schema | Estado |
|--------|--------|
| Product | ❌ No existe |
| Organization | ❌ No existe |
| Website | ❌ No existe |
| BreadcrumbList | ❌ No existe |
| FAQ | ❌ No existe |
| SearchAction | ❌ No existe |

### 5.4 Performance

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| Image optimization | ✅ Pipeline existe | sharp → webp/avif, `<picture>` en frontend |
| Image lazy loading | ❌ No implementado | Sin `loading="lazy"` |
| Image sizes/srcset | ⚠️ Parcial | `<picture>` sources existen pero sin `sizes` |
| LCP optimization | ❌ No existe | Sin `fetchpriority="high"` |
| CSS critical path | ❌ No existe | styled-components runtime |
| Font strategy | ❌ Sin optimizar | Sin preload, posible FOIT |
| Cache headers | ❌ No optimizados | Solo `no-store` en maintenance |
| Bundle splitting | ❌ Default Vite | Sin manual chunks |

### 5.5 On-Page

| Aspecto | Estado |
|---------|--------|
| Title dinámico | ❌ Hardcoded "NovaVision" |
| Meta description | ❌ Hardcoded genérico |
| H1 por página | ⚠️ Sin validar — depende del template |
| Alt text imágenes | ⚠️ Sin auditar componentes individuales |
| Internal linking | ⚠️ Básico (categorías, relacionados) |
| URL structure | ✅ Limpia (`/p/:id`, `/search`) |

### 5.6 Analytics

| Aspecto | Estado |
|---------|--------|
| GA4 | ❌ No existe |
| Search Console | ❌ No verificado |
| GTM | ❌ No existe |
| E-commerce events | ❌ No existe |
| RUM / CWV tracking | ❌ No existe |

---

## 6. Recomendación SSR/SSG/Prerender

### Opciones evaluadas

| Opción | Pros | Contras | Costo | Riesgo |
|--------|------|---------|-------|--------|
| **A) Mantener CSR + Prerender Service** | Mínimo cambio en stack, riesgo bajo, incremental | No resuelve social previews dinámicos 100% | Bajo-Medio | Bajo |
| **B) Netlify Edge + Prerender** | Edge function inyecta meta antes de servir HTML. Resuelve social y bots. Sin cambio de framework. | Complejidad en edge, latencia adicional, cache strategy | Medio | Medio |
| **C) Migrar a Next.js/Remix (SSR/SSG)** | Solución canónica, best-in-class SEO | Rewrite masivo, riesgo altísimo, meses de trabajo | Muy Alto | Muy Alto |
| **D) Hybrid: Edge Meta Injection + Prerender para money pages** | Mejor ROI: social previews via edge, Google indexa via prerender service. Incremental. | 2 capas de cache/rendering | Medio | Medio-Bajo |

### **Recomendación: Opción D (Hybrid)**

1. **Fase inmediata (sin SSR):** Netlify Edge Function que intercepte requests de bots (Googlebot, facebookexternalhit, Twitterbot, etc.) y sirva HTML con meta tags dinámicos inyectados (consulta al API por slug + page type + entity ID).
2. **Fase siguiente:** Prerender service (Prerender.io o self-hosted con Puppeteer) para money pages (home, producto, categoría) que cachea HTML renderizado.
3. **Largo plazo (opcional):** Evaluar migración parcial del storefront a framework SSR/SSG solo si el volumen de páginas justifica la inversión.

**Justificación:** El pipeline de imágenes ya es bueno (webp/avif), el storefront funciona bien como SPA para usuarios. El problema real es que **bots y social crawlers** no ven contenido. La solución edge + prerender resuelve esto sin reescribir la app.

---

## 7. Supuestos y Evidencia Pendiente

| # | Supuesto | Evidencia necesaria |
|---|----------|---------------------|
| S1 | Netlify sirve 1 sitio para todas las tiendas (wildcard `*.novavision.lat`) | Captura del dashboard Netlify → Domain management |
| S2 | Custom domains Growth/Enterprise se agregan como domain aliases en el mismo sitio Netlify | Config Netlify + DNS records |
| S3 | Branch deploys de onboarding-preview-stable tienen URL diferente (deploy preview) | Verificar URLs de branch deploy |
| S4 | No hay CDN adicional (Cloudflare, etc.) entre Netlify y usuario | Confirmar DNS setup |
| S5 | Lighthouse scores actuales (necesito baseline real) | Ejecutar Lighthouse en producción con tenant activo |
| S6 | Search Console no tiene propiedades registradas para tenants | Verificar acceso a GSC |
| S7 | Google actualmente NO indexa contenido útil de las tiendas | Buscar `site:slug.novavision.lat` en Google |

> **Solicito al TL:** Confirmación de S1-S4 con capturas o acceso. Para S5-S7 puedo ejecutar si tengo URLs de tenants activos.

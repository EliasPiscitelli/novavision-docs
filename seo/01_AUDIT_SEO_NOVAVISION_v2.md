# Auditoría SEO — NovaVision Multi-Tenant SaaS (v2)

**Fecha:** 2026-02-12 (rev. v2)  
**Autor:** Agente Copilot (Principal SEO Architect + Staff Engineer + Security Auditor)  
**Revisión:** Incorpora feedback de TL — correcciones de criterio, riesgos no cubiertos, hallazgos funcionales nuevos.  
**Ramas auditadas:** `feature/multitenant-storefront` (web), `feature/automatic-multiclient-onboarding` (api/admin)

---

## Índice
1. [Arquitectura del Sistema](#1-arquitectura-del-sistema)
2. [Análisis Preciso de Configs](#2-análisis-preciso-de-configs-redirects--robots--edge)
3. [Estado Actual SEO — Diagnóstico Corregido](#3-estado-actual-seo--diagnóstico-corregido)
4. [Hallazgos Priorizados (P0/P1/P2)](#4-hallazgos-priorizados-p0p1p2)
5. [Matriz Riesgo vs Impacto (corregida)](#5-matriz-riesgo-vs-impacto-corregida)
6. [Análisis por Dominio SEO](#6-análisis-por-dominio-seo)
7. [Recomendación SSR/Prerender (revisada)](#7-recomendación-ssrprerender-revisada)
8. [Supuestos y Evidencia Pendiente](#8-supuestos-y-evidencia-pendiente)

---

## 1. Arquitectura del Sistema

### 1.1 Apps del Monorepo

| App | Repo | Framework | Deploy | Propósito |
|-----|------|-----------|--------|-----------|
| **Web (Storefront)** | `templatetwo` | Vite + React 18 + Styled Components | Netlify | Tienda pública multi-tenant — **lo que Google indexa** |
| **API (Backend)** | `templatetwobe` | NestJS + Supabase | Railway | Backend multi-tenant (REST API) |
| **Admin (Super Admin)** | `novavision` | Vite + React 19 + MUI | Netlify | Dashboard interno NovaVision (gestión de clientes) |
| **Onboarding Preview** | Rama en `templatetwo` | Misma app web | Netlify (branch deploy) | Preview de tiendas no publicadas |

### 1.2 Hosting y Netlify

**Web Storefront** (`netlify.toml`):
- 1 edge function `maintenance` en `/*` — health check del backend, passthrough para `/robots.txt`, `/sitemap.xml`, `/assets/`
- Headers globales: COOP, COEP, CORS, CSP
- **NO hay `[context.deploy-preview]`** ni `[context.branch-deploy]` → branch deploys no tienen `X-Robots-Tag: noindex`
- **NO hay cache headers** para assets estáticos (excepción: `maintenance.html` tiene `no-store`)

**`_redirects`:**
```
/*    /index.html   200
```

**`robots.txt` (estático):**
```
User-agent: *
Disallow:
```

### 1.3 Resolución de Tenant — HALLAZGO FUNCIONAL CRÍTICO

**Frontend** (`tenantResolver.js`):
```javascript
const parts = hostname.split('.');
if (parts.length >= 3) return parts[0]; // slug.novavision.lat → OK
return null; // mitienda.com (2 partes) → NULL
```

**`tenantScope.js`** → si resolver devuelve `null` → retorna `'unknown'`

**`TenantProvider.jsx`** → si slug es `'unknown'`:
```javascript
if (!slug || slug === 'unknown' || slug === 'server') {
  setError({ code: 'NO_SLUG', message: 'No se encontró la tienda en la URL' });
  return; // DEAD END — la tienda no carga
}
```

> **⚠️ P0 FUNCIONAL: Custom domains están rotos en el frontend.** Un usuario que visita `mitienda.com` ve "Tienda No Encontrada". El backend SÍ tiene lógica para resolver custom domains (via `x-forwarded-host` buscando en `nv_accounts.custom_domain`), pero el frontend se aborta antes de llegar a consultarlo.
>
> **El frontend NO envía `x-forwarded-host`** en ningún request. Solo envía `x-tenant-slug` / `x-store-slug`.

**Backend** (`tenant-context.guard.ts`) — cadena de resolución que SÍ funciona:
1. Header `x-tenant-slug` → busca slug en `nv_accounts`
2. Header `x-forwarded-host` / `host` → busca custom domain en `nv_accounts.custom_domain`
3. Subdominio del host → extrae slug igual que el frontend
4. Si nada resuelve → 401

### 1.4 Ambientes y Ramas

| Rama | Entorno | Protección de indexación |
|------|---------|------------------------|
| `feature/multitenant-storefront` | **Producción storefront** | ❌ Ninguna (robots permite todo) |
| `feature/onboarding-preview-stable` | **Preview onboarding** | ❌ Ninguna (sin X-Robots-Tag ni noindex) |
| `develop` | Integración | ❌ Ninguna |

---

## 2. Análisis Preciso de Configs (Redirects + Robots + Edge)

### 2.1 Flujo de un request a `tienda.novavision.lat/robots.txt`

```
Request → Netlify CDN
  → Edge Function `maintenance` (path: /*)
    → url.pathname === '/robots.txt' → context.next() [BYPASS]
  → Netlify busca archivo estático: public/robots.txt → EXISTE → lo sirve
  → Status 200, Content-Type: text/plain
```

**Resultado:** `/robots.txt` sirve el archivo estático genérico. ✅ Funciona, pero es el mismo para TODOS los tenants.

### 2.2 Flujo de un request a `tienda.novavision.lat/sitemap.xml`

```
Request → Netlify CDN
  → Edge Function `maintenance` (path: /*)
    → url.pathname === '/sitemap.xml' → context.next() [BYPASS]
  → Netlify busca archivo estático: public/sitemap.xml → NO EXISTE
  → Netlify aplica _redirects: /*  /index.html  200
  → Status 200, Content-Type: text/html ← SIRVE LA SPA COMO SI FUERA SITEMAP
```

**🔴 P0:** `/sitemap.xml` retorna el HTML de la SPA con status 200. Googlebot lo interpreta como sitemap inválido. Esto NO es solo "no hay sitemap" — es un **sitemap envenenado** que Google intenta parsear y falla.

### 2.3 Flujo de un request a `tienda.novavision.lat/admin-dashboard`

```
Request → _redirects: /*  /index.html  200
  → SPA carga → React Router muestra AdminDashboard (con auth guard)
  → Google recibe 200 + HTML vacío (<div id="root">)
  → Si Google ejecuta JS: ve la página de login
```

**Problema:** Google puede intentar indexar `/admin-dashboard` (status 200, no hay robots block ni noindex).

### 2.4 Flujo de un 404 real (ej: `/pagina-que-no-existe`)

```
Request → _redirects: /*  /index.html  200
  → SPA carga → React Router: <NotFoundFallback>
  → Status HTTP: 200 ← INCORRECTO, debería ser 404
  → Google ve "página existe" con contenido inútil (soft 404)
```

**Problema:** Netlify **siempre retorna 200** por el catch-all. Google tiene que detectar "soft 404" por heurísticas, gastando crawl budget.

### 2.5 Custom domains — sin política de canonical/redirect

**Escenario actual:**
- `modafit.novavision.lat` sirve la misma app que `modafit.com`
- Ambos retornan **status 200 con el mismo HTML** (meta genéricos de NovaVision)
- **No hay `<link rel="canonical">`**
- **No hay redirect 301** de un dominio al otro
- **Google ve contenido duplicado** sin señal de cuál es el primario

**Política necesaria (una de las dos):**
- **Opción A (recomendada):** Custom domain es el canónico. `modafit.novavision.lat` hace 301 → `modafit.com`
- **Opción B:** Subdominio es canónico. `modafit.com` es alias con canonical apuntando a subdominio.

---

## 3. Estado Actual SEO — Diagnóstico Corregido

> **Nota de revisión:** El diagnóstico anterior decía "SEO inexistente". Corrección: **"SEO técnico incompleto + CSR puro sin head dinámico"**.
>
> Google hoy **sí renderiza JS** (Web Rendering Service). El SPA no es un bloqueante absoluto de indexación. Los problemas reales son: **descubrimiento (sitemap + robots)**, **duplicados (canonical + custom domains)**, **social previews (OG/Twitter)**, y **control de indexación (preview/draft)**.

### Lo que funciona

| Aspecto | Estado | Evidencia |
|---------|--------|-----------|
| Pipeline de imágenes | ✅ Bueno | `sharp` → webp/avif, `<picture>` sources, variantes por size |
| URLs limpias | ✅ OK | `/p/:id`, `/search` (aunque `/p/:id` es mejorable con slug) |
| Resolución tenant (subdominios) | ✅ Funciona | `slug.novavision.lat` → extraído correctamente |
| Backend multi-tenant | ✅ Robusto | Guard con 3 métodos de resolución, gating por status |
| Planes + entitlements | ✅ Completo | `custom_domain: true` para Growth+, feature gating |
| robots.txt servido | ✅ Parcial | Archivo estático existe, edge function lo deja pasar |

### Lo que NO funciona

| Aspecto | Problema real | Severidad |
|---------|--------------|-----------|
| Custom domains en frontend | **Roto** — devuelve "Tienda no encontrada" | 🔴 P0 Funcional |
| `/sitemap.xml` | Retorna `index.html` como HTML con 200 (sitemap envenenado) | 🔴 P0 SEO |
| Preview/staging indexable | Sin `X-Robots-Tag`, sin `noindex`, sin context de deploy | 🔴 P0 Higiene |
| Canonical links | Inexistentes → duplicate content subdomain/custom domain | 🔴 P0 SEO |
| Meta tags | Hardcodeados "NovaVision" genérico en todas las tiendas | 🟡 P1 SEO |
| Structured data | Cero JSON-LD | 🟡 P1 SEO |
| Social previews (OG/Twitter) | Genéricos — WhatsApp/FB siempre muestran "NovaVision" | 🟡 P1 |
| Analytics | Sin GA4, GTM, Search Console | 🟡 P1 Operación |
| 404 handling | Soft 404 (200 status) por catch-all SPA | 🟡 P1 |
| Cache headers | Sin optimizar — solo maintenance tiene no-store | 🟠 P2 |

---

## 4. Hallazgos Priorizados (P0/P1/P2)

### P0 — Bloquean funcionalidad o causan daño real

| # | Hallazgo | Impacto | Evidencia |
|---|----------|---------|-----------|
| P0-1 | **Custom domains rotos en frontend** | Tiendas Growth/Enterprise con custom domain → pantalla de error | `tenantResolver.js` → retorna `null` para hostnames de 2 partes |
| P0-2 | **`/sitemap.xml` sirve HTML con 200** | Google recibe sitemap corrupto → error en Search Console | `_redirects: /* /index.html 200` + no existe `sitemap.xml` estático |
| P0-3 | **Preview/staging sin noindex** (global, no feature) | Tiendas draft/preview pueden indexarse → daño reputacional | Sin `[context.deploy-preview]` en `netlify.toml`, sin meta robots |
| P0-4 | **Sin canonical + sin redirect entre subdomain/custom domain** | Contenido duplicado permanente → dilución de autoridad | `grep -r "canonical" src/` → vacío |
| P0-5 | **Rutas privadas indexables** (`/admin-dashboard`, `/cart`, `/profile`) | Google intenta indexar páginas de admin/usuario | `robots.txt` sin `Disallow:` para estas rutas, SPA retorna 200 |

### P1 — Alto impacto SEO (servicio vendible)

| # | Hallazgo | Impacto |
|---|----------|---------|
| P1-1 | **Meta tags hardcodeados** "NovaVision" en todas las tiendas | Cada tienda pierde identidad en SERPs |
| P1-2 | **Social previews genéricos** (OG/Twitter) | WhatsApp/FB/Twitter muestran "NovaVision" al compartir producto |
| P1-3 | **Sin sitemap por tenant** | Google no puede descubrir páginas de las tiendas |
| P1-4 | **Structured data (JSON-LD) inexistente** | Sin rich snippets en SERPs (precio, stock, review) |
| P1-5 | **Analytics inexistente** (GA4/GTM/GSC) | Imposible medir impacto SEO |
| P1-6 | **URLs `/p/:id` sin slug semántico** | URL no descriptiva, pierde señal de relevancia |
| P1-7 | **Soft 404 (200 status)** en páginas inexistentes | Crawl budget desperdiciado |

### P2 — Mejora continua

| # | Hallazgo | Impacto |
|---|----------|---------|
| P2-1 | Cache headers sin optimizar | TTFB alto, repeat visits lentos |
| P2-2 | Imágenes sin `loading="lazy"` / `sizes` / `fetchpriority` | CWV penalizado |
| P2-3 | Font loading sin optimizar | CLS por FOIT/FOUT |
| P2-4 | Bundle splitting default | Admin code cargado en storefront público |
| P2-5 | Blog/CMS inexistente | Sin páginas de contenido para long tail |
| P2-6 | Breadcrumbs inexistentes | Estructura de navegación invisible para Google |
| P2-7 | Manifest PWA genérico ("NovaVision") | Install prompt con branding incorrecto |

---

## 5. Matriz Riesgo vs Impacto (corregida)

```
IMPACTO →
  ▲ ALTO  │ P0-1(custom dom) P0-2(sitemap/html) P0-4(canonical)
          │ P1-1(meta)       P1-2(social)        P1-3(sitemap real)
          │
  MEDIO   │ P0-3(noindex)    P0-5(rutas priv.)   P1-4(schema)
          │ P1-5(analytics)  P1-6(url slugs)     P1-7(soft 404)
          │
  BAJO    │ P2-1(cache)      P2-4(bundle)        P2-7(manifest)
          │ P2-2(img)        P2-3(fonts)         P2-5(blog)
          └───────────────────────────────────────────────→
            BAJO             MEDIO               ALTO
                      ← RIESGO DE IMPLEMENTACIÓN
```

**Lectura:**
- **Cuadrante ALTO impacto / BAJO riesgo:** noindex preview, robots Disallow, redirect de `_redirects`, canonical policy → **Hacer PRIMERO (Fase 0)**
- **Cuadrante ALTO impacto / MEDIO riesgo:** Custom domains fix, meta dinámicos, sitemap por tenant → **Fase 0-1**
- **Cuadrante ALTO impacto / ALTO riesgo:** Edge meta injection para social crawlers → **Fase 1-2 con cache strategy**
- **Cuadrante BAJO impacto / BAJO riesgo:** Cache headers, manifest → **Quick wins entre fases**

---

## 6. Análisis por Dominio SEO

### 6.1 Indexación y Rastreo

| Aspecto | Estado | Detalle |
|---------|--------|---------|
| `robots.txt` | ⚠️ Deficiente | Existe pero genérico, sin `Sitemap:`, sin `Disallow:` para rutas privadas |
| `/sitemap.xml` | 🔴 ROTO | Retorna `index.html` como HTML con 200 (catch-all SPA) |
| Canonical | ❌ No existe | Riesgo duplicados subdomain/custom domain |
| 404 handling | ⚠️ Soft 404 | SPA retorna 200 siempre → Google ve "soft 404" |
| `noindex` en preview | ❌ No existe | Sin X-Robots-Tag, sin context de deploy |
| `noindex` en rutas privadas | ❌ No existe | `/admin-dashboard`, `/cart`, `/profile` son indexables |

### 6.2 Rendering

| Aspecto | Estado | Realidad |
|---------|--------|---------|
| Tipo | CSR puro (SPA React) | Google **sí renderiza JS** (WRS), pero con delay y crawl budget extra |
| HTML inicial | `<div id="root"></div>` | Bots que no ejecutan JS (FB, Twitter, WhatsApp) → ven vacío |
| SSR/SSG/prerender | No existe | No es bloqueante para Google, pero sí para social crawlers |
| Helmet/head manager | No existe | `document.title` NUNCA cambia |

### 6.3 Structured Data

| Schema | Estado |
|--------|--------|
| Product | ❌ No existe |
| Organization | ❌ No existe |
| Website + SearchAction | ❌ No existe |
| BreadcrumbList | ❌ No existe |
| FAQ | ❌ No existe |

### 6.4 Performance

| Aspecto | Estado | Nota |
|---------|--------|------|
| Image pipeline | ✅ Bueno | sharp → webp/avif, `<picture>` |
| Image lazy loading | ❌ No implementado | Sin `loading="lazy"` |
| Image sizes/srcset | ⚠️ Parcial | `<picture>` sources sin `sizes` attr |
| LCP optimization | ❌ | Sin `fetchpriority="high"` |
| Cache headers | ❌ | Sin headers para assets estáticos fingerprinteados |
| Bundle splitting | ❌ Default Vite | Admin code en bundle público |
| Font strategy | ❌ | Sin preload |

### 6.5 Analytics

| Aspecto | Estado |
|---------|--------|
| GA4 | ❌ No existe |
| Search Console | ❌ Sin verificación |
| GTM | ❌ No existe |
| E-commerce events | ❌ No existe |
| RUM / CWV tracking | ❌ No existe |

---

## 7. Recomendación SSR/Prerender (revisada)

### Corrección de criterio del TL

> Google renderiza JS. No es "no indexa nada". El problema real es:
> 1. **Descubrimiento** (sitemap/robots) → se resuelve sin SSR
> 2. **Duplicados** (canonical/redirects) → se resuelve sin SSR
> 3. **Social crawlers** (OG/Twitter) → requiere ayuda (edge o prerender)
> 4. **Control de indexación** (noindex) → se resuelve sin SSR

### Riesgo de dynamic rendering / cloaking

Si servís HTML **diferente** solo a bots (ej: con meta tags que los humanos no ven porque el SPA los sobreescribe), estás en zona de **dynamic rendering**. Google lo permite **siempre que el contenido sea el mismo**. La regla:

- ✅ OK: Inyectar `<title>`, `<meta>`, `<link rel="canonical">`, JSON-LD que **coinciden** con lo que la SPA renderiza
- ❌ Riesgo: Inyectar contenido textual visible (párrafos, títulos) que la SPA no muestra al usuario
- ❌ Cloaking: Servir páginas completamente diferentes

### Riesgo de cache multi-tenant en edge

Cualquier edge function que cachee HTML DEBE variar por **Host**. Si no:
- `tiendaA.novavision.lat` cachea HTML con meta de tiendaA
- `tiendaB.novavision.lat` recibe el HTML cacheado de tiendaA → **cross-tenant HTML leak** (P0 seguridad)

**Requisito:** Cache key DEBE incluir `Host` + `pathname`. O directamente **no cachear HTML** y solo cachear la respuesta del API `/seo/meta`.

### Estrategia recomendada (en orden)

1. **PRIMERO:** `react-helmet-async` para titles/meta/canonical dinámicos → funciona para Google (que ejecuta JS) y mejora UX
2. **SEGUNDO:** Edge function SOLO para social crawlers (FB/Twitter/WhatsApp) que NO ejecutan JS → inyecta OG/Twitter meta en el HTML estático
3. **OPCIONAL (futuro):** Prerender service para money pages si Search Console muestra problemas de rendering

---

## 8. Supuestos y Evidencia Pendiente

| # | Supuesto | Evidencia necesaria | Acción |
|---|----------|---------------------|--------|
| S1 | Netlify sirve 1 sitio para todas las tiendas (wildcard `*.novavision.lat`) | Captura del dashboard Netlify → Domain management | TL confirma |
| S2 | Custom domains se agregan como domain aliases en el mismo sitio | Config Netlify + DNS records | TL confirma |
| S3 | Branch deploys de `onboarding-preview-stable` tienen URL tipo `onboarding-preview-stable--sitename.netlify.app` | Verificar URL de branch deploy | TL confirma |
| S4 | No hay CDN adicional (Cloudflare) entre Netlify y usuario | DNS setup | TL confirma |
| S5 | **Custom domains NO funcionan actualmente en producción** (por bug en tenantResolver) | Probar `curl -I mitienda.com` si existe alguno configurado | TL prueba |
| S6 | Google actualmente indexa las tiendas vía JS rendering (WRS) | Buscar `site:slug.novavision.lat` + Inspect URL en GSC | TL verifica |
| S7 | Search Console no tiene propiedades registradas | Verificar acceso a GSC | TL confirma |

### Checks de realidad pendientes (recomendados antes de Fase 0)

1. **`site:slug.novavision.lat`** en Google con un tenant real → ¿qué titles muestra? ¿cuántas páginas?
2. **"View Source"** en producción → confirmar que Google ve `<div id="root"></div>` vacío
3. **"Inspect URL"** en Search Console (si hay propiedad) → ¿Google renderiza los productos?
4. **Facebook Sharing Debugger** con URL de producto → ¿qué OG data ve?
5. **Compartir en WhatsApp** un link de producto → ¿qué preview muestra?

# SEO Fase 1 — Implementación completa (Backend + Frontend + Infra)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` → commit `e6de8fc`
  - Web: `feature/multitenant-storefront` → commit `161727d`
  - Admin: `feature/automatic-multiclient-onboarding` → commit `7cc23f5`

---

## Archivos modificados

### API (templatetwobe)
| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `migrations/backend/20260212_seo_settings.sql` | NEW | Migración: tabla seo_settings, columnas SEO en products/categories, backfill slugs, RLS |
| `src/seo/seo.module.ts` | NEW | Módulo NestJS |
| `src/seo/seo.controller.ts` | NEW | 4 endpoints: GET/PUT settings, GET/PUT meta/:entity/:id |
| `src/seo/seo.service.ts` | NEW | CRUD Supabase con filtro client_id |
| `src/seo/dto/update-seo-settings.dto.ts` | NEW | DTO con validación (MaxLength 70/160, IsObject) |
| `src/seo/dto/update-entity-meta.dto.ts` | NEW | DTO para meta de entidades |
| `src/seo/dto/index.ts` | NEW | Barrel export |
| `src/app.module.ts` | MOD | +SeoModule + auth middleware excludes para GET /seo/* |
| `src/plans/featureCatalog.ts` | MOD | +6 SEO entries (3 live, 3 planned) + categoría 'seo' |

### Web (templatetwo)
| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/hooks/useSeoSettings.js` | NEW | Hook: GET /seo/settings, graceful 403/404 |
| `src/components/SEOHead/index.jsx` | NEW | Meta dinámicos por tenant: título, OG, Twitter, canonical, GA4, GTM |
| `src/components/SEOHead/ProductSEO.jsx` | NEW | Meta por producto: og:type=product, precio, slug canonical |
| `src/components/SEOHead/SearchSEO.jsx` | NEW | Meta por búsqueda: noindex en queries, indexable en categorías |
| `src/App.jsx` | MOD | +HelmetProvider + SEOHead global |
| `src/pages/ProductPage/index.jsx` | MOD | +ProductSEO |
| `src/pages/SearchPage/index.jsx` | MOD | +SearchSEO |
| `index.html` | MOD | Limpieza meta hardcoded "NovaVision" → fallbacks genéricos |
| `public/robots.txt` | MOD | +Disallow rutas privadas (9 paths) |
| `netlify.toml` | MOD | +noindex deploy-preview/branch-deploy, cache /assets/*, CSP GA4 |
| `public/_redirects` | MOD | +/sitemap.xml → 404 (evita SPA HTML) |
| `package.json` | MOD | +react-helmet-async@^2.0.5 |

### Admin (novavision)
| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/utils/featureCatalog.ts` | MOD | +categoría 'seo' en type FeatureCategory |

---

## Resumen del cambio

Implementación completa de SEO Fase 1 para NovaVision multi-tenant:

### Backend
- **Tabla `seo_settings`**: configuración SEO por tenant (site_title, meta_description, og_image, favicon_url, ga4_measurement_id, gtm_container_id, google_search_console_id, custom_meta JSONB)
- **Columnas SEO en `products`**: slug (auto-generado, UNIQUE por client_id), meta_title, meta_description, noindex
- **Columnas SEO en `categories`**: slug, meta_title, meta_description
- **RLS**: 5 políticas por tabla (tenant select, admin insert/update, server bypass)
- **Módulo NestJS**: Controller con gating por plan (growth+enterprise), Service con Supabase
- **Feature catalog**: 6 features SEO registradas

### Frontend (Storefront)
- **react-helmet-async**: gestión dinámica de `<head>` sin re-renders innecesarios
- **SEOHead**: meta dinámicos por tenant (título tienda, OG, Twitter Card, canonical con store domain, favicon, inyección GA4/GTM/Search Console)
- **ProductSEO**: og:type=product con precio/disponibilidad, canonical con slug del producto
- **SearchSEO**: noindex en búsquedas por query, indexable en navegación por categoría
- **robots.txt**: Disallow para 9 rutas privadas
- **netlify.toml**: Preview/branch deploys no indexables, cache inmutable para assets, CSP para GA4

### Fixes P0 aplicados
- **P0-2**: /sitemap.xml retorna 404 en vez de HTML del SPA
- **P0-3**: Deploy previews y branch deploys no son indexables (X-Robots-Tag: noindex)
- **P0-5**: Rutas privadas bloqueadas en robots.txt

---

## Por qué

Los stores NovaVision no tenían ningún soporte SEO: meta tags hardcoded con "NovaVision", sin OG/Twitter dinámicos, rutas privadas indexables, previews indexables, sin analytics. Esta implementación cubre los P0 críticos y establece la infraestructura (tabla, endpoints, componentes) para las fases siguientes.

---

## Cómo probar

### Backend
```bash
cd apps/api && npm run start:dev

# Obtener settings SEO (requiere plan growth+)
curl -H "x-client-id: <CLIENT_UUID>" \
     -H "Authorization: Bearer <JWT>" \
     http://localhost:3000/seo/settings

# Actualizar settings (admin)
curl -X PUT http://localhost:3000/seo/settings \
  -H "Content-Type: application/json" \
  -H "x-client-id: <CLIENT_UUID>" \
  -H "Authorization: Bearer <JWT_ADMIN>" \
  -d '{"site_title":"Mi Tienda","meta_description":"Descripción","ga4_measurement_id":"G-XXXXXXX"}'

# Meta de un producto
curl -H "x-client-id: <CLIENT_UUID>" \
     -H "Authorization: Bearer <JWT>" \
     http://localhost:3000/seo/meta/products/<PRODUCT_ID>
```

### Frontend
```bash
cd apps/web && npm run dev
# Abrir http://localhost:5173?tenant=<slug>
# Inspeccionar <head> → debe tener título dinámico, OG tags, canonical
# Navegar a producto → meta title cambia, og:type=product
# Buscar → meta noindex en query, indexable en categoría
```

### Verificar robots.txt
```
https://<domain>/robots.txt → Debe mostrar Disallow para rutas privadas
```

### Verificar noindex en previews
Deploy previews de Netlify deben tener header `X-Robots-Tag: noindex, nofollow`

---

## Notas de seguridad
- La migración fue ejecutada directamente contra la DB de producción (Supabase backend). Verificado: tabla creada, columnas añadidas, 28/28 slugs backfilled, RLS activo.
- Los endpoints GET de SEO son públicos (excluidos de auth middleware) pero gatados por plan via PlanFeature guard.
- GA4/GTM IDs se inyectan client-side desde seo_settings → no hay exposición de keys de servicio.
- SERVICE_ROLE_KEY no se usa/expone en el frontend.

---

## Fase 2 pendiente
- Sitemap XML dinámico por tenant (`seo.sitemap`)
- JSON-LD structured data (`seo.schema`)
- Gestor de redirecciones 301 (`seo.redirects`)
- Admin UI panel para configurar SEO
- Edge function para OG injection (social crawlers no ejecutan JS)
- robots.txt dinámico por tenant
- Canonical redirect strategy para custom domains (P0-1)

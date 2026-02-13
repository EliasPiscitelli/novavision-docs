# SEO Fase 2 — Admin Panel + OG Edge Function + Redirects CRUD

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` → commit `5144bcb` → develop `fb6fabd`
  - Web: `feature/multitenant-storefront` → commit `4e0ea10` → develop `b77f75e`
  - Admin: `feature/automatic-multiclient-onboarding` → commit `1d84b11` → develop `645ba16`

---

## Resumen

Cierre completo de SEO Fase 2. Tres entregables que completan los pendientes:

### 1. Panel SEO en Admin (super admin)

- **Nueva vista** `SeoView.jsx` accesible en `/dashboard/seo`
- Selector de cliente (dropdown) + formulario de configuración SEO por tenant
- Campos: `site_title`, `site_description`, `brand_name`, `og_image_default`, `favicon_url`, `ga4_measurement_id`, `gtm_container_id`, `search_console_token`, `product_url_pattern`
- Contadores de caracteres para title (70) y description (160)
- Comunicación multi-tenant vía header `x-tenant-slug`
- Toast feedback para éxito/error
- NAV_ITEM en categoría `operations` con `superOnly: true`

### 2. Edge Function `og-inject` (social bot pre-rendering)

- Detecta 14+ user agents de bots sociales (Facebook, WhatsApp, Twitter, LinkedIn, Telegram, Discord, etc.)
- Para bots: llama `GET /seo/og?path=...` al backend y construye HTML mínimo con:
  - Open Graph meta tags
  - Twitter Cards
  - JSON-LD (Product u Organization según la ruta)
- Para usuarios normales: pass-through transparente (`context.next()`)
- Cache: 5min browser + 10min CDN (`s-maxage`)
- Registrada en `netlify.toml` encadenada después de `maintenance`

### 3. Redirects CRUD (backend, enterprise-only)

- **Migración:** tabla `seo_redirects` con:
  - `from_path`, `to_url`, `redirect_type` (301/302), `active`, `hit_count`
  - UNIQUE(client_id, from_path), índice para lookups activos
  - RLS: service_role bypass + tenant select + admin write
- **DTOs:** `CreateRedirectDto`, `UpdateRedirectDto` (class-validator)
- **Endpoints:** GET/POST/PUT/DELETE `/seo/redirects` gated por `@PlanFeature('seo.redirects')` — enterprise only
- **OG endpoint:** `GET /seo/og?path=...` público (sin auth) para la edge function
- **Feature catalog:** `seo.redirects` actualizado a status `live`
- **Auth exclude:** `/seo/og` GET excluido de AuthMiddleware

---

## Archivos Modificados

### API (`templatetwobe`)
| Archivo | Cambio |
|---------|--------|
| `migrations/backend/20260212_seo_redirects.sql` | **Nuevo** — DDL tabla + RLS |
| `src/seo/dto/redirect.dto.ts` | **Nuevo** — DTOs Create/Update |
| `src/seo/dto/index.ts` | Exports de redirect DTOs |
| `src/seo/seo.service.ts` | Métodos: `getOgData`, `getRedirects`, `createRedirect`, `updateRedirect`, `deleteRedirect` |
| `src/seo/seo.controller.ts` | Endpoints: OG + Redirects CRUD |
| `src/app.module.ts` | Auth exclude para `/seo/og` |
| `src/plans/featureCatalog.ts` | `seo.redirects` → `live` |

### Web (`templatetwo`)
| Archivo | Cambio |
|---------|--------|
| `netlify/edge-functions/og-inject.ts` | **Nuevo** — Edge function pre-render |
| `netlify.toml` | Registro edge function `og-inject` en `/*` |

### Admin (`novavision`)
| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/SeoView.jsx` | **Nuevo** — Vista completa |
| `src/pages/AdminDashboard/index.jsx` | NAV_ITEM + import FaGlobe |
| `src/App.jsx` | Ruta `/dashboard/seo` + import SeoView |

---

## Cómo Probar

### Admin Panel
1. Loguearse como super admin en `/login`
2. Ir a Dashboard → "SEO" en el sidebar
3. Seleccionar un cliente del dropdown
4. Verificar que carguen los settings actuales
5. Modificar un campo (ej. `site_title`) y guardar → verificar toast y persistencia

### OG Edge Function
1. Asegurar variable `BACKEND_API_URL` configurada en Netlify env
2. Testear con curl simulando un bot:
   ```bash
   curl -H "User-Agent: facebookexternalhit/1.1" https://{slug}.novavision.lat/p/{product-id}/slug
   ```
3. Verificar que retorna HTML con `<meta property="og:title">`
4. Testear sin bot UA → verificar que retorna el SPA normal

### Redirects CRUD
1. Ejecutar migración: `psql "$BACKEND_DB_URL" -f migrations/backend/20260212_seo_redirects.sql`
2. Como admin de un tenant enterprise:
   ```bash
   curl -X POST /seo/redirects -H "Authorization: Bearer ..." -H "x-client-id: ..." \
     -d '{"from_path": "/old-page", "to_url": "/new-page", "redirect_type": 301}'
   ```
3. GET/PUT/DELETE para validar CRUD completo
4. Verificar que tenants no-enterprise reciben 403

---

## Notas de Seguridad

- `GET /seo/og` es público (sin auth) para que la edge function pueda llamarlo sin JWT. Solo devuelve datos públicos (título, OG image, precio). No expone datos sensibles.
- Redirects gated por `PlanAccessGuard` + `RolesGuard` → solo admins de tenants enterprise.
- Edge function NO almacena estado; todo se consulta al backend en cada request de bot.

---

## Migración Pendiente

⚠️ Ejecutar en producción:
```bash
psql "$BACKEND_DB_URL" -f migrations/backend/20260212_seo_redirects.sql
```

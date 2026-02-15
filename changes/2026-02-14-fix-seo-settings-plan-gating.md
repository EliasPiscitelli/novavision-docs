# Fix: Skip SEO settings fetch for plans without SEO feature

- **Autor:** agente-copilot
- **Fecha:** 2026-02-14
- **Rama:** develop (web storefront)
- **Archivos:** 
  - `apps/web/src/hooks/useSeoSettings.js`
  - `apps/web/src/components/SEOHead/index.jsx`

## Resumen

El hook `useSeoSettings` llamaba incondicionalmente a `GET /seo/settings` en cada mount de `SEOHead`. Para tenants con plan `starter` (que no tienen la feature de SEO), el backend devolvía un 403 `FEATURE_GATED`. Este request innecesario podía causar errores de CORS en cascada cuando la validación de origen async del backend tenía latencia, rompiendo la carga completa de la tienda (sin productos, sin datos).

## Cambios

### `useSeoSettings.js`
- Se agregó parámetro `{ enabled = true }` al hook
- Cuando `enabled === false`, el hook retorna `{ seo: null, loading: false, error: null }` inmediatamente sin hacer ningún request HTTP
- Se agregó `enabled` a la dependency array del `useEffect`

### `SEOHead/index.jsx`
- Se calcula `seoEnabled` basado en `tenant?.plan`: solo es `true` para planes `growth` y `enterprise`
- Se pasa `{ enabled: seoEnabled }` a `useSeoSettings()`
- Para plan `starter`: no se hace el request, se usan los fallbacks (nombre del tenant, logo, etc.)

## Por qué

- **Problema directo:** El request a `/seo/settings` retornaba 403 para plan `starter`, request innecesario que puede causar cascada de errores CORS
- **Impacto:** La tienda e2e-alpha (starter) quedaba completamente rota — no mostraba productos ni datos
- **Solución:** No hacer el request si el plan no tiene la feature, evitando el error 403 en origen

## Feature Catalog (backend reference)

| Feature ID | starter | growth | enterprise |
|---|---|---|---|
| `seo.settings` | ❌ | ✅ | ✅ |
| `seo.entity_meta` | ❌ | ✅ | ✅ |

## Cómo probar

1. Levantar web: `npm run dev`
2. Ir a `?tenant=e2e-alpha` (plan starter) → NO debe haber request a `/seo/settings` en Network tab
3. Ir a `?tenant=e2e-beta` (plan growth) → SÍ debe hacer request a `/seo/settings`
4. En ambos casos los productos y la tienda deben cargar correctamente

## Notas de seguridad

- No aplica — es un cambio de optimización/UX, no toca autenticación ni datos
- El backend sigue protegido por `PlanAccessGuard` como defensa en profundidad

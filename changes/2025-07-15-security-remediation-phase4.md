# Cambio: Remediación de Seguridad — Phase 4

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding
- **Rama Web:** develop → cherry-pick a feature/multitenant-storefront
- **Rama Docs:** main

## Archivos Modificados

### Admin (novavision)
- `src/hooks/usePalettes.ts` — Reemplazo de `localStorage.getItem("token")` por `supabase.auth.getSession()`

### Web (templatetwo)
- `public/_headers` — Limpieza de CSP comentada/obsoleta → redirección a `netlify.toml`

### Docs (novavision-docs)
- `audit/SECURITY_AUDIT_2025-07-14.md` — Actualización de checklist y hallazgos Phase 4

## Resumen de Cambios

### H-18 · Legacy token en usePalettes.ts — ✅ RESUELTO

**Problema:** `usePalettes.ts` usaba `localStorage.getItem("token")` para obtener el JWT de autenticación. Esa key nunca es escrita por ningún otro archivo del proyecto, resultando en `Authorization: Bearer null`. Vector de riesgo: un atacante que logre XSS podría escribir en esa key y redirigir requests.

**Solución:**
- `getAuthContext()` ahora es `async` y usa `supabase.auth.getSession()` → `session.access_token`
- Los 4 puntos de llamada actualizados a `await getAuthContext()`
- Import de `supabase` agregado desde `../services/supabase`

**Nota:** `IdentitySettingsTab.tsx` también tenía `localStorage.getItem("token")` en líneas 168 y 190, pero es **código muerto** — no está importado en ningún componente del proyecto. No requiere corrección.

### H-29 · _headers file en Web — ✅ RESUELTO

**Problema:** `public/_headers` contenía 3 líneas comentadas con CSP obsoleta incluyendo:
- `Access-Control-Allow-Origin: *`
- `localhost:3000` y `templatetwobe` en connect-src

**Solución:** Reemplazado por comentario que redirige a `netlify.toml` como fuente autoritativa de headers.

### H-25 · CASCADE DELETE — ⚠️ RIESGO ACEPTABLE (re-evaluado)

**Evaluación detallada:**
- Tablas de config (logos, faqs, contact_info, seo_settings, social_links, services) → CASCADE. Aceptable para datos satelitales fácilmente recreables.
- Tablas M:N (product_categories) → CASCADE. Patrón correcto.
- **Tablas críticas** (orders, payments, products, cart_items, users) → `NO ACTION`. **Bloquean la eliminación.** El riesgo real es significativamente menor al evaluado originalmente.
- Algunos FKs duplicados detectados (2 constraints apuntando a la misma relación) — no son un riesgo de seguridad. Mejora futura de limpieza.

### H-27 · Rate limiting en uploads — ⚠️ MITIGADO

**Evaluación detallada:**
- **Existe** rate limiting global activo: `rate-limit.middleware.ts` (Express middleware usando `rate-limiter-flexible`, in-memory). Protege TODOS los endpoints, incluyendo upload.
- **Código muerto:** NestJS `ThrottlerGuard` (`rate-limiter.guard.ts`) NO está registrado en ningún módulo. `ThrottlerModule` no tiene consumers. No afecta la seguridad ya que el middleware global ES el mecanismo activo.
- Mejora futura: rate limiting diferenciado por ruta (más restrictivo en uploads).

## Cómo Probar

### Admin — usePalettes.ts
1. Levantar Admin: `npm run dev`
2. Navegar al Builder → PaletteSelector
3. Verificar que las paletas se cargan correctamente (deben usar JWT de la sesión Supabase)
4. Inspeccionar Network tab: `Authorization: Bearer <token-real>` (NO `null`)

### Web — _headers
1. Deploy a Netlify (o verificar local) → revisar que los headers de `netlify.toml` se aplican
2. `cat public/_headers` → solo debe contener el comentario de redirección

### Validación de builds
```bash
# Admin
cd apps/admin && npx tsc --noEmit --project tsconfig.typecheck.json  # ✅ Sin errores

# Web
cd apps/web && npx tsc --noEmit --project tsconfig.typecheck.json    # ✅ Sin errores
```

## Notas de Seguridad

- `usePalettes.ts` ahora usa el canal estándar de autenticación (`supabase.auth.getSession()`) en vez de un token artesanal inexistente
- `_headers` ya no contiene CSP obsoleta que podría confundir a desarrolladores futuros
- Los hallazgos H-25 y H-27 se re-evaluaron con análisis de código/DB y se clasificaron como riesgo aceptable con mitigaciones existentes

## Hallazgos Restantes (para planificación futura)

| Hallazgo | Prioridad | Estado | Notas |
|----------|-----------|--------|-------|
| H-01 | P0 | Pendiente | Email hardcoded en ~78 RLS policies. Requiere sprint dedicado. |
| H-09 | P0 | Diferido | `internal_key` en sessionStorage. Cross-origin httpOnly cookie complejo (Safari ITP, SameSite=None). |
| H-16 | P1 | Mitigado | `builder_token` en localStorage usado activamente en ClientCompletionDashboard. Tiene cleanup en Web StorefrontAdminGuard. |
| H-24 | P2 | Pendiente | Webhook backoff no exponencial. |
| H-30/31/32 | P3 | Pendiente | Items de bajo riesgo. |

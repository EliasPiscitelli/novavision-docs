# Cambio: Migración a api.novavision.lat + httpOnly cookie para internal_key

- **Autor:** agente-copilot
- **Fecha:** 2026-02-17
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` → `32968c8`
  - Admin: `feature/automatic-multiclient-onboarding` → `d6394f9`
  - Web: `feature/multitenant-storefront` → `831321a` (cherry-pick a develop: `45c93bd`)

## Archivos modificados

### API (templatetwobe)
- `src/main.ts` — CSP connectSrc fallback actualizado
- `src/auth/auth.controller.ts` — Nuevos endpoints verify/revoke internal_key cookie + lectura de cookie en Google OAuth callback
- `src/guards/super-admin.guard.ts` — Lectura de cookie `nv_ik` con fallback a header

### Admin (novavision)
- `src/services/api/nestjs.js` — PROD_URL actualizada + withCredentials: true
- `src/pages/LoginPage/index.jsx` — Flujo httpOnly cookie reemplaza sessionStorage
- `src/components/SuperAdminVerifyModal.jsx` — Validación via API + cookie
- `src/pages/BuilderWizard/steps/Step7MercadoPago.tsx` — URL fallback actualizada
- `src/pages/OAuthCallback/index.jsx` — Removido internal_key del body + credentials: include
- `netlify.toml` — CSP connect-src actualizada

### Web (templatetwo)
- `src/api/client.ts` — URL fallback actualizada
- `netlify.toml` — CSP connect-src actualizada

## Resumen de cambios

### 1. Migración de dominio
Todas las referencias a `novavision-production.up.railway.app` fueron reemplazadas por `api.novavision.lat`. Esto incluye:
- URLs de API en código frontend (Admin y Web)
- CSP headers en netlify.toml (Admin y Web) 
- CSP fallback en main.ts del API
- Variables de entorno locales (.env, gitignored)

### 2. httpOnly cookie para internal_key (H-09)
El `internal_key` (clave de verificación super_admin) se migró de sessionStorage + header `x-internal-key` a una cookie httpOnly:
- **Cookie:** `nv_ik`, httpOnly, secure (prod), sameSite: none (prod), domain: .novavision.lat, maxAge: 24h
- **Nuevos endpoints:** `POST /auth/internal-key/verify` (set cookie) y `POST /auth/internal-key/revoke` (clear cookie)
- **Guard:** Lee `request.cookies['nv_ik']` primero, fallback a `request.headers['x-internal-key']` (backwards compat)
- **Frontend:** Ya no almacena el secreto; solo guarda flag `internal_key_set` en sessionStorage

## Por qué
- **Dominio propio:** `api.novavision.lat` es más profesional, permite cookies cross-subdomain con `.novavision.lat`, y desacopla de la URL interna de Railway.
- **httpOnly cookie:** El internal_key en sessionStorage era accesible via XSS (hallazgo H-09 de la auditoría de seguridad). La cookie httpOnly no es accesible desde JavaScript.

## Cómo probar
1. Verificar que `https://api.novavision.lat/healthz` responda OK (requiere fix de puerto en Railway: 8070 → 3000)
2. Login en Admin → verificar que la cookie `nv_ik` se setea (DevTools → Application → Cookies)
3. Operaciones super_admin (crear cliente, etc.) deben funcionar sin header manual
4. Google OAuth callback debe funcionar correctamente

## Pasos manuales pendientes (usuario)
1. **Railway:** Cambiar target port de `api.novavision.lat` de 8070 a 3000
2. **Railway env vars:** `BACKEND_URL=https://api.novavision.lat`, `PUBLIC_BASE_URL=https://api.novavision.lat`, `MP_REDIRECT_URI=https://api.novavision.lat/mp/oauth/callback`
3. **Netlify env vars (Admin+Web):** Verificar/actualizar `VITE_BACKEND_API_URL=https://api.novavision.lat`

## Notas de seguridad
- La cookie usa `sameSite: 'none'` + `secure: true` en producción para permitir cross-origin entre `novavision.lat` (Admin) y `api.novavision.lat` (API)
- El guard mantiene backwards compatibility con el header `x-internal-key` por si hay clientes legacy; se puede remover en el futuro
- cookie-parser ya estaba activo globalmente en main.ts

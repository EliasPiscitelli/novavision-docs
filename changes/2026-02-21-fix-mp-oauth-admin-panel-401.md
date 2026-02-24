# Fix: MP OAuth 401 desde panel admin del storefront

- **Autor:** agente-copilot
- **Fecha:** 2026-02-21
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Web:** `develop`

## Problema

Al hacer click en "Conectar Ahora" en `PaymentsConfig` (panel admin del storefront), se abría:
```
https://api.novavision.lat/mp/oauth/start?client_id=24788979-53cf-4611-904d-e2ab5d07b8db
```
Esto retornaba `401 Missing authentication token` porque `window.open()` abre una pestaña nueva **sin headers de Authorization**.

### Causa raíz
Dos flujos de OAuth MP coexisten:
1. **Builder Wizard (onboarding):** usa `?token=<builderJWT>` como query param → funciona ✅
2. **Admin Panel (storefront):** hacía `window.open(url?client_id=xxx)` sin auth → 401 ❌

## Archivos modificados

### Backend (API)

| Archivo | Cambio |
|---------|--------|
| `src/mp-oauth/mp-oauth.service.ts` | Agregado `returnBaseUrl?` a `OAuthState`. Nuevo método `generateAuthUrlForClient(clientId, returnTo, returnBaseUrl?)` que resuelve `accountId` internamente vía `getAccountForClient()` y genera URL OAuth con PKCE. Callback ahora retorna `returnBaseUrl` del state. |
| `src/mp-oauth/mp-oauth.controller.ts` | Callback actualizado para usar `returnBaseUrl` del state Redis (redirige al storefront, no al admin). Nuevo endpoint `GET /mp/oauth/start-url` protegido con `@UseGuards(RolesGuard)` + `@Roles('admin', 'super_admin')`. Usa `req.clientId` del TenantContextGuard. |
| `src/auth/auth.middleware.ts` | Agregado `/mp/oauth/callback` a `PUBLIC_PATH_PREFIXES` (MP redirige sin headers). Cambiado prefix `/mp/oauth/start` → `/mp/oauth/start?` para no matchear accidentalmente con `/mp/oauth/start-url` por `startsWith`. |

### Frontend (Web)

| Archivo | Cambio |
|---------|--------|
| `src/services/payments.js` | Nueva función `getMpOauthStartUrl()` que llama a `GET /api/mp/oauth/start-url` vía axios (interceptor agrega JWT + `x-tenant-slug` automáticamente). |
| `src/components/admin/PaymentsConfig/index.jsx` | Botón "Conectar Ahora": reemplazado `window.open(url)` por `async fetch → window.location.href = authUrl`. Agregado `useEffect` para detectar `?mp_connected=true` al volver del callback OAuth, refrescar status de MP y mostrar toast de éxito. |

## Flujo corregido

```
Admin click "Conectar Ahora"
  → axios GET /api/mp/oauth/start-url (JWT + x-tenant-slug automáticos)
  → BE: req.clientId → accountId, genera state+PKCE, guarda en Redis (10min TTL)
  → FE: recibe { authUrl }, redirige con window.location.href
  → MP: usuario autoriza → redirige a /mp/oauth/callback?code=x&state=y
  → BE: valida state, intercambia code+PKCE por tokens, encripta AES-256-GCM, guarda
  → BE: redirige a {storefrontOrigin}/admin?tab=pagos&mp_connected=true
  → FE: useEffect detecta mp_connected, refresca getMpConnectionStatus(), toast ✅
```

## Notas de seguridad

- `GET /mp/oauth/start-url` requiere auth (JWT + tenant context) — NO está en rutas públicas
- `GET /mp/oauth/callback` está en rutas públicas (MP redirige sin headers) — protegido por state Redis + PKCE
- `GET /mp/oauth/start` (builder flow) sigue funcionando con `?token=<jwt>` — no se tocó ese flujo
- Se evitó que `/mp/oauth/start-url` matchee como ruta pública cambiando prefix a `/mp/oauth/start?`

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Web: `npm run dev` (terminal front)
3. Ir a panel admin → Pagos → "Conectar Ahora"
4. Debería redirigir a MercadoPago (sin 401)
5. Autorizar → debe volver al storefront con toast de éxito
6. Verificar estado "Conectado ✅" en sección MP

## Validación

- `npx tsc --noEmit` en API → sin errores ✅
- `npx tsc --noEmit` en Web → sin errores ✅

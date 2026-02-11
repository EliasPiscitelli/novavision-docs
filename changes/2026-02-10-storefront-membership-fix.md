# Cambio: Fix storefront membership check — Admin DB vs Backend DB

- **Autor:** agente-copilot
- **Fecha:** 2026-02-10
- **Rama:** feature/automatic-multiclient-onboarding
- **Commit:** ca97ef5

## Archivos modificados

- `src/common/membership.service.ts` — añadido `assertStorefrontMembership()`
- `src/client-dashboard/client-managed-domain.controller.ts` — cambiado a `assertStorefrontMembership`

## Resumen

El endpoint `/client/managed-domains` retornaba 401 "Access Denied" para usuarios de tienda (storefront) porque `assertMembership()` consultaba la tabla `users` de **Admin DB** buscando por Supabase Auth UID. Pero Admin DB tiene una identidad separada — los user IDs allí no coinciden con los UIDs de Supabase Auth.

**Ejemplo concreto (kaddocpendragon@gmail.com):**
- Supabase Auth UID: `038d70c0-c48f-4211-9ee0-d9a816888aa7`
- Admin DB `users.id`: `935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0` (DIFERENTE)
- Backend DB `users.id`: `038d70c0-c48f-4211-9ee0-d9a816888aa7` (CORRECTO)

## Por qué

El middleware de auth extrae el `userId` del JWT (Supabase Auth UID). `assertMembership` buscaba ese UID en Admin DB → no lo encontraba → 401.

## Solución

- Nuevo método `assertStorefrontMembership()` que consulta **Backend (Multicliente) DB** donde `users.id` = Supabase Auth UID.
- `assertMembership()` se mantiene para endpoints del admin panel (operan sobre Admin DB).
- El controller de managed-domains ahora usa `assertStorefrontMembership`.

## Cómo probar

```bash
# 1. Obtener token de prueba para kaddocpendragon
# 2. Llamar al endpoint
curl -X GET "https://novavision-production.up.railway.app/client/managed-domains" \
  -H "X-Tenant-Slug: qa-tienda-ropa" \
  -H "Authorization: Bearer <JWT>"
# Antes: 401 "Access Denied"
# Después: 200 con datos de dominio o 404 "No managed domain found"
```

## Notas de seguridad

- El check de membership sigue siendo estricto: verifica que `user.client_id === clientId` del tenant.
- Si no se encuentra el user en Backend DB: 401 (seguridad por obscuridad).
- Si el user pertenece a otro tenant: 403.
- No hay otros endpoints usando `assertMembership` para storefront users (verificado con grep).

## Investigación adicional: Admin icon en header

El admin icon (escudo/badge) en el header de la tienda **está presente y correcto** en el código desplegado:
- `DynamicHeader` resuelve al `HeaderFifth` (template_id="default" → fallback "fifth")
- `HeaderFifth` tiene `isAdminUser = role === "admin" || role === "super_admin"`
- El bundle desplegado en Netlify contiene el `AdminBadge` con `title="Administrador"`
- El `syncMembership` con `POST /auth/session/sync` está en el bundle
- El backend retorna `role: "admin"` para kaddocpendragon

**Si el usuario no ve el icon admin, debe:**
1. Cerrar sesión y re-loguearse con Google OAuth (regenera JWT con metadata actualizada)
2. Hard refresh (Cmd+Shift+R) para asegurar bundles frescos
3. Verificar en DevTools → Console que aparezca `[AuthProvider] Membership synced: role= admin`

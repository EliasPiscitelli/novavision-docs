# Cambio: resolución de cuenta para super admin en panel cliente

- Autor: GitHub Copilot
- Fecha: 2026-03-09
- Rama: feature/automatic-multiclient-onboarding

## Archivos modificados

- apps/api/src/db/db-router.service.ts
- apps/api/src/guards/client-dashboard.guard.ts
- apps/api/src/guards/builder-or-supabase.guard.ts
- apps/api/src/guards/client-dashboard.guard.spec.ts

## Resumen

Se corrigió la resolución de `account_id` para endpoints del panel cliente cuando el request entra con un usuario `super_admin` y un tenant explícito, por ejemplo vía `x-tenant-slug: farma`.

Además, se endureció el fallback para admins normales: si no existe vínculo por `user_id/email` en `nv_accounts`, el guard ahora puede resolver la cuenta a partir del `client_id` ya validado del contexto autenticado.

## Por qué

El panel cliente estaba asumiendo que todo usuario autenticado tenía una fila propia en `nv_accounts`. Eso no aplica al `super_admin` global. En esos casos el guard dejaba `req.account_id` vacío y controladores como `seo-ai/audit` terminaban respondiendo `No se pudo resolver la cuenta. Revisá la autenticación.` aunque el JWT fuera válido.

## Qué se cambió

- Se agregaron lookups centralizados de cuentas admin por `id`, `slug`, `client_id` y `user/email` en `DbRouterService`.
- `ClientDashboardGuard` ahora resuelve la cuenta objetivo con esta precedencia:
  1. `account_id` ya presente en la sesión.
  2. `x-tenant-slug` o `x-store-slug`.
  3. `client_id` resuelto del contexto autenticado.
  4. fallback histórico por `user_id/email`.
- La resolución por `slug` para usuarios no `super_admin` sólo se acepta si el `client_id` del tenant coincide con el `client_id` autenticado.
- `BuilderOrSupabaseGuard` quedó alineado con la misma lógica para no dejar rutas del onboarding/coupons/dev con comportamiento distinto.

## Cómo probar

En apps/api:

```bash
npm test -- --runInBand src/guards/client-dashboard.guard.spec.ts
npm run lint
npm run typecheck
npm run build
```

Smoke manual sugerido:

```bash
curl 'https://api.novavision.lat/seo-ai/audit' \
  -H 'authorization: Bearer <jwt-super-admin>' \
  -H 'x-tenant-slug: farma'
```

Resultado esperado:

- el endpoint ya no responde `No se pudo resolver la cuenta`;
- el request opera sobre la cuenta asociada al slug `farma`;
- un usuario no `super_admin` no puede apuntar a un slug ajeno si no coincide con su `client_id` autenticado.

## Notas de seguridad

- No se abrió acceso cross-tenant para admins comunes.
- El `super_admin` sólo puede cambiar de contexto cuando el tenant queda explícitamente resuelto por `slug` o `client_id`.
- La resolución sigue ocurriendo server-side contra `nv_accounts`; no se confía ciegamente en el slug del cliente sin lookup de base.
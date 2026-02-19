# Cambios: Security Hardening + PaymentsConfig Fixes + Ticket Limits

- **Autor:** agente-copilot
- **Fecha:** 2026-02-19
- **Ramas:** API/Admin: `feature/automatic-multiclient-onboarding` | Web: `feature/multitenant-storefront`

---

## Resumen

Sesión con 3 bloques principales de trabajo:

### 1. Feature: Ticket Limits (API + Admin)
- **API:** `src/support/support.service.ts`, `src/support/support-admin.controller.ts`, `migrations/admin/ADMIN_061_add_ticket_limit.sql`
- **Admin:** `src/pages/AdminDashboard/SupportConsoleView.jsx`
- Se agregó columna `ticket_limit` (default 5) en `nv_accounts` (Admin DB).
- El servicio de soporte ahora valida el límite antes de crear tickets.
- Nuevos endpoints: `GET/PATCH /support/admin/ticket-limit`.
- UI en SupportConsoleView para que super admin configure el límite por cliente.

### 2. Fixes Web: AnnouncementBar + PaymentsConfig
- **AnnouncementBar** (`src/components/AnnouncementBar/style.jsx`): `position: sticky`, `top: 0`, `z-index: 10001` — se ocultaba detrás del header.
- **PaymentsConfig** (`src/components/admin/PaymentsConfig/index.jsx` + `style.jsx`):
  - Container: max-width 980→1120px, padding aumentado.
  - Switch activo: track más oscuro + knob con color accent (antes indistinguible).
  - Botones: tamaños unificados (fontSize 0.8rem, padding 4px 12px).
  - **Bug crítico:** `client_id=undefined` causaba 401. Cambiado de `user?.client_id` a `useTenant().id`.

### 3. Fix API: Identity PATCH deep-merge
- **Archivo:** `src/home/home-settings.service.ts`
- `updateIdentity()` ahora hace deep-merge del payload con la identidad existente.
- Evita que un PATCH parcial sobreescriba objetos anidados (colores, tipografía).

### 4. Security Hardening: Cross-Tenant Audit (9 controllers, 11 vulnerabilidades)

Auditoría completa de 71 controllers. Vulnerabilidades encontradas y corregidas:

| Severidad | Controller | Problema | Fix |
|-----------|-----------|----------|-----|
| CRITICAL | cors-origins | Sin auth ni guards | +SuperAdminGuard |
| CRITICAL | legal (6 EPs) | Fallback a `x-client-id` header (spoofable) | →`getClientId(req)` |
| CRITICAL | legal /cancellation | Sin auth | +SuperAdminGuard |
| CRITICAL | home sections (5 EPs) | `req.client_id` = undefined | →`getClientId(req)` |
| HIGH | media-admin | RolesGuard (sin INTERNAL_ACCESS_KEY) | →SuperAdminGuard |
| HIGH | mp-oauth status/disconnect | Sin validación cross-tenant | +cross-tenant check + RolesGuard |
| HIGH | mp-oauth refresh | Cualquier admin podía refrescar cualquier cuenta | →super_admin only |
| HIGH | subscriptions reconcile/status | BuilderSessionGuard (IDOR) | →SuperAdminGuard |
| HIGH | dev-portal whitelist | BuilderOrSupabaseGuard (cualquier user auth) | →SuperAdminGuard |
| MEDIUM | debug whoami | Sin auth | +SuperAdminGuard |
| MEDIUM | metrics | RolesGuard sin double-factor | →SuperAdminGuard |

**Patrón principal de vulnerabilidad:** `req.headers['x-client-id']` como fallback permite que un atacante inyecte tenant arbitrario. El fix consistente es usar `getClientId(req)` que lee SOLO `req.clientId` (seteado por middleware/guard).

---

## Archivos modificados

### API (templatetwobe)
- `src/support/support.service.ts`
- `src/support/support-admin.controller.ts`
- `migrations/admin/ADMIN_061_add_ticket_limit.sql` (NEW)
- `src/home/home-settings.service.ts`
- `src/mp-oauth/mp-oauth.controller.ts`
- `src/cors-origins/cors-origins.controller.ts`
- `src/legal/legal.controller.ts`
- `src/home/home.controller.ts`
- `src/admin/media-admin.controller.ts`
- `src/subscriptions/subscriptions.controller.ts`
- `src/dev/dev-portal.controller.ts`
- `src/debug/debug.controller.ts`
- `src/metrics/metrics.controller.ts`

### Admin (novavision)
- `src/pages/AdminDashboard/SupportConsoleView.jsx`

### Web (templatetwo)
- `src/components/AnnouncementBar/style.jsx`
- `src/components/admin/PaymentsConfig/index.jsx`
- `src/components/admin/PaymentsConfig/style.jsx`

---

## Validación

- ✅ API: `npm run lint` + `npm run typecheck` + `npm run build`
- ✅ Web: `npm run lint` + `npm run typecheck` + `npm run build`
- ✅ Admin: `npm run lint` + `npm run typecheck` + `npm run build`
- ✅ Migración ADMIN_061 ejecutada en Admin DB

## Notas de seguridad

- **SuperAdminGuard** requiere double-factor: email en tabla `super_admins` + header `x-internal-key` con timing-safe comparison.
- Endpoints de debug/metrics/cors-origins ahora requieren SuperAdminGuard (antes eran accesibles sin auth).
- El patrón `req.headers['x-client-id']` fue eliminado de TODOS los controllers donde existía. Solo queda `getClientId(req)` como forma segura de obtener el tenant.

## Riesgos

- Los endpoints que ahora requieren SuperAdminGuard (`x-internal-key` header) necesitan que los clientes que los consumen (Admin dashboard, scripts) envíen ese header. Verificar que el Admin FE lo envíe en llamadas a `/metrics`, `/debug`, `/cors-origins`.
- La migración ADMIN_061 ya fue ejecutada en producción (Admin DB). No requiere re-ejecución.

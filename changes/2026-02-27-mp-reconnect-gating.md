# Cambio: Gating de reconexión Mercado Pago por cuenta

- **Autor:** copilot-agent
- **Fecha:** 2026-02-27
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Admin:** `feature/automatic-multiclient-onboarding`
- **Rama Web:** `develop` (cherry-pick a `feature/multitenant-storefront`)

## Archivos modificados

### API (`apps/api`)
- `src/mp-oauth/mp-oauth.service.ts` — `getConnectionStatus()` ahora incluye `allow_mp_reconnect` en select y response
- `src/mp-oauth/mp-oauth.controller.ts` — `start-url` y `disconnect` endpoints bloqueados si `allow_mp_reconnect=false`; `status/:clientId` retorna el flag
- `src/admin/admin.controller.ts` — Nuevo endpoint `PATCH /admin/accounts/:id/allow-mp-reconnect`
- `migrations/admin/ADMIN_093_allow_mp_reconnect.sql` — Columna `allow_mp_reconnect BOOLEAN DEFAULT false`

### Web (`apps/web`)
- `src/components/admin/PaymentsConfig/index.jsx` — Botones "Conectar Ahora" y "Desconectar" solo visibles si `allow_mp_reconnect=true`; mensaje "Contacte al administrador" cuando está bloqueado

### Admin (`apps/admin`)
- `src/pages/AdminDashboard/ClientApprovalDetail.jsx` — Nuevo toggle checkbox "Permitir reconexión MP" debajo de "Estado Pagos"

## Resumen

Se implementó un sistema de gating por cuenta para la reconexión de Mercado Pago. Por defecto, todos los clientes tienen `allow_mp_reconnect=false`, lo que significa que:

1. **No pueden** conectar ni desconectar MP desde el admin del storefront
2. El super admin debe **habilitar explícitamente** el permiso desde el panel de admin
3. Los endpoints `start-url` y `disconnect` en el API devuelven 403 si está deshabilitado
4. La UI muestra un mensaje "Contacte al administrador para habilitar la conexión" cuando está bloqueado

### Flujo

```
Super Admin (Admin Panel)
  → Toggle "Permitir reconexión MP" en detalle de cuenta
  → PATCH /admin/accounts/:id/allow-mp-reconnect { allow: true }
  → nv_accounts.allow_mp_reconnect = true

Cliente Admin (Web Storefront)
  → GET /mp/oauth/status/:clientId → { connected, allow_mp_reconnect, ... }
  → Si allow_mp_reconnect=true: muestra botones Connect/Disconnect
  → Si allow_mp_reconnect=false: muestra mensaje "Contacte al administrador"
  → Si intenta acceder a start-url o disconnect directamente → 403 Forbidden
```

## Por qué

El usuario reportó que los clientes cambian su cuenta de Mercado Pago con frecuencia ("cada 2 por 3"), lo que causa problemas operativos. El gating centraliza el control en el super admin.

## Migración

- **ADMIN_093**: `ALTER TABLE nv_accounts ADD COLUMN IF NOT EXISTS allow_mp_reconnect BOOLEAN NOT NULL DEFAULT false;`
- **Estado:** Ejecutada ✅

## Validación

### Builds
- API: lint ✅ (0 errores), typecheck ✅, build ✅
- Web: lint ✅ (0 errores), typecheck ✅, build ✅
- Admin: lint ✅, typecheck ✅, build ✅

### DB
- Farma: `mp_connected=true`, `allow_mp_reconnect=false` — bloqueado correctamente

## Cómo probar

1. **Admin Panel:**
   - Ir a detalle de cuenta → Sección "Estado Pagos"
   - Verificar que el toggle "Permitir reconexión MP" existe y está en OFF por defecto
   - Activarlo → debe mostrar toast de confirmación
   - Desactivarlo → debe mostrar toast de confirmación

2. **Web Storefront (con toggle OFF):**
   - Ir a /admin → tab Pagos
   - Verificar que NO aparece botón "Conectar Ahora" ni "Desconectar"
   - Verificar que aparece texto "Contacte al administrador para habilitar la conexión"

3. **Web Storefront (con toggle ON):**
   - Activar toggle desde admin panel
   - Refrescar tab Pagos en storefront
   - Verificar que botones Connect/Disconnect aparecen normalmente

4. **Seguridad (endpoint directo):**
   - Con toggle OFF, intentar `GET /mp/oauth/start-url` → debe devolver 403
   - Con toggle OFF, intentar `POST /mp/oauth/disconnect/:clientId` → debe devolver 403

## Notas de seguridad

- El gating es defense-in-depth: se valida tanto en frontend (ocultando botones) como en backend (403 en endpoints)
- El endpoint de onboarding (`GET /mp/oauth/start` con builder token) **NO** está afectado — la primera conexión durante onboarding sigue funcionando normalmente
- Solo `super_admin` puede modificar el flag via `SuperAdminGuard`

## Riesgos

- **Bajo:** Si se necesita reconectar MP urgentemente y el super admin no está disponible, el cliente queda bloqueado. Mitigación: el super admin puede habilitar remotamente en cualquier momento.

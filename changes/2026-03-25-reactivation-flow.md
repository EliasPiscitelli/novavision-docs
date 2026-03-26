# Flujo de Reactivación para Tenants Cancelados

**Fecha**: 2026-03-25
**Apps**: API, Admin, Web
**Tipo**: Feature

## Resumen

Implementación completa del flujo de reactivación para tenants con suscripción cancelada, suspendida o desactivada.

## Cambios

### Fase 1: API

- **`auth.service.ts`**: `getUserSession()` ahora retorna `subscription_status` y `subscription_cancel_info` (cancelled_at, cancellation_reason, purge_at, deactivate_at) para enriquecer la sesión del frontend.
- **`subscriptions.service.ts`**: Nuevo método `reactivate()` que crea un NUEVO preapproval en MercadoPago (el anterior está muerto tras cancelación). Status queda `pending` hasta confirmación vía webhook. También `adminReactivate()` para super admin.
- **`subscriptions.controller.ts`**: 3 nuevos endpoints:
  - `POST /subscriptions/manage/reactivate` (BuilderSessionGuard)
  - `POST /subscriptions/client/manage/reactivate` (ClientDashboardGuard)
  - `POST /subscriptions/admin/reactivate/:accountId` (SuperAdminGuard)

### Fase 2: Admin Dashboard

- **`AuthContext.jsx`**: Nuevo estado `subscriptionStatus`. Interceptor en `handleAuthRedirect` que redirige a `/reactivate` si la suscripción está en estado cancelado/suspendido/desactivado.
- **`onboardingRoutesMap.ts`**: Ruta `REACTIVATE: '/reactivate'` agregada a ROUTES y ALLOWED_PATHS.
- **`App.jsx`**: Ruta `/reactivate` registrada dentro de `<OnboardingGuardedRoute>`.
- **`ReactivationPage.tsx`** (NUEVO): Página completa de reactivación con dark theme, alerta de urgencia si hay purge_at, selección de plan, input de cupón win-back, y CTA que redirige a MercadoPago.
- **`builder/api.ts`**: Nueva función `requestReactivation()`.
- **`SubscriptionExpiredBanner.tsx`**: `handleAction()` ahora redirige a `/reactivate` para estados cancelados.
- **`BillingPage.tsx`**: Botón "Reactivar mi tienda" agregado en el bloque de suscripción cancelada.

### Fase 3: Web Storefront

- **`TenantProvider.jsx`**: Pantalla de tienda suspendida mejorada — texto amigable + CTA "Reactivar mi tienda" que lleva a novavision.lat/reactivate.
- **`StorefrontAdminGuard.jsx`**: Mensaje mejorado para admins de tienda suspendida con CTA de reactivación.

### Fase 4: Super Admin

- **`SubscriptionDetailView.jsx`**: Botón "Forzar Reactivación" visible cuando status es cancelado/suspendido/desactivado. Modal con selector de plan. Copia el init_point al portapapeles para enviar al tenant.
- **`adminApi.js`**: Nueva función `forceReactivate(accountId, planKey)`.

## Flujo técnico

1. Tenant cancela → suscripción pasa a `canceled`, tienda se pausa
2. Tenant accede a novavision.lat → login → AuthContext detecta `subscription_status: 'canceled'` → redirect a `/reactivate`
3. En `/reactivate`: selecciona plan → API crea NUEVO preapproval MP → redirect a MP init_point
4. Tenant paga en MP → webhook dispara `processMpEvent()` → status pasa a `active`
5. `unpauseStoreIfReactivated()` y `syncEntitlementsAfterUpgrade()` restauran tienda automáticamente

## Validación

- API: typecheck + build OK
- Admin: typecheck OK (errores preexistentes en tests no relacionados), build OK
- Web: typecheck + build OK

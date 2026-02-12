# Cambio: Auth unificado + Rediseño UX de Suscripción/Tienda

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** feature/automatic-multiclient-onboarding (`d3ad2fe`)
- **Rama Web:** feature/multitenant-storefront (`3d9035e`) + cherry-pick a develop (`68bed4c`)

---

## Problema

Los endpoints `/subscriptions/client/manage/*` usaban `BuilderSessionGuard`, que **solo** acepta tokens `builder_session` (firmados con JWT_SECRET). Los admin de tiendas activas que inician sesión con Supabase Auth recibían 401 "Invalid or expired builder token" porque su Supabase JWT no era reconocido.

Además, el componente `SubscriptionManagement` en el frontend:
- Mostraba datos crudos ("Sin suscripción", "Sin plan") sin formato legible
- Usaba CSS plano desalineado del design system
- Mostraba siempre el botón "Cancelar suscripción" aunque no hubiera pago recurrente

## Archivos modificados

### API (templatetwobe)
| Archivo | Cambio |
|---------|--------|
| `src/guards/client-dashboard.guard.ts` | Reescrito: acepta Supabase JWT (admin/super_admin) + builder token. Eliminada dep. de DbRouterService. |
| `src/subscriptions/subscriptions.controller.ts` | Import ClientDashboardGuard, 6 endpoints `/client/manage/*` migrados de BuilderSessionGuard |
| `src/subscriptions/subscriptions.service.ts` | `getManageStatus()` enriquecido: query a Backend DB (products count, store info), display labels en español |

### Web (templatetwo)
| Archivo | Cambio |
|---------|--------|
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Reescrito completo: styled-components con themeUtils, StatusBadge, StoreInfoRow, acciones condicionales |

## Detalle técnico

### Flujo de auth unificado (ClientDashboardGuard)

```
Intento 1: X-Builder-Token header → builder_session JWT → authType='builder'
Intento 2: req.user (AuthMiddleware) → role admin/super_admin → authType='supabase'
Intento 3: Authorization Bearer fallback (solo si no hay req.user) → builder_session JWT
```

El servicio usa `assertClientAdminRole()` que acepta:
- `authType='builder'` + `account_id` ✓
- `authType='supabase'` + `account_id` ✓
- Fallback: `role === 'admin' || 'super_admin'` ✓

Y `resolveAccountFromRequest()` busca en `nv_accounts` por:
1. `account_id` (metadata) → 2. `email` → 3. `client_id_backend` (resolvedClientId)

### Respuesta enriquecida de getManageStatus

Nuevo shape:
```json
{
  "account": { "id", "slug", "business_name", "plan_key", "store_paused", ... },
  "subscription": { ... } | null,
  "display": {
    "plan_name": "Starter",
    "status": "Activa",
    "payment_type": "Pago recurrente (Mercado Pago)",
    "next_payment_date": "2026-03-01T...",
    "store_active": true
  },
  "store": {
    "is_active": true,
    "created_at": "2025-...",
    "products_count": 42,
    "store_url": "https://ejemplo.novavision.lat"
  }
}
```

### UX rediseñada

- Cards con labels en español (`Plan`, `Estado`, `Tipo de pago`, `Próximo pago`)
- StatusBadge con color-coded dots (success=verde, warning=amarillo, danger=rojo, muted=gris)
- StoreInfoRow con: URL del sitio (link), productos, fecha de creación, estado
- Botón "Cancelar suscripción" solo visible si `mp_preapproval_id` existe (pago recurrente)
- Botones con styled-components (BtnPrimary, BtnSecondary, BtnDanger)

## Cómo probar

### API
```bash
cd apps/api && npm run start:dev
# Login como admin de tienda → obtener JWT
curl -H "Authorization: Bearer <SUPABASE_JWT>" \
     -H "x-client-id: <CLIENT_UUID>" \
     https://api.novavision.lat/subscriptions/client/manage/status
# Debería devolver datos enriquecidos con display y store
```

### Web
```bash
cd apps/web && npm run dev
# Login como admin → ir a Suscripción y Tienda
# Verificar que muestra plan, estado, tipo de pago, info de tienda
```

## Riesgos

- **Bajo:** Si no existe `nv_accounts` para el email/client_id del admin, `resolveAccountFromRequest` lanzará 404. Mitigation: el onboarding crea nv_accounts durante el setup.
- **Bajo:** Si Backend DB no tiene el `client_id_backend`, la sección `store` será `null` pero el endpoint sigue respondiendo.
- **Ninguno:** Los endpoints `manage/*` (builder flow original) siguen usando `BuilderSessionGuard` → no hay regresión.

## Notas de seguridad

- ClientDashboardGuard NO hace queries a DB — solo valida JWT o rol del middleware
- Los endpoint `/client/manage/*` requieren `assertClientAdminRole` en el service (segunda capa de validación)
- `resolveAccountFromRequest` siempre filtra por el contexto del usuario autenticado (no hay acceso cross-tenant)

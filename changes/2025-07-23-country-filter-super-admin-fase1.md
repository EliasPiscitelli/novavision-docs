# Cambio: Fase 1 — Filtro por país en Super Admin Dashboard

- Autor: agente-copilot
- Fecha: 2025-07-23
- Rama API: feature/automatic-multiclient-onboarding
- Rama Admin: feature/automatic-multiclient-onboarding

## Archivos modificados

### Backend (API)
- `src/admin/admin-quotas.controller.ts` — `@Query('country')` + filtro por `nv_accounts.country`
- `src/admin/admin-adjustments.controller.ts` — `@Query('country')` + filtro en list y detail
- `src/admin/admin.controller.ts` — Nuevo endpoint `GET /admin/dashboard-meta` + `country` param en `pending-approvals`, `pending-completions`, `subscription-events`
- `src/admin/admin.service.ts` — Nuevo `getDashboardMeta()` (cuenta tenants por país + join con `country_configs`); actualizado `getPendingApprovals()`, `getPendingCompletions()`, `getSubscriptionEvents()` con param `country`

### Frontend (Admin)
- **NUEVO** `src/context/CountryFilterContext.jsx` — Context global con `selectedCountry` + países cargados de `/admin/dashboard-meta`, persistido en localStorage
- **NUEVO** `src/components/CountrySelector.jsx` — Dropdown con banderas + count de tenants por país
- `src/pages/AdminDashboard/index.jsx` — Wrappea con `CountryFilterProvider`, agrega `CountrySelector` al header
- `src/services/adminApi.js` — Nuevo helper `getDashboardMeta()` + `getQuotas()` acepta params
- `src/pages/AdminDashboard/QuotasView.jsx` — Consume `useCountryFilter`, pasa `country` al fetch
- `src/pages/AdminDashboard/GmvCommissionsView.jsx` — Consume `useCountryFilter`, pasa `country` al fetch
- `src/pages/AdminDashboard/PendingApprovalsView.tsx` — Consume `useCountryFilter`, pasa `country` al fetch
- `src/pages/AdminDashboard/PendingCompletionsView.tsx` — Consume `useCountryFilter`, pasa `country` al fetch
- `src/pages/AdminDashboard/SubscriptionEventsView.jsx` — Consume `useCountryFilter`, pasa `country` al fetch

## Resumen

Implementación de Fase 1 del plan de visibilidad por país. Agrega un selector global de país en el header del dashboard super admin que filtra las vistas principales:

1. **Backend**: Todos los endpoints que hacen JOIN con `nv_accounts` ahora aceptan `?country=XX` (ISO alpha-2). El nuevo endpoint `GET /admin/dashboard-meta` devuelve la lista de países con count de tenants para popular el selector.

2. **Frontend**: Un React Context (`CountryFilterContext`) carga los países disponibles y mantiene la selección (persistida en localStorage). Un dropdown (`CountrySelector`) aparece en el header junto a los badges. Las 5 vistas P0 consumen el context y refetchean automáticamente al cambiar el país seleccionado.

## Por qué

Con la expansión multi-país (7 países LATAM), los super admins necesitan poder filtrar el dashboard por país para gestionar cada mercado de forma independiente. Sin este filtro, todas las métricas y listas mezclan datos de todos los países.

## Cómo probar

1. Levantar backend: `npm run start:dev` en terminal back
2. Levantar admin: `npm run dev` en terminal admin
3. Loguearse como super admin
4. Verificar que aparece el selector de país en el header (solo si hay >1 país con tenants)
5. Seleccionar un país → las vistas de Quotas, Ajustes/Comisiones, Aprobaciones, Completaciones y Eventos se refiltran
6. Seleccionar "Todos los países" → vuelve a mostrar todo
7. Recargar la página → la selección se mantiene (localStorage)

### Endpoints a testear
```bash
# Dashboard meta (lista de países)
curl -H "Authorization: Bearer <JWT>" -H "Cookie: nv_ik=<IK>" \
  https://<api>/admin/dashboard-meta

# Quotas filtrado por país
curl -H "Authorization: Bearer <JWT>" -H "Cookie: nv_ik=<IK>" \
  "https://<api>/admin/quotas?country=AR"

# Ajustes filtrado por país  
curl -H "Authorization: Bearer <JWT>" -H "Cookie: nv_ik=<IK>" \
  "https://<api>/admin/adjustments?country=AR"
```

## Notas de seguridad

- Todos los endpoints filtrados requieren `SuperAdminGuard` (sin cambio)
- El filtro solo restringe resultados; no amplía acceso
- `dashboard-meta` no expone datos sensibles (solo country_id, nombre, moneda, count)

## Vistas NO conectadas (próxima iteración)

- `ClientsView` — Fuentes de datos heterogéneas (Backend DB + Admin DB). Requiere refactor del endpoint `GET /admin/clients`.
- `MetricsView` — Usa RPC `dashboard_metrics` que no soporta `country` aún
- `BillingView`, `RenewalCenterView` — Por priorizar en Fase 2

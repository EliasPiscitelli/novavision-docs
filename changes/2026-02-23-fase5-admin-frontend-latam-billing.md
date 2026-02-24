# Fase 5 — Frontend Super Admin (LATAM Billing)

- **Autor:** agente-copilot  
- **Fecha:** 2026-02-23  
- **Rama:** `feature/automatic-multiclient-onboarding`  
- **Repos:** admin (novavision), API (templatetwobe)

---

## Resumen

Implementación completa de las 10 tareas de Fase 5: vistas de administración para el sistema de billing LATAM, incluyendo 5 vistas nuevas, extensiones a vistas existentes, API wrappers, sidebar, routing y un controlador backend adicional.

---

## Archivos creados

| Archivo | Descripción |
|---------|-------------|
| `apps/admin/src/pages/AdminDashboard/FxRatesView.jsx` | CRUD de tasas de cambio (fx_rates_config). Tabla con acciones inline edit/delete, formulario de creación. |
| `apps/admin/src/pages/AdminDashboard/CountryConfigsView.jsx` | CRUD de configuración por país (country_configs). Toggle activo, formulario con locale/currency/timezone/tax. |
| `apps/admin/src/pages/AdminDashboard/GmvCommissionsView.jsx` | Gestión de ajustes de facturación (billing_adjustments). Filtros por estado/tipo, acciones charge/waive, bulk charge, recalculate overages. |
| `apps/admin/src/pages/AdminDashboard/QuotasView.jsx` | Estado de cuotas por tenant (quota_state). Badges de estado, progress bars, inline edit de state/limits, reset counters. |
| `apps/admin/src/pages/AdminDashboard/FeeSchedulesView.jsx` | CRUD de fee schedules + lines con filas expandibles. Crear/eliminar schedules, agregar/editar/eliminar líneas inline. |
| `apps/admin/src/pages/ClientDetails/hooks/useClientBilling.js` | Hook React para quota state + adjustments de un tenant específico. |
| `apps/api/src/admin/admin-fee-schedules.controller.ts` | 7 endpoints CRUD para fee_schedules + fee_schedule_lines (BE prerequisito). |

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `apps/admin/src/services/adminApi.js` | +23 métodos nuevos para FX rates, country configs, quotas, adjustments, fee schedules, overages. |
| `apps/admin/src/pages/AdminDashboard/PlansView.jsx` | +6 columnas LATAM en tabla (USD price, GMV threshold, commission %, included orders, BW, overage). |
| `apps/admin/src/components/PlanEditorModal.jsx` | Sección "LATAM Billing" con 6 campos: price_usd, gmv_threshold_usd, gmv_commission_pct, included_orders, included_bandwidth_gb, overage_allowed. |
| `apps/admin/src/pages/ClientDetails/index.jsx` | +Sección "Estado de Quota" (4 cards) + "Ajustes de Facturación" (tabla con charge/waive). |
| `apps/admin/src/pages/AdminDashboard/index.jsx` | +5 iconos FaIcon + 5 NAV_ITEMS en categoría billing (fx-rates, country-configs, quotas, adjustments, fee-schedules). |
| `apps/admin/src/App.jsx` | +5 imports + 5 Route elements bajo /dashboard. |
| `apps/api/src/admin/admin.module.ts` | Registrado AdminFeeSchedulesController. |

---

## Detalle por tarea

| # | Tarea | Estado |
|---|-------|--------|
| 5.1 | FxRatesView | ✅ |
| 5.2 | CountryConfigsView | ✅ |
| 5.3 | GmvCommissionsView (adjustments) | ✅ |
| 5.4 | QuotasView | ✅ |
| 5.5 | FeeSchedulesView | ✅ |
| 5.5-BE | AdminFeeSchedulesController (prerequisito) | ✅ |
| 5.6 | PlansView + PlanEditorModal (LATAM columns) | ✅ |
| 5.7 | ClientDetails (quotas + billing sections) | ✅ |
| 5.8 | Sidebar NAV_ITEMS (5 nuevos) | ✅ |
| 5.9 | adminApi.js (23 métodos) | ✅ |
| 5.10 | App.jsx routes (5 rutas) | ✅ |

---

## Cómo probar

1. Levantar API: `cd apps/api && npm run start:dev`
2. Levantar Admin: `cd apps/admin && npm run dev`
3. Login como super_admin → Dashboard
4. Sidebar: verificar que aparecen los 5 nuevos items bajo "Billing"
5. Navegar a cada vista y verificar carga de datos / formularios
6. En ClientDetails de cualquier tenant: verificar secciones "Estado de Quota" y "Ajustes de Facturación" al final

## Build

```bash
cd apps/admin && npx vite build  # ✓ built in 4.33s
```

## Notas de seguridad

- Todas las vistas nuevas están bajo rutas protegidas con `requireSuperAdmin={true}`.
- Los NAV_ITEMS nuevos tienen `superOnly: true`.
- El controlador backend usa `@UseGuards(InternalAccessGuard)`.

# CRM Hardening — Robustez 100%

**Fecha:** 2026-03-16
**Alcance:** API (NestJS) + Admin Dashboard UI
**Branch:** feature/multitenant-storefront
**Estado:** Implementado, builds verificados, pendiente test manual + deploy

## Contexto

El CRM Phase 1-2 estaba al 92%. Tres auditorias independientes revelaron gaps en performance, seguridad de inputs, UX y automatizacion. Este cambio cierra todos los gaps para produccion.

## Cambios realizados

### FASE 1 — Infraestructura

- **NUEVO** `api/src/crm/dto/crm-account-filters.dto.ts` — DTO con class-validator para filtros de cuentas: whitelist de lifecycle/sort, page_size cap 100, health_min/max validados
- **Editado** `api/src/crm/types/crm.types.ts` — 6 interfaces tipadas para el cron (`HealthScoreUpdate`, `LifecycleTransition`, `CronAccountRow`, `CronSubscriptionRow`, `CronOnboardingRow`, `CronStoreRow`), eliminando todos los `any` del health cron
- **NUEVO** `admin/src/constants/crm.constants.js` — Constantes compartidas: `LIFECYCLE_STAGES`, `TASK_PRIORITIES`, `TASK_STATUSES`, `TIMELINE_COLORS`, helpers `stageColor()`, `stageLabel()`, `healthColor()`

### FASE 2 — Backend fixes criticos

| Fix | Archivo | Detalle |
|-----|---------|---------|
| N+1 → batch | `crm-health.cron.ts` | Loop secuencial reemplazado por `Promise.allSettled` en chunks de 10 |
| getMetrics memory | `crm.service.ts` | Fallback que cargaba TODAS las filas → N queries `head: true, count: 'exact'` en `Promise.all` |
| Concurrency guard | `crm-health.cron.ts` | Flag `isRunning` con early return + `try/finally` |
| UUID validation | `crm-admin.controller.ts` | `ParseUUIDPipe` en todos los `@Param` (accountId, noteId, taskId) |
| DTO validado | `crm-admin.controller.ts` | `CrmAccountFilters` (type) → `CrmAccountFiltersDto` (class con validacion runtime) |
| NaN safety | `crm-health.cron.ts` | `Number.isFinite(total)` check antes del clamp, fallback a 0 con warning |
| Backend DB down | `crm-health.cron.ts` | Cuando `store === null` por DB caida, renormaliza pesos excluyendo activation+publishing (0.60 → 1.0) |
| n8n paralelo | `crm-health.cron.ts` | Loop secuencial → `Promise.allSettled` para alertas n8n |

### FASE 3 — Backend adiciones

- **Cron overdue tasks** (`@Cron('*/30 * * * *')`) — Query `crm_tasks` pendientes vencidas, alerta consolidada a n8n webhook
- **Auto-tarea at_risk** — Al transicionar a `at_risk`, crea tarea idempotente (`automation_key = at_risk_review_{id}`) con prioridad alta

### FASE 4 — UI fixes criticos

| Fix | Vista | Detalle |
|-----|-------|---------|
| Confirm dialogs | Customer360View | `ConfirmDialog` en: eliminar nota, remover tag, cambiar lifecycle stage |
| Paginacion | CrmDashboardView | Estado `page`, controles Anterior/Siguiente, reset en cambio de filtro |
| Timeline load more | Customer360View | Estado `timelineOffset`, boton "Cargar mas" con append |
| Error toasts | Customer360View | `showToast({ status: 'error' })` en catch de fetchNotes, fetchTasks, fetchTimeline |
| Search debounce | CrmDashboardView | 300ms → 500ms + AbortController para cancelar requests en vuelo |

### FASE 5 — UI adiciones

- **Bulk actions** (CrmDashboardView) — Checkbox column + toolbar condicional: cambiar lifecycle, agregar tag (Promise.allSettled)
- **CSV export** (CrmDashboardView) — Boton "CSV" genera archivo client-side con BOM UTF-8, exporta pagina actual
- **Constantes compartidas** — Ambas vistas migradas a `crm.constants.js`, eliminando duplicacion

## Archivos modificados

| Archivo | Tipo |
|---------|------|
| `api/src/crm/dto/crm-account-filters.dto.ts` | NUEVO |
| `api/src/crm/dto/index.ts` | Editado |
| `api/src/crm/types/crm.types.ts` | Editado |
| `api/src/crm/crm-health.cron.ts` | Editado (el mas modificado) |
| `api/src/crm/crm.service.ts` | Editado |
| `api/src/crm/crm-admin.controller.ts` | Editado |
| `admin/src/constants/crm.constants.js` | NUEVO |
| `admin/src/pages/AdminDashboard/Customer360View.jsx` | Editado |
| `admin/src/pages/AdminDashboard/CrmDashboardView.jsx` | Editado (reescrito) |

## Verificacion

- [x] `tsc --noEmit` (API) — sin errores
- [x] `npm run build` (API) — compila OK
- [x] `npx vite build` (Admin) — sin errores
- [ ] Test manual: `POST /admin/crm/health/recompute` → logs muestran batch chunks
- [ ] Test manual: paginacion, confirm dialogs, CSV export, timeline load more
- [ ] Test manual: crear tarea con due_date pasado → verificar alerta overdue en 30 min
- [ ] Test manual: bulk actions (cambiar lifecycle, agregar tag a multiples cuentas)

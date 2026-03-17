# CRM Interno — Phase 1 completo (Backend + DB + UI)

**Fecha:** 2026-03-16
**Alcance:** API (NestJS) + Admin DB migration + Admin Dashboard UI
**Branch:** feature/multitenant-storefront
**Estado:** Migración ejecutada, UI implementada, pendiente deploy

## Cambios realizados

### Migración: `ADMIN_030_crm_core.sql`
- Columnas nuevas en `nv_accounts`: `lifecycle_stage`, `commercial_owner`, `health_score`, `health_computed_at`, `last_activity_at`, `tags[]`
- Tabla `crm_notes` — notas internas por cuenta con author, pinning, timestamps
- Tabla `crm_tasks` — tareas internas con status, priority, due_date, assigned_to, automation_key para idempotencia
- Tabla `crm_activity_log` — timeline unificado de eventos por cuenta
- Índices optimizados: lifecycle, health, owner, tags (GIN), automation dedup
- RLS habilitada en las 3 tablas (service_role only)
- Backfill automático de `lifecycle_stage` basado en `status` actual
- CHECK constraints en lifecycle_stage y health_score

### Módulo NestJS: `src/crm/`
- `CrmService` — Customer 360 agregador cross-DB, CRUD notas, CRUD tareas, activity log, lifecycle management, métricas CRM
- `CrmAdminController` — 15 endpoints REST bajo `admin/crm/*`
- DTOs con class-validator: CreateNoteDto, CreateTaskDto, UpdateTaskDto
- Types: LifecycleStage, TaskStatus, TaskPriority, Customer360, CrmAccountFilters
- Registrado en `app.module.ts`

### Endpoints disponibles

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/crm/customer-360/:accountId` | Vista 360 completa |
| GET | `/admin/crm/accounts` | Lista con filtros CRM |
| GET | `/admin/crm/metrics` | Métricas dashboard CRM |
| PATCH | `/admin/crm/accounts/:id/lifecycle` | Cambiar lifecycle stage |
| PATCH | `/admin/crm/accounts/:id/owner` | Asignar owner |
| PATCH | `/admin/crm/accounts/:id/tags` | Actualizar tags |
| GET | `/admin/crm/accounts/:id/notes` | Listar notas |
| POST | `/admin/crm/accounts/:id/notes` | Crear nota |
| PATCH | `/admin/crm/notes/:id` | Editar nota |
| DELETE | `/admin/crm/notes/:id` | Eliminar nota |
| GET | `/admin/crm/tasks` | Listar tareas (filtros) |
| POST | `/admin/crm/accounts/:id/tasks` | Crear tarea para cuenta |
| POST | `/admin/crm/tasks` | Crear tarea global |
| PATCH | `/admin/crm/tasks/:id` | Actualizar tarea |
| GET | `/admin/crm/accounts/:id/timeline` | Timeline de actividad |

### Plan completo
- Ver: `novavision-docs/plans/PLAN_CRM_INTERNAL_SUPERADMIN.md`

### Admin Dashboard UI: `src/pages/AdminDashboard/`
- `CrmDashboardView.jsx` — Vista principal CRM con métricas, filtros lifecycle, tabla de cuentas
- `Customer360View.jsx` — Vista 360 por cuenta con 4 tabs: Overview, Notas, Tareas, Timeline
- `adminApi.js` — 13 métodos CRM agregados (accounts, metrics, notes CRUD, tasks CRUD, timeline)
- Ruta `/dashboard/crm` y `/dashboard/crm/:accountId` registradas en `App.jsx`
- Nav item "CRM Interno" agregado en categoría "Clientes y Ventas"

#### Funcionalidades UI
- Métricas en tiempo real: total cuentas, activas, en riesgo, tareas vencidas, health promedio
- Filtros por lifecycle stage (pills interactivos) y búsqueda por email/slug
- Tabla de cuentas con lifecycle badge, health score, tags, última actividad
- Customer 360: cambiar lifecycle stage, agregar/remover tags inline
- Notas internas: crear, editar, eliminar, pin/unpin
- Tareas: crear con prioridad, cambiar estado inline (pending → in_progress → done)
- Timeline de actividad con dot-colors por actor_type (system, admin, automation, n8n)

## Migración
- [x] Ejecutada en Admin DB — 23 cuentas backfilled (20 trial, 3 lead)
- [x] 3 tablas CRM creadas con RLS + 14 índices + triggers updated_at

## Validación
- `tsc --noEmit` — OK (API)
- `eslint src/crm/` — OK (API)
- `npm run build` — OK (API)
- `vite build` — OK (Admin)

### Activity Log Instrumentation
- Helper `crm-activity.helper.ts` — función fire-and-forget que escribe en `crm_activity_log` + actualiza `last_activity_at`
- 10 eventos instrumentados en servicios existentes:

| Evento | Servicio | Método |
|--------|----------|--------|
| `ONBOARDING_PAYMENT_APPROVED` | OnboardingService | handleMpWebhookPayment() |
| `ACCOUNT_PROVISIONED` | ProvisioningWorkerService | provisionClientFromOnboardingInternal() |
| `ACCOUNT_APPROVED_BY_ADMIN` | AdminService | approveClient() |
| `SUBSCRIPTION_ACTIVATED` | SubscriptionsService | processMpEvent() |
| `SUBSCRIPTION_CANCELLED` | SubscriptionsService | processMpEvent() |
| `RECURRING_PAYMENT_APPROVED` | SubscriptionsService | handlePaymentSuccess() |
| `PLAN_CHANGED` | SubscriptionsService | requestUpgrade() |
| `ADDON_PURCHASED` | AddonsService | createPurchase() |
| `ADDON_ACTIVATED` | AddonsService | activateRecurringAddon() |
| `CUSTOM_DOMAIN_CONFIGURED` | AdminService | setCustomDomain() |
| `ACCOUNT_REJECTED` | AdminService | rejectClient() |

- Todas las llamadas son fire-and-forget (try-catch interno, nunca bloquean el flujo crítico)
- Cada log incluye `detail` en español + metadata relevante (plan_key, amounts, IDs)

### Health Score Cron (Phase 2)
- `crm-health.cron.ts` — Cron cada 6h (00:05, 06:05, 12:05, 18:05)
- Computa health_score (0-100) con fórmula ponderada:
  - Payment (0.30): status de suscripción + failures
  - Activation (0.25): cantidad de productos
  - Publishing (0.15): tienda publicada y activa
  - Activity (0.15): recencia de última actividad
  - Onboarding (0.10): estado del onboarding
  - Recency (0.05): bonus por antigüedad
- Lifecycle automático: 7 reglas de transición (active→at_risk, at_risk→churned, trial→onboarding, etc.)
- Endpoint manual: `POST /admin/crm/health/recompute` para trigger inmediato
- Batch processing: todas las cuentas en una sola ejecución, cross-DB para datos de tienda

### n8n Workflows CRM
- **WF-CRM-ALERT-V1** (id: `AyXOMejRIf5cTrp4`) — Webhook trigger en `/webhook/crm-alert`
  - Recibe payload del health cron cuando una cuenta transiciona a `at_risk` o `churned`
  - Formatea alerta con emoji de severidad, datos de cuenta y link al CRM
  - Envía por WhatsApp al `SALES_ALERT_PHONE`
  - Estado: **activo**
- **WF-CRM-WEEKLY-DIGEST-V1** (id: `k938xqWS2MrecDoG`) — Cron lunes 12:00 UTC (9:00 ART)
  - 4 queries paralelas a Admin DB: lifecycle distribution, actividad 7d, estado tareas, top at-risk
  - Formatea resumen semanal con métricas y envía por WhatsApp
  - Estado: **activo**
- Integración backend: `crm-health.cron.ts` dispara webhook fire-and-forget a n8n tras transiciones alertables
- Env var: `N8N_CRM_ALERT_WEBHOOK_URL` en `.env` y `.env.example`

## Próximos pasos
- [ ] Configurar `SALES_ALERT_PHONE` en n8n para recibir alertas WhatsApp
- [ ] Testear WF-CRM-ALERT-V1 con un POST manual al webhook
- [ ] Deploy a producción

# Support Tickets — AI Analysis Pipeline

**Fecha:** 2026-03-23
**Apps afectadas:** API, Admin, Web
**Plan:** `plans/PLAN_SUPPORT_TICKETS_AI_PIPELINE.md`

---

## Resumen

Se extendió el sistema de soporte existente con análisis AI (Claude), pipeline de desarrollo por etapas, descomposición en tareas, chat de intake guiado con diagnóstico automático, y generación de prompts enriquecidos para Claude Code.

## Cambios en Base de Datos (Admin DB)

### Columnas nuevas en `support_tickets`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `stage` | TEXT (open/dev/qa/done) | Pipeline de desarrollo interno (separado de `status`) |
| `ai_analysis` | TEXT | Resultado del análisis de Claude |
| `ai_analysis_at` | TIMESTAMPTZ | Fecha del análisis |
| `approval_status` | TEXT (pending/approved/rejected) | Estado de aprobación del plan AI |
| `approved_by` | UUID | Super admin que aprobó |
| `approved_at` | TIMESTAMPTZ | Fecha de aprobación |

### Tabla nueva: `ticket_tasks`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `id` | UUID PK | |
| `ticket_id` | UUID FK → support_tickets | |
| `title` | TEXT | Título de la tarea |
| `description` | TEXT | Descripción técnica |
| `repo` | TEXT | api/admin/web |
| `sort_order` | INT | Orden de la tarea |
| `is_done` | BOOLEAN | Completada |
| `done_at` | TIMESTAMPTZ | Fecha de completado |
| `done_by` | UUID | Quién la completó |

**Script:** `apps/api/scripts/support-ai-migration.sql`

## Endpoints Nuevos (API)

| Método | Ruta | Descripción |
|--------|------|-------------|
| `POST` | `/admin/support/tickets/:id/analyze` | Generar prompt enriquecido para Claude Code |
| `PATCH` | `/admin/support/tickets/:id/analysis` | Guardar análisis externo |
| `PATCH` | `/admin/support/tickets/:id/approve` | Aprobar/rechazar plan AI |
| `PATCH` | `/admin/support/tickets/:id/stage` | Avanzar stage (open→dev→qa→done) |
| `GET` | `/admin/support/tickets/:id/tasks` | Listar tareas del ticket |
| `PATCH` | `/admin/support/tasks/:id` | Toggle tarea completada |
| `GET` | `/client-dashboard/support/diagnose?category=X` | Diagnóstico automático del tenant |

Los endpoints `/admin/*` requieren `SuperAdminGuard`. El endpoint `/client-dashboard/*` requiere `ClientDashboardGuard` + `PlanFeature('support.tickets')`.

## Archivos Creados/Modificados

### API (`apps/api/src/support/`)
- **Nuevo:** `support-ai.service.ts` — Generación de prompts enriquecidos + stage management + tasks
- **Nuevo:** `support-diagnostic.service.ts` — Diagnóstico automático por categoría (billing, tech, bugs, onboarding)
- **Nuevo:** `dto/approve-ticket.dto.ts`
- **Nuevo:** `dto/advance-stage.dto.ts`
- **Nuevo:** `dto/update-task.dto.ts`
- **Modificado:** `support-admin.controller.ts` — 5 endpoints nuevos
- **Modificado:** `support.module.ts` — Registro de SupportAiService + SupportDiagnosticService
- **Modificado:** `support.controller.ts` — Endpoint de diagnóstico para tenants
- **Modificado:** `dto/index.ts` — Re-exports de nuevos DTOs
- **Modificado:** `types/ticket.types.ts` — Tipos TicketStage, ApprovalStatus, TicketTaskRow, AiAnalysisResult, stage transitions
- **Nuevo script:** `scripts/support-ai-migration.sql`

### Admin Dashboard (`apps/admin/src/`)
- **Nuevo:** `components/support/StagePipeline.jsx` — Indicador visual 4 pasos
- **Nuevo:** `components/support/AiAnalysisSection.jsx` — Botón Claude + aprobación + análisis
- **Nuevo:** `components/support/TicketTasks.jsx` — Lista de tareas con checkboxes
- **Modificado:** `pages/AdminDashboard/SupportConsoleView.jsx` — Integración de los 3 componentes

### Web Storefront (`apps/web/src/`)
- **Rediseñado:** `components/admin/SupportTickets/IntakeChat.jsx` — Diagnóstico guiado por categoría con preguntas específicas, diagnóstico automático contra DB real, screenshots, y ticket enriquecido
- **Modificado:** `components/admin/SupportTickets/index.jsx` — Reemplazo del modal form por IntakeChat

## Dependencias

- Sin dependencias externas nuevas (se removió `@anthropic-ai/sdk` — ahora genera prompts para copiar en Claude Code)

## Notas de Diseño

- `status` (customer-facing: open/triaged/in_progress/etc) y `stage` (dev pipeline: open/dev/qa/done) son campos **separados**
- No se llama a la API de Claude directamente — se genera un prompt copy-paste para usar en terminal Claude Code
- El prompt incluye: contexto del ticket, datos del cliente, diagnóstico automático (queries reales a la DB), respuestas del diagnóstico guiado, y screenshots adjuntos
- Stage `open→dev` requiere aprobación del plan AI
- Al rechazar un plan, se limpian el análisis y las tareas generadas

## Flujo completo

1. **Tenant** abre IntakeChat → selecciona categoría → responde preguntas específicas → se ejecuta diagnóstico contra DB real → adjunta screenshots → envía ticket enriquecido
2. **Super admin** ve el ticket en la consola → hace clic en "Generar prompt" → se genera prompt con TODO el contexto (ticket + diagnóstico + datos DB + screenshots) → lo copia y pega en Claude Code
3. **Claude Code** investiga el código y la DB, resuelve el problema, y marca el ticket como done vía SQL
4. **Super admin** aprueba el plan y avanza el stage si es necesario

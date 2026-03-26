# PLAN: Sistema de Tickets con Análisis AI y Pipeline de Desarrollo

> **Fecha:** 2026-03-23
> **Estado:** Aprobado — en ejecución
> **Autor:** Claude (Lead Engineer)
> **Alcance:** API (support module) + Admin Dashboard + Web Storefront
> **Dependencias:** Admin DB, Anthropic API (Claude), módulo support existente

---

## Resumen Ejecutivo

El sistema de soporte ya tiene un módulo funcional (~60% completo): tickets, mensajes, SLA, notificaciones y CSAT. Este plan **extiende** lo existente para agregar análisis AI con Claude, un pipeline de desarrollo por etapas (open→dev→qa→done), descomposición en tareas, y un chat de intake en el storefront para que los tenants reporten problemas.

**Decisión arquitectónica:** Extender el módulo `support/` existente. NO crear módulo paralelo.

**Justificación:**
- Las tablas `support_tickets`, `support_messages`, `support_ticket_events` ya existen
- El controller admin y tenant ya tienen rutas funcionales
- `SupportConsoleView.jsx` ya maneja lista, detalle, mensajes y filtros
- El proyecto NO usa TypeORM — usa Supabase JS via `DbRouterService`

---

## 1. Estado Actual (Investigación completada)

### 1.1 DB (Admin DB — erbfzlsznqsmwmjugspo)

| Tabla | Existe | Columnas clave |
|-------|--------|----------------|
| `support_tickets` | Sí | `id`, `ticket_number` (serial), `account_id`, `subject`, `category`, `priority`, `status`, `channel`, `assigned_agent_id`, SLA fields |
| `support_messages` | Sí | `ticket_id`, `author_type` (customer/agent/system), `body`, `attachments`, `is_internal` |
| `support_ticket_events` | Sí | Audit trail completo con `event_type`, `from_value`, `to_value` |
| `support_sla_policies` | Sí | Políticas por plan (growth: 480min, enterprise: 120min) |
| `support_csat` | Sí | Rating 1-5 post-ticket |
| `ticket_tasks` | **NO** | Crear |

### 1.2 API Backend

| Archivo | Existe | Funcionalidad |
|---------|--------|---------------|
| `support/support.module.ts` | Sí | Registrado en AppModule |
| `support/support.service.ts` | Sí | CRUD tickets, mensajes, SLA |
| `support/support.controller.ts` | Sí | Tenant: `/client-dashboard/support/*` |
| `support/support-admin.controller.ts` | Sí | Admin: `/admin/support/*` |
| `support/support-notification.service.ts` | Sí | Emails via `email_jobs` |
| `support/support-sla.service.ts` | Sí | Cron SLA cada 5min |
| Análisis AI | **NO** | Implementar |
| Gestión de tasks | **NO** | Implementar |
| Endpoints stage/approve | **NO** | Implementar |

### 1.3 Admin Frontend

| Componente | Existe | Ubicación |
|------------|--------|-----------|
| `SupportConsoleView.jsx` | Sí | `pages/AdminDashboard/` (~1400 líneas) |
| Ruta `/dashboard/soporte` | Sí | En `App.jsx` |
| Item en navegación | Sí | En `NAV_ITEMS` de `AdminDashboard/index.jsx` |
| Botón "Ejecutar Claude" | **NO** | Implementar |
| ApprovalBar | **NO** | Implementar |
| StagePipeline | **NO** | Implementar |
| TicketTasks | **NO** | Implementar |

### 1.4 Web Storefront

| Funcionalidad | Existe |
|---------------|--------|
| Chat intake soporte | **NO** |
| Ruta de soporte | **NO** |
| `TenantProvider` con `tenant.id` | Sí |

---

## 2. Implementación — Fases

### Fase 2.1 — Migración SQL (Admin DB)

**Archivo:** `apps/api/scripts/support-ai-migration.sql`

```sql
-- Nuevas columnas en support_tickets
ALTER TABLE support_tickets
  ADD COLUMN IF NOT EXISTS stage TEXT NOT NULL DEFAULT 'open',
  ADD COLUMN IF NOT EXISTS ai_analysis TEXT,
  ADD COLUMN IF NOT EXISTS ai_analysis_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS approval_status TEXT DEFAULT 'pending',
  ADD COLUMN IF NOT EXISTS approved_by UUID,
  ADD COLUMN IF NOT EXISTS approved_at TIMESTAMPTZ;

-- CHECK constraints
ALTER TABLE support_tickets
  ADD CONSTRAINT chk_stage CHECK (stage IN ('open', 'dev', 'qa', 'done'));

ALTER TABLE support_tickets
  ADD CONSTRAINT chk_approval_status CHECK (approval_status IN ('pending', 'approved', 'rejected'));

-- Índice para stage
CREATE INDEX IF NOT EXISTS idx_support_tickets_stage ON support_tickets(stage);

-- Nueva tabla: ticket_tasks
CREATE TABLE IF NOT EXISTS ticket_tasks (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  ticket_id UUID NOT NULL REFERENCES support_tickets(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  repo TEXT,
  sort_order INT DEFAULT 0,
  is_done BOOLEAN DEFAULT false,
  done_at TIMESTAMPTZ,
  done_by UUID,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ticket_tasks_ticket_id ON ticket_tasks(ticket_id);

-- RLS para ticket_tasks
ALTER TABLE ticket_tasks ENABLE ROW LEVEL SECURITY;
CREATE POLICY server_bypass ON ticket_tasks FOR ALL USING (true) WITH CHECK (true);
```

**Ejecutar contra Admin DB** y verificar con `\d support_tickets` y `\d ticket_tasks`.

### Fase 2.2 — Backend: Extender módulo support

**Archivos nuevos:**
- `support/dto/analyze-ticket.dto.ts`
- `support/dto/approve-ticket.dto.ts`
- `support/dto/advance-stage.dto.ts`
- `support/dto/update-task.dto.ts`
- `support/support-ai.service.ts` — lógica de análisis con Anthropic SDK

**Archivos a modificar:**
- `support/support.service.ts` — agregar métodos para tasks y stages
- `support/support-admin.controller.ts` — agregar 4 endpoints nuevos
- `support/support.module.ts` — registrar `SupportAiService`

**Endpoints nuevos (todos super-admin only):**

| Método | Ruta | Acción |
|--------|------|--------|
| `POST` | `/admin/support/tickets/:id/analyze` | Trigger análisis Claude |
| `PATCH` | `/admin/support/tickets/:id/approve` | Aprobar/rechazar plan AI |
| `PATCH` | `/admin/support/tickets/:id/stage` | Avanzar etapa del pipeline |
| `GET` | `/admin/support/tickets/:id/tasks` | Listar tareas del ticket |
| `PATCH` | `/admin/support/tasks/:id` | Toggle tarea done/undone |

**SupportAiService.analyzeTicket(ticketId):**
1. Cargar ticket + mensajes desde Admin DB
2. Llamar a Anthropic API con system prompt de análisis
3. Parsear respuesta JSON: `{ analysis, priority, category, affected_repo, tasks[] }`
4. Guardar `ai_analysis`, `ai_analysis_at` en `support_tickets`
5. Crear registros en `ticket_tasks`
6. Setear `approval_status = 'pending'`
7. Registrar evento en `support_ticket_events`

**Validaciones de transición de stage:**
- `open → dev`: solo si `approval_status === 'approved'`
- `dev → qa`: libre
- `qa → done`: libre, setea `resolved_at = now()`
- No se permite retroceder

### Fase 2.3 — Admin Frontend: Componentes AI/Pipeline

**Archivos nuevos en `apps/admin/src/`:**

| Archivo | Responsabilidad |
|---------|-----------------|
| `components/support/ExecuteClaudeButton.jsx` | Botón con spinner, deshabilitado si ya tiene análisis |
| `components/support/ApprovalBar.jsx` | Barra aprobar/rechazar, visible cuando `approval_status === 'pending'` |
| `components/support/StagePipeline.jsx` | Indicador visual 4 pasos: OPEN→DEV→QA→DONE |
| `components/support/TicketTasks.jsx` | Lista de tareas con checkboxes toggle |

**Modificar:** `SupportConsoleView.jsx` — integrar los 4 componentes nuevos en la vista de detalle del ticket.

**Patrón UI:** styled-components + dark theme (consistente con el resto del dashboard). No MUI components.

### Fase 2.4 — Web Storefront: Chat de Intake

**Archivos nuevos en `apps/web/src/`:**

| Archivo | Responsabilidad |
|---------|-----------------|
| `components/support/SupportChat.jsx` | Chat de 4 preguntas secuenciales |
| `pages/SupportPage.jsx` | Página contenedora del chat |

**Flujo del chat:**
1. "¿Qué problema estás experimentando?" → texto libre
2. "¿En qué sección ocurre?" → opciones: Checkout, Catálogo, Dashboard, Tienda pública, Otro
3. "¿El problema bloquea ventas activas?" → Sí bloquea / Es molesto / Solo informativo
4. "¿Aparece algún error en pantalla?" → texto libre

Al completar: resumen → botón "Enviar reporte" → `POST /client-dashboard/support/tickets` → confirmación con ticket_number.

**Nota:** El endpoint tenant ya existe. El `account_id` se resuelve server-side desde el guard (no necesitamos exponerlo en el frontend).

---

## 3. Convenciones Obligatorias

- **No TypeORM**: usar `this.dbRouter.getAdminClient()` para todas las queries
- **Guards**: `@UseGuards(SuperAdminGuard)` + `@AllowNoTenant()` para endpoints admin
- **Guards tenant**: `@UseGuards(ClientDashboardGuard)` + `@PlanFeature('support.tickets')` para endpoints tenant
- **API key**: `ANTHROPIC_API_KEY` desde `ConfigService`, nunca hardcodeada
- **Anthropic SDK**: `@anthropic-ai/sdk` — instalar como dependencia
- **UI**: styled-components + dark theme, consistente con `SupportConsoleView.jsx`
- **Sin mocks**: todo desde DB real
- **Idioma código**: inglés. Comentarios: español solo si necesario

---

## 4. Validación (Fase 3)

1. Build exitoso: `cd apps/api && npm run build` + `cd apps/admin && npm run build`
2. Verificar tablas en DB con `psql`
3. Smoke test: crear ticket → analizar con Claude → aprobar → avanzar stages
4. Changelog en `novavision-docs/changes/2026-03-23-support-tickets-ai-pipeline.md`

---

## 5. Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|------------|
| `ANTHROPIC_API_KEY` no configurada en prod | Validar en startup, log warning si falta |
| Análisis AI devuelve JSON inválido | Try/catch + retry 1 vez + fallback a error descriptivo |
| Conflicto con columnas existentes de `status` vs `stage` | Son campos separados: `status` = customer-facing, `stage` = dev pipeline |
| RLS bloquea queries de tasks | Policy `server_bypass` para service_role (igual que otras tablas) |

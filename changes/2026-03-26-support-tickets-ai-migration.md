# Support Tickets AI Pipeline — Migración SQL

**Fecha:** 2026-03-26
**Plan:** `PLAN_SUPPORT_TICKETS_AI_PIPELINE.md` Fase 2
**Estado:** Migración creada (pendiente ejecución en Admin DB)

---

## Problema

El código backend para el pipeline AI de soporte ya estaba 100% implementado (SupportAiService, endpoints admin, DTOs, tipos), pero las columnas y tabla necesarias en la base de datos Admin no existían. Sin la migración, los endpoints fallarían en runtime al intentar leer/escribir `stage`, `ai_analysis`, `approval_status`, etc.

## Solución

### Migración: `20260326_support_tickets_ai_pipeline.sql`

**Columnas agregadas a `support_tickets`:**
| Columna | Tipo | Default | Propósito |
|---------|------|---------|-----------|
| `stage` | TEXT NOT NULL | `'open'` | Pipeline de desarrollo (open→dev→qa→done) |
| `ai_analysis` | TEXT | NULL | Resultado del análisis Claude |
| `ai_analysis_at` | TIMESTAMPTZ | NULL | Timestamp del análisis |
| `approval_status` | TEXT | `'pending'` | Estado de aprobación del plan AI |
| `approved_by` | UUID | NULL | Quién aprobó |
| `approved_at` | TIMESTAMPTZ | NULL | Cuándo se aprobó |

**Tabla nueva: `ticket_tasks`**
- Descomposición de trabajo por ticket
- Campos: id, ticket_id (FK), title, description, repo, sort_order, is_done, done_at, done_by
- RLS con service_role bypass
- Índice en ticket_id

**Constraints:**
- `chk_support_tickets_stage`: solo valores `open`, `dev`, `qa`, `done`
- `chk_support_tickets_approval_status`: solo `pending`, `approved`, `rejected`

### Pendiente

- Ejecutar migración contra Admin DB (`psql $ADMIN_DB_URL < migrations/admin/20260326_support_tickets_ai_pipeline.sql`)
- Admin dashboard UI (4 componentes: ExecuteClaudeButton, ApprovalBar, StagePipeline, TicketTasks)

### Archivos creados

- `api/migrations/admin/20260326_support_tickets_ai_pipeline.sql`

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK

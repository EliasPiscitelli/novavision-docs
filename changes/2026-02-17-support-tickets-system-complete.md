# Sistema de Tickets de Soporte — Entrega completa

- **Autor:** agente-copilot
- **Fecha:** 2026-02-17
- **Rama:** `feature/automatic-multiclient-onboarding`

---

## Resumen

Implementación completa del **Sistema de Tickets de Soporte** para clientes Growth + Enterprise de NovaVision.
Incluye backend (NestJS), frontend admin (super admin), frontend tenant (tienda), cron SLA, migración SQL, tests unitarios y validación completa.

---

## Archivos creados / modificados

### Backend (`apps/api/`)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/support/types/ticket.types.ts` | Creado | Enums, interfaces DB, máquina de estados |
| `src/support/dto/create-ticket.dto.ts` | Creado | DTO de creación de ticket |
| `src/support/dto/create-message.dto.ts` | Creado | DTO de mensaje |
| `src/support/dto/update-ticket.dto.ts` | Creado | DTO de actualización (admin) |
| `src/support/dto/close-ticket.dto.ts` | Creado | DTO de cierre + CSAT |
| `src/support/dto/ticket-filters.dto.ts` | Creado | DTO de filtros y paginación |
| `src/support/dto/index.ts` | Creado | Barrel exports |
| `src/support/support.service.ts` | Creado | Servicio principal: CRUD tickets, mensajes, CSAT |
| `src/support/support-sla.service.ts` | Creado | Cálculo de SLA, detección de breaches |
| `src/support/support-notification.service.ts` | Creado | Notificaciones por email (email_jobs) |
| `src/support/support.controller.ts` | Creado | 7 endpoints tenant (`/client-dashboard/support/*`) |
| `src/support/support-admin.controller.ts` | Creado | 7 endpoints admin (`/admin/support/*`) |
| `src/support/support.module.ts` | Creado | Módulo NestJS (modificado para exportar SlaService) |
| `src/cron/support-sla.cron.ts` | Creado | Cron cada 5 min para detectar SLA breaches |
| `src/cron/cron.module.ts` | Modificado | Agregó `SupportSlaCron` + import `SupportModule` |
| `src/app.module.ts` | Modificado | Agregó `SupportModule` |
| `src/plans/featureCatalog.ts` | Modificado | Agregó feature `support.tickets` |
| `src/support/__tests__/support.service.spec.ts` | Creado | 5 tests: create, list, get, get-not-found, close |
| `src/support/__tests__/support-sla.service.spec.ts` | Creado | 5 tests: calculateDueDates (3), checkBreaches (2) |
| `src/support/__tests__/support-notification.service.spec.ts` | Creado | 8 tests: lifecycle notifications |
| `src/cron/__tests__/support-sla.cron.spec.ts` | Creado | 4 tests: cron invocation, logging, error handling |

### Admin Frontend (`apps/admin/`)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/pages/AdminDashboard/SupportConsoleView.jsx` | Creado | Consola de soporte super admin (~800 líneas, dark theme) |
| `src/App.jsx` | Modificado | Ruta `/dashboard/soporte` |
| `src/pages/AdminDashboard/index.jsx` | Modificado | NAV_ITEMS "Soporte" + FaHeadset |

### Web / Tenant Frontend (`apps/web/`)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/components/admin/SupportTickets/style.jsx` | Creado | Styled-components (~600 líneas, CSS vars, animaciones) |
| `src/components/admin/SupportTickets/index.jsx` | Creado | UI completa de tickets (~500 líneas) |
| `src/pages/AdminDashboard/index.jsx` | Modificado | Registró sección `supportTickets` en dashboard |

### Migración (`migrations/admin/`)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `20260216_support_tickets.sql` | Creado + Aplicado | 5 tablas, 7 índices, RLS, trigger, seed SLA |

---

## Tablas creadas (Admin DB)

| Tabla | Descripción |
|-------|-------------|
| `support_tickets` | Tickets de soporte con SLA, estado, prioridad |
| `support_messages` | Mensajes (customer/agent/system) con attachments |
| `support_ticket_events` | Auditoría de cambios de estado |
| `support_sla_policies` | Políticas SLA por plan (seed: growth 480/2880, enterprise 120/1440) |
| `support_csat` | Satisfacción del cliente (1-5 + comentario) |

---

## Endpoints

### Tenant (`/client-dashboard/support/`)

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/tickets` | Listar tickets (filtros, paginación) |
| POST | `/tickets` | Crear ticket |
| GET | `/tickets/:id` | Detalle de ticket |
| GET | `/tickets/:id/messages` | Mensajes del ticket |
| POST | `/tickets/:id/messages` | Agregar mensaje |
| PATCH | `/tickets/:id/close` | Cerrar ticket + CSAT |
| PATCH | `/tickets/:id/reopen` | Reabrir ticket |

### Admin (`/admin/support/`)

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/tickets` | Listar tickets cross-tenant |
| GET | `/tickets/:id` | Detalle de ticket |
| PATCH | `/tickets/:id` | Actualizar ticket (assign, status, priority) |
| GET | `/tickets/:id/messages` | Mensajes (incluye internos) |
| POST | `/tickets/:id/messages` | Agregar mensaje/nota interna |
| PATCH | `/tickets/:id/resolve` | Resolver ticket |
| GET | `/metrics` | Métricas de soporte |

---

## Tests (22 pasando)

| Suite | Tests | Estado |
|-------|-------|--------|
| `support.service.spec.ts` | 5 | ✅ |
| `support-sla.service.spec.ts` | 5 | ✅ |
| `support-notification.service.spec.ts` | 8 | ✅ |
| `support-sla.cron.spec.ts` | 4 | ✅ |

---

## Validación

| Check | API | Web | Admin |
|-------|-----|-----|-------|
| Lint | ✅ 0 errors | ✅ 0 errors | ✅ (prev. session) |
| TypeScript | ✅ 0 errors | ✅ 0 errors | ✅ (prev. session) |
| Build | ✅ OK | — | — |
| Tests | ✅ 22/22 | — | — |

---

## Cómo probar

### Backend
```bash
cd apps/api
npm run start:dev
# Tenant endpoints (requiere JWT + x-client-id):
# GET  http://localhost:3001/client-dashboard/support/tickets
# POST http://localhost:3001/client-dashboard/support/tickets
# etc.
```

### Frontend Web (tenant)
```bash
cd apps/web
npm run dev
# Ir a panel admin → sección "Soporte" (requiere plan Growth/Enterprise)
```

### Frontend Admin (super admin)
```bash
cd apps/admin
npm run dev
# Ir a /dashboard/soporte
```

---

## Notas de seguridad

- Todos los endpoints tenant validan `account_id` del JWT (no se puede acceder a tickets de otro tenant)
- `is_internal: true` en mensajes solo visible para admins (el endpoint tenant filtra `is_internal = false`)
- RLS habilitado en las 5 tablas con políticas por tenant + service_role bypass
- CSAT upsert por `ticket_id` previene duplicados
- Cron SLA ejecuta cada 5 minutos sin bloquear el event loop

## Riesgos / Rollback

- **Riesgo bajo:** Las tablas nuevas no tienen dependencias con tablas existentes
- **Rollback:** `DROP TABLE support_csat, support_ticket_events, support_messages, support_sla_policies, support_tickets CASCADE;`
- **Plan gating:** Feature `support.tickets` solo habilitada para Growth/Enterprise — Basic no ve la sección

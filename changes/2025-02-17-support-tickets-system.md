# Cambio: Sistema de Tickets de Soporte (Growth + Enterprise)

- **Autor:** agente-copilot
- **Fecha:** 2025-02-17
- **Rama:** feature/automatic-multiclient-onboarding
- **Alcance:** BE + Admin FE

---

## Resumen

Implementación completa del sistema de tickets de soporte para clientes con planes Growth y Enterprise. Incluye:

- **Fase 0 (Auditoría):** Relevamiento del stack, patrones de auth, plan gating, DB, email y módulos existentes.
- **Fase 1 (Diseño):** Especificación con ERD, modelo de datos (5 tablas), 14 endpoints (7 tenant + 7 admin), máquina de estados, matriz de notificaciones, comportamiento de downgrade y SLA.
- **Fase 2 (Implementación):** Backend completo (NestJS module) + consola super admin (React).

---

## Archivos creados

### Documentación
| Archivo | Propósito |
|---------|-----------|
| `novavision-docs/SUPPORT_TICKETS_AUDIT.md` | Auditoría fase 0 — hallazgos y decisiones arquitectónicas |
| `novavision-docs/SUPPORT_TICKETS_SPEC.md` | Especificación completa (ERD, endpoints, UX, SLA, notificaciones) |

### Backend — `apps/api/`
| Archivo | Propósito |
|---------|-----------|
| `migrations/admin/20260216_support_tickets.sql` | Migración: 5 tablas, 7 índices, RLS, triggers, seed SLA |
| `src/support/types/ticket.types.ts` | Enums, interfaces DB, máquina de estados, label maps |
| `src/support/types/index.ts` | Barrel export |
| `src/support/dto/create-ticket.dto.ts` | DTO creación ticket (class-validator) |
| `src/support/dto/create-message.dto.ts` | DTO mensaje (body, attachments, is_internal) |
| `src/support/dto/update-ticket.dto.ts` | DTO actualización (status, priority, agent, tags) |
| `src/support/dto/close-ticket.dto.ts` | DTO cierre con CSAT (rating 1-5) |
| `src/support/dto/ticket-filters.dto.ts` | DTO filtros/paginación para listado |
| `src/support/dto/index.ts` | Barrel export DTOs |
| `src/support/support.service.ts` | Servicio principal: CRUD tenant + operaciones admin |
| `src/support/support-sla.service.ts` | Cálculo/breach de SLA por plan |
| `src/support/support-notification.service.ts` | Notificaciones email vía email_jobs queue |
| `src/support/support.controller.ts` | 7 endpoints tenant `/client-dashboard/support/*` |
| `src/support/support-admin.controller.ts` | 7 endpoints admin `/admin/support/*` |
| `src/support/support.module.ts` | Módulo NestJS con providers/controllers |

### Admin Frontend — `apps/admin/`
| Archivo | Propósito |
|---------|-----------|
| `src/pages/AdminDashboard/SupportConsoleView.jsx` | Consola super admin (~730 líneas): métricas, filtros, tabla, detalle, conversación, sidebar editable |

### Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `apps/api/src/app.module.ts` | Agregado `SupportModule` al array de imports |
| `apps/api/src/plans/featureCatalog.ts` | Agregada categoría `support` + feature `support.tickets` (growth/enterprise) |
| `apps/admin/src/App.jsx` | Import + ruta `/dashboard/soporte` para SupportConsoleView |
| `apps/admin/src/pages/AdminDashboard/index.jsx` | Import `FaHeadset` + NAV_ITEM "Soporte" en categoría operations |

---

## Decisiones arquitectónicas

| # | Decisión | Motivo |
|---|----------|--------|
| D1 | Tickets en Admin DB (no Backend/Multicliente) | Acceso cross-tenant para super admins; los tickets no son datos de tienda |
| D2 | `account_id` (nv_accounts.id) como FK principal | Identifica al tenant en Admin DB, no confundir con `client_id` de Backend DB |
| D3 | `@PlanFeature('support.tickets')` | Reutiliza el sistema de plan gating existente (PlanAccessGuard) |
| D4 | `ClientDashboardGuard` para endpoints tenant | Resuelve `req.account_id` vía `resolveAccountId()` — patrón ya probado |
| D5 | `SuperAdminGuard` para endpoints admin | Validación via tabla `super_admins` + `x-internal-key` |
| D6 | Emails vía `email_jobs` queue | Reutiliza el worker Postmark existente (cron 5s) |
| D7 | `ticket_number` serial para identificador humano | UX: "Ticket #42" es más claro que un UUID |
| D8 | Consola super admin en `apps/admin` | Es la app de gestión NovaVision; la UI tenant en `apps/web` queda diferida |

---

## Tablas creadas (Admin DB)

| Tabla | Columnas clave |
|-------|---------------|
| `support_sla_policies` | plan_key, first_response_minutes, resolution_minutes |
| `support_tickets` | ticket_number, account_id, subject, category, priority, status, assigned_agent_id, SLA fields |
| `support_messages` | ticket_id, author_type, author_id, body, attachments, is_internal |
| `support_ticket_events` | ticket_id, event_type, actor_id, old_value → new_value |
| `support_csat` | ticket_id, account_id, rating (1-5), comment |

---

## Cómo probar

### Backend
```bash
cd apps/api
npm run lint        # 0 errores
npm run typecheck   # compila sin errores
npm run build       # dist/main.js generado OK
```

### Admin Frontend
```bash
cd apps/admin
npm run lint        # pasa sin errores
npm run typecheck   # compila sin errores
```

### Migración (pendiente de aplicar)
```sql
-- Ejecutar en Admin DB (Supabase SQL Editor):
-- Contenido de migrations/admin/20260216_support_tickets.sql
```

### Funcional
1. Aplicar migración en Admin DB
2. Levantar API: `cd apps/api && npm run start:dev`
3. Levantar admin: `cd apps/admin && npm run dev`
4. Navegar a `/dashboard` → sidebar → "Soporte" (categoría Operaciones)
5. Verificar que la consola carga (mostrará "No hay tickets" vacío inicialmente)

---

## Notas de seguridad

- Endpoints tenant protegidos con `ClientDashboardGuard` + `PlanAccessGuard` + JWT
- Endpoints admin protegidos con `SuperAdminGuard` (tabla `super_admins` + `x-internal-key`)
- RLS habilitado en todas las tablas con bypass `service_role`
- Mensajes internos (`is_internal: true`) nunca visibles para el tenant
- Attachments validados con max 5 items, URL + nombre requeridos

---

## Pendiente (fuera de este cambio)

- [ ] UI de soporte para tenant admin en `apps/web` (endpoints ya existen)
- [ ] Cron job para `SupportSlaService.checkBreaches()`
- [ ] Templates de email dedicados para soporte (actualmente HTML inline)
- [ ] Tests unitarios y E2E
- [ ] Aplicar migración SQL en Admin DB de producción

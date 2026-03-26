# 2026-03-23 — Seguridad + Cancelled + Toggle soporte + Límite mensual

## Resumen

4 mejoras al sistema de soporte:

1. **Fix seguridad**: Queries tenant ya no exponen campos internos (`ai_analysis`, `approval_status`, `approved_by/at`). Se usa `stripInternal()` en todos los métodos tenant.
2. **Status cancelled**: Nuevo estado real para tickets. El cliente puede cancelar (desde `open` e `in_progress`) y reabrir. Botón "Cancelar ticket" en web, badge rojo, dropdown actualizado en admin.
3. **Toggle soporte por tienda**: El super-admin puede habilitar/deshabilitar soporte por tienda individual via `clients.feature_overrides['support.tickets']`. Reset a plan default disponible.
4. **Límite mensual**: Nuevo límite de tickets por mes calendario (`tickets_per_month` en `nv_accounts`). Defaults: starter=0, growth=5, enterprise=15. Indicador en web y admin.

## Archivos modificados

### API (`apps/api/`)
- `src/support/types/ticket.types.ts` — `cancelled` en TicketStatus, TicketEventType, TICKET_TRANSITIONS, STATUS_LABELS
- `src/support/support.service.ts` — `stripInternal()`, `cancelTenantTicket()`, `enforceMonthlyTicketLimit()`, `getSupportAccessInfo()`, `toggleSupportAccess()`, extendido `getAccountTicketLimitInfo()` y `setAccountTicketLimit()`
- `src/support/support.controller.ts` — Endpoints: `PATCH .../cancel`, `GET .../ticket-limits`
- `src/support/support-admin.controller.ts` — Endpoints: `GET/PATCH .../support-access`, extendido `PATCH .../ticket-limit`
- `src/support/dto/cancel-ticket.dto.ts` — Nuevo DTO
- `src/support/dto/update-ticket.dto.ts` — Agregado `cancelled` al IsIn
- `src/support/dto/index.ts` — Export del nuevo DTO
- `src/support/__tests__/support.service.spec.ts` — Actualizado chainBuilder y mock para monthly limit

### Web (`apps/web/`)
- `src/components/admin/SupportTickets/index.jsx` — Status `cancelled`, botón "Cancelar ticket", indicador de límites (activos + mensuales)
- `src/components/admin/SupportTickets/style.jsx` — Color rojo para `cancelled`

### Admin (`apps/admin/`)
- `src/pages/AdminDashboard/SupportConsoleView.jsx` — Status `cancelled` en labels/colors, toggle soporte, límite mensual en TicketLimitRow

### Migración SQL (Admin DB)
- `support_tickets.status` CHECK constraint: agregado `cancelled`
- `nv_accounts.tickets_per_month` columna nueva (integer, nullable)

## Validación
- API: lint (0 errors), typecheck (0 errors), build OK, tests 5/5 pass
- Web: typecheck OK, build OK
- Admin: build OK (errores pre-existentes en tests no relacionados)

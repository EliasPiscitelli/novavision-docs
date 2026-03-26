# Plan: Seguridad + Status cancelled + Toggle soporte + Límite mensual

## Contexto

El sistema de soporte tiene 4 gaps:
1. **Seguridad**: `select('*')` en queries tenant expone `ai_analysis`, `approval_status`, `approved_by/at` al cliente
2. **Cancel**: No existe status `cancelled` — el cliente solo puede cerrar, no cancelar
3. **Toggle por tienda**: No hay forma de habilitar/deshabilitar soporte por tienda individual desde el super-admin
4. **Límite mensual**: Solo existe límite de tickets activos, no por mes (growth:5/mes, enterprise:15/mes)

**Rol del cliente**: solo puede **crear** y **cancelar** tickets. El super-admin controla todo lo demás.

---

## Paso 1 — Fix seguridad: columnas explícitas en queries tenant

**Archivo**: `apps/api/src/support/support.service.ts`

- Definir constante estática `TENANT_SAFE_COLUMNS`:
  ```
  id, ticket_number, account_id, created_by_user_id, subject, category, priority, status,
  channel, order_id, assigned_agent_id, first_response_at, resolved_at, closed_at,
  last_customer_message_at, last_agent_message_at, first_response_due_at, resolution_due_at,
  sla_first_response_breached, sla_resolution_breached, tags, meta, stage, created_at, updated_at
  ```
- **Excluidos**: `ai_analysis`, `ai_analysis_at`, `approval_status`, `approved_by`, `approved_at`
- Reemplazar `.select('*')` → `.select(TENANT_SAFE_COLUMNS)` en 5 métodos tenant:
  - `listTenantTickets()` (L129)
  - `getTenantTicket()` (L162)
  - `createTicket()` (L86)
  - `closeTenantTicket()` (L297)
  - `reopenTenantTicket()` (L350)

---

## Paso 2 — Status `cancelled` como estado real

### 2a. Types (`apps/api/src/support/types/ticket.types.ts`)

- Agregar `'cancelled'` al union `TicketStatus`
- Agregar `'cancelled'` al union `TicketEventType`
- Agregar transiciones en `TICKET_TRANSITIONS`:
  ```typescript
  // Desde open e in_progress, el customer puede cancelar
  open: [
    ...existentes,
    { to: 'cancelled', actors: ['customer', 'agent'] },
  ],
  in_progress: [
    ...existentes,
    { to: 'cancelled', actors: ['customer', 'agent'] },
  ],
  // Desde cancelled, se puede reabrir
  cancelled: [
    { to: 'open', actors: ['customer'] },
  ],
  ```
- Agregar label en `STATUS_LABELS_ES`: `cancelled: 'Cancelado'`

### 2b. Migración SQL (Admin DB)

```sql
-- Agregar 'cancelled' al CHECK constraint de status en support_tickets
ALTER TABLE support_tickets DROP CONSTRAINT IF EXISTS support_tickets_status_check;
ALTER TABLE support_tickets ADD CONSTRAINT support_tickets_status_check
  CHECK (status IN ('open','triaged','in_progress','waiting_customer','resolved','closed','cancelled'));
```

### 2c. Service (`apps/api/src/support/support.service.ts`)

- Nuevo método `cancelTenantTicket(ticketId, accountId, userId, reason?)`:
  - Valida transición via `isTransitionAllowed(status, 'cancelled', 'customer')`
  - Update: `status='cancelled'`, `closed_at=now()`
  - Registra evento `event_type: 'cancelled'` con razón en `description`
  - Usa `.select(TENANT_SAFE_COLUMNS)`

- **Ajustar `enforceActiveTicketLimit()`**: NO contar tickets `cancelled` como activos (ya no se cuentan porque filtra por `['open', 'in_progress', 'waiting_on_customer']`)

### 2d. Controller (`apps/api/src/support/support.controller.ts`)

- Nuevo endpoint: `PATCH /client-dashboard/support/tickets/:ticketId/cancel`
- Body: `{ reason?: string }`

### 2e. Frontend Web (`apps/web/src/components/admin/SupportTickets/`)

**`index.jsx`**:
- Agregar a `STATUS_LABELS`: `cancelled: 'Cancelado'`
- Reemplazar botón "Cerrar" por "Cancelar ticket" cuando `status === 'open'`
- El botón "Cerrar" permanece para status `in_progress` y `resolved` (si el super-admin lo puso ahí)
- Botón "Reabrir" visible también cuando `status === 'cancelled'`
- Nuevo handler `handleCancel` que llama `PATCH .../cancel` con modal opcional para razón

**`style.jsx`**:
- Agregar color para `cancelled` en `statusColors`: `{ bg: '#ef4444', fg: '#fff' }` (rojo)

### 2f. Frontend Admin (`apps/admin/.../SupportConsoleView.jsx`)

- Agregar a `STATUS_LABELS`: `cancelled: 'Cancelado'`
- Agregar a `STATUS_COLORS`: `cancelled: '#ef4444'` (rojo)
- El super-admin ya puede cambiar status vía dropdown — solo necesita el nuevo valor en las constantes

---

## Paso 3 — Toggle soporte por tienda (super-admin)

### 3a. Service (`apps/api/src/support/support.service.ts`)

Nuevos métodos usando `dbRouter.getBackendClient()`:

- `getSupportAccessInfo(accountId)`:
  - Resuelve `client` via `clients.nv_account_id = accountId`
  - Lee `feature_overrides` y `plan_key` del client
  - Compara con `featureCatalog` para `support.tickets`
  - Retorna: `{ enabled, source: 'plan_default'|'override', plan_key, plan_allows }`

- `toggleSupportAccess(accountId, enabled: boolean | null)`:
  - Lee `feature_overrides` actual del client
  - Si `enabled === null` → borra la key `support.tickets` (reset a plan default)
  - Si `enabled === true/false` → setea `feature_overrides['support.tickets'] = enabled`
  - Update `clients.feature_overrides`
  - Patrón: idéntico a `admin-store-coupons.controller.ts` L228-281

### 3b. Admin Controller (`apps/api/src/support/support-admin.controller.ts`)

- `GET /admin/support/accounts/:accountId/support-access`
- `PATCH /admin/support/accounts/:accountId/support-access` — body: `{ enabled: boolean | null }`

### 3c. Frontend Admin (`apps/admin/.../SupportConsoleView.jsx`)

- En la sección de info del cliente (sidebar del ticket detail), agregar un toggle row:
  - Label: "Soporte habilitado"
  - Toggle switch / checkbox
  - Indicador: "Plan default" vs "Override personalizado"
  - Botón "Reset a plan" cuando hay override
- Usa los endpoints `GET/PATCH .../support-access`

---

## Paso 4 — Límite mensual de tickets

### 4a. Migración SQL (Admin DB)

```sql
ALTER TABLE nv_accounts ADD COLUMN IF NOT EXISTS tickets_per_month integer DEFAULT NULL;
```

### 4b. Service (`apps/api/src/support/support.service.ts`)

- Nueva constante:
  ```typescript
  static readonly PLAN_MONTHLY_DEFAULTS: Record<string, number> = {
    starter: 0,
    growth: 5,
    enterprise: 15,
  };
  ```

- Nuevo método `enforceMonthlyTicketLimit(accountId)`:
  - Lee `plan_key` y `tickets_per_month` de `nv_accounts`
  - Cuenta tickets con `created_at >= primer día del mes actual`
  - Lanza `ForbiddenException` code `MONTHLY_TICKET_LIMIT_REACHED` si se excede
  - Fail-open en caso de error de conteo

- En `createTicket()`: agregar después de `enforceActiveTicketLimit()`:
  ```typescript
  await this.enforceMonthlyTicketLimit(accountId);
  ```

- Extender `getAccountTicketLimitInfo()` para incluir:
  - `monthly_plan_default`, `monthly_custom_limit`, `monthly_effective_limit`, `monthly_count`

- Extender `setAccountTicketLimit()` para aceptar también `tickets_per_month`

### 4c. Admin Controller (`apps/api/src/support/support-admin.controller.ts`)

- Extender `PATCH /admin/support/accounts/:accountId/ticket-limit` body para aceptar `tickets_per_month`
- El response de `GET .../ticket-limit` ya incluirá los datos mensuales

### 4d. Frontend Admin (`apps/admin/.../SupportConsoleView.jsx`)

- Extender el `TicketLimitRow` existente para mostrar:
  - Fila adicional: "Tickets este mes: X / Y"
  - Barra de progreso mensual (mismos colores: verde <60%, amarillo 60-90%, rojo ≥90%)
  - Input para editar `tickets_per_month` custom (junto al de `ticket_limit`)
  - Reset a plan default

### 4e. Frontend Web (`apps/web/.../SupportTickets/index.jsx`)

- Mostrar indicador de límites al crear ticket (en `IntakeChat.jsx` o en la vista principal):
  - "Tickets activos: 2/3"
  - "Tickets este mes: 4/5"
  - Si se alcanza el límite, mostrar mensaje explicativo en vez del botón "Nuevo ticket"

---

## Archivos críticos

| Archivo | Cambios |
|---------|---------|
| `apps/api/src/support/types/ticket.types.ts` | `cancelled` en TicketStatus, TicketEventType, TICKET_TRANSITIONS, STATUS_LABELS |
| `apps/api/src/support/support.service.ts` | TENANT_SAFE_COLUMNS, cancelTenantTicket, enforceMonthlyTicketLimit, toggleSupportAccess, extender getAccountTicketLimitInfo |
| `apps/api/src/support/support.controller.ts` | Endpoint PATCH cancel |
| `apps/api/src/support/support-admin.controller.ts` | Endpoints toggle soporte, extender ticket-limit con monthly |
| `apps/web/src/components/admin/SupportTickets/index.jsx` | Botón cancelar, status cancelled, indicador de límites |
| `apps/web/src/components/admin/SupportTickets/style.jsx` | Color para cancelled |
| `apps/web/src/components/admin/SupportTickets/IntakeChat.jsx` | Mostrar límites disponibles |
| `apps/admin/src/pages/AdminDashboard/SupportConsoleView.jsx` | Status cancelled, toggle soporte, límite mensual en TicketLimitRow |
| Migración SQL (Admin DB) | CHECK constraint + columna `tickets_per_month` |

---

## Verificación

1. **Seguridad**: `GET /client-dashboard/support/tickets` → response NO contiene `ai_analysis`
2. **Cancel**: Crear ticket → cancelar → verificar `status='cancelled'` y evento `cancelled` → reabrir → verificar `status='open'`
3. **Toggle**: Desactivar soporte para una tienda → `POST /client-dashboard/support/tickets` retorna 403 `FEATURE_GATED`
4. **Límite mensual**: Setear `tickets_per_month=1` → crear 1 ticket → intentar crear otro → 403 `MONTHLY_TICKET_LIMIT_REACHED`
5. **Frontend web**: Botón "Cancelar" visible en ticket open, badge rojo para cancelled, indicador de límites
6. **Frontend admin**: Toggle soporte en sidebar, límite mensual en TicketLimitRow, status cancelled en dropdown y colores
7. **Tests**: `npm run test` en API
8. **Build**: `npm run lint && npm run typecheck && npm run build` en API, Web y Admin

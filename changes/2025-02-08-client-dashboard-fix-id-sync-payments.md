# Fix Client Dashboard – ID Desync, Pagos Vacíos, Null Safety

- **Autor:** agente-copilot
- **Fecha:** 2025-02-08
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Archivos modificados:**
  - `apps/api/src/admin/admin.service.ts` (getAccountDetails)
  - `apps/api/src/admin/admin-client.controller.ts` (payments, invoices, usage-months)
  - `apps/admin/src/pages/ClientDetails/hooks/useClientData.js`
  - `apps/admin/src/pages/ClientDetails/index.jsx`

---

## Contexto del problema

Después de 7 PRs de refactorización del dashboard de detalle de cliente (ClientDetails),
**todo el dashboard quedó roto**: sin datos de estado, pagos vacíos, suscripciones invisibles
y status badges sin información. El usuario reportó "Todo roto, ningun req anda, no hay datos
bien sincronizados, las suscripciones siguen sin verse en los pagos".

---

## Diagnóstico: 5 Causas Raíz

### P1 – CRÍTICO: ID Desync entre Admin DB y Backend DB

**Cómo**: La URL de ClientDetails pasa `client.id` (Backend DB, ej: `f2d3f270-...`).
El hook `useClientData` intentaba resolver un `accountId` para llamar a
`GET /admin/accounts/:id/details`. Cuando `nv_account_id` es null (caso Pablo, cliente
pre-onboarding), el fallback usaba `client.id` como accountId. Pero `getAccountDetails`
buscaba en `nv_accounts` con ese ID → no encuentra → 404 → todos los badges de estado
quedan null.

**Mapeo real en DB:**
| Backend DB clients | nv_accounts (Admin DB) |
|---|---|
| Pablo: id=`f2d3f270`, nv_account_id=**null** | — (no existe) |
| Tienda Test: id=`19986d95`, nv_account_id=`7f62b1e5` | id=`7f62b1e5`, status=approved |

### P2 – CRÍTICO: Tabla `payments` vacía (0 rows)

El endpoint `getClientPayments` solo consultaba la tabla `payments` de Admin DB.
Esa tabla tiene **0 registros** porque no se registraron pagos manuales. Resultado:
la sección de pagos siempre mostraba "Sin pagos registrados".

### P3 – MEDIO: Suscripciones no visibles en pagos

Los pagos de suscripción de MercadoPago se registran en `nv_billing_events`
(keyed by `account_id`, es decir el ID de `nv_accounts`). El endpoint de pagos
**nunca consultaba esa tabla**, por lo que los pagos de suscripción no aparecían.

### P4 – MEDIO: Edge Functions fallando

- `admin-client-diff`: CORS bloqueado desde `novavision.lat`
- `admin-sync-usage`: HTTP 500
- `admin-sync-invoices`: HTTP 500

Estas son funciones de Supabase Edge Functions, fuera del scope del código NestJS.
Los cambios en el backend hacen que los endpoints NestJS sean resilientes
independientemente del estado de las Edge Functions.

### P5 – BAJO: Pablo sin `nv_account_id`

Cliente pre-onboarding con `nv_account_id = null`. Sin fallback seguro,
todos los derivados de cuenta (accountStatus, subscriptionStatus, plan_key) eran null.

---

## Soluciones implementadas

### FIX BE-1: `getAccountDetails` con fallback (admin.service.ts)

**Qué cambió:** Cuando la búsqueda en `nv_accounts` por el ID recibido falla, ahora:
1. Consulta Backend DB `clients` WHERE `id = accountId` → obtiene `nv_account_id`
2. Si lo encuentra, reintenta en `nv_accounts` con ese ID
3. Si no existe cuenta alguna, retorna un objeto null-safe con valores default
   en lugar de lanzar `NotFoundException`

**Por qué:** El frontend siempre envía el Backend client.id. Para clientes con
`nv_account_id` (ej: Tienda Test), necesitamos resolver la indirección.
Para clientes sin cuenta (ej: Pablo), necesitamos degradación graceful, no un 404.

**Código clave:**
```typescript
// Fallback: buscar en Backend DB clients para obtener nv_account_id
const backendClient = await this.dbRouter.getBackendClient();
const { data: clientRow } = await backendClient
  .from('clients').select('nv_account_id').eq('id', accountId).maybeSingle();

if (clientRow?.nv_account_id) {
  // Reintentar con el ID correcto
  resolvedId = clientRow.nv_account_id;
  // ... retry nv_accounts lookup
}

// Si aún no hay cuenta → devolver defaults null-safe
return {
  account: { id: null, slug: null, plan_key: null },
  subscription: null,
  catalog_counts: { products: 0, categories: 0, banners: 0 },
  // ... todos los campos con valores seguros
};
```

### FIX BE-2: Pagos unificados + dual-ID para invoices/usage (admin-client.controller.ts)

**Qué cambió:** 3 endpoints reescritos:

#### a) `getClientPayments` – Merge legacy + billing events
- Agregado helper privado `resolveIds(clientId)`: consulta Backend DB para obtener
  tanto el `backendClientId` como el `accountId` (nv_account_id).
- Consulta `payments` (legacy manual) con `client_id = backendClientId`
- Consulta `nv_billing_events` con `account_id = accountId` (si existe)
- Mapea billing events al mismo shape que payments legacy:
  ```typescript
  { id, type: event_type, amount, paid_at, method: provider, note: admin_note, source: 'billing_event' }
  ```
- Mergea y ordena por fecha desc

**Por qué:** Las dos fuentes de pagos usan IDs diferentes (`client_id` vs `account_id`).
El merge permite mostrar TODOS los pagos en una sola tabla.

#### b) `getClientInvoices` – Fallback dual-ID
- Intenta primero con `client_id = clientId`
- Si no hay resultados y existe `accountId`, reintenta con `client_id = accountId`

#### c) `getClientUsageMonths` – Misma estrategia dual-ID
- Misma lógica de fallback que invoices

**Por qué:** Las Edge Functions de sync escriben `client_id` usando el Backend DB ID.
Pero si por algún motivo se usó el nv_account_id (inconsistencia de datos), el fallback
lo cubre.

### FIX FE-1: null-safe account status (useClientData.js)

**Qué cambió:** La derivación de `accountStatus` y `subscriptionStatus` ahora tiene
fallbacks basados en los campos del cliente Backend:

```javascript
// Antes: dependía 100% de accountDetails → crash si null
// Ahora:
accountStatus: accountDetails?.status
  ?? (client?.is_active ? 'approved' : 'suspended'),
subscriptionStatus: accountDetails?.subscription?.status
  ?? (client?.plan_paid_until ? 'active' : 'past_due'),
```

**Por qué:** Para clientes pre-onboarding sin `nv_accounts`, derivamos un estado
razonable a partir de lo que sí tenemos (is_active, plan_paid_until).

### FIX FE-2: Columna "Origen" en tabla de pagos (ClientDetails/index.jsx)

**Qué cambió:**
- Nueva columna "Origen" en la tabla de pagos
- Muestra "Suscripción" (azul, bold) para pagos de `nv_billing_events`
- Muestra "Manual" (gris) para pagos legacy
- Formateo null-safe de fechas y montos

**Por qué:** Con el merge de dos fuentes de pago, el usuario necesita distinguir
el origen. También protege contra `paid_at = null` y `amount = null`.

---

## Diagrama de resolución de IDs

```
URL: /clients/:clientId (Backend DB client.id)
         │
         ▼
   ┌─ resolveIds(clientId) ─┐
   │  Backend DB clients     │
   │  WHERE id = clientId    │
   │  → nv_account_id        │
   └─────────┬───────────────┘
             │
   ┌─────────┴──────────────────────────┐
   │                                     │
   ▼ backendClientId                     ▼ accountId (nv_account_id)
   │                                     │
   ├─ payments (legacy)                  ├─ nv_billing_events
   ├─ invoices (primary)                 ├─ nv_accounts
   └─ client_usage_month (primary)       └─ subscriptions
                                         └─ invoices (fallback)
                                         └─ client_usage_month (fallback)
```

---

## Validación

### Lint & Typecheck
- API lint: 0 errores (769 warnings pre-existentes, todos `no-explicit-any`)
- API typecheck: `tsc --noEmit` limpio
- Admin lint: limpio

### Cómo probar (local)

1. `cd apps/api && npm run start:dev`
2. `cd apps/admin && npm run dev`
3. Abrir Admin Dashboard → Ir a detalle de cualquier cliente
4. **Verificar status badges**: deben mostrar estado incluso para clientes sin `nv_account_id`
5. **Verificar pagos**: debe mostrar pagos de suscripción (billing_events) + manuales separados por "Origen"
6. **Verificar invoices/usage**: deben cargar incluso si el client_id no coincide directamente

### Datos de prueba (DB real)

| Entidad | ID | Nota |
|---|---|---|
| Pablo (Backend) | `f2d3f270-...` | nv_account_id=null, pre-onboarding |
| Tienda Test (Backend) | `19986d95-...` | nv_account_id=`7f62b1e5-...` |
| nv_accounts | `7f62b1e5-...` | status=approved, subscription active |
| invoices | client_id=`f2d3f270-...` | 1 factura (month=2025-11) |
| payments (legacy) | — | 0 rows |
| nv_billing_events | — | 0 rows |

---

## Notas de seguridad

- El helper `resolveIds` usa `DbRouterService.getBackendClient()` que opera con
  SERVICE_ROLE_KEY; nunca se expone al frontend.
- Los endpoints siguen validados por `SuperAdminGuard` (solo super_admin puede acceder).
- No se modificaron políticas RLS ni se abrieron accesos.

---

## Limitaciones conocidas / Fuera de scope

- **Edge Functions** (`admin-client-diff`, `admin-sync-usage`, `admin-sync-invoices`):
  siguen fallando (CORS / 500). Son funciones Supabase, no NestJS. Requieren fix separado.
- **`nv_billing_events` vacía**: Los pagos de suscripción solo aparecerán cuando
  MercadoPago procese un pago y el webhook lo registre. Actualmente la tabla está vacía
  porque la suscripción de prueba no ha generado cobros reales.
- **Pablo sin nv_account_id**: Se necesita either (a) correr el onboarding para Pablo,
  o (b) asignarle un nv_account_id manualmente. Los fixes hacen que el dashboard funcione
  sin él, pero con datos limitados.

---

## Riesgos y rollback

- **Riesgo bajo**: Los cambios son aditivos (agregan fallbacks, no eliminan lógica existente).
- **Rollback**: revertir los 4 archivos a su versión previa en la rama.
- **Performance**: `resolveIds` hace 1 query extra a Backend DB por cada request de
  payments/invoices/usage. Es aceptable dado que son endpoints admin de baja frecuencia.

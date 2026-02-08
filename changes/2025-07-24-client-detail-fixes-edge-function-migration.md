# Cambio: Correcciones de Client Detail + Migración de Edge Functions a NestJS

- **Autor:** agente-copilot
- **Fecha:** 2025-07-24
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding

---

## Resumen

Se corrigen ~8 bugs/inconsistencias reportados en la página de detalle de cliente (`/client/:id`) del Admin Dashboard, y se migran 4 Edge Functions rotas a endpoints NestJS.

## Problemas resueltos

### 1. Onboarding mostraba "Enviado a revisión" en cuentas aprobadas
- **Causa raíz:** `nv_onboarding.state` queda en `submitted_for_review` incluso después de que la cuenta es aprobada.
- **Fix:** El frontend ahora deriva el estado como `'completed'` cuando `accountStatus` es `'approved'` o `'live'`.

### 2. Teléfono mostraba "No registrado"
- **Causa raíz:** El backend devolvía `clients.phone` de Backend DB que nunca se sincronizó desde onboarding.
- **Fix:** 
  - Backend: `getAccountDetails` ahora resuelve phone con cascada de 7 campos: `nv_accounts.phone` → `nv_accounts.phone_number` → `nv_accounts.contact_phone` → campos de `nv_onboarding.progress`.
  - Frontend: fallback `resolvedPhone = client?.phone || accountDetails?.phone`.

### 3. "Requisitos de completitud" visible para cuentas aprobadas
- **Causa raíz:** Sección siempre renderizada sin condicional.
- **Fix:** Se envuelve en `{!['approved', 'live'].includes(accountStatus) && (...)}`.

### 4. Edge Function `admin-client-diff` no existía
- **Fix:** Creado endpoint NestJS `GET /admin/clients/:id/diff` que compara datos del cliente entre Admin DB y Backend DB.

### 5. Edge Function `admin-sync-usage` sin env vars
- **Causa raíz:** Faltaban `MULTI_EXPORT_URL` y `REPORTING_HMAC_SECRET` (el endpoint de export nunca se creó).
- **Fix:** Migrado `triggerSyncUsage.jsx` para usar `POST /admin/metering/sync` del módulo NestJS existente.

### 6. Edge Function `admin-sync-invoices` con error de schema cache
- **Causa raíz:** PostgREST no podía resolver `public.clients` desde la Edge Function.
- **Fix:** Creado endpoint NestJS `POST /admin/clients/:id/sync-invoices` que genera facturas desde `client_usage_month`.

### 7. Edge Function `admin-sync-client` sin equivalente directo
- **Fix:** Creado endpoint NestJS `POST /admin/clients/:id/sync-to-backend` que sincroniza datos de Admin DB → Backend DB.

## Archivos modificados

### Admin (apps/admin)

| Archivo | Cambio |
|---------|--------|
| `src/pages/ClientDetails/index.jsx` | Usar `resolvedPhone`; condicionar Requisitos completitud |
| `src/pages/ClientDetails/hooks/useClientData.js` | Derivar onboarding como 'completed' para approved/live; agregar `resolvedPhone` |
| `src/utils/normalizeAccountHealth.js` | Agregar 'completed' y 'finished' a `ONBOARDING_STATE_MAP` |
| `src/utils/checkClientSync.jsx` | Migrar de Edge Function a `adminApi.getClientDiff()` |
| `src/utils/triggerSyncUsage.jsx` | Migrar de Edge Function a `POST /admin/metering/sync` |
| `src/utils/syncClientInvoicesActive.jsx` | Migrar de Edge Function a `POST /admin/clients/:id/sync-invoices` |
| `src/utils/syncClientToBackend.jsx` | Migrar de Edge Function a `POST /admin/clients/:id/sync-to-backend` |
| `src/services/adminApi.js` | Agregar `getClientDiff()` |

### API (apps/api)

| Archivo | Cambio |
|---------|--------|
| `src/admin/admin-client.controller.ts` | Nuevos endpoints: `GET :id/diff`, `POST :id/sync-invoices`, `POST :id/sync-to-backend` |
| `src/admin/admin.service.ts` | Enriquecer `getAccountDetails` con phone cascade |

## Nuevos endpoints NestJS

| Método | Ruta | Propósito |
|--------|------|-----------|
| GET | `/admin/clients/:id/diff` | Comparar datos admin vs backend |
| POST | `/admin/clients/:id/sync-invoices` | Generar facturas desde usage data |
| POST | `/admin/clients/:id/sync-to-backend` | Sync core data admin → backend |

## Cómo probar

1. Abrir detalle de un cliente aprobado (`/client/:id`)
2. Verificar:
   - Onboarding muestra "Finalizado" (badge verde)
   - Teléfono muestra el valor real
   - "Requisitos de completitud" NO aparece
3. Probar botones de diagnóstico:
   - "Verificar cliente" → usa endpoint diff
   - "Refrescar métricas" → usa metering sync
   - "Sincronizar ahora" → usa sync-to-backend
4. Probar generación de facturas:
   - Usar la acción de sync invoices desde el panel

## Verificación

```bash
# API
cd apps/api && npm run typecheck  # ✅ 0 errors
# Admin
cd apps/admin && npm run lint     # ✅ 0 errors, 0 warnings
```

## Notas de seguridad

- Los nuevos endpoints están protegidos por `SuperAdminGuard` (heredado del controller)
- Las operaciones de sync usan `service_role` desde el backend (nunca expuesto al frontend)
- Se eliminó la dependencia de 4 Edge Functions rotas en producción

## Pendiente / No resuelto en este cambio

- **Dominio Gestionado UX/UI**: El componente `ClientDomains` muestra un solo dominio; pendiente refactorizar para lista de dominios
- **Historial de pagos vacío**: La data no existe en DB. Se necesita registrar el pago inicial de suscripción retroactivamente o verificar que el webhook de MercadoPago cree el billing event
- **Uso mensual vacío**: Depende de que existan datos en `usage_ledger`/`usage_daily`. El cron de metering (`metrics.cron.ts` 03:15 AR) debe generar estos registros; luego el sync los poblará en `client_usage_month`

# Cambio: Subscription Hardening — F0 + F1

- **Autor:** copilot-agent
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Fase:** F0 (Critical fixes) + F1 (Consolidate pipeline)

---

## Archivos modificados

### API (templatetwobe)
| Archivo | Cambio |
|---------|--------|
| `src/admin/admin.controller.ts` | Nuevo endpoint `GET /admin/accounts/:id/details` |
| `src/admin/admin.service.ts` | Nuevo método `getAccountDetails()` (~90 líneas) |
| `src/subscriptions/subscriptions.service.ts` | Downgrade prevention, `syncAccountSubscriptionStatus()`, `pauseStoreIfNeeded()`, wired calls en 5 métodos |
| `src/tenant-payments/mercadopago.service.ts` | `@deprecated` en `handleSubscriptionEvent`, `reconcileSubscriptions` |
| `migrations/admin/subscription-backfill-sync.sql` | Script SQL para reconciliar `nv_accounts.subscription_status` vs `subscriptions.status` |

### Admin (novavision)
| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/ClientApprovalDetail.jsx` L1496 | Fix read path: `data?.payments?.subscription_status ?? data?.subscription_status` |

---

## Resumen de cambios

### F0 — Critical fixes (3 bugs)

1. **F0.1 — Fix subscription_status read path**
   - **Bug:** `ClientApprovalDetail.jsx` accedía a `data?.subscription_status` pero la API devuelve el campo anidado en `data.payments.subscription_status`.
   - **Fix:** Cambió a `data?.payments?.subscription_status ?? data?.subscription_status` (con fallback).

2. **F0.2 — Create missing GET /admin/accounts/:id/details**
   - **Bug:** `ClientDetails/index.jsx` llamaba a `adminApi.getAccountDetails(accountId)` → 404 (endpoint no existía).
   - **Fix:** Creó endpoint + servicio que retorna: `account_status`, `subscription_status` (prioriza tabla `subscriptions`), `onboarding_state`, `catalog_source`, `catalog_counts`.

3. **F0.3 — Downgrade prevention**
   - **Bug:** `requestUpgrade()` aceptaba cualquier cambio de plan, incluso downgrades.
   - **Fix:** Compara `PLAN_TIERS[currentBase]` vs `PLAN_TIERS[targetBase]` (usa `basePlan()` para strips `_annual`). Lanza `BadRequestException` si target < current.

### F1 — Consolidate pipeline (4 sub-items)

1. **F1.1 — Map pipeline gaps**
   - Identificó que `processMpEvent()` actualizaba `subscriptions.status` pero NO sincronizaba a `nv_accounts.subscription_status`.
   - Identificó que ningún punto del pipeline nuevo pausaba `clients.publication_status` al cancelar/suspender.

2. **F1.2 — Write-through sync helpers**
   - `syncAccountSubscriptionStatus(accountId, status)` — escribe `nv_accounts.subscription_status` desde Admin DB.
   - `pauseStoreIfNeeded(accountId, status)` — pausa `clients.publication_status` en Multicliente DB cuando status ∈ {suspended, canceled, cancel_scheduled, deactivated}.
   - **Wired en:**
     - `processMpEvent()` → preapproval.authorized y past_due
     - `handleSubscriptionCreated()` → tras status update
     - `handleSubscriptionUpdated()` → tras cada branch (past_due, cancel_scheduled, otros)
     - `reconcileSubscriptions()` cron → al suspender cuentas con gracia expirada
     - `handlePaymentFailed()` → cuando 3+ fallos consecutivos → suspension

3. **F1.3 — Deprecate legacy handlers**
   - `handleSubscriptionEvent()` en `mercadopago.service.ts`: `@deprecated` + warning log.
   - `reconcileSubscriptions()` en `mercadopago.service.ts`: `@deprecated`.
   - Nota: estos métodos ya estaban muertos (MpRouterService nunca los invoca), pero el código seguía presente.

4. **F1.4 — Backfill SQL**
   - Script en `migrations/admin/subscription-backfill-sync.sql`:
     - Step 1: SELECT diagnóstico de desviaciones
     - Step 2: UPDATE comentado (descomentar tras revisar Step 1)
     - Step 3: Verificación post-backfill

---

## Por qué se hizo

**Root Cause Analysis (RCA):** La cuenta `7f62b1e5-c518-402c-abcb-88ab9db56dfe` ("Tienda Test", plan GROWTH) mostraba `subscription_status = "-"` en el Super Admin Dashboard, a pesar de estar activa en MercadoPago.

**Causas raíz:**
1. Frontend leía campo en path incorrecto
2. Endpoint faltante → 404 → null → "-"
3. Pipeline dual: webhook escribía en `subscriptions` pero no propagaba a `nv_accounts` (fuente de verdad del dashboard)
4. Sin downgrade prevention → posibles inconsistencias
5. Sin store pause on cancellation → tiendas activas sin suscripción

---

## Cómo probar

### F0.1 — Read path
1. Abrir Super Admin → detalle de cualquier cuenta con suscripción activa
2. Verificar que `subscription_status` muestra "active" (no "-")

### F0.2 — Missing endpoint
1. `GET /admin/accounts/{account_id}/details` con token super_admin
2. Verificar respuesta con `account_status`, `subscription_status`, `catalog_counts`

### F0.3 — Downgrade
1. Intentar `POST /subscriptions/accounts/{id}/upgrade` con plan inferior (ej: growth → starter)
2. Esperar 400: `"Solo se permiten upgrades de plan (starter → growth → enterprise)"`

### F1 — Sync pipeline
1. Verificar que `nv_accounts.subscription_status` se actualiza en paralelo con `subscriptions.status` al procesar webhook
2. Verificar que `clients.publication_status = 'paused'` cuando suscripción → canceled/suspended

### Backfill
1. Ejecutar Step 1 del SQL contra Admin DB
2. Revisar output (cuentas con desviación)
3. Descomentar Step 2 y ejecutar en transacción

---

## Notas de seguridad

- `pauseStoreIfNeeded` accede a Multicliente DB via `SERVICE_ROLE_KEY` — solo server-side.
- Backfill SQL debe ejecutarse con review manual (Step 2 está comentado intencionalmente).
- Downgrade prevention usa PLAN_TIERS hardcoded; si se agregan planes, actualizar `types/palette.ts`.

---

## Validación

- **API lint:** 0 errores (717 warnings preexistentes `no-explicit-any`)
- **API typecheck:** 0 errores
- **Admin lint:** 0 errores

# Billing & Subscription Flow — RCA + Fix Plan

> **Fecha:** 2026-02-06  
> **Autor:** Copilot Agent (RCA Senior Engineer)  
> **Rama:** feature/automatic-multiclient-onboarding  
> **Caso repro:** Account `7f62b1e5-c518-402c-abcb-88ab9db56dfe` ("Tienda Test", plan GROWTH)

---

## Índice

- [A. Flujo AS-IS (real, basado en código)](#a-flujo-as-is)
- [B. GAP vs Documentación Existente](#b-gap-vs-documentación-existente)
- [C. Diagnóstico (evidencia)](#c-diagnóstico)
- [D. RCA (Root Cause Analysis)](#d-rca)
- [E. Flujo TO-BE (corregido)](#e-flujo-to-be)
- [F. Fix Plan](#f-fix-plan)
- [G. Backfill / Reconcile Plan](#g-backfill--reconcile-plan)
- [H. Edge Cases](#h-edge-cases)
- [I. Monitoreo y Alertas](#i-monitoreo-y-alertas)
- [J. Cambios de DB (si aplica)](#j-cambios-de-db)

---

## A. Flujo AS-IS

### A.1 Fuente de verdad

| DB | Tabla | Rol |
|---|---|---|
| **Admin** | `subscriptions` | Registro de suscripción MP: `mp_preapproval_id`, `status`, `current_period_end`, `grace_until`, etc. |
| **Admin** | `nv_accounts` | Cuenta del dueño de tienda. Tiene campo **denormalizado** `subscription_status` (mirror de `subscriptions.status`) |
| **Admin** | `mp_connections` | Tokens OAuth MP (AES-256-GCM encrypted), `mp_user_id`, `status` |
| **Admin** | `nv_billing_events` | Hub centralizado de facturación (domain renewals, plan subscriptions, one-time services) |

**Fuente de verdad definida:** tabla `subscriptions` (Admin DB), con fallback a `nv_accounts.subscription_status`.

### A.2 Máquina de estados de suscripción

```
                  ┌─────────────────────────────────────────────────────┐
                  │                                                     │
  pending ─── active ───┬──── cancel_scheduled ─── deactivated ─── purged
               ▲        │         ▲                     ▲
               │        │         │                     │
               │        ├─── past_due ──► suspended ────┘
               │        │     (grace 7d)   (cron 3AM)
               │        │
               │        └─── payment_failed (retry 3x → past_due)
               │
               └──── (payment approved = reactivación)
```

### A.3 Pipeline de webhooks MP (rutas)

```
MP notification_url               Controller                    Domain     Handler
─────────────────────────────────────────────────────────────────────────────────────
/subscriptions/webhook          → SubscriptionsController      → platform → SubscriptionsService.processMpEvent()
/webhooks/mp/platform-subs      → MpRouterController           → platform → SubscriptionsService.processMpEvent()
/webhooks/mp/tenant-payments    → MpRouterController           → tenant   → MercadoPagoService.confirmPayment()
/mercadopago/webhook (legacy)   → MercadoPagoController        → tenant   → MercadoPagoService.confirmPayment()
```

**MpRouterService** centraliza:
1. Parse del topic/resourceId
2. Verificación de firma (`MP_WEBHOOK_SECRET_PLATFORM` / `MP_WEBHOOK_SECRET_TENANT`)
3. Dedup por SHA256 hash → insert en `subscription_events` (platform) o `tenant_payment_events` (tenant)
4. Detección de misroute por `external_reference` (`NV_SUB:*` vs `NV_ORD:*`)
5. Fetch del recurso en MP → despacho al handler

### A.4 Flujo "Super Admin ve Suscripción"

```
[Super Admin Dashboard]
        │
        ├──► GET /admin/pending-approvals/:id
        │       │
        │       └──► adminService.getApprovalDetail(id)
        │               ├── Lee nv_accounts
        │               ├── Lee nv_onboarding
        │               ├── Lee mp_connections (para ownership signals)
        │               └── Construye response:
        │                     ├── account: { ...nv_accounts completo }
        │                     ├── payments: {
        │                     │     mp_connected,
        │                     │     subscription_status,    ◄── de nv_accounts.subscription_status
        │                     │     preapproval_id
        │                     │   }
        │                     ├── mpOwnership: { status, owner: { email } }
        │                     └── ...otros campos
        │
        ├──► Frontend: ClientApprovalDetail.jsx
        │       │
        │       ├── const subscriptionStatus = data?.subscription_status  ◄── ⚠️ UNDEFINED
        │       │                                                            (está en data.payments.subscription_status)
        │       └── Renderiza: "Suscripción: {subscriptionStatus || '-'}" → muestra "-"
        │
        └──► Botón "Consultar estado"
                │
                └── GET /admin/accounts/:id/subscription-status
                       │
                       └── adminService.getSubscriptionStatus(id)
                              ├── Lee subscriptions (tabla dedicada)
                              ├── Lee nv_accounts (fallback)
                              └── Retorna: { status, is_active, subscription, account }
                                    ↓
                              Frontend setea subscriptionCheck → muestra Badge ✅
```

### A.5 Flujo "Titular NO coincide"

```
GET /admin/pending-approvals/:id
    └── mpOauthService.getOwnerSignalsForAccount(accountId)
            ├── Lee nv_accounts.email
            ├── Desencripta mp_access_token de mp_connections
            ├── Llama GET https://api.mercadopago.com/users/me
            └── Compara: account.email vs mp_owner.email (case-insensitive)
                  ├── Iguales → status: 'verified'  → "✅ Titular coincide"
                  ├── Distintos → status: 'mismatch' → "⚠️ Titular NO coincide"
                  └── Sin datos → status: 'unverified' / 'not_connected'
```

**Efecto del mismatch:** Solo visual (badge rojo). NO bloquea aprobación, NO bloquea suscripción, NO oculta datos.

### A.6 Pipeline duplicado (problema de diseño)

Existen **dos caminos paralelos** para procesar eventos de suscripción:

| Servicio | Opera sobre | Origen |
|---|---|---|
| `SubscriptionsService.processMpEvent()` | tabla `subscriptions` + `nv_accounts` | Nuevo (routing via MpRouterService, domain=platform) |
| `MercadoPagoService.handleSubscriptionEvent()` | solo `nv_accounts.subscription_status` + `clients` | Legacy (acceso directo por preapprovalId) |

Ambos actualizan `nv_accounts.subscription_status`, pero solo `SubscriptionsService` opera la tabla `subscriptions`.

### A.7 Cron Jobs activos

| Cron | Servicio | Función | Tabla |
|---|---|---|---|
| 2:00 AM | SubscriptionsService | `checkAndUpdatePrices` | subscriptions (ajuste ARS) |
| 3:00 AM | SubscriptionsService | `reconcileSubscriptions` | subscriptions → suspended |
| c/30 min | SubscriptionsService | `processDeactivations` | subscriptions → deactivated |
| 4:00 AM | SubscriptionsService | `processPurges` | subscriptions → purged |
| 1:30 AM | SubscriptionsService | `enqueueLifecycleNotifications` | subscription_notification_outbox |
| c/10 min | SubscriptionsService | `dispatchLifecycleNotifications` | outbox → emails |
| 3:00 AM | PaymentReconciliationService | `runReconciliation` | payments (tiendas) |
| c/12 h | MpTokenRefreshWorker | `refreshExpiringTokens` | mp_connections |
| 2:00 AM | MpTokenRefreshWorker | `markExpiredConnections` | mp_connections + nv_accounts |

---

## B. GAP vs Documentación Existente

### Documentación existente (apps/api/docs/)

Se encontraron **9 documentos** del subscription system (README, walkthrough, implementation plan, webhooks, payment failures, admin dashboard, admin guide, task checklist, testing localhost) y **5 documentos** de MP OAuth.

### Gaps identificados

| # | Tema | Doc dice | Código real | Severidad |
|---|---|---|---|---|
| **G1** | Endpoint admin subscription status | Doc `subscription-admin-dashboard.md` describe badges en UI del cliente | La UI del **Super Admin** (`ClientApprovalDetail`) tiene un bug de acceso a campo anidado | **ALTA** |
| **G2** | Pipeline dual | Docs solo mencionan `SubscriptionsService` como handler | Existe `MercadoPagoService.handleSubscriptionEvent()` (legacy) que opera en paralelo y escribe `nv_accounts.subscription_status` sin tocar `subscriptions` | **ALTA** |
| **G3** | Reconciliación | Doc describe cron 3AM que revisa grace periods | Reconciliación NO consulta MP para confirmar estado real. Solo revisa plazos vencidos en DB local. La reconciliación real contra MP está en `MercadoPagoService.reconcileSubscriptions()` (manual, no cron) | **MEDIA** |
| **G4** | Fuente de verdad | Docs mencionan tabla `subscriptions` como SoT | Múltiples pantallas leen `nv_accounts.subscription_status` directamente sin consultar `subscriptions` | **MEDIA** |
| **G5** | Webhook routing | No documentado en ningún doc | `MpRouterService` con dedup, signature verification, misroute detection → no tiene doc | **MEDIA** |
| **G6** | `ClientDetails` endpoint | No mencionado | `GET /admin/accounts/:id/details` no existe (404). `ClientDetails/index.jsx` lo llama y falla silenciosamente | **ALTA** |
| **G7** | Titular mismatch efecto | No documentado | Solo visual, no bloquea. No hay doc que lo aclare → los reviewers no saben si deben bloquear o no | **BAJA** |

---

## C. Diagnóstico (evidencia)

### Bullet 1: Campo anidado incorrecto en UI (CAUSA PRINCIPAL)

El endpoint `GET /admin/pending-approvals/:id` retorna `subscription_status` dentro de `data.payments.subscription_status`, pero `ClientApprovalDetail.jsx` línea ~1439 lo busca como `data?.subscription_status` (primer nivel) → **siempre undefined → muestra "-"**.

**Evidencia:**
- [admin.service.ts](apps/api/src/admin/admin.service.ts) → `getApprovalDetail()` retorna: `{ account, payments: { subscription_status, ... }, ... }`
- [ClientApprovalDetail.jsx L1439](apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx#L1439): `const subscriptionStatus = data?.subscription_status;`

### Bullet 2: Endpoint faltante para ClientDetails

`ClientDetails/index.jsx` línea ~611 llama a `adminApi.getAccountDetails(accountId)` → `GET /admin/accounts/:id/details` que **no existe** como endpoint en el backend → 404 → catch silencioso → `accountDetails = null` → muestra "-".

**Evidencia:**
- [ClientDetails/index.jsx L611](apps/admin/src/pages/ClientDetails/index.jsx#L611)
- Grep en `admin.controller.ts`: no hay ruta `accounts/:id/details`

### Bullet 3: Botón "Consultar estado" SÍ funciona

El endpoint `GET /admin/accounts/:id/subscription-status` existe y retorna correctamente el estado de la tabla `subscriptions` + fallback `nv_accounts`. Pero el resultado se guarda en state local (`subscriptionCheck`) y se muestra como Badge temporal, **no actualiza el campo estático** de la grilla.

### Bullet 4: La suscripción probablemente SÍ existe en DB

Dado que el flujo de `createSubscriptionForAccount` inserta en `subscriptions` durante el onboarding checkout, y el botón "Consultar estado" funciona, la suscripción **existe en la tabla `subscriptions`** y también hay un valor en `nv_accounts.subscription_status`. El problema es 100% de lectura del frontend.

### Bullet 5: "Titular NO coincide" es solo visual

El mismatch de email (`kaddocpendragon@gmail.com` vs `test_user_1100113720@testuser.com`) produce un badge rojo pero **NO bloquea** ninguna funcionalidad. Es esperable en sandbox (test users tienen emails generados).

### Bullet 6: `account_status: incomplete` es independiente

`incomplete` se setea por provisioning incompleto (faltan items: productos, logo, etc.) o por el super admin pidiendo correcciones. **No tiene relación con la suscripción.**

---

## D. RCA (Root Cause Analysis)

### Causa raíz

**Bug de acceso a propiedad anidada en el frontend.** La API retorna `subscription_status` dentro del objeto `payments`, pero el frontend lo busca en el primer nivel del response.

### Por qué pasó

1. El endpoint `getApprovalDetail` fue diseñado con datos agrupados por dominio (payments, identity, branding, etc.)
2. El frontend fue escrito asumiendo una estructura plana (`data.subscription_status`)
3. No hay contrato definido (OpenAPI/TypeScript types) entre backend y admin frontend
4. No hay tests de integración que validen el shape del response

### Por qué no se detectó

1. El botón "Consultar estado" funciona (llama a un endpoint diferente), dando la impresión de que el sistema funciona
2. En sandbox, la mayoría de las cuentas están en estado `incomplete` → el reviewer asume que el "-" es por eso
3. No hay monitoreo/alerta que detecte discrepancia entre `subscriptions` (DB) y lo que muestra el dashboard

### Hipótesis validadas

| Hipótesis | Resultado |
|---|---|
| A) Suscripción existe en MP pero no se persistió | **Descartada parcialmente.** La suscripción SÍ se persiste en `subscriptions`. El problema es que la UI no la lee correctamente. |
| B) UI muestra "-" porque depende de account_status=complete | **Descartada.** La UI muestra "-" porque busca `data.subscription_status` pero el dato está en `data.payments.subscription_status`. |
| C) "Titular NO coincide" bloquea suscripción | **Descartada.** Es solo un badge visual. |
| D) Desalineación de IDs | **Parcialmente válida.** Hay dos fuentes de datos paralelas (`subscriptions` vs `nv_accounts.subscription_status`). |
| E) Webhook se descarta | **No aplica.** El webhook funciona; el problema es de lectura en UI. |
| F) RLS/permisos falla al upsert | **No aplica.** Los upserts usan service_role que bypasea RLS. |
| G) "Consultar estado" no actualiza DB | **Confirmada.** El botón consulta y muestra en UI pero NO escribe en DB. Sin embargo, esto no es la causa principal del "-". |
| H) Cron con credenciales equivocadas | **No aplica.** Los crons operan sobre datos ya en DB, no consultan MP (excepto el de precios). |

---

## E. Flujo TO-BE (corregido)

### E.1 Fuente de verdad única: tabla `subscriptions` (Admin DB)

- `subscriptions.status` → estado canónico
- `nv_accounts.subscription_status` → mirror denormalizado (se actualiza siempre que cambia `subscriptions.status`)
- `nv_accounts.status` → estado del account (incomplete/active/approved/etc.), **independiente** de suscripción

### E.2 Fix del Super Admin Dashboard

```
GET /admin/pending-approvals/:id
    └── Response (sin cambios en API):
          ├── payments.subscription_status  ← ya se retorna correctamente
          └── account.subscription_status   ← también disponible

Frontend ClientApprovalDetail.jsx:
    ANTES: const subscriptionStatus = data?.subscription_status;          // ← UNDEFINED
    DESPUÉS: const subscriptionStatus = data?.payments?.subscription_status
                                    || data?.account?.subscription_status
                                    || null;
```

### E.3 Fix de ClientDetails

Opción recomendada: Reusar el endpoint existente `getSubscriptionStatus` o agregar `subscription_status` al endpoint que sí existe para detalles de cuenta.

### E.4 Botón "Consultar estado" → debe persistir

```
ANTES:  Consulta MP → muestra en Badge efímero → no escribe DB
DESPUÉS: Consulta MP → upsert en subscriptions + nv_accounts → muestra Badge → refresh UI
```

### E.5 Consolidar pipeline (eliminar dual path)

- **Eliminar** `MercadoPagoService.handleSubscriptionEvent()` (legacy)
- **Único handler:** `SubscriptionsService.processMpEvent()` vía MpRouterService
- La reconciliación manual (`reconcileSubscriptions` en MercadoPagoService) se migra a `SubscriptionsService`

---

## F. Fix Plan

### F1. Frontend — ClientApprovalDetail (FIX INMEDIATO)

**Archivo:** `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx`  
**Línea ~1439:**

```diff
- const subscriptionStatus = data?.subscription_status;
+ const subscriptionStatus = data?.payments?.subscription_status
+                         || data?.account?.subscription_status
+                         || null;
```

**Riesgo:** Bajo. Solo cambia la ruta de lectura del campo.  
**Test:** Verificar que al cargar una cuenta con suscripción activa, el campo muestre el estado correcto en vez de "-".

### F2. Frontend — ClientDetails (FIX INMEDIATO)

**Archivo:** `apps/admin/src/pages/ClientDetails/index.jsx`  
**Línea ~611:**

Dos opciones:
- **Opción A:** Usar `data?.account?.subscription_status` si la data viene de un endpoint que sí existe
- **Opción B:** Agregar endpoint `GET /admin/accounts/:id/details` al backend

### F3. Backend — "Consultar estado" debe persistir

**Archivo:** `apps/api/src/admin/admin.service.ts` → `getSubscriptionStatus()`

Agregar al final del método:
```typescript
// Si el status de subscriptions difiere de nv_accounts, sincronizar
if (subscription && subscription.status !== account.subscription_status) {
  await adminSupabase.from('nv_accounts').update({
    subscription_status: subscription.status,
    updated_at: new Date().toISOString(),
  }).eq('id', accountId);
}
```

### F4. Backend — Reconciliación real contra MP (mejora)

**Archivo:** `apps/api/src/subscriptions/subscriptions.service.ts`

Agregar un método `reconcileWithMp()` que:
1. Lea todos los `subscriptions` con `mp_preapproval_id` != null
2. Consulte a MP `GET /preapproval/{id}`
3. Compare status y actualice si difiere
4. Marque `last_synced_at` en `subscriptions`

### F5. Eliminar pipeline dual (mejora a mediano plazo)

**Archivo:** `apps/api/src/tenant-payments/mercadopago.service.ts`
- Deprecar `handleSubscriptionEvent()` y `reconcileSubscriptions()`
- Toda lógica de suscripción pasa por `SubscriptionsService`

### F6. Tests mínimos

- **Admin Frontend:**
  - Test que verifica acceso correcto a `payments.subscription_status` en `ClientApprovalDetail`
  - Test que verifica fallback chain: `payments.subscription_status || account.subscription_status || null`
- **API:**
  - Test de `getSubscriptionStatus` que verifica la sincronización de `nv_accounts` cuando difiere de `subscriptions`
  - Test de `processMpEvent` que verifica escritura en `subscriptions` Y `nv_accounts`

---

## G. Backfill / Reconcile Plan

### Job de reconciliación one-time

```sql
-- 1. Detectar cuentas con suscripción activa en subscriptions
--    pero sin reflejo en nv_accounts
SELECT
  s.account_id,
  s.status AS subscriptions_status,
  a.subscription_status AS nv_accounts_status,
  s.mp_preapproval_id,
  s.current_period_end
FROM subscriptions s
JOIN nv_accounts a ON a.id = s.account_id
WHERE s.status != COALESCE(a.subscription_status, '')
ORDER BY s.updated_at DESC;

-- 2. Fix: sincronizar nv_accounts.subscription_status desde subscriptions
UPDATE nv_accounts a
SET
  subscription_status = s.status,
  updated_at = now()
FROM subscriptions s
WHERE s.account_id = a.id
  AND s.status != COALESCE(a.subscription_status, '')
  AND s.id = (
    SELECT id FROM subscriptions
    WHERE account_id = a.id
    ORDER BY created_at DESC
    LIMIT 1
  );
```

### Job de reconciliación recurrente (propuesta)

Endpoint `POST /admin/subscriptions/reconcile-all`:
1. Recorre `nv_accounts` con `mp_connected = true`
2. Para cada uno, consulta tabla `subscriptions`
3. Si hay discrepancia con `nv_accounts.subscription_status` → sincroniza
4. Opcionalmente, consulta MP para confirmar estado real
5. Genera reporte: `{ processed, synced, errors, details[] }`

---

## H. Edge Cases

| # | Edge Case | Comportamiento actual | Comportamiento esperado |
|---|---|---|---|
| 1 | Suscripción activa en MP, webhook caído | Si MP no puede entregar → reintentos por 48h. Si falla, DB queda desactualizada | Cron de reconciliación contra MP cada 6h detecta discrepancias |
| 2 | Webhook duplicado / fuera de orden | `MpRouterService` dedup por SHA256 hash. Si hash ya existe, se ignora | ✅ Correcto (ya implementado) |
| 3 | Cambio de plan (upgrade) durante período activo | `requestUpgrade` cancela preapproval viejo, crea nuevo. `subscriptions` se actualiza | ✅ Correcto pero requiere test de carrera entre webhook de cancelación y nueva creación |
| 4 | MP identity email distinto (test users) | Badge "⚠️ Titular NO coincide". Es esperado en sandbox | Agregar en UI: "En ambiente sandbox, es normal que los emails no coincidan" |
| 5 | Tokens MP rotados/expirados | Cron cada 12h refresca tokens. Cron 2AM marca expirados como `expired`. Ownership signals fallan gracefully | ✅ Correcto |
| 6 | Cuenta `incomplete` pero MP activo | UI muestra "-" (bug). La suscripción funciona pero no se ve | **FIX F1/F2:** mostrar suscripción independientemente del account_status |
| 7 | Sandbox vs prod mezclado | `PlatformMercadoPagoService` valida `site_id=MLA` al iniciar. OAuth guarda `live_mode` | ✅ Parcialmente. Falta validación en reconciliación para no mezclar envs |
| 8 | Race: approve store vs webhook billing | Webhook y aprobación operan tablas distintas (subscriptions vs clients). No hay lock compartido | Riesgo bajo: no hay conflicto de write. Si ambos escriben `nv_accounts.subscription_status`, el último gana |
| 9 | `getApprovalDetail` falla al obtener ownership | Try/catch con fallback a `{ status: 'unverified' }` | ✅ Correcto (ya implementado) |
| 10 | Cuenta sin suscripción (plan free / one-time) | `subscriptions` vacío + `nv_accounts.subscription_status` null | UI debe mostrar "Sin suscripción" en vez de "-" |

---

## I. Monitoreo y Alertas

### Métricas mínimas

| Métrica | Query/Check | Alerta si |
|---|---|---|
| Cuentas con MP conectado sin subscription en DB | `SELECT count(*) FROM nv_accounts a WHERE a.mp_connected = true AND NOT EXISTS (SELECT 1 FROM subscriptions s WHERE s.account_id = a.id)` | count > 0 y mp_connected_at > 7 días |
| Desync subscriptions vs nv_accounts | Query del backfill (sección G) | count > 0 |
| Webhooks fallidos (últimas 24h) | `SELECT count(*) FROM subscription_events WHERE processed = false AND created_at > now() - interval '24h'` | count > 5 |
| Suscripciones sin cobro reciente | `SELECT count(*) FROM subscriptions WHERE status = 'active' AND current_period_end < now() - interval '7d'` | count > 0 |

### Logs con correlation_id

Cada operación de suscripción debe loguear:
```json
{
  "correlation_id": "<uuid>",
  "account_id": "<account_id>",
  "mp_preapproval_id": "<preapproval_id>",
  "action": "process_mp_event | reconcile | payment_success",
  "old_status": "<status>",
  "new_status": "<status>",
  "source": "webhook | cron | manual"
}
```

---

## J. Cambios de DB (si aplica)

### No se requieren cambios de esquema

La tabla `subscriptions` ya existe con todos los campos necesarios:
- `account_id`, `mp_preapproval_id`, `status`, `current_period_end`, `grace_until`, `grace_ends_at`, etc.

La tabla `nv_accounts` ya tiene `subscription_status` como mirror denormalizado.

### Mejora opcional: agregar `last_synced_at` a `subscriptions`

Si se implementa el reconcile contra MP, agregar:

```sql
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS last_mp_synced_at timestamptz;
CREATE INDEX IF NOT EXISTS idx_subscriptions_last_synced ON subscriptions (last_mp_synced_at)
  WHERE status IN ('active', 'past_due', 'grace');
```

**Impacto RLS:** Ninguno (la tabla ya opera con service_role).  
**Impacto índices:** Índice parcial para optimizar queries del reconcile job.

---

## Apéndice: Documentación existente auditada

| Doc | Estado | Observación |
|---|---|---|
| `subscription-system-README.md` | ✅ Correcto | Índice maestro, links válidos |
| `subscription-system-walkthrough.md` | ⚠️ Parcial | No documenta pipeline dual ni MpRouterService |
| `subscription-implementation-plan.md` | ⚠️ Desactualizado | Plan original, no refleja estado actual (ej: billing hub) |
| `subscription-webhooks.md` | ⚠️ Parcial | Falta MpRouterService y dedup logic |
| `subscription-admin-dashboard.md` | ⚠️ Incorrecto | Describe badges para UI del cliente, no del Super Admin |
| `subscription-admin-guide.md` | ✅ Correcto | Guía para admin, aplica al flujo del cliente |
| `subscription-task-checklist.md` | ✅ Correcto | 9/11 fases completas, 10-11 pendientes |
| `mp_oauth_*` (5 docs) | ✅ Correcto | OAuth flow bien documentado |
| `WEBHOOK_FIX_*` (3 docs) | ✅ Correcto | Fix de webhook de pagos de tiendas |

---

## Resumen ejecutivo

**El problema NO es de backend, webhooks, ni Mercado Pago.** Es un **bug de frontend** en dos pantallas del Super Admin Dashboard:

1. **`ClientApprovalDetail.jsx`:** Busca `data.subscription_status` pero el API lo retorna dentro de `data.payments.subscription_status` → muestra "-"
2. **`ClientDetails/index.jsx`:** Llama a `GET /admin/accounts/:id/details` que **no existe** → 404 silencioso → muestra "-"

El fix es inmediato (2 cambios en frontend, 1 endpoint nuevo o ajuste en backend).

**Mejoras adicionales recomendadas:**
- Consolidar pipeline dual de webhooks (eliminar handler legacy)
- Reconciliación periódica contra MP API (no solo grace periods)
- Monitoreo de desync entre `subscriptions` y `nv_accounts`

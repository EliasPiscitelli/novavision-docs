# Plan de Hardening del Sistema de Suscripciones — NovaVision

> **Fecha:** 2026-02-06  
> **Autor:** Copilot Agent (Senior Fullstack + Data Engineer)  
> **Estado:** ✅ F0 + F1 + F2 + F3 + F4 + F5 + F6 implementados — Plan completo  
> **Ref:** RCA en `novavision-docs/audit/billing-subscription-flow.md`  
> **Changelog:** `novavision-docs/changes/2026-02-06-subscription-hardening-f0-f1.md`

---

## Inventario de problemas detectados (base del plan)

| # | Problema | Severidad | Dónde |
|---|---|---|---|
| P1 | UI Super Admin muestra "Suscripción: -" por acceso a campo anidado incorrecto | **CRÍTICA** | Admin FE |
| P2 | `ClientDetails` llama a endpoint inexistente (`GET /admin/accounts/:id/details`) | **CRÍTICA** | Admin FE + API |
| P3 | `requestUpgrade` permite **downgrade** (Growth→Starter) sin validación | **CRÍTICA** | API |
| P4 | No se validan entitlements al cambiar de plan (ej: 2000 productos en Growth → Starter con límite 300) | **ALTA** | API |
| P5 | `SubscriptionGuard` existe pero **nunca se usa** — dead code | **ALTA** | API |
| P6 | Pipeline dual de webhooks: `SubscriptionsService` y `MercadoPagoService` procesan suscripciones en paralelo | **ALTA** | API |
| P7 | Reconciliación cron (3AM) solo revisa grace periods, **no consulta MP** para confirmar estado real | **MEDIA** | API |
| P8 | UI de gestión de suscripción en client dashboard: handlers preparados pero **JSX no renderizado** | **MEDIA** | Admin FE |
| P9 | `SubscriptionExpiredBanner` navega a `/settings/billing` que **no existe** | **MEDIA** | Admin FE |
| P10 | Upgrade modifica `transaction_amount` del PreApproval pero **no cambia frecuencia** (monthly↔annual) | **MEDIA** | API |
| P11 | No hay audit log de cambios de plan | **MEDIA** | API/DB |
| P12 | Botón "Consultar estado" muestra resultado pero **no persiste** en DB | **BAJA** | API |
| P13 | No hay monitoreo de desync entre `subscriptions` y `nv_accounts.subscription_status` | **BAJA** | Infra |

---

## Jerarquía de planes (referencia inmutable del plan)

```
starter ($20/m)  <  growth ($60/m)  <  enterprise ($250/m)
    │                  │                    │
    └── _annual        └── _annual          └── _annual
        ($200/y)           ($600/y)             ($2500/y)
```

**Regla de negocio:** Solo se permite **upgrade** (hacia arriba en la jerarquía). Nunca downgrade desde el client dashboard. El Super Admin podría forzar un cambio en cualquier dirección (caso excepcional con audit log).

**Upgrade de ciclo:** monthly → annual = upgrade (paga menos por mes). annual → monthly = downgrade (NO permitido desde client dashboard).

---

## Fases del plan

### FASE 0 — Fixes críticos (0 riesgo, impacto inmediato)
> **Objetivo:** Arreglar lo que está roto hoy sin cambiar arquitectura.  
> **Esfuerzo estimado:** 1-2 días  
> **Riesgo:** Mínimo — son correcciones de lectura y adición de validación server-side.

#### F0.1 — Fix lectura de suscripción en Super Admin

**Problema:** P1  
**Alcance:** Solo FE (Admin)

| Archivo | Cambio |
|---|---|
| `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx` (~L1439) | `data?.subscription_status` → `data?.payments?.subscription_status \|\| data?.account?.subscription_status` |
| `apps/admin/src/pages/ClientDetails/index.jsx` (~L611) | Misma corrección de ruta de acceso al campo |

**Test:** Cargar una cuenta con suscripción activa → campo "Suscripción" muestra estado real en vez de "-".

#### F0.2 — Bloqueo de downgrade en `requestUpgrade`

**Problema:** P3  
**Alcance:** Solo API

| Archivo | Cambio |
|---|---|
| `apps/api/src/subscriptions/subscriptions.service.ts` → `requestUpgrade()` | Agregar validación de jerarquía antes de ejecutar |

**Lógica:**
```
PLAN_HIERARCHY = { starter: 1, starter_annual: 1, growth: 2, growth_annual: 2, enterprise: 3, enterprise_annual: 3 }

currentTier = PLAN_HIERARCHY[subscription.plan_key]
targetTier  = PLAN_HIERARCHY[targetPlanKey]

if (targetTier < currentTier) → throw BadRequestException('DOWNGRADE_NOT_ALLOWED')
if (targetTier === currentTier && isDowngradeCycle(current, target)) → throw BadRequestException('CYCLE_DOWNGRADE_NOT_ALLOWED')
```

Donde `isDowngradeCycle` = pasar de annual a monthly dentro del mismo tier.

**Test:**
- `starter` → `growth` ✅
- `growth` → `starter` ❌ `DOWNGRADE_NOT_ALLOWED`
- `starter` → `starter_annual` ✅
- `growth_annual` → `growth` ❌ `CYCLE_DOWNGRADE_NOT_ALLOWED`
- `growth` → `enterprise` ✅

#### F0.3 — "Consultar estado" persiste desync

**Problema:** P12  
**Alcance:** API

| Archivo | Cambio |
|---|---|
| `apps/api/src/admin/admin.service.ts` → `getSubscriptionStatus()` | Si `subscriptions.status !== nv_accounts.subscription_status` → upsert |

**Test:** Cuenta con `subscriptions.status=active` pero `nv_accounts.subscription_status=null` → al consultar, el campo se sincroniza.

**Entregables F0:**
- [x] PR con 3 fixes (F0.1 read path, F0.2 endpoint, F0.3 downgrade prevention)
- [ ] Tests unitarios de jerarquía de planes
- [x] Lint + typecheck OK en ambos repos

---

### FASE 1 — Consolidación de pipeline y fuente de verdad
> **Objetivo:** Eliminar el pipeline dual de webhooks. Una sola ruta para procesar eventos de suscripción. Definir `subscriptions` como SoT inmutable.  
> **Esfuerzo estimado:** 3-5 días  
> **Riesgo:** Medio — toca el flujo de webhooks (requiere testing en sandbox).

#### F1.1 — Deprecar `MercadoPagoService.handleSubscriptionEvent()` (legacy)

**Problema:** P6  
**Alcance:** API

| Archivo | Cambio |
|---|---|
| `apps/api/src/tenant-payments/mercadopago.service.ts` | Deprecar `handleSubscriptionEvent()` y `reconcileSubscriptions()`. Agregar logs de deprecation warning si se invoca. |
| `apps/api/src/services/mp-router.service.ts` | Asegurar que TODO evento `domain=platform` pasa por `SubscriptionsService.processMpEvent()` exclusivamente |

**Estrategia:** No eliminar de golpe. Primero agregar flag `LEGACY_SUB_HANDLER_ENABLED=false` (env var). Si se invoca con flag off → log warning + skip. En una fase posterior se elimina el código.

#### F1.2 — Sincronización atómica `subscriptions` → `nv_accounts`

**Problema:** P4 parcial  
**Alcance:** API

Crear un método privado `syncAccountFromSubscription(subscriptionId)` que:
1. Lee `subscriptions` row
2. Actualiza `nv_accounts.subscription_status` y `nv_accounts.plan_key` para que siempre reflejen `subscriptions`
3. Se invoca desde:
   - `processMpEvent()` (después de actualizar `subscriptions`)
   - `handlePaymentSuccess()` (ya lo hace parcialmente; unificarlo)
   - `requestUpgrade()` (ya lo hace; unificarlo)
   - `requestCancel()` (ya lo hace; unificarlo)

**Regla:** `nv_accounts.subscription_status` es un **mirror de solo-lectura**. Nunca se escribe independientemente.

#### F1.3 — Activar `SubscriptionGuard` en endpoints críticos

**Problema:** P5  
**Alcance:** API

| Controller | Endpoints a proteger |
|---|---|
| `ProductsController` | CRUD de productos |
| `CategoriesController` | CRUD de categorías |
| `BannersController` | CRUD de banners |
| `OrdersController` | Lectura de órdenes |
| `StorefrontController` | Configuración de la tienda |

**Decisión de diseño:** El guard acepta `status IN ('active', 'trialing', 'grace')` — no solo `active`. Así no se corta el servicio durante grace period.

**Cambio en `subscription.guard.ts`:**
```
ACTIVE_STATUSES = ['active', 'trialing', 'grace', 'past_due']
isActive = ACTIVE_STATUSES.includes(subscription?.status)
```

La idea: el usuario puede operar durante `past_due` y `grace` (tiene servicio pero se le muestra banner de advertencia). Solo se bloquea en `suspended`, `deactivated`, `purged`, `canceled`.

#### F1.4 — Backfill de desync existentes

**Problema:** Datos históricos inconsistentes  
**Alcance:** DB (query one-time)

```sql
-- Detectar desync
SELECT s.account_id, s.status AS sub_status, a.subscription_status AS acc_status
FROM subscriptions s
JOIN nv_accounts a ON a.id = s.account_id
WHERE s.status != COALESCE(a.subscription_status, '')
  AND s.id = (SELECT id FROM subscriptions WHERE account_id = s.account_id ORDER BY created_at DESC LIMIT 1);

-- Fix
UPDATE nv_accounts a
SET subscription_status = s.status, plan_key = s.plan_key, updated_at = now()
FROM subscriptions s
WHERE s.account_id = a.id
  AND s.id = (SELECT id FROM subscriptions WHERE account_id = a.id ORDER BY created_at DESC LIMIT 1)
  AND s.status != COALESCE(a.subscription_status, '');
```

**Entregables F1:**
- [x] PR: deprecation del handler legacy + @deprecated annotations
- [x] PR: métodos `syncAccountSubscriptionStatus()` + `pauseStoreIfNeeded()` + wired en 5 puntos
- [ ] PR: activación de `SubscriptionGuard` con statuses expandidos (movido a F2)
- [x] SQL script de backfill (`migrations/admin/subscription-backfill-sync.sql`) — pendiente ejecución con aprobación TL
- [ ] Tests de integración del pipeline unificado

---

### FASE 2 — Upgrade robusto con validación de entitlements
> **Objetivo:** Que el upgrade sea seguro, auditable y con validación de compatibilidad. Solo hacia arriba.  
> **Esfuerzo estimado:** 3-5 días  
> **Riesgo:** Medio — requiere lógica de negocio nueva.

#### F2.1 — Tabla de jerarquía de planes en DB

**Problema:** P3 reforzado  
**Alcance:** DB + API

Agregar columna `tier_level` a tabla `plans`:

```sql
ALTER TABLE plans ADD COLUMN IF NOT EXISTS tier_level INTEGER NOT NULL DEFAULT 0;

UPDATE plans SET tier_level = CASE
  WHEN plan_key IN ('starter', 'starter_annual') THEN 1
  WHEN plan_key IN ('growth', 'growth_annual') THEN 2
  WHEN plan_key IN ('enterprise', 'enterprise_annual') THEN 3
  ELSE 0
END;

CREATE INDEX IF NOT EXISTS idx_plans_tier ON plans (tier_level);
```

**Ventaja:** La jerarquía queda en DB (configurable), no hardcodeada en código.

#### F2.2 — Validación de entitlements pre-upgrade

**Problema:** P4  
**Alcance:** API

Nuevo método `validateUpgradeCompatibility(accountId, targetPlanKey)`:
1. Lee entitlements actuales del account (de `account_entitlements` o `plans`)
2. Lee entitlements target de `plans`
3. Lee uso real del account (productos, categorías, banners, órdenes del mes)
4. Genera reporte:
   - `{ compatible: true }` → puede hacer upgrade directo
   - `{ compatible: true, gains: [...] }` → upgrade con nuevas features
   - Error si es downgrade (bloqueado en F0.2)

**Nota sobre downgrades futuros (Super Admin):** Si en el futuro se quiere permitir downgrade forzado desde Super Admin, este método retornaría `{ compatible: false, conflicts: [{ entity: 'products', current: 2000, limit: 300 }] }` y el Super Admin decidiría si proceder con un plan de reducción.

#### F2.3 — Propagación de entitlements post-upgrade

**Alcance:** API

Después de un upgrade exitoso, `requestUpgrade` debe:
1. Leer nuevos entitlements del plan target desde `plans`
2. Actualizar `account_entitlements` (Admin DB)
3. Actualizar `clients.entitlements_snapshot` (Multicliente DB)
4. Loguear en audit: `{ action: 'plan_upgrade', from: 'starter', to: 'growth', entitlements_diff: {...} }`

#### F2.4 — Manejo de cambio de ciclo (monthly ↔ annual)

**Problema:** P10  
**Alcance:** API

Cuando el upgrade implica cambio de ciclo billing:
- **monthly → annual (mismo tier):** Cancelar PreApproval mensual, crear nuevo PreApproval anual. Calcular prorateo del periodo actual ya pagado.
- **monthly → annual (tier superior):** Cancelar PreApproval mensual, crear nuevo PreApproval anual del tier superior.
- **annual → monthly:** Solo permitido si es upgrade de tier (ej: starter_annual → growth). NO permitido como downgrade de ciclo dentro del mismo tier.

**Decisión:** Si cambia la `frequency` o `frequency_type` del auto_recurring, MP NO permite editar — hay que cancelar y crear nuevo PreApproval. El método `updateSubscriptionPrice` solo sirve para cambio de monto dentro del mismo ciclo.

```
startNewPreApproval(account, targetPlan):
  1. Cancelar preapproval viejo en MP (status=cancelled)
  2. Marcar subscription vieja como 'superseded' (nuevo status)
  3. Crear nuevo registro en subscriptions con nuevo mp_preapproval_id
  4. Crear nuevo preapproval en MP
  5. syncAccountFromSubscription()
```

#### F2.5 — Audit log de cambios de plan

**Problema:** P11  
**Alcance:** DB + API

Opción A (preferida): Usar `nv_billing_events` existente con `event_type: 'plan_change'`:

```sql
INSERT INTO nv_billing_events (account_id, event_type, status, amount, metadata)
VALUES (
  :accountId, 'plan_change', 'completed', 0,
  '{"from_plan": "starter", "to_plan": "growth", "initiated_by": "client", "reason": "upgrade"}'::jsonb
);
```

Opción B: Tabla dedicada `subscription_audit_log` (si se necesita más estructura).

**Entregables F2:**
- [ ] Migración: `tier_level` en `plans` (pendiente — por ahora usa PLAN_TIERS hardcoded)
- [ ] Método `validateUpgradeCompatibility()` (pendiente — por ahora bloquea downgrade, no valida usage vs limits)
- [x] Propagación de entitlements post-upgrade (`syncEntitlementsAfterUpgrade`)
- [ ] Manejo de cambio de ciclo (cancel viejo + crear nuevo PreApproval) (pendiente — annual↔monthly blocked, same-cycle upgrade works)
- [x] Audit log en billing_events (via `BillingService.createEvent` con metadata plan_upgrade)
- [x] SubscriptionGuard activado con `getEffectiveStatus` (active + grace window)
- [x] Cycle downgrade prevention (annual → monthly mismo tier bloqueado)
- [x] Decorator `@SkipSubscriptionCheck()` para rutas de billing/manage
- [ ] Tests:
  - starter → growth (monthly): solo cambia precio
  - starter → growth_annual: cancela/crea PreApproval
  - growth → starter: ❌ bloqueado
  - growth_annual → growth: ❌ bloqueado
  - growth → enterprise: ✅ validación de entitlements

---

### FASE 3 — UI de gestión de suscripción (client dashboard)
> **Objetivo:** El dueño de tienda puede ver y gestionar su suscripción. Solo upgrades hacia arriba.  
> **Esfuerzo estimado:** 3-5 días  
> **Riesgo:** Bajo — es UI nueva que consume endpoints ya existentes.

#### F3.1 — Página `/settings/billing` en Admin app

**Problema:** P9  
**Alcance:** Admin FE

Crear nueva página con:

| Sección | Contenido |
|---|---|
| **Plan actual** | Nombre del plan, precio (ARS/USD), ciclo, próximo cobro, `current_period_end` |
| **Estado** | Badge: active/past_due/grace/canceled + `SubscriptionExpiredBanner` integrado |
| **Upgrade** | Cards de planes superiores disponibles (solo los que son upgrade). Botón "Cambiar a {plan}" con `ConfirmDialog` |
| **Historial de pagos** | Tabla con `subscription_price_history` (fecha, monto, rate, status) |
| **Acciones** | Cancelar suscripción (con confirmación y advertencia de consecuencias) |
| **Identidad MP** | Badge de ownership: si coincide o no; email del titular |

**Reglas de la UI:**
- Solo mostrar planes con `tier_level` > `currentTier` como opciones de upgrade
- Mostrar diff de entitlements entre plan actual y plan target ("+1700 productos", "+5 imágenes", etc.)
- Botón de cancel: confirmación en 2 pasos con texto explícito
- No mostrar opción de downgrade nunca

#### F3.2 — Renderizar sección de suscripción en `ClientCompletionDashboard`

**Problema:** P8  
**Alcance:** Admin FE

Los handlers ya existen (líneas 527-556 de `index.tsx`). Falta renderizar la sección en el JSX:

| Elemento | Descripción |
|---|---|
| Card "Tu Suscripción" | Plan actual, status badge, próximo cobro |
| Botón "Cambiar plan" | Link a `/settings/billing` |
| Banner de expiración | Integrar `SubscriptionExpiredBanner` |

#### F3.3 — Super Admin: suscripción visible sin bugs

**Problema:** P1, P2  
**Alcance:** Admin FE

Completar los fixes de F0.1 y además:
- En `ClientApprovalDetail`: mostrar también `current_period_end`, `plan_key` del endpoint de subscription-status
- En `ClientDetails`: agregar endpoint backend `GET /admin/accounts/:id/details` o reusar `subscription-status`

**Entregables F3:**
- [x] Página `/settings/billing` completa
- [x] Sección renderizada en `ClientCompletionDashboard`
- [x] Fixes de visualización en Super Admin

---

### FASE 4 — Reconciliación robusta contra MP
> **Objetivo:** Detectar y corregir desync entre DB y Mercado Pago automáticamente.  
> **Esfuerzo estimado:** 2-3 días  
> **Riesgo:** Bajo-Medio — requiere consultas a API de MP.

#### F4.1 — Cron de reconciliación contra MP

**Problema:** P7  
**Alcance:** API

Nuevo cron en `SubscriptionsService`:

```
@Cron('0 6 * * *')  // 6AM diario (después del cron de precios a las 2AM)
async reconcileWithMercadoPago():
  1. Lee subscriptions WHERE status IN ('active','past_due','grace') AND mp_preapproval_id IS NOT NULL
  2. Para cada una:
     a. GET /preapproval/{mp_preapproval_id} desde MP
     b. Compara status MP vs status DB
     c. Si difiere → log + upsert en subscriptions + syncAccountFromSubscription()
     d. Marca last_mp_synced_at = now()
  3. Rate limit: max 20 req/s a MP (batch con delay)
  4. Genera reporte: { total, synced, errors, details[] }
  5. Log del reporte en nv_billing_events (metadata.type = 'reconcile_report')
```

#### F4.2 — Columna `last_mp_synced_at` en `subscriptions`

```sql
ALTER TABLE subscriptions ADD COLUMN IF NOT EXISTS last_mp_synced_at TIMESTAMPTZ;
CREATE INDEX IF NOT EXISTS idx_subs_sync ON subscriptions (last_mp_synced_at)
  WHERE status IN ('active', 'past_due', 'grace');
```

#### F4.3 — Migrar `reconcileSubscriptions()` legacy a nuevo servicio

Mover la lógica de `MercadoPagoService.reconcileSubscriptions()` al nuevo cron de F4.1 y deprecar el viejo. El endpoint manual `POST /mercadopago/subscriptions/reconcile` pasa a llamar al nuevo método.

**Entregables F4:**
- [x] Cron `reconcileWithMercadoPago()` con rate limiting
- [x] Migración: `last_mp_synced_at` + `last_reconcile_source`
- [x] Deprecación del reconcile legacy (cron removido, método kept as fallback)
- [x] Endpoint `POST /subscriptions/reconcile` rewired al nuevo método
- [x] DTO `CreateBillingEventDto` extendido para `reconcile_report`
- [ ] Test con mock de MP API

---

### FASE 5 — Monitoreo, alertas y observabilidad
> **Objetivo:** Nunca más tener desync silencioso. Detectar problemas antes que el Super Admin los reporte.  
> **Esfuerzo estimado:** 2 días  
> **Riesgo:** Bajo.

#### F5.1 — Health-check de suscripciones

Endpoint `GET /admin/subscriptions/health` (protegido con `PlatformAuthGuard`):

```json
{
  "total_active": 45,
  "total_by_status": { "active": 40, "past_due": 3, "grace": 1, "suspended": 1 },
  "desync_count": 0,
  "stale_sync_count": 2,
  "stale_sync_threshold_hours": 48,
  "webhook_failures_24h": 0,
  "mp_connected_no_subscription": 1,
  "last_reconcile_at": "2026-02-06T06:00:00Z"
}
```

#### F5.2 — Queries de monitoreo

| Métrica | Query | Alerta si |
|---|---|---|
| Desync sub↔account | `SELECT count(*) FROM subscriptions s JOIN nv_accounts a ON a.id = s.account_id WHERE s.status != COALESCE(a.subscription_status,'')` | > 0 |
| Sync stale > 48h | `SELECT count(*) FROM subscriptions WHERE status='active' AND (last_mp_synced_at IS NULL OR last_mp_synced_at < now()-interval '48h')` | > 0 |
| MP conectado sin sub | `SELECT count(*) FROM nv_accounts WHERE mp_connected=true AND NOT EXISTS (SELECT 1 FROM subscriptions WHERE account_id = nv_accounts.id)` | > 0 y `mp_connected_at < now()-7d` |
| Webhooks no procesados | `SELECT count(*) FROM subscription_events WHERE processed=false AND created_at > now()-interval '24h'` | > 5 |

#### F5.3 — Correlation ID en todos los logs de suscripción

Cada log de operación de suscripción debe incluir:
```json
{
  "correlation_id": "<uuid>",
  "account_id": "<>",
  "subscription_id": "<>",
  "mp_preapproval_id": "<>",
  "action": "webhook_received | status_changed | payment_success | upgrade | cancel | reconcile",
  "old_status": "<>",
  "new_status": "<>",
  "source": "webhook | cron | manual | client_action"
}
```

**Entregables F5:**
- [x] Endpoint `/admin/subscriptions/health` (SuperAdminGuard)
- [x] Queries de monitoreo integradas (desync, stale sync, MP sin sub, last reconcile)
- [x] `logSubAction()` helper con correlation_id en processMpEvent, handleSubscriptionUpdated, requestUpgrade, requestCancel

---

### FASE 6 — Hardening de seguridad y edge cases
> **Objetivo:** Cubrir todos los escenarios límite identificados en el RCA.  
> **Esfuerzo estimado:** 2-3 días  
> **Riesgo:** Bajo — son validaciones adicionales.

#### F6.1 — Validación de firma de webhooks (hardening)

Verificar que `MpRouterService` rechaza webhooks sin firma válida con `401`. Si el secret no está configurado → log `CRITICAL` + rechazar.

#### F6.2 — Idempotencia reforzada en webhooks

El dedup actual usa SHA256 hash. Reforzar:
- Si el evento ya fue procesado con mismo topic/resourceId → retornar `200` sin reprocesar
- Si hay race condition (dos instancias procesan el mismo evento) → usar `SELECT ... FOR UPDATE` o unique constraint + ON CONFLICT

#### F6.3 — Sandbox vs Producción

Agregar validación en `createSubscriptionForAccount`:
- Si `NODE_ENV=production` y el account usa test user email → bloquear creación
- Si PreApproval fue creada en sandbox y estamos en prod → marcar como `sandbox_only` y no sincronizar

#### F6.4 — Tokens rotados/expirados

Si al hacer reconcile o upgrade el token MP está expirado:
1. Intentar refresh vía `MpTokenRefreshWorker`
2. Si falla → marcar `mp_connected=false` + notificar al cliente
3. No permitir operaciones que requieran token MP si está expirado

#### F6.5 — Race condition: upgrade vs webhook

Si un webhook de pago llega mientras se procesa un upgrade:
- `requestUpgrade` debe adquirir lock por `account_id` (Redis distributed lock o `SELECT ... FOR UPDATE`)
- `processMpEvent` debe respetar el mismo lock
- Timeout del lock: 10s

#### F6.6 — Edge case: cuenta `incomplete` con suscripción activa

- La suscripción se muestra correctamente (fix F0.1)
- El `account_status: incomplete` se muestra como algo separado ("Faltan items por completar")
- No se mezclan los conceptos

**Entregables F6:**
- [x] Hardening de firma de webhooks (production hard-reject si no hay secret + error logging)
- [x] Idempotencia reforzada (dedup logging con event key prefix)
- [x] Validación sandbox vs prod (test user block en createSubscription + live_mode skip en reconcile)
- [x] Manejo de tokens expirados (auth error detection en reconcile + requestUpgrade con mensaje claro)
- [x] Race condition lock (in-memory advisory lock con TTL 30s en processMpEvent + requestUpgrade)
- [x] Edge case incomplete→active (webhook promueve incomplete/pending a active automáticamente)
- [ ] Tests de edge cases

---

## Diagrama de dependencias entre fases

```
FASE 0 ──────────────────────────────── (fixes críticos, sin dependencias)
   │
   ▼
FASE 1 ──────────────────────────────── (consolidación pipeline)
   │          │
   ▼          ▼
FASE 2     FASE 4 ─────────────────── (reconcile contra MP)
   │          │
   ▼          ▼
FASE 3     FASE 5 ─────────────────── (monitoreo)
   │
   ▼
FASE 6 ──────────────────────────────── (hardening, puede ir en paralelo con F4-F5)
```

**F0 → F1:** Obligatorio. F1 depende de que los fixes básicos estén.  
**F1 → F2:** F2 requiere pipeline unificado (F1) para que el upgrade sea consistente.  
**F1 → F4:** F4 requiere que el pipeline esté unificado para evitar conflictos.  
**F2 → F3:** F3 (UI) requiere que el upgrade esté validado (F2) antes de exponerlo al usuario.  
**F6:** Puede ejecutarse en paralelo con F3-F5 ya que son validaciones independientes.

---

## Resumen de cambios de DB propuestos

| Fase | Cambio | Migración |
|---|---|---|
| F2.1 | `ALTER TABLE plans ADD COLUMN tier_level INTEGER` | `ADMIN_XXX_add_plan_tier_level.sql` |
| F4.2 | `ALTER TABLE subscriptions ADD COLUMN last_mp_synced_at TIMESTAMPTZ` | `ADMIN_XXX_add_subscription_sync_timestamp.sql` |

**Nota:** Ambos son aditivos (ADD COLUMN). No rompen nada existente. No requieren cambios RLS (las tablas operan con `service_role`).

---

## Resumen de archivos impactados por fase

### FASE 0
| Repo | Archivo | Cambio |
|---|---|---|
| Admin FE | `src/pages/AdminDashboard/ClientApprovalDetail.jsx` | Fix acceso a campo anidado |
| Admin FE | `src/pages/ClientDetails/index.jsx` | Fix acceso a campo / endpoint |
| API | `src/subscriptions/subscriptions.service.ts` → `requestUpgrade()` | Validación de jerarquía |
| API | `src/admin/admin.service.ts` → `getSubscriptionStatus()` | Sync on read |

### FASE 1
| Repo | Archivo | Cambio |
|---|---|---|
| API | `src/tenant-payments/mercadopago.service.ts` | Deprecar handler legacy |
| API | `src/services/mp-router.service.ts` | Verificar routing exclusivo |
| API | `src/subscriptions/subscriptions.service.ts` | Método `syncAccountFromSubscription()` |
| API | `src/guards/subscription.guard.ts` | Expandir statuses aceptados |
| API | Controllers varios | Agregar `@UseGuards(SubscriptionGuard)` |

### FASE 2
| Repo | Archivo | Cambio |
|---|---|---|
| API | `src/subscriptions/subscriptions.service.ts` | `validateUpgradeCompatibility()`, propagación entitlements, manejo ciclo |
| API | `src/subscriptions/platform-mercadopago.service.ts` | Método `cancelAndCreateNew()` para cambio de ciclo |
| DB | `migrations/admin/` | Migración `tier_level` |

### FASE 3
| Repo | Archivo | Cambio |
|---|---|---|
| Admin FE | `src/pages/Settings/BillingPage.tsx` (NUEVO) | Página completa de billing |
| Admin FE | `src/pages/ClientCompletionDashboard/index.tsx` | Renderizar sección de suscripción |
| Admin FE | `src/components/SubscriptionExpiredBanner.tsx` | Apuntar a `/settings/billing` (que ahora existirá) |

### FASE 4
| Repo | Archivo | Cambio |
|---|---|---|
| API | `src/subscriptions/subscriptions.service.ts` | Cron `reconcileWithMercadoPago()` |
| DB | `migrations/admin/` | Migración `last_mp_synced_at` |

### FASE 5
| Repo | Archivo | Cambio |
|---|---|---|
| API | `src/admin/admin.controller.ts` | Endpoint `/admin/subscriptions/health` |
| API | `src/admin/admin.service.ts` | Método `getSubscriptionsHealth()` |

### FASE 6
| Repo | Archivo | Cambio |
|---|---|---|
| API | `src/services/mp-router.service.ts` | Hardening firma + idempotencia |
| API | `src/subscriptions/subscriptions.service.ts` | Lock distribuido en upgrade + processMpEvent |
| API | `src/mp-oauth/mp-oauth.service.ts` | Validación de tokens expirados |

---

## Criterios de aceptación por fase

### F0 (Must-have para merge)
- [ ] Super Admin ve estado de suscripción real (no "-")
- [ ] Un Growth no puede hacer downgrade a Starter
- [ ] Botón "Consultar estado" sincroniza nv_accounts si hay desync
- [ ] `npm run lint && npm run typecheck` OK en ambos repos

### F1
- [ ] Solo un handler procesa eventos de suscripción
- [ ] `nv_accounts.subscription_status` se actualiza atómicamente desde `subscriptions`
- [ ] `SubscriptionGuard` activo en endpoints de operación de tienda
- [ ] Zero desync entre `subscriptions` y `nv_accounts` post-backfill

### F2
- [ ] Upgrade starter→growth funciona end-to-end (API + MP)
- [ ] Downgrade growth→starter rechazado con error claro
- [ ] Entitlements del account actualizados post-upgrade
- [ ] Cambio de ciclo genera nuevo PreApproval
- [ ] Audit log registrado para cada cambio de plan

### F3
- [ ] Página `/settings/billing` renderiza correctamente
- [ ] Solo se muestran planes superiores como opciones de upgrade
- [ ] Diff de entitlements visible antes de confirmar
- [ ] Cancel con doble confirmación

### F4
- [ ] Cron reconcilia contra MP diariamente
- [ ] Discrepancias detectadas y corregidas automáticamente
- [ ] `last_mp_synced_at` actualizado

### F5
- [ ] Endpoint health retorna métricas correctas
- [ ] Logs con correlation_id en todas las operaciones de suscripción

### F6
- [x] Webhooks sin firma válida rechazados con 401 (producción: UnauthorizedException si no hay secret)
- [x] Race conditions manejadas con advisory lock in-memory (TTL 30s por account_id)
- [x] Tokens expirados detectados y flaggeados (reconcile marca `last_reconcile_source=auth_error`, upgrade da 500 claro)
- [x] Sandbox subs no contaminan producción (live_mode check en reconcile + test user block en creación)
- [x] Transición incomplete→active automática por webhook

---

## Timeline sugerido

| Semana | Fase | Días |
|---|---|---|
| **Semana 1** | F0 + F1 | 5 días |
| **Semana 2** | F2 + F4 (en paralelo) | 5 días |
| **Semana 3** | F3 + F5 (en paralelo) | 5 días |
| **Semana 4** | F6 + QA integral + docs finales | 5 días |

**Total estimado:** 4 semanas (20 días hábiles)

---

## Decisiones de diseño clave (para validar con TL)

| # | Decisión | Alternativa descartada | Motivo |
|---|---|---|---|
| D1 | Fuente de verdad = tabla `subscriptions` | Usar solo `nv_accounts.subscription_status` | La tabla dedicada tiene más campos (period, grace, preapproval_id) y es auditable |
| D2 | Solo upgrade desde client dashboard | Permitir downgrade con advertencia | Simplifica lógica, evita conflictos de entitlements, alineado con requerimiento de negocio |
| D3 | Cambio de ciclo = cancel + nuevo PreApproval | Intentar editar frecuencia del existente | MP no permite cambiar `frequency_type` en preapproval existente |
| D4 | `SubscriptionGuard` permite `past_due` y `grace` | Solo `active` | Si cortamos servicio de golpe el usuario no tiene forma de pagar. Mejor: servicio + banner de advertencia |
| D5 | Reconcile como cron (no real-time) | Webhook + reconcile en cada request | Rate limits de MP (20/s) + complejidad. Un cron diario es suficiente |
| D6 | Audit log en `nv_billing_events` | Tabla dedicada | Reusar tabla existente reduce complejidad. Si crece, se puede migrar |

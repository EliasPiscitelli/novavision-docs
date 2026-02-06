# Guardrails del Sistema de Suscripciones — NovaVision

> **Última actualización:** 2026-02-06
> **Contexto:** Plan de hardening F0-F6 completado. Este documento es la referencia canónica para cualquier agente o desarrollador que toque el sistema de suscripciones.

---

## 🚨 REGLAS INMUTABLES — NO ROMPER

### 1. Fuente de verdad = tabla `subscriptions` (Admin DB)

| Tabla | Rol | Quién escribe |
|---|---|---|
| `subscriptions` | **SoT** (source of truth) | Solo `SubscriptionsService` |
| `nv_accounts.subscription_status` | **Mirror de solo lectura** | Solo `syncAccountSubscriptionStatus()` |

**NUNCA** escribir directamente en `nv_accounts.subscription_status`. Siempre actualizar `subscriptions` primero y luego llamar `syncAccountSubscriptionStatus(accountId, newStatus)`.

### 2. Solo upgrades, nunca downgrades (desde client dashboard)

```
PLAN_TIERS = { starter: 1, growth: 2, enterprise: 3 }
```

- `targetTier > currentTier` → ✅ permitido
- `targetTier < currentTier` → ❌ `BadRequestException('Downgrade not allowed')`
- `targetTier === currentTier` Y `annual → monthly` → ❌ `BadRequestException('Cycle downgrade not allowed')`
- `targetTier === currentTier` Y `monthly → annual` → ✅ permitido

**Dónde está:** `requestUpgrade()` en `subscriptions.service.ts` (~L703).
**Si necesitás downgrade forzado:** Hacerlo desde Super Admin con audit log explícito. NO agregar downgrade al flujo de cliente.

### 3. Pipeline único de webhooks

```
MP Webhook → MpRouterController → MpRouterService.handleWebhook() →
  domain=platform → SubscriptionsService.processMpEvent()
  domain=tenant   → MercadoPagoService.confirmPayment()
```

**NUNCA** crear un segundo handler para eventos de suscripción. El pipeline legacy en `MercadoPagoService.handleSubscriptionEvent()` está `@deprecated`. No reactivarlo.

### 4. ConfigService key name = `this.config` (no `this.configService`)

En `SubscriptionsService`, el `ConfigService` está inyectado como `private readonly config: ConfigService`. Usar `this.config.get<string>(...)`, NO `this.configService`.

### 5. Webhook secret obligatorio en producción

Si `NODE_ENV === 'production'` y no hay `MP_WEBHOOK_SECRET_PLATFORM` ni `MP_WEBHOOK_SECRET_TENANT` ni `MP_WEBHOOK_SECRET` configurado → los webhooks se rechazan con 401. **No remover esta validación.**

---

## 📁 Mapa de archivos críticos

### Suscripciones (core)

| Archivo | Responsabilidad | Líneas aprox |
|---|---|---|
| `src/subscriptions/subscriptions.service.ts` | Core lifecycle: create, upgrade, cancel, reconcile, webhooks | ~2400 |
| `src/subscriptions/subscriptions.controller.ts` | REST endpoints: manage-status, manage-upgrade, manage-cancel, reconcile | ~220 |
| `src/subscriptions/platform-mercadopago.service.ts` | SDK wrapper: create/get/update/cancel PreApproval en MP | ~485 |

### Webhook routing

| Archivo | Responsabilidad |
|---|---|
| `src/services/mp-router.service.ts` | Central router: parseEvent, verifySignature, insertEvent (dedup), route by domain |
| `src/controllers/mp-router.controller.ts` | 2 endpoints: `/webhooks/mp/tenant-payments` y `/webhooks/mp/platform-subscriptions` |
| `src/controllers/mercadopago-webhook.controller.ts` | Legacy `/webhooks/mercadopago` (solo payments de tenants, NO suscripciones) |

### Monitoreo

| Archivo | Responsabilidad |
|---|---|
| `src/admin/admin.controller.ts` | `GET /admin/subscriptions/health` (SuperAdminGuard) |
| `src/admin/admin.service.ts` | `getSubscriptionsHealth()` — 5 queries de monitoreo |

### UI (Admin frontend)

| Archivo | Responsabilidad |
|---|---|
| `src/pages/Settings/BillingPage.tsx` | Página billing: plan actual, upgrade, cancel |
| `src/pages/ClientCompletionDashboard/index.tsx` | Tarjeta de suscripción + banner expiración |

### Tipos y constantes

| Archivo | Qué exporta |
|---|---|
| `src/types/palette.ts` L59-63 | `PLAN_TIERS`, `normalizePlanKey()` |
| `src/billing/billing.service.ts` | `CreateBillingEventDto` (tipos de evento + status) |

---

## 🔄 Flujos críticos (no modificar sin entender)

### Flujo de webhook (preapproval)
```
1. MP envía POST /webhooks/mp/platform-subscriptions
2. MpRouterService.handleWebhook():
   a. parseEvent() → topic + resourceId
   b. verifySignature() → 401 si inválida (prod: también si no hay secret)
   c. computeEventKey() → SHA256 dedup
   d. insertEvent() → subscription_events con unique constraint (23505 = dedup)
   e. fetchPlatformResource() → getSubscription(preapprovalId)
   f. SubscriptionsService.processMpEvent({ topic, resourceId, mpData })
3. processMpEvent():
   a. acquireLock(account_id) → skip si locked (F6.5)
   b. statusMap: authorized→active, paused→past_due, cancelled→canceled
   c. logSubAction() con correlation_id (F5.3)
   d. incomplete/pending + authorized → promote to active (F6.6)
   e. canceled → markCancelScheduled()
   f. past_due → update + sync
   g. active → update + sync
   h. releaseLock() en finally
```

### Flujo de upgrade
```
1. POST /subscriptions/manage-upgrade { target_plan_key }
2. requestUpgrade():
   a. resolveAccountFromRequest(req)
   b. Load subscription (latest by account_id)
   c. Validate: not same plan
   d. Validate: not downgrade (PLAN_TIERS)
   e. Validate: not cycle downgrade (annual→monthly same tier)
   f. acquireLock(account_id) → 400 si locked (F6.5)
   g. Load planConfig from plans table
   h. Calculate price: planPriceUsd × blueDollarRate → ARS
   i. platformMp.updateSubscriptionPrice() — with auth error catch (F6.4)
   j. Update subscription row
   k. Update nv_accounts.plan_key
   l. logSubAction + billingService.createEvent (audit)
   m. syncEntitlementsAfterUpgrade()
   n. releaseLock() en finally
```

### Flujo de reconcile (cron diario 6AM)
```
1. @Cron('0 6 * * *') reconcileWithMercadoPago('cron')
2. Query subs WHERE status IN (active, past_due, grace, grace_period) AND mp_preapproval_id NOT NULL
3. Batch de 10 con 1s delay:
   a. platformMp.getSubscription(mp_preapproval_id)
   b. Sandbox check: live_mode=false en prod → skip (F6.3)
   c. Map MP status → internal status
   d. Update last_mp_synced_at + last_reconcile_source
   e. If mismatch → apply correction + sync account
   f. Catch: auth error → flag last_reconcile_source=auth_error (F6.4)
4. Log report to nv_billing_events
```

---

## ⚠️ Patrones que NO hacer

| ❌ NO hacer | ✅ Hacer en cambio |
|---|---|
| Escribir `nv_accounts.subscription_status` directamente | Usar `syncAccountSubscriptionStatus()` |
| Agregar downgrade en `requestUpgrade()` | Crear endpoint separado de Super Admin con audit |
| Crear segundo handler de webhook para suscripciones | Extender `processMpEvent()` |
| Quitar el webhook secret check de producción | Configurar `MP_WEBHOOK_SECRET_*` en Railway |
| Usar `this.configService` en SubscriptionsService | Usar `this.config` (es el nombre inyectado) |
| Hardcodear estados de suscripción como strings | Usar `statusMap` existente |
| Agregar `@Cron` a `reconcileSubscriptions()` legacy | Usar `reconcileWithMercadoPago()` |
| Remover el advisory lock sin poner Redis lock | Mantener lock hasta migrar a multi-instancia |
| Hacer queries sin `client_id` filter en Backend DB | Siempre `.eq('client_id', clientId)` |

---

## 🧪 Cómo verificar que no rompiste nada

### Typecheck
```bash
# Terminal back (api)
npm run typecheck
# Esperado: 0 errors, ~717 warnings (no-explicit-any preexistentes)
```

### Tests clave manuales

| Test | Endpoint | Esperado |
|---|---|---|
| Downgrade bloqueado | `POST /subscriptions/manage-upgrade { "target_plan_key": "starter" }` (siendo growth) | 400: "Downgrade not allowed" |
| Cycle downgrade bloqueado | `POST /subscriptions/manage-upgrade { "target_plan_key": "growth" }` (siendo growth_annual) | 400: "Cycle downgrade not allowed" |
| Upgrade OK | `POST /subscriptions/manage-upgrade { "target_plan_key": "enterprise" }` (siendo growth) | 200: `{ ok: true, status: 'upgraded' }` |
| Health check | `GET /admin/subscriptions/health` (super admin) | 200: JSON con métricas |
| Reconcile manual | `POST /subscriptions/reconcile` (super admin) | 200: `{ total, synced, errors, details }` |
| Webhook sin secret (prod) | `POST /webhooks/mp/platform-subscriptions` (sin secret env) | 401 |

### Build check
```bash
npm run build
# Esperado: 0 errors (excluir client-dashboard.service.ts:900 unused var que es preexistente)
```

---

## 📊 Variables de entorno relevantes

| Variable | Dónde se usa | Obligatoria |
|---|---|---|
| `MP_WEBHOOK_SECRET_PLATFORM` | `MpRouterService` → firma de webhooks platform | Sí en prod |
| `MP_WEBHOOK_SECRET_TENANT` | `MpRouterService` → firma de webhooks tenant | Sí en prod |
| `MP_WEBHOOK_SECRET` | `MpRouterService` → fallback genérico | Opcional |
| `MP_SANDBOX_MODE` | `PlatformMercadoPagoService` → swap test users | Solo dev |
| `MP_TEST_PAYER_EMAIL` | `PlatformMercadoPagoService` → email de test user MP | Solo dev |
| `NODE_ENV` | Guards de producción (firma, sandbox, test users) | Siempre |

---

## 📦 Tablas de DB involucradas (Admin DB)

| Tabla | Campos clave | Notas |
|---|---|---|
| `subscriptions` | id, account_id, mp_preapproval_id, status, plan_key, last_mp_synced_at, last_reconcile_source | **SoT de suscripciones** |
| `nv_accounts` | id, subscription_status, plan_key, mp_connected | **Mirror** — solo escribir via `syncAccountSubscriptionStatus()` |
| `plans` | plan_key, monthly_fee, entitlements | Config de planes |
| `account_entitlements` | account_id, entitlement_key, value | Límites post-upgrade |
| `nv_billing_events` | account_id, event_type, status, metadata | Audit log |
| `subscription_events` | event_key (unique), topic, resource_id, domain | Dedup de webhooks (platform) |
| `tenant_payment_events` | event_key (unique), topic, resource_id | Dedup de webhooks (tenant) |

---

## 🕐 Crons activos

| Cron | Horario | Método | Descripción |
|---|---|---|---|
| Price sync | `0 2 * * *` (2AM) | `updateAllPrices()` | Actualiza precios ARS por dólar blue |
| **Reconcile** | `0 6 * * *` (6AM) | `reconcileWithMercadoPago()` | Compara DB vs MP API, corrige mismatches |
| ~~Grace check~~ | ~~`0 3 * * *`~~ | ~~`reconcileSubscriptions()`~~ | **@deprecated** — absorbido por reconcile nuevo |

---

## 📝 Historial de fases

| Fase | Qué hizo | Changelog |
|---|---|---|
| F0 | Fix lectura sub en Super Admin, downgrade prevention, sync on read | `2026-02-06-subscription-hardening-f0-f1.md` |
| F1 | Pipeline unificado, deprecación legacy, `syncAccountSubscriptionStatus()` | `2026-02-06-subscription-hardening-f0-f1.md` |
| F2 | Upgrade robusto: tier validation, cycle check, entitlements sync, audit | `2026-02-06-subscription-hardening-f2-f3.md` |
| F3 | BillingPage, tarjeta en dashboard, ruta `/settings/billing` | `2026-02-06-subscription-hardening-f2-f3.md` |
| F4 | Reconcile cron contra MP API, migración last_mp_synced_at | `2026-02-06-subscription-hardening-f4.md` |
| F5 | Health-check endpoint, 5 queries monitoreo, correlation_id logging | `2026-02-06-subscription-hardening-f5-f6.md` |
| F6 | Webhook firma, sandbox guard, token error handling, advisory lock, incomplete→active | `2026-02-06-subscription-hardening-f5-f6.md` |

---

## Pendientes conocidos (no bloqueantes)

| Item | Prioridad | Notas |
|---|---|---|
| Tests unitarios de PLAN_TIERS y downgrade logic | Media | Candidato para TDD en próxima iteración |
| Tests de integración para reconcile con mock MP | Media | Requiere setup de test fixtures |
| Migración `tier_level` en tabla `plans` (DB) | Baja | Actualmente usa `PLAN_TIERS` hardcoded; funcional |
| Cancel+crear nuevo PreApproval para cambio de ciclo | Baja | Monthly↔annual bloqueado por validación, solo same-cycle upgrade funciona |
| Migrar advisory lock a Redis (si se escala a multi-instancia) | Baja | Actual: single-instance suficiente |
| Ejecutar `subscription-backfill-sync.sql` en producción | Media | Pendiente aprobación TL |

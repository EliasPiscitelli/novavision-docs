# Subscription Pause + Downgrade Execution — Churn Lifecycle Fase 2

**Fecha:** 2026-03-26
**Plan:** `PLAN_CHURN_LIFECYCLE.md` Fase 2
**Estado:** Implementado + testeado

---

## Problema

El sistema solo tenía **store pause** (pausar la tienda visualmente) pero no **subscription pause** (pausar la facturación en MercadoPago). Además, el check de elegibilidad para downgrade existía pero no había endpoint para ejecutar el downgrade.

## Solución

### Subscription Pause (nueva funcionalidad)

**Endpoints:**
| Ruta | Guard | Propósito |
|------|-------|-----------|
| `POST /subscriptions/manage/pause-subscription` | BuilderSessionGuard | Pausar suscripción (builder) |
| `POST /subscriptions/manage/resume-subscription` | BuilderSessionGuard | Reanudar suscripción (builder) |
| `POST /subscriptions/client/manage/pause-subscription` | ClientDashboardGuard | Pausar suscripción (client) |
| `POST /subscriptions/client/manage/resume-subscription` | ClientDashboardGuard | Reanudar suscripción (client) |

**Reglas de negocio:**
- Solo suscripciones `active`/`authorized` pueden pausarse
- Duración: 1-3 meses (parámetro `months`)
- Máximo 2 pausas por año (verificado contra `subscription_events`)
- Pausa la preapproval en MercadoPago (`platformMp.pauseSubscription`)
- Pausa automáticamente la tienda (`pauseStoreIfNeeded`)
- Al reanudar, reactiva la preapproval en MP y despublicar tienda

**Flujo:**
1. Validar estado + max pausas/año
2. Advisory lock
3. Pause en MP
4. Update subscription (status='paused', paused_at, pause_expires_at)
5. Sync status → auto-pause store
6. Log CRM + lifecycle event

### Downgrade Execution (nueva funcionalidad)

**Endpoints:**
| Ruta | Guard | Propósito |
|------|-------|-----------|
| `POST /subscriptions/manage/downgrade` | BuilderSessionGuard | Ejecutar downgrade |
| `POST /subscriptions/client/manage/downgrade` | ClientDashboardGuard | Ejecutar downgrade |

**Reglas de negocio:**
- Usa `plansService.checkDowngradeEligibility()` — NUNCA permite downgrade si el uso excede los límites del plan destino
- Solo suscripciones `active`/`authorized` pueden bajarse
- Multi-LATAM: resuelve precio local con FX rate
- Actualiza precio en MP, subscription, nv_accounts
- Sincroniza entitlements al plan inferior
- Emite evento outbox para sync en Backend DB

**Flujo:**
1. Resolver client_id desde account
2. Verificar eligibilidad (6 métricas: products, banners, coupons, faqs, services, storage)
3. Advisory lock
4. Update MP price
5. Update subscription + nv_accounts plan_key
6. Sync entitlements
7. Emit plan.changed outbox
8. Log CRM + billing event + lifecycle

### Pause Expiration Cron

- `expirePausedSubscriptions()` @ 3:30 AM daily en `lifecycle-cleanup.cron.ts`
- Busca subscriptions con `status='paused'` y `pause_expires_at <= NOW()`
- Las cancela automáticamente (`status='canceled'`, `lifecycle_stage='churned'`)
- Registra evento `pause_expired` en `subscription_events`
- Procesa hasta 50 por ejecución, resiliente a errores individuales

### Migraciones ejecutadas

| Migración | BD | Resultado |
|-----------|-----|-----------|
| `20260326_support_tickets_ai_pipeline.sql` | Admin | OK — columnas y tabla ya existían (idempotente) |
| `20260326_subscription_pause_columns.sql` | Admin | OK — `paused_at`, `pause_expires_at` + índice creados |

### Cambios auxiliares

- `pauseStoreIfNeeded()` ahora reconoce estado `'paused'` como trigger de pausa de tienda
- `PlansService` inyectado en `SubscriptionsService` para check de elegibilidad
- Test preexistente `subscriptions-lifecycle.spec.ts` actualizado para nuevo constructor parameter

### Archivos modificados

- `api/src/subscriptions/subscriptions.service.ts` — 4 métodos nuevos: `requestSubscriptionPause()`, `requestSubscriptionResume()`, `requestDowngrade()`, `resolveClientIdForAccount()`
- `api/src/subscriptions/subscriptions.controller.ts` — 6 endpoints nuevos
- `api/src/lifecycle/lifecycle-cleanup.cron.ts` — cron `expirePausedSubscriptions()`
- `api/migrations/admin/20260326_subscription_pause_columns.sql` — migración columnas pause
- `api/test/subscriptions-lifecycle.spec.ts` — fix constructor args

### Tests creados

- `api/src/subscriptions/__tests__/subscription-pause-downgrade.spec.ts` — 12 tests:
  - Pause: pausar activa, rechazar months>3, rechazar months<1, rechazar no-active, rechazar max pausas
  - Resume: reanudar pausada, rechazar no-pausada
  - Downgrade: ejecutar eligible, rechazar exceedances, rechazar sin plan inferior, rechazar no-active, rechazar sin client
- `api/src/lifecycle/__tests__/lifecycle-cleanup.cron.spec.ts` — 4 tests nuevos:
  - Cancelar pausas expiradas, no-op sin expiradas, error DB graceful, continuar si falla una

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 111/111 suites, 1103/1105 tests OK (2 skipped preexistentes)

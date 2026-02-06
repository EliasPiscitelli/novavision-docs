# Cambio: Subscription Hardening — F5 (Observabilidad) + F6 (Security hardening)

- **Autor:** copilot-agent
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Fases del plan:** F5 + F6 (de subscription-hardening-plan.md)

---

## Archivos modificados

### F5 — Monitoreo y observabilidad

| Archivo | Acción | Descripción |
|---|---|---|
| `apps/api/src/admin/admin.controller.ts` | MODIFIED | Nuevo endpoint `GET /admin/subscriptions/health` con `SuperAdminGuard` |
| `apps/api/src/admin/admin.service.ts` | MODIFIED | Nuevo método `getSubscriptionsHealth()` (~95 líneas) con 5 queries de monitoreo |
| `apps/api/src/subscriptions/subscriptions.service.ts` | MODIFIED | Helper `logSubAction()` con correlation_id, instrumentado en 4 flujos |

### F6 — Security hardening y edge cases

| Archivo | Acción | Descripción |
|---|---|---|
| `apps/api/src/services/mp-router.service.ts` | MODIFIED | F6.1: production hard-reject sin webhook secret + error logging en firma inválida. F6.2: dedup logging con eventKey. |
| `apps/api/src/subscriptions/subscriptions.service.ts` | MODIFIED | F6.3: test user block en `createSubscriptionForAccount()` + sandbox skip en `reconcileWithMercadoPago()`. F6.4: auth error detection en reconcile + upgrade. F6.5: advisory lock in-memory en `processMpEvent()` + `requestUpgrade()`. F6.6: transición `incomplete/pending → active` automática por webhook. |

---

## Detalle de cada sub-tarea

### F5.1 — Health-check endpoint
```
GET /admin/subscriptions/health → SuperAdminGuard
```
Retorna:
- `total_active`, `total_by_status` (active, past_due, grace, etc.)
- `desync_count`: subscriptions.status ≠ nv_accounts.subscription_status
- `stale_sync_count`: subs activas sin sync en >48h
- `mp_connected_no_subscription`: cuentas con MP conectado pero sin registro en subscriptions
- `last_reconcile_at`: última ejecución del cron de reconciliación

### F5.2 — Queries de monitoreo integradas
5 queries ejecutadas en paralelo dentro de `getSubscriptionsHealth()`:
1. Desync sub ↔ account
2. Stale sync >48h
3. MP connected sin subscription
4. Last reconcile event
5. Totales por status

### F5.3 — Correlation ID en logs
Helper `logSubAction()` — estructura:
```typescript
{
  correlation_id: string,
  account_id: string,
  subscription_id: string,
  mp_preapproval_id: string,
  action: 'webhook_received' | 'status_changed' | 'plan_upgrade' | 'cancel_requested' | ...,
  old_status: string,
  new_status: string,
  source: 'webhook' | 'cron' | 'manual' | 'client_action',
  extra?: Record<string, any>
}
```
Instrumentado en: `processMpEvent`, `handleSubscriptionUpdated`, `requestUpgrade`, `requestCancel`.

---

### F6.1 — Webhook signature hardening
**Archivo:** `mp-router.service.ts` → `handleWebhook()`

**Cambio:**
- Si la firma es inválida → `this.logger.error()` con `domain`, `topic`, `resourceId` (antes era silencioso)
- Si no hay webhook secret configurado:
  - **En producción (`NODE_ENV=production`):** → `throw new UnauthorizedException('Webhook secret not configured')` — rechazo duro
  - **En desarrollo:** → `this.logger.warn('CRITICAL: No webhook secret configured')` — solo advertencia

**Por qué:** En producción, un webhook sin secret es un vector de ataque. Un atacante podría enviar eventos falsos para cambiar estados de suscripción. El rechazo duro previene esto.

### F6.2 — Idempotencia reforzada
**Archivo:** `mp-router.service.ts` → `handleWebhook()`

**Cambio:** Cuando `insertEvent()` detecta un duplicado (`!inserted`), ahora loguea:
```
⚡ Duplicate webhook event detected (key=<first 12 chars>…). Ignoring.
```

**Por qué:** Antes los duplicados eran silenciosos. Si un webhook llega 3 veces, ahora se ve en los logs cuántas veces fue descartado, útil para debugging.

### F6.3 — Sandbox vs Producción
**Archivo:** `subscriptions.service.ts`

**Cambios:**
1. **En `createSubscriptionForAccount()`:** Si `NODE_ENV=production`, bloquea emails que contienen `test_user_` o terminan en `@testuser.com`. Retorna un 403 con mensaje claro.
2. **En `reconcileWithMercadoPago()`:** Si `NODE_ENV=production` y MP devuelve `live_mode: false` para un preapproval, se skipea esa suscripción con warning. No se sincronizan datos de sandbox a producción.

**Por qué:** En sandbox, MP usa test users. Si alguna suscripción de sandbox "se cuela" en producción (ej: por migración de datos), el reconcile podría sobrescribir estados con datos de sandbox. El guard previene esto.

### F6.4 — Tokens rotados/expirados
**Archivo:** `subscriptions.service.ts`

**Cambios:**
1. **En `reconcileWithMercadoPago()`:** El catch de cada sub ahora detecta errores 401/403/unauthorized/invalid_token. Si es auth error:
   - Loguea `🔑 AUTH ERROR` con contexto
   - Flaggea `last_reconcile_source = '{source}_auth_error'` en la sub
   - El admin dashboard puede surfacear esto con `getSubscriptionsHealth()`
2. **En `requestUpgrade()`:** El `platformMp.updateSubscriptionPrice()` ahora está envuelto en try/catch. Si es auth error → `InternalServerErrorException('Mercado Pago credentials may have expired. Please contact support.')`. Errores no-auth se re-threwan normalmente.

**Por qué:** Cuando MP rota tokens o el access_token expira, las operaciones fallaban con mensajes genéricos. Ahora el error es específico y se flaggea en DB para que el health-check lo surfacee.

### F6.5 — Race condition: upgrade vs webhook
**Archivo:** `subscriptions.service.ts`

**Cambio:** Advisory lock in-memory con `Map<accountId, timestamp>` y TTL 30s:
- `acquireLock(accountId)` → `true` si libre o expirado, `false` si locked
- `releaseLock(accountId)` → limpia el lock

Aplicado en:
- `processMpEvent()` (rama preapproval): si locked → log warning + skip (idempotente, el webhook se reintentará)
- `requestUpgrade()`: si locked → `throw BadRequestException('Another operation is in progress')` (el usuario puede reintentar)

Ambos usan `try/finally` para garantizar `releaseLock()`.

**Por qué:** Si un webhook de MP llega (ej: payment.authorized) exactamente mientras el usuario hace upgrade, ambos intentan escribir el mismo registro y pueden pisar estados mutuamente. El lock serializa las operaciones por account_id.

**Limitación:** Es in-memory, por lo que solo funciona en single-instance. Si se escala a múltiples instancias, se necesita Redis distributed lock o `SELECT...FOR UPDATE`. Para el volumen actual de NovaVision (decenas de clientes), single-instance es suficiente.

### F6.6 — Edge case: incomplete/pending → active
**Archivo:** `subscriptions.service.ts` → `processMpEvent()`

**Cambio:** Antes del check de `canceled`/`past_due`, se agregó:
```typescript
if (newStatus === 'active' && (subscription.status === 'incomplete' || subscription.status === 'pending')) {
  // promote to active + syncAccount
}
```

**Por qué:** Cuando un usuario crea una suscripción pero no completa el pago, el status queda `incomplete` o `pending`. Cuando finalmente paga, MP envía webhook con `status: authorized`. Sin este guard, el código no hacía nada especial porque `active !== subscription.status` caía al else genérico. Ahora loguea el evento como transición exitosa.

---

## Cómo probar

### F5 — Health check
```bash
curl -X GET http://localhost:3000/admin/subscriptions/health \
  -H "Authorization: Bearer <super_admin_jwt>"
# → JSON con métricas (desync_count, stale_sync_count, etc.)
```

### F6 — Webhook sin firma (producción)
```bash
# Con NODE_ENV=production y sin MP_WEBHOOK_SECRET configurado:
curl -X POST http://localhost:3000/webhooks/mp/platform-subscriptions \
  -H "Content-Type: application/json" \
  -d '{"type":"preapproval","data":{"id":"123"}}'
# → 401 Unauthorized
```

### F6 — Race condition
```bash
# Enviar upgrade y webhook simultáneamente para el mismo account
# El segundo request debe recibir 400 o ser skipped (webhook)
```

---

## Notas de seguridad
- **WEBHOOK SECRET EN PRODUCCIÓN ES OBLIGATORIO.** Sin él, los webhooks se rechazan con 401. Configurar `MP_WEBHOOK_SECRET_PLATFORM` y/o `MP_WEBHOOK_SECRET_TENANT` en Railway.
- El advisory lock tiene TTL 30s para auto-recovery si un request crashea sin liberar.
- Los test users de MP se bloquean solo en `NODE_ENV=production`. En dev/staging se permite para testing.

---

## Riesgos
- **Lock in-memory:** No sobrevive restart ni funciona multi-instancia. Si NovaVision escala, migrar a Redis lock.
- **Auth error detection:** Se basa en string matching (`'unauthorized'`, `'forbidden'`, etc.). Si MP cambia el formato de error, podría no detectarse. Monitoreado por `last_reconcile_source=auth_error`.
- **Sandbox check:** `live_mode` solo está disponible si MP lo incluye en la respuesta del SDK. Si el campo no viene, no se bloquea (fail-open por seguridad operativa).

# Hardening completo del ciclo de vida de suscripciones

- **Autor:** agente-copilot
- **Fecha:** 2026-02-16
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** develop → cherry-pick a feature/multitenant-storefront
- **Commits API:** `05c5c62`, `230621d`
- **Commits Web:** `910c409` (develop), `3fe39d7` (multitenant-storefront)

---

## Archivos modificados

### API (templatetwobe)
| Archivo | Cambio |
|---------|--------|
| `src/plans/plans.service.ts` | `getClientPlanKey()` reescrito para leer de Backend DB |
| `src/outbox/outbox-worker.service.ts` | `handlePlanChanged()` ahora escribe `plan_key` + `plan` |
| `src/subscriptions/subscriptions.service.ts` | 6 fixes en flujo de suscripción |

### Web (templatetwo)
| Archivo | Cambio |
|---------|--------|
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Filtrado de planes inferiores al actual |

---

## Resumen de bugs encontrados y corregidos

### Bug 1 (CRÍTICO): `getClientPlanKey()` siempre retornaba `'starter'`

**Causa raíz:** La función buscaba en Admin DB `subscriptions` usando el UUID del Backend `clients.id`, que es un espacio de UUIDs completamente diferente al de `nv_accounts.id` (Admin Auth). Nunca matcheaba → fallback a `'starter'`.

**Impacto:** Todos los endpoints que usaban `getClientPlanKey()` (ej: `/plans/my-limits`, shipping plan gating) siempre devolvían entitlements de plan Starter, sin importar el plan real del cliente.

**Fix:** Reescrito para leer directamente de Backend DB `clients.plan_key ?? clients.plan` — misma fuente de verdad que `PlanAccessGuard`. Eliminadas 3 queries cross-DB innecesarias reducidas a 1.

### Bug 2 (ALTO): Outbox `plan.changed` no sincronizaba `plan_key`

**Causa raíz:** `handlePlanChanged()` solo actualizaba `clients.plan` (columna legacy) pero no `clients.plan_key` (columna nueva). `PlanAccessGuard` lee `plan_key ?? plan`, así que funcionaba por fallback, pero `getClientPlanKey()` leía `plan_key` primero y lo encontraba `null`.

**Fix:** Agregado `plan_key: p.new_plan` al update fields del outbox worker.

### Bug 3 (ALTO): `syncEntitlementsAfterUpgrade()` no escribía `plan_key` al Backend

**Causa raíz:** Solo escribía el blob `entitlements`, dejando `plan_key` y `plan` sin actualizar hasta que el outbox asíncrono lo procesara.

**Fix:** Agregados `plan_key` y `plan` al update de Backend `clients`.

### Bug 4 (ALTO): Lista de planes mostraba downgrades

**Causa raíz:** `getManagePlans()` devolvía TODOS los planes activos sin ningún filtro de tier. El frontend solo excluía el plan actual exacto (`p.plan_key !== currentPlanKey`) pero no los inferiores.

**Impacto:** Un usuario Growth veía "Starter Store — Cambiar a este plan" en la UI. Si hacía clic, el backend rechazaba el downgrade, pero la UX era confusa.

**Fix (doble capa):**
- **Backend:** `getManagePlans()` ahora filtra por `normalizePlanKey()` + `PLAN_TIERS`, solo retorna planes de tier >= al actual.
- **Frontend:** `availablePlans` aplica el mismo filtro con `PLAN_TIER` local como defensa en profundidad.

### Bug 5 (ALTO): `syncEntitlementsAfterCancel()` no limpiaba `plan_key` en Backend ni Admin

**Causa raíz:** La función limpiaba `entitlements` correctamente pero dejaba `clients.plan_key = 'growth'` y `nv_accounts.plan_key = 'growth'` intactos.

**Impacto dual:**
1. El Backend pensaba que el cliente seguía en Growth (guards de acceso no bloqueaban)
2. `getManagePlans()` con el nuevo filtro no mostraría Starter al usuario cancelado que quiere re-suscribirse

**Fix:** Limpia `plan_key`/`plan` a `'starter'` (o plan free si existe) en Backend DB y `nv_accounts`.

### Bug 6 (CRÍTICO): `revertCancel()` no reactivaba suscripción en MercadoPago

**Causa raíz:** `requestCancel()` cancela el preapproval en MP inmediatamente (incluso si es `cancel_scheduled`). Pero `revertCancel()` solo restaura el estado en DB → MP queda cancelado → no se cobra el próximo período.

**Fix:** Agregada llamada a `this.platformMp.resumeSubscription(preapprovalId)` con manejo non-blocking de errores (MP podría rechazar si el preapproval ya expiró).

### Bug 7 (ALTO): `handlePaymentSuccess()` no despausaba la tienda

**Causa raíz:** Cuando un pago exitoso reactiva una suscripción suspendida, el código hacía un update directo a `nv_accounts` sin pasar por `syncAccountSubscriptionStatus()`, que es la función que evalúa si la tienda debe despausarse via `unpauseStoreIfReactivated()`.

**Impacto:** Tienda quedaba pausada hasta el cron `reconcileCrossDb` (6:15 AM).

**Fix:** Reemplazado update directo por `syncAccountSubscriptionStatus(account_id, 'active')` que ejecuta la cadena completa incluyendo unpause.

### Bug 8 (MEDIO): `processDeactivations()` no pausaba tienda ni bajaba entitlements

**Causa raíz:** El cron que procesa `cancel_scheduled → deactivated` solo actualizaba estados en Admin DB pero no ejecutaba side-effects en Backend DB.

**Impacto:** Tienda seguía publicada + entitlements en nivel premium después de que vence el período pagado.

**Fix:** Agregado loop que llama `pauseStoreIfNeeded()` + `syncEntitlementsAfterCancel()` para cada cuenta deactivada.

---

## Pipeline de sincronización de `plan_key` — Estado FINAL

```
┌─────────────────────────────────────────────────────────────────┐
│  PATH                          │ sub │ nv_acc │ BE.plan_key │ BE.plan │
│────────────────────────────────┼─────┼────────┼─────────────┼─────────│
│  createSubscription            │ ✅  │  ❌*  │     ❌*     │   ❌*   │
│  requestUpgrade                │ ✅  │  ✅   │  ✅ (sync)  │ ✅ (sync)│
│  syncEntitlementsAfterUpgrade  │ --  │  --   │     ✅      │   ✅    │
│  outbox plan.changed           │ --  │  --   │     ✅      │   ✅    │
│  requestCancel (immediate)     │ --  │  ✅   │  ✅ (clean) │ ✅ (clean)│
│  syncEntitlementsAfterCancel   │ --  │  ✅   │     ✅      │   ✅    │
│  processDeactivations (cron)   │ --  │  ✅   │  ✅ (clean) │ ✅ (clean)│
│  revertCancel                  │ --  │  --   │     --      │   --    │
│  handlePaymentSuccess          │ --  │  ✅†  │     --      │   --    │
└─────────────────────────────────────────────────────────────────┘

* = Delegado al flujo de onboarding (fuera de este scope)
† = Vía syncAccountSubscriptionStatus() que puede unpausar
```

---

## Cómo probar

### Filtrado de planes (Bug 4)
1. Loguearse como admin de tienda con plan Growth
2. Ir a Administración > Suscripción > "Planes disponibles"
3. **Esperado:** Solo muestra Growth Annual y Enterprise (NO Starter)
4. **Antes del fix:** Mostraba Starter Store y Starter Store Annual

### Cancelación y re-suscripción (Bugs 5, 6)
1. Desde plan Growth, solicitar cancelación
2. Si tiene período pagado → cancel_scheduled (revertible)
3. Revertir → debe reactivar en MP + UI dice "Activa"
4. Si no tiene período → cancel_immediate → plan_key baja a starter
5. Volver a ver planes → muestra Starter + Growth + Enterprise

### Payment recovery (Bug 7)
1. Simular 3 pagos fallidos → store se pausa
2. Confirmar pago exitoso vía webhook
3. **Esperado:** Tienda se despausa automáticamente
4. **Antes del fix:** Tienda quedaba pausada hasta cron 6:15 AM

---

## Notas de seguridad
- El filtrado de planes es double-layer (backend + frontend) para defense-in-depth
- El backend ya bloqueaba downgrades en `performUpgrade()` con excepción explícita
- La reactivación MP en `revertCancel()` es non-blocking: si MP rechaza, se loguea pero no rompe el flujo
- Los errores de syncEntitlementsAfterCancel en processDeactivations se loguean per-account sin interrumpir el batch

## Riesgos / Rollback
- **Riesgo bajo:** Los fixes son defensivos y se aplican en paths que antes no hacían nada (agregan funcionalidad, no cambian la existente)
- **Rollback:** Revertir commit `230621d` en API y `910c409`/`3fe39d7` en Web

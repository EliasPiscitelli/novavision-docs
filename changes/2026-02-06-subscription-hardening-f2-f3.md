# Cambio: Subscription Hardening — F2 (Upgrade robusto) + F3 (Billing UI)

- **Autor:** copilot-agent
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Fases del plan:** F2 + F3 (de subscription-hardening-plan.md)

---

## Archivos modificados

### F2 — Upgrade hardening

| Archivo | Acción | Descripción |
|---|---|---|
| `apps/api/src/subscriptions/subscriptions.service.ts` → `requestUpgrade()` | MODIFIED | Downgrade tier prevention (`PLAN_TIERS`), cycle downgrade prevention (annual→monthly mismo tier), sync entitlements post-upgrade, audit log via billing events |
| `apps/api/src/subscriptions/subscriptions.service.ts` → `syncEntitlementsAfterUpgrade()` | NEW method | Lee plan → upsert `account_entitlements` (Admin DB) + actualiza `clients` (Backend DB) |
| `apps/api/src/subscriptions/subscriptions.service.ts` → `getEffectiveStatus()` | NEW method | Combina `subscriptions.status` + grace window para resolver status efectivo |
| `apps/api/src/types/palette.ts` L59-63 | MODIFIED | Exporta `PLAN_TIERS = { starter: 1, growth: 2, enterprise: 3 }` |
| `apps/api/src/guards/subscription.guard.ts` | MODIFIED | Expandido: acepta `active`, `trialing`, `grace`, `past_due` → permite operar durante grace |
| Decorador `@SkipSubscriptionCheck()` | NEW | Permite rutas de billing/manage esquivar el guard |

### F3 — Billing UI para clientes

| Archivo | Acción | Descripción |
|---|---|---|
| `apps/admin/src/pages/Settings/BillingPage.tsx` | NEW (~480 líneas) | Página completa: plan actual, status badge, precio ARS/USD, próximo cobro, acciones upgrade/cancel |
| `apps/admin/src/pages/ClientCompletionDashboard/index.tsx` | MODIFIED | Integrada tarjeta de suscripción + `SubscriptionExpiredBanner` con link a `/settings/billing` |
| `apps/admin/src/App.jsx` | MODIFIED | Nueva ruta `/settings/billing` → `BillingPage` |

---

## Por qué se hizo

### F2 — Motivación
- **P3 (CRÍTICA):** `requestUpgrade()` permitía downgrades (Growth→Starter) sin validación.
- **P4 (ALTA):** Tras un upgrade, los entitlements (límites de productos, categorías, etc.) no se propagaban al account ni al backend multicliente.
- **P10:** Cambio de ciclo annual→monthly en mismo tier era un downgrade disfrazado.
- **P11:** No existía audit log de cambios de plan.

### F3 — Motivación
- **P8:** Los handlers de gestión de suscripción estaban preparados en `ClientCompletionDashboard` pero el JSX nunca se renderizaba.
- **P9:** `SubscriptionExpiredBanner` navegaba a `/settings/billing` que no existía → 404.

---

## Lógica clave

### Jerarquía de planes (inmutable)
```
PLAN_TIERS = { starter: 1, growth: 2, enterprise: 3 }
```
- Solo se permite `targetTier > currentTier` (upgrade).
- Para mismo tier: `monthly → annual` = OK, `annual → monthly` = BLOQUEADO.
- `normalizePlanKey()` mapea `pro` → `enterprise` para compatibilidad.

### Sync de entitlements post-upgrade
1. Lee plan target desde tabla `plans` (Admin DB)
2. Upsert en `account_entitlements` (Admin DB)
3. Actualiza `clients.max_products`, `clients.max_categories`, etc. (Backend/Multicliente DB)
4. Log en `nv_billing_events`

### BillingPage — Endpoints consumidos
- `GET /subscriptions/manage-status` → plan, status, precios, período
- `GET /subscriptions/manage-plans` → planes disponibles (solo superiores)
- `POST /subscriptions/manage-upgrade` → ejecuta upgrade
- `POST /subscriptions/manage-cancel` → cancela suscripción

---

## Cómo probar

### F2
```bash
# Terminal back
npm run start:dev

# Test upgrade (debe funcionar)
curl -X POST http://localhost:3000/subscriptions/manage-upgrade \
  -H "Authorization: Bearer <jwt>" \
  -d '{"target_plan_key": "growth"}'

# Test downgrade (debe rechazar con 400)
curl -X POST http://localhost:3000/subscriptions/manage-upgrade \
  -H "Authorization: Bearer <jwt>" \
  -d '{"target_plan_key": "starter"}'
# → "Downgrade not allowed: cannot go from growth to starter"

# Test cycle downgrade (debe rechazar con 400)
curl -X POST http://localhost:3000/subscriptions/manage-upgrade \
  -H "Authorization: Bearer <jwt>" \
  -d '{"target_plan_key": "growth"}'
# (siendo growth_annual) → "Cycle downgrade not allowed"
```

### F3
```bash
# Terminal front (admin)
npm run dev
# Abrir http://localhost:5174/settings/billing
# Verificar: plan actual, state badge, botón upgrade (solo planes superiores), cancel con doble confirmación
```

---

## Notas de seguridad
- `@SkipSubscriptionCheck()` solo se aplica a rutas de billing/manage y health-check. Nunca a CRUD de tienda.
- BillingPage no muestra opción de downgrade. Solo planes con tier superior.
- Cancel tiene doble confirmación en UI + `markCancelScheduled()` registra auditoría.

---

## Riesgos
- `syncEntitlementsAfterUpgrade` depende de que `plans` tenga entitlements configurados. Si un plan no tiene `max_products` definido, no se actualiza ese campo.
- Cambio de ciclo (monthly↔annual) que requiera cancelar+crear nuevo PreApproval aún no implementado (solo cambio de precio funciona). Bloqueado por validación.

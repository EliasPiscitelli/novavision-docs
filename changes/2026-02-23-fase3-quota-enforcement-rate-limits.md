# Cambio: Fase 3 — Quota Enforcement + Rate Limits

- **Autor:** agente-copilot
- **Fecha:** 2026-02-23
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Fase:** 3 de Plan Maestro Internacionalización

---

## Archivos creados (7 nuevos)

| Archivo | Tarea | Descripción |
|---------|-------|-------------|
| `src/billing/usage-consolidation.cron.ts` | 3.1 | Cron diario (02:30 UTC) que agrega `usage_daily` (Backend DB) → `usage_rollups_monthly` (Admin DB). Idempotente vía UPSERT en `(tenant_id, period_start)`. |
| `src/billing/quota-enforcement.service.ts` | 3.2 | Máquina de estados de quotas. Evalúa uso vs límites del plan y transiciona: ACTIVE → WARN_50 → WARN_75 → WARN_90 → SOFT_LIMIT → GRACE → HARD_LIMIT. Feature flag `ENABLE_QUOTA_ENFORCEMENT` (default: OFF). |
| `src/guards/quota-check.guard.ts` | 3.3 | Guard NestJS pre-write. Bloquea POST/PUT/PATCH/DELETE si tenant está en HARD_LIMIT (403). Agrega headers `X-Quota-State`, `X-Quota-Warning`. Fail-open ante errores. |
| `src/common/decorators/skip-quota-check.decorator.ts` | 3.3 | Decorator `@SkipQuotaCheck()` para bypass en endpoints críticos (webhooks, health). |
| `src/guards/tenant-rate-limit.guard.ts` | 3.4 | Guard per-tenant rate limiting vía Redis. Dos ventanas: sustained (rps_sustained/1s) y burst (rps_burst×5s). Lee límites del plan con cache in-memory 60s. Fail-open sin Redis. |
| `src/admin/admin-quotas.controller.ts` | 3.5 | Endpoints Super Admin: `GET/PATCH /admin/quotas/:tenantId`, `POST /admin/quotas/:tenantId/reset`. |
| `src/admin/dto/update-quota-state.dto.ts` | 3.5 | DTO con class-validator para override de estado. |
| `src/billing/quota.controller.ts` | 3.6 | Endpoints tenant-facing: `GET /v1/tenants/:id/quotas`, `POST /v1/quota/check`. |

## Archivos modificados (2)

| Archivo | Cambio |
|---------|--------|
| `src/billing/billing.module.ts` | Registrados: `UsageConsolidationCron`, `QuotaEnforcementService`, `QuotaController`. Exports: `QuotaEnforcementService`. |
| `src/admin/admin.module.ts` | Registrado: `AdminQuotasController` en controllers. |

## Resumen de la máquina de estados

```
ACTIVE (< 50%) → WARN_50 (50-74%) → WARN_75 (75-89%) → WARN_90 (90-99%)
  → SOFT_LIMIT (≥ 100%)
    → GRACE (si overage_allowed, con grace_days del plan)
      → HARD_LIMIT (grace expirado, o sin overage_allowed)
```

- Los estados son **monotónicos** dentro de un período de billing (no retroceden)
- El reset ocurre al inicio de un nuevo período vía `POST /admin/quotas/:id/reset` o futuro cron
- Las dimensiones evaluadas: `orders`, `apiCalls`, `egressGb`, `storageGb`
- Se usa el **máximo** entre las 4 dimensiones para derivar el estado

## Feature flag

| Variable | Valores | Efecto |
|----------|---------|--------|
| `ENABLE_QUOTA_ENFORCEMENT` | `true` / `1` | Persiste transiciones y encola notificaciones |
| (cualquier otro valor o ausente) | — | Dry-run: evalúa y loguea pero NO bloquea ni actualiza DB |

## Rate limits per-tenant (Plan Maestro §ADMIN_066)

| Plan | Sustained (RPS) | Burst (RPS) |
|------|-----------------|-------------|
| Starter | 5 | 15 |
| Growth | 15 | 45 |
| Enterprise | 60 | 180 |

## Notificaciones

Las transiciones de estado encoladoras notificaciones en `subscription_notification_outbox` con notif_types:
- `quota_warn_50`, `quota_warn_75`, `quota_warn_90`
- `quota_soft_limit`, `quota_grace`, `quota_hard_limit`

Procesadas por el worker existente de `SubscriptionsService`.

## Dependencias de tablas (Fase 1 — ya existentes)

- `quota_state` (ADMIN_069) — PK: `tenant_id`, state FSM
- `usage_rollups_monthly` (ADMIN_070) — PK: `(tenant_id, period_start)`
- `plans` (ADMIN_066 extended) — `rps_sustained`, `rps_burst`, `included_orders`, etc.
- `subscription_notification_outbox` — tabla existente reusada

## Cómo probar

### 1. Verificar feature flag OFF (default)
```bash
# Levantar API
npm run start:dev

# El cron de consolidación corre a las 02:30 UTC (o invocar manualmente via test)
# El enforcement evalúa a las 03:00 UTC en modo dry-run (solo logs)
```

### 2. Probar endpoints admin
```bash
# Listar quotas
curl -X GET http://localhost:3000/admin/quotas \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>"

# Ver detalle de un tenant
curl -X GET http://localhost:3000/admin/quotas/<TENANT_ID> \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>"

# Override manual
curl -X PATCH http://localhost:3000/admin/quotas/<TENANT_ID> \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>" \
  -H "Content-Type: application/json" \
  -d '{"state": "WARN_75"}'

# Reset a ACTIVE
curl -X POST http://localhost:3000/admin/quotas/<TENANT_ID>/reset \
  -H "Authorization: Bearer <SUPER_ADMIN_JWT>"
```

### 3. Probar endpoints tenant
```bash
# Quota status
curl -X GET http://localhost:3000/v1/tenants/<TENANT_ID>/quotas

# Pre-flight check
curl -X POST http://localhost:3000/v1/quota/check \
  -H "x-tenant-slug: <SLUG>" \
  -H "Content-Type: application/json" \
  -d '{"resource": "order"}'
```

### 4. Activar enforcement
```bash
ENABLE_QUOTA_ENFORCEMENT=true npm run start:dev
```

## Validación
```bash
npm run lint      # 0 errors, ~1189 warnings (preexistentes)
npx tsc --noEmit  # 0 errors
npm run build     # ✅ dist/main.js generado
```

## Riesgos / Notas

1. **QuotaCheckGuard NO está registrado como guard global** — se aplica selectivamente con `@UseGuards(QuotaCheckGuard)`. El motivo es que registrarlo globalmente bloquearía rutas donde no es deseable (health, auth, webhooks). Se debe aplicar en módulos de negocio (products, orders, cart) cuando se active enforcement.

2. **TenantRateLimitGuard NO está registrado como guard global** — requiere decidir si aplicar en el middleware global o selectivamente. Sugerencia: aplicar globalmente una vez validado en staging.

3. **`orders_gmv_usd` en rollups** — se inicializa en 0. Será populado por `GmvCommissionCron` en Fase 4.

4. **Resolución tenant_id desde clientId** — Tanto QuotaCheckGuard como TenantRateLimitGuard resuelven `nv_account_id` desde `clients.id`. En alto tráfico, considerar cache Redis para esta resolución.

5. **Grace days** — Leídos de `plans.grace_days`. Default: Starter=7, Growth=14, Enterprise=30.

# Corrección de hallazgos P0 de seguridad — Billing/LATAM

**Fecha:** 2026-02-23  
**Autor:** agente-copilot  
**Rama:** feature/automatic-multiclient-onboarding  
**Origen:** Auditoría de seguridad Fase 7.6 (`2025-07-15-security-audit-billing-latam.md`)

---

## Archivos modificados

| Archivo | Cambio |
|---|---|
| `src/billing/quota.controller.ts` | `@UseGuards(SuperAdminGuard)` en `GET /v1/tenants/:id/quotas` |
| `src/billing/billing.controller.ts` | Role check `superadmin` en `GET billing/admin/all` |
| `src/app.module.ts` | Registrar `QuotaCheckGuard` + `TenantRateLimitGuard` como APP_GUARD |
| `src/common/common.module.ts` | Agregar `RedisRateLimiter` a providers y exports |

---

## Detalle por hallazgo

### P0-1: IDOR en `/v1/tenants/:id/quotas`

**Problema:** El endpoint aceptaba cualquier `tenantId` como parámetro y devolvía las quotas sin verificar ownership ni rol. Con `@AllowNoTenant()`, cualquier usuario autenticado podía enumerar quotas de cualquier tenant.

**Fix:** Agregar `@UseGuards(SuperAdminGuard)` al endpoint. Los super admins ya tienen `INTERNAL_ACCESS_KEY` + validación en tabla `super_admins`. Los tenants regulares usan `GET /quotas/me` que resuelve automáticamente desde su contexto de autenticación.

**Impacto:** Solo super admins pueden consultar quotas por ID arbitrario. El endpoint `GET /quotas/me` para tenants no se ve afectado.

---

### P0-2: Role check faltante en `billing/admin/all`

**Problema:** `GET /billing/admin/all` usaba `PlatformAuthGuard` sin verificar que el usuario tenga rol `superadmin`. Cualquier usuario de la plataforma con JWT válido de Admin DB podía listar todos los eventos de billing de todos los tenants.

**Fix:** Agregar `@Req() req` y verificar `req.user?.role !== 'superadmin'` → `403 Forbidden`. Este patrón ya existía en `admin/:id/mark-paid` y `admin/:id/sync`.

**Impacto:** Solo super admins pueden listar todos los billing events. El endpoint `GET /billing/me` para tenants regulares no se ve afectado.

---

### P0-3: `QuotaCheckGuard` no registrado como APP_GUARD

**Problema:** El guard existía y funcionaba correctamente, pero nunca fue registrado globalmente. La enforcement de quotas de plan (bloquear writes en HARD_LIMIT) no estaba activa.

**Fix:** Registrar en `app.module.ts` como:
```typescript
{ provide: APP_GUARD, useClass: QuotaCheckGuard }
```

**Orden de ejecución de guards:**
1. `TenantContextGuard` → resuelve `request.clientId`
2. `MaintenanceGuard` → bloquea tenants en mantenimiento
3. `QuotaCheckGuard` → bloquea writes si HARD_LIMIT
4. `TenantRateLimitGuard` → rate limiting per-plan

**Comportamiento:**
- GET/HEAD/OPTIONS → siempre permitido (reads)
- POST/PUT/PATCH/DELETE → evalúa quota state
- `HARD_LIMIT` → 403 con `{ code: 'QUOTA_EXCEEDED' }`
- `SOFT_LIMIT` / `GRACE` → permite con header `X-Quota-Warning`
- Feature flag: `ENABLE_QUOTA_ENFORCEMENT=true` requerido
- Bypass: `@SkipQuotaCheck()` decorator

---

### P0-4: `TenantRateLimitGuard` no registrado como APP_GUARD

**Problema:** El guard existía pero no estaba inyectable porque `RedisRateLimiter` no estaba registrado en ningún módulo, y el guard nunca se registró globalmente.

**Fix (2 partes):**

1. **`CommonModule`**: Agregar `RedisRateLimiter` a `providers` y `exports` (ya era `@Injectable()` pero no estaba en ningún módulo)

2. **`app.module.ts`**: Registrar como APP_GUARD:
```typescript
{ provide: APP_GUARD, useClass: TenantRateLimitGuard }
```

**Comportamiento:**
- Rutas con `@AllowNoTenant()` → skip
- Sin `clientId` → pass (fail-open)
- Con tenant: evalúa sustainable RPS (1s) + burst RPS (5s)
- Límites por plan: Starter 5/15, Growth 15/45, Enterprise 60/180
- Redis no disponible → fail-open (logger.error + allow)
- Bloqueado → 429 + `Retry-After` header

---

## Validación

```bash
# Lint + TypeScript + Build → 0 errores
npm run ci          ✅

# Tests Fase 7 → 85/85 passed
npx jest test/*.spec.ts --no-coverage  ✅
```

---

## Riesgos y rollback

| Riesgo | Mitigación |
|---|---|
| Rate limiter bloquea tráfico legítimo si Redis falla | Fail-open: si Redis no responde, el guard permite todo |
| QuotaCheckGuard bloquea operaciones si feature flag está off | `ENABLE_QUOTA_ENFORCEMENT=true` requerido; sin flag → pass-through |
| SuperAdminGuard en quota endpoint podría romper integraciones | Solo afecta `/v1/tenants/:id/quotas` (admin-only); el endpoint tenant `GET /quotas/me` no cambia |

**Rollback:** Remover las 2 entradas `APP_GUARD` de `app.module.ts` para desactivar ambos guards globales sin afectar el resto del sistema.

---

## Notas de seguridad

- Los 4 fixes son defensas en profundidad: RLS de Supabase sigue siendo la barrera primaria
- `TenantRateLimitGuard` usa `ioredis` con `rate-limiter-flexible` — sin dependencias nuevas
- `QuotaCheckGuard` depende de `QuotaEnforcementService` que ya está en `BillingModule` (@Global)
- No se crearon migraciones ni se modificó la DB

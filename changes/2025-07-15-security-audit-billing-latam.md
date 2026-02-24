# Auditoría de Seguridad — Endpoints Billing/LATAM (Fases 1-6)

**Fecha:** 2025-07-15 (auditoría) · 2026-02-23 (fixes aplicados)  
**Autor:** agente-copilot  
**Rama:** feature/automatic-multiclient-onboarding  
**Scope:** Todos los controllers nuevos/modificados en Fases 1-6 del proyecto billing LATAM  
**Estado:** ✅ Todos los hallazgos P0 corregidos (2026-02-23)

---

## 1. Infraestructura Global de Seguridad

| Mecanismo | Estado | Detalle |
|---|---|---|
| `TenantContextGuard` (APP_GUARD) | ✅ PASS | Global, resuelve tenant por slug/domain |
| `MaintenanceGuard` (APP_GUARD) | ✅ PASS | Global, bloquea tenants en mantenimiento |
| Global `ValidationPipe` | ✅ PASS | `{ whitelist: true, transform: true }` en main.ts |
| `QuotaCheckGuard` | ✅ FIXED | Registrado como APP_GUARD (2026-02-23). Bloquea writes en HARD_LIMIT, headers X-Quota-* |
| `TenantRateLimitGuard` | ✅ FIXED | Registrado como APP_GUARD (2026-02-23). Per-tenant RPS por plan, fail-open |
| `SuperAdminGuard` | ✅ PASS | Valida email en tabla `super_admins` + `INTERNAL_ACCESS_KEY` con timing-safe comparison |

---

## 2. Veredicto por Controller

| Controller | Veredicto | Hallazgos |
|---|---|---|
| `AdminFxRatesController` | ✅ PASS | — |
| `AdminCountryConfigsController` | ✅ PASS | — |
| `AdminQuotasController` | ✅ PASS | — |
| `AdminAdjustmentsController` | ⚠️ WARN | Sin DTOs class-validator |
| `AdminFeeSchedulesController` | ⚠️ WARN | Sin DTOs class-validator |
| `QuotaController` (tenant-facing) | ✅ FIXED | IDOR corregido — `SuperAdminGuard` agregado (2026-02-23) |
| `PlansController` | ✅ PASS | — |
| `PlansAdminController` | ⚠️ WARN | DTOs sin validators, sin ParseUUIDPipe |
| `SubscriptionsController` | ⚠️ WARN | Bodies sin DTOs formales |
| `TenantController` | ✅ PASS | — |
| **`BillingController`** | ✅ FIXED | Role check de superadmin agregado a `admin/all` (2026-02-23) |
| `AdminController` | ✅ PASS | ID hardcodeado (bajo riesgo) |
| `AdminClientController` | ⚠️ WARN | DTOs sin validators |
| `AdminAccountsController` | ⚠️ WARN | DTO sin validators |
| `AdminManagedDomainController` | ⚠️ WARN | LIKE pattern wildcards, sin DTO |
| `AdminRenewalsController` | ✅ PASS | — |
| `AdminShippingController` | ✅ PASS | — |
| `AdminOptionSetsController` | ✅ PASS | — |
| `FinanceController` | ✅ PASS | — |

---

## 3. Hallazgos Críticos

### IDOR-1 ~~(ALTA)~~ ✅ CORREGIDO — `/v1/tenants/:id/quotas`
- `@AllowNoTenant()` sin verificación de ownership
- Cualquier usuario autenticado podía enumerar quotas de cualquier tenant
- **Fix aplicado (2026-02-23):** `@UseGuards(SuperAdminGuard)` agregado al endpoint. Solo super admins con INTERNAL_ACCESS_KEY pueden consultar quotas de otros tenants. Los tenants usan `GET /quotas/me` (resuelve desde su contexto).

### AUTH-1 ~~(ALTA)~~ ✅ CORREGIDO — `BillingController`
- `PlatformAuthGuard` sin role check en `billing/admin/all`
- Cualquier usuario de la plataforma podía listar todos los eventos de billing
- **Fix aplicado (2026-02-23):** Agregado check `req.user?.role !== 'superadmin'` → 403 Forbidden. Consistente con `mark-paid` y `sync`.

### GUARD-1 ~~(ALTA)~~ ✅ CORREGIDO — `QuotaCheckGuard` no activo
- El guard existía pero no estaba registrado como APP_GUARD
- La enforcement de quotas por write operations no estaba funcionando
- **Fix aplicado (2026-02-23):** Registrado como `APP_GUARD` en `app.module.ts`. Ejecuta después de TenantContextGuard + MaintenanceGuard. Skippeable con `@SkipQuotaCheck()`.

### GUARD-2 ~~(ALTA)~~ ✅ CORREGIDO — `TenantRateLimitGuard` no activo
- El guard existía pero no estaba aplicado en ningún lado
- El rate limiting per-tenant basado en plan no estaba activo
- **Fix aplicado (2026-02-23):** Registrado como `APP_GUARD` en `app.module.ts`. `RedisRateLimiter` agregado a `CommonModule` (DI). Fail-open si Redis no está configurado. Respeta `@AllowNoTenant()` para rutas sin tenant.

---

## 4. Hallazgos de Inyección

| ID | Severidad | Ubicación | Detalle |
|---|---|---|---|
| INJ-1 | MEDIA | `seo.service.ts` | `.or()` con interpolación directa de `catSlug` — filter injection |
| INJ-2 | BAJA | `support.service.ts` | `.ilike()` — wildcards `%`/`_` no escapados |
| INJ-3 | BAJA | admin-managed-domain.controller | `.ilike()` — mismo patrón, solo super admin |

---

## 5. Recomendaciones (priorizado)

### P0 — ✅ TODOS CORREGIDOS (2026-02-23)
1. ~~**Corregir `BillingController`**~~ → Role check de superadmin agregado a `admin/all`
2. ~~**Fix IDOR en `/v1/tenants/:id/quotas`**~~ → `@UseGuards(SuperAdminGuard)` aplicado
3. ~~**Registrar `QuotaCheckGuard` como APP_GUARD**~~ → Registrado en `app.module.ts`
4. ~~**Registrar `TenantRateLimitGuard` como APP_GUARD**~~ → Registrado en `app.module.ts` + `RedisRateLimiter` en `CommonModule`

### P1 — Antes de expansión LATAM
5. Agregar DTOs class-validator a: Adjustments, FeeSchedules, PlansAdmin, Subscriptions, AdminClient, AdminAccounts
6. Fix filter injection en `seo.service.ts` (usar `.eq()` en lugar de `.or()` interpolado)

### P2 — Mejora continua
7. Escapar wildcards en `.ilike()` para búsquedas con input de usuario
8. Mover `INTERNAL_CLIENT_ID` a variable de entorno

---

## 6. Secretos Hardcodeados

| Hallazgo | Riesgo |
|---|---|
| `INTERNAL_CLIENT_ID = 'ae02842d-...'` en AdminController | BAJO — Es un ID de filtrado |
| No se encontraron tokens, passwords ni API keys hardcodeados | ✅ |

---

## 7. Notas

- La auditoría cubre los controllers existentes en la rama `feature/automatic-multiclient-onboarding`
- Supabase SDK parametriza queries automáticamente, lo que mitiga riesgos de SQL injection directa
- El `ValidationPipe({ whitelist: true })` global solo funciona si los DTOs tienen decorators class-validator
- Las funciones `.rpc()` de Supabase usan parámetros nombrados (seguro)

# Plan: Single Cluster + Metering / Quotas / Enforcement

**Fecha**: 2026-02-28  
**Autor**: agente-copilot  
**Rama**: `feature/automatic-multiclient-onboarding`  
**Prerequisitos completados**: Investigación A-D (inventario exhaustivo con evidencia)

---

## Resumen ejecutivo

El sistema tiene **tres capas de enforcement** independientes:

| Capa | Tipo | Latencia | Estado actual |
|------|------|----------|--------------|
| **A. Plan Limits** (real-time) | Síncrona, por endpoint | 0 ms | ✅ Funcional para 4 acciones |
| **B. Metering Pipeline** (batch) | Asíncrona, cron diario | 24h lag | ❌ **Rota** (DB mismatch) |
| **C. Quota Enforcement** (batch) | State machine diaria | 24h lag | 🟡 Código OK, flag OFF |

### Evidencia de los hallazgos

1. **Backend DB `client_usage`** → tiene triggers para `products_count`, `banners_active_count`, `storage_bytes_used`, `orders_month_count` ✅
2. **Tabla `coupons`** → NO EXISTE en Backend DB → `active_coupons_count` es placeholder ✅ (correcto)
3. **`usage_ledger`, `usage_hourly`, `usage_daily`** → existen en **Admin DB** (via `SUPABASE_METERING_CLIENT`) pero el `UsageConsolidationCron` los busca en **Backend DB** → ❌ DB y columnas incorrectas
4. **`ENABLE_QUOTA_ENFORCEMENT`** → default `false` en todos los entornos (18 matches en codebase)
5. **`PlansService.validateAction('create_order')`** → soft cap only (siempre retorna `allowed: true`)
6. **Plans table** → tiene entitlements completos (products_limit, banners_active_limit, max_monthly_orders, storage_gb_quota, etc.)
7. **Hardcoded limits** → existen en `design.validator.ts`, `palettes.service.ts`, admin FE (`ManualProductLoader`, `CatalogLoader`)
8. **`chooseBackendCluster()`** → funciona con 1 cluster (`cluster_shared_01`) pero tiene weighted random innecesario

---

## Bloque 1: Single Cluster Hardening (P0)

### Objetivo
Simplificar y endurecer el routing para 1 solo cluster, eliminando complejidad innecesaria.

### 1.1 — Forzar `cluster_shared_01` como constante (P0, ~1h)

**Archivo**: `src/db/db-router.service.ts`  
**Líneas**: ~183-210 (`chooseBackendCluster()`)

**Estado actual**: Weighted random across clusters con filtro por `status='ready'`, con fallback a `cluster_shared_01`.  
**Cambio**: Retornar `cluster_shared_01` directamente, saltando el query + weighted random.

```typescript
// ANTES (simplificado):
async chooseBackendCluster(): Promise<string> {
  const clusters = await this.getClusterList(); // query + cache  
  // weighted random...
  return selected?.cluster_id ?? 'cluster_shared_01';
}

// DESPUÉS:
async chooseBackendCluster(): Promise<string> {
  // Single-cluster mode: bypass query + weighted random
  return 'cluster_shared_01';
}
```

**Riesgo**: Bajo. El fallback ya era `cluster_shared_01`.  
**Rollback**: Revertir a la versión anterior.  
**DoD**: `chooseBackendCluster()` retorna `'cluster_shared_01'` sin query a Admin DB.

### 1.2 — Backfill `backend_cluster_id` en `nv_accounts` (P0, ~30min)

**Migración**: `migrations/admin/ADMIN_071_backfill_cluster_id.sql`

```sql
-- Asegurar que todas las cuentas activas tengan cluster asignado
UPDATE nv_accounts
SET backend_cluster_id = 'cluster_shared_01', updated_at = NOW()
WHERE (backend_cluster_id IS NULL OR backend_cluster_id = '')
  AND status IN ('approved', 'live', 'provisioned', 'pending_approval');
```

**Riesgo**: Nulo. Solo backfills NULLs.  
**DoD**: `SELECT COUNT(*) FROM nv_accounts WHERE backend_cluster_id IS NULL AND status IN (...)` = 0.

### 1.3 — Guard de creación de clusters (P1, ~30min)

**Archivo**: `src/admin/admin.service.ts` (si existe endpoint de crear cluster)  
**Cambio**: Si existe `createCluster` o endpoint similar, agregar check:

```typescript
if (process.env.MULTI_CLUSTER_ENABLED !== 'true') {
  throw new ForbiddenException('Multi-cluster is not enabled in this environment');
}
```

**Verificar antes**: si existe un endpoint de crear cluster (puede no existir aún).

---

## Bloque 2: Metering / Quotas — Arreglar la cadena batch (P0-P1)

### 2.1 — Fix `UsageConsolidationCron`: leer de Admin DB con columnas correctas (P0, ~2h)

**Archivo**: `src/billing/usage-consolidation.cron.ts`  
**Problema dual**:
1. Lee `usage_daily` de **Backend DB** (`dbRouter.getBackendClient()`) pero la tabla está en **Admin DB**
2. Selecciona columnas wide-format (`request_count, egress_bytes, order_count, storage_bytes`) pero la tabla tiene formato dimensional (`client_id, bucket_date, metric, quantity`)

**Fix**: Cambiar a leer de Admin DB (donde `MetricsService.syncAggregate()` escribe) y pivotar del modelo dimensional:

```typescript
// ANTES:
const tenantBackend = this.dbRouter.getBackendClient(account.backend_cluster_id);
const { data: dailyRows } = await tenantBackend
  .from('usage_daily')
  .select('client_id, request_count, egress_bytes, order_count, storage_bytes')
  ...

// DESPUÉS:
// usage_daily está en Admin DB (escrita por MetricsService via SUPABASE_METERING_CLIENT)
const { data: dailyRows } = await adminClient
  .from('usage_daily')
  .select('client_id, bucket_date, metric, quantity')
  .eq('client_id', account.id)
  .gte('bucket_date', periodStart)
  .lt('bucket_date', monthEnd.split('T')[0]);

// Pivotar a formato wide para rollup
const pivoted = pivotDailyRows(dailyRows);
// orders_confirmed = sum(quantity where metric='order')
// api_calls = sum(quantity where metric='request')
// egress_gb = sum(quantity where metric='egress_bytes') / 1GB
// storage_gb_avg = avg(quantity where metric='storage_bytes') / 1GB
```

**Riesgo**: Medio. Cambia la fuente de datos. Sin embargo, la fuente anterior (Backend DB) nunca funcionó.  
**Rollback**: Revertir fichero.  
**DoD**: Cron ejecuta sin error, `usage_rollups_monthly` tiene datos para el período actual.

### 2.2 — Verificar que MetricsInterceptor + UsageRecorderService → usage_ledger funciona (P0, ~1h)

**Archivos**: `src/metrics/metrics.interceptor.ts`, `src/metrics/usage-recorder.service.ts`

**Estado actual**: `UsageRecorderService` escribe a `usage_ledger` via `SUPABASE_METERING_CLIENT` (Admin DB). La tabla existe en Admin DB ✅.

**Verificación**:
1. Confirmar que el interceptor registra eventos (agregar log de conteo cada 5min si no existe)
2. Confirmar que el flush a `usage_ledger` ejecuta sin error
3. Query: `SELECT COUNT(*) FROM usage_ledger WHERE occurred_at > NOW() - INTERVAL '1 hour'` en Admin DB

**No hay cambio de código necesario si funciona.** Solo verificación.

### 2.3 — Verificar MetricsCron aggregation (P0, ~30min)

**Archivo**: `src/metrics/metrics.cron.ts` → `MetricsService.syncAggregate()`

**Estado actual**: Lee de `usage_ledger` y escribe a `usage_hourly` + `usage_daily`, todo en Admin DB ✅.

**Verificación**:
1. Query: `SELECT COUNT(*) FROM usage_hourly` y `SELECT COUNT(*) FROM usage_daily` en Admin DB
2. Si vacías, trigger manual: `POST /admin/metering/sync` con `{ "hours": 48 }`
3. Verificar que ambas tablas se pueblan

**Cambio**: Ninguno si funciona. Si falla por falta de datos en ledger, arreglar interceptor primero.

### 2.4 — Unificar constantes de overage rates (P1, ~1h)

**Problema**: Tasas inconsistentes entre:
- `MetricsService` (fallback hardcoded en L~300+)
- `OverageService` (lee de `plans` table)
- `plans` table (source of truth)

**Fix**: Hacer que `MetricsService.summary()` lea siempre de `plans` table en vez de usar fallbacks.

**Archivos**:
- `src/metrics/metrics.service.ts` (~L300-400, sección de overage/cost calculation)

**Riesgo**: Bajo. Solo cambia origen de las tasas en el dashboard de métricas.

---

## Bloque 3: Enforcement — Activar la protección (P0-P1)

### 3.1 — Activar `ENABLE_QUOTA_ENFORCEMENT=true` en Railway (P0, ~15min)

**Archivo**: `.env` / Railway environment variables  
**Cambio**: `ENABLE_QUOTA_ENFORCEMENT=true`

**Prerequisito**: Bloques 2.1-2.3 verificados (la cadena batch debe funcionar antes de activar enforcement).

**Efecto**: `QuotaEnforcementService` (cron 03:00 UTC) empezará a actualizar `quota_state`. `QuotaCheckGuard` (global APP_GUARD) empezará a bloquear escrituras cuando `quota_state = HARD_LIMIT`.

**Riesgo**: Medio. Si los rollups tienen datos incorrectos, podría bloquear tenants legítimos.  
**Mitigación**: Activar primero en modo dry-run (ya está diseñado: cuando enforcement=OFF, loguea pero no actualiza).  
**Rollback**: `ENABLE_QUOTA_ENFORCEMENT=false` en Railway → toma efecto inmediato al next request.

### 3.2 — Decisión: ¿`create_order` hard block o mantener soft cap? (P1)

**Estado actual**: `PlansService.validateAction('create_order')` siempre retorna `allowed: true`.

**Opciones**:
- **A) Mantener soft cap** (recomendado para launch): Solo `console.warn` + métricas. El batch pipeline (HARD_LIMIT) bloquea si el tenant excede >100% en todas las dimensiones.
- **B) Hard block**: Cambiar a `allowed: false` cuando excede `max_monthly_orders`. Riesgo: bloquea checkout de compradores reales.

**Recomendación**: Opción A para launch. El batch HARD_LIMIT es suficiente protección. Agregar `@PlanAction('create_order')` al endpoint de checkout con modo soft (solo log).

### 3.3 — Agregar `@PlanAction()` a endpoints faltantes (P1, ~1h)

**Estado actual**: Solo 4 endpoints tienen `@PlanAction()`:
- `create_product`
- `upload_image`
- `create_banner`
- `create_coupon`

**Faltantes a considerar**:
- **`create_order`**: agregar en modo soft-cap (no bloquear, solo log)
- **`create_service`**: si existe, necesita `@PlanAction('create_product')` o equivalente
- **`update_settings`**: no necesita limit (es 1 por tenant)

**Verificar**: qué endpoints de escritura admin existen y no tienen decorador.

### 3.4 — Verificar QuotaCheckGuard fail-open behavior (P0, ~30min)

**Archivo**: `src/guards/quota-check.guard.ts`

**Estado actual** (verificado):
- Fail-open en caso de error (catch → true) ✅
- Skip para GET/HEAD/OPTIONS ✅
- Skip para `@SkipQuotaCheck()` y `@AllowNoTenant()` ✅
- Bloquea solo en `HARD_LIMIT` ✅

**Verificación**: Confirmar que al activar enforcement, un tenant en ACTIVE no se bloquea. Test manual.

### 3.5 — Hardcoded limits en frontend (P2, ~2h)

**Problema**: Límites duplicados y hardcodeados en:
- `src/onboarding/validators/design.validator.ts` — `PLAN_LIMITS` (colores, imágenes por producto)
- `src/palettes/palettes.service.ts` — `CUSTOM_PALETTE_LIMITS`
- Admin FE: `ManualProductLoader.tsx`, `CatalogLoader.tsx` — `PLAN_LIMITS`
- Web FE: `basicPlanLimits.jsx`, `professionalPlanLimits.jsx`, `premiumPlanLimits.jsx`

**Fix ideal**: Leer de `plans.entitlements` via API endpoint `/plans/:planKey`.  
**Fix pragmático para launch**: Asegurar que los valores hardcodeados coinciden con `plans.entitlements` en DB. Documentar la deuda técnica.

**Riesgo**: Bajo. Es cosmético — el backend enforcement real lee de la DB.

---

## Resumen de prioridades

| ID | Tarea | Prioridad | Esfuerzo | Bloquea launch? |
|----|-------|-----------|----------|-----------------|
| 1.1 | Forzar cluster_shared_01 | P0 | 1h | No, pero simplifica |
| 1.2 | Backfill backend_cluster_id | P0 | 30min | No |
| 2.1 | **Fix UsageConsolidationCron** | **P0** | **2h** | **Sí** (batch pipeline rota) |
| 2.2 | Verificar MetricsInterceptor→ledger | P0 | 1h | Sí (prereq de 2.1) |
| 2.3 | Verificar MetricsCron aggregation | P0 | 30min | Sí (prereq de 2.1) |
| 3.1 | Activar ENABLE_QUOTA_ENFORCEMENT | P0 | 15min | Sí |
| 3.4 | Verificar QuotaCheckGuard fail-open | P0 | 30min | Sí |
| 2.4 | Unificar overage rates | P1 | 1h | No |
| 3.2 | Decisión create_order block | P1 | - | No |
| 3.3 | @PlanAction endpoints faltantes | P1 | 1h | No |
| 1.3 | Guard creación clusters | P1 | 30min | No |
| 3.5 | Hardcoded limits FE | P2 | 2h | No |

**Total P0**: ~5.5h  
**Total P1**: ~2.5h  
**Total P2**: ~2h

---

## Orden de implementación recomendado

```
1) 1.1 + 1.2  (cluster hardening, paralelo)
2) 2.2        (verificar interceptor → ledger fluye)
3) 2.3        (verificar MetricsCron → hourly/daily fluye)
4) 2.1        (fix UsageConsolidationCron → rollups fluyen)
5) 3.4        (verificar QuotaCheckGuard)
6) 3.1        (activar enforcement flag)
7) --- P1 ---
8) 2.4        (unificar rates)
9) 3.3        (@PlanAction endpoints)
10) 1.3       (guard clusters)
11) 3.5       (hardcoded limits FE)
```

---

## Archivos a tocar

### Backend API (`apps/api/`)
| Archivo | Cambio |
|---------|--------|
| `src/db/db-router.service.ts` | 1.1 — Simplificar `chooseBackendCluster()` |
| `src/billing/usage-consolidation.cron.ts` | 2.1 — Fix DB source + columnas |
| `src/metrics/metrics.service.ts` | 2.4 — Unificar rates (P1) |
| `src/guards/quota-check.guard.ts` | 3.4 — Verificar (no cambio) |
| `.env` / Railway | 3.1 — `ENABLE_QUOTA_ENFORCEMENT=true` |

### Migraciones
| Archivo | DB target |
|---------|-----------|
| `migrations/admin/ADMIN_071_backfill_cluster_id.sql` | Admin DB |

### Documentación
| Archivo | Cambio |
|---------|--------|
| `novavision-docs/changes/YYYY-MM-DD-*.md` | Registro de cambios |
| `novavision-docs/plans/MULTI_CLUSTER_FUTURE.md` | Items F2.1-F2.4 como pendientes |

---

## Multi-cluster: items pendientes para futuro

Los siguientes items se documentarán como **PENDIENTE: solo necesario al agregar 2° cluster** en `novavision-docs/plans/MULTI_CLUSTER_FUTURE.md`:

- **F2.1**: Routing migration — `chooseBackendCluster()` con weighted random real
- **F2.2**: Cross-cluster metering — `UsageConsolidationCron` consolidando de múltiples Backend DBs
- **F2.3**: Cluster management — CRUD de clusters + health checks
- **F2.4**: Data migration — mover tenants entre clusters
- **Estimación**: ~34h totales

---

## Riesgos y rollback

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| Consolidation genera datos incorrectos | Media | Alto | Correr en dry-run primero, verificar rollups |
| Enforcement bloquea tenant legítimo | Baja | Alto | Flag OFF inmediato (`ENABLE_QUOTA_ENFORCEMENT=false`) |
| Metering tables en Admin DB no tienen datos | Media | Medio | Verificar con queries antes de activar enforcement |
| Hardcoded limits inconsistentes con DB | Alta | Bajo | Solo cosmético, backend enforcement es correcto |

---

## Definition of Done (por bloque)

### Bloque 1 ✅
- [ ] `chooseBackendCluster()` retorna `'cluster_shared_01'` sin query
- [ ] Todas las `nv_accounts` activas tienen `backend_cluster_id = 'cluster_shared_01'`
- [ ] Build + lint + typecheck pasan

### Bloque 2 ✅
- [ ] `usage_ledger` en Admin DB tiene registros (verificar con query)
- [ ] `usage_daily` en Admin DB tiene registros (verificar con query)
- [ ] `usage_rollups_monthly` en Admin DB tiene datos actuales (verificar con query)
- [ ] `UsageConsolidationCron` ejecuta sin error (verificar en logs)

### Bloque 3 ✅  
- [ ] `ENABLE_QUOTA_ENFORCEMENT=true` en Railway
- [ ] `QuotaEnforcementService` evalúa tenants y loguea estados
- [ ] `QuotaCheckGuard` NO bloquea tenants en ACTIVE
- [ ] `QuotaCheckGuard` bloquea escrituras en HARD_LIMIT (test con estado forzado)

# NovaVision — Auditoría de Metering por Tenant (DB + API + Overage)

**Fecha:** 2026-02-27  
**Autor:** agente-copilot  
**Rama:** `feature/automatic-multiclient-onboarding`  
**Tenant validado:** farma (`nv_accounts.id = f6740bf8-9a6d-495f-ae61-9e61aeeceea9`)

---

## ENTREGABLE A — Reporte: Qué se mide hoy vs Qué NO se puede medir

### Métricas facturables (billable)

| Métrica | Fuente | Pipeline | Destino final | Estado PRE-fix | Estado POST-fix |
|---------|--------|----------|---------------|----------------|-----------------|
| `orders_confirmed` | `mercadopago.service.ts` L2286 emite `order` qty=1 | MetricsInterceptor → usage_ledger → usage_daily → usage_rollups_monthly | `usage_rollups_monthly.orders_confirmed` | ✅ Funciona (emisión agregada sesión anterior) | ✅ |
| `orders_gmv_usd` | Backend `orders.total_amount` + FX conversion | GmvPipelineCron → usage_rollups_monthly | `usage_rollups_monthly.orders_gmv_usd` | ❌ **BUG**: ID mismatch en L108 → siempre $0 | ✅ Corregido |
| `api_calls` | MetricsInterceptor emite `request` qty=1 por request | usage_ledger → usage_daily → usage_rollups_monthly | `usage_rollups_monthly.api_calls` | ✅ Funciona | ✅ |
| `egress_bytes` / `egress_gb` | MetricsInterceptor emite `egress_bytes` (content-length) | usage_ledger → usage_daily → usage_rollups_monthly | `usage_rollups_monthly.egress_gb` | ✅ Funciona | ✅ |
| `storage_gb_avg` | Backend `client_usage.storage_bytes` gauge | UsageConsolidationCron lee gauge → rollups | `usage_rollups_monthly.storage_gb_avg` | ✅ Funciona (gauge = 0 porque no hay assets) | ✅ |

### Métricas internas (no facturables, para dashboards/COGS)

| Métrica | Fuente | Pipeline | Destino | Estado |
|---------|--------|----------|---------|--------|
| `products_count` | Triggers en tabla `products` | Trigger → `client_usage.products_count` | `client_usage` (gauge) | ❌ **BUG**: Triggers duplicados (doble conteo) |
| `banners_count` | Triggers en tabla `banners` | Trigger → `client_usage.banners_count` | `client_usage` (gauge) | ✅ Funciona |
| `storage_bytes` | Triggers en `client_assets` | Trigger → `client_usage.storage_bytes` | `client_usage` (gauge) | ✅ Funciona |
| `client_usage.orders_count` | Trigger en `orders` | Trigger → `client_usage.orders_count` | `client_usage` (gauge) | ✅ Funciona |

### Lo que NO se puede medir hoy

| Dimensión | Por qué no | Impacto | Prioridad |
|-----------|-----------|---------|-----------|
| CPU/IO por tenant | Railway no expone per-process metrics por tenant | No facturable | Baja (no necesaria pre-launch) |
| DB query cost por tenant | Supabase no segmenta costo de query por tenant | No facturable | Baja |
| Bandwidth real (CDN) | No se mide tráfico de assets estáticos (Netlify CDN) | Subestima egress real | Media — evaluar post-launch |
| Email sends por tenant | `email_jobs` existe pero no se cuenta como métrica metering | Podría facturarse en el futuro | Baja |

---

## ENTREGABLE B — Plan de Ajuste Mínimo (sin duplicar tablas/cron)

### Bugs corregidos en esta sesión

| # | Bug | Severidad | Archivo | Fix aplicado |
|---|-----|-----------|---------|--------------|
| BUG-M01 | **GmvPipelineCron ID mismatch** — `gmv-pipeline.cron.ts` L108 usaba `nv_accounts.id` para query `orders.client_id` en Backend DB | CRÍTICO | `src/billing/gmv-pipeline.cron.ts` | Agregado mapping `nv_account_id → clients.id` (mismo patrón que UsageConsolidationCron) |
| BUG-M02 | **Duplicate product triggers** — `tr_product_insert_count` + `trg_products_usage_insert` ambos incrementan `products_count` | ALTO | Backend DB triggers | Migración `BACKEND_050`: drop triggers viejos + recalcular gauge |
| BUG-M03 | **OverageService hardcoded rates** — Tasas en código ($0.015/order) no coincidían con DB `plans` ($0.06/order) | ALTO | `src/billing/overage.service.ts` | Ahora lee `overage_per_order`, `overage_per_gb_egress`, `overage_per_1k_requests` de la tabla `plans` |

### Bugs corregidos en sesión anterior (pendientes de commit)

| # | Bug | Archivo | Fix |
|---|-----|---------|-----|
| BUG-P01 | UsageConsolidationCron leía de DB incorrecta + formato dimensional erróneo + ID mismatch | `src/billing/usage-consolidation.cron.ts` | Reescrito completo con mapping correcto |
| BUG-P02 | Faltaba emisión de métrica `order` en MercadoPago webhook | `src/tenant-payments/mercadopago.service.ts` | Agregado emit `order` qty=1 |
| BUG-P03 | `chooseBackendCluster()` era complejo innecesariamente | `src/db/db-router.service.ts` | Simplificado a return `'cluster_shared_01'` |

### Migraciones pendientes de ejecución

| Migración | DB | Qué hace | Pre-requisito |
|-----------|-----|---------|---------------|
| `ADMIN_071_backfill_cluster_id.sql` | Admin | Setea `backend_cluster_id` en nv_accounts existentes | Ninguno |
| `ADMIN_091_plans_overage_storage_column.sql` | Admin | Agrega `overage_per_gb_storage` a tabla `plans` | Ninguno |
| `BACKEND_050_fix_duplicate_product_triggers.sql` | Backend | Elimina triggers duplicados + recalcula gauge | Ninguno |

### Discrepancia de tasas de overage (ahora corregida)

| Dimensión | Antes (hardcoded) | Ahora (de DB `plans`) | Plan |
|-----------|-------------------|----------------------|------|
| orders | $0.015/order | $0.06/order | growth |
| egress | $0.08/GB | $0.15/GB | growth |
| requests | $0.0002/req | $0.30/1k req → $0.0003/req | growth |
| storage | $0.021/GB (hardcoded) | $0.021/GB (fallback → `overage_per_gb_storage` post-migración) | growth |

---

## ENTREGABLE C — Tests Recomendados

### C.1 — Orders + GMV Pipeline

```typescript
// test: GmvPipelineCron maps nv_accounts.id → Backend clients.id correctly
describe('GmvPipelineCron', () => {
  it('should resolve Backend client_id via nv_account_id mapping', async () => {
    // Setup: nv_accounts.id='AAA', clients.id='BBB', clients.nv_account_id='AAA'
    // orders has client_id='BBB' (NOT 'AAA')
    // Assert: cron queries orders with client_id='BBB'
    // Assert: writes gmvUsd > 0 to usage_rollups_monthly.tenant_id='AAA'
  });

  it('should skip tenants with no Backend client mapping', async () => {
    // Setup: nv_accounts.id='CCC', no corresponding client in Backend
    // Assert: logs "no Backend client mapping found, skipping"
    // Assert: no crash
  });

  it('should convert currency to USD using FxService rates', async () => {
    // Setup: orders with total_amount=10000, currency=ARS, FX rate=1000
    // Assert: gmvUsd ≈ 10.00
  });
});
```

### C.2 — Storage Gauge

```typescript
describe('UsageConsolidationCron - Storage', () => {
  it('should read storage_bytes from Backend client_usage gauge', async () => {
    // Setup: client_usage.storage_bytes = 1073741824 (1 GB)
    // Assert: usage_rollups_monthly.storage_gb_avg = 1.0
  });

  it('should handle 0 storage gracefully', async () => {
    // Setup: client_usage.storage_bytes = 0
    // Assert: usage_rollups_monthly.storage_gb_avg = 0
  });
});
```

### C.3 — API Calls + Egress Pipeline

```typescript
describe('MetricsInterceptor → usage_ledger → rollups', () => {
  it('should accumulate api_calls from usage_daily to usage_rollups_monthly', async () => {
    // Setup: usage_daily has 3 days with api_calls = [100, 200, 150]
    // After consolidation: usage_rollups_monthly.api_calls = 450
  });

  it('should convert egress_bytes from daily to egress_gb in rollups', async () => {
    // Setup: usage_daily.egress_bytes = 2147483648 (2 GB)
    // Assert: usage_rollups_monthly.egress_gb ≈ 2.0
  });
});
```

### C.4 — Enforcement (Quota Check Guard)

```typescript
describe('QuotaCheckGuard', () => {
  it('should allow request when ENABLE_QUOTA_ENFORCEMENT=false (default)', async () => {
    // Assert: guard returns true (fail-open)
  });

  it('should resolve Backend client_id → nv_account_id for quota lookup', async () => {
    // Setup: client.nv_account_id = 'AAA', quota_state.tenant_id = 'AAA', state = 'ACTIVE'
    // Assert: request allowed
  });

  it('should block request when quota state is SUSPENDED and enforcement enabled', async () => {
    // Setup: ENABLE_QUOTA_ENFORCEMENT=true, quota_state.state='SUSPENDED'
    // Assert: ForbiddenException thrown
  });

  it('should allow create_order even when WARNED (soft cap)', async () => {
    // Setup: quota_state.state='WARNED', action='create_order'
    // Assert: request allowed (soft cap)
  });
});
```

### C.5 — Overage Billing

```typescript
describe('OverageService', () => {
  it('should read overage rates from plans table, not hardcoded values', async () => {
    // Setup: plans.overage_per_order = 0.06
    // usage_rollups_monthly.orders_confirmed = 200, plan.included_orders = 100
    // Assert: excess = 100, amount = 100 × 0.06 = $6.00 (not $1.50 from old hardcoded rate)
  });

  it('should convert overage_per_1k_requests to per-request rate', async () => {
    // Setup: plans.overage_per_1k_requests = 0.30
    // usage = 15000, included = 10000 → excess = 5000
    // Assert: amount = 5000 × 0.0003 = $1.50
  });

  it('should use storage fallback rate when DB column is null', async () => {
    // Setup: plans.overage_per_gb_storage = null (column not yet migrated)
    // Assert: uses STORAGE_OVERAGE_RATE_FALLBACK = 0.021
  });

  it('should be idempotent (no duplicate billing_adjustments)', async () => {
    // Run overage calculation twice for same period
    // Assert: only 1 adjustment per dimension per tenant per period
  });

  it('should skip tenants where overage_allowed=false (starter plan)', async () => {
    // Setup: plan_key='starter', overage_allowed=false
    // Assert: no billing_adjustments created, no error
  });
});
```

### C.6 — Products Count Gauge (post-migration)

```typescript
describe('Product triggers (post BACKEND_050)', () => {
  it('should increment products_count by exactly 1 on INSERT', async () => {
    // Setup: client_usage.products_count = 5
    // Action: INSERT 1 product
    // Assert: client_usage.products_count = 6 (not 7)
  });

  it('should decrement products_count by exactly 1 on DELETE', async () => {
    // Setup: client_usage.products_count = 5
    // Action: DELETE 1 product
    // Assert: client_usage.products_count = 4 (not 3)
  });
});
```

---

## ENTREGABLE D — Go-Live Checklist para Billing/Quotas

### Pre-requisitos (antes de activar billing)

- [ ] **Ejecutar migración `ADMIN_071`** — backfill `backend_cluster_id` en nv_accounts
- [ ] **Ejecutar migración `ADMIN_091`** — agregar `overage_per_gb_storage` a tabla `plans`
- [ ] **Ejecutar migración `BACKEND_050`** — eliminar triggers duplicados + recalcular gauge
- [ ] **Deploy con fixes** — GmvPipelineCron, OverageService, UsageConsolidationCron, order metric
- [ ] **Verificar que crons corren** — esperar 24hs y validar:
  - `usage_rollups_monthly` tiene registros (consolidation cron 02:30 UTC)
  - `orders_gmv_usd > 0` si hay órdenes (GmvPipeline 02:45 UTC)
  - `quota_state` tiene registros (enforcement 03:00 UTC)
- [ ] **Verificar gauges** — `client_usage.products_count` = `COUNT(products)` real

### Activación progresiva

| Fase | Acción | Config | Riesgo |
|------|--------|--------|--------|
| 1. Metering silencioso | Deploy fixes, crons corren → llenan `usage_rollups_monthly` | `ENABLE_QUOTA_ENFORCEMENT=false` (default) | Ninguno — solo observa |
| 2. Dry-run enforcement | Activar enforcement en modo warning-only | `ENABLE_QUOTA_ENFORCEMENT=true` | Bajo — solo loguea warnings, no bloquea |
| 3. Enforcement real | Cambiar `plans.enforcement_policy` de `soft` a `hard` en los planes que corresponda | Por plan en DB | Medio — podría bloquear tenants que exceden |
| 4. Billing activo | Dejar correr OverageService (Day 2 cada mes) | Ya activo, solo genera `billing_adjustments` | Bajo — no cobra automáticamente |
| 5. Cobro automático | Activar AutoChargeCron (Day 5 de cada mes) | AutoChargeCron ya schedulado | Alto — genera preferencias de pago reales |

### Validación por dimensión (post-deploy, con datos reales)

| Dimensión | Query de validación | Valor esperado |
|-----------|-------------------|----------------|
| api_calls | `SELECT api_calls FROM usage_rollups_monthly WHERE tenant_id='f6740bf8...' AND period_start='2026-03-01'` | > 0 (proporcional a tráfico real) |
| egress_gb | `SELECT egress_gb FROM usage_rollups_monthly WHERE ...` | > 0 (bytes de responses) |
| orders_confirmed | `SELECT orders_confirmed FROM usage_rollups_monthly WHERE ...` | = COUNT de órdenes pagadas en el mes |
| orders_gmv_usd | `SELECT orders_gmv_usd FROM usage_rollups_monthly WHERE ...` | = SUM(total_amount) / FX_rate |
| storage_gb_avg | `SELECT storage_gb_avg FROM usage_rollups_monthly WHERE ...` | = client_usage.storage_bytes / 1e9 |
| products_count | `SELECT products_count FROM client_usage WHERE client_id='1fad8213...'` | = COUNT(products) exacto |

### Circuit breakers y fail-safes

| Componente | Fail-open? | Feature flag | Override |
|-----------|------------|--------------|---------|
| QuotaCheckGuard | ✅ Sí (L151-161) — si falla query, permite request | `ENABLE_QUOTA_ENFORCEMENT` | Desactivar con `false` |
| OverageService | ✅ Idempotente — no duplica adjustments | Ninguno | No corre si no hay `overage_allowed=true` |
| GmvPipelineCron | ✅ Semaphore `running` — no se superpone | Ninguno | Desactivar removiendo @Cron |
| QuotaEnforcementService | ✅ Semaphore `running` | Mismo que QuotaCheckGuard | Desactivar con `false` |

### Planes y sus límites (referencia)

| Plan | orders | bandwidth GB | requests | storage GB | overage_allowed |
|------|--------|-------------|----------|-----------|----------------|
| starter | 200 | 5 | 50000 | 1 | NO (hard cap) |
| growth | 2000 | 15 | 200000 | 5 | SÍ |
| enterprise | 50000 | 100 | 2000000 | 50 | SÍ |

---

## Pipeline E2E — Diagrama de flujo de datos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│ RUNTIME (cada request HTTP)                                                 │
│                                                                             │
│  Request → MetricsInterceptor (client_id = Backend clients.id)              │
│            ├─ emit 'request', qty=1                                         │
│            └─ emit 'egress_bytes', qty=content-length                       │
│                    ↓                                                        │
│         UsageRecorderService (buffer, flush cada 30s)                       │
│                    ↓                                                        │
│         usage_ledger (Admin DB) ── client_id = Backend clients.id           │
│                                                                             │
│  MercadoPago webhook → emit 'order', qty=1                                  │
│                      → emit 'gmv', qty=total_amount                         │
│                                                                             │
│  Product/Banner CRUD → DB triggers → client_usage gauge (Backend DB)        │
│  Asset upload/delete → DB triggers → client_usage.storage_bytes (Backend)   │
└─────────────────────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ CRON LAYER (diario + mensual)                                               │
│                                                                             │
│  03:15 ART ─ MetricsCron.syncAggregate()                                    │
│               usage_ledger → usage_hourly + usage_daily (Admin DB)          │
│               (client_id = Backend clients.id en ambas tablas)              │
│                                                                             │
│  02:30 UTC ─ UsageConsolidationCron                                         │
│               1. Lee usage_daily (Admin) + client_usage.storage_bytes (BE)  │
│               2. Mapea: clients.nv_account_id → nv_accounts.id              │
│               3. Escribe: usage_rollups_monthly.tenant_id = nv_accounts.id  │
│                                                                             │
│  02:45 UTC ─ GmvPipelineCron (CORREGIDO)                                    │
│               1. Lee nv_accounts (Admin)                                    │
│               2. Mapea: nv_account_id → Backend clients.id                  │
│               3. Lee orders (Backend) con Backend client_id correcto        │
│               4. FX conversion → escribe orders_gmv_usd en rollups (Admin)  │
│                                                                             │
│  03:00 UTC ─ QuotaEnforcementService                                        │
│               Lee usage_rollups_monthly + plans → escribe quota_state       │
│               Todo en Admin DB (tenant_id = nv_accounts.id)                 │
│                                                                             │
│  Day 2 06:00 ─ GmvCommissionCron                                            │
│                 Lee rollups.orders_gmv_usd → billing_adjustments (Admin)    │
│                                                                             │
│  Day 2 06:30 ─ OverageService (CORREGIDO)                                   │
│                 Lee rollups + plans (rates de DB, no hardcoded)              │
│                 → billing_adjustments (Admin)                               │
│                                                                             │
│  Day 3 06:00 ─ CostRollupCron                                               │
│                 Lee rollups → cost_rollups (Admin, COGS interno)            │
│                                                                             │
│  Day 5 08:00 ─ AutoChargeCron                                               │
│                 Lee billing_adjustments → genera preferencias MP             │
└─────────────────────────────────────────────────────────────────────────────┘
                         ↓
┌─────────────────────────────────────────────────────────────────────────────┐
│ ENFORCEMENT (cada request)                                                  │
│                                                                             │
│  Request → QuotaCheckGuard                                                  │
│            1. Lee x-client-id (Backend clients.id)                          │
│            2. Resuelve clients.nv_account_id → nv_accounts.id               │
│            3. Lee quota_state.state (Admin)                                 │
│            4. Si ENABLE_QUOTA_ENFORCEMENT=false → allow (fail-open)         │
│            5. Si SUSPENDED → block (403)                                    │
│            6. Si WARNED + acción soft (create_order) → allow con header     │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Identidad canónica del tenant (validada con evidencia)

| Capa | Archivo + Línea | ID usado | Entidad | 
|------|----------------|----------|---------|
| Interceptor | `metrics.interceptor.ts` L79 | `x-client-id` header | Backend `clients.id` |
| Buffer/Flush | `usage-recorder.service.ts` L139 | Mismo header | Backend `clients.id` |
| Materialización | `metrics.service.ts` L140,148 | client_id de ledger | Backend `clients.id` |
| Consolidación | `usage-consolidation.cron.ts` L122-138 | Mapea via `nv_account_id` | Escribe `nv_accounts.id` |
| GMV Pipeline | `gmv-pipeline.cron.ts` L95-112 **(CORREGIDO)** | Mapea via `nv_account_id` | Lee Backend, escribe Admin |
| Enforcement | `quota-enforcement.service.ts` L130 | `tenant_id` = `nv_accounts.id` | Admin |
| Guard | `quota-check.guard.ts` L151-161 | Resuelve `nv_account_id` | Backend → Admin |
| Overage | `overage.service.ts` L120 | `nv_accounts.id` | Admin |

---

## Evidencia de validación con tenant "farma"

| Dato | Fuente | Valor | Observación |
|------|--------|-------|-------------|
| nv_accounts.id | Admin DB | `f6740bf8-9a6d-495f-ae61-9e61aeeceea9` | ✅ |
| clients.id | Backend DB | `1fad8213-1d2f-46bb-bae2-24ceb4377c8a` | ✅ |
| clients.nv_account_id | Backend DB | `f6740bf8-...` | ✅ FK correcta |
| plan_key | Admin DB | `growth` | ✅ overage_allowed=true |
| orders (real) | Backend DB | 0 | Sin órdenes aún |
| products_count (gauge) | Backend DB | 33 | ❌ Debería ser 11 (BUG-M02) |
| products (real) | Backend DB | 11 | Ground truth |
| storage_bytes | Backend DB | 0 | Sin assets cargados |
| usage_ledger | Admin DB | 245 requests, 690 bytes egress | ✅ Metering funciona |
| usage_daily | Admin DB | 245 requests, 690 bytes (2026-02-27) | ✅ Materialización funciona |
| usage_rollups_monthly | Admin DB | 0 filas | ⚠️ Cron no corrió aún post-fix |
| quota_state | Admin DB | 0 filas | ⚠️ Downstream de rollups vacíos |
| billing_adjustments | Admin DB | 0 filas | ⚠️ Esperado — no hay período cerrado aún |

# Cambio: Overage Accumulation + Debt Management (Option A)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Alcance:** Solo Backend (API)
- **Migration:** ADMIN_092 ejecutada ✅

---

## Resumen

Implementación completa de **Option A: Acumulación de overages en la suscripción de Mercado Pago**. Cuando un cliente excede los límites de su plan (GMV, órdenes, requests, storage, bandwidth), el sistema calcula el excedente, lo convierte a un monto monetario y lo **infla en el precio de la suscripción de MP** del siguiente ciclo. Si el cliente cancela con deuda pendiente, se registra en `cancellation_debt_log` y se requiere pago antes de completar la cancelación.

### Decisión de diseño

Se eligió Option A sobre Option B (cobros separados por MP preference) porque:
- Menos fricción para el cliente (no necesita aprobar pagos adicionales)
- Un solo flujo de pago (la suscripción mensual ya existente)
- Más simple de reconciliar contablemente
- AutoChargeCron queda como fallback (Day 5) si la inflación falla

---

## Archivos Modificados/Creados

### Nuevos (5 archivos)

| Archivo | Líneas | Descripción |
|---------|--------|-------------|
| `src/billing/overage-accumulation.cron.ts` | 58 | Cron Day 3/mes: busca `billing_adjustments` con status `pending` y llama a `BillingService.inflateSubscriptionWithOverages()` para cada tenant |
| `migrations/admin/ADMIN_091_plans_overage_storage_column.sql` | 13 | Agrega `overage_rate_storage` a `plans` |
| `migrations/admin/ADMIN_092_overage_accumulation_and_debt.sql` | 80 | 3 columnas nuevas en `nv_subscriptions` + tabla `cancellation_debt_log` + constraint `billing_unique_period_type` |
| `src/billing/__tests__/billing-overage.service.spec.ts` | 874 | 22 tests unitarios para BillingService (overages, inflación, deuda, rollback) |
| `src/billing/__tests__/overage-accumulation.cron.spec.ts` | 80 | 4 tests unitarios para OverageAccumulationCron |

### Modificados (7 archivos)

| Archivo | Cambio | Descripción |
|---------|--------|-------------|
| `src/billing/billing.service.ts` | +598 líneas | 7 métodos nuevos: `inflateSubscriptionWithOverages()`, `rollbackInflation()`, `resolveAccruingAdjustments()`, `accumulateDebtOnCancel()`, `resolveDebtWithPayment()`, `getClientDebt()`, `getInflationMetadata()` |
| `src/billing/billing.module.ts` | +2 líneas | Registra `OverageAccumulationCron` como provider |
| `src/billing/auto-charge.cron.ts` | +4 líneas | Comentario clarificador: "fallback si la inflación no cubrió" |
| `src/billing/overage.service.ts` | +40 líneas | Adapta cálculo para que overages con plan `accumulate_into_subscription` generen adjustments con status `pending` en vez de `ready` |
| `src/billing/gmv-pipeline.cron.ts` | +45 líneas | Consideraciones de inflación al procesar pipeline GMV |
| `src/billing/usage-consolidation.cron.ts` | +194/-73 líneas | Refactor para soportar acumulación de overages; lógica de rollup mensual adaptada |
| `src/subscriptions/subscriptions.service.ts` | +197 líneas | 4 modificaciones: (1) `requestCancel` guarda deuda pendiente, (2) `checkAndUpdatePrices` salta suscripciones infladas, (3) `handlePaymentSuccess` resuelve adjustments `accruing`, (4) `markCancelScheduled` maneja deuda |

---

## Cambios en Base de Datos

### Migration ADMIN_092 (ejecutada ✅)

```sql
-- 3 columnas nuevas en nv_subscriptions
ALTER TABLE nv_subscriptions
  ADD COLUMN IF NOT EXISTS pending_debt numeric(12,2) DEFAULT 0,
  ADD COLUMN IF NOT EXISTS original_amount numeric(12,2),
  ADD COLUMN IF NOT EXISTS inflated_until timestamptz;

-- Tabla de deuda por cancelación
CREATE TABLE IF NOT EXISTS cancellation_debt_log (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id uuid NOT NULL REFERENCES nv_accounts(id),
  subscription_id uuid REFERENCES nv_subscriptions(id),
  amount numeric(12,2) NOT NULL,
  currency char(3) NOT NULL DEFAULT 'ARS',
  reason text NOT NULL DEFAULT 'overages_at_cancellation',
  status text NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending','paid','waived','written_off')),
  created_at timestamptz DEFAULT now(),
  resolved_at timestamptz,
  resolved_by text,
  mp_payment_id text,
  notes text
);

-- Constraint de unicidad para billing_adjustments
ALTER TABLE billing_adjustments
  ADD CONSTRAINT billing_unique_period_type
  UNIQUE (account_id, period, type);
```

### Migration ADMIN_091 (ejecutada ✅)

```sql
ALTER TABLE plans ADD COLUMN IF NOT EXISTS overage_rate_storage numeric(10,4) DEFAULT 0;
```

---

## Cambios en API Contract

### `POST /subscriptions/:id/cancel` (requestCancel)

**Antes:** Retornaba siempre `{ status: 'cancelled' | 'cancel_scheduled', ... }`

**Ahora:** Puede retornar un nuevo status cuando hay deuda pendiente:

```json
{
  "status": "cancel_pending_payment",
  "message": "Hay overages pendientes de $X. Se requiere pago antes de cancelar.",
  "debt": {
    "amount": 1500.00,
    "currency": "ARS",
    "debt_id": "uuid",
    "payment_url": "https://..."
  }
}
```

---

## Cronograma de Crons (completo actualizado)

| Cron | Horario | Servicio | Propósito |
|------|---------|----------|-----------|
| MetricsCron | 03:15 ART diario | MetricsCron | `syncAggregate(48h)` |
| UsageConsolidationCron | 02:30 UTC diario | UsageConsolidationCron | daily→monthly rollups |
| GmvPipelineCron | 02:45 UTC diario | GmvPipelineCron | orders→orders_gmv_usd |
| QuotaEnforcementService | 03:00 UTC diario | QuotaEnforcementService | evaluar estados de cuota |
| checkAndUpdatePrices | 02:00 UTC diario | SubscriptionsService | actualizar precios MP por FX (salta infladas) |
| GmvCommissionCron | 06:00 UTC día 2/mes | GmvCommissionCron | comisiones GMV |
| OverageService | 06:30 UTC día 2/mes | OverageService | calcular overages → `billing_adjustments` |
| **OverageAccumulationCron** | **07:00 UTC día 3/mes** | **OverageAccumulationCron** | **Inflar monto de suscripción MP con overages** |
| AutoChargeCron | 08:00 UTC día 5/mes | AutoChargeCron | fallback: cobros separados por MP preference |

---

## Tests

### 26 tests en 2 suites — todos pasando ✅

**billing-overage.service.spec.ts** (22 tests):
- `inflateSubscriptionWithOverages`: 8 tests (happy path, sin adjustments, sin suscripción, error MP, rollback, idempotencia, multi-type)
- `rollbackInflation`: 3 tests (happy path, sin original_amount, error MP)
- `resolveAccruingAdjustments`: 3 tests (happy path, sin adjustments, partial)
- `accumulateDebtOnCancel`: 3 tests (happy path, sin pending, ya existente)
- `resolveDebtWithPayment`: 3 tests (happy path, no debt found, ya resuelta)
- `getClientDebt`: 2 tests (con deuda, sin deuda)

**overage-accumulation.cron.spec.ts** (4 tests):
- Procesar accounts con adjustments pending
- Skippear si no hay pending
- Continuar con siguiente account si uno falla
- No ejecutar fuera del día 3

---

## Validación de Build

| App | Lint | TypeCheck | Build |
|-----|------|-----------|-------|
| API | ✅ 0 errores (1291 warnings) | ✅ clean | ✅ exitoso |
| Admin | ✅ 0 errores, 0 warnings | — | — |
| Web | ✅ 0 errores (39 warnings pre-existentes) | — | — |

---

## Gaps Identificados en Admin UI (trabajo futuro)

### 🔴 Críticos (P0)

| # | Gap | Componente | Descripción |
|---|-----|-----------|-------------|
| GAP-1 | `cancellation_debt_log` invisible | — (no existe) | La tabla `cancellation_debt_log` no tiene NINGUNA representación en el admin. Super admin no puede ver, gestionar ni resolver deudas de cancelación. |
| GAP-2 | Inflación invisible | `SubscriptionDetailView.jsx` | No muestra `pending_debt`, `original_amount`, `inflated_until` ni metadata de inflación. El super admin no sabe si una suscripción tiene el precio inflado por overages. |
| GAP-4 | Cancelaciones sin deuda | `CancellationsView.jsx` | Zero referencias a deuda. Cuando un cliente cancela con deuda pendiente, la vista no lo muestra. |

### 🟡 Altos (P1)

| # | Gap | Componente | Descripción |
|---|-----|-----------|-------------|
| GAP-3 | Status `accruing` faltante | `GmvCommissionsView.jsx` (L165-169) | El dropdown de filtro no incluye `accruing` como opción. `StatusBadge` (L18) no tiene color mapping para este status. Faltan types `overage_requests` y `overage_storage` en el filtro de tipo (L171-174). |
| GAP-5 | Deuda en ClientDetails | `ClientDetails/index.jsx` (L1218-1221) | No hay sección de deuda por cancelación. `accruing` no tiene color mapping en los status badges. |
| GAP-6 | BillingPage sin overages | `BillingPage.tsx` (client-facing) | Los clientes no pueden ver sus overages acumulados ni deuda pendiente. |

### 🟢 Medio (P2)

| # | Gap | Componente | Descripción |
|---|-----|-----------|-------------|
| GAP-7 | Evento no rastreado | — | El evento `cancellation_debt_resolved` del lifecycle no se muestra en ninguna timeline UI. |

---

## Riesgo en Web Storefront

### 🔴 HIGH: SubscriptionManagement.jsx (cancel handler)

**Archivo:** `src/components/admin/SubscriptionManagement.jsx` (L733-759)
**Problema:** El handler de cancelación llama al endpoint `requestCancel` pero NO maneja el nuevo status `cancel_pending_payment`. Cuando el backend retorna este status (indicando que hay deuda pendiente), el frontend muestra "Cancelada correctamente" de forma incorrecta.

**Impacto:** El tenant admin ve un mensaje de éxito cuando en realidad la cancelación está bloqueada por deuda.

**Fix requerido:** Agregar branch para `cancel_pending_payment` que muestre la deuda y el link de pago.

### ✅ Flujo de comprador: NO afectado

El checkout, pagos, carrito y órdenes del comprador final son completamente independientes del sistema de billing/overages. No hay riesgo para el flujo de compra.

---

## Flujo Completo (Option A)

```
Día 1/mes: Cierre de período anterior
  └→ UsageConsolidationCron (02:30 UTC): rollup daily→monthly

Día 2/mes: Cálculo de overages
  ├→ GmvCommissionCron (06:00 UTC): comisiones GMV
  └→ OverageService (06:30 UTC): calcula excedentes
      └→ Genera billing_adjustments con status='pending'

Día 3/mes: Inflación de suscripción ★ NUEVO
  └→ OverageAccumulationCron (07:00 UTC)
      ├→ Busca adjustments con status='pending'
      ├→ Suma total de overages del período
      ├→ Guarda original_amount en nv_subscriptions
      ├→ Llama MP API update preapproval_plan
      ├→ Marca adjustments como status='accruing'
      └→ Setea inflated_until = fin del ciclo

Día 5/mes: Fallback
  └→ AutoChargeCron (08:00 UTC)
      └→ Si quedan adjustments sin resolver → cobro separado

Pago mensual recibido (webhook MP):
  └→ handlePaymentSuccess()
      ├→ Detecta que suscripción está inflada
      ├→ Resuelve adjustments 'accruing' → 'charged'
      ├→ Restaura precio original en MP
      └→ Limpia inflated_until

Cancelación con deuda:
  └→ requestCancel()
      ├→ Calcula overages pendientes
      ├→ Crea registro en cancellation_debt_log
      ├→ Retorna status='cancel_pending_payment'
      └→ Requiere pago de deuda antes de completar cancelación
```

---

## Notas de Seguridad

- Las operaciones de inflación/rollback usan `SERVICE_ROLE_KEY` (server-side only)
- Todos los montos se calculan en backend (nunca confiamos en el frontend)
- La deuda por cancelación se registra en `cancellation_debt_log` con audit trail completo
- `resolved_by` trackea quién resolvió la deuda (usuario, admin, sistema)
- El constraint `billing_unique_period_type` previene duplicación de adjustments

---

## Cómo Probar

### Backend (terminal back)

```bash
cd apps/api

# Tests unitarios
npx jest src/billing/__tests__/billing-overage.service.spec.ts --verbose
npx jest src/billing/__tests__/overage-accumulation.cron.spec.ts --verbose

# Lint + TypeCheck + Build
npm run lint
npm run typecheck
npm run build
```

### Verificar tablas post-migración

```sql
-- Admin DB: Verificar columnas nuevas en nv_subscriptions
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name = 'nv_subscriptions'
AND column_name IN ('pending_debt', 'original_amount', 'inflated_until');

-- Admin DB: Verificar tabla cancellation_debt_log
SELECT column_name, data_type
FROM information_schema.columns
WHERE table_name = 'cancellation_debt_log'
ORDER BY ordinal_position;

-- Admin DB: Verificar constraint
SELECT constraint_name
FROM information_schema.table_constraints
WHERE table_name = 'billing_adjustments'
AND constraint_type = 'UNIQUE';
```

---

## Trabajo Pendiente (Backlog)

### P0 — Críticos antes de producción
1. Fix `SubscriptionManagement.jsx` para manejar `cancel_pending_payment`
2. UI admin para `cancellation_debt_log` (CRUD + resolución)
3. Mostrar inflación en `SubscriptionDetailView`
4. Mostrar deuda en `CancellationsView`

### P1 — Importantes
5. Agregar `accruing` al filtro de `GmvCommissionsView`
6. Sección de deuda en `ClientDetails`
7. BillingPage (client-facing) con overages visibles
8. Dashboard card: total deudas pendientes

### P2 — Nice-to-have  
9. Timeline event para `cancellation_debt_resolved`
10. PlansView: mostrar columnas `included_requests` e `included_storage_gb`
11. QuotasView: mostrar requests y storage usage/limits

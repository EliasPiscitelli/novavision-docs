# Plan: Visibilidad por País + Expansión de Tests E2E

- **Autor:** agente-copilot
- **Fecha:** 2026-02-24
- **Estado:** PLAN — No ejecutar sin aprobación del TL
- **Rama target:** `feature/automatic-multiclient-onboarding` (API + Admin)
- **Refs cruzadas:**
  - [PLAN_ONBOARDING_DINAMICO_MULTILATAM.md](PLAN_ONBOARDING_DINAMICO_MULTILATAM.md)
  - [LATAM_INTERNATIONALIZATION_PLAN.md](../architecture/LATAM_INTERNATIONALIZATION_PLAN.md)
  - [PLAN_MAESTRO_IMPLEMENTACION.md](../architecture/PLAN_MAESTRO_IMPLEMENTACION.md)
  - [PLAN-IMPLEMENTACION-PRE-LANZAMIENTO.md](../implementations/PLAN-IMPLEMENTACION-PRE-LANZAMIENTO.md)
  - [FUTURE_IMPROVEMENTS.md](../improvements/FUTURE_IMPROVEMENTS.md)

---

## Índice

1. [Diagnóstico: ¿Qué existe y qué falta?](#1-diagnóstico-qué-existe-y-qué-falta)
2. [Fase 1 — Filtro Global por País en Super Admin](#2-fase-1--filtro-global-por-país-en-super-admin)
3. [Fase 2 — Métricas y Aggregates por País](#3-fase-2--métricas-y-aggregates-por-país)
4. [Fase 3 — Tests E2E: Cubrir Gaps Críticos](#4-fase-3--tests-e2e-cubrir-gaps-críticos)
5. [Fase 4 — Tests E2E: Multi-País](#5-fase-4--tests-e2e-multi-país)
6. [Fase 5 — Flujos Faltantes y Hardening](#6-fase-5--flujos-faltantes-y-hardening)
7. [Matriz de Riesgos](#7-matriz-de-riesgos)
8. [Cronograma Estimado](#8-cronograma-estimado)
9. [Pendientes / Preguntas para TL](#9-pendientes--preguntas-para-tl)

---

## 1. Diagnóstico: ¿Qué existe y qué falta?

### 1.1 Infraestructura de país — EXISTE

| Componente | Estado | Ubicación |
|-----------|--------|-----------|
| Tabla `country_configs` (7 países, solo AR activo) | ✅ | ADMIN_064 + ADMIN_080 + ADMIN_086 |
| `CountryContextService` (cache 30min) | ✅ | `src/common/country-context.service.ts` |
| Vista CRUD `CountryConfigsView.jsx` | ✅ | Admin Dashboard |
| `nv_accounts.country` + `nv_accounts.currency` + `nv_accounts.mp_site_id` | ✅ | ADMIN_085 backfill |
| `subscriptions.country_id` + `subscriptions.currency` | ✅ | ADMIN_085 backfill |
| `fee_schedules.country_id` | ✅ | ADMIN_073 |
| `fx_rates_config` por country_id (6 países) | ✅ | ADMIN_065 |
| Fiscal ID Validator por país | ✅ | `fiscal-id-validator.service.ts` |

### 1.2 Visibilidad por país en Super Admin — NO EXISTE

| Lo que falta | Impacto | Esfuerzo |
|-------------|---------|----------|
| Filtro global "País" en navbar/header del dashboard | 🔴 CRÍTICO | Medio |
| `?country=XX` en endpoints: quotas, adjustments, accounts, usage, subscriptions | 🔴 CRÍTICO | Medio |
| `nv_accounts.country` NO se incluye en SELECTs de admin controllers | 🟠 ALTO | Bajo |
| Métricas/KPIs desglosadas por país (DashboardHome) | 🟠 ALTO | Alto |
| `quota_state`, `billing_adjustments`, `usage_rollups_monthly` sin columna `country_id` | 🟡 MEDIO | Bajo (JOIN vs denormalize) |
| Gráficos por país (revenue, usuarios, órdenes) | 🟡 MEDIO | Alto |
| Billing crons sin country-awareness | 🟡 MEDIO | Medio |

### 1.3 Tests E2E — Gap Analysis

| Flujo | Suites existentes | Gap |
|-------|------------------|-----|
| Onboarding builder | 02, qa-01 | ✅ Cubierto |
| Auth | 05, qa-03, qa-v2/02 | ✅ Cubierto |
| Catálogo | 06, qa-02, qa-v2/01 | ✅ Cubierto |
| Cart + Checkout | 07, 08, qa-04 | ✅ Cubierto |
| Multi-tenant isolation | 10, qa-05, qa-v2/09 | ✅ Cubierto |
| Subscription cancel/revert | qa-11 | ✅ Cubierto |
| **Support Tickets (tenant)** | — | ❌ 0 tests |
| **Support Console (super admin)** | — | ❌ 0 tests |
| **Email Jobs** | — | ❌ 0 tests |
| **Store pause/resume** | — | ❌ 0 tests |
| **Plan upgrade** | — | ❌ 0 tests |
| **Approval flow vía API** | Suite 03 (vía DB patch) | ⚠️ Bloqueado por bug auth |
| **Super Admin dashboard views** | qa-v2/08 (solo login+nav) | ⚠️ Sin validación de datos |
| **Onboarding multi-país** | — | ❌ 0 tests |
| **Pagos multi-país** | — | ❌ 0 tests |
| **Billing/Finance admin** | — | ❌ 0 tests |
| **MP OAuth** | — | ❌ 0 tests |
| **Custom domain** | — | ❌ 0 tests |
| **wa-inbox** | — | ❌ No implementado |

---

## 2. Fase 1 — Filtro Global por País en Super Admin

**Objetivo:** El super admin puede filtrar TODAS las vistas del dashboard por país.
**Esfuerzo estimado:** 3-4 días (BE + FE)
**Dependencia:** Ninguna

### 2.1 Backend — Agregar `country` a SELECTs y soportar `?country=`

#### 2.1.1 Modificar admin controllers para incluir `country` en JOINs

**Archivos a tocar:**

| Controller | Cambio |
|-----------|--------|
| `admin-quotas.controller.ts` | JOIN `nv_accounts` → agregar `country` al select. Nuevo query param `?country=` que filtra via `.eq('nv_accounts.country', country)` |
| `admin-adjustments.controller.ts` | JOIN `nv_accounts` → agregar `country` al select. Nuevo query param `?country=` |
| `admin-accounts.controller.ts` | Si tiene listado → agregar `?country=`. Si no, crear `GET /admin/accounts` con filtro |
| `admin-renewals.controller.ts` | JOIN con `nv_accounts.country` → filtro `?country=` |
| Admin endpoint de subscriptions | Agregar `?country=` filter |

**Ejemplo de diff (quotas):**
```typescript
// ANTES:
.select(`tenant_id, state, grace_until, last_evaluated_at, updated_at,
         nv_accounts!inner(business_name, slug, plan_key, status)`)

// DESPUÉS:
.select(`tenant_id, state, grace_until, last_evaluated_at, updated_at,
         nv_accounts!inner(business_name, slug, plan_key, status, country)`)
// + si query.country:
.eq('nv_accounts.country', query.country)
```

#### 2.1.2 Nuevo endpoint: `GET /admin/dashboard-meta`

Retorna datos para el selector de país:
```json
{
  "countries": [
    { "country_id": "AR", "country_name": "Argentina", "active": true, "tenant_count": 12 },
    { "country_id": "CL", "country_name": "Chile", "active": true, "tenant_count": 3 }
  ],
  "total_tenants": 15
}
```

Query:
```sql
SELECT na.country, cc.country_name, cc.active, COUNT(*) as tenant_count
FROM nv_accounts na
LEFT JOIN country_configs cc ON cc.country_id = na.country
GROUP BY na.country, cc.country_name, cc.active
ORDER BY tenant_count DESC;
```

### 2.2 Frontend — CountryFilterContext + selector global

#### 2.2.1 Nuevo context: `CountryFilterContext`

```jsx
// src/context/CountryFilterContext.jsx
const CountryFilterContext = createContext({
  selectedCountry: null, // null = todos
  setSelectedCountry: () => {},
  countries: [],
});
```

- Se carga al montar `AdminDashboard` via `GET /admin/dashboard-meta`
- Persiste en `localStorage` para no perder al navegar
- Exponerse via `useCountryFilter()` hook

#### 2.2.2 Selector en AdminDashboard header/toolbar

- Dropdown simple: "Todos los países" | "🇦🇷 Argentina (12)" | "🇨🇱 Chile (3)" | ...
- Se muestra en la barra superior junto al theme toggle
- Al cambiar, todos los componentes hijos re-fetching con `?country=XX`

#### 2.2.3 Conectar vistas existentes

Cada vista que hace fetch a endpoints admin debe:
1. Leer `selectedCountry` del context
2. Agregar `?country=${selectedCountry}` al request (si no es null)
3. Mostrar badge/chip indicando filtro activo

**Vistas a conectar (por prioridad):**

| Vista | Prioridad | Complejidad |
|-------|-----------|-------------|
| `QuotasView.jsx` | P0 | Baja — ya tiene filtro de state, agregar country |
| `GmvCommissionsView.jsx` | P0 | Baja — ya tiene filtros |
| `ClientsView.jsx` | P0 | Media — es la vista principal de clientes |
| `DashboardHome.jsx` | P0 | Alta — métricas agregadas necesitan adaptarse |
| `SubscriptionEventsView.jsx` | P1 | Baja |
| `RenewalCenterView.jsx` | P1 | Baja |
| `BillingView.jsx` | P1 | Baja |
| `UsageView.jsx` | P1 | Baja |
| `ClientsUsageView.jsx` | P1 | Baja |
| `FinanceView.jsx` | P2 | Media |
| `MetricsView.jsx` | P2 | Alta (gráficos) |
| `EmailsJobsView.jsx` | P2 | Media |
| `SupportConsoleView.jsx` | P2 | Media |
| `LeadsView.jsx` | P3 | Baja |

### 2.3 Tests propuestos (Fase 1)

```
tests/qa-v2/19-country-filter.spec.ts
```

- Super admin login
- Verificar selector de país visible
- Filtrar por "AR" → tabla muestra solo tenants AR
- Filtrar por "Todos" → muestra todos
- Verificar que el filtro persiste entre vistas
- Verificar que la URL refleja `?country=XX`

---

## 3. Fase 2 — Métricas y Aggregates por País

**Objetivo:** DashboardHome muestra KPIs con breakdown por país.
**Esfuerzo estimado:** 3-5 días (BE + FE)
**Dependencia:** Fase 1 (filtro global)

### 3.1 Backend — Nuevos endpoints de métricas

#### 3.1.1 `GET /admin/metrics/by-country`

```json
{
  "period": "2026-02",
  "countries": [
    {
      "country_id": "AR",
      "country_name": "Argentina",
      "tenants_active": 10,
      "tenants_trial": 2,
      "tenants_suspended": 1,
      "subscriptions_active": 10,
      "subscriptions_cancel_scheduled": 1,
      "mrr_usd": 480.00,
      "gmv_usd": 15200.00,
      "orders_count": 342,
      "revenue_commission_usd": 76.00,
      "usage_api_calls": 45000,
      "usage_storage_gb": 12.5
    },
    {
      "country_id": "CL",
      "country_name": "Chile",
      // ...
    }
  ],
  "totals": {
    // suma de todos los países
  }
}
```

**Queries necesarias:**

```sql
-- Tenants por país y estado
SELECT na.country, na.status, COUNT(*) as count
FROM nv_accounts na
GROUP BY na.country, na.status;

-- Subscriptions por país y estado
SELECT na.country, s.status, COUNT(*) as count
FROM subscriptions s
JOIN nv_accounts na ON na.id = s.account_id
GROUP BY na.country, s.status;

-- MRR por país (suma de subscriptions activas)
SELECT na.country, SUM(p.price_usd) as mrr_usd
FROM subscriptions s
JOIN nv_accounts na ON na.id = s.account_id
JOIN plans p ON p.plan_key = s.plan_key
WHERE s.status IN ('active', 'cancel_scheduled')
GROUP BY na.country;

-- GMV + Órdenes por país (del mes actual, via usage_rollups o billing_adjustments)
SELECT na.country, 
       SUM(ur.orders_confirmed) as orders,
       SUM(ba.amount_usd) as commission_usd
FROM usage_rollups_monthly ur
JOIN nv_accounts na ON na.id = ur.tenant_id
LEFT JOIN billing_adjustments ba ON ba.tenant_id = ur.tenant_id 
  AND ba.period_start = ur.period_start AND ba.type = 'gmv_commission'
WHERE ur.period_start = date_trunc('month', now())
GROUP BY na.country;
```

#### 3.1.2 `GET /admin/metrics/trends?country=&months=6`

Devuelve series temporales por país para gráficos:
- MRR mensual
- Tenants activos mensual
- GMV mensual
- Churn mensual (cancel_scheduled o deactivated)

### 3.2 Frontend — Dashboard con breakdown por país

#### 3.2.1 `DashboardHome.jsx` — KPI cards con filtro

Si `selectedCountry === null` → mostrar cards globales + mini-tabla por país.
Si `selectedCountry === 'AR'` → mostrar cards solo de AR.

**KPI Cards propuestas:**

| Card | Dato | Acción |
|------|------|--------|
| Tenants Activos | count por estado | Click → ClientsView |
| MRR | suma USD | Click → BillingView |
| Órdenes del mes | count | Click → UsageView |
| GMV del mes | USD | Click → GmvCommissionsView |
| Suscripciones | breakdown por status | Click → SubscriptionEventsView |
| Tickets abiertos | count | Click → SupportConsoleView |

#### 3.2.2 Gráfico: "Distribución por País" (donut/bar)

- Muestra proporción de tenants por país
- Al hover: detalle de MRR, órdenes, GMV
- Usa datos de `GET /admin/metrics/by-country`

#### 3.2.3 Gráfico: "Tendencia MRR" (line chart por país)

- X: meses, Y: MRR USD
- Una línea por país activo
- Usa datos de `GET /admin/metrics/trends`

### 3.3 Tests propuestos (Fase 2)

```
tests/qa-v2/20-admin-metrics-country.spec.ts
```

- Verificar que DashboardHome renderiza KPI cards
- Verificar breakdown por país visible
- Filtrar por país → KPIs se actualizan
- Verificar que montos son > 0 (no vacíos)

---

## 4. Fase 3 — Tests E2E: Cubrir Gaps Críticos

**Objetivo:** Agregar E2E tests para los flujos de negocio que hoy tienen 0 cobertura.
**Esfuerzo estimado:** 5-7 días
**Dependencia:** Ninguna (puede ejecutarse en paralelo con Fases 1-2)

### 4.1 Support Tickets — `tests/qa-v2/21-support-tickets.spec.ts`

**Flujo a testear:**

```
Tenant admin creates ticket → super admin sees it → super admin replies →
tenant sees reply → tenant closes ticket → super admin verifies closed
```

**Checks:**

| # | Test | Endpoint |
|---|------|----------|
| 1 | Admin tenant crea ticket | `POST /client-dashboard/support/tickets` |
| 2 | Admin tenant lista sus tickets | `GET /client-dashboard/support/tickets` |
| 3 | Super admin ve ticket cross-tenant | `GET /admin/support/tickets` |
| 4 | Super admin asigna agente | `PATCH /admin/support/tickets/:id/assign` |
| 5 | Super admin responde | `POST /admin/support/tickets/:id/messages` |
| 6 | Tenant ve respuesta | `GET /client-dashboard/support/tickets/:id/messages` |
| 7 | Tenant cierra ticket | `PATCH /client-dashboard/support/tickets/:id/close` |
| 8 | Super admin ve métricas | `GET /admin/support/metrics` |
| 9 | Cross-tenant: admin B no ve ticket de A | `GET /client-dashboard/support/tickets` con otro tenant |
| 10 | Plan gating: starter con límite de tickets | Verificar `PlanFeature('support.tickets')` |

### 4.2 Email Jobs — `tests/qa-v2/22-email-jobs.spec.ts`

**Flujo a testear:**

```
Action triggers email job → job appears in email_jobs → worker processes →
super admin can see job status in EmailsJobsView
```

**Checks:**

| # | Test | Método |
|---|------|--------|
| 1 | Crear ticket genera email_job | Via DB check post-ticket-creation |
| 2 | Email job tiene campos correctos | `to, subject, template, status, created_at` |
| 3 | Worker procesa job (status → sent/failed) | Poll DB status |
| 4 | Super admin ve jobs en lista | `GET /admin/email-jobs` (si existe) o DB query |
| 5 | Retry de job failed | Verificar backoff exponencial |

### 4.3 Store Pause/Resume — `tests/qa-v2/23-store-pause-resume.spec.ts`

**Flujo completo:**

```
Owner pauses store → storefront returns 503 → owner resumes → storefront works
```

**Checks:**

| # | Test | Endpoint |
|---|------|----------|
| 1 | Owner pausa tienda | `POST /subscriptions/manage/pause-store` |
| 2 | Storefront retorna 503 "maintenance" | `GET /storefront/:slug` → 503 |
| 3 | API del tenant retorna 503 | `GET /api/products?tenant=slug` → 503 |
| 4 | Owner reanuda tienda | `POST /subscriptions/manage/resume-store` |
| 5 | Storefront funciona de nuevo | `GET /storefront/:slug` → 200 |
| 6 | Super admin puede pausar | `POST /admin/clients/:id/pause` |
| 7 | Historial de pausa registrado | Verificar log/evento |

### 4.4 Plan Upgrade — `tests/qa-v2/24-plan-upgrade.spec.ts`

**Flujo:**

```
Tenant on Starter → requests upgrade to Growth → verify entitlements change
```

**Checks:**

| # | Test | Endpoint |
|---|------|----------|
| 1 | Owner ve planes disponibles | `GET /subscriptions/manage/plans` |
| 2 | Solo planes superiores disponibles | No se puede "downgrade" |
| 3 | Owner inicia upgrade | `POST /subscriptions/manage/upgrade` |
| 4 | Suscripción cambia de plan | Verificar `subscriptions.plan_key` |
| 5 | Entitlements se actualizan | Verificar `account_entitlements` |
| 6 | Feature gates reflejan nuevo plan | Endpoint gated → ahora permitido |

### 4.5 Approval Flow — `tests/qa-v2/25-approval-flow.spec.ts`

> ⚠️ **Pre-requisito:** Corregir bug AUTH en `POST /onboarding/approve/:accountId` (auth middleware excluye `/onboarding/*`)

**Flujo:**

```
Onboarding submitted → super admin reviews → approve/request-changes/reject
```

**Checks:**

| # | Test | Endpoint |
|---|------|----------|
| 1 | Cuenta submitted aparece en pendientes | `GET /admin/pending-approvals` |
| 2 | Super admin ve detalle | `GET /admin/pending-approvals/:id` |
| 3 | Request changes (ida y vuelta) | `POST /admin/clients/:id/request-changes` |
| 4 | Cuenta vuelve a "pending" post-changes | Verificar status |
| 5 | Approve happy path | `POST /admin/clients/:id/approve` |
| 6 | Post-approve: status = approved | Verificar `nv_accounts.status` |
| 7 | Reject final | `POST /admin/clients/:id/reject-final` |
| 8 | Post-reject: status = rejected | Verificar `nv_accounts.status` |
| 9 | Email de notificación creado | Verificar `email_jobs` |

### 4.6 Super Admin Financial Views — `tests/qa-v2/26-admin-financial-views.spec.ts`

**Verifica que las vistas financieras renderizan datos correctos:**

| # | Test | Vista |
|---|------|-------|
| 1 | QuotasView carga tabla | Verificar filas, badges de estado, business_name |
| 2 | GmvCommissionsView carga | Verificar columnas type, status, business_name |
| 3 | FeeSchedulesView carga | Verificar country_id, currency, lines expandibles |
| 4 | FxRatesView carga | Verificar 6 países, source, rates |
| 5 | BillingView carga | Verificar datos de facturación |
| 6 | RenewalCenterView carga | Verificar centro de renovaciones |
| 7 | Dark theme en todas las vistas | Toggle dark → verificar no hay texto ilegible |

### 4.7 Subscription Lifecycle Extendido — `tests/qa-v2/27-subscription-lifecycle-extended.spec.ts`

Extiende qa-11 con:

| # | Test | Lo que cubre |
|---|------|-------------|
| 1 | Coupon validation en sub | `POST /client/manage/validate-coupon` |
| 2 | Grace period behavior | Verificar acceso durante grace |
| 3 | Suspend → reactivate flow | Post-grace: suspended → pago → active |
| 4 | Deactivate → purge timeline | TTL cleanup |

---

## 5. Fase 4 — Tests E2E: Multi-País

**Objetivo:** Validar que el sistema funciona para tenants de diferentes países.
**Esfuerzo estimado:** 4-5 días
**Dependencia:** Fase 1 (filtro por país) + PLAN_ONBOARDING_DINAMICO_MULTILATAM completado

### 5.1 Pre-requisitos de implementación

Antes de poder testear multi-país, necesitan estar implementados:

| Requisito | Doc de referencia | Estado actual |
|-----------|------------------|---------------|
| `Step8ClientData.tsx` dinámico por país | PLAN_ONBOARDING_DINAMICO_MULTILATAM §3 | ❌ Hardcodeado AR |
| `PlatformMercadoPagoService` multi-moneda | PLAN_ONBOARDING_DINAMICO_MULTILATAM §5 | ❌ Solo MLA+ARS |
| Validaciones fiscales por país en onboarding | PLAN_ONBOARDING_DINAMICO_MULTILATAM §4 | ❌ Solo CUIT 11 dígitos |
| Subdivisiones por país (tablas) | PLAN_ONBOARDING_DINAMICO_MULTILATAM §2 | ❌ No existen |
| `country_configs` activados (CL, MX como mínimo) | ADMIN_086 (solo AR activo) | ⚠️ Seed existe, toggle off |

### 5.2 Tests propuestos

#### 5.2.1 `tests/qa-v2/28-onboarding-multi-country.spec.ts`

| # | Test | País | Valida |
|---|------|------|--------|
| 1 | Onboarding AR (baseline) | AR | CUIT, provincias, ARS |
| 2 | Onboarding CL | CL | RUT, regiones, CLP |
| 3 | Onboarding MX | MX | RFC, estados, MXN |
| 4 | País inactivo rechazado | PE (si inactive) | Error graceful |
| 5 | Fiscal ID validation | AR→CUIT, CL→RUT, MX→RFC | Regex + dígito verificador |
| 6 | Plan pricing en moneda local | CL | Precios en CLP con FX rate |

#### 5.2.2 `tests/qa-v2/29-payments-multi-country.spec.ts`

| # | Test | País | Valida |
|---|------|------|--------|
| 1 | Checkout AR (ARS) | AR | `currency_id: 'ARS'` en preferencia MP |
| 2 | Checkout CL (CLP) | CL | `currency_id: 'CLP'` en preferencia MP |
| 3 | Checkout MX (MXN) | MX | `currency_id: 'MXN'` en preferencia MP |
| 4 | Webhook con moneda correcta | CL | Webhook confirma orden en CLP |
| 5 | FX rate usado para billing | CL | Comisión convertida a USD correctamente |
| 6 | Cross-country isolation | AR+CL | Tenant AR no afecta datos de CL |

#### 5.2.3 `tests/qa-v2/30-approvals-multi-country.spec.ts`

| # | Test | Valida |
|---|------|--------|
| 1 | Super admin filtra aprobaciones por país | `GET /admin/pending-approvals?country=CL` |
| 2 | Approve actualiza status + country_id coherente | `nv_accounts.country = 'CL'` |
| 3 | Bulk actions por país | Aprobar todos los pendientes de AR |
| 4 | Notifications con locale correcto | Email de aprobación usa `es-CL` |

#### 5.2.4 `tests/qa-v2/31-super-admin-country-overview.spec.ts`

| # | Test | Valida |
|---|------|--------|
| 1 | Dashboard muestra breakdown por país | KPI cards por país |
| 2 | Filtro selects AR → solo datos AR | Verify API call con `?country=AR` |
| 3 | QuotasView filtrada por CL | Solo tenants CL |
| 4 | GmvCommissionsView por MX | Solo comisiones MX |
| 5 | Selector persiste entre vistas | LocalStorage |
| 6 | "Todos" muestra totales globales | Sin filtro |

---

## 6. Fase 5 — Flujos Faltantes y Hardening

**Objetivo:** Implementar flujos menores y hardening general.
**Esfuerzo estimado:** 5-7 días
**Dependencia:** Fases 1-4

### 6.1 Email Tracking mejorado

**Estado actual:** `EmailsJobsView.jsx` existe pero no tiene filtros avanzados.

**Mejoras:**
- Filtro por país (via tenant → nv_accounts.country)
- Filtro por template/tipo de email
- Retry manual desde la UI
- Contador de emails sent/failed/pending en DashboardHome
- Alerta si % failed > threshold

**Endpoint nuevo:** `GET /admin/email-jobs?country=&status=&template=&page=&limit=`

### 6.2 Support Resolution tracking

**Estado actual:** `SupportConsoleView.jsx` + 10 endpoints admin.

**Mejoras:**
- Filtro por país en consola de soporte
- Métricas de resolución por país (time-to-respond, time-to-resolve)
- SLA tracking (P0 < 15min, P1 < 2h, P2 < 24h)
- Dashboard widget: "Tickets abiertos por país"
- Export CSV de tickets

### 6.3 Subscription monitoring por país

**Estado actual:** `SubscriptionEventsView.jsx` sin filtro país.

**Mejoras:**
- Filtro por país
- KPIs:  churn rate por país, average LTV por país, trial conversion rate por país
- Alerta si churn de un país > threshold
- Gráfico: lifecycle funnel por país (active → cancel_scheduled → suspended → deactivated)

### 6.4 Billing crons country-aware

**Estado actual:** Crons ejecutan globalmente sin considerar país.

**Mejoras (opcionales, no bloqueantes para go-live):**
- Log con country_id en cada operación de billing
- Métricas de billing agrupadas por país en la ejecución
- Posibilidad de ejecutar cron solo para un país específico (dry-run + execute)

### 6.5 Bug fixes bloqueantes

| Bug | Severidad | Fix |
|-----|-----------|-----|
| `POST /onboarding/approve/:accountId` — auth bypass | 🔴 P0 | Agregar excepción específica en auth middleware para approve (no excluir todo `/onboarding/*`) |
| wa-inbox sin controller | 🟡 P2 | Implementar o remover DTOs huérfanos |

---

## 7. Matriz de Riesgos

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| Multi-país requiere más cambios de los estimados en onboarding | Alta | Alto | Fase 4 depende explícitamente de PLAN_ONBOARDING_DINAMICO; no empezar sin base |
| Performance de JOINs con `nv_accounts.country` en tablas grandes | Baja | Medio | Index ya existe en `nv_accounts(country)`. Monitorear P95 post-deploy |
| Tests E2E flaky por timing de email_jobs worker | Media | Bajo | Usar retry/poll con timeout en tests, no assertions instantáneas |
| Bug de auth en `/onboarding/approve` bloquea tests de Fase 3.5 | Alta | Alto | Fix del bug como pre-requisito explícito |
| FX rates stale afectan métricas por país | Baja | Medio | Verificar que `fx_rates_config.last_auto_fetch_at` < 24h como health check |
| Falta de data de test para países no-AR | Media | Medio | Crear seed de datos demo para CL y MX en E2E fixtures |

---

## 8. Cronograma Estimado

```
Semana 1:  Fase 1 — Filtro global por país (BE endpoints + FE selector + conectar 4 vistas P0)
Semana 2:  Fase 1 cont. + Fase 3a — Tests E2E support tickets + email jobs + store pause
Semana 3:  Fase 2 — Métricas por país (BE aggregates + FE DashboardHome KPIs + gráficos)
Semana 4:  Fase 3b — Tests E2E approval flow (post-bug-fix) + financial views + sub lifecycle
Semana 5:  Fase 4 — Tests multi-país (requiere onboarding dinámico implementado)
Semana 6:  Fase 5 — Hardening: email tracking, support resolution, sub monitoring mejorado
```

**Total estimado: ~6 semanas** (asumiendo 1 dev full-time, sin bloqueos por dependencias externas)

### Entregables por semana

| Semana | Entregable | Criterio de aceptación |
|--------|-----------|----------------------|
| 1 | Filtro por país funcional en super admin | Selector visible, 4 vistas filtran, endpoint `dashboard-meta` activo |
| 2 | 3 nuevos specs E2E (support, email, pause) | Specs verdes en CI, gaps críticos cubiertos |
| 3 | Métricas por país en DashboardHome | KPI cards, gráfico de distribución, endpoint `metrics/by-country` |
| 4 | 3 nuevos specs E2E (approval, financial, lifecycle) | Specs verdes, bug auth corregido |
| 5 | 4 specs multi-país | Onboarding AR+CL+MX, pagos multi-moneda, approvals filtrados |
| 6 | Hardening + monitoring por país | Email tracking, support SLA, sub churn por país |

---

## 9. Pendientes / Preguntas para TL

### Decisiones requeridas antes de implementar

| # | Pregunta | Opciones | Impacto |
|---|----------|----------|---------|
| 1 | ¿Priorizar filtro por país (Fase 1) o tests E2E (Fase 3) primero? | a) País primero (visibilidad), b) Tests primero (cobertura), c) En paralelo | Define orden de ejecución |
| 2 | ¿Denormalizar `country_id` en `quota_state`/`billing_adjustments` o resolver por JOIN con `nv_accounts`? | a) Denormalize (más rápido en queries, más mantenimiento), b) JOIN (menos cambios, depende de índices) | Performance vs complejidad |
| 3 | ¿Activar CL o MX en `country_configs` para tests multi-país, o crear un país ficticio "TEST"? | a) Activar CL (más realista), b) País ficticio (más seguro en prod) | Afecta seed data de E2E |
| 4 | ¿El fix del bug AUTH en `/onboarding/approve` es pre-requisito para esta rama o se hace en otra? | a) Fixear en esta rama, b) Rama separada | Bloquea Fase 3.5 |
| 5 | ¿Se necesitan gráficos (charts) en DashboardHome o alcanza con tablas/KPI cards? | a) Charts (más visual, requiere lib), b) Solo KPI cards (más rápido) | Esfuerzo de Fase 2 |
| 6 | ¿Billing crons country-aware (Fase 5.4) es prioridad o se difiere post-launch? | a) Pre-launch, b) Post-launch | Reduce scope de Fase 5 |
| 7 | ¿E2E tests van en `novavision-e2e` o inline en cada repo? | a) E2E centralizado (actual), b) Inline | Estructura del repo |

### Bloqueos identificados

| Bloqueo | Afecta | Resolución |
|---------|--------|-----------|
| Bug AUTH en `/onboarding/approve` | Fase 3.5 (approval tests) | Fix en auth middleware |
| Onboarding Step8 hardcodeado AR | Fase 4 (multi-país tests) | Requiere PLAN_ONBOARDING_DINAMICO |
| `PlatformMercadoPagoService` solo MLA | Fase 4 (pagos multi-país) | Requiere refactor del service |
| wa-inbox sin controller | Fase 5 (completeness) | Implementar o deprecar |

---

## Appendix A: Resumen de archivos a crear/modificar por fase

### Fase 1 (BE + FE)

**API (5 archivos a modificar, 1 nuevo):**
- `src/admin/admin-quotas.controller.ts` — agregar `country` a select, query param
- `src/admin/admin-adjustments.controller.ts` — agregar `country` a select, query param
- `src/admin/admin-renewals.controller.ts` — agregar `country` filter
- `src/admin/admin.controller.ts` — nuevo endpoint `GET /admin/dashboard-meta`
- DTO para dashboard-meta response

**Admin (3 nuevos, ~10 a modificar):**
- `src/context/CountryFilterContext.jsx` — NUEVO
- `src/hooks/useCountryFilter.js` — NUEVO
- `src/components/CountrySelector.jsx` — NUEVO (dropdown)
- `src/pages/AdminDashboard/QuotasView.jsx` — conectar filtro
- `src/pages/AdminDashboard/GmvCommissionsView.jsx` — conectar filtro
- `src/pages/AdminDashboard/ClientsView.jsx` — conectar filtro
- `src/pages/AdminDashboard/DashboardHome.jsx` — conectar filtro
- (...y ~6 vistas más incrementalmente)

### Fase 2 (BE + FE)

**API (2 nuevos endpoints):**
- `GET /admin/metrics/by-country`
- `GET /admin/metrics/trends?country=&months=`

**Admin (2-3 archivos modificados):**
- `DashboardHome.jsx` — KPI cards + gráfico distribución
- Posible nueva lib de gráficos (recharts o similar)

### Fase 3 (E2E)

**novavision-e2e (7 nuevos specs):**
- `tests/qa-v2/21-support-tickets.spec.ts`
- `tests/qa-v2/22-email-jobs.spec.ts`
- `tests/qa-v2/23-store-pause-resume.spec.ts`
- `tests/qa-v2/24-plan-upgrade.spec.ts`
- `tests/qa-v2/25-approval-flow.spec.ts`
- `tests/qa-v2/26-admin-financial-views.spec.ts`
- `tests/qa-v2/27-subscription-lifecycle-extended.spec.ts`

### Fase 4 (E2E)

**novavision-e2e (4 nuevos specs):**
- `tests/qa-v2/28-onboarding-multi-country.spec.ts`
- `tests/qa-v2/29-payments-multi-country.spec.ts`
- `tests/qa-v2/30-approvals-multi-country.spec.ts`
- `tests/qa-v2/31-super-admin-country-overview.spec.ts`

### Fase 5 (BE + FE + E2E)

**API (3-4 endpoints nuevos/modificados):**
- `GET /admin/email-jobs` con filtros
- `GET /admin/support/metrics-by-country`
- `GET /admin/subscriptions/stats-by-country`

**Admin (3-4 vistas mejoradas):**
- `EmailsJobsView.jsx` — filtros por país
- `SupportConsoleView.jsx` — filtros por país
- `SubscriptionEventsView.jsx` — KPIs por país

---

## Appendix B: Migraciones SQL potenciales

### Fase 1 — No requiere migraciones nuevas
Todo se resuelve con JOINs a `nv_accounts.country`. 

### Fase 2 — Opcional: vista materializada para métricas
```sql
-- Opcional: si el JOIN es lento con muchos tenants
CREATE MATERIALIZED VIEW mv_metrics_by_country AS
SELECT 
  na.country,
  COUNT(DISTINCT na.id) FILTER (WHERE na.status = 'live') as tenants_active,
  COUNT(DISTINCT s.id) FILTER (WHERE s.status = 'active') as subs_active,
  SUM(p.price_usd) FILTER (WHERE s.status IN ('active','cancel_scheduled')) as mrr_usd
FROM nv_accounts na
LEFT JOIN subscriptions s ON s.account_id = na.id
LEFT JOIN plans p ON p.plan_key = s.plan_key
GROUP BY na.country;

-- Refresh con cron cada hora
CREATE INDEX ON mv_metrics_by_country(country);
```

### Fase 5 — Opcional: denormalizar country en tablas de alto volumen
```sql
-- Solo si JOINs se vuelven un bottleneck
ALTER TABLE quota_state ADD COLUMN country_id TEXT;
ALTER TABLE billing_adjustments ADD COLUMN country_id TEXT;

-- Backfill
UPDATE quota_state qs SET country_id = (SELECT country FROM nv_accounts WHERE id = qs.tenant_id);
UPDATE billing_adjustments ba SET country_id = (SELECT country FROM nv_accounts WHERE id = ba.tenant_id);
```

---

*Fin del plan. Esperar aprobación del TL antes de ejecutar cualquier fase.*

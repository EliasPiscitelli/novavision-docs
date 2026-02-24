# NovaVision — Plan de Planes, Límites y Economía SaaS

- **Autor:** agente-copilot (SaaS Pricing Architecture)
- **Fecha:** 2026-02-22
- **Estado:** PLAN — No ejecutar sin aprobación del TL
- **Refs cruzadas:**
  - [LATAM_INTERNATIONALIZATION_PLAN.md](LATAM_INTERNATIONALIZATION_PLAN.md) (FX, fees, facturación)
  - [subscription-guardrails.md](subscription-guardrails.md) (sistema existente de suscripciones)
  - [subscription-hardening-plan.md](subscription-hardening-plan.md) (hardening F0-F6 completado)

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Estado Actual del Sistema de Suscripciones](#2-estado-actual-del-sistema-de-suscripciones)
3. [Schedule de Planes (T&C Ready)](#3-schedule-de-planes-tc-ready)
4. [Modelo Financiero y Cost-to-Serve](#4-modelo-financiero-y-cost-to-serve)
5. [Simulaciones por Escala](#5-simulaciones-por-escala)
6. [Overages y Auto-Upgrade](#6-overages-y-auto-upgrade)
7. [Enforcement Técnico y Anti-Noisy-Neighbor](#7-enforcement-técnico-y-anti-noisy-neighbor)
8. [Diseño de Datos (Tablas DB)](#8-diseño-de-datos-tablas-db)
9. [Endpoints API](#9-endpoints-api)
10. [Rollout Timeline](#10-rollout-timeline)
11. [Matriz de Pruebas E2E](#11-matriz-de-pruebas-e2e)
12. [Texto para Términos y Condiciones](#12-texto-para-términos-y-condiciones)
13. [Gaps, Riesgos y Decisiones Pendientes](#13-gaps-riesgos-y-decisiones-pendientes)
14. [Cross-References con Plan LATAM](#14-cross-references-con-plan-latam)

---

## 1. Resumen Ejecutivo

NovaVision puede sostener **Starter USD 20**, **Growth USD 60** y **Enterprise desde USD 280** con márgenes sanos (~76-79% bruto) en LATAM, siempre que los planes tengan **límites explícitos (quotas)**, **enforcement gradual** y protección **anti-noisy-neighbor** (single DB + single API actuales).

El diseño se apoya en tres pilares:

1. **Schedule de Planes** con límites medibles: tiendas activas, órdenes/mes, API calls/mes, egress/mes, storage y rate-limits (RPS/concurrencia).
2. **Modelo financiero cost-to-serve** con costos unitarios de infra (Railway/Supabase) y procesamiento de pagos; target margen ≥70%.
3. **Capa técnica de enforcement** (DB + API): rate limits por tenant, colas para trabajos pesados, rollups de uso, estado de cuota y auditoría.

**Resultado con mix 70% Starter / 25% Growth / 5% Enterprise (stress test: 100% de cuota usada):**

| Tiendas pagas | Revenue mensual | COGS mensual | Margen bruto |
|---------------|----------------|-------------|-------------|
| 100 | USD 4.300 | USD 1.033 | 75.98% |
| 500 | USD 21.500 | USD 4.666 | 78.30% |
| 1.000 | USD 43.000 | USD 9.177 | 78.66% |

---

## 2. Estado Actual del Sistema de Suscripciones

### 2.1 Infraestructura existente

| Componente | Estado | Ref |
|-----------|--------|-----|
| Tabla `subscriptions` (SoT) | ✅ Implementada | `subscription-guardrails.md` §1 |
| Tabla `plans` (config de planes) | ✅ Implementada | `subscription-guardrails.md` §DB |
| Tabla `account_entitlements` | ✅ Implementada | Post-upgrade entitlements |
| Tabla `nv_billing_events` | ✅ Implementada | Audit log básico |
| Pipeline webhooks unificado | ✅ F1 completado | `mp-router.service.ts` |
| Upgrade con validación (no downgrade) | ✅ F2 completado | `subscriptions.service.ts` |
| Reconcile cron (6AM vs MP API) | ✅ F4 completado | `reconcileWithMercadoPago()` |
| Health-check endpoint | ✅ F5 completado | `/admin/subscriptions/health` |
| Advisory lock en operaciones | ✅ F6 completado | `acquireLock()` / `releaseLock()` |
| Rate limiting global (Express) | ✅ Implementado | `rate-limit.middleware.ts` (in-memory) |
| Rate limiting **per-tenant** | ❌ No existe | — |
| Tracking de uso (API calls, egress, orders) | ❌ No existe | — |
| Quotas y enforcement gradual | ❌ No existe | — |
| Overages y auto-charge | ❌ No existe | — |
| Trial/Free tier | ❌ No existe | — |
| Cost-to-serve tracking | ❌ No existe | — |

### 2.2 Jerarquía de planes existente

```
starter ($20/m, $200/y)  <  growth ($60/m, $600/y)  <  enterprise ($250/m, $2500/y)
```

> **⚠️ DISCREPANCIA:** El documento fuente propone Enterprise desde **USD 280**. El sistema actual tiene **USD 250**. Requiere decisión del TL antes de implementar.

### 2.3 Tabla `plans` actual (Admin DB)

| Campo | Tipo | Notas |
|-------|------|-------|
| plan_key | text PK | `starter`, `starter_annual`, `growth`, `growth_annual`, `enterprise`, `enterprise_annual` |
| monthly_fee | numeric | Precio en USD |
| entitlements | jsonb | Límites por plan (productos, tiendas, etc.) |

### 2.4 Gap analysis: actual vs. propuesto

| Capacidad | Actual | Propuesto | Delta |
|-----------|--------|-----------|-------|
| Plan definitions | `plans` table con `entitlements` JSONB | `plan_catalog` con límites explícitos tipados | Migración + nuevos campos |
| Subscription lifecycle | `subscriptions` + webhooks MP | `tenant_subscription` con auto-charge flag | Extender tabla existente |
| Usage tracking | ❌ Ninguno | `usage_rollups_hourly` + `usage_rollups_monthly` | **Nuevo** — requiere instrumentación |
| Quota enforcement | ❌ Ninguno | `quota_state` con state machine (8 estados) | **Nuevo** — requiere middleware |
| Cost tracking | ❌ Ninguno | `cost_rollups_monthly` | **Nuevo** — requiere cálculo periódico |
| Rate limiting per-tenant | Global (Express middleware) | Token bucket + concurrency per tenant | **Refactor** significativo |
| Overage billing | ❌ Ninguno | `billing_adjustments` + auto-charge opt-in | **Nuevo** — Growth/Enterprise only |
| Trial tier | ❌ No existe | Plan Trial $0 con límites estrictos | **Nuevo** |
| Audit log | `nv_billing_events` (básico) | `audit_log` con before/after de cambios | Extender existente |

---

## 3. Schedule de Planes (T&C Ready)

### 3.1 Definiciones contractuales

| Término | Definición (para T&C) |
|---------|----------------------|
| **Tienda activa** | Tienda que tuvo al menos 1 evento relevante en los últimos 30 días (venta, publicación, cambio de catálogo o login admin) |
| **Orden/Transacción** | Orden con status "pagada/confirmada" (no intentos ni rechazadas) |
| **API Call** | Request autenticado a la API de NV (excluye healthchecks y webhooks entrantes) |
| **Egress** | GB de salida hacia Internet atribuibles al tenant (API responses + assets/descargas) |
| **Storage** | GB de archivos/imágenes del tenant almacenados en el sistema |

### 3.2 Tabla comparativa de planes

> **Nota:** GMV se usa como "fit guidance" (para ventas y soporte). Las cuotas duras son órdenes/API/egress/storage porque son los drivers de costo y riesgo de performance.

| Plan | Precio | Fórmula ARS | Incluye | Límites mensuales (hard) | Rate limits (hard) |
|------|--------|------------|---------|--------------------------|-------------------|
| **Trial (Free)** | USD 0 | — | 1 tienda para probar + publishing básico | 1 tienda, 30 órdenes, 20k API calls, 2 GB egress, 0.5 GB storage | 2 RPS / burst 6 / conc. 5 |
| **Starter** | USD 20 | ARS = 20 × FX_ref | Tienda chica / validación | 1 tienda, 150 órdenes, 100k API calls, 20 GB egress, 1 GB storage | 5 RPS / burst 15 / conc. 15 |
| **Growth** | USD 60 | ARS = 60 × FX_ref | Negocio creciendo, multi-tienda | 3 tiendas, 1.000 órdenes, 800k API calls, 100 GB egress, 10 GB storage | 20 RPS / burst 60 / conc. 60 |
| **Enterprise** | desde USD 280 | ARS = 280 × FX_ref | PYME alto volumen + lane separado | 10 tiendas, 10.000 órdenes, 8M API calls, 500 GB egress, 200 GB storage | 60 RPS / burst 180 / conc. 180 |

### 3.3 Sobre FX_ref (conversión ARS)

> **Vínculo con Plan LATAM §6.5 (Modelo de tres capas de pricing):**
>
> `FX_ref` corresponde a la **Capa 2 (Precio de cobro operativo)** del modelo de tres capas. Para facturación (Capa 3), se usa TC BNA vendedor divisa.
>
> Se recomienda definir `FX_ref` en contrato como un tipo de cambio público y replicable. Opciones:
> - TC BNA vendedor divisa (alineado con Factura E — ver LATAM plan §10.3)
> - TC MEP promedio diario (si la política de la empresa difiere)
>
> **DECISIÓN PENDIENTE:** ¿Se usa el mismo TC para cobro operativo (Capa 2) que para facturación (Capa 3)? Usar el mismo minimiza descalce documental.

### 3.4 Qué incluye cada plan (para pricing page y T&C)

**Trial:**
- 1 tienda activa con funcionalidad completa limitada
- Branding NV visible ("Powered by NovaVision")
- Soporte: documentación + comunidad
- Sin overages — hard limit estricto
- Conversión automática → Starter al exceder

**Starter:**
- 1 tienda activa
- Dominio personalizado + branding básico
- Soporte estándar (email, 48h SLA)
- Sin overages — upgrade obligatorio al exceder

**Growth:**
- **Multi-tienda real (hasta 3)**
- Integraciones y automatizaciones adicionales
- Métricas avanzadas
- Soporte priorizado (email, 24h SLA)
- Overages permitidos con auto-charge (hasta 150% de cuota)

**Enterprise:**
- Hasta 10 tiendas activas
- **Lane de ejecución separado:** workers dedicados a tareas pesadas (exportaciones, batch, reconciliación)
- Límites superiores
- Soporte prioritario (email + chat, 12h SLA)
- Opciones contractuales: SLA / auditoría / logs extendidos
- Overages hasta 200% con auto-charge
- **Add-on disponible:** Infra dedicada física (DB/servicios separados) desde ~USD 550 (custom por capacidad)

> **⚠️ ASSUMPTION:** Enterprise base (USD 280) = carril separado lógico (colas, workers, límites, SLA) **dentro del stack compartido**. La infra dedicada física es add-on, no base, para preservar margen.

---

## 4. Modelo Financiero y Cost-to-Serve

### 4.1 Stack actual y estructura de costos

| Componente | Proveedor | Modelo de pricing |
|------------|----------|-------------------|
| Backend API + workers | Railway | Suscripción + CPU/RAM/egress/volume |
| DB + Storage + Auth | Supabase | Pro/Team: cuotas incluidas + overages + compute por instancia |
| Front admin | Netlify | Free/Pro tier (build minutes limitados) |
| Cobro suscripciones NV | Mercado Pago | Fee por transacción (varía por país/cuotas/medio) |
| Cobro suscripciones NV (futuro) | Stripe (posible) | 2.9% + 30¢ doméstico; +1.5% intl; +1% FX |

### 4.2 Costos unitarios primarios

| Recurso | Costo unitario | Fuente |
|---------|---------------|--------|
| Railway CPU | $20/vCPU/mes | Pricing Railway |
| Railway RAM | $10/GB/mes | Pricing Railway |
| Railway Egress | $0.05/GB | Pricing Railway |
| Railway Volume | $0.15/GB/mes | Pricing Railway |
| Supabase Egress (overage) | $0.09/GB (250 GB incluidos en Pro) | Pricing Supabase |
| Supabase Storage (overage) | $0.021/GB (100 GB incluidos en Pro) | Pricing Supabase |
| Supabase Disk DB (overage) | $0.125/GB (8 GB incluidos) | Pricing Supabase |
| Supabase Compute Micro | $10/mes | Referencia escalado |
| Supabase Compute Medium | $60/mes | Referencia escalado |
| Supabase Compute Large | $110/mes | Referencia escalado |
| Supabase Compute XL | $210/mes | Referencia escalado |

### 4.3 ASSUMPTIONS del modelo de costos

> ⚠️ Estos supuestos se reemplazan por datos reales cuando estén disponibles. Ver §13 "Inputs necesarios".

| # | ASSUMPTION | Valor usado | Cómo reemplazarlo |
|---|-----------|-------------|-------------------|
| C1 | Distribución de egress: 70% Supabase (assets) / 30% Railway (API) | Costo egress blended: $0.078/GB | Medir egress real por proveedor |
| C2 | Costo compute por 1M API calls | $0.20 | Profiling real de CPU por request |
| C3 | Costo operativo por orden (writes DB, webhooks, tasks) | $0.001/orden | Medir recursos por orden |
| C4 | Infra fija mensual core cluster | 100t=$145, 500t=$226, 1000t=$297 | Factura real Railway + Supabase |
| C5 | Enterprise comparte DB (carril lógico separado, no físico) | — | Add-on dedicado si cliente lo requiere |
| C6 | Fee de cobro peor caso (Stripe cross-border + FX) | 2.9% + 1.5% + 1% + $0.30 | Fee real de MP por país/medio |

> **⚠️ NOTA CRÍTICA (C6):** El modelo usa fees de Stripe como "peor caso". NV cobra con **Mercado Pago**, cuyas comisiones varían significativamente por país, medio de pago, cuotas y plazo de liquidación. Para Argentina: el fee real depende de la configuración en `client_payment_settings` y `mp_fee_table`. Para LATAM: ver Plan LATAM §6 (fees por país).
>
> **Esto hace que el margen real pueda ser MEJOR o PEOR que el calculado**, dependiendo del mix de medios de pago y países.

### 4.4 Fórmula COGS por tenant (mensual)

```
COGS_tenant = FeePago + CostoEgress + CostoStorage + CostoAPI + CostoOrdenes + ShareFijo
```

Donde:

| Componente | Fórmula |
|-----------|---------|
| **FeePago** | `P × (2.9% + 1.5% + 1%) + $0.30` (escenario Stripe cross-border+FX) |
| **CostoEgress** | `EgressGB × $0.078` (blended Supabase+Railway) |
| **CostoStorage** | `StorageGB × $0.021` (overage Supabase) |
| **CostoAPI** | `(APIcalls / 1.000.000) × $0.20` |
| **CostoOrdenes** | `Órdenes × $0.001` |
| **ShareFijo** | `CostoFijoMensual / #tenants` |

### 4.5 Cost-to-serve por plan (stress test: 100% cuota + Stripe cross-border)

| Plan | Precio | FeePago | CostoEgress | CostoStorage | CostoAPI | CostoOrdenes | ShareFijo (100t) | **COGS** | **GM%** |
|------|--------|---------|------------|-------------|---------|-------------|-----------------|---------|--------|
| Starter ($20) | $20 | $1.38 | $1.56 | $0.02 | $0.02 | $0.15 | $1.45 | **$4.58** | **77%** |
| Growth ($60) | $60 | $3.54 | $7.80 | $0.21 | $0.16 | $1.00 | $1.45 | **$14.16** | **76%** |
| Enterprise ($280) | $280 | $15.42 | $39.00 | $4.20 | $1.60 | $10.00 | $1.45 | **$71.67** | **74%** |

> El driver #1 del costo en planes chicos es el **fee del cobro**. Por eso la estrategia de cobranza (MP vs. Stripe, local vs. cross-border) importa tanto para el margen.

---

## 5. Simulaciones por Escala

### 5.1 Supuesto de mix comercial

| Plan | % del mix |
|------|----------|
| Starter | 70% |
| Growth | 25% |
| Enterprise | 5% |

### 5.2 Escenario stress test (todos usan 100% cuota + Stripe cross-border)

| Tiendas pagas | Revenue mensual | COGS mensual | Margen bruto | Margen bruto % |
|---------------|----------------|-------------|-------------|----------------|
| 100 | USD 4.300 | USD 1.033 | USD 3.267 | **75.98%** |
| 500 | USD 21.500 | USD 4.666 | USD 16.834 | **78.30%** |
| 1.000 | USD 43.000 | USD 9.177 | USD 33.823 | **78.66%** |

### 5.3 Costo fijo por escala (ASSUMPTION C4)

| Escala | DB Supabase | Railway API | Overhead (monitoreo, colas, correo) | **Total fijo/mes** | **ShareFijo/tenant** |
|--------|------------|------------|-------------------------------------|-------------------|---------------------|
| 100 tiendas | Micro ($10) | 2vCPU/2GB ($60) | $75 | **$145** | $1.45 |
| 500 tiendas | Medium ($60) | 3vCPU/3GB ($90) | $76 | **$226** | $0.45 |
| 1.000 tiendas | Large ($110) | 4vCPU/4GB ($112) | $75 | **$297** | $0.30 |

### 5.4 Benchmark de referencia

| Métrica | Benchmark B2B SaaS | NV estimado |
|---------|--------------------|--------------------|
| Margen bruto (subscription) | ~77% ($1M-$20M ARR) | 76-79% |
| Margen bruto (median) | ~72% (equity-backed) | 76% (stress test) |
| Target mínimo saludable | ≥70% | ✅ Cumple en todos los escenarios |

---

## 6. Overages y Auto-Upgrade

### 6.1 Reglas por plan

| Plan | Overages | Condición | Límite de overage |
|------|----------|-----------|-------------------|
| **Trial** | ❌ NO | — | Hard limit → CTA upgrade a Starter |
| **Starter** | ❌ NO | — | Upgrade obligatorio. Protege infra compartida |
| **Growth** | ✅ SÍ | auto-charge ON + método de pago válido | Hasta 150% de cuota |
| **Enterprise** | ✅ SÍ | auto-charge ON + método de pago válido | Hasta 200% de cuota |

### 6.2 Precios de overage (Growth y Enterprise)

| Recurso | Precio overage | Unidad |
|---------|---------------|--------|
| API calls extra | USD 1 | por cada 100k calls |
| Egress extra | USD 2 | por cada 10 GB |
| Storage extra | USD 0.50 | por GB/mes |

> **Sin método de pago válido:** overages NO disponibles → se aplican límites estrictos (hard limit).

### 6.3 Regla de auto-upgrade

Se ofrece upgrade automático cuando:
```
overage_proyectado > 60% × (precio_plan_superior - precio_plan_actual)
```

**Ejemplo:** Growth $60 → Enterprise $280 (diff $220). Si overage proyectado > $132 → se sugiere upgrade.

### 6.4 Add-on: Enterprise Dedicated (infra física aislada)

| Aspecto | Detalle |
|---------|---------|
| **Qué incluye** | DB y/o API dedicadas (Supabase instancia separada + Railway service separado) |
| **Precio mínimo** | desde ~USD 550/mes (custom por capacidad) |
| **Por qué no es el base** | Un DB Medium/Large para 1-5 clientes destruye el margen a USD 280 base |
| **Target GM** | ≥60% (menor que base porque el costo fijo es alto) |
| **Cuándo ofrecerlo** | Compliance, SLA contractual, altísimo volumen (>10k órdenes/mes) |

---

## 7. Enforcement Técnico y Anti-Noisy-Neighbor

### 7.1 State machine de enforcement

```
ACTIVE ──(50%)──→ WARN_50 ──(75%)──→ WARN_75 ──(90%)──→ WARN_90
                                                            │
                                                         (100%)
                                                            ↓
                                                       SOFT_LIMIT
                                                            │
                                               grace_available?
                                                     │         │
                                                    YES        NO
                                                     ↓         ↓
                                                   GRACE   HARD_LIMIT
                                                     │
                                            grace_expired ∨
                                            metric ≥ 110%
                                                     ↓
                                                HARD_LIMIT
```

Adicionalmente:
```
payment_failed → BILLING_HOLD → (grace_expired) → SUSPENDED
payment_cleared ∧ within_limits → ACTIVE
upgrade_completed ∧ within_limits → ACTIVE
```

### 7.2 Reglas de enforcement por plan

| Regla | Trial | Starter | Growth | Enterprise |
|-------|-------|---------|--------|-----------|
| Warnings (% cuota) | 50/75/90/100 | 50/75/90/100 | 50/75/90/100 | 50/75/90/100 |
| Grace period | 0 días | 7 días | 14 días | 30 días |
| Overages | NO | NO | Sí (hasta 150%) | Sí (hasta 200%) |
| Hard limit trigger | 100% inmediato | 100% + fin grace | 110% o fin grace | 120% o fin grace |
| Sin método de pago | Hard a 100% | Hard a 100% | Hard a 100% | Hard a 100% |

### 7.3 Rate limits por tenant

Dos limitadores complementarios:

1. **Token bucket (RPS):** Controla requests por segundo con burst permitido.
2. **Concurrency limiter:** Evita que un tenant monopolice conexiones con requests lentos/pesados.

| Plan | RPS sostenido | Burst máximo | Concurrencia máxima |
|------|--------------|-------------|-------------------|
| Trial | 2 | 6 | 5 |
| Starter | 5 | 15 | 15 |
| Growth | 20 | 60 | 60 |
| Enterprise | 60 | 180 | 180 |

> **Referencia:** Stripe API limita a 25 req/seg por defecto con 429 + retry.

### 7.4 Cambios requeridos en rate limiting actual

| Aspecto | Estado actual | Target |
|---------|--------------|--------|
| Mecanismo | Express middleware global (`rate-limit.middleware.ts`, in-memory, `rate-limiter-flexible`) | Per-tenant token bucket + concurrency limiter |
| Scope | Global (todos los tenants comparten el mismo bucket) | Por `client_id` (cada tenant tiene su bucket) |
| Store | In-memory (se pierde con restart) | Redis (persistente, compartido si multi-instancia) |
| Identificación | IP-based | `client_id` extraído del JWT/header (post-auth) |
| Configuración | Estática en código | Dinámica desde `plan_catalog` (RPS/burst/conc por plan) |

> **Riesgo de migración:** El rate limiter actual protege contra DDoS genérico. El nuevo (per-tenant) protege contra noisy neighbors. Se recomienda **mantener ambos**: global como primera línea + per-tenant como segunda línea.

### 7.5 Acciones por estado de enforcement

| Estado | UI al tenant | API behavior | Notificación |
|--------|-------------|-------------|-------------|
| ACTIVE | Normal | Normal | — |
| WARN_50 | Banner informativo | Normal | Email + in-app |
| WARN_75 | Banner naranja | Normal | Email + in-app |
| WARN_90 | Banner rojo + CTA upgrade | Normal | Email urgente + in-app |
| SOFT_LIMIT | Modal "alcanzaste tu límite" | Writes bloqueados (reads OK) | Email |
| GRACE | Modal + countdown | Writes bloqueados | Email diario |
| HARD_LIMIT | Modo lectura + CTA upgrade | Writes bloqueados, nuevas órdenes rechazadas | Email + in-app |
| BILLING_HOLD | Banner "verificá tu pago" | Funcionalidad reducida | Email |
| SUSPENDED | Tienda offline | Todo bloqueado excepto login admin + upgrade/pagar | Email final |

---

## 8. Diseño de Datos (Tablas DB)

### 8.1 Mapeo con tablas existentes

| Tabla propuesta | Tabla existente equivalente | Acción |
|----------------|---------------------------|--------|
| `plan_catalog` | `plans` | **Extender** `plans` con columnas de límites tipados |
| `tenant_subscription` | `subscriptions` | **Extender** `subscriptions` con `auto_charge_enabled`, `overage_allowed` |
| `usage_rollups_hourly` | ❌ No existe | **Crear nueva** |
| `usage_rollups_monthly` | ❌ No existe | **Crear nueva** |
| `cost_rollups_monthly` | ❌ No existe | **Crear nueva** |
| `quota_state` | ❌ No existe | **Crear nueva** |
| `billing_adjustments` | ❌ No existe | **Crear nueva** |
| `audit_log` (plan changes) | `nv_billing_events` | **Extender** con campos before/after |

> **Principio:** Preferimos **extender** tablas existentes en lugar de crear duplicados. Solo se crean tablas nuevas para conceptos que no tienen equivalente.

### 8.2 Extensión de `plans` (Admin DB)

```sql
-- Extender tabla existente 'plans' con límites explícitos
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS max_active_stores integer NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS max_orders_month integer NOT NULL DEFAULT 150,
  ADD COLUMN IF NOT EXISTS max_api_calls_month integer NOT NULL DEFAULT 100000,
  ADD COLUMN IF NOT EXISTS max_egress_gb_month numeric(10,2) NOT NULL DEFAULT 20,
  ADD COLUMN IF NOT EXISTS max_storage_gb numeric(10,2) NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS rps_sustained integer NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS rps_burst integer NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS max_concurrency integer NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS overage_allowed boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS overage_max_percent integer DEFAULT NULL,  -- ej: 150 = hasta 150% del límite
  ADD COLUMN IF NOT EXISTS grace_days integer NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS price_usd numeric(10,2) NOT NULL DEFAULT 0,
  ADD COLUMN IF NOT EXISTS is_trial boolean NOT NULL DEFAULT false;
```

**Seed de referencia:**

```sql
-- Trial
INSERT INTO plans (plan_key, monthly_fee, price_usd, max_active_stores, max_orders_month, max_api_calls_month, max_egress_gb_month, max_storage_gb, rps_sustained, rps_burst, max_concurrency, overage_allowed, overage_max_percent, grace_days, is_trial, entitlements)
VALUES ('trial', 0, 0, 1, 30, 20000, 2, 0.5, 2, 6, 5, false, NULL, 0, true, '{}')
ON CONFLICT (plan_key) DO UPDATE SET
  max_active_stores = EXCLUDED.max_active_stores,
  max_orders_month = EXCLUDED.max_orders_month,
  max_api_calls_month = EXCLUDED.max_api_calls_month,
  max_egress_gb_month = EXCLUDED.max_egress_gb_month,
  max_storage_gb = EXCLUDED.max_storage_gb,
  rps_sustained = EXCLUDED.rps_sustained,
  rps_burst = EXCLUDED.rps_burst,
  max_concurrency = EXCLUDED.max_concurrency,
  overage_allowed = EXCLUDED.overage_allowed,
  grace_days = EXCLUDED.grace_days,
  is_trial = EXCLUDED.is_trial;

-- Starter (y completar para starter_annual, growth, growth_annual, enterprise, enterprise_annual)
```

### 8.3 Extensión de `subscriptions` (Admin DB)

```sql
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS auto_charge_enabled boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS payment_method_id text,          -- ref a método de pago para overages
  ADD COLUMN IF NOT EXISTS current_period_start timestamptz,
  ADD COLUMN IF NOT EXISTS current_period_end timestamptz;
```

### 8.4 Nueva tabla: `usage_rollups_hourly` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS usage_rollups_hourly (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES nv_accounts(id),
  hour timestamptz NOT NULL,  -- truncado a hora (ej: '2026-02-22T14:00:00Z')
  api_calls integer NOT NULL DEFAULT 0,
  egress_bytes bigint NOT NULL DEFAULT 0,
  orders_confirmed integer NOT NULL DEFAULT 0,
  storage_bytes_snapshot bigint,  -- NULL si no se midió esa hora
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, hour)
);

CREATE INDEX idx_usage_hourly_tenant_hour ON usage_rollups_hourly (tenant_id, hour DESC);
```

### 8.5 Nueva tabla: `usage_rollups_monthly` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS usage_rollups_monthly (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES nv_accounts(id),
  period_start date NOT NULL,       -- primer día del mes
  api_calls bigint NOT NULL DEFAULT 0,
  egress_gb numeric(10,4) NOT NULL DEFAULT 0,
  orders_confirmed integer NOT NULL DEFAULT 0,
  storage_gb_avg numeric(10,4) NOT NULL DEFAULT 0,
  active_stores integer NOT NULL DEFAULT 0,
  peak_rps numeric(10,2),           -- p99 RPS del período
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, period_start)
);

CREATE INDEX idx_usage_monthly_tenant_period ON usage_rollups_monthly (tenant_id, period_start DESC);
```

### 8.6 Nueva tabla: `cost_rollups_monthly` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS cost_rollups_monthly (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES nv_accounts(id),
  period_start date NOT NULL,
  cost_egress_usd numeric(10,4) NOT NULL DEFAULT 0,
  cost_storage_usd numeric(10,4) NOT NULL DEFAULT 0,
  cost_api_usd numeric(10,4) NOT NULL DEFAULT 0,
  cost_orders_usd numeric(10,4) NOT NULL DEFAULT 0,
  cost_payment_fee_usd numeric(10,4) NOT NULL DEFAULT 0,
  cost_fixed_share_usd numeric(10,4) NOT NULL DEFAULT 0,
  cogs_total_usd numeric(10,4) GENERATED ALWAYS AS (
    cost_egress_usd + cost_storage_usd + cost_api_usd + cost_orders_usd + cost_payment_fee_usd + cost_fixed_share_usd
  ) STORED,
  revenue_usd numeric(10,4) NOT NULL DEFAULT 0,
  margin_pct numeric(5,2) GENERATED ALWAYS AS (
    CASE WHEN revenue_usd > 0 THEN ((revenue_usd - (cost_egress_usd + cost_storage_usd + cost_api_usd + cost_orders_usd + cost_payment_fee_usd + cost_fixed_share_usd)) / revenue_usd * 100) ELSE 0 END
  ) STORED,
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, period_start)
);

CREATE INDEX idx_cost_monthly_tenant_period ON cost_rollups_monthly (tenant_id, period_start DESC);
```

### 8.7 Nueva tabla: `quota_state` (Admin DB)

```sql
CREATE TYPE quota_status AS ENUM (
  'active',
  'warn_50',
  'warn_75',
  'warn_90',
  'soft_limit',
  'grace',
  'hard_limit',
  'billing_hold',
  'suspended'
);

CREATE TABLE IF NOT EXISTS quota_state (
  tenant_id uuid PRIMARY KEY REFERENCES nv_accounts(id),
  status quota_status NOT NULL DEFAULT 'active',
  highest_metric_pct numeric(5,2) DEFAULT 0,      -- % de la cuota con mayor uso
  highest_metric_name text,                        -- 'api_calls' | 'egress' | 'orders' | 'storage' | 'stores'
  grace_started_at timestamptz,
  grace_until timestamptz,
  last_warning_sent_at timestamptz,
  last_state_change_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

### 8.8 Nueva tabla: `billing_adjustments` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS billing_adjustments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id uuid NOT NULL REFERENCES nv_accounts(id),
  period_start date NOT NULL,
  type text NOT NULL CHECK (type IN ('overage', 'credit', 'refund', 'promo')),
  resource text,                    -- 'api_calls', 'egress', 'storage', NULL para créditos genéricos
  quantity numeric(10,4),           -- unidades excedidas
  unit_price_usd numeric(10,4),    -- precio por unidad
  amount_usd numeric(10,4) NOT NULL,
  currency text NOT NULL DEFAULT 'USD',
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'charged', 'failed', 'waived')),
  charged_at timestamptz,
  payment_reference text,           -- ref al pago de MP/Stripe
  notes text,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_billing_adj_tenant_period ON billing_adjustments (tenant_id, period_start);
```

### 8.9 Extensión de `nv_billing_events` (audit con before/after)

```sql
ALTER TABLE nv_billing_events
  ADD COLUMN IF NOT EXISTS before_state jsonb,      -- snapshot antes del cambio
  ADD COLUMN IF NOT EXISTS after_state jsonb,       -- snapshot después del cambio
  ADD COLUMN IF NOT EXISTS triggered_by text,       -- 'user', 'system', 'super_admin', 'cron'
  ADD COLUMN IF NOT EXISTS correlation_id text;     -- para agrupar eventos relacionados
```

### 8.10 SQL de cost-to-serve por tenant (query operativa)

```sql
-- Costo mensual estimado por tenant (para dashboard super-admin)
WITH u AS (
  SELECT
    tenant_id,
    period_start,
    api_calls,
    egress_gb,
    storage_gb_avg,
    orders_confirmed
  FROM usage_rollups_monthly
  WHERE period_start = date_trunc('month', now())::date
)
SELECT
  u.tenant_id,
  a.name AS tenant_name,
  p.plan_key,
  p.price_usd AS revenue,
  u.api_calls,
  u.egress_gb,
  u.storage_gb_avg,
  u.orders_confirmed,
  (u.egress_gb * 0.078) AS cost_egress,
  (u.storage_gb_avg * 0.021) AS cost_storage,
  ((u.api_calls / 1000000.0) * 0.20) AS cost_api,
  (u.orders_confirmed * 0.001) AS cost_orders,
  -- Fee de cobro (ASSUMPTION: Stripe cross-border)
  (p.price_usd * 0.054 + 0.30) AS cost_payment_fee,
  -- COGS total
  (u.egress_gb * 0.078) + (u.storage_gb_avg * 0.021) + ((u.api_calls / 1000000.0) * 0.20) + (u.orders_confirmed * 0.001) + (p.price_usd * 0.054 + 0.30) AS cogs_estimated
FROM u
JOIN nv_accounts a ON a.id = u.tenant_id
JOIN subscriptions s ON s.account_id = a.id AND s.status = 'active'
JOIN plans p ON p.plan_key = s.plan_key
ORDER BY cogs_estimated DESC;
```

---

## 9. Endpoints API

### 9.1 Endpoints nuevos requeridos

| Método | Ruta | Guard | Descripción |
|--------|------|-------|-------------|
| GET | `/v1/tenants/:id/quotas` | Auth + Tenant/Admin | Uso actual vs. límites del plan |
| POST | `/v1/quota/check` | Internal (middleware) | Verifica si la acción está dentro de cuota antes de ejecutarla |
| POST | `/v1/billing/upgrade` | Auth + Tenant | Upgrade self-serve inmediato |
| POST | `/v1/billing/autocharge/enable` | Auth + Tenant | Opt-in para overages |
| GET | `/admin/tenants/:id/cost-to-serve` | SuperAdmin | Cost-to-serve de un tenant |
| GET | `/admin/economics/summary` | SuperAdmin | Dashboard económico global |

### 9.2 Contract: GET `/v1/tenants/:id/quotas`

```json
{
  "plan": "growth",
  "period": "2026-02",
  "quotas": {
    "active_stores": { "used": 2, "limit": 3, "pct": 66.7 },
    "orders": { "used": 450, "limit": 1000, "pct": 45.0 },
    "api_calls": { "used": 320000, "limit": 800000, "pct": 40.0 },
    "egress_gb": { "used": 38.5, "limit": 100, "pct": 38.5 },
    "storage_gb": { "used": 4.2, "limit": 10, "pct": 42.0 }
  },
  "rate_limits": {
    "rps_sustained": 20,
    "rps_burst": 60,
    "max_concurrency": 60
  },
  "enforcement": {
    "status": "active",
    "highest_metric": "active_stores",
    "highest_pct": 66.7,
    "grace_until": null,
    "overage_enabled": true,
    "overage_max_pct": 150
  }
}
```

### 9.3 Middleware de quota check (pseudocódigo)

```typescript
// Ejecuta ANTES de operaciones que consumen cuota
async function quotaCheckMiddleware(req, res, next) {
  const tenantId = req.tenantContext.clientId;
  const action = resolveAction(req); // 'create_order', 'api_call', 'upload_file', etc.

  const quotaState = await getQuotaState(tenantId);

  if (quotaState.status === 'hard_limit' || quotaState.status === 'suspended') {
    if (isWriteAction(action)) {
      return res.status(429).json({
        error: 'quota_exceeded',
        message: 'Has alcanzado el límite de tu plan. Upgradeá para continuar.',
        upgrade_url: '/settings/billing'
      });
    }
  }

  if (quotaState.status === 'soft_limit' || quotaState.status === 'grace') {
    if (isWriteAction(action) && !isOverageAllowed(tenantId)) {
      return res.status(429).json({
        error: 'quota_soft_limit',
        message: 'Has alcanzado el límite. Habilitá auto-charge o upgradeá.',
      });
    }
  }

  next();
}
```

---

## 10. Rollout Timeline

### 10.1 Cronograma de 6 semanas

| Semana | Entregable | Detalle |
|--------|-----------|---------|
| **Week 1** | DB schema | Crear/extender `plans` + crear `quota_state` + `usage_rollups_hourly`. Seed de planes con límites. Migración sin downtime |
| **Week 2** | Instrumentación | Middleware que incrementa `usage_rollups_hourly` (API calls, orders). Cron horario para consolidar egress/storage |
| **Week 3** | UI + Warnings | Endpoint `/quotas` + UI de consumo (barra de progreso por métrica). Warnings 50/75/90/100% (email + in-app banner) |
| **Week 4** | Rate limits + enforcement | Per-tenant rate limiter (Redis). Soft limit + grace. `quota_state` state machine |
| **Week 5** | Overages | `billing_adjustments` + auto-charge opt-in (Growth/Enterprise). UI para habilitar/ver overages |
| **Week 6** | Auditoría + E2E + T&C | `nv_billing_events` extended. E2E tests (ver §11). Publicar Schedule en T&C. Dashboard super-admin |

### 10.2 Dependencias con otros planes

| Dependencia | De | Estado |
|------------|-----|--------|
| Redis para rate limiting | Rate limiter per-tenant (Week 4) | ⚠️ Verificar si ya hay Redis en Railway (usado para MP state en OAuth?) |
| Plan LATAM §6.5 (FX_ref) | FX_ref para conversión ARS (§3.3) | Plan, no implementado |
| Subscription hardening F0-F6 | Base estable para extender | ✅ Completado |

---

## 11. Matriz de Pruebas E2E

| # | Escenario | Input | Esperado |
|---|----------|-------|----------|
| 1 | Onboarding Trial | Alta + 1 tienda | Límites Trial correctos. `quota_state` = ACTIVE |
| 2 | Cruce 50% | Uso alcanza 50% API calls | Warning en UI + email |
| 3 | Cruce 75% | Uso alcanza 75% egress | Warning naranja + email |
| 4 | Cruce 90% | Uso alcanza 90% órdenes | Warning rojo + CTA upgrade |
| 5 | Cruce 100% Starter | Excede cuota órdenes | SOFT_LIMIT + GRACE 7d + CTA |
| 6 | Hard limit Starter | Fin de gracia sin upgrade | Writes bloqueados, reads OK |
| 7 | Growth overage OK | Excede 100% con auto-charge | Permite hasta 150%. `billing_adjustments` creado |
| 8 | Growth overage sin pago | Auto-charge OFF + excede | Hard limit a 100% |
| 9 | Upgrade inmediato | hard_limit → upgrade a Growth | Desbloqueo instantáneo. `quota_state` = ACTIVE |
| 10 | Downgrade | Growth → Starter | Efectivo al próximo ciclo (guarda). Entitlements validados |
| 11 | Pago fallido | Renovación falla | BILLING_HOLD → email → 14d → SUSPENDED |
| 12 | Auditoría | Cambio de plan via super-admin | `nv_billing_events` con before_state/after_state |
| 13 | Rate limit hit | 25 req/seg sostenidos (Starter, límite 5) | 429 después del burst. No afecta otros tenants |
| 14 | Trial → Starter | Excede Trial → paga | Trial limits reemplazados por Starter |

---

## 12. Texto para Términos y Condiciones

### 12.1 Límites de uso

> "Cada Plan incluye límites de uso mensuales (por ejemplo: tiendas activas, órdenes, llamadas a la API, egreso de datos y almacenamiento). NovaVision medirá el uso mediante métricas internas y/o datos derivados del uso del Servicio. Las métricas de NovaVision constituyen la referencia para la aplicación de límites."

### 12.2 Enforcement y suspensión

> "Al aproximarse a los límites, NovaVision podrá notificar al Cliente. Al excederlos, NovaVision podrá aplicar limitaciones graduales (advertencias, limitación de rendimiento, suspensión parcial) y, de persistir el excedente, suspender funcionalidades hasta el próximo ciclo o hasta que el Cliente realice un upgrade."

### 12.3 Overages y auto-charge

> "En planes que lo permitan, el Cliente puede habilitar 'auto-charge' para cargos por excedente. Sin método de pago válido, los excedentes no estarán disponibles y se aplicarán límites estrictos."

### 12.4 Tipo de cambio (para pricing ARS)

> "Los precios expresados en ARS se calculan aplicando el tipo de cambio de referencia publicado por [entidad a definir] ('FX_ref') vigente al momento del cobro. Ante variaciones significativas, NovaVision podrá actualizar los precios ARS con aviso previo de [X] días."

> **Conexión con Plan LATAM §6.5:** Este texto debe ser consistente con la política de Factura E (si NV factura en USD, el precio ARS es informativo/operativo).

---

## 13. Gaps, Riesgos y Decisiones Pendientes

### 13.1 Decisiones abiertas (requieren input del TL)

| # | Decisión | Impacto | Opciones |
|---|---------|---------|---------|
| D1 | **Enterprise: $250 (actual) o $280 (propuesto)?** | Migración de suscripciones existentes, comunicación a clientes | A) Mantener $250. B) Subir a $280 para nuevos, grandfather $250 |
| D2 | **FX_ref: ¿TC BNA vendedor divisa o MEP?** | Consistencia con Factura E (LATAM plan) | A) BNA vendedor (alineado con ARCA). B) MEP. C) Definir por contrato |
| D3 | **Trial: ¿existe hoy? ¿se crea?** | UX de onboarding, churn | A) Crear Trial. B) Solo Starter con 30-day money-back |
| D4 | **Redis: ¿ya hay instancia o hay que provisionar?** | Rate limiting per-tenant y usage tracking | Verificar Railway/infra actual |
| D5 | **Fee de cobro real de MP** | El modelo usa Stripe como proxy. El fee real de MP puede variar ±2-3% | Obtener fee real de MP dashboard |
| D6 | **Tienda "activa" = ¿qué eventos cuentan?** | Define cuándo un tenant consume cuota de tiendas | Propuesta: venta, publicación, cambio catálogo o login admin en 30 días |
| D7 | **¿Overages se cobran inmediatamente o al final del ciclo?** | Cash flow y UX | A) Al final del ciclo (como Supabase). B) Inmediato al exceder |

### 13.2 Inputs necesarios para eliminar ASSUMPTIONS

| # | Dato requerido | Para qué | Estado |
|---|---------------|---------|--------|
| I1 | Factura real mensual de Railway (CPU/RAM/egress/volumes) | Reemplazar ASSUMPTION C4 | ❌ PENDIENTE |
| I2 | Factura real de Supabase (compute, egress, storage consumidos) | Reemplazar ASSUMPTION C4 | ❌ PENDIENTE |
| I3 | Métricas reales: p95/p99 RPS por tenant, tamaño promedio respuesta | Calibrar rate limits y cost model | ❌ PENDIENTE |
| I4 | % egress desde Supabase storage vs Railway API (real) | Reemplazar ASSUMPTION C1 | ❌ PENDIENTE |
| I5 | Fee real de MP por cobro de suscripción NV (% + fijo, por medio/plazo) | Reemplazar ASSUMPTION C6 | ❌ PENDIENTE |
| I6 | Distribución real de tenants por plan (si hay datos históricos) | Validar o reemplazar mix 70/25/5 | ❌ PENDIENTE |

### 13.3 Riesgos identificados

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|--------|-------------|---------|-----------|
| R1 | **Fee real de MP >> Stripe** → margen menor al proyectado | MEDIA | ALTO | Obtener fee real (I5). Si pasa del 8%, ajustar pricing o negociar con MP |
| R2 | **Noisy neighbor antes de implementar enforcement** → degradación global | ALTA (hoy) | ALTO | Priorizar Week 4 (rate limits). Mantener rate limiter global como baseline |
| R3 | **Redis no disponible** → per-tenant rate limiting requiere provisionar | MEDIA | MEDIO | Verificar infra (D4). Alternativa: in-memory per-instance (pierde sync multi-instancia) |
| R4 | **Trial abuse** → usuarios crean múltiples trials | MEDIA | BAJO | Rate limit por IP/email en signup. Verificación email obligatoria |
| R5 | **Overage disputes** → cliente reclama que no autorizó el cargo | BAJA | MEDIO | Auto-charge requiere opt-in explícito. Notificaciones previas. T&C claro |
| R6 | **Usage tracking overhead** → incrementar contadores en cada request impacta latencia | MEDIA | MEDIO | Incrementos no-bloqueantes (fire-and-forget a Redis, batch flush a DB cada hora) |

### 13.4 Deuda técnica que este plan genera o surfacea

| Item | Deuda | Prioridad |
|------|-------|-----------|
| DT1 | `ThrottlerModule` de NestJS fue eliminado en security hardening. Rate limiting está en Express middleware. Agregar per-tenant requiere reevaluar el approach | ALTA |
| DT2 | `account_entitlements` y los nuevos límites en `plans` pueden duplicar concepto. Definir SoT | MEDIA |
| DT3 | `updateAllPrices()` cron (2AM) usa "dólar blue" para calcular precios ARS. Si se define FX_ref oficial (D2), este cron debe migrar | ALTA |
| DT4 | No hay infra de emails transaccionales robusta para warnings (50/75/90). Verificar si el sistema de email actual soporta este volumen | MEDIA |

---

## 14. Cross-References con Plan LATAM

| Tema de este doc | Sección LATAM relacionada | Conexión |
|-----------------|--------------------------|---------|
| FX_ref para conversión ARS (§3.3) | §6.5 Modelo tres capas de pricing | FX_ref = Capa 2 (operativo). Factura E = Capa 3 (fiscal, TC BNA vendedor divisa) |
| Fee de cobro por transacción (§4.2) | §6.1 Dimensiones del modelo de fees | El fee varía por país (CL/MX/CO). El cost-to-serve de este doc usa Stripe como proxy; el modelo LATAM detalla fees MP por país |
| Overages y facturación (§6) | §10.3 Factura E | Si NV cobra overages, ¿se facturan por separado en Factura E? ¿O se agregan al monto mensual? |
| Rate limits per-tenant (§7.3) | §7.6 Criterios habilitación fiscal por país | Ambos son "gates": uno técnico (rate limit) y otro fiscal (country activation) |
| Trial tier (§3.2) | §2 B2B-only policy | ¿El Trial aplica solo a AR o también a sellers LATAM? Si es LATAM, necesita B2B verification en signup |
| Texto T&C (§12) | §2 Cláusulas contractuales B2B | Los textos T&C de este doc deben integrarse con las 7 cláusulas B2B del plan LATAM |
| Enterprise Dedicated add-on (§6.4) | §8 Cronograma Fase 5 | Infra dedicada requiere decisiones de DB que impactan el modelo multi-tenant del plan LATAM |

### Preguntas cruzadas (para agregar al plan LATAM)

| # | Pregunta | Contexto |
|---|---------|---------|
| Q22 | ¿Los límites de plan (quotas) se definen globalmente o por país del tenant? | Un Starter en Chile podría tener costo diferente que en Argentina (fees MP, egress) |
| Q23 | ¿El Trial está disponible para sellers no-AR? Si sí, ¿requiere verificación B2B? | Interacción entre Trial tier y policy B2B-only del plan LATAM |

---

*Este documento es un plan. No se ejecutan cambios sin aprobación explícita del TL.*

# NovaVision — Plan Maestro de Implementación v3

- **Autor:** agente-copilot
- **Fecha:** 2026-02-22 (v3)
- **Estado:** PLAN — No ejecutar sin aprobación del TL
- **Origen:** Plan final proporcionado por el TL, validado contra el código y DB reales
- **Refs cruzadas:**
  - [LATAM_INTERNATIONALIZATION_PLAN.md](LATAM_INTERNATIONALIZATION_PLAN.md) (i18n, fees, facturación)
  - [PLANS_LIMITS_ECONOMICS.md](PLANS_LIMITS_ECONOMICS.md) (primera versión de planes/economía)
  - [subscription-guardrails.md](subscription-guardrails.md) (reglas inmutables del sistema actual)

---

## Índice

1. [Resumen Ejecutivo (Adaptado)](#1-resumen-ejecutivo-adaptado)
2. [Explicación de Decisiones y Items Resueltos](#2-explicación-de-decisiones-y-items-resueltos)
3. [Investigación FX: Fuentes de Tipo de Cambio](#3-investigación-fx-fuentes-de-tipo-de-cambio)
4. [Comisión por Ventas (GMV): Diseño Completo](#4-comisión-por-ventas-gmv-diseño-completo)
5. [Super Admin Dashboard: Configuración Centralizada](#5-super-admin-dashboard-configuración-centralizada)
6. [Mapeo de Tablas: Propuestas vs. Existentes](#6-mapeo-de-tablas-propuestas-vs-existentes)
7. [DB Schema: Migraciones Completas (SQL Final)](#7-db-schema-migraciones-completas-sql-final)
8. [Contratos API (con Request/Response)](#8-contratos-api-con-requestresponse)
9. [Roadmap por Fases (con pre-checks)](#9-roadmap-por-fases-con-pre-checks)
10. [Reglas de Facturación, Pricing y Simulaciones de Costos](#10-reglas-de-facturación-pricing-y-simulaciones-de-costos)
11. [Documento Legal: T&C y Cláusulas Fiscales](#11-documento-legal-tc-y-cláusulas-fiscales)
12. [Matriz de Riesgos (Validada)](#12-matriz-de-riesgos-validada)
13. [PENDIENTES Actualizados + Tareas Legales/Ops](#13-pendientes-actualizados--tareas-legalesops)

---

## 1. Resumen Ejecutivo (Adaptado)

El plan maestro se adapta a un sistema de suscripciones **ya maduro** (3600+ líneas en `subscriptions.service.ts`, hardening F0-F6 completado, lifecycle completo con grace/suspend/deactivate/purge, reconciliación cross-DB, distributed locking, outbox notifications).

**Cambios clave del plan maestro vs. doc anterior (PLANS_LIMITS_ECONOMICS.md):**

| Aspecto | Doc anterior | Plan maestro (este doc) | Impacto |
|---------|-------------|------------------------|---------|
| Enterprise price | USD 280 | **USD 390** (definitivo, sin grandfather) | Migración `plans` seed + pricing page |
| Enterprise infra | Carril lógico (base) + add-on dedicado | **Infra dedicada real (DB/API separadas) = requisito** | Mayor COGS pero mayor precio lo compensa |
| Trial | Plan aparte | **Cupón/días gratis dentro de Starter/Growth** | Simplifica: no hay plan "trial", solo descuento temporal |
| Comisión por ventas | No contemplada | **% sobre ventas tras exceder umbrales de GMV** | Nuevo revenue stream + nueva lógica (ver §4) |
| B2B/B2C | Solo B2B | **Mixto B2B/B2C, registrar datos fiscales opcional** | Onboarding más flexible |
| Rate limits Growth | 20 RPS / 60 burst | **15 RPS / 45 burst** | Ajuste menor |
| FX_ref | dólar blue (en prod) | **Estrategia dual: dolarapi oficial para AR + multi-source para LATAM** | Ver §3 |

---

## 2. Explicación de Decisiones y Items Resueltos

### 2.1 Punto de Venta Factura E ante ARCA (ex AFIP)

**¿Qué es?** En Argentina, para emitir facturas legalmente, todo contribuyente necesita un **Punto de Venta** (PV) registrado ante ARCA (Administración Federal de Ingresos Públicos, ex AFIP). Existen distintos tipos de facturas:

- **Factura A**: entre Responsables Inscriptos (RI)
- **Factura B**: de RI a Consumidor Final
- **Factura C**: de Monotributista a cualquier receptor (la que NV usa hoy)
- **Factura E**: para **exportación de servicios** (servicios prestados a clientes fuera de Argentina, o servicios digitales categorizados como exportación)

**¿Por qué importa?** NovaVision cobra suscripciones SaaS en USD a clientes que pueden estar en cualquier país LATAM. Esto se clasifica fiscalmente como **exportación de servicios**. Para emitir una Factura E, se necesita:
1. Un PV habilitado específicamente para Factura E (se tramita online en la web de ARCA)
2. Definir si NV opera como Monotributo o Responsable Inscripto (afecta el tipo de PV)
3. El PV se usa luego para generar cada factura con CAE (Código de Autorización Electrónico)

**¿Bloquea la operación actual?** NO para Argentina doméstico (NV opera con Factura C de Monotributo). SÍ bloquea:
- Facturación formal en USD
- Cobro a clientes internacionales con comprobante fiscal válido
- Deducción de IVA en servicios digitales de exportación

**Acción concreta:**
1. Entrar a [serviciosweb.afip.gob.ar](https://serviciosweb.afip.gob.ar) → ABM de Puntos de Venta
2. Dar de alta un PV tipo "RECE" (Comprobantes en Línea) para Factura E
3. Anotar el número de PV asignado → guardarlo en config (`punto_venta` en `nv_invoices`)
4. Tiempo estimado: 15 min online (si la CUIT/categoría ya está habilitada)

**¿Afecta el código?** Solo el campo `punto_venta` en la tabla `nv_invoices`. El PV es un número que se guarda y se envía al webservice de ARCA para solicitar CAE. Es **configurable desde el super admin** (ver §5).

### 2.2 Consulta BCRA sobre Liquidación de Divisas

**¿Qué es?** Cuando un contribuyente argentino recibe pagos del exterior (cobros en USD por exportación de servicios), existe una normativa del BCRA (Banco Central) que obliga a **liquidar las divisas en el Mercado Libre de Cambios (MLC)** dentro de ciertos plazos (generalmente 5 días hábiles). Esto significa convertir los USD recibidos a ARS al tipo de cambio oficial.

**¿Por qué importa?** Si NV cobra suscripciones en USD a clientes de Chile, México, etc., técnicamente recibe divisas del exterior. La normativa vigente (Com. A 7518 y modificatorias) obliga a liquidar esos dólares, lo que genera:
- **Pérdida por brecha cambiaria** (el oficial es mucho más bajo que el paralelo)
- **Carga administrativa** (documentación, DJAI de servicios)
- **Riesgo de sanción** por incumplimiento

**¿Hay excepciones?** Sí, existen exenciones y regímenes especiales:
- **Economía del Conocimiento (Ley 27.506)**: permite retener hasta el 30% de las divisas sin liquidar
- **Exportaciones de servicios digitales < USD 12.000/año**: régimen simplificado
- **Cobros via MercadoPago que ya se acreditan en ARS**: no hay "ingreso de divisas" real — MP hace la conversión automáticamente

**Punto clave para NV:** Si NV cobra a clientes de Chile/México via MP, los pagos **ya llegan en ARS** (MP convierte). En ese caso, **no hay obligación de liquidar divisas** porque nunca se recibieron dólares — MP liquidó internamente. Esto es lo más probable para NV con MP como procesador.

**Acción concreta:**
1. Consultar con contador/asesor impositivo: "¿Los cobros de suscripciones SaaS a clientes LATAM que se procesan vía MercadoPago y se acreditan en ARS requieren declaración de exportación o liquidación BCRA?"
2. Documentar la respuesta como memo legal
3. Probable resultado: NO aplica si todo se liquida en ARS vía MP

**¿Afecta el código?** No directamente. Es un tema regulatorio/contable.

### 2.3 MercadoPago Cross-border

**¿Qué es?** MP opera como procesador de pagos en cada país de forma independiente (MLA = Argentina, MLC = Chile, MLM = México, etc.). "Cross-border" significa **cobrar a un comprador de un país usando el MP de otro país**.

**Escenarios:**
- Un tenant NV en Chile (MLC) vende a compradores chilenos → todo local, sin cross-border
- NV (empresa en Argentina, MLA) cobra suscripciones a un tenant en Chile → esto ES cross-border

**¿Cómo funciona?** MP tiene un programa de **Cross-border payments** pero:
- Requiere habilitación especial por parte de MP
- El vendedor (NV) debe tener credenciales válidas para operar en el marketplace del comprador
- Las comisiones cross-border son más altas (~5-6% vs ~3.5-4.5% doméstico)
- Los fondos se liquidan en la moneda del vendedor (ARS para NV)

**¿Qué necesita NV?**
- **Para cobro de suscripciones NV (B2B)**: NV cobra a tenants. Si el tenant es de Chile, NV necesita poder crear una preferencia/preapproval en CLP. Opciones:
  - **Opción A**: Cross-border puro (NV cobra desde MLA a MLC) → requiere habilitación
  - **Opción B**: Cada tenant se conecta CON SU PROPIO MP del país → NV cobra vía preapproval con el access_token del tenant (no hay cross-border real)
  - **Opción C**: NV abre entidades MP en cada país (más complejo)
  
  **Opción B es la más viable** y ya está implementada parcialmente: el onboarding ya pide OAuth de MP al tenant. NV usa el `access_token` del tenant para crear preapprovals.

- **Para cobro de tienda (B2C)**: El tenant ya cobra a sus compradores con SU PROPIO MP → no hay cross-border, todo es local.

**Acción concreta:**
1. Validar con MP account manager: "¿Podemos crear preapprovals (suscripciones) usando el access_token de un seller de otro país (ej: CL) desde nuestra plataforma registrada en AR?"
2. Respuesta probable: SÍ, porque NV usa el token del seller (no cobra "como NV" sino "por cuenta del seller")
3. Si la respuesta es NO → evaluar alternativas (Stripe para suscripciones B2B, mantener MP solo para B2C)

**¿Afecta el código?** Solo la validación de `site_id` en OAuth. El sistema ya maneja access_tokens de tenants.

### 2.4 Enterprise a USD 390 (Definitivo)

**Decisión confirmada:** Enterprise queda en **USD 390/mes** (USD 3.900/año con 2 meses gratis). No hay grandfather policy — es el precio definitivo. Los clientes actuales en Enterprise $250 migran al nuevo precio.

**Migración:**
1. UPDATE `plans SET monthly_fee = 390 WHERE plan_key = 'enterprise'`
2. Comunicación a clientes Enterprise existentes con 30 días de aviso
3. La próxima facturación automática ya cobra $390

---

## 3. Investigación FX: Fuentes de Tipo de Cambio

### 3.1 Estado Actual

| Servicio | Archivo | Endpoint | Uso |
|----------|---------|---------|-----|
| **FxService** (global) | `src/common/fx.service.ts` | `dolarapi.com/v1/dolares/blue` | Suscripciones (USD→ARS), dominios, pricing display |
| **DolarBlueService** (aislado) | `src/common/services/dolar-blue.service.ts` | `dolarapi.com/v1/dolares/blue` | Solo SEO AI billing |

**Problema:** Ambos usan dólar **blue** (mercado paralelo). Para facturación fiscal (Factura E), ARCA exige el TC **BNA vendedor divisa** (tipo de cambio oficial del Banco de la Nación Argentina).

### 3.2 Investigación de APIs Disponibles

#### dolarapi.com (API que ya usamos)

La misma API que ya usamos tiene **TODOS los tipos de cambio oficiales**:

| Endpoint | Descripción | Uso recomendado |
|----------|-------------|-----------------|
| `/v1/dolares/blue` | Dólar blue (paralelo) | ❌ NO usar para billing/fiscal |
| **`/v1/dolares/oficial`** | **Dólar oficial BNA** (compra/venta) | ✅ **USAR ESTE para AR — pricing y fiscal** |
| `/v1/dolares/contadoconliqui` | Dólar CCL (financiero) | No aplica |
| `/v1/dolares/mayorista` | Mayorista BCRA | No aplica |
| `/v1/cotizaciones/eur` | Euro BNA | Para futuro si se necesita EUR |
| `/v1/cotizaciones/brl` | Real BNA | Para futuro si se expande a BR |

**Respuesta de `/v1/dolares/oficial`:**
```json
{
  "moneda": "USD",
  "casa": "oficial",
  "nombre": "Oficial",
  "compra": 1050.00,
  "venta": 1090.00,     ← ESTE es "BNA vendedor divisa"
  "fechaActualizacion": "2026-02-21T15:00:00.000Z"
}
```

**Conclusión para Argentina:** Solo hay que cambiar el endpoint de `/blue` a `/oficial` en la misma API. El campo `venta` del oficial **ES** el "BNA vendedor divisa" que pide ARCA. **No se necesita otra API para AR.**

#### BCRA API oficial (alternativa de respaldo)

| Endpoint | Variable | Descripción |
|----------|---------|-------------|
| `api.bcra.gob.ar/estadisticas/v2.0/datosvariable/4` | TC minorista vendedor | Dólar oficial BNA |
| `api.bcra.gob.ar/estadisticas/v2.0/datosvariable/5` | TC mayorista | BCRA |

- **Pro:** Fuente oficial directa del Banco Central
- **Contra:** Requiere certificado de API BCRA (registro previo), rate limit bajo, formato de respuesta diferente
- **Uso recomendado:** Como **fallback** si dolarapi.com cae

#### Para otros países LATAM

MP cobra en moneda local del comprador. Para convertir precios de planes (en USD) a moneda local para display, opciones:

| Opción | API | Costo | Monedas | Fiabilidad |
|--------|-----|-------|---------|-----------|
| **frankfurter.app** | `api.frankfurter.app/latest?from=USD&to=CLP,MXN,COP` | Gratis | 30+ (BCE) | ✅ Buena, daily updates |
| **exchangerate.host** | `api.exchangerate.host/latest?base=USD&symbols=CLP` | Gratis (100 req/mo) | 170+ | ⚠️ Límite bajo |
| **Tasa MP implícita** | No pública / calcular de preferencias | Gratis | Solo MP supported | ⚠️ No determinista |
| **Manual (super admin)** | N/A | Gratis | Cualquiera | ✅ Control total |

### 3.3 Estrategia Propuesta: Dual-Source + Configurable

```
┌─────────────────────────────────────────────────────────────────────┐
│                        FxService v2 (refactored)                     │
│                                                                       │
│  ┌─────────────┐    ┌──────────────┐    ┌───────────────────────┐   │
│  │  Argentina   │    │  Otros LATAM │    │     Config Admin      │   │
│  │  (AR/ARS)    │    │  (CL/MX/CO)  │    │   (Super Admin UI)   │   │
│  │              │    │              │    │                       │   │
│  │ dolarapi.com │    │ frankfurter  │    │ ┌─────────────────┐  │   │
│  │ /oficial     │    │ .app + manual│    │ │ fx_source: auto  │  │   │
│  │              │    │ override     │    │ │ fallback_rate    │  │   │
│  │ Cache: Redis │    │ Cache: Redis │    │ │ cache_ttl_min    │  │   │
│  │ TTL: 15min   │    │ TTL: 1h      │    │ │ manual_override  │  │   │
│  │              │    │              │    │ └─────────────────┘  │   │
│  │ Fallback:    │    │ Fallback:    │    │                       │   │
│  │ BCRA API ──▶ │    │ Manual rate  │    │                       │   │
│  │ Hardcoded    │    │ from admin   │    │                       │   │
│  └─────────────┘    └──────────────┘    └───────────────────────┘   │
│                                                                       │
│  Modo hybrid:                                                         │
│    getRate('AR') → dolarapi oficial → cache → fallback BCRA           │
│    getRate('CL') → frankfurter → cache → fallback manual_rate         │
│    getRate('MX') → frankfurter → cache → fallback manual_rate         │
│                                                                       │
│  Super admin puede:                                                   │
│    - Ver rate actual por país                                         │
│    - Forzar override manual (ej: CLP=950)                            │
│    - Configurar TTL de cache                                          │
│    - Ver historial de rates usados                                    │
│    - Invalidar cache manualmente                                      │
└─────────────────────────────────────────────────────────────────────┘
```

### 3.4 Tabla `fx_rates_config` (nueva, Admin DB)

```sql
CREATE TABLE IF NOT EXISTS fx_rates_config (
  country_id text PRIMARY KEY,            -- AR, CL, MX, CO, UY, PE
  source text NOT NULL DEFAULT 'auto',    -- 'auto' | 'manual'
  auto_endpoint text,                     -- URL del endpoint automático
  auto_field_path text DEFAULT 'venta',   -- path JSON al valor (ej: 'venta', 'rates.CLP')
  manual_rate numeric(12,4),              -- rate manual (si source='manual')
  manual_rate_date date,                  -- fecha del rate manual
  cache_ttl_minutes integer DEFAULT 15,   -- TTL de cache en minutos
  fallback_rate numeric(12,4),            -- rate hardcodeado de emergencia
  last_auto_rate numeric(12,4),           -- último rate obtenido automáticamente
  last_auto_fetch_at timestamptz,         -- timestamp del último fetch
  last_error text,                        -- último error (si hubo)
  updated_by uuid,                        -- super admin que editó
  updated_at timestamptz DEFAULT now()
);

-- Seed inicial
INSERT INTO fx_rates_config VALUES
  ('AR', 'auto', 'https://dolarapi.com/v1/dolares/oficial', 'venta', NULL, NULL, 15, 1200, NULL, NULL, NULL, NULL, now()),
  ('CL', 'auto', 'https://api.frankfurter.app/latest?from=USD&to=CLP', 'rates.CLP', NULL, NULL, 60, 950, NULL, NULL, NULL, NULL, now()),
  ('MX', 'auto', 'https://api.frankfurter.app/latest?from=USD&to=MXN', 'rates.MXN', NULL, NULL, 60, 17.5, NULL, NULL, NULL, NULL, now()),
  ('CO', 'auto', 'https://api.frankfurter.app/latest?from=USD&to=COP', 'rates.COP', NULL, NULL, 60, 4200, NULL, NULL, NULL, NULL, now()),
  ('UY', 'auto', 'https://api.frankfurter.app/latest?from=USD&to=UYU', 'rates.UYU', NULL, NULL, 60, 42, NULL, NULL, NULL, NULL, now()),
  ('PE', 'auto', 'https://api.frankfurter.app/latest?from=USD&to=PEN', 'rates.PEN', NULL, NULL, 60, 3.75, NULL, NULL, NULL, NULL, now())
ON CONFLICT (country_id) DO NOTHING;
```

### 3.5 Refactor de FxService (pseudocódigo)

```typescript
// src/common/fx.service.ts — REFACTORED

@Injectable()
export class FxService {
  constructor(
    @Inject('REDIS_CLIENT') private redis: Redis,
    @Inject('SUPABASE_ADMIN') private adminDb: SupabaseClient,
  ) {}

  /**
   * Obtiene rate USD → moneda local para un país.
   * Estrategia: Cache Redis → API externa → Fallback hardcoded
   */
  async getRate(countryId: string = 'AR'): Promise<FxRateResult> {
    // 1. Leer config de fx_rates_config
    const config = await this.getConfig(countryId);

    // 2. Si source='manual', retornar rate manual
    if (config.source === 'manual' && config.manual_rate) {
      return { rate: config.manual_rate, source: 'manual', date: config.manual_rate_date };
    }

    // 3. Buscar en cache Redis
    const cacheKey = `fx:${countryId}`;
    const cached = await this.redis.get(cacheKey);
    if (cached) return JSON.parse(cached);

    // 4. Fetch automático
    try {
      const rate = await this.fetchFromEndpoint(config.auto_endpoint, config.auto_field_path);
      const result = { rate, source: 'auto', date: new Date().toISOString() };
      
      // Guardar en cache
      await this.redis.setex(cacheKey, config.cache_ttl_minutes * 60, JSON.stringify(result));
      
      // Actualizar last_auto_rate
      await this.adminDb.from('fx_rates_config')
        .update({ last_auto_rate: rate, last_auto_fetch_at: new Date(), last_error: null })
        .eq('country_id', countryId);
      
      return result;
    } catch (error) {
      // 5. Fallback: rate hardcodeado
      this.logger.error(`FX fetch failed for ${countryId}: ${error.message}`);
      await this.adminDb.from('fx_rates_config')
        .update({ last_error: error.message })
        .eq('country_id', countryId);
      return { rate: config.fallback_rate, source: 'fallback', date: null };
    }
  }

  /** Backward compat — migración gradual */
  async getBlueDollarRate(): Promise<number> {
    const result = await this.getRate('AR');
    return result.rate;
  }

  /** Convertir USD a moneda local del país */
  async convertUsdToLocal(usdAmount: number, countryId: string): Promise<number> {
    const { rate } = await this.getRate(countryId);
    return usdAmount * rate;
  }
}
```

### 3.6 Plan de Migración FxService

1. **Crear `fx_rates_config`** tabla + seed
2. **Refactorear `FxService`** con la estrategia dual + cache Redis
3. **Mantener `getBlueDollarRate()`** como wrapper que ahora llama a `getRate('AR')` con el endpoint **oficial** (no blue)
4. **Eliminar `DolarBlueService`** — consolidar todo en `FxService` refactoreado
5. **Los 3 consumidores actuales** (`subscriptions.service.ts`, `managed-domain.service.ts`, `seo-ai-purchase.service.ts`) siguen llamando a `getBlueDollarRate()` sin cambios — solo cambia internamente de blue a oficial
6. **Agregar endpoint admin** `GET /admin/fx/rates` y `PATCH /admin/fx/rates/:countryId` para configurar desde super admin

---

## 4. Comisión por Ventas (GMV): Diseño Completo

### 4.1 Concepto

Ciertos planes incluyen un **umbral de volumen de ventas (GMV = Gross Merchandise Value)** mensual. Si el tenant supera ese umbral, NV cobra un % sobre el excedente.

| Plan | Umbral GMV (USD/mes) | Comisión sobre excedente |
|------|---------------------|-------------------------|
| Starter | $5.000 | 0% (no aplica comisión) |
| Growth | $40.000 | 2% sobre lo que exceda $40k |
| Enterprise | Negociable | Negociable |

**Ejemplo Growth:** Si un tenant Growth vende $55.000 USD en un mes:
- Excedente = $55.000 - $40.000 = $15.000
- Comisión = $15.000 × 2% = **$300 USD** adicionales al plan

### 4.2 Pipeline de Datos (End-to-End)

```
┌─ Backend DB ──────────────────────────────────────────────────────┐
│                                                                    │
│  1. Cada orden pagada genera un registro en usage_ledger           │
│     metric='order', quantity=1, plus order total in orders.total   │
│                                                                    │
│  2. Cron existente agrega → usage_hourly → usage_daily             │
│     (ya funciona para pedidos, pero NO guarda GMV aún)             │
│                                                                    │
│  ⚠️ NUEVO: Agregar campo 'amount' a usage_ledger para órdenes     │
│     O crear metric='gmv' con quantity=total_order_amount           │
│                                                                    │
└────────────────────────────┬───────────────────────────────────────┘
                             │
                             │ Cron diario 3:00 AM
                             │ (nuevo: UsageConsolidationCron)
                             ▼
┌─ Admin DB ────────────────────────────────────────────────────────┐
│                                                                    │
│  3. usage_rollups_monthly (nueva tabla)                            │
│     - orders_confirmed: count de órdenes del mes                   │
│     - orders_gmv_usd: SUM(orders.total) convertido a USD          │
│     - api_calls, egress_gb, storage_gb_avg, etc.                   │
│                                                                    │
│  4. Cron día 1 o 2 del mes siguiente (GmvCommissionCron)          │
│     → Lee usage_rollups_monthly del mes cerrado                    │
│     → Lee plans (gmv_threshold_usd, gmv_commission_pct)            │
│     → Calcula comisión si GMV > threshold                          │
│     → Inserta en billing_adjustments type='gmv_commission'         │
│                                                                    │
│  5. billing_adjustments                                            │
│     - tenant_id, period_start, type='gmv_commission'               │
│     - resource='gmv_excess', quantity=excess_usd                   │
│     - unit_price=commission_pct, amount_usd=comisión               │
│     - status='pending' → 'charged' (al cobrarse)                  │
│                                                                    │
│  6. Auto-charge:                                                   │
│     Si subscription.auto_charge=true:                              │
│       → Crear preferencia MP por el monto de billing_adjustments   │
│       → Webhook confirma → status='charged'                        │
│     Si auto_charge=false:                                          │
│       → Queda pending, super admin puede:                          │
│         - Cobrar manualmente                                       │
│         - Marcar como waived (exentar)                             │
│         - Enviar recordatorio al tenant                            │
│                                                                    │
└────────────────────────────────────────────────────────────────────┘
```

### 4.3 Modificaciones al Pipeline de Métricas Existente

**Archivo: `src/metrics/usage-recorder.service.ts`** — Actualmente registra metric `'order'` con `quantity=1`. Necesita también registrar el monto:

```typescript
// NUEVO: Agregar metric gmv cuando se confirma un pago
async recordOrderGmv(clientId: string, orderId: string, totalAmount: number, currency: string) {
  // Convertir a USD si no es USD
  let amountUsd = totalAmount;
  if (currency !== 'USD') {
    const fx = await this.fxService.getRate(this.getCountryFromCurrency(currency));
    amountUsd = totalAmount / fx.rate; // moneda local / rate = USD
  }
  
  this.buffer.push({
    client_id: clientId,
    metric: 'gmv',
    quantity: amountUsd,  // en USD
    path: `/orders/${orderId}`,
    method: 'PAYMENT_CONFIRMED',
  });
}
```

**Punto de integración:** En el webhook de MP (`confirmPayment()` en `tenant-payments/mercadopago.controller.ts`), después de marcar la orden como `paid`, llamar a `usageRecorder.recordOrderGmv()`.

### 4.4 Cron: UsageConsolidationCron (Nuevo)

```typescript
// src/billing/usage-consolidation.cron.ts — NUEVO

@Injectable()
export class UsageConsolidationCron {
  // Se ejecuta a las 3:00 AM todos los días
  @Cron('0 3 * * *')
  async consolidateDailyUsage() {
    const yesterday = startOfYesterday();
    
    // Para cada tenant activo:
    const tenants = await this.adminDb.from('nv_accounts')
      .select('id, plan_key')
      .eq('is_active', true);

    for (const tenant of tenants.data) {
      // Leer métricas del día de usage_daily (Backend DB)
      const daily = await this.backendDb.from('usage_daily')
        .select('*')
        .eq('client_id', tenant.id)
        .eq('bucket_date', format(yesterday, 'yyyy-MM-dd'));
      
      // Upsert en usage_rollups_monthly (Admin DB)
      const periodStart = startOfMonth(yesterday);
      await this.adminDb.from('usage_rollups_monthly')
        .upsert({
          tenant_id: tenant.id,
          period_start: periodStart,
          api_calls: incrementar,
          egress_gb: incrementar,
          orders_confirmed: incrementar,
          orders_gmv_usd: incrementar,  // ← GMV acumulado
          storage_gb_avg: recalcular_promedio,
          updated_at: new Date(),
        }, { onConflict: 'tenant_id,period_start' });
    }
  }
}
```

### 4.5 Cron: GmvCommissionCron (Nuevo)

```typescript
// src/billing/gmv-commission.cron.ts — NUEVO

@Injectable()
export class GmvCommissionCron {
  // Se ejecuta el día 2 de cada mes a las 6:00 AM
  @Cron('0 6 2 * *')
  async calculateMonthlyCommissions() {
    const lastMonth = subMonths(new Date(), 1);
    const periodStart = startOfMonth(lastMonth);
    
    // Obtener todos los tenants con su plan
    const tenants = await this.adminDb
      .from('nv_accounts')
      .select('id, plan_key')
      .eq('is_active', true);

    for (const tenant of tenants.data) {
      // Obtener límites del plan
      const plan = await this.adminDb.from('plans')
        .select('gmv_threshold_usd, gmv_commission_pct')
        .eq('plan_key', tenant.plan_key)
        .single();

      // Si no tiene comisión configurada, skip
      if (!plan.data?.gmv_threshold_usd || !plan.data?.gmv_commission_pct) continue;

      // Obtener GMV del mes
      const usage = await this.adminDb.from('usage_rollups_monthly')
        .select('orders_gmv_usd')
        .eq('tenant_id', tenant.id)
        .eq('period_start', periodStart)
        .single();

      const gmv = usage.data?.orders_gmv_usd || 0;
      const threshold = plan.data.gmv_threshold_usd;
      const commissionPct = plan.data.gmv_commission_pct;

      // Calcular excedente
      if (gmv > threshold) {
        const excess = gmv - threshold;
        const commission = excess * commissionPct;

        // Verificar idempotencia (no duplicar)
        const existing = await this.adminDb.from('billing_adjustments')
          .select('id')
          .eq('tenant_id', tenant.id)
          .eq('period_start', periodStart)
          .eq('type', 'gmv_commission')
          .maybeSingle();

        if (!existing.data) {
          await this.adminDb.from('billing_adjustments').insert({
            tenant_id: tenant.id,
            period_start: periodStart,
            type: 'gmv_commission',
            resource: 'gmv_excess',
            quantity: excess,
            unit_price_usd: commissionPct,
            amount_usd: commission,
            status: 'pending',
            notes: `GMV ${gmv.toFixed(2)} USD, threshold ${threshold} USD, excess ${excess.toFixed(2)} USD × ${(commissionPct * 100).toFixed(1)}%`,
          });

          this.logger.log(`Commission created for tenant ${tenant.id}: $${commission.toFixed(2)} USD`);
        }
      }
    }
  }
}
```

### 4.6 Flujo Visual Completo

```
Comprador paga orden
        │
        ▼
  Webhook MP confirma pago
        │
        ├──▶ Actualiza orders.status = 'paid'
        ├──▶ usageRecorder.record('order', 1)     ← ya existe
        └──▶ usageRecorder.recordOrderGmv(total)  ← NUEVO
                │
                ▼
          usage_ledger
          (metric='gmv', quantity=total_usd)
                │
  ──────────────│────────── 3:00 AM diario
                ▼
        UsageConsolidationCron
                │
                ▼
        usage_rollups_monthly
        (orders_gmv_usd += daily_gmv)
                │
  ──────────────│────────── Día 2, 6:00 AM
                ▼
        GmvCommissionCron
        gmv > threshold ? → billing_adjustments
                │
                ├── auto_charge=true → Crear preferencia MP → Cobrar
                └── auto_charge=false → Queda pending en dashboard admin
```

---

## 5. Super Admin Dashboard: Configuración Centralizada

### 5.1 Vista Actual del Dashboard

El super admin ya tiene estas secciones (32 páginas):

| Categoría | Vistas existentes |
|-----------|-------------------|
| **Métricas** | DashboardHome, MetricsView, UsageView, FinanceView |
| **Clientes** | ClientsView, LeadsView, NewClientPage, PendingApprovalsView, PendingCompletionsView, ClientDetails |
| **Billing** | PlansView, RenewalCenterView, BillingView, CouponsView, StoreCouponsView, SeoAiPricingView, SubscriptionEventsView |
| **Operaciones** | OptionSetsView, PlaybookView, InboxView, EmailsJobsView, ShippingView, SeoView, SupportConsoleView |
| **Infra** | BackendClustersView, DesignSystemView, DevPortalWhitelistView |

### 5.2 Nuevas Vistas/Secciones a Agregar

#### 5.2.1 `/dashboard/fx-rates` — Configuración de Tipos de Cambio

**Ruta:** `dashboard/fx-rates` (superOnly)  
**Componente:** `FxRatesView.jsx`  
**Categoría sidebar:** Facturación y Planes

| Feature | Descripción |
|---------|-------------|
| **Tabla de rates por país** | Muestra: país, source (auto/manual), rate actual, última actualización, último error |
| **Editar rate manual** | Click en un país → modal para ingresar rate manual + fecha |
| **Toggle auto/manual** | Switch para cambiar entre fuente automática o manual |
| **Config TTL cache** | Input numérico para minutos de cache |
| **Botón "Refrescar rate"** | Fuerza un fetch inmediato (invalida cache) |
| **Historial** | Mini tabla con últimos 10 rates usados por país |

**API endpoints necesarios:**
- `GET /admin/fx/rates` → Lista todos los países con su config y rate actual
- `PATCH /admin/fx/rates/:countryId` → Actualiza config (source, manual_rate, cache_ttl)
- `POST /admin/fx/rates/:countryId/refresh` → Fuerza refresh del rate

#### 5.2.2 `/dashboard/country-configs` — Configuración por País

**Ruta:** `dashboard/country-configs` (superOnly)  
**Componente:** `CountryConfigsView.jsx`  
**Categoría sidebar:** Infraestructura y Config

| Feature | Descripción |
|---------|-------------|
| **Tabla de países** | site_id, country_id, currency, locale, timezone, VAT rate, activo/inactivo |
| **Toggle país activo** | Habilitar/deshabilitar un país (feature flag) |
| **Editar config** | Modal con todos los campos editables |
| **Agregar país** | Botón para agregar nuevo país |

**API endpoints:**
- `GET /admin/country-configs` → Lista todos
- `PATCH /admin/country-configs/:siteId` → Actualiza config
- `POST /admin/country-configs` → Crea nuevo país

#### 5.2.3 `/dashboard/gmv-commissions` — Comisiones por GMV

**Ruta:** `dashboard/gmv-commissions` (superOnly)  
**Componente:** `GmvCommissionsView.jsx`  
**Categoría sidebar:** Facturación y Planes

| Feature | Descripción |
|---------|-------------|
| **Resumen del mes** | Cards: total comisiones pendientes, total cobradas, total waived |
| **Tabla de ajustes** | Lista de billing_adjustments type='gmv_commission': tenant, período, GMV, excedente, comisión, status |
| **Filtros** | Por período, por plan, por status (pending/charged/waived) |
| **Acciones por fila** | Cobrar (crear preferencia MP), Waive (exentar), Enviar reminder |
| **Bulk actions** | "Cobrar todos los pending", "Exportar CSV" |

**API endpoints:**
- `GET /admin/billing/gmv-commissions?period=&status=` → Lista billing_adjustments filtrados
- `POST /admin/billing/gmv-commissions/:id/charge` → Cobrar un ajuste
- `POST /admin/billing/gmv-commissions/:id/waive` → Marcar como exento
- `POST /admin/billing/gmv-commissions/bulk-charge` → Cobrar todos los pending

#### 5.2.4 `/dashboard/quotas` — Quotas y Enforcement

**Ruta:** `dashboard/quotas` (superOnly)  
**Componente:** `QuotasView.jsx`  
**Categoría sidebar:** Métricas y Finanzas

| Feature | Descripción |
|---------|-------------|
| **Vista global** | Tabla de todos los tenants con: plan, estado quota (active/warn/soft_limit/etc.), métrica más alta, % uso |
| **Filtros** | Por plan, por estado, por métrica |
| **Detalle por tenant** | Click → ver desglose de cada recurso (orders, API calls, storage, egress, GMV) con barras de progreso |
| **Override manual** | Botón para cambiar estado de quota de un tenant (ej: extender grace) |
| **Alertas** | Badge rojo en sidebar si hay tenants en soft_limit o superior |

**API endpoints:**
- `GET /admin/quotas` → Lista todos los quota_state con datos de uso
- `GET /admin/quotas/:tenantId` → Detalle de un tenant
- `PATCH /admin/quotas/:tenantId` → Override manual de estado
- `POST /admin/quotas/:tenantId/extend-grace` → Extender período de gracia

#### 5.2.5 `/dashboard/plans` — Extensión del PlansView existente

**Ya existe** `PlansView.jsx` — agregar:

| Feature | Descripción |
|---------|-------------|
| **Columnas nuevas en tabla** | Mostrar: RPS, burst, max stores, GMV threshold, commission %, overages |
| **Editar plan** | Modal `PlanEditorModal` extendido con nuevos campos (rate limits, GMV config, overage toggles) |
| **Preview de pricing** | Mostrar cómo se ve el plan para el tenant (con conversión FX) |

#### 5.2.6 `/dashboard/fee-schedules` — Comisiones MP por País

**Ruta:** `dashboard/fee-schedules` (superOnly)  
**Componente:** `FeeSchedulesView.jsx`  
**Categoría sidebar:** Facturación y Planes

| Feature | Descripción |
|---------|-------------|
| **Tabla por país** | Lista fee_schedules agrupados por country_id |
| **Detalle** | Click → ver fee_schedule_lines (método de pago, cuotas, % comisión, fee fijo, settlement days) |  
| **Editar** | CRUD completo de líneas de comisión |
| **Vigencia** | valid_from / valid_to para manejar cambios de tarifas MP |

**API endpoints:**
- `GET /admin/fee-schedules` → Lista todos los schedules
- `GET /admin/fee-schedules/:id` → Detalle con lines
- `POST /admin/fee-schedules` → Crear schedule + lines
- `PATCH /admin/fee-schedules/:id` → Actualizar
- `DELETE /admin/fee-schedules/:id` → Eliminar

#### 5.2.7 Extensión de `/client/:clientId` — Detalle del Cliente

En `ClientDetails.jsx`, agregar tabs/secciones:

| Tab nuevo | Contenido |
|-----------|-----------|
| **Quotas** | Barras de progreso por recurso, estado de enforcement, acciones manuales |
| **Billing Adjustments** | Lista de overages y comisiones del tenant |
| **FX History** | Rates usados para este tenant (por su country_id) |
| **Usage Monthly** | Gráfico de uso mensual (ya parcialmente existe en UsageView) |

### 5.3 Sidebar Actualizado (propuesta)

```
─────── Métricas y Finanzas ───────
Dashboard
Métricas
Finanzas
Uso
🆕 Quotas

─────── Clientes y Ventas ───────
Clientes (superOnly)
Leads
Nuevo Cliente
Aprobaciones Pendientes
Completimientos Pendientes

─────── Facturación y Planes ───────
Planes                          ← extendido
Renovaciones
Billing (superOnly)
🆕 Comisiones GMV (superOnly)
🆕 Fee Schedules (superOnly)
Cupones
Cupones Tienda (superOnly)
SEO AI Pricing (superOnly)
Eventos de Suscripción

─────── Operaciones ───────
Option Sets (superOnly)
Playbook
Inbox
Emails (superOnly)
Envíos (superOnly)
SEO (superOnly)
Soporte (superOnly)

─────── Config e Infraestructura ───────
Backend Clusters (superOnly)
🆕 Tipos de Cambio (superOnly)
🆕 Config por País (superOnly)
Design System
Dev Whitelist (superOnly)
```

---

## 6. Mapeo de Tablas: Propuestas vs. Existentes

### 🔴 CRÍTICO: Tablas que el plan propone PERO YA EXISTEN

| Tabla propuesta | Tabla EXISTENTE | DB | Acción |
|----------------|----------------|-----|--------|
| `plan_catalog` | **`plans`** | Admin | ⚠️ **NO crear**. Extender `plans` con columnas nuevas |
| `tenant_subscription` | **`subscriptions`** | Admin | ⚠️ **NO crear**. Agregar `auto_charge` |
| `usage_rollups_hourly` | **`usage_hourly`** + **`usage_daily`** | Backend | ⚠️ **Reusar** para alimentar rollup mensual |

### ✅ Tablas 100% nuevas a crear

| Tabla | DB | FK | Notas |
|-------|-----|-----|-------|
| `country_configs` | Admin | PK: site_id | Config por país |
| `fx_rates_config` | Admin | PK: country_id | Config FX por país (NUEVA) |
| `fee_schedules` + `fee_schedule_lines` | Admin | fee_schedules.country_id | Fees MP |
| `quota_state` | Admin | nv_accounts(id) | Enforcement |
| `usage_rollups_monthly` | Admin | nv_accounts(id) | Consolidación mensual |
| `billing_adjustments` | Admin | nv_accounts(id) | Overages + comisiones GMV |
| `nv_invoices` | Admin | nv_accounts(id) | Facturas E |
| `cost_rollups_monthly` | Admin | nv_accounts(id) | COGS |

### ⚠️ Tablas existentes a modificar (ALTER)

| Tabla | DB | Columnas a agregar |
|-------|-----|-------------------|
| `plans` | Admin | rps_sustained, rps_burst, max_concurrency, max_active_stores, grace_days, overage_allowed, overage_max_percent, gmv_threshold_usd, gmv_commission_pct |
| `subscriptions` | Admin | auto_charge, payment_method_ref |
| `nv_accounts` | Admin | mp_site_id, country, currency, seller_fiscal_id, seller_fiscal_name, seller_fiscal_address, seller_b2b_declared, signup_ip, tos_version, tos_accepted_at |
| `clients` | Backend | country, locale, timezone |
| `orders` | Backend | currency, exchange_rate, exchange_rate_date, total_ars |

---

## 7. DB Schema: Migraciones Completas (SQL Final)

Todas las migraciones con SQL ejecutable. Números asignados a partir de la secuencia actual:
- **Admin DB:** último = ADMIN_063 → nuevas desde ADMIN_064
- **Backend DB:** último = BACKEND_044 → nuevas desde BACKEND_045

> ⚠️ **Reconciliación SQL vs tablas existentes:** El input del TL propone `plan_catalog`, `tenant_subscription` y `usage_rollups_hourly` como tablas nuevas. **No se crean** porque `plans`, `subscriptions` y `usage_hourly`/`usage_daily` ya existen en producción (ver §6). La funcionalidad equivalente se logra con ALTER de las tablas existentes.

### 7.1 — ADMIN_064: `country_configs` + seed

```sql
-- ADMIN_064: Configuración de países/monedas
CREATE TABLE IF NOT EXISTS country_configs (
  site_id TEXT PRIMARY KEY,            -- MLA, MLC, MLM, MCO, MLU, MPE
  country_id TEXT NOT NULL,            -- AR, CL, MX, CO, UY, PE
  currency_id TEXT NOT NULL,           -- ARS, CLP, MXN, COP, UYU, PEN
  locale TEXT NOT NULL,                -- es-AR, es-CL, ...
  timezone TEXT NOT NULL,              -- America/Argentina/Buenos_Aires, ...
  decimals SMALLINT NOT NULL,          -- 2 para ARS/MXN, 0 para CLP/COP
  arca_cuit_pais TEXT,                 -- CUIT fiscal del país ante ARCA (solo para Factura E)
  vat_digital_rate NUMERIC(5,2) NOT NULL, -- IVA digital del país
  active BOOLEAN NOT NULL DEFAULT true,
  created_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO country_configs VALUES
  ('MLA','AR','ARS','es-AR','America/Argentina/Buenos_Aires',2,'50000000016',0.21,true,now()),
  ('MLC','CL','CLP','es-CL','America/Santiago',0,'55000002206',0.19,true,now()),
  ('MLM','MX','MXN','es-MX','America/Mexico_City',2,'55000002338',0.16,true,now()),
  ('MCO','CO','COP','es-CO','America/Bogota',0,'55000002168',0.19,true,now()),
  ('MLU','UY','UYU','es-UY','America/Montevideo',2,'55000002842',0.22,true,now()),
  ('MPE','PE','PEN','es-PE','America/Lima',2,'55000002604',0.18,true,now())
ON CONFLICT (site_id) DO NOTHING;
```

### 7.2 — ADMIN_065: `fx_rates_config` + seed

```sql
-- ADMIN_065: Configuración de tipos de cambio por país
CREATE TABLE IF NOT EXISTS fx_rates_config (
  country_id TEXT PRIMARY KEY,
  source TEXT NOT NULL DEFAULT 'auto',     -- 'auto' | 'manual'
  auto_endpoint TEXT,
  auto_field_path TEXT DEFAULT 'venta',    -- path JSON al valor
  manual_rate NUMERIC(12,4),
  manual_rate_date DATE,
  cache_ttl_minutes INTEGER DEFAULT 15,
  fallback_rate NUMERIC(12,4),
  last_auto_rate NUMERIC(12,4),
  last_auto_fetch_at TIMESTAMPTZ,
  last_error TEXT,
  updated_by UUID,
  updated_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO fx_rates_config VALUES
  ('AR','auto','https://dolarapi.com/v1/dolares/oficial','venta',NULL,NULL,15,1200,NULL,NULL,NULL,NULL,now()),
  ('CL','auto','https://api.frankfurter.app/latest?from=USD&to=CLP','rates.CLP',NULL,NULL,60,950,NULL,NULL,NULL,NULL,now()),
  ('MX','auto','https://api.frankfurter.app/latest?from=USD&to=MXN','rates.MXN',NULL,NULL,60,17.5,NULL,NULL,NULL,NULL,now()),
  ('CO','auto','https://api.frankfurter.app/latest?from=USD&to=COP','rates.COP',NULL,NULL,60,4200,NULL,NULL,NULL,NULL,now()),
  ('UY','auto','https://api.frankfurter.app/latest?from=USD&to=UYU','rates.UYU',NULL,NULL,60,42,NULL,NULL,NULL,NULL,now()),
  ('PE','auto','https://api.frankfurter.app/latest?from=USD&to=PEN','rates.PEN',NULL,NULL,60,3.75,NULL,NULL,NULL,NULL,now())
ON CONFLICT (country_id) DO NOTHING;
```

### 7.3 — ADMIN_066: ALTER `plans` (rate limits + GMV + overages)

```sql
-- ADMIN_066: Extender plans con enforcement, GMV y rate limits
ALTER TABLE plans
  ADD COLUMN IF NOT EXISTS max_active_stores INTEGER NOT NULL DEFAULT 1,
  ADD COLUMN IF NOT EXISTS rps_sustained INTEGER NOT NULL DEFAULT 5,
  ADD COLUMN IF NOT EXISTS rps_burst INTEGER NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS max_concurrency INTEGER NOT NULL DEFAULT 15,
  ADD COLUMN IF NOT EXISTS overage_allowed BOOLEAN NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS overage_max_percent INTEGER,
  ADD COLUMN IF NOT EXISTS grace_days INTEGER NOT NULL DEFAULT 7,
  ADD COLUMN IF NOT EXISTS gmv_threshold_usd NUMERIC(12,2),
  ADD COLUMN IF NOT EXISTS gmv_commission_pct NUMERIC(5,4);

-- Seeds definitivos (alineados con plan_catalog del TL)
UPDATE plans SET
  max_active_stores=1, rps_sustained=5, rps_burst=15, max_concurrency=15,
  overage_allowed=false, grace_days=7,
  included_orders=150, included_requests=100000, included_bandwidth_gb=5, included_storage_gb=1,
  gmv_threshold_usd=5000, gmv_commission_pct=0
WHERE plan_key = 'starter';

UPDATE plans SET
  max_active_stores=3, rps_sustained=15, rps_burst=45, max_concurrency=60,
  overage_allowed=true, overage_max_percent=150, grace_days=14,
  included_orders=1000, included_requests=800000, included_bandwidth_gb=40, included_storage_gb=10,
  gmv_threshold_usd=40000, gmv_commission_pct=0.02
WHERE plan_key = 'growth';

UPDATE plans SET
  monthly_fee=390, max_active_stores=10, rps_sustained=60, rps_burst=180,
  max_concurrency=180, overage_allowed=true, overage_max_percent=200, grace_days=30,
  included_orders=5000, included_requests=3000000, included_bandwidth_gb=200, included_storage_gb=50,
  gmv_threshold_usd=NULL, gmv_commission_pct=NULL
WHERE plan_key = 'enterprise';

UPDATE plans SET monthly_fee = 390 * 10
WHERE plan_key = 'enterprise_annual';
```

### 7.4 — ADMIN_067: ALTER `nv_accounts` (i18n + fiscal)

```sql
-- ADMIN_067: Extender nv_accounts con datos del seller
ALTER TABLE nv_accounts
  ADD COLUMN IF NOT EXISTS mp_site_id TEXT,
  ADD COLUMN IF NOT EXISTS country TEXT,
  ADD COLUMN IF NOT EXISTS currency TEXT,
  ADD COLUMN IF NOT EXISTS seller_fiscal_id TEXT,
  ADD COLUMN IF NOT EXISTS seller_fiscal_name TEXT,
  ADD COLUMN IF NOT EXISTS seller_fiscal_address TEXT,
  ADD COLUMN IF NOT EXISTS seller_b2b_declared BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS signup_ip INET,
  ADD COLUMN IF NOT EXISTS tos_version TEXT,
  ADD COLUMN IF NOT EXISTS tos_accepted_at TIMESTAMPTZ;

CREATE INDEX IF NOT EXISTS idx_nv_accounts_country ON nv_accounts(country);
```

### 7.5 — ADMIN_068: ALTER `subscriptions` (auto_charge)

```sql
-- ADMIN_068: Agregar auto_charge a subscriptions existente
-- NOTA: NO crear tenant_subscription — reusar tabla existente
ALTER TABLE subscriptions
  ADD COLUMN IF NOT EXISTS auto_charge BOOLEAN DEFAULT false,
  ADD COLUMN IF NOT EXISTS payment_method_ref TEXT;
```

### 7.6 — ADMIN_069: `quota_state`

```sql
-- ADMIN_069: Estado de cuota por tenant
CREATE TABLE IF NOT EXISTS quota_state (
  tenant_id UUID PRIMARY KEY REFERENCES nv_accounts(id),
  state TEXT NOT NULL DEFAULT 'ACTIVE',
  grace_until TIMESTAMPTZ,
  last_evaluated_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ DEFAULT now()
);
-- States: ACTIVE, WARN_50, WARN_75, WARN_90, SOFT_LIMIT, GRACE, HARD_LIMIT
```

### 7.7 — ADMIN_070: `usage_rollups_monthly`

```sql
-- ADMIN_070: Consolidación mensual de uso
-- NOTA: NO crear usage_rollups_hourly — reusar usage_hourly/usage_daily existentes en Backend DB
CREATE TABLE IF NOT EXISTS usage_rollups_monthly (
  tenant_id UUID NOT NULL REFERENCES nv_accounts(id),
  period_start DATE NOT NULL,
  orders_confirmed INTEGER DEFAULT 0,
  orders_gmv_usd NUMERIC(14,2) DEFAULT 0,
  api_calls BIGINT DEFAULT 0,
  egress_gb NUMERIC(10,4) DEFAULT 0,
  storage_gb_avg NUMERIC(10,4) DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (tenant_id, period_start)
);
```

### 7.8 — ADMIN_071: `billing_adjustments`

```sql
-- ADMIN_071: Overages y comisiones GMV
CREATE TABLE IF NOT EXISTS billing_adjustments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID NOT NULL REFERENCES nv_accounts(id),
  period_start DATE NOT NULL,
  type TEXT NOT NULL,                   -- 'gmv_commission', 'overage_orders', 'overage_egress'
  resource TEXT NOT NULL,               -- 'gmv_excess', 'orders', 'egress_gb'
  quantity NUMERIC(14,4) NOT NULL,
  unit_price_usd NUMERIC(10,6) NOT NULL,
  amount_usd NUMERIC(12,2) NOT NULL,
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'charged', 'waived', 'failed'
  mp_preference_id TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  charged_at TIMESTAMPTZ
);
CREATE INDEX IF NOT EXISTS idx_billing_adj_tenant ON billing_adjustments(tenant_id, period_start);
CREATE INDEX IF NOT EXISTS idx_billing_adj_status ON billing_adjustments(status);
```

### 7.9 — ADMIN_072: `nv_invoices` (Factura E)

```sql
-- ADMIN_072: Facturas de exportación NovaVision
CREATE TABLE IF NOT EXISTS nv_invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id UUID REFERENCES nv_accounts(id),
  invoice_type CHAR(1) DEFAULT 'E',     -- 'E' = exportación, 'C' = monotributo
  punto_venta INTEGER,                  -- PV de ARCA (configurable desde super admin)
  numero BIGINT,                        -- Número de comprobante
  cae TEXT,                             -- Código Autorización Electrónico
  cae_vencimiento DATE,
  receptor_nombre TEXT,
  receptor_pais TEXT,
  receptor_id_fiscal TEXT,
  currency TEXT NOT NULL,               -- USD, ARS
  subtotal NUMERIC(12,2),
  iva NUMERIC(12,2) DEFAULT 0,
  total NUMERIC(12,2),
  exchange_rate NUMERIC(12,4),          -- TC BNA del día
  exchange_rate_date DATE,
  total_ars NUMERIC(12,2),              -- total convertido
  related_period TEXT,                  -- '2026-02'
  related_orders UUID[],                -- IDs de orders facturadas
  status TEXT DEFAULT 'draft',          -- 'draft', 'issued', 'cancelled', 'voided'
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_nv_invoices_tenant ON nv_invoices(tenant_id);
CREATE INDEX IF NOT EXISTS idx_nv_invoices_status ON nv_invoices(status);
```

### 7.10 — ADMIN_073: `fee_schedules` + `fee_schedule_lines`

```sql
-- ADMIN_073: Comisiones MP por país
CREATE TABLE IF NOT EXISTS fee_schedules (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  country_id TEXT NOT NULL,
  currency_id TEXT NOT NULL,
  valid_from DATE NOT NULL,
  valid_to DATE,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE TABLE IF NOT EXISTS fee_schedule_lines (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id UUID NOT NULL REFERENCES fee_schedules(id) ON DELETE CASCADE,
  payment_method TEXT NOT NULL,
  installments_from INTEGER NOT NULL DEFAULT 1,
  installments_to INTEGER NOT NULL DEFAULT 1,
  settlement_days INTEGER NOT NULL,
  percent_fee NUMERIC(5,4) NOT NULL,
  fixed_fee NUMERIC(12,2) NOT NULL DEFAULT 0,
  UNIQUE(schedule_id, payment_method, installments_from, installments_to, settlement_days)
);
```

### 7.11 — ADMIN_074: `cost_rollups_monthly`

```sql
-- ADMIN_074: COGS por tenant
CREATE TABLE IF NOT EXISTS cost_rollups_monthly (
  tenant_id UUID NOT NULL REFERENCES nv_accounts(id),
  period_start DATE NOT NULL,
  cpu_cost_usd NUMERIC(10,4) DEFAULT 0,
  ram_cost_usd NUMERIC(10,4) DEFAULT 0,
  egress_cost_usd NUMERIC(10,4) DEFAULT 0,
  storage_cost_usd NUMERIC(10,4) DEFAULT 0,
  mp_fee_cost_usd NUMERIC(10,4) DEFAULT 0,
  total_cost_usd NUMERIC(12,4) DEFAULT 0,
  updated_at TIMESTAMPTZ DEFAULT now(),
  PRIMARY KEY (tenant_id, period_start)
);
```

### 7.12 — BACKEND_045: ALTER `clients` (country/locale/tz)

```sql
-- BACKEND_045: Agregar i18n al tenant en Backend DB
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS country TEXT,
  ADD COLUMN IF NOT EXISTS locale TEXT,
  ADD COLUMN IF NOT EXISTS timezone TEXT;

CREATE INDEX IF NOT EXISTS idx_clients_country ON clients(country);
```

### 7.13 — BACKEND_046: ALTER `orders` (currency/exchange_rate)

```sql
-- BACKEND_046: Conciliación multi-moneda en orders
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS currency TEXT DEFAULT 'ARS',
  ADD COLUMN IF NOT EXISTS exchange_rate NUMERIC(12,4),
  ADD COLUMN IF NOT EXISTS exchange_rate_date DATE,
  ADD COLUMN IF NOT EXISTS total_ars NUMERIC(12,2);
```

### 7.14 — Backfill one-time (post migraciones)

```sql
-- Backfill nv_accounts: copiar datos existentes
UPDATE nv_accounts SET
  mp_site_id = 'MLA',
  country = 'AR',
  currency = 'ARS'
WHERE country IS NULL;

-- Backfill clients en Backend DB
UPDATE clients SET
  country = 'AR',
  locale = 'es-AR',
  timezone = 'America/Argentina/Buenos_Aires'
WHERE country IS NULL;
```

### 7.15 — Tabla de Reconciliación (SQL del TL vs. implementación real)

| SQL propuesto por TL | Implementación real | Motivo |
|---------------------|--------------------|---------|
| `CREATE TABLE plan_catalog (...)` | **ALTER TABLE `plans`** (§7.3) | `plans` ya existe con 6 plan_keys, lifecycle y seeds. Se extiende con columnas nuevas |
| `CREATE TABLE tenant_subscription (...)` | **ALTER TABLE `subscriptions`** (§7.5) | `subscriptions` ya existe con lifecycle completo (3600 líneas de servicio). Se agrega `auto_charge` |
| `CREATE TABLE usage_rollups_hourly (...)` | **Reusar `usage_hourly` + `usage_daily`** existentes (Backend DB) | Ya recopilan métricas. El nuevo cron consolida a `usage_rollups_monthly` (Admin DB) |
| `CREATE TABLE quota_state (FK → clients)` | `quota_state` (FK → **`nv_accounts`**) (§7.6) | `nv_accounts` es la SoT de tenants en Admin DB, no `clients` (que es Backend DB) |
| `CREATE TABLE country_configs` | ✅ Se crea igual (§7.1) | — |
| `CREATE TABLE fee_schedules/lines` | ✅ Se crea igual (§7.10) | — |
| `CREATE TABLE nv_invoices` | ✅ Se crea igual, extendida (§7.9) | Se agregaron campos: `status`, `related_orders[]`, `cae_vencimiento` |
| `ALTER nv_accounts`, `clients`, `orders` | ✅ Se aplica igual (§7.4, §7.12, §7.13) | — |

---

## 8. Contratos API (con Request/Response)

### 8.1 Endpoints existentes que se mantienen

Todos los endpoints actuales de `adminApi.js` (418 líneas, ~40 métodos) se mantienen sin cambios. Incluye: `getClient`, `getAccountDetails`, `getFinanceClients`, `getDashboardMetrics`, planes CRUD, renewals, billing, coupons, shipping, SEO, support, etc.

### 8.2 Nuevos Endpoints Admin (Super Admin)

#### FX Rates
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/fx/rates` | Listar rates por país con config |
| PATCH | `/admin/fx/rates/:countryId` | Actualizar config (source, manual_rate, cache_ttl) |
| POST | `/admin/fx/rates/:countryId/refresh` | Forzar refresh del rate |

#### Country Configs
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/country-configs` | Listar países |
| PATCH | `/admin/country-configs/:siteId` | Actualizar config país |
| POST | `/admin/country-configs` | Crear nuevo país |

#### Quotas
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/quotas` | Listar todos los tenants con estado de quota |
| GET | `/admin/quotas/:tenantId` | Detalle quota de un tenant |
| PATCH | `/admin/quotas/:tenantId` | Override manual de estado |
| POST | `/admin/quotas/:tenantId/extend-grace` | Extender grace period |

#### GMV Commissions
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/billing/gmv-commissions` | Listar billing_adjustments type=gmv_commission |
| POST | `/admin/billing/gmv-commissions/:id/charge` | Cobrar un ajuste |
| POST | `/admin/billing/gmv-commissions/:id/waive` | Exentar un ajuste |
| POST | `/admin/billing/gmv-commissions/bulk-charge` | Cobrar todos los pending |

#### Fee Schedules
| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/fee-schedules` | Listar schedules |
| GET | `/admin/fee-schedules/:id` | Detalle con lines |
| POST | `/admin/fee-schedules` | Crear |
| PATCH | `/admin/fee-schedules/:id` | Actualizar |
| DELETE | `/admin/fee-schedules/:id` | Eliminar |

### 8.3 Tenant-facing Endpoints (con Request/Response)

#### `GET /v1/tenants/:tenantId/quotas`

Devuelve límites del plan y uso actual del tenant.

**Request:** `GET /v1/tenants/abc123/quotas?period=2026-02`  
**Headers:** `Authorization: Bearer <jwt>`, `x-client-id: <uuid>`

**Response (200):**
```json
{
  "tenantId": "abc123",
  "plan": "Growth",
  "limits": {
    "stores": 3,
    "orders": 1000,
    "apiCalls": 800000,
    "storageGB": 10,
    "egressGB": 40
  },
  "usage": {
    "stores": 3,
    "orders": 120,
    "apiCalls": 45230,
    "storageGB": 2.7,
    "egressGB": 8.4
  },
  "state": "WARN_50",
  "graceUntil": null
}
```

#### `POST /v1/quota/check`

Middleware para verificar si se puede consumir un recurso antes de ejecutar la operación.

**Request:**
```json
{
  "tenantId": "abc123",
  "resource": "orders",
  "increment": 1
}
```

**Response (200 — permitido):**
```json
{ "allowed": true }
```

**Response (429 — soft limit alcanzado):**
```json
{ "allowed": false, "reason": "Soft limit reached for orders", "state": "SOFT_LIMIT" }
```

#### `POST /v1/billing/upgrade`

Solicita upgrade de plan del tenant.

**Request:**
```json
{
  "tenantId": "abc123",
  "targetPlan": "Growth",
  "paymentMethodId": "pm_xyz"
}
```

**Response (200):**
```json
{ "status": "upgrade_success", "newPlan": "Growth", "charged": 40.00 }
```

#### `GET /v1/tenants/:tenantId/context`

Devuelve CountryContext completo del tenant (país, moneda, locale, impuestos).

**Response (200):**
```json
{
  "siteId": "MLC",
  "countryId": "CL",
  "currencyId": "CLP",
  "locale": "es-CL",
  "timezone": "America/Santiago",
  "currencyDecimals": 0,
  "vatDigitalRate": 0.19,
  "arcaCuitPais": "55000002206"
}
```

#### `POST /webhooks/mp` (Webhook MercadoPago)

**Flujo interno:**
1. Validar firma MP (`x-signature`)
2. Identificar tenant + orden vía `external_reference`
3. Confirmar pago → `orders.status = 'paid'`
4. Registrar `usageRecorder.record('order', 1)` + `usageRecorder.recordOrderGmv(total)`
5. Calcular `marketplace_fee` si aplica → generar billing event
6. Idempotencia: verificar `mp_idempotency` antes de procesar

> **⚠️ NOTA G4:** `mercadopago.controller.ts` tiene 1559 líneas con múltiples flujos de `status === 'approved'` (algunos comentados). Antes de hookear GMV, se debe mapear TODOS los flujos de confirmación para no duplicar registros.

---

## 9. Roadmap por Fases (con pre-checks)

### 🔵 FASE 0: Pre-requisitos y Validación (Día 1-2)

> **ANTES de empezar cualquier implementación**

#### Pre-check obligatorio:
- [ ] Leer `novavision-docs/changes/` para verificar que no hay cambios recientes que conflicten
- [ ] Verificar rama correcta: `feature/automatic-multiclient-onboarding` (API)
- [ ] Verificar que `npm run ci` pasa en las 3 apps (api, admin, web)
- [ ] Verificar acceso a las 2 DBs (Admin y Backend)
- [ ] Verificar que los seeds actuales de `plans` no generan conflicto con los nuevos

#### Tareas:
| # | Tarea | Esfuerzo | Output |
|---|-------|---------|--------|
| 0.1 | Inventariar todos los clientes Enterprise existentes | 0.5h | Lista con pricing actual |
| 0.2 | Verificar que `nv_accounts.plan_key` CHECK admite 'enterprise' | 1h | Fix si falta |
| 0.3 | Verificar que `subscription_upgrade_log` tiene migración DDL | 0.5h | Crear si falta |
| 0.4 | Documentar valores actuales de seeds `plans` | 0.5h | Snapshot pre-migración |

---

### 🟢 FASE 1: Migraciones DB + Tablas Base (Semana 1)

#### Pre-check antes de empezar Fase 1:
- [ ] Fase 0 completada al 100%
- [ ] Backup de Admin DB y Backend DB
- [ ] Plan de rollback definido (scripts de `ALTER TABLE DROP COLUMN IF EXISTS`)
- [ ] Migraciones testeadas en entorno local / staging

#### Tareas:
| # | Tarea | Esfuerzo | Archivos | Dependencias |
|---|-------|---------|---------|-------------|
| 1.1 | Crear migración `country_configs` + seed | 0.5d | `migrations/admin/ADMIN_0XX_country_configs.sql` | Ninguna |
| 1.2 | Crear migración `fx_rates_config` + seed | 0.5d | `migrations/admin/ADMIN_0XX_fx_rates_config.sql` | Ninguna |
| 1.3 | ALTER `plans` con rate limits + GMV | 0.5d | `migrations/admin/ADMIN_0XX_plans_extend.sql` | Ninguna |
| 1.4 | UPDATE `plans` seeds (Enterprise $390) | 0.5d | Mismo archivo que 1.3 | 1.3 |
| 1.5 | ALTER `nv_accounts` con i18n + fiscal | 1d | `migrations/admin/ADMIN_0XX_nv_accounts_i18n.sql` | Ninguna |
| 1.6 | ALTER `subscriptions` con auto_charge | 0.5d | `migrations/admin/ADMIN_0XX_subscriptions_auto_charge.sql` | Ninguna |
| 1.7 | ALTER `clients` con country/locale/tz | 0.5d | `migrations/backend/BACKEND_0XX_clients_i18n.sql` | Ninguna |
| 1.8 | ALTER `orders` con currency/exchange_rate | 0.5d | `migrations/backend/BACKEND_0XX_orders_currency.sql` | Ninguna |
| 1.9 | Crear `fee_schedules` + `fee_schedule_lines` + seed AR | 1d | `migrations/admin/ADMIN_0XX_fee_schedules.sql` | 1.1 |
| 1.10 | Crear `quota_state` | 0.5d | `migrations/admin/ADMIN_0XX_quota_state.sql` | 1.5 |
| 1.11 | Crear `usage_rollups_monthly` | 0.5d | `migrations/admin/ADMIN_0XX_usage_rollups_monthly.sql` | 1.5 |
| 1.12 | Crear `billing_adjustments` | 0.5d | `migrations/admin/ADMIN_0XX_billing_adjustments.sql` | 1.5 |
| 1.13 | Crear `nv_invoices` | 0.5d | `migrations/admin/ADMIN_0XX_nv_invoices.sql` | 1.5 |
| 1.14 | Crear `cost_rollups_monthly` | 0.5d | `migrations/admin/ADMIN_0XX_cost_rollups_monthly.sql` | 1.5 |
| 1.15 | Backfill `nv_accounts`: copiar cuit_cuil → seller_fiscal_id, set country/currency/mp_site_id | 0.5d | Script SQL one-time | 1.5 |

#### Validación post Fase 1:
- [ ] `npm run ci` pasa en API
- [ ] Todas las migraciones aplicadas sin errores
- [ ] Query de verificación: `SELECT * FROM plans` muestra columnas nuevas
- [ ] Query de verificación: `SELECT count(*) FROM country_configs` = 6
- [ ] Query de verificación: `SELECT count(*) FROM fx_rates_config` = 6
- [ ] NV_accounts backfill: `SELECT count(*) FROM nv_accounts WHERE seller_fiscal_id IS NOT NULL` > 0

---

### 🟡 FASE 2: FxService Refactor + CountryContext (Semana 2)

#### Pre-check antes de empezar Fase 2:
- [ ] Fase 1 completada y validada al 100%
- [ ] Verificar que `fx_rates_config` tiene seeds correctos
- [ ] Verificar que `ioredis` está configurado y funcionando en la API
- [ ] Leer el código actual de `FxService` y `DolarBlueService` para entender todos los puntos de integración

#### Tareas:
| # | Tarea | Esfuerzo | Archivos principales |
|---|-------|---------|---------------------|
| 2.1 | Refactorear `FxService` → dual-source con Redis cache | 1.5d | `src/common/fx.service.ts` |
| 2.2 | Eliminar `DolarBlueService`, consolidar en FxService | 0.5d | `src/common/services/dolar-blue.service.ts` (eliminar), `src/seo-ai-billing/` (actualizar imports) |
| 2.3 | Crear `CountryContextService` | 1d | `src/common/country-context.service.ts` (nuevo) |
| 2.4 | API admin endpoints: GET/PATCH/POST `/admin/fx/rates` | 1d | `src/admin/fx-rates.controller.ts` (nuevo) |
| 2.5 | API admin endpoints: GET/PATCH/POST `/admin/country-configs` | 1d | `src/admin/country-configs.controller.ts` (nuevo) |
| 2.6 | Sync `country`/`locale`/`timezone` en `reconcileCrossDb()` | 0.5d | `src/subscriptions/subscriptions.service.ts` |

#### Validación post Fase 2:
- [ ] `npm run ci` pasa
- [ ] `FxService.getRate('AR')` retorna rate oficial (no blue)
- [ ] `FxService.getRate('CL')` retorna rate CLP desde frankfurter
- [ ] Cache Redis funciona (segundo call es instantáneo)
- [ ] `getBlueDollarRate()` sigue funcionando (backward compat)
- [ ] Endpoints admin funcionan (list, update, refresh)

---

### 🟠 FASE 3: Quota Enforcement + Rate Limits (Semana 3-4)

#### Pre-check antes de empezar Fase 3:
- [ ] Fase 2 completada y validada
- [ ] `quota_state` y `usage_rollups_monthly` tablas existen
- [ ] Entender cómo `RedisRateLimiter` funciona actualmente (para extenderlo)
- [ ] Definir feature flag `enable_quota_enforcement` (inicialmente OFF)

#### Tareas:
| # | Tarea | Esfuerzo | Archivos |
|---|-------|---------|---------|
| 3.1 | Cron `UsageConsolidationCron` (usage_daily → usage_rollups_monthly) | 1.5d | `src/billing/usage-consolidation.cron.ts` (nuevo) |
| 3.2 | `QuotaEnforcementService` (state machine) | 2d | `src/billing/quota-enforcement.service.ts` (nuevo) |
| 3.3 | Guard `QuotaCheckGuard` (middleware pre-write) | 1d | `src/guards/quota-check.guard.ts` (nuevo) |
| 3.4 | Rate limits per-tenant (extender RedisRateLimiter) | 1d | `src/common/utils/rate-limit-redis.ts` (modificar) |
| 3.5 | API admin: GET/PATCH `/admin/quotas` | 1d | `src/admin/quotas.controller.ts` (nuevo) |
| 3.6 | API tenant: GET `/v1/tenants/:id/quotas`, POST `/v1/quota/check` | 1d | `src/billing/quota.controller.ts` (nuevo) |
| 3.7 | Notificaciones quota (email + in-app vía outbox existente) | 1d | Extender `subscription_notification_outbox` |

#### Validación post Fase 3:
- [ ] `npm run ci` pasa
- [ ] Cron de consolidación crea registros en `usage_rollups_monthly`
- [ ] QuotaEnforcement transiciona correctamente: ACTIVE → WARN_50 → WARN_75 → WARN_90 → SOFT_LIMIT → GRACE → HARD_LIMIT
- [ ] Rate limit per-tenant: Starter limitado a 5 RPS, Growth a 15 RPS
- [ ] Feature flag OFF = sin enforcement (bypass)
- [ ] Feature flag ON = enforcement activo
- [ ] Endpoints admin retornan datos correctos

---

### 🔴 FASE 4: Comisión GMV + Overages + Billing (Semana 4-5)

#### Pre-check antes de empezar Fase 4:
- [ ] Fase 3 completada y validada
- [ ] `usage_rollups_monthly` tiene datos (al menos de testing)
- [ ] `billing_adjustments` tabla existe
- [ ] Entender cómo `BillingService` (372 líneas, `src/billing/billing.service.ts`) y `nv_billing_events` funcionan actualmente
- [ ] **⚠️ G4: Mapear TODOS los flujos `status === 'approved'` en `mercadopago.controller.ts` (1559 líneas, al menos 3 bloques, algunos comentados)** para identificar el hook point exacto y evitar duplicar registros GMV
- [ ] Verificar que `UsageRecorderService` NO está inyectado en `mercadopago.controller.ts` (hay que agregarlo al module + controller)
- [ ] Definir: umbrales GMV confirmados (Starter $5k, Growth $40k)

#### Tareas:
| # | Tarea | Esfuerzo | Archivos |
|---|-------|---------|---------|
| 4.1 | Agregar metric `gmv` a `UsageRecorderService` | 0.5d | `src/metrics/usage-recorder.service.ts` |
| 4.2 | Hook en webhook MP: cuando orden se confirma → `recordOrderGmv()` | 0.5d | `src/tenant-payments/mercadopago.controller.ts` |
| 4.3 | Cron `GmvCommissionCron` (calcula comisiones mensuales) | 1.5d | `src/billing/gmv-commission.cron.ts` (nuevo) |
| 4.4 | Lógica de overages (calcular excess vs plan limits) | 1.5d | `src/billing/overage.service.ts` (nuevo) |
| 4.5 | Auto-charge: crear preferencia MP para cobrar adjustments | 1d | Extender `BillingService` |
| 4.6 | API admin: GMV commissions CRUD + bulk charge | 1d | `src/admin/gmv-commissions.controller.ts` (nuevo) |
| 4.7 | Crear `cost_rollups_monthly` cron (COGS) | 1d | `src/billing/cost-rollup.cron.ts` (nuevo) |

#### Validación post Fase 4:
- [ ] `npm run ci` pasa
- [ ] Orden pagada → metric `gmv` registrada en `usage_ledger`
- [ ] Consolidación mensual incluye `orders_gmv_usd`
- [ ] GmvCommissionCron genera `billing_adjustments` correctamente para tenants Growth con GMV > $40k
- [ ] auto_charge=true → se crea preferencia MP
- [ ] Dashboard admin muestra comisiones pending/charged/waived
- [ ] Idempotencia: no se duplican comisiones si el cron corre 2 veces

---

### 🟣 FASE 5: Frontend Super Admin (Semana 5-6)

#### Pre-check antes de empezar Fase 5:
- [ ] Fases 1-4 completadas y validadas
- [ ] Todos los endpoints admin funcionan
- [ ] Verificar que `apps/admin` compila sin errores
- [ ] Verificar rama correcta: `develop` (admin)

#### Tareas:
| # | Tarea | Esfuerzo | Archivos |
|---|-------|---------|---------|
| 5.1 | `FxRatesView.jsx` (nueva página) | 1.5d | `src/pages/AdminDashboard/FxRatesView.jsx` |
| 5.2 | `CountryConfigsView.jsx` (nueva página) | 1d | `src/pages/AdminDashboard/CountryConfigsView.jsx` |
| 5.3 | `GmvCommissionsView.jsx` (nueva página) | 1.5d | `src/pages/AdminDashboard/GmvCommissionsView.jsx` |
| 5.4 | `QuotasView.jsx` (nueva página) | 1.5d | `src/pages/AdminDashboard/QuotasView.jsx` |
| 5.5 | `FeeSchedulesView.jsx` (nueva página) | 1d | `src/pages/AdminDashboard/FeeSchedulesView.jsx` |
| 5.6 | Extender `PlansView.jsx` con columnas nuevas | 1d | `src/pages/AdminDashboard/PlansView.jsx` |
| 5.7 | Extender `ClientDetails` con tabs Quotas/Billing/FX | 1d | `src/pages/ClientDetails/` |
| 5.8 | Actualizar sidebar con nuevas rutas | 0.5d | `src/pages/AdminDashboard/index.jsx` |
| 5.9 | Actualizar `adminApi.js` con nuevos endpoints | 0.5d | `src/services/adminApi.js` |
| 5.10 | Agregar rutas en `App.jsx` | 0.5d | `src/App.jsx` |

#### Validación post Fase 5:
- [ ] `npm run ci` pasa en admin (lint + typecheck + build)
- [ ] Todas las nuevas páginas renderizan sin errores
- [ ] CRUD funciona end-to-end: FX rates, country configs, fee schedules
- [ ] Quotas view muestra datos reales de tenants
- [ ] GMV commissions view muestra adjustments y permite cobrar/waive
- [ ] PlansView muestra columnas nuevas
- [ ] Sidebar tiene las 5 nuevas entradas

---

### ⚫ FASE 6: Web Storefront + Trial (Semana 6)

#### Pre-check:
- [ ] Fase 5 completada
- [ ] Rama correcta: `develop` (web)
- [ ] CountryContext endpoint funcionando

#### Tareas:
| # | Tarea | Esfuerzo |
|---|-------|---------|
| 6.1 | `formatCurrency` dinámico con CountryContext (**~50 archivos**: 23 con 'ARS' + 27 con 'es-AR') | **2.5d** |
| 6.2 | SEO tags dinámicos (og:locale, product:price:currency) | 1d |
| 6.3 | Trial como cupón en onboarding (7 días gratis) | 1d |
| 6.4 | Feature flags por país (`enable_country_AR`, `enable_country_CL`, etc.) | 0.5d |
| 6.5 | **CREAR** pricing page ($20/$60/$390) — **no existe** en `apps/web/` | **1.5d** |
| 6.6 | **CREAR** quota dashboard para tenant (barras de progreso) — **100% nuevo** | **2d** |

---

### 🔵 FASE 7: Tests E2E + Go-Live (Semana 7-8)

#### Pre-check:
- [ ] TODAS las fases anteriores completadas y validadas
- [ ] Environment de staging con datos reales
- [ ] Feature flags definidos y configurados

#### Tareas:
| # | Tarea | Esfuerzo |
|---|-------|---------|
| 7.1 | Tests E2E: quota enforcement (13 scenarios) | 2d |
| 7.2 | Tests E2E: GMV commission calculation | 1d |
| 7.3 | Tests E2E: FX rates multi-country | 1d |
| 7.4 | Tests E2E: rate limiting per-tenant | 0.5d |
| 7.5 | Tests E2E: checkout multi-currency | 1d |
| 7.6 | Security audit: nuevos endpoints admin | 0.5d |
| 7.7 | Go-live AR: feature flags ON, monitoring | 1d |
| 7.8 | Monitoreo post-go-live + hotfixes | 1 semana |

---

## 10. Reglas de Facturación, Pricing y Simulaciones de Costos

### 10.1 Pricing Definitivo

| Plan | USD/mes | USD/año (2 meses gratis) |
|------|---------|-------------------------|
| Starter | $20 | $200 |
| Growth | $60 | $600 |
| Enterprise | $390 | $3.900 |

### 10.2 Fórmula COGS

```
COGS_tenant = FeePagoMP + CostoEgress + CostoStorage + CostoAPI + CostoOrdenes + ShareFijo
```

**Costos unitarios de referencia (Railway + Supabase):**

| Recurso | Costo unitario | Fuente |
|---------|---------------|--------|
| CPU | ~$20/vCPU·mes | Railway |
| RAM | ~$10/GB·mes | Railway |
| Egress | ~$0.05/GB (Railway) + ~$0.09/GB (Supabase) ≈ **$0.078/GB** promedio | Railway + Supabase |
| Storage | ~$0.021/GB·mes | Supabase |
| MP Fee (suscripciones NV) | ~5.4% estimado (2.9%+30¢ base + 1.5% intl + 1% FX) | **⚠️ P5: confirmar fees reales** |

**Fórmula expandida:**
```
COGS_tenant = (MP_fee_pct × plan_price)
            + (0.01 × orders_count)         -- costo procesamiento órdenes
            + (0.20 × api_calls / 1_000_000)  -- costo API calls
            + (0.021 × storage_gb)            -- costo storage
            + (0.078 × egress_gb)             -- costo egress
```

### 10.3 Simulaciones de Costos

**Mix modelado:** 70% Starter / 25% Growth / 5% Enterprise (stress: 100% cuota usada)

| Escenario | Tiendas | Revenue USD/mes | COGS USD/mes | Margen bruto |
|-----------|---------|----------------|-------------|-------------|
| Early stage | 100 | $4.300 | $1.033 | **76%** |
| Scale-up | 500 | $21.500 | $4.666 | **78%** |
| Mature | 1.000 | $43.000 | $9.177 | **79%** |

**Desglose por plan (100% cuota usada):**

| Plan | Precio USD | Uso aprox (órd/mes) | Storage GB | COGS/tenant USD | Margen |
|------|-----------|--------------------|-----------|-----------------| -------|
| Starter | $20 | 150 | 1 | ~$2.70 | **86%** |
| Growth | $60 | 1.000 | 10 | ~$14.80 | **75%** |
| Enterprise | $390 | 5.000 | 50 | ~$85 | **78%** |

> Se recomienda crear una hoja de cálculo parametrizable con estas fórmulas en `novavision-docs/economics/`.

### 10.4 Overages

| Plan | Órdenes extra | Egress extra | GMV commission |
|------|--------------|-------------|----------------|
| Starter | NO (hard limit) | NO (hard limit) | 0% |
| Growth | $0.015/orden | $0.08/GB | 2% sobre GMV > $40k USD |
| Enterprise | Negociable | Negociable | Negociable |

### 10.5 FX

| País | Fuente | Endpoint | Fallback |
|------|--------|---------|---------|
| AR | dolarapi.com | `/v1/dolares/oficial` campo `venta` | BCRA API → hardcoded 1200 |
| CL | frankfurter.app | `/latest?from=USD&to=CLP` | Manual admin → hardcoded 950 |
| MX | frankfurter.app | `/latest?from=USD&to=MXN` | Manual admin → hardcoded 17.5 |
| CO, UY, PE | frankfurter.app | Igual patrón | Manual admin |

---

## 11. Documento Legal: T&C y Cláusulas Fiscales

### 11.1 Modelo Merchant-of-Record (MoR)

> "NovaVision proporciona la plataforma de e-commerce. El Cliente suscriptor es el vendedor (Merchant of Record) ante sus compradores. El Cliente debe emitir los comprobantes locales requeridos (boletas, facturas, etc.). NovaVision solo emite facturas de exportación de servicios (Factura E) al Cliente por comisiones/plataforma. El Cliente asume toda responsabilidad fiscal por sus ventas locales."

### 11.2 Impuestos y Monedas

> "Todos los precios de planes están en USD. Las facturas de NovaVision se emitirán en USD (o en ARS con tipo BNA vendedor divisa si aplica ARS). Las comisiones y pagos en moneda local se convertirán usando el tipo de cambio oficial BNA vendedor del día hábil anterior al cobro. Diferencias cambiarias no generan ajuste por parte de NovaVision."

### 11.3 Límites y Overages

> "El servicio tiene límites mensuales (órdenes, llamadas API, almacenamiento, egress, GMV). Si se exceden, NovaVision cobrará automáticamente un cargo de excedente según tarifas vigentes publicadas en el Schedule de Planes. El Cliente será notificado del exceso vía email y dashboard, y puede actualizar su plan para evitar cargos adicionales. Si no hay pago, el servicio excedente puede suspenderse parcialmente hasta pago o renovación."

### 11.4 Comisión por ventas (GMV)

> "Determinados planes incluyen un umbral de volumen de ventas (GMV). Al superar dicho umbral, NovaVision cobrará una comisión sobre el excedente según la tabla publicada. El cálculo se realiza mensualmente sobre el acumulado de ventas confirmadas (status=paid) convertidas a USD."

### 11.5 Suspensión y Cancelación

> "NovaVision puede suspender parcial o totalmente la cuenta si el Cliente incumple pagos o abusa del servicio. Se dará aviso previo de al menos 7 días para resolver la situación. Al reincidir dentro de los 90 días, se podrá cancelar la cuenta sin reembolso. El proceso de suspensión sigue: notificación → grace period → soft limit (solo lectura) → hard limit (desactivación) → purge (90 días después)."

### 11.6 Política de Uso Justo

> "El Cliente debe usar el servicio de buena fe. NovaVision monitoreará el consumo y podrá aplicar limitaciones graduales según el plan contratado. Uso excesivo o ilícito (p.ej. contenido ilegal, vulneración de derechos de propiedad intelectual, phishing, spam) permite a NovaVision cancelar sin reembolso. El Cliente indemnizará a NovaVision por reclamos legales derivados de su actividad en la tienda."

### 11.7 Protección de Datos

> "NovaVision tratará datos de usuarios y compradores conforme a Ley 25.326 (Datos Personales, Argentina) y normativas equivalentes de cada país LATAM donde opere (Ley 19.628 Chile, Ley 1581 Colombia, LFPDPPP México). El Cliente debe contar con consentimiento/legitimación para todo dato que comparta a través de la plataforma (datos de compradores, logística, facturación). NovaVision no utiliza datos de compradores para fines comerciales propios."

### 11.8 Tabla resumen por cláusula

| Cláusula | Aplica a | Requerido en T&C | Requerido en contrato B2B |
|----------|---------|------------------|-------------------------|
| MoR | Todos los planes | ✅ | ✅ |
| Impuestos/Monedas | Todos | ✅ | ✅ |
| Límites/Overages | Growth + Enterprise | ✅ | ✅ |
| Comisión GMV | Growth (2%) + Enterprise (negociable) | ✅ | ✅ |
| Suspensión | Todos | ✅ | ✅ |
| Uso Justo | Todos | ✅ | ✅ |
| Protección Datos | Todos | ✅ | ✅ |

---

## 12. Matriz de Riesgos (Validada)

| # | Riesgo | Impacto | Mitigación |
|---|--------|---------|-----------|
| R1 | **PtoVta Factura E** no tramitado | 🔴 ALTO | Tramitar ya. Ver §2.1 — son 15 min online |
| R2 | **BCRA liquidación** | 🟠 MEDIO | MP liquida en ARS → probablemente no aplica. Ver §2.2 |
| R3 | **MP Cross-border** | 🟠 MEDIO | NV usa token del seller, no hay cross-border real. Ver §2.3 |
| R4 | **FxService usa blue** | 🟠 MEDIO → solucionado en Fase 2 | Cambiar endpoint de `/blue` a `/oficial` en misma API |
| R5 | **Enterprise $390** | 🟡 BAJO (sin grandfather) | Comunicar con 30 días de aviso |
| R6 | **Entitlements no enforceados** | 🟡 MEDIO → solucionado en Fase 3 | QuotaEnforcement con feature flag gradual |
| R7 | **Cross-DB cron (Backend→Admin)** | 🟡 BAJO | Diseño robusto con retry + idempotency |
| R8 | **Protección de datos (Ley 25.326)** | 🟠 MEDIO | Verificar inscripción AAIP/DP si aplica. Ver §11.7 y §13 tarea legal |
| R9 | **MP controller 1559 líneas** | 🟠 MEDIO | Múltiples flujos `approved` (algunos comentados). Mapear TODOS antes de hookear GMV (Fase 4). Ver nota G4 en §8.3 |

---

## 13. PENDIENTES Actualizados + Tareas Legales/Ops

### ✅ Resueltos (en este documento)

| # | Item | Resolución |
|---|------|----------|
| ~~P1~~ | PtoVta Factura E | Explicado en §2.1 — trámite online, no es bloqueante técnico |
| ~~P2~~ | BCRA liquidación | Explicado en §2.2 — probable que no aplique con MP |
| ~~P3~~ | MP Cross-border | Explicado en §2.3 — NV usa token del seller |
| ~~P4~~ | Grandfather Enterprise | Resuelto: $390 definitivo, sin grandfather |
| ~~P7~~ | Fuente API BNA | Resuelto: `dolarapi.com/v1/dolares/oficial` (misma API, endpoint diferente) |

### 🟠 Pendientes técnicos que requieren acción

| # | Pendiente | Responsable | Criticidad | Fase |
|---|----------|-------------|-----------|------|
| P5 | Obtener fees reales MP por cobro suscripción NV | Finance | 🟠 | Antes de Fase 4 |
| P6 | Confirmar umbrales GMV (Starter $5k, Growth $40k) | TL | 🟠 | Antes de Fase 1 (seeds §7.3) |
| P8 | Duración exacta del trial (7 o 14 días) | TL | 🟡 | Antes de Fase 6 |
| P9 | Cuentas test MP para CL, MX, CO | Ops | 🟠 | Antes de Fase 7 |
| P10 | Fix `nv_accounts.plan_key` CHECK (falta 'enterprise') | Dev | 🟠 | Fase 0 |
| P11 | Provisionar infra Enterprise dedicada | Ops | 🟠 | Cuando haya cliente |
| P12 | Migración formal `subscription_upgrade_log` | Dev | 🟡 | Fase 1 |

### 🔴 Tareas Legales/Ops (BLOQUEANTES para go-live internacional)

Estas tareas deben concluir **antes del lanzamiento LATAM** (Fase 7). Las que no tienen fechalímite pueden avanzar en paralelo.

| # | Tarea | Responsable | Bloquea | Estado |
|---|-------|------------|---------|--------|
| L1 | **Registrar PV Factura E en ARCA** (§2.1) — ABM online, ~15 min | TL / Contador | Go-live LATAM | ⬜ Pendiente |
| L2 | **Consulta BCRA**: confirmar si cobros via MP (liquidados en ARS) requieren declaración de exportación | Contador | Go-live LATAM | ⬜ Pendiente |
| L3 | **Verificar inscripción AAIP** (Dirección de Datos Personales): ¿aplica a NV como procesador de datos de compradores? Ley 25.326 | Legales | Go-live LATAM | ⬜ Pendiente |
| L4 | **Redactar T&C completos** usando las cláusulas de §11 como base. Incluir secciones de MoR, impuestos, overages, GMV, suspensión, datos personales | Legales | Go-live LATAM | ⬜ Pendiente |
| L5 | **Firmar avisos MoR** con tenants existentes: notificar que NV no es vendedor de sus productos y que la responsabilidad fiscal es del tenant | Ops / Legales | Go-live LATAM | ⬜ Pendiente |
| L6 | **Validar con MP account manager**: ¿se pueden crear preapprovals con access_token de seller de otro país? (ver §2.3) | Ops | Habilitación CL/MX | ⬜ Pendiente |

### 📋 Mapping: Sprints del TL → Fases del Plan

Para referencia, el mapping entre los 5 sprints propuestos y las 8 fases del plan:

| Sprint TL | Fases del Plan | Contenido |
|-----------|---------------|----------|
| Sprint 1 | **Fase 0 + Fase 1 + Fase 2** (parcial) | Migraciones DB, country_configs, captura site_id OAuth, CountryContextService, refactor checkout currency dinámica |
| Sprint 2 | **Fase 2** (resto) **+ Fase 3** | plan_catalog → ALTER plans, subscriptions, rate limiting per-tenant, quota check, quota_state |
| Sprint 3 | **Fase 4** | Fee schedules, marketplace_fee, billing cron, nv_invoices, servicio TC BNA diario |
| Sprint 4 | **Fase 5 + Fase 6** | Frontend admin (vistas), formatCurrency web, trial, quota dashboards |
| Sprint 5 | **Fase 7** | Habilitar CL/MX, E2E tests, feature flags, monitoreo, go-live |

> Las fases del plan son más granulares (pre-checks por fase, validación post-fase) y agregan Fase 0 como setup explícito. El contenido es equivalente.

### 🟡 Backlog técnico (no bloqueante)

| # | Item | Notas |
|---|------|-------|
| P13-P20 | Deuda técnica general | En `novavision-docs/improvements/` |
| G5 | 3 vistas admin no inventariadas en §5.1 | `ClientsUsageView`, `ClientApprovalDetail`, `RenewalDetailView` — no afectan implementación |
| G6 | Cross-DB cron sin patrón documentado | Documentar el patrón de conexión Backend→Admin DB antes de Fase 3 |
| G9 | `managed-domain.service.ts` también usa FxService | 3er consumidor no mencionado en §3 — verificar al refactorear |
| G10 | `billing.service.ts` (372 líneas) no descrito | Ya existe, maneja `nv_billing_events`. Documentar estado actual antes de Fase 4 |

---

*Este documento es un plan. No se ejecutan cambios sin aprobación explícita del TL.*

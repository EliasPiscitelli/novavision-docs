# NovaVision — Plan de Internacionalización LATAM (Pagos, Pricing, Suscripciones)

- **Autor:** agente-copilot (Payment Architecture + i18n)
- **Fecha:** 2026-02-21
- **Estado:** PLAN — No ejecutar sin aprobación del TL
- **Rama target:** (nueva) `feature/i18n-latam-payments`

---

## Índice

1. [Impact Analysis](#1-impact-analysis)
2. [Decisiones de Producto y Policy](#2-decisiones-de-producto-y-policy)
3. [CountryContext — Contrato y Resolución Determinística](#3-countrycontext--contrato-y-resolución-determinística)
4. [Diseño de Datos](#4-diseño-de-datos)
5. [Templates Bulletproof](#5-templates-bulletproof)
6. [Fees: Modelo, Carga y Mantenimiento](#6-fees-modelo-carga-y-mantenimiento)
7. [Plan de QA, Monitoreo y Release](#7-plan-de-qa-monitoreo-y-release)
8. [Cronograma y Fases](#8-cronograma-y-fases)
9. [Preguntas de Descubrimiento](#9-preguntas-de-descubrimiento)
10. [Marco Legal/Fiscal y Facturación](#10-marco-legalfiscal-y-facturación)

---

## 1. Impact Analysis

### 1.1 Inventario de Hardcodes (hallazgos reales del código)

Se auditó exhaustivamente `apps/api/src/`, `apps/web/src/` y `apps/admin/src/`. Resumen:

| Módulo | # Hardcodes | Riesgo si seller de otro país | Qué rompe |
|--------|-------------|-------------------------------|-----------|
| **Checkout/Pagos MP** | ~10 | 🔴 CRÍTICO | `currency_id: 'ARS'` en preferencias MP → MP rechaza si token es de otro país |
| **Suscripciones NV** | 2 | 🔴 CRÍTICO | `currency_id: 'ARS'` en PreApproval/Plans → falla creación |
| **SEO/OG Tags** | ~6 | 🟠 ALTO | `locale: es_AR`, `currency: ARS` en meta tags → Google indexa mal |
| **Formateo precios (web)** | ~35+ | 🟠 ALTO | `Intl.NumberFormat("es-AR", {currency: "ARS"})` en TODA la web |
| **Fechas/Timezone** | ~40+ | 🟡 MEDIO | `America/Argentina/Buenos_Aires` everywhere |
| **Analytics** | 4 | 🟡 MEDIO | Response dice `tz: BsAs` y `currency: ARS` |
| **Shipping** | ~6 | 🟡 MEDIO | Fallback `currency: 'ARS'` en cotizaciones |
| **Validación productos** | 1 | 🟡 MEDIO | `VALID_CURRENCIES` = `['ARS', 'USD']` — no acepta CLP, MXN, etc. |
| **Admin panels** | ~25+ | 🟢 BAJO | `'es-AR'` en dashboards internos NV (super admin) |
| **Demo/seed** | ~30+ | 🟢 BAJO | Solo datos de ejemplo |

**Total: ~160+ hardcodes que asumen Argentina.**

### 1.2 Subsistemas impactados

#### A. Auth/Login
- **Supuesto single-country que se rompe:** Ninguno directo — auth es global vía Supabase.
- **Datos adicionales necesarios:** `country`, `locale` del user para UX.
- **Fallas típicas:** Ninguna crítica — los users heredan el country del tenant.
- **Riesgo:** 🟢 BAJO

#### B. Onboarding OAuth (MP)
- **Supuesto que se rompe:** El flujo OAuth permite seleccionar país en MP. El backend NO captura el `site_id`/país del seller autorizado.
- **Datos necesarios:** `site_id` (MLA/MLC/MLM...), `country_id`, `currency_id` del seller.
- **Fallas:** Si un seller chileno se conecta, el sistema guarda sus tokens pero cree que es argentino → todas las preferencias fallan con currency mismatch.
- **Estado actual:** `fetchMpOwnerInfo()` llama a `/users/me` pero solo extrae `id, email, nickname, first_name, last_name` — **NO extrae `site_id`** (el campo existe en la respuesta de MP).
- **Riesgo:** 🔴 CRÍTICO

#### C. Pricing/Catálogo
- **Supuesto:** Precios en un solo campo `price` (numeric). No hay `currency` por producto — se asume ARS globalmente.
- **Datos necesarios:** `currency` por tenant (ya existe `client_payment_settings.currency` pero no se propaga).
- **Fallas:** Productos con precio en ARS mostrados como CLP o viceversa. Import CSV solo acepta `['ARS', 'USD']`.
- **Riesgo:** 🟠 ALTO

#### D. Checkout/Pagos (Preferencias MP)
- **Supuesto que se rompe:** `currency_id: 'ARS'` hardcodeado en ~10 lugares al crear preferencias MP.
- **Datos necesarios:** `currency_id` del seller (resuelto del country/site_id), `country` para payer address.
- **Fallas:** MP **rechaza** la preferencia si `currency_id` no coincide con la moneda del `access_token` del seller. Error típico: `"invalid currency_id for this user"`.
- **Riesgo:** 🔴 CRÍTICO — bloquea pagos completamente

#### E. Suscripciones (PreApproval)
- **Supuesto:** `currency_id: 'ARS' as const` hardcodeado en `createPreApproval()` y `updateSubscriptionPrice()`.
- **Fallas:** Suscripción falla al crearse para un seller de otro país.
- **Riesgo:** 🔴 CRÍTICO

#### F. Webhooks/Notificaciones
- **Supuesto:** El webhook no discrimina por moneda. Los montos se guardan en `orders.total` sin contexto de currency.
- **Datos necesarios:** Persistir `currency` en `orders` y `payments` para conciliación correcta.
- **Fallas:** Conciliación incorrecta — un pago de 10.000 CLP ($10 USD aprox.) se leería como 10.000 ARS ($10 USD aprox., coincidencia, pero en otros montos diverge significativamente por redondeo y decimales).
- **Riesgo:** 🟡 MEDIO

#### G. Conciliación/Reporting
- **Supuesto:** Analytics hardcodea `currency: 'ARS'` y `tz: 'America/Argentina/Buenos_Aires'`.
- **Fallas:** Reportes muestran moneda incorrecta. Facturación de NovaVision mezcla monedas sin conversión.
- **Riesgo:** 🟡 MEDIO

#### H. Customer Support / Refunds
- **Supuesto:** Refunds usan el `access_token` del seller → la API de MP maneja la moneda correctamente.
- **Fallas:** Menores — el monto de refund se procesa en la moneda del seller por MP. El riesgo está en la UI que muestra el monto formateado como ARS.
- **Riesgo:** 🟡 MEDIO

#### I. Panel Admin / Ops
- **Supuesto:** ~25+ `'es-AR'` en dashboards de super admin.
- **Fallas:** Formatos localizados incorrectamente pero funcional.
- **Riesgo:** 🟢 BAJO (es interno)

---

## 2. Decisiones de Producto y Policy

### Cross-Country Sellers — Opciones

#### Opción A: Permitir sellers multi-país con el mismo onboarding

| Aspecto | Detalle |
|---------|---------|
| **Pros** | Mayor TAM, un solo flujo de onboarding, sellers eligen su país en MP naturalmente |
| **Contras** | Hay que propagar country/currency en todo el stack, fee tables por país, soporte multi-moneda en reporting y facturación NV |
| **Complejidad técnica** | ALTA — requiere refactor de ~160 hardcodes + migraciones + fee tables |
| **Impacto conversión** | POSITIVO — no friction para sellers de otros países |
| **Impacto legal/ops** | MEDIO — NovaVision factura en ARS (empresa argentina). Comisiones de sellers externos se cobrarían en ARS al seller o en su moneda local (definir) |
| **Templates** | Todos deben aceptar `CountryContext` obligatorio |
| **Fees** | Tabla `mp_fee_table` ya soporta `country_code` pero solo tiene seed AR |
| **Conciliación** | Requiere reportes con breakdown por moneda |

#### Opción B: Restringir por país (bloquear onboarding si no es AR)

| Aspecto | Detalle |
|---------|---------|
| **Pros** | CERO cambios en pagos/pricing/suscripciones hoy. Solo validar en OAuth callback |
| **Contras** | Limita crecimiento a Argentina únicamente |
| **Complejidad técnica** | MÍNIMA — 1 validación en callback + 1 seed en signup |
| **Impacto conversión** | NEGATIVO — pierde sellers LATAM |
| **Impacto legal/ops** | Ninguno — todo sigue en ARS |
| **Implementación** | Agregar check de `site_id` en OAuth callback; si != `MLA` → error amigable |

#### ASSUMPTION: Recomendación

**Opción A (multi-país)** como objetivo estratégico, pero implementada en **fases** con gating por feature flag. Mientras tanto, **registrar el `site_id`/country del seller siempre** (incluso si solo se permite AR), para tener datos y no perder información de sellers que intenten conectarse.

**Short-term safeguard (implementar YA):**
- Capturar `site_id` del seller en OAuth callback vía `/users/me`
- Guardar en `nv_accounts.mp_site_id` y `nv_accounts.country`
- Si `site_id != 'MLA'`: completar conexión pero **marcar cuenta con flag** `country_mismatch: true`
- En checkout: si `country_mismatch` → bloquear con mensaje amigable "Próximamente disponible en tu país"
- Esto da datos de demanda real por país sin romper nada

### Decisión fiscal: Merchant-of-Record (MoR)

Esta decisión es **la más importante del plan** porque define toda la estructura fiscal, de facturación y de compliance. Ver análisis completo en [Sección 10](#10-marco-legalfiscal-y-facturación).

#### Modelo A: Sellers como MoR (RECOMENDADO)

```
Comprador → paga al Seller (local) → Seller factura localmente a su comprador
NV (Argentina) → factura Factura E (B2B exportación) al Seller por comisión/plataforma
```

| Aspecto | Detalle |
|---------|--------|
| **Factura del Seller** | Cada seller emite comprobante local a su comprador (boleta en CL, CFDI en MX, factura en CO, etc.) |
| **Factura de NV** | Factura E (exportación de servicios B2B) al seller por la comisión de plataforma |
| **IVA digital en destino** | NO aplica a NV — el consumo local es responsabilidad del seller |
| **Exposición fiscal de NV** | MÍNIMA: solo exportación de servicios desde AR |
| **Encuadre IVA AR** | Exportación exenta / tasa 0% — NV computa créditos fiscales vinculados |
| **marketplace_fee** | NV cobra vía `marketplace_fee` de MP (retención automática). La Factura E de NV al seller documenta esa comisión |
| **Complejidad** | BAJA para NV, MEDIA para sellers (deben cumplir su ley local) |

#### Modelo B: NV como MoR (NO RECOMENDADO para multi-país)

| Aspecto | Detalle |
|---------|--------|
| **Factura** | NV factura al consumidor final extranjero |
| **IVA digital** | NV debe registrarse y pagar IVA/IGV en **cada país destino** (CL 19%, MX 16%, CO 19%, PE 18%, UY 22%) |
| **Exposición fiscal** | MÁXIMA: registros, declaraciones, representantes fiscales en 5+ jurisdicciones |
| **Complejidad** | MUY ALTA — inviable en corto/medio plazo |

**Decisión: Modelo A (sellers como MoR).** NV emite Factura E B2B al seller. El seller factura localmente a sus compradores.

> **Implicación técnica:** La tabla `nv_invoices` (nueva, ver Sección 4) registra las Facturas E que NV emite a sellers por comisiones. `marketplace_fee` en preferencias MP debe coincidir con el monto facturado.

### Separación documental: Cadena A (SaaS) y Cadena B (Comercio del cliente)

La arquitectura fiscal y legal de NV se basa en separar **documentalmente** dos cadenas con roles económicos distintos:

| | Cadena A: Suscripción SaaS | Cadena B: Comercio del cliente |
|---|---|---|
| **¿Quién vende?** | NV (Argentina) | El seller/cliente (país local) |
| **¿Qué se vende?** | Servicio de plataforma e-commerce | Productos/servicios del seller a compradores finales |
| **MoR** | NV es MoR de la suscripción | Seller es MoR de sus ventas |
| **Factura** | Factura E (NV → Seller) por exportación B2B | Comprobante local (Seller → Comprador final) |
| **Cobro** | `marketplace_fee` + suscripción mensual | Preferencia MP con token del seller |
| **Conciliación** | `nv_invoices` ↔ liquidaciones MP | Responsabilidad del seller |
| **Compliance fiscal** | ARCA + BCRA (exportación) | Autoridad fiscal local del seller |
| **Contrato** | TyC + contrato de servicio NV | TyC de la tienda del seller |

> **Principio clave:** La "responsabilidad por contenido" se gestiona en contrato y enforcement, pero NO sustituye la separación correcta de roles económicos. NV documenta su Cadena A; el seller documenta su Cadena B.

### Patrones de cobro para la suscripción SaaS — Comparación estratégica

| Patrón | Descripción | ¿Evita registro en destino? | Riesgo fiscal B2C | Complejidad | Comentario |
|--------|-------------|:---:|---|---|---|
| **1. Cobro desde cuenta AR** | NV cobra suscripción directamente desde su cuenta MP Argentina | Potencialmente sí | Medio/alto si hay B2C | Media | Factura E OK; cuello de botella es operativo (PSP del comprador, liquidación) |
| **2. Cuentas MP locales por país** | NV abre cuenta MP en cada país para cobrar localmente | ❌ No — requiere alta por país | Medio | Alta | Contradice restricción de no registrarse. Máximo "local-friendly" pero inviable en fase 1 |
| **3. Vía seller con marketplace_fee** | Seller paga localmente y NV retiene comisión vía `marketplace_fee` | ✅ Sí si seller es B2B | Baja | Alta | **ELEGIDO.** El cliente (sujeto local) asume pagos; NV factura exportación B2B |

**Decisión: Patrón 3** (cobro vía marketplace_fee, seller asume relación local). Compatible con Cadena A/B y con la restricción de no registrarse en destino.

> **Escalabilidad:** Si aparecen clientes B2C relevantes fuera de AR, el Patrón 3 se vuelve frágil porque las normas de IVA/IGV digital apuntan al prestador no residente en relaciones B2C. Ver Carril B2C más abajo.

### Política B2B-only verificable para suscripciones internacionales

**Fundamento legal:** Varios países distinguen obligaciones cuando el receptor es consumidor vs. contribuyente/empresa. Operar "B2B-only" real minimiza exposición a regímenes de IVA digital que apuntan a B2C (Chile/SII, México/SAT, Colombia/DIAN, Perú/SUNAT).

**Requisitos operativos para verificar B2B:**

| Dato | Campo DB | Obligatoriedad | Ejemplo |
|------|----------|---------------|---------|
| ID fiscal local | `nv_accounts.seller_fiscal_id` | Obligatorio para suscripción internacional | RUT 12.345.678-9 (CL), RFC XAXX010101000 (MX) |
| Razón social / nombre legal | `nv_accounts.seller_fiscal_name` | Obligatorio | "Mi Tienda SpA" |
| Dirección fiscal | `nv_accounts.seller_fiscal_address` | Recomendado | "Av. Providencia 1234, Santiago" |
| Declaración de actividad económica | Checkbox en onboarding | Obligatorio | "Declaro que utilizo el servicio para actividad comercial/profesional" |

**Cláusulas contractuales requeridas (TyC/contrato):**
1. **MoR explícito:** "El Cliente es el vendedor (merchant-of-record) de las transacciones realizadas en su tienda."
2. **Autoliquidación fiscal:** "El Cliente es responsable de cumplir con las obligaciones tributarias de su jurisdicción, incluyendo IVA/IGV sobre sus ventas."
3. **Indemnidad:** "El Cliente mantendrá indemne a NV respecto de reclamos fiscales, de consumo o legales derivados de las ventas de su tienda."
4. **Cooperación con autoridades:** NV cooperará ante requerimientos legales (ej: datos de sellers ante autoridad fiscal).
5. **Takedown / notice and takedown:** NV puede suspender tienda ante contenido manifiestamente ilícito al tomar conocimiento fehaciente.
6. **Impuestos en destino:** "Los impuestos aplicables en la jurisdicción del Cliente (IVA, IGV, ISS, etc.) son responsabilidad exclusiva del Cliente."
7. **Conversión monetaria:** "NV factura en ARS al tipo de cambio oficial BNA. Las diferencias de tipo de cambio no generan obligación de ajuste."

> **Nota sobre Defensa del Consumidor:** Si un seller califica como "consumidor final" (Ley 24.240), NV podría estar en una relación de consumo respecto a su servicio SaaS. Esto implica obligaciones de información, cláusulas claras, derecho de revocación, y canales de reclamo. Evaluar con asesor si corresponde incluir botón de "arrepentimiento" y libro de quejas digital.

> **Nota sobre datos personales (AAIP):** NV trata datos de compradores de las tiendas (al menos name, email, dirección si hay envío). Esto genera obligaciones bajo la ley 25.326: base legal, medidas de seguridad, y potencial inscripción ante AAIP. Si sellers de otros países procesan datos de residentes de esos países, evaluar GDPR-like obligations (especialmente si hay compradores de la UE).

### Carril B2C — Definición y riesgos (NO habilitado en fase 1)

**Si NV habilitara suscripciones a personas físicas sin tax ID (B2C) fuera de Argentina**, se activan obligaciones de IVA/IGV digital que los países de destino exigen a prestadores no residentes:

| País | Autoridad | Obligación B2C no-residente | Referencia |
|------|-----------|---------------------------|------------|
| Chile | SII | IVA 19% sobre servicios remotos remunerados prestados por no residentes/no domiciliados | Ley 21.210 |
| México | SAT | Pago de IVA 16% sobre contraprestaciones cobradas + reportes trimestrales de operaciones con receptores en territorio nacional | Art. 18-B LIVA |
| Colombia | DIAN | Inscripción en RUT + firma electrónica + declaración/pago IVA periódico | Estatuto Tributario |
| Perú | SUNAT | Declarar/pagar IGV 18%; si no cumple, "facilitadores del pago" retienen/perciben | Ley 31736 |
| Uruguay | DGI | Régimen en evolución; consultas tributarias activas sobre IVA y plataformas digitales | — |

**Estrategia si se habilita B2C:**
1. Registro local país por país → costoso y lento
2. Uso de intermediario MoR (ej: Paddle, Lemon Squeezy) → pierde control pero evita registros
3. Geofencing: bloquear onboarding B2C en países con IVA digital exigible → simple pero pierde mercado

> **Trigger de escalación:** Si >5% del revenue o >10 sellers de un país son B2C (persona física sin tax ID), activar revisión de estrategia fiscal para ese país.

### Paquete mínimo de evidencia de ubicación (compliance)

Aunque NV factura todo con Factura E desde Argentina, es buena práctica guardar evidencia de territorialidad para auditoría y compliance:

| Evidencia | Para qué | Sensibilidad | Obligatoriedad | Campo DB |
|-----------|----------|:---:|---|---|
| País declarado + domicilio fiscal/billing | Factura E / contrato / auditoría | Media | **Obligatorio** en onboarding B2B y B2C | `nv_accounts.country`, `seller_fiscal_address` |
| Tax ID local (B2B) | Reduce exposición B2C; soporte documental | Media | **Obligatorio** para sellers fuera de AR en fase 1 | `nv_accounts.seller_fiscal_id` |
| IP + timestamp de alta | Señal técnica de ubicación | **Alta** (dato personal) | Recomendado con minimización/retención limitada | `nv_accounts.signup_ip`, `signup_ip_country` |
| País del medio de pago (PSP) | Señal fuerte de territorio donde se paga | Media | Recomendado — guardar como metadata | `orders.payer_country` (del webhook MP) |
| Aceptación de TyC (hash + versión) | Prueba contractual para disputes/auditoría | Baja | **Imprescindible** | `nv_accounts.tos_version`, `tos_accepted_at`, `tos_hash` |

---

## 3. CountryContext — Contrato y Resolución Determinística

### Definición

```typescript
interface CountryContext {
  /** MercadoPago site_id del seller — ej: 'MLA', 'MLC', 'MLM' */
  siteId: string;
  
  /** ISO 3166-1 alpha-2 del país del seller — ej: 'AR', 'CL', 'MX' */
  countryId: string;
  
  /** ISO 4217 currency code — ej: 'ARS', 'CLP', 'MXN' */
  currencyId: string;
  
  /** BCP 47 locale tag — ej: 'es-AR', 'es-CL', 'es-MX' */
  locale: string;
  
  /** IANA timezone — ej: 'America/Argentina/Buenos_Aires', 'America/Santiago' */
  timezone: string;
  
  /** Decimales de la moneda (0 para CLP, 2 para ARS/MXN) */
  currencyDecimals: number;
  
  /** Redondeo: 'round' | 'ceil' | 'floor' */
  roundingMode: 'round' | 'ceil' | 'floor';
  
  /** Separador de miles (punto o coma) */
  thousandsSeparator: '.' | ',';
  
  /** Separador decimal (coma o punto) */
  decimalSeparator: ',' | '.';

  // --- Campos fiscales (ver Sección 10) ---
  
  /** Tasa de IVA/IGV digital B2C del país destino (informativo, para pricing) */
  vatDigitalRate: number;  // 0.19 para CL, 0.16 para MX, 0.19 para CO, 0.18 para PE, 0.22 para UY, 0 para AR
  
  /** Si NV necesitaría registrarse en el régimen de IVA digital del país (B2C) */
  requiresDigitalVatRegistration: boolean;
  
  /** CUIT genérico del país destino (para Factura E ARCA) */
  arcaCuitPais: string;  // ej: '55000002206' para Chile
  
  /** Existe CDI (Convenio Doble Imposición) con Argentina */
  hasCdiWithAR: boolean;
}
```

### Tabla de referencia estática (seed)

| site_id | country | currency | locale | timezone | decimals | rounding | thousands | decimal |
|---------|---------|----------|--------|----------|----------|----------|-----------|---------|
| MLA | AR | ARS | es-AR | America/Argentina/Buenos_Aires | 2 | round | . | , |
| MLB | BR | BRL | pt-BR | America/Sao_Paulo | 2 | round | . | , |
| MLC | CL | CLP | es-CL | America/Santiago | 0 | round | . | *(none)* |
| MLM | MX | MXN | es-MX | America/Mexico_City | 2 | round | , | . |
| MCO | CO | COP | es-CO | America/Bogota | 0 | round | . | , |
| MLU | UY | UYU | es-UY | America/Montevideo | 2 | round | . | , |
| MPE | PE | PEN | es-PE | America/Lima | 2 | round | , | . |
| MEC | EC | USD | es-EC | America/Guayaquil | 2 | round | . | , |

> **ASSUMPTION:** Ecuador usa USD (lo confirma la referencia de ML). Paraguay (MPY) no está en la lista por bajo volumen, pero la tabla es extensible.

### Fuente de verdad

| Momento | Fuente de `CountryContext` |
|---------|---------------------------|
| **Onboarding OAuth callback** | `GET /users/me` con `access_token` del seller → MP retorna `site_id` → se mapea a la tabla de referencia → se persiste en `nv_accounts` |
| **Creación de checkout** | Se lee de `nv_accounts.mp_site_id` (vía `getAccountForClient()`) → se resuelve a `CountryContext` desde la tabla `country_configs` |
| **Creación de suscripción** | Idem checkout |
| **Webhooks** | La orden ya tiene `currency` persistido; se usa para display. Para validación de monto se compara en la moneda original |
| **Frontend (storefront)** | Se expone `CountryContext` como parte de `clientConfig` en el endpoint `/tenant-bootstrap` o similar → el frontend lo usa para `Intl.NumberFormat` |

### Resolución determinística

```
1. Seller conecta MP vía OAuth
2. Callback → exchangeCode → fetchMpOwnerInfo (ACTUAL) 
   + fetchMpUserSite (NUEVO: extraer site_id de /users/me)
3. site_id → lookup en country_configs → {country, currency, locale, tz, ...}
4. Persistir en nv_accounts: mp_site_id, country, currency
5. Sincronizar a clients y client_payment_settings (backend DB)
6. Toda operación downstream usa CountryContext resuelto del tenant
7. Si country_configs no tiene el site_id → RECHAZAR conexión con error descriptivo
```

**NUNCA se asume un default sin tener el dato real del seller.** Si no se puede resolver → error explícito.

---

## 4. Diseño de Datos

### 4.1 Nueva tabla: `country_configs` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS country_configs (
  site_id       text PRIMARY KEY,           -- 'MLA', 'MLC', etc.
  country_id    text NOT NULL,              -- 'AR', 'CL', etc.
  country_name  text NOT NULL,              -- 'Argentina', 'Chile'
  currency_id   text NOT NULL,              -- 'ARS', 'CLP'
  currency_name text NOT NULL,              -- 'Peso argentino', 'Peso chileno'
  locale        text NOT NULL DEFAULT 'es-AR',
  timezone      text NOT NULL DEFAULT 'America/Argentina/Buenos_Aires',
  currency_decimals smallint NOT NULL DEFAULT 2,
  rounding_mode text NOT NULL DEFAULT 'round',  -- 'round' | 'ceil' | 'floor'
  thousands_sep text NOT NULL DEFAULT '.',
  decimal_sep   text NOT NULL DEFAULT ',',
  mp_enabled    boolean NOT NULL DEFAULT true,   -- si MP opera en este país
  -- Campos fiscales (Sección 10)
  vat_digital_rate   numeric(5,4) NOT NULL DEFAULT 0,       -- tasa IVA/IGV digital B2C (0.19 para CL)
  requires_vat_registration boolean NOT NULL DEFAULT false,  -- si NV debe registrarse como MoR B2C
  arca_cuit_pais     text,                                   -- CUIT genérico del país para Factura E
  has_cdi_with_ar    boolean NOT NULL DEFAULT false,          -- CDI vigente con Argentina
  cdi_notes          text,                                   -- "CDI integral" vs "Notas reversales"
  created_at    timestamptz DEFAULT now(),
  updated_at    timestamptz DEFAULT now()
);

-- Seed
INSERT INTO country_configs VALUES
  ('MLA', 'AR', 'Argentina',  'ARS', 'Peso argentino', 'es-AR', 'America/Argentina/Buenos_Aires', 2, 'round', '.', ',', true, 0.21,   false, '50000000016', false, 'N/A — país local',             now(), now()),
  ('MLB', 'BR', 'Brasil',     'BRL', 'Real brasileño',  'pt-BR', 'America/Sao_Paulo',     2, 'round', '.', ',', true, 0,      false, '50000000582', false, 'Sin CDI con AR',               now(), now()),
  ('MLC', 'CL', 'Chile',      'CLP', 'Peso chileno',   'es-CL', 'America/Santiago',       0, 'round', '.', '',  true, 0.19,   true,  '55000002206', true,  'CDI integral vigente',         now(), now()),
  ('MLM', 'MX', 'México',     'MXN', 'Peso mexicano',  'es-MX', 'America/Mexico_City',    2, 'round', ',', '.', true, 0.16,   true,  '55000002338', true,  'CDI integral vigente',         now(), now()),
  ('MCO', 'CO', 'Colombia',   'COP', 'Peso colombiano', 'es-CO', 'America/Bogota',        0, 'round', '.', ',', true, 0.19,   true,  '55000002168', false, 'Solo notas reversales',        now(), now()),
  ('MLU', 'UY', 'Uruguay',    'UYU', 'Peso uruguayo',  'es-UY', 'America/Montevideo',     2, 'round', '.', ',', true, 0.22,   true,  '55000002842', false, 'Acuerdo intercambio info 2013', now(), now()),
  ('MPE', 'PE', 'Perú',       'PEN', 'Sol peruano',    'es-PE', 'America/Lima',           2, 'round', ',', '.', true, 0.18,   true,  '55000002604', false, 'Solo notas reversales',        now(), now()),
  ('MEC', 'EC', 'Ecuador',    'USD', 'Dólar',          'es-EC', 'America/Guayaquil',      2, 'round', '.', ',', true, 0.12,   false, '55000002249', false, 'Sin CDI con AR',               now(), now())
ON CONFLICT (site_id) DO NOTHING;
```

### 4.2 Columnas nuevas en `nv_accounts` (Admin DB)

```sql
ALTER TABLE nv_accounts
  ADD COLUMN IF NOT EXISTS mp_site_id text,                    -- 'MLA', 'MLB', etc.
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'AR',          -- ISO alpha-2
  ADD COLUMN IF NOT EXISTS currency text DEFAULT 'ARS',        -- ISO 4217
  ADD COLUMN IF NOT EXISTS locale text DEFAULT 'es-AR',        -- BCP 47
  ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'America/Argentina/Buenos_Aires';

-- Índice para queries por país
CREATE INDEX IF NOT EXISTS idx_nv_accounts_country ON nv_accounts(country);
```

### 4.3 Columnas nuevas en `clients` (Backend DB)

```sql
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS country text DEFAULT 'AR',
  ADD COLUMN IF NOT EXISTS locale text DEFAULT 'es-AR',
  ADD COLUMN IF NOT EXISTS timezone text DEFAULT 'America/Argentina/Buenos_Aires';
-- currency ya existe en client_payment_settings

CREATE INDEX IF NOT EXISTS idx_clients_country ON clients(country);
```

### 4.4 Columna `currency` en `orders` (Backend DB)

```sql
ALTER TABLE orders
  ADD COLUMN IF NOT EXISTS currency text DEFAULT 'ARS';
  ADD COLUMN IF NOT EXISTS exchange_rate numeric(12,4);           -- TC BNA vendedor divisa día hábil anterior
  ADD COLUMN IF NOT EXISTS exchange_rate_date date;               -- Fecha del TC aplicado
  ADD COLUMN IF NOT EXISTS exchange_rate_source text DEFAULT 'BNA_VENDEDOR_DIVISA'; -- Fuente del TC
  ADD COLUMN IF NOT EXISTS total_ars numeric(12,2);               -- Equivalente en ARS al TC (para contabilidad NV)
-- Para conciliación: saber en qué moneda se cobró cada orden y el equivalente contable
```

### 4.5 Nueva tabla: `nv_invoices` (Admin DB) — Facturas E de NV

Registra las Facturas E que NovaVision emite a sellers por comisión/plataforma. Es independiente del sistema de facturación del seller a sus compradores.

```sql
CREATE TABLE IF NOT EXISTS nv_invoices (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id         uuid NOT NULL REFERENCES clients(id),       -- el seller/tenant
  
  -- Identificación fiscal del comprobante
  invoice_type      text NOT NULL DEFAULT 'E',                   -- 'E' (exportación), 'B' (nacional), etc.
  punto_venta       integer NOT NULL,                            -- Punto de venta ARCA
  numero            bigint NOT NULL,                             -- Número correlativo
  cae               text,                                        -- Código de Autorización Electrónico
  cae_vencimiento   date,
  
  -- Datos del receptor (seller en su país)
  receptor_nombre   text NOT NULL,
  receptor_pais     text NOT NULL,                               -- ISO alpha-2 ('CL', 'MX')
  receptor_cuit_pais text,                                       -- CUIT genérico del país destino (tablas ARCA)
  receptor_id_fiscal text,                                       -- RUT/RFC/NIT del seller en su país
  
  -- Montos
  currency          text NOT NULL,                               -- Moneda de la factura ('ARS' o moneda extranjera)
  subtotal          numeric(12,2) NOT NULL,
  iva_amount        numeric(12,2) NOT NULL DEFAULT 0,            -- 0 en exportación (exenta/0%)
  total             numeric(12,2) NOT NULL,
  
  -- Tipo de cambio (obligatorio para Factura E según ARCA)
  exchange_rate     numeric(12,4),                               -- TC BNA vendedor divisa día hábil anterior
  exchange_rate_date date,
  total_ars         numeric(12,2),                               -- Equivalente en ARS
  
  -- Vinculación con pagos/operaciones
  related_period    text,                                        -- 'YYYY-MM' o rango
  related_order_ids uuid[],                                      -- Órdenes cubiertas por esta factura
  marketplace_fee_total numeric(12,2),                           -- Total de marketplace_fee en el período
  
  -- Estado
  status            text NOT NULL DEFAULT 'draft',               -- 'draft', 'authorized', 'sent', 'cancelled'
  pdf_url           text,                                        -- URL del PDF generado
  xml_url           text,                                        -- URL del XML firmado
  
  -- Auditoría
  created_by        text,
  created_at        timestamptz DEFAULT now(),
  updated_at        timestamptz DEFAULT now(),
  
  UNIQUE(punto_venta, numero, invoice_type)
);

CREATE INDEX idx_nv_invoices_client ON nv_invoices(client_id);
CREATE INDEX idx_nv_invoices_period ON nv_invoices(related_period);
CREATE INDEX idx_nv_invoices_status ON nv_invoices(status);
```

> **Nota:** Esta tabla NO reemplaza la tabla `invoices` existente (que registra la facturación interna NV → seller por plan/cuota mensual). `nv_invoices` es específicamente para Facturas E de exportación por comisiones de marketplace.

### 4.6 Columnas adicionales en `nv_accounts` (Admin DB) — datos fiscales del seller

```sql
ALTER TABLE nv_accounts
  ADD COLUMN IF NOT EXISTS seller_fiscal_id text,               -- RUT/RFC/NIT/CNPJ del seller
  ADD COLUMN IF NOT EXISTS seller_fiscal_name text,             -- Razón social fiscal del seller
  ADD COLUMN IF NOT EXISTS seller_fiscal_address text,          -- Domicilio fiscal (para Factura E)
  ADD COLUMN IF NOT EXISTS seller_activity_declaration text,    -- Declaración de actividad comercial del seller
  ADD COLUMN IF NOT EXISTS seller_b2b_declaration boolean DEFAULT false,  -- Seller declara que opera como empresa/profesional (B2B)
  ADD COLUMN IF NOT EXISTS seller_b2b_declared_at timestamptz,  -- Fecha en que aceptó la declaración B2B
  -- Evidencia de ubicación/compliance (Sección 2)
  ADD COLUMN IF NOT EXISTS signup_ip inet,                       -- IP de registro (dato personal, retención limitada)
  ADD COLUMN IF NOT EXISTS signup_ip_country text,               -- País resuelto de la IP (GeoIP)
  ADD COLUMN IF NOT EXISTS tos_version text,                     -- Versión de TyC aceptados (ej: 'v2.1')
  ADD COLUMN IF NOT EXISTS tos_accepted_at timestamptz,          -- Fecha/hora de aceptación
  ADD COLUMN IF NOT EXISTS tos_hash text;                        -- SHA-256 del documento aceptado
```

> **Nota B2B-only:** Los campos `seller_b2b_declaration` y `seller_b2b_declared_at` son requeridos por la política de verificación B2B (Sección 2). Al onboardear un seller internacional, el flujo debe exigir que:
> 1. Complete `seller_fiscal_id`, `seller_fiscal_name`, `seller_fiscal_address`
> 2. Declare actividad comercial (`seller_activity_declaration`)
> 3. Acepte checkbox B2B (`seller_b2b_declaration = true`), registrando timestamp
> Sin estos campos completos, el seller no debe poder publicar tienda.

### 4.7 Fee schedules versionadas: `fee_schedules` + `fee_schedule_lines`

```sql
-- Reemplaza mp_fee_table con un modelo versionado
CREATE TABLE IF NOT EXISTS fee_schedules (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  country_id    text NOT NULL,             -- 'AR', 'CL', etc.
  currency_id   text NOT NULL,             -- 'ARS', 'CLP'
  source        text NOT NULL DEFAULT 'manual',  -- 'manual' | 'api' | 'scraped'
  valid_from    date NOT NULL,
  valid_to      date,                      -- NULL = vigente
  notes         text,
  created_by    text,
  created_at    timestamptz DEFAULT now(),
  
  UNIQUE(country_id, valid_from)
);

CREATE TABLE IF NOT EXISTS fee_schedule_lines (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  schedule_id     uuid NOT NULL REFERENCES fee_schedules(id) ON DELETE CASCADE,
  payment_method  text NOT NULL,           -- 'credit_card', 'debit_card', 'account_money', 'bank_transfer', 'ticket'
  installments_from smallint NOT NULL DEFAULT 1,
  installments_to   smallint NOT NULL DEFAULT 1,
  settlement_days   smallint NOT NULL,     -- 0, 10, 14, 28, etc. (varía por país)
  percent_fee     numeric(6,4) NOT NULL,   -- 4.99 → 0.0499
  fixed_fee       numeric(12,2) NOT NULL DEFAULT 0,
  tax_included    boolean NOT NULL DEFAULT false,
  notes           text,
  
  UNIQUE(schedule_id, payment_method, installments_from, installments_to, settlement_days)
);

-- Índices
CREATE INDEX idx_fsl_schedule ON fee_schedule_lines(schedule_id);
CREATE INDEX idx_fs_country_valid ON fee_schedules(country_id, valid_from DESC);
```

### 4.8 Plan de migración (sin downtime)

| Paso | Acción | Downtime | Rollback |
|------|--------|----------|----------|
| 1 | `ALTER TABLE ADD COLUMN ... DEFAULT` en nv_accounts/clients/orders | NO — defaults no bloquean | `ALTER TABLE DROP COLUMN` |
| 2 | `CREATE TABLE country_configs` + seed | NO | `DROP TABLE` |
| 3 | Backfill `country='AR'`, `currency='ARS'` para todos los registros existentes | NO — son defaults | N/A |
| 4 | `CREATE TABLE fee_schedules` + seed AR desde `mp_fee_table` actual | NO | `DROP TABLE` |
| 5 | Deploy código que LEA de columnas nuevas pero con fallback a hardcodes | NO | Revert deploy |
| 6 | Capturar `site_id` en OAuth callback (solo nuevos sellers) | NO | Revert code |
| 7 | Migrar código para USAR columnas nuevas en vez de hardcodes (gradual por módulo) | NO | Feature flags |
| 8 | Deprecar `mp_fee_table` vieja cuando `fee_schedules` esté validada | NO | Re-enable vieja |

---

## 5. Templates Bulletproof

### 5.1 Inventario de templates existentes

| Template | Archivo principal | Inputs actuales | CountryContext? |
|----------|-------------------|-----------------|-----------------|
| Crear preferencia checkout | `mercadopago.service.ts → createPreferenceUnified()` | items, payer, back_urls, totals | ❌ Hardcodea ARS |
| Crear suscripción/plan | `platform-mercadopago.service.ts → createPreApproval()` | plan, amount, email | ❌ Hardcodea ARS |
| URLs/redirects (back_urls) | Dentro de createPreferenceUnified | baseUrl del tenant | ✅ OK (dinámico) |
| Webhook handler | `mp-router.service.ts` + `mercadopago.service.ts → confirmPayment()` | payment_id, order | ❌ No valida currency |
| Emails de pago | `mercadopago.service.ts → notifyOrderComplete()` | order data | ❌ Formatea ARS |
| SEO meta tags | `seo.service.ts` | product data | ❌ Hardcodea es_AR/ARS |
| Formateo de precios (web) | `formatCurrency.jsx`, `quoteHelpers.js` | amount | ❌ Hardcodea es-AR/ARS |
| Cotización shipping | `shipping-quote.service.ts` | zone, weight | ❌ Fallback ARS |
| Import CSV productos | `products.service.ts → importCsv()` | CSV data | ❌ Whitelist solo [ARS,USD] |

### 5.2 Template refactorizado: Crear preferencia

```typescript
// ANTES (inseguro)
const currency = totals?.currency || 'ARS';  // ← HARDCODE

// DESPUÉS (bulletproof)
async createPreferenceUnified(/* ... */) {
  // 1. Resolver CountryContext del tenant
  const ctx = await this.resolveCountryContext(clientId);
  
  // 2. Validar que currency del tenant == currency del CountryContext
  if (ctx.currencyId !== tenantCurrency) {
    throw new BadRequestException(
      `Currency mismatch: tenant=${tenantCurrency}, country=${ctx.currencyId}`
    );
  }
  
  // 3. Usar currency del CountryContext
  items.forEach(item => {
    item.currency_id = ctx.currencyId;
    item.unit_price = this.roundForCurrency(item.unit_price, ctx);
  });
  
  // 4. Payer country
  preferenceData.payer.address = {
    ...preferenceData.payer.address,
    country: ctx.countryId,  // NO hardcodear 'AR'
  };
}
```

### 5.3 Template refactorizado: Crear suscripción

```typescript
// ANTES
currency_id: 'ARS' as const,  // ← HARDCODE

// DESPUÉS
const ctx = await this.resolveCountryContext(clientId);
const planBody = {
  // ...
  auto_recurring: {
    frequency: 1,
    frequency_type: 'months',
    transaction_amount: this.roundForCurrency(amount, ctx),
    currency_id: ctx.currencyId,  // ← del CountryContext
  },
};
```

### 5.4 Template refactorizado: Webhook handler

```typescript
// Al procesar webhook, validar currency
const order = await this.getOrder(orderId);
const paymentInfo = await this.fetchMpPayment(paymentId, accessToken);

if (paymentInfo.currency_id !== order.currency) {
  this.logger.error(`Currency mismatch in webhook: payment=${paymentInfo.currency_id}, order=${order.currency}`);
  // Procesar igualmente pero alertar
  await this.alertOps('CURRENCY_MISMATCH', { orderId, expected: order.currency, got: paymentInfo.currency_id });
}
```

### 5.5 Template refactorizado: Frontend formateo

```typescript
// ANTES (hardcodeado)
export function formatCurrency(amount) {
  return new Intl.NumberFormat("es-AR", { style: "currency", currency: "ARS" }).format(amount);
}

// DESPUÉS (del CountryContext del tenant)
export function formatCurrency(amount, { locale, currencyId } = {}) {
  const l = locale || tenantConfig?.locale || 'es-AR';
  const c = currencyId || tenantConfig?.currency || 'ARS';
  return new Intl.NumberFormat(l, { style: "currency", currency: c }).format(amount);
}
```

### 5.6 Validaciones obligatorias por template

| Validación | Dónde | Qué previene |
|-----------|-------|--------------|
| `currency_id` en items == `CountryContext.currencyId` | createPreference | MP rechaza preference |
| `currency_id` en auto_recurring == `CountryContext.currencyId` | createPreApproval | Suscripción falla |
| `order.currency` == `payment.currency_id` | webhook handler | Conciliación incorrecta |
| `external_reference` contiene `clientId` | createPreference | Trazabilidad cross-tenant |
| `roundForCurrency()` aplicado a todos los montos | Todos los templates | CLP sin decimales, ARS con 2 |
| `marketplace_fee` calculado desde `fee_schedules` | createPreference (futuro) | Comisión NV correcta por país |

---

## 6. Fees: Modelo, Carga y Mantenimiento

### 6.1 Dimensiones del modelo de fees

| Dimensión | Ejemplo | Fuente |
|-----------|---------|--------|
| País/site_id | AR/MLA, CL/MLC | OAuth del seller |
| Moneda | ARS, CLP | Derivado del país |
| Producto/flujo | checkout vs suscripción | Tipo de operación |
| Medio de pago | credit_card, debit_card, account_money, bank_transfer, ticket | MP payment_method_id |
| Cuotas | 1, 3, 6, 12, 18 | installments |
| Plazo de disponibilidad | 0, 10, 14, 28 días | settlement_days (configurable por seller en MP) |
| Fee del PSP (MP) | % + fijo | Varía por todo lo anterior |
| Fee de marketplace (NV) | % sobre venta | `marketplace_fee` en preferencia |
| Vigencia temporal | valid_from / valid_to | Versionado |
| **IVA/Retención sobre fee MP (AR)** | 21% IVA sobre comisión MP | Factura que MP emite a NV |
| **Retenciones provinciales (IIBB)** | Varía por jurisdicción | Padrón SIRCUPA (PBA) / AGIP (CABA) etc. |
| **IVA digital destino (B2C)** | 12%-22% según país | Solo si NV fuera MoR (Modelo B) — **NO aplica con Modelo A** |

### 6.2 Seed por país (datos reales a completar)

#### Argentina (MLA) — Ya cargado en `mp_fee_table`
- Crédito 1 cuota / disponibilidad inmediata: 5.99% + IVA
- Crédito 1 cuota / 14 días: 4.49% + IVA
- Débito / inmediata: 2.99% + IVA
- Transferencia: 0.5%
- Etc.

#### Chile (MLC) — **PENDIENTE**
- **ASSUMPTION:** Comisiones MP Chile: crédito ~3.49-4.49%, débito ~1.49-2.49%, transferencia ~0.99% (verificar en panel MP Chile)
- CLP NO tiene decimales → `currency_decimals: 0`
- Cuotas: MP Chile ofrece hasta 48 cuotas (vs 12 en AR)

#### México (MLM) — **PENDIENTE**
- **ASSUMPTION:** Comisiones MP México: crédito ~3.49-4.99%, débito ~2.49%, OXXO ~2.99%
- MXN tiene 2 decimales
- Métodos adicionales: OXXO (efectivo), SPEI (transferencia)

#### Colombia (MCO) — **PENDIENTE**
- COP NO tiene decimales (en la práctica)
- Métodos adicionales: PSE (transferencia), Efecty (efectivo)

### 6.3 Reglas de redondeo por moneda

| Moneda | Decimales | Regla | Ejemplo |
|--------|-----------|-------|---------|
| ARS | 2 | `Math.round(amount * 100) / 100` | 1234.567 → 1234.57 |
| CLP | 0 | `Math.round(amount)` | 1234.567 → 1235 |
| MXN | 2 | `Math.round(amount * 100) / 100` | 1234.567 → 1234.57 |
| COP | 0 | `Math.round(amount)` | 1234567.89 → 1234568 |
| BRL | 2 | `Math.round(amount * 100) / 100` | 1234.567 → 1234.57 |
| UYU | 2 | `Math.round(amount * 100) / 100` | 1234.567 → 1234.57 |
| PEN | 2 | `Math.round(amount * 100) / 100` | 1234.567 → 1234.57 |

### 6.4 Mecanismo de mantenimiento

| Mecanismo | Frecuencia | Responsable |
|-----------|------------|-------------|
| **Carga manual desde panel super-admin** | Al agregar país nuevo o cuando MP cambia tarifas | Ops/Finance |
| **Alerta de desvío fee estimada vs real** | Por cada pago: comparar fee estimada (de `fee_schedule_lines`) vs fee real (del webhook payment.fee_details) | Automático |
| **SLA de revisión** | Mensual por país activo | Ops |
| **Auditoría** | Cada cambio en `fee_schedules` genera log con `created_by`, `source`, `notes` | Automático |

### 6.5 Modelo de tres capas de pricing (contractual / operativo / fiscal)

Para evitar descalces documentales entre lo cobrado, lo facturado y lo registrado, el pricing de NV debe operar en **tres capas separadas**:

| Capa | Nombre | Moneda | Ejemplo | Dónde se usa |
|------|--------|--------|---------|---------------|
| **1. Precio base (contractual)** | Precio acordado en contrato/TyC | USD (recomendado) | "USD 20/mes" | Contrato, orden de compra, TyC |
| **2. Precio de cobro (operativo)** | Monto enviado al PSP en moneda local | Moneda local del seller | 18.500 CLP, 350 MXN | `marketplace_fee` en preferencia MP, suscripción |
| **3. Precio fiscal (comprobante)** | Importe en la Factura E | USD o ARS | USD 20 o ARS equiv. al TC BNA | Factura E, registro contable ARCA |

**Reglas de conversión entre capas:**
- **Capa 1 → Capa 2:** TC comercial (puede ser tipo de cambio de mercado, definido por NV). **Esto es lógica comercial, no fiscal.**
- **Capa 2 → Capa 3:** Si Factura E en ARS, usar TC BNA vendedor divisa del día hábil anterior (ARCA). Si Factura E en USD, la conversión fiscal la hace ARCA automáticamente.
- **NUNCA** usar un TC no oficial (ej: "dolar blue") como base de conversión en la Capa 3 (fiscal). Ver Q15.

> **Enfoque robusto recomendado:** Contrato en USD + Factura E en USD, dejando que el TC oficial opere solo para la valuación fiscal/contable. Esto minimiza puntos de fricción y descalces. Si NV cobra el equivalente en ARS usando un TC comercial distinto al oficial, eso es una decisión de pricing (Capa 1→2), no un problema fiscal mientras la Factura E (Capa 3) use el TC correcto.

> **Cross-reference:** El concepto de `FX_ref` para Capa 1→2 está desarrollado en detalle en [PLANS_LIMITS_ECONOMICS.md §3.3](PLANS_LIMITS_ECONOMICS.md) como el tipo de cambio usado para expresar planes en ARS. La decisión D2 de ese documento debe alinearse con las capas aquí definidas.

### 6.6 Cálculo de precio final y neto al seller

```
precio_producto = price (del catálogo, en currency del tenant)
subtotal = Σ(precio_producto × qty) 
extras = costos extra del tenant (client_extra_costs)
service_fee = fee del servicio NV (configurable)
mp_fee = lookup en fee_schedule_lines(country, method, installments, settlement_days)
marketplace_fee = comisión NV (% configurable por plan, Secc. 10)

// Para el comprador:
total_buyer = roundForCurrency(subtotal + extras + service_fee + shipping, ctx)

// Para el seller (neto que MP acredita):
neto_seller = total_buyer - mp_fee_real - marketplace_fee

// Para NV (ingreso por comisión):
// IMPORTANTE: marketplace_fee se expresa en MONEDA LOCAL del seller (documentado por MP).
// No es "USD" — es CLP, MXN, COP, etc. según el país del seller.
ingreso_nv_moneda_local = marketplace_fee  // en la moneda del seller
ingreso_nv_ars = marketplace_fee × exchange_rate_bna_vendedor  // equivalente contable para Factura E
// NOTA: TC = BNA VENDEDOR DIVISA del día hábil anterior (NO comprador)

// Facturación NV → Seller:
// Emitir Factura E por ingreso_nv_ars (o en moneda extranjera con TC vendedor BNA)
// IVA = $0 (exportación exenta)
// Vincular con order_ids del período

// ADVERTENCIA: No diseñar "USD neto constante" sin capa de FX.
// Incluso con MP Cross Border (cobro local / retiro externo), el neto real
// depende de: (i) TC cobro local, (ii) comisiones MP locales,
// (iii) conversión y costos de retiro, (iv) retenciones en destino.
// Ver Sección 10.8 sobre MP Cross Border.
```

### 6.7 Conciliación fiscal por operación

**Flujo contable por cada pago (Modelo A: seller MoR):**

```
Evento                           Debe (NV)                           Haber (NV)
─────────────────────────────────────────────────────────────────────────────────
1. MP acredita marketplace_fee   Créditos x cobrar MP (ARS equiv.)   Ingresos exportación servicios
2. MP liquida a NV               Banco/CVU                           Créditos x cobrar MP
                                 Gastos comisión MP (fee s/fact MP)  Banco/CVU (neto)
3. Si retención IIBB (SIRCUPA)   Impuestos a cuenta IIBB             Banco/CVU (menos retención)
```

**Datos a persistir por pago para conciliación:**
- `order.currency` + `order.exchange_rate` + `order.total_ars`
- `marketplace_fee_amount` (en moneda local del seller)
- `marketplace_fee_ars` (equivalente al TC vendedor divisa BNA del día)
- `mp_fee_real` (del webhook `fee_details`)
- `nv_invoice_id` (referencia a la Factura E que cubre esa comisión)

---

## 7. Plan de QA, Monitoreo y Release

### 7.1 Matriz de pruebas

| País | Moneda | Flujo | Método | Escenario | Test |
|------|--------|-------|--------|-----------|------|
| AR | ARS | Checkout | Crédito 1 cuota | Aprobado | E2E |
| AR | ARS | Checkout | Débito | Rechazado | E2E |
| AR | ARS | Suscripción | Crédito | Alta + cobro | E2E |
| CL | CLP | Checkout | Crédito 1 cuota | Aprobado | E2E |
| CL | CLP | Checkout | Débito | Aprobado | E2E |
| CL | CLP | Checkout | Transferencia | Pending → Aprobado | E2E |
| CL | CLP | Suscripción | Crédito | Alta | E2E |
| MX | MXN | Checkout | Crédito 3 cuotas | Aprobado | E2E |
| MX | MXN | Checkout | OXXO | Pending → Aprobado | E2E |
| CO | COP | Checkout | Crédito | Aprobado | E2E |
| CO | COP | Checkout | PSE | Pending → Aprobado | E2E |
| * | * | Webhook | Duplicado | Idempotente | Unit |
| * | * | Webhook | Currency mismatch | Alerta + procesa | Unit |
| * | * | OAuth | Callback otro país | Registra site_id | Integration |
| * | * | Formateo | Precio en locale correcto | Unit |
| * | * | Redondeo | CLP sin decimales | Unit |

### 7.2 Tests automáticos requeridos

#### Unit tests
- `roundForCurrency(amount, ctx)` — para cada moneda
- `resolveCountryContext(clientId)` — retorna contexto correcto
- `formatCurrency(amount, ctx)` — formatea según locale
- `buildPreferenceItems(items, ctx)` — currency_id correcto
- `validateCurrencyMatch(order, payment)` — detecta mismatch

#### Integration tests
- OAuth callback → persiste `mp_site_id` + `country` + `currency` en `nv_accounts`
- Sync `nv_accounts` → `clients` propaga `country`/`currency`
- `createPreferenceUnified()` con tenant CL → `currency_id: 'CLP'` en preferencia
- Fee lookup con `country_code: 'CL'` → retorna fee chilena

#### E2E tests (con test users de MP por país)
- **ASSUMPTION:** MP permite crear test users por país vía API (`/users/test_user`). Cada país requiere un test user separado.
- Flujo completo: onboarding → conectar MP (país X) → crear producto → checkout → pago → webhook → orden completada

### 7.3 Tests anti-hardcode (build guardrails)

```bash
# Script que falla el CI si hay hardcodes de país/moneda fuera de country_configs
# Agregar a pre-push-check.sh

echo "Checking for hardcoded currency..."
HARDCODES=$(grep -rn "'ARS'" apps/api/src/ apps/web/src/ \
  --include="*.ts" --include="*.tsx" --include="*.js" --include="*.jsx" \
  | grep -v "node_modules" | grep -v "country_configs" | grep -v "test" \
  | grep -v "migration" | grep -v "seed" | grep -v ".spec." \
  | grep -v "DEFAULT 'ARS'" | grep -v "demo" | wc -l)

if [ "$HARDCODES" -gt 0 ]; then
  echo "❌ Found $HARDCODES hardcoded 'ARS' references outside allowed locations"
  exit 1
fi
```

### 7.4 Métricas y alertas

| Métrica | Alerta si | Dashboard |
|---------|-----------|-----------|
| Tasa de aprobación por país | < 60% (AR) o < 50% (otros) | Analytics |
| Currency mismatch en webhooks | > 0 | Slack #ops-alerts |
| Token expiración sin refresh | > 1 en 24h | Slack #ops-alerts |
| Webhook failures por país | > 5% de total | Grafana |
| Fee estimada vs fee real (desvío) | > 1% del monto | Finance report |
| Sellers conectados por país | Dashboard (no alerta) | Admin |
| Conversión checkout por país | < 50% del baseline AR | Analytics |

### 7.5 Release gradual (feature flags)

| Fase | Feature Flag | Qué habilita | Rollback |
|------|-------------|--------------|----------|
| 0 | `i18n_capture_site_id` | Solo capturar site_id en OAuth, sin cambiar lógica | Revert deploy |
| 1 | `i18n_country_context` | Resolver CountryContext y propagar a checkout | Flag OFF |
| 2 | `i18n_allow_cl` | Permitir sellers de Chile (MLC) | Flag OFF |
| 3 | `i18n_allow_mx` | Permitir sellers de México (MLM) | Flag OFF |
| 4 | `i18n_all_latam` | Todos los países habilitados | Flag OFF |

### 7.6 Criterios de habilitación fiscal por país

Un país solo debe habilitarse (feature flag ON) cuando se cumplen TODOS los criterios:

| # | Criterio | Verificación |
|---|----------|-------------|
| 1 | Fee schedule cargado y validado para el país | `fee_schedules` tiene datos vigentes |
| 2 | Carril B2B completo: formulario de onboarding pide tax ID local + validación de formato | Probado en staging |
| 3 | `country_configs` tiene seed completo (moneda, locale, tz, CUIT país, vat_digital_rate) | Seed verificado |
| 4 | Flujo cobro → factura → registro puede conciliarse end-to-end | Test de conciliación manual aprobado |
| 5 | TyC actualizados con cláusulas de impuestos en destino y B2B | Versión contractual publicada |
| 6 | Al menos 1 test user de MP del país creado y E2E aprobado | QA report |

> **Política de "país habilitado":** Habilitar país solo cuando el carril B2B esté completo y se pueda conciliar cobro→factura→registro. Si se omite este gate, el riesgo fiscal y operativo aumenta sin control.

---

## 8. Cronograma y Fases

### Fase 0: Captura de datos (1-2 días) — SIN RIESGO

| Tarea | Detalle | Archivos |
|-------|---------|----------|
| Migración DB: agregar columnas a nv_accounts | `mp_site_id`, `country`, `currency`, `locale`, `timezone` | `migrations/admin/` |
| Migración DB: agregar columnas a clients | `country`, `locale`, `timezone` | `migrations/backend/` |
| Migración DB: agregar `currency` a orders | Para conciliación | `migrations/backend/` |
| Crear tabla `country_configs` + seed | 8 países LATAM | `migrations/admin/` |
| Actualizar `fetchMpOwnerInfo()` | Extraer `site_id` de `/users/me` | `mp-oauth.service.ts` |
| Persistir `site_id` + country en OAuth callback | Lookup en `country_configs`, guardar en `nv_accounts` | `mp-oauth.service.ts` |
| Sync country/currency a clients (backend DB) | En el sync existente nv_accounts → clients | `mp-oauth.service.ts` |
| Backfill: todos los registros existentes = AR/ARS/MLA | UPDATE masivo con defaults | Script SQL |

### Fase 1: CountryContext + refactor backend (3-5 días)

| Tarea | Detalle |
|-------|---------|
| Crear `CountryContextService` | Resuelve CountryContext por clientId, cachea en Redis |
| Refactorizar `createPreferenceUnified()` | Usar `ctx.currencyId` en vez de `'ARS'` |
| Refactorizar `createPreApproval()` | Idem |
| Refactorizar `confirmPayment()` (webhook) | Validar currency match |
| Refactorizar `analytics.service.ts` | Resolver tz/currency del tenant |
| Actualizar `VALID_CURRENCIES` en import CSV | Agregar CLP, MXN, COP, BRL, UYU, PEN |
| Crear `roundForCurrency()` utility | Redondeo correcto por moneda |
| Crear tabla `fee_schedules` + migrar datos AR | Desde `mp_fee_table` actual |

### Fase 2: Refactor frontend (3-4 días)

| Tarea | Detalle |
|-------|---------|
| Exponer `CountryContext` en tenant bootstrap | API → FE via clientConfig |
| Refactorizar `formatCurrency.jsx` | Aceptar locale/currency del CountryContext |
| Refactorizar `dateFormat.jsx` | Aceptar timezone del CountryContext |
| Refactorizar SEO meta tags | `og:locale` y `product:price:currency` dinámicos |
| Refactorizar ~30 `toLocaleString('es-AR')` | Usar locale del tenant |
| Actualizar `homeData.schema.ts` | Agregar monedas LATAM al enum |

### Fase 3: Fee tables + marketplace_fee + facturación (3-5 días)

| Tarea | Detalle |
|-------|---------|
| Seed fee_schedules para CL, MX, CO | Datos de comisiones reales |
| Implementar `marketplace_fee` en preferencias | Comisión NV por operación |
| Panel super-admin para gestionar fees | CRUD fee_schedules con versionado |
| Alerta de desvío fee estimada vs real | Comparar fee_details del webhook |
| **NUEVO:** Servicio de tipo de cambio BNA | Consulta diaria TC **vendedor divisa** BNA, cachea en Redis/DB |
| **NUEVO:** Tabla `nv_invoices` + CRUD | Alta/consulta de Facturas E (draft → authorized → sent) |
| **NUEVO:** Modelo de datos fiscales del seller | Recopilar RUT/RFC/NIT en onboarding (campos opcionales, luego obligatorios) |

### Fase 4: QA + release por país (2-3 días por país)

| Tarea | Detalle |
|-------|---------|
| Crear test users MP por país | Vía API de MP |
| E2E por país (AR, CL, MX, CO) | Matriz completa |
| Habilitar feature flag por país | Gradual |
| Monitoreo post-release | 1 semana por país |
| **NUEVO:** Validar Factura E con ARCA | Emitir factura de prueba en sandbox ARCA |
| **NUEVO:** Validar conciliación fiscal | marketplace_fee == monto facturado en Factura E |

### Fase 5 (paralela): Habilitación fiscal — REQUIERE DECISIONES DEL TL

| Tarea | Detalle | Bloqueante |
|-------|---------|-----------|
| Habilitar punto de venta Factura E ante ARCA | Trámite ante ARCA (si no existe) | Sí — sin esto no hay facturación |
| Integrar Web Services ARCA para CAE automático | O definir proceso manual/semi-automático | No bloqueante si se emite manual al inicio |
| Actualizar TyC/contratos con sellers | Incluir cláusulas impuestos destino + conversión monetaria | Sí para go-live multi-país |
| Consulta BCRA sobre encuadre de liquidación | Confirmar si aplica excepción para persona jurídica | Sí — riesgo regulatorio |
| Confirmar derechos de exportación vigentes | Alícuota actual para la actividad de NV | Sí — impacta pricing |

**Total estimado: ~20-25 días de desarrollo (1 developer) + tiempo de trámites fiscales (Fase 5).**
**Fase 5 puede correr en paralelo con Fases 0-4, pero debe completarse ANTES del go-live multi-país.**

---

## 9. Preguntas de Descubrimiento

| # | Pregunta | Impacto si no se define | Estado |
|---|----------|------------------------|--------|
| 1 | ¿NovaVision cobraría `marketplace_fee` a MP (retención automática) o factura por separado a los sellers? | Define si implementamos marketplace_fee en preferencias o no | **RESPONDIDA**: Usar `marketplace_fee` (retención automática por MP) + emitir Factura E al seller por la comisión. Ambos montos deben coincidir. |
| 2 | ¿Hay planes de pricing diferenciados por país? (ej: plan basic en AR = $X ARS, en CL = $Y CLP) | Define si `nv_accounts.monthly_fee` necesita `currency` | ABIERTA |
| 3 | ¿El super admin de NV cobra en ARS siempre (empresa argentina) o en moneda local del seller? | Define conciliación y facturación | **RESPONDIDA**: NV factura en ARS (Factura E con TC BNA vendedor divisa). `marketplace_fee` se cobra en moneda local del seller pero NV contabiliza en ARS al TC del día. |
| 4 | ¿Hay requisitos legales por país? (ej: factura electrónica en México, boleta en Chile) | Define si se necesita módulo de facturación por país | **RESPONDIDA**: Con Modelo A (seller MoR), la facturación local al comprador es responsabilidad del seller. NV solo emite Factura E B2B. Ver Sección 10. |
| 5 | ¿Se habilitarían todos los países a la vez o uno por uno? | Define si feature flags por país son necesarios | ABIERTA — plan propone uno por uno (Sección 7.5) |
| 6 | ¿Los sellers pueden tener productos en USD además de su moneda local? | Define si el catálogo es single-currency o multi-currency por tenant | ABIERTA |
| 7 | ¿Test users de MP de otros países están disponibles en el plan actual de MP? | Define si podemos hacer E2E reales o solo simulados | ABIERTA |
| 8 | ¿El shipping (envío) operaría en otros países o solo el checkout? | Define alcance de i18n en shipping module | ABIERTA |
| 9 | ¿NV está inscripta como exportadora de servicios ante ARCA? ¿Tiene punto de venta habilitado para Factura E? | Bloquea toda facturación B2B al exterior | ABIERTA — **CRÍTICA** |
| 10 | ¿Qué régimen tributario tiene NV (Responsable Inscripto / Monotributo)? | Define tratamiento IVA en exportación y formato de Factura E. **Nota:** ambos regímenes permiten Factura E (ARCA lo confirma para monotributo), pero difieren en crédito fiscal IVA y topes de facturación. Ver tabla comparativa en Sección 10.1 | ABIERTA — **CRÍTICA** |
| 11 | ¿NV tiene estructura para liquidar cobros de exportación ante BCRA dentro de los 20 días hábiles? ¿O aplica la excepción de Com. "A" 8330? | Riesgo cambiario/regulatorio si no se cumple | ABIERTA |
| 12 | ¿NV tiene o va a tener un representante contable/fiscal que gestione Factura E y declaraciones? ¿O se delega al sistema? | Define si se necesita integración con Web Services ARCA para CAE automático o si se emite manual | ABIERTA |
| 13 | ¿La comisión de NV a sellers (marketplace_fee) incluye o no IVA? (En exportación sería 0%/exenta, pero debe estar definido contractualmente) | Afecta montos en Factura E y en la configuración de marketplace_fee en MP | ABIERTA |
| 14 | ¿NV tiene contratos/TyC con sellers que incluyan cláusula de impuestos en destino y conversión monetaria? | Riesgo contractual si un seller desconoce sus obligaciones fiscales locales | ABIERTA |
| 15 | **NUEVA:** ¿El pricing de suscripciones NV se actualiza con referencia a algún TC no oficial (ej: "dólar blue")? | Riesgo de **descalce documental**: lo cobrado vs Factura E vs registro contable. ARCA exige TC BNA vendedor divisa para comprobantes en moneda extranjera | ABIERTA — **RIESGO ALTO** |
| 16 | **NUEVA:** ¿La cuenta MP de NV tiene habilitado MP Cross Border (cobrar local / retirar en otro país)? | Si no está habilitado, el cobro de marketplace_fee en moneda local del seller queda como saldo en la moneda del seller dentro de MP | ABIERTA |
| 17 | **NUEVA:** ¿NV tiene bases de datos inscriptas ante la AAIP (Agencia de Acceso a la Información Pública) según Ley 25.326? | Obligación legal si se tratan datos personales de terceros (compradores de las tiendas) | ABIERTA |
| 18 | **NUEVA:** ¿NV cuenta con proceso de "notice and takedown" para contenido ilícito en tiendas hosted? | Riesgo legal de responsabilidad por contenido si NV toma conocimiento y no actúa (jurisprudencia digital AR) | ABIERTA |
| 19 | **NUEVA:** ¿NV emitirá Factura E en USD o en ARS? | El plan recomienda **USD** (ver Sección 10.3) para evitar descalce documental. Si se elige ARS, hay conversión manual obligatoria con TC BNA vendedor divisa | ABIERTA — ver recomendación en §10.3 |
| 20 | **NUEVA:** ¿Cuál es la política de retención de datos de evidencia de ubicación (IP, timestamp de signup)? | Dato personal sensible (Ley 25.326 / AAIP). Minimizar retención vs. necesidad de prueba ante disputas fiscales o contractuales | ABIERTA |
| 21 | **NUEVA:** ¿NV tiene definido un umbral para activar revisión fiscal si aparecen sellers B2C? | El plan sugiere >5% del revenue o >10 sellers B2C como trigger para revisar la estrategia "sin registro" (Sección 2, Carril B2C) | ABIERTA |
| 22 | **NUEVA:** ¿Los límites de plan (quotas/cuotas) se definen globalmente o por país del tenant? Un Starter en Chile podría tener costo diferente que en Argentina (fees MP, egress) | Define si `plans.max_orders_month` es universal o necesita variante por country. Impacta cost-to-serve y pricing por país (Q2) | ABIERTA — ver [PLANS_LIMITS_ECONOMICS.md §13.1 D1-D7](PLANS_LIMITS_ECONOMICS.md) |
| 23 | **NUEVA:** ¿El tier Trial (gratuito) estará disponible para sellers no-AR? Si sí, ¿requiere verificación B2B en el signup? | Interacción entre Trial y la policy B2B-only de §2. Sin verificación, podría haber abuse con trials desde países sin enforcement fiscal | ABIERTA — ver [PLANS_LIMITS_ECONOMICS.md §3.2](PLANS_LIMITS_ECONOMICS.md) |

---

## Supuestos Explícitos (ASSUMPTION)

| # | Supuesto | Riesgo si es incorrecto | Origen |
|---|----------|------------------------|--------|
| A1 | El `site_id` se puede obtener de `GET /users/me` con el access_token del seller | Si no viene, habría que pedir al seller que seleccione país manualmente | Auditoría técnica |
| A2 | Un client_id de MP Argentina (MLA) puede aceptar sellers de otros países vía OAuth | Si MP bloquea cross-country OAuth, solo se necesita validar y messaging | Auditoría técnica |
| A3 | `marketplace_fee` en preferencias de MP funciona cross-country (seller de CL con marketplace de AR) | Si no funciona, NV cobra por facturación directa sin retención automática | Auditoría técnica |
| A4 | CLP y COP no usan decimales en MP (montos enteros) | Si MP acepta decimales para estas monedas, ajustar rounding | Auditoría técnica |
| A5 | Los crons de NV (managed-domain, metrics) son operaciones de plataforma y mantienen timezone de AR | Si sellers necesitan crons en su tz, requiere cambio | Auditoría técnica |
| A6 | Las comisiones de MP no varían significativamente entre sellers del mismo país | Si hay tarifas negociadas por seller, el modelo de fees por país no alcanza | Auditoría técnica |
| A7 | Ecuador usa USD como moneda (no tiene moneda propia) | Confirmado por la API de ML | Auditoría técnica |
| A8 | NV opera bajo Modelo A (seller como MoR). NV NO es merchant-of-record ante el comprador final | Si NV fuera MoR (Modelo B), necesita registrarse para IVA digital en 5+ países — inviable a corto plazo | Análisis legal/fiscal |
| A9 | La operación de NV hacia sellers extranjeros encuadra como "exportación de servicios utilizados/explotados en el exterior" | Si ARCA determina que el servicio se "usa en Argentina" (ej: porque la infra está en AR), pierde exención IVA. Riesgo madre fiscal | Análisis legal/fiscal |
| A10 | NV puede emitir Factura E (requisitos: punto de venta habilitado, CUIT del país destino según tablas ARCA) | Si NV no tiene habilitación → no puede facturar exportación → no puede cobrar formalmente a sellers extranjeros | Análisis legal/fiscal |
| A11 | Los cobros de NV por marketplace_fee liquidados por MP en ARS no generan obligación BCRA de ingreso de divisas (porque ya se liquidaron en ARS localmente) | Si BCRA considera que el "cobro de exportación" debió hacerse en divisas y luego liquidarse, hay riesgo cambiario | Análisis legal/fiscal |
| A12 | Las retenciones nacionales sobre cobros electrónicos (IVA/Ganancias) siguen derogadas (RG 5554/2024) al momento de implementar | Si se restituyen, afecta el neto que NV recibe. Las retenciones provinciales (IIBB/SIRCUPA) sí pueden aplicar | Análisis legal/fiscal |
| A13 | Los derechos de exportación de servicios son 0% al momento de implementar (post-2022) | Verificar antes de go-live: si se reactiva el 5-12%, impacta directamente en el pricing de la comisión | Análisis legal/fiscal |
| A14 | **NUEVO:** `marketplace_fee` de MP se expresa en moneda local del flujo que se está cobrando (documentado por MP), NO en USD | Si MP permitiera expresarlo en otra moneda, la arquitectura de fees cambia. Pero la documentación confirma moneda local | Documentación MP |
| A15 | **NUEVO:** MP Cross Border NO está automáticamente habilitado en cuentas estándar; requiere habilitación comercial | Si se asume que "siempre aplica" y no está habilitado, el modelo financiero falla | Documentación MP |
| A16 | **NUEVO:** Las Facturas que MP emite a NV por sus servicios son tipo "B" | Relevante para la conciliación fiscal: vincular Factura B (MP→NV) + Factura E (NV→Seller) + liquidación | Documentación MP |
| A17 | **NUEVO:** NV usa o planea usar un TC oficial (BNA vendedor divisa) para la conversión en Factura E, NO un TC de mercado paralelo | Si se usa TC no oficial → descalce documental entre lo cobrado, lo facturado y lo registrado. ARCA podría objetar | Análisis legal/fiscal |
| A18 | **NUEVO:** NV no tendrá sellers B2C (personas humanas no-profesionales) fuera de Argentina en fase 1 | Si aparecen, los regímenes de IVA/IGV digital podrían obligar a NV a registrarse (Chile/SII, México/SAT, Perú/SUNAT) | 3er análisis legal/fiscal |
| A19 | **NUEVO:** La Factura E se emitirá en USD cuando el contrato SaaS esté en USD | Enfoque robusto recomendado: elimina conversión manual, TC oficial opera automáticamente para valuación fiscal | 3er análisis legal/fiscal |
| A20 | **NUEVO:** El cobro de la comisión NV vía `marketplace_fee` (Patrón 3: retención automática por MP en cada venta del seller) es técnicamente factible sin estructura local por país | Hipótesis operativa a validar con pruebas reales por país. Si MP no lo permite cross-country, se requiere facturación directa (Patrón 1) | 3er análisis legal/fiscal |

---

## 10. Marco Legal/Fiscal y Facturación

> **Fuente:** Análisis legal/fiscal sobre facturación desde Argentina hacia LATAM cobrando con MP (febrero 2026). Este análisis es informativo/técnico y NO reemplaza asesoramiento legal profesional.

### 10.1 Encuadre: NV como exportador de servicios desde Argentina

**Premisa fundamental:** NovaVision presta un servicio de plataforma/SaaS a sellers de otros países. El servicio se desarrolla en Argentina pero se utiliza/explota efectivamente en el exterior (la tienda del seller opera para compradores en CL/MX/CO/etc.).

| Concepto | Tratamiento |
|----------|------------|
| **IVA Argentina** | Exportación de servicios → exenta / tasa 0%. Si NV es Responsable Inscripto, puede computar créditos fiscales vinculados. Si es Monotributo, no hay crédito fiscal pero la exención aplica igualmente |
| **Ganancias** | NV tributa por resultado global (residente AR). Doble imposición se resuelve por CDI (CL, MX) o crédito unilateral. Si NV es Monotributo, Ganancias no aplica (reemplazado por cuota fija) |
| **Derechos de exportación** | VERIFICAR: históricamente 5-12% (D. 1201/2018), reducido a 0% post-2022. **Confirmar estado actual antes de implementar** |
| **Factura** | Factura E (exportación). Puede emitirse en ARS o moneda extranjera. ARCA lo habilita explícitamente para monotributo (guía de exportación de servicios) |
| **Tipo de cambio** | TC BNA **vendedor divisa** del día hábil anterior a la emisión. ARCA publica reglas operativas: cuando se cancela en la misma moneda, se usa TC vendedor divisa BNA del día hábil anterior, y el sistema puede consignarlo automáticamente |

#### Implicaciones según régimen tributario de NV

| Aspecto | Monotributo | Responsable Inscripto |
|---------|-------------|---------------------|
| Factura E | ✅ Habilitada (ARCA lo confirma expresamente) | ✅ Habilitada |
| IVA exportación | Exenta (no genera crédito fiscal) | Exenta/0% (puede computar crédito fiscal de insumos) |
| Ganancias | No aplica (cuota fija monotributo) | Tributa por resultado global |
| Límite de facturación | ⚠️ Topes de categoría monotributo — verificar si la facturación internacional entra en los límites | Sin límite (solo lo que el negocio genere) |
| Crédito fiscal IVA | ❌ No puede computar | ✅ Puede computar (ej: IVA de la comisión de MP) |
| Complejidad contable | BAJA | MEDIA-ALTA |

> **RIESGO: Topes de monotributo.** Si NV escala la operación internacional significativamente, los ingresos de exportación podrían superar el tope de la categoría de monotributo, obligando a pasar a Responsable Inscripto. Planificar el umbral.

### 10.2 IVA/IGV digital por país destino

**Solo aplica si NV fuera MoR ante el consumidor final (Modelo B). Con Modelo A (seller MoR), esto es responsabilidad del seller.**

| País | IVA | Régimen servicios digitales B2C no-residente | CDI con AR | Riesgo NV (Modelo A) | Mitigación fase 1 |
|------|-----|----------------------------------------------|----------|---------------------------|-----|
| Chile | 19% | SII: IVA a servicios remotos remunerados por no residentes (Ley 21.210) | ✅ CDI integral | 🟢 BAJO — seller factura localmente | B2B-only verificable (RUT) o postergar |
| México | 16% | SAT: IVA 16% + reportes trimestrales de operaciones con receptores en territorio nacional | ✅ CDI integral | 🟢 BAJO — seller factura localmente | Si no quiere registro, evitar B2C; vender a empresas con RFC |
| Colombia | 19% | DIAN: inscripción RUT + firma electrónica + declaración IVA periódica | ⚠️ Solo notas reversales | 🟢 BAJO — seller factura localmente | B2B estricto (NIT) + evaluar retenciones en fuente |
| Perú | 18% | SUNAT: declarar/pagar IGV; si no cumple, "facilitadores del pago" retienen/perciben (Ley 31736) | ⚠️ Solo notas reversales | 🟢 BAJO — seller factura localmente | B2B-only + evaluar si canal de cobro queda bajo facilitadores |
| Uruguay | 22% | DGI: régimen en evolución; consultas tributarias activas sobre IVA y plataformas | ⚠️ Acuerdo parcial 2013 | 🟢 BAJO — seller factura localmente | Tratar como "país a validar" con asesor local al tener ventas relevantes |
| Ecuador | 12% | Régimen en evolución | ❌ Sin CDI | 🟢 BAJO — seller factura localmente | Monitorear regulación |
| Brasil | ~17-25% (ICMS/ISS) | Complejo, varía por estado | ❌ Sin CDI | 🟢 BAJO — seller factura localmente | Riesgo alto de doble tributación si BR retiene — postergar si no hay demanda |

**Conclusión Modelo A:** NV NO necesita registrarse para IVA digital en ningún país destino **mientras opere B2B-only**. Si se activa B2C fuera de AR en >1-2 países, la estrategia "sin registro" se vuelve insostenible. La fase más defendible es: **B2B-only internacional + Factura E**, y habilitar B2C país por país con asesoría local.

### 10.3 Factura E — Requisitos operativos

#### Datos mínimos de una Factura E

```
┌─────────────────────────────────────────────────────────────────┐
│ FACTURA E (Exportación de Servicios)                           │
├─────────────────────────────────────────────────────────────────┤
│ Emisor: NovaVision [CUIT NV] - Razón social - Domicilio fiscal│
│ Punto de venta: XXXX  |  Factura Nro: YYYYYYYY                │
│ Fecha emisión: YYYY-MM-DD                                      │
│ CAE: [código]  |  Vto CAE: YYYY-MM-DD                         │
├─────────────────────────────────────────────────────────────────┤
│ Receptor: [Nombre seller]                                      │
│ País: Chile  |  CUIT país: 55000002206 (tabla ARCA)           │
│ ID fiscal seller: RUT 12.345.678-9 (informativo)              │
├─────────────────────────────────────────────────────────────────┤
│ Concepto: Servicio de plataforma e-commerce - Plan [X]         │
│           Período: YYYY-MM                                      │
│ Moneda: ARS (o USD)                                            │
│ TC aplicado: $1.234,56 (BNA vendedor divisa día hábil anterior)  │
│ Fecha TC: YYYY-MM-DD                                           │
│ Importe: $XXX (IVA: $0 — exportación exenta)                  │
│ Referencia MP: marketplace_fee orders [ids]                    │
├─────────────────────────────────────────────────────────────────┤
│ Generado automáticamente — vinculado a nv_invoices.id          │
└─────────────────────────────────────────────────────────────────┘
```

#### Frecuencia de emisión

> **Recomendación: Factura E en USD.** ARCA permite emitir la Factura E en moneda extranjera (USD) o en ARS. El enfoque más robusto es facturar en USD cuando el contrato es en USD, porque:
> - Elimina la conversión manual a ARS por parte de NV.
> - El TC oficial (BNA vendedor divisa) se aplica automáticamente para la valuación fiscal.
> - Reduce riesgo de descalce entre precio contractual y monto facturado.
> - Si el contrato dijera "USD 20/mes" y la Factura E dice "USD 20", no hay inconsistencia.
> - La conversión ARS la hace ARCA/contabilidad según sus propias reglas publicadas.
>
> **Alternativa (Factura E en ARS):** Válida, pero requiere que NV convierta explícitamente usando TC BNA vendedor divisa del día hábil anterior y lo documente en cada factura.

| Modelo | Frecuencia | Detalle |
|--------|-----------|---------|
| Factura E por comisión mensual (plan del seller) | Mensual | 1 factura por seller activo por mes |
| Factura E por marketplace_fee acumulado | Mensual (o por período) | Suma de marketplace_fee del período, con detalle de órdenes |
| NC E (nota de crédito exportación) | Según necesidad | Devoluciones, ajustes |

### 10.4 BCRA — Ingreso y liquidación de cobros de exportación

| Concepto | Regla |
|----------|-------|
| **Obligación general** | Cobros de exportación de servicios deben ingresarse y liquidarse en MULC en 20 días hábiles |
| **Excepción (Com. "A" 8330)** | Personas humanas sin límite de monto (eliminó tope USD 36K/año). Personas jurídicas: verificar condiciones |
| **Impacto para NV** | Si NV es persona jurídica (SAS/SRL), confirmar si aplica excepción o debe liquidar divisas |
| **Escenario MP** | Si MP liquida en ARS directamente (porque el pago se procesó localmente), el flujo de fondos "nunca fue divisa" — pero el encuadre BCRA depende de la operación y no solo del medio |

> **ASSUMPTION A11:** Si MP acredita en ARS en la CVU/CBU de NV, se asume que no hay obligación BCRA de ingresar divisas porque no hubo movimiento en moneda extranjera. VERIFICAR con asesor.

### 10.5 Retenciones y percepciones vigentes en Argentina

| Tipo | Estado (feb 2026) | Impacto en NV |
|------|-------------------|---------------|
| **IVA sobre cobros electrónicos** | DEROGADO (RG 5554/2024, desde 1/9/2024) | ✅ No hay retención de IVA sobre acreditaciones MP |
| **Ganancias sobre cobros electrónicos** | DEROGADO (RG 5554/2024) | ✅ No hay retención |
| **IIBB provincial (PBA — SIRCUPA)** | VIGENTE desde 2025 | ⚠️ ARBA puede retener sobre acreditaciones en CVU según padrón y actividad |
| **IIBB CABA (AGIP)** | Puede aplicar | ⚠️ Según domicilio fiscal de NV |

> **Impacto en el modelo de fees:** Las retenciones provinciales reducen el neto que NV recibe, pero NO cambian el `marketplace_fee` ni el neto del seller. Son costos de NV.

### 10.6 Doble imposición — Matriz por país

| País seller | CDI con AR | Tipo instrumento | Implicancia práctica |
|-------------|-----------|-------------------|---------------------|
| Chile | ✅ | CDI integral | Si el seller retiene impuesto chileno a NV, NV puede computar crédito en AR |
| México | ✅ | CDI integral | Idem Chile |
| Colombia | ⚠️ | Notas reversales (limitado) | No es CDI estándar — riesgo de doble tributación si CO retiene |
| Uruguay | ⚠️ | Acuerdo intercambio info (2013) | No es CDI integral — riesgo similar a CO |
| Perú | ⚠️ | Notas reversales (parcial) | Cobertura limitada — verificar caso por caso |
| Brasil | ❌ | Sin CDI | Riesgo alto de doble tributación si BR retiene ISS/IR |
| Ecuador | ❌ | Sin CDI | Idem Brasil |

### 10.7 Checklist legal-operativo para go-live multi-país

| # | Área | Verificación | Estado |
|---|------|-------------|--------|
| 1 | Encuadre fiscal | Documentar que el servicio NV se utiliza/explota en el exterior (evidencia: sellers operan tiendas para público local de su país) | ❌ PENDIENTE |
| 2 | Factura E habilitada | NV tiene punto de venta para Factura E. Preferiblemente integrado con Web Services ARCA para CAE automático | ❌ PENDIENTE |
| 3 | CUIT por país | Cargar tabla ARCA de CUITs genéricos por país en `country_configs.arca_cuit_pais` | ✅ En seed |
| 4 | Tipo de cambio | Implementar servicio que consulte TC BNA **vendedor divisa** diario y lo persista | ❌ PENDIENTE |
| 5 | Contratos/TyC | Actualizar TyC con cláusulas detalladas (ver Sección 2: Política B2B-only) | ❌ PENDIENTE |
| 6 | BCRA | Confirmar encuadre: ¿persona jurídica con excepción? ¿o debe liquidar divisas? | ❌ PENDIENTE |
| 7 | IIBB/SIRCUPA | Verificar si NV está en padrón de retenciones, impacto en neto | ❌ PENDIENTE |
| 8 | Derechos exportación | Confirmar alícuota vigente (expectativa: 0%) | ❌ PENDIENTE |
| 9 | Audit trail | Cada factura vinculada a: CAE, payment_ids MP, TC aplicado, PDFs/XMLs almacenados | En diseño (tabla `nv_invoices`) |
| 10 | Seller fiscal data | Recopilar datos fiscales del seller (RUT/RFC/NIT, razón social, domicilio) para Factura E | En diseño (columnas `nv_accounts`) |
| 11 | **NUEVO:** Datos personales | Inventario de datos tratados (compradores), base legal, medidas seguridad, inscripción AAIP si corresponde | ❌ PENDIENTE |
| 12 | **NUEVO:** Defensa del consumidor | Evaluar si sellers califican como "consumidores" (Ley 24.240): botón arrepentimiento, libro quejas digital | ❌ PENDIENTE |
| 13 | **NUEVO:** B2B-only verificable | Proceso de verificación de tax ID del seller implementado en onboarding | ❌ PENDIENTE |
| 14 | **NUEVO:** Pricing vs facturación | Confirmar que el precio cobrado al seller NO usa TC no oficial (ej: "blue"). ARCA exige TC BNA vendedor divisa | ❌ PENDIENTE — **RIESGO ALTO de descalce documental** |
| 15 | **NUEVO:** MP Cross Border | Evaluar si la cuenta MP de NV tiene habilitado Cross Border para retiro en otra cuenta/país | ❌ PENDIENTE — no asumir disponibilidad |

### 10.8 MP Cross Border — Cobro local con retiro en otro país

MP documenta una solución "Cross Border" que permite cobrar de manera local peroen retirar fondos en una cuenta bancaria en un país diferente al del cobro.

| Aspecto | Detalle |
|---------|---------|
| **Qué resuelve** | NV podría cobrar comisiones en moneda local del seller y retirar a cuenta AR (o viceversa), sin abrir estructura operativa por país |
| **Qué NO resuelve** | (i) TC de conversión (lo fija MP), (ii) costos/comisiones de retiro, (iii) descalce entre precio, factura y registro contable, (iv) impuestos en destino |
| **Disponibilidad** | NO es automático — requiere habilitación comercial en la cuenta MP. No asumir que cualquier cuenta estándar lo tiene |
| **Impacto en el plan** | Si está disponible, simplifica el flujo de fondos pero NO elimina la necesidad de Factura E, conciliación, ni TC oficial |
| **Riesgo** | Diseñar "USD neto constante" vía Cross Border sin capa de FX/fees genera descalce entre: (i) precio mostrado/cobrado, (ii) Factura E emitida, (iii) registro contable |

**Recomendación:** Investigar disponibilidad de Cross Border para la cuenta de NV como mecanismo complementario, pero NO diseñar la arquitectura financiera asumiendo que "siempre aplica".

### 10.9 Factura B de MP y conciliación

MP emite **Factura tipo "B"** a NV por el servicio de procesamiento de pagos (comisión MP). Este comprobante:

- Documenta la comisión que MP cobra a NV (no al seller).
- Es separado de la Factura E que NV emite al seller.
- Debe vincularse en la conciliación: **Factura B (MP→NV)** + **Factura E (NV→Seller)** + **Liquidación MP** + **Banco**.

```
Conciliación completa por operación:
Factura B (MP → NV)     ← comisión MP por procesamiento
Factura E (NV → Seller) ← comisión NV por plataforma (marketplace_fee)
Liquidación MP           ← detalle de fondos acreditados/retenidos
Extracto bancario        ← fondos efectivamente recibidos
```

### 10.10 Datos personales y obligaciones AAIP

NV trata datos de compradores de las tiendas (nombre, email, dirección si hay envío, datos de pago parciales). Aunque el seller es quien tiene la relación directa con el comprador, NV como plataforma tiene acceso a esos datos.

| Obligación | Detalle | Aplica a NV |
|-----------|---------|-------------|
| **Base legal de tratamiento** | Consentimiento o interés legítimo para procesar datos en nombre del seller | ✅ — definir en TyC y política de privacidad |
| **Medidas de seguridad** | Técnicas y organizativas (cifrado, acceso mínimo, backups) | ✅ — ya implementadas en mayor parte (Supabase RLS + service_role) |
| **Inscripción de bases AAIP** | Si corresponde según el volumen y tipo de datos | ⚠️ Evaluar con asesor |
| **Transferencia internacional** | Si datos de compradores de CL/MX/CO se almacenan en servidores (Supabase en US), evaluar si hay restricciones | ⚠️ Evaluar — Supabase está en US |
| **Derecho de acceso/supresión** | Compradores podrían solicitar acceso/eliminación de sus datos | ✅ — contemplar endpoint o proceso manual |
| **Notice and takedown** | Deber de diligencia ante contenido manifiestamente ilícito en tiendas hosted | ⚠️ Implementar proceso de denuncia + suspensión |

---

## Documentos relacionados

| Documento | Relación |
|-----------|----------|
| [PLANS_LIMITS_ECONOMICS.md](PLANS_LIMITS_ECONOMICS.md) | Planes, quotas, enforcement, cost-to-serve. Define FX_ref, rate limits per-tenant, overages. Las secciones §3.3 (FX_ref), §4 (fees), §7 (enforcement) tienen dependencias directas con este plan |
| [subscription-guardrails.md](subscription-guardrails.md) | Guardrails del sistema de suscripciones actual (SoT, webhooks, upgrade flow). **Nota:** el upgrade flow usa `blueDollarRate` que debe migrar a FX_ref oficial |
| [subscription-hardening-plan.md](subscription-hardening-plan.md) | Historial de hardening F0-F6 (completado). Base estable sobre la que se construye el plan de quotas |

---

*Este documento es un plan. No se ejecutan cambios sin aprobación explícita del TL.*

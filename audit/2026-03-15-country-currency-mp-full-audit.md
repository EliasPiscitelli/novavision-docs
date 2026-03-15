# Auditoría País/Moneda/MercadoPago — Onboarding a Tienda Publicada

**Fecha**: 2026-03-15
**Auditor**: Claude Opus 4.6 — investigación de codigo real sobre 3 repos + documentación oficial MP
**Repos auditados**: API (`apps/api`), Admin (`apps/admin`), Web (`apps/web`), Migraciones SQL
**Método**: 4 agentes paralelos + investigación MP API docs
**Estado**: COMPLETA

---

## 1. Resumen Ejecutivo

### Veredicto: El sistema tiene infraestructura multi-país pero opera como Argentina-only

NovaVision tiene un **diseño dual**: existe un `CountryContextService` con tabla `country_configs` que modela 7 países LATAM correctamente, pero la **implementación real** está plagada de hardcodes a Argentina (AR/ARS/MLA) en ~160+ lugares del código. El flujo OAuth de MercadoPago **no captura el `site_id` del seller**, lo cual es el gap más crítico: no hay forma de validar que la cuenta MP conectada pertenece al país seleccionado.

**Estado por área:**

| Área | Estado | Confianza | Riesgo |
|------|--------|-----------|--------|
| Modelo de datos (country_configs) | SANO — bien diseñado | Alta | Bajo |
| Onboarding — selección de país | PARCIAL — API soporta, Admin no lo expone | Media | Alto |
| Onboarding — datos fiscales por país | FUNCIONAL — validación dinámica | Alta | Bajo |
| Provisioning — propagación country | INCOMPLETO — countryLocaleMap solo 4 de 7 países | Media | Medio |
| OAuth MP — captura site_id seller | NO IMPLEMENTADO | N/A | **P0 CRÍTICO** |
| Validación cuenta MP vs país tienda | NO EXISTE | N/A | **P0 CRÍTICO** |
| Checkout — currency en preferences | DINÁMICO pero con fallback ARS | Media | Alto |
| Storefront — display currency | DINÁMICO via country_context | Alta | Bajo |
| Admin UI — labels currency | HARDCODED a ARS | Baja | Medio |
| Shipping — currency | HARDCODED a ARS (~15 lugares) | Baja | Alto |
| Addons — checkout currency | HARDCODED a ARS (~10 lugares) | Baja | Alto |
| Fee table — MP rates por país | SOLO SEED ARGENTINA | Baja | Alto |

### Respuestas a las 10 preguntas críticas

1. **Source of truth del país**: `nv_accounts.country` (Admin DB) → se propaga a `clients.country` (Backend DB). Default: `'AR'`.
2. **Source of truth de la moneda**: `country_configs.currency_id` (Admin DB), resuelto vía `CountryContextService` usando `country_id` o `site_id`. No hay columna `currency` en `clients` como source of truth directa — se deriva del país.
3. **Se permite cambiar país post-alta**: No hay restricción técnica, pero tampoco hay UI. Un cambio de country en `nv_accounts` no se propaga automáticamente al tenant.
4. **País y moneda desacoplados**: Sí, peligrosamente. `clients.country` puede decir 'AR' pero no hay `currency` persistida en clients — se resuelve dinámicamente. Si `country_configs` no tiene el país, fallback a ARS.
5. **Onboarding adapta campos por país**: La API sí (endpoints `/onboarding/country-config/:countryId`). El Admin app (wizard) NO — hardcodea DNI, CUIT, y texto AFIP/Argentina.
6. **Config MP toma país correcto**: Parcialmente. `resolveTenantCurrency()` lee `clients.country` → `country_configs.currency_id`. Pero hay ~160 fallbacks a ARS.
7. **Preference alineada con currency**: Sí si `country_configs` tiene el país. No si falla la resolución (cae a ARS).
8. **Se detecta cuenta MP de otro país**: **NO**. El OAuth callback no captura `site_id` del seller. No se llama `/users/me` con el access_token.
9. **Writes/reads inconsistentes**: Sí. `clients.country` puede ser 'CL' pero `mp_fee_table` solo tiene rates de AR. `addons.service.ts` hardcodea ARS.
10. **Qué se rompe con mismatch**: Si tienda es CL y cuenta MP es AR → preference con CLP falla en MP. Si tienda es AR y se cambia a CL → no se re-provisiona currency.

---

## 2. Mapa de Flujo End-to-End

```
┌─────────────────────────────────────────────────────────────────┐
│                        ONBOARDING                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Step 1: Email + Slug                                            │
│    └─ NO se pide país en Admin wizard (API lo soporta)          │
│                                                                  │
│  Step 8: Business Info                                           │
│    └─ Admin wizard: CUIT/CUIL hardcoded (11 dígitos)            │
│    └─ API: POST /onboarding/business-info                        │
│       └─ Lee country del account                                 │
│       └─ Valida fiscal_id con FiscalIdValidatorService           │
│       └─ Guarda en nv_accounts: fiscal_id, fiscal_id_type,      │
│          persona_type, fiscal_category, subdivision_code         │
│                                                                  │
│  Step 7/9: MP OAuth                                              │
│    └─ Admin: Redirige a mercadopago.com.ar (HARDCODED)          │
│    └─ API: GET /mp/oauth/start → redirect a MP                  │
│    └─ Callback: extrae access_token, refresh_token, user_id,    │
│       public_key, live_mode                                      │
│    └─ ⚠ NO captura site_id ni country_id del seller             │
│    └─ Guarda en nv_accounts: mp_access_token_encrypted,         │
│       mp_user_id, mp_connected=true                              │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                      PROVISIONING                                │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  provisioning-worker.service.ts:                                 │
│    1. Lee nv_accounts.country (default: 'AR')                   │
│    2. Resuelve locale/timezone con countryLocaleMap:             │
│       AR → es-AR / Buenos_Aires                                  │
│       MX → es-MX / Mexico_City                                  │
│       CL → es-CL / Santiago                                     │
│       CO → es-CO / Bogota                                       │
│       ⚠ UY, PE, BR NO ESTÁN EN EL MAP                          │
│    3. Crea client en Backend DB con:                             │
│       country, locale, timezone, persona_type, fiscal_id, etc.  │
│    4. Sync MP credentials a Backend DB                           │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                    TENANT BOOTSTRAP                              │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  GET /tenant/bootstrap:                                          │
│    1. TenantService resuelve slug → client                      │
│    2. Lee nv_accounts.mp_site_id (probablemente NULL)           │
│    3. Si mp_site_id: CountryContextService.getConfigBySiteId()  │
│    4. Si no: CountryContextService.getConfigByCountry(country)  │
│    5. Retorna country_context:                                   │
│       { locale, currency_id, country_id, decimals, timezone }   │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                    STOREFRONT                                    │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  TenantProvider.jsx:                                             │
│    1. Recibe country_context del bootstrap                       │
│    2. setCurrencyConfig({ locale, currency, decimals })          │
│    3. formatCurrency() usa config global                         │
│    4. useCurrency() hook para componentes                        │
│    ✅ DINÁMICO — muestra moneda correcta del tenant             │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│                    CHECKOUT                                      │
├─────────────────────────────────────────────────────────────────┤
│                                                                  │
│  Frontend: POST /mercadopago/create-preference-for-plan          │
│    └─ Envía: baseAmount, selection, cartItems                   │
│    └─ ⚠ NO envía currency_id (backend debe inferir)            │
│                                                                  │
│  Backend: MercadoPagoService.createPreferenceWithParams()        │
│    1. currency = totals?.currency || resolveTenantCurrency()    │
│    2. resolveTenantCurrency():                                   │
│       └─ Lee clients.country                                    │
│       └─ CountryContextService.getConfigByCountry(country)      │
│       └─ Retorna currency_id                                    │
│       └─ Fallback: 'ARS'                                        │
│    3. Crea preference en MP con currency + access_token seller  │
│    4. Si currency ≠ país real del token → MP RECHAZA            │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## 3. Matriz Maestra de País/Moneda

| Concepto | Source of Truth | Tabla.Columna | Base | Default | Quién escribe | Quién consume | Obligatorio | Validación | Estado |
|----------|----------------|---------------|------|---------|---------------|---------------|-------------|------------|--------|
| store_country | `nv_accounts.country` | nv_accounts.country | Admin | `'AR'` | Onboarding business-info | Provisioning worker, TenantService | No (nullable) | Ninguna (text libre) | VERIFICADO |
| store_country (replica) | `clients.country` | clients.country | Backend | `account.country \|\| 'AR'` | Provisioning worker | MercadoPagoService, TenantService | Sí (con default) | Ninguna | VERIFICADO |
| currency_id | `country_configs.currency_id` | country_configs.currency_id | Admin | N/A (lookup) | Seed/admin manual | CountryContextService → todos | Sí | country_id FK | VERIFICADO |
| locale | `country_configs.locale` | country_configs.locale | Admin | N/A | Seed | TenantProvider, SEOHead | Sí | Ninguna | VERIFICADO |
| locale (replica) | `clients.locale` | clients.locale | Backend | `countryLocaleMap[country]` | Provisioning worker | Frontend, emails | Sí | Ninguna | VERIFICADO — incompleto (4/7 países) |
| timezone | `country_configs.timezone` | country_configs.timezone | Admin | N/A | Seed | TenantProvider | Sí | Ninguna | VERIFICADO |
| timezone (replica) | `clients.timezone` | clients.timezone | Backend | `countryLocaleMap[country]` | Provisioning worker | Frontend | Sí | Ninguna | VERIFICADO — incompleto |
| site_id | `country_configs.site_id` | country_configs.site_id | Admin | N/A | Seed | CountryContextService | Sí | PK | VERIFICADO |
| mp_site_id (seller) | `nv_accounts.mp_site_id` | nv_accounts.mp_site_id | Admin | NULL | **NADIE — no capturado** | TenantService (con fallback) | No | Ninguna | **NO IMPLEMENTADO** |
| mp_user_id | `nv_accounts.mp_user_id` | nv_accounts.mp_user_id | Admin | NULL | OAuth callback | Provisioning, validación | No | Ninguna | VERIFICADO |
| mp_access_token | `nv_accounts.mp_access_token_encrypted` | nv_accounts.mp_access_token_encrypted | Admin | NULL | OAuth callback (encriptado) | MpOauthService.syncToBackend | No | Ninguna | VERIFICADO |
| mp_public_key | OAuth response | Transitorio | - | NULL | OAuth callback | Backend para preferences | No | Ninguna | VERIFICADO |
| fiscal_id | `nv_accounts.fiscal_id` | nv_accounts.fiscal_id | Admin | NULL | POST /onboarding/business-info | Provisioning → clients.fiscal_id | No | FiscalIdValidatorService (AR/CL/MX/CO/UY/PE) | VERIFICADO |
| fiscal_id_type | `nv_accounts.fiscal_id_type` | nv_accounts.fiscal_id_type | Admin | NULL | POST /onboarding/business-info | Provisioning → clients.fiscal_id_type | No | country_configs.fiscal_id_label | VERIFICADO |
| persona_type | `nv_accounts.persona_type` | nv_accounts.persona_type | Admin | NULL | POST /onboarding/business-info | Provisioning → clients.persona_type | No | 'natural' \| 'juridica' | VERIFICADO |
| fiscal_category | `nv_accounts.fiscal_category` | nv_accounts.fiscal_category | Admin | NULL | POST /onboarding/business-info | Provisioning → clients.fiscal_category | No | country_fiscal_categories lookup | VERIFICADO |
| subdivision_code | `nv_accounts.subdivision_code` | nv_accounts.subdivision_code | Admin | NULL | POST /onboarding/business-info | Provisioning → clients.subdivision_code | No | country_subdivisions lookup | VERIFICADO |
| payment_currency (default) | `client_payment_settings.currency` | client_payment_settings.currency | Backend | `'ARS'` | Migration default | PaymentsService | Sí | Ninguna | **HARDCODED ARS** |
| order_currency | `order_payment_breakdown.currency` | order_payment_breakdown.currency | Backend | `'ARS'` | Order creation | Reports, admin | Sí | Ninguna | **HARDCODED ARS** |
| coupon_currency | `coupons.currency` | coupons.currency | Admin | `'ARS'` | Admin creation | Checkout validation | No | Ninguna | **HARDCODED ARS** |

---

## 4. Matriz de Onboarding por País

| País | Campos Requeridos Esperados | Campos Realmente Pedidos (Admin Wizard) | Validación FE | Validación BE | Persistencia | Riesgo |
|------|----------------------------|----------------------------------------|---------------|---------------|-------------|--------|
| **AR** | CUIT/CUIL (11 dig), DNI (7-8 dig), Monotributo/RI, Provincia, Dir fiscal | CUIT/CUIL, DNI, Dir fiscal, Teléfono, Email facturación | Regex `^\d{11}$` para CUIT | FiscalIdValidator Mod11 | nv_accounts.fiscal_id, fiscal_id_type, etc. | Bajo — funcional |
| **CL** | RUT (8-9 dig + check K), Región, Giro comercial | **Mismo form que AR (CUIT label)** | **Usa validación AR** | FiscalIdValidator CL Mod11 disponible pero FE no lo llama | Guardaría en mismas columnas | **ALTO — FE no adaptado** |
| **MX** | RFC (12-13 chars alfanum), Estado, Régimen fiscal | **Mismo form que AR** | **Usa validación AR** | FiscalIdValidator MX regex disponible | Guardaría en mismas columnas | **ALTO — FE no adaptado** |
| **CO** | NIT (9-10 dig), Departamento, Tipo contribuyente | **Mismo form que AR** | **Usa validación AR** | FiscalIdValidator CO Mod11 disponible | Guardaría en mismas columnas | **ALTO — FE no adaptado** |
| **UY** | RUT (12 dig), Departamento | **Mismo form que AR** | **Usa validación AR** | FiscalIdValidator UY Mod11 disponible | Guardaría en mismas columnas | **ALTO — FE no adaptado** |
| **PE** | RUC (11 dig), Departamento | **Mismo form que AR** | **Usa validación AR** | FiscalIdValidator PE Mod11 disponible | Guardaría en mismas columnas | **ALTO — FE no adaptado** |
| **BR** | CNPJ (14 dig) / CPF (11 dig) | **Mismo form que AR** | **Usa validación AR** | **Sin validación BR** | Guardaría en mismas columnas | **CRÍTICO — sin validación BE** |

**Hallazgo clave**: La API tiene `FiscalIdValidatorService` funcional para AR/CL/MX/CO/UY/PE (6 países). El Admin wizard ignora esto y muestra siempre campos Argentina con labels hardcodeados ("CUIT/CUIL", "DNI", "AFIP").

---

## 5. Matriz de Mercado Pago por País

| País Onboarding | Currency Tienda | site_id Esperado | site_id Real Seller | Se Valida Mismatch? | Se Bloquea Publish? | Preference Correcta? | Riesgo | Evidencia |
|-----------------|-----------------|------------------|---------------------|---------------------|---------------------|---------------------|--------|-----------|
| AR | ARS | MLA | **DESCONOCIDO** (no capturado) | NO | NO | Sí (si seller es AR) | **P0** si seller no es AR | mp-oauth.service.ts no captura site_id |
| CL | CLP | MLC | **DESCONOCIDO** | NO | NO | Falla si seller es AR (currency mismatch) | **P0** | resolveTenantCurrency cae a ARS si falla lookup |
| MX | MXN | MLM | **DESCONOCIDO** | NO | NO | Falla si seller es AR | **P0** | Mismo problema |
| CO | COP | MCO | **DESCONOCIDO** | NO | NO | Falla si seller es AR | **P0** | Mismo problema |
| UY | UYU | MLU | **DESCONOCIDO** | NO | NO | Falla si seller es AR | **P0** | countryLocaleMap no tiene UY |
| PE | PEN | MPE | **DESCONOCIDO** | NO | NO | Falla si seller es AR | **P0** | countryLocaleMap no tiene PE |
| BR | BRL | MLB | **DESCONOCIDO** | NO | NO | Falla si seller es AR | **P0** | FiscalIdValidator no tiene BR |
| AR | ARS | MLA | Seller es MX (MLM) | NO | NO | **FALLA** — MP rechaza ARS con token MX | **P0** | Sin validación en callback |

### Capacidad real de validación (investigación MP docs)

**OAuth Token Response devuelve:**
- `access_token`, `token_type`, `expires_in`, `scope`, `user_id`, `refresh_token`, `public_key`, `live_mode`
- **NO devuelve `site_id` ni `country_id`**

**GET /users/{user_id} (con access_token del seller) devuelve:**
- `id`, `nickname`, `country_id` (ej: "AR"), `site_id` (ej: "MLA"), `email`, `identification`, `address`
- **ESTA ES LA FORMA de validar el país de la cuenta conectada**

**Estrategia recomendada:**
1. Después del OAuth callback, con el `access_token` del seller, llamar `GET https://api.mercadolibre.com/users/me`
2. Extraer `site_id` y `country_id` de la respuesta
3. Persistir en `nv_accounts.mp_site_id` y `nv_accounts.mp_country_id`
4. Comparar `mp_country_id` vs `nv_accounts.country`
5. Si mismatch → warn o block

---

## 6. Matriz de Migración/Provisioning

| Dato | Dónde Nace | Base Origen | Tabla Origen | Columna Origen | Base Destino | Tabla Destino | Columna Destino | Worker/Servicio | Consumidor Final | Estado |
|------|-----------|-------------|-------------|---------------|-------------|--------------|----------------|----------------|-----------------|--------|
| country | Onboarding business-info | Admin | nv_accounts | country | Backend | clients | country | provisioning-worker | TenantService, MercadoPagoService | VERIFICADO |
| locale | Derivado de country | Admin | country_configs | locale | Backend | clients | locale | provisioning-worker (countryLocaleMap) | Frontend TenantProvider | PARCIAL — solo 4 países en map |
| timezone | Derivado de country | Admin | country_configs | timezone | Backend | clients | timezone | provisioning-worker (countryLocaleMap) | Frontend | PARCIAL — solo 4 países |
| fiscal_id | Onboarding form | Admin | nv_accounts | fiscal_id | Backend | clients | fiscal_id | provisioning-worker | Admin dashboard | VERIFICADO |
| fiscal_id_type | Derivado de country_configs | Admin | nv_accounts | fiscal_id_type | Backend | clients | fiscal_id_type | provisioning-worker | Admin dashboard | VERIFICADO |
| persona_type | Onboarding form | Admin | nv_accounts | persona_type | Backend | clients | persona_type | provisioning-worker | Admin dashboard | VERIFICADO |
| fiscal_category | Onboarding form | Admin | nv_accounts | fiscal_category | Backend | clients | fiscal_category | provisioning-worker | Admin dashboard | VERIFICADO |
| subdivision_code | Onboarding form | Admin | nv_accounts | subdivision_code | Backend | clients | subdivision_code | provisioning-worker | Admin dashboard | VERIFICADO |
| mp_access_token | OAuth callback | Admin | nv_accounts | mp_access_token_encrypted | Backend | clients | mp_access_token | MpOauthService.syncToBackend | MercadoPagoService | VERIFICADO |
| mp_public_key | OAuth callback | Admin | nv_accounts | (transitorio) | Backend | clients | mp_public_key | MpOauthService.syncToBackend | MercadoPagoService | VERIFICADO |
| mp_site_id | **DEBERÍA: OAuth → /users/me** | Admin | nv_accounts | mp_site_id | — | — | — | **NO IMPLEMENTADO** | TenantService (fallback a country) | **NO FUNCIONAL** |
| currency | NO se persiste directamente | — | — | — | — | — | — | — | Resuelto dinámicamente via CountryContextService | VERIFICADO pero frágil |

---

## 7. Lista de Inconsistencias

### P0 — Críticas

| # | Problema | Impacto | Evidencia | Fix |
|---|---------|---------|-----------|-----|
| 1 | **OAuth no captura site_id del seller** | No se puede validar que la cuenta MP pertenece al país de la tienda. Una tienda CL con cuenta MP AR falla en cobro. | `mp-oauth.service.ts` — no llama `/users/me` post-callback | Llamar `/users/me` con access_token, persistir `mp_site_id` |
| 2 | **No existe validación de mismatch país/cuenta MP** | Publish de tienda con cuenta MP de otro país → checkout roto | Ningún guard en publish ni en provisioning | Agregar guard en publish y warning en onboarding |
| 3 | **~160+ hardcodes de ARS** en API | Addons, shipping, payments, import wizard — todos asumen ARS | `addons.service.ts` (~10x), `payments.service.ts` (~5x), shipping providers (~15x) | Reemplazar por `resolveTenantCurrency()` |
| 4 | **mp_fee_table solo tiene seed de Argentina** | Tiendas de otros países no tienen rates → cálculos de comisión incorrectos | `20251003_seed_mp_fee_table.sql` — 10 rows todas AR | Seed rates para CL/MX/CO/UY/PE/BR |
| 5 | **Admin wizard hardcodea Argentina** | Form muestra "CUIT/CUIL", DNI 7-8 dígitos, texto AFIP — no adapta por país | `Step7ClientData.tsx`, `Step8ClientData.tsx`, `Step6bDNI.tsx` | Consumir `/onboarding/country-config/:countryId` y adaptar forms |

### P1 — Importantes

| # | Problema | Impacto | Evidencia |
|---|---------|---------|-----------|
| 6 | **countryLocaleMap incompleto** — solo AR/MX/CL/CO | UY y PE provisionan con locale/timezone de AR (fallback) | `provisioning-worker.service.ts:548-555` |
| 7 | **client_payment_settings.currency DEFAULT 'ARS'** | Nuevos clientes de otros países arrancan con ARS en payment settings | Migration `20251007_add_payment_tables_and_order_cols.sql:22` |
| 8 | **order_payment_breakdown.currency DEFAULT 'ARS'** | Órdenes de tiendas no-AR se registran como ARS si no se override | Migration `20251007:97` |
| 9 | **PaymentsConfig UI carga fees con `getMpFees("AR")`** | Admin de tienda CL ve fees de Argentina | `PaymentsConfig/index.jsx:378` |
| 10 | **Label "(ARS)" hardcoded en service cost** | Admin ve ARS sin importar su país | `PaymentsConfig/index.jsx:792,805` |
| 11 | **Import wizard limita a ARS/USD** | No acepta CLP/MXN/COP etc. en import CSV | `import-wizard.validators.ts:16,290` |

### P2 — Deuda técnica

| # | Problema | Impacto |
|---|---------|---------|
| 12 | Admin wizard redirige a `mercadopago.com.ar` (hardcoded) | Sellers de otros países ven dominio AR |
| 13 | coupons.currency DEFAULT 'ARS' | Cupones de monto fijo asumen ARS |
| 14 | Demo data toda en ARS | No afecta producción |
| 15 | FiscalIdValidator no tiene BR | Brasil no tiene validación de CNPJ/CPF |
| 16 | No hay CHECK constraint en country (text libre) | Podría guardarse "argentina" en vez de "AR" |

---

## 8. Casos de Prueba E2E

### Caso 1: Alta tienda Argentina + ARS + cuenta MP Argentina
- **Precondiciones**: Email nuevo, slug disponible
- **Steps**: Onboarding completo, seleccionar país AR, conectar MP AR
- **Writes**: nv_accounts.country='AR', clients.country='AR', clients.locale='es-AR'
- **Resultado esperado**: Checkout crea preference con currency_id='ARS'
- **Resultado actual**: FUNCIONA (happy path actual)
- **Gap**: Ninguno
- **Prioridad**: N/A (ya funciona)

### Caso 2: Alta tienda Chile + CLP + cuenta MP Chile
- **Precondiciones**: Email nuevo, slug disponible, cuenta MP chilena
- **Steps**: Onboarding, seleccionar país CL, conectar MP CL
- **Writes esperados**: nv_accounts.country='CL', mp_site_id='MLC'
- **Resultado esperado**: Checkout con CLP, fees de CL, fiscal con RUT
- **Resultado actual**: **FALLA** — Admin wizard muestra CUIT en vez de RUT, no captura mp_site_id, provisioning asigna es-CL correctamente (está en map), pero mp_fee_table vacía para CL, PaymentsConfig carga fees AR
- **Gap**: Admin wizard, mp_site_id, fee table seed, PaymentsConfig
- **Prioridad**: P0

### Caso 3: Alta tienda Uruguay + UYU + cuenta MP Uruguay
- **Resultado actual**: **FALLA** — countryLocaleMap no tiene UY, cae a es-AR/Buenos_Aires. Fee table vacía para UY.
- **Gap**: countryLocaleMap, fee table seed
- **Prioridad**: P0

### Caso 4: Alta tienda México + MXN + cuenta MP México
- **Resultado actual**: **PARCIAL** — countryLocaleMap tiene MX, locale/timezone OK. Pero fees vacías, admin wizard muestra CUIT en vez de RFC.
- **Prioridad**: P0

### Caso 5: Alta tienda Colombia + COP + cuenta MP Colombia
- **Resultado actual**: **PARCIAL** — Similar a MX. countryLocaleMap tiene CO, pero fees vacías, admin hardcodea CUIT.
- **Prioridad**: P0

### Caso 6: Alta tienda Perú + PEN + cuenta MP Perú
- **Resultado actual**: **FALLA** — countryLocaleMap no tiene PE (cae a AR). Fee table vacía.
- **Prioridad**: P0

### Caso 7: Alta tienda AR + cuenta MP MX (MISMATCH)
- **Precondiciones**: Tienda registrada como AR, seller conecta cuenta MP mexicana
- **Resultado esperado**: Warning o bloqueo — cuentas de diferente país
- **Resultado actual**: **NO SE DETECTA** — OAuth guarda tokens sin verificar site_id. Preference se crea con ARS pero token es de MX → MP rechaza con error de currency.
- **Gap**: Falta captura y validación de mp_site_id
- **Prioridad**: **P0 CRÍTICO**

### Caso 8: Alta tienda UY + currency ARS (MISMATCH)
- **Resultado esperado**: Sistema debería forzar UYU para tienda UY
- **Resultado actual**: Si country='UY' y country_configs tiene UY con currency_id='UYU', resolveTenantCurrency devuelve UYU. Pero client_payment_settings.currency es ARS por default de la migración.
- **Gap**: Default de migración no respeta país
- **Prioridad**: P1

### Caso 9: Cambio de país después de conectar MP
- **Resultado esperado**: Warning de que tokens MP pueden no ser válidos para nuevo país
- **Resultado actual**: **No hay UI ni API para cambiar país**. Si se cambia manualmente en DB, no se re-valida MP.
- **Prioridad**: P1

### Caso 10: Checkout mostrando una moneda y preference usando otra
- **Precondiciones**: Tienda CL, country_configs tiene CLP, pero addons.service.ts hardcodea ARS
- **Resultado esperado**: Nunca debería pasar
- **Resultado actual**: Storefront muestra CLP (via formatCurrency), pero addon checkout envía ARS → **INCONSISTENCIA VISIBLE AL COMPRADOR**
- **Prioridad**: P0

---

## 9. Reglas Objetivo Recomendadas

1. **País de tienda obligatorio e inmutable post-provisioning** — Una vez provisioned, country no se puede cambiar sin migración explícita.
2. **Currency derivada del país, nunca editable manualmente** — `currency_id = country_configs[country].currency_id`. Eliminar defaults ARS de migraciones.
3. **site_id derivado del país** — `site_id = country_configs[country].site_id`. No editable.
4. **Validación obligatoria de cuenta MP post-OAuth** — Llamar `/users/me`, extraer `site_id`, comparar con tienda. Warning si mismatch, block si difiere.
5. **Bloqueo de publish si mismatch** — Guard: `nv_accounts.country` debe coincidir con `nv_accounts.mp_site_id` → `country_configs.country_id`.
6. **Formularios dinámicos** — Admin wizard debe consumir `/onboarding/country-config/:countryId` para labels, validaciones, masks, y opciones fiscales.
7. **Fee table por país** — Seed obligatorio de `mp_fee_table` para cada país activo en `country_configs`.
8. **Zero hardcodes de currency** — Toda referencia a ARS debe resolverse via `resolveTenantCurrency()` o equivalente.

---

## 10. Plan de Corrección por Fases

### Phase 0 — Riesgos Críticos (inmediato)

| Fix | Archivos | Tablas | Migración SQL | Riesgo Regresión | Prioridad |
|-----|---------|--------|---------------|-----------------|-----------|
| **Capturar mp_site_id en OAuth callback** | `mp-oauth.service.ts` | nv_accounts (ADD mp_site_id, mp_country_id) | ALTER TABLE nv_accounts ADD COLUMN mp_site_id VARCHAR(3), ADD COLUMN mp_country_id VARCHAR(2) | Bajo — additive | P0 |
| **Validar mismatch país/cuenta MP** | `mp-oauth.service.ts`, nuevo guard | nv_accounts | — | Bajo | P0 |
| **Completar countryLocaleMap** | `provisioning-worker.service.ts:548-555` | — | — | Bajo | P0 |
| **Seed mp_fee_table para todos los países** | Nuevo migration SQL | mp_fee_table | INSERT rows CL/MX/CO/UY/PE/BR | Bajo | P0 |

### Phase 1 — Modelo de Datos (1-2 semanas)

| Fix | Archivos | Impacto |
|-----|---------|---------|
| Eliminar DEFAULT 'ARS' de client_payment_settings.currency | Migration SQL | Medio — necesita backfill |
| Eliminar DEFAULT 'ARS' de order_payment_breakdown.currency | Migration SQL | Medio |
| Agregar CHECK constraint a nv_accounts.country | Migration SQL | Bajo |
| Hacer que payment settings hereden currency del tenant | payments.service.ts | Medio |

### Phase 2 — Onboarding Dinámico (2-3 semanas)

| Fix | Archivos | Impacto |
|-----|---------|---------|
| Admin wizard: agregar country picker en Step 1 o Step 8 | Step1Slug.tsx o Step8ClientData.tsx | Alto — cambio de UX |
| Admin wizard: consumir /onboarding/country-config/:countryId | Step7ClientData.tsx, Step8ClientData.tsx | Alto |
| Admin wizard: adaptar labels fiscales por país | Step7ClientData.tsx | Medio |
| Admin wizard: adaptar validación de documento por país | Step6bDNI.tsx | Medio |
| Admin wizard: MP redirect dinámico por país | Step7MercadoPago.tsx | Bajo |
| Agregar FiscalIdValidator para BR (CNPJ/CPF) | fiscal-id-validator.service.ts | Bajo |

### Phase 3 — Currency Hardening (3-4 semanas)

| Fix | Archivos | Impacto |
|-----|---------|---------|
| Reemplazar ~160 hardcodes de ARS por resolveTenantCurrency() | addons.service.ts, payments.service.ts, shipping/*.ts | Alto — muchos archivos |
| PaymentsConfig: getMpFees(tenant.country) | PaymentsConfig/index.jsx | Medio |
| PaymentsConfig: labels dinámicos de currency | PaymentsConfig/index.jsx | Bajo |
| Import wizard: aceptar todas las currencies de country_configs | import-wizard.validators.ts | Medio |

### Phase 4 — QA y Regresión (ongoing)

| Fix | Archivos | Impacto |
|-----|---------|---------|
| E2E test: onboarding CL + checkout CLP | novavision-e2e | Alto |
| E2E test: onboarding MX + checkout MXN | novavision-e2e | Alto |
| E2E test: mismatch país/cuenta MP → warning | novavision-e2e | Alto |
| Seed test accounts MP por país | Tests | Medio |
| Integration test: resolveTenantCurrency para cada país | apps/api tests | Medio |

---

## Fuentes

### Documentación Oficial MercadoPago
- [OAuth Token Creation](https://www.mercadopago.com.ar/developers/en/docs/security/oauth/creation)
- [OAuth Token Reference](https://www.mercadopago.com.ar/developers/en/reference/oauth/_oauth_token/post)
- [Users API - Manage Users](https://developers.mercadolivre.com.br/en_us/services-manage-users)
- [Global Selling - User Management](https://global-selling.mercadolibre.com/devsite/manage-users-global-selling)
- [MercadoPago Countries and Currencies](https://www.zoho.com/checkout/faq/payment-gateways/mercado-countries.html)
- [MercadoPago Gateway Guide - Spreedly](https://docs.spreedly.com/payment-gateways/mercado-pago/)

### Código Fuente Auditado
- `apps/api/src/common/country-context.service.ts` — Hub central de resolución país/moneda
- `apps/api/src/common/fiscal-id-validator.service.ts` — Validación de IDs fiscales por país
- `apps/api/src/mp-oauth/mp-oauth.service.ts` — OAuth flow (falla de captura site_id)
- `apps/api/src/tenant-payments/mercadopago.service.ts` — Resolución de moneda en checkout
- `apps/api/src/worker/provisioning-worker.service.ts` — Propagación country/locale/timezone
- `apps/api/src/onboarding/onboarding.controller.ts` — Endpoints de country-config
- `apps/admin/src/pages/BuilderWizard/` — Wizard de onboarding (hardcoded AR)
- `apps/web/src/utils/formatCurrency.jsx` — Formatting dinámico
- `apps/web/src/context/TenantProvider.jsx` — Bootstrap country_context
- `apps/web/src/components/admin/PaymentsConfig/index.jsx` — Config pagos (hardcoded AR)
- `migrations/20251003_seed_mp_fee_table.sql` — Seed solo Argentina

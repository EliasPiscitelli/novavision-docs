# 2026-03-15 — Country/Currency/MP Hardening (Auditoría Multi-País)

## Resumen
Resolución de los gaps críticos identificados en la auditoría de país/moneda/MercadoPago.

## Phase 0 — Riesgos Críticos

### 1. Captura de mp_site_id en OAuth callback
- **Archivo:** `apps/api/src/mp-oauth/mp-oauth.service.ts`
- **Cambio:** Después del OAuth token exchange, llama `GET /users/{user_id}` con el access_token del seller para obtener `site_id` y `country_id`
- **Persistencia:** Nuevas columnas `mp_site_id`, `mp_country_id`, `mp_country_mismatch` en `nv_accounts`
- **Validación:** Si el país del seller (MP) no coincide con el país de la tienda, se loguea WARNING y se persiste `mp_country_mismatch=true`
- **Migración:** `migrations/admin/20260315_mp_seller_geo_columns.sql`

### 2. CountryLocaleMap completo (7 países)
- **Archivo:** `apps/api/src/worker/provisioning-worker.service.ts`
- **Cambio:** Agregados UY (es-UY, Montevideo), PE (es-PE, Lima), BR (pt-BR, São Paulo)
- **Antes:** Solo AR, MX, CL, CO (4 países). UY/PE/BR caían a fallback AR.

### 3. Fee table seed para LATAM
- **Migración:** `migrations/backend/20260315_seed_mp_fees_latam.sql`
- **Cambio:** 24 filas insertadas (4 por país: CL, MX, CO, UY, PE, BR)
- **Antes:** Solo 10 filas de AR

## Phase 1 — Modelo de Datos

### 4. Eliminar defaults ARS de payment tables
- **Migración:** `migrations/backend/20260315_remove_ars_defaults.sql`
- **Cambio:** `client_payment_settings.currency` y `order_payment_breakdown.currency` ya no tienen DEFAULT 'ARS'
- **Impacto:** Nuevas tiendas deben especificar currency explícitamente (resuelto via API)

## Phase 3 — Currency Hardening

### 5. Addons: checkout_currency dinámico
- **Archivo:** `apps/api/src/addons/addons.service.ts`
- **Cambio:** Type `checkout_currency` cambiado de literal `'ARS'` a `string`. Los 4 puntos de consumo (`persistPurchase`) ahora resuelven currency vía `resolveAccountCurrency(accountId)` usando `CountryContextService`
- **Test:** Mock de `CountryContextService` agregado en `addons.service.spec.ts`

### 6. Import wizard: currencies LATAM
- **Archivo:** `apps/api/src/import-wizard/import-wizard.validators.ts`
- **Cambio:** `VALID_CURRENCIES` expandido de `['ARS', 'USD']` a incluir CLP, MXN, COP, UYU, PEN, BRL

### 7. Products service: currencies LATAM
- **Archivo:** `apps/api/src/products/products.service.ts`
- **Cambio:** `VALID_CURRENCIES` expandido igual que import wizard

### 8. PaymentsConfig UI: fees dinámicos
- **Archivo:** `apps/web/src/components/admin/PaymentsConfig/index.jsx`
- **Cambio:** `getMpFees("AR")` → `getMpFees(tenant?.country_context?.country_id || "AR")`
- **Cambio:** Label `(ARS)` → dinámico desde `tenant.country_context.currency_id`

## Verificación
- API build: OK (0 errores)
- API tests: 89 suites, 781 passed
- Web typecheck: OK
- Farma live: OK (storeName=Farma, 15 productos)
- Fee table: 7 países con rates (AR=10, CL/MX/CO/UY/PE/BR=4 cada uno)

## Pendiente (Phase 2 — Onboarding Dinámico)
- Admin wizard: agregar country picker
- Admin wizard: consumir /onboarding/country-config/:countryId para labels fiscales
- Admin wizard: adaptar validación de documento por país (DNI → RUT/RFC/NIT/etc.)
- Admin wizard: MP redirect dinámico por país (no .com.ar hardcoded)
- FiscalIdValidator para BR (CNPJ/CPF)

## Pendiente (Shipping Providers)
- Los 4 providers (Correo Argentino, OCA, Andreani, Manual) hardcodean 'ARS'
- Son providers Argentina-specific por naturaleza (carriers argentinos)
- Para otros países se necesitarán providers locales

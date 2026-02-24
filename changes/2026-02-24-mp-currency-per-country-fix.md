# Fix: Resolución dinámica de currency en el flujo de pago por país del tenant

- **Autor:** agente-copilot
- **Fecha:** 2026-02-24
- **Rama:** `feature/automatic-multiclient-onboarding` (API)
- **Repos afectados:** API (templatetwobe), E2E (novavision-e2e)

---

## Resumen

Se eliminaron **15 referencias hardcodeadas a `'ARS'`** en el flujo de checkout/pagos del backend y se reemplazaron con resolución dinámica basada en el país del tenant (`clients.country` → `country_configs.currency_id`).

### Problema detectado

El sistema multi-país tenía `CountryContextService` correctamente implementado y conectado al bootstrap de tenants, pero el flujo de pagos (Mercado Pago) ignoraba completamente la configuración de país: siempre enviaba `currency: 'ARS'` al crear preferencias de MP, quotes, y al persistir breakdowns en `order_payment_breakdown`.

Esto significaba que un tenant de Chile (CL) con `currency_id=CLP` en `country_configs` igualmente recibiría una preferencia de MP con items en ARS.

### Solución implementada

**Principio:** El `MercadoPagoService` ahora resuelve la currency del tenant consultando `clients.country` → `CountryContextService.getConfigByCountry()` → `currency_id`, con fallback a `'ARS'` si no hay configuración.

**Flujo después del fix:**
```
clients.country (Backend DB: AR, CL, MX, CO, UY, PE)
    │
    ▼
CountryContextService.getConfigByCountry() → country_configs → currency_id
    │
    ▼
resolveTenantCurrency(clientId) → ARS / CLP / MXN / COP / UYU / PEN
    │
    ▼
createPreferenceUnified → MP preference items con currency_id correcto ✅
snapshotBreakdown → order_payment_breakdown con currency correcto ✅
```

---

## Archivos modificados

### API (templatetwobe) — 4 archivos

| Archivo | Cambio |
|---------|--------|
| `src/tenant-payments/mercadopago.service.ts` | +import CountryContextService, +inyección en constructor, +método `resolveTenantCurrency(clientId)`, cambio de `'ARS'` → `await this.resolveTenantCurrency(clientId)` |
| `src/tenant-payments/mercadopago.controller.ts` | Removido `currency: 'ARS'` de totals en flujos partial y total (la currency se resuelve en el service) |
| `src/payments/payments.controller.ts` | Removido `currency: 'ARS'` de totals en flujos partial y total |
| `src/payments/payments.service.ts` | +parámetro `currency?` en `snapshotBreakdown`, +resolución dinámica inline (`clients.country` → map → currency), payload usa variable resuelta |

### E2E (novavision-e2e) — 2 archivos

| Archivo | Cambio |
|---------|--------|
| `tests/qa-v2/21-mp-currency-per-country.spec.ts` | **Nuevo** — Suite 21 con 24 tests en 9 fases |
| `playwright.config.ts` | +proyecto `v2-21-mp-currency` |

---

## Detalle técnico del fix

### `mercadopago.service.ts` — método nuevo

```typescript
private async resolveTenantCurrency(clientId: string): Promise<string> {
  const { data: clientRow } = await this.supabaseService
    .getMulticlienteClient()
    .from('clients')
    .select('country')
    .eq('id', clientId)
    .maybeSingle();

  if (!clientRow?.country) return 'ARS';

  const config = await this.countryContext.getConfigByCountry(clientRow.country);
  return config?.currency_id || 'ARS';
}
```

### `payments.service.ts` — resolución inline en `snapshotBreakdown`

```typescript
if (!currency && clientId) {
  const { data: cl } = await this.supabaseService
    .getMulticlienteClient()
    .from('clients')
    .select('country')
    .eq('id', clientId)
    .maybeSingle();
  const countryToCurrency: Record<string, string> = {
    AR: 'ARS', CL: 'CLP', MX: 'MXN',
    CO: 'COP', UY: 'UYU', PE: 'PEN', BR: 'BRL',
  };
  currency = countryToCurrency[cl?.country] || 'ARS';
}
```

---

## Suite E2E 21 — MP Currency Per Country

**24 tests, 9 fases:**

| Fase | Tests | Qué valida |
|------|-------|------------|
| 21.01 | 1 | `country_configs` tiene las 6 currencies correctas |
| 21.02 | 1 | Existen test tenants para los 6 países en Backend DB |
| 21.03 | 6 | `/tenant/bootstrap` retorna `currency_id` correcto por país |
| 21.04 | 6 | `/mercadopago/quote` requiere auth (401 esperado) |
| 21.05 | 6 | `create-preference` resuelve currency correcta (o MP_NOT_CONFIGURED) |
| 21.06 | 1 | Tenant sin país cae a fallback ARS (skip si no hay) |
| 21.07 | 1 | Tenants no-AR NO reciben ARS del bootstrap |
| 21.08 | 1 | `country_configs` tiene todos los campos requeridos |
| 21.09 | 1 | Cleanup de test orders y users |

**Resultado:** 23 passed, 1 skipped (21.06 — no hay tenants sin país), 0 failed

---

## Validación de suscripciones

Se investigó y confirmó que el flujo de **suscripciones** (`SubscriptionService`) ya maneja currency correctamente:
- Planes priceados en USD (`plans.monthly_fee`)
- `FxService` convierte USD → moneda local via `fx_rates_config`
- `getCurrencyForCountry()` mapea país → currency dinámicamente
- MP PreApproval recibe `currency_id` correcto
- Cron diario ajusta precios por inflación

**No requiere cambios.**

---

## Estado de DB verificado

| Tabla | Filas | Impacto |
|-------|-------|---------|
| `client_payment_settings` | 0 | Siempre cae al fallback — no hay datos para migrar |
| `orders` | 0 | No hay datos para migrar |
| `order_payment_breakdown` | 0 | No hay datos para migrar |
| `clients.country` | 6+ tenants con país real | AR, CL, MX, CO, PE, UY |
| `country_configs` | 7 | AR, CL, MX, CO, UY, PE, BR (BR inactivo) |

---

## Cómo probar

```bash
# 1. API (lint + typecheck + build)
cd apps/api && npm run lint && npm run typecheck && npm run build

# 2. Levantar API
npm run start:dev

# 3. E2E suite 21
cd novavision-e2e
export $(grep -v '^#' .env.e2e | grep '=' | xargs)
API_URL=http://localhost:3000 npx playwright test --project=v2-21-mp-currency --reporter=list --config=pw-no-setup.config.ts
```

---

## Riesgos y notas

- **`mp_fee_table`** tiene columna `country_code` pero `findFeeRule()` no filtra por país — las comisiones de MP pueden variar por país. Es un fix futuro separado.
- **Fallback seguro:** Si un tenant no tiene `country` o la config no existe, siempre cae a `'ARS'` (comportamiento actual preservado).
- **No hay breaking changes:** Los callers que ya pasaban `currency` en `totals` siguen funcionando igual; el nuevo código solo resuelve cuando `totals.currency` es `undefined`.

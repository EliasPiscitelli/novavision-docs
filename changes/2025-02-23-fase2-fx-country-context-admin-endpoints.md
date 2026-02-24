# Fase 2 — FxService v2, CountryContextService y Admin Endpoints

- **Autor:** agente-copilot
- **Fecha:** 2025-02-23
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Repo:** `apps/api` (templatetwobe)

---

## Archivos creados

| Archivo | Descripción |
|---------|-------------|
| `src/common/fx.service.ts` | FxService v2 — multi-país, Redis+memory cache, dual-source (dolarapi AR / frankfurter otros) |
| `src/common/country-context.service.ts` | CountryContextService — lee `country_configs` de Admin DB, cache 30min |
| `src/admin/admin-fx-rates.controller.ts` | GET/PATCH/POST `/admin/fx/rates` — CRUD tasas FX para super admins |
| `src/admin/admin-country-configs.controller.ts` | GET/PATCH/POST `/admin/country-configs` — CRUD configs de país para super admins |

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/common/common.module.ts` | Agregado `CountryContextService` a providers/exports + import `RedisModule` |
| `src/admin/admin.module.ts` | Registrados 2 nuevos controllers (`AdminFxRatesController`, `AdminCountryConfigsController`) |
| `src/seo-ai-billing/seo-ai-billing.module.ts` | Eliminado `DolarBlueService` de providers/exports |
| `src/seo-ai-billing/seo-ai-purchase.service.ts` | Reemplazado `DolarBlueService` por `FxService` (method `getBlueDollarRate()`) |
| `src/seo-ai-billing/seo-ai-purchase.controller.ts` | Reemplazado `DolarBlueService` por `FxService` (response shape cambia: `rate` + `fetchedAt`) |
| `src/subscriptions/subscriptions.service.ts` | Inyectado `CountryContextService`; `reconcileCrossDb()` ahora selecciona `country, locale, timezone` y tiene check D7 que sincroniza country/locale/timezone de Admin→Backend |

## Archivos archivados (legacy)

| Archivo | Antes |
|---------|-------|
| `src/common/fx.service.legacy.ts` | Era `fx.service.ts` (39 líneas, cache single AR) |
| `src/common/services/dolar-blue.service.legacy.ts` | Era `dolar-blue.service.ts` (100 líneas, solo dólar blue) |

---

## Resumen de cambios

### 2.1 — FxService v2 (multi-país + Redis)
- Soporta múltiples países (AR→dolarapi oficial, resto→frankfurter.dev vía `fx_rates_config`)
- Cache dual: Redis (si disponible) + in-memory fallback
- TTL configurable por país desde `fx_rates_config.cache_ttl_seconds`
- Persiste `last_auto_rate` y `last_error` de vuelta a DB (fire-and-forget)
- Backward-compatible: `getBlueDollarRate()` delega a `getRate('AR')`

### 2.2 — Eliminación de DolarBlueService
- Consumidores migrados a FxService v2
- Archivo original archivado como `.legacy.ts`

### 2.3 — CountryContextService
- Lee tabla `country_configs` de Admin DB
- Cache en memoria con TTL 30min
- Métodos: `getConfigBySiteId()`, `getConfigByCountry()`, `getAllActive()`, `refresh()`
- Implementa `OnModuleInit` para carga eager

### 2.4 — Admin FX Rates (`/admin/fx/rates`)
- `GET /admin/fx/rates` — lista todas las tasas (merged config + rate actual)
- `PATCH /admin/fx/rates/:countryId` — actualiza config (manual_rate, enabled, ttl, etc.)
- `POST /admin/fx/rates/:countryId/refresh` — fuerza refresh de tasa
- Protegido con `SuperAdminGuard` + `@AllowNoTenant()`

### 2.5 — Admin Country Configs (`/admin/country-configs`)
- `GET /admin/country-configs` — lista todas (incluyendo inactivas)
- `PATCH /admin/country-configs/:siteId` — actualiza config
- `POST /admin/country-configs` — crea nuevo país
- Invalida cache de CountryContextService en mutaciones
- Protegido con `SuperAdminGuard` + `@AllowNoTenant()`

### 2.6 — Sync country en reconcileCrossDb
- `nv_accounts` SELECT ahora incluye `country, mp_site_id`
- `clients` SELECT ahora incluye `country, locale, timezone`
- Nuevo check D7: si `account.country != client.country`, actualiza client con country + locale/timezone (vía CountryContextService lookup)

---

## Por qué

Infraestructura de internacionalización LATAM definida en el Plan Maestro §9 Fase 2. Permite:
- Cotizar precios de suscripción en moneda local de cada país
- Configurar y monitorear tasas FX desde el admin
- Mantener sincronizados los datos de país entre Admin y Backend DBs
- Escalar a nuevos países solo agregando filas en `country_configs` y `fx_rates_config`

## Cómo probar

```bash
# 1. Lint (0 errors, solo warnings preexistentes)
cd apps/api && npm run lint

# 2. TypeScript (0 errors)
npx tsc --noEmit

# 3. Build
npm run build && ls -la dist/main.js

# 4. Levantar dev
npm run start:dev
# Verificar en logs que CountryContextService carga configs
# Verificar que FxService se inicializa sin errores

# 5. Test endpoints admin (requiere cookie nv_ik o header x-internal-key)
curl -H "x-internal-key: <INTERNAL_ACCESS_KEY>" http://localhost:3000/admin/fx/rates
curl -H "x-internal-key: <INTERNAL_ACCESS_KEY>" http://localhost:3000/admin/country-configs
```

## Notas de seguridad

- Ambos endpoints admin requieren `SuperAdminGuard` (tabla `super_admins` + INTERNAL_ACCESS_KEY)
- No se exponen keys ni tokens en el código
- FxService usa `SERVICE_ROLE_KEY` (via DbRouterService) para leer/escribir `fx_rates_config` en Admin DB

## Riesgos

- **Response shape change** en `GET /seo-ai/packs`: ahora devuelve `usd_rate` / `rate_fetched_at` en vez de `usd_rate` / `rate_updated_at`. El frontend admin necesitará actualización en Fase 5.
- **Redis opcional**: Si no hay `REDIS_URL`, FxService usa only in-memory cache. En prod con múltiples instancias Railway, cada instancia tendrá su propia cache (eventual consistency aceptable para FX rates).
- **reconcileCrossDb D7**: Si `country_configs` no tiene el site_id esperado, solo sincroniza country sin locale/timezone.

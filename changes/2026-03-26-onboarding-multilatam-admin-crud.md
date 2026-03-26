# Onboarding Multi-LATAM — Admin CRUD para Subdivisions y Fiscal Categories

**Fecha:** 2026-03-26
**Plan:** `PLAN_COUNTRY_VISIBILITY_E2E_EXPANSION.md` — Onboarding Multi-LATAM
**Estado:** Implementado + testeado

---

## Problema

Las tablas `country_subdivisions` y `country_fiscal_categories` ya estaban migradas y seedeadas (149 subdivisiones en 6 países, 24 categorías fiscales), pero no existían endpoints admin para gestionarlas. El super admin no podía agregar, editar ni eliminar subdivisiones o categorías fiscales sin tocar la base de datos directamente.

## Solución

### Endpoints agregados a `AdminCountryConfigsController`

| Ruta | Método | Propósito |
|------|--------|-----------|
| `GET /admin/country-configs/:countryId/subdivisions` | GET | Listar subdivisiones por país |
| `POST /admin/country-configs/:countryId/subdivisions` | POST | Crear subdivisión |
| `PATCH /admin/country-configs/subdivisions/:id` | PATCH | Actualizar subdivisión |
| `DELETE /admin/country-configs/subdivisions/:id` | DELETE | Eliminar subdivisión |
| `GET /admin/country-configs/:countryId/fiscal-categories` | GET | Listar categorías fiscales por país |
| `POST /admin/country-configs/:countryId/fiscal-categories` | POST | Crear categoría fiscal |
| `PATCH /admin/country-configs/fiscal-categories/:id` | PATCH | Actualizar categoría fiscal |
| `DELETE /admin/country-configs/fiscal-categories/:id` | DELETE | Eliminar categoría fiscal |

### Detalles

- Todos protegidos con `SuperAdminGuard` + `@AllowNoTenant()`
- `countryId` se normaliza a uppercase para consistencia con la BD
- Validación inline de campos requeridos (`code`+`name` para subdivisions, `code`+`label` para fiscal categories)
- Los endpoints operan sobre Admin DB vía `dbRouter.getAdminClient()`

### Estado previo del onboarding multi-LATAM (ya implementado)

- 5 migraciones de BD ejecutadas (country_configs columns, country_subdivisions, country_fiscal_categories, nv_accounts generic fiscal, subscriptions multicurrency)
- `FiscalIdValidatorService` para 7 países (AR, BR, CL, CO, UY, PE, MX)
- `CountryContextService` con cache de configs
- Endpoints de onboarding: `GET /onboarding/country-config/:countryId`, `GET /onboarding/active-countries`

### Archivos modificados

- `api/src/admin/admin-country-configs.controller.ts` — 8 endpoints CRUD nuevos

### Tests creados

- `api/src/admin/__tests__/admin-country-configs.controller.spec.ts` — 24 tests:
  - listCountries (2): retorna datos, error DB
  - updateCountry (2): actualiza + invalida cache, NotFoundException
  - createCountry (1): crea + invalida cache
  - listSubdivisions (2): lista con uppercase, array vacío
  - createSubdivision (3): crea, falta code, falta name
  - updateSubdivision (2): actualiza por id, NotFoundException
  - deleteSubdivision (2): elimina, error DB
  - listFiscalCategories (2): lista, array vacío
  - createFiscalCategory (4): crea, falta code, falta label, con description+sort_order
  - updateFiscalCategory (2): actualiza por id, NotFoundException
  - deleteFiscalCategory (2): elimina, error DB

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 110/110 suites, 1087/1089 tests OK (2 skipped preexistentes)

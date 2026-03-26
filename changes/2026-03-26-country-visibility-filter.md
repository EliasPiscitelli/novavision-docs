# Country Visibility Filter — Phase 1

**Fecha:** 2026-03-26
**Plan:** `PLAN_COUNTRY_VISIBILITY_E2E_EXPANSION.md` Phase 1
**Estado:** Implementado (API-side)

---

## Problema

El super admin dashboard no tenía forma de filtrar por país en las vistas principales de clientes y finanzas. Con la expansión multi-LATAM, es necesario poder segmentar las vistas por país.

## Solución

### Endpoints que ya tenían country filter (previo)

| Endpoint | Estado |
|----------|--------|
| `GET /admin/dashboard-meta` | Ya retornaba breakdown por país |
| `GET /admin/pending-approvals?country=` | Ya implementado |
| `GET /admin/pending-completions?country=` | Ya implementado |
| `GET /admin/quotas?country=` | Ya implementado |
| `GET /admin/adjustments?country=` | Ya implementado |
| `GET /admin/subscription-events?country=` | Ya implementado |
| `GET /admin/cancellations?country=` | Ya implementado |

### Endpoints modificados (nuevo)

| Endpoint | Cambio |
|----------|--------|
| `GET /admin/clients?country=` | Filtro en Backend DB (`clients.country`) + Admin DB (`nv_accounts.country`) para drafts |
| `GET /admin/finance/clients?country=` | Filtro + campo `country` agregado al select |

### Dato clave

La tabla `clients` (Backend DB) tiene columna `country` — actualmente 1 AR + 2 NULL.
La tabla `nv_accounts` (Admin DB) tiene columna `country` — usada en `dashboard-meta`.

### Pendiente (no API)

- Frontend: `CountryFilterContext` + selector dropdown en admin dashboard
- `GET /admin/metrics/summary`: usa RPC `dashboard_metrics`, requiere migración SQL para agregar param `p_country`

### Archivos modificados

- `api/src/admin/admin.controller.ts` — `getAllClients()` y `getFinanceClients()` con query param `country`

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 109/109 suites, 1063/1065 tests OK

# Cambio: fixes de addons recurrentes y runtime del dashboard de tienda

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Ramas objetivo: `feature/automatic-multiclient-onboarding`, `develop`, `feature/multitenant-storefront`
- Repositorios: `apps/api`, `apps/web`, `novavision-docs`

## Archivos modificados

- `apps/api/src/addons/addons.service.ts`
- `apps/api/src/addons/addons.service.spec.ts`
- `apps/web/src/components/admin/AnalyticsDashboard/index.jsx`
- `apps/web/src/components/admin/AnalyticsDashboard/AnalyticsLineChart.jsx`

## Resumen

Se corrigieron dos fallas productivas distintas:

1. El endpoint admin de addons recurrentes dejaba de responder en entornos legacy porque asumía la existencia de `account_addons.created_at`.
2. El dashboard admin de tienda seguía exponiendo un `ReferenceError` minificado en produccion dentro del chunk `admin-dashboard`, asociado a la carga temprana de `recharts` dentro de `AnalyticsDashboard`.

## Qué se cambió

### API

- Se removió `created_at` del `select` sobre `account_addons` en `listRecurringAddonsAdmin()`.
- Se mantuvo el campo de salida `created_at` con fallback a `purchased_at` y luego `updated_at`, para no romper el contrato del super admin dashboard.
- Se ajustó el test de cobertura para validar que el flujo sigue funcionando aun cuando `created_at` no exista en el row devuelto por la tabla legacy.

### Web

- Se extrajo el render de charts de `AnalyticsDashboard` a un componente lazy separado (`AnalyticsLineChart.jsx`).
- El dashboard principal ya no importa `recharts` en el scope del modulo base del tab de analytics.
- Se agregaron `Suspense` y un fallback chico por gráfico, para diferir la carga del bundle de charts y evitar el ciclo/TDZ observado en producción.

## Por qué

- Los logs productivos del backend confirmaron el error real: `column account_addons.created_at does not exist`.
- La investigacion del bundle del storefront y el changelog de performance previo ya marcaban a `recharts` como candidato sensible dentro de `admin-dashboard`; la estrategia segura es moverlo a una carga lazy interna sin cambiar el contrato del tab.

## Cómo probar

### API

Desde `apps/api`:

```bash
npm test -- --runInBand src/addons/addons.service.spec.ts
npm run lint
npm run typecheck
npm run build
```

### Web

Desde `apps/web`:

```bash
npm run lint
npm run typecheck
npm run build
```

## Riesgos

- Bajo en API: el contrato de salida se conserva, solo se elimina una dependencia a una columna no portable.
- Bajo en Web: el cambio solo afecta la carga de los gráficos de analytics; el resto del dashboard no cambia.

## Notas de seguridad

- No se modificaron permisos, autenticacion, RLS ni contratos de pago.

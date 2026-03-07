# Cambio: degradación segura para endpoints de addons en super admin dashboard

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama API: feature/automatic-multiclient-onboarding
- Rama Docs: main

## Archivos modificados

- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts

## Resumen

Se blindaron los endpoints del addon store consumidos por el super admin dashboard para que no respondan con `500` cuando el ambiente todavía tiene migraciones parciales o schema drift en tablas nuevas como `account_addons` o `billing_adjustments`.

## Por qué

La vista global de addons del dashboard dispara varias requests en paralelo:

- `GET /admin/addons/catalog`
- `GET /admin/addons/purchases`
- `GET /admin/addons/recurring/statuses`
- `GET /admin/addons/purchases/:id`

En ambientes donde la fase de addons quedó desplegada parcialmente, algunas consultas podían romper por:

- tablas aún no presentes en PostgREST cache
- columnas legacy faltantes
- valor enum `addon_subscription` todavía no habilitado en `billing_adjustments`

El resultado era ruido de red y errores visibles en el super admin dashboard aunque el resto del panel estuviera sano.

## Qué se cambió

- `listRecurringAddonsAdmin()` ahora devuelve vacío si `account_addons` no está disponible todavía.
- La carga de `billing_adjustments` para overdue recurrente ahora se degrada a `overdue_adjustments: []` cuando el enum `addon_subscription` aún no existe en la DB.
- Los jobs manuales y la reconciliación de uplifts recurrentes ahora también salen de forma segura con resultado vacío si el schema aún no soporta esos objetos.
- Se centralizó la detección de schema drift combinando:
  - tabla faltante / schema cache inconsistente
  - valor enum inválido para `addon_subscription`

## Cómo probar

Desde apps/api:

```bash
npm run test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build
```

Validación funcional sugerida:

1. Abrir el super admin dashboard en la vista de addon store.
2. Verificar que la pantalla cargue aunque el ambiente no tenga aún datos o migraciones completas de addons.
3. Confirmar que las tarjetas/listas muestren vacío en lugar de error fatal.

## Notas de seguridad

- No se relajaron guards ni autenticación.
- No se cambió el contrato exitoso de los endpoints cuando el schema está completo.
- El cambio sólo evita que fallos de migración parcial derriben la experiencia del dashboard.
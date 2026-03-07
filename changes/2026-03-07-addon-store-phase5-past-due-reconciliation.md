# Cambio: Addon Store Phase 5 - reconciliación past_due y ejecución controlada

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Docs: main

## Archivos modificados

- apps/api/src/addons/addon-recurring-billing.cron.ts
- apps/api/src/addons/addons.admin.controller.ts
- apps/api/src/addons/addons.module.ts
- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts
- novavision-docs/runbooks/addon-store-smoke-qa.md

## Resumen

Se cerró la política funcional pendiente para uplifts recurrentes: ahora existe reconciliación de `past_due` basada en `billing_adjustments` vencidos de tipo `addon_subscription`, con reactivación automática al regularizar deuda y re-sincronización de `entitlement_overrides`. También se ejecutó el trigger manual y la reconciliación sobre el período controlado `2026-03-01`.

## Qué se implementó

- Cron diario de reconciliación de uplifts recurrentes.
- Endpoint manual `POST /admin/addons/recurring/reconcile-status`.
- Reconciliación `active ↔ past_due` en `account_addons` según deuda vencida de períodos anteriores.
- Bloqueo de recompra cuando un uplift ya existe en estado `active` o `past_due`.
- Re-sincronización de `clients.entitlement_overrides` cuando el addon entra o sale de `past_due`.
- Fix de wiring real: `AddonsModule` ahora importa `SubscriptionsModule` para resolver `PlatformMercadoPagoService` en runtime.

## Ejecución controlada real

Período ejecutado: `2026-03-01`

### Preview previo

- Cuentas candidatas a generar `addon_subscription`: `0`
- Uplifts con deuda vencida para marcar `past_due`: `0`

### Resultado del trigger manual

```json
{
  "created": 0,
  "skipped": 0,
  "errors": 0,
  "periodStart": "2026-03-01",
  "details": []
}
```

### Resultado de la reconciliación manual

```json
{
  "markedPastDue": 0,
  "reactivated": 0,
  "errors": 0,
  "periodStart": "2026-03-01",
  "details": []
}
```

## Smoke QA manual

Se ejecutó la pasada guiada de backend/DB del runbook:

- historial real en `account_addon_purchases`: sin registros
- fulfillments reales en `account_addon_fulfillments`: sin registros
- addons activos en `account_addons`: sin registros

Conclusión: la superficie quedó lista y consistente, pero el ambiente todavía no tiene datos reales del addon store para validar compra/historial/fulfillment con casos vivos.

## Validación técnica

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm run test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build
```

Resultado:

- tests focalizados: OK
- typecheck: OK
- build: OK

## Riesgos / próximos pasos

- Falta repetir el smoke QA cuando exista al menos una compra real de addon o uplift en la DB.
- La política `past_due` ya revoca capacidad efectiva, pero la estrategia de notificación al tenant por deuda vencida todavía puede ampliarse en una fase posterior.
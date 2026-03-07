# Cambio: FAQ y Services con hard enforcement backend

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Rama: feature/automatic-multiclient-onboarding / feature/multitenant-storefront / main
- Archivos:
  - `apps/api/src/plans/plans.service.ts`
  - `apps/api/src/faq/faq.service.ts`
  - `apps/api/src/service/service.service.ts`
  - `apps/web/src/hooks/useEffectivePlanConfig.js`
  - `apps/web/src/components/admin/FaqSection/index.jsx`
  - `apps/web/src/components/admin/ServiceSection/index.jsx`

## Resumen

Se convirtió FAQ y Services en capacidades con enforcement backend real usando el mismo motor de límites del plan. El frontend sigue mostrando límites y ahora además refleja el mensaje real del backend cuando se supera el cupo.

## Qué se hizo

1. Se extendió `PlansService` para exponer y validar:
   - `max_faqs`
   - `max_services`
   - `faqs_count`
   - `services_count`
2. Se agregaron acciones nuevas en validación:
   - `create_faq`
   - `create_service`
3. Se aplicó enforcement real en backend dentro de:
   - `FaqService.createFaq()`
   - `ServiceService.createService()`
4. Se mantuvo compatibilidad usando fallback temporal a los límites legacy por plan cuando esos campos todavía no existen en `plans.entitlements`.
5. El frontend ahora prioriza `max_faqs` y `max_services` efectivos cuando vienen de `/plans/my-limits`.
6. El frontend muestra el mensaje exacto devuelto por backend cuando el plan excede el límite.

## Impacto funcional

- Antes: FAQ y Services estaban limitados solo por frontend.
- Ahora: no se pueden crear por API si el plan ya alcanzó el límite.
- Edición y borrado siguen permitidos.
- No se agregaron todavía migraciones para persistir `max_faqs` y `max_services` en `plans.entitlements`; por eso se usa fallback backend temporal.

## Validación ejecutada

### API

- `api:typecheck` OK
- `api:build` OK
- Sin errores en archivos modificados

### Web

- `npm run ci:storefront` OK
- Sin errores en archivos modificados
- Persisten warnings históricos no bloqueantes del repo

## Riesgos conocidos

1. `max_faqs` y `max_services` todavía no viven en schema como entitlements base reales; el enforcement usa fallback backend por plan.
2. Falta mostrar uso de FAQ y Services en un dashboard de uso más completo.
3. Falta cerrar la misma estrategia para categories, support y domains.

## Siguiente paso recomendado

Persistir `max_faqs` y `max_services` en `plans.entitlements` y dejar de depender del fallback temporal, luego extender `GET /plans/my-limits` hacia un dashboard de uso más completo.
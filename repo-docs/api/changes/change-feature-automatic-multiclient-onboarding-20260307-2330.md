# Cambio: hard limits de addons, storage y cleanup de Jest

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/plans/plans.service.ts, src/plans/plans-admin.controller.ts, src/faq/faq.service.ts, src/service/service.service.ts, src/banner/banner.service.ts, src/logo/logo.service.ts, src/home/home-settings.controller.ts, src/import-wizard/import-wizard.controller.ts, src/import-wizard/import-wizard.service.ts, src/shipping/shipping-quote.service.ts, migrations/admin/ADMIN_092_seed_faq_service_entitlements.sql

## Resumen

Se endurecieron los limites backend-hard para FAQ y Services, se agrego enforcement de storage en uploads de banners, logos, popup e import wizard, se incorporo chequeo preventivo y bloqueante por lote en import wizard y se corrigio un intervalo sin cleanup que podia dejar handles abiertos en Jest.

## Por que

El Addon Store y los limites de plan necesitaban enforcement real desde backend. Ademas, algunos flujos de media seguian subiendo assets sin pasar por validacion dura de cuota. Por ultimo, ShippingQuoteService dejaba un intervalo vivo que podia mantener el event loop abierto en suites e2e.

## Como validar

1. Ejecutar `npm run lint`.
2. Ejecutar `npm run typecheck`.
3. Ejecutar `npm run build`.
4. Verificar desde el dashboard cliente que FAQ, Services, logo, popup, banners e import wizard muestren o respeten limites de plan.
5. Confirmar que import wizard bloquee la confirmacion del lote si la proyeccion excede storage.

## Notas de seguridad

- No se agregaron credenciales nuevas.
- Los limites de storage y cantidad ahora se validan del lado servidor.
- El cambio de lifecycle en shipping solo limpia recursos; no modifica permisos ni acceso a datos.

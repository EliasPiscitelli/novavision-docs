# Cambio: hardening de shipping, pagos e Instagram webhook

- Autor: GitHub Copilot
- Fecha: 2026-03-09
- Rama: feature/automatic-multiclient-onboarding
- Archivos: cambios en shipping, tenant-payments, addons, admin, outreach, orders y tests relacionados

Resumen: se consolidan ajustes de contratos de shipping y pagos, mejoras de addons/admin, soporte de package data en productos y el gateway backend para Instagram que valida Meta y reenvia a n8n.

Actualización 2026-03-09 noche: `GET /admin/dashboard-meta` deja de depender solo de `nv_accounts.country` y ahora resuelve el país también por `nv_accounts.mp_site_id` cuando el campo legacy está vacío, evitando que todos los tenants caigan en `UNKNOWN`.

Por que: el lote actual combina hardening funcional y de contrato entre backend, storefront y admin, y necesita trazabilidad antes del push.

Como probar:
- `npm run lint`
- `npm run typecheck`
- `npm run build`
- `npm test -- --runInBand src/outreach/instagram-webhook.controller.spec.ts src/outreach/outreach.service.spec.ts src/orders/orders.controller.spec.ts src/orders/orders.service.spec.ts src/shipping/provider-specs.spec.ts src/shipping/shipping.service.spec.ts src/shipping/shipping-quote.service.spec.ts src/shipping/shipping-settings.service.spec.ts src/tenant-payments/__tests__/dto.validation.spec.ts src/tenant-payments/__tests__/helpers.sanitize.spec.ts src/tenant-payments/__tests__/service.confirmByExternalReference.spec.ts src/tenant-payments/__tests__/service.updateStock.spec.ts src/addons/addons.service.spec.ts src/import-wizard/__tests__/import-wizard.service.spec.ts src/import-wizard/__tests__/import-wizard.validators.spec.ts src/import-wizard/__tests__/import-wizard.worker.spec.ts`

Notas de seguridad:
- El callback de Meta queda backend-first en `/webhooks/instagram`.
- El relay a n8n depende de `N8N_IG_INBOUND_WEBHOOK_URL`.
- Los dumps temporales bajo `tmp/` no forman parte del commit productivo.
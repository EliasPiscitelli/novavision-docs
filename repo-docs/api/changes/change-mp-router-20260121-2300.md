# Cambio: Router de webhooks MP + dedupe por dominio

- Autor: agente-copilot
- Fecha: 2026-01-21
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/controllers/mp-router.controller.ts, src/services/mp-router.service.ts, src/webhooks/mp-router.module.ts, src/tenant-payments/mercadopago.controller.ts, src/tenant-payments/mercadopago.service.ts, src/tenant-payments/helpers/external-reference.ts, src/subscriptions/subscriptions.controller.ts, src/subscriptions/subscriptions.service.ts, src/auth/auth.middleware.ts, migrations/admin/20260121_create_tenant_payment_events.sql, src/tenant-payments/__tests__/controller.webhook.spec.ts

Resumen: Se incorporó un router dedicado para webhooks de Mercado Pago, con idempotencia por dominio (tenant vs platform), verificación de firma por dominio, guardrails de external_reference y tabla de dedupe para checkout de tiendas. Se estandarizó external_reference (NV_SUB / NV_ORD) y se ajustaron endpoints legacy para delegar al router.

Por qué: Evitar cruces entre dominios de MP, garantizar idempotencia y facilitar reconciliación/observabilidad.

Cómo probar / comandos ejecutados:
- (pendiente) npm run lint (apps/api)
- (pendiente) npm run typecheck (apps/api)

Notas de seguridad: Webhooks requieren secretos por dominio (MP_WEBHOOK_SECRET_PLATFORM / MP_WEBHOOK_SECRET_TENANT). No se expusieron credenciales.

# Addon store phase 2 purchases and fulfillment

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Repos afectados: API (templatetwobe), Web (templatetwo), Docs
- Ramas: `feature/automatic-multiclient-onboarding`, `feature/multitenant-storefront`, `main`

## Resumen

Se avanzó con las dos piezas pendientes del addon store:

1. persistencia real de compras de addons en Admin DB;
2. historial tenant + primer flujo de fulfillment manual para servicios one-time.

## Archivos modificados

### API

- `migrations/admin/20260306_addon_store_purchases_and_fulfillment.sql`
- `src/addons/addons.module.ts`
- `src/addons/addons.service.ts`
- `src/addons/addons.controller.ts`
- `src/addons/addons.admin.controller.ts`
- `src/seo-ai-billing/seo-ai-purchase.service.ts`
- `src/app.module.ts`

### Web

- `src/components/admin/AddonStoreDashboard/index.jsx`

## Qué se implementó

- tabla `account_addon_purchases` para registrar compras con snapshot comercial y vínculo a `nv_billing_events`;
- tabla `account_addon_fulfillments` para addons de servicio con entrega manual;
- persistencia automática para compras iniciadas desde `/addons/purchase`;
- sincronización de compras SEO ya acreditadas cuando el webhook agrega créditos;
- endpoint tenant `GET /addons/purchases` para historial;
- endpoint webhook `POST /addons/webhook` para servicios one-time;
- endpoints super admin para listar compras, ver detalle y actualizar fulfillment.

## Decisiones

- SEO AI sigue con su webhook actual, pero ahora sincroniza la compra persistida cuando acredita créditos.
- Los servicios one-time usan webhook propio del módulo `addons` y quedan en `pending_fulfillment` tras pago aprobado.
- El historial tenant soporta tanto consumibles como servicios.

## Riesgos / siguientes pasos

- La migración admin debe aplicarse antes de usar historial y fulfillment en producción.
- Falta UI super admin para operar fulfillments; por ahora existe vía API.
- Los uplifts mensuales todavía no entran en esta fase y seguirán en el backlog de `entitlement_overrides`.
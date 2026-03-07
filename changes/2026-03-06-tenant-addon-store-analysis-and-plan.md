# Tenant addon store analysis and plan

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Repos relevados: API (templatetwobe), Web (templatetwo), Admin (novavision), Docs
- Ramas: `feature/automatic-multiclient-onboarding`, `feature/multitenant-storefront`, `main`

## Archivos documentados

- `plans/PLAN_TENANT_ADDON_STORE_V1.md`
- `plans/PLAN_TENANT_ADDON_STORE_TECHNICAL_DESIGN.md`

## Resumen

Se documentó la propuesta para evolucionar el patrón actual de SEO AI packs hacia un store de addons para tenant admins.

La definición quedó separada en dos capas:

1. Catálogo comercial inicial y reglas de pricing por plan.
2. Diseño técnico para pagos, provisión, endpoints, DB y reglas anti-abuso.

## Hallazgos relevantes que motivan la propuesta

- El patrón de compra de SEO AI ya resuelve catálogo, billing event, Mercado Pago, webhook e idempotencia.
- `addon_catalog` ya existe, pero su diseño actual es demasiado chico para soportar distintos tipos de addon.
- `PlansService` ya soporta `plans.entitlements + clients.entitlement_overrides`, que es la vía correcta para uplifts persistentes.
- No conviene modelar aumentos estructurales como compra one-time permanente.

## Decisiones documentadas

- Consumibles y servicios one-time sí deben poder comprarse por checkout directo.
- Los uplifts de capacidad deben ser mensuales y recomputar `entitlement_overrides`.
- Starter no debería recibir uplifts estructurales libres en V1.
- Growth sí puede recibir uplifts moderados con topes por familia.
- Enterprise debe quedar mayormente en flujo asistido para cambios estructurales grandes.

## Alcance sugerido V1

- Mantener SEO AI packs como vertical productivo inicial.
- Agregar servicios operativos one-time.
- Habilitar uplifts mensuales solo para Growth.
- Posponer ledger genérico hasta tener un segundo caso real además de SEO.

## Por qué se registró en docs

La definición toca pricing, billing, límites de plan, UX de tenant admin y operación super admin. Necesitaba quedar consolidada antes de implementar para evitar soluciones parciales o mezclas entre tokens, overrides y upgrades de plan.
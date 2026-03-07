# Cambio: Plan de implementación para Addon Store con hard entitlements

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Rama: main
- Archivos: plans/PLAN_ADDON_STORE_HARD_ENTITLEMENTS_IMPLEMENTATION.md

## Resumen

Se agregó un plan de implementación por etapas para convertir el Addon Store en un sistema basado en entitlements backend duros, límites por plan, políticas de stacking y lifecycle completo.

## Por qué

La auditoría detectó que el estado actual del Addon Store solo soporta de forma sólida uplifts de productos y banners, mientras que FAQ, Services, Media, Storage, Support y Domain Bridge requieren cerrar backend enforcement, medición de uso, truth sources y lifecycle antes de publicarse como SKUs self-serve.

## Qué define el plan

- Entitlements nuevos a modelar.
- Deltas de addons a soportar.
- Reglas anti-cannibalización.
- Lifecycle esperado por familia.
- Etapas de implementación con gates de salida.
- Matriz de impacto por flujo.
- Suite mínima de validación por etapa.

## Cómo validar

1. Revisar el plan en `plans/PLAN_ADDON_STORE_HARD_ENTITLEMENTS_IMPLEMENTATION.md`.
2. Confirmar que cubre:
   - pricing,
   - tenant admin,
   - Addon Store,
   - billing,
   - webhooks,
   - uploads,
   - domains,
   - support,
   - operación interna,
   - E2E.
3. Usarlo como backlog base para tickets P0/P1/P2.

## Notas de seguridad

- El plan asume que backend manda sobre frontend.
- No propone publicar nuevos addons hasta cerrar enforcement y lifecycle.
- Mantiene la separación entre extensiones de capacidad y upgrades de plan.
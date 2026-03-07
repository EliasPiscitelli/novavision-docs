# Cambio: Etapa 0 del Addon Store - source of truth alignment

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Rama: feature/multitenant-storefront / feature/automatic-multiclient-onboarding / main
- Archivos:
  - `apps/web/src/hooks/useEffectivePlanConfig.js`
  - `apps/web/src/components/admin/FaqSection/index.jsx`
  - `apps/web/src/components/admin/ServiceSection/index.jsx`
  - `apps/web/src/components/admin/BannerSection/index.jsx`
  - `apps/web/src/components/admin/ProductDashboard/index.jsx`
  - `apps/web/src/components/ProductModal/index.jsx`
  - `apps/web/src/components/CategoryManager/index.jsx`
  - `apps/web/src/components/admin/UserDashboard/index.jsx`
  - `apps/web/src/components/admin/LogoSection/index.jsx`
  - `plans/PLAN_ADDON_STORE_HARD_ENTITLEMENTS_BACKLOG.md`
  - `plans/PLAN_ADDON_STORE_ENTITLEMENTS_SCHEMA_API.md`

## Resumen

Se ejecutó el primer paso real de la Etapa 0: los componentes legacy del tenant admin dejaron de resolver el plan exclusivamente desde mirrors estáticos y ahora combinan el plan real de `GET /plans/my-limits` con un fallback controlado para campos aún no modelados en backend.

## Por qué

El estado previo tenía una fractura entre:

- pricing público,
- backend entitlements,
- tenant admin legacy config.

Eso hacía que partes del admin se comportaran con límites distintos al backend real. El cambio no elimina toda la deuda, pero reduce la deriva en límites críticos mientras se prepara la ampliación de schema/API.

## Qué se hizo

1. Se agregó `useEffectivePlanConfig()` en web.
2. El hook toma como base `GET /plans/my-limits`.
3. Mantiene fallback a `getPlanLimits()` solo para campos aún no modelados en backend.
4. Se migraron 8 consumidores legacy del helper estático.
5. Se documentó el backlog P0/P1/P2 y el diseño de schema/API para nuevos entitlements.

## Impacto validado

- Productos: ahora consumen `products_limit` e `images_per_product` efectivos.
- Banners: ahora consumen `banners_active_limit` efectivo.
- AI import: sigue usando `aiImport` real del backend cuando existe.
- FAQ, Services, Categories, Users, Logo: mantienen fallback legacy, pero anclado al plan real reportado por backend.

## Cómo probar

1. En tenant admin, abrir:
   - productos,
   - modal de producto,
   - banners,
   - FAQ,
   - services,
   - categorías,
   - usuarios,
   - logo.
2. Confirmar que no hay errores de render.
3. Confirmar que `UsageDashboard` y estos módulos no muestran planes contradictorios para Starter/Growth/Enterprise.
4. Ejecutar validación del frontend.

## Comandos ejecutados

- Validación estática con errores de archivos modificados.
- Queda pendiente corrida completa del frontend después de este cambio.

## Notas de seguridad

- No se tocó billing ni checkout.
- No se relajó enforcement backend.
- El cambio reduce la dependencia en mirrors legacy y prepara la migración a hard entitlements completos.
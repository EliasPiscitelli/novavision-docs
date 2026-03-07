# Cambio: Persistencia de entitlements FAQ/Services, cleanup de mirrors y enforcement de storage/media

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Rama API: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront
- Rama Admin: feature/automatic-multiclient-onboarding

## Resumen

Se avanzó sobre los puntos 1, 2 y 3 del plan inmediato:

1. Se dejó lista la migración para persistir `max_faqs` y `max_services` en `plans.entitlements`.
2. Se alinearon fallbacks legacy de límites del storefront con los seeds reales del backend y se eliminó drift interno en límites de secciones del admin builder.
3. Se endureció enforcement de storage/media para uploads de banners y servicios.

## Archivos modificados

- `apps/api/migrations/admin/ADMIN_092_seed_faq_service_entitlements.sql`
- `apps/api/src/plans/plans-admin.controller.ts`
- `apps/api/src/banner/banner.service.ts`
- `apps/api/src/service/service.service.ts`
- `apps/web/src/config/basicPlanLimits.jsx`
- `apps/web/src/config/professionalPlanLimits.jsx`
- `apps/web/src/config/premiumPlanLimits.jsx`
- `apps/admin/src/utils/sectionMigration.ts`

## Qué se hizo

### 1. Persistencia de entitlements

- Se agregó la migración `ADMIN_092_seed_faq_service_entitlements.sql`.
- La migración setea `max_faqs` y `max_services` en `public.plans.entitlements` para:
  - `starter` / `starter_annual`
  - `growth` / `growth_annual`
  - `enterprise` / `enterprise_annual`
- La migración fue aplicada en Admin DB usando `ADMIN_DB_URL`.
- `PlansAdminController` ahora acepta y expone esos campos en overrides/admin ops.
- `PlansService` dejó de depender del fallback legacy para `max_faqs` y `max_services`; ahora exige que vengan persistidos desde `plans.entitlements`.

### 2. Cleanup de mirrors legacy

- Se actualizaron los fallbacks estáticos del storefront para que no contradigan el seed real del backend cuando `/plans/my-limits` no esté disponible.
- Ajustes principales:
  - Starter: `maxProducts` 300
  - Growth: `maxProducts` 2000, `maxImagesPerProduct` 4, `maxDesktopBanners` 8
  - Enterprise: `maxProducts` 50000, `maxImagesPerProduct` 8, `maxDesktopBanners` 100
- En admin builder, `sectionMigration.ts` dejó de usar un límite duplicado `5/10/15` y ahora deriva de `registry/sections.ts`, que ya era la referencia correcta `8/12/unlimited`.

### 3. Enforcement de storage/media

- `BannerService.updateBanners()` ahora valida cuota de storage antes de subir archivos.
- `ServiceService.createService()` ahora valida:
  - cupo de cantidad de servicios
  - cuota de storage para la imagen
- `ServiceService.updateService()` ahora también valida cuota de storage si entra un nuevo archivo.
- `LogoService.updateLogo()` ahora valida cuota de storage antes de subir el logo.
- `HomeSettingsController.uploadPopupImage()` ahora valida cuota de storage antes de procesar la imagen del popup.
- `ImportWizardController.uploadStagedImage()` ahora valida:
  - cuota de storage del archivo staging
  - máximo de imágenes por item según `images_per_product`

### 4. UX de services y media

- `ServiceSection` ahora adapta densidad y copy según cantidad de servicios cargados.
- La grilla pasa de layout rígido a columnas adaptativas.
- Se agrega resumen de uso/capacidad/recomendación para que el usuario entienda mejor cuándo ya está saturando la sección.
- `LogoSection` y el upload de popup ahora muestran el mensaje real devuelto por backend cuando el bloqueo viene por storage/cupo.
- `LogoSection` y `IdentityConfigSection` ahora muestran storage usado, cuota total y margen antes del upload.
- Import Wizard expone un chequeo agregado por lote (`GET /import-wizard/batches/:batchId/storage-check`) para evaluar peso staged total sin crear una reserva persistente de cuota.
- `ImportWizardService.enqueueBatch()` ahora bloquea la confirmación si el peso staged proyecta un uso total por encima de `storage_gb_quota`.
- El paso final del wizard consume `storage-check` y deshabilita preventivamente `Confirmar e importar` cuando la proyección del lote ya excede la cuota.

## Validación

### API

- `npm run typecheck` OK en ejecución aislada
- `npm run build` OK en ejecución aislada

### Admin

- `npm run typecheck` OK en ejecución aislada

### Bases de datos

- Admin DB: migración `ADMIN_092_seed_faq_service_entitlements.sql` aplicada OK (`UPDATE 6`).
- Backend DB: validada la presencia de `clients.entitlement_overrides`; no requirió migración para este cambio.

### Web

- `npm run ci:storefront` OK
- Persisten warnings históricos no bloqueantes del repo

## Riesgos conocidos

1. Si un ambiente no tiene aplicada la migración de planes, `PlansService` ahora va a fallar explícitamente al faltar `max_faqs` o `max_services`.
2. El control de storage usa tamaño de archivo de entrada; no descuenta automáticamente variantes anteriores al reemplazar imágenes existentes.

## Siguiente paso recomendado

Replicar la migración en cualquier otro ambiente que todavía no esté alineado y luego avanzar al siguiente hueco de media/storage que siga sin enforcement duro.
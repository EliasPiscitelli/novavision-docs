# Cambio: paridad de preview entre shell nativo y contrato de secciones

- Autor: GitHub Copilot
- Fecha: 2026-03-13
- Rama: feature/multitenant-storefront + feature/automatic-multiclient-onboarding
- Archivos: apps/web/src/pages/PreviewHost/index.tsx, apps/web/src/services/homeData/homeService.jsx, apps/web/src/services/identity.js, apps/web/src/utils/normalizeSections.js, apps/web/src/utils/termsModalRouting.js, apps/web/src/App.jsx, apps/web/src/__tests__/normalize-sections.test.js, apps/web/src/__tests__/home-data-services.test.jsx, apps/web/src/__tests__/preview-host.test.jsx, apps/web/src/__tests__/terms-modal-routing.test.js, apps/api/src/home/home-settings.service.ts, apps/api/src/home/home-settings.service.spec.ts, novavision-e2e/tests/qa-v2/24-store-visual-settings.spec.ts, novavision-e2e/tests/qa-v2/25-preview-parity.spec.ts, novavision-e2e/helpers/provision-tenants.ts, novavision-e2e/playwright.config.ts

## Resumen

Se corrigieron dos causas raíz distintas del sistema de preview de NovaVision. En onboarding Step 4 se ajustó el shell del preview nativo para que los templates Tailwind no hereden offsets visuales de un header inexistente. En Store Design se alineó el contrato de secciones entre API y renderer para que el preview y la home real usen la misma variante de componente.

## Qué se cambió

- `PreviewHost` ahora fuerza `--header-height` y `--announcement-height` a `0px` cuando renderiza preview nativo de templates 6, 7 y 8.
- `PreviewHost` dejó de forzar `mode="store"` en ese path y mantiene el modo de preview/editor para no pisar variables CSS inyectadas por el propio host.
- Se agregó `normalizeSections.js` para unificar `component_key`, `componentKey` y `componentId` en el storefront.
- `fetchHomeData()` y `identityService` normalizan las listas de secciones apenas cruzan el borde de red.
- `HomeSettingsService` ahora selecciona `component_key` desde `home_sections` y devuelve `componentKey`/`componentId` además del campo original.
- Se agregó test unitario que fija este contrato en API.
- Se agregaron tests unitarios en web para validar la normalización de secciones y la respuesta efectiva de `fetchHomeData()` e `identityService`.
- Se agregó un test unitario específico de `PreviewHost` para validar el path nativo de templates 6-8, el modo `editor` y el reset de variables de header dentro del iframe.
- Se registró una smoke E2E en `novavision-e2e` para cubrir Step 4 del builder y Store Design contra preview/home real del tenant.
- Se corrigió un bug real del storefront shell: el modal de términos podía quedar abierto al navegar hacia `/admin-dashboard`, bloqueando Store Design en E2E y en navegación real.
- Se agregó `termsModalRouting.js` y un test unitario de regresión para garantizar que rutas admin, preview y dev no arrastren ese modal.
- Se actualizó `v2-24-store-visual-settings` al DOM actual de Design Studio (`button.template-card`, `.palette-card`) y al flujo real de guardado con confirmación de créditos.
- Se ajustó el provisioning E2E para crear `home_sections` persistidas base, evitando que Store Design compare una estructura visible por defaults contra una estructura persistida vacía.

## Por qué

El problema del onboarding no era de datos sino de contexto visual: los templates Tailwind calculaban márgenes con variables de header que el preview no renderizaba realmente. El problema del Store Design no era de CSS sino de shape mismatch: algunas rutas devolvían `component_key` en snake_case y el renderer resolvía variantes usando `componentKey` o `componentId`, por lo que podía caer en componentes genéricos o presets equivocados.

## Cómo probar

1. En `apps/api`, ejecutar `npm test -- --runInBand src/home/home-settings.service.spec.ts`.
2. En `apps/api`, ejecutar `npm run build`.
3. En `apps/web`, ejecutar `npm run typecheck`.
4. En `apps/web`, ejecutar `npm run build`.
5. En `apps/web`, ejecutar `npx vitest run src/__tests__/normalize-sections.test.js src/__tests__/home-data-services.test.jsx src/__tests__/store-design-section.test.jsx --reporter=verbose`.
6. En `apps/web`, ejecutar `npx vitest run src/__tests__/preview-host.test.jsx --reporter=verbose`.
7. En `novavision-e2e`, ejecutar `API_URL=http://127.0.0.1:3000 WEB_URL=http://localhost:5173 ADMIN_URL=http://localhost:5174 E2E_ALLOW_DESTRUCTIVE=true npx playwright test tests/qa-v2/24-store-visual-settings.spec.ts --project=v2-24-store-visual-settings --no-deps` para validar el acceso y guardado visual de Store Design en local.
8. En `novavision-e2e`, ejecutar `API_URL=http://127.0.0.1:3000 WEB_URL=http://localhost:5173 ADMIN_URL=http://localhost:5174 E2E_ALLOW_DESTRUCTIVE=true npx playwright test tests/qa-v2/25-preview-parity.spec.ts --project=v2-25-preview-parity --no-deps` para validar el smoke nuevo.
9. Abrir onboarding Step 4 con un template 6, 7 u 8 y comparar contra la home real del storefront.
10. Abrir Store Design con una home que use variantes específicas por sección y verificar que el iframe muestre la misma composición que `/home/data` en runtime.

## Estado de validación al cierre

- `PreviewHost` unit test: OK.
- `terms-modal-routing` unit test: OK.
- `v2-24-store-visual-settings` aislado con `--no-deps` contra localhost: OK.
- `v2-25-preview-parity` aislado con `--no-deps`: el caso de Step 4 quedó verde.
- El caso E2E estructural de `v2-25-preview-parity` dejó de estar bloqueado por acceso/carga, pero sigue rojo por una inconsistencia distinta del editor: varias secciones seeded siguen cayendo en `Props avanzados` de solo lectura y no exponen el formulario guiado que la smoke necesita para editar contenido visible de forma estable.
- Se confirmó que el problema residual ya no es el shell del dashboard ni la autenticación del tenant, sino la cobertura real de edición guiada de `Store Design` para las secciones disponibles en el fixture local.

## Notas de seguridad

- No se modificaron permisos, auth ni flujos sensibles.
- El cambio de API solo amplía el contrato de lectura para preservar la variante real de cada sección.
- El cambio visual en preview está encapsulado al iframe y no altera el storefront productivo.

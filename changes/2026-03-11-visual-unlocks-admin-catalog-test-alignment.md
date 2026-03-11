# Cambio: Alineación de test de visual unlocks con catálogo admin

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/addons/addons.service.spec.ts

## Resumen

Se ajustó el spec que valida la publicación de visual unlocks para consultar `listCatalogAdmin()` en lugar de `listCatalog()`.

## Por qué

Los visual unlocks quedaron definidos con `ui_scope = admin_only`, por lo que forman parte del catálogo administrativo y no del catálogo tenant. El test estaba validando contra el endpoint equivocado y generaba un falso negativo.

## Cómo probar

1. En `apps/api`, correr `npm test -- --runInBand src/addons/addons.service.spec.ts src/home/home-settings.service.spec.ts src/home/home.controller.spec.ts src/onboarding/onboarding.service.video-plan-guard.spec.ts`
2. Verificar que los 4 test suites pasen.

## Notas de seguridad

No cambia permisos ni exposición de catálogo. Solo alinea la cobertura automatizada con el comportamiento actual de `ui_scope`.
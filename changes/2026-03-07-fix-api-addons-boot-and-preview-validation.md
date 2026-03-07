# Cambio: fix de arranque del API en AddonsModule y validacion de preview

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/addons/addons.module.ts, apps/api/src/client-dashboard/client-dashboard.module.ts, apps/api/migrations/backend/20260306_add_design_config_to_client_home_settings.sql

## Resumen

Se corrigio el arranque del API despues de detectar que Railway quedaba unhealthy por una falla de inyeccion de dependencias de NestJS en `ClientDashboardGuard` cuando era usado desde `AddonsController`.

Tambien se corrigio un caracter invalido en la migracion backend `20260306_add_design_config_to_client_home_settings.sql` (`alter` habia quedado como `Íalter`), se revalido la migracion contra la base y se verifico que el endpoint raiz responda `200 OK` en `start:prod`.

## Por que

El deploy no estaba fallando por migraciones pendientes sino por runtime boot failure. `AddonsModule` necesitaba resolver `ClientDashboardGuard` dentro de su propio contexto, incluyendo `JwtService`.

La validacion de ramas de web mostro diferencias grandes entre `develop` y `feature/onboarding-preview-stable`, pero el bloque reciente corresponde al storefront tenant y al dashboard del tenant. El flujo de preview del builder usa `PreviewHost` y no depende de `/home/data`, por lo que no se identifico una necesidad visual obligatoria de propagar este paquete completo a preview.

## Como probar

1. En `apps/api`, ejecutar `npm run build`.
2. En `apps/api`, levantar con variables de entorno reales: `npm run start:prod`.
3. Verificar `curl -i http://127.0.0.1:3000/` y confirmar `HTTP/1.1 200 OK`.
4. Reaplicar de forma idempotente la migracion backend: `psql "$BACKEND_DB_URL" -v ON_ERROR_STOP=1 -f migrations/backend/20260306_add_design_config_to_client_home_settings.sql`.
5. Comparar web preview si hace falta con `git diff --stat develop origin/feature/onboarding-preview-stable -- <archivos compartidos>`.

## Notas de seguridad

- El problema era de wiring de NestJS, no de permisos ni de datos cross-tenant.
- La migracion backend se confirmo idempotente y la columna `client_home_settings.design_config` ya existia en la base.
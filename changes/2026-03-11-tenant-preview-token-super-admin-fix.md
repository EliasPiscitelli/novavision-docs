# Cambio: fix de preview token tenant para super admin

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/automatic-multiclient-onboarding

## Archivos modificados

- apps/api/src/home/home-settings.service.ts
- apps/api/src/home/home-settings.controller.ts
- apps/web/src/preview/previewUtils.js

## Resumen

Se corrigió la generación del preview token para el panel tenant-admin cuando el request entra con un `super_admin` y un tenant explícito como `farma`.

El backend ahora genera el token a partir del cliente backend ya resuelto por tenant, usando su `slug` real y evitando depender de un lookup adicional por `slug` en `nv_accounts`. Además, el scope emitido quedó alineado con el que el preview host del storefront acepta.

## Por qué

El endpoint `POST /settings/home/preview-token` podía seguir respondiendo 500 aunque el `TenantGuard` resolviera correctamente el `client_id`. El punto frágil era el segundo lookup hacia `nv_accounts`, innecesario para obtener el `slug` del preview cuando ya existe un cliente backend válido.

También había una inconsistencia de contrato: el token de tenant-admin salía con `scope: preview:tenant_admin`, pero el storefront solo aceptaba `preview:admin` o `preview:owner`.

## Qué se cambió

- `HomeSettingsService.generateTenantPreviewToken()` ahora resuelve primero `clients.id -> slug` en backend y usa ese `slug` como fuente de verdad del preview.
- El `account_id` del token usa `clients.nv_account_id` si existe, con fallback a `clientId` para no bloquear la emisión.
- El token tenant-admin ahora se emite con `scope: preview:admin`.
- La respuesta del endpoint `/settings/home/preview-token` reporta el mismo scope real.
- `previewUtils.isValidPreviewToken()` acepta también `preview:tenant_admin` para mantener compatibilidad con tokens previos todavía abiertos en sesiones activas.

## Cómo probar

En apps/api:

```bash
npm run lint
npm run typecheck
npm run build
```

En apps/web:

```bash
npm run lint
npm run typecheck
npm run build
```

Smoke manual sugerido:

```bash
curl 'https://api.novavision.lat/settings/home/preview-token' \
  -X POST \
  -H 'authorization: Bearer <jwt-super-admin>' \
  -H 'x-tenant-slug: farma'
```

Resultado esperado:

- responde `200` con `token` y `scope: preview:admin`;
- Store Design deja de mostrar error al pedir el token;
- el preview embebido o en pantalla completa abre con el slug correcto del tenant.

## Notas de seguridad

- No se relajó el tenant resolution ni se volvió a confiar en headers de cliente sin validación.
- El token sigue requiriendo `PREVIEW_TOKEN_SECRET` y expiración de 30 minutos.
- El fallback de `account_id` evita un 500 de lookup, pero no amplía permisos cross-tenant: el tenant sigue viniendo del `TenantGuard`.
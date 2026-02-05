# Cambio: aceptar clientId resuelto por TenantContextGuard

- Autor: GitHub Copilot
- Fecha: 2026-02-04
- Rama: feature/automatic-multiclient-onboarding
- Archivos modificados:
  - apps/api/src/common/utils/client-id.helper.ts

## Resumen
Se permitió que `getClientId()` use el `clientId` resuelto por `TenantContextGuard` antes de exigir el header `x-client-id`, manteniendo el requisito del header cuando no hay tenant resuelto.

## Por qué
Los endpoints públicos (`/home/data`, `/home/navigation`) estaban fallando con `x-client-id header is required` aunque el guard ya había resuelto el tenant por slug. Esto bloqueaba el storefront en dev y generaba errores en `HomeController`.

## Cómo probar
1. Levantar API en dev.
2. Hacer GET a `/home/data` con header `x-tenant-slug: test-store` (sin `x-client-id`).
3. Verificar respuesta `200` con `success: true` y ausencia del error del header.

## Notas de seguridad
- No se habilitan fallbacks desde JWT/metadata.
- Solo se acepta `clientId` resuelto por `TenantContextGuard` o el header explícito `x-client-id`.

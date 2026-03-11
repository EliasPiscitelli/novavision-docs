# Cambio: Fix envío de email en request-changes

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/onboarding/onboarding-notification.module.ts, apps/api/src/onboarding/onboarding-notification.service.ts, apps/api/src/admin/admin.service.ts

## Resumen
Se ajustó el encolado de emails para priorizar el backend cluster del cliente y usar fallback al admin si falla. Además, se propagó `backend_cluster_id` desde el flujo de request-changes y se hizo el envío no bloqueante para evitar 500 ante fallas de encolado.

## Por qué
El endpoint `/admin/clients/:id/request-changes` seguía devolviendo 500 cuando el encolado se intentaba en un proyecto sin tabla `email_jobs` o con restricciones. El fallback asegura el envío y deja trazas claras de error.

## Cómo probar
- API (terminal back): `npm run lint` y `npm run build`.
- Reintentar el POST de request-changes con el mismo payload.
- Verificar que se cree el job en `email_jobs` (admin o backend cluster) y que el endpoint responda 200.

## Notas de seguridad
No se exponen credenciales. Se mantiene el envío via `email_jobs` y no se toca RLS.

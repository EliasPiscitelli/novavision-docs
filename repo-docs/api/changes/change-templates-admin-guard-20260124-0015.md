# Cambio: guard correcto para templates admin

- Autor: agente-copilot
- Fecha: 2026-01-24
- Rama: pendiente
- Archivos: apps/api/src/templates/templates.controller.ts

## Resumen de cambios
- Los endpoints admin de templates ahora usan `SuperAdminGuard` en lugar de `BuilderSessionGuard`.
- Se permite rol `super_admin` además de `admin`.

## Motivo / por qué
Evitar 401 por token de builder inválido en endpoints de administración.

## Cómo probar
- Ejecutar PUT/POST/DELETE en /templates/admin/* con token de admin/super_admin y verificar respuesta 200.

## Notas de seguridad
- Sin exposición de credenciales ni cambios en secretos.
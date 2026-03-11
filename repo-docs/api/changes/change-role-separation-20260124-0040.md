# Cambio: separación de roles super admin vs admin cliente

- Autor: agente-copilot
- Fecha: 2026-01-24
- Rama: pendiente
- Archivos: apps/api/src/templates/templates.controller.ts, apps/api/src/palettes/palettes.controller.ts, apps/api/src/payments/admin-payments.controller.ts

## Resumen de cambios
- Consolidé el acceso a endpoints de templates/paletas admin bajo `SuperAdminGuard` sin validaciones de rol redundantes.
- Apliqué `SuperAdminGuard` a endpoints de revisión admin.
- Restringí endpoints de admin de pagos a `admin`/`super_admin` con `TenantContextGuard`.

## Motivo / por qué
Alinear el modelo de roles: super admin para administración global, admin cliente para su tienda.

## Cómo probar
- Templates/Paletas admin: validar 403 con admin cliente y 200 con super admin.
- Admin review: validar 403 sin super admin.
- Admin payments: validar acceso solo con admin cliente/super admin y client_id resuelto.

## Notas de seguridad
- Sin exposición de credenciales.
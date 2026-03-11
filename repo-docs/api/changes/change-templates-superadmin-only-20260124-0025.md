# Cambio: templates admin solo super_admin

- Autor: agente-copilot
- Fecha: 2026-01-24
- Rama: pendiente
- Archivos: apps/api/src/templates/templates.controller.ts

## Resumen de cambios
- Restringí create/update/delete de templates a rol `super_admin` únicamente.

## Motivo / por qué
Requerimiento de seguridad: solo super admin puede editar/borrar/cambiar info.

## Cómo probar
- Intentar PUT/POST/DELETE con token admin y validar 403.
- Intentar PUT/POST/DELETE con token super_admin y validar 200.

## Notas de seguridad
- Sin exposición de credenciales.
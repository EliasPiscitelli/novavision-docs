# Cambio: Onboarding como única fuente de completitud

- Autor: GitHub Copilot
- Fecha: 2026-02-05 12:00
- Rama: pendiente
- Archivos modificados:
  - src/client-dashboard/client-dashboard.service.ts
  - src/client-dashboard/client-dashboard.controller.ts
  - src/onboarding/onboarding-migration.helper.ts
  - src/admin/admin.service.ts
  - src/admin/admin.controller.ts
  - migrations/admin/20260205_drop_completion_staging_tables.sql

## Resumen

Se migró la lógica de completitud a leer y escribir exclusivamente desde `nv_onboarding.progress`, eliminando el uso de tablas `completion_*` en el backend. Se recalculan conteos y porcentaje en servicios/endpoint administrativos y se agregó una migración para eliminar las tablas staging.

## Motivo

Había inconsistencias entre `completion_*` y `nv_onboarding.progress`. Se unifica la fuente de verdad para evitar desalineaciones en checklist y estados.

## Cómo probar

- Ejecutar lint y build del API si corresponde.
- Probar endpoints:
  - GET /client-dashboard/completion-checklist
  - POST /client-dashboard/products|categories|faqs|contact-info|social-links
  - GET /admin/pending-completions
  - GET /admin/accounts/:id/completion-checklist
  - GET /admin/pending-approvals/:id

## Notas de seguridad

Sin cambios de permisos. No se expusieron secretos.

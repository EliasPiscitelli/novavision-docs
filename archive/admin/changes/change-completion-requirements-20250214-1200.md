# Cambio: Requisitos de completitud configurables

- Autor: GitHub Copilot
- Fecha: 2025-02-14 12:00
- Rama: pendiente
- Archivos:
  - apps/api/src/admin/admin.service.ts
  - apps/api/src/admin/admin.controller.ts
  - apps/api/src/client-dashboard/client-dashboard.service.ts
  - src/admin/admin.service.ts
  - src/admin/admin.controller.ts
  - src/client-dashboard/client-dashboard.service.ts
  - apps/admin/src/pages/AdminDashboard/PlansView.jsx
  - apps/admin/src/pages/ClientDetails/index.jsx
  - apps/admin/src/pages/ClientDetails/style.jsx
  - apps/admin/src/services/adminApi.js
  - apps/api/migrations/admin/20260202_add_completion_requirements.sql
  - migrations/admin/20260202_add_completion_requirements.sql
  - apps/admin/supabase/sql/10_app_settings.sql
  - apps/api/migrations/admin/run_migrations_admin.sh
  - migrations/admin/run_migrations_admin.sh

## Resumen
Se agregaron requisitos de completitud configurables con defaults globales y overrides por cliente. El backend resuelve requisitos efectivos y ajusta la lógica de aprobación, missing items y checklist. El dashboard permite editar los mínimos globales y los overrides por cliente.

## Por qué
Habilitar configuración flexible de mínimos para onboarding, con control global y excepciones específicas por cliente.

## Cómo probar
- Admin: abrir Gestión de Planes y editar requisitos globales.
- Admin: abrir detalle de cliente y configurar override; verificar que se aplique.
- API: validar endpoints de completitud en admin y client-dashboard.

## Comandos sugeridos
- API: npm run lint && npm run typecheck && npm run build
- Admin: npm run lint && npm run typecheck

## Notas de seguridad
- Sin cambios en exposición de claves.
- RLS se mantiene para `nv_account_settings` y `app_settings`.

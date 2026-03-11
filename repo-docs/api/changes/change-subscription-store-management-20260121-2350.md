# Cambio: Endpoints de gestión de suscripción y pausa de tienda

- Autor: agente-copilot
- Fecha: 2026-01-21
- Rama: pendiente
- Archivos: src/subscriptions/subscriptions.controller.ts, src/subscriptions/subscriptions.service.ts, src/auth/auth.middleware.ts, migrations/admin/20260121_nv_accounts_store_pause.sql

Resumen: Se agregaron endpoints de autogestión para ver estado de suscripción, cancelar, pausar/reanudar tienda y solicitar upgrade de plan. Además, se habilitó el bypass de auth para endpoints de builder session y se incorporaron columnas de pausa de tienda en nv_accounts.

Por qué: Permitir que los clientes administren su suscripción y el estado de su tienda desde el dashboard, con trazabilidad y control explícito.

Cómo probar / comandos ejecutados:
- Pendiente (no se ejecutaron comandos).
- Probar con builder token:
  - GET /subscriptions/manage/status
  - GET /subscriptions/manage/plans
  - POST /subscriptions/manage/pause-store
  - POST /subscriptions/manage/resume-store
  - POST /subscriptions/manage/upgrade
  - POST /subscriptions/manage/cancel

Notas de seguridad:
- Los endpoints usan BuilderSessionGuard y AllowNoTenant.
- Revisar que el builder token sea válido y que la cuenta se resuelva correctamente por account_id o client_id.

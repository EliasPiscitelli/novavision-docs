# Cambio: Habilitar RLS en subscription_notification_outbox y tenant_payment_events

- Autor: agente-copilot
- Fecha: 2026-01-21
- Rama: feature/automatic-multiclient-onboarding
- Archivos: migrations/admin/20260121_enable_rls_subscription_outbox_tenant_events.sql

Resumen: Se habilitó RLS en las tablas subscription_notification_outbox y tenant_payment_events y se agregaron políticas de acceso para service_role y super_admin.

Por qué: Evitar accesos sin control en tablas sensibles de deduplicación y outbox.

Cómo probar / comandos ejecutados:
- psql "$ADMIN_DB_URL" -f apps/api/migrations/admin/20260121_enable_rls_subscription_outbox_tenant_events.sql
- psql "$ADMIN_DB_URL" -c "SELECT relname, relrowsecurity FROM pg_class ..."

Notas de seguridad:
- Se permite acceso completo solo a service_role y super_admin.

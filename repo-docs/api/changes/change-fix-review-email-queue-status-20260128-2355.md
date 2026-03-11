# Cambio: Respuesta con estado de encolado de email en request-changes

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/admin/admin.service.ts

Resumen: Se agregó `email_queued` y `email_error` en la respuesta del endpoint de request-changes para visibilidad cuando el encolado falla.

Por qué: El endpoint podía responder success aunque el encolado de email fallara por esquema/cache. Necesitamos feedback explícito sin romper el flujo.

Migraciones / DB:
- Ejecutado en ADMIN_DB_URL y BACKEND_DB_URL: apps/api/migrations/admin/20260118_add_email_deduplication.sql
- Recarga de schema cache: `SELECT pg_notify('pgrst', 'reload schema');`

Cómo probar / comandos ejecutados:
- Sin tests automatizados.
- Ejecutar POST /admin/clients/:id/request-changes y validar que la respuesta incluya `email_queued`.

Notas de seguridad: No se exponen secretos ni se altera RLS.
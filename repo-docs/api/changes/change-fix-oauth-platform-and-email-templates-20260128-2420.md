# Cambio: OAuth platform y alineación de templates de email

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/auth/auth.service.ts, apps/api/src/onboarding/onboarding-notification.service.ts

Resumen: Se habilita el inicio de OAuth para `client_id=platform` con validación de origen por allowlist/CORS. Además, se alinean estilos de templates de onboarding (links centrados y CTA en blanco) y se asegura el almacenamiento de nonces de OAuth.

Por qué: El flujo de login desde novavision.lat fallaba con `CLIENT_NOT_FOUND`. Y los emails mostraban links desalineados y texto de botón con color incorrecto.

Migraciones / DB:
- ADMIN_DB_URL: apps/api/migrations/20251026_create_oauth_state_nonces.sql
- ADMIN_DB_URL: apps/api/migrations/admin/20260128_alter_oauth_state_nonces_client_id_text.sql
- BACKEND_DB_URL: apps/api/migrations/20251026_create_oauth_state_nonces.sql
- BACKEND_DB_URL: apps/api/migrations/admin/20260128_alter_oauth_state_nonces_client_id_text.sql

Cómo probar / comandos ejecutados:
- Ejecutar POST /auth/google/start con client_id=platform y origin https://novavision.lat.
- Verificar que devuelve URL de OAuth (HTTP 200).
- Enviar emails de onboarding y validar CTA con texto blanco y footer centrado.

Notas de seguridad: No se exponen secretos ni se altera RLS.
# Cambio: Fallback real a Admin DB en encolado de emails

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/onboarding/onboarding-notification.service.ts, apps/api/src/admin/admin.service.ts

Resumen: El fallback de encolado ahora usa el cliente del Admin DB real; además se mejora el mensaje de error cuando falla el encolado.

Por qué: El cliente inyectado apuntaba al proyecto backend (SUPABASE_URL), por lo que el fallback nunca tocaba el Admin DB. Esto dejaba el encolado sin destino cuando el backend cluster fallaba.

Cómo probar / comandos ejecutados:
- Ejecutar POST /admin/clients/:id/request-changes.
- Verificar fila en email_jobs del Admin DB si falla el backend.
- Validar respuesta con `email_queued` y `email_error` descriptivo.

Notas de seguridad: No se exponen secretos ni se altera RLS.
# Cambio: Procesar cola de email en Admin DB

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/email-jobs/email-jobs.worker.ts

Resumen: El worker ahora procesa colas de email en backend y en Admin DB. Se agrega fallback sin RPC y se usa la columna de error correcta en cada base.

Por qué: Los jobs de onboarding se encolan en Admin DB y no eran procesados porque el worker solo leía la cola del backend. Además, Admin DB no tiene `last_error` ni el RPC `claim_email_jobs`.

Cómo probar / comandos ejecutados:
- Requiere deploy del API.
- Encolar un email de ajustes y verificar que pase a `sent` en Admin DB.

Notas de seguridad: No se exponen secretos ni se altera RLS.
# Cambio: Endpoints de suscripción para dashboard de cliente (rol admin)

- Autor: agente-copilot
- Fecha: 2026-01-22
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/subscriptions/subscriptions.controller.ts, src/subscriptions/subscriptions.service.ts

Resumen: Se agregaron endpoints /subscriptions/client/manage/* protegidos por token Supabase, restringidos al rol admin del cliente. Se evita mezclar el flujo de builder session con el dashboard del cliente.

Por qué: Asegurar que la autogestión de suscripción en el storefront use autorización estándar y roles correctos.

Cómo probar / comandos ejecutados:
- GET /subscriptions/client/manage/status
- GET /subscriptions/client/manage/plans
- POST /subscriptions/client/manage/pause-store
- POST /subscriptions/client/manage/resume-store
- POST /subscriptions/client/manage/upgrade
- POST /subscriptions/client/manage/cancel

Notas de seguridad:
- Se rechaza cualquier rol distinto de admin en estos endpoints.
- Se resuelve la cuenta por client_id autenticado.
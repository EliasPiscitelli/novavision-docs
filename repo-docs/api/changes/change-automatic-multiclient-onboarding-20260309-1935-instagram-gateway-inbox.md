# Cambio: Gateway Instagram y lectura de inbox en super admin

- Autor: GitHub Copilot
- Fecha: 2026-03-09
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/outreach/outreach.service.ts, src/outreach/outreach.service.spec.ts, src/admin/admin.controller.ts, src/admin/admin.service.ts, .env.example

Resumen: Se corrigió el gateway público de Instagram para que el API valide la firma de Meta y reenvíe a n8n los eventos inbound y los eventos de delivery/read por caminos distintos, manteniendo compatibilidad con los workflows actuales. Además, se agregaron endpoints read-only para que el super admin pueda listar conversaciones y mensajes de Instagram desde el core conversacional (`conversation_inbox_view` y `message_events`).

Por qué: El webhook nuevo del API solo reenviaba al inbound y dejaba fuera el workflow de status. A la vez, el dashboard admin no tenía una fuente HTTP propia para inspeccionar conversaciones Instagram.

Cómo probar:

1. Configurar `META_APP_SECRET`, `META_VERIFY_TOKEN`, `N8N_IG_INBOUND_WEBHOOK_URL` y `N8N_IG_STATUS_WEBHOOK_URL`.
2. Verificar `GET /webhooks/instagram?hub.mode=subscribe&hub.verify_token=...&hub.challenge=...`.
3. Enviar un DM real a la cuenta conectada y confirmar que el payload se relaya a n8n inbound.
4. Confirmar que eventos `delivery/read` se relayan a n8n status.
5. Consultar `GET /admin/instagram/conversations` y `GET /admin/instagram/messages?threadId=...` autenticado como super admin.

Notas de seguridad: La firma HMAC se sigue validando en API antes del relay. Los endpoints de lectura del inbox Instagram están protegidos por `SuperAdminGuard`.
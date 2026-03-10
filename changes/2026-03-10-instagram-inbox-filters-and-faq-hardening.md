# Cambio: inbox con filtros de canal y bot de Instagram con FAQ real

- Autor: GitHub Copilot
- Fecha: 2026-03-10
- Rama: main
- Archivos:
  - n8n-workflows/wf-ig-inbound-v1.json
  - ../NovaVisionRepo/apps/admin/src/pages/AdminInbox/index.jsx
  - ../NovaVisionRepo/apps/admin/src/pages/AdminInbox/style.jsx
  - ../NovaVisionRepo/apps/admin/src/pages/AdminInstagramInbox/index.jsx
  - ../NovaVisionRepo/apps/admin/src/services/api/waInbox.js
  - ../NovaVisionRepo/apps/admin/src/components/Inbox/ConversationHeader/index.jsx
  - ../NovaVisionRepo/apps/admin/supabase/functions/admin-wa-messages/index.ts

## Resumen

Se endureció el flujo `WF-IG-INBOUND-V1` para reutilizar la base fija de preguntas y respuestas del chatbot web de NovaVision dentro del contexto del bot de Instagram. Además se reforzó el post-proceso con fallbacks específicos para:

- preguntas de precio,
- afirmaciones cortas tipo `si`, `dale`, `ok`,
- respuestas repetidas o circulares.

En paralelo, el inbox admin ahora muestra un selector visible entre WhatsApp e Instagram y el inbox principal permite filtrar el timeline del lead por canal para validar historiales multicanal sin confusión.

## Por qué

El bot de Instagram estaba contestando con vueltas genéricas y en algunos casos repetía una idea que ya había dado, especialmente cuando el lead pedía precio o respondía una afirmación breve. A la vez, el inbox principal no daba herramientas claras para separar visualmente la actividad de WhatsApp vs Instagram sobre un mismo lead.

## Cómo probar

### Admin

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npm run lint
npm run typecheck
npm run build
```

### Workflow n8n

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/novavision-docs
./scripts/n8n-workflows.sh status --workflow wf-ig-inbound-v1.json --strict
./scripts/n8n-workflows.sh sync --workflow wf-ig-inbound-v1.json
./scripts/n8n-workflows.sh status --workflow wf-ig-inbound-v1.json --strict
```

Validación funcional recomendada:

1. Abrir `/dashboard/inbox` y alternar `Ver todo`, `Solo 📱` y `Solo 📸` sobre un lead con actividad cruzada.
2. Enviar un DM de Instagram preguntando precio y confirmar que el bot responda con los planes públicos y el link de precios, sin volver al builder como única salida.
3. Responder `Si` después de que el bot ofrezca mandar el link o los planes y validar que cumpla esa promesa en vez de reiniciar la conversación.
4. Confirmar en el inbox de Instagram que la respuesta del bot quede persistida en `message_events`.

## Notas de seguridad

- No se agregaron secretos al workflow.
- La fuente FAQ copiada contiene solo contenido público de NovaVision.
- El sync de n8n debe publicarse sobre el snapshot activo y, si hiciera falta, reiniciar runtime para evitar cache de webhooks.
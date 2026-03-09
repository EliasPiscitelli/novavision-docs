# Smoke Staging — Instagram DM Inbound

- Fecha: 2026-03-08
- Objetivo: validar que Instagram DM inbound opere sobre el core canónico en Admin DB sin tocar BACKEND_DB_URL.
- Workflows objetivo:
   - `n8n-workflows/wf-ig-inbound-v1.json`
   - `n8n-workflows/wf-ig-delivery-status-v1.json`
   - `n8n-workflows/wf-ig-handoff-ops-v1.json`

## Precondiciones

1. Importar los workflows `WF-IG-INBOUND-V1`, `WF-IG-DELIVERY-STATUS-V1` y `WF-IG-HANDOFF-OPS-V1` en n8n staging.
2. Cargar credenciales y variables:
   - `META_APP_SECRET`
   - `META_GRAPH_VERSION`
   - `META_IG_ACCESS_TOKEN`
   - `META_IG_REPLY_ENDPOINT_ID`
   - `WHATSAPP_PHONE_NUMBER_ID`
   - `WHATSAPP_TOKEN`
   - `SALES_ALERT_PHONE`
   - Postgres `Admin DB`
   - OpenAI API
3. Verificar que la migración del core ya esté aplicada en Admin DB.
4. Verificar que el webhook público de Meta apunte a `https://api.novavision.lat/webhooks/instagram`.
5. Verificar que `N8N_IG_INBOUND_WEBHOOK_URL` y `N8N_IG_STATUS_WEBHOOK_URL` apunten a los paths publicados de n8n para el relay interno desde el backend.

## Casos de prueba

### 1. Inbound nuevo

Input esperado desde Meta:
- DM real desde una cuenta de prueba a la cuenta de Instagram conectada.

Validar:
1. El webhook responde 200.
2. Se crea o reutiliza `contacts`.
3. Se crea o reutiliza `contact_channel_identities` con `channel = 'INSTAGRAM'`.
4. Se crea o reutiliza `threads`.
5. Se inserta 1 fila inbound en `message_events`.
6. Se proyecta el lead en `outreach_leads` con `last_channel = 'INSTAGRAM'`.
7. Se inserta el espejo en `outreach_logs`.
8. Se envía reply por Graph API.
9. Se inserta 1 fila outbound en `message_events`.

### 2. Duplicado por provider_message_id

Reenviar el mismo payload.

Validar:
1. El webhook responde 200.
2. No se inserta un segundo `message_event` inbound con el mismo `provider_message_id`.
3. No se duplica el reply.

### 3. Handoff humano

Preparación:
1. Marcar `threads.human_handoff = true` para el thread del contacto.

Validar:
1. Entra el inbound.
2. Se persiste el inbound en `message_events`.
3. No se envía reply automático.
4. Queda trazabilidad del bloqueo operativo.

### 4. Opt-out

Preparación:
1. Marcar `contact_channel_identities.is_opted_out = true`.

Validar:
1. Entra el inbound.
2. Se persiste el inbound.
3. No se envía reply automático.
4. No se vuelve a abrir automatización del hilo.

### 5. Hot lead

Forzar un mensaje con intención clara de compra.

Validar:
1. `contacts.hot_lead = true`.
2. `contacts.ai_engagement_score` aumenta.
3. Sale la alerta interna por WhatsApp al número configurado.

### 6. Expiración de handoff

Preparación:
1. Crear o reutilizar un thread `INSTAGRAM`.
2. Marcar `threads.human_handoff = true`.
3. Setear `threads.human_handoff_expires_at = NOW() - INTERVAL '1 minute'`.
4. Insertar `handoff_events` activo con `handoff_status = 'ACTIVE'` o `REQUESTED`.

Validar:
1. El cron de `WF-IG-HANDOFF-OPS-V1` detecta el thread vencido.
2. `threads.human_handoff` vuelve a `false`.
3. `threads.status` vuelve a `BOT_ACTIVE`.
4. El evento activo previo queda marcado `EXPIRED`.
5. Se inserta un nuevo `handoff_events` de auditoría con metadata del workflow.
6. Se agrega un `message_events` de sistema para trazabilidad.

## Queries de verificación sugeridas

```sql
SELECT id, display_name, lifecycle_status, conversation_stage, hot_lead, ai_engagement_score
FROM public.contacts
ORDER BY updated_at DESC
LIMIT 10;
```

```sql
SELECT id, channel, status, human_handoff, human_handoff_reason, human_handoff_expires_at, updated_at
FROM public.threads
WHERE channel = 'INSTAGRAM'
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT thread_id, handoff_status, requested_by_actor, requested_reason, expires_at, ended_at, created_at
FROM public.handoff_events
ORDER BY created_at DESC
LIMIT 20;
```

```sql
SELECT channel, provider, direction, actor, provider_message_id, processing_status, created_at
FROM public.message_events
WHERE channel = 'INSTAGRAM'
ORDER BY created_at DESC
LIMIT 20;
```

```sql
SELECT id, name, phone, email, status, last_channel, updated_at
FROM public.outreach_leads
ORDER BY updated_at DESC
LIMIT 20;
```

```sql
SELECT lead_id, channel, action, direction, wamid, processing_status, created_at
FROM public.outreach_logs
WHERE channel = 'INSTAGRAM'
ORDER BY created_at DESC
LIMIT 20;
```

## Resultado esperado

1. El modelo primario queda en `contacts`, `contact_channel_identities`, `threads` y `message_events`.
2. `outreach_leads` y `outreach_logs` sólo actúan como read model derivado.
3. No hay cambios en BACKEND DB.
4. No hay duplicados por `provider_message_id`.
5. El reply sale sólo si no hay opt-out ni handoff activo.

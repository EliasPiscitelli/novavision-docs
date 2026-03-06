# WF-INBOUND — WhatsApp Inbound + AI Closer

## Propósito

Recibir y procesar **mensajes entrantes de WhatsApp** de leads y prospectos. Incluye un **AI Closer** (GPT-4.1-mini) que responde automáticamente con contexto de la conversación, playbook de ventas y sistema de cupones. Es el flujo más complejo — 35 nodos.

## Resultado

- Cada mensaje entrante de WhatsApp se procesa, valida (firma, dedup, opt-out) y registra.
- Si el lead no existe en la base, se **crea automáticamente** como `IN_CONVERSATION`.
- Si el lead tiene `bot_enabled = true`, la IA genera una respuesta contextual usando el playbook de ventas y la envía con un **delay humanizado** (3–12 segundos).
- Se actualiza el engagement score, el conversation stage, y se detectan hot leads.
- Si el lead es hot (score ≥ 80 o la IA lo marca), se envía una **alerta WA al equipo de ventas**.
- Si la IA ofrece un cupón, se registra en `outreach_coupon_offers`.
- Si el lead dice "stop/parar/basta", se marca como `LOST` con `opt_out`.

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Webhook POST |
| Path | `/wa-inbound` |
| Respuesta | 200 OK inmediato (antes de procesar) |

Meta envía el webhook cuando llega un mensaje de WhatsApp al número configurado.

---

## Flujo nodo por nodo

### Fase 1: Recepción y validación

#### 1. `Webhook WA Inbound` (webhook)
Recibe el POST de Meta con el payload del mensaje.

#### 2. `Respond 200 OK` (respondToWebhook)
Responde `{"status":"ok"}` inmediatamente a Meta para evitar reintentos. El procesamiento continúa en background.

#### 3. `Verify Signature` (Code)
Valida la firma HMAC-SHA256 del webhook usando `WHATSAPP_APP_SECRET`. Si no coincide → **error, se detiene**.

```javascript
const expected = 'sha256=' + crypto.createHmac('sha256', $env.WHATSAPP_APP_SECRET)
  .update(body).digest('hex');
if (sig !== expected) throw new Error('Invalid webhook signature');
```

#### 4. `Parse WA Message` (Code)
Extrae del payload de Meta:
- `wamid` — ID único del mensaje
- `from` — número de teléfono del remitente
- `msg_type` — text, button, interactive
- `text` — contenido del mensaje
- `contact_name` — nombre del perfil de WhatsApp
- `is_status_update` — si es solo una notificación de estado (delivered, read)

#### 5. `Is Status Update?` (IF)
Si es solo un status update (delivered/read) → **se ignora** (termina).
Si es un mensaje real → continúa.

### Fase 2: Deduplicación y Opt-out

#### 6. `Check WAMID Dedup` (Postgres)
```sql
SELECT EXISTS(
  SELECT 1 FROM outreach_logs WHERE wamid = '{wamid}' LIMIT 1
) as is_duplicate
```
Verifica si este `wamid` ya fue procesado (Meta puede enviar webhooks duplicados).

#### 7. `Already Processed?` (IF)
Si `is_duplicate = true` → **se ignora** (termina).

#### 8. `Check Opt-out` (Code)
Busca keywords de opt-out en el texto del mensaje:
- `stop`, `parar`, `basta`, `no más`, `cancelar suscripción`, `dejar de recibir`, `no me escriban`, `borrame`, `eliminarme`, `desuscribirme`

#### 9. `Is Opt-out?` (IF)
Si es opt-out → rama de despedida.
Si no → rama de procesamiento normal.

### Fase 2a: Rama Opt-out

#### 10. `Mark Lead LOST` (Postgres)
```sql
UPDATE outreach_leads
SET status = 'LOST', lost_at = NOW(), lost_reason = 'opt_out',
    bot_enabled = false, next_followup_at = NULL
WHERE phone = '{from}'
```

#### 11. `Send Opt-out Reply` (HTTP Request)
Envía un mensaje de despedida empático:
> "Listo, no te vamos a escribir más. Si en algún momento querés saber más sobre NovaVision, escribinos cuando quieras. ¡Éxitos! 🙌"

### Fase 3: Identificación del lead

#### 12. `Find Lead by Phone` (Postgres)
Busca el lead por número de teléfono. Trae datos completos: status, conversation_stage, ai_state, bot_enabled, hot_lead, ai_engagement_score, etc.

#### 13. `Lead Found Check` (Code)
Determina si se encontró un lead existente o es un contacto nuevo.

#### 14. `Lead Found?` (IF)
- **Sí** → `Update Lead IN_CONV`
- **No** → `Create Inbound Lead`

#### 15a. `Update Lead IN_CONV` (Postgres)
Si el lead ya existía, actualiza `status = 'IN_CONVERSATION'`, `last_channel = 'WHATSAPP'`.

#### 15b. `Create Inbound Lead` (Postgres)
Si el lead no existía, lo crea con upsert por phone:
```sql
INSERT INTO outreach_leads (name, phone, status, source, ...)
VALUES ('{contact_name}', '{from}', 'IN_CONVERSATION', 'INBOUND_WA', ...)
ON CONFLICT (phone) DO UPDATE SET status = 'IN_CONVERSATION', ...
```

### Fase 4: Logging y contexto

#### 16. `Log Inbound Message` (Postgres)
Registra el mensaje entrante en `outreach_logs` con `action = 'INBOUND_MSG'`.

#### 17. `Get Conversation History` (Postgres)
```sql
SELECT direction, message_text, created_at
FROM outreach_logs
WHERE lead_id = '{lead_id}'
ORDER BY created_at DESC
LIMIT 10
```
Trae los últimos 10 mensajes de la conversación para contexto de la IA.

### Fase 5: Configuración de IA

#### 18. `Check Config Cache` (Code)
Verifica si el playbook está cacheado en `staticData` (TTL: 12 horas). Si no, marca `needs_playbook = true`.

#### 19. `Get NV Playbook` (Postgres)
```sql
SELECT key, segment, stage, type, title, content, priority, topic
FROM nv_playbook WHERE active = true ORDER BY priority ASC
```
Carga el playbook de ventas (pricing, FAQ, objeciones, scripts por stage).

#### 20. `Fetch Coupon Config` (Postgres)
Lee configuración de cupones de `outreach_config`:
- `coupon_enabled` — si el sistema de cupones está activo
- `coupon_offer_stage` — en qué stage se puede ofrecer (ej: `closing`)
- `coupon_default_code` — código por defecto
- `coupon_offer_message` — mensaje sugerido

#### 21. `Fetch Active Coupons` (Postgres)
```sql
SELECT id, code, description, discount_type, discount_value, valid_until, max_uses, current_uses
FROM outreach_coupons WHERE active = true LIMIT 5
```

#### 22. `Build AI Prompt` (Code)
Construye el system prompt dinámico con:
- **Base prompt**: reglas del bot (no inventar precios, no USD, máx 300 chars, formato JSON de respuesta)
- **Playbook**: secciones ordenadas por prioridad
- **Cupones**: reglas de cuándo ofrecer + lista de códigos activos
- Cachea el playbook para futuras ejecuciones

#### 23. `Prepare AI Context` (Code)
Arma el contexto completo para la IA:
- Datos del lead (nombre, empresa, status, stage, engagement score)
- Historial de conversación (últimos 10 mensajes)
- Si ya se ofreció un cupón en la conversación (para no repetir)

### Fase 6: AI Closer

#### 24. `Bot Enabled?` (IF)
Si `bot_enabled = false` → **termina** (aguarda que un humano responda).

#### 25. `AI Closer Brain` (OpenAI — GPT-4.1-mini)
Llama a la API de OpenAI con:
- **System prompt**: playbook completo + reglas + cupones
- **User message**: datos del lead + historial + mensaje actual
- **Temperatura**: 0.7
- **Max tokens**: 500

Formato de respuesta esperada (JSON):
```json
{
  "reply": "texto del mensaje",
  "engagement_delta": -10 a +20,
  "conversation_stage": "INTRO|DISCOVERY|FOLLOWUP|CLOSING|DEMO_OFFERED",
  "intent": "interested|curious|objection|not_interested|spam|human_request",
  "should_notify_sales": true/false,
  "coupon_code_offered": "CÓDIGO" o null,
  "reasoning": "explicación interna"
}
```

#### 26. `Post-process AI` (Code)
Aplica **guardrails** a la respuesta de la IA:
- Trunca reply a 1000 chars
- Clampea `engagement_delta` entre -10 y +20
- Valida que `conversation_stage` sea un valor válido
- **Remueve montos en USD** (regex) → reemplaza con `[consultar precio]`
- Calcula nuevo engagement score (clamp 0–100)
- Determina si es hot lead (score ≥ 80 o `should_notify_sales`)
- Valida que el cupón ofrecido exista en la lista de cupones activos

### Fase 7: Acciones post-IA

#### 27. `Coupon Offered?` (IF)
Si la IA ofreció un cupón válido → registrar.

#### 28. `Log Coupon Offer` (Postgres)
```sql
INSERT INTO outreach_coupon_offers (lead_id, coupon_id) VALUES (...)
```

#### 29. `Update Lead Intelligence` (Postgres)
Actualiza el lead con los datos de la IA:
```sql
UPDATE outreach_leads
SET ai_engagement_score = {new_score},
    conversation_stage = '{new_stage}',
    hot_lead = {is_hot}
WHERE id = '{lead_id}'
```

#### 30. `Is Hot Lead?` (IF)
Si el lead es hot → notificar al equipo.

#### 31. `Notify Sales (Hot Lead)` (HTTP Request)
Envía un WhatsApp al número de ventas (`SALES_ALERT_PHONE`):
```
🔥 HOT LEAD
Nombre: {lead_name}
Teléfono: {from}
Score: {new_score}/100
Intent: {intent}
Último msg: {input_text}
```

### Fase 8: Respuesta

#### 32. `Humanize Delay` (Code)
Espera un delay aleatorio entre **3 y 12 segundos** para simular que un humano está escribiendo.

#### 33. `Send WA Reply` (HTTP Request)
Envía la respuesta de la IA como texto plano por WhatsApp Cloud API.

#### 34. `Log Bot Reply` (Postgres)
Registra la respuesta del bot en `outreach_logs`:
- `action = 'BOT_REPLY'`
- `direction = 'BOT'`
- `ai_state` = JSON con intent, score, stage, reasoning, coupon_offered

---

## Diagrama de flujo

```
Webhook POST /wa-inbound
    │
    ├── Respond 200 OK (inmediato)
    │
    ▼
Verify Signature ──(inválida)──> ERROR
    │
    ▼
Parse WA Message
    │
    ▼
Is Status Update? ──(sí)──> FIN
    │ (no)
    ▼
Check WAMID Dedup
    │
Already Processed? ──(sí)──> FIN
    │ (no)
    ▼
Check Opt-out
    │
Is Opt-out? ──(sí)──> Mark LOST → Send Goodbye → FIN
    │ (no)
    ▼
Find Lead by Phone
    │
Lead Found? ──(no)──> Create Inbound Lead
    │ (sí)              │
    ▼                   │
Update to IN_CONV       │
    │                   │
    └───────┬───────────┘
            │
            ▼
    Log Inbound Message
            │
            ▼
    Get Conversation History (últimos 10)
            │
            ▼
    Check Config Cache → Get Playbook (si expiró)
            │
            ├── Fetch Coupon Config
            ├── Fetch Active Coupons
            │
            ▼
    Build AI Prompt (playbook + cupones)
            │
            ▼
    Prepare AI Context (lead + historial)
            │
    Bot Enabled? ──(no)──> FIN (espera humano)
            │ (sí)
            ▼
    AI Closer Brain (GPT-4.1-mini)
            │
            ▼
    Post-process AI (guardrails)
            │
    Coupon Offered? ──(sí)──> Log Coupon Offer
            │                         │
            ▼ ◄──────────────────────-┘
    Update Lead Intelligence
            │
    Is Hot Lead? ──(sí)──> Notify Sales 🔥
            │                     │
            ▼ ◄──────────────────┘
    Humanize Delay (3-12s)
            │
            ▼
    Send WA Reply
            │
            ▼
    Log Bot Reply → FIN
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_leads` | SELECT | Buscar lead por teléfono |
| `outreach_leads` | INSERT/UPSERT | Crear lead nuevo si no existe |
| `outreach_leads` | UPDATE | Status → IN_CONVERSATION, engagement score, conversation stage, hot_lead, opt-out |
| `outreach_logs` | SELECT | Dedup por WAMID; historial de conversación |
| `outreach_logs` | INSERT | Log de mensaje entrante, respuesta del bot, AI state |
| `nv_playbook` | SELECT | Playbook de ventas para prompt de IA |
| `outreach_config` | SELECT | Configuración de cupones |
| `outreach_coupons` | SELECT | Cupones activos disponibles |
| `outreach_coupon_offers` | INSERT | Registro de cupones ofrecidos |

## APIs externas

| API | Uso |
|-----|-----|
| WhatsApp Cloud API v22.0 | Recibir webhooks, enviar respuestas de texto |
| OpenAI API (GPT-4.1-mini) | AI Closer — respuestas contextuales |

## Variables de entorno requeridas

| Variable | Descripción |
|----------|-------------|
| `WHATSAPP_APP_SECRET` | Secret de la Meta App para validar firma |
| `WHATSAPP_TOKEN` | Access token de WhatsApp Cloud API |
| `WHATSAPP_PHONE_NUMBER_ID` | ID del número para enviar mensajes |
| `SALES_ALERT_PHONE` | Número del equipo de ventas para alertas hot lead |

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |
| OpenAI API | `2T4ykWJki0wAQvUx` | OpenAI (GPT-4.1-mini) |

## Guardrails de seguridad

1. **Firma HMAC-SHA256**: Todo webhook se valida antes de procesar
2. **Deduplicación por WAMID**: Evita procesar el mismo mensaje dos veces
3. **Opt-out automático**: Respeta keywords de baja y deja de escribir
4. **Remoción de USD**: La IA no puede filtrar precios en dólares al lead
5. **Capping de scores**: Engagement delta limitado a [-10, +20], score total [0, 100]
6. **Playbook centralizado**: La IA no inventa — sigue el playbook cargado de la DB
7. **Delay humanizado**: Respuestas no son instantáneas (simula tipeo humano)

# Alcance Productivo — Flujo n8n Instagram DM

- Fecha: 2026-03-08
- Autor: GitHub Copilot
- Estado: especificación implementable
- Impacto de entorno:
  - `ADMIN_DB_URL`: sí, lectura/escritura del core conversacional.
  - `BACKEND_DB_URL`: no.

## 1. Objetivo operativo

Dejar Instagram DM funcionando en producción con el mismo motor conversacional de WhatsApp, pero sin depender de nodos o paths acoplados a WhatsApp y sin usar Facebook Trigger como base de mensajería.

## 2. Decisión técnica cerrada

El canal Instagram se implementa con:

1. `Webhook` genérico de n8n para inbound desde Meta.
2. Verificación HMAC/firmas antes de cualquier lógica.
3. Normalización a payload canónico compartido con WhatsApp.
4. Llamadas salientes vía `HTTP Request` contra Graph API.
5. Persistencia exclusiva en Admin DB usando el core canónico.

No se usa `Facebook Trigger` para DMs porque la cobertura documentada de n8n para Instagram no deja eso suficientemente cerrado a nivel productivo.

## 3. Workflows productivos que hay que tener

### 3.0 Verificación pública Meta

La verificación pública `GET hub.challenge` no la resuelve n8n en producción. La resuelve el backend en `GET /webhooks/instagram`, que ya tiene acceso seguro a `META_VERIFY_TOKEN`.

Secuencia exacta:

1. Meta llama `GET https://api.novavision.lat/webhooks/instagram`
2. Backend valida `hub.verify_token`
3. Backend responde `hub.challenge`

`WF-IG-WEBHOOK-VERIFY-V1` queda sólo como workflow legado de diagnóstico y no debe publicarse como endpoint productivo.

### 3.1 WF-IG-INBOUND-PROD

Responsable de recibir, validar, normalizar, persistir y responder DMs.

Secuencia exacta:

1. `Webhook IG Inbound`
2. `Respond 200 OK`
3. `Verify Meta Signature`
4. `Parse Instagram Event`
5. `Filter Unsupported Events`
6. `Normalize Canonical Payload`
7. `Resolve Contact + Thread` usando `public.resolve_conversation_entities(...)`
8. `Append Inbound Event` usando `public.append_message_event(...)`
9. `Check Compliance Gates`
10. `Load Conversation Context`
11. `Build AI Prompt`
12. `AI Closer Brain`
13. `Post-process AI`
14. `Apply Guardrails`
15. `Send IG Reply`
16. `Append Outbound Event`
17. `Sync Legacy Read Model` solo si el inbox actual todavía depende de espejo legacy
18. `Hot Lead Alert`

### 3.2 WF-META-DELIVERY-STATUS-PROD

Responsable de delivery/read receipts y errores del provider.

Secuencia exacta:

1. `Webhook Meta Status`
2. `Respond 200 OK`
3. `Verify Meta Signature`
4. `Parse Status Event`
5. `Resolve Message Event`
6. `Insert delivery_events`
7. `Update message_events.provider_status`
8. `If failed => create compliance_events/manual review`

### 3.3 WF-HANDOFF-OPS-PROD

Responsable de lock humano y expiración controlada.

Secuencia exacta:

1. `Cron every 5 min`
2. `Select expired handoff events`
3. `Release thread lock`
4. `Insert handoff_events status RELEASED/EXPIRED`
5. `Optional notify operator`

## 4. Payload canónico obligatorio

Todo canal debe converger a este shape antes de consultar AI o DB:

```json
{
  "channel": "INSTAGRAM",
  "provider": "META",
  "channel_account_id": "<instagram-business-account-id>",
  "external_user_id": "<instagram-user-id>",
  "external_display_name": "<nombre visible>",
  "provider_message_id": "<mid>",
  "provider_parent_message_id": null,
  "direction": "INBOUND",
  "event_type": "MESSAGE",
  "message_type": "TEXT",
  "text_body": "mensaje del lead",
  "normalized_text": "mensaje normalizado",
  "media_url": null,
  "received_at": "ISO8601",
  "raw_payload": {}
}
```

## 5. Guardrails productivos obligatorios

### 5.1 Antes del AI

1. Rechazar evento sin firma válida.
2. Rechazar duplicados por `dedup_key` o `provider_message_id`.
3. Frenar respuesta si `thread.human_handoff = true` y no expiró.
4. Frenar respuesta si `identity.is_opted_out = true`.

### 5.2 Después del AI y antes del send

1. No responder si se supera la ventana de 24 horas.
2. No enviar reply vacío.
3. Limitar longitud máxima por canal.
4. Quitar claims no permitidos, precios inventados o menciones no aprobadas.
5. No insistir si el hilo ya tiene 3 outbound seguidos sin inbound posterior.

### 5.3 Operación y observabilidad

1. Cada fallo de send genera `delivery_events` o `compliance_events`.
2. Cada pedido de humano genera `handoff_events` y lock real del thread.
3. Todo bloqueo de ventana o opt-out genera `compliance_events`.

## 6. Variables y credenciales que deben existir antes de implementar

En n8n o vault externo, sin hardcode en JSON:

1. `META_APP_SECRET`
2. `META_VERIFY_TOKEN`
3. `META_GRAPH_VERSION`
4. `META_IG_ACCESS_TOKEN`
5. `META_IG_BUSINESS_ACCOUNT_ID`
6. credencial Postgres Admin DB
7. credencial OpenAI

## 7. Impacto real por entorno

### `ADMIN_DB_URL`

Se usa para:

1. resolver contacto/identidad/thread
2. persistir `message_events`
3. persistir `handoff_events`
4. persistir `delivery_events`
5. persistir `compliance_events`
6. leer `nv_playbook` y configuración operativa

### `BACKEND_DB_URL`

No entra en el flujo Instagram DM productivo. No se consulta ni se modifica.

## 8. Alcance que sí entra en producción inicial

1. inbound DM
2. respuesta automática
3. hot lead alert
4. handoff humano con lock
5. opt-out
6. métricas mínimas
7. delivery/read tracking
8. compatibilidad transitoria con inbox legacy

## 9. Alcance que se excluye del arranque solo por control de blast radius

1. outbound frío por Instagram
2. campañas promocionales fuera de ventana
3. multiagente
4. automation de media enriquecida más allá de texto/quick replies del primer corte

Esto no queda “para futuro” como diseño faltante: simplemente no forma parte del primer release productivo porque no es requisito para dejar el canal operativo y controlado.

## 10. Qué falta cerrar para arrancar implementación hoy

1. crear el webhook path definitivo en n8n
2. definir el Graph endpoint exacto de reply según el setup Meta definitivo del proyecto
3. crear la credencial segura de Meta en n8n
4. ejecutar la migración del core en Admin DB
5. sembrar `nv_playbook` si sigue vacío
6. decidir si el hot lead alert sigue saliendo por WhatsApp o cambia a email/slack interno
7. definir el espejo mínimo hacia `outreach_leads/outreach_logs` mientras viva el inbox legacy

## 11. Criterio de aceptación para arrancar build

1. Existe un workflow de inbound productivo definido nodo por nodo.
2. Existe un schema canónico que soporta IG y WA.
3. Está cerrado que solo impacta `ADMIN_DB_URL`.
4. Está cerrado que `BACKEND_DB_URL` queda afuera.
5. Ya no hay ninguna dependencia técnica bloqueante de `phone` ni `wamid` como identidad central.
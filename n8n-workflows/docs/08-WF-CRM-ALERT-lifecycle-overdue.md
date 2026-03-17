# WF-CRM-ALERT-V2 — Lifecycle Transitions + Overdue Tasks

**Version:** v2.001
**Trigger:** Webhook POST `/webhook/crm-alert`
**Origen:** NestJS `crm-health.cron.ts` (fire-and-forget)
**Estado:** Pendiente importar en n8n (reemplaza WF-CRM-ALERT-V1)
**Archivo:** `wf-crm-alert-v2.json`

---

## Flujo

```
Webhook POST /crm-alert
        │
    Switch: ¿alert_type === "overdue_tasks"?
        │                    │
      [true]              [false]
        │                    │
  Formatear           Formatear
  Overdue             Lifecycle
        │                    │
  WA: Overdue         WA: Lifecycle ──→ Log Activity
        │                    │
        └──── NoOp (fin) ───┘
```

## Payloads recibidos

### 1. Lifecycle transition (cada 6 horas, si hay transiciones)

```json
{
  "account_id": "uuid",
  "email": "cliente@ejemplo.com",
  "slug": "mi-tienda",
  "from_stage": "active",
  "to_stage": "at_risk",
  "health_score": 35,
  "reason": "Health score bajo (35) — posible riesgo de churn"
}
```

### 2. Overdue tasks (cada 30 min, si hay tareas vencidas)

```json
{
  "alert_type": "overdue_tasks",
  "count": 3,
  "tasks": [
    {
      "id": "uuid",
      "account_id": "uuid",
      "title": "Revision cuenta en riesgo",
      "due_date": "2026-03-14T00:00:00Z",
      "priority": "high"
    }
  ]
}
```

## Nodos

| Nodo | Tipo | Funcion |
|------|------|---------|
| Webhook CRM Alert | Webhook | Recibe POST del backend |
| Switch: Tipo de Alerta | If | Bifurca por `alert_type === 'overdue_tasks'` |
| Formatear Overdue | Code (JS) | Genera mensaje WA con lista de tareas vencidas (max 15, con prioridad emoji) |
| Formatear Lifecycle | Code (JS) | Genera mensaje WA con datos de cuenta, transicion, health score, motivo |
| WA: Overdue Tasks | HTTP Request | Envia WhatsApp a `SALES_ALERT_PHONE` |
| WA: Lifecycle Alert | HTTP Request | Envia WhatsApp a `SALES_ALERT_PHONE` |
| Log Activity (Lifecycle) | Postgres | INSERT en `crm_activity_log` con `actor_type='n8n'` |
| NoOp (fin) | NoOp | Cierre del workflow |

## Variables de entorno requeridas

| Variable | Descripcion |
|----------|-------------|
| `SALES_ALERT_PHONE` | Telefono del equipo de ventas (formato internacional) |
| `WHATSAPP_PHONE_NUMBER_ID` | ID del numero WhatsApp Business |
| `WHATSAPP_TOKEN` | Token de la API de WhatsApp |

## Credenciales n8n

| Credencial | ID | Tipo | Uso |
|-----------|-----|------|-----|
| Admin DB | `ADMIN_DB_CREDENTIAL_ID` | Postgres | Log de actividad (reemplazar con ID real) |

## Cambios vs V1

| Aspecto | V1 | V2 |
|---------|-----|-----|
| Payloads soportados | Solo lifecycle | Lifecycle + overdue tasks |
| Routing | Directo (un solo flujo) | Switch node bifurca por tipo |
| Activity log | No registraba | INSERT en `crm_activity_log` para lifecycle |
| Formato overdue | No existia | Lista con emojis de prioridad, max 15 items |

## Setup

1. Importar `wf-crm-alert-v2.json` en n8n
2. Configurar credencial Postgres (Admin DB) con el ID real
3. Configurar `SALES_ALERT_PHONE` en variables de entorno de n8n
4. Activar el workflow
5. Desactivar WF-CRM-ALERT-V1 (id: `AyXOMejRIf5cTrp4`)
6. Verificar con un POST manual al webhook

# WF-WEEKLY-REPORT — Reporte Semanal por WhatsApp

## Propósito

Generar y enviar un reporte semanal completo del pipeline de outreach por WhatsApp todos los lunes. Consolida métricas del funnel, actividad, mensajería, conversión y leads calientes en un mensaje formateado con emojis listo para lectura rápida.

## Resultado

- Snapshot completo del funnel (leads por estado)
- Actividad de los últimos 7 días (nuevos, contactados, ganados)
- Métricas de mensajería (enviados, recibidos, errores)
- KPIs de conversión (tasa de conversión, engagement, score AI promedio)
- Top 10 leads calientes con score y último contacto
- Todo formateado y enviado como mensaje de WhatsApp al número de alertas

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Schedule (Cron) |
| Expresión | `0 12 * * 1` |
| Hora | **12:00 UTC** (09:00 ART) |
| Frecuencia | Lunes |

Se envía los lunes a la mañana (hora Argentina) para arrancar la semana con visibilidad del pipeline.

---

## Flujo nodo por nodo

### 1. `Lunes 12:00 UTC` (scheduleTrigger)
Dispara el workflow cada lunes a las 12:00 UTC.

### 2. Ejecución en paralelo — 5 queries simultáneas:

#### 2a. `Funnel Snapshot` (Postgres)
```sql
SELECT
  count(*) FILTER (WHERE status = 'NEW') as new,
  count(*) FILTER (WHERE status = 'CONTACTED') as contacted,
  count(*) FILTER (WHERE status = 'IN_CONVERSATION') as in_conversation,
  count(*) FILTER (WHERE status = 'QUALIFIED') as qualified,
  count(*) FILTER (WHERE status = 'ONBOARDING') as onboarding,
  count(*) FILTER (WHERE status = 'WON') as won,
  count(*) FILTER (WHERE status = 'COLD') as cold,
  count(*) FILTER (WHERE status = 'LOST') as lost,
  count(*) FILTER (WHERE status = 'DISCARDED') as discarded,
  count(*) as total
FROM outreach_leads;
```
Cuenta total de leads por cada estado del pipeline.

#### 2b. `Actividad Semanal` (Postgres)
```sql
SELECT
  count(*) FILTER (WHERE created_at > now() - interval '7 days') as new_this_week,
  count(*) FILTER (WHERE status = 'CONTACTED' AND updated_at > now() - interval '7 days') as contacted_this_week,
  count(*) FILTER (WHERE status = 'WON' AND won_at > now() - interval '7 days') as won_this_week,
  count(*) FILTER (WHERE status = 'COLD' AND updated_at > now() - interval '7 days') as cold_this_week,
  count(*) FILTER (WHERE status = 'LOST' AND updated_at > now() - interval '7 days') as lost_this_week
FROM outreach_leads;
```
Métricas de movimiento en la última semana.

#### 2c. `Metricas Mensajeria` (Postgres)
```sql
SELECT
  count(*) FILTER (WHERE direction = 'outbound' AND created_at > now() - interval '7 days') as sent_this_week,
  count(*) FILTER (WHERE direction = 'inbound' AND created_at > now() - interval '7 days') as received_this_week,
  count(*) FILTER (WHERE status = 'error' AND created_at > now() - interval '7 days') as errors_this_week
FROM outreach_messages;
```
Volumen de mensajes enviados, recibidos y con error.

#### 2d. `KPIs Conversion` (Postgres)
```sql
SELECT
  ROUND(
    count(*) FILTER (WHERE status = 'WON')::numeric /
    NULLIF(count(*) FILTER (WHERE status NOT IN ('NEW', 'DISCARDED')), 0) * 100,
    1
  ) as conversion_rate,
  ROUND(
    count(*) FILTER (WHERE status IN ('IN_CONVERSATION', 'QUALIFIED', 'ONBOARDING', 'WON'))::numeric /
    NULLIF(count(*) FILTER (WHERE status NOT IN ('NEW', 'DISCARDED')), 0) * 100,
    1
  ) as engagement_rate,
  ROUND(AVG(ai_score) FILTER (WHERE ai_score IS NOT NULL), 1) as avg_ai_score
FROM outreach_leads;
```
Tasas de conversión y engagement calculadas, más score AI promedio.

#### 2e. `Top Hot Leads` (Postgres)
```sql
SELECT
  first_name, last_name, company_name, status, ai_score,
  to_char(updated_at, 'DD/MM HH24:MI') as last_contact
FROM outreach_leads
WHERE status IN ('IN_CONVERSATION', 'QUALIFIED', 'ONBOARDING')
  AND ai_score IS NOT NULL
ORDER BY ai_score DESC
LIMIT 10;
```
Top 10 leads más calientes por score AI.

### 3. `Merge All Data` (merge)
Combina los resultados de las 5 queries en un solo objeto de datos.

### 4. `Formatear Reporte` (code / set)
Construye un mensaje de WhatsApp con formato legible y emojis:

```
📊 *REPORTE SEMANAL OUTREACH*
📅 Semana del DD/MM al DD/MM

━━━━━━━━━━━━━━━━━━
📈 *FUNNEL ACTUAL*
━━━━━━━━━━━━━━━━━━
🆕 Nuevos: X
📤 Contactados: X
💬 En conversación: X
⭐ Calificados: X
🚀 Onboarding: X
🏆 Ganados: X
❄️ Fríos: X
❌ Perdidos: X
🗑️ Descartados: X
📊 Total: X

━━━━━━━━━━━━━━━━━━
📅 *ACTIVIDAD SEMANAL*
━━━━━━━━━━━━━━━━━━
🆕 Nuevos esta semana: X
📤 Contactados: X
🏆 Ganados: X
❄️ Enfriados: X
❌ Perdidos: X

━━━━━━━━━━━━━━━━━━
📨 *MENSAJERÍA*
━━━━━━━━━━━━━━━━━━
📤 Enviados: X
📥 Recibidos: X
⚠️ Errores: X

━━━━━━━━━━━━━━━━━━
📊 *KPIs*
━━━━━━━━━━━━━━━━━━
🎯 Conversión: X%
💡 Engagement: X%
🤖 Score AI promedio: X

━━━━━━━━━━━━━━━━━━
🔥 *TOP LEADS CALIENTES*
━━━━━━━━━━━━━━━━━━
1. Nombre (Empresa) - Score: X - Último contacto: DD/MM
...
```

### 5. `Enviar por WhatsApp` (httpRequest)
Envía el mensaje formateado via la API de WhatsApp Cloud:
```
POST https://graph.facebook.com/v22.0/{PHONE_NUMBER_ID}/messages
{
  "messaging_product": "whatsapp",
  "to": "{SALES_ALERT_PHONE}",
  "type": "text",
  "text": { "body": "{reporte_formateado}" }
}
```

---

## Diagrama de flujo

```
Lunes 12:00 UTC
    │
    ├─────────────┬──────────────┬───────────────┬──────────────┐
    ▼             ▼              ▼               ▼              ▼
  Funnel      Actividad     Métricas         KPIs          Top Hot
  Snapshot    Semanal       Mensajería       Conversión    Leads
    │             │              │               │              │
    └─────────────┴──────────────┼───────────────┴──────────────┘
                                 │
                                 ▼
                         Merge All Data
                                 │
                                 ▼
                       Formatear Reporte
                                 │
                                 ▼
                    Enviar por WhatsApp → FIN
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_leads` | SELECT | Funnel, actividad, KPIs, top leads |
| `outreach_messages` | SELECT | Métricas de mensajería |

## Variables de entorno requeridas

| Variable | Descripción |
|----------|-------------|
| `SALES_ALERT_PHONE` | Número de WhatsApp destino del reporte (formato E.164) |
| `WHATSAPP_PHONE_NUMBER_ID` | ID del número de WA (`859363390593864`) |
| `WHATSAPP_TOKEN` | Token de acceso a la Graph API |

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |

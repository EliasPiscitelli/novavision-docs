# WF-RETENTION-V1 — Retención Post-Cancel

**Version:** v1.001
**Trigger:** Cron diario 09:00 UTC
**Origen:** Autónomo (consulta Admin DB directamente)
**Estado:** PENDIENTE de importar en n8n
**n8n ID:** `retention_v1_001`
**Archivo:** `wf-retention-v1.json`

---

## Propósito

Enviar emails de retención escalonados a cuentas que cancelaron su suscripción en los últimos 30 días. El objetivo es recuperar tenants ofreciendo descuentos progresivos según los días desde la cancelación.

## Cadencia de emails

| Días desde cancel | Template | Cupón | Mensaje clave |
|-------------------|----------|-------|---------------|
| 0-1 | `day1_empathy` | Ninguno | "Lamentamos verte partir" — empático, pide feedback |
| 2-4 | `day3_value` | Ninguno | "Tu tienda aún está ahí" — recuerda productos/visitas |
| 5-10 | `day7_winback` | COMEBACK30 (30%) | "Volvé con descuento" — primer incentivo |
| 11-17 | `day7_winback` | COMEBACK50 (50%) | "Volvé con descuento" — incentivo mayor |
| 18-30 | `day14_final` | FREERETURN (100%) | "Última oportunidad" — urgencia, warning de purga |

## Flujo

```
Cron 09:00 UTC
      │
  Fetch Churned ──── (query Admin DB: nv_accounts + lifecycle_events)
      │
  ¿Hay cuentas?
      │         │
   [true]    [false]
      │         │
  Loop ───→ NoOp (sin cuentas) ──→ Fin
      │
  Clasificar Etapa ──── (Code: mapea days_since_cancel → template + coupon)
      │
  HMAC Sign Request ── (Code: firma HMAC-SHA256 con N8N_INTERNAL_SECRET)
      │
  API: Send Email ──── (HTTP POST /internal/retention/email/send)
      │
  Log Result ──── (Code: evalúa success/failure)
      │
      ├── Log CRM Activity ── (Postgres: INSERT crm_activity_log)
      │         │
      └── WA: Notificar ──── (HTTP: WhatsApp al equipo de ventas)
                │
          Loop (siguiente cuenta)
```

## Nodos

| Nodo | Tipo | Función |
|------|------|---------|
| Cron Diario 09:00 UTC | Schedule Trigger | Ejecuta una vez al día |
| Fetch Churned Accounts | Postgres | Query cuentas canceladas sin email de retención enviado |
| ¿Hay cuentas? | If | Verifica que haya resultados |
| Loop Accounts | Split In Batches | Procesa 1 por 1 |
| Clasificar Etapa | Code (JS) | Mapea `days_since_cancel` → template + cupón |
| HMAC Sign Request | Code (JS) | Firma la request con HMAC-SHA256 |
| API: Send Retention Email | HTTP Request | POST al endpoint HMAC-protected del API |
| Log Result | Code (JS) | Evalúa si el email se envió o falló |
| Log CRM Activity | Postgres | INSERT en `crm_activity_log` con actor_type='n8n' |
| WA: Notificar Equipo | HTTP Request | WhatsApp al `SALES_ALERT_PHONE` |

## Query principal

```sql
SELECT
  a.id AS account_id,
  a.email, a.store_name, a.slug, a.plan_key, a.country,
  a.subscription_status,
  le.created_at AS cancelled_at,
  le.new_value->>'reason' AS cancellation_reason,
  EXTRACT(DAY FROM NOW() - le.created_at)::int AS days_since_cancel
FROM nv_accounts a
JOIN lifecycle_events le ON le.account_id = a.id
  AND le.event_type = 'subscription_cancel_requested'
WHERE a.subscription_status IN ('canceled', 'suspended')
  AND le.created_at >= NOW() - INTERVAL '30 days'
  AND a.id NOT IN (
    SELECT DISTINCT (event_data->>'account_id')::uuid
    FROM crm_activity_log
    WHERE event_type = 'retention_email_sent'
      AND created_at >= le.created_at
  )
ORDER BY le.created_at ASC
LIMIT 20
```

**Anti-duplicación**: La subconsulta en `NOT IN` excluye cuentas que ya recibieron un email de retención después de su cancelación actual. Esto permite re-engagement si una cuenta cancela, reactiva y vuelve a cancelar.

## API Endpoint consumido

```
POST /internal/retention/email/send
```

**Auth**: HMAC-SHA256 con headers:
- `X-NV-Timestamp`: unix millis
- `X-NV-Signature`: `sha256=<hex>`
- `X-Correlation-Id`: UUID v4

**Body**:
```json
{
  "account_id": "uuid",
  "template": "day1_empathy | day3_value | day7_winback | day14_final",
  "coupon_code": "COMEBACK30 | COMEBACK50 | FREERETURN | null"
}
```

**Response**: `{ "ok": true, "email_job_id": "uuid" }`

## Variables de entorno requeridas

| Variable | Descripción | Dónde |
|----------|-------------|-------|
| `N8N_INTERNAL_SECRET` | Clave compartida para HMAC signing | n8n + Railway API |
| `API_URL` | URL base del API (default: `https://novavision-production.up.railway.app`) | n8n |
| `SALES_ALERT_PHONE` | Teléfono equipo ventas (formato internacional) | n8n |
| `WHATSAPP_PHONE_NUMBER_ID` | ID número WhatsApp Business | n8n |
| `WHATSAPP_TOKEN` | Token API WhatsApp | n8n |

## Credenciales n8n

| Credencial | ID | Tipo | Uso |
|-----------|-----|------|-----|
| Admin DB | `dMEly2JOB3W86tWW` | Postgres | Fetch cuentas + Log CRM |

## Setup

1. Importar `wf-retention-v1.json` en n8n (https://n8n-production-c19d.up.railway.app)
2. Verificar credencial Postgres (Admin DB) — ID: `dMEly2JOB3W86tWW`
3. Verificar que `N8N_INTERNAL_SECRET` coincida entre n8n y Railway API
4. Test manual: ejecutar workflow una vez y verificar logs
5. Activar el workflow
6. Verificar que no hay cuentas canceladas en el rango (si QA solo tiene cuentas activas, no habrá resultados — OK)

## Consideraciones

- **Rate limiting**: Procesa 1 cuenta a la vez (batchSize=1) para no sobrecargar el API
- **continueOnFail**: Habilitado en nodos de envío — si un email falla, sigue con el siguiente
- **Idempotencia**: El INSERT en `crm_activity_log` previene que la misma cuenta reciba el mismo tipo de email dos veces
- **Cupones**: Los cupones COMEBACK30/50 y FREERETURN tienen `max_uses_per_account=1`, así que si el tenant ya usó uno, el API lo rechaza silenciosamente

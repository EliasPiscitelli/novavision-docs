# WF-SEED-V2 — Seed Diario (Primer Contacto)

## Propósito

Enviar el **primer mensaje de contacto** a todos los leads nuevos (`status = 'NEW'`) mediante dos canales: **WhatsApp** (plantilla aprobada por Meta) y **Email** (Gmail HTML). Se ejecuta automáticamente una vez al día.

## Resultado

Cada lead con status `NEW` recibe un mensaje personalizado.  
- Si tiene teléfono válido → recibe **WhatsApp** con la plantilla `novavision_primer_contacto_qr_v1`.  
- Si tiene email válido → recibe **Email HTML** con propuesta de valor.  
- Si tiene ambos → recibe **ambos** canales.  
- El lead pasa de `NEW` → `CONTACTED` y se agenda su primer follow-up a **3 días**.

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Schedule (Cron) |
| Hora | **10:00 UTC** (7:00 ART) |
| Frecuencia | Diario |

---

## Flujo nodo por nodo

### 1. `Cron Seed Diario` (scheduleTrigger)
Dispara el workflow todos los días a las 10:00 UTC.

### 2. `Fetch NEW Leads` (Postgres)
```sql
SELECT id, name, email, phone, source, category, last_channel, web, builder_url, store_slug
FROM outreach_leads
WHERE status = 'NEW'
ORDER BY created_at ASC
LIMIT 50
```
Trae hasta 50 leads nuevos, priorizando los más antiguos. Si no hay leads, el workflow termina sin acción.

### 3. `Loop Items` (splitInBatches)
Itera uno por uno (`batchSize: 1`) para procesar cada lead individualmente y evitar que un error en un lead frene a los demás.

### 4. `Validate Contact` (Code — JavaScript)
Limpia y valida los datos del lead. Genera las 6 variables de contexto para la plantilla de WhatsApp:

| Variable | Lógica |
|----------|--------|
| `first_name` | Primer nombre del lead, fallback `"hola"` |
| `sender_name` | Env `OUTREACH_SENDER_NAME`, fallback `"equipo NovaVision"` |
| `business_name` | `lead.name` o `lead.category`, fallback `"tu negocio"` |
| `source_channel` | `lead.source`, fallback `"base comercial"` |
| `current_sales_channel` | `lead.last_channel`, fallback `"WhatsApp"` |
| `cta_link` | `builder_url` > `web` > `slug.novavision.app` > env `OUTREACH_CTA_LINK` > URL de onboarding |

También valida:
- **Teléfono**: regex `^\+?[1-9]\d{7,14}$` → `has_valid_phone`
- **Email**: regex estándar → `has_valid_email`

### 5. `Has Valid Phone?` (IF)
Si `has_valid_phone === true` → rama **WhatsApp**.  
Si no → salta WhatsApp.

### 6. `Send WA Seed` (HTTP Request → WhatsApp Cloud API)
Envía la plantilla aprobada por Meta con 6 parámetros de body:

```json
{
  "messaging_product": "whatsapp",
  "to": "{phone_clean}",
  "type": "template",
  "template": {
    "name": "novavision_primer_contacto_qr_v1",
    "language": { "code": "es_AR" },
    "components": [{
      "type": "body",
      "parameters": [
        { "type": "text", "text": "{first_name}" },
        { "type": "text", "text": "{sender_name}" },
        { "type": "text", "text": "{business_name}" },
        { "type": "text", "text": "{source_channel}" },
        { "type": "text", "text": "{current_sales_channel}" },
        { "type": "text", "text": "{cta_link}" }
      ]
    }]
  }
}
```

**On Error:** continúa por rama de error (no detiene el loop).

### 7a. `Update Lead WA OK` (Postgres — rama éxito)
```sql
UPDATE outreach_leads
SET status = 'CONTACTED',
    last_channel = 'WHATSAPP',
    last_contacted_at = NOW(),
    attempt_count = 1,
    next_followup_at = NOW() + INTERVAL '3 days',
    updated_at = NOW()
WHERE id = '{lead_id}'
```

### 7b. `Log WA Success` (Postgres)
Registra en `outreach_logs`:
- `channel = 'WHATSAPP'`
- `action = 'SEED_SENT'`
- `direction = 'OUTBOUND'`
- `wamid` = ID del mensaje de WhatsApp (para trazabilidad)

### 7c. `Log WA Failure` (Postgres — rama error)
Si el envío falla, registra `action = 'SEED_FAILED'` con `processing_status = 'error'`.

### 8. `Has Valid Email?` (IF)
Si `has_valid_email === true` → rama **Email**.  
Si no → salta Email.

### 9. `Send Email Seed` (Gmail)
Envía un email HTML profesional desde `hola@novavision.com.ar` con:
- Asunto: "Tu tienda online en minutos — NovaVision"
- Body HTML: saludo personalizado + 4 bullets de propuesta de valor + CTA "Crear mi tienda gratis →"
- Pie: opt-out suave ("Si no te interesa, no te vamos a molestar más")

**Credencial:** Gmail OAuth2 (`id: yWIgAG6zWIonR54e`)

### 10a. `Update Lead Email OK` (Postgres)
Igual que 7a pero con `last_channel = 'EMAIL'`.

### 10b. `Log Email Success` (Postgres)
Registra `channel = 'EMAIL'`, `action = 'SEED_SENT'`.

### 10c. `Log Email Failure` (Postgres)
Registra error si falla el envío de email.

### 11. Retorno a `Loop Items`
Todas las ramas (éxito y error) retornan al loop para procesar el siguiente lead.

---

## Diagrama de flujo

```
Cron 10:00 UTC
    │
    ▼
Fetch NEW Leads (max 50)
    │
    ▼
┌── Loop Items ◄─────────────────────────────────────────┐
│       │                                                 │
│       ▼                                                 │
│   Validate Contact                                      │
│       │                                                 │
│   ┌───┴───┐                                             │
│   ▼       ▼                                             │
│ Phone?  Email?                                          │
│   │       │                                             │
│   ▼       ▼                                             │
│ Send WA  Send Email                                     │
│ ┌──┴──┐  ┌──┴──┐                                       │
│ ▼     ▼  ▼     ▼                                       │
│ OK  Fail OK  Fail                                      │
│ │     │  │     │                                       │
│ Update │  Update │                                      │
│ + Log  │  + Log  │                                      │
│ │     │  │     │                                       │
│ └──┬──┘  └──┬──┘                                       │
│    └────┬───┘                                           │
│         └───────────────────────────────────────────────┘
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_leads` | SELECT | Trae leads con `status = 'NEW'` |
| `outreach_leads` | UPDATE | Marca `CONTACTED`, agenda followup |
| `outreach_logs` | INSERT | Registra éxito o error de cada envío |

## APIs externas

| API | Uso |
|-----|-----|
| WhatsApp Cloud API v22.0 | Envío de plantilla aprobada |
| Gmail API | Envío de email HTML |

## Variables de entorno requeridas

| Variable | Descripción |
|----------|-------------|
| `WHATSAPP_PHONE_NUMBER_ID` | ID del número de teléfono en Meta |
| `WHATSAPP_TOKEN` | Access token de WhatsApp Cloud API |
| `OUTREACH_SENDER_NAME` | Nombre del remitente (ej: "Eli de NovaVision") |
| `OUTREACH_CTA_LINK` | URL de CTA por defecto |

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |
| Gmail — NovaVision | `yWIgAG6zWIonR54e` | Gmail OAuth2 |

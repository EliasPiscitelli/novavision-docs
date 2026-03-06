# WF-FOLLOWUP-V2 — Seguimientos Automáticos

## Propósito

Enviar **mensajes de follow-up** a leads que ya fueron contactados (`status = 'CONTACTED'`) pero no respondieron, siguiendo una cadencia creciente. Si se agota el máximo de intentos, el lead se marca como `COLD` automáticamente.

## Resultado

- Leads con follow-up pendiente reciben un nuevo mensaje de WhatsApp con plantilla progresiva.
- La cadencia de seguimiento es **creciente**: 3 → 5 → 7 días entre intentos.
- Máximo de intentos: **4**. Superado ese límite → lead pasa a `COLD` con razón `max_followups_exhausted`.
- Cada intento queda registrado en `outreach_logs`.

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Schedule (Cron) |
| Horas | **11:00 UTC** y **17:00 UTC** (8:00 y 14:00 ART) |
| Frecuencia | 2 veces por día |

Se ejecuta dos veces al día para maximizar la ventana de contacto.

---

## Flujo nodo por nodo

### 1. `Cron Follow-ups` (scheduleTrigger)
Dispara el workflow a las 11:00 y 17:00 UTC cada día.

### 2. `Fetch FU Leads` (Postgres)
```sql
SELECT id, name, email, phone, company, status, attempt_count, 
       last_channel, conversation_stage, source
FROM outreach_leads
WHERE status = 'CONTACTED'
  AND next_followup_at <= NOW()
ORDER BY next_followup_at ASC
LIMIT 100
```
Trae hasta 100 leads cuyo follow-up ya venció (`next_followup_at <= NOW()`).

### 3. `Loop Items` (splitInBatches)
Procesa uno por uno (`batchSize: 1`).

### 4. `Compute FU Number` (Code — JavaScript)
Calcula la lógica del follow-up:

| Variable | Lógica |
|----------|--------|
| `fu_number` | `attempt_count + 1` (número de este intento) |
| `is_max_reached` | `true` si `fu_number >= 4` |
| `next_delay_days` | Cadencia progresiva: `[3, 5, 7]` días |
| `template_name` | `novavision_followup{N}` donde N = min(fu_number - 1, 3) |

**Ejemplo de cadencia:**
| Intento | Días hasta siguiente | Template |
|---------|---------------------|----------|
| 1 (seed) | 3 | — (seed tiene su propio template) |
| 2 (FU1) | 5 | `novavision_followup1` |
| 3 (FU2) | 7 | `novavision_followup2` |
| 4 (FU3) | — (marca COLD) | `novavision_followup3` |

### 5. `Max Reached?` (IF)
- **Sí (is_max_reached = true)** → rama de finalización (Mark COLD)
- **No** → rama de envío (Send WA Follow-up)

---

### Rama: Máximo alcanzado (COLD)

### 6a. `Mark COLD` (Postgres)
```sql
UPDATE outreach_leads
SET status = 'COLD',
    next_followup_at = NULL,
    lost_reason = 'max_followups_exhausted',
    updated_at = NOW()
WHERE id = '{lead_id}'
```
El lead deja de recibir seguimientos automáticos.

### 6b. `Log Marked COLD` (Postgres)
Registra en `outreach_logs`:
- `channel = 'SYSTEM'`
- `action = 'MARKED_COLD'`
- `message_text = 'Max follow-ups reached, marked COLD'`

→ Retorna al **Loop Items** para continuar con el siguiente lead.

---

### Rama: Enviar follow-up

### 7. `Send WA Follow-up` (HTTP Request → WhatsApp Cloud API)
```json
{
  "messaging_product": "whatsapp",
  "to": "{phone}",
  "type": "template",
  "template": {
    "name": "{template_name}",
    "language": { "code": "es" },
    "components": [{
      "type": "body",
      "parameters": [
        { "type": "text", "text": "{name || 'emprendedor/a'}" }
      ]
    }]
  }
}
```
Usa un template progresivo con 1 parámetro (nombre del lead).

**On Error:** continúa por rama de error.

### 8a. `Update Lead FU OK` (Postgres — rama éxito)
```sql
UPDATE outreach_leads
SET attempt_count = {fu_number},
    last_channel = 'WHATSAPP',
    last_contacted_at = NOW(),
    next_followup_at = NOW() + ({next_delay_days} * INTERVAL '1 day'),
    updated_at = NOW()
WHERE id = '{lead_id}'
```
Agenda el siguiente follow-up con la cadencia calculada.

### 8b. `Log FU Success` (Postgres)
Registra `action = 'FU_SENT'` con el número de intento.

### 8c. `Log FU Failure` (Postgres — rama error)
Registra `action = 'FU_FAILED'` con `processing_status = 'error'`.

### 9. Retorno a Loop Items
Todas las ramas retornan al loop.

---

## Diagrama de flujo

```
Cron 11:00 / 17:00 UTC
    │
    ▼
Fetch FU Leads (CONTACTED + followup vencido, max 100)
    │
    ▼
┌── Loop Items ◄────────────────────────────────┐
│       │                                        │
│       ▼                                        │
│   Compute FU Number                            │
│       │                                        │
│   Max Reached?                                 │
│   ┌───┴───┐                                    │
│   ▼       ▼                                    │
│  YES      NO                                   │
│   │       │                                    │
│ Mark     Send WA                               │
│ COLD     Follow-up                             │
│   │      ┌──┴──┐                               │
│ Log      ▼     ▼                               │
│ COLD    OK    Fail                             │
│   │     │      │                               │
│   │   Update  Log                              │
│   │   + Log   Fail                             │
│   │     │      │                               │
│   └──┬──┴──────┘                               │
│      └─────────────────────────────────────────┘
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_leads` | SELECT | Leads `CONTACTED` con `next_followup_at <= NOW()` |
| `outreach_leads` | UPDATE | Incrementa `attempt_count`, agenda siguiente followup o marca `COLD` |
| `outreach_logs` | INSERT | Registra cada acción (FU_SENT, FU_FAILED, MARKED_COLD) |

## APIs externas

| API | Uso |
|-----|-----|
| WhatsApp Cloud API v22.0 | Envío de plantillas de follow-up |

## Variables de entorno requeridas

| Variable | Descripción |
|----------|-------------|
| `WHATSAPP_PHONE_NUMBER_ID` | ID del número de teléfono en Meta |
| `WHATSAPP_TOKEN` | Access token de WhatsApp Cloud API |

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |

# WF-HYGIENE — Mantenimiento Diario de la Base de Leads

## Propósito

Limpiar automáticamente la base de leads cada día a las 6:00 UTC. Ejecuta tres operaciones de mantenimiento en paralelo y registra los resultados.

## Resultado

- Leads inactivos con follow-ups agotados → marcados `COLD` automáticamente
- Leads con teléfonos inválidos → marcados `DISCARDED`
- Leads duplicados por teléfono → solo se mantiene el más antiguo, los demás se descartan
- Todo queda registrado en `outreach_logs` con contadores de cada operación

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Schedule (Cron) |
| Expresión | `0 6 * * *` |
| Hora | **06:00 UTC** (03:00 ART) |
| Frecuencia | Diario |

Se ejecuta en horario de baja actividad para minimizar impacto.

---

## Flujo nodo por nodo

### 1. `Cron 06:00 UTC` (scheduleTrigger)
Dispara el workflow una vez por día a las 6:00 UTC.

### 2. `Leer Config` (Postgres)
```sql
SELECT value::int as days FROM outreach_config WHERE key = 'cold_after_days'
```
Lee la cantidad de días de inactividad configurada antes de marcar un lead como COLD. Default: **14 días**.

### 3. Ejecución en paralelo — 3 operaciones simultáneas:

#### 3a. `Auto-COLD Inactivos` (Postgres)
```sql
WITH cold_candidates AS (
  UPDATE outreach_leads
  SET status = 'COLD',
      lost_reason = 'Auto-COLD: sin actividad > {days} dias',
      updated_at = now()
  WHERE status IN ('CONTACTED', 'IN_CONVERSATION')
    AND updated_at < now() - ({days} || ' days')::interval
    AND followup_count >= (SELECT COALESCE(value::int, 4) FROM outreach_config WHERE key = 'max_followup_attempts')
  RETURNING id
)
SELECT count(*) as cold_count FROM cold_candidates;
```
**Criterio**: lead debe estar `CONTACTED` o `IN_CONVERSATION`, sin actividad por más de N días, Y haber agotado el máximo de follow-ups configurado.

#### 3b. `Descartar Phones Inválidos` (Postgres)
```sql
WITH discarded AS (
  UPDATE outreach_leads
  SET status = 'DISCARDED',
      lost_reason = 'Auto-DISCARD: telefono invalido',
      updated_at = now()
  WHERE status = 'NEW'
    AND (phone IS NULL OR phone = '' OR length(phone) < 8
         OR phone !~ '^\+?[1-9][0-9]{7,14}$')
  RETURNING id
)
SELECT count(*) as discard_count FROM discarded;
```
**Criterio**: leads `NEW` con teléfono nulo, vacío, muy corto, o que no matchea el regex E.164.

#### 3c. `De-duplicar por Phone` (Postgres)
```sql
WITH dedup AS (
  SELECT id, ROW_NUMBER() OVER (PARTITION BY phone ORDER BY created_at ASC) as rn
  FROM outreach_leads
  WHERE phone IS NOT NULL AND phone != ''
    AND status NOT IN ('DISCARDED', 'WON')
),
duplicates AS (
  UPDATE outreach_leads
  SET status = 'DISCARDED',
      lost_reason = 'Auto-DISCARD: duplicado por phone',
      updated_at = now()
  WHERE id IN (SELECT id FROM dedup WHERE rn > 1)
  RETURNING id
)
SELECT count(*) as dedup_count FROM duplicates;
```
**Criterio**: si hay múltiples leads con el mismo teléfono, solo se mantiene el más antiguo (`created_at ASC`). Los duplicados se descartan. No toca leads `DISCARDED` ni `WON`.

### 4. `Resumen Post-Limpieza` (Postgres)
Después de las 3 operaciones, genera un snapshot del estado actual de la base:
```sql
SELECT
  count(*) FILTER (WHERE status = 'NEW') as total_new,
  count(*) FILTER (WHERE status = 'CONTACTED') as total_contacted,
  count(*) FILTER (WHERE status = 'IN_CONVERSATION') as total_in_conv,
  count(*) FILTER (WHERE status = 'QUALIFIED') as total_qualified,
  count(*) FILTER (WHERE status = 'ONBOARDING') as total_onboarding,
  count(*) FILTER (WHERE status = 'WON') as total_won,
  count(*) FILTER (WHERE status = 'COLD') as total_cold,
  count(*) FILTER (WHERE status = 'LOST') as total_lost,
  count(*) FILTER (WHERE status = 'DISCARDED') as total_discarded,
  count(*) FROM outreach_leads as grand_total;
```

### 5. `Log Ejecucion` (Postgres)
Registra los resultados de la limpieza en `outreach_logs` como evento de sistema:
```json
{
  "type": "hygiene_run",
  "cold_count": N,
  "discard_count": N,
  "dedup_count": N,
  "timestamp": "..."
}
```

---

## Diagrama de flujo

```
Cron 06:00 UTC
    │
    ▼
Leer Config (cold_after_days)
    │
    ├──────────────┬──────────────┐
    ▼              ▼              ▼
Auto-COLD      Descartar     De-duplicar
Inactivos      Phones        por Phone
    │          Inválidos         │
    │              │              │
    └──────────────┼──────────────┘
                   │
                   ▼
           Resumen Post-Limpieza
                   │
                   ▼
            Log Ejecución → FIN
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_config` | SELECT | Lee `cold_after_days` y `max_followup_attempts` |
| `outreach_leads` | UPDATE | Marca COLD, DISCARDED según criterios |
| `outreach_leads` | SELECT | Snapshot del funnel |
| `outreach_logs` | INSERT | Log del run de higiene con contadores |

## Variables de entorno

Ninguna específica — solo la credencial de base de datos.

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |

## Configuración en `outreach_config`

| Key | Default | Descripción |
|-----|---------|-------------|
| `cold_after_days` | 14 | Días sin actividad para auto-COLD |
| `max_followup_attempts` | 4 | Follow-ups requeridos antes de marcar COLD |

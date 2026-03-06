# WF-ONBOARDING-BRIDGE — Sincronización Lead ↔ Onboarding

## Propósito

Detectar automáticamente cuando un lead del pipeline de outreach inicia el proceso de onboarding en NovaVision. Sincroniza el estado del lead con los datos reales del onboarding (cuenta, tienda, etc.) para cerrar el ciclo de ventas.

## Resultado

- Leads cuyo email coincide con un onboarding activo → status `ONBOARDING`
- Leads cuyo email coincide con una cuenta activa → status `WON` (cerrado ganado)
- Se enriquece el lead con `onboarding_id`, `account_id`, `store_slug`, `builder_url`
- Se registran timestamps de calificación y cierre (`qualified_at`, `won_at`)
- Log de sincronización con resumen de matches encontrados

---

## Trigger

| Campo | Valor |
|-------|-------|
| Tipo | Schedule (Cron) |
| Expresión | `0 */2 * * *` |
| Frecuencia | **Cada 2 horas** |

Se ejecuta frecuentemente para capturar rápidamente cuando un lead comienza su onboarding.

---

## Flujo nodo por nodo

### 1. `Cada 2h` (scheduleTrigger)
Dispara el workflow cada 2 horas.

### 2. `Buscar Matches Lead<>Onboarding` (Postgres)
```sql
SELECT
  l.id as lead_id,
  l.email as lead_email,
  l.status as lead_status,
  o.id as onboarding_id,
  o.status as onboarding_status,
  a.id as account_id,
  a.status as account_status,
  a.store_slug,
  a.builder_url
FROM outreach_leads l
INNER JOIN nv_onboarding o ON lower(l.email) = lower(o.email)
LEFT JOIN nv_accounts a ON o.account_id = a.id
WHERE l.status IN ('CONTACTED', 'IN_CONVERSATION', 'QUALIFIED')
  AND l.onboarding_id IS NULL;
```
**Lógica**: Hace un JOIN por email (case-insensitive) entre `outreach_leads` y `nv_onboarding`. Solo busca leads que:
- Estén en estados activos del pipeline (CONTACTED, IN_CONVERSATION, QUALIFIED)
- No tengan ya un `onboarding_id` asignado (evita re-procesar)

También trae datos de `nv_accounts` si el onboarding ya tiene cuenta creada.

### 3. `Hay matches?` (if)
Evalúa si la query devolvió resultados. Si no hay matches, el workflow termina silenciosamente.

### 4. `Actualizar Lead con Onboarding` (Postgres)
Para cada match encontrado, actualiza el lead con los datos del onboarding:
```sql
UPDATE outreach_leads
SET
  status = CASE
    WHEN '{account_status}' = 'active' THEN 'WON'
    WHEN '{onboarding_status}' = 'in_progress' THEN 'ONBOARDING'
    ELSE 'QUALIFIED'
  END,
  onboarding_id = '{onboarding_id}',
  account_id = CASE WHEN '{account_id}' != '' THEN '{account_id}'::uuid ELSE NULL END,
  store_slug = NULLIF('{store_slug}', ''),
  builder_url = NULLIF('{builder_url}', ''),
  won_at = CASE WHEN '{account_status}' = 'active' THEN now() ELSE NULL END,
  qualified_at = CASE WHEN qualified_at IS NULL THEN now() ELSE qualified_at END,
  updated_at = now()
WHERE id = '{lead_id}';
```

**Lógica de estados**:

| Condición | Nuevo Status | Significado |
|-----------|-------------|-------------|
| `account_status = 'active'` | **WON** | Ya tiene tienda activa → venta cerrada |
| `onboarding_status = 'in_progress'` | **ONBOARDING** | Está en proceso de setup |
| Otro | **QUALIFIED** | Tiene onboarding pero aún no arrancó |

### 5. `Log Sync` (Postgres)
Registra cada sincronización en `outreach_logs`:
```json
{
  "type": "onboarding_bridge_sync",
  "lead_id": "uuid",
  "lead_email": "...",
  "old_status": "CONTACTED",
  "new_status": "ONBOARDING",
  "onboarding_id": "uuid",
  "account_id": "uuid"
}
```

### 6. `Resumen` (noOp)
Nodo terminal que consolida el output del workflow para visualización en n8n.

---

## Diagrama de flujo

```
Cada 2h (Cron)
    │
    ▼
Buscar Matches Lead ↔ Onboarding
(JOIN outreach_leads ←→ nv_onboarding ←→ nv_accounts)
    │
    ▼
¿Hay matches?
    │
    ├── NO → FIN (silencioso)
    │
    └── SÍ ──→ Actualizar Lead con Onboarding
                    │
                    ├── account active  → WON
                    ├── onb in_progress → ONBOARDING
                    └── otro            → QUALIFIED
                    │
                    ▼
              Log Sync → Resumen → FIN
```

---

## Tablas involucradas

| Tabla | Operación | Detalle |
|-------|-----------|---------|
| `outreach_leads` | SELECT + UPDATE | Busca matches y actualiza status/datos |
| `nv_onboarding` | SELECT (JOIN) | Fuente de datos de onboarding |
| `nv_accounts` | SELECT (LEFT JOIN) | Datos de cuenta activa |
| `outreach_logs` | INSERT | Log de cada sincronización |

## Campos enriquecidos en el lead

| Campo | Origen | Descripción |
|-------|--------|-------------|
| `onboarding_id` | `nv_onboarding.id` | ID del proceso de onboarding |
| `account_id` | `nv_accounts.id` | ID de la cuenta creada |
| `store_slug` | `nv_accounts.store_slug` | Slug de la tienda |
| `builder_url` | `nv_accounts.builder_url` | URL del builder de la tienda |
| `won_at` | `now()` | Timestamp de cierre (solo si WON) |
| `qualified_at` | `now()` | Timestamp de calificación |

## Credenciales n8n

| Credencial | ID | Servicio |
|------------|-----|---------|
| Admin DB (Postgres) | `dMEly2JOB3W86tWW` | Supabase Admin DB |

# Cambio: Fixes P0 - Provisioning Jobs Dedupe, Status Live, Saga/Resume

- **Autor:** agente-copilot  
- **Fecha:** 2025-07-15  
- **Rama:** (pendiente creación)  
- **Relacionado:** BUG-001 (rollback parcial), BUG-002 (status 'live'), BUG-NEW (no dedupe)

---

## Archivos Modificados/Creados

### Migraciones SQL (nuevas)
- `apps/api/migrations/admin/ADMIN_056_add_live_to_account_status_check.sql`
- `apps/api/migrations/admin/ADMIN_057_provisioning_jobs_dedupe_and_compat.sql`
- `apps/api/migrations/admin/ADMIN_058_create_provisioning_job_steps.sql`

### Código Backend (modificados)
- `apps/api/src/onboarding/onboarding.service.ts` (~línea 1071)
- `apps/api/src/worker/provisioning-worker.service.ts` (interface Job, helper `_runStep`, normalización jobType)

### Scripts de Validación (nuevo)
- `apps/api/scripts/validate-schema.js` (utilidad para validar bugs contra DB en vivo)

---

## Resumen de Cambios

### 1. ADMIN_056: Add 'live' to Account Status Check
**Problema:** El código intentaba setear `status='live'` pero el constraint `nv_accounts_status_check` no lo permitía.

**Solución:** 
```sql
ALTER TABLE nv_accounts DROP CONSTRAINT IF EXISTS nv_accounts_status_check;
ALTER TABLE nv_accounts ADD CONSTRAINT nv_accounts_status_check 
  CHECK (status IN ('pending','trial','trialing','active','past_due',
                    'paused','suspended','cancelled','closed','archived',
                    'provisioning','failed','live','sandbox'));
```

### 2. ADMIN_057: Provisioning Jobs Dedupe + Type/job_type Compat
**Problema:** 
- No había constraint UNIQUE, permitiendo jobs duplicados para el mismo (account_id, job_type)
- Drift entre código (usa `type`) y DB (columna `job_type`)

**Solución:**
- Columna `dedupe_key` con UNIQUE INDEX
- Trigger `sync_provisioning_jobs_fields` para mantener `type` y `job_type` sincronizados
- RPC `enqueue_provisioning_job` con `ON CONFLICT DO UPDATE` para idempotencia

### 3. ADMIN_058: Provisioning Job Steps (Saga/Resume)
**Problema:** Si el worker fallaba a mitad del proceso, no había forma de resumir desde donde quedó.

**Solución:**
- Tabla `provisioning_job_steps` con (job_id, step_name) UNIQUE
- Helper functions: `is_job_step_done()`, `complete_job_step()`
- Columnas: status (pending/running/done/failed), attempt, step_data, error_info

### 4. Webhook Patch (onboarding.service.ts)
**Problema:** El webhook swallowea errores al insertar jobs.

**Solución:**
```typescript
// ANTES: raw .insert() sin manejo de errores
// AHORA: usa RPC con error propagation
const { error: enqueueError } = await adminClient.rpc('enqueue_provisioning_job', {
  p_account_id: accountId,
  p_job_type: 'provision_client',
  p_payload: { account_id: accountId, trigger: 'subscription_active_webhook' },
});
if (enqueueError) {
  this.logger.error(`[provisionClientIfNeeded] enqueue_provisioning_job failed: ${enqueueError.message}`);
  throw new InternalServerErrorException('Failed to enqueue provisioning job');
}
```

### 5. Worker Helper (`_runStep`) + Interface Update
**Cambios:**
- Interface `Job` ahora incluye `job_type?: string`
- Normalización: `const jobType = job.job_type ?? job.type;`
- Helper `_runStep<T>()` (~100 líneas) para ejecutar steps con:
  - Verificación de step ya completado (resume)
  - Marcado de step como running/done/failed
  - Persistencia de resultados en `step_data`
  - Tracking de intentos

---

## Por qué

1. **Dedupe es P0:** Sin él, cualquier retry del webhook crea jobs duplicados que se ejecutan en paralelo, causando race conditions y datos corruptos.

2. **Status 'live' es drift crítico:** El código espera poder setear este estado pero la DB lo rechaza, causando fallos silenciosos.

3. **Saga/Resume:** Provisioning tiene ~10 pasos (crear client, migrar catálogo, configurar pagos, etc.). Sin step ledger, un fallo a mitad deja datos parciales sin forma de continuar.

---

## Cómo Probar

### Pre-requisitos
```bash
# Variables de entorno necesarias
export SUPABASE_ADMIN_URL="https://erbfzlsznqsmwmjugspo.supabase.co"
export SUPABASE_ADMIN_SERVICE_ROLE_KEY="<key>"
```

### 1. Validar bugs (antes de migrar)
```bash
cd apps/api
node scripts/validate-schema.js
# Debería mostrar: status='live' REJECTED, duplicate insert succeeded
```

### 2. Aplicar migraciones (en orden)
```sql
-- Primero en Supabase SQL Editor (Admin DB)
-- 1. ADMIN_056
-- 2. ADMIN_057
-- 3. ADMIN_058
```

### 3. Desplegar API
```bash
# Después de ADMIN_057, desplegar para que webhook use RPC
npm run build && npm run start:prod
```

### 4. Verificar dedupe funciona
```bash
# Llamar webhook dos veces con mismo account_id
# Segunda llamada debe devolver el job existente, no crear duplicado
```

### 5. Verificar status='live' funciona
```sql
UPDATE nv_accounts SET status = 'live' WHERE id = '<test_account>';
-- Ahora debe funcionar sin error
```

---

## Orden de Rollout (recomendado)

1. **ADMIN_056** (status live) - Sin dependencias
2. **ADMIN_057** (dedupe + RPC) - Sin dependencias
3. **Deploy API** con webhook patch - Requiere ADMIN_057
4. **ADMIN_058** (steps ledger) - Sin dependencias
5. **Deploy Worker** con `_runStep` habilitado - Requiere ADMIN_058

---

## Notas de Seguridad

- Las migraciones usan `IF NOT EXISTS` / `DROP IF EXISTS` para idempotencia
- El RPC `enqueue_provisioning_job` usa `SECURITY DEFINER` - solo callable desde backend con service_role
- El trigger solo se ejecuta en INSERT, no expone datos

---

## Riesgos y Rollback

### Riesgos
- **ADMIN_056:** Ninguno, solo agrega valores al constraint
- **ADMIN_057:** El trigger `sync_provisioning_jobs_fields` podría tener overhead mínimo en INSERTs
- **ADMIN_058:** Nueva tabla, sin impacto en existente

### Rollback
```sql
-- ADMIN_058: DROP TABLE provisioning_job_steps CASCADE;
-- ADMIN_057: DROP TRIGGER/FUNCTION/INDEX (ver script)
-- ADMIN_056: Revertir constraint (remover 'live')
```

---

## Comandos Ejecutados

```bash
# Validación de errores TypeScript
npm run typecheck  # ✅ 0 errors

# Validación de lint
npm run lint  # ✅ 0 errors (714 warnings preexistentes)
```

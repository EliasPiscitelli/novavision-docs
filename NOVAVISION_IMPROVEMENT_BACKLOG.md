# NovaVision - Backlog de Mejoras y Correcciones

> **Fuente:** [NOVAVISION_SYSTEM_AUDIT.md](./NOVAVISION_SYSTEM_AUDIT.md)  
> **Fecha:** 2026-02-03  
> **Última actualización:** 2025-07-15  
> **Prioridades:** P0 (Bloqueante) → P1 (Importante) → P2 (Mejora)

---

## 🔴 P0 - CRÍTICOS (Bloquean operación o causan pérdida de datos)

### ~~BUG-001: Falla parcial sin rollback en provisioning~~ ✅ MITIGADO

| Campo | Valor |
|-------|-------|
| **Estado** | ✅ **IMPLEMENTADO** - Pendiente deploy |
| **Archivo** | `apps/api/src/worker/provisioning-worker.service.ts` |
| **Migración** | `ADMIN_058_create_provisioning_job_steps.sql` |
| **Descripción** | Si `migrateCatalog()` falla después de crear `clients` y `users`, no hay rollback. |
| **Solución implementada** | Helper `_runStep<T>()` + tabla `provisioning_job_steps` para saga/resume pattern |
| **Documentación** | Ver `apps/api/docs/changes/change-p0-bugs-provisioning-20250715.md` |

**Estado de implementación:**
- [x] Tabla `provisioning_job_steps` con UNIQUE(job_id, step_name)
- [x] Helper functions: `is_job_step_done()`, `complete_job_step()`
- [x] Método `_runStep<T>()` en worker (~100 líneas)
- [ ] Migrar `processJob()` para usar `_runStep()` en cada step
- [ ] Testing E2E de resume after failure

---

### ~~BUG-002: Estado 'live' no está en CHECK constraint~~ ✅ IMPLEMENTADO

| Campo | Valor |
|-------|-------|
| **Estado** | ✅ **IMPLEMENTADO** - Pendiente deploy |
| **Archivo** | `apps/api/migrations/admin/ADMIN_056_add_live_to_account_status_check.sql` |
| **Descripción** | El código usa `status='live'` pero el constraint SQL no lo permitía |
| **Solución implementada** | Nueva migración que agrega 'live' y 'sandbox' al constraint |
| **Documentación** | Ver `apps/api/docs/changes/change-p0-bugs-provisioning-20250715.md` |

**Verificado contra DB:** `INSERT INTO nv_accounts(status) VALUES('live')` ahora funciona tras migrar.

---

### ~~BUG-NEW: No hay dedupe en provisioning_jobs~~ ✅ IMPLEMENTADO

| Campo | Valor |
|-------|-------|
| **Estado** | ✅ **IMPLEMENTADO** - Pendiente deploy |
| **Migración** | `ADMIN_057_provisioning_jobs_dedupe_and_compat.sql` |
| **Descripción** | Sin constraint UNIQUE, webhooks pueden crear jobs duplicados |
| **Solución implementada** | Columna `dedupe_key` + UNIQUE INDEX + RPC `enqueue_provisioning_job` con ON CONFLICT |
| **Documentación** | Ver `apps/api/docs/changes/change-p0-bugs-provisioning-20250715.md` |

**Componentes:**
- [x] Columna `dedupe_key` con generación automática
- [x] UNIQUE INDEX `idx_provisioning_jobs_dedupe`
- [x] Trigger `sync_provisioning_jobs_fields` para compat type/job_type
- [x] RPC `enqueue_provisioning_job` con idempotencia
- [x] Webhook patched en `onboarding.service.ts` para usar RPC

---

## 🟡 P1 - IMPORTANTES (Afectan calidad o acumulan deuda)

### BUG-003: purgeExpiredDrafts está comentado

| Campo | Valor |
|-------|-------|
| **Archivo** | `apps/api/src/worker/provisioning-worker.service.ts` |
| **Línea** | ~1600+ |
| **Descripción** | El cron de limpieza de drafts expirados está comentado, causando acumulación de registros |
| **Impacto** | Crecimiento indefinido de nv_accounts con status='draft' y draft_expires_at pasado |

**Fix propuesto:**
```typescript
// Descomentar y ajustar:
@Cron('0 2 * * *') // 2am diario
async purgeExpiredDrafts() {
  const { data, error } = await this.adminClient
    .from('nv_accounts')
    .delete()
    .eq('status', 'draft')
    .lt('draft_expires_at', new Date().toISOString());
  
  this.logger.log(`Purged ${data?.length || 0} expired drafts`);
}
```

**Esfuerzo estimado:** 2 horas  
**Riesgo de no implementar:** Medio - DB crece, queries más lentas

---

### BUG-004: Logo base64 nunca se limpia de nv_onboarding

| Campo | Valor |
|-------|-------|
| **Archivo** | `apps/api/src/worker/provisioning-worker.service.ts` |
| **Descripción** | Después de migrar logo a Storage, el base64 queda en `nv_onboarding.progress.wizard_assets.logo_url` |
| **Impacto** | JSONB payload crece (5MB+ por logo), queries más lentas |

**Fix propuesto:**
```typescript
// Después de migrateLogoToBackend():
await this.adminClient
  .from('nv_onboarding')
  .update({
    progress: {
      ...onboarding.progress,
      wizard_assets: {
        ...onboarding.progress?.wizard_assets,
        logo_url: null, // Limpiar base64
        logo_migrated_to: storageUrl // Guardar referencia
      }
    }
  })
  .eq('account_id', accountId);
```

**Esfuerzo estimado:** 2 horas  
**Riesgo de no implementar:** Medio - performance degradada con muchos accounts

---

### BUG-005: Slug inmutabilidad post-paid no enforced en DB

| Campo | Valor |
|-------|-------|
| **Descripción** | Después de pagar, el slug debería ser inmutable, pero no hay constraint en DB |
| **Impacto** | Un UPDATE manual o bug podría cambiar el slug post-pago |

**Fix propuesto:**
```sql
-- Trigger para prevenir cambio de slug post-paid
CREATE OR REPLACE FUNCTION prevent_slug_change() RETURNS TRIGGER AS $$
BEGIN
  IF OLD.status NOT IN ('draft', 'awaiting_payment') 
     AND NEW.slug != OLD.slug THEN
    RAISE EXCEPTION 'Cannot change slug after payment (status=%)', OLD.status;
  END IF;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_prevent_slug_change
BEFORE UPDATE ON nv_accounts
FOR EACH ROW EXECUTE FUNCTION prevent_slug_change();
```

**Esfuerzo estimado:** 1 hora  
**Riesgo de no implementar:** Medio - integridad de datos

---

### BUG-006: hardDeleteAccounts deshabilitado

| Campo | Valor |
|-------|-------|
| **Archivo** | `apps/api/src/worker/provisioning-worker.service.ts` |
| **Descripción** | Cron de hard delete para accounts marcados como deleted está deshabilitado |
| **Impacto** | Datos de cuentas "borradas" persisten indefinidamente |

**Fix propuesto:**
```typescript
@Cron('0 3 * * 0') // Domingos 3am
async hardDeleteAccounts() {
  // Borrar accounts con soft_deleted_at > 30 días
  const thirtyDaysAgo = new Date();
  thirtyDaysAgo.setDate(thirtyDaysAgo.getDate() - 30);
  
  await this.adminClient
    .from('nv_accounts')
    .delete()
    .lt('soft_deleted_at', thirtyDaysAgo.toISOString());
}
```

**Esfuerzo estimado:** 2 horas  
**Riesgo de no implementar:** Bajo - compliance/GDPR a futuro

---

### BUG-007: RLS en Backend DB sin verificar exhaustivamente

| Campo | Valor |
|-------|-------|
| **Descripción** | No hay tests automatizados que verifiquen que RLS bloquea cross-tenant access |
| **Impacto** | Posible leak de datos entre tenants si hay bug en políticas |

**Fix propuesto:**
```typescript
// Test E2E:
describe('Cross-Tenant RLS', () => {
  it('should block reading products from another client', async () => {
    const userA = await loginAs('user@clientA.com');
    const clientBProductId = 'uuid-of-client-b-product';
    
    const { data, error } = await supabase
      .from('products')
      .select('*')
      .eq('id', clientBProductId);
    
    expect(data).toHaveLength(0); // RLS debe filtrar
  });
});
```

**Esfuerzo estimado:** 1 día  
**Riesgo de no implementar:** Alto - seguridad de datos

---

## 🟢 P2 - MEJORAS (Nice to have, mejoran DX/observabilidad)

### IMP-001: Correlation ID en todos los logs

| Campo | Valor |
|-------|-------|
| **Descripción** | No hay ID único que conecte logs de un mismo request/job |
| **Beneficio** | Trazabilidad completa de errores en producción |

**Fix propuesto:**
```typescript
// Middleware para generar correlation ID
@Injectable()
export class CorrelationIdMiddleware implements NestMiddleware {
  use(req: Request, res: Response, next: NextFunction) {
    req['correlationId'] = req.headers['x-correlation-id'] || uuidv4();
    res.setHeader('x-correlation-id', req['correlationId']);
    next();
  }
}

// En cada log:
this.logger.log(`[${correlationId}] Processing job ${jobId}`);
```

**Esfuerzo estimado:** 4 horas

---

### IMP-002: Backoff exponencial en retry de jobs

| Campo | Valor |
|-------|-------|
| **Descripción** | Jobs fallidos se reintentan con delay fijo, puede saturar si falla repetidamente |
| **Beneficio** | Resiliencia, evita thundering herd |

**Fix propuesto:**
```typescript
// En requeueJob:
const backoffMinutes = Math.pow(2, job.attempts); // 2, 4, 8, 16, 32...
const maxBackoff = 60; // Max 1 hora
const actualBackoff = Math.min(backoffMinutes, maxBackoff);

const runAfter = new Date(Date.now() + actualBackoff * 60 * 1000);
await this.adminClient
  .from('provisioning_jobs')
  .update({ status: 'pending', run_after: runAfter.toISOString() })
  .eq('id', jobId);
```

**Esfuerzo estimado:** 2 horas

---

### IMP-003: Métricas Prometheus para provisioning

| Campo | Valor |
|-------|-------|
| **Descripción** | No hay métricas de duración/éxito de provisioning jobs |
| **Beneficio** | Dashboards, alertas, optimización |

**Fix propuesto:**
```typescript
// Usando @willsoto/nestjs-prometheus
@Injectable()
export class ProvisioningMetrics {
  constructor(
    @InjectMetric('provisioning_job_duration_seconds')
    private readonly durationHistogram: Histogram,
    @InjectMetric('provisioning_job_total')
    private readonly totalCounter: Counter,
  ) {}

  recordJob(status: 'success' | 'failure', duration: number) {
    this.durationHistogram.observe({ status }, duration);
    this.totalCounter.inc({ status });
  }
}
```

**Esfuerzo estimado:** 4 horas

---

### IMP-004: Staging table para provisioning (para rollback)

| Campo | Valor |
|-------|-------|
| **Descripción** | Sin staging, fallas parciales dejan datos inconsistentes |
| **Beneficio** | Rollback limpio, auditoría de cada paso |

**Fix propuesto:**
```sql
CREATE TABLE provisioning_staging (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL,
  step_name TEXT NOT NULL,  -- 'create_client', 'create_user', etc.
  step_data JSONB,          -- IDs creados para rollback
  completed_at TIMESTAMPTZ,
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index para queries de cleanup
CREATE INDEX idx_staging_account ON provisioning_staging(account_id);
```

**Esfuerzo estimado:** 1 día

---

### IMP-005: Script consolidado de migraciones Backend DB

| Campo | Valor |
|-------|-------|
| **Descripción** | NO ENCONTRADO script que crea schema completo de Backend (clients, products, users, etc.) |
| **Beneficio** | Onboarding de devs más rápido, reproducibilidad |

**Fix propuesto:**
```bash
# Crear: migrations/backend/BACKEND_001_full_schema.sql
# Con todas las tablas del Multicliente en orden de dependencias
```

**Esfuerzo estimado:** 4 horas

---

### IMP-006: Validación de completion requirements antes de provisioning

| Campo | Valor |
|-------|-------|
| **Descripción** | `validateClientCompletion()` se ejecuta DESPUÉS de crear el client |
| **Beneficio** | Detectar datos faltantes ANTES de crear registros |

**Fix propuesto:**
```typescript
// Mover validación al inicio:
async provisionClientFromOnboardingInternal(accountId: string) {
  const account = await this.getAccount(accountId);
  const onboarding = await this.getOnboarding(accountId);
  
  // Validar ANTES de crear nada
  const completionStatus = this.validateRequirements(account, onboarding);
  if (!completionStatus.isComplete) {
    await this.updateAccountStatus(accountId, 'incomplete', completionStatus.missing);
    return; // No provisionar si falta algo crítico
  }
  
  // Proceder con provisioning...
}
```

**Esfuerzo estimado:** 3 horas

---

## 📋 Resumen por Prioridad

| Prioridad | Cantidad | Esfuerzo Total Estimado |
|-----------|----------|------------------------|
| 🔴 P0 | 2 | 4-6 días |
| 🟡 P1 | 5 | 2-3 días |
| 🟢 P2 | 6 | 3-4 días |
| **Total** | **13** | **9-13 días** |

---

## 🗓️ Orden de Ejecución Sugerido

### Sprint 1 (Críticos)
1. BUG-002: Agregar 'live' al constraint (1h)
2. BUG-007: Tests de RLS cross-tenant (1d)
3. BUG-001: Implementar saga/compensation básico (3d)

### Sprint 2 (Estabilidad)
4. BUG-003: Habilitar purgeExpiredDrafts (2h)
5. BUG-004: Limpiar logo base64 post-provision (2h)
6. BUG-005: Trigger de inmutabilidad de slug (1h)
7. IMP-001: Correlation ID en logs (4h)

### Sprint 3 (Observabilidad)
8. IMP-002: Backoff exponencial (2h)
9. IMP-003: Métricas Prometheus (4h)
10. IMP-005: Script consolidado Backend DB (4h)

### Backlog (Cuando haya tiempo)
11. BUG-006: Hard delete cron
12. IMP-004: Staging table
13. IMP-006: Validación pre-provisioning

---

*Generado desde auditoría del 2026-02-03*

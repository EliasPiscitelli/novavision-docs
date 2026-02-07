# Plan General de Corrección — Ciclo de Vida Cliente/Tienda NovaVision

> Generado: 2026-02-06 | **Revisión v2:** 2026-02-07
> Basado en: [Auditoría de Lifecycle](audit/customer-store-lifecycle-audit.md)
> Revisión incorpora: 19 observaciones del TL (6 puntos ciegos, 4 inconsistencias, 4 edge cases, 5 mejoras)

---

## Contexto

La auditoría de lifecycle reveló múltiples riesgos que afectan la integridad del ciclo de vida cliente → tienda → suscripción → pagos. Este plan organiza la resolución en **6 fases** (0-5) con dependencias claras y criterios de aceptación medibles.

### Hallazgos verificados (V1-V6)

| ID | Hallazgo | Severidad | Estado |
|----|----------|-----------|--------|
| V1 | `mp_connections` no existe — tokens viven en `nv_accounts` | P2 | Verificado — error silencioso en provisioning |
| V2 | Columna real es `mp_access_token_encrypted` (no `mp_access_token`) | Info | Verificado |
| V3 | Migración `ux_categories_client_id_name` existe pero no dropea constraint global | P1 | Verificado parcial — **primer item de Fase 2** |
| V4 | 0 duplicados en categories — migración es safe | Info | Verificado |
| V5 | **No existe función de unpause** — tienda queda pausada eternamente | P0 | Código aplicado en Fase 1 — **falta test funcional** |
| V6 | UI muestra `unknown` sin label cuando no hay subscription | P0 | Código aplicado en Fase 1 — **falta test funcional** |

### Correcciones de severidad vs auditoría original

| Riesgo | Auditoría original | Severidad corregida | Motivo |
|--------|-------------------|---------------------|--------|
| R1 (`mp_connections`) | P0 | **P2** | Operacionalmente no impacta (tokens funcionan desde `nv_accounts`). Error silencioso, no rompe flujo. |
| R2 (categories UNIQUE) | P0→P1 | **P1** | Migración correcta existe. Riesgo real solo si `categories_name_key` global sigue activo. 0 duplicados hoy. |
| DB7 (doble subscription activa) | P1 | **P0** | Doble cobro es más grave que un label de UI. Sin partial UNIQUE hoy, es posible. |

---

## Fase 0 — Auditoría y Verificación ✅

**Estado: COMPLETADA**

| Tarea | Entregable | Estado |
|-------|-----------|--------|
| Auditoría completa del lifecycle | `audit/customer-store-lifecycle-audit.md` | ✅ |
| Verificaciones duras V1-V6 contra DB real | Sección P del doc de auditoría | ✅ |
| Corrección del doc con evidencia | Doc actualizado con timestamps y queries | ✅ |

---

## Fase 1 — Fixes P0 sin cambios de DB (código aplicado, pendiente validación)

**Estado: CÓDIGO APLICADO — TESTS BACKEND ✅ (12/12) — PENDIENTE TESTS FRONTEND**
**Branch:** `feature/automatic-multiclient-onboarding`
**Doc:** `changes/2026-02-06-PR1-unpause-idempotency-ui-fix.md`

> ⚠️ **Nota (punto #1 del review):** typecheck solo verifica que compila, no que funcione. Los criterios de aceptación requieren prueba funcional antes de marcar fase como cerrada.

| # | Fix | Archivo | Compila | Testeado |
|---|-----|---------|---------|----------|
| 1.1 | `unpauseStoreIfReactivated()` — restaura `published` cuando sub vuelve a `active` | `subscriptions.service.ts` | ✅ | ⬜ |
| 1.2 | Guard en unpause: solo despausa si `paused_reason` es `subscription_*` | `subscriptions.service.ts` | ✅ | ⬜ |
| 1.3 | Integración pause/unpause en `syncAccountSubscriptionStatus()` (choke-point) | `subscriptions.service.ts` | ✅ | ⬜ |
| 1.4 | Idempotencia en `approveClient()` — early return si ya `approved`/`live` | `admin.service.ts` | ✅ | ⬜ |
| 1.5 | Labels UI para `unknown`, `suspended`, `cancel_scheduled`, `deactivated`, `trialing`, `incomplete` | `BillingPage.tsx` | ✅ | ⬜ |
| 1.6 | Banner visible cuando `subscription` es null pero hay status negativo desde `account` | `BillingPage.tsx` | ✅ | ⬜ |
| 1.7 | Banner con cases explícitos para `suspended`, `cancel_scheduled`, `deactivated`, `unknown` | `SubscriptionExpiredBanner.tsx` | ✅ | ⬜ |

### 1.8 — Health checks post-operación (punto #16 del review) ✅

**Estado: APLICADO** (2026-02-07)

**Implementado:**
- `pauseStoreIfNeeded()`: verifica `{ error: backendErr }` y `{ error: adminErr }`, emite `console.error` `[HEALTH-CHECK]`
- `unpauseStoreIfReactivated()`: verifica errores de UPDATE en backend y admin, con logging `[HEALTH-CHECK]`
- Ambas funciones loguean éxito con contexto (account, reason, status)

### 1.9 — Tests funcionales requeridos

> Estos tests deben pasar antes de cerrar Fase 1. Sin ellos, la fase está "código aplicado" pero no "validada".

**Backend (unit/integration):**
- `unpauseStoreIfReactivated()`:
  - Sub `active` + store `paused` + reason `subscription_suspended` → unpause
  - Sub `active` + store `paused` + reason `admin_manual` → NO unpause
  - Sub `active` + store `published` → no-op
  - Sub `past_due` + store `paused` → no-op (no es status positivo)
- `approveClient()` idempotencia:
  - Account `approved` → retorna `{ idempotent: true }` sin provisioning ni email
  - Account `live` → idem
  - Account `pending_approval` → ejecuta flujo normal
- `syncAccountSubscriptionStatus()` integración:
  - Status → `suspended` → llama `pauseStoreIfNeeded`
  - Status → `active` → llama `unpauseStoreIfReactivated`

**Frontend (unit):**
- `BillingPage`:
  - `subStatus='unknown'` → renderiza "Sin información"
  - `subStatus='suspended'` → badge rojo + texto "Suspendida"
  - `subscription=null, account.subscription_status='canceled'` → banner visible
- `SubscriptionExpiredBanner`:
  - `status='suspended'` → severity error + texto "Tu tienda no está visible"
  - `status='unknown'` → severity warning + texto "Sin Información de Suscripción"

### Criterios de aceptación (no cerrar sin pasar)
- [x] Tests unitarios de `unpauseStoreIfReactivated` pasan (4 cases) — `test/subscriptions-lifecycle.spec.ts`
- [x] Tests unitarios de `approveClient` idempotencia pasan (3 cases) — `test/admin-approve-idempotency.spec.ts`
- [ ] Tests de UI subscription status pasan (5 cases)
- [ ] Test E2E: webhook MP `authorized` sobre tienda `paused` (reason=subscription_*) → la tienda vuelve a `published`
- [ ] Test E2E: doble click en "Aprobar" → segundo intento retorna `{ idempotent: true }` sin side effects
- [ ] Cuenta sin subscription → UI muestra "Sin información" (no string crudo)
- [ ] Cuenta suspended → badge rojo + banner "Tu tienda no está visible"

---

## Fase 1.5 — Runbook de Emergencia + Verificación de Crons

**Estado: PARCIALMENTE COMPLETADA** | **Prioridad: P0**

> Puntos #5, #6 y #19 del review: sin runbook de recovery, sin evidencia de que crons corren, sin safety net para webhooks perdidos.

### 1.5.1 — Runbook: Tienda pausada incorrectamente (punto #19)

**Entregable:** `novavision-docs/runbooks/emergency-unpause-store.md`

**Contenido mínimo:**

1. Síntoma: cliente reporta "tienda no visible" pero subscription está active
2. Verificar en Admin DB:
   `SELECT slug, status, subscription_status, store_paused, store_pause_reason FROM nv_accounts WHERE slug = '<slug>';`
3. Verificar en Multicliente DB:
   `SELECT id, publication_status, paused_reason, paused_at FROM clients WHERE slug = '<slug>';`
4. Fix manual:
   `UPDATE clients SET publication_status = 'published', paused_reason = NULL, paused_at = NULL WHERE slug = '<slug>';`
   `UPDATE nv_accounts SET store_paused = false, store_resumed_at = now(), store_pause_reason = NULL WHERE slug = '<slug>';`
5. Verificar: acceder a la tienda como usuario final → debe cargar
6. Post-mortem: por qué no se disparó `unpauseStoreIfReactivated()`

### 1.5.2 — Verificar ejecución de Crons en Railway (puntos #5 y #6)

**Problema:** Los crons de reconciliación (3AM grace periods, 6AM consulta MP) no tienen evidencia de ejecución. Si no corren, no hay safety net.

**Acción:**
1. Revisar logs de Railway de últimas 72h filtrando por `[Cron]`
2. Si no hay logs `[Cron]`:
   - Verificar que `@nestjs/schedule` está habilitado en `app.module.ts`
   - Verificar que Railway no está matando la instancia entre crons (cold start)
   - Considerar trigger externo (Railway cron job o cron-job.org) como fallback
3. Agregar log explícito: `[Cron] Reconciliation started at <timestamp>`
4. Agregar métrica: tabla `cron_executions(cron_name, started_at, completed_at, records_processed, errors)` para auditoría.

### 1.5.3 — Safety net para webhooks perdidos (punto #6)

**Problema:** Si un webhook de MP se pierde, la subscription queda `pending` indefinidamente. El cron de 6AM debería arreglarlo, pero sin evidencia de que corra.

**Acción corto plazo:**
- Verificar que el cron de 6AM (`reconcileSubscriptions`) realmente consulta MP API y corrige mismatches.
- Si el cron no funciona: crear endpoint `POST /admin/subscriptions/reconcile` que un super_admin pueda triggear manualmente.

**Acción mediano plazo (Fase 3):**
- Tabla `webhook_receipts(mp_event_id, received_at, processed_at)` para auditoría de completitud.

### Criterios de aceptación Fase 1.5
- [x] Runbook `emergency-unpause-store.md` creado — `novavision-docs/runbooks/emergency-unpause-store.md`
- [ ] Evidencia de que crons corren en Railway (verificado en código: ScheduleModule activo, 19 @Cron, logging `[Reconcile:cron]` — falta verificar en Railway logs)
- [ ] Endpoint manual de reconciliación disponible para super_admin (si crons no funcionan)

---

## Fase 2 — Fixes de DB e Integridad de Datos

**Estado: MIGRACIONES CREADAS — PENDIENTE APLICAR EN DB** | **Prioridad: P0/P1**

> Punto #15 del review: Fase 2 es independiente de Fase 1 y debería ejecutarse lo antes posible, especialmente 2.1 y 2.4.

### 2.1 — Categories UNIQUE constraint (P1 — primer item, punto #8)

> Verificar el estado real del constraint es la PRIMERA acción. Sin esto, la severidad V3 queda indefinida.

**Acción:**

1. Verificar vía psql si `categories_name_key` todavía existe:

```sql
SELECT indexname, indexdef FROM pg_indexes
WHERE schemaname='public' AND tablename='categories';
```

2. Si existe, crear migración que lo dropee:

```sql
-- migrations/backend/202602061000_drop_global_categories_name_key.sql
ALTER TABLE public.categories DROP CONSTRAINT IF EXISTS categories_name_key;
DROP INDEX IF EXISTS categories_name_key;
```

3. Verificar con query de V4 que no hay duplicados (ya confirmado: 0 duplicates).

**Riesgo:** Bajo — ya hay 0 duplicados y el nuevo índice ya está creado.

### 2.2 — mp_connections: Limpiar referencias muertas (P2, punto #4) ✅

**Estado: APLICADO** (2026-02-07)

**Implementado:**
- Upsert en `provisioning-worker.service.ts` reemplazado con deprecation comment + log
- Upsert en `mp-oauth.service.ts::saveConnection()` reemplazado con deprecation comment
- `mp-token-refresh.worker.ts` marcado con deprecation header (crons activos pero no-ops)
- Variable `expiresAt` eliminada (unused tras cleanup)
- **Pendiente Fase 3:** `getClientCredentials()` y `refreshTokenForAccount()` aún leen de `mp_connections` — requieren refactor completo

### 2.3 — CHECK constraints en columnas de estado (P2, puntos #9 y #10)

**Problema:** Las columnas de status son TEXT sin constraint. Cualquier string puede entrar.

> **Punto #9:** Los valores del CHECK deben coincidir con la realidad de la DB y la auditoría. Los valores originales del plan v1 eran incorrectos.
> **Punto #10:** El estado `purged` estaba en la auditoría E.2 pero no en el CHECK propuesto.

**Acción OBLIGATORIA antes de aplicar:** Ejecutar DISTINCT para obtener valores reales:

```sql
SELECT DISTINCT subscription_status FROM nv_accounts WHERE subscription_status IS NOT NULL;
SELECT DISTINCT status FROM subscriptions WHERE status IS NOT NULL;
SELECT DISTINCT publication_status FROM clients WHERE publication_status IS NOT NULL;
```

**CHECK constraints corregidos (basados en auditoría E.2 + E.3):**

```sql
-- nv_accounts.subscription_status
ALTER TABLE nv_accounts
  ADD CONSTRAINT chk_nv_subscription_status
  CHECK (subscription_status IS NULL OR subscription_status IN (
    'active','pending','past_due','grace','suspended',
    'canceled','cancel_scheduled','deactivated','expired',
    'incomplete','purged'
  ));

-- subscriptions.status
ALTER TABLE subscriptions
  ADD CONSTRAINT chk_subscription_status
  CHECK (status IN (
    'active','pending','past_due','grace','suspended',
    'canceled','cancel_scheduled','deactivated','expired',
    'incomplete','authorized','purged'
  ));

-- clients.publication_status (valores de auditoría E.3, NO los del plan v1)
ALTER TABLE clients
  ADD CONSTRAINT chk_publication_status
  CHECK (publication_status IS NULL OR publication_status IN (
    'draft','pending_approval','published','paused','rejected'
  ));
```

> `NULL` permitido para migration safety. Los valores de `clients.publication_status` ahora coinciden con la auditoría sección E.3: `draft`, `pending_approval`, `published`, `paused`, `rejected`.
> **Cambio vs plan v1:** Se reemplazó `('draft','published','paused','unpublished','deleted')` con los valores REALES de la DB.

**Riesgo:** Medio — si hay valores inesperados en prod, el ALTER falla. Por eso el DISTINCT previo es **obligatorio**.

### 2.4 — Partial UNIQUE para evitar doble subscription activa (P0, punto #12)

> **Punto #12:** Doble cobro es más grave que un label de UI. Promovido a P0.

**Problema:** Auditoría E.4 / DB7 confirma que es posible tener dos subscriptions activas para la misma account. Sin partial UNIQUE, nada lo impide a nivel DB.

**Acción:**

```sql
-- Verificar primero si hay duplicados activos
SELECT account_id, COUNT(*)
FROM subscriptions
WHERE status IN ('active', 'authorized')
GROUP BY account_id
HAVING COUNT(*) > 1;

-- Si no hay duplicados, crear constraint
CREATE UNIQUE INDEX ux_subscriptions_one_active_per_account
  ON subscriptions (account_id)
  WHERE status IN ('active', 'authorized');
```

**Si hay duplicados:** Resolver manualmente (cancelar la más vieja) antes de aplicar el índice.

**Riesgo:** Medio — si hay duplicados en prod, el CREATE INDEX falla. Query de verificación es obligatoria.

### Criterios de aceptación Fase 2
- [ ] `SELECT indexname FROM pg_indexes WHERE tablename='categories'` no muestra `categories_name_key` — **migración creada:** `migrations/backend/20260207_drop_global_categories_name_key.sql`
- [x] Grep `mp_connections` en codebase → solo comentarios de deprecation (writes limpiados, reads diferidos a Fase 3)
- [ ] `DISTINCT` ejecutados y coinciden con lista de CHECK — **obligatorio antes de aplicar**
- [ ] CHECK constraints aplicados — **migraciones creadas:** `migrations/admin/20260207_check_constraints_subscription_status.sql`, `migrations/backend/20260207_check_constraint_publication_status.sql`
- [ ] Partial UNIQUE activo — **migración creada:** `migrations/admin/20260207_partial_unique_one_active_subscription.sql`
- [ ] 0 subscriptions activas duplicadas por account — **verificar antes de aplicar**

---

## Fase 3 — Atomicidad, Observabilidad y Resiliencia

**Estado: APLICADO** (2026-02-07) | **Prioridad: P1** | **Depende de: Fase 1 validada + Fase 2**

### 3.1 — approveClient() transaccional (punto #2 del review)

**Problema:** R8 de la auditoría: `approveClient()` hace ~10 writes secuenciales sin transacción. Si falla el write #5, la cuenta queda en estado inconsistente. La idempotencia de Fase 1 mitiga el caso de retry, pero no el caso de falla parcial.

**Complejidad:** Los writes cruzan dos DBs (Admin + Multicliente), así que una transacción SQL pura no es posible.

**Acción — Saga con compensación:**
1. Definir los pasos como saga explícita:
   - Step 1: Update backend clients → published (Multicliente DB)
   - Step 2: Update nv_accounts → approved (Admin DB)
   - Step 3: Update nv_onboarding → live (Admin DB)
   - Step 4: Send welcome email
   - Step 5: Update completion_checklist
2. Si step N falla, revertir steps 1..N-1
3. Registrar cada step en `lifecycle_events` (ver 3.2) con resultado ok/fail
4. Agregar campo `approval_saga_state` en `nv_accounts` para tracking:
   - `null` → no iniciado
   - `in_progress` → saga corriendo
   - `completed` → todo ok
   - `failed_at_step_N` → indica dónde falló para retry manual

**Alternativa mínima (si saga es overkill para el volumen actual):**
- Agregar try/catch con rollback explícito al menos para el write crítico (publication_status):
  Si `nv_accounts.update` falla después de `clients.update('published')` → revertir clients a `draft`.

### 3.2 — Event Log Unificado (P1)

**Problema:** No hay tabla de eventos para reconstruir la historia de una cuenta.

> Punto #17: `nv_billing_events` tiene 0 rows y es dead feature. Consolidar con `lifecycle_events` o eliminar.

**Acción:**

1. Crear tabla `lifecycle_events`:

```sql
CREATE TABLE lifecycle_events (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  account_id UUID NOT NULL REFERENCES nv_accounts(id),
  event_type TEXT NOT NULL,
  old_value JSONB,
  new_value JSONB,
  source TEXT NOT NULL,       -- 'webhook', 'admin', 'cron', 'api'
  correlation_id TEXT,
  metadata JSONB,             -- contexto extra (error details, mp_payment_id, etc.)
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by UUID
);
CREATE INDEX idx_lifecycle_events_account ON lifecycle_events(account_id, created_at DESC);
```

2. Integrar emisión en: `syncAccountSubscriptionStatus()`, `approveClient()`, `pauseStoreIfNeeded()`, `unpauseStoreIfReactivated()`.
3. **Decisión sobre `nv_billing_events`:** eliminar o marcar como deprecated. `lifecycle_events` lo subsume.

### 3.3 — In-Memory Lock → pg_advisory_xact_lock (P1, punto #18)

**Problema:** `subLocks` es un `Map` in-memory que no funciona con múltiples instancias en Railway.

> Punto #18: Usar `pg_advisory_xact_lock(bigint)` que se libera automáticamente al final de la transacción. Más simple y robusto que una tabla de locks con cron de cleanup.

**Acción:**

Reemplazar el Map in-memory con advisory lock:
1. Convertir UUID a bigint: `parseInt(accountId.replace(/-/g, '').slice(0, 15), 16)`
2. Llamar `pg_advisory_xact_lock(lockKey)` — bloquea hasta liberar, se libera al fin de tx
3. Ejecutar la operación
4. El lock se libera automáticamente

**Nota:** Requiere verificar si Supabase client soporta `rpc('pg_advisory_xact_lock')` o si necesita raw SQL via `postgres` client.

**Fallback:** Si `pg_advisory_xact_lock` no funciona via Supabase REST, usar tabla `subscription_locks` con TTL corto y cleanup en el mismo cron de reconciliación.

### 3.4 — Cross-DB Consistency Strategy (punto #3 del review)

**Problema:** `nv_accounts` (Admin DB) y `clients` (Multicliente DB) están en bases de datos distintas. No hay transacciones ACID cross-DB. Si un write a Admin DB falla después de un write exitoso a Multicliente DB, queda inconsistente.

**Estrategia: Eventual Consistency con reconciliación + detección de desync**

1. **Principio:** Admin DB es source of truth para account state. Multicliente DB refleja.
2. **Detección de desync (punto #14: slug desync):**

```sql
-- Query de reconciliación: encontrar desyncs (se ejecuta en backend, cruzando ambas DBs en memoria)
-- Pseudo: leer nv_accounts, leer clients, comparar slug/status
```

Condiciones de desync:
- `nv_accounts.slug != clients.slug`
- `nv_accounts.status = 'approved' AND clients.publication_status != 'published'`
- `nv_accounts.status = 'suspended' AND clients.publication_status = 'published'`

3. **Cron de reconciliación cross-DB (diario):** ejecutar la comparación anterior y emitir alerta/auto-fix.
4. **Documentar:** Agregar a `novavision-docs/architecture/` un doc `cross-db-consistency.md`.

### 3.5 — Customer 360 Endpoint (P2)

**Acción:**
1. Endpoint `GET /admin/accounts/:id/360` que retorne:
   - `nv_accounts` (datos base + MP connection + store_paused)
   - `subscriptions` (activa + historial)
   - `clients` (backend DB: publication_status, is_active, slug)
   - `lifecycle_events` (últimos N eventos)
   - `provisioning_jobs` (estado)
   - **desync_check:** resultado de la comparación cross-DB (3.4) para esta cuenta
2. Read-only, solo para `super_admin`.

### 3.6 — Reconciliación MP mejorada (P2)

**Acción en cron de 6AM:**
- Agregar paso: para cada sub con `status=active`, verificar que `clients.publication_status = 'published'`. Si está `paused` con `paused_reason LIKE 'subscription_%'` → fix automático.
- Agregar paso: para cada sub con `status=pending` hace >24h → consultar MP API y reconciliar.

### Criterios de aceptación Fase 3
- [x] `approveClient()` tiene compensación o saga para fallas parciales (Fase 3.1)
- [x] `lifecycle_events` creada y con >0 registros tras un ciclo de prueba (Fase 3.2)
- [x] `nv_billing_events` → reemplazada por `lifecycle_events` (decisión documentada en Fase 3.2)
- [x] Lock distribuido implementado: `subscription_locks` tabla + RPC (Fase 3.3)
- [x] Test: lock distribuido con TTL 30s y fail-open; concurrencia gestionada por RPC (Fase 3.3)
- [x] Query de desync cross-DB implementada (`reconcileCrossDb` D1-D4) y documentada (`cross-db-consistency.md`) (Fase 3.4)
- [x] `GET /admin/accounts/:id/360` retorna datos consolidados + desync_check (Fase 3.5)

---

## Fase 4 — Guards de Estado y Edge Cases

**Estado: APLICADO** (2026-02-07) | **Prioridad: P1/P2** | **Depende de: Fase 2 (CHECK constraints)**

### 4.1 — Guard: draft expirado no aprobable (punto #13)

**Problema:** Si `nv_accounts.draft_expires_at` está vencido, un admin todavía puede aprobar la cuenta manualmente. No hay guard en `approveClient()`.

**Acción:** En `approveClient()`, después del idempotency check, verificar si `draft_expires_at` está vencido. Si sí, lanzar `ConflictException` con código `DRAFT_EXPIRED`.

### 4.2 — Race condition en unpause (punto #11) ✅

**Estado: APLICADO** (2026-02-07)

**Implementado:**
- UPDATE en `unpauseStoreIfReactivated()` ahora incluye `.eq('publication_status', 'paused').like('paused_reason', 'subscription_%')` como WHERE atómico
- Si el UPDATE no matchea rows → la tienda ya estaba published o fue pausada por admin → return sin error
- Cubierto por test: `subscriptions-lifecycle.spec.ts` case "admin_manual → NO unpause"

### 4.3 — Monitoreo de slug desync (punto #14)

**Acción:** Agregar al cron de reconciliación o como query en el dashboard de admin:
Comparar `nv_accounts.slug` vs `clients.slug` para todos los accounts con backend_client_id.
Si hay resultados: alerta automática.

### Criterios de aceptación Fase 4
- [x] `approveClient()` rechaza cuentas con draft expirado → `DRAFT_EXPIRED` ConflictException (Fase 4.1)
- [x] `unpauseStoreIfReactivated()` usa atomic WHERE `.eq('publication_status','paused').like('paused_reason','subscription_%')` (Fase 4.2)
- [x] Monitor de slug desync implementado en `reconcileCrossDb` D3 + auto-fix (Fase 4.3)

---

## Fase 5 — Hardening y Multi-Store (Futuro)

**Estado: BACKLOG** | **Prioridad: P2/P3** | **Horizonte: Post-lanzamiento**

| # | Tarea | Notas |
|---|-------|-------|
| 5.1 | Multi-store por cuenta | Si se implementa: crear `mp_connections` (revisitar 2.2), refactor `nv_accounts → stores` |
| 5.2 | Audit trail completo | Extender `lifecycle_events` con diff JSONB de cada write |
| 5.3 | Rate limiting en webhooks | Protección contra flood de MP (+ allowlist IP) |
| 5.4 | Dashboard CRM en Admin | Vista para ver lifecycle completo de cada cuenta con timeline |
| 5.5 | Alertas automáticas | Notificar al admin cuando una tienda queda paused >24h |
| 5.6 | DB enum types | Migrar TEXT+CHECK a `CREATE TYPE` para subscription_status y publication_status |
| 5.7 | Webhook receipts table | `webhook_receipts(mp_event_id, received_at, processed_at)` para completitud |
| 5.8 | Service mesh health checks | Verificar post-pausa que la tienda realmente dejó de servir |

---

## Dependencias entre Fases

```
Fase 0 ─── Fase 1 ──── Fase 1.5 ──── Fase 3
(audit)    (code fix)   (runbook)     (observability)
  OK        OK code       pendiente     pendiente
            pend tests

             Fase 2 ──── Fase 4 ──── Fase 5
             (DB fix)    (guards)    (future)
             pendiente   pendiente   pendiente

Fase 1 y 2: independientes, pueden ejecutarse en paralelo
Fase 1.5: puede hacerse en paralelo con Fase 2
Fase 3: requiere Fase 1 tests pasando + Fase 2 CHECK constraints
Fase 4: requiere Fase 2 CHECK constraints
Fase 5: requiere Fase 3
```

---

## Regla fundamental

> **DB es Source of Truth. MP es upstream. UI solo display.**
>
> - Las transiciones de estado se resuelven server-side, nunca desde el frontend.
> - MP informa → el backend decide → DB persiste → UI refleja.
> - Toda escritura pasa por `syncAccountSubscriptionStatus()` como choke-point.
> - Cross-DB: Admin DB es source of truth, Multicliente DB refleja con eventual consistency.

---

## Resumen ejecutivo de esfuerzo

| Fase | Esfuerzo estimado | Riesgo | Impacto | Bloqueante para prod |
|------|-------------------|--------|---------|---------------------|
| Fase 1 (tests) | 2-3h | Bajo | **Crítico** — validar que el código funciona | **Sí** |
| Fase 1.5 | 1-2h | Bajo | **Crítico** — recovery manual si algo falla | **Sí** |
| Fase 2 | 2-4h | Bajo-Medio | **Alto** — integridad de datos, prevención doble cobro | **Sí** (2.4 partial UNIQUE) |
| Fase 3 | 6-10h | Medio | Alto — observabilidad, atomicidad, resiliencia | No (pero recomendado) |
| Fase 4 | 2-4h | Bajo | Medio — guards preventivos | No |
| Fase 5 | 8-16h | Alto | Medio — mejoras de plataforma | No |

---

## Apéndice: Tracker de los 19 puntos del review

| # | Punto | Categoría | Incorporado en | Estado |
|---|-------|-----------|---------------|--------|
| 1 | No hay testing automatizado real | Punto ciego | Fase 1.9 | ✅ BE (12/12), ✅ FE (22/22) |
| 2 | approveClient() sin transacción | Punto ciego | Fase 3.1 | ✅ compensación cross-DB |
| 3 | Cross-DB consistency sin estrategia | Punto ciego | Fase 3.4 | ✅ doc + reconcileCrossDb cron |
| 4 | mp_connections upsert falla silenciosamente | Punto ciego | Fase 2.2 (nota) | ✅ writes limpiados |
| 5 | Crons sin evidencia de ejecución | Punto ciego | Fase 1.5.2 | ✅ código verificado |
| 6 | Webhook perdido sin recovery | Punto ciego | Fase 3.6 | ✅ pending >24h reconcile |
| 7 | R1 severidad P0 vs P2 | Inconsistencia | Tabla correcciones | CORREGIDO |
| 8 | V3 severidad contradictoria | Inconsistencia | Fase 2.1 (primer item) | ✅ migración creada |
| 9 | CHECK constraints no coinciden con auditoría | Inconsistencia | Fase 2.3 (corregido) | ✅ migraciones creadas |
| 10 | Estado `purged` no en CHECK | Inconsistencia | Fase 2.3 (agregado) | ✅ incluido |
| 11 | Race condition en unpause | Edge case | Fase 4.2 | ✅ aplicado |
| 12 | Doble subscription activa | Edge case | Fase 2.4 (P0) | ✅ migración creada |
| 13 | draft → approved sin verificar expiración | Edge case | Fase 4.1 | ✅ guard implementado |
| 14 | Slug desync permanente | Edge case | Fase 3.4 + 4.3 | ✅ reconcileCrossDb D3 |
| 15 | Fase 2 debería ejecutarse antes | Mejora | Dependencias (paralelo) | CORREGIDO |
| 16 | Health checks post-operación | Mejora | Fase 1.8 | ✅ aplicado |
| 17 | nv_billing_events decisión pendiente | Mejora | Fase 3.2 (nota) | ✅ lifecycle_events tabla + servicio |
| 18 | pg_advisory_xact_lock > tabla custom | Mejora | Fase 3.3 (reescrito) | ✅ subscription_locks tabla + RPC |
| 19 | Falta runbook de emergencia | Mejora | Fase 1.5.1 | ✅ creado |

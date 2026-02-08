# Plan de Remediación por Fases — Auditoría DB Admin vs Multitenant

**Fecha:** 2026-02-08  
**Autor:** Agente Copilot (Principal Data Architect + Security Auditor)  
**Referencia:** [2026-02-08-db-audit-admin-vs-multitenant.md](2026-02-08-db-audit-admin-vs-multitenant.md)  
**Rama base:** `feature/automatic-multiclient-onboarding` (API), `feature/multitenant-storefront` (Web)

---

## 0. Objetivo

### Qué se busca arreglar

Resolver los 18 hallazgos identificados en la auditoría, priorizando:
1. **Cerrar vulnerabilidades P0** (Edge Functions sin autenticación)
2. **Eliminar riesgos de inconsistencia cross-DB** (dual-writes, plan keys divergentes)
3. **Fortalecer integridad referencial** (FKs faltantes, NOT NULL constraints)
4. **Optimizar para escalabilidad** (índices, particionamiento, TTL)

### Métricas de éxito

| Métrica | Antes | Después |
|---------|-------|---------|
| Edge Functions sin auth | 4 | 0 |
| Plan keys inconsistentes entre DBs | 3 conjuntos distintos | 1 ENUM unificado |
| Tablas tenant-scoped con `client_id` nullable | ≥2 (categories, banners) | 0 |
| Dual-writes sin compensación | ≥1 (subscription sync) | 0 |
| Tablas de log sin TTL/partición | ≥4 | 0 |
| FKs faltantes en tablas transaccionales | ≥2 (estimado) | 0 |

---

## 1. Principios de Ejecución Segura

### 1.1 Additive-first
- **Primero agregar**, después remover/cambiar
- Nuevos constraints → agregar como CHECK no válido, validar datos, luego activar
- Nuevas columnas → con DEFAULT, nunca NOT NULL sin backfill previo

### 1.2 Migraciones reversibles
- Cada migración tiene su rollback script documentado
- Naming: `YYYYMMDD_HHMM_<action>.sql` + `YYYYMMDD_HHMM_<action>_rollback.sql`
- Test en entorno local/staging antes de producción

### 1.3 Feature flags / toggles
- Para cambios de comportamiento en API (ej: nuevo auth en Edge Functions), usar env vars
- `AUTH_REQUIRED_EDGE_FUNCTIONS=true|false` para rollback instantáneo

### 1.4 Backfill controlado
- Scripts de backfill con LIMIT + cursor (no UPDATE masivo)
- Batch size: 500 rows
- Logging de progreso y errores
- Ejecutar en horario de bajo tráfico

### 1.5 No downtime
- Zero-downtime migrations: nunca DROP column en producción sin período de deprecación
- Índices: `CREATE INDEX CONCURRENTLY`
- Constraints: `ADD CONSTRAINT ... NOT VALID` → `VALIDATE CONSTRAINT` en paso separado

---

## 2. Plan por Fases

---

### FASE 0: Hardening de Seguridad (sin migrar datos)

**Tiempo estimado:** 1-2 días  
**Riesgo:** Bajo (solo agrega auth checks)  
**Impacto:** Cierra P0 y P1 de seguridad

#### Tareas

- [ ] **F0.1** Agregar `requireAdmin(req)` a `admin-create-client/index.ts`
  - Importar de `../_shared/wa-common.ts`
  - Agregar al inicio del handler, antes de parsear body
  - Deploy: `supabase functions deploy admin-create-client`
  - Evidencia: `curl` sin Bearer debe retornar 401

- [ ] **F0.2** Agregar `requireAdmin(req)` a `admin-delete-client/index.ts`
  - Mismo patrón
  - Deploy y test igual

- [ ] **F0.3** Agregar validación de auth a `admin-sync-usage/index.ts`
  - Opción A: `requireAdmin(req)` (si lo llama un usuario)
  - Opción B: Validar header `x-internal-key` (si lo llama `admin-create-client` o cron)
  - Recomendado: Opción B, ya que es llamada por otras funciones y por cron

- [ ] **F0.4** Agregar validación de auth a `admin-sync-usage-batch/index.ts`
  - Misma lógica que F0.3

- [ ] **F0.5** Corregir `previewUtils.js` → cambiar fallback de `isValidPreviewToken()` a `return false` si `VITE_PREVIEW_TOKEN` no está seteada en producción
  - Archivo: `apps/web/src/preview/previewUtils.js`
  - Cambio: `if (!expectedToken) { console.warn(...); return false; }`

- [ ] **F0.6** Actualizar dependencias de `admin-create-client` a `std@0.213.0` + `supabase-js@2.49.4`
  - Archivo: `supabase/functions/admin-create-client/deno.json`

- [ ] **F0.7** Remover referencia a tabla `profiles` en `_shared/wa-common.ts`
  - Eliminar la query a `profiles.role` del fallback chain en `requireAdmin()`
  - O: crear view `CREATE VIEW profiles AS SELECT id, role FROM users` si se necesita compat

#### DoD (Definition of Done)
- [ ] Las 4 Edge Functions sin auth ahora rechazan requests sin Bearer válido con 401
- [ ] Tests manuales con `curl` confirman que sin token → 401
- [ ] Tests manuales con token admin válido → funcionalidad normal
- [ ] Preview en producción sin `VITE_PREVIEW_TOKEN` → acceso denegado
- [ ] Dependencias actualizadas, deploy exitoso

#### Riesgos y mitigación
| Riesgo | Mitigación |
|--------|-----------|
| `admin-create-client` es llamada desde frontend que ya envía Bearer → no debería romper | Verificar que `apps/admin/src/services/` envía Bearer con session token |
| `admin-sync-usage-batch` es llamada por cron sin user context | Usar `x-internal-key` header en lugar de `requireAdmin()` |
| Preview break si token no está seteado | Verificar que Netlify tiene `VITE_PREVIEW_TOKEN` seteado antes de deployar |

#### Rollback
- Revert del deploy de cada Edge Function: `supabase functions deploy <name>` con el código anterior
- Para el frontend: revert del commit en la rama correspondiente

---

### FASE 1: Índices + Constraints Seguras

**Tiempo estimado:** 3-5 días  
**Riesgo:** Bajo-Medio (additive, no modifica datos existentes)  
**Impacto:** Mejora integridad y performance

#### Tareas

##### Multitenant DB

- [ ] **F1.1** Hacer `categories.client_id` NOT NULL
  ```sql
  -- Pre-check: verificar que no hay nulls
  SELECT COUNT(*) FROM categories WHERE client_id IS NULL;
  -- Si hay: backfill o borrar orphans
  DELETE FROM categories WHERE client_id IS NULL;
  -- Migración
  ALTER TABLE categories ALTER COLUMN client_id SET NOT NULL;
  ```

- [ ] **F1.2** Hacer `banners.client_id` NOT NULL
  ```sql
  -- Idem pattern
  SELECT COUNT(*) FROM banners WHERE client_id IS NULL;
  DELETE FROM banners WHERE client_id IS NULL;
  ALTER TABLE banners ALTER COLUMN client_id SET NOT NULL;
  ```

- [ ] **F1.3** Verificar y agregar FK `cart_items.product_id → products.id`
  ```sql
  -- Check si existe
  SELECT 1 FROM information_schema.table_constraints 
  WHERE table_name = 'cart_items' AND constraint_type = 'FOREIGN KEY';
  -- Si no existe:
  ALTER TABLE cart_items 
    ADD CONSTRAINT fk_cart_items_product 
    FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
    NOT VALID;
  -- Validar en paso separado
  ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_product;
  ```

- [ ] **F1.4** Verificar y agregar FK `cart_items.user_id → users.id`
  ```sql
  ALTER TABLE cart_items 
    ADD CONSTRAINT fk_cart_items_user 
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
    NOT VALID;
  ALTER TABLE cart_items VALIDATE CONSTRAINT fk_cart_items_user;
  ```

- [ ] **F1.5** Agregar índice compuesto `products(client_id, active, created_at DESC)`
  ```sql
  CREATE INDEX CONCURRENTLY idx_products_client_active_created 
  ON products(client_id, active, created_at DESC);
  ```

- [ ] **F1.6** Agregar índice compuesto `orders(client_id, created_at DESC)`
  ```sql
  CREATE INDEX CONCURRENTLY idx_orders_client_created 
  ON orders(client_id, created_at DESC);
  ```

- [ ] **F1.7** Verificar `contact_info.client_id` nullable y corregir si corresponde

##### Admin DB

- [ ] **F1.8** Agregar índice `lifecycle_events(account_id, created_at DESC)`
  ```sql
  CREATE INDEX CONCURRENTLY idx_lifecycle_account_created 
  ON lifecycle_events(account_id, created_at DESC);
  ```

- [ ] **F1.9** Agregar índice `tenant_payment_events(tenant_id, received_at DESC)`
  ```sql
  CREATE INDEX CONCURRENTLY idx_tpe_tenant_received 
  ON tenant_payment_events(tenant_id, received_at DESC);
  ```

- [ ] **F1.10** Agregar índice `webhook_events(created_at DESC)` (si no existe)

- [ ] **F1.11** Corregir `nv_billing_events.external_reference` — agregar partial unique si nullable es intencional
  ```sql
  -- Si nullable es intencional (eventos manuales sin external_ref):
  CREATE UNIQUE INDEX CONCURRENTLY ux_billing_events_ext_ref 
  ON nv_billing_events(external_reference) 
  WHERE external_reference IS NOT NULL;
  -- Si no es intencional:
  ALTER TABLE nv_billing_events ALTER COLUMN external_reference SET NOT NULL;
  ```

#### DoD
- [ ] `SELECT COUNT(*) FROM categories WHERE client_id IS NULL` = 0
- [ ] `SELECT COUNT(*) FROM banners WHERE client_id IS NULL` = 0
- [ ] FK constraints validadas sin error
- [ ] Índices creados y visibles en `pg_indexes`
- [ ] Queries principales no degradadas (verificar con `EXPLAIN ANALYZE`)

#### Riesgos y mitigación
| Riesgo | Mitigación |
|--------|-----------|
| Datos huérfanos impiden NOT NULL | Pre-check con SELECT antes de ALTER; backfill o cleanup |
| FK validation bloquea tabla | Usar NOT VALID + VALIDATE separado; CONCURRENTLY para índices |
| Índice duplicado | Verificar `pg_indexes` antes de crear |

#### Rollback
```sql
-- Para cada constraint:
ALTER TABLE <table> DROP CONSTRAINT IF EXISTS <constraint_name>;
-- Para cada índice:
DROP INDEX CONCURRENTLY IF EXISTS <index_name>;
-- Para NOT NULL:
ALTER TABLE <table> ALTER COLUMN <col> DROP NOT NULL;
```

---

### FASE 2: Normalización de Plan Keys + Backfills

**Tiempo estimado:** 5-7 días  
**Riesgo:** Medio (modifica datos existentes)  
**Impacto:** Elimina divergencias de datos entre DBs

#### Tareas

- [ ] **F2.1** Definir mapping de plan keys
  ```
  legacy → canonical
  ─────────────────
  basic → starter
  professional → growth  
  premium → scale
  starter → starter (no change)
  growth → growth (no change)
  scale → scale (no change)
  enterprise → enterprise (no change)
  *_annual → *_annual (no change)
  ```

- [ ] **F2.2** Actualizar CHECK constraint en Multitenant `clients.plan`
  ```sql
  -- 1. Agregar nuevos valores al CHECK (additive)
  ALTER TABLE clients DROP CONSTRAINT IF EXISTS clients_plan_check;
  ALTER TABLE clients ADD CONSTRAINT clients_plan_check 
    CHECK (plan IN ('starter', 'growth', 'scale', 'enterprise', 
                    'starter_annual', 'growth_annual', 'scale_annual', 'enterprise_annual',
                    'basic', 'professional', 'premium'));
  -- Nota: mantener legacy values durante transición
  ```

- [ ] **F2.3** Backfill plan keys en Multitenant `clients`
  ```sql
  -- Transaccional, con logging
  BEGIN;
  UPDATE clients SET plan = 'starter' WHERE plan = 'basic';
  UPDATE clients SET plan = 'growth' WHERE plan = 'professional';
  UPDATE clients SET plan = 'scale' WHERE plan = 'premium';
  COMMIT;
  -- Verificar: SELECT plan, COUNT(*) FROM clients GROUP BY plan;
  ```

- [ ] **F2.4** Actualizar CHECK constraint en Multitenant (remover legacy)
  ```sql
  ALTER TABLE clients DROP CONSTRAINT clients_plan_check;
  ALTER TABLE clients ADD CONSTRAINT clients_plan_check 
    CHECK (plan IN ('starter', 'growth', 'scale', 'enterprise', 
                    'starter_annual', 'growth_annual', 'scale_annual', 'enterprise_annual'));
  ```

- [ ] **F2.5** Alinear CHECK de `subscriptions.plan_key` en Admin DB con el mismo set

- [ ] **F2.6** Actualizar `OnboardingService` y `SubscriptionsService` en API para usar plan keys canónicos
  - Buscar: `grep -rn "basic\|professional\|premium" apps/api/src/`
  - Actualizar mappings/constants

- [ ] **F2.7** Resolver denormalización de `subscription_status`
  - Opción A (recomendada): Crear trigger en Admin DB
    ```sql
    CREATE OR REPLACE FUNCTION sync_subscription_status_to_account()
    RETURNS TRIGGER AS $$
    BEGIN
      UPDATE nv_accounts 
      SET subscription_status = NEW.status,
          updated_at = NOW()
      WHERE subscription_id = NEW.id;
      RETURN NEW;
    END;
    $$ LANGUAGE plpgsql;
    
    CREATE TRIGGER trg_sync_sub_status
    AFTER UPDATE OF status ON subscriptions
    FOR EACH ROW
    EXECUTE FUNCTION sync_subscription_status_to_account();
    ```
  - Opción B: Eliminar `nv_accounts.subscription_status` y hacer JOIN siempre

- [ ] **F2.8** Verificar integridad cross-DB: `clients.nv_account_id` matchea `nv_accounts.id`
  - Script de validación (ejecutar desde API):
    ```typescript
    // En un script one-off
    const adminAccounts = await adminDb.from('nv_accounts').select('id, slug');
    const backendClients = await backendDb.from('clients').select('id, nv_account_id');
    const orphans = backendClients.filter(c => 
      c.nv_account_id && !adminAccounts.find(a => a.id === c.nv_account_id)
    );
    console.log('Orphaned clients:', orphans);
    ```

#### DoD
- [ ] `SELECT DISTINCT plan FROM clients` solo retorna plan keys canónicos
- [ ] `SELECT a.subscription_status, s.status FROM nv_accounts a JOIN subscriptions s ON a.subscription_id = s.id WHERE a.subscription_status != s.status` retorna 0 rows
- [ ] Trigger de sync funciona: actualizar `subscriptions.status` → `nv_accounts.subscription_status` se actualiza automáticamente
- [ ] No hay orphan `clients.nv_account_id`

#### Riesgos y mitigación
| Riesgo | Mitigación |
|--------|-----------|
| API usa plan keys legacy en lógica de negocio | Buscar TODOS los usos antes de migrar; agregar mapping transitorio |
| Backfill falla a mitad | Ejecutar en transacción; verificar counts antes/después |
| Trigger race condition | El trigger es síncrono (AFTER UPDATE), no hay race dentro de la misma DB |

#### Rollback
```sql
-- Plan keys: re-agregar legacy values al CHECK
ALTER TABLE clients DROP CONSTRAINT clients_plan_check;
ALTER TABLE clients ADD CONSTRAINT clients_plan_check 
  CHECK (plan IN ('basic', 'professional', 'premium', 'starter', 'growth', 'scale', 'enterprise', ...));
-- Revertir backfill (si se tiene mapping inverso)
UPDATE clients SET plan = 'basic' WHERE plan = 'starter' AND created_at < '2026-02-10';
-- Trigger: DROP TRIGGER trg_sync_sub_status ON subscriptions;
```

---

### FASE 3: RLS / RBAC Ajustes Finos

**Tiempo estimado:** 3-5 días  
**Riesgo:** Medio (cambios de policies pueden romper acceso)  
**Impacto:** Cierra gaps de seguridad residuales

#### Tareas

- [ ] **F3.1** Auditar y documentar overlap de policies en `cart_items`
  - Las 5 policies actuales se OR-merge. Documentar el comportamiento resultante.
  - Si admin NO debe ver carts de otros users → remover `is_admin()` de `cart_items_select_tenant`
  - Si SÍ debe ver (para soporte) → documentar explícitamente

- [ ] **F3.2** Auditar `order_payment_breakdown` — 2 SELECT policies
  - `opb_select_admin` + `opb_select_tenant` → el resultado es que cualquier user autenticado del tenant puede leer
  - Decidir: ¿debería ser solo admin? Consolidar en 1 policy

- [ ] **F3.3** Verificar que `admin-analytics` Edge Function filtra por `client_id`
  - Actualmente lee TODOS los orders/payments sin scope → correcto para super admin dashboard
  - Documentar que es intencional: "Super admin analytics: cross-tenant by design"

- [ ] **F3.4** Verificar `admin-cors-origins` — validar que `client_id` enviado por payload existe
  ```typescript
  // Agregar validación:
  const { data: client } = await multi.from('clients').select('id').eq('id', client_id).single();
  if (!client) return errorResponse(400, 'Invalid client_id');
  ```

- [ ] **F3.5** (Opcional) Crear audit table para operaciones admin sobre datos de tienda
  ```sql
  CREATE TABLE IF NOT EXISTS admin_audit_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    admin_user_id UUID NOT NULL,
    client_id UUID NOT NULL,
    action TEXT NOT NULL, -- 'product_update', 'order_status_change', etc.
    table_name TEXT NOT NULL,
    record_id UUID,
    old_value JSONB,
    new_value JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
  );
  CREATE INDEX idx_admin_audit_client ON admin_audit_log(client_id, created_at DESC);
  ```

#### DoD
- [ ] Policies de `cart_items` y `order_payment_breakdown` documentadas con decisión explícita
- [ ] `admin-cors-origins` valida `client_id` antes de insertar
- [ ] (Si se implementa F3.5) Admin audit log captura operaciones admin en datos de tienda

#### Riesgos y mitigación
| Riesgo | Mitigación |
|--------|-----------|
| Cambio de RLS policy rompe acceso legítimo | Testear con user de cada rol (user, admin, super_admin) antes de deploy |
| Audit log agrega latencia | Insertar audit de forma asíncrona (o trigger AFTER) |

#### Rollback
```sql
-- Para cada policy cambiada: restaurar la versión anterior
DROP POLICY IF EXISTS <new_policy> ON <table>;
CREATE POLICY <old_policy> ON <table> ...;
```

---

### FASE 4: Optimización + Observabilidad

**Tiempo estimado:** 5-7 días  
**Riesgo:** Bajo  
**Impacto:** Escalabilidad y operabilidad a largo plazo

#### Tareas

##### TTL / Particionamiento

- [ ] **F4.1** Implementar limpieza de `email_jobs` (Multitenant)
  ```sql
  -- Cron job (pg_cron o script externo)
  DELETE FROM email_jobs WHERE created_at < NOW() - INTERVAL '90 days' AND status = 'sent';
  ```

- [ ] **F4.2** Implementar limpieza de `mp_idempotency` (Multitenant)
  ```sql
  DELETE FROM mp_idempotency WHERE created_at < NOW() - INTERVAL '30 days';
  ```

- [ ] **F4.3** Implementar limpieza de `tenant_payment_events` (Admin)
  ```sql
  -- Archivar a tabla _archive antes de borrar
  INSERT INTO tenant_payment_events_archive SELECT * FROM tenant_payment_events 
  WHERE received_at < NOW() - INTERVAL '12 months';
  DELETE FROM tenant_payment_events WHERE received_at < NOW() - INTERVAL '12 months';
  ```

- [ ] **F4.4** Implementar limpieza de `subscription_notification_outbox` (Admin)
  ```sql
  DELETE FROM subscription_notification_outbox 
  WHERE status = 'sent' AND sent_at < NOW() - INTERVAL '30 days';
  ```

##### Observabilidad

- [ ] **F4.5** Agregar tracking de email delivery en `email_jobs`
  ```sql
  ALTER TABLE email_jobs ADD COLUMN IF NOT EXISTS delivery_status TEXT;
  ALTER TABLE email_jobs ADD COLUMN IF NOT EXISTS delivery_error TEXT;
  ALTER TABLE email_jobs ADD COLUMN IF NOT EXISTS delivered_at TIMESTAMPTZ;
  ```

- [ ] **F4.6** (Opcional) Métricas de latencia por tenant
  - En API: middleware que registra request duration por `clientId`
  - Tabla (Admin DB): `tenant_request_metrics` con agregación horaria

##### Consolidación

- [ ] **F4.7** Consolidar los 2 clientes axios del Storefront
  - Mover lógica de custom domain de `api/client.ts` al `axiosConfig.jsx` principal
  - Deprecar `api/client.ts`
  - Migrar callers de `client.ts` al principal

- [ ] **F4.8** Refactorizar `AuthService` en 2 servicios separados
  - `TenantAuthService` → operaciones de auth de tienda (Multitenant DB)
  - `PlatformAuthService` → operaciones de auth de plataforma (Admin DB)
  - Eliminar la lógica `clientId === 'platform'` switch

- [ ] **F4.9** Implementar compensación/saga para dual-writes cross-DB
  - En `SubscriptionsService.syncAccountSubscriptionStatus()`:
    - Si Multitenant write falla → encolar reintento en `provisioning_jobs` (tipo `SYNC_STATUS`)
    - Worker reintenta con backoff exponencial
    - Alertar si falla 3 veces

#### DoD
- [ ] Cron de limpieza ejecutándose en schedule (verificar con `SELECT * FROM pg_cron.job`)
- [ ] No hay rows > 90 días en `email_jobs` con status 'sent'
- [ ] No hay rows > 30 días en `mp_idempotency`
- [ ] Storefront tiene un solo cliente axios
- [ ] AuthService separado en 2 servicios
- [ ] Dual-write tiene compensación con reintento

#### Riesgos y mitigación
| Riesgo | Mitigación |
|--------|-----------|
| Cron de limpieza borra datos necesarios | Archivar antes de borrar; verificar que los datos no se consultan |
| Refactor de AuthService rompe flows existentes | Tests E2E completos antes y después |
| Consolidación de axios rompe custom domains | Test con tienda en subdomain + tienda en custom domain |

#### Rollback
- Crons: desactivar en `pg_cron.job`
- Refactors: revert de commits
- Dual-write compensation: desactivar el worker sin desactivar la sync principal

---

## 3. Orden Recomendado de Ejecución (Quick Wins Primero)

```
Semana 1 ──────────────────────────────────────────────
  Día 1-2: FASE 0 (Hardening seguridad)
    → F0.1, F0.2, F0.3, F0.4 (auth en Edge Functions)
    → F0.5 (preview token)
    → F0.6 (deps update)
    → F0.7 (profiles reference)
    
Semana 2 ──────────────────────────────────────────────
  Día 3-5: FASE 1 (Constraints + Índices)
    → F1.1, F1.2 (NOT NULL en client_id)
    → F1.3, F1.4 (FKs en cart_items)
    → F1.5, F1.6 (índices compuestos)
    → F1.8, F1.9, F1.10 (índices Admin)
    → F1.11 (billing external_reference)

Semana 3-4 ────────────────────────────────────────────
  Día 6-12: FASE 2 (Plan keys + Backfills)
    → F2.1 (mapping)
    → F2.2, F2.3, F2.4, F2.5 (backfill + constraints)
    → F2.6 (API code updates)
    → F2.7 (trigger de subscription_status)
    → F2.8 (cross-DB validation)

Semana 5 ──────────────────────────────────────────────
  Día 13-17: FASE 3 (RLS / RBAC)
    → F3.1, F3.2 (policy cleanup)
    → F3.3 (documentación)
    → F3.4 (validation fix)
    → F3.5 (audit log - opcional)

Semana 6-7 ────────────────────────────────────────────
  Día 18-24: FASE 4 (Optimización)
    → F4.1-F4.4 (TTL/limpiezas)
    → F4.5-F4.6 (observabilidad)
    → F4.7-F4.9 (refactors)
```

---

## 4. Lista Priorizada (P0 → P3) con Estimación

| Hallazgo | Sev. | Fase | Tarea | Esfuerzo | Quick Win? |
|----------|------|------|-------|----------|-----------|
| H01 | P0 | F0 | F0.1 | S (2h) | ✅ |
| H02 | P0 | F0 | F0.2 | S (2h) | ✅ |
| H03 | P1 | F2 | F2.1-F2.6 | M (3-5d) | ❌ |
| H04 | P1 | F4 | F4.9 | M (2-3d) | ❌ |
| H05 | P1 | F0 | F0.3, F0.4 | S (2h) | ✅ |
| H06 | P1 | F4 | F4.8 | L (3-5d) | ❌ |
| H07 | P1 | F2 | F2.7 | M (1d) | ❌ |
| H08 | P2 | F3 | F3.1 | S (2h) | ✅ |
| H09 | P2 | F1 | F1.11 | S (1h) | ✅ |
| H10 | P2 | F0* | (en storefront) | S (1h) | ✅ |
| H11 | P2 | F4 | F4.7 | S (2h) | ✅ |
| H12 | P2 | F4 | F4.7 | M (1-2d) | ❌ |
| H13 | P2 | F0 | F0.6 | S (30min) | ✅ |
| H14 | P2 | F0 | F0.7 | S (30min) | ✅ |
| H15 | P3 | F4 | F4.3 | S (2h) | ✅ |
| H16 | P3 | F4 | F4.1 | S (1h) | ✅ |
| H17 | P3 | F1 | F1.8-F1.10 | S (1h) | ✅ |
| H18 | P2 | F0 | F0.5 | S (30min) | ✅ |

**Leyenda:** S = Small (< 4h), M = Medium (1-3 días), L = Large (3-5 días)

**Quick wins (aplicables en Fase 0-1, < 1 día total):** H01, H02, H05, H08, H09, H10, H11, H13, H14, H15, H16, H17, H18 = 13 de 18 hallazgos resolubles en la primera semana.

---

## 5. Plan de Pruebas

### 5.1 Smoke Tests (post cada fase)

```bash
# Fase 0: Verificar auth en Edge Functions
curl -X POST $ADMIN_URL/functions/v1/admin-create-client \
  -H "Content-Type: application/json" \
  -d '{"name":"test","slug":"test"}' \
  # Esperado: 401 Unauthorized

curl -X POST $ADMIN_URL/functions/v1/admin-create-client \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $VALID_ADMIN_TOKEN" \
  -d '{"name":"test","slug":"smoke-test-$(date +%s)","email":"smoke@test.com","plan":"starter"}' \
  # Esperado: 200/201

# Fase 1: Verificar constraints
psql $MULTITENANT_DB -c "INSERT INTO categories (name) VALUES ('test');"
  # Esperado: ERROR violates NOT NULL constraint on client_id

# Fase 2: Verificar plan keys
psql $MULTITENANT_DB -c "SELECT DISTINCT plan FROM clients;"
  # Esperado: solo starter, growth, scale, enterprise (+ annual variants)
```

### 5.2 Regresión Multi-tenant (crítica)

| Test | Descripción | Comando/Steps | Resultado esperado |
|------|------------|--------------|-------------------|
| **No fuga entre tenants** | User de tenant-A no puede acceder datos de tenant-B | E2E: login como user-A, request GET /products con slug de tenant-B | 403 o datos vacíos |
| **Admin scoped** | Admin de tenant-A no puede modificar productos de tenant-B | E2E: login como admin-A, PUT /products/:idB con slug de tenant-A | 404 |
| **Cross-tenant guard** | Storefront axios bloquea requests a otro tenant | Abrir tienda-A, injectar `X-Tenant-Slug: tienda-B` via DevTools | Request bloqueado por interceptor |
| **RLS funciona con anon key** | Client con anon key solo ve datos de su tenant | Supabase client con anon key, SELECT products WHERE client_id = 'otro-tenant' | 0 rows |

### 5.3 Pruebas de Pagos

| Test | Descripción | Resultado esperado |
|------|------------|-------------------|
| **No compras en preview** | Abrir /preview, intentar POST /mercadopago/* | Bloqueado por PreviewNetworkGuard (no llega al server) |
| **Webhook idempotente** | Enviar mismo webhook 3 veces | 1 sola actualización de order.status; 1 solo decrement de stock |
| **External reference scoped** | Webhook con external_ref de otro tenant | Rechazado: order no encontrada para ese client_id |
| **Precios desde backend** | Modificar precio en payload de checkout | Backend calcula total desde DB, ignora precio del frontend |

### 5.4 Pruebas de Onboarding

| Test | Descripción | Resultado esperado |
|------|------------|-------------------|
| **Provisioning idempotente** | Ejecutar provisioning job 2 veces para mismo account | Segunda ejecución: steps ya completados se skipean |
| **Slug claim atómico** | 2 requests simultáneos para mismo slug | Solo 1 éxito; el otro recibe error de conflicto |
| **Onboarding link one-time** | Usar link de onboarding 2 veces | Segunda vez: error "link ya usado" |
| **Draft expiration** | Draft con draft_expires_at pasado | No se puede avanzar; status queda en expired |

### 5.5 Tests E2E existentes a verificar

Referencia: `novavision-e2e/tests/`

```bash
cd novavision-e2e
npx playwright test --grep "tenant|payment|cart|auth|checkout"
```

Verificar que todos pasan después de cada fase. Si alguno falla, es blocker para avanzar a la siguiente fase.

---

## Apéndice: Script de Validación Post-Audit

```bash
#!/bin/bash
# validate-audit-fixes.sh
# Ejecutar después de cada fase para verificar estado

echo "=== Verificación de Edge Functions Auth ==="
# Test H01: admin-create-client sin auth
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$ADMIN_SUPABASE_URL/functions/v1/admin-create-client" \
  -H "Content-Type: application/json" \
  -d '{"test": true}')
if [ "$STATUS" = "401" ]; then echo "✅ H01: admin-create-client requiere auth"; 
else echo "❌ H01: admin-create-client accesible sin auth (status=$STATUS)"; fi

# Test H02: admin-delete-client sin auth
STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X POST "$ADMIN_SUPABASE_URL/functions/v1/admin-delete-client" \
  -H "Content-Type: application/json" \
  -d '{"test": true}')
if [ "$STATUS" = "401" ]; then echo "✅ H02: admin-delete-client requiere auth"; 
else echo "❌ H02: admin-delete-client accesible sin auth (status=$STATUS)"; fi

echo ""
echo "=== Verificación de DB Constraints ==="
echo "Ejecutar manualmente contra cada DB:"
echo ""
echo "-- Multitenant DB:"
echo "SELECT 'categories_null' as check, COUNT(*) FROM categories WHERE client_id IS NULL"
echo "UNION ALL SELECT 'banners_null', COUNT(*) FROM banners WHERE client_id IS NULL;"
echo ""
echo "-- Admin DB:"
echo "SELECT a.id, a.subscription_status, s.status"
echo "FROM nv_accounts a"
echo "LEFT JOIN subscriptions s ON a.subscription_id = s.id"
echo "WHERE a.subscription_status IS DISTINCT FROM s.status;"
echo ""
echo "SELECT DISTINCT plan FROM clients ORDER BY plan;"
```

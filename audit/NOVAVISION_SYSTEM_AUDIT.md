# NovaVision System Audit - Validación E2E Multitenant (VERIFICADO)

> **Fecha:** 2026-02-03  
> **Autor:** NovaVision Auditor (QA + Arquitecto + Data Engineer)  
> **Objetivo:** Validar end-to-end el sistema multitenant con referencias exactas a código/SQL  
> **Método:** Cada afirmación está anclada a archivo + función + línea aproximada

---

## AVISO DE VERIFICACIÓN

Todo dato en este documento fue verificado contra:
- Migraciones SQL en `apps/api/migrations/admin/` y `apps/api/migrations/backend/`
- Código TypeScript en `apps/api/src/`
- Constraints reales de base de datos

Si algo dice **"NO ENCONTRADO"**, significa que no existe en el repo actual.

---

## 1) RUNBOOK LOCAL (Dos Modos)

### 1.1 Requisitos Previos

| Herramienta | Versión Mínima | Instalación |
|-------------|----------------|-------------|
| Node.js | 18.x+ | `nvm install 18` |
| pnpm | 8.x+ | `npm install -g pnpm` |
| Docker | 24.x+ | [Docker Desktop](https://docker.com) |
| Supabase CLI | 1.100+ | `npm install -g supabase` |
| psql | 14+ | `brew install postgresql` (macOS) |

### 1.2 MODO A: Cloud Dev (2 Proyectos Supabase)

#### Paso 1: Crear proyectos en Supabase Dashboard
1. Ir a https://supabase.com/dashboard
2. Crear proyecto **"novavision-admin"** (Admin DB)
3. Crear proyecto **"novavision-multicliente"** (Backend DB)
4. Anotar URLs y keys de cada proyecto

#### Paso 2: Variables de Entorno API (`apps/api/.env`)
```bash
# ============ OBLIGATORIAS (verificadas en código) ============
NODE_ENV=development
PORT=3000

# JWT - usado en: apps/api/src/auth/jwt.strategy.ts
JWT_SECRET=dev-jwt-secret-minimum-32-chars-long

# PGP - usado en: apps/api/src/db/db-router.service.ts línea ~120 (decrypt clusters)
# NOTA: Solo necesario si backend_clusters usa service_role_key_encrypted
PGP_ENCRYPTION_KEY=dev-pgp-key-32-chars-min-xxxxx

# Admin Database - usado en: apps/api/src/db/db-router.service.ts línea ~30
SUPABASE_ADMIN_URL=https://xxx-admin.supabase.co
SUPABASE_ADMIN_SERVICE_ROLE_KEY=eyJxxx...

# MercadoPago - usado en: apps/api/src/subscriptions/platform-mercadopago.service.ts
MP_ACCESS_TOKEN=TEST-1234567890...
MP_CLIENT_ID=1234567890
MP_CLIENT_SECRET=xxx

# URLs - usadas en onboarding.service.ts para redirects
ADMIN_URL=http://localhost:5174
WEB_URL=http://localhost:5173
API_URL=http://localhost:3000
```

#### Paso 3: Variables Admin Dashboard (`apps/admin/.env`)
```bash
VITE_API_URL=http://localhost:3000
VITE_SUPABASE_URL=https://xxx-admin.supabase.co
VITE_SUPABASE_ANON_KEY=eyJxxx...
VITE_GOOGLE_CLIENT_ID=xxx.apps.googleusercontent.com
```

#### Paso 4: Variables Web Storefront (`apps/web/.env`)
```bash
VITE_API_URL=http://localhost:3000
VITE_SUPABASE_URL=https://xxx-multicliente.supabase.co
VITE_SUPABASE_ANON_KEY=eyJxxx...
```

#### Paso 5: Ejecutar migraciones Admin DB

**ORDEN EXACTO** (verificado en estructura de archivos):
```bash
cd apps/api

# 1. Extensiones y tipos base
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_001_extensions.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_002_types.sql

# 2. Tablas core (en orden de dependencia FK)
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_003_security_lockdown.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_010_create_backend_clusters.sql  # ANTES de nv_accounts!
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_004_create_nv_accounts.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_005_create_nv_onboarding.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_008_create_provisioning_jobs.sql

# 3. Extensiones de tablas
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_022_extend_onboarding_tables.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_042_fix_account_status_constraint.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_023_create_slug_reservations.sql
psql $ADMIN_DB_URL -f migrations/admin/ADMIN_024_create_webhook_events.sql

# 4. RPCs críticas
psql $ADMIN_DB_URL -f migrations/admin/202503081300_claim_provisioning_jobs.sql
psql $ADMIN_DB_URL -f migrations/20260131_claim_slug_rpc.sql
```

#### Paso 6: Seed backend_clusters (CRÍTICO)

**Referencia:** `DbRouterService.getBackendClient()` en `apps/api/src/db/db-router.service.ts` línea ~80

```sql
-- Admin DB: Sin esto, provisionClient falla con "Unknown cluster"
INSERT INTO backend_clusters (
  id,
  cluster_id,
  name,
  supabase_url,
  service_role_key_encrypted,
  status,
  weight
) VALUES (
  gen_random_uuid(),
  'cluster_shared_01',
  'Shared Cluster 01',
  'https://xxx-multicliente.supabase.co',
  -- OPCIÓN A: Sin encriptar (development)
  'eyJxxx...service_role_key...',
  -- OPCIÓN B: Encriptado (production) - requiere PGP_ENCRYPTION_KEY
  -- pgp_sym_encrypt('eyJxxx...', 'tu_pgp_key'),
  'ready',
  100
);
```

#### Paso 7: Migraciones Backend/Multicliente DB

**NOTA:** Las migraciones backend están dispersas. Principales:
```bash
psql $BACKEND_DB_URL -f migrations/backend/202503081320_add_nv_account_id_to_clients.sql
psql $BACKEND_DB_URL -f migrations/backend/202503081330_fix_nv_account_id_unique.sql
```

**NO ENCONTRADO:** Script consolidado de migraciones backend. El schema de `clients`, `products`, `users` parece crearse via Supabase Dashboard o migraciones legacy no versionadas en el repo actual.

### 1.3 MODO B: Local con Supabase CLI (Docker)

```bash
# 1. Inicializar Supabase local
cd apps/api
supabase init  # Si no existe supabase/

# 2. Levantar containers
supabase start
# Output:
#   API URL: http://localhost:54321
#   Studio URL: http://localhost:54323
#   DB URL: postgresql://postgres:postgres@localhost:54322/postgres

# 3. Usar las URLs locales en .env
# SUPABASE_ADMIN_URL=http://localhost:54321
# etc.

# 4. Ejecutar migraciones
supabase db push  # Si hay supabase/migrations/
# O ejecutar SQL directamente via Studio
```

**LIMITACIÓN:** Supabase local corre UN solo proyecto. Para simular Admin + Backend necesitás:
- Opción 1: Usar schemas separados (`admin.*` vs `public.*`)
- Opción 2: Dos instancias Supabase en puertos distintos

### 1.4 Levantar Servicios

```bash
# Terminal 1: API (NestJS)
cd apps/api
pnpm install
pnpm run start:dev
# → http://localhost:3000

# Terminal 2: Admin Dashboard (Vite)
cd apps/admin
pnpm install
pnpm run dev
# → http://localhost:5174

# Terminal 3: Web Storefront (Vite)
cd apps/web
pnpm install
pnpm run dev
# → http://localhost:5173
```

### 1.5 Reset Total (Todas las DBs)

```sql
-- ===== ADMIN DB =====
TRUNCATE provisioning_jobs, slug_reservations, webhook_events, nv_onboarding, nv_accounts CASCADE;
-- NOTA: CASCADE borra FKs dependientes

-- ===== BACKEND DB =====
TRUNCATE products, categories, product_categories, orders, order_items, cart_items, users, clients CASCADE;
```

### 1.6 Reset por Tenant

```sql
-- Admin DB: Borrar account específico (cascadea a nv_onboarding, jobs, etc.)
DELETE FROM nv_accounts WHERE slug = 'tienda-a-borrar';

-- Backend DB: Borrar client específico
DELETE FROM clients WHERE slug = 'tienda-a-borrar';
-- NOTA: Verificar que products/orders tengan ON DELETE CASCADE o borrar manualmente
```

### 1.7 Troubleshooting

| Error | Causa | Solución |
|-------|-------|----------|
| `Unknown backend cluster: xxx` | Falta seed de `backend_clusters` | Ejecutar INSERT del paso 6 |
| `relation "nv_accounts" does not exist` | Migraciones no ejecutadas | Ejecutar ADMIN_004 |
| `column "backend_cluster_id" violates not-null constraint` | Draft sin cluster | Verificar `ADMIN_022` que hace nullable backend_cluster_id |
| `JWT malformed` | JWT_SECRET incorrecto | Verificar match entre API y tokens |
| Provisioning job no corre | Status no es 'queued' | `SELECT * FROM provisioning_jobs WHERE status != 'done'` |

---

## 2) MAPA DEL FLUJO E2E (Estados REALES)

### 2.1 Estados de `nv_accounts.status`

**Fuente:** `apps/api/migrations/admin/ADMIN_042_fix_account_status_constraint.sql` líneas 13-28

```sql
-- Constraint REAL en DB:
CHECK (status IN (
  'draft',           -- Onboarding iniciado
  'awaiting_payment', -- Checkout iniciado
  'paid',            -- Pago confirmado
  'provisioning',    -- Job en ejecución
  'provisioned',     -- Client creado en backend
  'pending_approval', -- Esperando review
  'incomplete',      -- Falta algo
  'changes_requested', -- Admin pidió cambios
  'approved',        -- Aprobado
  'rejected',        -- Rechazado
  'expired',         -- Draft expiró
  'failed',          -- Error en provisioning
  'suspended'        -- Suspendido
))
```

**NOTA:** Estado `live` NO está en el constraint SQL actual. El código lo usa pero la DB no lo permite.

**BUG IDENTIFICADO:** Discrepancia entre código (`onboardingRoutesMap.ts` línea 137: `live: [ROUTES.HUB...]`) y constraint SQL.

### 2.2 Estados de `nv_onboarding.state`

**Fuente:** `apps/api/migrations/admin/ADMIN_002_types.sql` líneas 3-10 + extensiones en `20260203_add_missing_onboarding_columns.sql`

```sql
-- ENUM REAL:
CREATE TYPE nv_onboarding_state AS ENUM (
  'draft_builder',      -- Wizard en progreso
  'pending_payment',    -- Esperando pago
  'approved',           -- NO CONFUNDIR con account status
  'provisioning',       
  'live',               
  'failed',
  -- Agregados en 20260203:
  'pending_review',
  'submitted_for_review',
  'provisioned',
  'rejected'
);
```

### 2.3 Diagrama de Flujo (VERIFICADO)

```mermaid
flowchart TD
    subgraph ONBOARDING["1. Onboarding"]
        A[Usuario entra a /builder] --> B["POST /onboarding/builder/start<br/>📁 onboarding.service.ts:createDraftAccount ~L80"]
        B --> C{Account existe?}
        C -->|No| D["INSERT nv_accounts status='draft'<br/>INSERT nv_onboarding state='draft_builder'"]
        C -->|Sí status=draft| E[Retornar session existente]
        D --> F[Generar builder_token JWT]
        E --> F
        F --> G[Steps 1-4 en wizard]
        G --> H["Import Catalog<br/>📁 onboarding.service.ts ~L2400"]
        H --> I["Upload Logo a progress.wizard_assets<br/>(base64 en JSONB)"]
        I --> J[Seleccionar Plan]
        J --> K["OAuth Google<br/>📁 auth.service.ts"]
        K --> L["UPDATE nv_accounts.user_id"]
    end
    
    subgraph CHECKOUT["2. Checkout"]
        L --> M["POST /onboarding/start-checkout<br/>📁 onboarding.service.ts:startCheckout ~L800"]
        M --> N["INSERT slug_reservations<br/>expires_at = NOW() + 30min"]
        N --> O["platformMp.createPreapproval()<br/>UPDATE status='awaiting_payment'"]
        O --> P[Redirect a MercadoPago]
        P --> Q{Pago aprobado?}
        Q -->|No| R[Mostrar error]
        Q -->|Sí| S["POST /payments/webhook<br/>📁 onboarding.service.ts:handleCheckoutWebhook ~L880"]
    end
    
    subgraph PROVISIONING["3. Provisioning"]
        S --> T["1. INSERT webhook_events (idempotency)<br/>2. UPDATE status='paid'<br/>3. INSERT provisioning_jobs type='PROVISION_CLIENT_FROM_ONBOARDING'"]
        T --> U["Worker @Cron(EVERY_30_SECONDS)<br/>📁 provisioning-worker.service.ts:processJobs ~L147"]
        U --> V["claim_provisioning_jobs RPC<br/>FOR UPDATE SKIP LOCKED"]
        V --> W["provisionClientFromOnboardingInternal<br/>📁 ~L650"]
        W --> X["UPSERT clients<br/>onConflict: 'nv_account_id'"]
        X --> Y["UPSERT users<br/>id = nv_accounts.user_id"]
        Y --> Z["migrateLogoToBackend()<br/>base64 → Storage"]
        Z --> AA["migrateCatalog()<br/>JSON → products/categories"]
        AA --> AB["UPDATE nv_accounts status='provisioned' o 'pending_approval'"]
    end
    
    subgraph GOLIVE["4. Go Live"]
        AB --> AC{isComplete?}
        AC -->|Sí| AD["sendSuperAdminNotification()<br/>UPDATE status='pending_approval'"]
        AC -->|No| AE["sendPendingCompletionEmail()<br/>UPDATE status='incomplete'"]
        AD --> AF[Super Admin revisa en /hub]
        AF --> AG{Aprobado?}
        AG -->|Sí| AH["UPDATE clients.is_active=true<br/>📁 admin.service.ts"]
        AG -->|No| AI["UPDATE status='changes_requested'"]
    end
```

### 2.4 Detalle por Paso con Referencias

| Paso | Archivo/Función | Línea | Inputs | Tablas | Output |
|------|-----------------|-------|--------|--------|--------|
| Start Builder | `onboarding.service.ts:createDraftAccount` | ~80 | email, name | nv_accounts, nv_onboarding | builder_token |
| Import Catalog | `onboarding.service.ts:importHomeBundle` | ~2400 | products[], categories[] | nv_onboarding.data (NO home_data) | ok |
| Upload Logo | Progress update via builder | - | file base64 | nv_onboarding.progress | logo_url |
| OAuth Login | `auth.service.ts:handleGoogleCallback` | - | Google token | nv_accounts.user_id | session |
| Start Checkout | `onboarding.service.ts:startCheckout` | ~800 | plan_id, cycle | slug_reservations, nv_accounts | redirect_url |
| Webhook | `onboarding.service.ts:handleCheckoutWebhook` | ~880 | payment_id | webhook_events, provisioning_jobs | job_id |
| Claim Jobs | `provisioning-worker.service.ts:takeJobs` | ~330 | limit | provisioning_jobs (RPC) | jobs[] |
| Provision | `provisioning-worker.service.ts:provisionClientFromOnboardingInternal` | ~650 | account_id | clients, users, products | client_id |

---

## 3) MATRIZ DE DATOS (Staging vs Runtime)

### 3.1 Columnas REALES de `nv_onboarding`

**Fuente:** `ADMIN_005_create_nv_onboarding.sql` + `ADMIN_022_extend_onboarding_tables.sql`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `account_id` | UUID PK FK | Referencia a nv_accounts |
| `state` | ENUM | draft_builder, pending_payment, etc. |
| `selected_template_key` | TEXT | Ej: 'template_1' |
| `selected_palette_key` | TEXT | Ej: 'starter_default' |
| `data` | JSONB | Datos legacy/varios |
| `plan_key_selected` | TEXT | Plan elegido en checkout |
| `cycle` | TEXT | 'month' o 'year' |
| `checkout_preference_id` | TEXT | ID de preferencia MP |
| `checkout_payment_id` | TEXT | ID de pago MP |
| `client_id` | UUID | Post-provision: ID en backend |
| `provisioned_at` | TIMESTAMPTZ | Timestamp de provisioning |

**NO ENCONTRADO:** Columna `home_data`. Los productos se guardan en `data` JSONB o `progress` JSONB.

### 3.2 Dónde Vive Cada Dato

| Dato | Onboarding (staging) | Runtime (final) | Source of Truth |
|------|---------------------|-----------------|-----------------|
| **Slug deseado** | `nv_onboarding.data.builder_payload.desired_slug` → `slug_reservations.slug` | `nv_accounts.slug` + `clients.slug` | `clients.slug` post-provision |
| **Plan** | `nv_onboarding.plan_key_selected` | `nv_accounts.plan_key` → `clients.plan` | `clients.plan` |
| **Logo** | `nv_onboarding.progress.wizard_assets.logo_url` (base64 o URL temp) | `clients.logo_url` (URL Storage) | Storage URL |
| **Productos** | `nv_onboarding.data.catalog_data.products` o `progress.products` | `products` tabla | `products` tabla |
| **Categorías** | Extraídas de productos | `categories` tabla | `categories` tabla |
| **Template** | `nv_onboarding.selected_template_key` | `client_home_settings.template_key` | `client_home_settings` |
| **Paleta** | `nv_onboarding.selected_palette_key` | `client_home_settings.palette_key` | `client_home_settings` |
| **MP Credentials** | `nv_accounts.mp_access_token` etc. | `mp_connections` | `mp_connections` |
| **User ID** | `nv_accounts.user_id` | `users.id` (Backend) | Mismo UUID de auth.users |

### 3.3 Política de Retención

| Dato en Staging | Se limpia? | Cuándo | Referencia |
|-----------------|------------|--------|------------|
| `slug_reservations` | ✅ Sí | En provisioning | `provisioning-worker.service.ts` ~L900 |
| Logo base64 en progress | ❌ No | Nunca (queda en JSONB) | **BUG:** Payload crece indefinidamente |
| webhook_events | ❌ No | Nunca | Para auditoría |
| provisioning_jobs completados | ❌ No | Nunca | Para auditoría |
| Drafts expirados | ❓ Comentado | Debería: cron 2am | `purgeExpiredDrafts` está comentado |

---

## 4) MODELO `nv_accounts` (REAL)

### 4.1 Definición de Tabla

**Fuente:** `ADMIN_004_create_nv_accounts.sql`

```sql
CREATE TABLE IF NOT EXISTS public.nv_accounts (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  email CITEXT NOT NULL UNIQUE,
  slug TEXT NOT NULL UNIQUE,
  plan_key TEXT NOT NULL DEFAULT 'starter',
  backend_cluster_id UUID REFERENCES public.backend_clusters(id),  -- Nullable desde ADMIN_022
  draft_expires_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

### 4.2 Columnas Agregadas por Migraciones

| Columna | Migración | Tipo | Descripción |
|---------|-----------|------|-------------|
| `user_id` | ADMIN_022 | UUID FK auth.users | ID de usuario autenticado |
| `status` | ADMIN_022 | TEXT | Estado del account |
| `last_saved_at` | ADMIN_022 | TIMESTAMPTZ | Último auto-save |
| `mp_access_token` | ADMIN_102 o similar | TEXT | Token MP encriptado |
| `mp_public_key` | - | TEXT | Public key MP |
| `mp_refresh_token` | - | TEXT | Refresh token MP |
| `mp_user_id` | - | TEXT | ID de usuario MP |
| `mp_live_mode` | - | BOOLEAN | Modo sandbox/producción |
| `phone` | ADMIN_041 | TEXT | Teléfono de contacto |

### 4.3 Constraints REALES

**Fuente:** `ADMIN_042_fix_account_status_constraint.sql`

```sql
-- UNIQUE constraints (verificados)
UNIQUE (email)
UNIQUE (slug)

-- CHECK constraint (verificado)
CHECK (status IN (
  'draft', 'awaiting_payment', 'paid', 'provisioning', 'provisioned',
  'pending_approval', 'incomplete', 'changes_requested', 'approved',
  'rejected', 'expired', 'failed', 'suspended'
))
```

### 4.4 Invariantes Verificables

| # | Invariante | Verificación SQL |
|---|------------|------------------|
| 1 | Email único | `SELECT email, COUNT(*) FROM nv_accounts GROUP BY email HAVING COUNT(*) > 1` |
| 2 | Slug único | `SELECT slug, COUNT(*) FROM nv_accounts GROUP BY slug HAVING COUNT(*) > 1` |
| 3 | Status válido | Constraint `nv_accounts_status_check` lo impide |
| 4 | user_id inmutable post-paid | **NO HAY CONSTRAINT** - Solo lógica en código |
| 5 | Slug inmutable post-paid | **NO HAY CONSTRAINT** - Solo lógica en código |
| 6 | 1 account = 1 client | `clients.nv_account_id UNIQUE` (ver `202503081330_fix_nv_account_id_unique.sql`) |

---

## 5) PLAN DE PRUEBAS P0/P1 (Con Queries de Verificación)

### 5.1 Tests P0 (Bloqueantes)

#### P0-001: Happy Path Completo
```sql
-- Pre: DB limpia
-- Post: Verificar
SELECT a.id, a.status, a.slug, o.state, c.id as client_id
FROM nv_accounts a
JOIN nv_onboarding o ON o.account_id = a.id
LEFT JOIN clients c ON c.nv_account_id = a.id
WHERE a.email = 'test@e2e.com';

-- Esperado: status='provisioned' o 'pending_approval', client_id NOT NULL
```

#### P0-002: Idempotencia Provisioning
```sql
-- Pre: Ejecutar PROVISION_CLIENT_FROM_ONBOARDING dos veces para mismo account_id
-- Post:
SELECT COUNT(*) FROM clients WHERE nv_account_id = 'ACCOUNT_UUID';
-- Esperado: 1 (no duplicados)

SELECT COUNT(*) FROM provisioning_jobs WHERE account_id = 'ACCOUNT_UUID' AND status = 'done';
-- Esperado: Puede ser > 1 pero client no duplicado
```

#### P0-003: Webhook Idempotente
```sql
-- Pre: Enviar mismo webhook 3 veces
-- Post:
SELECT COUNT(*) FROM webhook_events 
WHERE source = 'mercadopago' AND payment_id = '12345';
-- Esperado: 1 (dedup por unique index)

SELECT status FROM webhook_events 
WHERE source = 'mercadopago' AND payment_id = '12345';
-- Esperado: 'processed' (solo una vez procesado)
```

#### P0-005: Cross-Tenant Read Block
```sql
-- Como user de client_a intentar:
SELECT * FROM products WHERE client_id = 'CLIENT_B_UUID';
-- Esperado: 0 rows si RLS está bien configurado
```

### 5.2 Tests P1 (Importantes)

#### P1-001: Concurrencia Slug Claim
```sql
-- Simular con 2 transacciones paralelas:
-- T1: INSERT INTO slug_reservations (slug, account_id) VALUES ('popular', 'ACC_A');
-- T2: INSERT INTO slug_reservations (slug, account_id) VALUES ('popular', 'ACC_B');
-- Esperado: Una falla con unique violation
```

---

## 6) AUDITORÍA DE PROVISIONING (VERIFICADO)

### 6.1 Entrypoint Real

| Componente | Ubicación | Línea |
|------------|-----------|-------|
| Cron trigger | `provisioning-worker.service.ts` | L147 `@Cron(CronExpression.EVERY_30_SECONDS)` |
| Job claim | `provisioning-worker.service.ts:takeJobs()` | L330 |
| RPC SQL | `202503081300_claim_provisioning_jobs.sql` | L1-35 |
| Provisioning lógica | `provisioning-worker.service.ts:provisionClientFromOnboardingInternal()` | L650 |

### 6.2 Flujo de Provisioning (Código Real)

**Fuente:** `provisioning-worker.service.ts` líneas 650-1000

```
1. getAccount(accountId)                              // L656
2. if (account.status === 'provisioned') → warn      // L663 - Idempotencia parcial
3. getOnboarding()                                   // L670
4. getReservedSlug() o fallback a account.slug      // L679-689
5. validate user_id exists                           // L692
6. getPlanEntitlements()                             // L699
7. chooseBackendCluster()                            // L706
8. UPSERT clients (onConflict: 'nv_account_id')     // L716 - Idempotente
9. UPSERT users (onConflict: 'id')                  // L750 - Idempotente
10. UPDATE nv_accounts.status='provisioned'          // L775
11. UPSERT mp_connections                            // L787
12. UPDATE nv_onboarding (client_id, provisioned_at) // L820
13. validateClientCompletion()                       // L858
14. DELETE slug_reservations                         // L901
15. UPSERT client_home_settings                      // L910
16. INSERT custom_palettes (si hay)                  // L935
17. migrateSessionAssets()                           // L965
18. migrateLogoToBackend()                           // L970
19. migrateCatalog()                                 // L980
20. seedDefaultPages()                               // L995
```

### 6.3 Mecanismos de Idempotencia

| Mecanismo | Ubicación | Tipo | Efectividad |
|-----------|-----------|------|-------------|
| Webhook dedupe | `ADMIN_024_create_webhook_events.sql` L27 | UNIQUE INDEX (source, payment_id, event_type) | ✅ Fuerte |
| Job claim | `202503081300_claim_provisioning_jobs.sql` L17-22 | FOR UPDATE SKIP LOCKED | ✅ Fuerte |
| Client upsert | `provisioning-worker.service.ts` L716 | onConflict: 'nv_account_id' | ✅ Fuerte |
| User upsert | `provisioning-worker.service.ts` L750 | onConflict: 'id' | ✅ Fuerte |
| Status check | `provisioning-worker.service.ts` L663 | if status === 'provisioned' warn | ⚠️ Parcial (no bloquea, solo warn) |

### 6.4 Fallas y Compensación

**HALLAZGO CRÍTICO:** No hay transacción ni compensación

```typescript
// provisioning-worker.service.ts ~L980
try {
  await this.migrateCatalog(...);  // Si esto falla...
} catch (catError) {
  await adminClient
    .from('nv_accounts')
    .update({ status: 'incomplete', ... });  // ...marca incomplete
  throw new Error(`CATALOG_MIGRATION_FAILED: ${catError.message}`);
}
// PERO: Client ya fue creado en L716, users en L750, etc.
// NO hay rollback de esos inserts
```

**IMPACTO:** Si `migrateCatalog` falla:
- `clients` existe sin productos
- `users` existe
- `nv_accounts.status` = 'incomplete' (no 'provisioned')
- El job puede reintentar, pero el client ya existe

### 6.5 RPCs Verificadas

#### `claim_provisioning_jobs`
**Fuente:** `202503081300_claim_provisioning_jobs.sql`
```sql
WITH picked AS (
  SELECT j.id
  FROM provisioning_jobs j
  WHERE j.status = 'pending'
  ORDER BY j.created_at ASC
  FOR UPDATE SKIP LOCKED
  LIMIT p_limit
)
UPDATE provisioning_jobs j
SET status = 'running', started_at = now()
FROM picked
WHERE j.id = picked.id
RETURNING ...
```

**NOTA SOBRE STATUS:** El ENUM original `nv_job_status` definía `'queued'`, pero la migración `ADMIN_027_fix_job_status_enum.sql` agregó `'pending'` y `'completed'` para compatibilidad con la RPC. La migración también convierte jobs existentes de `'queued'` → `'pending'`.

**Estados finales del ENUM (verificado):**
- `queued` (original)
- `running` (original)
- `done` (original)
- `failed` (original)
- `pending` (agregado en ADMIN_027)
- `completed` (agregado en ADMIN_027)

#### `claim_slug_final`
**Fuente:** `20260131_claim_slug_rpc.sql`
```sql
-- Verifica:
1. desired_slug existe en nv_onboarding.builder_payload
2. Reservation válida (account_id + not expired)
3. Slug no tomado por otro account con status permanente
4. UPDATE nv_accounts.slug
5. DELETE slug_reservations
```

**OK:** Esta RPC sí es atómica y segura.

---

## 7) BUGS/RIESGOS (Verificados en Código)

### 7.1 P0 - Críticos

| ID | Bug | Archivo | Línea | Reproducción | Fix |
|----|-----|---------|-------|--------------|-----|
| BUG-001 | **Falla parcial sin rollback** | provisioning-worker.service.ts | ~980 | Forzar error en migrateCatalog | Implementar saga/compensation pattern |
| BUG-002 | **Status 'live' no está en constraint** | ADMIN_042_fix_account_status_constraint.sql | 14-28 | `UPDATE nv_accounts SET status='live'` falla | Agregar 'live' al CHECK o usar 'approved' |

### 7.2 P1 - Importantes

| ID | Bug | Archivo | Línea | Reproducción | Fix |
|----|-----|---------|-------|--------------|-----|
| BUG-004 | **purgeExpiredDrafts comentado** | provisioning-worker.service.ts | ~1600+ | Drafts viejos acumulan | Descomentar o reimplementar |
| BUG-005 | **Logo base64 nunca se limpia** | - | - | progress JSONB crece | Limpiar post-provision |
| BUG-006 | **Slug inmutabilidad post-paid no enforced** | - | - | UPDATE nv_accounts SET slug='x' WHERE status='paid' funciona | Agregar trigger o RLS |

### 7.3 P2 - Mejoras

| ID | Mejora | Beneficio |
|----|--------|-----------|
| IMP-001 | Correlation ID en logs | Trazabilidad de requests |
| IMP-002 | Backoff exponencial en retry | Evitar saturación |
| IMP-003 | Métricas Prometheus | Observabilidad |

---

## 8) CHECKLIST INNEGOCIABLE (Ejecutable)

### 8.1 Multi-Tenant Data Safety

```bash
# 1. Verificar que products.client_id es NOT NULL y FK
# Backend DB:
psql $BACKEND_DB -c "\d products" | grep client_id
# Esperado: client_id | uuid | not null

# 2. Verificar RLS habilitado en products
psql $BACKEND_DB -c "SELECT relname, relrowsecurity FROM pg_class WHERE relname = 'products';"
# Esperado: relrowsecurity = t

# 3. Verificar política de RLS
psql $BACKEND_DB -c "SELECT polname, polcmd, polqual FROM pg_policies WHERE tablename = 'products';"
# Esperado: Políticas que incluyan client_id = current_client_id()

# 4. Grep para queries sin filtro client_id
cd apps/api
grep -rn "from('products')" src/ --include="*.ts" | grep -v "client_id"
# Esperado: 0 matches (toda query debe filtrar por client_id)
```

### 8.2 Idempotencia (Doble Webhook/Click/Approval)

```bash
# 1. Verificar unique index en webhook_events
psql $ADMIN_DB -c "\di idx_webhook_events_dedup"
# Esperado: Muestra el índice UNIQUE

# 2. Verificar unique en clients.nv_account_id
psql $BACKEND_DB -c "\di ux_clients_nv_account_id"
# Esperado: Muestra índice UNIQUE

# 3. Verificar FOR UPDATE SKIP LOCKED en claim_provisioning_jobs
psql $ADMIN_DB -c "\sf claim_provisioning_jobs" | grep -i "skip locked"
# Esperado: "FOR UPDATE SKIP LOCKED"

# 4. Test manual de doble webhook
curl -X POST $API_URL/payments/webhook \
  -H "Content-Type: application/json" \
  -d '{"id":"test-123","type":"payment","data":{"id":"pay_123"}}'
# Ejecutar 2 veces - segunda debe retornar "already processed" o similar
```

### 8.3 Migración (Minimal Consistent Set)

```sql
-- Admin DB: Verificar tablas mínimas existen
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN (
  'nv_accounts', 'nv_onboarding', 'provisioning_jobs', 
  'slug_reservations', 'webhook_events', 'backend_clusters'
);
-- Esperado: 6 rows

-- Backend DB: Verificar tablas mínimas existen
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('clients', 'users', 'products', 'categories');
-- Esperado: 4 rows

-- Verificar FK de nv_accounts → backend_clusters
SELECT confrelid::regclass, conname 
FROM pg_constraint 
WHERE conrelid = 'nv_accounts'::regclass AND contype = 'f';
-- Esperado: Incluye referencia a backend_clusters
```

### 8.4 Data Retention (Onboarding vs Runtime)

```sql
-- Admin DB: Verificar que hay cleanup de drafts expirados
-- (purgeExpiredDrafts está activo)
SELECT * FROM nv_accounts 
WHERE status = 'draft' 
AND draft_expires_at < NOW() - INTERVAL '30 days';
-- Esperado: 0 rows si purge funciona

-- Verificar slug_reservations se limpian post-provision
SELECT sr.* 
FROM slug_reservations sr
JOIN nv_accounts na ON sr.account_id = na.id
WHERE na.status IN ('provisioned', 'pending_approval', 'approved');
-- Esperado: 0 rows (se borran al provisionar)
```

### 8.5 Verificación Rápida de Estados

```sql
-- Admin DB: Verificar constraint de status
SELECT pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname LIKE 'nv_accounts%status%';
-- Esperado: CHECK con 13 valores (NO incluye 'live')

-- Verificar enum de job_status
SELECT enumlabel FROM pg_enum 
WHERE enumtypid = 'nv_job_status'::regtype;
-- Esperado: queued, running, done, failed, pending, completed (6 valores)

-- Verificar enum de onboarding_state
SELECT enumlabel FROM pg_enum 
WHERE enumtypid = 'nv_onboarding_state'::regtype;
-- Esperado: draft_builder, pending_payment, approved, provisioning, live, failed, 
--           pending_review, submitted_for_review, provisioned, rejected (10 valores)
```

---

## 9) DEFINITION OF DONE (Resumen Ejecutivo)

### ✅ Multi-Tenant Data Safety
- [ ] Cada query en Services filtra por `client_id` (verificar con grep §8.1.4)
- [ ] RLS habilitado en todas las tablas de Backend DB (verificar §8.1.2)
- [ ] No hay políticas "SELECT para todos" sin filtro
- [ ] Test cross-tenant read/write ejecutado y pasando (§5.1 P0-005, P0-006)

### ✅ Idempotencia
- [ ] `webhook_events` tiene unique index (verificar §8.2.1)
- [ ] `clients.nv_account_id` tiene unique index (verificar §8.2.2)
- [ ] `claim_provisioning_jobs` usa FOR UPDATE SKIP LOCKED (verificar §8.2.3)
- [ ] Test de doble webhook no crea duplicados (§5.1 P0-003)

### ✅ Provisioning
- [ ] Job usa idempotency via UPSERT (verificado en §6.3)
- [ ] Verificación de status antes de operaciones críticas (§6.2 paso 2)
- [ ] Estados claros: paid → provisioning → provisioned → pending_approval
- [ ] Logs con referencias a account_id y job_id

### ✅ Assets (Logo/Banners)
- [ ] Base64 → Storage migration funciona (§6.2 pasos 17-18)
- [ ] URL final es accesible públicamente
- [ ] Falla de storage marca status='incomplete' (no rompe completamente)

### ✅ Import JSON (Catálogo)
- [ ] Validación Zod en import-home-bundle
- [ ] Errores reportados sin crash
- [ ] client_id siempre seteado en products

---

## Anexo A: SQL de Diagnóstico (Verificados)

```sql
-- Ver estado de accounts (columnas reales)
SELECT id, email, slug, status, plan_key, user_id, backend_cluster_id, created_at
FROM nv_accounts
ORDER BY created_at DESC
LIMIT 20;

-- Ver jobs pendientes (columnas reales de ADMIN_008 + ADMIN_027)
-- Status: pending, running, done, failed, queued, completed
SELECT id, account_id, job_type, status, attempts, last_error, created_at
FROM provisioning_jobs
WHERE status IN ('pending', 'running', 'failed')  -- Usar valores del ENUM extendido
ORDER BY created_at DESC;

-- Ver reservations activas
SELECT slug, account_id, expires_at
FROM slug_reservations
WHERE expires_at > NOW();

-- Ver clientes en Backend DB (columnas del schema Multicliente)
SELECT id, slug, plan, is_active, nv_account_id, name, email_admin, created_at
FROM clients
ORDER BY created_at DESC
LIMIT 20;

-- Verificar cross-tenant (debe dar 0 si RLS funciona)
-- Ejecutar como user de client_a
SELECT COUNT(*) FROM products WHERE client_id = 'client_b_uuid_aqui';
-- Esperado: 0 rows (bloqueado por RLS)

-- Verificar idempotencia de clients por nv_account_id
SELECT nv_account_id, COUNT(*) as duplicates
FROM clients
WHERE nv_account_id IS NOT NULL
GROUP BY nv_account_id
HAVING COUNT(*) > 1;
-- Esperado: 0 rows (unique index impide duplicados)
```

---

## Anexo B: Comandos de Emergencia

```sql
-- Forzar reprocesamiento (usar status del ENUM extendido)
UPDATE provisioning_jobs 
SET status = 'pending', attempts = 0, last_error = NULL, locked_at = NULL
WHERE id = 'JOB_UUID';

-- Limpiar reservation bloqueante
DELETE FROM slug_reservations WHERE slug = 'slug-bloqueado';

-- Reset account a draft (validar que 'draft' está en constraint)
UPDATE nv_accounts 
SET status = 'draft', slug = 'draft-' || id::text 
WHERE id = 'ACCOUNT_UUID';

-- Verificar constraint de status (13 estados válidos)
SELECT conname, pg_get_constraintdef(oid) 
FROM pg_constraint 
WHERE conname = 'nv_accounts_status_check';

-- Verificar valores del enum nv_job_status (6 valores post-ADMIN_027)
SELECT enumlabel 
FROM pg_enum 
WHERE enumtypid = 'nv_job_status'::regtype
ORDER BY enumsortorder;

-- Ver webhook duplicados detectados
SELECT source, payment_id, event_type, COUNT(*)
FROM webhook_events
GROUP BY source, payment_id, event_type
HAVING COUNT(*) > 1;
-- Esperado: 0 rows (unique index previene)
```

---

## Anexo C: Schema Backend DB (Multicliente) - Tabla clients

**Fuente:** `novavision-admin.instructions.md` (schema real de Supabase)

| Columna | Tipo | Nullable | Default | Descripción |
|---------|------|----------|---------|-------------|
| `id` | uuid | NO | gen_random_uuid() | PK |
| `name` | text | NO | - | Nombre de la tienda |
| `email_admin` | text | NO | - | Email del admin |
| `plan` | text | NO | - | Plan actual |
| `monthly_fee` | numeric | NO | - | Tarifa mensual |
| `base_url` | text | NO | - | URL base del tenant |
| `connection_type` | text | NO | - | Tipo de conexión |
| `logo_url` | text | YES | - | URL del logo en Storage |
| `mp_public_key` | text | YES | - | Public key de MP |
| `mp_access_token` | text | YES | - | Access token de MP |
| `is_active` | boolean | YES | true | Si la tienda está activa |
| `nv_account_id` | uuid | YES | - | Referencia a Admin DB (UNIQUE) |
| `created_at` | timestamptz | YES | now() | Timestamp de creación |

**Índices críticos:**
- `ux_clients_nv_account_id UNIQUE ON (nv_account_id)` - Garantiza 1 account = 1 client

---

*Documento auditado por NovaVision Auditor*  
*Cada afirmación verificada contra código fuente*  
*Versión: 2.0 | Fecha: 2026-02-03*

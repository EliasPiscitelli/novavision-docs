# Baseline Evidence — Fase -1 Reconcilio de Evidencia

**Fecha:** 2026-02-09  
**Autor:** Agente Copilot  
**Objetivo:** Convertir supuestos del plan de remediación en hechos verificables, parametrizar el plan con nombres reales.  
**Gate:** Sin este documento aprobado, no se habilita Fase 0.

---

## Tabla de contenidos

1. [Inventario de tablas y scope (Multitenant DB)](#1-multitenant-db)
2. [Inventario de tablas y scope (Admin DB)](#2-admin-db)
3. [Divergencia de plan_key cross-DB](#3-plan-key)
4. [Storage: buckets, paths, isolation](#4-storage)
5. [Edge Functions: auth real por función](#5-edge-functions)
6. [API: rutas @AllowNoTenant()](#6-allownotenant)
7. [API: Tenant resolution real](#7-tenant-resolution)
8. [API: Guards completo](#8-guards)
9. [Secretos: exposición y leaks](#9-secrets)
10. [Hallazgos P0/P1 confirmados](#10-hallazgos)
11. [Tabla de alias: nombre real → nombre del plan](#11-alias)

---

## 1. Multitenant DB — Tablas y scope {#1-multitenant-db}

### 1.1 Tablas pre-existentes (no creadas en migraciones backend)

Estas tablas existen en la Multitenant DB pero fueron creadas fuera de las migraciones del repo (posiblemente desde Supabase Dashboard o seeds iniciales). Sus columnas y RLS están documentados en las instrucciones adjuntas.

| # | Tabla | Scope column | NOT NULL? | FK a clients? | RLS |
|---|-------|-------------|-----------|---------------|-----|
| 1 | `clients` | — (es la tabla raíz) | — | — | ✅ |
| 2 | `users` | `client_id` | NO (nullable) | NO (sin FK) | ✅ |
| 3 | `products` | `client_id` | YES* | NO (sin FK explícita en schema) | ✅ |
| 4 | `categories` | `client_id` | YES* | NO | ✅ |
| 5 | `product_categories` | `client_id` | YES* | NO | ✅ |
| 6 | `cart_items` | `client_id` | YES | NO | ✅ |
| 7 | `orders` | `client_id` | YES* | NO | ✅ |
| 8 | `payments` | `client_id` | YES* | NO | ✅ |
| 9 | `banners` | `client_id` | YES* | NO | ✅ |
| 10 | `contact_info` | `client_id` | YES* | NO | ✅ |
| 11 | `social_links` | `client_id` | YES* | NO | ✅ |
| 12 | `services` | `client_id` | YES* | NO | ✅ |
| 13 | `faqs` | `client_id` | YES* | NO | ✅ |
| 14 | `favorites` | `client_id` | YES* | NO | ✅ |
| 15 | `logos` | `client_id` | YES* | NO | ✅ |
| 16 | `cors_origins` | (varies) | — | — | ✅ |
| 17 | `email_jobs` | `client_id` | YES* | NO | ✅ |
| 18 | `mp_idempotency` | `client_id` | YES* | NO | ✅ |
| 19 | `order_payment_breakdown` | `client_id` | YES* | NO | ✅ |
| 20 | `client_extra_costs` | `client_id` | YES | NO | ✅ |
| 21 | `client_payment_settings` | `client_id` | YES | NO | ✅ |
| 22 | `client_mp_fee_overrides` | `client_id` | YES | NO | ✅ |
| 23 | `mp_fee_table` | — (catálogo global) | — | — | ✅ |
| 24 | `webhook_events` | — (sin scope) | — | — | ✅ |

> `*` = nullability inferida de la data de instrucciones; verificar con `SELECT count(*) FROM <table> WHERE client_id IS NULL` en producción.

### 1.2 Tablas creadas en migraciones backend

| # | Tabla | Scope column | NOT NULL? | FK a clients? | RLS | Hallazgo |
|---|-------|-------------|-----------|---------------|-----|----------|
| 25 | `client_secrets` | `client_id` (PK) | ✅ | ✅ CASCADE | **❌ NO** | ⚠️ P1: tokens encriptados sin RLS |
| 26 | `client_usage` | `client_id` (PK) | ✅ | ✅ CASCADE | ✅ | OK |
| 27 | `client_home_settings` | `client_id` (PK) | ✅ | ✅ CASCADE | **❌ NO** | ⚠️ P2: sin RLS en migraciones |
| 28 | `coupons` | `client_id` | ✅ | ✅ CASCADE | ✅ | Solo policy service_role |
| 29 | `home_sections` | `client_id` | ✅ | ✅ CASCADE | **❌ NO** | ⚠️ P2: sin RLS |
| 30 | `client_assets` | `client_id` | ✅ | ✅ CASCADE | **❌ NO** | ⚠️ P2: sin RLS |
| 31 | `tenant_payment_events` | **`tenant_id`** | **❌ NULLABLE** | **❌ Sin FK** | ✅ | ⚠️ P2: scope nullable y sin integridad referencial |

**Observaciones clave:**
- **Scope column es `client_id`** en todas las tablas excepto `tenant_payment_events` que usa **`tenant_id`**.
- Las tablas pre-existentes **no tienen FKs a `clients`** — la integridad referencial depende del backend.
- 4 tablas de migraciones backend **no tienen RLS habilitado**: `client_secrets`, `client_home_settings`, `home_sections`, `client_assets`.

### 1.3 CHECK constraint de `clients.plan` (Multitenant DB)

```sql
-- Migración: 20260207_update_clients_plan_check.sql
clients_plan_check: plan = ANY(ARRAY[
  'basic','professional','premium',
  'starter','starter_annual',
  'growth','growth_annual',
  'enterprise','enterprise_annual'
])
```

### 1.4 Enums creados en Multitenant DB

| Enum | Valores |
|------|---------|
| `discount_type_enum` | `percentage`, `fixed` |
| `client_publication_status` | `draft`, `pending_payment`, `pending_approval`, `provisioning`, `published`, `rejected`, `failed` |

### 1.5 Funciones clave en Multitenant DB

| Función | Propósito |
|---------|-----------|
| `_get_pgp_key()` | Lee `app.pgp_key` de session config |
| `encrypt_secret(text)` → bytea | AES256 PGP symmetric encrypt |
| `decrypt_secret(bytea)` → text | PGP symmetric decrypt |
| `protect_client_columns()` (trigger) | Bloquea cambios a `publication_status`, `is_published`, `is_active`, `has_demo_data` por non-service_role |
| `reset_monthly_usage()` | Resetea contadores mensuales (sin pg_cron — debe invocarse externamente) |

---

## 2. Admin DB — Tablas y scope {#2-admin-db}

### 2.1 Tablas activas (37 total)

| # | Tabla | PK | Scope column | RLS | Hallazgo |
|---|-------|-----|-------------|-----|----------|
| 1 | `nv_accounts` | `id` (uuid) | — (es la raíz) | ✅ | OK — tabla central, 60+ columnas |
| 2 | `nv_onboarding` | `account_id` | `account_id` FK CASCADE | ✅ | OK |
| 3 | `addon_catalog` | `addon_key` | — (catálogo global) | ✅ | OK |
| 4 | `account_addons` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 5 | `account_entitlements` | `account_id` | `account_id` FK CASCADE | ✅ | OK |
| 6 | `provisioning_jobs` | `id` (bigserial) | `account_id` FK CASCADE | ✅ | OK |
| 7 | `provisioning_job_steps` | `id` (bigserial) | `account_id` FK CASCADE | ✅ | OK |
| 8 | `mp_events` | `id` (bigserial) | — (sin scope tenant) | ✅ | ⚠️ Eventos MP sin scope account |
| 9 | `backend_clusters` | `cluster_id` (text) | — (infra global) | ✅ | Contiene `service_role_key` en text plano |
| 10 | `coupons` | `id` | — (catálogo global) | ✅ | OK |
| 11 | `coupon_redemptions` | `id` | `account_id` FK | ✅ | OK |
| 12 | `palette_catalog` | `palette_key` | — (catálogo global) | ✅ | OK |
| 13 | `custom_palettes` | `id` | `client_id` FK CASCADE | ✅ | OK |
| 14 | `client_themes` | `client_id` | `client_id` FK CASCADE | ✅ | OK |
| 15 | `nv_templates` | `key` | — (catálogo global) | ✅ | OK |
| 16 | `plans` | `plan_key` | — (catálogo global) | ✅ | OK |
| 17 | `nv_billing_events` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 18 | `slug_reservations` | `slug` | `account_id` FK CASCADE | ✅ | TTL 30min |
| 19 | `webhook_events` | `id` | — (sin scope) | ✅ | OK |
| 20 | `auth_handoff` | `id` | `client_id` (NO FK) | **❌ NO** | ⚠️ P2: tokens temporales sin RLS |
| 21 | `super_admins` | `id` | — (tabla global) | **❌ DISABLED** | ⚠️ P1: tabla de autorización sin RLS |
| 22 | `managed_domains` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 23 | `managed_domain_renewals` | `id` | via `managed_domain_id` FK | ✅ | OK |
| 24 | `subscriptions` | `id` | `account_id` FK CASCADE (UNIQUE) | ✅ | OK, 1 activa por account |
| 25 | `subscription_events` | `id` | `subscription_id` FK CASCADE | ✅ | OK |
| 26 | `subscription_notification_outbox` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 27 | `tenant_payment_events` | `id` | `tenant_id` (**NULLABLE, sin FK**) | ✅ | ⚠️ P2: duplicada en ambas DBs |
| 28 | `system_events` | `id` | `account_id` (nullable) | ✅ | OK — log global |
| 29 | `email_jobs` | `id` | `client_id` (text, NO FK) | ✅ (service_role only) | ⚠️ `client_id` es text, no uuid |
| 30 | `mp_connections` | `id` | `account_id` FK CASCADE (UNIQUE) | ✅ | Contiene `access_token` en text plano |
| 31 | `pro_projects` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 32 | `client_completion_checklist` | `id` | `account_id` FK CASCADE (UNIQUE) | ✅ | OK |
| 33 | `client_completion_events` | `id` | `account_id` FK CASCADE | ✅ | OK |
| 34 | `nv_account_settings` | `(nv_account_id, key)` | `nv_account_id` FK CASCADE | ✅ | OK |
| 35 | `dev_portal_whitelist` | `email` | — (global) | ✅ | OK |
| 36 | `lifecycle_events` | `id` | `account_id` FK CASCADE | ✅ (service_role only) | OK |
| 37 | `subscription_locks` | `account_id` | `account_id` (PK) | ✅ (service_role only) | OK |

### 2.2 CHECK constraints clave en Admin DB

**`nv_accounts.status` (Admin):**
```
draft, awaiting_payment, paid, provisioning, provisioned,
pending_approval, incomplete, changes_requested, approved,
rejected, expired, failed, suspended, live
```

**`subscriptions.plan_key` (Admin):**
```
starter, growth, pro, enterprise
```

**`subscriptions.billing_cycle` (Admin):**
```
monthly, annual
```

**`palette_catalog.min_plan_key` (Admin):**
```
starter, growth, pro, enterprise
```

### 2.3 Funciones clave en Admin DB

| Función | Tipo | Propósito |
|---------|------|-----------|
| `is_super_admin()` | boolean | Verifica `auth.email()` en `super_admins` |
| `enqueue_provisioning_job()` | uuid | Enqueue idempotente con `dedupe_key` |
| `claim_provisioning_jobs(batch_size)` | SETOF | SELECT FOR UPDATE SKIP LOCKED |
| `try_lock_subscription(account_id, ttl)` | boolean | Lock distribuido |
| `set_backend_cluster_db_url(cluster_id, url, key)` | void | Encripta db_url con PGP |
| `get_backend_cluster_db_url(cluster_id, key)` | text | Desencripta db_url |
| `dashboard_metrics(...)` | jsonb | Métricas unificadas |
| `finance_summary(...)` | jsonb | MRR, churn, forecast |

---

## 3. Divergencia de plan_key cross-DB {#3-plan-key}

| Fuente | Valores permitidos | Incluye billing cycle? |
|--------|-------------------|----------------------|
| **Multi DB** `clients.plan` CHECK | `basic, professional, premium, starter, starter_annual, growth, growth_annual, enterprise, enterprise_annual` | Sí (sufijo `_annual`) |
| **Admin DB** `subscriptions.plan_key` CHECK | `starter, growth, pro, enterprise` | No (separado en `billing_cycle`) |
| **Admin DB** `subscriptions.billing_cycle` CHECK | `monthly, annual` | — |
| **Admin DB** `plans` tabla (catálogo) | `starter, growth, pro, enterprise` (seeds) | — |
| **Admin DB** `palette_catalog.min_plan_key` CHECK | `starter, growth, pro, enterprise` | — |

### Conflictos detectados

| Conflicto | Detalle | Impacto |
|-----------|---------|---------|
| **`basic` / `professional` / `premium`** existen en Multi pero NO en Admin | Legacy plan keys sin mapping | Feature gating inconsistente |
| **`pro`** existe en Admin pero NO en Multi | Admin dice `pro`, Multi dice `professional` | Mismatch en onboarding |
| **`_annual` suffix** en Multi vs `billing_cycle` column en Admin | Dos representaciones del mismo concepto | Sync service debe mapear |
| **Multi no tiene `billing_cycle`** column | El ciclo se infiere del sufijo del plan key | Frágil, propenso a errores |

### Mapping canónico propuesto

| Canónico (Admin) | Multi DB legacy | Acción |
|-------------------|-----------------|--------|
| `starter` | `starter`, `basic` | Backfill `basic` → `starter` |
| `growth` | `growth`, `professional` | Backfill `professional` → `growth` |
| `pro` ← **renombrar a `scale`** | `premium` | Backfill `premium` → `scale` |
| `enterprise` | `enterprise` | OK |
| `monthly` / `annual` | Inferir de sufijo `_annual` | Agregar `billing_period` column en Multi |

---

## 4. Storage: buckets, paths, isolation {#4-storage}

### Bucket único: `product-images`

Definido en [apps/api/src/common/storage/storage.service.ts](apps/api/src/common/storage/storage.service.ts) L33. **Todos los assets** (productos, QR, banners, logos) van al mismo bucket.

### Path conventions (3 convenciones coexisten)

| Fuente | Patrón | Ejemplo |
|--------|--------|---------|
| `path-builder.ts` (nuevo) | `clients/{clientId}/products/{productId}/{variant}/{fileName}` | `clients/abc-123/products/def-456/main/foto.jpg` |
| `storage-path.helper.ts` (legacy) | `{clientId}/products/{uuid}_{originalName}` | `abc-123/products/uuid_foto.jpg` |
| `mercadopago.service.ts` (QR) | `{clientId}/orders/qr_{orderId}.png` | `abc-123/orders/qr_xyz.png` |

### Hallazgos de storage

| ID | Severidad | Hallazgo | Evidencia |
|----|-----------|----------|-----------|
| ST-1 | **P1** | **No hay Storage Policies en Supabase** — todo depende del `service_role` bypass + path convention | Sin policies encontradas en migraciones ni código |
| ST-2 | **P2** | **3 convenciones de path coexisten** — no hay validación de que el `clientId` en el path coincida con el tenant autenticado | [path-builder.ts](apps/api/src/common/storage/path-builder.ts) vs [storage-path.helper.ts](apps/api/src/common/utils/storage-path.helper.ts) |
| ST-3 | **P2** | **QR sin tenant isolation posible** — si `clientId` es null/vacío, el path es `orders/qr_xxx.png` (raíz) | [mercadopago.service.ts](apps/api/src/tenant-payments/mercadopago.service.ts) L870 |
| ST-4 | **INFO** | Bucket `product-images` probablemente público para lectura (usa `getPublicUrl()`) | — |

---

## 5. Edge Functions: autenticación real por función {#5-edge-functions}

### Shared auth helper: `_shared/wa-common.ts`

```typescript
// requireAdmin(req): JWT + rol admin/super_admin
// Verifica: adminClient.auth.getUser(token) → metadata.role → profiles.role → users.role
// CORS: Access-Control-Allow-Origin: * (en TODAS las funciones)
```

### Inventario completo

| # | Función | Auth | Muta DB? | Severidad |
|---|---------|------|----------|-----------|
| 1 | `admin-analytics` | ✅ JWT + rol | No (read) | OK |
| 2 | `admin-app-settings` | ✅ JWT + rol | Sí (upsert/delete) | OK |
| 3 | `admin-cors-origins` | ✅ JWT + rol | Sí (CRUD) | OK |
| 4 | **`admin-create-client`** | **❌ NINGUNA** | **Sí** (crea clients, auth users, cors, usage) | **🔴 P0** |
| 5 | **`admin-delete-client`** | **❌ NINGUNA** (HMAC solo en llamada saliente) | **Sí** (purge SQL, storage, auth) | **🔴 P0** |
| 6 | `admin-fetch-exchange-rate` | ❌ Ninguna | No (proxy API externa) | 🟢 Bajo |
| 7 | `admin-payments` | ✅ JWT + rol | Sí (CRUD payments) | OK |
| 8 | `admin-storage` | ✅ JWT + rol | Sí (delete, signed URLs) | OK |
| 9 | `admin-sync-client` | ✅ JWT + rol | Sí (upsert clients en Multi) | OK |
| 10 | `admin-sync-invoices` | ✅ JWT + rol | Sí (upsert invoices) | OK |
| 11 | **`admin-sync-usage`** | **❌ NINGUNA** | Sí (upsert usage/cursors) | **🟠 P1** |
| 12 | **`admin-sync-usage-batch`** | **❌ NINGUNA** | Sí (orquesta N syncs) | **🟠 P1** |
| 13 | `admin-wa-conversations` | ✅ `requireAdmin` | No (read) | OK |
| 14 | `admin-wa-messages` | ✅ `requireAdmin` | No (read) | OK |
| 15 | `admin-wa-send-reply` | ✅ `requireAdmin` | Sí (insert log, send WA) | OK |
| 16 | `admin-wa-update-conversation` | ✅ `requireAdmin` | Sí (update lead) | OK |
| 17 | `calendly-webhook` | ✅ HMAC firma Calendly | Sí (meetings, leads) | OK (webhook) |
| 18 | `multi-delete-client` | ✅ HMAC + anti-replay | Sí (purge) | OK (interno) |

### Supabase client key en cada función

**TODAS** las funciones que usan Supabase lo inicializan con **`SERVICE_ROLE_KEY`** (bypasean RLS). Esto es esperado para Edge Functions server-side, pero amplifica el riesgo de las funciones sin auth.

---

## 6. API: Rutas @AllowNoTenant() — inventario completo {#6-allownotenant}

### A nivel de CLASE (12 controllers)

| Controller | Path | Guard protector | Riesgo |
|------------|------|----------------|--------|
| `BillingController` | `/billing` | `PlatformAuthGuard` (parcial) | Medio — un método usa `AuthMiddleware` como guard (no funciona) |
| `FinanceController` | `/admin/finance` | `SuperAdminGuard` | OK |
| `AccountsController` | `/accounts` | **Ninguno** | ⚠️ Algunos métodos sin guard explícito |
| `AdminCouponsController` | `/admin/coupons` | `SuperAdminGuard` | OK |
| **`CouponsController`** | `/coupons` | **Ninguno** | **⚠️ P1**: `POST /coupons/validate` público sin auth |
| `SuperAdminEmailJobsController` | `/admin/super-emails` | `SuperAdminGuard` | OK |
| `AdminController` | `/admin` | `SuperAdminGuard` (por método) | OK |
| `AdminClientController` | `/admin/clients` | `SuperAdminGuard` | OK |
| `AdminManagedDomainController` | `/admin/managed-domains` | `SuperAdminGuard` | OK |
| `AdminAccountsController` | `/admin/accounts` | `SuperAdminGuard` | OK |
| `AdminRenewalsController` | `/admin/renewals` | `SuperAdminGuard` | OK |
| `MediaAdminController` | `/admin/media` | `RolesGuard` + `@Roles('admin', 'super_admin')` | OK |

### A nivel de MÉTODO — Endpoints sensibles sin guard

| Endpoint | Controller | Guard? | Riesgo |
|----------|-----------|--------|--------|
| `POST /onboarding/builder/start` | OnboardingController | **Ninguno** | ⚠️ P2: crea drafts sin captcha/rate limit |
| `GET /onboarding/resume?user_id=` | OnboardingController | **Ninguno** | **⚠️ P1**: lookup público por UUID |
| `POST /onboarding/checkout/webhook` | OnboardingController | **Ninguno** (firma MP opcional) | ⚠️ P1: warn si secret falta, no rechaza |
| `GET /onboarding/public/status` | OnboardingController | **Ninguno** | OK (público por diseño) |
| `GET /onboarding/plans` | OnboardingController | **Ninguno** | OK (catálogo público) |
| `POST /webhooks/mp/tenant-payments` | MpRouterController | **Ninguno** | OK (webhook, firma interna) |
| `POST /webhooks/mp/platform-subscriptions` | MpRouterController | **Ninguno** | OK (webhook, firma interna) |
| `POST /subscriptions/webhook` | SubscriptionsController | **Ninguno** | OK (webhook) |
| `POST /dev/seed-tenant` | DevSeedingController | **Ninguno** | ⚠️ P1: depende solo de NODE_ENV check |
| `GET /dev/tenants` | DevSeedingController | **Ninguno** | ⚠️ P1: expone lista de tenants |
| `DELETE /dev/tenants/:slug` | DevSeedingController | **Ninguno** | ⚠️ P1: borra tenants sin auth |
| `GET /dev/portal/health` | DevPortalController | **Ninguno** | OK (health check) |

---

## 7. Tenant resolution real {#7-tenant-resolution}

**Archivo:** [apps/api/src/guards/tenant-context.guard.ts](apps/api/src/guards/tenant-context.guard.ts) (446 líneas)

### Orden de resolución

1. **`@AllowNoTenant()` bypass** → `return true` inmediato
2. **Header `x-tenant-slug` o `x-store-slug`** → busca `nv_accounts.slug` en Admin DB → luego `clients` en Backend DB por `nv_account_id`
3. ~~Header `x-client-id`~~ → **REMOVIDO** (auditoría P0 previa)
4. **Custom domain** → `x-forwarded-host` o `host` → busca `nv_accounts.custom_domain`
5. **Subdominio** → extrae slug de `{slug}.novavision.lat`
6. ~~Fallback user metadata~~ → **REMOVIDO**
7. **Sin tenant** → `UnauthorizedException` (si no tiene `@AllowNoTenant`)

### Subdominios reservados

`admin, api, www, novavision, localhost, build, novavision-production`

### Lo que setea en `request`

- `request.clientId` — UUID del client en Multitenant DB
- `request.tenant` — `{ clientId, slug }` 
- `request.requestId` — UUID trazabilidad

### `gateStorefront()` — Bloqueos

| Condición | Código | Mensaje |
|-----------|--------|---------|
| `client.deleted_at` | 401 | `STORE_NOT_FOUND` |
| `client.is_active === false` | 403 | `STORE_SUSPENDED` |
| `client.maintenance_mode` | 403 | `STORE_MAINTENANCE` |
| `publication_status !== 'published'` | 403 | `STORE_NOT_PUBLISHED` |

---

## 8. Guards completo {#8-guards}

### Guards globales (APP_GUARD)

| Guard | Prioridad | Propósito |
|-------|-----------|-----------|
| `TenantContextGuard` | 1° | Resuelve clientId |
| `MaintenanceGuard` | 2° | Bloquea si tienda en mantenimiento |

### Guards per-route

| Guard | Auth type | Usado en |
|-------|-----------|---------|
| `SuperAdminGuard` | JWT + email en `super_admins` + `x-internal-key` (timing-safe) | `/admin/*` controllers |
| `BuilderSessionGuard` | JWT custom (`type=builder_session`) | `/onboarding/*` endpoints |
| `BuilderOrSupabaseGuard` | Builder JWT **O** Supabase JWT | `/dev/portal/*` |
| `ClientDashboardGuard` | Builder token → fallback por email | `/client-dashboard/*` |
| `RolesGuard` | `@Roles(...)` check en `req.user.role` | `MediaAdminController` |
| `TenantAuthGuard` | JWT Multicliente + `client_id` match | Endpoints específicos tenant |
| `PlatformAuthGuard` | JWT Admin + superadmin check | `/billing/admin/*` |
| `SubscriptionGuard` | Suscripción activa requerida | `/subscriptions/manage/upgrade` |
| `PlanAccessGuard` | Feature gating por `@PlanFeature(id)` | Endpoints con feature gates |
| `PlanLimitsGuard` | Límites cuantitativos por `@PlanAction(action)` | Endpoints con límites |
| `RateLimiterGuard` | Throttle por IP+path+clientId | Global (si registrado) |

### Auth Middleware — Rutas excluidas

El `AuthMiddleware` ([auth.middleware.ts](apps/api/src/auth/auth.middleware.ts)) excluye (no requiere `Authorization` header):

```
/, /products, /plans/catalog, /categories, /products/search, /products/:id
/auth/*, /health*, /favicon.ico
/mercadopago/webhook*, /mercadopago/notification
/tenant/bootstrap, /tenant/status
/onboarding/*, /settings/home*, /demo/seed, /dev/*
```

### Dual-project JWT validation

ValIda en orden:
1. **Multiclient** (SUPABASE_URL + SERVICE_ROLE_KEY) → `project: 'multiclient'`
2. **Admin** (SUPABASE_ADMIN_URL + ADMIN_SERVICE_ROLE_KEY) → `project: 'admin'`

---

## 9. Secretos: exposición y leaks {#9-secrets}

### 🚨 P0 CRÍTICO: Archivos .env con secretos REALES en Git

| Archivo | En Git? | Secretos reales |
|---------|---------|-----------------|
| `.env.bak` | **✅ TRACKEADO** | SERVICE_ROLE_KEY, PLATFORM_MP_ACCESS_TOKEN (producción), SMTP_PASS, POSTMARK_API_KEY |
| `.env.backup.manual` | **✅ TRACKEADO** | Mismos secretos |
| `.env.backup.20260111_203920` | **✅ TRACKEADO** | Mismos secretos |

**Secretos expuestos en historial Git:**

| Secreto | Tipo | Impacto |
|---------|------|---------|
| `SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...` (2 proyectos) | Service role | 🚨 Acceso total a DB, bypasea RLS |
| `PLATFORM_MP_ACCESS_TOKEN=APP_USR-336...` | MP PRODUCCIÓN | 🚨 Acceso real a Mercado Pago |
| `SUPABASE_SMTP_PASS=bxip jzcg cnvl cwpk` | Gmail App Password | 🚨 Enviar emails como NovaVision |
| `POSTMARK_API_KEY=d094f45c-...` | Postmark | 🚨 Enviar emails |

### Frontend — Servicio role check

| App | Exposición de service_role? | Verificado en |
|-----|----------------------------|---------------|
| `apps/web/src/` | ❌ No | ✅ Limpio |
| `apps/admin/src/` | ⚠️ Acepta como input en BackendClustersView (UI admin → backend) | Aceptable |
| `apps/web/.env.example` | ❌ Solo `VITE_API_URL`, `VITE_ENABLE_DEBUG` | ✅ Limpio |
| `apps/admin/.env.example` | ❌ Solo anon keys + advertencia "NEVER include SERVICE_ROLE_KEY" | ✅ Limpio |

### VITE_ variables sospechosas

| Variable | Riesgo |
|----------|--------|
| `VITE_ACCESS_KEY` (admin) | ⚠️ P2: "Access Key for Admin Panel" expuesto en bundle JS frontend |

### HMAC / Internal secrets

| Secret | Manejo | Evaluación |
|--------|--------|------------|
| `INTERNAL_ACCESS_KEY` | Env var, fail-closed en `SuperAdminGuard` | ✅ OK (verificar timing-safe) |
| `MP_WEBHOOK_SECRET` | **⚠️ P1**: `mercadopago.service.ts` solo hace `warn` sin rechazar; `mp-router.service.ts` sí rechaza en producción | Inconsistente |
| `DELETE_HMAC_SECRET` | Edge Function `multi-delete-client` usa HMAC + anti-replay (±5min) | ✅ OK |
| `CALENDLY_WEBHOOK_SIGNING_KEY` | HMAC-SHA256 con timing-safe comparison | ✅ OK |

---

## 10. Hallazgos P0/P1 confirmados con evidencia {#10-hallazgos}

### 🔴 P0 — Detener antes de Fase 0

| ID | Hallazgo | Evidencia | Acción |
|----|----------|-----------|--------|
| **P0-1** | **Secretos de producción en Git** (3 archivos .env backup trackeados) | `.env.bak`, `.env.backup.manual`, `.env.backup.20260111_203920` en repo | **Rotar TODOS los secretos** + `git filter-repo` + actualizar `.gitignore` |
| **P0-2** | **`admin-create-client` sin auth** — crea clients, auth users, escribe 5+ tablas | [admin-create-client/index.ts](apps/admin/supabase/functions/admin-create-client/index.ts) L145: no hay `requireAuth` | Agregar `requireAdmin` (importar de `_shared/wa-common.ts`) |
| **P0-3** | **`admin-delete-client` sin auth del caller** — operación destructiva e irreversible | [admin-delete-client/index.ts](apps/admin/supabase/functions/admin-delete-client/index.ts) L40: no verifica JWT | Agregar `requireAdmin` antes de procesar |

### 🟠 P1 — Fase 0

| ID | Hallazgo | Evidencia | Acción |
|----|----------|-----------|--------|
| **P1-1** | `admin-sync-usage` y `admin-sync-usage-batch` sin auth | [admin-sync-usage/index.ts](apps/admin/supabase/functions/admin-sync-usage/index.ts) L131 | Agregar `requireAdmin` o `x-internal-key` |
| **P1-2** | `GET /onboarding/resume?user_id=` público sin auth | [onboarding.controller.ts](apps/api/src/onboarding/onboarding.controller.ts) L975 | Agregar auth (BuilderSessionGuard o validar token) |
| **P1-3** | `POST /coupons/validate` público sin auth ni tenant | [coupons.controller.ts](apps/api/src/coupons/coupons.controller.ts) L7 | Quitar `@AllowNoTenant()` de clase o agregar guard |
| **P1-4** | `DevSeedingController` endpoints públicos | [dev-seeding.controller.ts](apps/api/src/dev/dev-seeding.controller.ts) L56-117 | Agregar guard que bloquee en producción |
| **P1-5** | Plan keys divergentes cross-DB (ver §3) | CHECK constraints incompatibles | Migración de normalización (Fase 2) |
| **P1-6** | `super_admins` con RLS **deshabilitado** | Admin DB migración `fix_super_admin_rls` | Re-habilitar con policies adecuadas |
| **P1-7** | `client_secrets` sin RLS | [BACKEND_001_create_client_secrets.sql](apps/api/migrations/backend/BACKEND_001_create_client_secrets.sql) | Habilitar RLS + policy `service_role` |
| **P1-8** | `mercadopago.service.ts` warn sin rechazar webhooks cuando falta `MP_WEBHOOK_SECRET` | Inconsistente con `mp-router.service.ts` que sí rechaza | Unificar: rechazar siempre en producción |

### 🟡 P2

| ID | Hallazgo |
|----|----------|
| P2-1 | `home_sections`, `client_assets`, `client_home_settings` sin RLS |
| P2-2 | `tenant_payment_events.tenant_id` nullable y sin FK (en ambas DBs) |
| P2-3 | 3 convenciones de storage paths coexisten |
| P2-4 | `auth_handoff` sin RLS |
| P2-5 | `VITE_ACCESS_KEY` potencialmente expuesto en bundle frontend |
| P2-6 | `publication_status` — conflicto text vs enum (2 CHECK + 1 enum para la misma columna) |
| P2-7 | UNIQUE indexes duplicados en `products(client_id, sku)` (3 variantes), `categories(client_id, name)` (2 variantes) |
| P2-8 | `mp_connections.access_token` en text plano en Admin DB |
| P2-9 | `backend_clusters.service_role_key` en text plano |

---

## 11. Tabla de alias: nombre real → nombre del plan {#11-alias}

El plan de remediación v1 usaba nombres que no coinciden exactamente con el código real. Acá está el mapping:

| Alias en plan v1 | Nombre real en código | Dónde |
|-------------------|----------------------|-------|
| "columna `client_id` en `categories`" | ✅ Correcto: `categories.client_id` | Multitenant DB |
| "tabla `clients` con `plan`" | ✅ Correcto: `clients.plan` con CHECK constraint | Multitenant DB |
| "`admin-create-client` sin auth" | ✅ Confirmado: zero auth | `supabase/functions/admin-create-client/index.ts` |
| "`admin-delete-client` sin auth" | ✅ Confirmado: zero auth caller-side | `supabase/functions/admin-delete-client/index.ts` |
| "scope=client_id en todas las tablas" | **⚠️ Parcialmente incorrecto**: `tenant_payment_events` usa `tenant_id` | Ambas DBs |
| "categories.client_id nullable" | **Requiere verificar en prod** — migraciones no muestran nullability original | SQL check needed |
| "`clients.plan` CHECK values" | Confirmado: `basic,professional,premium,starter,starter_annual,growth,growth_annual,enterprise,enterprise_annual` | Multi DB |
| "`subscriptions.plan_key` CHECK" | Confirmado: `starter,growth,pro,enterprise` | Admin DB |

### Nombres que **no existían** pero el plan v1 asumía

| Nombre asumido | Realidad |
|---------------|----------|
| `plan_definitions` tabla | Fue renombrada a `plans` (ADMIN_043) |
| `outbox` table | No existe aún — debe crearse en Fase 3 |
| `admin_actions_audit` | No existe — debe crearse en Fase 4 |

---

## Resumen ejecutivo

| Categoría | Resultado |
|-----------|-----------|
| **Tablas Multitenant DB** | 31 tablas (24 pre-existentes + 7 de migraciones) |
| **Tablas Admin DB** | 37 tablas activas + 5 eliminadas |
| **Scope column** | `client_id` en 99% de tablas; `tenant_id` solo en `tenant_payment_events` |
| **Tablas sin RLS (Multitenant)** | 4: `client_secrets`, `client_home_settings`, `home_sections`, `client_assets` |
| **Tablas sin RLS (Admin)** | 2: `super_admins` (disabled), `auth_handoff` |
| **Edge Functions sin auth** | 4: `admin-create-client`, `admin-delete-client`, `admin-sync-usage`, `admin-sync-usage-batch` |
| **Endpoints API sin auth** | 5 con riesgo real: resume, coupons validate, dev/* (3 endpoints) |
| **Plan key divergencia** | SÍ: 9 valores en Multi vs 4 en Admin + billing_cycle separado |
| **Storage isolation** | Solo por convención de path (3 convenciones), sin Storage Policies |
| **Secretos en Git** | 🚨 3 archivos .env backup con secretos de producción trackeados |

**Gate status: Fase -1 COMPLETA. Los datos están parametrizados para la Fase 0.**

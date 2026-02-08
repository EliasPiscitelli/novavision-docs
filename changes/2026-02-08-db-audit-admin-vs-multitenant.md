# Auditoría de Arquitectura de Datos — Admin DB vs Multitenant DB

**Fecha:** 2026-02-08  
**Autor:** Agente Copilot (Principal Data Architect + Security Auditor)  
**Rama de referencia:** `feature/automatic-multiclient-onboarding` (API), `feature/multitenant-storefront` (Web)  
**Alcance:** Admin DB (Supabase Admin project) + Multitenant DB (Supabase Backend project) + API NestJS + Admin Frontend Edge Functions + Web Storefront

---

## 0. Resumen Ejecutivo

### Estado general: 🟡 AMARILLO

La arquitectura multi-tenant es **sólida en su diseño central**: el Backend filtra por `client_id` en todas las queries de tienda, RLS está habilitado en ambas DBs, y el Storefront tiene protección cross-tenant a nivel axios interceptor. Sin embargo, existen **vulnerabilidades P0 en Edge Functions del Admin** (endpoints sin autenticación), **inconsistencias de plan keys entre DBs**, y **riesgos de dual-write sin rollback** en operaciones cross-DB.

### Top 5 Riesgos

| # | Sev. | Riesgo | DB/Capa |
|---|------|--------|---------|
| 1 | **P0** | Edge Function `admin-create-client` sin autenticación: cualquier actor con la URL + anon key puede crear clientes | Admin EF |
| 2 | **P0** | Edge Function `admin-delete-client` sin autenticación del caller: permite borrar clientes sin verificar identidad | Admin EF |
| 3 | **P1** | Dual-write cross-DB (Admin + Multitenant) sin transacción distribuida ni rollback automático en `SubscriptionsService.syncAccountSubscriptionStatus()` | API |
| 4 | **P1** | Plan keys divergentes: `nv_accounts` CHECK (starter/growth/scale), `subscriptions` CHECK (+enterprise/annual), `clients` CHECK (basic/professional/premium/starter/growth/enterprise) — inconsistencia puede romper joins cross-DB | Ambas DBs |
| 5 | **P1** | `admin-sync-usage` y `admin-sync-usage-batch` sin autenticación: escritura de datos de uso sin verificación de caller | Admin EF |

### Recomendación global

1. **Inmediato (esta semana):** Agregar `requireAuth()` a las 4 Edge Functions sin auth (P0).
2. **Corto plazo (2 semanas):** Normalizar plan keys con un ENUM compartido y migración de datos.
3. **Mediano plazo (1 mes):** Implementar patrón saga/compensación para dual-writes cross-DB.

---

## 1. Contexto y Alcance

### Qué se auditó
- **Admin DB:** Tablas, índices, RLS policies, RPCs, enums (via migraciones en `migrations/admin/` e instrucciones de contexto)
- **Multitenant DB:** Tablas, índices, RLS policies, helper functions (via migraciones en `migrations/backend/` y root, más instrucciones de contexto)
- **API NestJS:** `src/supabase/`, `src/db/`, `src/auth/`, `src/guards/`, `src/onboarding/`, `src/subscriptions/`, `src/tenant-payments/`, `src/billing/`, `src/finance/`, `src/products/`, `src/orders/`, `src/cart/`
- **Admin Frontend:** 17 Edge Functions en `supabase/functions/`, servicios en `src/services/`
- **Web Storefront:** Tenant resolution, axios config, auth flow, cart/checkout, preview mode, Netlify edge functions

### Qué NO se auditó (fuera de alcance)
- Ejecución real de queries contra las DBs (no se tenía acceso directo a `pg_catalog`/`information_schema`)
- Performance real de queries (no se ejecutaron `EXPLAIN ANALYZE`)
- Logs de producción (no se tenía acceso a Railway/Netlify logs)
- WhatsApp integration en detalle (Edge Functions WA son secundarias)
- Tests E2E existentes (se auditó el codebase, no su cobertura)

### Suposiciones explícitas

| ID | Suposición | Cómo validar |
|----|-----------|--------------|
| S1 | Las migraciones en `migrations/admin/` se ejecutan contra Admin DB y las de `migrations/backend/` contra Multitenant DB | Verificar en `run_migrations.sh` y deployment scripts |
| S2 | El Backend multi-cluster (via `backend_clusters`) actualmente tiene un solo cluster activo (`cluster_shared_01`) | Ejecutar: `SELECT cluster_key, is_active FROM backend_clusters` en Admin DB |
| S3 | La tabla `profiles` referenciada en `_shared/wa-common.ts` de Edge Functions no existe | Ejecutar: `SELECT 1 FROM information_schema.tables WHERE table_name = 'profiles'` en Admin DB |
| S4 | Los `VITE_PREVIEW_TOKEN` en producción están correctamente configurados en Netlify | Verificar en Netlify UI: Site settings → Build & deploy → Environment variables |
| S5 | El `SUPABASE_CLIENT` (anon key) del API inyectado por `SupabaseModule` apunta al mismo proyecto que `SUPABASE_ADMIN_CLIENT` (service_role) | Verificar que `SUPABASE_URL` sea igual en ambos providers |

---

## 2. Arquitectura Actual

### Diagrama de componentes

```
┌─────────────────────┐    ┌────────────────────────┐
│  Admin Frontend      │    │  Web Storefront        │
│  (Vite + React)      │    │  (Vite + React)        │
│  Netlify             │    │  Netlify               │
│                      │    │                        │
│  ┌────────────────┐  │    │  Headers:              │
│  │ Edge Functions  │  │    │  x-tenant-slug: {slug} │
│  │ (17 funciones)  │  │    │  Authorization: Bearer │
│  └──────┬─────────┘  │    └──────────┬─────────────┘
│         │             │               │
│  Admin Supabase Auth  │    Multitenant Supabase Auth
│  (PKCE + service_role)│    (PKCE + anon key)
└─────────┬─────────────┘               │
          │  ┌──────────────────────────┐│
          │  │   NestJS API (Railway)    ││
          └──┤                          ├┘
             │  AuthMiddleware           │
             │  ┌─ JWT validation (dual)│
             │  └─ Role extraction      │
             │                          │
             │  TenantContextGuard      │
             │  ┌─ slug → nv_accounts   │
             │  │  (Admin DB lookup)    │
             │  └─ slug → clients       │
             │     (Backend DB lookup)  │
             │                          │
             │  SupabaseModule (legacy) │
             │  ┌─ SUPABASE_CLIENT     ─┼──┐
             │  ├─ SUPABASE_ADMIN_CLIENT┼──┤─── Multitenant DB
             │  ├─ SUPABASE_ADMIN_DB   ─┼──┤    (Supabase Project B)
             │  └─ SUPABASE_METERING   ─┼──┤
             │                          │  │
             │  DbRouterService (modern)│  │
             │  ┌─ getAdminClient()    ─┼──┼─── Admin DB
             │  └─ getBackendClient()  ─┼──┘    (Supabase Project A)
             │     (multi-cluster!)     │
             └──────────────────────────┘
                    │                │
         ┌──────────┘                └──────────┐
         ▼                                      ▼
┌─────────────────────────┐    ┌─────────────────────────────────┐
│       ADMIN DB           │    │       MULTITENANT DB             │
│  (Control Plane)         │    │  (Data Plane / Tiendas)          │
├─────────────────────────┤    ├─────────────────────────────────┤
│ Dominio: Cuentas/Billing │    │ Dominio: Tiendas/E-commerce      │
│                          │    │                                  │
│ nv_accounts (central)    │    │ clients (tenant config)          │
│ nv_onboarding            │    │ users (compradores/admins)        │
│ subscriptions            │    │ products, categories              │
│ nv_billing_events        │    │ orders, payments, cart_items      │
│ provisioning_jobs/steps  │    │ banners, logos, faqs, services    │
│ backend_clusters         │    │ client_payment_settings           │
│ plans                    │    │ client_extra_costs                │
│ super_admins             │    │ mp_fee_table, mp_idempotency      │
│ subscription_locks       │    │ order_payment_breakdown           │
│ subscription_*           │    │ email_jobs, favorites             │
│ lifecycle_events         │    │ cors_origins, client_secrets      │
│ tenant_payment_events    │    │ client_usage (counters)           │
│ mp_events                │    │ contact_info, social_links        │
│ nv_templates             │    │ qr_codes                         │
│ palette_catalog          │    │                                  │
│ coupons/redemptions      │    │ Schemas:                         │
│ slug_reservations        │    │   public (tablas de negocio)     │
│ auth_bridge_codes        │    │   reporting (mat. views + RPCs)  │
│ managed_domains          │    │   admin_tools (purge RPCs)       │
│ addon_catalog            │    │                                  │
│ account_addons           │    │ RLS: current_client_id(),        │
│ account_entitlements     │    │   is_admin(), is_super_admin()   │
│ email_jobs (admin)       │    │                                  │
│ webhook_events           │    │ Storage buckets:                 │
│ dev_portal_whitelist     │    │   product-images, banners,       │
│ client_completion_*      │    │   logos, services, dni-uploads   │
│                          │    │                                  │
│ RLS: REVOKE ALL anon,    │    │                                  │
│   service_role bypass,   │    │                                  │
│   super_admin policies   │    │                                  │
└─────────────────────────┘    └─────────────────────────────────┘
```

### Integración entre DBs

| Punto de integración | Dirección | Mecanismo | ID compartido |
|---------------------|-----------|-----------|---------------|
| Provisioning | Admin → Multitenant | `OnboardingService` crea row en `clients` (Multitenant) tras aprobar en Admin | `nv_accounts.id` ↔ `clients.nv_account_id` |
| Suscripción sync | Admin → Multitenant | `SubscriptionsService.syncAccountSubscriptionStatus()` escribe `clients.publication_status` | `nv_accounts.id` → busca `clients.nv_account_id` |
| Tenant resolution | Read Admin + Multitenant | `TenantContextGuard` busca slug en `nv_accounts` (Admin) + `clients` (Multitenant) | slug como key natural |
| Usage sync | Multitenant → Admin | Edge Function `admin-sync-usage` vía HMAC-signed HTTP | `client_id` (Multitenant) ↔ `nv_accounts.id` (Admin) |
| Delete client | Admin → Multitenant | Edge Function `admin-delete-client` → `multi-delete-client` via HMAC | `client_id` |
| MP credentials | Admin ↔ Multitenant | `MpOauthService` lee `nv_accounts` (Admin), escribe `client_secrets` (Multitenant) | `nv_account_id` |

---

## 3. Hallazgos (Tabla Consolidada)

| ID | Sev. | Prob. | DB/Capa | Objeto | Descripción | Impacto | Evidencia | Fix sugerido | Esfuerzo |
|----|------|-------|---------|--------|-------------|---------|-----------|-------------|----------|
| H01 | **P0** | Alta | Admin EF | `admin-create-client` | **Sin autenticación.** No valida Bearer token ni rol. Cualquier actor con URL + anon key puede crear clientes en ambas DBs. | Creación no autorizada de tenants, consumo de recursos, posible DoS. | `supabase/functions/admin-create-client/index.ts` — ausencia de `requireAuth()` al inicio; README confirma `Authorization: Bearer <anon-key>` | Agregar `requireAdmin(req)` de `_shared/wa-common.ts` al inicio del handler | S |
| H02 | **P0** | Alta | Admin EF | `admin-delete-client` | **Sin autenticación del caller.** HMAC solo protege la llamada interna a `multi-delete-client`, no quién invoca `admin-delete-client`. | Borrado de tenants sin autorización. | `supabase/functions/admin-delete-client/index.ts` — sin check de Bearer/rol | Agregar `requireAdmin(req)` | S |
| H03 | **P1** | Alta | Ambas DBs | `nv_accounts.plan_key` vs `clients.plan` | **Plan keys divergentes.** Admin: CHECK (starter, growth, scale). Multitenant: CHECK (basic, professional, premium, starter, growth, enterprise + annual). `subscriptions`: (starter, growth, scale, enterprise + annual). No hay enum unificado. | Joins cross-DB fallan si un plan existe en una DB pero no en otra. Provisioning puede insertar plan inválido. | `migrations/admin/` → `nv_accounts` CHECK vs `migrations/backend/` → `clients.plan` CHECK | Unificar en tabla `plans` (Admin DB) como source of truth. Migrar `basic`→`starter`, `professional`→`growth`, `premium`→`scale` en Multitenant. | M |
| H04 | **P1** | Media | API | `SubscriptionsService.syncAccountSubscriptionStatus()` | **Dual-write sin compensación.** Escribe en Admin DB (`nv_accounts`) y luego en Multitenant DB (`clients.publication_status`). Si la segunda escritura falla, el estado queda inconsistente. Solo loguea el error. | Cuenta activa en Admin pero tienda aún pausada en Multitenant (o viceversa). | `src/subscriptions/subscriptions.service.ts` — try/catch con log pero sin rollback | Implementar patrón saga: si falla la Multitenant write, revertir la Admin write o encolar reintento. | M |
| H05 | **P1** | Media | Admin EF | `admin-sync-usage`, `admin-sync-usage-batch` | **Sin autenticación.** Escriben datos de uso en Admin DB sin validar al caller. | Actor malicioso podría inyectar datos de uso falsos (afecta facturación). | `supabase/functions/admin-sync-usage/index.ts`, `admin-sync-usage-batch/index.ts` — sin check auth | Agregar validación de header secreto (`x-internal-key`) o `requireAdmin()` | S |
| H06 | **P1** | Baja | API | `AuthService` | **Routing complejo triple-DB.** Accede a `SUPABASE_CLIENT`, `SUPABASE_ADMIN_CLIENT` y `SUPABASE_ADMIN_DB_CLIENT` con lógica `clientId === 'platform'`. Alta superficie de error. | Bug en routing podría exponer datos admin en contexto de tienda o viceversa. | `src/auth/` — presencia de `getInternalClient()` con switch por `clientId` | Refactorizar en 2 servicios: `TenantAuthService` + `PlatformAuthService` | L |
| H07 | **P1** | Media | Ambas DBs | `subscription_status` | **Denormalización sin sync automático.** `subscriptions.status` es source of truth, pero `nv_accounts.subscription_status` es una copia denormalizada. Si se actualiza uno sin el otro, el estado diverge. | Dashboard Admin muestra estado desactualizado; gating de tienda basado en dato stale. | `migrations/admin/` → `nv_accounts.subscription_status` + `subscriptions.status` | Agregar trigger en `subscriptions` que propague a `nv_accounts.subscription_status` o eliminar la denormalización. | M |
| H08 | **P2** | Media | Multitenant DB | `cart_items` | **Doble RLS policy conflictiva.** `cart_items_owner_all` (FOR ALL, owner) + `cart_items_select_tenant` (FOR SELECT, admin OR owner) + `cart_items_insert_tenant` (FOR INSERT). Las policies OR-merged pueden dar acceso más amplio del esperado. | Admin podría ver cart_items de otros users del mismo tenant (intencionado pero no documentado explícitamente). | Políticas RLS listadas en instrucciones → `cart_items` tiene 5 policies con overlap | Revisar si el overlap es intencional. Documentar. Si admin NO debe ver carts ajenos, remover `is_admin()` de select. | S |
| H09 | **P2** | Media | Admin DB | `nv_billing_events.external_reference` | **Unique constraint parcial.** `external_reference` es UNIQUE pero nullable. Múltiples NULLs son permitidos por Postgres. Validar que la app siempre setee `external_reference` para pagos MP (idempotencia). | Pagos sin external_reference podrían duplicarse si el webhook reintenta. | Migración de `nv_billing_events` — `external_reference text UNIQUE` | Cambiar a `NOT NULL` con default o agregar partial unique `WHERE external_reference IS NOT NULL` si los manuales no lo tienen. | S |
| H10 | **P2** | Baja | Web | `tenantResolver.js` | **Query param `?tenant=` aceptado en producción.** Permite forzar slug vía URL en cualquier entorno. | Impacto bajo: el backend valida contra dominio/slug real. Pero podría confundir al frontend si hay mismatch. | `src/utils/tenantResolver.js` → prioridad: query param > env > subdomain | Restringir query param a entornos de desarrollo (`hostname === 'localhost'` ya parcialmente implementado). | S |
| H11 | **P2** | Baja | Web | `CartProvider` | **Fallback `resolvedClientId` a `VITE_CLIENT_ID`.** Si no hay user ni sessionStorage, usa env var estática que podría estar hardcodeada a un tenant específico. | Requests de carrito anónimo podrían ir scoped a un tenant incorrecto. | `src/context/CartProvider.jsx` → `resolvedClientId` fallback chain | Eliminar fallback a `VITE_CLIENT_ID`. En su lugar, obtener `clientId` del `TenantProvider` context (que ya lo resuelve del backend). | S |
| H12 | **P2** | Baja | Web | `api/client.ts` | **Dos clientes axios duplicados.** `axiosConfig.jsx` y `api/client.ts` tienen lógica de headers y tenant resolution diferente. `client.ts` tiene custom domain support que `axiosConfig.jsx` no. | Inconsistencia en headers enviados. Features de custom domain podrían fallar si se usa el cliente incorrecto. | Ambos archivos en `src/services/` y `src/api/` | Consolidar en un solo cliente. Mover la lógica de custom domain de `client.ts` al principal. | M |
| H13 | **P2** | Baja | Admin EF | `admin-create-client` | **Dependencias desactualizadas.** Usa `std@0.168.0` + `supabase-js@2.39.3` vs el resto que usa `std@0.213.0` + `supabase-js@2.49.4`. | Posibles bugs conocidos o vulnerabilidades parcheadas en versiones más nuevas. | `deno.json` de la función vs las demás | Actualizar imports a las mismas versiones del resto | S |
| H14 | **P2** | Baja | Admin EF | `_shared/wa-common.ts` | **Referencia a tabla `profiles` inexistente.** `requireAdmin()` busca rol en `profiles.role` como fallback. Si la tabla no existe, la query retorna null silenciosamente. | No es un bug funcional (el fallback a `users.role` funciona), pero genera queries innecesarias y confusión. | `_shared/wa-common.ts` → `supabase.from('profiles')...` | Remover el fallback a `profiles` o crear la tabla como alias/view. | S |
| H15 | **P3** | Baja | Admin DB | `client_usage_month` | **Sin particionamiento ni TTL.** Tabla de métricas que crece indefinidamente. | Performance degradation a largo plazo en queries de dashboard y sync. | Tabla sin `PARTITION BY` ni job de limpieza documentado | Implementar particionamiento por mes o agregar cron de cleanup (>= 24 meses). | M |
| H16 | **P3** | Baja | Multitenant DB | `email_jobs` | **Sin TTL ni archivado.** La tabla crece por cada email enviado sin mecanismo de limpieza. | Tabla potencialmente grande, impacto en performance de queries admin. | Migración `20251007_create_email_jobs_table.sql` — sin partition/TTL | Agregar cron de limpieza (archivar/borrar > 90 días) o particionar por mes. | S |
| H17 | **P3** | Baja | Ambas DBs | Varios | **Lifecyle/audit events sin índice por fecha.** `lifecycle_events`, `tenant_payment_events`, `webhook_events` tienen `created_at`/`received_at` pero sin índice compuesto con `account_id`. | Queries de auditoría serán lentas con volumen. | Migraciones de dichas tablas — solo PK e índices simples | Agregar `idx_<table>_account_created (account_id, created_at DESC)` | S |
| H18 | **P2** | Media | Web | `previewUtils.js` | **Preview token fallback abierto.** Si `VITE_PREVIEW_TOKEN` no está seteada, `isValidPreviewToken()` retorna `true` con warning. | En producción sin token, cualquiera accede al preview (riesgo bajo por el network guard, pero igual expone temas/datos). | `src/preview/previewUtils.js` → `if (!expectedToken) { console.warn...; return true }` | Cambiar a `return false` si no hay token en producción. | S |

---

## 4. Deep Dive por Categoría

### 4.1 Multi-tenant Isolation

**Patrón de aislamiento:** `client_id` en todas las tablas de negocio (Multitenant DB).

**Validación positiva:**
- ✅ Todas las tablas de catálogo y transaccionales tienen `client_id` como columna
- ✅ `client_id` es `NOT NULL` en las tablas críticas: `cart_items`, `client_extra_costs`, `client_payment_settings`, `client_mp_fee_overrides`
- ✅ `TenantContextGuard` es `APP_GUARD` global — se ejecuta para TODA ruta excepto las decoradas con `@AllowNoTenant()`
- ✅ Storefront envía `x-tenant-slug` (no `x-client-id`), evitando identifier leakage
- ✅ Cross-tenant check en axios interceptor del Storefront: bloquea request si slug del header ≠ slug actual
- ✅ `x-client-id` header fue **explícitamente removido** del TenantContextGuard (comentario "Identifier Leakage P0 audit")

**Gaps identificados:**

| Tabla | `client_id` | `NOT NULL` | Comentario |
|-------|------------|-----------|-----------|
| `categories` | ✅ | ❌ nullable | Debería ser NOT NULL — una categoría sin tenant es huérfana |
| `banners` | ✅ | ❌ nullable | Idem |
| `contact_info` | ✅ | ❌ (`client_id` existe pero listada como nullable en instrucciones) | Verificar en DB real |
| `mp_fee_table` | ❌ | — | Tabla global de comisiones MP. Correcto que no tenga `client_id`. Override por tenant en `client_mp_fee_overrides`. |

**Evidencia de tablas sin client_id que deberían tenerlo:**
- ⚠️ `contact_info` tiene `client_id` nullable según el schema provided. Podría haber rows sin scope.
- La query de validación sería: `SELECT COUNT(*) FROM categories WHERE client_id IS NULL` y `SELECT COUNT(*) FROM banners WHERE client_id IS NULL`

**Índices de tenant:**
- ✅ Índice `idx_<table>_client_id` presente en todas las tablas principales (confirmado por migraciones)
- ✅ Índices compuestos: `orders(user_id, client_id)`, `cart_items(client_id, user_id)` (confirmados por el schema de instrucciones)
- ⚠️ No se encontró índice compuesto `(client_id, created_at)` explícito en `products` ni `orders` — verificar con `pg_indexes`

### 4.2 RLS / RBAC

#### Multitenant DB — RLS

**Patrón uniforme confirmado:**

| Operación | Política estándar |
|-----------|-------------------|
| SELECT (catálogo) | `client_id = current_client_id()` |
| INSERT/UPDATE/DELETE (catálogo) | `client_id = current_client_id() AND is_admin()` |
| SELECT (transacciones) | `client_id = current_client_id() AND (user_id = auth.uid() OR is_admin())` |
| ALL operations | `auth.role() = 'service_role'` (bypass) |

**Helper functions:**
```sql
current_client_id() → SELECT client_id FROM users WHERE id = auth.uid()
is_admin()          → role IN ('admin', 'super_admin')
is_super_admin()    → role = 'super_admin'
```

**Observaciones:**
- ✅ `server_bypass` policy en TODAS las tablas
- ✅ `clients` table: solo `is_super_admin()` puede update/delete; users normales solo `SELECT WHERE id = current_client_id()`
- ✅ `users` table: update con `role IS DISTINCT FROM 'super_admin'` — previene escalación de privilegios
- ⚠️ `order_payment_breakdown`: tiene 2 policies de SELECT (`opb_select_admin` y `opb_select_tenant`) que se OR-merge. El resultado es que cualquier user autenticado del tenant puede leer, no solo admin. Verificar intencionalidad.
- ⚠️ `cart_items`: 5 policies con overlap (ver H08)

#### Admin DB — RLS

**Patrón más restrictivo:**
```sql
REVOKE ALL ON SCHEMA public FROM anon, authenticated;
-- Solo service_role tiene acceso
```

- ✅ `server_bypass` en todas las tablas
- ✅ `subscription_locks`, `lifecycle_events` → solo service_role
- ✅ Super admin policies para tablas de gestión (clients, invoices, payments, users)
- ⚠️ `client_usage_month` y `invoices` tienen policy `USING (true) WITH CHECK (true)` para `service_role` — correcto pero amplio. Verificar que no haya anon access habilitado.

#### Edge Functions — Auth Gaps (ver H01, H02, H05)

| Función | Auth | Riesgo |
|---------|------|--------|
| `admin-create-client` | ❌ Ninguna | P0 |
| `admin-delete-client` | ❌ Ninguna (HMAC solo interno) | P0 |
| `admin-sync-usage` | ❌ Ninguna | P1 |
| `admin-sync-usage-batch` | ❌ Ninguna | P1 |
| `admin-fetch-exchange-rate` | ❌ Pública (solo lectura) | P3 |
| Resto (12 funciones) | ✅ `requireAdmin()` | OK |

### 4.3 Integridad Referencial

#### Foreign Keys confirmadas

| Tabla | FK | ON DELETE |
|-------|----|----|
| `nv_onboarding.account_id` | → `nv_accounts.id` | CASCADE |
| `subscriptions.account_id` | → `nv_accounts.id` | CASCADE |
| `provisioning_jobs.account_id` | → `nv_accounts.id` | CASCADE |
| `provisioning_job_steps.job_id` | → `provisioning_jobs.id` | CASCADE |
| `provisioning_job_steps.account_id` | → `nv_accounts.id` | — |
| `nv_accounts.subscription_id` | → `subscriptions.id` | — |
| `nv_accounts.backend_cluster_id` | → `backend_clusters.cluster_key` | — |
| `product_categories.product_id` | → `products.id` | (presumido) |
| `product_categories.category_id` | → `categories.id` | (presumido) |
| `client_secrets.client_id` | → `clients.id` | (presumido) |

#### Gaps de integridad

1. **`clients.nv_account_id` (Multitenant):** No tiene FK real a Admin DB (cross-DB FK no soportado). La consistencia depende enteramente de la lógica de aplicación.
   - **Validación:** `SELECT c.id FROM clients c LEFT JOIN nv_accounts a ON c.nv_account_id = a.id WHERE a.id IS NULL` (requiere cross-DB query vía application layer)

2. **`cart_items.product_id` → `products.id`:** Asumido FK por naming, pero no confirmado en migraciones. Si no existe, un producto borrado deja cart_items huérfanos.
   - **Validación:** `SELECT * FROM information_schema.table_constraints WHERE table_name = 'cart_items' AND constraint_type = 'FOREIGN KEY'`

3. **`order_items.order_id` → `orders.id`:** Similar — verificar FK real.

4. **`orders.payment_id`:** Migración `20250816_make_orders_payment_id_nullable.sql` hizo nullable esta columna. Verificar que no haya orphan references.

#### Unique Constraints de idempotencia

| Constraint | Tabla | Columnas |
|-----------|-------|----------|
| ✅ | `mp_idempotency` | Verificar exact constraint name |
| ✅ | `nv_billing_events` | `external_reference` (UNIQUE, nullable — ver H09) |
| ✅ | `webhook_events` | `(source, payment_id, event_type)` UNIQUE |
| ✅ | `subscriptions` | `mp_preapproval_id` UNIQUE NOT NULL |
| ✅ | `subscriptions` | Partial unique `one_active_per_account` WHERE status='active' |
| ✅ | `nv_accounts` | `email` (citext UNIQUE), `slug` UNIQUE |
| ✅ | `slug_reservations` | Tiene TTL (30min) |
| ✅ | `auth_bridge_codes` | Dedup implícito por `account_id` + `code` |
| ✅ | `subscription_events` | `event_id` UNIQUE (idempotencia de webhooks) |

### 4.4 Pagos & Onboarding

#### Mercado Pago — Tenant Payments (compradores finales)

**Flujo:**
```
Storefront → POST /mercadopago/create-preference-for-plan
  → MercadoPagoService.createPreferenceForPlan()
    → Obtiene MP credentials del tenant (clients.mp_access_token o via MpOauthService)
    → Crea preferencia MP con access_token del tenant
    → Inserta/actualiza en mp_idempotency
    → Retorna redirect_url + external_reference

MP Webhook → POST /payments/webhook
  → Valida firma x-signature
  → Lock in-memory + mp_idempotency check
  → Consulta payment a MP API
  → Actualiza orders.status, payments, order_payment_breakdown
```

**Validación positiva:**
- ✅ Precios calculados desde backend (no confía en frontend)
- ✅ Idempotency key en create-preference (header `Idempotency-Key`)
- ✅ `mp_idempotency` table con dedup
- ✅ Firma `x-signature` validada en webhook
- ✅ Webhook actualiza stock solo en `approved`
- ✅ `external_reference` incluye `clientId` para scoping

**Riesgos:**
- ⚠️ Lock in-memory no escala en múltiples instancias (Railway puede tener >1 instance). Mitigado por `mp_idempotency` table como segunda capa.
- ⚠️ Si el webhook falla entre update de `payments` y `orders`, quedan inconsistentes. No hay transacción atómica.

#### Mercado Pago — Platform Subscriptions (cobro a clientes NovaVision)

**Flujo:**
```
Admin Dashboard → Onboarding checkout → PlatformMercadoPagoService.createPreference()
  → Usa PLATFORM_MP_ACCESS_TOKEN (credenciales de NovaVision, no del tenant)
  → Crea preference para setup fee / subscription

MP Webhook → SubscriptionsService.handleWebhook()
  → Valida event via subscription_events.event_id (idempotencia)
  → Distributed lock via try_lock_subscription() RPC
  → Actualiza subscriptions.status, nv_accounts.subscription_status
  → Sync a Multitenant: clients.publication_status
```

**Validación positiva:**
- ✅ Distributed locks via Postgres RPC (no in-memory)
- ✅ Event idempotencia via `subscription_events.event_id` UNIQUE
- ✅ Grace period, auto-suspend, auto-deactivate lifecycle implementado
- ✅ `subscription_payment_failures` logging con retry tracking

**Riesgos:**
- ⚠️ La sync a Multitenant DB (ver H04) puede fallar sin compensación
- ⚠️ `PLATFORM_MP_ACCESS_TOKEN` como env var única — no hay rotación documentada

#### Onboarding — Provisioning

**Flujo multi-paso:**
```
1. startDraftBuilder(email, slug)
   → Admin DB: INSERT nv_accounts (status='draft', slug=draft-UUID)
   → Admin DB: INSERT nv_onboarding (state='draft_builder')
   
2. submitForReview(accountId) o auto-approve
   → Admin DB: UPDATE nv_accounts.status → 'approved'
   → Admin DB: INSERT provisioning_jobs (type=PROVISION_CLIENT, status='queued')

3. Worker processes job (saga pattern)
   → Admin DB: provisioning_job_steps (create_client, create_user, seed_data, ...)
   → Backend DB: INSERT clients, users, categories, products, banners (demo data)
   → Admin DB: UPDATE nv_onboarding.state → 'provisioned'

4. completeOwnerScaffold(accountId, token, userData)
   → Admin DB: Supabase Auth createUser
   → Admin DB: UPSERT users
   → Admin DB: UPDATE nv_accounts.status → 'active'
```

**Validación positiva:**
- ✅ Saga pattern con `provisioning_job_steps` permite retries parciales
- ✅ `is_provisioning_step_done()` RPC previene re-ejecución de pasos completados
- ✅ `onboarding_links` consume atómico (`UPDATE ... SET used_at = NOW() WHERE used_at IS NULL RETURNING *`)
- ✅ `slug_reservations` con TTL de 30 minutos previene squatting

**Riesgos:**
- ⚠️ Si el provisioning falla después de crear `clients` en Multitenant pero antes de completar todos los steps, queda un tenant parcialmente provisioned. El saga puede reintentar, pero si falla definitivamente, necesita cleanup manual.
- ⚠️ Auth user creation (paso 4) es en Admin DB Supabase Auth. El user necesita poder hacer login contra Multitenant DB Supabase Auth también → requires `auth_bridge_codes` flow. Punto de falla si el bridge falla.

#### Preview — Protección contra compras

**3 capas de protección:**
1. **App.jsx:** rutas `/preview` bypasean completamente `CartProvider` y `AuthProvider`
2. **MockCartProvider:** todas las mutaciones de carrito son no-op con `console.warn('[Preview] bloqueado')`
3. **PreviewNetworkGuard:** hard-block de `fetch()` y `XMLHttpRequest` para URLs que contengan: `payments`, `mercadopago`, `orders`, `checkout`, `cart`, `preference`, `webhook`, `create-preference`, `charge`, `subscribe`

**Evaluación:** ✅ Muy bien implementado. La 3ra capa (network guard) es especialmente robusta porque parchea a nivel de runtime, no solo de componentes.

### 4.5 Performance / Índices

#### Hot Paths identificados

| Path | Frecuencia | Tablas | Índice requerido |
|------|-----------|--------|-----------------|
| `GET /products?category=&search=&page=` | Muy alta | `products`, `product_categories`, `categories` | `products(client_id, active)`, `product_categories(product_id)` ✅ |
| `GET /home/data` (bootstrap de tienda) | Alta | `clients`, `banners`, `categories`, `products` | `clients(id)` ✅, `banners(client_id)` ✅ |
| `POST /cart/items` + `GET /cart` | Alta | `cart_items`, `products` | `cart_items(client_id, user_id)` ✅ |
| `GET /orders` (admin) | Media | `orders`, `payments` | `orders(client_id, status)` ✅ |
| `TenantContextGuard` (cada request) | Muy alta | `nv_accounts` (Admin), `clients` (Multi) | `nv_accounts(slug)` ✅, `clients(nv_account_id)` ✅ |
| MP Webhook processing | Media | `mp_idempotency`, `orders`, `payments`, `order_payment_breakdown` | `orders(client_id, external_reference)` ⚠️ verificar |

#### Riesgos de crecimiento

| Tabla | Crecimiento | Riesgo | Mitigación sugerida |
|-------|------------|--------|---------------------|
| `lifecycle_events` (Admin) | Ilimitado | Lento en queries históricas | Particionar por mes o `created_at` range |
| `tenant_payment_events` (Admin) | Alto (1 por webhook) | Idem | TTL de 12 meses + archive |
| `email_jobs` (Multitenant) | Alto (1 por email) | Idem | TTL de 90 días |
| `mp_idempotency` (Multitenant) | Alto (1 por pago) | Idem | TTL de 30 días |
| `client_usage_month` (Admin) | Bajo (1 row/client/mes) | Moderado a largo plazo | Sin acción inmediata |
| `subscription_notification_outbox` (Admin) | Medio | Si no se limpia | TTL de 30 días post-sent |

### 4.6 Observabilidad / Auditoría

**Lo que existe (positivo):**
- ✅ `lifecycle_events` (Admin): log unificado de cambios de estado de cuenta (event_type, old/new value, source, correlation_id)
- ✅ `webhook_events` (Admin): log idempotente de webhooks MP platform
- ✅ `tenant_payment_events` (Admin): log de webhooks MP tenant
- ✅ `subscription_events` (Admin): idempotencia de eventos de suscripción
- ✅ `client_completion_events` (Admin): audit log de checklist de completitud
- ✅ `provisioning_job_steps` (Admin): audit trail de provisioning saga
- ✅ `request_id` generado en TenantContextGuard y Edge Functions

**Lo que falta:**
- ❌ No hay audit table para operaciones de **admin sobre datos de tienda** (ej: admin modifica producto → no queda log)
- ❌ No hay audit table para **cambios de configuración de pago** (client_payment_settings)
- ❌ No hay métricas de **latencia por tenant** (para detectar tenants que consumen recursos desproporcionados)
- ❌ Los `email_jobs` no tienen tracking de delivery success/failure (solo `sent_at`)

---

## 5. "Decisiones Recomendadas" — Source of Truth

### Qué vive en Admin DB (Control Plane)

| Dominio | Tabla(s) | Source of Truth para |
|---------|---------|---------------------|
| **Cuentas** | `nv_accounts` | Identidad, estado, plan, email, slug, custom domain |
| **Suscripciones** | `subscriptions`, `subscription_*` | Estado de suscripción, historial de pagos, precios |
| **Billing** | `nv_billing_events` | Eventos de facturación platform |
| **Plans** | `plans` | Catálogo de planes y entitlements |
| **Onboarding** | `nv_onboarding`, `provisioning_jobs/steps`, `onboarding_links` | Estado y progreso del onboarding |
| **Templates** | `nv_templates`, `palette_catalog` | Catálogo de templates y paletas |
| **Super Admins** | `super_admins` | Lista de super admins de la plataforma |
| **Infrastructure** | `backend_clusters` | Clusters de Supabase disponibles |

### Qué vive en Multitenant DB (Data Plane)

| Dominio | Tabla(s) | Source of Truth para |
|---------|---------|---------------------|
| **Config de tienda** | `clients` | Nombre, logo, theme, MP credentials, publication_status |
| **Catálogo** | `products`, `categories`, `product_categories` | Productos y categorías del tenant |
| **Apariencia** | `banners`, `logos`, `social_links`, `faqs`, `contact_info`, `services` | Contenido visual |
| **Transacciones** | `orders`, `payments`, `cart_items`, `order_payment_breakdown` | Pedidos y pagos de compradores |
| **Config de pago** | `client_payment_settings`, `client_extra_costs`, `client_mp_fee_overrides` | Settings de pago por tenant |
| **Usuarios** | `users` | Compradores y admins del tenant |
| **Email** | `email_jobs` | Cola de emails transaccionales |
| **Seguridad** | `client_secrets` | MP tokens encriptados |
| **Métricas** | `client_usage` | Contadores de uso (trigger-maintained) |

### Qué se sincroniza y cómo

| Dato | From | To | Mecanismo | Frecuencia |
|------|------|----|-----------|-----------|
| `publication_status` | Admin DB (`nv_accounts.status`) | Multitenant DB (`clients.publication_status`) | `SubscriptionsService.syncAccountSubscriptionStatus()` | On status change |
| `plan` → `entitlements` | Admin DB (`plans`) | Multitenant DB (`clients.entitlements`) | Provisioning + plan change | On plan change |
| Usage metrics | Multitenant DB (`client_usage`, `orders`) | Admin DB (`client_usage_month`) | Edge Function `admin-sync-usage` via HMAC HTTP | Periodic batch |
| MP credentials | Admin DB (`nv_onboarding`) | Multitenant DB (`client_secrets`) | `MpOauthService` | On MP OAuth connect |
| Tenant creation | Admin DB (`nv_accounts`) | Multitenant DB (`clients`) | Provisioning saga | One-time |

### Contrato mínimo entre DBs

```
Admin DB ──┬── nv_accounts.id (UUID) ───→ clients.nv_account_id (Multitenant)
           │                               (NO HAY FK CROSS-DB — validar por app)
           │
           ├── nv_accounts.slug ─────────→ Resuelto por TenantContextGuard
           │                               (busca en Admin primero, luego Multitenant)
           │
           └── backend_clusters.cluster_key ──→ Determina qué Supabase project
                                                 usar para cada tenant
```

---

## 6. Checklist de Validación (para QA/Dev)

### Multi-tenant isolation

```sql
-- 1. Verificar que NO hay categorías/banners sin client_id
SELECT 'categories' as tbl, COUNT(*) FROM categories WHERE client_id IS NULL
UNION ALL
SELECT 'banners', COUNT(*) FROM banners WHERE client_id IS NULL
UNION ALL
SELECT 'contact_info', COUNT(*) FROM contact_info WHERE client_id IS NULL;
-- Esperado: 0 en todas

-- 2. Verificar índices de client_id
SELECT tablename, indexname FROM pg_indexes 
WHERE indexdef LIKE '%client_id%' 
ORDER BY tablename;

-- 3. Verificar que todas las tablas de negocio tienen RLS
SELECT c.relname, c.relrowsecurity 
FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace 
WHERE n.nspname = 'public' AND c.relkind = 'r'
ORDER BY c.relname;
-- Esperado: relrowsecurity = true en todas

-- 4. Verificar FKs en cart_items y order_items
SELECT tc.table_name, tc.constraint_name, tc.constraint_type,
       kcu.column_name, ccu.table_name AS foreign_table
FROM information_schema.table_constraints tc
JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
LEFT JOIN information_schema.constraint_column_usage ccu ON tc.constraint_name = ccu.constraint_name
WHERE tc.table_name IN ('cart_items', 'order_items') AND tc.constraint_type = 'FOREIGN KEY';
```

### Cross-tenant test (E2E)

```
1. Crear 2 tenants: tenant-A y tenant-B
2. Con user de tenant-A, intentar:
   a. GET /products con header x-tenant-slug: tenant-B → debe retornar 403/404
   b. POST /cart/items con product_id de tenant-B → debe fallar
   c. GET /orders con orderId de tenant-B → debe retornar 404
3. Verificar que el TenantContextGuard resuelve correctamente por:
   a. Subdomain
   b. Custom domain
   c. Query param (solo dev)
```

### Webhook idempotencia

```
1. Enviar mismo webhook MP 3 veces consecutivas
2. Verificar que:
   a. Solo 1 row en mp_idempotency (o 1 update)
   b. Solo 1 cambio de estado en orders
   c. Stock decrementado solo 1 vez
```

### Preview no puede comprar

```
1. Abrir /preview de una tienda
2. Intentar (via DevTools/fetch):
   a. POST a /mercadopago/create-preference → bloqueado por NetworkGuard
   b. POST a /cart/items → bloqueado
   c. POST a /orders/checkout → bloqueado
```

---

## 7. Anexos

### Rutas de archivos revisadas

#### API (NestJS)
- `apps/api/src/supabase/supabase.module.ts` — SupabaseModule (4 providers)
- `apps/api/src/db/db-router.service.ts` — DbRouterService (multi-cluster)
- `apps/api/src/supabase/request-client.helper.ts` — Request-scoped Supabase client
- `apps/api/src/auth/auth.middleware.ts` — JWT validation, dual-project
- `apps/api/src/guards/tenant-context.guard.ts` — Tenant resolution (global guard)
- `apps/api/src/guards/maintenance.guard.ts` — Maintenance mode gating
- `apps/api/src/guards/roles.guard.ts` — @Roles() decorator guard
- `apps/api/src/guards/super-admin.guard.ts` — SuperAdmin validation
- `apps/api/src/guards/subscription.guard.ts` — Subscription check
- `apps/api/src/guards/builder-session.guard.ts` — Builder token validation
- `apps/api/src/guards/builder-or-supabase.guard.ts` — Dual auth
- `apps/api/src/guards/client-dashboard.guard.ts` — Client dashboard access
- `apps/api/src/guards/rate-limiter.guard.ts` — Throttling
- `apps/api/src/common/decorators/allow-no-tenant.decorator.ts` — @AllowNoTenant()
- `apps/api/src/common/decorators/skip-subscription-check.decorator.ts` — @SkipSubscriptionCheck()
- `apps/api/src/onboarding/onboarding.service.ts` — Provisioning service (3472 líneas)
- `apps/api/src/subscriptions/subscriptions.service.ts` — Subscription lifecycle
- `apps/api/src/subscriptions/platform-mercadopago.service.ts` — Platform MP
- `apps/api/src/tenant-payments/mercadopago.service.ts` — Tenant MP
- `apps/api/src/billing/billing.service.ts` — Billing events
- `apps/api/src/finance/finance.service.ts` — Finance dashboard
- `apps/api/src/products/` — Products CRUD
- `apps/api/src/orders/` — Orders
- `apps/api/src/cart/` — Cart

#### Admin (Frontend + Edge Functions)
- `apps/admin/supabase/functions/_shared/wa-common.ts` — Shared auth helper
- `apps/admin/supabase/functions/admin-create-client/index.ts` — Create client (sin auth)
- `apps/admin/supabase/functions/admin-delete-client/index.ts` — Delete client (sin auth)
- `apps/admin/supabase/functions/admin-sync-usage/index.ts` — Sync usage (sin auth)
- `apps/admin/supabase/functions/admin-sync-usage-batch/index.ts` — Batch sync (sin auth)
- `apps/admin/supabase/functions/admin-analytics/index.ts` — Analytics
- `apps/admin/supabase/functions/admin-payments/index.ts` — Payments CRUD
- `apps/admin/supabase/functions/admin-sync-client/index.ts` — Sync client
- `apps/admin/supabase/functions/admin-sync-invoices/index.ts` — Sync invoices
- `apps/admin/supabase/functions/admin-cors-origins/index.ts` — CORS origins
- `apps/admin/supabase/functions/admin-app-settings/index.ts` — App settings
- `apps/admin/supabase/functions/admin-storage/index.ts` — Storage ops
- `apps/admin/supabase/functions/multi-delete-client/index.ts` — Multi delete (HMAC)
- `apps/admin/supabase/functions/calendly-webhook/index.ts` — Calendly webhook
- `apps/admin/supabase/functions/admin-wa-*/index.ts` — WhatsApp inbox (4 functions)
- `apps/admin/src/services/supabase/index.js` — Supabase client setup
- `apps/admin/src/services/api/nestjs.js` — NestJS API client
- `apps/admin/src/services/api/waInbox.js` — WA inbox API

#### Web (Storefront)
- `apps/web/src/utils/tenantResolver.js` — Tenant slug resolution
- `apps/web/src/utils/tenantScope.js` — Scoped storage keys
- `apps/web/src/context/TenantProvider.jsx` — Tenant context provider
- `apps/web/src/context/AuthProvider.jsx` — Auth provider
- `apps/web/src/context/CartProvider.jsx` — Cart provider
- `apps/web/src/services/axiosConfig.jsx` — Main axios client
- `apps/web/src/api/client.ts` — Alternative axios client
- `apps/web/src/services/supabase.js` — Supabase anon client
- `apps/web/src/hooks/cart/useCheckout.js` — Checkout flow
- `apps/web/src/pages/PaymentResultPage/index.jsx` — Payment result
- `apps/web/src/preview/PreviewProviders.tsx` — Preview mocks
- `apps/web/src/preview/PreviewNetworkGuard.tsx` — Network guard
- `apps/web/src/preview/previewUtils.js` — Preview utilities
- `apps/web/netlify/edge-functions/maintenance.ts` — Maintenance edge function

#### Migraciones
- `apps/api/migrations/admin/` — ~85 archivos de migraciones Admin DB
- `apps/api/migrations/backend/` — ~30 archivos de migraciones Multitenant DB
- `apps/api/migrations/storage/` — Storage bucket policies
- `apps/api/migrations/run_subscription_migrations.sh` — Script de ejecución

### Queries sugeridas para profundizar (requieren acceso a DB)

```sql
-- Admin DB: verificar estado de backend_clusters
SELECT cluster_key, is_active, status, display_name FROM backend_clusters;

-- Admin DB: verificar plan keys en uso
SELECT plan_key, COUNT(*) FROM nv_accounts GROUP BY plan_key ORDER BY COUNT(*) DESC;

-- Admin DB: verificar drafts expirados sin cleanup
SELECT COUNT(*) FROM nv_accounts WHERE status = 'draft' AND draft_expires_at < NOW();

-- Admin DB: verificar subscription_status sync
SELECT a.id, a.subscription_status, s.status 
FROM nv_accounts a 
LEFT JOIN subscriptions s ON a.subscription_id = s.id
WHERE a.subscription_status IS DISTINCT FROM s.status;

-- Multitenant DB: verificar orphan cart_items (producto borrado)
SELECT ci.id, ci.product_id 
FROM cart_items ci 
LEFT JOIN products p ON ci.product_id = p.id 
WHERE p.id IS NULL;

-- Multitenant DB: verificar tablas sin RLS
SELECT c.relname FROM pg_class c 
JOIN pg_namespace n ON n.oid = c.relnamespace 
WHERE n.nspname = 'public' AND c.relkind = 'r' AND NOT c.relrowsecurity;

-- Multitenant DB: verificar FKs faltantes
SELECT c.column_name, c.table_name
FROM information_schema.columns c
WHERE c.column_name LIKE '%_id' 
  AND c.table_schema = 'public'
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints tc
    JOIN information_schema.key_column_usage kcu ON tc.constraint_name = kcu.constraint_name
    WHERE kcu.column_name = c.column_name 
      AND kcu.table_name = c.table_name 
      AND tc.constraint_type = 'FOREIGN KEY'
  )
ORDER BY c.table_name, c.column_name;
```

### Notas

1. El sistema multi-cluster (`backend_clusters` + `DbRouterService`) es una base excelente para sharding horizontal futuro. Actualmente parece tener un solo cluster activo.
2. El patrón saga de provisioning (`provisioning_job_steps`) es robusto y permite recovery automático.
3. El `PreviewNetworkGuard` del storefront es una implementación defensiva ejemplar — 3 capas de protección contra compras en preview.
4. La separación Admin DB / Multitenant DB es conceptualmente correcta (control plane vs data plane). Los puntos de sincronización son los riesgos principales.
5. El sistema de suscripciones es completo pero complejo: 6+ tablas, distributed locks, lifecycle events, grace periods, auto-suspend, auto-deactivate, purge. La complejidad introduce riesgo de bugs sutiles en edge cases.

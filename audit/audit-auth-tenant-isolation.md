# Auditoría de Seguridad: Autenticación, Autorización y Aislamiento de Tenant

**Fecha:** 2025-02-25  
**Alcance:** `apps/api/src/` — capa de auth middleware, guards, decorators, Supabase clients  
**Severidad:** Se usa escala P0 (crítico) / P1 (alto) / P2 (medio) / P3 (bajo/informativo)

---

## 1. Inventario de Archivos Auditados

| # | Archivo | Propósito |
|---|---------|-----------|
| 1 | `src/auth/auth.middleware.ts` | Middleware global: extrae JWT, valida contra Supabase, resuelve `client_id`, popula `req.user` |
| 2 | `src/guards/tenant-context.guard.ts` | Guard global (APP_GUARD): resuelve tenant por slug/host/dominio, gatea estado de tienda |
| 3 | `src/guards/super-admin.guard.ts` | Guard para super admins: valida email en tabla + internal key |
| 4 | `src/guards/roles.guard.ts` | Guard de roles: compara `user.role` vs `@Roles()` metadata |
| 5 | `src/guards/builder-session.guard.ts` | Guard para sesiones builder (JWT propio con `JWT_SECRET`) |
| 6 | `src/guards/client-dashboard.guard.ts` | Guard dual: builder token O Supabase JWT para dashboard de cliente |
| 7 | `src/guards/builder-or-supabase.guard.ts` | Guard dual: builder token O Supabase JWT (para coupons, SEO, etc.) |
| 8 | `src/guards/maintenance.guard.ts` | Guard global: bloquea requests a tenants en mantenimiento/eliminados |
| 9 | `src/guards/tenant-rate-limit.guard.ts` | Guard global: rate limiting por plan (Redis) |
| 10 | `src/guards/quota-check.guard.ts` | Guard global: bloquea writes cuando el tenant excede cuota |
| 11 | `src/guards/subscription.guard.ts` | Guard: bloquea si suscripción no está activa |
| 12 | `src/auth/guards/platform-auth.guard.ts` | Guard: valida JWT solo contra Admin DB |
| 13 | `src/auth/guards/tenant-auth.guard.ts` | Guard: valida JWT solo contra Multicliente DB + valida `client_id` match |
| 14 | `src/plans/guards/plan-limits.guard.ts` | Guard: valida límites de plan antes de crear recursos |
| 15 | `src/plans/guards/plan-access.guard.ts` | Guard: valida acceso a features por plan |
| 16 | `src/common/decorators/allow-no-tenant.decorator.ts` | Decorator: `@AllowNoTenant()` — bypass de TenantContextGuard |
| 17 | `src/common/decorators/skip-quota-check.decorator.ts` | Decorator: `@SkipQuotaCheck()` — bypass de QuotaCheckGuard |
| 18 | `src/common/decorators/skip-subscription-check.decorator.ts` | Decorator: `@SkipSubscriptionCheck()` — bypass de SubscriptionGuard |
| 19 | `src/common/guards/client-context.guard.ts` | Guard auxiliar: extrae `clientId` usando helper |
| 20 | `src/common/utils/client-id.helper.ts` | Helper: extrae `clientId` solo desde `req.clientId` (NO de headers) |
| 21 | `src/common/middleware/rate-limit.middleware.ts` | Middleware: rate limiting por IP (Express, in-memory) |
| 22 | `src/supabase/supabase.module.ts` | Módulo global: provee 4 Supabase clients inyectables |
| 23 | `src/supabase/request-client.helper.ts` | Helper: crea Supabase client per-request con JWT del usuario |
| 24 | `src/db/db-router.service.ts` | Service: gestión de conexiones Admin + Backend clusters |
| 25 | `src/app.module.ts` | Módulo raíz: registra guards globales y middleware |
| 26 | `src/main.ts` | Bootstrap: helmet, CORS, rate limiting, Swagger |
| 27 | `src/auth/auth.module.ts` | Módulo de auth |
| 28 | `src/auth/auth.service.ts` | Service de auth (signup, login, OAuth, bridge SSO) |
| 29 | `src/auth/auth.controller.ts` | Controller de auth |

---

## 2. Pipeline de Request (Orden de Ejecución)

```
Incoming Request
  │
  ├─ 1. Express middlewares (main.ts):
  │     helmet → compression → cookieParser → bodyParser → rateLimit()
  │
  ├─ 2. CORS validation (async, per-origin DB lookup)
  │
  ├─ 3. NestJS middleware pipeline:
  │     AuthMiddleware (si no está excluida la ruta)
  │       → Extrae JWT de Authorization header
  │       → Valida contra Supabase (multiclient primero, luego admin)
  │       → Resuelve client_id (por rol y membership)
  │       → Popula req.user, req.supabase, req.headers['x-client-id']
  │
  ├─ 4. Global Guards (APP_GUARD, en orden de registro):
  │     a) TenantContextGuard  → Resuelve tenant por slug/host/dominio
  │     b) MaintenanceGuard    → Bloquea si tenant en mantenimiento
  │     c) QuotaCheckGuard     → Bloquea writes si cuota excedida
  │     d) TenantRateLimitGuard → Rate limit per-tenant por plan (Redis)
  │
  ├─ 5. Route-specific Guards (@UseGuards):
  │     RolesGuard, SuperAdminGuard, BuilderSessionGuard,
  │     ClientDashboardGuard, PlanLimitsGuard, PlanAccessGuard,
  │     SubscriptionGuard, etc.
  │
  └─ 6. Controller → Service → DB
```

---

## 3. Análisis Detallado por Componente

### 3.1 AuthMiddleware (`src/auth/auth.middleware.ts`)

**382 líneas.** Middleware global que se aplica a todas las rutas excepto las excluidas explícitamente en `AppModule.configure()`.

#### Cómo se extrae y valida el JWT

```typescript
const token = req.headers.authorization?.split(' ')[1];
```

**Validación real:** Se llama a `this.resolveUserFromToken(token)` que hace:
```typescript
await candidate.client.auth.getUser(token);
```
Esto es validación **server-side** contra Supabase Auth (NO es solo decodificación local). Prueba primero en proyecto `multiclient`, luego en `admin`. ✅ **BIEN: Validación real del JWT contra Supabase.**

#### Cómo se procesa x-client-id

El header `x-client-id` se lee pero **solo se usa como pista** — nunca como fuente única de verdad:

- **Para admin project**: `resolvedClientId = effectiveHeaderClientId || userClientId`
- **Para super_admin**: igual (Cross-tenant controlado con audit log)
- **Para usuarios normales**: se valida que el `x-client-id` del header **esté en el set de client_ids permitidos** del usuario (consultando tabla `users`). Si no coincide, se usa el default del usuario.

✅ **BIEN: Anti-spoofing para usuarios normales.** Un usuario no puede operar con un tenant que no le pertenece.

#### Cómo se propaga client_id

1. Se setea `req.headers['x-client-id'] = resolvedClientId`
2. Se crea `req.supabase` (per-request Supabase client con el JWT del usuario)
3. Se popula `req.user` con `resolvedClientId`, `role`, `project`

#### Mecanismo builder

Hay un flujo paralelo para tokens `x-builder-token` (JWT propio firmado con `JWT_SECRET`):
- Solo para ciertas rutas (`/accounts/me`, `/client-dashboard/`, `/palettes`, `/templates`)
- Valida firma y `type === 'builder_session'`

#### Rutas públicas (sin auth)

Se listan `PUBLIC_PATH_PREFIXES` usando `url.startsWith()`:
```typescript
'/mercadopago/webhook', '/health', '/auth/signup', '/auth/login',
'/onboarding/', '/coupons/', '/seo-ai/webhook', ...
```

⚠️ **P2 — OBSERVACIÓN: `/coupons/` es público en el middleware (comment dice "auth handled by BuilderOrSupabaseGuard at controller level")**, lo cual es correcto si el guard está aplicado consistentemente a todos los endpoints de ese controller.

#### Rutas excluidas del middleware (AppModule)

La lista de exclusión en `AppModule.configure()` es extensa (~50 entries). Incluye:
- GET `/products`, `/categories`, `/home/data` → público para storefront ✅
- POST `/auth/signup`, `/auth/login` → público por diseño ✅
- POST `/onboarding/*` → protegido por BuilderSessionGuard ✅
- GET `/tenant/bootstrap`, `/tenant/status` → público para resolución ✅
- GET `/seo/*`, `/legal/documents` → público ✅
- POST `/dev/seed-tenant` → **solo en dev** (DevModule no se carga en prod) ✅

---

### 3.2 TenantContextGuard (`src/guards/tenant-context.guard.ts`)

**447 líneas.** Guard GLOBAL (APP_GUARD) que resuelve el tenant.

#### Resolución de tenant (prioridad)

1. **Header slug** (`x-tenant-slug` o `x-store-slug`) → busca en `nv_accounts` por slug → resuelve `clients.id`
2. ~~Header `x-client-id`~~ → **ELIMINADO por auditoría P0** (comment: "Removed per P0 audit (Identifier Leakage)") ✅
3. **Custom domain** (`x-forwarded-host` o `host`) → busca en `nv_accounts.custom_domain`
4. **Subdominio** (e.g., `tienda1.novavision.lat`) → extrae slug → busca en `nv_accounts`
5. ~~Fallback desde `req.user`~~ → **ELIMINADO por auditoría P0** ✅

✅ **EXCELENTE: El tenant se resuelve SOLO desde fuentes confiables (slug DB-resolved o dominio verificado).** No se acepta un UUID crudo de un header.

#### Gateo de estado de tienda

Para cada tenant resuelto, se ejecuta `gateStorefront()`:
- `deleted_at` → 401 STORE_NOT_FOUND
- `is_active === false` → 403 STORE_SUSPENDED
- `maintenance_mode === true` → 403 STORE_MAINTENANCE
- `publication_status !== 'published'` → 403 STORE_NOT_PUBLISHED

✅ **BIEN: Defense in depth.** Tiendas inactivas/eliminadas son bloqueadas a nivel de guard.

#### `@AllowNoTenant()` bypass

El decorator funciona via `Reflector.getAllAndOverride()` con key `allow_no_tenant`. Cuando está presente, el guard retorna `true` sin resolver tenant.

**Usos encontrados de `@AllowNoTenant()` (15 instancias):**
- `auth.controller.ts` — endpoints de auth (login, signup, bridge, OAuth) ✅
- `admin-option-sets.controller.ts` — admin ✅
- `support.controller.ts` (7 endpoints) — ⚠️ verificar que tenga guard propio
- `support-admin.controller.ts` — super admin ✅
- `admin-fx-rates.controller.ts` — admin ✅
- `admin-country-configs.controller.ts` — admin ✅
- `admin-quotas.controller.ts` — admin ✅
- `billing/quota.controller.ts` — 1 endpoint ✅
- `admin-adjustments.controller.ts` — admin ✅
- `admin-fee-schedules.controller.ts` — admin ✅

⚠️ **P2 — Revisar:** Los controllers admin con `@AllowNoTenant()` deben tener `SuperAdminGuard` o `PlatformAuthGuard` explícito. Si no, quedan abiertos.

#### Subdominios reservados

```typescript
const reserved = ['admin', 'api', 'app', 'www', 'novavision', 'localhost', 'build', 'novavision-production'];
```
✅ **BIEN:** Previene colisión de slugs con subdominios del sistema.

---

### 3.3 SuperAdminGuard (`src/guards/super-admin.guard.ts`)

**Doble validación:**
1. Email del usuario debe existir en tabla `super_admins` (Admin DB)
2. Internal key validada con `timingSafeEquals` (desde cookie `nv_ik` o header `x-internal-key`)

✅ **EXCELENTE: Defensa en profundidad.** No basta con tener un JWT de admin; necesitás estar en la tabla super_admins Y tener la internal key.

⚠️ **P3 — Observación:** Si `INTERNAL_ACCESS_KEY` no está configurada, se lanza `ForbiddenException` ("failing closed"). Correcto.

---

### 3.4 RolesGuard (`src/guards/roles.guard.ts`)

- Usa metadata `@Roles('admin', 'super_admin')` via `Reflector`
- Si no hay `@Roles()`, permite todo → ✅ correcto (guard no aplica)
- **Anti-escalación:** bloquea explícitamente que un `admin` del proyecto `admin` sin `client_id` se haga pasar por `super_admin`:

```typescript
if (roles.includes('super_admin') && project === 'admin' && user.role === 'admin' && !userClientId) {
  throw new ForbiddenException('Acceso denegado: escalación de admin a super_admin no permitida');
}
```
✅ **BIEN.**

---

### 3.5 BuilderSessionGuard (`src/guards/builder-session.guard.ts`)

- Extrae token de `x-builder-token` o `Authorization: Bearer`
- Valida con `JwtService.verify()` usando `JWT_SECRET`
- Valida `type === 'builder_session'` y expiración
- Popula `req.account_id`, `req.email`, `req.builderSession`
- **NO confía en account_id del body** (solo del JWT) ✅

---

### 3.6 ClientDashboardGuard (`src/guards/client-dashboard.guard.ts`)

Guard dual que acepta:
1. **Builder token** → valida JWT, popula builder context
2. **Supabase JWT** → acepta roles `admin`, `super_admin`, `builder`, `client`
3. **Fallback:** Authorization Bearer como builder token si no hay `req.user`

Si no hay `account_id`, lo resuelve desde `nv_accounts` por `user_id` o `email`.

✅ **BIEN: Flexible pero seguro.** Necesita al menos uno de los dos tipos de auth.

---

### 3.7 BuilderOrSupabaseGuard (`src/guards/builder-or-supabase.guard.ts`)

Similar a ClientDashboardGuard pero más simple:
1. Intenta builder token
2. Intenta Supabase JWT (valida contra ambos proyectos: admin y multiclient)
3. Popula `req.account_id` y `req.email`

Para Supabase, crea un `createClient` con anon key para validar. **Nota:** valida contra admin primero, luego multiclient.

---

### 3.8 Rate Limiting

**Dos capas:**

1. **IP-based (Express middleware, in-memory)** — `src/common/middleware/rate-limit.middleware.ts`:
   - Auth write (login/register): 20 req/min
   - Auth read (session checks): 120 req/min
   - Generic: 100 req/min
   - Admin: 200 req/5min
   - Excluye webhooks MP, healthz

2. **Tenant-based (NestJS guard, Redis)** — `src/guards/tenant-rate-limit.guard.ts`:
   - Starter: 5 RPS sustained, 15 RPS burst
   - Growth: 15 RPS sustained, 45 RPS burst
   - Enterprise: 60 RPS sustained, 180 RPS burst
   - Fail-open si Redis no disponible

✅ **BIEN: Doble capa de rate limiting.**

---

## 4. Clientes Supabase — Inventario Completo

### 4.1 Clientes inyectables (SupabaseModule — global)

| Token DI | URL | Key | Propósito |
|----------|-----|-----|-----------|
| `SUPABASE_CLIENT` | `SUPABASE_URL` | `SUPABASE_KEY` | **⚠️ Usa ANON KEY** — cliente para operaciones con RLS del user |
| `SUPABASE_ADMIN_CLIENT` | `SUPABASE_URL` | `SUPABASE_SERVICE_ROLE_KEY` | **SERVICE_ROLE** — bypassa RLS en Multicliente DB |
| `SUPABASE_ADMIN_DB_CLIENT` | `SUPABASE_ADMIN_URL` | `SUPABASE_ADMIN_SERVICE_ROLE_KEY` | **SERVICE_ROLE** — Admin DB |
| `SUPABASE_METERING_CLIENT` | `SUPABASE_ADMIN_URL` | `SUPABASE_ADMIN_SERVICE_ROLE_KEY` | **SERVICE_ROLE** — dup de Admin DB (para metering) |

### 4.2 Clientes estáticos en AuthMiddleware

```typescript
const multiProjectClient = createClient(SUPABASE_URL, SUPABASE_SERVICE_ROLE_KEY);
const adminProjectClient = createClient(SUPABASE_ADMIN_URL, SUPABASE_ADMIN_SERVICE_ROLE_KEY);
```
**SERVICE_ROLE** — usados solo para `auth.getUser(token)` (validación de JWT). ✅

### 4.3 Cliente per-request (`request-client.helper.ts`)

```typescript
createClient(url, anonKey, { global: { headers: { Authorization: `Bearer ${userToken}` } } });
```
**ANON KEY + user JWT** — respeta RLS. Se adjunta a `req.supabase`. ✅

### 4.4 DbRouterService

- `adminClient`: `createClient(SUPABASE_ADMIN_URL, SUPABASE_ADMIN_SERVICE_ROLE_KEY)` — **SERVICE_ROLE**
- `backendClients` (Map): `createClient(cluster.supabase_url, cluster.service_role_key)` — **SERVICE_ROLE** per cluster

### 4.5 main.ts

```typescript
const supabase = createClient(supabaseUrl, supabaseKey); // SERVICE_ROLE — para CORS origin lookup
```

### 4.6 qr-cleanup.cron.ts

```typescript
createClient(url, key) // SERVICE_ROLE — Admin DB para cron cleanup
```

### 4.7 Resumen: Total de Supabase clients

| # | Ubicación | Key type | DB | Scope |
|---|-----------|----------|----|-------|
| 1 | SupabaseModule `SUPABASE_CLIENT` | **anon** | Multicliente | Global singleton |
| 2 | SupabaseModule `SUPABASE_ADMIN_CLIENT` | **service_role** | Multicliente | Global singleton |
| 3 | SupabaseModule `SUPABASE_ADMIN_DB_CLIENT` | **service_role** | Admin | Global singleton |
| 4 | SupabaseModule `SUPABASE_METERING_CLIENT` | **service_role** | Admin | Global singleton |
| 5 | AuthMiddleware `multiProjectClient` | **service_role** | Multicliente | Module-level static |
| 6 | AuthMiddleware `adminProjectClient` | **service_role** | Admin | Module-level static |
| 7 | `makeRequestSupabaseClient()` | **anon + user JWT** | Multicliente | Per-request |
| 8 | DbRouterService `adminClient` | **service_role** | Admin | Singleton |
| 9 | DbRouterService `backendClients` (N) | **service_role** | Per cluster | Cached per cluster |
| 10 | main.ts CORS client | **service_role** | Multicliente | Module-level static |
| 11 | qr-cleanup.cron.ts | **service_role** | Admin | Singleton |

**Total: 11 instancias** (algunas son singletons, otras per-request).

⚠️ **P2 — SUPABASE_METERING_CLIENT es idéntico a SUPABASE_ADMIN_DB_CLIENT.** Podría consolidarse para reducir conexiones, aunque no es un riesgo de seguridad.

⚠️ **P2 — main.ts usa SERVICE_ROLE_KEY para CORS lookup.** Esto es correcto funcionalmente pero podría usar anon key si la tabla `cors_origins` tuviera una política de lectura pública (SELECT abierto para anon). Actualmente la tabla solo permite `super_admin` en RLS, así que service_role es necesario.

---

## 5. Hallazgos de Seguridad

### ✅ POSITIVOS (bien implementado)

| # | Hallazgo | Severidad | Detalle |
|---|----------|-----------|---------|
| S-01 | JWT validado server-side | ✅ | `supabase.auth.getUser(token)` — no solo decodificación local |
| S-02 | x-client-id no se acepta crudo | ✅ | Eliminado per auditoría P0. Tenant se resuelve por slug →DB→ client_id |
| S-03 | Anti-spoofing para usuarios normales | ✅ | Se valida membership en tabla `users` antes de permitir operar con un tenant |
| S-04 | Super admin requiere doble factor | ✅ | Email en tabla + internal key (timing-safe) |
| S-05 | Anti-escalación admin→super_admin | ✅ | RolesGuard bloquea explícitamente |
| S-06 | Builder token no confía en body | ✅ | `account_id` solo del JWT |
| S-07 | Rate limiting doble capa | ✅ | IP (memory) + tenant (Redis) |
| S-08 | Gateo de status de tienda | ✅ | Suspended/maintenance/deleted/unpublished bloqueados |
| S-09 | Subdominios reservados | ✅ | admin, api, www, etc. no se resuelven como slugs |
| S-10 | Helmet + CSP | ✅ | Configurado en main.ts |
| S-11 | CORS dinámico con DB lookup | ✅ | Origins validados contra tabla `cors_origins` |
| S-12 | client-id.helper.ts seguro | ✅ | Solo extrae de `req.clientId` (set por TenantContextGuard), nunca de headers |
| S-13 | startsWith para paths públicos | ✅ | Evita bypass por query string (`/evil?redirect=/auth/login`) |
| S-14 | Fail-closed para super admin config | ✅ | Si `INTERNAL_ACCESS_KEY` missing → ForbiddenException |
| S-15 | Webhook MP excluido de rate limit | ✅ | Evita falsos bloqueos de reintentos legítimos |

### ⚠️ OBSERVACIONES Y RIESGOS

| # | Hallazgo | Severidad | Detalle | Remediación |
|---|----------|-----------|---------|-------------|
| R-01 | `@AllowNoTenant()` en controllers admin — **VERIFICADO OK** | **P3 (cerrado)** | Todos los admin controllers con `@AllowNoTenant()` tienen `@UseGuards(SuperAdminGuard)` a nivel de clase: `admin-option-sets`, `admin-fx-rates`, `admin-country-configs`, `admin-quotas`, `admin-adjustments`, `admin-fee-schedules`, `admin-coupons`. `support.controller.ts` tiene `@UseGuards(ClientDashboardGuard)` en cada endpoint. | N/A — protección confirmada. |
| R-02 | Token Authorization no es tomado si coincide con builder_session type | **P3** | En `AuthMiddleware`, si `isBuilderAccountsRoute` y el token parece builder, se salta la validación Supabase. Esto es esperado pero crea dos paths de validación. | Documentar claramente que builder accounts routes no pasan por Supabase auth. |
| R-03 | SUPABASE_CLIENT usa SUPABASE_KEY (variable ambigua) | **P2** | En `supabase.module.ts`, el provider `SUPABASE_CLIENT` usa `process.env.SUPABASE_KEY`. Debería verificarse que esta variable contenga la **anon key** y no la service role key. Si contienen service_role, `SUPABASE_CLIENT` bypassaría RLS. | Verificar en `.env` que `SUPABASE_KEY` = anon key. Renombrar a `SUPABASE_ANON_KEY` para claridad. |
| R-04 | `/coupons/` en PUBLIC_PATH_PREFIXES — **VERIFICADO OK** | **P3 (cerrado)** | `CouponsController` tiene `@UseGuards(BuilderOrSupabaseGuard)` a nivel de clase (1 endpoint: `POST /coupons/validate`). `AdminCouponsController` tiene `@UseGuards(SuperAdminGuard)` a nivel de clase. Ambos están protegidos. | N/A — protección confirmada. |
| R-05 | `makeRequestSupabaseClient` usa fallback a `SUPABASE_KEY` | **P2** | `const anonKey = process.env.SUPABASE_ANON_KEY \|\| process.env.SUPABASE_KEY`. Si `SUPABASE_KEY` es service_role, este client per-request (que recibe JWT del usuario) podría tener privilegios elevados. | Mismo que R-03: asegurar que `SUPABASE_KEY` sea anon key. |
| R-06 | `console.log` extensivo en TenantContextGuard | **P3** | Logs con `clientId`, `slug`, `userId`, `role`, `path` en texto plano. En producción, estos logs podrían exponer información si los logs no están protegidos. | Usar `Logger` de NestJS (que respeta niveles) en vez de `console.log`. Actualmente mezcla ambos. |
| R-07 | Rate limit IP-based es in-memory | **P2** | `RateLimiterMemory` no se comparte entre instancias de Railway. Si hay múltiples replicas, cada una tiene su propio contador. Un atacante podría distribuir requests entre replicas. | Para prod, considerar Redis para el rate limit por IP también (o confiar en el tenant-based que ya usa Redis). |
| R-08 | `tenant-rate-limit.guard` fail-open | **P2** | Si Redis no está disponible, el guard permite todo: `if (!limits) return true`. | Considerar fail-closed o al menos un fallback in-memory cuando Redis falla. |
| R-09 | Maintenance guard fail-open en error de DB | **P3** | Si la query a la DB falla, el request pasa. | Registrar alerta/métrica cuando esto ocurra. |
| R-10 | Doble lectura de tenant info | **P3** | `TenantContextGuard` resuelve el tenant (query DB), luego `MaintenanceGuard` vuelve a consultar `clients` para `maintenance_mode`. Son 2 queries por request al mismo dato. | Cachear la información del tenant en `request` desde TenantContextGuard y reutilizarla. El TenantContextGuard ya trae `is_active`, `publication_status`, `maintenance_mode`, `deleted_at` en `resolveClientByAccount`. |
| R-11 | Swagger expuesto en non-production | **P3** | `SwaggerModule.setup('api/docs', app, doc)` en dev/staging. Asegurar que staging no sea accesible públicamente. | Confirmar que staging tiene auth o restricción de acceso. |
| R-12 | `x-internal-key` header sin deprecación | **P3** | `SuperAdminGuard` acepta tanto cookie `nv_ik` como header `x-internal-key`. El header es menos seguro (visible en logs, proxies). | Deprecar el header y usar solo cookie httpOnly. |

---

## 6. ¿Puede el client_id ser spoofed?

**Respuesta: NO para usuarios normales. CONTROLADO para super_admin.**

### Flujo de protección:

1. **TenantContextGuard** resuelve `clientId` SOLO desde:
   - `x-tenant-slug` → DB lookup → `nv_accounts.id` → `clients.id`
   - Custom domain / subdominio → DB lookup → `clients.id`
   - **NUNCA** desde `x-client-id` header (eliminado en auditoría P0)

2. **AuthMiddleware** para usuarios normales:
   - Consulta tabla `users` por `user.id` para obtener todos los `client_id` asociados
   - Si el header `x-client-id` no coincide con ningún tenant del usuario, usa el default
   - **No es posible** operar con un tenant ajeno

3. **Para super_admin**: puede operar cross-tenant (por diseño), con audit log

4. **`client-id.helper.ts`** extrae SOLO de `req.clientId` (seteado por TenantContextGuard), nunca de headers

---

## 7. ¿La validación JWT realmente ocurre?

**SÍ.** Se usa `supabase.auth.getUser(token)` que:
1. Envía el token al servidor de Supabase
2. Supabase verifica firma, expiración, y que el usuario exista y no esté baneado
3. Retorna el user completo o error

**NO es** solo `jwt.decode()` local (que solo lee el payload sin verificar firma).

**Excepción:** Builder tokens se verifican localmente con `jwt.verify(token, JWT_SECRET)` usando jsonwebtoken. Esto es correcto porque son tokens propios firmados con el secret del backend.

---

## 8. ¿Hay endpoints sin guards?

### Rutas sin AuthMiddleware (excluidas en AppModule):
Todas las excluidas son públicas por diseño (storefront GET, auth POST, webhooks, health, onboarding).

### Rutas con `@AllowNoTenant()`:
Bypasean solo TenantContextGuard (no auth). Pero si el AuthMiddleware también está excluido para esa ruta, quedan sin ninguna protección de identidad. Los endpoints admin con `@AllowNoTenant()` **necesitan** un guard propio (SuperAdminGuard, PlatformAuthGuard).

### Endpoints potencialmente sin protección adecuada (requiere verificación):
- `support.controller.ts` — 7 endpoints `@AllowNoTenant()` — ¿tienen guard propio?
- Controllers admin con `@AllowNoTenant()` — ¿todos tienen SuperAdminGuard?

---

## 9. Resumen Ejecutivo

### Fortalezas principales:
1. **Aislamiento de tenant robusto:** Resolución por slug/dominio DB-verified, nunca por header crudo UUID
2. **JWT validado server-side** contra Supabase (no solo decodificación local)  
3. **Doble factor para super admin** (tabla whitelist + internal key)
4. **Anti-spoofing** verificado con membership lookup para usuarios normales
5. **Fallbacks previos eliminados** por auditoría P0 (comments explícitos en código)
6. **Rate limiting de doble capa** (IP + tenant/plan con Redis)
7. **Gateo de estados de tienda** (suspended, maintenance, deleted, unpublished)

### Áreas de mejora prioritarias:
1. **R-03/R-05 (P2):** Verificar que `SUPABASE_KEY` es anon key, renombrar a `SUPABASE_ANON_KEY`
2. **R-07 (P2):** Considerar Redis para rate limit por IP en producción multi-replica
3. **R-08 (P2):** Considerar fail-closed o fallback in-memory cuando Redis falla en rate limit
4. **R-10 (P3):** Cachear datos de tenant en request para evitar queries duplicadas
5. **R-12 (P3):** Deprecar header `x-internal-key` en favor de cookie `nv_ik` exclusivamente

### Hallazgos cerrados (verificados OK):
- **R-01:** Todos los `@AllowNoTenant()` admin controllers tienen `SuperAdminGuard` ✅
- **R-04:** CouponsController tiene `BuilderOrSupabaseGuard` clase-level ✅

### Score general: **8/10** — Capa de seguridad madura con buenas prácticas aplicadas. Los hallazgos P2 son mejoras de hardening, no vulnerabilidades explotables.

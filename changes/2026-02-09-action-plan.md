# Plan de Acción — Remediación de Seguridad y Consistencia NovaVision

**Fecha:** 2026-02-09  
**Última revisión:** 2026-02-09 (v2 — incorpora feedback TL)  
**Autor:** Agente Copilot  
**Basado en:** [Baseline Evidence](2026-02-09-baseline-evidence.md) + [Plan de Fases v2](2026-02-09-db-audit-plan-v2.md)  
**Estado:** En ejecución

---

## Registro de cambios del plan

| Versión | Fecha | Cambio |
|---------|-------|--------|
| v1 | 2026-02-09 | Plan inicial |
| v2 | 2026-02-09 | **Correcciones TL**: (1) `.env.production` agregado como P0 — estaba trackeado con secretos reales, (2) DevSeedingController subido a Fase 0 — aunque el service rechaza en prod, el módulo se carga y expone surface, (3) Registrado commit `27c3344` como completado (RolesGuard 10 controllers), (4) Corregido que 0.5.1 resume NO estaba hecho (sigue público), (5) Descartado rename `tenant_id→client_id` en 1.3 — solo NOT NULL + FK, (6) Fases 2-4 pospuestas a semana 4+ hasta cerrar seguridad |

---

## Índice

- [Pre-requisitos](#pre-requisitos)
- [YA COMPLETADO — Commit 27c3344](#completado)
- [Fase 0 — P0: Secretos + Auth crítica + DevSeeding](#fase-0)
  - [0.1 Secretos en Git (incluye .env.production)](#01-secretos)
  - [0.2 Edge Functions sin auth](#02-edge-functions)
  - [0.3 RLS faltante en client_secrets](#03-rls-secrets)
  - [0.4 DevSeedingController — bloqueo en prod](#04-devseeding)
- [Fase 0.5 — P1: Cerrar superficies auth API](#fase-05)
  - [0.5.1 Onboarding resume público](#051-resume)
  - [0.5.2 CouponsController sin guard](#052-coupons)
  - [0.5.3 Webhook MP inconsistente](#053-webhook)
  - [0.5.4 admin-sync-usage sin auth](#054-sync)
  - [0.5.5 super_admins RLS disabled](#055-superadmins)
- [Fase 1 — P1/P2: RLS + Integridad + Storage](#fase-1)
  - [1.1 RLS tablas Multi DB](#11-rls-multi)
  - [1.2 RLS tablas Admin DB](#12-rls-admin)
  - [1.3 tenant_payment_events scope fix](#13-tpe)
  - [1.4 Storage policies](#14-storage)
  - [1.5 Índices hot-path](#15-indices)
- [Fase 2 — P1: Normalización plan_key](#fase-2)
- [Fase 3 — Outbox cross-DB](#fase-3)
- [Fase 4 — Observabilidad y auditoría](#fase-4)
- [Checklist de verificación global](#checklist)

---

## Pre-requisitos

```bash
# Branches correctas
cd apps/api   && git checkout feature/automatic-multiclient-onboarding && git pull
cd apps/admin && git checkout feature/automatic-multiclient-onboarding && git pull
cd apps/web   && git checkout develop && git pull
```

**Convención de commits:**
```
[CELULA-3][AUDIT-{ID}] [FIX] descripción concreta
```

---

## YA COMPLETADO — Commit 27c3344 {#completado}

> Registrado como logro del hardening previo. NO estaba en el plan v1.

**Commit:** `27c3344` — `[CELULA-3] [FIX] Security audit: RolesGuard on 10 controllers, validateStock throw, amount validation, confirm-by-reference user check, email fields, cart availability`

| Cambio | Archivos | Impacto |
|--------|----------|--------|
| `@UseGuards(RolesGuard)` + `@Roles('admin')` en 10 controllers | banner, categories, contact-info, faq, home-settings, settings, logo, products, service, social-links | Admin endpoints requieren rol admin |
| Stock validation — throw en vez de warn | `cart.service.ts` | Bloquea compras sin stock |
| Amount validation en webhook MP | `mercadopago.service.ts` | Rechaza pagos con monto alterado |
| User check en confirm-by-reference | `mercadopago.controller.ts` | Previene IDOR en confirmación |
| Cart filter `available=true` | `cart.service.ts` | No agrega productos inactivos |

**Estado:** ✅ Completado y desplegado.

---

## Fase 0 — P0: Secretos + Auth crítica + DevSeeding {#fase-0}

> **Blocker: nada más se ejecuta hasta completar 0.1, 0.2, 0.3, 0.4.**

### 0.1 Secretos en Git {#01-secretos}

**Hallazgo:** P0-1 — **`.env.production` con secretos reales está TRACKEADO en Git** (más grave que los .bak). Los `.env.bak/backup` ya fueron removidos del tracking, pero `.env.production` sigue.

**Archivos afectados (repo `templatetwobe`):**
- **`.env.production`** — 🔴 ACTIVAMENTE TRACKEADO con SERVICE_ROLE_KEY, MP_ACCESS_TOKEN, SMTP_PASS, POSTMARK_API_KEY
- `.env.bak` — ✅ ya removido del tracking
- `.env.backup.manual` — ✅ ya removido del tracking  
- `.env.backup.20260111_203920` — ✅ ya removido del tracking

**Nota:** `.gitignore` actual solo tiene `.env` y `.env.*.local` — NO cubre `.env.production`, `*.bak`, `*.backup*`.

#### Tareas

| # | Tarea | Responsable | Detalle |
|---|-------|-------------|---------|
| 0.1.1 | Agregar a `.gitignore` | Agente | Agregar `.env.production`, `*.bak`, `*.backup*`, `.env.*` (con excepción de `.env.example`, `.env.email.example`, `.env.subscription_config`) |
| 0.1.2 | Eliminar `.env.production` del tracking | Agente | `git rm --cached .env.production` |
| 0.1.3 | Limpiar historial Git | TL | `git filter-repo --path .env.production --path .env.bak --path .env.backup.manual --path .env.backup.20260111_203920 --invert-paths` — requiere force push |
| 0.1.4 | Rotar TODOS los secretos expuestos | TL | Ver checklist de rotación abajo |
| 0.1.5 | Actualizar Railway env vars | TL | Con los nuevos valores rotados |
| 0.1.6 | Actualizar Edge Functions env vars | TL | Los mismos secretos se usan en Supabase Edge Functions |
| 0.1.7 | Verificar que apps siguen funcionando | TL + QA | Health check post-rotación |

#### Checklist de rotación

| Secreto | Dónde rotar | Dónde actualizar |
|---------|-------------|-----------------|
| `SUPABASE_SERVICE_ROLE_KEY` (Multi) | Supabase Dashboard → Settings → API | Railway env vars API |
| `SUPABASE_SERVICE_ROLE_KEY` (Admin) | Supabase Dashboard → Settings → API (proyecto Admin) | Railway env vars API + Edge Functions env |
| `PLATFORM_MP_ACCESS_TOKEN` | Mercado Pago → Tu aplicación → Credenciales de producción | Railway env vars API |
| `SUPABASE_SMTP_PASS` | Google → App Passwords → Revocar y crear nueva | Supabase Dashboard → Auth → SMTP |
| `POSTMARK_API_KEY` | Postmark → Servers → API Tokens → Rotar | Railway env vars API |

#### `.gitignore` — Líneas a agregar

```gitignore
# Security: never track env files with secrets
.env.production
.env.staging
.env.local
*.bak
*.backup*
.env.*
!.env.example
!.env.email.example
!.env.subscription_config
```

#### Verificación

```bash
# Post-cleanup: confirmar que no hay secretos en staging
git log --all --diff-filter=A -- '*.bak' '*.backup*' '.env.*' | head -5
# Debe devolver vacío después de filter-repo

# Post-rotación: health check
curl -s https://api.novavision.lat/health | jq .status
```

---

### 0.2 Edge Functions sin auth {#02-edge-functions}

**Hallazgo:** P0-2, P0-3 — `admin-create-client` y `admin-delete-client` no verifican JWT del caller.

#### 0.2.1 — `admin-create-client`

**Archivo:** `apps/admin/supabase/functions/admin-create-client/index.ts`

**Cambio:** Agregar verificación de admin JWT al inicio del handler, antes de cualquier lógica.

```typescript
// AGREGAR al inicio del handler, después de parsear body
import { requireAdmin } from '../_shared/wa-common.ts';

// Dentro de serve():
const admin = await requireAdmin(req);
if (admin instanceof Response) return admin; // 401/403
```

**Alternativa (si `requireAdmin` no encaja):** verificar JWT directo:

```typescript
const authHeader = req.headers.get('Authorization');
if (!authHeader?.startsWith('Bearer ')) {
  return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
}
const token = authHeader.replace('Bearer ', '');
const { data: { user }, error } = await adminClient.auth.getUser(token);
if (error || !user) {
  return new Response(JSON.stringify({ error: 'Invalid token' }), { status: 401 });
}
// Verificar rol admin/super_admin en users o metadata
```

#### 0.2.2 — `admin-delete-client`

**Archivo:** `apps/admin/supabase/functions/admin-delete-client/index.ts`

**Cambio:** Mismo patrón — agregar `requireAdmin` al inicio.

```typescript
import { requireAdmin } from '../_shared/wa-common.ts';

// En el handler:
const admin = await requireAdmin(req);
if (admin instanceof Response) return admin;
```

> **Nota:** Esta función también es llamada desde la API backend con HMAC (`multi-delete-client`). El HMAC protege la función `multi-delete-client`, pero `admin-delete-client` es callable directamente desde el frontend admin.

#### Verificación

```bash
# Test: sin token → 401
curl -X POST https://<ADMIN_SUPABASE_URL>/functions/v1/admin-create-client \
  -H "Content-Type: application/json" \
  -d '{"name":"test","email":"test@test.com","plan":"starter","slug":"test-hack"}' \
  -w "\nHTTP_CODE: %{http_code}\n"
# Esperado: HTTP_CODE: 401

# Test: con token admin → 200 (o 4xx por validación de payload)
curl -X POST https://<ADMIN_SUPABASE_URL>/functions/v1/admin-create-client \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer <ADMIN_JWT>" \
  -d '{"name":"test","email":"test@test.com","plan":"starter","slug":"test-e2e"}' \
  -w "\nHTTP_CODE: %{http_code}\n"
# Esperado: HTTP_CODE: 200 o 400 (validación)
```

---

### 0.3 RLS faltante en `client_secrets` {#03-rls-secrets}

**Hallazgo:** P1-7 — Tabla con MP access tokens encriptados, sin RLS.

**Archivo a crear:** `apps/api/migrations/backend/BACKEND_032_enable_rls_client_secrets.sql`

```sql
-- BACKEND_032: Habilitar RLS en client_secrets
-- Hallazgo: P1-7 del Baseline Evidence (2026-02-09)
-- Solo service_role puede acceder (backend server-side)

ALTER TABLE client_secrets ENABLE ROW LEVEL SECURITY;

CREATE POLICY "server_bypass"
ON client_secrets
FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');

-- Bloquear acceso anon/authenticated
-- (no se necesitan policies adicionales — solo el backend accede)
```

#### Verificación

```sql
-- Confirmar RLS habilitado
SELECT tablename, rowsecurity
FROM pg_tables
WHERE tablename = 'client_secrets' AND schemaname = 'public';
-- Esperado: rowsecurity = true
```

---

### 0.4 DevSeedingController — bloqueo en prod {#04-devseeding}

**Hallazgo:** P1-4 (subido a P0 por feedback TL) — Endpoints `/dev/seed-tenant`, `/dev/tenants`, `DELETE /dev/tenants/:slug` con `@AllowNoTenant()` y sin guards de auth.

**Estado actual verificado:**
- El **service** tiene `throw new ForbiddenException('Dev seeding is not available in production')` si `NODE_ENV === 'production'` ✅
- Pero el **módulo se carga incondicionalmente** (línea 132 de `app.module.ts`) → surface expuesta, loguea `⚠️ DevModule loaded in production mode`
- El check está en el **service** no en el **controller** — si alguien agrega un método que no pasa por ese service, queda abierto

**Archivo:** `apps/api/src/app.module.ts` (carga) + `apps/api/src/dev/dev.module.ts` (módulo)

**Cambio recomendado — Opción B del plan original (módulo condicional):**

```typescript
// app.module.ts — ANTES (línea 132):
    DevModule, // Dev tools for local testing (only in development)

// DESPUÉS:
    ...(process.env.NODE_ENV !== 'production' ? [DevModule] : []),
```

**Cambio complementario — Guard en controller como defensa en profundidad:**

```typescript
// dev-seeding.controller.ts — agregar:
import { UseGuards } from '@nestjs/common';
import { SuperAdminGuard } from '../guards/super-admin.guard';

@Controller('dev')
@AllowNoTenant()
@UseGuards(SuperAdminGuard)  // Defensa en profundidad: si el módulo se carga, requiere super_admin
export class DevSeedingController {
```

#### Verificación

```bash
# En prod (Railway): el módulo no debería cargar
# Buscar en logs: NO debe aparecer "DevModule loaded"

# Si carga (fallback guard): sin token → 401
curl -s -X POST https://api.novavision.lat/dev/seed-tenant \
  -H "Content-Type: application/json" \
  -d '{"slug":"hack-test"}' -w "\n%{http_code}\n"
# Esperado: 401 o 404 (si módulo no carga)
```

---

## Fase 0.5 — P1: Cerrar superficies auth API {#fase-05}

> Se ejecuta una vez completada Fase 0.

### 0.5.1 `GET /onboarding/resume` público {#051-resume}

**Hallazgo:** P1-2 — Permite lookup de sesión de onboarding por `user_id` UUID sin autenticación.

**Estado actual verificado:** ❌ **NO estaba hecho** — el endpoint sigue público sin guard (verificado directamente en código).

**Código actual** (`onboarding.controller.ts` L968-986):
```typescript
@AllowNoTenant()
@Get('resume')
@HttpCode(HttpStatus.OK)
async resumeOnboarding(@Query('user_id') userId: string) {
  if (!userId) throw new BadRequestException('user_id is required');
  const result = await this.onboardingService.resumeSession(userId);
  return result;
}
```

**Archivo:** `apps/api/src/onboarding/onboarding.controller.ts`

**Cambio:** Agregar `@UseGuards(BuilderSessionGuard)` al método `resume`, o validar que el `user_id` del query param coincida con el JWT del caller.

```typescript
// Opción A: Guard completo
@Get('resume')
@UseGuards(BuilderSessionGuard)
async resume(@Query('user_id') userId: string, @Req() req) {
  // Validar que userId === req.user.id (evitar IDOR)
  if (userId !== req.user?.id) throw new ForbiddenException();
  return this.onboardingService.resume(userId);
}

// Opción B: Validar token mínimo (menos intrusivo)
@Get('resume')
async resume(@Query('user_id') userId: string, @Req() req) {
  if (!req.user?.id) throw new UnauthorizedException('Token required');
  if (userId !== req.user.id) throw new ForbiddenException('Cannot access other sessions');
  return this.onboardingService.resume(userId);
}
```

#### Verificación

```bash
# Sin token → 401
curl -s "http://localhost:3000/onboarding/resume?user_id=any-uuid" -w "\n%{http_code}\n"
# Esperado: 401

# Con token de otro user → 403
curl -s "http://localhost:3000/onboarding/resume?user_id=OTHER_UUID" \
  -H "Authorization: Bearer <JWT_USER_A>" -w "\n%{http_code}\n"
# Esperado: 403
```

---

### 0.5.2 `CouponsController` sin guard {#052-coupons}

**Hallazgo:** P1-3 — `@AllowNoTenant()` a nivel de clase sin ningún guard.

**Estado actual verificado:** ❌ Guard está **comentado** en el código: `// @UseGuards(AuthGuard) // Protect endpoint? Yes, usually.`

**Archivo:** `apps/api/src/coupons/coupons.controller.ts`

**Opciones (elegir una):**

| Opción | Cambio | Impacto |
|--------|--------|---------|
| A | Quitar `@AllowNoTenant()` de la clase → tenant requerido | Rompe si se llama sin `x-tenant-slug` |
| B | Agregar `@UseGuards(BuilderSessionGuard)` a nivel clase | Solo builder puede validar cupones |
| C | Mover `@AllowNoTenant()` solo a métodos públicos necesarios y agregar guards a los demás | Granular, más seguro |

**Recomendación:** Opción C — mantener `@AllowNoTenant()` solo en el método `validate` si es necesario para onboarding, pero agregar `@UseGuards(BuilderSessionGuard)` a ese método.

```typescript
// ANTES:
@Controller('coupons')
@AllowNoTenant()
export class CouponsController {

// DESPUÉS:
@Controller('coupons')
export class CouponsController {
  
  @Post('validate')
  @AllowNoTenant()
  @UseGuards(BuilderSessionGuard) // Al menos requiere builder session
  async validate(@Body() dto: ValidateCouponDto) { ... }
}
```

---

### 0.5.3 Webhook MP inconsistente {#053-webhook}

**Hallazgo:** P1-8 — `mercadopago.service.ts` warn sin rechazar cuando falta `MP_WEBHOOK_SECRET`.

**Estado actual verificado:** Parcialmente mitigado por commit `27c3344` (validación de monto), pero la firma HMAC NO es fail-closed.

**Nota:** MP usa un esquema con `ts` + `v1` en el header `x-signature`. El commit BUG-006 trabajó esto. Verificar que la reconstrucción de firma esté completa.

**Archivo:** `apps/api/src/tenant-payments/mercadopago.service.ts`

**Cambio:** Hacer fail-closed en producción.

```typescript
// ANTES (warn solamente):
if (!this.configService.get('MP_WEBHOOK_SECRET')) {
  this.logger.warn('MP_WEBHOOK_SECRET not configured');
}

// DESPUÉS (fail-closed en producción):
const secret = this.configService.get('MP_WEBHOOK_SECRET');
if (!secret) {
  if (process.env.NODE_ENV === 'production') {
    this.logger.error('MP_WEBHOOK_SECRET required in production');
    throw new InternalServerErrorException('Webhook signature verification not configured');
  }
  this.logger.warn('MP_WEBHOOK_SECRET not configured — skipping signature check (dev only)');
}
```

---

### 0.5.4 `admin-sync-usage` sin auth {#054-sync}

**Hallazgo:** P1-1 — Funciones que escriben datos de uso sin autenticación.

**Archivos:**
- `apps/admin/supabase/functions/admin-sync-usage/index.ts`
- `apps/admin/supabase/functions/admin-sync-usage-batch/index.ts`

**Cambio:** Agregar auth. Como son funciones que podrían ser llamadas por cron, admitir JWT admin **o** `x-internal-key`:

```typescript
// Verificación de auth para sync functions
const authHeader = req.headers.get('Authorization');
const internalKey = req.headers.get('x-internal-key');
const expectedKey = Deno.env.get('INTERNAL_ACCESS_KEY');

if (internalKey && expectedKey && internalKey === expectedKey) {
  // OK — llamada interna (cron/worker)
} else if (authHeader?.startsWith('Bearer ')) {
  const admin = await requireAdmin(req);
  if (admin instanceof Response) return admin;
} else {
  return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 });
}
```

---

### 0.5.5 `super_admins` RLS disabled {#055-superadmins}

**Hallazgo:** P1-6 — Tabla de autorización con RLS explícitamente deshabilitado en Admin DB.

**Migración SQL a ejecutar en Admin DB:**

```sql
-- Habilitar RLS en super_admins
ALTER TABLE super_admins ENABLE ROW LEVEL SECURITY;

-- Solo service_role puede acceder (las Edge Functions y el backend usan service_role)
CREATE POLICY "server_bypass"
ON super_admins
FOR ALL
USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');

-- Lectura para que is_super_admin() funcione (usa auth.email())
CREATE POLICY "self_read"
ON super_admins
FOR SELECT
USING (email = auth.email());
```

> **Cuidado:** La función `is_super_admin()` consulta `super_admins` — verificar que se ejecuta con `SECURITY DEFINER` o con un rol que tenga bypass. Si no, la lectura podría fallar. Testear antes de desplegar.

#### Verificación

```sql
SELECT tablename, rowsecurity FROM pg_tables
WHERE tablename = 'super_admins' AND schemaname = 'public';
-- rowsecurity = true

-- Test: is_super_admin() sigue funcionando para admins reales
SELECT is_super_admin(); -- con JWT de super admin → true
```

---

## Fase 1 — P1/P2: RLS + Integridad + Storage {#fase-1}

### 1.1 RLS tablas Multitenant DB {#11-rls-multi}

**Tablas sin RLS:** `client_home_settings`, `home_sections`, `client_assets`

**Migración:** `BACKEND_033_enable_rls_missing_tables.sql`

```sql
-- Habilitar RLS en tablas que solo se acceden desde backend (service_role)

-- client_home_settings
ALTER TABLE client_home_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON client_home_settings
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');

-- home_sections
ALTER TABLE home_sections ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON home_sections
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');

-- client_assets
ALTER TABLE client_assets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON client_assets
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

---

### 1.2 RLS tablas Admin DB {#12-rls-admin}

**Tabla sin RLS:** `auth_handoff`

**Migración en Admin DB:**

```sql
ALTER TABLE auth_handoff ENABLE ROW LEVEL SECURITY;

CREATE POLICY "server_bypass" ON auth_handoff
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
```

---

### 1.3 `tenant_payment_events` scope fix {#13-tpe}

**Hallazgo:** P2-2 — `tenant_id` nullable sin FK — en AMBAS databases.

**Migración Multi DB:** `BACKEND_034_fix_tenant_payment_events.sql`

```sql
-- Paso 1: Backfill NULLs (investigar y asignar tenant correcto)
-- ANTES de ejecutar, verificar:
SELECT count(*) FROM tenant_payment_events WHERE tenant_id IS NULL;

-- Si hay registros huérfanos, decidir: borrar o asignar manualmente
-- DELETE FROM tenant_payment_events WHERE tenant_id IS NULL;

-- Paso 2: Hacer NOT NULL
ALTER TABLE tenant_payment_events
  ALTER COLUMN tenant_id SET NOT NULL;

-- Paso 3: Agregar FK (tenant_id referencia clients.id)
ALTER TABLE tenant_payment_events
  ADD CONSTRAINT fk_tpe_client
  FOREIGN KEY (tenant_id) REFERENCES clients(id) ON DELETE CASCADE;

-- NOTA: NO renombrar tenant_id → client_id.
-- Decisión TL: el rename es riesgoso por múltiples referencias en código
-- (incluido commit BUG-012 que movió la tabla entre DBs).
-- NOT NULL + FK es suficiente para garantizar integridad.
```

---

### 1.4 Storage: Policies + path consolidation {#14-storage}

**Hallazgo:** ST-1, ST-2 — Sin Storage Policies, 3 convenciones de path.

#### 1.4.1 Storage Policy (Supabase Dashboard → Storage → Policies)

```sql
-- Policy: solo el backend (service_role) puede subir/borrar
CREATE POLICY "service_upload" ON storage.objects
FOR INSERT TO service_role
WITH CHECK (bucket_id = 'product-images');

CREATE POLICY "service_delete" ON storage.objects
FOR DELETE TO service_role
USING (bucket_id = 'product-images');

-- Lectura pública (si el bucket es público)
CREATE POLICY "public_read" ON storage.objects
FOR SELECT TO anon, authenticated
USING (bucket_id = 'product-images');
```

#### 1.4.2 Consolidación de paths (cambio gradual)

**Acción:** Definir convención canónica y deprecar las otras.

| Convención | Estado | Acción |
|-----------|--------|--------|
| `clients/{clientId}/...` (path-builder.ts) | **Canónica** | Mantener |
| `{clientId}/...` (storage-path.helper.ts) | Legacy | Marcar deprecated, migrar gradualmente |
| QR sin prefix | Bug | Fix en `mercadopago.service.ts` — siempre incluir `clients/{clientId}/` |

**Archivo a modificar:** `apps/api/src/tenant-payments/mercadopago.service.ts` (L~870)

```typescript
// ANTES:
const qrPath = `${clientId}/orders/qr_${orderId}.png`;

// DESPUÉS:
const qrPath = `clients/${clientId}/orders/qr_${orderId}.png`;
```

---

### 1.5 Índices hot-path {#15-indices}

**Migración:** `BACKEND_035_add_hotpath_indexes.sql`

```sql
-- Órdenes: listado por tenant + fecha
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_client_created
ON orders (client_id, created_at DESC);

-- Órdenes por estado
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_orders_client_status_created
ON orders (client_id, status, created_at DESC);

-- Carritos por usuario
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_cart_items_client_user
ON cart_items (client_id, user_id);

-- Productos activos por tenant
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_products_client_active
ON products (client_id, active) WHERE active = true;

-- Pagos por tenant + orden
CREATE INDEX CONCURRENTLY IF NOT EXISTS idx_payments_client_order
ON payments (client_id, order_id);
```

> **Nota:** `CREATE INDEX CONCURRENTLY` no bloquea escrituras. Seguro para producción.

#### Verificación

```sql
-- Confirmar que el índice se usa en la query principal
EXPLAIN (ANALYZE, BUFFERS)
SELECT * FROM orders WHERE client_id = '<UUID>' ORDER BY created_at DESC LIMIT 20;
-- Debe mostrar Index Scan, NO Seq Scan
```

---

## Fase 2 — P1: Normalización plan_key {#fase-2}

**Hallazgo:** P1-5 — 9 valores en Multi vs 4 en Admin, `pro` vs `professional`/`premium`.

### Decisión canónica

| Plan Key | Billing Period | Multi DB legacy equivalentes |
|----------|---------------|------------------------------|
| `starter` | `monthly` / `annual` | `starter`, `starter_annual`, `basic` |
| `growth` | `monthly` / `annual` | `growth`, `growth_annual`, `professional` |
| `pro` | `monthly` / `annual` | `premium` |
| `enterprise` | `monthly` / `annual` | `enterprise`, `enterprise_annual` |

### Tareas (en orden estricto)

| # | Tarea | DB | Tipo |
|---|-------|----|------|
| 2.1 | Agregar `plan_key` y `billing_period` columns en `clients` (Multi DB) | Multi | Migración additive |
| 2.2 | Backfill `plan_key` y `billing_period` desde `clients.plan` legacy | Multi | Data migration |
| 2.3 | Actualizar código API para leer `plan_key` + `billing_period` (dual-read) | API | Code |
| 2.4 | Actualizar código API para escribir `plan_key` + `billing_period` (dual-write) | API | Code |
| 2.5 | Verificar sync service mapea correctamente | API | Test |
| 2.6 | Marcar `clients.plan` como deprecated | Multi | Documentation |
| 2.7 | (Futuro) Remover `clients.plan` y CHECK constraint legacy | Multi | Breaking migration |

### Migración 2.1 — Agregar columnas canónicas

```sql
-- BACKEND_036_add_canonical_plan_columns.sql

-- Paso 1: Agregar columnas
ALTER TABLE clients
  ADD COLUMN IF NOT EXISTS plan_key TEXT,
  ADD COLUMN IF NOT EXISTS billing_period TEXT DEFAULT 'monthly';

-- Paso 2: CHECK constraints canónicos
ALTER TABLE clients
  ADD CONSTRAINT clients_plan_key_check
  CHECK (plan_key IS NULL OR plan_key IN ('starter', 'growth', 'pro', 'enterprise'));

ALTER TABLE clients
  ADD CONSTRAINT clients_billing_period_check
  CHECK (billing_period IS NULL OR billing_period IN ('monthly', 'annual'));
```

### Migración 2.2 — Backfill

```sql
-- BACKEND_037_backfill_plan_key.sql

UPDATE clients SET
  plan_key = CASE plan
    WHEN 'basic' THEN 'starter'
    WHEN 'starter' THEN 'starter'
    WHEN 'starter_annual' THEN 'starter'
    WHEN 'professional' THEN 'growth'
    WHEN 'growth' THEN 'growth'
    WHEN 'growth_annual' THEN 'growth'
    WHEN 'premium' THEN 'pro'
    WHEN 'enterprise' THEN 'enterprise'
    WHEN 'enterprise_annual' THEN 'enterprise'
    ELSE plan -- fallback para valores inesperados
  END,
  billing_period = CASE
    WHEN plan LIKE '%_annual' THEN 'annual'
    ELSE 'monthly'
  END
WHERE plan_key IS NULL;

-- Verificar: no deben quedar NULLs
-- SELECT count(*) FROM clients WHERE plan_key IS NULL;
```

---

## Fase 3 — Outbox cross-DB {#fase-3}

**Objetivo:** Reemplazar dual-writes con patrón outbox idempotente.

### Tabla outbox (Admin DB)

```sql
-- Migración Admin DB
CREATE TABLE IF NOT EXISTS account_sync_outbox (
  id          BIGSERIAL PRIMARY KEY,
  event_key   TEXT NOT NULL UNIQUE,  -- idempotency: '{account_id}:{event_type}:{version}'
  account_id  UUID NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,
  event_type  TEXT NOT NULL,         -- 'account.created', 'account.updated', 'plan.changed', etc.
  payload     JSONB NOT NULL,
  status      TEXT NOT NULL DEFAULT 'pending'
              CHECK (status IN ('pending', 'processing', 'completed', 'failed', 'dlq')),
  attempts    INT NOT NULL DEFAULT 0,
  max_attempts INT NOT NULL DEFAULT 5,
  next_retry_at TIMESTAMPTZ DEFAULT NOW(),
  last_error  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  processed_at TIMESTAMPTZ
);

CREATE INDEX idx_outbox_pending ON account_sync_outbox (status, next_retry_at)
WHERE status IN ('pending', 'processing');

CREATE INDEX idx_outbox_account ON account_sync_outbox (account_id);
```

### Contrato de eventos

| event_type | Payload mínimo | Acción en Multi DB |
|-----------|----------------|-------------------|
| `account.created` | `{ slug, name, email, plan_key, billing_period }` | Upsert `clients` |
| `account.updated` | `{ slug, fields_changed: {...} }` | Update `clients` |
| `plan.changed` | `{ slug, old_plan, new_plan, billing_period }` | Update `clients.plan_key` + `billing_period` |
| `account.suspended` | `{ slug, reason }` | `clients.is_active = false` |
| `account.deleted` | `{ slug }` | Soft delete `clients.deleted_at = NOW()` |

### Worker (API backend)

```
Cron (cada 30s) → SELECT * FROM account_sync_outbox 
  WHERE status = 'pending' AND next_retry_at <= NOW()
  ORDER BY created_at LIMIT 10
  FOR UPDATE SKIP LOCKED
→ Procesar cada evento → Aplicar en Multi DB → Marcar completed
→ Si falla → attempts++ → next_retry_at = NOW() + backoff → Si attempts >= max → status = 'dlq'
```

---

## Fase 4 — Observabilidad y auditoría {#fase-4}

### 4.1 TTL/archiving

| Tabla | Retención | Acción |
|-------|-----------|--------|
| `account_sync_outbox` (completed) | 30 días | Cron: DELETE WHERE status='completed' AND processed_at < NOW()-30d |
| `mp_events` | 90 días | Cron o pg_partman |
| `webhook_events` | 90 días | Cron |
| `tenant_payment_events` | 1 año | Partitioning por mes |
| `lifecycle_events` | 1 año | Partitioning |

### 4.2 `admin_actions_audit` (Admin DB)

```sql
CREATE TABLE IF NOT EXISTS admin_actions_audit (
  id          BIGSERIAL PRIMARY KEY,
  actor_id    UUID NOT NULL,        -- auth.uid() del super_admin
  actor_email TEXT NOT NULL,
  action      TEXT NOT NULL,         -- 'client.created', 'client.deleted', 'plan.changed', etc.
  target_type TEXT,                  -- 'account', 'subscription', 'client'
  target_id   TEXT,                  -- UUID o slug
  payload     JSONB,                -- detalles del cambio
  ip_address  INET,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX idx_audit_actor ON admin_actions_audit (actor_id, created_at DESC);
CREATE INDEX idx_audit_target ON admin_actions_audit (target_type, target_id, created_at DESC);

ALTER TABLE admin_actions_audit ENABLE ROW LEVEL SECURITY;
CREATE POLICY "server_bypass" ON admin_actions_audit
FOR ALL USING (auth.role() = 'service_role')
WITH CHECK (auth.role() = 'service_role');
CREATE POLICY "superadmin_read" ON admin_actions_audit
FOR SELECT USING (is_super_admin());
```

### 4.3 Dashboard de jobs

- Endpoint `GET /admin/system/health` que devuelva:
  - Outbox pending count + oldest pending age
  - Last provisioning job status
  - Last sync cursor per client
  - Edge Function last invocation (if available)

---

## Checklist de verificación global {#checklist}

### Por Fase

| Fase | Verificación | Cómo |
|------|-------------|------|
| 0.1 | No hay secretos en historial Git | `git log --all --diff-filter=A -- '*.bak'` vacío |
| 0.1 | Secretos rotados y apps funcionan | Health checks post-rotación |
| 0.2 | Edge Functions requieren auth | `curl` sin token → 401 |
| 0.3 | `client_secrets` tiene RLS | `SELECT rowsecurity FROM pg_tables WHERE tablename='client_secrets'` |
| 0.5 | Endpoints sensibles requieren auth | Suite de tests negativos |
| 1.1 | Todas las tablas Multi con RLS | Query contra `pg_tables` |
| 1.3 | `tenant_payment_events.tenant_id` NOT NULL | `SELECT count(*) WHERE tenant_id IS NULL` = 0 |
| 1.4 | Storage Policies activas | Supabase Dashboard |
| 1.5 | Queries usan índices | `EXPLAIN ANALYZE` sin Seq Scan |
| 2 | Plan keys consistentes | `SELECT plan_key, count(*) FROM clients GROUP BY 1` = solo 4 valores |
| 3 | Outbox procesa sin duplicados | Replay test: mismo evento 3x → 1 efecto |
| 4 | Auditoría registra acciones admin | Crear/borrar client → row en `admin_actions_audit` |

### Métricas DoD global (del plan v2)

| Métrica | Target | Cómo medir |
|---------|--------|-----------|
| Superficies sin auth real | **0** | Inventario de `@AllowNoTenant()` sin guard |
| Tenant leakage paths | **0** | E2E: tenant A no accede datos de B |
| Plan key contracts | **1** | CHECK constraints idénticos cross-DB |
| Divergencias cross-DB sin outbox | **0** | Diff query entre Admin `nv_accounts` y Multi `clients` |
| Service keys en cliente | **0** | Build audit: `grep service_role dist/` |

---

## Orden de ejecución recomendado

```
SEMANA 1 (URGENTE — BLOCKER):
├── 0.1   Secretos Git → .env.production + rotación completa
├── 0.4   DevSeedingController → módulo condicional + guard
├── 0.2   Edge Functions auth (admin-create/delete-client)
└── 0.3   RLS client_secrets

SEMANA 2:
├── 0.5.1 Onboarding resume auth (NO hecho — sigue público)
├── 0.5.2 CouponsController guard (guard comentado)
├── 0.5.3 Webhook MP fail-closed (parcial — falta HMAC)
├── 0.5.4 admin-sync-usage auth
└── 0.5.5 super_admins RLS

SEMANA 3:
├── 1.1   RLS tablas Multi DB
├── 1.2   RLS tablas Admin DB
├── 1.3   tenant_payment_events NOT NULL + FK (sin rename)
├── 1.4   Storage policies + path consolidation
└── 1.5   Índices hot-path

SEMANA 4+ (pospuesto hasta cerrar seguridad):
├── 2     Plan key normalization
├── 3     Outbox cross-DB
└── 4     Observabilidad + auditoría
```

> **Nota:** Fases 2-4 son mejoras de consistencia y operabilidad. Se posponen
> deliberadamente hasta que todas las superficies de seguridad (Fases 0-1) estén
> cerradas. El plan key normalization es un cambio de esquema grande con impacto
> en sync, onboarding y billing — requiere estabilidad previa.

---

## Estado actual de ejecución

| Ítem | Estado | Evidencia |
|------|--------|-----------|
| **27c3344** RolesGuard 10 controllers | ✅ Completado | Commit desplegado |
| 0.1 Secretos Git | 🔴 Pendiente | `.env.production` sigue trackeado |
| 0.2 Edge Functions auth | 🔴 Pendiente | Confirmado: 0 líneas de auth |
| 0.3 RLS client_secrets | 🔴 Pendiente | Sin migración |
| 0.4 DevSeedingController | 🟡 Mitigado parcial | Service rechaza en prod, pero módulo se carga |
| 0.5.1 Resume | 🔴 Pendiente | Verificado: sigue público |
| 0.5.2 Coupons | 🔴 Pendiente | Guard comentado en código |
| 0.5.3 Webhook MP | 🟡 Parcial | Commit 27c3344 validó monto, falta HMAC fail-closed |
| 0.5.4 admin-sync-usage | 🔴 Pendiente | 0 líneas de auth |
| 0.5.5 super_admins RLS | 🔴 Pendiente | RLS disabled |
| 1.x - 4.x | 🔴 Pendiente | Todo |

---

**Siguiente paso:** Ejecutar Fase 0 — comenzando por 0.1 (secretos).

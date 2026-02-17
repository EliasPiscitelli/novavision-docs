# 🔧 Plan de Remediación Detallado — NovaVision Security Audit

**Fecha:** 2026-02-16
**Estado:** Pendiente de aprobación del TL
**Organización:** 🔴 CRÍTICOS → 🟠 MEJORAS → 🔵 SUGERENCIAS

> ⚠️ Todos los diffs son **propuestas**. NO se aplicarán sin aprobación explícita.

---

# 🔴 PARTE 1: CRÍTICOS (Implementar INMEDIATAMENTE)

Estos hallazgos representan **vectores de ataque activos** que podrían resultar en fuga de datos cross-tenant, escalamiento de privilegios o compromiso de PII.

---

## CRÍTICO-1: Path Traversal en Uploads (H-04)

### Problema
El helper `buildStorageObjectPath()` sanitiza la `category` pero **NO** sanitiza el `originalName`. Un atacante puede subir un archivo con nombre `../../otro-tenant/products/malware.jpg` y escribir en el bucket de otro tenant.

### Archivo afectado
`apps/api/src/common/utils/storage-path.helper.ts`

### Código actual (VULNERABLE)
```typescript
export function buildStorageObjectPath(
  clientId: string,
  category: string,
  originalName: string,
): string {
  const safeCategory = category.replace(/[^a-z0-9-_]/gi, '').toLowerCase();
  return `${clientId}/${safeCategory}/${uuidv4()}_${originalName}`;
  //                                              ^^^^^^^^^^^^^^^^
  //                                              SIN SANITIZAR
}
```

### Implementación propuesta
```typescript
import { v4 as uuidv4 } from 'uuid';
import * as path from 'path';

/**
 * Genera una ruta canónica multi-tenant para objetos en Storage cumpliendo la policy:
 * split_part(name,'/',1) = current_client_id()
 * Resultado: <clientId>/<category>/<uuid>_<sanitizedName>
 */
export function buildStorageObjectPath(
  clientId: string,
  category: string,
  originalName: string,
): string {
  const safeCategory = category.replace(/[^a-z0-9-_]/gi, '').toLowerCase();

  // Sanitizar originalName:
  // 1. Extraer solo el nombre base (elimina cualquier path traversal como ../../)
  // 2. Reemplazar caracteres peligrosos por underscore
  // 3. Limitar longitud para evitar problemas de filesystem
  const baseName = path.basename(originalName);
  const safeName = baseName
    .replace(/[^a-zA-Z0-9._-]/g, '_')  // Solo alfanuméricos, punto, guión, underscore
    .substring(0, 100);                  // Limitar a 100 caracteres

  return `${clientId}/${safeCategory}/${uuidv4()}_${safeName}`;
}
```

### Qué cambia
- `path.basename()` elimina cualquier componente de directorio (`../../` etc.)
- Regex reemplaza caracteres especiales por `_`
- Límite de 100 chars previene nombres extremadamente largos
- El UUID prefix ya existía y sigue garantizando unicidad

### Riesgo de la implementación
**Bajo.** El cambio es aditivo — solo modifica cómo se construye el filename final. No afecta la lógica de upload ni los archivos ya existentes.

### Test sugerido
```typescript
describe('buildStorageObjectPath', () => {
  it('debe sanitizar path traversal en originalName', () => {
    const result = buildStorageObjectPath('tenant-1', 'products', '../../evil/hack.jpg');
    expect(result).not.toContain('..');
    expect(result).toMatch(/^tenant-1\/products\/[a-f0-9-]+_hack\.jpg$/);
  });

  it('debe reemplazar caracteres especiales', () => {
    const result = buildStorageObjectPath('t1', 'logos', 'mi logo (1).png');
    expect(result).not.toContain(' ');
    expect(result).not.toContain('(');
    expect(result).toMatch(/mi_logo__1_\.png$/);
  });

  it('debe truncar nombres muy largos', () => {
    const longName = 'a'.repeat(200) + '.jpg';
    const result = buildStorageObjectPath('t1', 'products', longName);
    const filename = result.split('/').pop()!;
    // uuid (36) + _ (1) + safeName (max 100) = 137 max
    expect(filename.length).toBeLessThanOrEqual(137);
  });
});
```

---

## CRÍTICO-2: Header `x-client-id` inyectable (H-05)

### Problema
El helper `getClientId()` tiene un fallback que toma el `client_id` directamente del header `x-client-id` si `req.clientId` no está disponible. En rutas con `@AllowNoTenant()`, el TenantContextGuard no corre, por lo que `req.clientId` no se resuelve — y un atacante puede inyectar cualquier UUID como `x-client-id`.

### Archivo afectado
`apps/api/src/common/utils/client-id.helper.ts`

### Código actual (VULNERABLE)
```typescript
export function getClientId(req: Request): string {
  const clientId =
    req.clientId || (req.headers['x-client-id'] as string | undefined);
  //                ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  //                FALLBACK PELIGROSO: el header puede ser inyectado
  if (!clientId) {
    throw new BadRequestException(
      'Tenant context is required...',
    );
  }
  return clientId;
}
```

### Implementación propuesta
```typescript
import { Request } from 'express';
import { BadRequestException } from '@nestjs/common';

/**
 * Extrae el client_id EXCLUSIVAMENTE desde req.clientId,
 * que es resuelto y validado por TenantContextGuard.
 *
 * NUNCA se debe confiar en el header x-client-id directamente
 * porque puede ser inyectado por el cliente.
 *
 * Si una ruta usa @AllowNoTenant() y necesita client_id,
 * debe obtenerlo del usuario autenticado (req.user.resolvedClientId).
 */
export function getClientId(req: Request): string {
  // Solo usar el clientId resuelto por TenantContextGuard
  const clientId = req.clientId;

  if (!clientId) {
    throw new BadRequestException(
      'Tenant context is required. Provide x-tenant-slug header or use a tenant domain.',
    );
  }

  return clientId;
}

/**
 * Versión que intenta obtener client_id del contexto de tenant
 * o del usuario autenticado. Útil para rutas @AllowNoTenant()
 * que aún necesitan operar en un contexto de tenant.
 */
export function getClientIdOrFromUser(req: Request): string {
  const clientId =
    req.clientId ||
    (req as any).user?.resolvedClientId ||
    (req as any).user?.user_metadata?.client_id;

  if (!clientId) {
    throw new BadRequestException(
      'Tenant context is required. Authenticate or provide tenant context.',
    );
  }

  return clientId;
}
```

### Qué cambia
- Se elimina el fallback peligroso al header `x-client-id`
- Se crea `getClientIdOrFromUser()` para rutas que necesitan client_id sin TenantContextGuard pero con usuario autenticado
- El client_id ahora solo puede venir de fuentes validadas (guard o JWT)

### Impacto en código existente
Es necesario buscar todos los usos de `getClientId()` y verificar que:
1. Rutas CON TenantContextGuard → siguen funcionando igual (usan `req.clientId`)
2. Rutas con `@AllowNoTenant()` que llaman `getClientId()` → migrar a `getClientIdOrFromUser()`

### Búsqueda de impacto necesaria
```bash
grep -rn "getClientId" apps/api/src/ --include="*.ts" | grep -v "node_modules" | grep -v ".spec."
```

---

## CRÍTICO-3: DNI/PII con URL pública permanente (H-06)

### Problema
Las imágenes de DNI se suben correctamente al bucket `dni-uploads` pero se recuperan con `getPublicUrl()`, que genera URLs **permanentes y sin autenticación**. Cualquiera con la URL puede acceder al DNI.

### Archivo afectado
`apps/api/src/accounts/accounts.service.ts` (líneas ~243-260)

### Código actual (VULNERABLE)
```typescript
const { data: urlData } = supabaseAdmin.storage
  .from(bucket)
  .getPublicUrl(path);
//  ^^^^^^^^^^^^
//  URL permanente, sin auth, accesible por cualquiera

const updatePayload =
  side === 'front'
    ? { dni_front_url: urlData.publicUrl }
    : { dni_back_url: urlData.publicUrl };
```

### Implementación propuesta
```typescript
// 1. Subir normalmente (esto ya está bien)
const { error: uploadError } = await supabaseAdmin.storage
  .from(bucket)
  .upload(path, file.buffer, {
    contentType: file.mimetype,
    upsert: true,
  });

if (uploadError) {
  this.logger.error(`Error uploading DNI ${side}:`, uploadError);
  throw new Error(
    side === 'front'
      ? 'Error al subir imagen frontal'
      : 'Error al subir imagen dorso',
  );
}

// 2. Guardar solo el PATH relativo (no la URL pública)
const updatePayload =
  side === 'front'
    ? { dni_front_path: path }  // Guardar path, NO URL pública
    : { dni_back_path: path };

const { error: updateError } = await supabaseAdmin
  .from('nv_accounts')
  .update({
    ...updatePayload,
    updated_at: new Date().toISOString(),
  })
  .eq('id', accountId);

if (updateError) {
  this.logger.error('Error updating account DNI path:', updateError);
  throw new Error('Error al guardar imagen');
}

// 3. Generar URL firmada con expiración de 5 minutos (para respuesta inmediata)
const { data: signedData, error: signedError } = await supabaseAdmin.storage
  .from(bucket)
  .createSignedUrl(path, 300); // 300 segundos = 5 minutos

if (signedError) {
  this.logger.error('Error creating signed URL:', signedError);
  throw new Error('Error al generar URL segura');
}

return { url: signedData.signedUrl };
```

### Endpoint adicional necesario
Para que el admin pueda ver los DNI después:
```typescript
// accounts.controller.ts o accounts.service.ts
async getDniSignedUrl(accountId: string, side: 'front' | 'back'): Promise<string> {
  const adminClient = this.dbRouter.getAdminClient();
  const field = side === 'front' ? 'dni_front_path' : 'dni_back_path';

  const { data } = await adminClient
    .from('nv_accounts')
    .select(field)
    .eq('id', accountId)
    .single();

  const storedPath = data?.[field];
  if (!storedPath) throw new NotFoundException('DNI no encontrado');

  const { data: signedData, error } = await supabaseAdmin.storage
    .from('dni-uploads')
    .createSignedUrl(storedPath, 300);

  if (error) throw new Error('Error al generar URL segura');
  return signedData.signedUrl;
}
```

### Migración de DB necesaria
```sql
-- Agregar columnas de path (si no existen)
ALTER TABLE nv_accounts
  ADD COLUMN IF NOT EXISTS dni_front_path TEXT,
  ADD COLUMN IF NOT EXISTS dni_back_path TEXT;

-- Migrar datos existentes: extraer path de URL pública
-- NOTA: Solo ejecutar si hay datos con URL pública
UPDATE nv_accounts
SET dni_front_path = REGEXP_REPLACE(dni_front_url, '^https://[^/]+/storage/v1/object/public/dni-uploads/', '')
WHERE dni_front_url IS NOT NULL AND dni_front_path IS NULL;

UPDATE nv_accounts
SET dni_back_path = REGEXP_REPLACE(dni_back_url, '^https://[^/]+/storage/v1/object/public/dni-uploads/', '')
WHERE dni_back_url IS NOT NULL AND dni_back_path IS NULL;
```

### Riesgo
**Medio.** Requiere migración de DB y cambio en frontend para consumir signed URLs. Las URLs existentes seguirán siendo accesibles hasta que se reconfigure el bucket como privado.

---

## CRÍTICO-4: Endpoints sin guard de SuperAdmin (H-07 + H-08)

### Problema
`POST /admin/stats` no tiene `@UseGuards(SuperAdminGuard)` mientras todos los endpoints hermanos sí lo tienen. Los endpoints de `/admin/system/*` solo tienen `@AllowNoTenant()` sin ningún guard de autorización.

### Archivos afectados
1. `apps/api/src/admin/admin.controller.ts` — endpoint `POST /admin/stats`
2. `apps/api/src/observability/system.controller.ts` — todos los endpoints

### Código actual system.controller.ts (VULNERABLE — completo)
```typescript
@AllowNoTenant()
@Controller('admin/system')
export class SystemController {
  // ❌ No tiene @UseGuards(SuperAdminGuard) en la clase ni en métodos
  // Cualquier usuario autenticado puede acceder

  @Get('health')
  async health() { ... }

  @Get('audit/recent')
  async recentAudit() { ... }
}
```

### Implementación propuesta — system.controller.ts
```typescript
import { Controller, Get, UseGuards } from '@nestjs/common';
import { AllowNoTenant } from '../common/decorators/allow-no-tenant.decorator';
import { SuperAdminGuard } from '../guards/super-admin.guard';
import { SystemHealthService } from './system-health.service';
import { DbRouterService } from '../db/db-router.service';

@AllowNoTenant()
@UseGuards(SuperAdminGuard)   // ← AGREGAR: protege TODOS los endpoints de esta clase
@Controller('admin/system')
export class SystemController {
  constructor(
    private readonly healthService: SystemHealthService,
    private readonly dbRouter: DbRouterService,
  ) {}

  @Get('health')
  async health() {
    return this.healthService.getHealthReport();
  }

  @Get('audit/recent')
  async recentAudit() {
    try {
      const adminClient = this.dbRouter.getAdminClient();
      const { data, error } = await adminClient
        .from('admin_actions_audit')
        .select('*')
        .order('created_at', { ascending: false })
        .limit(100);

      if (error) {
        return { error: error.message };
      }
      return { count: data?.length ?? 0, entries: data ?? [] };
    } catch (err) {
      return { error: String(err) };
    }
  }
}
```

### Implementación propuesta — admin.controller.ts (solo el endpoint stats)
Buscar el endpoint `POST /admin/stats` y agregar `@UseGuards(SuperAdminGuard)`:
```typescript
  @UseGuards(SuperAdminGuard)   // ← AGREGAR
  @Post('stats')
  @HttpCode(HttpStatus.OK)
  async getStats(@Body() body: any) {
    // ... implementación existente
  }
```

### Búsqueda de impacto necesaria
```bash
# Buscar todos los endpoints en admin.controller.ts que NO tienen @UseGuards(SuperAdminGuard)
grep -n "@Post\|@Get\|@Patch\|@Delete\|@UseGuards" apps/api/src/admin/admin.controller.ts
```

### Riesgo
**Muy bajo.** Solo agrega un guard existente. No modifica lógica de negocio.

---

## CRÍTICO-5: `auth_bridge_codes` sin RLS (H-03)

### Problema
La tabla `auth_bridge_codes` en Admin DB tiene RLS **deshabilitado** y 0 policies. Contiene columnas `code`, `user_id`, `slug` — datos de autenticación.

### Implementación propuesta (SQL en Admin DB)
```sql
-- 1. Habilitar RLS
ALTER TABLE auth_bridge_codes ENABLE ROW LEVEL SECURITY;

-- 2. Solo el backend (service_role) puede leer/escribir
CREATE POLICY "auth_bridge_server_only"
  ON auth_bridge_codes
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- 3. Un usuario solo puede leer SU propio código (opcional, para frontend)
CREATE POLICY "auth_bridge_owner_read"
  ON auth_bridge_codes
  FOR SELECT
  USING (user_id = auth.uid());
```

### Riesgo
**Muy bajo.** La tabla tiene 0 filas actualmente. Si el código backend usa service_role para accederla (lo esperable), no se rompe nada.

---

## CRÍTICO-6: `order_items` sin policy de tenant (H-02)

### Problema
`order_items` no tiene columna `client_id` y solo tiene policies `server_bypass` y `Super Admin Access`. Cualquier lectura que no use service_role y no sea super_admin obtendrá 0 resultados (RLS lo bloquea), pero un super_admin vería TODOS los items de TODOS los tenants.

### Implementación propuesta (SQL en Backend DB)
```sql
-- Opción A: Policy via JOIN a orders (recomendada — no requiere migración de columna)
CREATE POLICY "order_items_tenant_via_order"
  ON order_items
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
        AND o.client_id = current_client_id()
    )
  );

-- Policy de escritura (INSERT/UPDATE/DELETE) — solo admin del tenant
CREATE POLICY "order_items_write_tenant_admin"
  ON order_items
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
        AND o.client_id = current_client_id()
    )
    AND is_admin()
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM orders o
      WHERE o.id = order_items.order_id
        AND o.client_id = current_client_id()
    )
    AND is_admin()
  );
```

### Verificación pre-aplicación
```sql
-- Verificar que current_client_id() y is_admin() existen como funciones
SELECT proname FROM pg_proc WHERE proname IN ('current_client_id', 'is_admin');

-- Verificar que orders tiene client_id
SELECT column_name FROM information_schema.columns
WHERE table_name = 'orders' AND column_name = 'client_id';

-- Contar order_items para dimensionar impacto
SELECT count(*) FROM order_items;
```

### Riesgo
**Medio.** El JOIN puede tener impacto de performance si hay muchos order_items. Crear índice:
```sql
CREATE INDEX IF NOT EXISTS idx_order_items_order_id ON order_items(order_id);
```

---

## CRÍTICO-7: Email hardcodeado en 78 policies RLS (H-01)

### Problema
47 tablas en Admin DB y 31 en Backend DB usan el email `novavision.contact@gmail.com` hardcodeado en policies RLS como check de super admin. Si esa cuenta es comprometida, el atacante tiene acceso total a 78 tablas.

### Análisis de impacto
Esta es la remediación más grande y riesgosa. Involucra reescribir 78+ policies en 2 bases de datos distintas.

### Implementación propuesta

**Paso 1: Crear tabla y función en Admin DB**
```sql
-- Ya existe `super_admins` según el guard, verificar estructura
-- Si no existe:
CREATE TABLE IF NOT EXISTS super_admins (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  email TEXT UNIQUE NOT NULL,
  created_at TIMESTAMPTZ DEFAULT now(),
  created_by TEXT
);

-- Insertar el super admin actual
INSERT INTO super_admins (email, created_by)
VALUES ('novavision.contact@gmail.com', 'migration')
ON CONFLICT (email) DO NOTHING;

-- Función helper para policies
CREATE OR REPLACE FUNCTION is_super_admin_by_table()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM super_admins
    WHERE email = (
      SELECT email FROM auth.users WHERE id = auth.uid()
    )
  );
$$;
```

**Paso 2: Crear función equivalente en Backend DB**
```sql
-- Backend DB: crear tabla local o consultar via foreign data wrapper
-- Opción simple: tabla local sincronizada
CREATE TABLE IF NOT EXISTS super_admins (
  email TEXT PRIMARY KEY,
  synced_at TIMESTAMPTZ DEFAULT now()
);

INSERT INTO super_admins (email)
VALUES ('novavision.contact@gmail.com')
ON CONFLICT DO NOTHING;

CREATE OR REPLACE FUNCTION is_super_admin_by_table()
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT EXISTS (
    SELECT 1 FROM super_admins
    WHERE email = (
      SELECT email FROM auth.users WHERE id = auth.uid()
    )
  );
$$;
```

**Paso 3: Script para reescribir policies (ejecutar tabla por tabla)**

Ejemplo para una tabla (`orders` en Backend DB):
```sql
-- Antes:
-- USING: (auth.jwt()->>'email' = 'novavision.contact@gmail.com')

-- Después:
DROP POLICY IF EXISTS "Super Admin Access" ON orders;
CREATE POLICY "Super Admin Access"
  ON orders
  FOR ALL
  USING (is_super_admin_by_table())
  WITH CHECK (is_super_admin_by_table());
```

### Plan de ejecución
1. Crear tablas y funciones en ambas DBs
2. Generar script SQL con todas las DROP + CREATE POLICY
3. Ejecutar en ambiente de staging/test
4. Verificar que el super admin sigue teniendo acceso
5. Aplicar en producción

### Riesgo
**ALTO.** Modifica 78 policies en producción. Si hay un error, puede bloquear acceso a tablas. **Ejecutar en una transacción y tener rollback preparado.** Hacer backup de las policies actuales antes:
```sql
SELECT tablename, policyname, cmd, qual, with_check
FROM pg_policies
WHERE qual::text LIKE '%novavision.contact@gmail.com%'
   OR with_check::text LIKE '%novavision.contact@gmail.com%';
```

> ⚠️ **Recomendación:** Dejar este para el final de los críticos. Ejecutar los demás primero, verificar que todo funcione, y después abordar este con un script generado automáticamente y revisado.

---

# 🟠 PARTE 2: MEJORAS (Implementar en Sprint Actual)

Estos hallazgos no tienen exploits inmediatos pero representan **debilidades estructurales** que facilitan ataques si otro vector se abre.

---

## MEJORA-1: Escalación implícita admin → super_admin (H-10)

### Problema
En `roles.guard.ts`, un admin del proyecto `admin` **sin `client_id`** es tratado como super_admin. Si un usuario pierde su `client_id` por bug o migración, escala privilegios.

### Archivo afectado
`apps/api/src/guards/roles.guard.ts` (líneas 48-53)

### Código actual
```typescript
if (
  roles.includes('super_admin') &&
  project === 'admin' &&
  user.role === 'admin' &&
  !userClientId
) {
  return true;  // ← admin sin client_id → tratado como super_admin
}
```

### Implementación propuesta
```typescript
// ELIMINAR el bloque completo de escalación implícita.
// Si alguien necesita acceso super_admin, debe tener role='super_admin'
// en su metadata Y pasar el SuperAdminGuard (que verifica la tabla super_admins).

// El bloque se reemplaza por un log de advertencia:
if (
  roles.includes('super_admin') &&
  project === 'admin' &&
  user.role === 'admin' &&
  !userClientId
) {
  // Log para auditoría — NO escalar privilegios
  const logger = new Logger('RolesGuard');
  logger.warn(
    `Admin user ${user.id} (${user.email}) from admin project has no client_id. ` +
    `Implicit super_admin escalation BLOCKED. User must have explicit super_admin role.`
  );
  throw new ForbiddenException(
    'Acceso denegado: Se requiere rol super_admin explícito',
  );
}
```

### Riesgo
**Bajo-Medio.** Verificar que ningún admin legítimo dependa de este flujo para acceder a endpoints super_admin. El `SuperAdminGuard` ya tiene su propia verificación vía tabla `super_admins`, por lo que este bypass en `RolesGuard` es redundante y peligroso.

---

## MEJORA-2: AuthMiddleware bypass por substring (H-11)

### Problema
`url.includes('/onboarding/')` permite bypass de auth en cualquier URL que contenga esa substring, p.ej. `/api/admin/malicious/onboarding/inject`.

### Archivo afectado
`apps/api/src/auth/auth.middleware.ts` (líneas 105-129)

### Código actual
```typescript
if (
  url.includes('/mercadopago/webhook') ||
  url.includes('/onboarding/') ||
  url.includes('/auth/signup') ||
  // ... más url.includes()
) {
  return next();
}
```

### Implementación propuesta
```typescript
// Lista de prefijos exactos que no requieren auth
const PUBLIC_PATH_PREFIXES = [
  '/mercadopago/webhook',
  '/mercadopago/notification',
  '/webhooks/mp/tenant-payments',
  '/webhooks/mp/platform-subscriptions',
  '/subscriptions/webhook',
  '/subscriptions/manage',
  '/health',
  '/auth/google/start',
  '/auth/google/callback',
  '/auth/confirm-email',
  '/auth/email-callback',
  '/auth/forgot-password',
  '/auth/reset-password',
  '/auth/signup',
  '/auth/login',
  '/auth/bridge/',
  '/oauth/callback',
  '/mp/oauth/start',
  '/onboarding/',
];

// Verificar con startsWith en lugar de includes
const isPublicPath = PUBLIC_PATH_PREFIXES.some(prefix =>
  url.startsWith(prefix)
);

if (isPublicPath) {
  return next();
}
```

### Qué cambia
- `url.includes()` → `url.startsWith()` — solo matchea si la URL **comienza** con el path
- Previene bypass como `/admin/onboarding/inject`
- La lista sigue siendo la misma, solo cambia el método de matching

### Riesgo
**Bajo.** `url` ya viene normalizado con `toLowerCase()`. Verificar que no haya rutas legítimas que se acceden con prefijo diferente (p.ej. `/api/onboarding/` vs `/onboarding/`).

---

## MEJORA-3: CSP con unsafe-eval + unsafe-inline en Web (H-12)

### Archivo afectado
`apps/web/netlify.toml` (línea 36)

### Implementación propuesta
```toml
[[headers]]
for = "/*"
  [headers.values]
  Cross-Origin-Opener-Policy = "same-origin-allow-popups"
  Cross-Origin-Embedder-Policy = "unsafe-none"
  # Eliminar Access-Control-Allow-Origin: * (ver MEJORA-6)
  Content-Security-Policy = "default-src 'self'; script-src 'self' 'nonce-{RANDOM}' blob: https://sdk.mercadopago.com https://www.googletagmanager.com https://http2.mlstatic.com; worker-src 'self' blob:; connect-src 'self' https://api.mercadopago.com https://novavision-production.up.railway.app https://*.railway.app https://http2.mlstatic.com https://*.supabase.co https://www.google-analytics.com https://www.googletagmanager.com wss:; img-src 'self' data: https://*.mlstatic.com https://*.supabase.co https://images.unsplash.com https://plus.unsplash.com https://placehold.co https://picsum.photos https://fastly.picsum.photos; font-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-src https://*.mercadopago.com https://*.mercadolibre.com"
```

### Notas
- Eliminar `'unsafe-eval'` — si MercadoPago SDK lo necesita, solo habilitarlo en la página de checkout vía headers específicos
- Idealmente eliminar `'unsafe-inline'` de script-src y usar nonces, pero requiere cambios en el build (Vite plugin)
- `'unsafe-inline'` en `style-src` es aceptable por ahora (styled-components lo necesita)

### Riesgo
**Medio.** Puede romper MercadoPago SDK o scripts de terceros. **Probar en staging primero.**

---

## MEJORA-4: Admin panel sin CSP (H-13)

### Archivo afectado
`apps/admin/netlify.toml`

### Implementación propuesta
Agregar al final del archivo:
```toml
[[headers]]
for = "/*"
  [headers.values]
  Content-Security-Policy = "default-src 'self'; script-src 'self' 'unsafe-inline'; connect-src 'self' https://novavision-production.up.railway.app https://*.supabase.co https://*.railway.app; img-src 'self' data: https://*.supabase.co; font-src 'self' data:; style-src 'self' 'unsafe-inline'; frame-src 'none'"
  X-Frame-Options = "DENY"
  X-Content-Type-Options = "nosniff"
  Strict-Transport-Security = "max-age=31536000; includeSubDomains"
  Referrer-Policy = "strict-origin-when-cross-origin"
  Permissions-Policy = "camera=(), microphone=(), geolocation=()"
```

### Riesgo
**Bajo.** Es aditivo — agrega headers que no existían.

---

## MEJORA-5: AnyFilesInterceptor sin límites (H-15)

### Archivo afectado
`apps/api/src/products/products.controller.ts`

### Implementación propuesta
```typescript
@UseInterceptors(AnyFilesInterceptor({
  limits: {
    files: 10,                    // Máximo 10 archivos por request
    fileSize: 5 * 1024 * 1024,    // Máximo 5MB por archivo
  },
  fileFilter: (_req, file, cb) => {
    // Solo aceptar imágenes
    const allowedMimes = ['image/jpeg', 'image/png', 'image/webp', 'image/gif'];
    if (allowedMimes.includes(file.mimetype)) {
      cb(null, true);
    } else {
      cb(new Error(`Tipo de archivo no permitido: ${file.mimetype}`), false);
    }
  },
}))
```

### Riesgo
**Bajo.** Solo limita uploads — no cambia lógica existente.

---

## MEJORA-6: `internal_key` en sessionStorage (H-09)

### Problema
El secreto de super admin viaja por URL query/hash, se persiste en `sessionStorage`, y se envía como header. Vulnerable a XSS.

### Archivos afectados
- `apps/admin/src/services/api/nestjs.js` (L75, L81)
- `apps/admin/src/components/SuperAdminVerifyModal.jsx` (L34)
- `apps/admin/src/pages/LoginPage/index.jsx` (L42, L53)

### Implementación propuesta (cambio de arquitectura)

**Fase 1 (inmediata):** Al menos no pasar la key por URL:
```jsx
// LoginPage/index.jsx — ELIMINAR la lectura de key desde URL
// La key solo debe ingresarse manualmente via SuperAdminVerifyModal
useEffect(() => {
  // Ya NO tomar key de URL params ni hash
  const existingKey = sessionStorage.getItem('internal_key');
  if (existingKey) {
    setAuthorized(true);
  } else {
    // Mostrar modal de verificación en lugar de redirigir
    window.dispatchEvent(new Event('super-admin-verify-needed'));
  }
}, []);
```

**Fase 2 (sprint siguiente):** Migrar a httpOnly cookie:
- El backend setea un cookie httpOnly con el internal_key después de verificación
- El frontend no almacena ni envía la key manualmente
- Elimina todo `sessionStorage.getItem/setItem('internal_key')`

### Riesgo
**Fase 1: Bajo** (solo cambia de dónde viene la key). **Fase 2: Medio** (requiere cambios en backend + frontend).

---

## MEJORA-7: SECURITY DEFINER sin SET search_path (H-19)

### Problema
~20 funciones SECURITY DEFINER en ambas DBs no tienen `SET search_path`, lo que permite search_path injection.

### Implementación propuesta (ejecutar en ambas DBs)

Ejemplo para las funciones más críticas:
```sql
-- Backend DB: funciones de encriptación de MP tokens
CREATE OR REPLACE FUNCTION decrypt_mp_token(encrypted_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp  -- ← AGREGAR
AS $$
-- ... cuerpo existente sin modificar
$$;

CREATE OR REPLACE FUNCTION encrypt_mp_token(plain_value TEXT)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp  -- ← AGREGAR
AS $$
-- ... cuerpo existente sin modificar
$$;

-- Admin DB: funciones críticas
-- Repetir para: is_super_admin, get_app_secret, claim_slug_final, etc.
```

### Cómo obtener la lista completa
```sql
SELECT p.proname, pg_get_functiondef(p.oid)
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.prosecdef = true
  AND (p.proconfig IS NULL OR NOT p.proconfig::text LIKE '%search_path%');
```

### Riesgo
**Bajo.** Solo agrega una directiva de configuración. No modifica la lógica de la función.

---

## MEJORA-8: JWT parcial logueado en producción (H-17)

### Archivo afectado
`apps/admin/src/services/api/nestjs.js` (líneas 53-57)

### Código actual
```javascript
console.log('[API] Session check:', {
  hasSession: !!session,
  hasToken: !!session?.access_token,
  tokenStart: session?.access_token
    ? session.access_token.substring(0, 10) + '...'
    : 'NONE',
});
```

### Implementación propuesta
```javascript
// Solo loguear en desarrollo, nunca en producción
if (import.meta.env.DEV) {
  console.log('[API] Session check:', {
    hasSession: !!session,
    hasToken: !!session?.access_token,
  });
}
```

### Riesgo
**Nulo.** Solo elimina un log.

---

## MEJORA-9: Código legacy localStorage.getItem("token") (H-18)

### Archivos afectados
- `apps/admin/src/components/IdentitySettingsTab.tsx` (L168, L190)
- `apps/admin/src/hooks/usePalettes.ts` (L45)

### Implementación propuesta
Reemplazar `localStorage.getItem("token")` por la sesión de Supabase:
```typescript
// Antes:
const token = localStorage.getItem("token");
headers: { Authorization: `Bearer ${token}` }

// Después:
const { data: { session } } = await supabase.auth.getSession();
const token = session?.access_token;
if (!token) throw new Error('No authenticated session');
headers: { Authorization: `Bearer ${token}` }
```

O mejor aún, usar el API client centralizado (`nestjs.js`) que ya maneja la sesión automáticamente.

---

# 🔵 PARTE 3: SUGERENCIAS (Planificar para Próximas Semanas)

Deuda técnica y hardening que no tiene urgencia inmediata pero mejora la postura de seguridad general.

---

## SUGERENCIA-1: `provisioning_job_steps` sin RLS (H-20)

```sql
ALTER TABLE provisioning_job_steps ENABLE ROW LEVEL SECURITY;

CREATE POLICY "pjs_server_only"
  ON provisioning_job_steps
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

---

## SUGERENCIA-2: Security headers faltantes en Web (H-21)

Agregar a `apps/web/netlify.toml`:
```toml
  Strict-Transport-Security = "max-age=31536000; includeSubDomains"
  X-Frame-Options = "SAMEORIGIN"
  X-Content-Type-Options = "nosniff"
  Referrer-Policy = "strict-origin-when-cross-origin"
  Permissions-Policy = "camera=(), microphone=(), geolocation=()"
```

---

## SUGERENCIA-3: ngrok en CORS de producción (H-23)

En `apps/api/src/main.ts`, la línea:
```typescript
if (normalized.endsWith('.ngrok-free.app')) return true;
```

Cambiar a:
```typescript
if (!isProd && normalized.endsWith('.ngrok-free.app')) return true;
```

---

## SUGERENCIA-4: CASCADE DELETE → RESTRICT (H-25)

Auditar todas las FKs con `ON DELETE CASCADE` en la tabla `clients`:
```sql
SELECT
  tc.table_name,
  tc.constraint_name,
  rc.delete_rule
FROM information_schema.referential_constraints rc
JOIN information_schema.table_constraints tc ON tc.constraint_name = rc.constraint_name
WHERE rc.delete_rule = 'CASCADE'
  AND EXISTS (
    SELECT 1 FROM information_schema.constraint_column_usage ccu
    WHERE ccu.constraint_name = rc.unique_constraint_name
      AND ccu.table_name = 'clients'
  );
```

Cambiar a `ON DELETE RESTRICT` y agregar soft delete con `deleted_at TIMESTAMPTZ`.

---

## SUGERENCIA-5: `Access-Control-Allow-Origin: *` en Web (H-14)

Reemplazar por un edge function en Netlify que setee el header dinámicamente basado en el origen:
```javascript
// netlify/edge-functions/cors-dynamic.js
export default async (request, context) => {
  const response = await context.next();
  const origin = request.headers.get('origin');

  // Solo permitir orígenes del propio tenant
  if (origin && origin.endsWith('.novavision.lat')) {
    response.headers.set('Access-Control-Allow-Origin', origin);
  }

  return response;
};
```

---

## SUGERENCIA-6: Rate limiting en uploads (H-27)

Agregar throttle decorator a endpoints de upload:
```typescript
import { Throttle } from '@nestjs/throttler';

@Throttle({ default: { limit: 20, ttl: 60000 } }) // 20 uploads por minuto
@Post('upload')
async uploadFile(...) { ... }
```

---

## SUGERENCIA-7: Doble policy en order_payment_breakdown (H-28)

```sql
-- Revisar y eliminar la policy duplicada
SELECT policyname, cmd, qual FROM pg_policies WHERE tablename = 'order_payment_breakdown';
-- Eliminar la redundante
DROP POLICY IF EXISTS "opb_select_admin" ON order_payment_breakdown;
-- Mantener solo opb_select_tenant + server_bypass
```

---

# 📋 Orden de Ejecución Recomendado

| # | Item | Tipo | Esfuerzo | Riesgo | Dependencias |
|---|------|------|----------|--------|-------------|
| 1 | Storage path sanitization | CRÍTICO-1 | 30 min | Bajo | Ninguna |
| 2 | Eliminar fallback x-client-id | CRÍTICO-2 | 1h | Bajo | Buscar usages |
| 3 | Guards en system + admin/stats | CRÍTICO-4 | 30 min | Muy bajo | Ninguna |
| 4 | RLS en auth_bridge_codes | CRÍTICO-5 | 30 min | Muy bajo | Acceso DB |
| 5 | Policy tenant en order_items | CRÍTICO-6 | 1h | Medio | Acceso DB |
| 6 | Auth bypass substring→startsWith | MEJORA-2 | 1h | Bajo | Ninguna |
| 7 | File upload limits + MIME | MEJORA-5 | 30 min | Bajo | Ninguna |
| 8 | Security headers admin | MEJORA-4 | 30 min | Bajo | Ninguna |
| 9 | DNI URL pública→signed | CRÍTICO-3 | 3h | Medio | Migración DB |
| 10 | Escalación admin→super_admin | MEJORA-1 | 1h | Bajo-Medio | Verificar flujos |
| 11 | Eliminar key de URL | MEJORA-6 Fase 1 | 1h | Bajo | Ninguna |
| 12 | SET search_path funciones | MEJORA-7 | 2h | Bajo | Acceso DB |
| 13 | Limpiar logs JWT + legacy code | MEJORA-8, 9 | 30 min | Nulo | Ninguna |
| 14 | CSP en web (quitar unsafe-eval) | MEJORA-3 | 2h | Medio | Testing |
| 15 | Reescribir 78 policies email | CRÍTICO-7 | 1-2 días | ALTO | Script + backup |
| 16 | Sugerencias 1-7 | SUGERENCIAS | 1 día | Bajo | Independientes |

---

*Documento generado como referencia. Todos los cambios requieren aprobación del TL antes de aplicarse.*

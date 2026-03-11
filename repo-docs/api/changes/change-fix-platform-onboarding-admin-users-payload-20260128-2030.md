# Cambio: Payload mínimo y rol 'client' para usuarios de plataforma

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: 
  - apps/api/src/auth/auth.service.ts (handleSessionAndUser, ensureMembership)
  - apps/admin/docs/sql/migration-add-client-role.sql
  - apps/admin/docs/sql/admin-schema.sql

## Resumen
Se implementaron 3 fixes para resolver el login OAuth de usuarios de la plataforma (client_id='platform') en Admin DB:
1. **Payload mínimo en INSERT**: Solo inserta columnas existentes en Admin DB (id, email, client_id, role)
2. **SELECT condicional**: Usa campos limitados para platform, '*' para tenants
3. **Rol 'client'**: Cambia defaultRole de 'user' a 'client' para cumplir con constraint de Admin DB

## Por qué
El Admin DB tiene schema limitado comparado con Tenant DB:
- No tiene columnas: `metadata`, `personal_info`, `terms_accepted`
- El constraint `users_role_check` solo acepta: 'admin', 'client', 'manager', 'viewer', 'super_admin'
- El SELECT '*' fallaba por columnas inexistentes

### Errores resueltos
1. Error `PGRST204`: Columnas inexistentes en INSERT
2. Error en SELECT: Columnas inexistentes al hacer SELECT '*'
3. Error `23514`: Violación de constraint por rol 'user' inválido

## Cambios en el código

### auth.service.ts - handleSessionAndUser (línea ~1005-1180)

```typescript
// Detección de plataforma
const isPlatform = this.isPlatformClientId(effectiveClientId);

// SELECT condicional
const selectFields = isPlatform
  ? 'id, email, client_id, role'  // Admin DB: campos mínimos
  : '*';                            // Tenant DB: todos los campos

// Rol por defecto
const defaultRole = isSuperAdmin 
  ? 'super_admin' 
  : isPlatform 
    ? 'client'      // Platform users en Admin DB
    : 'user';       // Store customers en Tenant DB

// mergedUser condicional (excluye campos no existentes en Admin DB)
const mergedUser = {
  id: existing.id || userId,
  email: existing.email || email,
  client_id: existing.client_id ?? normalizedClientId,
  role: existing.role || defaultRole,
  ...(isPlatform 
    ? {} 
    : {
        personal_info: existing.personal_info || personal_info,
        terms_accepted: existing.terms_accepted ?? false,
      }
  ),
};
```

### auth.service.ts - ensureMembership (línea ~1180-1270)

```typescript
private async ensureMembership(
  userId: string,
  clientId: string | null,
  email: string,
  defaultRole: 'user' | 'admin' | 'super_admin' | 'client' = 'user',  // Añadido 'client'
  personal_info: any = {},
)

// INSERT condicional
const insertObj = this.isPlatformClientId(clientId)
  ? { id: userId, email, client_id: null, role: defaultRole }  // Admin DB: payload mínimo
  : { id: userId, email, client_id: null, role: defaultRole,   // Tenant DB: payload completo
      personal_info, terms_accepted: false, 
      metadata: { createdAt: new Date().toISOString() } };
```

## Migración de base de datos

**Archivo**: `apps/admin/docs/sql/migration-add-client-role.sql`

Esta migración actualiza el constraint de la tabla `users` en Admin DB para aceptar el rol 'client' y 'super_admin':

```sql
-- Drop existing check constraint
ALTER TABLE public.users DROP CONSTRAINT IF EXISTS users_role_check;

-- Recreate constraint with 'client' and 'super_admin' included
ALTER TABLE public.users 
ADD CONSTRAINT users_role_check 
CHECK (role IN ('admin', 'client', 'manager', 'viewer', 'super_admin'));

-- Update default value to 'client' for new users
ALTER TABLE public.users 
ALTER COLUMN role SET DEFAULT 'client';
```

**Aplicar en Admin DB (Supabase)**:
```bash
# Conectarse al Admin DB y ejecutar:
psql <ADMIN_DB_URL> -f apps/admin/docs/sql/migration-add-client-role.sql
```

## Cómo probar

### 1. Aplicar migración SQL
Primero ejecutar la migración en Admin DB de Supabase.

### 2. Probar OAuth con platform
```bash
# URL de prueba (ajustar según entorno)
https://<api-url>/auth/google?cid=platform
```

### 3. Verificar en logs
- No debe haber error PGRST204 (columnas inexistentes)
- No debe haber error 23514 (constraint violation)
- Debe crear user con rol 'client' en Admin DB

### 4. Verificar en DB
```sql
-- Verificar usuarios de plataforma
SELECT id, email, role, client_id 
FROM users 
WHERE client_id IS NULL;

-- Debe mostrar usuarios con role='client' o 'super_admin'
```

### 5. Probar que no rompió login de tenants
```bash
# OAuth desde tienda específica
https://<api-url>/auth/google?cid=<real-client-uuid>
```
Debe seguir funcionando correctamente con role='user' en Tenant DB.

## Archivos no requeridos cambios adicionales

Revisé los siguientes archivos y **NO requieren cambios**:
- `guards/roles.guard.ts`: Compara strings, no tiene tipos hardcodeados
- `guards/super-admin.guard.ts`: Verifica tabla super_admins, independiente del rol
- `guards/tenant-context.guard.ts`: Lee rol sin validación de tipo

## Notas de seguridad
- Service role bypass sigue funcionando (auth.role() = 'service_role')
- RLS policies no afectadas (no se basan en tipos TypeScript)
- Aislamiento por tenant preservado (filtros por client_id intactos)
- El rol 'client' es apropiado para usuarios que gestionan su cuenta desde Admin Dashboard

## Riesgos y rollback

**Riesgos**: Bajo. Solo afecta flujo OAuth de plataforma.

**Rollback**:
Si hay problemas, revertir:
1. auth.service.ts a versión anterior
2. Migración SQL:
```sql
ALTER TABLE public.users DROP CONSTRAINT users_role_check;
ALTER TABLE public.users ADD CONSTRAINT users_role_check 
CHECK (role IN ('admin', 'manager', 'viewer'));
```


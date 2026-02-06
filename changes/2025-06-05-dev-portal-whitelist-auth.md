# Cambio: Dev Portal Whitelist Authentication

- **Autor**: agente-copilot
- **Fecha**: 2025-06-05
- **Rama**: feature/automatic-multiclient-onboarding

---

## Resumen

Se implementó un sistema de autenticación basado en whitelist para el Dev Portal, reemplazando el token hardcodeado (`nova-dev-2024`) por un sistema seguro con tabla en Supabase, RLS y gestión desde el Admin Dashboard.

## Por qué

El token hardcodeado presentaba riesgos de seguridad:
- Cualquier dev con acceso al código podía ver el token
- No había forma de revocar acceso a usuarios individuales
- No había auditoría de quién accedía al Dev Portal

## Archivos Creados

### API (apps/api)

| Archivo | Descripción |
|---------|-------------|
| `migrations/admin/20260205_create_dev_portal_whitelist.sql` | Tabla `dev_portal_whitelist` con RLS |
| `src/dev/dev-portal-access.service.ts` | Service con checkAccess + CRUD |
| `src/dev/dev-portal.controller.ts` | Controller con endpoints verify-access + CRUD |

### Web (apps/web)

| Archivo | Descripción |
|---------|-------------|
| `src/__dev/components/RequireDevPortalAccess.jsx` | Guard component de autenticación |

### Admin (apps/admin)

| Archivo | Descripción |
|---------|-------------|
| `src/pages/AdminDashboard/DevPortalWhitelistView.jsx` | UI CRUD para gestionar whitelist |

## Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| `apps/api/src/dev/dev.module.ts` | Agregado DevPortalController, DevPortalAccessService, JwtModule |
| `apps/web/src/__dev/DevPortalApp.jsx` | Reemplazado token hardcodeado por guard (con localhost bypass) |
| `apps/admin/src/App.jsx` | Agregada ruta `/admin/dev-whitelist` |
| `apps/admin/src/pages/AdminDashboard/index.jsx` | Agregado nav item "Dev Portal Whitelist" |

## Schema de Base de Datos

```sql
CREATE TABLE dev_portal_whitelist (
  email citext PRIMARY KEY,
  enabled boolean NOT NULL DEFAULT true,
  note text,
  created_by uuid REFERENCES auth.users(id),
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);
```

### Políticas RLS

- **super_admin**: ALL access
- **authenticated**: SELECT solo su propio email
- **service_role**: bypass completo

## Endpoints

| Método | Ruta | Descripción | Auth |
|--------|------|-------------|------|
| GET | `/dev/portal/verify-access` | Verifica si el usuario tiene acceso | JWT |
| GET | `/dev/portal/whitelist` | Lista todos los emails | Super Admin |
| POST | `/dev/portal/whitelist` | Agrega email a whitelist | Super Admin |
| PATCH | `/dev/portal/whitelist/:email` | Actualiza entrada | Super Admin |
| DELETE | `/dev/portal/whitelist/:email` | Elimina entrada | Super Admin |

## Modelo de Seguridad

```
┌─────────────────────────────────────────────────────────────┐
│ Dev Portal Request                                           │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ ¿Es localhost?                                               │
│ SÍ → Acceso libre (desarrollo local)                         │
│ NO → Continuar verificación                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ ¿Tiene sesión válida (JWT)?                                  │
│ NO → Redirect a /auth (login)                                │
│ SÍ → Continuar verificación                                  │
└──────────────────────┬──────────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────────┐
│ ¿Email está en whitelist + enabled=true?                     │
│ NO → Mostrar página 403 "Acceso denegado"                    │
│ SÍ → Renderizar Dev Portal                                   │
└─────────────────────────────────────────────────────────────┘
```

## Cómo Probar

### 1. Aplicar migración

```bash
# En Supabase Admin DB, ejecutar el SQL:
# apps/api/migrations/admin/20260205_create_dev_portal_whitelist.sql
```

### 2. Agregar email a whitelist

Desde Admin Dashboard → Dev Portal Whitelist → Add Email

O directamente en DB:
```sql
INSERT INTO dev_portal_whitelist (email, enabled, note)
VALUES ('dev@example.com', true, 'Developer access');
```

### 3. Probar acceso

```bash
# Iniciar API
cd apps/api && npm run start:dev

# Iniciar Web
cd apps/web && npm run dev

# Acceder al Dev Portal (debe redirigir a login si no hay sesión)
open http://localhost:5173/__dev
```

## Notas de Seguridad

- El `SERVICE_ROLE_KEY` solo se usa server-side (nunca expuesto en frontend)
- Las políticas RLS aseguran que solo super_admin puede gestionar la whitelist
- El bypass de localhost es intencional para facilitar desarrollo local
- Todos los endpoints CRUD usan `BuilderOrSupabaseGuard` para validar JWT

## Rollback

Si es necesario revertir:

1. Restaurar `DevPortalApp.jsx` con el token hardcodeado:
   ```jsx
   const DEV_TOKEN = 'nova-dev-2024';
   ```

2. Remover archivos creados (controller, service, guard, view)

3. Revertir cambios en `dev.module.ts`, `App.jsx`, `index.jsx`

4. Opcional: eliminar tabla
   ```sql
   DROP TABLE IF EXISTS dev_portal_whitelist;
   ```

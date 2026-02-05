# Cambio: Corrección tenant bootstrap y DevModule para testing local

- **Autor:** Copilot Agent
- **Fecha:** 2026-02-03
- **Rama:** main (desarrollo local)
- **Tipo:** Fix + Feature

## Archivos Modificados

### Nuevos archivos (DevModule)
- `src/dev/dev.module.ts` - Módulo para herramientas de desarrollo
- `src/dev/dev-seeding.controller.ts` - Controller con endpoints `/dev/*`
- `src/dev/dev-seeding.service.ts` - Servicio para crear tenants de prueba

### Archivos modificados
- `src/app.module.ts` - Import de DevModule y exclusiones de auth
- `src/tenant/tenant.service.ts` - Fix: usar backend DB en vez de admin DB
- `src/db/db-router.service.ts` - Fix: eliminar uso de `client_id_backend` deprecado

## Resumen de Cambios

### 1. DevModule para Testing Local (Feature)
Se creó un módulo de desarrollo que permite crear tenants de prueba sin pasar por el flujo completo de onboarding.

**Endpoints agregados:**
- `POST /dev/seed-tenant` - Crea un tenant completo (nv_accounts + clients)
- `GET /dev/tenants` - Lista tenants de desarrollo
- `DELETE /dev/tenants/:slug` - Elimina un tenant de desarrollo

**Uso:**
```bash
# Crear tenant de prueba
curl -X POST http://localhost:3000/dev/seed-tenant \
  -H "Content-Type: application/json" \
  -d '{"slug":"my-store","email":"test@demo.com"}'

# Probar bootstrap
curl -H "x-tenant-slug: my-store" http://localhost:3000/tenant/bootstrap

# Abrir storefront
open http://localhost:5173?tenant=my-store
```

### 2. Fix: TenantService buscaba en DB incorrecta
**Problema:** `getPublicTenantInfo()` usaba `adminClient.from('clients')` pero la tabla `clients` está en la Backend DB (Multicliente), no en Admin DB.

**Solución:** Cambiado a usar `backendClient` via `getClientBackendCluster()`.

### 3. Fix: DbRouterService usaba columna deprecada
**Problema:** `getClientBackendCluster()` buscaba por `nv_accounts.client_id_backend` que ya no existe.

**Solución:** Ahora busca primero el `nv_account_id` del client en backend DB, luego obtiene el `backend_cluster_id` del account en admin DB.

## Por Qué Se Hizo

El endpoint `/tenant/bootstrap` no funcionaba en desarrollo local porque:
1. No había datos de prueba disponibles
2. El servicio buscaba en la base de datos incorrecta
3. Una columna deprecada (`client_id_backend`) causaba errores silenciosos

## Cómo Probar

```bash
# 1. Iniciar API
cd apps/api && npm run start:dev

# 2. Crear tenant de prueba
curl -X POST http://localhost:3000/dev/seed-tenant \
  -H "Content-Type: application/json" \
  -d '{"slug":"test-store","email":"test@local.dev"}'

# 3. Verificar bootstrap
curl -H "x-tenant-slug: test-store" http://localhost:3000/tenant/bootstrap
# Debería devolver: {"success":true,"tenant":{"id":"...","slug":"test-store",...}}

# 4. Verificar status
curl -H "x-tenant-slug: test-store" http://localhost:3000/tenant/status
# Debería devolver: {"exists":true,"slug":"test-store","store_status":"live",...}

# 5. Probar storefront (si web está corriendo)
open http://localhost:5173?tenant=test-store
```

## Notas de Seguridad

- El DevModule verifica `NODE_ENV !== 'production'` antes de ejecutar cualquier operación
- Los endpoints `/dev/*` rechazan requests con 403 Forbidden en producción
- Los tenants creados tienen `metadata.dev_seeded: true` para identificación

## Impacto

- **Backend:** Nuevo módulo y fixes en tenant resolution
- **Frontend:** Sin cambios requeridos
- **Base de datos:** Compatible con schemas existentes (no requiere migraciones)

## Riesgos

- **Bajo:** El DevModule solo funciona en development
- **Mitigación:** Verificación explícita de NODE_ENV en cada operación

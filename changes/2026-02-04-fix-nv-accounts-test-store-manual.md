# Fix: Registro faltante en nv_accounts para test-store-manual

- **Autor:** Copilot Agent
- **Fecha:** 2026-02-04
- **Rama:** develop (API), feature/multitenant-storefront (Web)
- **Ticket:** N/A - Auditoría de flujo Onboarding → Provisioning → Storefront

---

## Resumen

Se corrigió el problema de "Tienda no encontrada" (401 Unauthorized) al acceder al storefront de `test-store-manual`. La causa raíz era la falta de sincronización entre Admin DB y Backend DB.

---

## Problema Detectado

Al intentar acceder a `http://localhost:5173/?tenant=test-store-manual`, los endpoints `/tenant/bootstrap` y `/home/data` devolvían:

```json
{
  "code": "STORE_NOT_FOUND",
  "message": "Tienda no encontrada"
}
```

### Diagnóstico

El flujo de resolución de tenant en `TenantContextGuard` es:

1. Frontend envía header `X-Tenant-Slug: test-store-manual`
2. Guard busca en `nv_accounts` (Admin DB) por `slug`
3. Si encuentra, obtiene `backend_cluster_id` y busca en `clients` por `nv_account_id`
4. Si no encuentra en paso 2 o 3, devuelve 401

**Estado antes del fix:**

| Base de Datos | Tabla | Registro | Estado |
|---------------|-------|----------|--------|
| Admin DB | `nv_accounts` | ❌ No existía | - |
| Backend DB | `clients` | ✅ Existía | `nv_account_id = NULL` |

---

## Solución Aplicada

### 1. Crear registro en `nv_accounts` (Admin DB)

```sql
INSERT INTO nv_accounts (id, email, slug, status, backend_cluster_id, business_name)
VALUES (
    'ab11b789-3d0b-4214-993c-ed87631ce069',
    'test-store-manual@novavision.lat',
    'test-store-manual',
    'live',
    'cluster_shared_01',
    'Test Store Manual'
);
```

**Nota:** Se usó el mismo UUID que `clients.id` para mantener consistencia (aunque no es requerido técnicamente).

### 2. Vincular `clients.nv_account_id` (Backend DB)

```sql
UPDATE clients 
SET nv_account_id = 'ab11b789-3d0b-4214-993c-ed87631ce069'
WHERE id = 'ab11b789-3d0b-4214-993c-ed87631ce069';
```

---

## Archivos Modificados

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| Admin DB: `nv_accounts` | SQL INSERT | Nuevo registro para test-store-manual |
| Backend DB: `clients` | SQL UPDATE | Vinculación de `nv_account_id` |

---

## Cambios Previos en la Sesión

También se habilitó el header de desarrollo:

| Archivo | Cambio |
|---------|--------|
| `apps/api/.env` | `# ALLOW_TENANT_HOST_HEADER=true` → `ALLOW_TENANT_HOST_HEADER=true` |

---

## Cómo Probar

### 1. Verificar endpoints con curl

```bash
# Bootstrap
curl -s "http://localhost:3000/tenant/bootstrap" \
  -H "x-tenant-slug: test-store-manual" | jq

# Home data
curl -s "http://localhost:3000/home/data" \
  -H "x-tenant-slug: test-store-manual" | jq
```

**Respuesta esperada:** `{"success": true, ...}`

### 2. Probar en navegador

```
http://localhost:5173/?tenant=test-store-manual
```

**Resultado esperado:** Storefront renderiza con 6 productos y 4 categorías.

---

## Verificación de Datos

```sql
-- Admin DB
SELECT id, slug, status, backend_cluster_id 
FROM nv_accounts 
WHERE slug = 'test-store-manual';

-- Backend DB  
SELECT id, slug, nv_account_id, is_active 
FROM clients 
WHERE slug = 'test-store-manual';
```

---

## Arquitectura del Flujo (Referencia)

```
┌─────────────────────────────────────────────────────────────┐
│                       FRONTEND                               │
│  http://localhost:5173/?tenant=test-store-manual            │
│                           │                                  │
│                           ▼                                  │
│              Header: X-Tenant-Slug: test-store-manual       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    API (NestJS)                              │
│                                                              │
│  TenantContextGuard                                          │
│    │                                                         │
│    ├─► 1. resolveAccountBySlug(slug)                        │
│    │      └─► Admin DB: nv_accounts                         │
│    │          SELECT id, backend_cluster_id                 │
│    │          WHERE slug = 'test-store-manual'              │
│    │                                                         │
│    └─► 2. resolveClientByAccount(accountId, clusterId)      │
│           └─► Backend DB: clients                           │
│               SELECT id, is_active, ...                     │
│               WHERE nv_account_id = :accountId              │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│                    BASES DE DATOS                            │
│                                                              │
│  ┌──────────────────────┐    ┌──────────────────────┐       │
│  │     Admin DB         │    │    Backend DB        │       │
│  │  (erbfzlsznqsmwmjug) │    │  (ulndkhijxtxvpmbf)  │       │
│  │                      │    │                      │       │
│  │  nv_accounts         │───▶│  clients             │       │
│  │  - id                │    │  - id                │       │
│  │  - slug              │    │  - nv_account_id ◀───│       │
│  │  - backend_cluster   │    │  - slug              │       │
│  │  - status            │    │  - is_active         │       │
│  └──────────────────────┘    └──────────────────────┘       │
└─────────────────────────────────────────────────────────────┘
```

---

## Notas de Seguridad

- ⚠️ `ALLOW_TENANT_HOST_HEADER=true` solo debe estar activo en desarrollo
- El registro en `nv_accounts` con status `live` permite acceso público al storefront
- Para ambiente de producción, el flujo completo de onboarding debe crear ambos registros sincronizados

---

## Impacto en Otros Clientes

Se detectaron 4 clientes sin `client_home_settings` en el Backend DB:
- `test-store-manual` (corregido)
- `local-test-store`
- `tiendav`
- `tiendav2`

Estos clientes pueden tener el mismo problema de falta de registro en `nv_accounts`. Se recomienda auditar y backfilllear según sea necesario.

---

## Próximos Pasos

1. [ ] Probar registro de usuario en storefront
2. [ ] Verificar flujo de carrito
3. [ ] Auditar otros clientes con `nv_account_id = NULL`
4. [ ] Documentar proceso de backfill para casos similares

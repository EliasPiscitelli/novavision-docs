# Runbook: Limpieza Obligatoria de Datos de Prueba

> **Regla INVIOLABLE**: Todo dato de prueba cargado en cualquier entorno (staging, producción, QA) **DEBE ser eliminado** una vez que se haya confirmado que los tests/validaciones pasaron correctamente. No se deja data residual.

## Cuándo aplica

- Después de ejecutar tests manuales de onboarding (crear clientes ficticios)
- Después de correr tests E2E que crean datos en DBs reales
- Después de probar flujos de pago con datos de prueba
- Después de validar cualquier feature que requiera datos temporales en DB
- Después de hacer QA con usuarios de prueba (emails `+e2e@`, `+test@`, etc.)

## Qué se debe limpiar

### 1. Admin DB (Supabase Admin — `erbfzlsznqsmwmjugspo`)

| Tabla | Orden de borrado | Condición |
|-------|-----------------|-----------|
| `coupon_redemptions` | 1° | `account_id` de cuentas de prueba |
| `lifecycle_events` | 2° | `account_id` de cuentas de prueba |
| `nv_onboarding` | 3° | `account_id` de cuentas de prueba |
| `nv_accounts` | 4° (último) | `slug LIKE 'draft-%'` O `slug LIKE 'e2e-%'` O emails de prueba |
| `auth.users` | 5° | user_id de las cuentas eliminadas (via Supabase Admin SDK) |

**SQL template:**
```sql
BEGIN;

-- 1. Listar IDs a borrar (verificar antes de ejecutar)
SELECT id, slug, email_admin, status
FROM nv_accounts
WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%'
   OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%';

-- 2. Borrar en orden de FK
DELETE FROM coupon_redemptions WHERE account_id IN (SELECT id FROM nv_accounts WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');
DELETE FROM lifecycle_events   WHERE account_id IN (SELECT id FROM nv_accounts WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');
DELETE FROM nv_onboarding      WHERE account_id IN (SELECT id FROM nv_accounts WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');
DELETE FROM nv_accounts        WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%';

COMMIT;
```

### 2. Backend DB (Supabase Multicliente — `ulndkhijxtxvpmbbfrgp`)

| Tabla | Orden de borrado | Condición |
|-------|-----------------|-----------|
| `order_payment_breakdown` | 1° | `client_id` de clientes de prueba |
| `email_jobs` | 2° | `client_id` de clientes de prueba |
| `payments` | 3° | `client_id` de clientes de prueba |
| `order_items` | 4° | `order_id` de órdenes del cliente |
| `orders` | 5° | `client_id` de clientes de prueba |
| `cart_items` | 6° | `client_id` de clientes de prueba |
| `product_categories` | 7° | `client_id` de clientes de prueba |
| `products` | 8° | `client_id` de clientes de prueba |
| `categories` | 9° | `client_id` de clientes de prueba |
| `banners` | 10° | `client_id` de clientes de prueba |
| `favorites` | 11° | `client_id` de clientes de prueba |
| `contact_info` | 12° | `client_id` de clientes de prueba |
| `social_links` | 13° | `client_id` de clientes de prueba |
| `faqs` | 14° | `client_id` de clientes de prueba |
| `services` | 15° | `client_id` de clientes de prueba |
| `logos` | 16° | `client_id` de clientes de prueba |
| `client_extra_costs` | 17° | `client_id` de clientes de prueba |
| `client_mp_fee_overrides` | 18° | `client_id` de clientes de prueba |
| `client_payment_settings` | 19° | `client_id` de clientes de prueba |
| `client_home_settings` | 20° | `client_id` de clientes de prueba |
| `users` | 21° | `client_id` de clientes de prueba |
| `clients` | 22° (último) | `slug LIKE 'draft-%'` O `slug LIKE 'e2e-%'` O emails de prueba |
| `auth.users` | 23° | user_id de los users eliminados (via Supabase Admin SDK) |

**SQL template:**
```sql
BEGIN;

-- 1. Identificar client_ids a borrar
SELECT id, name, email_admin FROM clients
WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%'
   OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%';

-- 2. Borrar tablas hijas (en orden de dependencia)
DELETE FROM client_home_settings WHERE client_id IN (SELECT id FROM clients WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');
DELETE FROM client_payment_settings WHERE client_id IN (SELECT id FROM clients WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');
DELETE FROM users WHERE client_id IN (SELECT id FROM clients WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%');

-- 3. Borrar cliente
DELETE FROM clients WHERE slug LIKE 'draft-%' OR slug LIKE 'e2e-%' OR email_admin LIKE '%+e2e%' OR email_admin LIKE '%+test%';

COMMIT;
```

### 3. Supabase Storage

- Bucket `identity-documents`: borrar carpetas con UUID del `nv_accounts.id` (contienen DNI front/back)
- Bucket de productos/banners: borrar carpetas con UUID del `clients.id`

### 4. Supabase Auth Users

Usar Supabase Admin SDK para eliminar usuarios de auth:
```javascript
const { error } = await supabase.auth.admin.deleteUser(userId);
```

Los `user_id` se obtienen de:
- Admin DB: `nv_accounts.user_id`
- Backend DB: `users.id` (que corresponde a `auth.uid()`)

## Scripts existentes (novavision-e2e)

| Script | Qué limpia | Uso |
|-------|------------|-----|
| `e2e-cleanup.mjs` | Admin DB (nv_onboarding + nv_accounts) | `node e2e-cleanup.mjs` |
| `scripts/_cleanup-partial.cjs` | Backend DB (child tables + clients + auth users) | `node scripts/_cleanup-partial.cjs` |
| `scripts/cleanup-qa.ts` | Backend DB (product reviews/questions + QA users) | `npx tsx scripts/cleanup-qa.ts` |

## Checklist post-test (copiar en el PR/ticket)

```
### Limpieza de datos de prueba
- [ ] Datos de prueba identificados (IDs, slugs, emails)
- [ ] Admin DB: nv_accounts + tablas dependientes eliminados
- [ ] Backend DB: clients + tablas dependientes eliminados
- [ ] Supabase Auth: usuarios de prueba eliminados
- [ ] Supabase Storage: archivos de prueba eliminados
- [ ] Verificación: consulta de conteo retorna 0 en ambas DBs
```

## Regla para agentes AI / Copilot

**Incluir en copilot-instructions.md de cada repo:**

> Después de cualquier test que cree datos en las bases de datos (onboarding, E2E, QA), el agente DEBE ejecutar la limpieza completa antes de cerrar la tarea. Referencia: `novavision-docs/runbooks/test-data-cleanup.md`

## Historial de limpiezas

| Fecha | Quién | Qué se limpió | DBs afectadas |
|-------|-------|---------------|---------------|
| 2025-07-16 | Copilot Agent | 5 cuentas de prueba (draft, e2e-tienda-a/b, belenlauria, kaddoc) | Admin + Backend + Auth |

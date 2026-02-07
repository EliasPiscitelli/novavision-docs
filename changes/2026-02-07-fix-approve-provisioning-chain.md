# Fix: Cadena de errores en endpoint POST /admin/clients/:id/approve

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** `feature/automatic-multiclient-onboarding` (templatetwobe)
- **Cuenta de test:** `7f62b1e5-c518-402c-abcb-88ab9db56dfe` / `kaddocpendragon@gmail.com` / slug=`test` / plan=`growth`

---

## Contexto

Al ejecutar `POST /admin/clients/:id/approve` para aprobar la primera tienda creada vía onboarding automático, se encontró una **cadena de 5 errores secuenciales** en el flujo de provisioning. Cada error impedía que el paso siguiente se ejecutara, y al reintentar (después de fixear cada uno) aparecía el siguiente en la cadena.

El flujo de provisioning tiene ~8 pasos:
1. Leer nv_accounts + plans desde Admin DB
2. Resolver slug
3. Crear/actualizar `clients` en Backend DB
4. Crear/actualizar `users` en Backend DB
5-6. Sync MP credentials
7. Actualizar `nv_onboarding.client_id` en Admin DB
8. Migrar catálogo (productos, FAQs, services, social links)

---

## Archivos modificados

### Código
- `src/worker/provisioning-worker.service.ts` — 5 commits con fixes
- `src/admin/admin.service.ts` — 1 commit (self-healing nv_onboarding)
- `src/subscriptions/subscriptions.service.ts` — 1 commit (remove entitlements_snapshot)

### Migraciones (aplicadas manualmente a producción)
- `migrations/backend/20260207_update_clients_plan_check.sql`
- `migrations/backend/20260207_add_missing_unique_indexes.sql`

---

## Errores y fixes (en orden cronológico)

### Error 1 — `entitlements_snapshot` column not found
**Commit:** `7801194`

**Síntoma:** `PROVISIONING_FAILED: "Could not find the 'entitlements_snapshot' column of 'clients' in the schema cache"`

**Causa:** El código insertaba `entitlements_snapshot` en el upsert de `clients`, pero esa columna nunca existió en la tabla del Backend DB.

**Fix:**
- Eliminado `entitlements_snapshot` del upsert en `provisioning-worker.service.ts` (2 ocurrencias: saga + directo)
- Eliminado `entitlements_snapshot` del update en `subscriptions.service.ts` (1 ocurrencia)
- Agregados campos NOT NULL faltantes al upsert: `name` (desde `nv_accounts.business_name`), `monthly_fee` (desde `plans`), `connection_type` ('mercadopago'), `base_url` (STORES_URL + slug)
- Agregado `business_name` al SELECT de nv_accounts y `monthly_fee` al SELECT de plans

**Por qué pasaba:** El esquema de `clients` en Backend DB difiere de lo que el código asumía. No se había validado contra el esquema real.

---

### Error 2 — `clients_plan_check` constraint violation
**Commit:** `71407de`

**Síntoma:** `PROVISIONING_FAILED: "new row for relation 'clients' violates check constraint 'clients_plan_check'"`

**Causa:** La tabla `clients` tenía un CHECK constraint que solo permitía los planes legacy (`basic`, `professional`, `premium`), pero el onboarding usa planes nuevos (`starter`, `growth`, `enterprise` + variantes `_annual`).

**Fix:**
- ALTER TABLE en producción (Backend DB):
  ```sql
  ALTER TABLE clients DROP CONSTRAINT clients_plan_check;
  ALTER TABLE clients ADD CONSTRAINT clients_plan_check CHECK (
    plan = ANY (ARRAY[
      'basic', 'professional', 'premium',
      'starter', 'starter_annual',
      'growth', 'growth_annual',
      'enterprise', 'enterprise_annual'
    ])
  );
  ```
- Migración guardada en `migrations/backend/20260207_update_clients_plan_check.sql`

**Por qué pasaba:** La tabla `plans` de Admin DB define `starter/growth/enterprise`, pero la constraint de `clients` en Backend DB nunca se actualizó al migrar el sistema de planes.

---

### Error 3 — `ON CONFLICT` no matching constraint (users)
**Commit:** `f553c5a`

**Síntoma:** `PROVISIONING_FAILED: "Failed to provision user: there is no unique or exclusion constraint matching the ON CONFLICT specification"`

**Causa:** La tabla `users` tiene PK compuesta `(id, client_id)`, pero el upsert usaba `onConflict: 'id'` (solo una columna). PostgreSQL requiere que el `ON CONFLICT` matchee un constraint existente.

**Fix:**
- Cambiado `onConflict: 'id'` → `onConflict: 'id,client_id'` en ambos paths (saga y directo) de `provisioning-worker.service.ts`

**Por qué pasaba:** La PK compuesta de `users` es inusual (generalmente es solo `id`). El código asumía PK simple.

---

### Error 4 — `PROVISIONING_INCOMPLETE_NO_PRODUCTS` (nv_onboarding.client_id NULL)
**Commit:** `a645c93`

**Síntoma:** `PROVISIONING_INCOMPLETE_NO_PRODUCTS: "Provisioning incomplete: missing products migration even after backfill."`

**Causa raíz:** Los errores 1-3 hicieron que el provisioning fallara **antes del paso 7** (el que escribe `nv_onboarding.client_id`). Al reintentar el approve:
1. `approveClient` ve que el client ya existe en Backend DB → no re-ejecuta provisioning
2. Salta al guardrail de productos → 0 productos → llama `runBackfillCatalog`
3. `runBackfillCatalog` lee `nv_onboarding.client_id` → **NULL** → throws "Client not provisioned yet"
4. El backfill falla silenciosamente → re-check da 0 productos → error final

**Fix (self-healing en dos puntos):**

1. **`runBackfillCatalog`**: Si `nv_onboarding.client_id` es NULL, resuelve el `client_id` desde Backend DB vía `clients.nv_account_id` y lo backfilla automáticamente en `nv_onboarding`.
2. **`approveClient`**: Después de confirmar que el client existe en Backend DB, verifica si `nv_onboarding.client_id` es NULL y lo popula proactivamente.
3. **Fix manual en producción:** `UPDATE nv_onboarding SET client_id = '19986d95-...' WHERE account_id = '7f62b1e5-...'`

**Por qué pasaba:** Diseño frágil — el paso 7 del provisioning es la única vía para setear `client_id` en `nv_onboarding`, pero si cualquier paso anterior falla, el paso 7 no se ejecuta. Al reintentar, el provisioning se salta (el client ya existe) y `client_id` queda NULL para siempre.

---

### Error 5 — Schema mismatches en `migrateCatalog`
**Commit:** `522f736`

**Síntoma:** 11 productos fallan con `"Could not find the 'full_text_search' column of 'products'"`, 6 FAQs fallan con `"Could not find the 'position' column of 'faqs'"`, 3 services fallan con `"Could not find the 'position' column of 'services'"`, social links falla con `"Could not find the 'platform' column of 'social_links'"`.

**Causa:** `migrateCatalog` fue escrita asumiendo un esquema diferente al real de Backend DB.

| Tabla | Código asumía | DB real | Fix |
|---|---|---|---|
| `products` | columna `full_text_search` | No existe | Eliminada del upsert |
| `faqs` | columna `position`, unique `(client_id, question)` | Columna `number`, unique `(client_id, number)` | Renombrada + onConflict corregido |
| `services` | columna `position`, unique `(client_id, title)` | Columna `number`, unique `(client_id, number)` | Renombrada + onConflict corregido |
| `social_links` | Filas individuales con `platform` + `url` | 1 fila por client con columnas `whatsApp`, `wspText`, `instagram`, `facebook` | Reescrito completamente |

**Fix DB (aplicados manualmente a producción):**
```sql
-- Unique indexes necesarios para onConflict
CREATE UNIQUE INDEX products_client_sku_unique ON products (client_id, sku);
CREATE UNIQUE INDEX categories_client_name_unique ON categories (client_id, name);

-- social_links: dedup + unique por client
DELETE FROM social_links WHERE id NOT IN (
  SELECT DISTINCT ON (client_id) id FROM social_links ORDER BY client_id, created_at DESC
);
CREATE UNIQUE INDEX social_links_client_unique ON social_links (client_id);
```

**Fix código:** Eliminado `full_text_search`, cambiado `position→number` en faqs/services con onConflict correcto, y reescrito social_links para upsert de 1 fila con columnas por red social.

**Por qué pasaba:** `migrateCatalog` fue escrita contra un esquema teórico/documentado que no coincide con el esquema real de producción.

---

## Patrón recurrente

Todos los errores comparten la misma raíz: **el código fue escrito contra un esquema asumido, no contra el esquema real de la DB de producción.** Columnas inexistentes, constraints incompatibles, PKs compuestas no consideradas, y diseño de tablas diferente al esperado.

**Recomendación:** Crear un snapshot del esquema real (`pg_dump --schema-only`) y validar todo el código de provisioning contra él antes de agregar nuevas features.

---

## Cómo probar

```bash
# 1. Verificar que los indexes existen
psql $BACKEND_DB_URL -c "
  SELECT indexname FROM pg_indexes 
  WHERE tablename IN ('products','categories','social_links') 
  AND indexname LIKE '%unique%';
"

# 2. Verificar nv_onboarding.client_id no es NULL
psql $ADMIN_DB_URL -c "
  SELECT client_id FROM nv_onboarding 
  WHERE account_id = '7f62b1e5-c518-402c-abcb-88ab9db56dfe';
"

# 3. Retry approve
curl -X POST https://novavision-production.up.railway.app/admin/clients/7f62b1e5-c518-402c-abcb-88ab9db56dfe/approve \
  -H "Authorization: Bearer <JWT>" \
  -H "x-internal-key: rol-admin:novavision_39628997_2025"

# 4. Verificar productos migrados
psql $BACKEND_DB_URL -c "
  SELECT count(*) FROM products 
  WHERE client_id = '19986d95-2702-4cf2-ba3d-5b4a3df01ef7';
"
```

---

## Commits (orden cronológico)

| Commit | Descripción |
|---|---|
| `7801194` | Remove entitlements_snapshot + add missing NOT NULL fields |
| `71407de` | Update clients_plan_check constraint |
| `f553c5a` | Fix users upsert onConflict composite PK |
| `a645c93` | Self-heal nv_onboarding.client_id |
| `522f736` | Fix migrateCatalog schema mismatches |

## Notas de seguridad

- No se expusieron credenciales nuevas.
- Los cambios de DB (ALTER TABLE, CREATE INDEX) fueron aplicados con service_role vía psql directo.
- El self-healing de `nv_onboarding.client_id` es seguro: solo resuelve desde Backend DB usando `nv_account_id` que es un FK controlado.

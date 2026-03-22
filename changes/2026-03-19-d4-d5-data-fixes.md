# D4 + D5: Data fixes — palette_catalog + clients e2e

**Fecha:** 2026-03-19
**Repo:** `apps/api` (migraciones SQL)
**Tickets:** D4 (Fix plan `pro` en palette_catalog) + D5 (Fix locale/template_id vacíos)

## D4: Fix plan `pro` en palette_catalog

**Problema:** `luxury_gold` tenía `min_plan_key = 'pro'` pero el plan `pro` no existe. Solo existen `starter`, `growth`, `enterprise`.

**Migración:** `migrations/admin/20260319_d4_fix_pro_plan_palette_catalog.sql`

**Cambios:**
- `luxury_gold.min_plan_key` → `enterprise`
- Safety net: actualiza cualquier otro registro con `'pro'`
- CHECK constraint actualizado: elimina `'pro'` de los valores permitidos

## D5: Fix locale y template_id vacíos en clientes e2e

**Problema:** Clientes `e2e-alpha` y `e2e-beta` tenían `locale = ''` y `template_id = ''`.

**Migración:** `migrations/backend/20260319_d5_fix_empty_locale_template.sql`

**Cambios:**
- `locale` vacío → `'es-AR'`
- `template_id` vacío → `'first'` (alpha) / `'fifth'` (beta)
- Default `locale = 'es-AR'` agregado a la columna
- CHECK constraints `clients_locale_not_empty` y `clients_template_id_not_empty` para prevenir vacíos futuros

## Estado

- Migraciones creadas, pendiente ejecución en BD
- Build API: OK

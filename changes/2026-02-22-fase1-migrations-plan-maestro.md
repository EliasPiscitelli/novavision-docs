# Cambio: Migraciones SQL Fase 1 — Plan Maestro Internacionalización + Billing

- **Autor:** agente-copilot
- **Fecha:** 2026-02-22
- **Rama:** feature/automatic-multiclient-onboarding
- **Referencia:** `novavision-docs/architecture/PLAN_MAESTRO_IMPLEMENTACION.md` §7

## Archivos creados

### Admin DB (12 migraciones + 1 backfill)
| Archivo | Propósito |
|---------|-----------|
| `ADMIN_064_country_configs.sql` | Tabla `country_configs` + seed 6 países LATAM |
| `ADMIN_065_fx_rates_config.sql` | Tabla `fx_rates_config` + seed con endpoints por país |
| `ADMIN_066_extend_plans_enforcement.sql` | ALTER `plans` (9 cols nuevas) + UPDATE seeds |
| `ADMIN_067_nv_accounts_i18n_fiscal.sql` | ALTER `nv_accounts` (10 cols: i18n + fiscal) |
| `ADMIN_068_subscriptions_auto_charge.sql` | ALTER `subscriptions` + limpiar CHECK `plan_key` |
| `ADMIN_069_quota_state.sql` | Tabla `quota_state` (FSM de cuotas por tenant) |
| `ADMIN_070_usage_rollups_monthly.sql` | Tabla `usage_rollups_monthly` |
| `ADMIN_071_billing_adjustments.sql` | Tabla `billing_adjustments` (overages + GMV) |
| `ADMIN_072_nv_invoices.sql` | Tabla `nv_invoices` (Factura E / ARCA) |
| `ADMIN_073_fee_schedules.sql` | Tablas `fee_schedules` + `fee_schedule_lines` |
| `ADMIN_074_cost_rollups_monthly.sql` | Tabla `cost_rollups_monthly` (COGS) |
| `ADMIN_075_subscription_upgrade_log.sql` | Tabla `subscription_upgrade_log` (P12 resuelto) |
| `BACKFILL_001_initial_data.sql` | Backfill: todos los tenants existentes → AR/MLA/ARS |

### Backend DB (2 migraciones + 1 backfill)
| Archivo | Propósito |
|---------|-----------|
| `BACKEND_045_clients_i18n.sql` | ALTER `clients` (country, locale, timezone) |
| `BACKEND_046_orders_multicurrency.sql` | ALTER `orders` (currency, exchange_rate, total_ars) |
| `BACKFILL_001_clients_i18n.sql` | Backfill: todos los clients → AR/es-AR |

## Decisiones de reconciliación (Fase 0 findings)

1. **`included_*` columns ya existían** (desde ADMIN_043): ADMIN_066 NO agrega esas columnas, solo las nuevas (max_active_stores, rps_*, gmv_*, etc.) y UPDATE los seeds.

2. **Seeds ajustados** con valores del Plan Maestro (plan_catalog del TL):
   - Starter: 150 orders (antes 200), 100k requests (antes 20k), 5GB BW (antes 50), 1GB storage (antes 2)
   - Growth: 800k requests (antes 100k), 40GB BW (antes 200)
   - Enterprise: $390/mo (antes $250), 5k orders (antes 20k), 3M requests (antes 999k)

3. **`subscriptions.plan_key` CHECK**: se limpia el valor muerto `'scale'` en ADMIN_068.

4. **`nv_accounts.plan_key`**: NO tiene CHECK constraint — confirmado en Fase 0, no requiere acción (P10 resuelto).

5. **`subscription_upgrade_log`**: DDL formalizado como ADMIN_075 (P12 resuelto). El código existente en subscriptions.service.ts ya funciona con try/catch; ahora la tabla existe formalmente.

## Cómo probar

### Orden de ejecución Admin DB
```bash
cd apps/api
# En orden (contra Admin DB: erbfzlsznqsmwmjugspo)
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_064_country_configs.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_065_fx_rates_config.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_066_extend_plans_enforcement.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_067_nv_accounts_i18n_fiscal.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_068_subscriptions_auto_charge.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_069_quota_state.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_070_usage_rollups_monthly.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_071_billing_adjustments.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_072_nv_invoices.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_073_fee_schedules.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_074_cost_rollups_monthly.sql
npx ts-node scripts/apply-admin-migration.ts migrations/admin/ADMIN_075_subscription_upgrade_log.sql
# Backfill (después de verificar que todo pasó OK)
npx ts-node scripts/apply-admin-migration.ts migrations/admin/BACKFILL_001_initial_data.sql
```

### Orden de ejecución Backend DB
```bash
# Contra Backend DB (ulndkhijxtxvpmbbfrgp)
psql $BACKEND_DB_URL -f migrations/backend/BACKEND_045_clients_i18n.sql
psql $BACKEND_DB_URL -f migrations/backend/BACKEND_046_orders_multicurrency.sql
psql $BACKEND_DB_URL -f migrations/backend/BACKFILL_001_clients_i18n.sql
```

### Validación post-migración
```sql
-- Verificar nuevas tablas (Admin DB)
SELECT tablename FROM pg_tables WHERE schemaname = 'public'
  AND tablename IN ('country_configs', 'fx_rates_config', 'quota_state',
    'usage_rollups_monthly', 'billing_adjustments', 'nv_invoices',
    'fee_schedules', 'fee_schedule_lines', 'cost_rollups_monthly',
    'subscription_upgrade_log');

-- Verificar seeds country_configs
SELECT site_id, country_id, currency_id FROM country_configs;

-- Verificar nuevos valores de plans
SELECT plan_key, monthly_fee, max_active_stores, rps_sustained,
       included_orders, included_requests, gmv_threshold_usd
FROM plans ORDER BY sort_order;

-- Verificar nv_accounts backfill
SELECT count(*), country FROM nv_accounts GROUP BY country;
```

## Notas de seguridad

- Ninguna de estas migraciones toca RLS — las tablas nuevas necesitarán políticas RLS antes de ser expuestas vía API (Fase 2+).
- Los backfills son idempotentes (`WHERE country IS NULL`, `ON CONFLICT DO NOTHING`).
- ADMIN_066 cambia precios de planes (Enterprise $250 → $390). Confirmar con negocio antes de ejecutar en producción.

## Riesgos

- **Enterprise pricing change**: los tenants Enterprise existentes verán el nuevo precio en su próximo billing cycle. Coordinar comunicación.
- **Seeds de limits ajustados**: Starter pierde orders (200→150) y bandwidth (50→5GB). Asegurar que no haya tenants Starter que ya superen los nuevos límites.
- **CHECK de subscriptions**: si existe alguna suscripción con `plan_key='scale'`, la migración ADMIN_068 fallará. Verificar antes de correr.

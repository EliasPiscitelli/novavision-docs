# Auditoría de Seguridad – Admin DB (NovaVision)

> **Fecha:** 2026-02-07  
> **Fuente:** 100+ archivos de migración en `apps/api/migrations/admin/`  
> **Autor:** Agente Copilot (auditoría automatizada)  
> **DB:** Supabase Admin (`erbfzlsznqsmwmjugspo`)

---

## Índice

1. [Extensiones](#1-extensiones)
2. [Tipos / Enums](#2-tipos--enums)
3. [Tablas](#3-tablas)
4. [Índices](#4-índices)
5. [Constraints (CHECK / UNIQUE / FK)](#5-constraints)
6. [RLS Policies](#6-rls-policies)
7. [Funciones / RPCs](#7-funciones--rpcs)
8. [Triggers](#8-triggers)
9. [GRANTs](#9-grants)
10. [pg_cron Jobs](#10-pg_cron-jobs)
11. [Storage Operations](#11-storage-operations)
12. [Hallazgos de Seguridad](#12-hallazgos-de-seguridad)

---

## 1. Extensiones

| Extensión | Migración |
|-----------|-----------|
| `pgcrypto` | ADMIN_001 |
| `citext` | ADMIN_001 |
| `uuid-ossp` | create_completion_staging_tables |

---

## 2. Tipos / Enums

### `nv_onboarding_state`
> Definido en ADMIN_002, extendido en 20260203, fix_enum_and_backfill_state

| Valor | Origen |
|-------|--------|
| `draft_builder` | ADMIN_002 |
| `pending_payment` | ADMIN_002 |
| `approved` | ADMIN_002 |
| `provisioning` | 20260203 |
| `live` | ADMIN_002 |
| `failed` | ADMIN_002 |
| `pending_review` | 20260203 |
| `submitted_for_review` | 20260203 / fix_enum_and_backfill_state |
| `rejected` | 20260203 |
| `provisioned` | 20260203 |

### `nv_job_status`
> Definido en ADMIN_002, extendido en ADMIN_027

| Valor |
|-------|
| `queued` |
| `running` |
| `done` |
| `failed` |
| `pending` |
| `completed` |

### `billing_event_type`
> Definido en ADMIN_044

| Valor |
|-------|
| `domain_renewal` |
| `plan_subscription` |
| `one_time_service` |

### `billing_event_status`
> Definido en ADMIN_044

| Valor |
|-------|
| `pending` |
| `paid` |
| `failed` |
| `cancelled` |

### `subscription_status`
> Definido en 20260102000001, extendido en 20260120

| Valor |
|-------|
| `active` |
| `past_due` |
| `grace` |
| `expired` |
| `canceled` |
| `cancel_scheduled` |
| `deactivated` |
| `purged` |

### `publication_status_enum`
> Definido en 20250101000003

| Valor |
|-------|
| `draft` |
| `pending_approval` |
| `published` |
| `paused` |
| `rejected` |

### `managed_domain_renewal_state`
> Definido en ADMIN_052

| Valor |
|-------|
| `none` |
| `due_soon` |
| `invoice_created` |
| `paid` |
| `overdue` |
| `renewal_failed` |

---

## 3. Tablas

### 3.1 `nv_accounts`
> Core: cuenta maestra del onboarding. ADMIN_004 + múltiples extensiones.

| Columna | Tipo | Nullable | Default | Notas |
|---------|------|----------|---------|-------|
| `id` | uuid | NO | `gen_random_uuid()` | **PK** |
| `email` | citext | NO | — | UNIQUE |
| `slug` | text | YES | — | UNIQUE |
| `plan_key` | text | NO | `'starter'` | |
| `backend_cluster_id` | text | YES | — | FK → `backend_clusters(cluster_id)` (20250101000002 / 202601201010) |
| `draft_expires_at` | timestamptz | YES | — | |
| `created_at` | timestamptz | NO | `NOW()` | |
| `updated_at` | timestamptz | NO | `NOW()` | |
| `user_id` | uuid | YES | — | FK → `auth.users(id)` (ADMIN_022) |
| `status` | text | NO | `'draft'` | CHECK constraint expandido (ADMIN_042/056) |
| `last_saved_at` | timestamptz | YES | — | ADMIN_022 |
| `deleted_at` | timestamptz | YES | — | ADMIN_016 |
| `subscription_id` | text | YES | — | ADMIN_016 |
| `subscription_status` | text | YES | — | ADMIN_016. CHECK `chk_nv_subscription_status` (20260207) |
| `is_super_admin` | boolean | YES | `false` | ADMIN_034 |
| `terms_accepted_at` | timestamptz | YES | — | ADMIN_028 |
| `terms_version` | text | YES | — | ADMIN_028 |
| `business_name` | text | YES | — | ADMIN_041 |
| `cuit_cuil` | text | YES | — | ADMIN_041 |
| `fiscal_address` | text | YES | — | ADMIN_041 |
| `phone` | text | YES | — | ADMIN_041 |
| `billing_email` | text | YES | — | ADMIN_041 |
| `dni` | text | YES | — | ADMIN_036 |
| `identity_verified` | boolean | YES | — | ADMIN_036 |
| `dni_front_url` | text | YES | — | ADMIN_036 |
| `dni_back_url` | text | YES | — | ADMIN_036 |
| `identity_verified_at` | timestamptz | YES | — | ADMIN_036 |
| `fulfillment_mode` | text | YES | — | CHECK `self_serve`/`concierge` (20250101000002) |
| `backend_api_url` | text | YES | — | 20250101000002 |
| `dedicated_project_ref` | text | YES | — | 20250101000002 |
| `go_live_approved_at` | timestamptz | YES | — | 20250101000002 |
| `migration_status` | text | YES | — | 20250101000002 |
| `migration_started_at` | timestamptz | YES | — | 20250101000002 |
| `migration_completed_at` | timestamptz | YES | — | 20250101000002 |
| `migrated_from_cluster_id` | text | YES | — | 20250101000002 |
| `last_migration_job_id` | uuid | YES | — | 20250101000002 |
| `store_paused` | boolean | YES | — | 20260121 |
| `store_paused_at` | timestamptz | YES | — | 20260121 |
| `store_resumed_at` | timestamptz | YES | — | 20260121 |
| `store_pause_reason` | text | YES | — | 20260121 |
| `custom_domain` | text | YES | — | UNIQUE partial lower() (20260126) |
| `custom_domain_status` | text | YES | — | CHECK `pending_dns`/`active`/`error` |
| `custom_domain_mode` | text | YES | — | CHECK `self_service`/`concierge` |
| `custom_domain_requested_at` | timestamptz | YES | — | |
| `custom_domain_verified_at` | timestamptz | YES | — | |
| `custom_domain_last_checked_at` | timestamptz | YES | — | |
| `custom_domain_error` | text | YES | — | |
| `netlify_site_id` | text | YES | — | |
| `custom_domain_concierge_until` | timestamptz | YES | — | 20260126 |

**CHECK constraint `nv_accounts_status_check`** (ADMIN_042 + 056):
```
status IN ('draft','awaiting_payment','paid','provisioning','provisioned',
'pending_approval','incomplete','changes_requested','approved','rejected',
'expired','failed','suspended','live')
```

**CHECK constraint `chk_nv_subscription_status`** (20260207):
```
subscription_status IS NULL OR subscription_status IN (
  'active','pending','past_due','grace','grace_period','suspended',
  'paused','canceled','cancel_scheduled','deactivated','expired','purged'
)
```

**CHECK constraint `nv_accounts_paid_requires_cluster`** (202601201010):
```
status NOT IN ('paid','provisioning','provisioned','live') OR backend_cluster_id IS NOT NULL
```

---

### 3.2 `nv_onboarding`
> Estado del onboarding por cuenta. ADMIN_005 + extensiones.

| Columna | Tipo | Nullable | Default | Notas |
|---------|------|----------|---------|-------|
| `account_id` | uuid | NO | — | **PK**, FK → `nv_accounts(id)` ON DELETE CASCADE |
| `state` | nv_onboarding_state | NO | `'draft_builder'` | |
| `selected_template_key` | text | YES | — | |
| `selected_palette_key` | text | YES | — | |
| `data` | jsonb | NO | `'{}'` | |
| `created_at` | timestamptz | — | `NOW()` | |
| `updated_at` | timestamptz | — | `NOW()` | |
| `selected_theme_override` | jsonb | YES | — | ADMIN_012 |
| `design_config` | jsonb | YES | — | CHECK jsonb_typeof='object' (ADMIN_013) |
| `state_reason` | text | YES | — | ADMIN_016 |
| `state_updated_at` | timestamptz | YES | — | ADMIN_016, trigger |
| `plan_key_selected` | text | YES | — | ADMIN_022 |
| `cycle` | text | YES | `'month'` | ADMIN_022 |
| `checkout_preference_id` | text | YES | — | ADMIN_022 |
| `checkout_external_reference` | text | YES | — | ADMIN_022 |
| `checkout_payment_id` | text | YES | — | ADMIN_022 |
| `checkout_quote_usd` | numeric | YES | — | ADMIN_022 |
| `checkout_quote_ars` | numeric | YES | — | ADMIN_022 |
| `checkout_blue_rate` | numeric | YES | — | ADMIN_022 |
| `checkout_created_at` | timestamptz | YES | — | ADMIN_022 |
| `paid_at` | timestamptz | YES | — | ADMIN_022 |
| `client_id` | uuid | YES | — | FK → `clients(id)` (ADMIN_022) |
| `provisioned_at` | timestamptz | YES | — | ADMIN_022 |
| `provisioning_error` | text | YES | — | ADMIN_022 |
| `mp_connection_status` | text | YES | — | 20250102000000 |
| `mp_error` | text | YES | — | 20250102000000 |
| `progress` | jsonb | YES | — | 20260203 |
| `submitted_at` | timestamptz | YES | — | 20260203 |
| `reviewed_at` | timestamptz | YES | — | 20260203 |
| `reviewed_by` | uuid | YES | — | 20260203 |
| `rejection_reason` | text | YES | — | 20260203 |

---

### 3.3 `plans`
> Catálogo de planes. ADMIN_043 (reemplaza versiones anteriores).

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `plan_key` | text | NO | — | **PK** |
| `display_name` | text | NO | — |
| `description` | text | YES | — |
| `features` | jsonb | YES | `'[]'` |
| `recommended` | boolean | YES | `false` |
| `is_active` | boolean | YES | `true` |
| `sort_order` | integer | YES | `100` |
| `monthly_fee` | numeric | NO | — |
| `setup_fee` | numeric | YES | `0` |
| `currency` | text | YES | `'ARS'` |
| `price_display` | text | YES | — |
| `entitlements` | jsonb | NO | — |
| `included_requests` | integer | NO | `10000` |
| `included_bandwidth_gb` | numeric | NO | `10` |
| `included_storage_gb` | numeric | NO | `10` |
| `included_orders` | integer | NO | `100` |
| `overage_per_1k_requests` | numeric | YES | `0` |
| `overage_per_gb_egress` | numeric | YES | `0` |
| `overage_per_order` | numeric | YES | `0` |
| `rate_version` | integer | YES | `1` |
| `effective_from` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Seeds:** starter, starter_annual, growth, growth_annual, enterprise, enterprise_annual

---

### 3.4 `addon_catalog`
> Catálogo de add-ons. ADMIN_006.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `addon_key` | text | NO | — | **PK** |
| `display_name` | text | NO | — |
| `delta_entitlements` | jsonb | YES | `'{}'` |
| `price_cents` | integer | YES | — |
| `is_active` | boolean | NO | `true` |

---

### 3.5 `account_addons`
> ADMIN_006b.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | **PK** |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `addon_key` | text | NO | — | FK → `addon_catalog` |
| `purchased_at` | timestamptz | YES | — |

---

### 3.6 `account_entitlements`
> ADMIN_007.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `account_id` | uuid | NO | — | **PK**, FK → `nv_accounts` ON DELETE CASCADE |
| `entitlements` | jsonb | NO | — |
| `computed_at` | timestamptz | YES | — |

---

### 3.7 `provisioning_jobs`
> ADMIN_008, extendido en ADMIN_057/20260120.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial / uuid | NO | — | **PK** |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `job_type` | text | NO | — |
| `type` | text | YES | — | ADMIN_057 (synced with job_type via trigger) |
| `payload` | jsonb | YES | `'{}'` |
| `status` | nv_job_status | YES | `'queued'` |
| `attempts` | integer | YES | `0` |
| `max_attempts` | integer | YES | — | 20260120 |
| `run_after` | timestamptz | YES | — |
| `locked_at` | timestamptz | YES | — |
| `locked_by` | text | YES | — |
| `last_error` | text | YES | — |
| `started_at` | timestamptz | YES | — | 20260120 |
| `completed_at` | timestamptz | YES | — | 20260120 |
| `dedupe_key` | text | YES | — | ADMIN_057, UNIQUE |
| `created_at` | timestamptz | — | `NOW()` |
| `updated_at` | timestamptz | — | `NOW()` |

---

### 3.8 `provisioning_job_steps`
> ADMIN_058.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial | NO | — | **PK** |
| `job_id` | uuid | NO | — | FK → `provisioning_jobs` ON DELETE CASCADE |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `step_name` | text | NO | — |
| `status` | text | NO | — | CHECK: queued/running/done/failed/skipped |
| `attempt` | integer | YES | — |
| `step_data` | jsonb | YES | — |
| `error` | text | YES | — |
| `started_at` | timestamptz | YES | — |
| `ended_at` | timestamptz | YES | — |
| `created_at` | timestamptz | — | `NOW()` |
| `updated_at` | timestamptz | — | `NOW()` |

**UNIQUE:** `(job_id, step_name)`

---

### 3.9 `mp_events`
> ADMIN_009.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial | NO | — | **PK** |
| `mp_event_id` | text | NO | — | UNIQUE |
| `topic` | text | YES | — |
| `payload` | jsonb | NO | — |
| `received_at` | timestamptz | YES | — |
| `processed_at` | timestamptz | YES | — |

---

### 3.10 `backend_clusters`
> ADMIN_010 + 20250101000002.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` / `cluster_id` | uuid / text | NO | — | **PK** |
| `cluster_key` / `display_name` | text | NO | — | UNIQUE (cluster_key) |
| `is_active` / `active` | boolean | YES | `true` |
| `db_url` | text | YES | — | 20250101000002 |
| `service_role_key` | text | YES | — | 20250101000002 |
| `storage_project_ref` | text | YES | — | 20250101000002 |
| `api_url` | text | YES | — | 20250101000002 |
| `db_url_encrypted` | text | YES | — | 202601201800 |
| `status` | text | YES | — | 202601201800 |
| `last_error` | text | YES | — | 202601201800 |
| `last_cloned_from` | text | YES | — | 202601201800 |
| `last_cloned_at` | timestamptz | YES | — | 202601201800 |
| `created_at` | timestamptz | — | `NOW()` |

> ⚠️ **HALLAZGO DE SEGURIDAD:** `db_url` y `service_role_key` almacenados en texto plano en versión 20250101000002. Versión 202601201800+ añade `db_url_encrypted` con PGP.

---

### 3.11 `coupons`
> ADMIN_011.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `code` | text | NO | — | UNIQUE |
| `description` | text | YES | — |
| `discount_type` | text | NO | — | CHECK: `percentage`/`fixed_amount` |
| `discount_value` | numeric | NO | — | CHECK > 0 |
| `currency` | text | YES | `'ARS'` |
| `max_uses` | integer | YES | — |
| `uses_count` | integer | YES | `0` |
| `active` | boolean | YES | `true` |
| `expires_at` | timestamptz | YES | — |
| `created_at` | timestamptz | — | — |

### 3.12 `coupon_redemptions`
> ADMIN_011.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `coupon_id` | uuid | YES | — | FK → `coupons` |
| `account_id` | uuid | YES | — | FK → `nv_accounts` |
| `order_id` | text | YES | — |
| `redeemed_at` | timestamptz | YES | — |
| `discount_amount` | numeric | NO | — |

---

### 3.13 `palette_catalog`
> ADMIN_011_create_palette_catalog.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `palette_key` | text | NO | — | **PK** |
| `label` | text | NO | — |
| `description` | text | YES | — |
| `min_plan_key` | text | YES | `'starter'` | CHECK: starter/growth/pro/enterprise |
| `preview` | jsonb | YES | — | CHECK jsonb_typeof='object' |
| `is_active` | boolean | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

---

### 3.14 `custom_palettes`
> ADMIN_014.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `client_id` | uuid | YES | — | FK → `clients` ON DELETE CASCADE |
| `palette_name` | text | YES | — |
| `based_on_key` | text | YES | — | FK → `palette_catalog` |
| `theme_vars` | jsonb | YES | — | CHECK jsonb_typeof='object' |
| `is_active` | boolean | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

**UNIQUE:** `(client_id, palette_name)`

---

### 3.15 `client_themes`
> ADMIN_015.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `client_id` | uuid | NO | — | **PK**, FK → `clients` ON DELETE CASCADE |
| `template_key` | text | YES | `'normal'` | CHECK `^[a-z0-9-]+$` (20260102000004) |
| `template_version` | integer | YES | — |
| `overrides` | jsonb | YES | `'{}'` | CHECK jsonb_typeof='object' |
| `updated_at` | timestamptz | — | — |

---

### 3.16 `nv_templates`
> ADMIN_040.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `key` | text | NO | — | **PK** |
| `label` | text | YES | — |
| `description` | text | YES | — |
| `thumbnail_url` | text | YES | — |
| `min_plan` | text | YES | `'starter'` | CHECK: starter/growth/pro/enterprise |
| `is_active` | boolean | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

FK: `client_themes.template_key` → `nv_templates(key)`

---

### 3.17 `slug_reservations`
> ADMIN_023.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `slug` | text | NO | — | **PK** |
| `account_id` | uuid | YES | — | FK → `nv_accounts` ON DELETE CASCADE |
| `reserved_at` | timestamptz | — | — |
| `expires_at` | timestamptz | YES | `now() + '30 min'` |

---

### 3.18 `webhook_events`
> ADMIN_024.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `source` | text | YES | — |
| `event_type` | text | YES | — |
| `payment_id` | text | YES | — |
| `external_reference` | text | YES | — |
| `payload` | jsonb | YES | — |
| `status` | text | YES | — | CHECK: received/processing/processed/failed |
| `processed_at` | timestamptz | YES | — |
| `error` | text | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

**UNIQUE INDEX:** `(source, payment_id, event_type)` — dedup

---

### 3.19 `auth_handoff`
> ADMIN_030.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `token_hash` | text | NO | — | UNIQUE |
| `client_id` | uuid | YES | — |
| `user_id` | uuid | YES | — |
| `payload_ciphertext` | text | NO | — |
| `payload_iv` | text | NO | — |
| `payload_tag` | text | NO | — |
| `expires_at` | timestamptz | NO | — |
| `consumed_at` | timestamptz | YES | — |
| `created_at` | timestamptz | NO | `NOW()` |

> ⚠️ **HALLAZGO:** RLS **NO** habilitado en esta tabla.

---

### 3.20 `super_admins`
> ADMIN_036/20250101000006.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | YES | PK (ADMIN_036) |
| `email` | text/citext | NO | — | PK o UNIQUE (según versión) |
| `created_at` | timestamptz | — | — |

> ⚠️ **HALLAZGO:** 20260201_fix_super_admin_rls.sql **DESHABILITA** RLS en esta tabla (`ALTER TABLE super_admins DISABLE ROW LEVEL SECURITY`).

---

### 3.21 `nv_billing_events`
> ADMIN_044, extendido en ADMIN_050.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `event_type` | billing_event_type | NO | — |
| `status` | billing_event_status | YES | `'pending'` |
| `amount` | numeric(10,2) | YES | — |
| `currency` | varchar(3) | YES | `'ARS'` |
| `external_reference` | varchar(255) | YES | — | UNIQUE |
| `provider` | text | YES | — | ADMIN_050 |
| `provider_payment_id` | varchar(255) | YES | — | UNIQUE partial WHERE NOT NULL |
| `provider_preference_id` | text | YES | — | ADMIN_050 |
| `paid_at` | timestamptz | YES | — | ADMIN_050 |
| `manual_reference` | text | YES | — | ADMIN_050 |
| `admin_note` | text | YES | — | ADMIN_050 |
| `metadata` | jsonb | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

---

### 3.22 `subscriptions`
> 20260102000001, extendido en 20260118/20260120/20260121.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE, UNIQUE |
| `provider_id` | text | YES | — | UNIQUE |
| `status` | subscription_status | YES | — |
| `plan_key` | text | YES | — | CHECK `subscriptions_plan_key_check` |
| `current_period_start` | timestamptz | YES | — |
| `current_period_end` | timestamptz | YES | — | CHECK >= start |
| `grace_until` | timestamptz | YES | — |
| `cancel_at_period_end` | boolean | YES | — |
| `metadata` | jsonb | YES | — |
| `billing_cycle` | text | YES | — | CHECK: monthly/annual (20260118) |
| `auto_renew` | boolean | YES | — | 20260118 |
| `external_reference` | text | YES | — | 20260121 |
| `cancel_requested_at` | timestamptz | YES | — | 20260120 |
| `grace_ends_at` | timestamptz | YES | — | 20260120 |
| `past_due_since` | timestamptz | YES | — | 20260120 |
| `suspended_at` | timestamptz | YES | — | 20260120 |
| `deactivate_at` | timestamptz | YES | — | 20260120 |
| `deactivated_at` | timestamptz | YES | — | 20260120 |
| `purge_at` | timestamptz | YES | — | 20260120 |
| `purged_at` | timestamptz | YES | — | 20260120 |
| `last_mp_synced_at` | timestamptz | YES | — | 20260206 |
| `last_reconcile_source` | text | YES | — | 20260206 |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

**UNIQUE partial index:** `ux_subscriptions_one_active_per_account ON (account_id) WHERE status = 'active'` (20260207)

---

### 3.23 `subscription_events`
> 20260102000001.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `event_id` | text | YES | — | UNIQUE |
| `subscription_id` | uuid | YES | — | FK → `subscriptions` |
| `event_type` | text | YES | — |
| `payload` | jsonb | YES | — |
| `processed_at` | timestamptz | YES | — |
| `created_at` | timestamptz | — | — |

---

### 3.24 `subscription_notification_outbox`
> 20260120.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` |
| `subscription_id` | uuid | YES | — | FK → `subscriptions` |
| `notif_type` | text | YES | — |
| `channel` | text | YES | — |
| `scheduled_for` | timestamptz | YES | — |
| `payload` | jsonb | YES | — |
| `status` | text | YES | — |
| `sent_at` | timestamptz | YES | — |
| `last_error` | text | YES | — |
| `created_at` | timestamptz | — | — |

**UNIQUE:** `(account_id, notif_type, channel, scheduled_for)`

---

### 3.25 `subscription_locks`
> 20260207.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `account_id` | uuid | NO | — | **PK** |
| `locked_at` | timestamptz | NO | `now()` |
| `locked_by` | text | YES | — |

---

### 3.26 `mp_connections`
> 20250102000000.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE, UNIQUE |
| `client_id_backend` | uuid | YES | — |
| `access_token` | text | YES | — | ⚠️ encrypted |
| `public_key` | text | YES | — |
| `refresh_token` | text | YES | — | ⚠️ encrypted |
| `mp_user_id` | text | YES | — |
| `live_mode` | boolean | YES | — |
| `expires_at` | timestamptz | YES | — |
| `status` | text | YES | — | CHECK: connected/revoked/error/expired |
| `last_error` | text | YES | — |
| `last_refresh_at` | timestamptz | YES | — |
| `connected_at` | timestamptz | YES | — |
| `updated_at` | timestamptz | — | — |

---

### 3.27 `managed_domains`
> ADMIN_052.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `domain` | citext | NO | — | UNIQUE |
| `expires_at` | timestamptz | YES | — |
| `auto_renew` | boolean | YES | — |
| `renewal_state` | managed_domain_renewal_state | YES | — |
| `renewal_window_days` | integer | YES | — |
| `renewal_price_ars` | numeric | YES | — |
| `management_fee_ars` | numeric | YES | — |
| `provider` | text | YES | — |
| `renewal_expected_price` | numeric | YES | — |
| `renewal_checkout_id` | uuid | YES | — |
| `renewal_payment_id` | uuid | YES | — |
| `renewal_requested_at` | timestamptz | YES | — |
| `last_renewed_at` | timestamptz | YES | — |
| `renewal_years` | integer | YES | — |
| `last_notified_at` | timestamptz | YES | — |
| `notification_stage` | text | YES | — |
| `active_renewal_id` | uuid | YES | — | ADMIN_053 |
| `management_fee_usd_override` | numeric | YES | — | ADMIN_053 |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

**UNIQUE:** `(account_id, domain)`

---

### 3.28 `managed_domain_renewals`
> ADMIN_053.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `managed_domain_id` | uuid | NO | — | FK → `managed_domains` ON DELETE CASCADE |
| `renewal_cost_usd` | numeric | YES | — |
| `management_fee_usd` | numeric | YES | — |
| `total_usd` | numeric | YES | — |
| `fx_rate_snapshot` | numeric | YES | — |
| `total_ars_charged` | numeric | YES | — |
| `quote_source` | text | YES | — |
| `quote_valid_until` | timestamptz | YES | — |
| `mp_preference_id` | text | YES | — |
| `payment_id` | uuid | YES | — |
| `payment_status` | text | YES | — |
| `status` | text | YES | — | CHECK: quoted/invoice_created/paid/renewed/failed/expired/cancelled |
| `manual_required_reason` | text | YES | — | CHECK constraint |
| `manual_required_detail` | text | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

---

### 3.29 `system_events`
> 20260102000005.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `created_at` | timestamptz | — | — |
| `level` | text | YES | — | CHECK: info/warn/error |
| `event_type` | text | YES | — |
| `account_id` | uuid | YES | — |
| `client_id` | uuid | YES | — |
| `user_id` | uuid | YES | — |
| `request_id` | text | YES | — |
| `ref_id` | text | YES | — |
| `message` | text | YES | — |
| `details` | jsonb | YES | — |

---

### 3.30 `lifecycle_events`
> 20260207.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `event_type` | text | NO | — |
| `old_value` | jsonb | YES | — |
| `new_value` | jsonb | YES | — |
| `source` | text | NO | — |
| `correlation_id` | text | YES | — |
| `metadata` | jsonb | YES | — |
| `created_at` | timestamptz | NO | `now()` |
| `created_by` | uuid | YES | — |

---

### 3.31 `email_jobs`
> 20260118_create_email_jobs, extendido con dedup en 20260118_add_email_deduplication.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `client_id` | text | YES | — |
| `order_id` | uuid | YES | — |
| `type` | text | YES | — |
| `payload` | jsonb | YES | — |
| `status` | text | YES | `'pending'` |
| `attempts` | integer | YES | — |
| `max_attempts` | integer | YES | `3` |
| `run_at` | timestamptz | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |
| `sent_at` | timestamptz | YES | — |
| `error` | text | YES | — |
| `dedupe_key` | text | YES | — | UNIQUE partial WHERE status != 'failed' |
| `provider_message_id` | text | YES | — |
| `provider_response` | jsonb | YES | — |
| `to_email` | text | YES | — |
| `template` | text | YES | — |
| `trigger_event` | text | YES | — |
| `request_id` | text | YES | — |
| `next_retry_at` | timestamptz | YES | — |

---

### 3.32 `tenant_payment_events`
> 20260121.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `event_key` | text | YES | — | UNIQUE index |
| `topic` | text | YES | — |
| `resource_id` | text | YES | — |
| `external_reference` | text | YES | — |
| `tenant_id` | uuid | YES | — |
| `cluster_id` | uuid | YES | — |
| `signature_valid` | boolean | YES | — |
| `payload` | jsonb | YES | — |
| `received_at` | timestamptz | YES | — |
| `processed_at` | timestamptz | YES | — |
| `process_result` | text | YES | — |
| `last_error` | text | YES | — |

---

### 3.33 `pro_projects`
> 20250101000002.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `status` | text | YES | `'kickoff_pending'` |
| `brief_data` | jsonb | YES | — |
| `notes` | text | YES | — |
| `assigned_to` | text | YES | — |
| `estimated_go_live` | timestamptz | YES | — |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

---

### 3.34 `client_completion_checklist`
> add_client_completion_checklist, extendido en 20260127/add_faqs_count.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE, UNIQUE |
| `logo_uploaded` | boolean | YES | `false` |
| `banner_uploaded` | boolean | YES | `false` |
| `products_count` | integer | YES | `0` |
| `categories_count` | integer | YES | `0` |
| `faqs_added` | boolean | YES | `false` |
| `faqs_count` | integer | YES | `0` |
| `contact_info_added` | boolean | YES | `false` |
| `social_links_added` | boolean | YES | `false` |
| `completion_percentage` | integer | YES | `0` |
| `last_updated_at` | timestamptz | — | `NOW()` |
| `completed_at` | timestamptz | YES | — |
| `notified_admin_at` | timestamptz | YES | — |
| `created_at` | timestamptz | — | `NOW()` |
| `updated_at` | timestamptz | — | `NOW()` |
| *(review columns)* | — | — | — | 20260127 |

---

### 3.35 `client_completion_events`
> 20260127.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | PK |
| `account_id` | uuid | NO | — | FK → `nv_accounts` ON DELETE CASCADE |
| `type` | text | YES | — |
| `payload` | jsonb | YES | — |
| `actor_id` | uuid | YES | — |
| `actor_label` | text | YES | — |
| `created_at` | timestamptz | — | — |

---

### 3.36 `nv_account_settings`
> 20260202.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `nv_account_id` | uuid | NO | — | FK → `nv_accounts`, parte del PK |
| `key` | text | NO | — | parte del PK |
| `value` | jsonb | YES | — |
| `updated_at` | timestamptz | — | — |
| `updated_by` | uuid | YES | — |

**PK:** `(nv_account_id, key)`

---

### 3.37 `dev_portal_whitelist`
> 20260205.

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `email` | citext | NO | — | **PK** |
| `enabled` | boolean | YES | — |
| `note` | text | YES | — |
| `created_by` | uuid | YES | — | FK → `auth.users` |
| `created_at` | timestamptz | — | — |
| `updated_at` | timestamptz | — | — |

---

### 3.38 Tablas de staging (DEPRECATED – dropped en 20260205)

> Fueron creadas en `create_completion_staging_tables.sql` y eliminadas en `20260205_drop_completion_staging_tables.sql`.

- `completion_products` — DROPPED
- `completion_categories` — DROPPED
- `completion_faqs` — DROPPED
- `completion_contact_info` — DROPPED
- `completion_social_links` — DROPPED

---

## 4. Índices

| Tabla | Índice | Columnas | Tipo/Parcial |
|-------|--------|----------|--------------|
| nv_accounts | `idx_nv_accounts_plan` | plan_key | btree |
| nv_accounts | `idx_nv_accounts_status` | status | btree |
| nv_accounts | `idx_nv_accounts_user` | user_id | btree |
| nv_accounts | `idx_nv_accounts_draft_expires` | draft_expires_at | partial: WHERE deleted_at IS NULL |
| nv_accounts | `idx_nv_accounts_deleted` | deleted_at | partial: WHERE deleted_at IS NOT NULL |
| nv_accounts | `idx_nv_accounts_super_admin` | is_super_admin | partial: WHERE is_super_admin=true |
| nv_accounts | UNIQUE partial | lower(custom_domain) | WHERE custom_domain IS NOT NULL |
| nv_onboarding | `idx_nv_onboarding_payment` | checkout_payment_id | UNIQUE partial WHERE NOT NULL |
| nv_onboarding | `idx_nv_onboarding_external_ref` | checkout_external_reference | partial WHERE NOT NULL |
| account_addons | `idx_account_addons_account` | account_id | btree |
| provisioning_jobs | `idx_jobs_status_run_after` | status, run_after | btree |
| provisioning_jobs | UNIQUE | dedupe_key | WHERE dedupe_key IS NOT NULL |
| provisioning_job_steps | UNIQUE | (job_id, step_name) | |
| mp_events | UNIQUE | mp_event_id | |
| plans | `idx_plans_is_active` | is_active | btree |
| plans | `idx_plans_sort_order` | sort_order | btree |
| plans | `idx_plans_recommended` | recommended | btree |
| palette_catalog | `idx_palette_catalog_active_true` | — | partial WHERE is_active=true |
| palette_catalog | `idx_palette_catalog_min_plan_key` | min_plan_key | btree |
| slug_reservations | `idx_slug_reservations_expires` | expires_at | btree |
| webhook_events | `idx_webhook_events_dedup` | (source, payment_id, event_type) | UNIQUE |
| nv_billing_events | UNIQUE | external_reference | |
| nv_billing_events | UNIQUE partial | provider_payment_id | WHERE NOT NULL |
| subscriptions | UNIQUE | account_id | |
| subscriptions | UNIQUE | provider_id | |
| subscriptions | `ux_subscriptions_one_active_per_account` | account_id | UNIQUE partial WHERE status='active' |
| subscriptions | `idx_subs_last_mp_synced` | last_mp_synced_at | partial WHERE status IN (active, past_due, grace) |
| system_events | multiple | account_id, event_type, etc. | btree |
| lifecycle_events | `idx_lifecycle_events_account` | (account_id, created_at DESC) | btree |
| lifecycle_events | `idx_lifecycle_events_type` | (event_type, created_at DESC) | btree |
| lifecycle_events | `idx_lifecycle_events_correlation` | correlation_id | partial WHERE NOT NULL |
| client_completion_checklist | `idx_completion_account` | account_id | btree |
| client_completion_checklist | `idx_completion_percentage` | completion_percentage | btree |
| tenant_payment_events | UNIQUE | event_key | |
| managed_domains | UNIQUE | domain | citext |
| managed_domains | UNIQUE | (account_id, domain) | |

---

## 5. Constraints

### CHECK constraints notables
| Tabla | Constraint | Expresión |
|-------|-----------|-----------|
| nv_accounts | `nv_accounts_status_check` | 14 valores válidos |
| nv_accounts | `chk_nv_subscription_status` | 12 valores válidos + NULL |
| nv_accounts | `nv_accounts_paid_requires_cluster` | Requiere cluster si status en paid/provisioning/provisioned/live |
| nv_onboarding | design_config CHECK | jsonb_typeof='object' OR NULL |
| subscriptions | period CHECK | current_period_end >= current_period_start |
| subscriptions | `subscriptions_plan_key_check` | plan_key format |
| coupons | discount_type CHECK | percentage/fixed_amount |
| coupons | discount_value CHECK | > 0 |
| webhook_events | status CHECK | received/processing/processed/failed |
| provisioning_job_steps | status CHECK | queued/running/done/failed/skipped |
| mp_connections | status CHECK | connected/revoked/error/expired |
| client_themes | template_key CHECK | `^[a-z0-9-]+$` regex |
| managed_domain_renewals | status CHECK | 7 valores |

---

## 6. RLS Policies

### Patrón general observado

1. **`service_role` bypass** — en la mayoría de tablas
2. **`is_super_admin()`** — función central de autorización
3. **Owner access** — `nv_accounts.user_id = auth.uid()`
4. **JWT metadata check** — `app_metadata.is_super_admin` o `user_metadata.is_super_admin`
5. **Email hardcoded** — `novavision.contact@gmail.com` y `elias@novavision.com.ar`

### Inventario por tabla

| Tabla | RLS Habilitado | Políticas |
|-------|---------------|-----------|
| **nv_accounts** | ✅ | select/update/insert/delete super_admin; select/update owner (user_id=auth.uid()) |
| **nv_onboarding** | ✅ | super_admin_all; select_own; update_own (via nv_accounts.user_id) |
| **plans** | ✅ | service_role bypass; `plans_read_all` (authenticated SELECT) |
| **addon_catalog** | ✅ | service_role bypass; `addon_catalog_read_all` (authenticated SELECT) |
| **account_addons** | ✅ | service_role bypass |
| **account_entitlements** | ✅ | service_role bypass |
| **provisioning_jobs** | ✅ | service_role bypass |
| **mp_events** | ✅ | service_role bypass |
| **backend_clusters** | ✅ | service_role bypass |
| **nv_billing_events** | ✅ | super admin ALL; account owner SELECT (WHERE account_id matches uid) |
| **subscriptions** | ✅ | select/insert/update/delete + service_role (20260102000001) |
| **subscription_events** | ✅ | service_role + super admin |
| **subscription_notification_outbox** | ✅ | service_role + super admin |
| **subscription_locks** | ✅ | service_role only |
| **tenant_payment_events** | ✅ | service_role + super admin |
| **system_events** | ✅ | super_admin + client own events |
| **lifecycle_events** | ✅ | service_role bypass only |
| **email_jobs** | ✅ | service_role only |
| **mp_connections** | ✅ | service_role only |
| **custom_palettes** | ✅ | client own (via app.client_id setting) |
| **client_themes** | ✅ | client read/update/insert own + admin manage all |
| **nv_templates** | ✅ | public read + admin manage |
| **managed_domains** | ✅ | GRANT to authenticated + service_role |
| **managed_domain_renewals** | ✅ | service_role full access |
| **client_completion_checklist** | ✅ | owner view/update; super admin all; service_role all |
| **client_completion_events** | ✅ | client own + super admin + service_role |
| **nv_account_settings** | ✅ | super admin + service_role |
| **dev_portal_whitelist** | ✅ | super_admin all; read own; service bypass |
| **client_usage_month** | ✅ | Super Admin Access + service_role_bypass |
| **invoices** | ✅ | Super Admin Access + service_role_bypass |
| **payments** | ✅ | Super Admin Access + service_role_bypass |
| **users** | ✅ | Super Admin Access + service_role_bypass |
| **sync_cursors** | ✅ | Super Admin Access + service_role_bypass |
| **super_admins** | ❌ **DISABLED** | Explícitamente deshabilitado en 20260201 |
| **auth_handoff** | ❌ **NOT ENABLED** | Nunca se habilita RLS |

### Patrón "Super Admin Access" (20260201 + 20260207)
Aplicado a 14+ tablas con esta expresión:
```sql
USING (
  ((auth.jwt()->'app_metadata'->>'is_super_admin')::boolean = true
  OR (auth.jwt()->'user_metadata'->>'is_super_admin')::boolean = true
  OR auth.email() = 'novavision.contact@gmail.com'
  OR auth.email() = 'elias@novavision.com.ar'
  OR is_super_admin())
)
```

> ⚠️ **HALLAZGO:** Emails hardcodeados como bypass de seguridad.

---

## 7. Funciones / RPCs

| Función | Tipo | Security | Migración | Propósito |
|---------|------|----------|-----------|-----------|
| `is_super_admin()` | RETURNS boolean | SECURITY DEFINER | 20250101000006 | Verifica email en `super_admins` |
| `has_valid_mp_connection(uuid)` | RETURNS boolean | — | 20250102000000 | Verifica conexión MP activa |
| `mark_mp_connection_for_refresh(uuid)` | RETURNS void | — | 20250102000000 | Marca conexión MP para refresh |
| `set_updated_at()` | RETURNS trigger | — | ADMIN_011 | Trigger genérico updated_at |
| `claim_provisioning_jobs(int)` | RETURNS TABLE | SECURITY DEFINER | 202503081300 | FOR UPDATE SKIP LOCKED |
| `enqueue_provisioning_job(...)` | RETURNS uuid | — | ADMIN_057 | Idempotent upsert por dedupe_key |
| `is_provisioning_step_done(uuid, text)` | RETURNS boolean | — | ADMIN_058 | Verifica step completado |
| `get_provisioning_step_data(uuid, text)` | RETURNS jsonb | — | ADMIN_058 | Obtiene datos de step |
| `set_backend_cluster_db_url(text, text, text)` | RETURNS void | SECURITY DEFINER | 202601201810 | PGP encrypt db_url |
| `get_backend_cluster_db_url(text, text)` | RETURNS text | SECURITY DEFINER | 202601201810 | PGP decrypt db_url |
| `try_lock_subscription(uuid, int)` | RETURNS boolean | SECURITY DEFINER | 20260207 | Lock distribuido |
| `release_subscription_lock(uuid)` | RETURNS void | SECURITY DEFINER | 20260207 | Release lock |
| `cleanup_stale_subscription_locks(int)` | RETURNS integer | SECURITY DEFINER | 20260207 | Limpieza de locks vencidos |
| `calculate_completion_percentage(uuid)` | RETURNS integer | — | add_client_completion_checklist | Calcula % completitud |
| `update_completion_percentage()` | RETURNS trigger | — | add_client_completion_checklist | Auto-update en trigger |
| `dashboard_metrics(...)` | RETURNS jsonb | — | 20260201 (múltiples versiones) | Métricas del dashboard |
| `finance_summary(...)` | RETURNS jsonb | — | 20260201 | Resumen financiero |
| `get_billing_dashboard(...)` | RETURNS jsonb | — | 20260201 | Vista unificada billing |
| `dashboard_tops(...)` | RETURNS jsonb | — | 20260201 | Top accounts |
| `dashboard_client_detail(...)` | RETURNS jsonb | — | 20260201 | Detalle por cliente |
| `check_invariant_approved_consistency()` | RETURNS TABLE | — | 20260118 | Invariant check |
| `check_invariant_pending_subscription()` | RETURNS TABLE | — | 20260118 | Invariant check |
| `check_invariant_active_client_subscription()` | RETURNS TABLE | — | 20260118 | Invariant check |
| `check_invariant_data_sync()` | RETURNS TABLE | — | 20260118 | Invariant check |
| `check_all_invariants()` | RETURNS TABLE | — | 20260118 | Ejecuta todas las invariants |

> ⚠️ **HALLAZGO:** 6 funciones `SECURITY DEFINER` — se ejecutan con los privilegios del owner (superuser si fue creada con service_role). Riesgo de escalación si mal usadas.

---

## 8. Triggers

| Trigger | Tabla | Función | Evento |
|---------|-------|---------|--------|
| `trg_palette_catalog_set_updated_at` | palette_catalog | `set_updated_at()` | BEFORE UPDATE |
| `trg_custom_palettes_set_updated_at` | custom_palettes | `set_updated_at()` | BEFORE UPDATE |
| `trg_client_themes_updated_at` | client_themes | `set_updated_at()` | BEFORE UPDATE |
| `trg_nv_templates_updated_at` | nv_templates | `set_updated_at()` | BEFORE UPDATE |
| `trigger_update_state_updated_at` | nv_onboarding | auto-set state_updated_at | BEFORE UPDATE OF state |
| `webhook_events_updated_at` | webhook_events | `set_updated_at()` | BEFORE UPDATE |
| `mp_connections_updated_at` | mp_connections | `set_updated_at()` | BEFORE UPDATE |
| `trg_subscriptions_updated` | subscriptions | `set_updated_at()` | BEFORE UPDATE |
| `trg_email_jobs_updated` | email_jobs | `set_updated_at()` | BEFORE UPDATE |
| `trg_sync_provisioning_jobs_fields` | provisioning_jobs | sync job_type↔type + dedupe_key | BEFORE INSERT OR UPDATE |
| `trigger_update_completion_percentage` | client_completion_checklist | `update_completion_percentage()` | BEFORE UPDATE |
| `trigger_update_dev_portal_whitelist_updated_at` | dev_portal_whitelist | `set_updated_at()` | BEFORE UPDATE |

---

## 9. GRANTs

| Tabla/Objeto | Role | Permisos | Migración |
|--------------|------|----------|-----------|
| nv_accounts | authenticated | SELECT, INSERT, UPDATE | 20260207 |
| nv_onboarding | authenticated | SELECT, INSERT, UPDATE | 20260207 |
| client_usage_month | authenticated | SELECT, INSERT, UPDATE, DELETE | 20260207 |
| invoices | authenticated | SELECT, INSERT, UPDATE, DELETE | 20260207 |
| payments | authenticated | SELECT, INSERT, UPDATE, DELETE | 20260207 |
| users | authenticated | SELECT, INSERT, UPDATE, DELETE | 20260207 |
| sync_cursors | authenticated | SELECT, INSERT, UPDATE, DELETE | 20260207 |
| client_tombstones | authenticated | SELECT | 20260207 |
| client_usage_month | service_role | ALL | 20260207 |
| invoices | service_role | ALL | 20260207 |
| payments | service_role | ALL | 20260207 |
| users | service_role | ALL | 20260207 |
| sync_cursors | service_role | ALL | 20260207 |
| completion_* (staging) | authenticated | ALL | create_completion_staging (DROPPED) |
| completion_* (staging) | service_role | ALL | create_completion_staging (DROPPED) |
| managed_domains | authenticated | — | ADMIN_052 |
| managed_domains | service_role | — | ADMIN_052 |
| `dashboard_metrics` (function) | authenticated | EXECUTE | ADMIN_035 |
| `claim_provisioning_jobs` (function) | service_role | EXECUTE | 202503081300 |
| `get_billing_dashboard` (function) | service_role | EXECUTE | 20260201 |

> ⚠️ **HALLAZGO:** `authenticated` role tiene DELETE en `invoices`, `payments`, `users`, `sync_cursors`. Si el RLS no filtra correctamente, cualquier usuario autenticado podría potencialmente borrar registros.

---

## 10. pg_cron Jobs

No se encontraron definiciones de `pg_cron` en los archivos de migración. Los crons se manejan externamente (Railway cron o aplicación NestJS).

La función `cleanup_stale_subscription_locks()` está diseñada para ser llamada desde un cron, pero la configuración del cron no está en las migraciones.

---

## 11. Storage Operations

No se encontraron operaciones de Supabase Storage (`storage.buckets`, `storage.objects`) en los archivos de migración del Admin DB. El storage se gestiona desde el backend (NestJS) directamente con la API de Supabase Storage.

---

## 12. Hallazgos de Seguridad

### 🔴 Críticos

| # | Descripción | Ubicación | Riesgo |
|---|-------------|-----------|--------|
| S-01 | **RLS DESHABILITADO en `super_admins`** | 20260201_fix_super_admin_rls.sql | Cualquier usuario con GRANT SELECT podría leer la tabla completa de super admins. Combinado con que `is_super_admin()` depende de esta tabla → un atacante que pueda insertar un email aquí se convierte en super admin. |
| S-02 | **RLS NO HABILITADO en `auth_handoff`** | ADMIN_030 | Tokens de handoff (aunque hasheados y encriptados) son accesibles sin filtro de tenant. |
| S-03 | **Emails hardcodeados como bypass** en políticas Super Admin | 20260201, 20260207 | `novavision.contact@gmail.com` y `elias@novavision.com.ar` hardcodeados en USING expressions. Si una cuenta con ese email es comprometida, tiene acceso total a todas las tablas. No se puede rotar sin migración. |
| S-04 | **6 funciones SECURITY DEFINER** | Múltiples | Se ejecutan con privilegios del owner. `try_lock_subscription`, `release_subscription_lock`, `set_backend_cluster_db_url`, `get_backend_cluster_db_url`, `claim_provisioning_jobs`, `cleanup_stale_subscription_locks`. Validar que los GRANTs de EXECUTE sean estrictos. |

### 🟡 Medio

| # | Descripción | Ubicación | Riesgo |
|---|-------------|-----------|--------|
| S-05 | **`service_role_key` en texto plano** en `backend_clusters` (versión 20250101000002) | 20250101000002 | La columna `service_role_key` almacena la key de servicio de otros proyectos Supabase sin encriptar. La versión 202601201810 añade PGP para `db_url` pero no para `service_role_key`. |
| S-06 | **GRANTs amplios a `authenticated`** | 20260207 | DELETE en `invoices`, `payments`, `users` — protegido solo por RLS. Si las políticas RLS son insuficientes, el riesgo es alto. |
| S-07 | **`access_token` y `refresh_token` de MP** campo `text` | 20250102000000 | Marcados como "encrypted" en comentarios pero almacenados como text. La encriptación probablemente es a nivel aplicación (NestJS), no DB. |
| S-08 | **is_super_admin() usa SECURITY DEFINER** | 20250101000006 | La función consulta `super_admins` y la ejecuta como owner del schema. Si `super_admins` no tiene RLS (ver S-01), el riesgo se amplifica. |
| S-09 | **Múltiples definiciones conflictivas** de `super_admins` y `backend_clusters` | ADMIN_010 vs 20250101000002, ADMIN_036 vs 20250101000006 | Schemas parcialmente incompatibles (uuid PK vs text PK). Depende del orden de ejecución. |

### 🟢 Bajo / Informativos

| # | Descripción | Ubicación |
|---|-------------|-----------|
| S-10 | Tablas de staging (completion_*) fueron correctamente eliminadas | 20260205 |
| S-11 | `subscription_locks` TTL de 30s por defecto es seguro para lock contention | 20260207 |
| S-12 | Invariant check functions permiten auditoría de consistencia de datos | 20260118 |
| S-13 | Webhook dedup por `(source, payment_id, event_type)` previene doble procesamiento | ADMIN_024 |
| S-14 | Partial unique index previene doble suscripción activa | 20260207 |

---

## Resumen ejecutivo

| Métrica | Valor |
|---------|-------|
| **Tablas activas** | ~35 |
| **Tablas dropped** | 5 (completion staging) + clients + plan_definitions |
| **Enums** | 7 |
| **Funciones** | ~22 |
| **Triggers** | 12 |
| **Funciones SECURITY DEFINER** | 6 |
| **Tablas con RLS habilitado** | ~33 |
| **Tablas sin RLS** | 2 (`auth_handoff`, `super_admins`→disabled) |
| **Hallazgos críticos** | 4 |
| **Hallazgos medios** | 5 |
| **Archivos de migración** | 100+ |
| **Emails hardcodeados en policies** | 2 |

---

*Fin del reporte de auditoría.*

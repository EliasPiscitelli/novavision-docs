# Inventario Completo — Admin DB (Supabase)

> **Generado:** 2026-02-08  
> **Fuente:** Todos los archivos en `apps/api/migrations/admin/`  
> **Nota:** Este inventario refleja el estado **final** acumulado de todas las migraciones.  
> Las tablas staging (`completion_*`) fueron creadas y luego **DROPeadas** en `20260205_drop_completion_staging_tables.sql` — se documentan como **ELIMINADAS**.

---

## 1. Extensiones

| Extensión | Migración |
|-----------|-----------|
| `pgcrypto` | ADMIN_001 |
| `citext` | ADMIN_001 |
| `uuid-ossp` | create_completion_staging_tables (redundante con pgcrypto) |

---

## 2. Enums

### `nv_onboarding_state`

| Valor | Origen |
|-------|--------|
| `draft_builder` | ADMIN_002 (original) |
| `pending_payment` | ADMIN_002 |
| `approved` | ADMIN_002 |
| `provisioning` | ADMIN_002 |
| `live` | ADMIN_002 |
| `failed` | ADMIN_002 |
| `pending_review` | 20260203 |
| `submitted_for_review` | 20260203 / fix_enum_and_backfill_state |
| `rejected` | 20260203 |
| `provisioned` | 20260203 |

### `nv_job_status`

| Valor | Origen |
|-------|--------|
| `queued` | ADMIN_002 (original) |
| `running` | ADMIN_002 |
| `done` | ADMIN_002 |
| `failed` | ADMIN_002 |
| `pending` | ADMIN_016 |
| `completed` | ADMIN_016 |

### `billing_event_type`

| Valor | Origen |
|-------|--------|
| `domain_renewal` | ADMIN_044 |
| `plan_subscription` | ADMIN_044 |
| `one_time_service` | ADMIN_044 |

### `billing_event_status`

| Valor | Origen |
|-------|--------|
| `pending` | ADMIN_044 |
| `paid` | ADMIN_044 |
| `failed` | ADMIN_044 |
| `cancelled` | ADMIN_044 |

### `subscription_status`

| Valor | Origen |
|-------|--------|
| `active` | 20260102000001 |
| `past_due` | 20260102000001 |
| `grace` | 20260102000001 |
| `expired` | 20260102000001 |
| `canceled` | 20260102000001 |
| `pending` | 20260102000003 |
| `grace_period` | 20260102000003 |
| `suspended` | 20260102000003 |
| `paused` | 20260102000003 |
| `cancel_scheduled` | 20260120 |
| `deactivated` | 20260120 |
| `purged` | 20260120 |

### `publication_status_enum`

| Valor | Origen |
|-------|--------|
| `draft` | 20250101000003 |
| `pending_approval` | 20250101000003 |
| `published` | 20250101000003 |
| `paused` | 20250101000003 |
| `rejected` | 20250101000003 |

### `managed_domain_renewal_state`

| Valor | Origen |
|-------|--------|
| `none` | ADMIN_052 |
| `due_soon` | ADMIN_052 |
| `invoice_created` | ADMIN_052 |
| `paid` | ADMIN_052 |
| `overdue` | ADMIN_052 |
| `renewal_failed` | ADMIN_052 |

---

## 3. Tablas

### 3.1 `nv_accounts`

> Tabla principal de cuentas/tenants del sistema NovaVision.

| Columna | Tipo | Nullable | Default | Notas |
|---------|------|----------|---------|-------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `email` | citext | NO | — | UNIQUE |
| `slug` | text | NO | — | UNIQUE |
| `plan_key` | text | NO | `'starter'` | |
| `backend_cluster_id` | text | YES | — | FK → backend_clusters(cluster_id), originalmente uuid |
| `draft_expires_at` | timestamptz | YES | — | |
| `created_at` | timestamptz | YES | `now()` | |
| `updated_at` | timestamptz | YES | `now()` | |
| `deleted_at` | timestamptz | YES | — | Soft delete (ADMIN_016) |
| `subscription_id` | uuid | YES | — | (ADMIN_016) |
| `subscription_status` | text | YES | — | CHECK `chk_nv_subscription_status` |
| `user_id` | uuid | YES | — | FK → auth.users (ADMIN_022) |
| `status` | text | YES | `'draft'` | CHECK `nv_accounts_status_check` |
| `last_saved_at` | timestamptz | YES | — | |
| `terms_accepted_at` | timestamptz | YES | — | (ADMIN_028) |
| `terms_version` | text | YES | — | |
| `is_super_admin` | boolean | YES | `false` | (ADMIN_034) |
| `dni` | text | YES | — | (ADMIN_036) |
| `identity_verified` | boolean | YES | `false` | |
| `dni_front_url` | text | YES | — | |
| `dni_back_url` | text | YES | — | |
| `identity_verified_at` | timestamptz | YES | — | |
| `business_name` | text | YES | — | (ADMIN_041) |
| `cuit_cuil` | text | YES | — | |
| `fiscal_address` | text | YES | — | |
| `phone` | text | YES | — | |
| `billing_email` | citext | YES | — | |
| `mp_connected` | boolean | YES | `false` | (MP OAuth) |
| `mp_user_id` | text | YES | — | |
| `mp_connected_at` | timestamptz | YES | — | |
| `fulfillment_mode` | text | YES | — | CHECK (`self_serve` \| `concierge`) |
| `backend_api_url` | text | YES | — | (Pro/Concierge) |
| `dedicated_project_ref` | text | YES | — | |
| `go_live_approved_at` | timestamptz | YES | — | |
| `migration_status` | text | YES | — | |
| `migration_started_at` | timestamptz | YES | — | |
| `migration_completed_at` | timestamptz | YES | — | |
| `migrated_from_cluster_id` | text | YES | — | |
| `last_migration_job_id` | uuid | YES | — | |
| `store_paused` | boolean | YES | `false` | (Store pause) |
| `store_paused_at` | timestamptz | YES | — | |
| `store_resumed_at` | timestamptz | YES | — | |
| `store_pause_reason` | text | YES | — | |
| `custom_domain` | text | YES | — | |
| `custom_domain_status` | text | YES | — | CHECK (`NULL` \| `pending_dns` \| `active` \| `error`) |
| `custom_domain_mode` | text | YES | — | CHECK (`NULL` \| `self_service` \| `concierge`) |
| `custom_domain_requested_at` | timestamptz | YES | — | |
| `custom_domain_verified_at` | timestamptz | YES | — | |
| `custom_domain_last_checked_at` | timestamptz | YES | — | |
| `custom_domain_error` | text | YES | — | |
| `custom_domain_concierge_until` | timestamptz | YES | — | |
| `netlify_site_id` | text | YES | — | |

**CHECK Constraints:**

| Nombre | Expresión |
|--------|-----------|
| `nv_accounts_status_check` | `status IN ('draft','awaiting_payment','paid','provisioning','provisioned','pending_approval','incomplete','changes_requested','approved','rejected','expired','failed','suspended','live')` |
| `chk_nv_subscription_status` | `subscription_status IS NULL OR subscription_status IN ('active','pending','past_due','grace','grace_period','suspended','paused','canceled','cancel_scheduled','deactivated','expired','purged')` |
| `nv_accounts_custom_domain_status_check` | `custom_domain_status IS NULL OR IN ('pending_dns','active','error')` |
| `nv_accounts_custom_domain_mode_check` | `custom_domain_mode IS NULL OR IN ('self_service','concierge')` |
| `check_fulfillment_mode` | `fulfillment_mode IS NULL OR IN ('self_serve','concierge')` |
| `nv_accounts_paid_requires_cluster` | `NOT (status IN ('paid','provisioning','live') AND backend_cluster_id IS NULL)` |

**Índices:**

| Nombre | Columna(s) | Tipo | Condición |
|--------|-----------|------|-----------|
| `nv_accounts_pkey` | `id` | PK | — |
| `nv_accounts_email_key` | `email` | UNIQUE | — |
| `nv_accounts_slug_key` | `slug` | UNIQUE | — |
| `idx_nv_accounts_plan` | `plan_key` | btree | — |
| `idx_nv_accounts_draft_expires` | `draft_expires_at` | btree | `WHERE deleted_at IS NULL` |
| `idx_nv_accounts_deleted` | `deleted_at` | btree | `WHERE deleted_at IS NOT NULL` |
| `idx_nv_accounts_status` | `status` | btree | — |
| `idx_nv_accounts_user` | `user_id` | btree | — |
| `idx_nv_accounts_expired` | `draft_expires_at` | btree | `WHERE status = 'draft'` (probablemente) |
| `idx_nv_accounts_super_admin` | `is_super_admin` | btree | `WHERE is_super_admin = TRUE` |
| `idx_nv_accounts_terms_accepted` | `terms_accepted_at` | btree | — |
| `idx_nv_accounts_identity_verified` | `identity_verified` | btree | — |
| `idx_nv_accounts_cuit_cuil` | `cuit_cuil` | btree | — |
| `idx_nv_accounts_billing_email` | `billing_email` | btree | — |
| `idx_accounts_mp_connected` | `mp_connected` | btree | — |
| `idx_nv_accounts_custom_domain_lower` | `lower(custom_domain)` | UNIQUE | `WHERE custom_domain IS NOT NULL` |

**RLS:** Habilitada

| Política | Operación | USING | WITH CHECK |
|----------|-----------|-------|------------|
| `nv_accounts_service_role` | ALL | `auth.role() = 'service_role'` | `auth.role() = 'service_role'` |
| `nv_accounts_select_super_admin` | SELECT | `is_super_admin()` | — |
| `nv_accounts_select_owner` | SELECT | `user_id = auth.uid()` | — |
| `nv_accounts_update_policy` | UPDATE | (owner based) | (owner based) |
| `nv_accounts_insert_policy` | INSERT | — | (conditions vary) |
| `nv_accounts_delete_policy` | DELETE | (conditions vary) | — |
| `Super Admin Access` | ALL | Super admin JWT checks + `is_super_admin()` | idem |

---

### 3.2 `nv_onboarding`

> Datos y estado del onboarding de cada cuenta.

| Columna | Tipo | Nullable | Default | Notas |
|---------|------|----------|---------|-------|
| `account_id` | uuid | NO | — | PK, FK → nv_accounts ON DELETE CASCADE |
| `state` | nv_onboarding_state | NO | `'draft_builder'` | |
| `selected_template_key` | text | YES | — | |
| `selected_palette_key` | text | YES | — | |
| `data` | jsonb | YES | — | |
| `created_at` | timestamptz | YES | `now()` | |
| `updated_at` | timestamptz | YES | `now()` | |
| `selected_theme_override` | jsonb | YES | — | (ADMIN_012) |
| `design_config` | jsonb | YES | — | CHECK is object (ADMIN_013) |
| `state_reason` | text | YES | — | (ADMIN_016) |
| `state_updated_at` | timestamptz | YES | — | |
| `plan_key_selected` | text | YES | — | (ADMIN_022) |
| `cycle` | text | YES | — | |
| `checkout_preference_id` | text | YES | — | |
| `checkout_external_reference` | text | YES | — | |
| `checkout_payment_id` | text | YES | — | |
| `checkout_quote_usd` | numeric | YES | — | |
| `checkout_quote_ars` | numeric | YES | — | |
| `checkout_blue_rate` | numeric | YES | — | |
| `checkout_created_at` | timestamptz | YES | — | |
| `paid_at` | timestamptz | YES | — | |
| `client_id` | uuid | YES | — | FK → clients (pre-drop) |
| `provisioned_at` | timestamptz | YES | — | |
| `provisioning_error` | text | YES | — | |
| `mp_connection_status` | text | YES | — | CHECK (`pending` \| `connected` \| `error` \| `skipped`) |
| `mp_error` | text | YES | — | |
| `progress` | jsonb | YES | — | (20260203) |
| `submitted_at` | timestamptz | YES | — | |
| `reviewed_at` | timestamptz | YES | — | |
| `reviewed_by` | uuid | YES | — | |
| `rejection_reason` | text | YES | — | |

**RLS:** Habilitada

| Política | Operación | USING / WITH CHECK |
|----------|-----------|-------------------|
| `nv_onboarding_service_role` | ALL | `auth.role() = 'service_role'` |
| `nv_onboarding_super_admin_all` | ALL | `is_super_admin()` |
| `nv_onboarding_select_own` | SELECT | `account_id IN (SELECT id FROM nv_accounts WHERE user_id = auth.uid())` |
| `nv_onboarding_update_own` | UPDATE | idem |

---

### 3.3 `addon_catalog`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `addon_key` | text | NO | — | PK |
| `display_name` | text | NO | — |
| `delta_entitlements` | jsonb | YES | — |
| `price_cents` | integer | YES | — |
| `is_active` | boolean | NO | `true` |

**RLS:** Habilitada

| Política | Operación | Condición |
|----------|-----------|-----------|
| `addon_catalog_read_all` | SELECT | authenticated |
| `addon_catalog_write_service` | ALL | service_role |

---

### 3.4 `account_addons`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `addon_key` | text | NO | — | FK → addon_catalog |
| `purchased_at` | timestamptz | YES | `now()` |

**Índices:** `idx_account_addons_account` (account_id)

---

### 3.5 `account_entitlements`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `account_id` | uuid | NO | — | PK, FK → nv_accounts CASCADE |
| `entitlements` | jsonb | NO | — |
| `computed_at` | timestamptz | YES | `now()` |

---

### 3.6 `provisioning_jobs`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial | NO | — | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `job_type` | text | NO | — |
| `type` | text | YES | — | Synced with job_type via trigger |
| `payload` | jsonb | YES | — |
| `status` | nv_job_status | YES | `'queued'` |
| `attempts` | integer | YES | `0` |
| `max_attempts` | integer | YES | `5` |
| `run_after` | timestamptz | YES | — |
| `locked_at` | timestamptz | YES | — |
| `locked_by` | text | YES | — |
| `last_error` | text | YES | — |
| `dedupe_key` | text | YES | — |
| `started_at` | timestamptz | YES | — |
| `completed_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:**

| Nombre | Columna(s) | Condición |
|--------|-----------|-----------|
| `idx_jobs_status_run_after` | `status, run_after` | — |
| `provisioning_jobs_dedupe_key_uniq` | `dedupe_key` | UNIQUE, `WHERE dedupe_key IS NOT NULL` |

**Triggers:** `trg_sync_provisioning_jobs_fields` → `sync_provisioning_jobs_fields()`

---

### 3.7 `provisioning_job_steps`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial | NO | — | PK |
| `job_id` | uuid | NO | — | FK → provisioning_jobs CASCADE |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `step_name` | text | NO | — |
| `status` | text | YES | `'queued'` | CHECK (`queued` \| `running` \| `done` \| `failed` \| `skipped`) |
| `attempt` | integer | YES | `0` |
| `step_data` | jsonb | YES | — |
| `error` | text | YES | — |
| `started_at` | timestamptz | YES | — |
| `ended_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:** `(job_id, step_name)` UNIQUE, `provisioning_job_steps_account_idx`, `provisioning_job_steps_status_idx`

---

### 3.8 `mp_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | bigserial | NO | — | PK |
| `mp_event_id` | text | NO | — | UNIQUE |
| `topic` | text | YES | — |
| `payload` | jsonb | NO | — |
| `received_at` | timestamptz | YES | `now()` |
| `processed_at` | timestamptz | YES | — |

---

### 3.9 `backend_clusters`

> Redefinida por migración concierge. La versión final es:

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `cluster_id` | text | NO | — | PK (originalmente uuid `id`, luego migrado a text) |
| `display_name` | text | NO | — |
| `db_url` | text | YES | — | (plain text fallback) |
| `db_url_encrypted` | text | YES | — | (encrypted via `set_backend_cluster_db_url()`) |
| `service_role_key` | text | YES | — |
| `storage_project_ref` | text | YES | — |
| `api_url` | text | YES | — |
| `active` | boolean | YES | `true` |
| `status` | text | YES | — |
| `last_error` | text | YES | — |
| `last_cloned_from` | text | YES | — |
| `last_cloned_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |

---

### 3.10 `coupons`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `code` | text | NO | — | UNIQUE |
| `description` | text | YES | — |
| `discount_type` | text | NO | — | CHECK (`percentage` \| `fixed_amount`) |
| `discount_value` | numeric | NO | — | CHECK (> 0) |
| `currency` | text | YES | `'ARS'` |
| `max_uses` | integer | YES | — |
| `uses_count` | integer | YES | `0` |
| `active` | boolean | YES | `true` |
| `expires_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |

**Índices:** `idx_coupons_code`, `idx_coupons_active`

---

### 3.11 `coupon_redemptions`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `coupon_id` | uuid | NO | — | FK → coupons |
| `account_id` | uuid | NO | — | FK → nv_accounts |
| `order_id` | text | YES | — |
| `redeemed_at` | timestamptz | YES | `now()` |
| `discount_amount` | numeric | NO | — |

**Índices:** `idx_coupon_redemptions_account`, `idx_coupon_redemptions_coupon`

---

### 3.12 `palette_catalog`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `palette_key` | text | NO | — | PK |
| `label` | text | NO | — |
| `description` | text | YES | — |
| `min_plan_key` | text | YES | `'starter'` | CHECK (`starter` \| `growth` \| `pro` \| `enterprise`) |
| `preview` | jsonb | YES | — | CHECK is object |
| `is_active` | boolean | YES | `true` |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:** `idx_palette_catalog_active_true` (partial WHERE is_active), `idx_palette_catalog_min_plan_key`  
**Trigger:** `trg_palette_catalog_set_updated_at` → `set_updated_at()`

---

### 3.13 `custom_palettes`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `client_id` | uuid | NO | — | FK → clients CASCADE |
| `palette_name` | text | YES | — |
| `based_on_key` | text | YES | — | FK → palette_catalog |
| `theme_vars` | jsonb | NO | — | CHECK is object |
| `is_active` | boolean | YES | `true` |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**UNIQUE:** `(client_id, palette_name)`  
**Trigger:** `trg_custom_palettes_set_updated_at` → `set_updated_at()`

---

### 3.14 `client_themes`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `client_id` | uuid | NO | — | PK, FK → clients CASCADE |
| `template_key` | text | YES | `'normal'` | FK → nv_templates(key) ON UPDATE CASCADE |
| `template_version` | integer | YES | — |
| `overrides` | jsonb | YES | `'{}'` | CHECK is object |
| `updated_at` | timestamptz | YES | `now()` |

**CHECK:** `client_themes_template_key_format` → regex `'^[a-z0-9-]+$'`  
**Trigger:** `trg_client_themes_updated_at` → `update_client_themes_updated_at()`

**RLS:**

| Política | Operación |
|----------|-----------|
| Clients can read their own theme | SELECT |
| Clients can update their own theme | UPDATE |
| Clients can insert their own theme | INSERT |
| Admins can manage all client themes | ALL (service_role) |

---

### 3.15 `nv_templates`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `key` | text | NO | — | PK |
| `label` | text | NO | — |
| `description` | text | YES | — |
| `thumbnail_url` | text | YES | — |
| `min_plan` | text | YES | `'starter'` | CHECK (`starter` \| `growth` \| `pro` \| `enterprise`) |
| `is_active` | boolean | YES | `true` |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Trigger:** `trg_nv_templates_updated_at` → `set_updated_at()`

**RLS:**

| Política | Operación |
|----------|-----------|
| Public can read active templates | SELECT (authenticated, `WHERE is_active`) |
| Admins can manage templates | ALL (service_role) |

---

### 3.16 `plans`

> Reemplaza a plan_definitions (ADMIN_043).

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `plan_key` | text | NO | — | PK |
| `display_name` | text | YES | — |
| `description` | text | YES | — |
| `features` | jsonb | YES | — |
| `recommended` | boolean | YES | — |
| `is_active` | boolean | YES | — |
| `sort_order` | integer | YES | — |
| `monthly_fee` | numeric | NO | — |
| `setup_fee` | numeric | YES | — |
| `currency` | text | YES | `'ARS'` |
| `price_display` | text | YES | — |
| `entitlements` | jsonb | NO | — |
| `included_requests` | integer | YES | — |
| `included_bandwidth_gb` | numeric | YES | — |
| `included_storage_gb` | numeric | YES | — |
| `included_orders` | integer | YES | — |
| `overage_per_1k_requests` | numeric | YES | — |
| `overage_per_gb_egress` | numeric | YES | — |
| `overage_per_order` | numeric | YES | — |
| `rate_version` | integer | YES | — |
| `effective_from` | timestamptz | YES | — |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:** `idx_plans_is_active`, `idx_plans_sort_order`, `idx_plans_recommended`

**RLS:**

| Política | Operación |
|----------|-----------|
| `plans_read_all` | SELECT (authenticated) |
| `plans_write_service` | ALL (service_role) |
| `Super Admin Access` | ALL |

---

### 3.17 `nv_billing_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `event_type` | billing_event_type | NO | — |
| `status` | billing_event_status | YES | `'pending'` |
| `amount` | numeric(10,2) | NO | — |
| `currency` | varchar(3) | YES | `'ARS'` |
| `external_reference` | varchar(255) | YES | — | UNIQUE |
| `provider_payment_id` | varchar(255) | YES | — |
| `provider` | text | YES | — | (ADMIN_050) |
| `provider_preference_id` | text | YES | — |
| `paid_at` | timestamptz | YES | — |
| `manual_reference` | text | YES | — |
| `admin_note` | text | YES | — |
| `metadata` | jsonb | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:**

| Nombre | Columna(s) |
|--------|-----------|
| `idx_billing_events_account` | `account_id` |
| `idx_billing_events_ref` | `external_reference` |
| `idx_billing_events_status` | `status` |
| `idx_nv_billing_events_type_status_created` | `event_type, status, created_at` |
| `uq_nv_billing_events_provider_payment_id` | UNIQUE `provider_payment_id` WHERE NOT NULL |

**RLS:**

| Política | Operación |
|----------|-----------|
| Super Admin can view all billing events | SELECT |
| Account Owners can view their own billing events | SELECT |
| `Super Admin Access` | ALL |

---

### 3.18 `slug_reservations`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `slug` | text | NO | — | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `reserved_at` | timestamptz | YES | `now()` |
| `expires_at` | timestamptz | YES | `now() + interval '30 minutes'` |

**Índices:** `idx_slug_reservations_expires`

---

### 3.19 `webhook_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `source` | text | NO | — |
| `event_type` | text | NO | — |
| `payment_id` | text | NO | — |
| `external_reference` | text | YES | — |
| `payload` | jsonb | NO | — |
| `status` | text | YES | `'received'` | CHECK (`received` \| `processing` \| `processed` \| `failed`) |
| `processed_at` | timestamptz | YES | — |
| `error` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:**

| Nombre | Tipo | Columna(s) |
|--------|------|-----------|
| `idx_webhook_events_dedup` | UNIQUE | `source, payment_id, event_type` |
| `idx_webhook_events_status` | btree | `status` |
| `idx_webhook_events_external_ref` | btree | `external_reference` |

**Trigger:** `webhook_events_updated_at` → `update_webhook_events_timestamp()`

---

### 3.20 `auth_handoff`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `token_hash` | text | NO | — | UNIQUE |
| `client_id` | uuid | NO | — |
| `user_id` | uuid | YES | — |
| `payload_ciphertext` | text | YES | — |
| `payload_iv` | text | YES | — |
| `payload_tag` | text | YES | — |
| `expires_at` | timestamptz | NO | — |
| `consumed_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |

**Índices:** `idx_auth_handoff_client_id`, `idx_auth_handoff_expires_at`, `idx_auth_handoff_consumed_at`

---

### 3.21 `super_admins`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `email` | text | NO | — | UNIQUE |
| `created_at` | timestamptz | YES | `now()` |

**RLS:** DESHABILITADA (fix_super_admin_rls desactiva explícitamente)

---

### 3.22 `managed_domains`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `domain` | citext | NO | — | UNIQUE (global) |
| `expires_at` | timestamptz | YES | — |
| `auto_renew` | boolean | YES | `true` |
| `renewal_state` | managed_domain_renewal_state | YES | `'none'` |
| `renewal_window_days` | integer | YES | — |
| `renewal_price_ars` | numeric | YES | — |
| `management_fee_ars` | numeric | YES | — |
| `management_fee_usd_override` | numeric | YES | — |
| `provider` | text | YES | — |
| `renewal_expected_price` | numeric | YES | — |
| `renewal_checkout_id` | text | YES | — |
| `renewal_payment_id` | text | YES | — |
| `renewal_requested_at` | timestamptz | YES | — |
| `last_renewed_at` | timestamptz | YES | — |
| `renewal_years` | integer | YES | — |
| `last_notified_at` | timestamptz | YES | — |
| `notification_stage` | text | YES | — |
| `active_renewal_id` | uuid | YES | — | FK → managed_domain_renewals |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**UNIQUE adicional:** `(account_id, domain)`  
**Índices:** `idx_managed_domains_account_id`, `idx_managed_domains_renewal_state`, `idx_managed_domains_expires_at`  
**RLS:** Habilitada, sin políticas abiertas (solo service_role)

---

### 3.23 `managed_domain_renewals`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `managed_domain_id` | uuid | NO | — | FK → managed_domains CASCADE |
| `renewal_cost_usd` | numeric | YES | — |
| `management_fee_usd` | numeric | YES | — |
| `total_usd` | numeric | YES | — |
| `fx_rate_snapshot` | numeric | YES | — |
| `total_ars_charged` | numeric | YES | — |
| `quote_source` | text | YES | — |
| `quote_valid_until` | timestamptz | YES | — |
| `mp_preference_id` | text | YES | — |
| `payment_id` | text | YES | — |
| `payment_status` | text | YES | — |
| `status` | text | YES | — | CHECK (`quoted` \| `invoice_created` \| `paid` \| `renewed` \| `failed` \| `expired` \| `cancelled`) |
| `manual_required_reason` | text | YES | — | CHECK (`infra` \| `premium` \| `price_missing` \| `high_cost` \| `other`) |
| `manual_required_detail` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:** `idx_mdr_domain_id`, `idx_mdr_status`, `idx_mdr_payment_id`  
**RLS:** `"Service Role Full Access Renewals"` (service_role only)

---

### 3.24 `subscriptions`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `provider_id` | text | NO | — | UNIQUE |
| `status` | subscription_status | YES | `'active'` |
| `plan_key` | text | NO | — | CHECK (`starter` \| `growth` \| `pro` \| `enterprise`) |
| `current_period_start` | timestamptz | YES | — |
| `current_period_end` | timestamptz | YES | — |
| `grace_until` | timestamptz | YES | — |
| `cancel_at_period_end` | boolean | YES | `false` |
| `metadata` | jsonb | YES | — |
| `billing_cycle` | text | YES | — | CHECK (`monthly` \| `annual`) |
| `auto_renew` | boolean | YES | `true` |
| `cancel_requested_at` | timestamptz | YES | — |
| `cancelled_at` | timestamptz | YES | — |
| `grace_ends_at` | timestamptz | YES | — |
| `past_due_since` | timestamptz | YES | — |
| `suspended_at` | timestamptz | YES | — |
| `deactivate_at` | timestamptz | YES | — |
| `deactivated_at` | timestamptz | YES | — |
| `purge_at` | timestamptz | YES | — |
| `purged_at` | timestamptz | YES | — |
| `external_reference` | text | YES | — |
| `initial_price_ars` | numeric | YES | — |
| `original_price_ars` | numeric | YES | — |
| `plan_price_usd` | numeric | YES | — |
| `last_charged_ars` | numeric | YES | — |
| `next_estimated_ars` | numeric | YES | — |
| `next_payment_date` | timestamptz | YES | — |
| `last_payment_date` | timestamptz | YES | — |
| `consecutive_failures` | integer | YES | `0` |
| `last_mp_synced_at` | timestamptz | YES | — |
| `last_reconcile_source` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Constraints:**

| Nombre | Tipo | Expresión |
|--------|------|-----------|
| `subscriptions_pkey` | PK | `id` |
| `subscriptions_account_id_key` | UNIQUE | `account_id` |
| `subscriptions_provider_id_key` | UNIQUE | `provider_id` |
| `valid_period` | CHECK | `current_period_end IS NULL OR current_period_end > current_period_start` |
| `valid_grace` | CHECK | `grace_until IS NULL OR grace_until > current_period_end` |
| `subscriptions_plan_key_check` | CHECK | `plan_key IN ('starter','growth','pro','enterprise')` |
| `ux_subscriptions_one_active_per_account` | UNIQUE partial | `account_id WHERE status = 'active'` |

**Índices:** `idx_subs_last_mp_synced` (partial WHERE status IN active/past_due/grace)

**Trigger:** `trg_subscriptions_updated` → `update_subscriptions_updated_at()`

**RLS:** Habilitada

| Política | Operación |
|----------|-----------|
| Super admin select/insert/update/delete | USING `is_super_admin()` |
| Service role bypass | ALL |
| `Super Admin Access` | ALL (JWT-based) |

---

### 3.25 `subscription_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `event_id` | text | NO | — | UNIQUE |
| `subscription_id` | uuid | NO | — | FK → subscriptions CASCADE |
| `event_type` | text | NO | — |
| `payload` | jsonb | NO | — |
| `processed_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |

**RLS:** super_admin SELECT, authenticated INSERT, service_role ALL

---

### 3.26 `subscription_notification_outbox`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `subscription_id` | uuid | YES | — | FK → subscriptions |
| `notif_type` | text | NO | — |
| `channel` | text | NO | — |
| `scheduled_for` | timestamptz | NO | — |
| `payload` | jsonb | YES | — |
| `status` | text | YES | `'pending'` |
| `sent_at` | timestamptz | YES | — |
| `last_error` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |

**UNIQUE:** `(account_id, notif_type, channel, scheduled_for)`  
**RLS:** service_role + super_admin

---

### 3.27 `tenant_payment_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `event_key` | text | NO | — |
| `topic` | text | YES | — |
| `resource_id` | text | YES | — |
| `external_reference` | text | YES | — |
| `tenant_id` | uuid | YES | — |
| `cluster_id` | uuid | YES | — |
| `signature_valid` | boolean | YES | — |
| `payload` | jsonb | YES | — |
| `received_at` | timestamptz | YES | `now()` |
| `processed_at` | timestamptz | YES | — |
| `process_result` | text | YES | — |
| `last_error` | text | YES | — |

**Índices:** `ux_tenant_payment_events_event_key` (UNIQUE)  
**RLS:** service_role + super_admin

---

### 3.28 `system_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `created_at` | timestamptz | YES | `now()` |
| `level` | text | NO | — | CHECK (`info` \| `warn` \| `error`) |
| `event_type` | text | NO | — |
| `account_id` | uuid | YES | — |
| `client_id` | uuid | YES | — |
| `user_id` | uuid | YES | — |
| `request_id` | text | YES | — |
| `ref_id` | text | YES | — |
| `message` | text | NO | — |
| `details` | jsonb | YES | — |

**Índices:** por `created_at DESC`, `level` (partial error), `account_id`, `event_type`, `request_id`

**RLS:** super_admin + client policy

---

### 3.29 `email_jobs`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `client_id` | text | NO | — |
| `order_id` | uuid | YES | — |
| `type` | text | NO | — |
| `payload` | jsonb | YES | — |
| `status` | text | YES | `'pending'` |
| `attempts` | integer | YES | `0` |
| `max_attempts` | integer | YES | `3` |
| `run_at` | timestamptz | YES | — |
| `sent_at` | timestamptz | YES | — |
| `error` | text | YES | — |
| `dedupe_key` | text | YES | — |
| `provider_message_id` | text | YES | — |
| `provider_response` | jsonb | YES | — |
| `to_email` | text | YES | — |
| `template` | text | YES | — |
| `trigger_event` | text | YES | — |
| `request_id` | text | YES | — |
| `next_retry_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:**

| Nombre | Tipo |
|--------|------|
| `idx_email_jobs_status_runat` | `status, run_at` |
| `idx_email_jobs_type` | `type` |
| `idx_email_jobs_client_id` | `client_id` |
| `idx_email_jobs_dedupe_key_unique` | UNIQUE `dedupe_key` WHERE NOT NULL |
| `idx_email_jobs_trigger_event` | `trigger_event` |
| `idx_email_jobs_to_email` | `to_email` |
| `idx_email_jobs_provider_message_id` | `provider_message_id` |
| `idx_email_jobs_next_retry` | `next_retry_at` |

**Trigger:** `trg_email_jobs_updated` → `update_email_jobs_timestamp()`  
**RLS:** `email_jobs_service_role` (service_role only)

---

### 3.30 `mp_connections`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE, UNIQUE |
| `client_id_backend` | uuid | YES | — |
| `access_token` | text | YES | — |
| `public_key` | text | YES | — |
| `refresh_token` | text | YES | — |
| `mp_user_id` | text | YES | — |
| `live_mode` | boolean | YES | — |
| `expires_at` | timestamptz | YES | — |
| `status` | text | YES | — | CHECK (`connected` \| `revoked` \| `error` \| `expired`) |
| `last_error` | text | YES | — |
| `last_refresh_at` | timestamptz | YES | — |
| `connected_at` | timestamptz | YES | — |
| `updated_at` | timestamptz | YES | `now()` |

**Trigger:** `mp_connections_updated_at` → `update_mp_connections_updated_at()`  
**RLS:** `service_role_full_access`

---

### 3.31 `pro_projects`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `status` | text | YES | `'kickoff_pending'` |
| `brief_data` | jsonb | YES | — |
| `notes` | text | YES | — |
| `assigned_to` | uuid | YES | — |
| `estimated_go_live` | date | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

---

### 3.32 `client_completion_checklist`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE, UNIQUE |
| `logo_uploaded` | boolean | YES | `false` |
| `banner_uploaded` | boolean | YES | `false` |
| `products_count` | integer | YES | `0` |
| `categories_count` | integer | YES | `0` |
| `faqs_added` | boolean | YES | `false` |
| `faqs_count` | integer | YES | `0` | (add_faqs_count_column) |
| `contact_info_added` | boolean | YES | `false` |
| `social_links_added` | boolean | YES | `false` |
| `completion_percentage` | integer | YES | `0` |
| `last_updated_at` | timestamptz | YES | `now()` |
| `completed_at` | timestamptz | YES | — |
| `notified_admin_at` | timestamptz | YES | — |
| `review_status` | text | YES | — | (20260127) |
| `review_items` | text[] | YES | — |
| `review_message` | text | YES | — |
| `review_requested_at` | timestamptz | YES | — |
| `review_updated_at` | timestamptz | YES | — |
| `review_request_count` | integer | YES | `0` |
| `reviewer_id` | uuid | YES | — |
| `reviewer_label` | text | YES | — |
| `resubmitted_at` | timestamptz | YES | — |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Índices:** `idx_completion_account`, `idx_completion_percentage`  
**Trigger:** `trigger_update_completion_percentage` → `update_completion_percentage()`

**RLS:**

| Política | Operación |
|----------|-----------|
| Clients can view own checklist | SELECT (owner) |
| Clients can update own checklist | UPDATE (owner) |
| Super admins can view all checklists | ALL |
| Service role has full access | ALL |

---

### 3.33 `client_completion_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `type` | text | NO | — |
| `payload` | jsonb | YES | — |
| `actor_id` | uuid | YES | — |
| `actor_label` | text | YES | — |
| `created_at` | timestamptz | YES | `now()` |

**RLS:** Clients own, Super admins all, Service role full

---

### 3.34 `nv_account_settings`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `nv_account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `key` | text | NO | — |
| `value` | jsonb | NO | — |
| `updated_at` | timestamptz | YES | `now()` |
| `updated_by` | uuid | YES | — |

**PK:** `(nv_account_id, key)`

**RLS:**

| Política | Operación |
|----------|-----------|
| `nv_account_settings_super_admin_all` | ALL |
| `nv_account_settings_service_all` | ALL (service_role) |

---

### 3.35 `dev_portal_whitelist`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `email` | citext | NO | — | PK |
| `enabled` | boolean | YES | `true` |
| `note` | text | YES | — |
| `created_by` | uuid | YES | — | FK → auth.users |
| `created_at` | timestamptz | YES | `now()` |
| `updated_at` | timestamptz | YES | `now()` |

**Trigger:** `trigger_update_dev_portal_whitelist_updated_at`

**RLS:**

| Política | Operación |
|----------|-----------|
| `dev_portal_whitelist_super_admin_all` | ALL |
| `dev_portal_whitelist_read_own` | SELECT (email = auth.email()) |
| `dev_portal_whitelist_service_bypass` | ALL (service_role) |

---

### 3.36 `lifecycle_events`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `id` | uuid | NO | `gen_random_uuid()` | PK |
| `account_id` | uuid | NO | — | FK → nv_accounts CASCADE |
| `event_type` | text | NO | — |
| `old_value` | jsonb | YES | — |
| `new_value` | jsonb | YES | — |
| `source` | text | NO | — |
| `correlation_id` | text | YES | — |
| `metadata` | jsonb | YES | — |
| `created_at` | timestamptz | NO | `now()` |
| `created_by` | uuid | YES | — |

**Índices:**

| Nombre | Columna(s) | Condición |
|--------|-----------|-----------|
| `idx_lifecycle_events_account` | `account_id, created_at DESC` | — |
| `idx_lifecycle_events_type` | `event_type, created_at DESC` | — |
| `idx_lifecycle_events_correlation` | `correlation_id` | `WHERE NOT NULL` |

**RLS:** `lifecycle_events_service_bypass` (service_role only)

---

### 3.37 `subscription_locks`

| Columna | Tipo | Nullable | Default |
|---------|------|----------|---------|
| `account_id` | uuid | NO | — | PK |
| `locked_at` | timestamptz | NO | `now()` |
| `locked_by` | text | YES | — |

**RLS:** `"server_bypass"` (service_role only)

---

### 3.38 `oauth_state_nonces`

> Tabla referenciada/alterada en migraciones pero no creada explícitamente en archivos leídos. `client_id` alterado a tipo text.

---

### 3.39 Tablas gestionadas con RLS pero NO creadas en estas migraciones

Estas tablas tienen RLS habilitada y/o políticas asignadas en las migraciones admin, pero su DDL está en otra parte (posiblemente pre-existentes o de otro esquema):

| Tabla | Acciones en migraciones |
|-------|------------------------|
| `clients` | RLS habilitada, DROP'd en ADMIN_037 (tabla eliminada de admin) |
| `payments` (admin context) | RLS, Super Admin Access |
| `invoices` | RLS habilitada (ADMIN_054), Super Admin Access |
| `users` (admin context) | RLS habilitada, Super Admin Access |
| `client_usage_month` | RLS habilitada, Super Admin Access |
| `sync_cursors` | RLS habilitada, Super Admin Access |
| `client_tombstones` | GRANT SELECT |
| `leads` | RLS habilitada |
| `app_settings` | RLS habilitada |
| `meetings` | RLS habilitada |
| `outreach_leads` | RLS habilitada |
| `nv_playbook` | RLS habilitada |

---

### 3.40 Tablas ELIMINADAS (staging — DROPeadas en 20260205)

Estas tablas fueron creadas en `create_completion_staging_tables.sql` y luego eliminadas permanentemente:

- `completion_products`
- `completion_categories`
- `completion_faqs`
- `completion_contact_info`
- `completion_social_links`

---

## 4. Funciones / RPCs

### Trigger Functions

| Función | Propósito | Tabla(s) |
|---------|-----------|----------|
| `set_updated_at()` | Setea `NEW.updated_at = now()` | palette_catalog, custom_palettes, nv_templates |
| `update_client_themes_updated_at()` | Setea updated_at | client_themes |
| `update_state_updated_at()` | Setea `state_updated_at` cuando `state` cambia | nv_onboarding |
| `update_webhook_events_timestamp()` | Setea updated_at | webhook_events |
| `update_mp_connections_updated_at()` | Setea updated_at | mp_connections |
| `update_email_jobs_timestamp()` | Setea updated_at | email_jobs |
| `update_subscriptions_updated_at()` | Setea updated_at | subscriptions |
| `update_dev_portal_whitelist_updated_at()` | Setea updated_at | dev_portal_whitelist |
| `sync_provisioning_jobs_fields()` | Sincroniza `job_type` ↔ `type`, genera `dedupe_key` | provisioning_jobs |
| `update_completion_percentage()` | Recalcula % completitud | client_completion_checklist |

### Business Logic Functions

| Función | Firma | Retorno | Propósito |
|---------|-------|---------|-----------|
| `is_super_admin()` | `()` | boolean | Verifica si `auth.email()` está en `super_admins` |
| `has_valid_mp_connection(uuid)` | `(p_account_id)` | boolean | Verifica conexión MP activa no expirada |
| `mark_mp_connection_for_refresh(uuid)` | `(p_account_id)` | void | Marca conexiones expiradas para refresh |
| `calculate_completion_percentage(uuid)` | `(checklist_id)` | integer | Calcula % de completitud (6 items, excluye banner) |

### Provisioning Functions

| Función | Firma | Retorno | Propósito |
|---------|-------|---------|-----------|
| `enqueue_provisioning_job(uuid, text, jsonb, timestamptz, int)` | (account_id, job_type, payload, run_after, max_attempts) | uuid | Enqueue idempotente con dedupe_key |
| `claim_provisioning_jobs(int)` | (batch_size) | SETOF provisioning_jobs | Claim con SKIP LOCKED |
| `is_provisioning_step_done(uuid, text)` | (job_id, step_name) | boolean | Consulta estado de step |
| `get_provisioning_step_data(uuid, text)` | (job_id, step_name) | jsonb | Lee step_data de un step |

### Crypto Functions

| Función | Firma | Retorno | Propósito |
|---------|-------|---------|-----------|
| `set_backend_cluster_db_url(text, text, text)` | (cluster_id, raw_url, secret_key) | void | Encripta y guarda db_url en backend_clusters |
| `get_backend_cluster_db_url(text, text)` | (cluster_id, secret_key) | text | Desencripta y devuelve db_url |

### Dashboard / Reporting RPCs

| Función | Retorno | Propósito |
|---------|---------|-----------|
| `dashboard_metrics(timestamptz, timestamptz, text, text, text, text)` | jsonb | Métricas consolidadas del dashboard principal |
| `dashboard_tops(...)` | table | Top accounts por revenue/orders |
| `dashboard_client_detail(...)` | table | Detalle de métricas por cliente |
| `finance_summary(int, int, timestamptz, timestamptz, text, text, text, text)` | jsonb | Resumen financiero (MRR, churn, forecast) |
| `get_billing_dashboard(int, int, text, uuid, text)` | table | Datos de billing unificados (subscriptions + billing_events) |

### Subscription Lock Functions

| Función | Firma | Retorno | Propósito |
|---------|-------|---------|-----------|
| `try_lock_subscription(uuid, int)` | (account_id, ttl_seconds=30) | boolean | Adquiere lock distribuido |
| `release_subscription_lock(uuid)` | (account_id) | void | Libera lock |
| `cleanup_stale_subscription_locks(int)` | (max_age_seconds=60) | integer | Limpia locks expirados |

### Invariant Check Functions

| Función | Propósito |
|---------|-----------|
| `check_invariant_approved_consistency()` | Verifica consistencia de cuentas aprobadas |
| `check_invariant_pending_subscription()` | Verifica subscripciones pendientes |
| `check_invariant_active_client_subscription()` | Verifica subscripciones activas tienen cliente |
| `check_invariant_data_sync()` | Verifica sincronización de datos |

---

## 5. Triggers

| Trigger | Tabla | Evento | Función |
|---------|-------|--------|---------|
| `trg_palette_catalog_set_updated_at` | palette_catalog | BEFORE UPDATE | `set_updated_at()` |
| `trg_custom_palettes_set_updated_at` | custom_palettes | BEFORE UPDATE | `set_updated_at()` |
| `trg_client_themes_updated_at` | client_themes | BEFORE UPDATE | `update_client_themes_updated_at()` |
| `trigger_update_state_updated_at` | nv_onboarding | BEFORE UPDATE | `update_state_updated_at()` |
| `webhook_events_updated_at` | webhook_events | BEFORE UPDATE | `update_webhook_events_timestamp()` |
| `mp_connections_updated_at` | mp_connections | BEFORE UPDATE | `update_mp_connections_updated_at()` |
| `trg_email_jobs_updated` | email_jobs | BEFORE UPDATE | `update_email_jobs_timestamp()` |
| `trg_subscriptions_updated` | subscriptions | BEFORE UPDATE | `update_subscriptions_updated_at()` |
| `trg_sync_provisioning_jobs_fields` | provisioning_jobs | BEFORE INSERT OR UPDATE | `sync_provisioning_jobs_fields()` |
| `trg_nv_templates_updated_at` | nv_templates | BEFORE UPDATE | `set_updated_at()` |
| `trigger_update_dev_portal_whitelist_updated_at` | dev_portal_whitelist | BEFORE UPDATE | `update_dev_portal_whitelist_updated_at()` |
| `trigger_update_completion_percentage` | client_completion_checklist | BEFORE UPDATE | `update_completion_percentage()` |

---

## 6. Storage Buckets

> No se encontraron `INSERT INTO storage.buckets` ni `CREATE BUCKET` en las migraciones admin.
> El storage se gestiona desde el dashboard de Supabase o migraciones de otro directorio.

---

## 7. Cron Jobs

> No se encontraron definiciones `pg_cron` / `cron.schedule()` en las migraciones admin.
> Los crons se gestionan desde el backend NestJS o el dashboard de Supabase.

---

## 8. GRANT / Permisos Explícitos

| Tabla | Rol | Permisos |
|-------|-----|----------|
| `nv_accounts` | authenticated | SELECT, INSERT, UPDATE |
| `nv_onboarding` | authenticated | SELECT, INSERT, UPDATE |
| `client_usage_month` | authenticated | SELECT, INSERT, UPDATE, DELETE |
| `invoices` | authenticated | SELECT, INSERT, UPDATE, DELETE |
| `payments` | authenticated | SELECT, INSERT, UPDATE, DELETE |
| `users` | authenticated | SELECT, INSERT, UPDATE, DELETE |
| `sync_cursors` | authenticated | SELECT, INSERT, UPDATE, DELETE |
| `client_tombstones` | authenticated | SELECT |
| `client_usage_month` | service_role | ALL |
| `invoices` | service_role | ALL |
| `payments` | service_role | ALL |
| `users` | service_role | ALL |
| `sync_cursors` | service_role | ALL |
| `completion_*` (staging, DROPeadas) | authenticated + service_role | ALL |

---

## 9. Seed Data Notable

### Plans (ADMIN_054b / ADMIN_055)
Se insertan/actualizan planes: `starter`, `growth`, `pro`, `enterprise` con precios en ARS, USD, entitlements, features, etc.

### Templates (ADMIN_040)
Se insertan templates base: `normal` (al menos).

### Super Admins
Se insertan emails admin en `super_admins`: `novavision.contact@gmail.com`, `elias@novavision.com.ar`.

---

## 10. Resumen de Tablas Activas (Final)

| # | Tabla | PK | RLS |
|---|-------|-----|-----|
| 1 | `nv_accounts` | `id` (uuid) | ✅ |
| 2 | `nv_onboarding` | `account_id` (uuid) | ✅ |
| 3 | `addon_catalog` | `addon_key` (text) | ✅ |
| 4 | `account_addons` | `id` (uuid) | ✅ |
| 5 | `account_entitlements` | `account_id` (uuid) | ✅ |
| 6 | `provisioning_jobs` | `id` (bigserial) | ✅ |
| 7 | `provisioning_job_steps` | `id` (bigserial) | ✅ |
| 8 | `mp_events` | `id` (bigserial) | ✅ |
| 9 | `backend_clusters` | `cluster_id` (text) | ✅ |
| 10 | `coupons` | `id` (uuid) | ✅ |
| 11 | `coupon_redemptions` | `id` (uuid) | ✅ |
| 12 | `palette_catalog` | `palette_key` (text) | ✅ |
| 13 | `custom_palettes` | `id` (uuid) | ✅ |
| 14 | `client_themes` | `client_id` (uuid) | ✅ |
| 15 | `nv_templates` | `key` (text) | ✅ |
| 16 | `plans` | `plan_key` (text) | ✅ |
| 17 | `nv_billing_events` | `id` (uuid) | ✅ |
| 18 | `slug_reservations` | `slug` (text) | ✅ |
| 19 | `webhook_events` | `id` (uuid) | ✅ |
| 20 | `auth_handoff` | `id` (uuid) | ✅ |
| 21 | `super_admins` | `id` (uuid) | ❌ (disabled) |
| 22 | `managed_domains` | `id` (uuid) | ✅ |
| 23 | `managed_domain_renewals` | `id` (uuid) | ✅ |
| 24 | `subscriptions` | `id` (uuid) | ✅ |
| 25 | `subscription_events` | `id` (uuid) | ✅ |
| 26 | `subscription_notification_outbox` | `id` (uuid) | ✅ |
| 27 | `tenant_payment_events` | `id` (uuid) | ✅ |
| 28 | `system_events` | `id` (uuid) | ✅ |
| 29 | `email_jobs` | `id` (uuid) | ✅ |
| 30 | `mp_connections` | `id` (uuid) | ✅ |
| 31 | `pro_projects` | `id` (uuid) | ✅ |
| 32 | `client_completion_checklist` | `id` (uuid) | ✅ |
| 33 | `client_completion_events` | `id` (uuid) | ✅ |
| 34 | `nv_account_settings` | `(nv_account_id, key)` | ✅ |
| 35 | `dev_portal_whitelist` | `email` (citext) | ✅ |
| 36 | `lifecycle_events` | `id` (uuid) | ✅ |
| 37 | `subscription_locks` | `account_id` (uuid) | ✅ |

**Total tablas activas: 37**  
**Tablas eliminadas (staging): 5**  
**Enums: 7**  
**Funciones/RPCs: ~30**  
**Triggers: 12**  

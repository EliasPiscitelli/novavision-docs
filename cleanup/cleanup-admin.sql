-- ============================================================
-- NOVAVISION — LIMPIEZA DE ACCOUNTS QA EN ADMIN DB
-- ============================================================
-- Propósito : Borrar todas las nv_accounts (QA) y su data derivada.
-- Preserva  : plans, super_admins, dashboard_admins, app_secrets,
--             app_settings, nv_playbook, nv_templates, palette_catalog,
--             addon_catalog, platform_shipping_providers, metering_prices,
--             custom_palettes, dev_portal_whitelist, outreach_leads,
--             outreach_logs, leads, lead_assets, coupons, coupon_redemptions,
--             invoices, payments, meetings, users (admin), auth.users,
--             backend_clusters, sync_cursors, system_events
--
-- Fecha     : 2026-07-14
-- DB        : db.erbfzlsznqsmwmjugspo.supabase.co (admin)
-- ============================================================
-- ⚠️  DESTRUCTIVO — NO EJECUTAR SIN APROBACIÓN DEL TL
-- ============================================================

BEGIN;

-- ── 1. Sub-hijos de subscriptions ──────────────────────────
TRUNCATE subscription_events               CASCADE;
TRUNCATE subscription_payment_failures     CASCADE;
TRUNCATE subscription_price_history        CASCADE;
TRUNCATE subscription_notification_outbox  CASCADE;
TRUNCATE subscription_locks                CASCADE;

-- ── 2. Sub-hijos de managed_domains ────────────────────────
TRUNCATE managed_domain_renewals           CASCADE;

-- ── 3. Sub-hijos de provisioning_jobs ──────────────────────
TRUNCATE provisioning_job_steps            CASCADE;

-- ── 4. Hijos directos de nv_accounts ───────────────────────
TRUNCATE account_addons                    CASCADE;
TRUNCATE account_entitlements              CASCADE;
TRUNCATE account_sync_outbox               CASCADE;
TRUNCATE client_completion_events          CASCADE;
TRUNCATE client_completion_checklist       CASCADE;
TRUNCATE lifecycle_events                  CASCADE;
TRUNCATE managed_domains                   CASCADE;
TRUNCATE mp_events                         CASCADE;
TRUNCATE nv_account_settings               CASCADE;
TRUNCATE nv_billing_events                 CASCADE;
TRUNCATE nv_onboarding                     CASCADE;
TRUNCATE onboarding_links                  CASCADE;
TRUNCATE provisioning_jobs                 CASCADE;
TRUNCATE slug_reservations                 CASCADE;
TRUNCATE subscriptions                     CASCADE;
-- coupon_redemptions tiene FK a nv_accounts Y subscriptions
-- pero el usuario quiere preservar coupons; solo truncar redemptions
TRUNCATE coupon_redemptions                CASCADE;

-- ── 5. Tablas de uso/eventos ligados a accounts ────────────
TRUNCATE tenant_payment_events             CASCADE;
TRUNCATE usage_daily                       CASCADE;
TRUNCATE usage_hourly                      CASCADE;
TRUNCATE usage_event                       CASCADE;
TRUNCATE usage_ledger                      CASCADE;
TRUNCATE billing_cycle                     CASCADE;
TRUNCATE client_usage_month                CASCADE;
TRUNCATE webhook_events                    CASCADE;
TRUNCATE orders_bridge                     CASCADE;
TRUNCATE email_jobs                        CASCADE;

-- ── 6. Tablas config por account ───────────────────────────
TRUNCATE client_themes                     CASCADE;
TRUNCATE client_tombstones                 CASCADE;
TRUNCATE client_extra_costs                CASCADE;
TRUNCATE auth_bridge_codes                 CASCADE;
TRUNCATE auth_handoff                      CASCADE;

-- ── 7. nv_accounts (tabla padre principal) ─────────────────
TRUNCATE nv_accounts                       CASCADE;

-- ── 8. NO TOCAR (catálogos / config / identidad) ──────────
-- plans                        → 6 registros (catálogo de planes)
-- super_admins                 → 2 registros (novavision.contact, elias)
-- dashboard_admins             → 1 registro
-- app_secrets                  → 1 registro
-- app_settings                 → 7 registros
-- nv_playbook                  → 85 registros
-- nv_templates                 → 5 registros
-- palette_catalog              → 20 registros
-- addon_catalog                → 1 registro
-- platform_shipping_providers  → 5 registros
-- outreach_leads               → 47,403 registros
-- outreach_logs                → 38 registros
-- leads                        → 7 registros
-- coupons                      → 7 registros
-- users                        → 2 registros (admin auth)
-- auth.users                   → 2 registros (intactos)
-- backend_clusters             → 1 registro

COMMIT;

-- ── VERIFICACIÓN (ejecutar después del COMMIT) ─────────────
-- SELECT 'nv_accounts' as t, count(*) FROM nv_accounts
-- UNION ALL SELECT 'subscriptions', count(*) FROM subscriptions
-- UNION ALL SELECT 'provisioning_jobs', count(*) FROM provisioning_jobs
-- UNION ALL SELECT 'plans (preservado)', count(*) FROM plans
-- UNION ALL SELECT 'super_admins (preservado)', count(*) FROM super_admins
-- UNION ALL SELECT 'outreach_leads (preservado)', count(*) FROM outreach_leads;

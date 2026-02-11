-- ============================================================================
-- CLEANUP ADMIN DB — Borrado en cascada de datos de prueba
-- DB: db.erbfzlsznqsmwmjugspo.supabase.co
-- Fecha: 2026-02-10
-- ============================================================================
-- Cuentas a MANTENER (nv_accounts):
--   67e3e091-78f0-4c0d-be80-ae2e64b859a0  (qa-tienda-ropa)
--   6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8  (qa-tienda-tech)
--
-- NOTA: f2d3f270-... (urbanprint/Pablo Piscitelli) NO existe en Admin DB,
--       solo en Backend DB.
-- ============================================================================

BEGIN;

-- ── Fase 1: Tablas con FK NO ACTION a nv_accounts (borrar ANTES) ─────────

DELETE FROM coupon_redemptions
WHERE account_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM mp_events
WHERE account_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

-- ── Fase 2: Tablas con subscription_id (hijas de subscriptions) ───────────
-- Borrar antes de que subscriptions se elimine por CASCADE de nv_accounts

DELETE FROM subscription_events
WHERE subscription_id IN (
  SELECT id FROM subscriptions
  WHERE account_id NOT IN (
    '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
    '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
  )
);

DELETE FROM subscription_payment_failures
WHERE subscription_id IN (
  SELECT id FROM subscriptions
  WHERE account_id NOT IN (
    '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
    '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
  )
);

DELETE FROM subscription_price_history
WHERE subscription_id IN (
  SELECT id FROM subscriptions
  WHERE account_id NOT IN (
    '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
    '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
  )
);

-- subscription_locks tiene account_id pero sin FK explícita
DELETE FROM subscription_locks
WHERE account_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

-- ── Fase 3: Tablas con client_id (patrón legacy, sin FK a nv_accounts) ────

DELETE FROM auth_handoff
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM billing_cycle
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM client_extra_costs
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM client_themes
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM client_tombstones
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM client_usage_month
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM custom_palettes
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM email_jobs
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM invoices
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM oauth_state_nonces
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM orders_bridge
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM payments
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM sync_cursors
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM usage_daily
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM usage_event
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM usage_hourly
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM usage_ledger
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

DELETE FROM users
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

-- system_events tiene account_id Y client_id
DELETE FROM system_events
WHERE account_id IS NOT NULL
  AND account_id NOT IN (
    '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
    '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
  );

DELETE FROM system_events
WHERE client_id IS NOT NULL
  AND client_id NOT IN (
    '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
    '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
  );

-- ── Fase 4: nv_accounts (CASCADE borra el resto) ─────────────────────────
-- Tablas que se eliminan automáticamente por CASCADE:
--   account_addons, account_entitlements, account_sync_outbox,
--   client_completion_checklist, client_completion_events, lifecycle_events,
--   managed_domains (→ managed_domain_renewals), nv_account_settings,
--   nv_billing_events, nv_onboarding, onboarding_links,
--   provisioning_jobs (→ provisioning_job_steps), slug_reservations,
--   subscription_notification_outbox, subscriptions

DELETE FROM nv_accounts
WHERE id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8'
);

-- ── Fase 5: Tablas genéricas sin referencia a account/client ──────────────
-- webhook_events, tenant_payment_events: sin client_id, limpiar si hay basura
TRUNCATE webhook_events;

-- Tablas catálogo (NO borrar): plans, addon_catalog, palette_catalog,
--   nv_templates, backend_clusters, coupons, mp_fee_table, app_settings,
--   dashboard_admins, super_admins, dev_portal_whitelist, nv_playbook

COMMIT;

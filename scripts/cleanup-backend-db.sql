-- ============================================================================
-- CLEANUP BACKEND DB (Multicliente) — Borrado en cascada de datos de prueba
-- DB: db.ulndkhijxtxvpmbbfrgp.supabase.co
-- Fecha: 2026-02-10
-- ============================================================================
-- Clientes a MANTENER:
--   67e3e091-78f0-4c0d-be80-ae2e64b859a0  (qa-tienda-ropa)
--   6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8  (qa-tienda-tech)
--   f2d3f270-583b-4644-9a61-2c0d6824f101  (urbanprint / Pablo Piscitelli)
-- ============================================================================

BEGIN;

-- ── Fase 1: Tablas hoja (sin FK hijos, sin restricción de orden) ──────────

DELETE FROM order_payment_breakdown
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM email_jobs
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM mp_idempotency
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM oauth_state_nonces
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM client_mp_fee_overrides
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM client_payment_settings
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

DELETE FROM favorites
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- ── Fase 2: Tablas con FK NO ACTION a clients (borrar ANTES de clients) ───

-- payments no tiene FK hijos, borrar directamente por client_id
DELETE FROM payments
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- orders → order_items (CASCADE), borrar orders elimina order_items automáticamente
DELETE FROM orders
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- products → product_categories (CASCADE), cart_items (CASCADE), favorites (CASCADE)
DELETE FROM products
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- categories → product_categories (CASCADE)
DELETE FROM categories
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- banners (NO ACTION a clients)
DELETE FROM banners
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- users → cart_items (CASCADE), ordenes ya borradas arriba
DELETE FROM users
WHERE client_id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- ── Fase 3: clients (CASCADE borra el resto) ─────────────────────────────
-- Tablas que se eliminan automáticamente por CASCADE:
--   client_assets, client_home_settings, client_secrets, client_usage,
--   contact_info, cors_origins, coupons, faqs, home_sections, home_settings,
--   logos, product_categories, services, social_links, tenant_payment_events

DELETE FROM clients
WHERE id NOT IN (
  '67e3e091-78f0-4c0d-be80-ae2e64b859a0',
  '6a6cdab2-4126-47dd-a8c2-90c85d3ba3f8',
  'f2d3f270-583b-4644-9a61-2c0d6824f101'
);

-- ── Fase 4: Tablas sin client_id (datos genéricos de test) ────────────────
-- webhook_events: no tiene client_id, son webhooks genéricos de MP
TRUNCATE webhook_events;

-- mp_fee_table: catálogo global, NO borrar

COMMIT;

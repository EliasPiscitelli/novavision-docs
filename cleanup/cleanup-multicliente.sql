-- ============================================================
-- NOVAVISION — LIMPIEZA COMPLETA MULTICLIENTE DB
-- ============================================================
-- Propósito : Borrar TODOS los datos de negocio y clientes.
--             Preparar la DB para un run limpio de E2E.
-- Preserva  : mp_fee_table (tarifas de Mercado Pago, config sistema)
-- Auth       : Borra TODOS los auth.users de Supabase
--
-- Fecha     : 2026-07-14
-- DB        : db.ulndkhijxtxvpmbbfrgp.supabase.co (multicliente)
-- ============================================================
-- ⚠️  DESTRUCTIVO — NO EJECUTAR SIN APROBACIÓN DEL TL
-- ============================================================

BEGIN;

-- ── 1. Tablas hoja (más dependientes — sin hijos) ──────────
TRUNCATE store_coupon_redemptions  CASCADE;
TRUNCATE store_coupon_targets      CASCADE;
TRUNCATE order_items               CASCADE;
TRUNCATE order_payment_breakdown   CASCADE;
TRUNCATE product_categories        CASCADE;
TRUNCATE cart_items                CASCADE;
TRUNCATE favorites                 CASCADE;
TRUNCATE shipments                 CASCADE;
TRUNCATE user_addresses            CASCADE;

-- ── 2. Tablas intermedias (dependen de parents, pueden tener hijos) ─
TRUNCATE email_jobs                CASCADE;
TRUNCATE mp_idempotency            CASCADE;
TRUNCATE webhook_events            CASCADE;
TRUNCATE tenant_payment_events     CASCADE;
TRUNCATE payments                  CASCADE;
TRUNCATE store_coupons             CASCADE;
TRUNCATE orders                    CASCADE;

-- ── 3. Productos y Categorías ──────────────────────────────
TRUNCATE products                  CASCADE;
TRUNCATE categories                CASCADE;

-- ── 4. Config de clientes (todas dependen de clients) ──────
TRUNCATE banners                   CASCADE;
TRUNCATE logos                     CASCADE;
TRUNCATE faqs                      CASCADE;
TRUNCATE contact_info              CASCADE;
TRUNCATE social_links              CASCADE;
TRUNCATE services                  CASCADE;
TRUNCATE cors_origins              CASCADE;
TRUNCATE home_sections             CASCADE;
TRUNCATE home_settings             CASCADE;
TRUNCATE client_home_settings      CASCADE;
TRUNCATE client_assets             CASCADE;
TRUNCATE client_secrets            CASCADE;
TRUNCATE client_shipping_settings  CASCADE;
TRUNCATE client_payment_settings   CASCADE;
TRUNCATE client_mp_fee_overrides   CASCADE;
TRUNCATE client_usage              CASCADE;
TRUNCATE seo_redirects             CASCADE;
TRUNCATE seo_settings              CASCADE;
TRUNCATE shipping_integrations     CASCADE;
TRUNCATE shipping_zones            CASCADE;
TRUNCATE oauth_state_nonces        CASCADE;

-- ── 5. Usuarios (public.users — depende de clients) ────────
TRUNCATE users                     CASCADE;

-- ── 6. Clientes (tabla raíz) ───────────────────────────────
TRUNCATE clients                   CASCADE;

-- ── 7. Auth users de Supabase (tabla interna) ──────────────
-- Borra todas las identidades y sesiones asociadas automáticamente
DELETE FROM auth.users;

COMMIT;

-- ── VERIFICACIÓN (ejecutar después del COMMIT) ─────────────
-- SELECT 'clients' as t, count(*) FROM clients
-- UNION ALL SELECT 'users', count(*) FROM users
-- UNION ALL SELECT 'products', count(*) FROM products
-- UNION ALL SELECT 'orders', count(*) FROM orders
-- UNION ALL SELECT 'auth.users', count(*) FROM auth.users
-- UNION ALL SELECT 'mp_fee_table (preservado)', count(*) FROM mp_fee_table;

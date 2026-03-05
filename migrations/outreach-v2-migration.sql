-- ============================================================================
-- MIGRACIÓN: Outreach System v2
-- Base de datos: Admin DB (Supabase)
-- Fecha: 2025-07-23
-- Autor: Copilot Agent
-- 
-- INSTRUCCIONES:
-- 1. Ejecutar PRIMERO en staging
-- 2. Verificar que no hay errores
-- 3. Ejecutar en producción solo con aprobación del TL
--
-- ROLLBACK: Ver sección al final del archivo
-- ============================================================================

BEGIN;

-- ============================================================================
-- PASO 1: Agregar nuevas columnas a outreach_leads (ANTES de migrar datos)
-- ============================================================================

-- Link a onboarding
ALTER TABLE outreach_leads
  ADD COLUMN IF NOT EXISTS account_id UUID REFERENCES nv_accounts(id),
  ADD COLUMN IF NOT EXISTS onboarding_id UUID REFERENCES nv_onboarding(id),
  ADD COLUMN IF NOT EXISTS store_slug TEXT,
  ADD COLUMN IF NOT EXISTS builder_url TEXT,
  ADD COLUMN IF NOT EXISTS onboarding_status TEXT;

-- Timestamps de lifecycle
ALTER TABLE outreach_leads
  ADD COLUMN IF NOT EXISTS qualified_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS won_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lost_at TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS lost_reason TEXT;

-- AI scoring
ALTER TABLE outreach_leads
  ADD COLUMN IF NOT EXISTS ai_engagement_score INTEGER DEFAULT 0
    CHECK (ai_engagement_score >= 0 AND ai_engagement_score <= 100);

-- ============================================================================
-- PASO 2: Actualizar CHECK constraint de status (ANTES de migrar datos)
-- ============================================================================

-- Eliminar constraint viejo
ALTER TABLE outreach_leads
  DROP CONSTRAINT IF EXISTS outreach_leads_status_check;

-- Crear constraint nuevo con estados expandidos
ALTER TABLE outreach_leads
  ADD CONSTRAINT outreach_leads_status_check
  CHECK (status = ANY (ARRAY[
    'NEW'::text,
    'CONTACTED'::text,
    'IN_CONVERSATION'::text,
    'QUALIFIED'::text,
    'ONBOARDING'::text,
    'WON'::text,
    'COLD'::text,
    'LOST'::text,
    'DISCARDED'::text
  ]));

-- ============================================================================
-- PASO 3: Migrar datos existentes (columnas y constraint ya existen)
-- ============================================================================

-- Migrar status 'CLIENT' → 'WON' (si existe alguno)
UPDATE outreach_leads
SET status = 'WON', won_at = updated_at
WHERE status = 'CLIENT';

-- Migrar status 'WORKING' → 'IN_CONVERSATION' (si existe alguno)
UPDATE outreach_leads
SET status = 'IN_CONVERSATION'
WHERE status = 'WORKING';

-- ============================================================================
-- PASO 4: Índices nuevos para outreach_leads  
-- ============================================================================

-- Índice para queries de follow-up (status + next_followup_at)
CREATE INDEX IF NOT EXISTS idx_outreach_leads_fu_query
  ON outreach_leads (status, next_followup_at)
  WHERE status = 'CONTACTED' AND next_followup_at IS NOT NULL;

-- Índice para bridge a onboarding
CREATE INDEX IF NOT EXISTS idx_outreach_leads_account_id
  ON outreach_leads (account_id)
  WHERE account_id IS NOT NULL;

-- Índice para hot leads activos
CREATE INDEX IF NOT EXISTS idx_outreach_leads_hot
  ON outreach_leads (hot_lead, status)
  WHERE hot_lead = true;

-- Índice para AI engagement scoring
CREATE INDEX IF NOT EXISTS idx_outreach_leads_engagement
  ON outreach_leads (ai_engagement_score DESC)
  WHERE status IN ('IN_CONVERSATION', 'QUALIFIED');

-- ============================================================================
-- PASO 5: Cambios en outreach_logs
-- ============================================================================

-- Columna para deduplicación de mensajes WA
ALTER TABLE outreach_logs
  ADD COLUMN IF NOT EXISTS wamid TEXT;

-- Columna para tracking de procesamiento
ALTER TABLE outreach_logs
  ADD COLUMN IF NOT EXISTS processing_status TEXT DEFAULT 'processed'
    CHECK (processing_status = ANY (ARRAY[
      'pending'::text,
      'processed'::text,
      'skipped'::text,
      'error'::text
    ]));

-- Índice único parcial para deduplicación por wamid
CREATE UNIQUE INDEX IF NOT EXISTS idx_outreach_logs_wamid
  ON outreach_logs (wamid)
  WHERE wamid IS NOT NULL;

-- Índice para queries de historial de conversación
CREATE INDEX IF NOT EXISTS idx_outreach_logs_lead_created
  ON outreach_logs (lead_id, created_at DESC);

-- ============================================================================
-- PASO 6: Tabla de configuración de outreach
-- ============================================================================

CREATE TABLE IF NOT EXISTS outreach_config (
  key TEXT PRIMARY KEY,
  value JSONB NOT NULL,
  description TEXT,
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by TEXT DEFAULT 'system'
);

-- Seed de configuración por defecto
INSERT INTO outreach_config (key, value, description) VALUES
  ('seed_batch_size', '50', 'Cantidad de leads a procesar por ejecución del seed'),
  ('fu_batch_size', '100', 'Cantidad de leads a procesar por ejecución de follow-up'),
  ('max_followup_attempts', '4', 'Máximo de intentos de follow-up antes de marcar COLD'),
  ('wa_daily_limit', '200', 'Límite diario de mensajes WA'),
  ('fu_delays_days', '[3, 5, 7]', 'Días de espera entre follow-ups (array JSON)'),
  ('qualification_threshold', '70', 'Score mínimo de engagement para marcar QUALIFIED'),
  ('hot_lead_threshold', '80', 'Score mínimo para notificar hot lead'),
  ('bot_enabled', 'true', 'Habilitar/deshabilitar bot AI globalmente'),
  ('seed_cron', '"0 10 * * 1-5"', 'Cron expression para seed (L-V 10am)'),
  ('fu_cron', '["0 11 * * 1-5", "0 17 * * 1-5"]', 'Cron expressions para follow-ups'),
  ('opt_out_keywords', '["stop","parar","basta","no más","cancelar suscripción","dejar de recibir","no me escriban","borrame","eliminarme","desuscribirme"]', 'Palabras clave para opt-out automático'),
  ('humanize_delay_ms', '{"min": 3000, "max": 12000}', 'Rango de delay humanizado para replies del bot (ms)')
ON CONFLICT (key) DO NOTHING;

-- RLS para outreach_config (solo service_role)
ALTER TABLE outreach_config ENABLE ROW LEVEL SECURITY;

CREATE POLICY "outreach_config_service_bypass"
  ON outreach_config
  FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- ============================================================================
-- PASO 7: Seed data para nv_playbook (si está vacío)
-- ============================================================================

INSERT INTO nv_playbook (id, key, segment, stage, type, title, content, priority, active, topic) VALUES
  (gen_random_uuid(), 'intro-what-is-nv', 'general', 'intro', 'pitch', 'Qué es NovaVision',
   'NovaVision es una plataforma que te permite crear tu tienda online en minutos, sin necesidad de conocimientos técnicos. Incluye catálogo de productos, carrito, pagos con Mercado Pago, y panel de administración.', 1, true, 'producto'),

  (gen_random_uuid(), 'pricing-basic', 'general', 'discovery', 'pricing', 'Plan Básico',
   'El plan básico incluye: tienda online completa, hasta 100 productos, SSL, dominio .novavision.com.ar gratuito, soporte por email. Precio promocional de lanzamiento (consultar monto actualizado).', 2, true, 'pricing'),

  (gen_random_uuid(), 'objection-price', 'general', 'closing', 'objection', 'Objeción: "Es caro"',
   'Comparado con una tienda custom o plataformas que cobran comisión por venta, NovaVision cobra una tarifa fija mensual baja. Además podés empezar gratis con el builder y pagar solo cuando decidas publicar.', 3, true, 'objeciones'),

  (gen_random_uuid(), 'objection-time', 'general', 'closing', 'objection', 'Objeción: "No tengo tiempo"',
   'El builder tarda menos de 15 minutos. Elegís un template, subís tus productos, y listo. Si ya tenés fotos de productos, en 10 minutos tenés tu tienda.', 4, true, 'objeciones'),

  (gen_random_uuid(), 'objection-technical', 'general', 'closing', 'objection', 'Objeción: "No sé de tecnología"',
   'NovaVision está pensado justamente para emprendedores sin conocimientos técnicos. El builder es visual, arrastrás y soltás. Y si tenés dudas, tenés soporte incluido.', 4, true, 'objeciones'),

  (gen_random_uuid(), 'cta-builder', 'general', 'closing', 'cta', 'CTA: Link al builder',
   'Podés empezar ahora mismo, gratis y sin compromiso: https://novavision.com.ar/builder — Creá tu tienda en 15 minutos.', 5, true, 'conversion'),

  (gen_random_uuid(), 'benefit-mp', 'general', 'discovery', 'benefit', 'Integración Mercado Pago',
   'La tienda viene con Mercado Pago integrado. Tus clientes pueden pagar con tarjeta, transferencia, QR. Vos recibís la plata directo en tu cuenta de MP. Sin comisiones extras de NovaVision.', 2, true, 'producto'),

  (gen_random_uuid(), 'benefit-admin', 'general', 'discovery', 'benefit', 'Panel de administración',
   'Desde el panel admin podés gestionar productos, ver pedidos, cambiar diseños, banners y más. Todo desde el celular o la compu. Incluye métricas de ventas en tiempo real.', 2, true, 'producto'),

  (gen_random_uuid(), 'benefit-templates', 'general', 'discovery', 'benefit', 'Templates profesionales',
   'Tenés múltiples diseños profesionales para elegir. Todos adaptables a celular, con SSL incluido y optimizados para velocidad. Tu tienda se ve profesional desde el día 1.', 2, true, 'producto'),

  (gen_random_uuid(), 'closing-urgency', 'general', 'closing', 'closing', 'Urgencia de lanzamiento',
   'Cuanto antes tengas tu tienda online, antes empezás a vender. El builder es gratis, no perdés nada probando. Muchos emprendedores se arrepienten de no haber empezado antes.', 5, true, 'conversion')
ON CONFLICT DO NOTHING;

-- ============================================================================
-- VERIFICACIÓN POST-MIGRACIÓN
-- ============================================================================

-- Verificar que los nuevos estados son válidos
DO $$
BEGIN
  -- Test: insertar y borrar un lead con cada nuevo status
  PERFORM 1 FROM (
    SELECT unnest(ARRAY['QUALIFIED','ONBOARDING','WON','COLD','LOST']) as s
  ) x
  WHERE x.s = ANY (ARRAY['QUALIFIED','ONBOARDING','WON','COLD','LOST']);

  RAISE NOTICE 'Migración exitosa: nuevos estados disponibles';
END $$;

-- Verificar que no quedaron leads con status viejo
DO $$
DECLARE
  bad_count INTEGER;
BEGIN
  SELECT COUNT(*) INTO bad_count
  FROM outreach_leads
  WHERE status IN ('CLIENT', 'WORKING');

  IF bad_count > 0 THEN
    RAISE EXCEPTION 'Hay % leads con status viejo (CLIENT/WORKING) sin migrar', bad_count;
  END IF;

  RAISE NOTICE 'Verificación OK: no hay leads con status viejo';
END $$;

COMMIT;

-- ============================================================================
-- ROLLBACK (ejecutar manualmente si algo falla)
-- ============================================================================
/*
BEGIN;

-- Revertir datos migrados
UPDATE outreach_leads SET status = 'CLIENT' WHERE status = 'WON' AND won_at IS NOT NULL;
UPDATE outreach_leads SET status = 'WORKING' WHERE status = 'IN_CONVERSATION';

-- Quitar columnas nuevas de outreach_leads
ALTER TABLE outreach_leads
  DROP COLUMN IF EXISTS account_id,
  DROP COLUMN IF EXISTS onboarding_id,
  DROP COLUMN IF EXISTS store_slug,
  DROP COLUMN IF EXISTS builder_url,
  DROP COLUMN IF EXISTS onboarding_status,
  DROP COLUMN IF EXISTS qualified_at,
  DROP COLUMN IF EXISTS won_at,
  DROP COLUMN IF EXISTS lost_at,
  DROP COLUMN IF EXISTS lost_reason,
  DROP COLUMN IF EXISTS ai_engagement_score;

-- Restaurar CHECK constraint original
ALTER TABLE outreach_leads DROP CONSTRAINT IF EXISTS outreach_leads_status_check;
ALTER TABLE outreach_leads ADD CONSTRAINT outreach_leads_status_check
  CHECK (status = ANY (ARRAY['NEW','CONTACTED','IN_CONVERSATION','CLIENT','DISCARDED','WORKING']));

-- Quitar columnas de outreach_logs
ALTER TABLE outreach_logs
  DROP COLUMN IF EXISTS wamid,
  DROP COLUMN IF EXISTS processing_status;

-- Quitar índices nuevos
DROP INDEX IF EXISTS idx_outreach_leads_fu_query;
DROP INDEX IF EXISTS idx_outreach_leads_account_id;
DROP INDEX IF EXISTS idx_outreach_leads_hot;
DROP INDEX IF EXISTS idx_outreach_leads_engagement;
DROP INDEX IF EXISTS idx_outreach_logs_wamid;
DROP INDEX IF EXISTS idx_outreach_logs_lead_created;

-- Quitar tabla de configuración
DROP TABLE IF EXISTS outreach_config;

-- Quitar playbook seeds (solo si fueron insertados por esta migración)
DELETE FROM nv_playbook WHERE key IN (
  'intro-what-is-nv', 'pricing-basic', 'objection-price', 'objection-time',
  'objection-technical', 'cta-builder', 'benefit-mp', 'benefit-admin',
  'benefit-templates', 'closing-urgency'
);

COMMIT;
*/

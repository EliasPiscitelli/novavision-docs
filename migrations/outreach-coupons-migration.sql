-- Tabla de cupones de outreach (para incentivos del bot)
CREATE TABLE IF NOT EXISTS outreach_coupons (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  code TEXT NOT NULL UNIQUE,
  description TEXT NOT NULL,
  discount_type TEXT NOT NULL CHECK (discount_type IN ('percent', 'fixed', 'free_months')),
  discount_value NUMERIC NOT NULL CHECK (discount_value > 0),
  max_uses INTEGER DEFAULT NULL,
  current_uses INTEGER DEFAULT 0,
  valid_from TIMESTAMPTZ DEFAULT now(),
  valid_until TIMESTAMPTZ DEFAULT NULL,
  active BOOLEAN DEFAULT true,
  min_plan TEXT DEFAULT NULL,
  applies_to TEXT DEFAULT 'subscription' CHECK (applies_to IN ('subscription', 'setup', 'both')),
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Tabla para tracking de cupones ofrecidos/redimidos por lead
CREATE TABLE IF NOT EXISTS outreach_coupon_offers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  lead_id BIGINT NOT NULL REFERENCES outreach_leads(id),
  coupon_id UUID NOT NULL REFERENCES outreach_coupons(id),
  offered_at TIMESTAMPTZ DEFAULT now(),
  redeemed_at TIMESTAMPTZ DEFAULT NULL,
  status TEXT DEFAULT 'offered' CHECK (status IN ('offered', 'redeemed', 'expired', 'rejected')),
  UNIQUE(lead_id, coupon_id)
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_outreach_coupons_active ON outreach_coupons (active, valid_until) WHERE active = true;
CREATE INDEX IF NOT EXISTS idx_outreach_coupon_offers_lead ON outreach_coupon_offers (lead_id);

-- RLS
ALTER TABLE outreach_coupons ENABLE ROW LEVEL SECURITY;
ALTER TABLE outreach_coupon_offers ENABLE ROW LEVEL SECURITY;

CREATE POLICY "outreach_coupons_service_bypass" ON outreach_coupons FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
CREATE POLICY "outreach_coupon_offers_service_bypass" ON outreach_coupon_offers FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Config entries para el bot
INSERT INTO outreach_config (key, value, description) VALUES
  ('coupon_enabled', 'true', 'Habilitar/deshabilitar oferta de cupones por el bot'),
  ('coupon_offer_stage', '"QUALIFIED"', 'Stage minimo para ofrecer cupon (QUALIFIED, IN_CONVERSATION, etc)'),
  ('coupon_default_code', '"NOVA10"', 'Codigo de cupon por defecto que ofrece el bot'),
  ('coupon_offer_message', '"Como beneficio especial por tu interes, te ofrecemos un cupon exclusivo: {code} que te da {description}. Es valido hasta {valid_until}."', 'Template del mensaje de cupon')
ON CONFLICT (key) DO NOTHING;

-- Seed: primer cupon de ejemplo
INSERT INTO outreach_coupons (code, description, discount_type, discount_value, max_uses, valid_until, active, applies_to) VALUES
  ('NOVA10', '10% de descuento en el primer mes', 'percent', 10, 100, now() + interval '90 days', true, 'subscription'),
  ('NOVASETUP', 'Setup gratuito', 'fixed', 15000, 50, now() + interval '60 days', true, 'setup')
ON CONFLICT (code) DO NOTHING;

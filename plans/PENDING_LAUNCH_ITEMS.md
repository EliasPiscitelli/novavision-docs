# Items Pendientes para Lanzamiento

**Fecha:** 2026-03-16
**Estado:** Todo el desarrollo técnico está completado. Los pendientes son configuración manual, contenido y decisiones.

---

## Configuración manual (no requiere desarrollo)

| # | Item | Plataforma | Tiempo est. | Notas |
|---|------|-----------|-------------|-------|
| 1 | Crear propiedad GA4 para novavision.lat | Google Analytics | 30 min | Crear propiedad, obtener Measurement ID (G-XXXXX), configurar en env vars del admin |
| 2 | Confirmar Pixel ID para novavision.lat | Meta Business Manager | 30 min | Crear/confirmar Pixel, obtener ID numérico, configurar en env vars |
| 3 | Generar Access Token CAPI | Meta Business Manager | 30 min | Token para Conversion API server-side de la plataforma |
| 4 | Verificar eventos en Meta Events Manager | Meta Events Tool | 1-2h | Confirmar que PageView, CompleteRegistration, Subscribe llegan correctamente |

---

## Contenido y creatividades

| # | Item | Formato | Tiempo est. | Prioridad |
|---|------|---------|-------------|-----------|
| 5 | Demo grabada del onboarding | Video 60-90 seg | 2-3h | Alta — pieza principal de ads |
| 6 | Tiendas demo live (1-2 rubros) | Tiendas publicadas | 2-3h c/u | Alta — prueba tangible para leads |
| 7 | Founder video UGC | Video cara a cámara 60-90 seg | 2h | Media-alta — genera confianza |
| 8 | Screen recording SEO AI generando metadata | Video corto 30-60 seg | 1h | Media — pieza para ads |

---

## Decisiones de negocio (ya tomadas, documentar)

| # | Decisión | Resultado | Documentado en |
|---|----------|-----------|----------------|
| ✅ | Política de entrada | Builder gratis + pago al publicar + cupones | PRICING_BIBLE.md, es.json |
| ✅ | Promesa hero | "Dejá de perder ventas por WhatsApp e Instagram." | es.json (Opción A) |
| ✅ | ICP lanzamiento | Pyme argentina, vende por WhatsApp/IG, catálogo chico/medio | info-v2.md |
| ✅ | Promo lanzamiento | Cupos limitados con cupones | 12 cupones pre-seeded en DB |
| ✅ | Precio Enterprise | $390/mo, "Consultar", setup caso a caso | PRICING_BIBLE.md, ADMIN_066, es.json |

---

## Desarrollo técnico completado (referencia)

Todo lo siguiente ya está implementado, testeado y pusheado:

- [x] Cookie consent (Ley 25.326)
- [x] Guest checkout completo
- [x] Country picker + currency dinámica
- [x] Churn detection + warning emails (cron 14 días)
- [x] Recovery emails onboarding (24h, 48h, 72h)
- [x] First-purchase celebration email
- [x] Ecommerce event tracking per-tenant (GA4 + Meta Pixel)
- [x] CTA tracking (WhatsApp, redes)
- [x] CAPI server-side (Subscribe + Purchase)
- [x] ConnectionsChecklist panel
- [x] SEO/tracking validation
- [x] PricingPage con Growth "Recomendado"
- [x] Landing reestructurada (embudo 6 preguntas)
- [x] Hero Opción A implementada
- [x] FAQs alineadas (11 preguntas, comparativa TN, SLA por plan)
- [x] Servicios = 5 pilares reales
- [x] Pricing cards con datos reales de DB
- [x] 6 tests pre-existentes corregidos (87/87 passing)
- [x] P0-P2 tech debt resuelto (MP redirect, CNPJ/CPF, runStep, logo dual source)
- [x] Pricing Bible como source of truth
- [x] Sistema de cupones verificado (12 pre-seeded, campo en onboarding)

---

## P3 — Roadmap futuro (post-lanzamiento)

Documentado en `changes/2026-03-15-p0p2-tech-debt-resolution.md`. Incluye:
Blog/CMS, email marketing, marketplace, AI chatbot, multi-idioma, Stripe/PayPal, POS, API pública, inventario multi-sucursal, Search Console integration, Google Ads, CAPI per-tenant, dashboard analytics, export CSV, categorías jerárquicas, carriers internacionales.

# Inventario de Pendientes del Sistema — Post-Auditorías 2026-03-15

Cruce de las 4 auditorías realizadas hoy contra el estado real del sistema.

---

## RESUELTO HOY (no requiere más trabajo)

| Item | Auditoría | Commit |
|------|-----------|--------|
| progress JSONB → columnas tipadas + dual-write | Tech Debt E2E | `9847e31` |
| runStep en 14 de 23 pasos del provisioning | Tech Debt E2E | `9847e31` |
| Schemas canónicos (backend_clusters, subscriptions) | Tech Debt E2E | `34f938f` |
| Drop has_demo_data + trigger recreado | Tech Debt E2E | `34f938f` |
| Migraciones retroactivas (nv_accounts, schema alignment, storage triggers) | Tech Debt E2E | `34f938f` |
| OAuth captura site_id del seller (resolveSellerGeo + validateCountryMatch) | Country/Currency | `0e9ecac` |
| countryLocaleMap completo 7/7 países | Country/Currency | `0e9ecac` |
| Fee table seed para 7 países LATAM | Country/Currency | `709b21c` |
| Defaults ARS eliminados de payment tables | Country/Currency | `709b21c` |
| Addons checkout_currency dinámico | Country/Currency | `0e9ecac` |
| Import wizard + Products: currencies LATAM (8 monedas) | Country/Currency | `0e9ecac` |
| PaymentsConfig UI: fees y labels dinámicos por tenant | Country/Currency | `e32df75` |
| Admin dashboard: formatters dinámicos por país | Country/Currency | `56d7cf9` |
| Admin approval: warning de MP country mismatch | Country/Currency | `56d7cf9` |
| Addon store: fix allowed_plans vacíos | Addon Store | `20a4961` |
| Addon store: rebalance deltas (images +1, products +2000) | Addon Store | `20a4961` |
| Addon store: repricing acorde a costos e incentivo upgrade | Addon Store | `20a4961` |
| Addon store: quitar precio USD, simplificar labels | Addon UX | `ee099a5` |
| Addon modal: fondo opaco (--nv-admin-surface) | UI Fix | `76e6bbe` |
| Ecommerce events GA4 + Meta Pixel (view_item, add_to_cart, begin_checkout, purchase) | SEO/Tracking | `83ac286` |
| Meta Pixel injection per-tenant | SEO/Tracking | `83ac286` |
| CTA tracking (WhatsApp, social links) | SEO/Tracking | `7e63720` |
| Meta Pixel field + validation en API DTO | SEO/Tracking | `e552346` |
| SeoEditTab: Meta Pixel + Search Console + validación inline | SEO/Tracking | `7e63720` |
| ConnectionsChecklist con impacto + guías + links externos | SEO/Tracking | `7e63720` |
| Migraciones canónicas para 4 tablas SEO | SEO/Tracking | `1cfeed2` |
| SEO pack repricing ($19/$49/$99) + entity cost 1 cr/entity | SEO/Tracking | `1cfeed2` |
| Tests ecommerce tracking (13 specs) | SEO/Tracking | `7e63720` |

---

## PENDIENTE TÉCNICO — Por prioridad

### P0 — Bloqueante para lanzamiento

| # | Item | Origen | Esfuerzo | Detalle |
|---|------|--------|:---:|--------|
| 1 | **GA4 + Pixel configurados en novavision.lat** | Pre-launch checklist | 1-2h | Crear propiedad GA4, confirmar Pixel ID, generar CAPI Access Token. Solo config en plataformas externas, no código. |
| 2 | **Verificar eventos de onboarding en tracking** | Pre-launch checklist | 1-2h | PageView, CompleteRegistration, InitiateCheckout, Subscribe deben estar firing en la landing. Testear con Meta Events Tool. |
| 3 | **Cookie banner en storefront** | SEO/Tracking audit | 3-4h | El agente de Web reportó NOT FOUND. El consent banner existe en la landing (novavision.lat) pero no se encontró en las tiendas de los tenants ([slug].novavision.lat). Si GA4/Pixel se inyectan sin consent, hay riesgo de compliance. |

### P1 — Importante para primeras semanas

| # | Item | Origen | Esfuerzo | Detalle |
|---|------|--------|:---:|--------|
| 4 | **Guest checkout** | Feature audit | 4-6h | Hoy se requiere cuenta para comprar. Guest checkout reduce fricción de conversión significativamente. |
| 5 | **Admin wizard: country picker** | Country/Currency audit | 4-6h | El wizard hardcodea Argentina (CUIT, DNI, AFIP). La API ya soporta /onboarding/country-config/:countryId con labels dinámicos. Falta el UI. |
| 6 | **Admin wizard: MP redirect dinámico** | Country/Currency audit | 1h | Hardcoded a mercadopago.com.ar. Debería ser dinámico según país del account. |
| 7 | **First-purchase celebration email** | Pre-launch checklist | 2-3h | Email al admin cuando su tienda recibe el primer pedido. Los webhooks y email system existen. |
| 8 | **Churn early warning email** | Pre-launch checklist | 3-4h | Email proactivo si tienda publicada tiene 0 pedidos en 14 días. Cron + email. |
| 9 | **runStep en 9 pasos restantes del provisioning** | Tech Debt E2E | 3-4h | Steps READ-only (fetch_account, fetch_onboarding, parse_progress, etc.). No urgente pero mejora debugging. |

### P2 — Mejora competitiva a mediano plazo

| # | Item | Origen | Esfuerzo | Detalle |
|---|------|--------|:---:|--------|
| 10 | **FiscalIdValidator para BR (CNPJ/CPF)** | Country/Currency | 2-3h | 6 de 7 países tienen validador. Brasil falta. |
| 11 | **Logo dual source of truth** | E2E audit P1 #4 | 3-4h | logos table vs identity_config.logo no sincronizados. |
| 12 | **clients.entitlements no recalcula en upgrade** | E2E audit P1 #6 | 4-6h | Snapshot se toma en provisioning, no se actualiza si cambia plan o addons. |
| 13 | **CAPI server-side per tenant** | SEO/Tracking | Alto | Hoy CAPI solo envía eventos de la plataforma NV, no de las tiendas. Para per-tenant se necesitaría access_token del tenant en Meta. |
| 14 | **Dashboard analytics mejorado** | SEO/Tracking | Medio | Que el admin vea sesiones, conversion rate, fuentes. Requiere conectar GA4 API o proxy. |
| 15 | **Product export** | Feature audit | 3-4h | Import existe (CSV/JSON con IA). Export no existe. |
| 16 | **Categorías jerárquicas** | Feature audit | Medio | Hoy son flat. Para catálogos grandes necesitan sub-categorías. |
| 17 | **Carriers internacionales** | Country/Currency | Alto/país | Andreani/OCA/Correo Argentino son AR-only. Para CL/MX/CO se necesitan carriers locales. |

### P3 — Futuro (post-validación de mercado)

| # | Item | Origen | Detalle |
|---|------|--------|--------|
| 18 | Blog integrado | Mejoras estratégicas | Content marketing y SEO orgánico |
| 19 | Email marketing / drip campaigns | Mejoras estratégicas | Automatización post-compra, newsletters |
| 20 | Marketplace de apps/integraciones | Mejoras estratégicas | Tiendanube tiene +100 apps, Shopify +8.000 |
| 21 | IA conversacional (chatbot en tienda) | Mejoras estratégicas | Chat Nube de TN resuelve +70% consultas |
| 22 | Multi-idioma | Feature audit | Solo español hoy |
| 23 | Stripe/PayPal | Mejoras estratégicas | Para operar fuera de MP |
| 24 | POS | Mejoras estratégicas | Para negocios con local físico |
| 25 | API pública | Mejoras estratégicas | Para integraciones custom Enterprise |
| 26 | Inventario multi-sucursal | Mejoras estratégicas | Para Enterprise con múltiples depósitos |
| 27 | Search Console integración real | SEO/Tracking | Hoy solo token — sin importación de datos |
| 28 | Google Ads conversion field | SEO/Tracking | Hoy se importan conversiones desde GA4 |

---

## PENDIENTE COMERCIAL — Por prioridad

| # | Item | Tipo | Esfuerzo |
|---|------|------|:---:|
| 1 | **Pricing Bible congelado** | Decisión | 2h |
| 2 | **Política de entrada definida** (builder gratis + pago al publicar, o trial) | Decisión | 1h |
| 3 | **Promesa principal en 5 segundos** | Decisión | 30min |
| 4 | **Landing reescrita** (6 preguntas en orden) | Contenido | 4-8h |
| 5 | **Demo grabada** (screen recording onboarding + tienda) | Contenido | 2-3h |
| 6 | **ICP de lanzamiento comunicado** | Decisión | 0 |
| 7 | **Growth como plan recomendado** (badge en landing) | UI | 1h |
| 8 | **Tiendas demo live** (2-3 rubros distintos) | Contenido | 2-3h/tienda |
| 9 | **Founder video UGC** | Contenido | 2h |
| 10 | **Tablero de métricas interno** (builder starts → pagos → publicaciones) | Dashboard | 4-6h |

---

## Vista rápida: qué hacer esta semana

```
HOY / MAÑANA (decisiones, 0 código):
  □ Pricing Bible
  □ Política de entrada
  □ Promesa 5 seg
  □ ICP confirmado

ESTA SEMANA (config + contenido):
  □ GA4 + Pixel en novavision.lat
  □ Verificar eventos onboarding
  □ Cookie banner en storefronts (si falta)
  □ Demo grabada
  □ Landing reescrita

PRÓXIMA SEMANA (código liviano):
  □ Guest checkout
  □ First-purchase email
  □ Churn warning email
  □ Growth badge en landing
  □ Tablero métricas interno
```

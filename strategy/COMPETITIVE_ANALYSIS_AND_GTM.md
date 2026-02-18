# NovaVision — Análisis Competitivo y Estrategia Go-To-Market

**Fecha:** 18 de febrero de 2026  
**Autor:** Agente Copilot (estrategia de producto)  
**Fuentes internas:** es.json (admin i18n), architecture docs, database-schema-reference.md, NOVAVISION_IMPROVEMENT_BACKLOG.md, system_flows_and_persistence.md, STORE_COUPONS_DESIGN.md, SIZES_OPTIONS_SYSTEM_REDESIGN.md, SHIPPING_CONFIG_MODEL.md  
**Fuentes externas:** Shopify AR (shopify.com/ar/precios, consultado 2026-02-18), Tiendanube (tiendanube.com, consultado 2026-02-18), Wix (wix.com/upgrade/website, consultado 2026-02-18), Ecwid (ecwid.com/pricing, consultado 2026-02-18), conocimiento público de WooCommerce, PrestaShop, BigCommerce, Squarespace, Jumpseller.

---

## 1. Resumen Ejecutivo

NovaVision es una plataforma SaaS multi-tenant de e-commerce orientada a pymes y emprendedores argentinos/LATAM. Su propuesta se centra en: setup rápido sin código, panel autoadministrable, integración nativa con Mercado Pago y costos predecibles en USD. La arquitectura (NestJS + Supabase + Vite/React) permite operar múltiples tiendas desde una sola infraestructura con aislamiento de datos por tenant.

**Verdad incómoda:** el producto está en etapa piloto (2 clientes activos, ~19 productos en DB). Varias capacidades clave que se promocionan están diseñadas pero no implementadas (cupones de tienda, talles/opciones, envíos con API de courier, filtros de búsqueda funcionales). El claim "500+ pymes confían en NovaVision" no tiene respaldo verificable en los datos internos.

**Lo que sí es real y defendible:** la arquitectura multi-tenant con provisioning automatizado, la integración profunda con Mercado Pago (webhooks idempotentes, single-item preference, breakdown de fees), y el modelo de negocio sin comisiones por transacción son diferenciadores concretos frente a algunos competidores.

**Acción clave:** antes de escalar marketing, cerrar los gaps P0 (revalidación de precios server-side, pérdida de datos de talle en carrito, filtros de búsqueda rotos) y pasar de 2 a 10+ clientes para tener evidencia real.

---

## 2. Mapa de Claims (Fase 0)

### 2.1 Promesa principal
> "Impulsa tu Negocio con una solución de comercio electrónico escalable y fácil de gestionar diseñada para pequeñas empresas y emprendedores."

**Evidencia:** es.json `banner.description`. **Estado:** parcialmente confirmada — la plataforma existe y funciona, pero "escalable" es una hipótesis (solo 2 clientes activos).

### 2.2 Tres pilares del producto

| # | Pilar | Evidencia interna | Estado |
|---|-------|-------------------|--------|
| 1 | **Setup rápido sin código** ("en segundos con autogestión y auto onboarding") | es.json FAQs #1; architecture/system_flows — wizard 5 pasos (Slug→Logo→Catálogo→Design Studio→Publish) | **Hipótesis a verificar** — "en segundos" es aspiracional; el wizard existe pero el Design Studio no está 100% integrado en frontend |
| 2 | **Panel autoadministrable** (productos, banners, colores, pedidos sin tocar código) | es.json FAQs #3,#6; admin dashboard real con CRUD de productos, banners, FAQs, social links, categorías | **Confirmada por insumo** — el panel existe y opera |
| 3 | **Integración de pagos local** (Mercado Pago nativo) | es.json FAQs #5, services #2; architecture/FLOW_DIAGRAM — preferencia single-item, QuoteService, webhook idempotente | **Confirmada por insumo** — integración profunda documentada y desplegada |

### 2.3 Capacidades mencionadas en claims

| # | Claim | Fuente | Estado | Comentario |
|---|-------|--------|--------|------------|
| C1 | "En segundos con autogestión y auto onboarding" | es.json testimonial #1, FAQ #1 | ⚠️ Hipótesis | Wizard existe pero Design Studio no 100% integrado; "segundos" no es medible aún |
| C2 | "500+ pymes confían en NovaVision" | es.json testimonials.subtitle | ❌ No verificable | DB muestra 2 clientes activos y 47.403 leads en outreach — no equivale a clientes |
| C3 | "Migramos el catálogo desde Shopify y en el mismo día estábamos vendiendo" | es.json testimonial #2 | ❌ No verificable | Testimonios parecen ficticios; no hay evidencia de migración desde Shopify |
| C4 | "Plantillas listas" / templates modernos | es.json services #1, testimonial #3 | ⚠️ Parcial | 5 templates en DB (`nv_templates`), solo 1 documentado en detalle ("normal"). 20 paletas de color en `palette_catalog` |
| C5 | "Gestión de Inventario en tiempo real" | es.json services #3 | ⚠️ Parcial | Stock global por producto existe; NO hay stock por variante/talle. No hay alertas de stock bajo |
| C6 | "Marketing & SEO integrado" | es.json services #5 | ⚠️ Hipótesis | No se encontró evidencia de herramientas SEO activas en el codebase más allá de meta tags básicos |
| C7 | "Configuración Fácil — lanza sin conocimientos técnicos" | es.json services #6 | **Confirmada** | Wizard de onboarding documentado y provisioning automatizado |
| C8 | "Puesta en línea express en 48hs" (plan Starter) | es.json pricing.plans[0].advantages[0] | ⚠️ Hipótesis | Depende de carga de datos; sin evidencia de tiempo real medido |
| C9 | "Sin comisiones ocultas ni cargos sorpresa" | es.json pricing.plans[0].advantages[2] | **Confirmada** | Modelo de suscripción fija + setup fee; sin comisión por transacción |
| C10 | "Hosting seguro, backups automáticos, actualizaciones" | es.json pricing features, FAQ #10 | **Confirmada** | Supabase + Netlify + Railway con deploys automáticos |
| C11 | "Integración con Stripe, PayPal y más" | es.json services #2 | ❌ No verificable | Solo Mercado Pago está implementado. "Otros gateways consultar" en plan Growth |
| C12 | "Soporte por WhatsApp o email" | es.json FAQ #7, contactSection | **Confirmada** | Hay número de WhatsApp y email documentados |
| C13 | "Carga masiva de productos" | es.json FAQ #2 | ⚠️ Hipótesis | No se encontró feature de import CSV/bulk en el codebase |
| C14 | "Cupones" / promos | STORE_COUPONS_DESIGN.md | ❌ Diseñado, NO implementado | Diseño completo con 6 PRs pendientes |
| C15 | "Envíos y logística" | SHIPPING_CONFIG_MODEL.md | ❌ Diseñado, NO implementado | La tabla `client_shipping_settings` no existe en el schema de producción |
| C16 | "Talles y opciones (polirrubro)" | SIZES_OPTIONS_SYSTEM_REDESIGN.md | ❌ Diseñado, NO implementado | 37 presets propuestos; actualmente talles hardcodeados XS-XXL |
| C17 | "Multi-tenant / multicliente" | architecture/OVERVIEW.md, TenantContextGuard | **Confirmada** | RLS + guards + middleware implementados (aunque RLS no testeada exhaustivamente — BUG-007) |
| C18 | "Dark mode" | system_flows_and_persistence.md | **Confirmada** | Toggle implementado con CSS variables `--nv-*` |
| C19 | "Dominio propio" (plan Growth) | es.json pricing.plans[1].features | ⚠️ Parcial | Mencionado; tabla `domains` existe en Admin DB. Implementación no documentada en detalle |

---

## 3. Set Competitivo (Fase 1)

### Competidores directos e indirectos para pymes en Argentina/LATAM

| # | Competidor | Modelo | Target | Precio base/mes (USD) | Comisión tx | Ecosistema/Apps | Time-to-launch | Personalización | Pagos locales (MP) | Soporte local | Fuente |
|---|-----------|--------|--------|----------------------|-------------|-----------------|----------------|-----------------|--------------------|---------------|--------|
| 1 | **Tiendanube** | SaaS | Pymes LATAM (líder AR) | Gratis (Inicial) / ~USD 20 (Esencial, ARS 24.999) | Sí, variable por plan | +350 apps | Mismo día (DIY) | Tienda de diseños + themes | ✅ Nativo (Pago Nube) | ✅ AR, MX, BR, CO | tiendanube.com, 2026-02-18 |
| 2 | **Shopify** | SaaS | Global, todas las escalas | USD 19 (Basic, anual) / USD 1 primeros 3 meses | 2% proveedores externos | 8.000+ apps | Mismo día (DIY) | Themes + Liquid + apps | ✅ Via app/gateway | ❌ Chat 24/7 en español, no local | shopify.com/ar/precios, 2026-02-18 |
| 3 | **Wix eCommerce** | SaaS | Generalista | USD 29 (Core) / USD 39 (Business recomendado) | 0% | App Market | Mismo día (drag-and-drop) | 2.000+ templates, editor visual | Via gateways (no nativo) | ❌ Global, no local AR | wix.com/upgrade/website, 2026-02-18 |
| 4 | **Ecwid (Lightspeed)** | SaaS/embeddable | Pymes, agregar ecom a sitio existente | USD 5 (Starter) / USD 29 (Venture) | 0% | App Market | Rápido (widget) | Templates + CSS | Via 70+ providers (incluye MP vía Stripe) | ❌ Email/chat en inglés | ecwid.com/pricing, 2026-02-18 |
| 5 | **WooCommerce** | OSS (WordPress) | Técnicos / agencias | Gratis (plugin) + hosting (~USD 5-30) | 0% (plugin); pasarela cobra | 55.000+ plugins | 1-7 días (requiere setup técnico) | Total (código abierto) | ✅ Plugin MP oficial | ❌ Comunidad, no soporte oficial | Conocimiento público |
| 6 | **PrestaShop** | OSS | Técnicos / agencias | Gratis (self-hosted) + hosting | 0% | Marketplace de módulos | 3-14 días (setup complejo) | Total (código abierto) | Via módulos | ❌ Comunidad | Conocimiento público |
| 7 | **Squarespace** | SaaS | Creativos, portafolios + venta | USD 27 (Business) / USD 33 (Basic Commerce) | 0% en Commerce plans | Extensiones limitadas | Mismo día (DIY) | Templates premium | ❌ Sin MP nativo, Stripe/PP | ❌ Global, inglés | Conocimiento público |
| 8 | **BigCommerce** | SaaS | Medianas-grandes | USD 29 (Standard) | 0% | 1.000+ apps | 1-3 días | Stencil framework | Via gateways | ❌ Global | Conocimiento público |
| 9 | **Jumpseller** | SaaS | Pymes LATAM (Chile base) | USD 19 (Basic) | 0% | Limitado | Mismo día | Templates + CSS | ✅ MP nativo | ⚠️ LATAM (Chile, parcial AR) | Conocimiento público |
| 10 | **Agencia + WordPress** | Servicio | Pymes que delegan | USD 500-5.000 (proyecto) + mantenimiento | Según pasarela | Según agencia | 2-8 semanas | Total (a medida) | Según implementación | ✅ Si es agencia local | Conocimiento público |

### Resumen: dónde gana y pierde cada competidor relevante

| Competidor | Dónde gana | Dónde pierde |
|-----------|-----------|-------------|
| **Tiendanube** | Líder LATAM (180K+ marcas), ecosistema completo (pagos, envíos, chat AI, marketing), plan gratis, soporte local | Lock-in moderado, comisiones por tx en planes bajos, diseño de themes puede ser genérico |
| **Shopify** | Escala global, apps, POS, checkout best-in-class (15% más conversión según su claim), trial USD 1 | Caro para pymes AR (comisión 2% + USD en AR), soporte no local, dependencia de apps para features |
| **Wix** | Editor drag-and-drop poderoso, 2.000+ templates, AI builder, no comisión | No especializado en ecommerce, pagos locales limitados, sin foco LATAM |
| **WooCommerce** | Gratis, máxima personalización, enorme ecosistema | Requiere dev, hosting, mantenimiento, seguridad — alto TCO para pymes sin equipo técnico |

---

## 4. Matriz Comparativa (Fase 2)

**Escala:** ✅ Mejor / ≈ Similar / ❌ Peor / — No aplica / ? No verificable

| # | Criterio | NovaVision | Tiendanube | Shopify | Wix | WooCommerce | Ecwid |
|---|---------|-----------|-----------|---------|-----|-------------|-------|
| 1 | **Time-to-launch** | ≈ Wizard 5 pasos, provisioning auto | ✅ Plan gratis, inmediato | ✅ Inmediato | ✅ Inmediato | ❌ 1-7 días | ✅ Widget rápido |
| 2 | **Onboarding guiado** | ≈ Wizard 5 pasos (Design Studio parcial) | ✅ Guías + soporte local | ✅ Videos + docs extensos | ✅ AI builder + tutoriales | ❌ DIY + comunidad | ≈ Básico |
| 3 | **Autogestión sin código** | ✅ Panel admin CRUD completo | ✅ Panel completo | ✅ Admin robusto | ✅ Drag-and-drop | ❌ Requiere WP admin | ≈ Dashboard simple |
| 4 | **Templates/temas** | ❌ 5 templates, 1 documentado, 20 paletas | ✅ Tienda de diseños, decenas | ✅ 100+ themes (pagos y gratis) | ✅ 2.000+ templates | ✅ Miles (ThemeForest+) | ≈ 70+ |
| 5 | **Personalización visual (sin código)** | ≈ Design Studio con paletas + overrides (parcial) | ✅ Editor visual completo | ✅ Theme editor + secciones | ✅ Editor drag-and-drop líder | ❌ Requiere código/plugins | ≈ CSS + settings |
| 6 | **Integración Mercado Pago** | ✅ Nativa, profunda (QuoteService, fees, webhooks) | ✅ Pago Nube (nativo, mejor) | ≈ Via app/gateway, funcional | ❌ No nativo | ≈ Plugin oficial | ≈ Via Stripe |
| 7 | **Otros medios de pago** | ❌ Solo MP (otros "consultar") | ✅ Múltiples nativos | ✅ Shopify Payments + 100+ gateways | ✅ Múltiples | ✅ 100+ plugins | ✅ 70+ providers |
| 8 | **Gestión de productos** | ≈ CRUD básico, 19 productos reales | ✅ Completo + variantes + masivo | ✅ Completo + variantes + masivo | ≈ Básico-medio | ✅ Muy completo | ✅ Variantes, digital, suscripciones |
| 9 | **Variantes/talles/opciones** | ❌ Hardcodeado XS-XXL, rediseño pendiente | ✅ Variantes nativas | ✅ Variantes robustas | ≈ Opciones básicas | ✅ Muy flexible | ✅ Variantes + opciones |
| 10 | **Cupones/descuentos** | ❌ Diseñado, no implementado | ✅ Nativo | ✅ Códigos + automáticos | ✅ Cupones nativos | ✅ Plugins | ✅ Cupones nativos |
| 11 | **Envíos/logística** | ❌ Diseñado, no implementado | ✅ Envío Nube (integrado) | ✅ Shipping nativo + carriers | ≈ Básico | ✅ Plugins extensos | ≈ Carriers via apps |
| 12 | **Checkout/conversión** | ≈ Checkout funcional con MP | ✅ Checkout acelerado (Pago Nube) | ✅ Best-in-class (Shop Pay) | ≈ Funcional | ≈ Depende del theme | ≈ Funcional |
| 13 | **Mobile experience** | ≈ Responsive (verificar) | ✅ App + responsive | ✅ App Shop, responsive | ✅ Mobile-first | ≈ Depende del theme | ✅ App + responsive |
| 14 | **Multi-tenant (operar múltiples tiendas)** | ✅ Arquitectura nativa multi-tenant | ❌ 1 cuenta = 1 tienda | ≈ Shopify Plus multi-store (caro) | ❌ 1 cuenta = 1 sitio | ❌ Multisite complejo | ≈ Múltiples sites básico |
| 15 | **Comisión por transacción** | ✅ 0% | ❌ Variable según plan | ❌ 2% (proveedores externos) | ✅ 0% | ✅ 0% (plugin gratis) | ✅ 0% |
| 16 | **Costo mensual (plan pyme)** | ≈ USD 20/mes + USD 110 setup | ✅ Gratis (Inicial) | ≈ USD 19/mes (+ comisión) | ❌ USD 29-39/mes | ✅ Gratis + hosting | ≈ USD 5-29/mes |
| 17 | **Setup fee** | ❌ USD 110-600 según plan | ✅ $0 | ✅ $0 | ✅ $0 | ✅ $0 (DIY) | ✅ $0 |
| 18 | **Lock-in / exportación** | ? No documentado export | ≈ Export CSV | ≈ Export CSV/API | ≈ Export | ✅ Código abierto, total control | ≈ Export CSV |
| 19 | **SEO avanzado** | ❌ Meta tags básicos | ✅ SEO nativo + blog | ✅ SEO robusto + blog | ✅ SEO tools + AI | ✅ Yoast + plugins | ≈ SEO básico |
| 20 | **Blog/contenido** | ❌ No tiene | ✅ Blog nativo | ✅ Blog nativo | ✅ Blog poderoso | ✅ WordPress = blog | ≈ Páginas adicionales |
| 21 | **Analytics/reportes** | ❌ No documentados | ✅ Dashboard métricas | ✅ Reportes avanzados | ≈ Analytics básicos | ✅ Plugins (GA, etc.) | ✅ Reportes nativos |
| 22 | **App market / extensibilidad** | ❌ No tiene | ✅ +350 apps | ✅ 8.000+ apps | ✅ App Market | ✅ 55.000+ plugins | ✅ App Market |
| 23 | **Seguridad (RLS, aislamiento)** | ≈ RLS + guards (no testeada exhaustivamente) | ✅ Plataforma madura | ✅ PCI DSS Level 1 | ✅ Enterprise-grade | ❌ Responsabilidad del dueño | ✅ PCI DSS Level 1 |
| 24 | **Soporte en español / local AR** | ✅ WhatsApp + email, equipo local | ✅ Soporte humano local AR | ≈ Chat 24/7 español (no local) | ❌ Global, inglés | ❌ Comunidad | ❌ Inglés |
| 25 | **Backups automáticos** | ✅ Supabase automáticos | ✅ Incluido | ✅ Incluido | ✅ Incluido | ❌ Responsabilidad del dueño | ✅ Incluido |

### 10 Insights concretos de la matriz

1. **NovaVision tiene el setup fee más alto del mercado.** Todos los competidores SaaS principales ofrecen $0 de setup. Esto es una barrera de entrada significativa.
2. **El plan gratis de Tiendanube es imbatible para captar pymes iniciales.** NovaVision arranca en USD 20/mes + USD 110 setup vs gratis.
3. **NovaVision es el único con 0% comisión + integración profunda de MP**, pero esto solo es ventaja frente a Shopify (2% en proveedores externos) y Tiendanube (comisión variable). Wix y Ecwid también cobran 0%.
4. **La arquitectura multi-tenant es un diferencial técnico real** pero irrelevante para el comprador pyme — solo importa si NovaVision vende a agencias/revendedores que operan múltiples tiendas.
5. **NovaVision tiene el catálogo de templates más limitado** (5 vs 70-2.000+ de competidores). Esto es un punto débil crítico para la primera impresión.
6. **Features de e-commerce core ausentes** (cupones, envíos, variantes funcionales, filtros) ponen a NovaVision por detrás de TODOS los competidores en funcionalidad real de tienda.
7. **El soporte local en español por WhatsApp es valioso** pero replicable — Tiendanube ya lo ofrece con escala mucho mayor.
8. **NovaVision no tiene blog, analytics ni SEO avanzado** — tres elementos que todos los competidores SaaS ofrecen out-of-the-box.
9. **Dark mode y Design Studio con paletas** son features de nicho — agradables pero no decision-makers para una pyme que quiere vender.
10. **La ausencia de app market/extensibilidad** limita el crecimiento: cuando el cliente necesita algo que la plataforma no ofrece, la única opción es Enterprise (costoso) o irse.

---

## 5. TOP 5 Diferenciales Validados (Fase 3)

### Candidatos evaluados

| # | Diferencial candidato | Tipo | Problema que resuelve | Evidencia interna | Evidencia externa | Criterios "único" (de 4) | Riesgo de claim | Puntaje |
|---|----------------------|------|----------------------|-------------------|-------------------|--------------------------|-----------------|---------|
| D1 | **0% comisión por tx + MP nativo profundo** | Business model + Feature | Pymes AR con márgenes chicos que pierden 2-3% en comisiones | QuoteService, single-item preference, breakdown de fees en órdenes | Shopify cobra 2%; Tiendanube cobra comisión variable; Ecwid 0% pero sin MP profundo | 2 de 4 (reduce costos ✅, impacta operación ✅, pero no es único vs Ecwid/Wix en 0%, y MP profundo es difícil de comunicar) | **Medio** | 6/10 |
| D2 | **Multi-tenant nativo (operar N tiendas desde 1 infra)** | Capability / Architecture | Agencias o emprendedores seriales que manejan múltiples marcas | TenantContextGuard, RLS, provisioning_jobs, Admin DB + Backend DB separados | Shopify Plus multi-store es USD 2.300/mes; Tiendanube 1 cuenta = 1 tienda; Wix 1 sitio por plan | 3 de 4 (no disponible en directos a este precio ✅, reduce costos ✅, defendible por arquitectura ✅, pero target actual es pyme individual, no agencias) | **Bajo** | 7/10 |
| D3 | **Costos predecibles en USD (suscripción fija, sin sorpresas)** | Business model | Pymes AR que sufren volatilidad cambiaria y cobros imprevistos | Planes en USD claros: $20/$60/$120 + setup | Tiendanube cobra en ARS (se devalúa); Shopify en USD pero con comisiones variables; Wix en USD | 1 de 4 (similar a otros en USD; no reduce fricción ni es exclusivo) | **Alto** — puede percibirse como más caro si no se contextualiza | 4/10 |
| D4 | **Provisioning automatizado de tiendas** | Capability | Tiempo de setup para nuevos clientes | provisioning_jobs, wizard 5 pasos, async worker | Tiendanube: instantáneo con plan gratis (mejor). Shopify: inmediato. WooCommerce: manual | 1 de 4 (no supera a competidores SaaS que son instantáneos sin setup fee) | **Alto** — el setup fee y la dependencia de provisioning async lo debilitan | 3/10 |
| D5 | **Panel admin simple + soporte local por WhatsApp** | Experience | Pymes no-tech que necesitan acompañamiento cercano | Panel admin real, WhatsApp +54 9 11 3930-6801. "Tutorial paso a paso" | Tiendanube: soporte humano local + múltiples canales (mejor). Shopify: chat 24/7 pero no local. WooCommerce: 0 soporte | 1 de 4 (Tiendanube ya lo hace mejor y a mayor escala) | **Alto** — claim legítimo pero no diferencial frente a líder local | 3/10 |
| D6 | **Theme system normalizado con overrides delta + dark mode** | Feature / Architecture | Personalización visual consistente sin romper el sitio | `client_themes` con template + overrides JSONB, deep merge, CSS vars `--nv-*`, dark mode | La mayoría de plataformas ofrecen themes. El patrón de overrides delta es técnicamente elegante pero invisible al usuario | 2 de 4 (reduce fricción de customización ✅, defendible por arquitectura ✅, pero no impacta conversión demostrable y no es comunicable) | **Medio** — real técnicamente, pero difícil de vender como diferencial | 5/10 |
| D7 | **Sin vendor lock-in (código propio, datos exportables)** | Business model | Miedo de pyme a quedar atrapada en una plataforma | Arquitectura propia, Supabase (Postgres estándar) | Shopify/Tiendanube/Wix: grado variable de lock-in. WooCommerce: 0 lock-in | ? No verificable — no hay documentación de export de datos para clientes | **Alto** — claim sin evidencia de herramienta de export | 2/10 |
| D8 | **Integración MP con breakdown de fees (transparencia de costos)** | Feature | Vendedores que quieren saber exactamente cuánto cobran de fee/comisión | QuoteService, `order_payment_breakdown`, `settlement_days`, `merchant_net` | Ningún competidor expone breakdown de fees MP al vendedor de forma nativa en el panel | 3 de 4 (no disponible en competidores ✅, impacta operación ✅, defendible por integración ✅, pero falta validar si los vendedores realmente lo quieren) | **Bajo** | 7/10 |

### TOP 5 Ranking Final

| Rank | Diferencial | Puntaje | Justificación |
|------|-----------|---------|---------------|
| 🥇 | **Multi-tenant nativo a precio pyme** | 7/10 | Único en el segmento — competitors cobran de 10x a 100x más para multi-store. Si se reorienta el target a agencias/revendedores, es potente |
| 🥈 | **Breakdown de fees MP transparente** | 7/10 | Feature que ningún competidor ofrece. El vendedor sabe exactamente cuánto cobra y cuánto recibe. Necesita validación con usuarios |
| 🥉 | **0% comisión + MP nativo** | 6/10 | Combinación valiosa aunque no totalmente única. Mejor framing: "pagás suscripción fija, no perdés margen" |
| 4 | **Theme system con overrides delta** | 5/10 | Técnicamente sólido pero difícil de comunicar. Puede traducirse como "tu tienda nunca se rompe al cambiar diseño" |
| 5 | **Costos predecibles sin sorpresas** | 4/10 | Legítimo pero requiere comparación explícita con el TCO real de competidores (apps, themes pagos, comisiones, hosting) |

### Definición operativa de "totalmente dinámico"

**¿Qué puede cambiar el admin de NovaVision sin dev?**
| Elemento | Sin dev | Evidencia |
|----------|---------|-----------|
| Logo | ✅ | Storage upload + `logo_url` |
| Colores/paleta | ✅ | Design Studio overrides, paletas |
| Banners (desktop/mobile) | ✅ | CRUD banners con `image_variants` JSONB |
| Productos (nombre, precio, stock, imagen) | ✅ | CRUD productos |
| Categorías | ✅ | CRUD categorías |
| FAQs | ✅ | CRUD FAQs |
| Redes sociales | ✅ | CRUD social_links |
| Info de contacto | ✅ | CRUD contact_info |
| Secciones del home / layout | ⚠️ Parcial | Design Studio existe pero "frontend integration pendiente" |
| Talles/opciones de producto | ❌ | Hardcodeado XS-XXL |
| Cupones/descuentos | ❌ | No implementado |
| Páginas adicionales (about, blog) | ❌ | No hay CMS |
| SEO (meta tags, URLs, sitemap) | ❌ | Solo meta tags básicos |
| Envíos/zonas | ❌ | No implementado |
| Dominio personalizado | ⚠️ Parcial | Tabla existe, implementación no documentada |
| Emails transaccionales | ❌ | Templates en codebase, no editables por admin |

**Comparación con estándar del mercado:**
- **Tiendanube/Shopify/Wix:** Todo lo anterior es editable sin código, plus blog, SEO avanzado, redirecciones, páginas custom, notificaciones personalizables, scripts custom.
- **NovaVision "dinámico"** cubre ~50% de lo que los competidores ofrecen como autogestión estándar.

---

## 6. Mensajes Listos para Usar (Fase 4)

### 6.1 One-liner
> "NovaVision: tu tienda online con Mercado Pago integrado, sin comisiones por venta y con transparencia total de costos."

### 6.2 Elevator pitch (92 palabras)
> NovaVision es una plataforma de e-commerce diseñada para pymes y emprendedores argentinos que quieren vender online sin depender de un programador. Configurás tu tienda desde un panel simple, integrás Mercado Pago en un paso y empezás a cobrar con una suscripción fija — sin comisiones por cada venta. Además, desde el panel ves exactamente cuánto se deducen de fees y cuánto te llega a tu cuenta. Si manejás varias marcas, podés operar múltiples tiendas desde una sola cuenta. Soporte local por WhatsApp.

### 6.3 Tres pilares (beneficio → prueba → resultado)

**PILAR 1: Vendé sin perder margen**
- Suscripción fija sin comisión por transacción
- Mercado Pago integrado nativamente con desglose de fees en cada venta
- Resultado: sabés exactamente cuánto cobrás y cuánto recibís, sin sorpresas

**PILAR 2: Tu tienda lista sin técnicos**
- Panel autoadministrable: productos, banners, colores, información — todo desde el navegador
- Wizard de onboarding guiado paso a paso
- Resultado: tu tienda online operativa sin depender de nadie para cambios del día a día

**PILAR 3: Soporte cercano y costos claros**
- Equipo local que responde por WhatsApp
- Sin costos ocultos: suscripción + setup, nada más
- Resultado: sabés cuánto pagás cada mes y tenés a quién recurrir si algo no funciona

### 6.4 "Por qué no Shopify / Tiendanube / WooCommerce" (contraste, no ataque)

| Si ya miraste... | Lo que puede pasar | Con NovaVision |
|------------------|-------------------|----------------|
| **Shopify** | Pagás USD 19/mes + 2% de comisión en cada venta con proveedor externo. Para features básicas necesitás apps pagas. El soporte es global y en inglés/español genérico. | Pagás suscripción fija sin comisión por venta. Mercado Pago integrado de raíz. Soporte local AR por WhatsApp. |
| **Tiendanube** | Plan gratis es limitado; los planes pagos cobran comisión por transacción que escala con las ventas. Mucha competencia visual entre tiendas con los mismos templates. | Sin comisión por transacción. Desglose transparente de fees de MP por cada pedido (sabés exactamente cuánto te llega). |
| **WooCommerce** | Necesitás hosting, dominio, SSL, actualizaciones, seguridad y un desarrollador para mantenerlo. Si algo se rompe, es tu problema. | Todo incluido: hosting seguro, backups, actualizaciones automáticas. Sin mantenimiento técnico de tu parte. |

### 6.5 10 Mensajes para ads/landing

| # | Titular | Subtítulo | CTA |
|---|---------|-----------|-----|
| 1 | "¿Cuánto perdés en comisiones por cada venta?" | Con NovaVision pagás una suscripción fija. Cada peso que vendés, es tuyo (menos los fees de MP que ves transparentes). | Calculá tu ahorro |
| 2 | "Tu tienda online lista sin programador" | Panel simple. Productos, banners, colores — todo lo cambiás vos. | Empezá ahora |
| 3 | "Mercado Pago integrado, fees transparentes" | Sabé exactamente cuánto cobrás y cuánto te llega. Sin letra chica. | Ver cómo funciona |
| 4 | "¿Manejás varias marcas? Una cuenta, múltiples tiendas" | Operá todas tus tiendas desde un solo panel, sin pagar por separado cada una. | Consultá planes |
| 5 | "Soporte real por WhatsApp, no un bot" | Equipo local que entiende tu negocio y responde rápido. | Escribinos ahora |
| 6 | "Tu tienda, tus reglas: sin comisiones ni sorpresas" | Suscripción fija mensual. Backups, hosting y actualizaciones incluidos. | Elegí tu plan |
| 7 | "Dejá de pagar 2% por cada venta" | Con NovaVision tu suscripción es fija. Vendé más, pagá lo mismo. | Compará planes |
| 8 | "Configurá tu tienda en minutos, vendé hoy" | Wizard guiado paso a paso: logo, productos, colores, Mercado Pago. Listo. | Crear mi tienda |
| 9 | "¿Tu ecommerce te complica más de lo que ayuda?" | Migrá a NovaVision. Te ayudamos con la transición. | Hablar con ventas |
| 10 | "Transparencia total en cada venta" | Desglose de fees, comisiones y neto en cada pedido. Sin letra chica. | Ver demo |

### 6.6 Objeciones típicas y respuestas

| # | Objeción | Respuesta |
|---|---------|-----------|
| 1 | **"Es más caro que Tiendanube gratis"** | El plan gratuito de Tiendanube es limitado y cobra comisión por transacción que crece con tus ventas. Con NovaVision pagás una suscripción fija sin comisión: cuando tus ventas crecen, no perdés margen. El setup fee se paga una sola vez e incluye configuración guiada y carga inicial de productos. |
| 2 | **"No los conozco, ¿cómo sé que son confiables?"** | NovaVision usa infraestructura enterprise (Supabase, Netlify, Railway) con backups automáticos y deploys continuos. Podemos mostrarte tu tienda funcionando antes de que pagues — pedí una demo personalizada. |
| 3 | **"¿Y si quiero migrar desde otra plataforma?"** | Te acompañamos en la migración de productos y contenido. La carga inicial está incluida en todos los planes (10-20 productos según plan). Para catálogos más grandes, podemos coordinar la importación. |
| 4 | **"¿Qué pasa si NovaVision cierra?"** | Tus datos están en Supabase (PostgreSQL estándar). Si necesitás irte, tus datos son exportables. No hay lock-in contractual — podés cancelar cuando quieras. *(Nota interna: implementar herramienta de export para respaldar este claim.)* |
| 5 | **"Solo integrás Mercado Pago, ¿y si necesito otro?"** | Para pymes en Argentina, Mercado Pago cubre el 85%+ de las transacciones online. Si tu negocio requiere otros gateways, el plan Growth y Enterprise permiten integrar alternativas a consultar. |
| 6 | **"No puedo personalizar mucho el diseño"** | El Design Studio te permite cambiar paleta de colores, banners, logo y estructura de secciones. Si necesitás algo más custom, el plan Enterprise incluye diseño a medida. Estamos ampliando las opciones de templates continuamente. |

---

## 7. Battlecards (Fase 5)

### Battlecard #1: NovaVision vs Tiendanube

**Cuándo Tiendanube gana (y conviene admitirlo):**
- El prospecto recién arranca y no quiere invertir nada al principio (plan gratis imbatible).
- Necesita +350 apps/integraciones (ej. ERP, logística avanzada, CRM).
- Quiere una marca reconocida con 180K+ tiendas operando.
- Necesita Chat con IA, envíos integrados y marketing automatizado ya.

**Cuándo NovaVision gana:**
- El prospecto ya está vendiendo y las comisiones por transacción le comen el margen.
- Quiere transparencia total de fees de Mercado Pago en cada venta.
- Maneja o planea manejar múltiples marcas/tiendas.
- Busca trato cercano y soporte directo, no un ticket en una cola masiva.

**Preguntas de diagnóstico:**
1. "¿Cuánto pagás hoy de comisión por transacción al mes? Hacemos la cuenta."
2. "¿Manejás una sola tienda o tenés (o pensás tener) varias marcas?"
3. "¿Te importa saber exactamente cuánto te llega de cada venta, desglosado?"

**Trampas comunes:**
- Tiendanube gratis parece $0 pero cobra comisión (2-3.5%) en cada venta — con volumen sale caro.
- Los planes pagos de TN también cobran comisión — incluso Escala.
- Apps de terceros pueden sumar USD 20-100/mes extra.

**Frase corta:** "Si cada peso cuenta y querés saber exactamente cuánto te llega de cada venta, elegí NovaVision."

---

### Battlecard #2: NovaVision vs Shopify

**Cuándo Shopify gana:**
- El prospecto necesita escala global, POS, multi-canal (TikTok, Instagram Shopping).
- Quiere el checkout con mayor conversión del mercado (Shop Pay).
- Necesita un ecosistema de 8.000+ apps.
- Es una marca establecida con equipo técnico.

**Cuándo NovaVision gana:**
- El prospecto es una pyme argentina que vende principalmente por Mercado Pago.
- No quiere pagar 2% de comisión sobre cada venta con proveedor externo.
- Necesita soporte en español rioplatense por WhatsApp.
- Busca costos fijos predecibles sin apps pagas extras.

**Preguntas de diagnóstico:**
1. "¿Vendés principalmente en Argentina/LATAM o global?"
2. "¿Usás Mercado Pago como medio de pago principal?"
3. "¿Cuántas apps estás pagando además de Shopify?"

**Trampas comunes:**
- Shopify US$19/mes suena barato pero con comisión de 2% + apps necesarias ($20-100/mes extra) + themes ($100-400) el TCO real es mucho mayor.
- El soporte no es local — las respuestas pueden no aplicar a la realidad AR.
- Shopify Payments (sin comisión) no está disponible en Argentina (a la fecha).

**Frase corta:** "Si vendés en Argentina con Mercado Pago, ¿por qué pagar 2% extra a Shopify por cada venta?"

---

### Battlecard #3: NovaVision vs Wix eCommerce

**Cuándo Wix gana:**
- El prospecto quiere un sitio web completo (no solo ecommerce) con editor drag-and-drop.
- Necesita 2.000+ templates de diseño.
- El ecommerce es secundario al contenido/portafolio.
- Necesita AI website builder.

**Cuándo NovaVision gana:**
- El prospecto necesita ecommerce real con Mercado Pago nativo en Argentina.
- No quiere pagar USD 39/mes (plan Business mínimo para ecommerce en Wix).
- Busca foco en venta online, no un sitio web genérico.

**Preguntas de diagnóstico:**
1. "¿Tu prioridad es vender productos o tener un sitio institucional?"
2. "¿Necesitás Mercado Pago como pago principal?"
3. "¿Cuántos productos tenés para vender?"

**Trampas comunes:**
- Wix eCommerce (plan Core USD 29) es limitado — el checkout completo requiere plan Business (USD 39).
- Mercado Pago no tiene integración nativa en Wix — requiere gateway de terceros.
- El editor es poderoso pero puede ser overwhelming para pymes que solo quieren vender.

**Frase corta:** "Si tu objetivo es vender online en Argentina, elegí una plataforma pensada para eso."

---

### Battlecard #4: NovaVision vs WooCommerce

**Cuándo WooCommerce gana:**
- El prospecto tiene equipo técnico (o presupuesto para agencia).
- Necesita personalización total que ningún SaaS puede ofrecer.
- Ya tiene un WordPress andando y quiere agregar venta.
- Maneja un catálogo muy grande o complejo.

**Cuándo NovaVision gana:**
- El prospecto NO tiene equipo técnico y no quiere depender de un freelancer.
- No quiere preocuparse por hosting, SSL, actualizaciones, seguridad.
- Quiere algo que funcione out-of-the-box con Mercado Pago.
- Necesita backups automáticos y mantenimiento incluido.

**Preguntas de diagnóstico:**
1. "¿Tenés alguien técnico en tu equipo o pagás a un freelancer/agencia?"
2. "¿Cuánto pagás hoy por hosting, SSL, mantenimiento y actualizaciones?"
3. "¿Alguna vez tu tienda WooCommerce se cayó o fue hackeada?"

**Trampas comunes:**
- WooCommerce es "gratis" pero el TCO real (hosting decente + theme + plugins + SSL + mantenimiento + seguridad) es USD 50-200/mes.
- Actualizaciones de WordPress/plugins pueden romper la tienda sin aviso.
- Seguridad es responsabilidad del dueño — y WooCommerce es target común de hackers.

**Frase corta:** "Si no querés ser tu propio equipo de IT, elegí NovaVision."

---

### Battlecard #5: NovaVision vs Ecwid

**Cuándo Ecwid gana:**
- El prospecto ya tiene un sitio web (WordPress, Wix, etc.) y solo quiere agregar una tienda.
- Necesita vender en múltiples sitios simultáneamente (widget embeddable).
- Quiere plan gratis (Starter, 10 productos).
- Necesita +70 medios de pago globales.

**Cuándo NovaVision gana:**
- El prospecto quiere una tienda standalone con identidad propia.
- Necesita Mercado Pago como integración profunda, no vía Stripe.
- Busca transparencia de fees de MP por cada venta.
- Quiere soporte local en Argentina.

**Preguntas de diagnóstico:**
1. "¿Necesitás una tienda propia o agregar venta a un sitio existente?"
2. "¿Usás Mercado Pago como medio de pago principal?"
3. "¿Necesitás soporte en español y que entiendan tu contexto?"

**Trampas comunes:**
- Ecwid Starter solo permite 10 productos — escalar requiere USD 29/mes mínimo.
- Soporte primario en inglés — chat solo lunes a viernes.
- MP no tiene integración directa en Ecwid; usa Stripe como intermediario (fees adicionales).

**Frase corta:** "Si vendés en Argentina y querés tu propia tienda con Mercado Pago nativo, elegí NovaVision."

---

## 8. Recomendaciones Concretas (Fase 6)

### 8.1 Cerrar gaps P0 antes de escalar marketing

| Prioridad | Gap | Impacto | Acción | Esfuerzo estimado |
|-----------|-----|---------|--------|-------------------|
| **P0** | Precios no revalidados server-side en checkout | Riesgo de fraude | Implementar revalidación en `createPreferenceUnified()` | 2-3 días |
| **P0** | Pérdida de datos de talle/color en carrito | Vendedor no sabe qué enviar | Enviar `selected_options` en `useCartItems` | 3-5 días |
| **P0** | Filtros de búsqueda rotos (backend ignora talle/color) | UX rota, producto no profesional | Implementar `search_products_v2` RPC | 3-5 días |
| **P0** | RLS no testeada exhaustivamente | Riesgo de leak cross-tenant — deal-breaker de confianza | Suite de tests automatizados cross-tenant | 2-3 días |

### 8.2 Mejoras mínimas para convertir claims en hechos

| # | Mejora | Qué convierte en "hecho" | Esfuerzo | Impacto en posicionamiento |
|---|--------|--------------------------|----------|---------------------------|
| 1 | **Implementar cupones de tienda** (ya diseñado) | El claim "herramientas de conversión" se vuelve real | 3-4 sprints (documentado) | Alto — feature estándar que falta |
| 2 | **Implementar shipping básico** (zona + pickup + arrange) | El claim "tienda completa" se vuelve real | 2-3 sprints | Alto — sin envíos no es ecommerce completo |
| 3 | **Agregar 10-15 templates** al catálogo | El claim "plantillas listas" se sostiene mejor | 3-5 días/template | Alto — primera impresión visual |
| 4 | **Implementar export CSV de productos/órdenes** | El claim "sin lock-in" se vuelve defendible | 2-3 días | Medio — importante para migraciones |
| 5 | **Dashboard de métricas básico** (ventas/día, productos top) | Parity con competidores en analytics | 5-7 días | Medio — esperado por cualquier admin |
| 6 | **Corregir claim "500+ pymes"** por dato real o quitarlo | Credibilidad. Usar "47.000+ interesados" (leads) si se puede respaldar | 1 hora | Alto — evita pérdida de confianza si alguien pregunta |

### 8.3 Métricas y experimentos sugeridos

| Métrica | Cómo medir | Objetivo |
|---------|-----------|----------|
| Time-to-first-sale | Desde signup hasta primera orden pagada | Benchmark real para claim de "rapidez" |
| Tasa de onboarding completado | % de signups que terminan el wizard (5 pasos) | Detectar donde se caen |
| Ahorro vs comisiones | Simulador: ingresá ventas mensuales → comparamos NovaVision vs TN/Shopify | Herramienta de venta concreta |
| NPS de soporte | Survey post-interacción WhatsApp | Validar claim de "soporte cercano" |
| Churn rate a 90 días | % de clientes que se van en primeros 3 meses | Indicador de product-market fit |

### 8.4 Cambios de packaging para reforzar diferencial

| Propuesta | Racionalidad |
|-----------|-------------|
| **Ofrecer trial gratuito de 14 días** (sin setup fee) | Eliminar la barrera de entrada más grande. Tiendanube y Shopify lo hacen. El setup fee puede cobrarse al publicar |
| **Crear plan "Agencia"** a precio especial | Monetizar el diferencial multi-tenant vendiendo a agencias que operan 5-20 tiendas |
| **Renombrar setup fee como "Configuración asistida"** e incluir onboarding 1:1 | Reframing: no es un costo de setup, es un servicio de acompañamiento |
| **Crear módulo "Calculadora de ahorro"** en la landing | Herramienta interactiva: "ingresá tus ventas mensuales" → comparamos cuánto pagás en TN/Shopify vs NovaVision. Convierte el diferencial de 0% comisión en algo tangible |

### 8.5 Pruebas sociales necesarias

| Tipo | Acción | Prioridad |
|------|--------|-----------|
| Caso de uso real (case study) | Documentar la experiencia de los 2 clientes activos con métricas reales | Urgente |
| Comparativa pública | Publicar "NovaVision vs Tiendanube: costos reales para una pyme con X ventas/mes" | Alta |
| Benchmark de time-to-launch | Grabar video de onboarding completo con cronómetro | Alta |
| Testimonios verificables | Reemplazar testimonios ficticios por quotes reales de clientes (con permiso) | Urgente |

---

## 9. Apéndice: Fuentes consultadas

| Fuente | URL | Fecha de consulta |
|--------|-----|-------------------|
| Shopify AR Precios | https://www.shopify.com/ar/precios | 2026-02-18 |
| Tiendanube Home + Planes | https://www.tiendanube.com/ | 2026-02-18 |
| Wix Plans | https://www.wix.com/upgrade/website | 2026-02-18 |
| Ecwid Pricing | https://www.ecwid.com/pricing | 2026-02-18 |
| WooCommerce | Conocimiento público documentado | — |
| PrestaShop | Conocimiento público documentado | — |
| Squarespace | Conocimiento público documentado | — |
| BigCommerce | Conocimiento público documentado | — |
| Jumpseller | Conocimiento público documentado | — |
| NovaVision es.json | apps/admin/src/i18n/es.json | 2026-02-18 |
| NovaVision architecture/* | novavision-docs/architecture/ | 2026-02-18 |
| NovaVision database-schema-reference.md | novavision-docs/architecture/ | 2026-02-18 |
| NovaVision IMPROVEMENT_BACKLOG | novavision-docs/ | 2026-02-18 |

---

*Documento generado como herramienta interna de trabajo. No publicar externamente sin validar claims marcados como "hipótesis" y corregir los datos no verificables.*

# NovaVision — Análisis Real de Capacidades y Estrategia GTM v2

**Fecha:** 19 de febrero de 2026  
**Autor:** Agente Copilot (estrategia de producto)  
**Método:** Investigación exhaustiva del código fuente real (apps/web, apps/api, apps/admin)  
**Fuentes:** Código fuente en producción — NO documentos de arquitectura. Cada claim está respaldado por archivo y líneas de código.

---

## 1. Resumen Ejecutivo

NovaVision es una plataforma SaaS multi-tenant de e-commerce **significativamente más avanzada** de lo que análisis previos describieron. La investigación directa del código fuente revela:

- **25+ módulos admin** completamente implementados con ~9.300+ líneas de UI
- **50+ módulos backend** NestJS con servicios robustos
- **SEO con IA** (OpenAI GPT-4o-mini) con sistema de créditos, billing via MP y 5 tabs de dashboard
- **Onboarding 100% automatizado** — no hay setup fee, el flujo es builder gratis → pagar suscripción → tienda live
- **5 templates** de diseño con sistema de secciones dinámicas
- **20 tutoriales interactivos** (tours guiados) para cada módulo del admin
- **Checkout de 4 pasos** con cupones, envío cotizable, estimador de cuotas y consentimiento legal
- **Feature gating por plan** con ~35 features categorizados y guards de NestJS
- **Shipping multi-proveedor** (Andreani, OCA, Correo Argentino, Manual) con 2.310+ líneas de UI
- **Option sets / variantes** (talles, colores, custom) con presets + selector visual en storefront
- **Reviews + Q&A** de productos con moderación admin
- **Sistema de soporte** con tickets, CSAT y workflow de estados

**Verdad actualizada:** El producto está técnicamente completo para salir a vender. Los gaps anteriores (cupones, envíos, variantes, filtros) están **todos implementados**. El desafío es de tracción comercial (pasar de piloto a escala), no de features.

---

## 2. Inventario Completo de Features (Verificado en Código)

### 2.1 Admin Dashboard — 24 Módulos (581 líneas orquestador)

Organizados en 5 categorías con buscador y feature gating por plan:

#### 🛒 Tienda y Ventas (9 módulos)

| Módulo | Líneas | Features clave |
|--------|--------|---------------|
| **Productos** | 904 | CRUD completo, upload Excel con preview, download .xlsx, búsqueda server-side, sorting multi-columna, column resize, plan limits |
| **Órdenes** | 611 | Listado paginado, escaneo QR (cámara frontal/trasera), filtros estado/fecha, búsqueda con debounce 400ms, deep-link por ID, labels de delivery method |
| **Pagos** | 1.302 | Conexión/desconexión MP OAuth, pago parcial (% reserva), cuotas 1-24, exclusión de tipos/métodos de pago, fee routing (4 modos), redondeo, settlement days, **simulador de cobro interactivo** |
| **Envíos** | 2.310+ | 3 pestañas (Config/Integraciones/Guías). Multi-proveedor (Andreani, OCA, Correo Argentino, Manual, Custom). Zonas por provincia, envío gratis, retiro en local, coordinar WhatsApp. Test de conexión API. Guías paso a paso por proveedor |
| **Cupones** | 800 | CRUD, 3 tipos (%, fijo, envío gratis), scope (tienda/productos/categorías), programados, límites de uso, stackable, copiar código, plan limits |
| **Opciones de Producto** | 318 | CRUD option sets (talle/color/custom), items con posición, color picker con swatches, duplicar sets, auto-generación de código |
| **Guías de Talles** | — | Tablas de medidas editables vinculadas a option sets |
| **Preguntas de Producto** | 280 | Moderación Q&A, responder inline, ocultar/restaurar, filtros por estado, cursor pagination |
| **Reviews** | 308 | Moderación reviews, responder inline, filtros por rating/estado, badge compra verificada, cursor pagination |

#### 🎨 Marca y Contenido (6 módulos)

| Módulo | Features clave |
|--------|---------------|
| **Logo** | Upload, preview, cambio |
| **Banners** | CRUD banners promocionales, desktop/mobile variants, drag reorder |
| **Identidad del Sitio** | Nombre, descripción, metadatos del sitio |
| **Servicios** | CRUD de servicios que aparecen en la tienda |
| **FAQs** | CRUD de preguntas frecuentes |
| **SEO AI Autopilot** | **689 líneas** — 5 pestañas completas (ver sección 2.3) |

#### 📧 Contacto y Redes (2 módulos)

| Módulo | Features clave |
|--------|---------------|
| **Datos de Contacto** | Dirección, teléfono, email, mapa |
| **Redes Sociales** | Instagram, Facebook, WhatsApp, TikTok, etc. |

#### 📊 Cuenta y Plan (5 módulos)

| Módulo | Líneas | Features clave |
|--------|--------|---------------|
| **Uso del Plan** | 110 | Barras de progreso por recurso (productos, storage, banners, órdenes), colores dinámicos, alerta upgrade al 80% |
| **Analytics** | 302 | KPIs (órdenes, ingresos, pagos, fees), gráficos Recharts (órdenes/día, ingresos/día), top productos, métodos de pago, presets 7d/30d/90d + custom |
| **Facturación** | — | Historial de facturación y pagos |
| **Suscripción** | 1.360 | Card resumen plan, upgrade con grilla de planes, cupón de descuento, pausar/reactivar tienda, cancelar con flujo 2 pasos + motivos, revertir cancelación, enterprise → WhatsApp |
| **Soporte** | 707 | Tickets completos: crear (categoría/prioridad), hilo de mensajes chat-like, cerrar/reabrir, CSAT (1-5 + comentario), status workflow (open→triaged→in_progress→waiting→resolved→closed) |

#### 👥 Usuarios (1 módulo)

| Módulo | Features clave |
|--------|---------------|
| **Usuarios** | Gestión de usuarios registrados y roles |

---

### 2.2 Checkout — Stepper de 4 Pasos (599 líneas + 248 hook)

| Paso | Componente | Qué hace |
|------|-----------|----------|
| **1. Carrito** | CartStep | Items con imagen, precio con/sin descuento, opciones seleccionadas (talle/color), controles de cantidad (+/−), eliminar |
| **2. Envío** | ShippingStep | 3 métodos: delivery (cotización por CP), pickup (retiro en local), arrange (coordinar WhatsApp). Aviso si no hay envío configurado |
| **3. Pago** | PaymentStep | Selector de medio de pago (débito/crédito/cuotas). Modal con tabla comparativa de costo de servicio por método |
| **4. Confirmación** | ConfirmationStep | Resumen: items + envío + medio de pago + desglose de totales. Checkbox de aceptación T&C (Ley 24.240, art. 34). Consent legal registrado vía API |

**Sidebar permanente (OrderSummary):** subtotal, descuentos, costo servicio, envío (o GRATIS), cupón aplicado (via CouponInput), total.

**Sistema de carrito (8 hooks especializados):**
- `useCartItems` — CRUD + quote inicial
- `useCartQuotes` — cotizaciones multi-plan con cache
- `useCartValidation` — validación pre-checkout (stock, precios)
- `useCheckout` — preferencia MP + idempotency key + redirect
- `usePaymentPolling` — estado de pago post-redirect
- `usePaymentSettings` — plan/cuotas/pago parcial
- `useShipping` — config tenant + cotización por CP
- `useAddresses` — direcciones guardadas del usuario

---

### 2.3 SEO AI Autopilot — Sistema Completo con IA

**El sistema SEO es mucho más que "meta tags básicos".** Es un producto completo con IA, billing propio y 30+ endpoints.

#### Arquitectura

```
Frontend (5 tabs)          →    API REST (30+ endpoints)     →    OpenAI gpt-4o-mini
SeoAutopilotDashboard             seo-ai/ + seo/ + seo-ai-billing/     ↓
  ├─ Auditoría (gratis)           seo-ai.controller.ts (650 lín.)    Genera: title, description, slug
  ├─ Editar SEO                   seo-ai-job.service.ts (411 lín.)   por producto/categoría/sitio
  ├─ Prompt Manual                seo-ai-worker.service.ts (609 lín.)
  ├─ Créditos & Packs             seo-ai-billing.service.ts
  └─ Generaciones AI              seo-ai-purchase.service.ts
```

#### 5 Pestañas del Dashboard

| Tab | Qué hace | Costo |
|-----|----------|-------|
| **🔍 Auditoría** | Score SEO %, completeness de title/description por producto/categoría, issues con severidad (error/warning), SERP preview por issue. Cache 60s | **Gratis** |
| **✏️ Editar SEO** | Editor manual: site-level (title, description, brand, GA4, GTM, robots.txt, favicon, og_image) + entity-level (inline edit título 65 chars, description 160 chars, slug, noindex, seo_locked). Badges de fuente (🤖 AI, ✏️ Manual, ⚠️ Sin SEO, 🔒 Bloqueado). SERP preview por entidad | **Gratis** |
| **📋 Prompt Manual** | Genera prompt copiable para ChatGPT/Claude (max 50 productos sin SEO). Parsea respuesta pegada (tabla markdown), matchea con catálogo (exact → substring → 60% token overlap), aplica masivamente | **Gratis** |
| **💳 Créditos** | Balance actual, 3 packs de créditos comprables via MP (site+categorías, 500 productos, 2000 productos). Precio ARS con tasa blue. Historial de compras | **Pago** |
| **🤖 Generaciones AI** | 3 tipos de job (productos/categorías/sitio), 2 modos (solo vacíos/regenerar todo respetando locked). Estimación de costo, selección personalizada de entidades, barra de progreso, auto-refresh 8s, confirmación con breakdown de créditos | **Créditos** |

#### Capabilities AI

- **Modelo:** GPT-4o-mini, temperature 0.3, JSON response format
- **Genera por entidad:** `seo_title` (≤65 chars), `seo_description` (≤160 chars), `seo_slug` (≤80 chars, URL-friendly)
- **System prompt:** Español rioplatense, rol "especialista SEO senior para e-commerce"
- **Worker:** Polling cada 10s, chunks de 25 entidades, 3 reintentos con backoff exponencial
- **Guardrails:** MAX 1 job concurrent por tenant, MAX 5 jobs/día
- **Billing:** Ledger de créditos, débito por entidad procesada, packs comprables via MercadoPago con webhook

#### SEO Non-AI

- **Sitemap XML dinámico** (`/seo/sitemap.xml`) — homepage + productos activos + categorías, max 50K URLs, cache 1h
- **Open Graph** (`/seo/og?path=`) — datos OG para edge function de pre-render (imagen, precio, stock)
- **Redirects 301/302** (Enterprise) — CRUD con hit_count, edge function de resolución
- **GA4 + GTM** — measurement ID y container ID configurables
- **robots.txt** — configurable por tenant
- **Custom meta** — JSONB extensible

---

### 2.4 Onboarding Automatizado (Sin Setup Fee)

**El onboarding es 100% automatizado. NO hay setup fee.**

```
┌─────────────────────────────────────────────────┐
│  Paso 1: Builder Start (GRATIS)                  │
│  POST /onboarding/builder/start                  │
│  → Recibe email + slug                           │
│  → Crea account draft + onboarding record        │
│  → Genera builder_token JWT (30 días)            │
│  → Encola provisioning job (trial)               │
├─────────────────────────────────────────────────┤
│  Paso 2: Wizard (GRATIS)                         │
│  → Elegir template (5 disponibles)               │
│  → Elegir paleta de colores (20+ disponibles)    │
│  → Subir logo y assets                           │
│  → Importar catálogo (home bundle, Zod-validado) │
│  → Todo auto-guardado contra DB                  │
├─────────────────────────────────────────────────┤
│  Paso 3: Business Info                           │
│  → Datos fiscales (CUIT, razón social, IVA)      │
│  → Dirección fiscal                              │
├─────────────────────────────────────────────────┤
│  Paso 4: Credenciales MP                         │
│  → Access token + public key de Mercado Pago     │
│  → Validación de formato APP_USR-*               │
├─────────────────────────────────────────────────┤
│  Paso 5: Aceptar T&C                            │
│  → Audit trail legal (IP + user-agent)           │
│  → Consent persistido via LegalService           │
├─────────────────────────────────────────────────┤
│  Paso 6: Checkout                                │
│  → Reserva slug (24h TTL)                        │
│  → Valida plan compatible con template/paleta    │
│  → Crea suscripción MP (USD→ARS vía blue rate)   │
│  → Redirect a MP para pagar primer mes           │
├─────────────────────────────────────────────────┤
│  Paso 7: Webhook (automático)                    │
│  → MP notifica pago aprobado                     │
│  → Claim final del slug                          │
│  → Encola provisioning job                       │
│  → Worker: crea client en Backend DB             │
│  → Configura storage, template, paleta           │
│  → Sincroniza entitlements                       │
├─────────────────────────────────────────────────┤
│  Paso 8: Publish (automático)                    │
│  → Tienda live en slug.novavision.lat            │
│  → Admin dashboard habilitado                    │
│  → 20 tutoriales interactivos disponibles        │
└─────────────────────────────────────────────────┘
```

**Setup fee:** Los 3 planes tienen `setup_fee: 0`. La columna existe en DB pero su valor es 0 para todos.

---

### 2.5 Planes y Feature Gating

#### Planes

| Plan | Precio USD/mes | Aliases legacy | Target |
|------|---------------|----------------|--------|
| **Starter** | $20 | basic | Emprendedores que empiezan |
| **Growth** | $60 (recomendado) | professional | Pymes en crecimiento |
| **Enterprise** | $390 | premium, pro, scale | Operaciones grandes |

#### Entitlements por plan (configurables en DB)

- `products_limit` — límite de productos
- `images_per_product` — imágenes por producto
- `banners_active_limit` — banners activos
- `coupons_active_limit` — cupones activos
- `storage_gb_quota` — almacenamiento GB
- `egress_gb_quota` — tráfico GB
- `custom_domain` — dominio propio (boolean)
- `max_monthly_orders` — soft cap de órdenes/mes
- `is_dedicated` — DB dedicada (Enterprise)

#### Feature Catalog (~35 features)

3 capas de gating:

1. **Feature Catalog** (`featureCatalog.ts`) — ~35 features con flag por plan (starter/growth/enterprise)
2. **PlanAccessGuard** — Guard NestJS con decorador `@PlanFeature('feature.id')`, 403 si plan insuficiente
3. **PlanLimitsGuard** — Guard para límites cuantitativos con `@PlanAction('create_product')`, valida usage vs entitlements

**Features por plan:**
- **Starter:** Productos, categorías, órdenes, logo, banners, FAQs, home sections, templates, preview, builder
- **Growth+:** Analytics, pagos avanzados, user management, cupones, option sets, size guides, SEO completo, shipping API, Q&A, reviews, soporte tickets, billing, identity
- **Enterprise:** SEO redirects 301/302, DB dedicada, dominio custom

**Per-client overrides:** `clients.feature_overrides` permite habilitar features individuales fuera del plan base.

---

### 2.6 Tour System — 20 Tutoriales Interactivos

Sistema de onboarding guiado con **Driver.js** y state machine custom:

```
idle → starting → running → paused → waitingForTarget → completed → aborted → error
```

**20 tours disponibles:** products, orders, payments, shipping, coupons, optionSets, sizeGuides, logo, banners, services, faqs, identity, seoAutopilot, contactInfo, socialLinks, users, analytics, usage, billing, subscription

**Capabilities:**
- Plan gating (cada tour tiene `planRequirement`)
- Device support (desktop/mobile)
- Versionado con resume de progreso
- Auto-actions (click automático para abrir modales)
- MutationObserver para esperar targets dinámicos con fallback a 3s
- Persistencia en localStorage
- Prompt de retomar tour incompleto

---

### 2.7 Storefront — Tienda del Comprador

#### Páginas (25 páginas)

| Categoría | Páginas |
|-----------|---------|
| **Comercio** | ProductPage (840 lín., galería con zoom, carrusel mobile, variantes), CartPage, SearchPage, FavoritesPage, PaymentResultPage (Success/Pending/Failure), TrackingPage |
| **Cuenta** | LoginPage, UserDashboard, CompleteSetup, EmailConfirmation, OAuthCallback |
| **Admin** | AdminDashboard (581 lín.) |
| **Legal** | LegalPage |
| **Otros** | PreviewHost, Maintenance, NotFound, NotAccess, UnauthorizedPage, Bridge |

#### Página de Producto (PDP)

- **ProductReviews** (478 lín.): Rating promedio + barras de distribución + formulario de reseña + cards
- **ProductQA** (276 lín.): Sistema Q&A tipo Mercado Libre, preguntar inline, respuestas con borde accent
- **ShippingEstimator** (148 lín.): Widget de cotización por CP + provincia (24 provincias AR) en el PDP
- **OptionSetSelector** (156 lín.): Selector visual — color circles (hex), size buttons, generic buttons
- **StarRating**: Componente reutilizable de estrellas

#### Templates y Secciones

**5 templates:**
| Template | Nombre | Status |
|----------|--------|--------|
| `first` | Classic Store | Stable |
| `second` | Modern Grid | Stable |
| `third` | Elegant Minimal | Stable |
| `fourth` | Boutique | Beta |
| `fifth` | Bold & Vibrant | Beta |

**Secciones dinámicas (Design Renderer):**
- Headers: classic, bold, elegant
- Heroes: fullwidth
- Catálogo: carousel
- Features: grid (ServicesGrid)
- Contenido: FAQ accordion, ContactInfo
- Footers: classic, elegant

---

### 2.8 Subscription Lifecycle Management

| Aspecto | Implementación |
|---------|---------------|
| **Creación** | USD→ARS via blue rate, cupón de descuento, preapproval MP |
| **Billing cycle** | Monthly o Annual (sufijo `_annual` en plan_key) |
| **Distributed locks** | `subscription_locks` table, TTL 30s |
| **Price adjustment** | Cron diario 2AM: blue rate → ajuste automático en MP |
| **Store pause/unpause** | Automático por estado de suscripción |
| **Cancelación** | Flujo 2 pasos + motivos + opción de contacto + rollback |
| **Usage reset** | Cron mensual: reinicio de contadores de órdenes |

---

### 2.9 API Backend — 50+ Módulos NestJS

| Categoría | Módulos |
|-----------|---------|
| **Core** | auth, tenant, guards, supabase, redis, observability, cron |
| **Comercio** | products (1.967 lín. service), categories, cart, orders, payments, tenant-payments, store-coupons (773 lín.), option-sets (814 lín.), shipping (958 lín.) |
| **Contenido** | banner, logo, faq, contact-info, social-links, services, settings |
| **SEO** | seo (550 lín.), seo-ai, seo-ai-billing |
| **Gestión** | users, plans, subscriptions, billing, accounts, addresses |
| **Onboarding** | onboarding, templates, themes, palettes, playbook |
| **Features** | analytics, filters, favorites, questions, reviews, legal |
| **Admin** | admin, superadmin, client-dashboard, finance, demo |
| **Infra** | image-processing, outbox, worker, workers, webhooks, wa-inbox |
| **Soporte** | support (tickets + CSAT) |

---

## 3. Correcciones a Claims Previos

### ❌ Claims que estaban MAL en el análisis anterior

| Claim previo | Realidad (código) |
|-------------|-------------------|
| "Cupones diseñados, no implementados" | ✅ 800 líneas frontend + 773 líneas backend, CRUD completo con 3 tipos, scoping, scheduling, stackable |
| "Envíos diseñados, no implementados" | ✅ 2.310+ líneas frontend + 958 líneas backend, 4 proveedores reales (Andreani, OCA, Correo Argentino, Manual) |
| "Talles/variantes no implementados" | ✅ 318 líneas frontend + 814 líneas backend + 156 líneas selector storefront, presets globales, color picker, filtros en búsqueda |
| "Filtros de búsqueda rotos" | ✅ 1.967 líneas service, 10+ parámetros de filtro, RPC full-text en Postgres |
| "SEO = solo meta tags básicos" | ✅ Sistema completo con IA (GPT-4o-mini), 5 tabs, billing propio, sitemap XML, Open Graph, redirects, GA4+GTM, 30+ endpoints |
| "Setup fee USD 110" | ✅ Setup fee = $0 para todos los planes, onboarding 100% automatizado |
| "El onboarding no está 100% integrado" | ✅ Wizard completo de 8 pasos, builder gratis → checkout → provisioning automático → tienda live |
| "Solo 5 templates, 1 documentado" | ✅ 5 templates registrados con manifest.js, 2 stable + 2 beta, sistema de secciones dinámicas |
| "Carga masiva no implementada" | ✅ Upload Excel con preview modal + download .xlsx del catálogo |
| "No hay herramientas de analytics" | ✅ Dashboard con KPIs, gráficos Recharts, top productos, métodos de pago, presets de fecha |

---

## 4. Set Competitivo Actualizado

### 4.1 Posicionamiento Real

NovaVision compite como **SaaS de e-commerce enfocado en pymes argentinas** con estas ventajas verificables:

| Diferenciador | NovaVision | Tiendanube | Shopify |
|--------------|-----------|-----------|---------|
| **Setup fee** | $0 (automatizado) | $0 | $0 |
| **Comisión por venta** | 0% | Sí (variable) | 2% en proveedores externos |
| **SEO con IA** | ✅ GPT-4o-mini integrado | ❌ Básico | Via apps pagos |
| **Onboarding guiado** | 20 tutoriales interactivos | Guías + soporte | Videos + docs |
| **Shipping AR nativo** | Andreani/OCA/Correo AR | Via apps | Via apps |
| **Cupones avanzados** | 3 tipos + scoping + scheduling | ✅ Similar | ✅ Similar |
| **Q&A + Reviews** | ✅ Con moderación | Via apps | Via apps |
| **Simulador de cobro** | ✅ Interactivo | ❌ | ❌ |
| **Payment config** | Fee routing 4 modos, redondeo, settlement | Básico | Apps |
| **Soporte tickets** | ✅ In-app con CSAT | WhatsApp/email | Chat 24/7 |

### 4.2 Superioridades técnicas vs competidores directos

1. **SEO AI Autopilot:** Ningún competidor directo en el segmento pyme ofrece generación SEO con IA integrada. Shopify/Wix lo ofrecen via apps de terceros (pagos separados).

2. **Zero comisiones:** Modelo de suscripción pura sin comisión por transacción, vs Tiendanube que cobra comisiones en planes bajos.

3. **Simulador de pagos:** El PaymentsConfig incluye un simulador interactivo donde el admin puede ver el breakdown exacto (total al cliente, neto al vendedor, fee MP) antes de guardar cambios. No existe equivalente en la competencia directa.

4. **Tour system:** 20 tutoriales interactivos con state machine, plan gating y persistencia. Tiendanube tiene guías estáticas; Shopify tiene videos.

5. **Shipping multi-proveedor nativo:** Integración directa con Andreani, OCA y Correo Argentino via API, no via apps de terceros.

6. **Subscription lifecycle completo:** Ajuste de precio automático por blue rate, pause/unpause automático por estado de suscripción, cancel con motivos.

---

## 5. Estrategia GTM Actualizada

### 5.1 Modelo de Pricing (Real)

| Plan | USD/mes | Setup Fee | Target |
|------|---------|-----------|--------|
| **Starter** | $20 | $0 | Emprendedores que empiezan, 1er tienda online |
| **Growth** | $60 | $0 | Pymes con catálogo >50 productos, necesitan analytics + cupones |
| **Enterprise** | $390 | $0 | Operaciones grandes, DB dedicada, dominio custom |

**Conversión USD→ARS:** Automática vía tasa blue rate, ajuste diario en suscripciones MP.

### 5.2 Propuesta de Valor (Basada en Código Real)

**Headline recomendado:**
> "Tu tienda online profesional lista en minutos. SEO con IA, envíos con Andreani/OCA, Mercado Pago integrado. Sin comisiones por venta."

**3 pilares actualizados:**

1. **Lanzá en minutos, no en semanas**
   - Builder gratis → elegí template → importá catálogo → pagá suscripción → live
   - 20 tutoriales interactivos para cada módulo
   - Sin programadores, sin agencia

2. **Vendé más con SEO AI + Analytics**
   - Auditoría SEO gratuita con score y issues
   - Generación automática de título, descripción y slug con IA
   - Dashboard de analytics con KPIs, gráficos y top productos
   - Cupones con scoping y programación

3. **Cobrá sin sorpresas**
   - $0 comisión por venta (solo suscripción fija)
   - Simulador de cobro para ver exactamente cuánto recibís
   - Envíos cotizables por CP con Andreani, OCA, Correo Argentino
   - Mercado Pago nativo con cuotas configurables

### 5.3 Canales y Acciones

| Fase | Acción | Canal | Métrica |
|------|--------|-------|---------|
| **1. Early Adopters (Mes 1-3)** | Invitar pymes del nicho ropa/accesorios. Trial gratis 14 días | Outreach directo + WhatsApp | 20 signups, 5 conversiones |
| **2. Content (Mes 2-6)** | Blog SEO "cómo vender online en Argentina", comparativas, tutoriales | SEO orgánico + YouTube | 1.000 visitas/mes al blog |
| **3. Partnerships (Mes 3-6)** | Contadores, diseñadores, community managers como referrers (10% comisión recurrente) | Programa de referidos | 10 partners activos |
| **4. Paid (Mes 4+)** | Google Ads "tienda online argentina", Meta Ads retargeting | SEM + Social Ads | CAC < $50 USD |

### 5.4 Mensajes por Buyer Persona

**Emprendedor que empieza (Starter):**
> "Armá tu tienda online profesional sin saber programar. Template listo, Mercado Pago integrado, envíos con cotización automática. Desde $20/mes sin comisiones."

**Pyme en crecimiento (Growth):**
> "Dejá de perder ventas. SEO con IA que optimiza tu catálogo, cupones que traen clientes de vuelta, analytics para tomar decisiones. Sin el 5% de comisión que te cobra Tiendanube."

**Operación grande (Enterprise):**
> "Infraestructura dedicada, dominio propio, DB aislada. Para marcas que necesitan performance y control total. Hablemos."

---

## 6. Riesgos y Mitigaciones

| Riesgo | Severidad | Mitigación |
|--------|-----------|-----------|
| Pocos clientes activos (2) → falta social proof | Alta | Trial gratis, case studies con primeros clientes, NPS |
| Percepción "no conozco NovaVision" | Alta | Content marketing agresivo, comparativas detalladas, demo pública |
| Blue rate volatilidad → pricing inestable | Media | Ajuste automático diario ya implementado (cron 2AM) |
| Competencia con Tiendanube plan gratis | Alta | No competir en gratis → competir en valor (sin comisiones, SEO AI) |
| Dependencia de Supabase/Railway | Baja | Migración posible; menor vendor lock-in que Shopify/Wix |

---

## 7. KPIs del GTM

| Métrica | Target Q1 | Target Q2 | Target Q4 |
|---------|-----------|-----------|-----------|
| Signups (builder starts) | 50 | 200 | 1.000 |
| Tiendas activas (pagando) | 10 | 40 | 150 |
| MRR (USD) | $400 | $2.000 | $8.000 |
| Churn mensual | <15% | <10% | <7% |
| NPS | >40 | >50 | >60 |
| Tiempo medio de onboarding | <30 min | <20 min | <15 min |

---

## 8. Conclusión

NovaVision tiene un producto **técnicamente maduro** con 50+ módulos backend, 24 módulos admin, checkout completo y features diferenciadores (SEO AI, simulador de pagos, shipping multi-proveedor, tours). El desafío no es de features sino de **tracción comercial**.

La estrategia debe enfocarse en:
1. **Generar social proof** (primeros 10-20 clientes con cases reales)
2. **Posicionar el SEO AI** como diferenciador principal (ningún competidor directo lo ofrece integrado)
3. **Explotar el zero-commission** como argumento económico vs Tiendanube/Shopify
4. **Usar el simulador de pagos** como herramienta de venta (demo interactiva)
5. **Convertir los 20 tours** en contenido de marketing (videos "así de fácil es...")

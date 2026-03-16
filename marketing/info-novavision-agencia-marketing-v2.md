# NovaVision — Documento Comercial y Estratégico v2

**Fecha**: 2026-03-15
**Versión**: 2.0 — Reescritura estratégica basada en auditoría de producto real
**Audiencia**: Agencia de marketing, inversores, alineación interna

---

# BLOQUE 1 — Diagnóstico del documento v1

## Qué está bien
- La estructura general (pricing → producto → ICP → embudo → tracking) es lógica y completa
- Los precios y unit economics son correctos y verificados
- El mapa de eventos de tracking es preciso y detallado
- Las respuestas a la agencia son honestas y útiles
- El ICP está bien definido (emprendedores → empresas, multi-rubro)

## Qué está desactualizado
- **SEO con IA**: El documento no menciona el módulo completo de SEO AI (auditoría, generación por IA, créditos, packs, locks manuales, scoring)
- **Addons/Store**: No menciona el Addon Store con uplifts de capacidad, packs SEO, y visual unlocks
- **Ecommerce tracking por tenant**: El sistema ahora inyecta GA4 + GTM + Meta Pixel per-tenant con eventos ecommerce reales (view_item, add_to_cart, begin_checkout, purchase)
- **Shipping**: No menciona los 3 carriers integrados (Andreani, OCA, Correo Argentino) + shipping manual con zonas y free shipping threshold
- **Reviews y preguntas**: No menciona que existen módulos de reviews y preguntas por producto
- **Favoritos**: No menciona wishlist/favoritos
- **Multi-país**: El documento dice "preparado para multi-país" sin matizar que hoy opera principalmente para Argentina con soporte parcial para 6 países más
- **8 templates + 20 paletas**: No menciona los números reales
- **ConnectionsChecklist**: Nuevo panel de conexiones con guías paso a paso para GA4, GTM, Meta Pixel, Search Console

## Qué está inflado o débil
- "Catálogo generado por IA en un click" → Parcialmente cierto. La IA genera metadata SEO y puede importar productos, pero no genera fotos ni precios reales. Es asistida, no mágica.
- "Personalización visual por IA" → La IA propone una paleta de colores basada en un prompt, pero no diseña layouts. Es un selector inteligente, no un diseñador.
- "Expansión internacional natural" → Hoy los shipping providers son argentinos (Andreani, OCA, Correo Argentino). Para otros países faltan carriers locales. El checkout y la currency sí son multi-país.
- "Panel admin completísimo" → Es sólido pero no tiene: email marketing, blog, inventario multi-sucursal, integración con ERPs, ni marketplace de apps.
- "Hoy Mercado Pago, mañana cualquier gateway" → Correcto arquitectónicamente pero hoy solo funciona con MP. No hay fecha para Stripe/PayPal.
- "Tutorial guiado en cada sección" → Existe un sistema de tours pero la cobertura no es completa en todas las secciones.

## Qué falta mencionar del sistema real
- **Módulo SEO completo**: sitemap dinámico, robots.txt custom, redirects 301/302, JSON-LD (5 schemas), canonical URLs, noindex per product, OG tags, Search Console token
- **SEO AI Autopilot**: generación por IA con GPT-4o-mini, sistema de créditos, auditoría gratuita, locks manuales, historial de generaciones
- **Addon Store**: packs SEO ($19-$99), uplifts de capacidad (+50 productos, +3 banners, etc.), visual unlocks de templates/paletas
- **Ecommerce events**: view_item, add_to_cart, begin_checkout, purchase enviados a GA4 + Meta Pixel per-tenant
- **ConnectionsChecklist**: panel que guía al admin con impacto de cada conexión + pasos para configurar
- **Cupones con múltiples modos**: porcentaje, monto fijo, mínimo de compra, fechas, límites de uso
- **Configuración avanzada de envíos**: free shipping threshold, zonas, múltiples carriers
- **Reviews y preguntas por producto**: módulos completos con CRUD
- **Favoritos/Wishlist**: implementado
- **User accounts para compradores**: registro, direcciones guardadas, historial de pedidos
- **Option sets y variantes**: talles, colores, materiales con stock independiente por variante

## Qué comparaciones con la competencia están flojas
- La comparación con Tiendanube no menciona que TN tiene plan gratuito (con 2% comisión) y Chat Nube con IA conversacional
- No menciona que Shopify tiene Shopify Magic + Sidekick (IA mucho más avanzada que NovaVision)
- No menciona Empretienda como competidor directo en el segmento micro ($8.490 ARS/mes, 0% comisión)
- No menciona que Mercado Shops cerró (oportunidad de mercado)
- Decir "somos mejores que todos" sin matizar en qué sí y en qué no debilita la credibilidad

---

# BLOQUE 2 — Nueva versión del documento

---

## 1. Qué es NovaVision

NovaVision es una plataforma de e-commerce para emprendedores y pymes de LATAM que quieren su tienda online profesional sin depender de un programador, sin pagar comisión por venta y con herramientas de inteligencia artificial para arrancar más rápido.

**En concreto:**
- Creás tu tienda en minutos con asistencia de IA
- Vendés con Mercado Pago integrado (cuotas, débito, crédito, transferencia)
- Gestionás todo desde un panel sin código
- Pagás una suscripción fija — sin comisión por venta, nunca

**Para quién es hoy:**
Emprendedores y negocios que venden (o quieren vender) productos online. Desde quien hoy opera solo por WhatsApp e Instagram hasta la empresa con local físico que necesita su canal digital propio. El nivel técnico requerido es bajo: si sabés usar redes sociales, podés administrar tu tienda en NovaVision.

---

## 2. Pricing

| Plan | Mensual (USD) | Anual (USD) | Comisión por venta |
|------|:---:|:---:|:---:|
| **Starter** | $20 | $200 | 0% |
| **Growth** | $60 | $600 | 0% |
| **Enterprise** | $390 | $3.500 | 0% |

- Cobro en ARS vía Mercado Pago al tipo de cambio del día
- Sin permanencia — cancelación inmediata sin penalidad
- Promos de lanzamiento disponibles (primer mes bonificado, descuentos por código, cupos limitados) — a definir con la agencia

**Margen bruto:** ≥76% en todos los planes. El modelo es sustentable desde las primeras 100 tiendas.

---

## 3. Qué incluye cada plan

### Starter ($20/mes)
- 1 tienda en `tutienda.novavision.lat`
- Hasta 300 productos, 200 órdenes/mes, 2 GB storage
- 1 imagen por producto, 3 banners, 6 FAQs, 3 servicios
- Mercado Pago integrado (OAuth automático)
- 8 templates seleccionables + 14 paletas de colores
- Generación de catálogo asistida por IA
- Panel admin: productos con variantes (talles, colores), categorías, pedidos, banners, FAQs, servicios, logo, redes sociales, contacto
- Reviews y preguntas por producto
- Favoritos/wishlist para compradores
- Envíos: Andreani, OCA, Correo Argentino, manual, zonas, free shipping
- SEO técnico: sitemap, robots.txt, canonical, OG tags, JSON-LD
- Soporte por email (48h SLA)

### Growth ($60/mes)
Todo lo de Starter más:
- Hasta 2.000 productos, 1.000 órdenes/mes, 10 GB storage
- 4 imágenes por producto, 8 banners, 20 FAQs, 12 servicios
- Cupones de descuento (%, monto fijo, mínimo de compra, fechas)
- Configuración avanzada de pagos: recargos por cuota, exclusión de medios, días de acreditación
- Dominio propio (custom domain)
- SEO AI Autopilot: generación de metadata por IA, auditoría SEO, locks manuales
- Tracking per-tenant: GA4, GTM, Meta Pixel con eventos ecommerce automáticos
- Google Search Console verification
- Redirects 301/302
- Panel de conexiones con guías paso a paso
- 6 paletas premium adicionales
- Soporte priorizado (24h SLA)

### Enterprise ($390/mes)
Todo lo de Growth más:
- Hasta 50.000 productos, 20.000 órdenes/mes, 100 GB storage
- 8 imágenes por producto, banners/FAQs/servicios ilimitados
- Base de datos dedicada (aislamiento total de datos)
- Desarrollos custom cotizados aparte (integraciones ERP, diseño a medida)
- SLA premium (12h) + canal de soporte directo

---

## 4. Diferenciadores reales

### Donde NovaVision ya se diferencia (verificado)

**0% comisión por venta, siempre.**
Tiendanube cobra entre 0.7% y 2% por transacción además de la suscripción. Shopify cobra 0.5%-2% si no usás Shopify Payments (que no está disponible en Argentina). NovaVision cobra solo la suscripción fija. Para una tienda que factura $500.000 ARS/mes, eso puede ser $5.000-$10.000 de ahorro mensual.

**IA para arrancar rápido.**
NovaVision usa IA (GPT-4o-mini) para dos cosas concretas: (1) generar metadata SEO de todo el catálogo automáticamente (títulos, descripciones, slugs optimizados para Google) y (2) asistir la importación de productos. No es magia — es una herramienta que reduce horas de trabajo manual a minutos. Ningún competidor LATAM-first ofrece esto nativamente.

**Mercado Pago integrado de verdad.**
No solo "aceptar pagos" — el admin configura cuotas, elige medios de pago, define quién absorbe el recargo, excluye métodos, elige días de acreditación. La conexión es por OAuth (un click), no copiando keys. Esto normalmente requiere un desarrollador.

**Revisión de calidad antes de publicar.**
Cada tienda pasa por control de calidad antes de activarse. Si falta algo, se notifica al cliente por email con lo que necesita completar. Ninguna otra plataforma de autoservicio hace esto.

**SEO técnico automático.**
Sitemap dinámico, robots.txt configurable, canonical URLs en todas las páginas, JSON-LD (Organization, WebSite, Product, Breadcrumb, ItemList), meta tags por producto/categoría, noindex configurable, redirects 301/302. El admin no necesita saber de SEO — el sistema lo resuelve.

**Tracking ecommerce per-tenant.**
Cada tienda puede tener su propio GA4, GTM y Meta Pixel. Los eventos de compra (view_item, add_to_cart, begin_checkout, purchase) se envían automáticamente. El admin solo pega su ID — no necesita configurar tags ni código.

### Donde la competencia sigue siendo más fuerte (honesto)

| Área | Competidor más fuerte | Por qué | Plan NovaVision |
|------|----------------------|---------|-----------------|
| Ecosistema de apps | Tiendanube (+100 apps), Shopify (+8.000) | NovaVision tiene Addon Store pero no marketplace de terceros | Futuro |
| IA conversacional | Tiendanube (Chat Nube), Shopify (Sidekick) | NovaVision tiene IA para SEO, no para atención al cliente | Futuro |
| Plan gratuito | Tiendanube (gratis + 2% comisión) | NovaVision no tiene plan gratuito todavía | A definir |
| Blog/content marketing | Shopify, Tiendanube | NovaVision no tiene blog integrado | Futuro |
| Multi-idioma | Shopify | NovaVision opera solo en español | Futuro |
| Personalización profunda | WooCommerce, Shopify (Liquid) | NovaVision tiene 8 templates + paletas, no CSS custom | Parcial |
| Carriers internacionales | Shopify | NovaVision tiene Andreani/OCA/Correo Argentino (Argentina) | Parcial |

### Posicionamiento recomendado hoy

NovaVision compite mejor como **"ecommerce guiado para pymes que quieren vender online sin complicarse"** — no como "competidor directo de Shopify". El diferencial real es: IA para arrancar rápido + 0% comisión + Mercado Pago bien integrado + revisión de calidad + panel intuitivo. Es el camino más corto entre "vendo por WhatsApp" y "tengo mi tienda online profesional".

---

## 5. ICP y segmentación

**Cliente ideal primario:** Emprendedor o pyme argentina que vende productos y quiere profesionalizar su canal digital. Hoy opera por WhatsApp, Instagram o local físico. Factura entre $100.000 y $5.000.000 ARS/mes. El decisor es el dueño.

**Cliente ideal secundario:** Empresa que necesita un canal e-commerce propio (B2B o D2C) con integración de Mercado Pago y panel de gestión sin depender de un desarrollador.

**Rubros:** Cualquier negocio que venda productos físicos online. Sin restricción de vertical — el sistema de variantes y la IA se adaptan a cualquier rubro. Excepciones: rubros prohibidos (armas, drogas, pharma con receta, piratería, adultos).

**Geo:** Argentina como mercado de lanzamiento. A mediano plazo: cualquier país donde opere Mercado Pago (Brasil, México, Colombia, Chile, Uruguay, Perú). El checkout ya soporta multi-moneda y multi-país. Los carriers de envío hoy son argentinos — para otros países se necesitan carriers locales.

---

## 6. Embudo y activación

**Evento de activación:** Pago de suscripción aprobado.

**Flujo:**
1. Registro (email + nombre de tienda)
2. Configuración asistida (IA genera catálogo + paleta) o manual
3. Selección de plan + pago con Mercado Pago
4. Tienda entra en revisión (24-48h)
5. Publicación o solicitud de completar lo que falta

**Lo clave:** el usuario puede pagar con solo registro + nombre de tienda. Todo lo demás se completa después o se solicita por email.

**Recovery:** Emails automáticos a las 24h, 48h y 72h para onboardings que no completaron el pago. Idempotente y configurable.

---

## 7. Tracking y data (estado real)

### Implementado y funcionando

| Componente | Estado | Detalle |
|-----------|--------|---------|
| GA4 per-tenant | **Verificado** | Script inyectado en `<head>` si el admin configura su Measurement ID |
| GTM per-tenant | **Verificado** | Script inyectado si configura Container ID |
| Meta Pixel per-tenant | **Verificado** | Script inyectado con PageView automático + eventos ecommerce |
| Eventos ecommerce | **Verificado** | view_item, add_to_cart, begin_checkout, purchase → GA4 + Meta Pixel + dataLayer |
| CTA tracking | **Verificado** | WhatsApp, Instagram, Facebook, YouTube clicks → GA4 cta_click + Meta Lead |
| CAPI server-side (plataforma) | **Verificado** | Subscribe + Purchase enviados a Meta desde el servidor cuando un cliente paga su suscripción |
| Search Console token | **Verificado** | Meta tag de verificación inyectado per-tenant |
| Consent banner | **Verificado** | Conforme a Ley 25.326 |
| Panel de conexiones | **Verificado** | Checklist con impacto, guías paso a paso, links a GA4/GTM/Pixel/Search Console/Ads |
| Validación de IDs | **Verificado** | Regex validation en frontend + backend para GA4 (G-XXX), GTM (GTM-XXX), Pixel (dígitos) |

### Pendiente de configurar (no es desarrollo)
- Crear propiedad GA4 y confirmar Pixel ID para la landing de NovaVision (novavision.lat)
- Generar Access Token de CAPI en Meta Business Manager

### No implementado todavía
- CAPI server-side per-tenant (hoy es solo para la plataforma, no para las tiendas de los clientes)
- Integración directa con Google Ads (se importan conversiones desde GA4)
- Dashboard de analytics avanzado per-tenant (hoy el admin ve pedidos, revenue, top productos)

---

## 8. Creatividades y messaging

**Assets existentes:**
- Logo y marca NovaVision
- Landing funcional (`novavision.lat`)
- Panel admin y storefront funcionales para demo/screen recording

**Piezas prioritarias:**
1. **Screen recording de la IA generando metadata SEO** — mostrar que en 1 minuto optimiza un catálogo entero para Google
2. **"$0 comisión = más ganancia"** — cálculo visual comparativo vs Tiendanube
3. **UGC founder** — "Creé NovaVision porque..." cara a cámara
4. **"Tu tienda lista en 5 minutos"** — fragmento del onboarding asistido
5. **Comparativa honesta** — NovaVision vs Tiendanube mostrando diferencias reales (comisión, IA, revisión de calidad)

**Tono:** Cercano, emprendedor, concreto. "Te ayudamos a vender más sin complicarte." Nada corporativo.

---

## 9. Plan de medios

- **Presupuesto:** USD 500/mes en Meta (escalable según resultados)
- **KPIs:** CPL (registros), CPA (pagos), activation rate (tiendas publicadas)
- **Meta 90 días:** 50-100 suscripciones pagas
- **Decisiones a definir con la agencia:** promo de lanzamiento, evento de optimización (Lead vs Purchase), landing vs registro directo

---

## 10. Operación y soporte

- **Canal:** WhatsApp + email. Llamadas solo para Enterprise o dudas de pago.
- **SLA:** Starter 48h, Growth 24h, Enterprise 12h
- **Objetivo:** 100% self-serve. El panel + IA + tours + panel de conexiones deben resolver el 90% de las dudas sin soporte humano.

---

## 11. Restricciones

**Rubros prohibidos:** Armas, drogas ilegales, pharma con receta, pornografía, estafas/MLM, falsificaciones, juegos de azar sin licencia, productos ilegales.

**Enforcement:** (1) IA detecta en onboarding, (2) revisión manual pre-publicación, (3) reportes post-publicación. Suspensión inmediata si se detecta contenido prohibido.

---

# BLOQUE 3 — Mejoras estratégicas para competir de verdad

## Qué ya está fuerte
- Core commerce (productos, variantes, checkout, MP, envíos, cupones)
- SEO técnico (sitemap, JSON-LD, canonical, robots, OG, redirects)
- SEO AI (generación, auditoría, créditos, locks)
- Tracking per-tenant (GA4, GTM, Meta Pixel, eventos ecommerce)
- Multi-país parcial (currency dinámico, 7 países en country_configs, fee tables por país)
- Onboarding asistido por IA
- Panel de conexiones con guías

## Qué está incompleto
1. **Admin analytics** — El dashboard del admin muestra pedidos y revenue pero no sesiones, conversiones, fuentes de tráfico ni funnel. El admin necesita ir a GA4 para eso.
2. **Carriers internacionales** — Solo Andreani/OCA/Correo Argentino. Para operar en Chile, México, Colombia se necesitan carriers locales.
3. **Personalización de diseño** — 8 templates + 20 paletas es bueno para empezar pero no para competir con Shopify/TN que permiten edición de código.
4. **Blog** — No existe. Es clave para content marketing y SEO orgánico.
5. **Email marketing** — Solo emails transaccionales. No hay campañas, newsletters ni automatizaciones.

## Qué falta para competir en serio (priorizado)

### Prioridad 1 — Corto plazo (impacto directo en conversión y retención)

| Gap | Por qué importa | Complejidad |
|-----|-----------------|-------------|
| **Plan gratuito o trial** | Tiendanube tiene plan gratis. Sin trial, NovaVision pierde leads que quieren probar antes de pagar. | Baja — la infra ya soporta meses gratis |
| **Blog integrado** | Sin blog no hay estrategia de content marketing. Los competidores lo tienen. | Media |
| **Email marketing básico** | Automatización post-compra (gracias, review request, cross-sell) y newsletter. Sin esto, la retención depende 100% del admin. | Alta |
| **Dashboard analytics mejorado** | Que el admin vea sesiones, conversion rate y fuentes sin salir del panel. Aunque sea conectando GA4 API. | Media |

### Prioridad 2 — Mediano plazo (diferenciación y escalabilidad)

| Gap | Por qué importa | Complejidad |
|-----|-----------------|-------------|
| **Marketplace de apps/integraciones** | Tiendanube tiene +100 apps, Shopify +8.000. NovaVision necesita al menos 10-20 integraciones clave (ERP, contabilidad, logística, marketing). | Alta |
| **IA conversacional** | Chat Nube de Tiendanube resuelve +70% de consultas. Un chatbot IA en la tienda sería diferencial fuerte. | Alta |
| **Carriers por país** | Para vender en Chile/México/Colombia se necesitan integraciones con carriers locales. | Media por país |
| **Más templates y personalización** | Section editor más flexible, más templates, posibilidad de CSS custom para Growth+. | Media |
| **Guest checkout** | Hoy se requiere cuenta para comprar. El guest checkout reduce fricción de conversión. | Baja |

### Prioridad 3 — Largo plazo (enterprise y global)

| Gap | Por qué importa |
|-----|-----------------|
| **Stripe/PayPal** | Para operar fuera de LATAM o con clientes que prefieren otro gateway |
| **Multi-idioma** | Para tiendas con público internacional |
| **API pública** | Para integraciones custom de Enterprise |
| **POS (punto de venta)** | Para negocios con local físico + online |
| **Inventario multi-sucursal** | Para Enterprise con múltiples depósitos |

---

# BLOQUE 4 — Tabla de Claims

| Claim | Estado | Evidencia | Ajuste |
|-------|--------|-----------|--------|
| "0% comisión por venta" | **Verificado** | Modelo de suscripción fija, sin % sobre transacciones | Mantener — es el diferencial #1 |
| "Catálogo generado por IA en un click" | **Parcial** | La IA genera metadata SEO y asiste importación de productos. No genera fotos ni precios. | Reformular: "Metadata SEO generada por IA" + "importación asistida" |
| "Personalización visual por IA" | **Parcial** | La IA propone paleta de colores, no diseña layouts | Reformular: "Paleta de colores sugerida por IA" |
| "Panel admin completísimo" | **Verificado** | Productos, variantes, categorías, pedidos, banners, FAQs, servicios, cupones, envíos, pagos, SEO, tracking | Mantener pero no decir "completísimo" — decir "panel de gestión completo" |
| "Mercado Pago integrado de verdad" | **Verificado** | OAuth, cuotas, exclusión de medios, recargos, días de acreditación | Mantener — es diferencial real |
| "Revisión de calidad antes de publicar" | **Verificado** | Flujo de revisión con estados (awaiting_review → published / changes_requested) | Mantener — ningún competidor lo hace |
| "Tutorial guiado en cada sección" | **Parcial** | Existe sistema de tours pero no cubre todas las secciones | Reformular: "Tours guiados en las secciones principales" |
| "Expansión internacional natural" | **Parcial** | Checkout multi-moneda OK. Carriers solo Argentina. Admin wizard hardcoded AR. | Reformular: "Checkout multi-país. Carriers disponibles hoy: Argentina" |
| "Hoy MP, mañana cualquier gateway" | **Futuro** | Arquitectura preparada pero solo MP implementado | Reformular: "Integración nativa con Mercado Pago" — no prometer otros gateways |
| "Tu tienda lista en 5 minutos" | **Parcial** | La configuración básica con IA toma ~5 min, pero la tienda no está "lista" — entra en revisión 24-48h | Reformular: "Configuración inicial en 5 minutos. Publicación en 24-48h post-revisión" |
| "Preview con datos demo" | **Verificado** | Templates se previsualizan con datos de ejemplo durante onboarding | Mantener |
| "Sin permanencia" | **Verificado** | Cancelación inmediata, sin penalidad, sin reembolso del período pagado | Mantener |
| "Soporte por plan con SLA" | **Verificado** | 48h Starter, 24h Growth, 12h Enterprise | Mantener |
| "CAPI server-side" | **Verificado** (plataforma) | Meta CAPI envía Subscribe/Purchase para suscripciones de NV, no para las tiendas | Aclarar que es para la plataforma, no per-tenant |
| "Tracking per-tenant con eventos ecommerce" | **Verificado** | GA4 + Meta Pixel + GTM con view_item, add_to_cart, begin_checkout, purchase | Nuevo claim — agregar al documento |
| "3 carriers de envío integrados" | **Verificado** | Andreani, OCA, Correo Argentino + manual | Nuevo claim — agregar |
| "SEO AI con auditoría y generación" | **Verificado** | GPT-4o-mini, créditos, locks, historial, scoring | Nuevo claim — agregar |
| "Addon Store con uplifts de capacidad" | **Verificado** | Packs SEO, +productos, +banners, +imágenes, +FAQs, +servicios | Nuevo claim — agregar |
| "Reviews y preguntas por producto" | **Verificado** | Módulos completos con CRUD | Nuevo claim — agregar |
| "Favoritos/wishlist" | **Verificado** | Implementado para compradores autenticados | Nuevo claim — agregar |

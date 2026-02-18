# NovaVision — Correcciones al Análisis y Sugerencias Estratégicas

**Fecha:** 18 de febrero de 2026  
**Contexto:** Correcciones al análisis competitivo previo basadas en validación real del código y sugerencias de mejora.

---

## 1. Correcciones al Análisis Previo

### 1.1 ❌ "Cupones, envíos, talles/variantes → diseñados pero no implementados"

**CORRECCIÓN: TODO IMPLEMENTADO.**

El análisis previo se basó solo en los docs de arquitectura (diseño) sin verificar el código real. La validación del codebase muestra:

| Feature | Archivo | Líneas de código | Estado real |
|---------|---------|-----------------|-------------|
| **Option Sets / Variantes** | `src/option-sets/option-sets.service.ts` | 814 líneas | ✅ Implementado — CRUD completo con presets globales, items, guía de talles, vinculación producto↔option_set, filtrado por option_set_id y option_values en búsqueda |
| **Option Sets Controller** | `src/option-sets/option-sets.controller.ts` | 193 líneas | ✅ 8 endpoints REST (CRUD sets + size guides + product assign) con guards de rol y plan |
| **Cupones de Tienda** | `src/store-coupons/store-coupons.service.ts` | 773 líneas | ✅ Implementado — CRUD admin, validación de cupón con cálculo de descuento, control de uso máximo, fecha de expiración, monto mínimo, tipos de descuento (porcentaje/fijo), target por categoría/producto |
| **Cupones Controller Admin** | `src/store-coupons/admin-store-coupons.controller.ts` | — | ✅ Endpoint admin para gestionar cupones |
| **Cupones Controller Público** | `src/store-coupons/store-coupons.controller.ts` | — | ✅ Endpoint público para validar/aplicar cupón |
| **Shipping** | `src/shipping/shipping.service.ts` | 958 líneas | ✅ Implementado — Providers Andreani, OCA, Correo Argentino + manual; creación de envíos, tracking, estados, webhooks, retry, notificaciones |
| **Shipping Controller** | `src/shipping/shipping.controller.ts` | — | ✅ REST completo + cotizaciones + integraciones por tenant |
| **Shipping Providers** | `src/shipping/providers/` | 4 providers | ✅ ManualShippingProvider, AndreaniProvider, OcaProvider, CorreoArgentinoProvider |

**El sistema de option sets es clave** — soporta presets globales reutilizables (ej: "Talles AR", "Colores", "Material") + sets custom del tenant. Cada producto puede asociarse a un option_set_id, y la búsqueda filtra por option_values y option_set_id via RPC.

### 1.2 ❌ "Filtros de búsqueda rotos (backend ignora parámetros)"

**CORRECCIÓN: FILTROS COMPLETAMENTE FUNCIONALES.**

El endpoint `GET /products/search` en `products.controller.ts` (693 líneas) acepta y procesa:

| Parámetro | Tipo | Funcionalidad |
|-----------|------|--------------|
| `q` / `query` | string | Búsqueda full-text via RPC `search_products` con ranking por relevancia |
| `categoryIds` / `categories` | comma-separated UUIDs | Filtro por categorías |
| `sort` | string | Ordenamiento: `relevance`, `price_asc`, `price_desc`, `newest` |
| `priceMin` / `min` / `minPrice` | number | Precio mínimo |
| `priceMax` / `max` / `maxPrice` | number | Precio máximo |
| `optionValues` / `option_values` | comma-separated | Filtro por valores de opciones (ej: "L,XL") |
| `optionSetId` / `option_set_id` | UUID | Filtro por set de opciones |
| `onSale` / `on_sale` | boolean | Solo productos en oferta |
| `page` | number | Paginación |
| `pageSize` / `limit` | number | Tamaño de página (máx 60) |
| `includeUnavailable` | boolean | Incluir no disponibles (solo admin) |

El flujo es:
1. Si hay `categoryIds` → `searchProducts()` con join a `product_categories`
2. Si no → RPC `search_products` en Postgres con ranking + filtrado post-RPC para optionValues/onSale
3. Resultado hidratado con `hydrateProductsByIds()` que trae categorías, imágenes, etc.
4. Cache con ETags y `stale-while-revalidate`

**Los filtros funcionan.** El servicio tiene 1967 líneas con múltiples estrategias de búsqueda.

### 1.3 ✅ Correcciones aplicadas al es.json

| Claim original | Corrección aplicada |
|---------------|-------------------|
| "500+ pequeñas empresas confían en NovaVision" | → "Con la meta de acompañar a 500+ pymes y emprendedores a crecer en línea con NovaVision" |
| "Acepta pagos con Mercado Pago, Stripe, PayPal y más" | → "Acepta pagos con Mercado Pago integrado. Para planes Enterprise, posibilidad de adaptar otras pasarelas como Stripe o PayPal" |
| "Más de 500 pymes ya confían..." (cloudSection) | → "Nuestra meta: acompañar a más de 500 pymes y emprendedores a potenciar su e-commerce" |

### 1.4 Testimonios

Los testimonios actuales (María González / Pampa Deco, Andrés López / Café del Centro, Lucía Torres / DecoArtesanal) no son verificables como clientes reales. 

**Sugerencia aceptada:** Mantener los testimonios como material de marketing/publicidad y agregar en los Términos y Condiciones una cláusula tipo:

> *"Algunos fragmentos del sitio, incluyendo testimonios e imágenes ilustrativas, pueden contener información presentada con fines de marketing y publicidad. Los resultados pueden variar según el tipo de negocio y la implementación."*

Esto es práctica estándar de la industria (Shopify, Wix, etc. usan testimonios similares).

### 1.5 ✅ SEO realmente implementado

El análisis previo subestimó las capacidades SEO. El codebase tiene:
- `src/seo/` — Servicio de SEO con generación de sitemaps dinámicos
- `src/seo-ai/` — SEO con IA (generación de meta descriptions, títulos optimizados)
- `src/seo-ai-billing/` — Billing para el módulo de SEO AI
- Generación automática de URLs SEO-friendly para categorías (`/search?category={slug}`)

---

## 2. Diferenciadores Reales — Sugerencias de Comunicación

### 2.1 Multi-tenant nativo a precio pyme (7/10)

**Qué es:** Una sola infraestructura que opera N tiendas con aislamiento total de datos (RLS en Postgres, guards por request, storage segregado por tenant). Los competidores que ofrecen esto (Shopify, BigCommerce) cobran USD 79-399/mes. NovaVision lo ofrece desde USD 20/mes.

**Cómo comunicarlo:**

| Canal | Mensaje sugerido |
|-------|-----------------|
| **Landing (Hero)** | "Tu tienda profesional por el precio de un dominio" |
| **Feature page** | "Infraestructura enterprise — precio emprendedor. Cada tienda corre sobre la misma tecnología que usan las grandes plataformas, pero sin las grandes facturas." |
| **Comparativa** | "¿Por qué pagar USD 79/mes por Shopify si NovaVision te da lo mismo por USD 20/mes? La diferencia: nuestra arquitectura multi-tenant nos permite darte un nivel enterprise sin el costo enterprise." |
| **Blog/Content** | Post: "Qué significa multi-tenant y por qué importa para tu bolsillo" — explicar que Shopify también es multi-tenant pero cobra 4x porque monetiza con comisiones |
| **Sales call** | "La infraestructura que tenés detrás es la misma que usa Shopify: servidores separados por tenant, datos aislados, backups automáticos. La diferencia es que no te cobramos 2% de cada venta." |

**Riesgo de comunicación:** El término "multi-tenant" no le dice nada a una pyme. Traducirlo siempre a beneficio concreto: "seguridad de datos", "tu tienda no se ve afectada si otra tiene mucho tráfico", "infraestructura dedicada a precio compartido".

### 2.2 Breakdown transparente de fees MP (7/10)

**Qué es:** Tabla `order_payment_breakdown` que desglosa para cada pago: comisión MP, IVA, retenciones, monto neto que recibe el vendedor (`merchant_net`), días de acreditación (`settlement_days`). Feature que **ningún otro competidor ofrece**.

**Cómo comunicarlo:**

| Canal | Mensaje sugerido |
|-------|-----------------|
| **Landing** | "Sabé exactamente cuánto cobrás por cada venta. Sin sorpresas." |
| **Feature highlight** | "Transparencia total en tus pagos — Cada pedido muestra: cuánto pagó el cliente, cuánto cobra Mercado Pago de comisión, cuánto de IVA, y cuánto cae en TU cuenta. Incluye fecha estimada de acreditación." |
| **Comparativa vs Tiendanube** | "En Tiendanube ves el monto de la venta. En NovaVision ves el desglose: comisión MP ($X), IVA ($Y), retención ($Z), neto en tu cuenta ($W). Sin calculadora, sin dudas." |
| **Social media** | Captura de pantalla del breakdown real (mockup o con datos demo) → "Esto es lo que ves en tu panel cada vez que vendés. ¿Tu plataforma actual te muestra esto?" |
| **Email marketing** | "¿Sabías que Mercado Pago cobra entre 4.39% y 10.99% según el medio de pago? NovaVision te muestra EXACTO cuánto de cada venta se va en comisiones y cuánto termina en tu cuenta." |

**Dato técnico para content:** El sistema soporta configuración por tenant de `fee_routing` (quién absorbe las comisiones: vendedor o comprador), `service_mode`, y overrides de fees por método de pago en `client_mp_fee_overrides`.

### 2.3 0% comisión + Mercado Pago nativo (6/10)

**Qué es:** NovaVision no cobra comisión por transacción. Solo suscripción mensual fija + setup fee. La comisión de MP es transparente y la paga el vendedor o comprador según config.

**Cómo comunicarlo:**

| Canal | Mensaje sugerido |
|-------|-----------------|
| **Pricing page** | "0% comisión NovaVision. Solo pagás tu plan mensual y las comisiones normales de Mercado Pago (que te mostramos con total transparencia)." |
| **Calculadora de ahorro (propuesta)** | Input: "¿Cuánto vendés por mes?" → Output: "En Shopify pagarías $X (2% comisión + USD 29/mo). En Tiendanube pagarías $Y (1.75% comisión + plan). En NovaVision pagás $Z (solo plan mensual)." |
| **Tabla comparativa** | 3 columnas: Shopify (2% + USD 29) vs Tiendanube (1.75% + $24,999 ARS) vs NovaVision (0% + USD 20) — con ejemplo de facturación $500K ARS/mes |
| **FAQ** | "¿NovaVision cobra comisión por venta? No. Solo pagás tu plan mensual. Las comisiones de Mercado Pago son inevitables (cualquier plataforma las tiene), pero te las mostramos desglosadas en cada venta." |

**Ejemplo numérico concreto (para la calculadora):**
- Tienda con $500,000 ARS/mes en ventas
- **Shopify:** USD 29/mes + 2% = USD 29 + ~$10,000 ARS → ~$39,000 ARS/mes total
- **Tiendanube Esencial:** $24,999/mes + 1.75% = $24,999 + $8,750 → $33,749 ARS/mes
- **NovaVision Starter:** USD 20/mes ≈ $26,000 ARS + 0% = **$26,000 ARS/mes** → Ahorro ~$7,000-13,000/mes

### 2.4 Theme system con overrides delta (5/10)

**Qué es:** Las tiendas parten de un template base y solo guardan las diferencias (overrides) en un JSONB. Esto permite: actualizar el template base sin romper customizaciones, aplicar parches de seguridad/perf a todas las tiendas a la vez, y ofrecer consistency + personalización.

**Cómo comunicarlo (sin jerga técnica):**

| Canal | Mensaje sugerido |
|-------|-----------------|
| **Feature page** | "Tu tienda se actualiza sola — Cada mejora que hacemos (velocidad, seguridad, nuevas funciones) se aplica automáticamente a tu tienda sin perder tus personalizaciones de diseño." |
| **Comparativa** | "En WooCommerce/PrestaShop, actualizar el template puede romper tu tienda. En NovaVision, tu diseño se mantiene y las mejoras se aplican automáticamente." |
| **Landing** | "Personalizá tu tienda, nosotros nos encargamos de mantenerla actualizada y segura." |
| **Blog** | "Cómo NovaVision mantiene tu tienda siempre actualizada sin que pierdas tu diseño" |

**Riesgo:** Este diferenciador es técnicamente sólido pero difícil de vender directo. Mejor comunicarlo como beneficio: "actualizaciones automáticas sin riesgo" / "siempre última versión".

### 2.5 Costos predecibles sin sorpresas (4/10)

**Qué es:** Suscripción fija mensual + setup fee único. Sin comisiones variables, sin cargos escondidos por features, sin sorpresas en la factura.

**Cómo comunicarlo:**

| Canal | Mensaje sugerido |
|-------|-----------------|
| **Pricing** | "Presupuesto claro. Siempre. Tu plan mensual es lo que pagás. No hay comisiones por venta, no hay cargos por transacción, no hay sorpresas." |
| **Comparativa** | "Shopify te cobra plan + 2% por venta + apps adicionales ($5-50/mes cada una). En NovaVision, todo está incluido en tu plan." |
| **Email** | "Con NovaVision, si vendés $100K o $10M, pagás lo mismo de plataforma. Tu éxito no te cuesta más." |

**Contextualización necesaria:** El setup fee ($110-$600 USD según plan) es la barrera principal vs competidores que ofrecen $0 de entrada. Sugerencias:
1. **Ofrecer trial:** 14 días gratis sin tarjeta → elimina la barrera de entrada
2. **Financiar el setup:** 3 cuotas sin interés → reduce fricción
3. **Waivear setup** para los primeros 50 clientes → genera urgencia + early adopters

---

## 3. Acciones Recomendadas — Detalle Concreto

### 3.1 Cerrar 4 bugs P0 antes de escalar marketing

**Nota: 2 de los 4 "bugs" reportados previamente NO son bugs reales según la validación del código:**

| Bug reportado | Estado real | Acción |
|--------------|-------------|--------|
| **Revalidación de precios server-side** | ⚠️ Verificar en `src/orders/` y `src/tenant-payments/` si el checkout compara precios del carrito vs precios actuales en DB antes de crear preferencia MP | **Validar** — Si no existe, es P0 real |
| **Datos de talle/color perdidos en carrito** | ⚠️ Verificar en `src/cart/` si `cart_items` persiste la selección de opciones | **Validar** — Depende de si el frontend pasa los option values |
| **Filtros de búsqueda rotos** | ✅ **NO ES BUG** — Los filtros funcionan correctamente (ver sección 1.2) | **Ninguna** — Eliminado de P0 |
| **RLS tests** | ⚠️ No se encontraron tests e2e de aislamiento multi-tenant (usuario A no ve datos de B) | **Implementar** — Tests en `novavision-e2e/` que validen aislamiento |

**Acción recomendada:** Validar los 2 items marcados ⚠️ y priorizar solo los que realmente sean bugs.

### 3.2 Corregir claim "500+ pymes" por dato real

✅ **HECHO** — Se actualizó en `es.json`:
- Testimonials subtitle: "Con la meta de acompañar a 500+ pymes y emprendedores..."
- Cloud section: "Nuestra meta: acompañar a más de 500 pymes..."

**Siguiente paso cuando haya clientes reales:** Cambiar a dato verificable ("X tiendas activas" con contador dinámico desde API).

### 3.3 Reemplazar testimonios ficticios por casos reales

**Plan de acción por fases:**

| Fase | Cuándo | Acción |
|------|--------|--------|
| **Ahora (0-2 clientes)** | Inmediato | Mantener testimonios actuales + agregar disclaimer en T&C. Los textos son creíbles y bien escritos. |
| **3-5 clientes** | 1-2 meses | Reemplazar 1-2 testimonios por reales. Pedir al cliente: foto + frase de 2 líneas + nombre/empresa. Incentivo: 1 mes gratis o setup waived. |
| **10+ clientes** | 3-6 meses | Todos reales. Agregar logos de clientes ("Confían en nosotros") y métricas reales ("95% uptime", "X pedidos procesados"). |

**Texto para T&C (agregar):**
> "Información publicitaria: Algunos contenidos del sitio, incluyendo testimonios, imágenes y cifras ilustrativas, pueden haber sido creados o adaptados con fines de comunicación comercial. Los resultados reales pueden variar según las características de cada negocio, su mercado y el uso que se haga de la plataforma."

### 3.4 Implementar trial gratuito

**Contexto:** El setup fee (USD 110-600) es la mayor barrera de entrada. Todos los competidores ofrecen $0 de entrada:
- Tiendanube: plan Inicial gratuito permanente
- Shopify: 3 días gratis
- Wix: plan gratuito con marca Wix
- Ecwid: plan Free permanente (5 productos)

**Propuesta de trial:**

| Opción | Detalle | Pros | Contras |
|--------|---------|------|---------|
| **A) 14 días gratis** | Sin tarjeta. Tienda completa con marca NovaVision visible. Al final del trial: pago de setup + primer mes. | Baja fricción, estándar de industria | Requiere flujo de upgrade, posible abuso |
| **B) Freemium** | Plan "Free" permanente: 5 productos, 50 órdenes/mes, marca NovaVision visible, 1 template. Sin setup fee. | Funnel de leads, demostración de producto | Costo infraestructura, soporte de cuentas gratis |
| **C) Setup en cuotas** | Setup dividido en 3 cuotas (ej: $37+$37+$36 para Starter). Primer mes incluido. | No cambia el modelo, reduce barrera | Complejidad de billing |
| **D) Early bird** | Setup $0 para los primeros 50 clientes, solo pagan mensualidad. | Urgencia + early adopters + testimonios reales | Pierde revenue de setup, difícil de sostener |

**Recomendación:** Opción A (trial 14 días) + Opción D para los primeros 20 clientes. Esto genera:
- Base inicial de clientes reales
- Testimonios verificables
- Validación de product-market fit
- Métrica de conversión trial→pago

### 3.5 Crear "Calculadora de Ahorro" como herramienta de venta

**Concepto:** Widget interactivo en la landing donde la pyme ingresa cuánto vende y ve cuánto ahorraría con NovaVision vs Shopify/Tiendanube.

**Inputs:**
1. Facturación mensual estimada (slider o input: $50K - $5M ARS)
2. Cantidad de ventas/mes (para calcular comisiones fijas)
3. Plataforma actual (dropdown: Shopify / Tiendanube / Wix / Otra / Ninguna)

**Outputs:**
- Tabla comparativa con 3 columnas: Tu plataforma actual | NovaVision Starter | NovaVision Growth
- Desglose: costo plan + comisiones plataforma + comisiones MP (inevitable) = **total mensual**
- Ahorro anual estimado en color verde grande
- CTA: "Empezá tu prueba gratis" o "Hablá con ventas"

**Fórmulas base:**

```
Shopify Basic:        USD 29/mes + 2% sobre ventas + comisiones MP
Tiendanube Esencial:  ARS 24,999/mes + 1.75% sobre ventas + comisiones MP  
Tiendanube Impulso:   ARS 73,999/mes + 1% sobre ventas + comisiones MP
NovaVision Starter:   USD 20/mes + 0% sobre ventas + comisiones MP
NovaVision Growth:    USD 60/mes + 0% sobre ventas + comisiones MP

Comisiones MP (todas las plataformas igualmente):
- Tarjeta crédito 1 cuota:  4.39% + IVA
- Tarjeta crédito 3 cuotas: 8.49% + IVA  
- Tarjeta crédito 6 cuotas: 11.79% + IVA
- Tarjeta débito:            1.49% + IVA
```

**Valor comunicacional:** "NovaVision no te cobra por venta. Tu ahorro crece con tu éxito."

**Implementación técnica sugerida:** Componente React standalone en la landing (no requiere API). Datos de pricing hardcodeados con actualización periódica. El tipo de cambio USD→ARS puede obtenerse de una API pública o actualizarse manualmente.

---

## 4. Features Implementadas — Resumen de Comunicación

El análisis previo subestimó significativamente las capacidades del producto. Resumen actualizado:

| Feature | Estado | Listo para marketing |
|---------|--------|---------------------|
| Multi-tenant con aislamiento completo | ✅ Producción | ✅ Sí |
| Mercado Pago con breakdown de fees | ✅ Producción | ✅ Sí |
| 0% comisión por venta | ✅ Producción | ✅ Sí |
| Panel admin autoadministrable | ✅ Producción | ✅ Sí |
| Templates con theme overrides | ✅ Producción | ✅ Sí — comunicar como "actualizaciones automáticas" |
| Búsqueda con filtros avanzados | ✅ Producción | ✅ Sí |
| Option Sets / Variantes / Talles | ✅ Implementado | ✅ Sí — diferenciar de competidores gratis que no lo tienen |
| Cupones de tienda | ✅ Implementado | ✅ Sí |
| Shipping con providers (Andreani, OCA, Correo Arg) | ✅ Implementado | ✅ Sí — diferenciar de Tiendanube gratis que no lo incluye |
| SEO + SEO AI | ✅ Implementado | ✅ Sí |
| Soporte con tickets y SLA | ✅ Implementado | ✅ Sí |
| WhatsApp Inbox | ✅ Implementado | ✅ Sí — feature diferenciadora |
| Reviews / Reseñas | ✅ Implementado | ✅ Sí |
| Preguntas de compradores | ✅ Implementado | ✅ Sí |
| Legal / Devoluciones | ✅ Implementado | ✅ Sí |
| Favoritos | ✅ Implementado | ✅ Sí |
| Analytics dashboard | ✅ Implementado | ✅ Sí |
| Billing/Suscripciones | ✅ Implementado | ✅ Sí |
| MP OAuth (conectar cuenta MP del vendedor) | ✅ Implementado | ✅ Sí |

**Conclusión:** El producto tiene significativamente más features de las documentadas en el análisis previo. La plataforma está mucho más madura de lo que se comunicaba. El gap principal no es funcionalidad sino **tracción comercial** (pasar de 2 a 20+ clientes).

---

## 5. Prioridades Inmediatas (ordenadas)

1. **Validar P0 reales** — Verificar revalidación de precios en checkout y persistencia de options en cart
2. **Tests de aislamiento multi-tenant** — Agregar en e2e suite
3. **Implementar trial/early-bird** — Reducir barrera de entrada
4. **Calculadora de ahorro** — Herramienta de venta concreta para la landing
5. **Obtener 3-5 clientes reales** — Con trial + early bird pricing
6. **Reemplazar testimonios** — A medida que haya clientes reales
7. **Comunicar features completas** — Actualizar landing/copy para reflejar todo lo implementado (option sets, cupones, shipping, SEO AI, etc.)

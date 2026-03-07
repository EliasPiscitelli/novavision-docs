# Plan: Tenant Admin Addon Store V1

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Rama base: feature/automatic-multiclient-onboarding / feature/multitenant-storefront
- Repos involucrados: API (templatetwobe), Admin (novavision), Web (templatetwo), Docs

## 1. Objetivo

Definir un store de addons para tenant admins que permita comprar capacidades y servicios desde el panel de cliente, usando Mercado Pago como checkout directo cuando corresponda, sin desarmar la escalera comercial entre Starter, Growth y Enterprise.

La referencia funcional y técnica existente es el sistema de packs SEO AI ya implementado.

## 2. Base ya existente

### 2.1 Piezas reutilizables verificadas

- `addon_catalog` ya existe en Admin DB como catálogo base de addons.
- `nv_billing_events` ya modela compras one-time con estado, provider, metadata y external reference.
- `seo_ai_credits` ya demuestra un patrón completo de compra con ledger consumible.
- `FxService` ya resuelve precio base USD hacia moneda local por país.
- `PlansService.getClientEntitlements()` ya soporta `plan base + entitlement_overrides`, que es la forma correcta de aplicar upgrades persistentes.

### 2.2 Decisión estratégica

No conviene vender todo como tokens.

Hay 3 familias distintas:

1. Consumibles: se compran y se agotan. Ejemplo: créditos SEO AI.
2. Servicios one-time: se pagan una vez y generan una entrega puntual. Ejemplo: carga inicial o revisión manual.
3. Uplifts mensuales: aumentan límites permanentes mientras el cliente los paga. Ejemplo: más productos, más banners o más storage.

Los uplifts mensuales no deben quedar modelados como compra eterna. Deben impactar el MRR del cliente y apagarse si el adicional deja de pagarse.

## 3. Reglas comerciales

### 3.1 Starter

- Puede comprar consumibles.
- Puede comprar servicios one-time.
- No debería poder comprar uplifts estructurales permanentes del storefront en V1.
- Si en el futuro se habilita un uplift para Starter, debe ser mensual, con tope bajo y con precio cercano al salto a Growth.

### 3.2 Growth

- Puede comprar consumibles.
- Puede comprar servicios one-time.
- Puede comprar uplifts mensuales moderados.
- Los uplifts deben tener techo por familia para evitar que Growth se convierta en Enterprise por acumulación desordenada.

### 3.3 Enterprise

- Puede comprar consumibles y servicios puntuales.
- Los cambios estructurales grandes deben quedar en flujo asistido o cotización manual.
- No conviene abrir un store libre para capacidades críticas de infraestructura.

## 4. Catálogo inicial propuesto

### 4.1 Lanzamiento V1

| Addon key | Tipo | Billing | Planes | Precio base | Qué entrega |
|-----------|------|---------|--------|-------------|-------------|
| `seo_ai_pack_50` | consumible | one_time | starter, growth, enterprise | USD 19 | 50 créditos SEO AI |
| `seo_ai_pack_250` | consumible | one_time | starter, growth, enterprise | USD 69 | 250 créditos SEO AI |
| `seo_ai_pack_1000` | consumible | one_time | starter, growth, enterprise | USD 199 | 1000 créditos SEO AI |
| `service_import_assisted_100` | servicio | one_time | starter, growth, enterprise | USD 79 | carga asistida de hasta 100 productos |
| `service_publish_review` | servicio | one_time | starter, growth, enterprise | USD 29 | revisión manual previa a publicación |
| `service_theme_setup` | servicio | one_time | starter, growth, enterprise | USD 49 | ajuste visual guiado o seteo inicial |
| `growth_products_boost_250` | uplift | monthly | growth | USD 12/mes | +250 productos |
| `growth_products_boost_1000` | uplift | monthly | growth | USD 35/mes | +1000 productos |
| `growth_banners_boost_3` | uplift | monthly | growth | USD 9/mes | +3 banners activos |
| `growth_storage_boost_5gb` | uplift | monthly | growth | USD 8/mes | +5 GB storage |
| `growth_images_boost_3` | uplift | monthly | growth | USD 10/mes | +3 imágenes por producto |

### 4.2 Backlog razonable

| Addon key | Tipo | Billing | Estado | Nota |
|-----------|------|---------|--------|------|
| `ai_copy_pack_small` | consumible | one_time | futuro | si se expone IA de copy fuera de SEO |
| `service_catalog_cleanup` | servicio | one_time | futuro | limpieza manual de catálogo |
| `service_seo_manual_audit` | servicio | one_time | futuro | servicio experto complementario |
| `growth_coupon_boost_25` | uplift | monthly | futuro | si cupones pasa a monetizarse en Growth |
| `growth_support_priority` | uplift | monthly | futuro | requiere definir SLA y operación |

## 5. Qué no vender como addon libre

No conviene vender libremente en self-serve:

- DB dedicada.
- Dominio custom como feature aislada si sigue siendo parte central del salto de plan.
- Overrides grandes de productos o storage para Starter.
- Cualquier uplift que acerque demasiado al valor Enterprise sin revisión manual.
- Cambios estructurales complejos de plataforma o branding premium si forman parte del diferencial del plan superior.

## 6. Pricing y escalera comercial

### 6.1 Referencia de planes

- Starter: USD 20/mes
- Growth: USD 60/mes
- Enterprise: USD 390/mes

### 6.2 Regla de pricing para uplifts

Los uplifts mensuales deben respetar esta regla:

1. La suma de uplifts activos no debe acercar al cliente a capacidades cercanas al siguiente plan por menos del 70% del gap de precio.
2. Si el uplift acumulado supera ese umbral, el sistema debe sugerir upgrade de plan en vez de seguir vendiendo boosters.
3. Para Starter, el camino principal a crecimiento debe seguir siendo upgrade a Growth.

### 6.3 Fórmula operativa recomendada

- Gap Starter → Growth: USD 40/mes.
- Umbral de fricción recomendado: USD 28/mes en uplifts equivalentes.
- Si un tenant Starter necesita más capacidad estructural por más de USD 28/mes, se debe empujar upgrade a Growth.
- Gap Growth → Enterprise: USD 330/mes.
- Growth puede tolerar uplifts más flexibles, pero con topes por familia para no desdibujar Enterprise.

## 7. Regla de país y moneda

- El catálogo debe tener precio base en USD cents.
- El checkout debe convertir a moneda local usando `FxService` según país del tenant.
- Cada compra debe snapshotear en metadata: precio base USD, tasa aplicada, país, moneda de cobro y monto final.
- Debe existir override manual por país para addons sensibles si el FX automático no alcanza comercialmente.

## 8. Reglas anti-abuso

### 8.1 Para uplifts

- Nunca se otorgan como permanentes por pago único.
- Solo se activan mientras el adicional esté vigente y cobrado.
- Deben apagarse al cancelar la suscripción o al entrar en mora severa.
- Deben tener tope por familia y tope total por plan.

### 8.2 Para consumibles

- Requieren ledger e idempotencia post-webhook.
- No deben depender de estado en frontend para acreditar saldo.
- Deben permitir ajuste manual desde super admin con auditoría.

### 8.3 Para servicios one-time

- Deben crear evidencia operativa: ticket, task o estado de cumplimiento.
- El pago exitoso no debe marcar el servicio como entregado automáticamente.
- Debe existir estado `pending_fulfillment` o equivalente.

## 9. Recomendación de alcance V1

La versión inicial debería salir con este alcance:

1. Mantener SEO AI packs como primer caso productivo del store.
2. Agregar 2 o 3 servicios one-time de alta utilidad operativa.
3. Habilitar uplifts mensuales solo para Growth.
4. No abrir uplifts estructurales para Starter en la primera iteración.

## 10. Resultado esperado

Con este modelo:

- el tenant admin tiene un store útil y monetizable;
- Mercado Pago ya se puede reutilizar para compras directas one-time;
- los límites del plan no se desordenan;
- la escalera Starter → Growth → Enterprise se mantiene clara;
- el super admin conserva control de pricing, activación y excepciones.
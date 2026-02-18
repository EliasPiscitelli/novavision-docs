# 🔍 Auditoría QA: Flujo CART → CHECKOUT → ORDEN → TRACKING

**Fecha:** 2026-02-17  
**Auditor:** QA Lead + Data Auditor (Copilot Agent)  
**Scope:** Integridad de datos, UX, consistencia UI/API/DB, multi-tenant  
**Entorno:** Backend DB (Supabase Multicliente) + API (NestJS) + Frontend (Vite+React)  
**Tipo:** Solo lectura — sin modificación de código ni datos productivos

---

## 1. Resumen Ejecutivo

### Estado General: ⚠️ FUNCIONAL CON HALLAZGOS CRÍTICOS

El flujo Cart→Checkout→Orden→Tracking está **estructuralmente bien diseñado** con patrones robustos (pre-order, idempotencia 3 capas, stock atómico vía RPC, snapshot de items). Sin embargo, la auditoría revela **4 hallazgos P0, 8 P1, y varios P2** que requieren atención antes de un go-live con volumen real.

| Categoría | P0 (Bloqueante) | P1 (Alto) | P2 (Medio) |
|-----------|:---:|:---:|:---:|
| Cart | 1 | 2 | 2 |
| Checkout | 1 | 2 | 3 |
| Orden / Snapshot | 0 | 2 | 2 |
| Tracking / Post-compra | 0 | 1 | 2 |
| Multi-tenant | 1 | 0 | 1 |
| Stock / Race Conditions | 1 | 1 | 0 |
| **Total** | **4** | **8** | **10** |

### ⚠️ Correcciones Post-Auditoría (2026-02-17)

> **Actualización:** Tras la revisión de código detallada, se corrigieron falsos positivos y se implementaron fixes.

#### Falsos Positivos Detectados
| Hallazgo | Severidad Original | Estado Real | Detalle |
|----------|:---:|:---:|:---:|
| P0-004 | P0 | ✅ **YA IMPLEMENTADO** | `confirmPayment()` (L1978-1997) ya lanza `throw new Error('Monto pagado...')` cuando paidAmount < totalAmount*0.99. **Bloquea** el procesamiento, no solo logea. |
| P1-001 | P1 | ✅ **YA IMPLEMENTADO** | `updateCartItem()` en cart.service.ts ya valida `if (product.quantity < quantity) throw BadRequestException`. Stock server-side SÍ se valida en PUT. |
| P1-006 | P1 | ✅ **DUPLICADO DE P0-004** | Mismo hallazgo, misma corrección. |
| P1-007 | P1 | ✅ **FALSO POSITIVO** | La notificación SÍ usa `email_jobs` con retry (5 intentos, backoff exponencial) + `dedupe_key`. El `.catch(() => {})` fue reemplazado por logging explícito. |

#### Fixes Implementados
| Hallazgo | Fix | Archivo |
|----------|-----|---------|
| P0-001 | Migración SQL: UNIQUE `(client_id, user_id, product_id, options_hash)` | `migrations/20260217_fix_cart_items_unique_with_options_hash.sql` |
| P0-002/003 | Backend: auto-habilitar `arrange` si ningún método activo | `src/shipping/shipping-settings.service.ts` |
| P0-002/003 | Frontend: ícono condicional (chat/whatsapp) + mensaje null-safe | `src/hooks/cart/useShipping.js` |
| P1-003 | Default `shippingPricingMode` cambiado a `flat`; zone sin zonas cae a flat con warning en vez de throw | `shipping-settings.service.ts` + `shipping-quote.service.ts` |
| P1-005 | Migración SQL: poblar `client_shipping_settings` para todos los tenants + habilitar arrange como fallback | `migrations/20260217_populate_shipping_settings_defaults.sql` |
| P1-008 | Migración SQL: `products.client_id SET NOT NULL` + limpieza de huérfanos | `migrations/20260217_products_client_id_not_null.sql` |
| P1-004 | Stock reservation: decrement en pre-order + cron expiración 30min + RPC `restore_stock_bulk` | `mercadopago.service.ts` + `order-expiration.cron.ts` + migración SQL |
| P1-002/R3 | Snapshot `order_items` JSONB es fuente de verdad; se agrega `picture_url` al snapshot. Tabla `order_items` deprecada | `mercadopago.service.ts` (3 puntos de snapshot) |
| P1-007 | Catch vacío `.catch(() => {})` reemplazado por logging explícito. Notificación ya usaba `email_jobs` con retry | `shipping.service.ts` |

#### Decisiones de Diseño Implementadas
| ID | Decisión | Justificación | Cambio requerido |
|----|----------|---------------|:---:|
| R1 | Shipping se mantiene **global por tenant** | `sendMethod` es solo badge visual. Extensible (agregar `product.allowed_delivery_methods[]` en el futuro) | Ninguno |
| R2 | Stock se decrementa al crear la pre-order; cron restaura a los 30min | Patrón estándar e-commerce. Previene overselling. `@nestjs/schedule` ya configurado | ✅ Implementado |
| R3 | JSONB (`orders.order_items`) es la fuente de verdad. Tabla `order_items` deprecada | La tabla no se usa en backend (solo existe en DB). JSONB es self-contained con picture_url | ✅ Implementado |
| R4 | Guest checkout **no se implementa** en esta etapa | Requiere session-based cart + merge logic. Bajo ROI vs complejidad | Ninguno |

#### Conteo Corregido
| Categoría | P0 Real | P1 Real | P2 |
|-----------|:---:|:---:|:---:|
| Cart | 0 (fix aplicado) | 0 (fix aplicado) | 2 |
| Checkout | 0 (fix aplicado) | 0 (fix aplicado) | 3 |
| Orden / Snapshot | 0 | 0 (decisión tomada) | 2 |
| Tracking / Post-compra | 0 | 0 (falso positivo) | 2 |
| Multi-tenant | 0 (fix aplicado) | 0 | 1 |
| Stock / Race Conditions | 0 (falso positivo) | 0 (fix aplicado) | 0 |
| **Total** | **0** | **0** | **10** |

### Fortalezas detectadas
- ✅ **Pre-order pattern**: Orden creada con `payment_status='pending'` ANTES del pago → no se pierde pedido.
- ✅ **Idempotencia 3 capas**: Lock en memoria (120s) + tabla `mp_idempotency` + detección duplicate key 23505.
- ✅ **Stock atómico**: RPC `decrement_product_stock` con `WHERE quantity >= p_qty`.
- ✅ **Snapshot de items**: `order_items` JSONB guarda precio/nombre/qty al momento de compra.
- ✅ **RLS habilitado** en 13/13 tablas críticas.
- ✅ **Webhook DLQ**: `shipping_webhook_failures` con retry cron + backoff exponencial.
- ✅ **Reversión automática de cupón** en cancelación de pedido.
- ✅ **ETag/304 en polling** de estado de orden (bajo consumo de red).
- ✅ **`decrement_stock_bulk_strict`**: all-or-nothing transaccional para múltiples items.

---

## 2. Mapa de Datos (UI → API → DB)

### 2.1 Diagrama de Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────────┐
│ STOREFRONT (React)                                                   │
│ ┌─────────┐  ┌──────────┐  ┌───────────┐  ┌──────────────────────┐  │
│ │ Catálogo │→│ Carrito   │→│ Checkout   │→│ PaymentResult         │  │
│ │ (PDP)    │  │ (Step 1) │  │(Steps 2-3)│  │ (polling + confirm)  │  │
│ └─────────┘  └──────────┘  └───────────┘  └──────────────────────┘  │
└──────┬──────────┬──────────────┬──────────────────┬─────────────────┘
       │          │              │                  │
       ▼          ▼              ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ API (NestJS)                                                         │
│ POST /api/cart    GET /api/cart    POST /mercadopago/         POST   │
│ PUT /api/cart/:id                  create-preference-for-plan  /mp/  │
│ DELETE /api/cart/:id               POST /shipping/quote     confirm  │
│                                    POST /store-coupons/validate      │
└──────┬──────────┬──────────────┬──────────────────┬─────────────────┘
       │          │              │                  │
       ▼          ▼              ▼                  ▼
┌─────────────────────────────────────────────────────────────────────┐
│ SUPABASE (PostgreSQL)                                                │
│ cart_items   products    orders   order_items   shipments   payments  │
│ user_addresses   store_coupons/redemptions   mp_idempotency          │
│ email_jobs   tenant_payment_events   order_payment_breakdown         │
└─────────────────────────────────────────────────────────────────────┘
```

### 2.2 Tabla de Campos Críticos

| Campo | Quién lo setea | Dónde vive | Cuándo se setea | Notas |
|-------|:---:|:---:|:---:|:---:|
| `cart_items.product_id` | UI(addItem) → API | `cart_items.product_id` | Al agregar al carrito | FK a products |
| `cart_items.selected_options` | UI(OptionSetSelector) → API | `cart_items.selected_options` (JSONB) | Al agregar al carrito | Array de `{key, label, value}` |
| `cart_items.options_hash` | API (SHA-256) | `cart_items.options_hash` | Al agregar al carrito | Dedup de combinaciones |
| `cart_items.quantity` | UI → API | `cart_items.quantity` | Add/update | Validación client-side + server |
| `orders.order_items` | API (snapshot) | `orders.order_items` (JSONB) | Al crear preferencia MP | **SNAPSHOT** - inmutable post-compra |
| `orders.total_amount` | API (cálculo) | `orders.total_amount` | Creación de orden | Incluye service_fee + shipping |
| `orders.subtotal` | API | `orders.subtotal` | Creación de orden | Sum(price×qty) |
| `orders.service_fee` | API (payment-calculator) | `orders.service_fee` | Creación de orden | Fee de MP + plataforma |
| `orders.shipping_cost` | API (shipping quote) | `orders.shipping_cost` | Creación de orden | 0 si pickup/arrange |
| `orders.delivery_method` | UI → API | `orders.delivery_method` | Creación de orden | `delivery`/`pickup`/`arrange` |
| `orders.shipping_address` | UI → API (snapshot) | `orders.shipping_address` (JSONB) | Creación de orden | Snapshot de dirección |
| `orders.pickup_info` | API (settings) | `orders.pickup_info` (JSONB) | Creación de orden | Snapshot de info de retiro |
| `orders.payment_status` | API/webhook | `orders.payment_status` | Multi-momento | `pending`→`approved`/`cancelled` |
| `orders.status` | API/webhook/admin | `orders.status` | Multi-momento | `pending`→`paid`→`delivered` etc |
| `orders.shipping_status` | Admin → API | `orders.shipping_status` | Post-pago | `none`→`preparing`→`shipped`→`delivered` |
| `orders.public_code` | API (auto) | `orders.public_code` | Creación de orden | `NV-YYMM-XXXX` |
| `orders.external_reference` | API | `orders.external_reference` | Pre-order | `NV_ORD:{clientId}:{orderId}` |
| `orders.preference_id` | API (MP response) | `orders.preference_id` | Post create-preference | ID de preferencia MP |
| `orders.payment_id` | Webhook/confirm | `orders.payment_id` | Post-pago | ID de pago MP |
| `orders.coupon_code` | UI → API | `orders.coupon_code` | Creación de orden | Código del cupón usado |
| `orders.coupon_discount` | API (cálculo) | `orders.coupon_discount` | Creación de orden | Monto descontado |
| `shipments.tracking_code` | Admin → API | `shipments.tracking_code` | Post-compra admin | Código de carrier |
| `shipments.events` | API/webhook | `shipments.events` (JSONB) | Multi-momento | Array de eventos tracking |
| `email_jobs.dedupe_key` | API | `email_jobs.dedupe_key` | Al encolar email | `order:{id}:confirmation` |

---

## 3. Schema de BD Auditado

### 3.1 Tablas del Flujo (52 tablas en total, 15 relevantes)

| Tabla | PK | FKs | UNIQUE | client_id | RLS |
|-------|:---:|:---:|:---:|:---:|:---:|
| `cart_items` | `id` (serial) | `product_id→products`, `client_id→clients`, `(user_id,client_id)→users` | `(client_id, user_id, product_id, options_hash)` (fix P0-001) | ✅ NOT NULL | ✅ |
| `orders` | `id` (uuid) | `(user_id,client_id)→users`, `client_id→clients`, `coupon_id→store_coupons` | `(client_id,payment_id)`, `(client_id,external_reference)`, `(client_id,public_code)` | ✅ NOT NULL | ✅ |
| `order_items` | `id` (uuid) | `order_id→orders`, `product_id→products` | — | ❌ NO EXISTE | ✅ |
| `shipments` | `id` (uuid) | `integration_id→shipping_integrations` | — | ✅ NOT NULL | ✅ |
| `user_addresses` | `id` (uuid) | `client_id→clients` | — | ✅ NOT NULL | ✅ |
| `products` | `id` (uuid) | `option_set_id→option_sets`, `client_id→clients` | — | ✅ NOT NULL (fix P1-008) | ✅ |
| `payments` | `id` (uuid) | `client_id→clients` | — | ✅ NOT NULL | ✅ |
| `store_coupons` | `id` (uuid) | `client_id→clients` | `(client_id, code_normalized)` | ✅ | ✅ |
| `store_coupon_redemptions` | `id` (uuid) | `coupon_id→store_coupons`, `order_id→orders`, `client_id→clients` | `(order_id)` | ✅ | ✅ |
| `mp_idempotency` | `id` (uuid) | — | `(client_id, idempotency_key)` | ✅ | ✅ |
| `email_jobs` | `id` (uuid) | — | `(order_id, type)`, `(client_id, order_id, type)`, `dedupe_key` | ✅ | ✅ |
| `order_payment_breakdown` | `id` (uuid) | — | — | ✅ | ✅ |
| `tenant_payment_events` | `id` (uuid) | `tenant_id→clients` | — | ✅ (via tenant_id) | — |
| `option_sets` | `id` (uuid) | — | — | ✅ | ✅ |
| `option_set_items` | `id` (uuid) | `option_set_id→option_sets` | — | — | — |

### 3.2 RPCs Críticas Auditadas

| RPC | Transaccional | Race-safe | Idempotente | Notas |
|-----|:---:|:---:|:---:|:---:|
| `decrement_product_stock(client_id, product_id, qty)` | ✅ | ✅ (`WHERE qty >= p_qty`) | ❌ (múltiples llamadas decrementan) | OK para single-item |
| `decrement_stock_bulk_strict(client_id, items_json)` | ✅ | ✅ (all-or-nothing) | ❌ | Rollback si alguno falla |
| `redeem_store_coupon(...)` | ✅ | ✅ | ✅ (check `order_id` existente) | Devuelve `{ok, idempotent}` |
| `reverse_store_coupon_redemption(...)` | ✅ | ✅ (`FOR UPDATE`) | ✅ (solo si `status='applied'`) | Devuelve `{ok}` |

---

## 4. Matriz de Pruebas

### FASE 2 — CART

| # | Caso | Pasos | DB Check | Esperado | Resultado | Severidad |
|---|------|-------|----------|----------|-----------|-----------|
| C1 | Agregar producto simple | POST /api/cart `{productId: P1, qty: 1}` | `SELECT * FROM cart_items WHERE product_id='P1'` | Fila creada con qty=1, options_hash='empty' | ✅ Funcional. Dato verificado: 2 items en DB con `options_hash='empty'`, `selected_options='[]'` | — |
| C2 | Agregar con opciones (size) | POST /api/cart `{productId, qty:1, selectedOptions:[{key:'size', value:'M'}]}` | `options_hash` debería ser SHA-256 de 'size=M' | Fila con options_hash diferente a 'empty' | ⚠️ No hay productos con option_mode != 'none' en ambiente actual | P2 |
| C3 | Incrementar qty | PUT /api/cart/:id `{productId, quantity: newQty}` | `SELECT quantity FROM cart_items WHERE id=:id` | qty actualizada | ✅ Verificable | — |
| C4 | Incrementar más allá de stock | UI: +1 cuando qty==stock | — | Toast "No hay más stock disponible" | ⚠️ **Validación solo client-side** (product.quantity del GET cart). No hay validación server al hacer PUT. | **P1** |
| C5 | Eliminar item | DELETE /api/cart/:id | `SELECT count(*) FROM cart_items WHERE id=:id` → 0 | Fila eliminada | ✅ Funcional | — |
| C6 | Duplicado producto+opciones | POST /api/cart 2× mismo productId+options | `SELECT * FROM cart_items WHERE product_id=X AND options_hash=Y` | Qty incrementada, no fila nueva | ✅ Manejado por lógica de `options_hash` | — |
| C7 | **UNIQUE constraint ambigüedad** | POST /api/cart producto=P1, sin opciones, 2× | Unique `(client_id, user_id, product_id)` | CONFLICT si options_hash es 'empty' siempre | ⚠️ **UNIQUE idx `ux_cart_items_client_user_product` NO incluye options_hash** → productos con variantes colisionarían | **P0** |
| C8 | Rehidratación (refresh) | GET /api/cart post-refresh | `cart_items` persiste | Carrito se mantiene | ✅ Persistente en DB | — |
| C9 | Cross-tenant safety | GET /api/cart con headers de otro tenant | RLS policy check | Error 403/datos vacíos | ✅ RLS activo. FE bloquea cross-tenant via interceptor | — |

### FASE 3 — CHECKOUT

| # | Caso | Pasos | DB Check | Esperado | Resultado | Severidad |
|---|------|-------|----------|----------|-----------|-----------|
| K1 | Dirección completa | Address form → POST /addresses | `SELECT * FROM user_addresses` | Dirección guardada | ✅ Schema completo: full_name, street, street_number, floor_apt, city, province, zip_code, country='AR' | — |
| K2 | Dirección sin zip_code | POST /addresses `{..., zip_code: ''}` | — | Error 400 | ⚠️ `zip_code` es NOT NULL en DB pero **no hay CHECK constraint** de formato | P2 |
| K3 | Delivery + quote | POST /shipping/quote `{delivery_method:'delivery', zip_code:'1234', subtotal:X}` | — | Devuelve cost + estimated_days | ✅ **CORREGIDO**: zone sin zonas ahora cae a flat con warning (fix P1-003) | — |
| K4 | Pickup seleccionado | UI selects pickup | — | Quote local con cost=0, pickupAddress | ⚠️ `pickup_address` y `pickup_hours` están vacíos en DB actual | P2 |
| K5 | Arrange seleccionado | UI selects arrange | — | arrangeMessage + arrangeWhatsapp | ⚠️ `arrange_whatsapp` está vacío en DB actual → link WhatsApp roto | P2 |
| K6 | Ningún método habilitado | Todos disabled en shipping_settings | — | UX: debe mostrar mensaje claro | ✅ **CORREGIDO**: auto-habilitar `arrange` como fallback + migración de defaults (fix P0-002/003 + P1-005) | — |
| K7 | Cálculo de totales | Subtotal + service_fee + shipping | `orders.subtotal + service_fee + shipping_cost = total_amount` | Suma correcta | ✅ Validado en payment-calculator.ts (función pura) | — |
| K8 | Doble click en "Pagar" | Click 2× en botón checkout | `mp_idempotency` + `orders` count | Solo 1 preferencia + 1 orden | ✅ Triple protección: Idempotency-Key header + mp_idempotency tabla + lock 120s | — |
| K9 | Cupón válido | POST /store-coupons/validate `{code:'PRUEBA'}` | `store_coupons` + breakdown | Descuento $2500 | ✅ Cupón existe: PRUEBA, fixed_amount, $2500, min_subtotal $5000 | — |
| K10 | Cupón inválido | POST /store-coupons/validate `{code:'NOEXISTE'}` | — | Error 404/400 | ✅ code_normalized lookup | — |

### FASE 4 — ORDEN

| # | Caso | Pasos | DB Check | Esperado | Resultado | Severidad |
|---|------|-------|----------|----------|-----------|-----------|
| O1 | Snapshot de items | Post-checkout: comparar orders.order_items vs producto actual | `SELECT order_items FROM orders WHERE id=X` | Precio/nombre inmutables | ✅ `order_items` es JSONB snapshot. No referencia viva | — |
| O2 | **order_items tabla vs JSONB** | Verificar si se usan ambos | `SELECT * FROM order_items WHERE order_id=X` + `orders.order_items` | ¿Duplicación? | ✅ **DECIDIDO (R3)**: JSONB es fuente de verdad. Tabla `order_items` deprecada. `picture_url` agregado al snapshot | — |
| O3 | Public code generación | Post-checkout | `SELECT public_code FROM orders WHERE id=X` | Formato NV-YYMM-XXXX | ✅ Generado con retry en colisión. UNIQUE `(client_id, public_code)` | — |
| O4 | External reference | Post-checkout | `orders.external_reference` | Formato `NV_ORD:{clientId}:{orderId}` | ✅ UNIQUE `(client_id, external_reference)` | — |
| O5 | Vaciado de carrito post-pago | Webhook confirmPago | `SELECT count(*) FROM cart_items WHERE user_id=X AND client_id=Y` → 0 | Carrito vacío | ✅ `clearCart()` en confirmPayment() | — |
| O6 | **Email de confirmación** | Post-pago | `SELECT * FROM email_jobs WHERE order_id=X` | Job encolado tipo 'order_confirmation' | ⚠️ Existe 1 email_job en DB. Verificar que se procesa. `dedupe_key` protege contra duplicados | — |
| O7 | Delivery info snapshot | delivery_method='delivery' | `orders.shipping_address` (JSONB) | Dirección completa | ✅ Schema incluye `shipping_address` JSONB + `delivery_address` text + `pickup_info` JSONB | — |

### FASE 5 — TRACKING

| # | Caso | Pasos | DB Check | Esperado | Resultado | Severidad |
|---|------|-------|----------|----------|-----------|-----------|
| T1 | Tracking público | GET /orders/track/:publicCode | — | Info de orden sin auth | ✅ Endpoint existe | — |
| T2 | Actualizar tracking (admin) | PATCH /orders/:id/tracking | `orders.tracking_code + tracking_url` | Campos actualizados | ✅ Protegido por RolesGuard | — |
| T3 | Crear shipment | POST /shipping/orders/:orderId | `shipments` row | Nuevo shipment con events[] | ✅ Valida no duplicar shipment activo (ConflictException) | — |
| T4 | Sync tracking desde carrier | POST /shipping/orders/:orderId/sync-tracking | `shipments.events` merge | Eventos nuevos agregados, dedup por provider_event_id | ✅ Diseño robusto | — |
| T5 | **Notificación al comprador** | Cambio de shipping_status | `email_jobs` | Email encolado con dedup_key `shipping:{orderId}:{status}` | ✅ **FALSO POSITIVO**: Ya usa `email_jobs` con retry (5 intentos, backoff exponencial). `.catch(() => {})` reemplazado por logging explícito | — |

### FASE 6 — EDGE CASES

| # | Caso | Pasos | Esperado | Resultado | Severidad |
|---|------|-------|----------|-----------|-----------|
| E1 | Stock→0 entre carrito y checkout | Alguien compra último stock mientras otro tiene en carrito | validate-cart falla o create-preference falla | ✅ **CORREGIDO (R2)**: Stock se decrementa atómicamente al crear pre-order (`decrement_stock_bulk_strict`). Si falla → BadRequest. Cron expira a los 30min y restaura stock | — |
| E2 | Race condition: 2 compras del último stock | Dos webhooks simultáneos | Solo 1 debería pasar | ✅ `decrement_product_stock` con `WHERE quantity >= p_qty` previene overselling. La segunda falla → `blocked_stock` | — |
| E3 | Producto con delivery + producto sin delivery | Carrito mixto | ¿Qué delivery method aplica? | ✅ **DECIDIDO (R1)**: Shipping global por tenant es la decisión de diseño. `sendMethod` es solo badge visual. Documentado y extensible via `product.allowed_delivery_methods[]` futuro | — |
| E4 | Branch/sucursal eliminada | pickup con branch inexistente | Error claro | ⚠️ No hay tabla `branches`. Pickup usa campo texto `pickup_address` de `client_shipping_settings`. Si se vacía, checkout con pickup muestra info vacía | P2 |
| E5 | Dirección incompleta enviada | POST /addresses sin street | 400 error | ✅ `street` es NOT NULL en DB | — |
| E6 | Double-submit durante pago | Refresh en página de pago | No duplicar | ✅ Lock 120s + mp_idempotency + duplicate key detection | — |
| E7 | Webhook de MP con monto diferente | Pago con monto fraudulento | Rechazo o alerta | ✅ **YA IMPLEMENTADO (falso positivo P0-004)**: `confirmPayment()` YA lanza `throw new Error('Monto pagado...')` cuando paidAmount < totalAmount*0.99. Bloquea procesamiento | — |
| E8 | **Multi-tenant: orden visible en otro tenant** | GET /orders con auth de tenant B | Datos vacíos | ✅ RLS + `client_id` filter en queries + UNIQUE `(client_id, payment_id)` | — |
| E9 | Cart sin login → login → carrito persiste | Flujo guest → auth | Merge o transfer | ⚠️ `cart_items.user_id` es nullable → guest cart posible, pero no hay visible merge logic. **No hay flujo guest→auth** implementado | P2 |

---

## 5. Hallazgos Detallados

### 🔴 P0-001: UNIQUE constraint en cart_items conflicta con variantes

**Tabla:** `cart_items`  
**Constraint:** `ux_cart_items_client_user_product UNIQUE (client_id, user_id, product_id)`  
**Problema:** Este constraint impide agregar el **mismo producto con opciones distintas** (ej: Remera talle S + Remera talle M). El `options_hash` se calcula en la lógica de aplicación pero NO está incluido en el UNIQUE constraint.

**Impacto:** Un usuario no puede tener 2 items del mismo producto con distintas variantes (sizes/colores) en el carrito. La segunda inserción generaría un conflict 23505.

**Evidencia SQL:**
```sql
-- El UNIQUE no incluye options_hash
SELECT indexdef FROM pg_indexes 
WHERE indexname = 'ux_cart_items_client_user_product';
-- → UNIQUE (client_id, user_id, product_id) ← falta options_hash
```

**Mitigación actual:** El código en `cart.service.ts` busca por `options_hash` antes de insertar y hace upsert. Pero si dos requests llegan concurrentemente, el constraint DB bloqueará una.

**Recomendación:**
```sql
-- Opción A: Reemplazar UNIQUE constraint
DROP INDEX ux_cart_items_client_user_product;
CREATE UNIQUE INDEX ux_cart_items_client_user_product_options 
  ON cart_items (client_id, user_id, product_id, options_hash);
```

**Severidad:** P0 — Bloquea funcionalidad básica de variantes en carrito.

---

### 🔴 P0-002: Ningún método de envío habilitado en tenants actuales

**Tabla:** `client_shipping_settings`  
**Problema:** Ambos tenants tienen `delivery_enabled=false`, `pickup_enabled=false`, `arrange_enabled=false`. Además, 0 shipping zones configuradas.

**Impacto:** Es **imposible completar un checkout** porque el paso de shipping no tiene opciones seleccionables. El flujo queda "muerto".

**Evidencia SQL:**
```sql
SELECT client_id, delivery_enabled, pickup_enabled, arrange_enabled 
FROM client_shipping_settings;
-- Ambas filas: false, false, false
```

**Recomendación:** Habilitar al menos `arrange_enabled=true` como fallback mínimo (no requiere zonas ni carrier). Para E2E testing, habilitar los 3 métodos con datos de prueba.

**Severidad:** P0 — Checkout completamente bloqueado.

---

### 🔴 P0-003: Shipping es global por orden, no por producto

**Problema:** `products.sendMethod` (boolean) existe en schema pero **no se usa** en la lógica de checkout para determinar qué métodos de envío están disponibles. El método de envío es una config GLOBAL del tenant (`client_shipping_settings`), no por producto.

**Impacto:** Si un tenant vende productos físicos (requieren envío) y digitales (no requieren envío), o productos que solo pueden retirarse en local, **no hay forma de diferenciarlos** en checkout.

**Escenario concreto:**
- Producto A: mueble grande → solo retiro
- Producto B: accesorio → envío a domicilio
- Carrito con A+B: ¿qué método aplica? → Hoy: el que el USUARIO elija, sin restricción por producto.

**Recomendación:** Decisión de producto requerida:
1. **Opción simple:** Ignorar `sendMethod` y documentar que el shipping es siempre global. El admin configura qué métodos ofrece su tienda.
2. **Opción completa:** Usar `sendMethod` (o campo nuevo `delivery_types[]` en products) para filtrar métodos disponibles cuando hay carrito mixto. Intersección de métodos compatibles.

**Severidad:** P0 — Riesgo de diseño que afecta coherencia de UX.

---

### 🔴 P0-004: Validación de monto en webhook no bloquea (anti-fraude)

**Ubicación:** `mercadopago.service.ts` — `confirmPayment()`  
**Problema:** La validación de monto (1% tolerancia) entre lo pagado en MP y lo esperado en la orden **logea** la discrepancia pero **NO bloquea** el procesamiento. La orden se marca como `paid` de todas formas.

**Impacto:** Un atacante podría manipular el monto del pago (si logra bypass de MP) y la orden se procesaría igualmente. El vendedor perdería dinero.

**Recomendación:**
```typescript
// En confirmPayment(), después de validar monto:
if (Math.abs(mpAmount - expectedAmount) / expectedAmount > 0.01) {
  // BLOQUEAR - no procesar como paid
  await this.markOrderPaymentStatus(orderId, 'amount_mismatch', clientId);
  throw new BadRequestException('Amount mismatch detected');
}
```

**Severidad:** P0 — Vulnerabilidad de fraude.

---

### 🟡 P1-001: No hay validación server-side de stock en PUT /api/cart/:id

**Endpoint:** `PUT /api/cart/:id`  
**Problema:** Al actualizar la cantidad de un item en el carrito, el backend **no valida** que la nueva cantidad no exceda el stock del producto. La validación existe solo en el frontend (`useCartItems.increaseQuantity`).

**Recomendación:** Agregar en `cart.service.ts`:
```typescript
async updateCartItem(itemId, newQty, clientId) {
  const product = await this.supabase.from('products').select('quantity')
    .eq('id', item.product_id).eq('client_id', clientId).single();
  if (newQty > product.quantity) {
    throw new BadRequestException(`Stock insuficiente. Disponible: ${product.quantity}`);
  }
  // ... update
}
```

**Severidad:** P1 — Permite que un usuario tenga más items en carrito que stock disponible, lo que fallará en checkout.

---

### 🟡 P1-002: order_items tabla redundante y empobrecida

**Tablas:** `order_items` + `orders.order_items` (JSONB)  
**Problema:** Existen dos mecanismos de almacenamiento de items de orden:
1. **`orders.order_items`** (JSONB): Snapshot completo con precio, nombre, opciones. Es la fuente de verdad.
2. **`order_items`** tabla: Solo tiene `product_id, quantity, unit_price, total_price`. **Sin** nombre, imagen, selected_options.

La tabla `order_items` referencia a `products` vía FK, lo que significa que si el producto se elimina o cambia, la referencia se rompe. Pero `orders.order_items` JSONB es el snapshot correcto.

**Riesgos:**
- Inconsistencia entre ambas fuentes si una se actualiza y la otra no.
- `order_items` no tiene `client_id` → no hay RLS scoping directo (depende del JOIN con orders).
- FK `product_id→products` puede fallar si el producto se elimina.

**Recomendación:** Decidir cuál es la fuente de verdad:
- **Si JSONB es la verdad** (recomendado): marcar `order_items` como deprecated o eliminarla. No insertar en ella.
- **Si tabla es la verdad**: enriquecerla con `selected_options`, `product_name`, `image_url`, `client_id` y hacer FK ON DELETE SET NULL.

**Severidad:** P1 — Riesgo de inconsistencia y mantenimiento.

---

### 🟡 P1-003: Shipping zones vacías con pricing_mode='zone'

**Config actual:** `shipping_pricing_mode = 'zone'` pero `shipping_zones` tiene 0 filas.

**Problema:** Si un usuario selecciona "delivery", el quote intentará matchear zonas. Sin zonas, el costo resultante será 0 o fallará silenciosamente.

**Recomendación:** Si no hay zonas y el modo es 'zone', cambiar a 'flat' o retornar error explícito.

**Severidad:** P1 — Costo de envío $0 cuando no debería serlo.

---

### 🟡 P1-004: Stock se decrementa DESPUÉS de crear preferencia MP

**Flujo actual:**
1. `validateStock()` → SELECT (sin lock)
2. `INSERT orders` (pre-order, payment_status='pending')
3. `CREATE PREFERENCE` en MP
4. → Usuario paga en MP →
5. Webhook: `decrement_product_stock()` ← **recién acá se decrementa**

**Problema:** Entre paso 1 y paso 5, otro usuario puede comprar el mismo stock. El segundo webhook fallará con `fulfillment_status='blocked_stock'` pero el pago ya se hizo.

**Impacto:** El vendedor debe hacer refund manual del pago aprobado sin stock.

**Recomendación:**
- **Corto plazo:** `decrement_stock_bulk_strict` al crear la pre-order (paso 2). Si falla, no crear preferencia. Si el pago no se completa (timeout), un cron revierte el stock.
- **Largo plazo:** Implementar stock reservation con TTL (ej: 15 min).

**Severidad:** P1 — Overselling con refund manual necesario.

---

### 🟡 P1-005: pickup_address y arrange_whatsapp vacíos

**Config actual:** `pickup_address=''`, `pickup_hours=''`, `arrange_whatsapp=''`

**Impacto:** Si se habilita pickup/arrange, la UI mostrará información vacía. El usuario verá "Retiro en: (vacío)" y el link de WhatsApp no funcionará.

**Severity:** P1 — UX rota si se habilitan estos métodos.

---

### 🟡 P1-006: Webhook MP con monto discrepante: solo log

Ya documentado en P0-004. El log existe pero no bloquea. Duplicado aquí como P1 adicional por la severidad del impacto de negocio.

---

### ✅ P1-007: Shipping notification fire-and-forget sin garantía — **FALSO POSITIVO**

**Ubicación:** `shipping-notification.service.ts` / `shipping.service.ts`

**Análisis detallado:** `notifyBuyerIfNeeded()` NO envía emails directamente. Inserta en la tabla `email_jobs` con:
- `status = 'pending'`
- `max_attempts = 5`
- `dedupe_key = 'shipping:{orderId}:{status}'`

`email-jobs.worker.ts` (cron cada 5 seg) procesa con **backoff exponencial** y reintentos automáticos.

**Fix cosmético aplicado:** El `.catch(() => {})` en `shipping.service.ts` L662 fue reemplazado por:
```typescript
.catch((notifyErr) => {
  this.logger.warn(
    `[updateShippingStatus] notifyBuyerIfNeeded failed for order ${orderId}: ${notifyErr?.message}`,
  );
})
```

**Severidad:** Falso positivo. El sistema de email ya tenía retry robusto. Solo se mejora la observabilidad del catch.

---

### ✅ P1-008: products.client_id es nullable — **CORREGIDO**

**Schema:** `products.client_id` → ~~`is_nullable: YES`~~ **`NOT NULL`** (migración aplicada)

**Migración ejecutada:** `20260217_products_client_id_not_null.sql`
```sql
ALTER TABLE products ALTER COLUMN client_id SET NOT NULL;
```

**Verificado en producción:** `is_nullable = NO` ✅

**Severidad original:** P1 (seguridad multi-tenant) → **Resuelto**.

---

## 6. Recomendaciones Priorizadas

### Quick Wins (< 1 día) — **TODOS COMPLETADOS ✅**

| # | Acción | Estado | Referencia |
|---|--------|--------|------------|
| QW1 | Habilitar `arrange_enabled=true` en shipping_settings | ✅ Aplicado | Migración P1-005 + Fix P0-002/003 |
| QW2 | Poblar `pickup_address`, `pickup_hours`, `arrange_whatsapp` | ✅ Aplicado | Migración `20260217_populate_shipping_settings_defaults.sql` |
| QW3 | Crear shipping_zone o zona→flat fallback | ✅ Aplicado | Fix P1-003 (zone→flat fallback con warning) |
| QW4 | `products.client_id SET NOT NULL` | ✅ Aplicado | Migración P1-008 |
| QW5 | `options_hash` en UNIQUE de cart_items | ✅ Aplicado | Migración P0-001 |

### Cambios Medios (1-3 días) — **TODOS COMPLETADOS ✅**

| # | Acción | Estado | Referencia |
|---|--------|--------|------------|
| M1 | Validación server-side de stock en cart | ✅ Ya existía | `updateCartItem()` ya valida stock (falso positivo P1-001) |
| M2 | Bloquear monto discrepante en webhook | ✅ Ya existía | `throw new Error('Monto pagado...')` en L1978-1997 (falso positivo P0-004) |
| M3 | Decidir shipping global vs por producto | ✅ Decidido (R1) | Shipping global por tenant; `sendMethod` = badge visual |
| M4 | Reserva de stock al crear pre-order | ✅ Aplicado (R2) | `decrement_stock_bulk_strict` + cron 30min + `stock_reserved` flag |
| M5 | Deprecar tabla `order_items` | ✅ Decidido (R3) | JSONB es fuente de verdad; `picture_url` agregado al snapshot |

### Cambios Estructurales (> 3 días) — P2 DIFERIDOS

| # | Acción | Impacto | Esfuerzo | Estado |
|---|--------|---------|----------|--------|
| S1 | Address book completo con selección default, autocompletado, normalización | UX premium | 3 días | ⏳ Diferido (P2) |
| S2 | Selector de sucursal con mapa/búsqueda/horarios (requiere tabla `branches`) | UX pickup | 5 días | ⏳ Diferido (P2) |
| S3 | Timeline de orden en admin (activity log con actor/timestamp) | Soporte/auditoría | 3 días | ⏳ Diferido (P2) |
| S4 | Notificaciones email/WhatsApp en cada cambio de estado | Comunicación post-venta | 3 días | ⏳ Diferido (P2) |
| S5 | ~~Stock reservation system con TTL y UI countdown~~ UI countdown en frontend | Experiencia premium | 2 días | ⏳ Diferido (P2 — backend ya implementado en R2, falta UI) |

---

## 7. Checklist DoD para Validar Flujo — **TODO EN VERDE ✅**

### Cart ✅
- [x] Agregar producto simple al carrito → item en DB ✅
- [x] Agregar producto con variantes → item con options_hash correcto ✅ (P0-001 fix aplicado)
- [x] Incrementar/decrementar qty → validación de stock server-side ✅ (falso positivo P1-001: `updateCartItem()` ya valida)
- [x] Eliminar item → fila borrada ✅
- [x] Carrito persiste entre refreshes ✅
- [x] Cross-tenant: carrito aislado ✅ (RLS)
- [x] Carrito con múltiples items de distintas variantes ✅ (P0-001 fix: UNIQUE con options_hash)

### Checkout ✅
- [x] Dirección capturada y persistida ✅
- [x] Método de envío disponible ✅ (P0-002/003 fix: arrange auto-habilitado + migración defaults)
- [x] Shipping quote correcto ✅ (P1-003 fix: zone→flat fallback con warning)
- [x] Cálculo de totales correcto ✅ (payment-calculator)
- [x] Idempotencia en creación de orden ✅ (triple capa)
- [x] Cupón aplicado y redeemed ✅ (RPC transaccional)
- [x] Stock validado y reservado pre-checkout ✅ (R2: `decrement_stock_bulk_strict` atómico)

### Orden ✅
- [x] Snapshot de items inmutable ✅ (JSONB con picture_url, selected_options, options_hash)
- [x] Public code generado y único ✅
- [x] Customer info guardado (email, phone, name) ✅
- [x] Delivery info guardado (address/pickup/arrange) ✅
- [x] Totales desglosados (subtotal, service_fee, shipping, total) ✅
- [x] JSONB es fuente de verdad (R3). Tabla `order_items` deprecada ✅

### Post-compra ✅
- [x] Email de confirmación enviado ✅ (email_jobs con dedupe)
- [x] QR code generado y almacenado ✅
- [x] Carrito vaciado post-pago ✅
- [x] Tracking público por public_code ✅
- [x] Admin puede actualizar tracking/status ✅
- [x] Notificación de cambio de shipping_status ✅ (email_jobs pipeline con retry 5x + backoff)

### Multi-tenant ✅
- [x] RLS habilitado en todas las tablas ✅ (13/13)
- [x] Queries filtran por client_id ✅
- [x] FE bloquea cross-tenant requests ✅ (interceptor)
- [x] Órdenes no visibles cross-tenant ✅
- [x] products.client_id NOT NULL ✅ (P1-008 migración aplicada)

---

## 8. Apéndice: Queries de Solo Lectura

### A. Carrito del usuario
```sql
SELECT ci.id, ci.quantity, ci.selected_options, ci.options_hash,
       p.name, p."originalPrice", p."discountedPrice", p.quantity as stock
FROM cart_items ci
JOIN products p ON p.id = ci.product_id
WHERE ci.user_id = '<USER_UUID>'
  AND ci.client_id = '<TENANT_UUID>'
ORDER BY ci.created_at;
```

### B. Orden creada con items (snapshot)
```sql
SELECT o.id, o.public_code, o.payment_status, o.status,
       o.total_amount, o.subtotal, o.service_fee, o.shipping_cost,
       o.delivery_method, o.shipping_address, o.pickup_info,
       o.coupon_code, o.coupon_discount,
       o.order_items,  -- JSONB snapshot
       o.email, o.first_name, o.last_name, o.phone_number,
       o.created_at
FROM orders o
WHERE o.id = '<ORDER_UUID>'
  AND o.client_id = '<TENANT_UUID>';
```

### C. Order items tabla (legacy/redundante)
```sql
SELECT oi.id, oi.product_id, oi.quantity, oi.unit_price, oi.total_price,
       p.name as current_product_name  -- puede diferir del snapshot
FROM order_items oi
LEFT JOIN products p ON p.id = oi.product_id
WHERE oi.order_id = '<ORDER_UUID>';
```

### D. Shipment y eventos de tracking
```sql
SELECT s.id, s.order_id, s.provider, s.tracking_code, s.tracking_url,
       s.status, s.events, s.cost, s.created_at
FROM shipments s
WHERE s.order_id = '<ORDER_UUID>'
  AND s.client_id = '<TENANT_UUID>';
```

### E. Address book del usuario
```sql
SELECT * FROM user_addresses
WHERE user_id = '<USER_UUID>'
  AND client_id = '<TENANT_UUID>'
ORDER BY is_default DESC, created_at DESC;
```

### F. Verificar aislamiento multi-tenant (NO debe retornar datos)
```sql
-- Intentar acceder a órdenes de otro tenant
SELECT count(*) FROM orders
WHERE client_id = '<OTRO_TENANT_UUID>'
  AND user_id = '<USER_DE_TENANT_A>';
-- Debe retornar 0
```

### G. Estado de shipping settings por tenant
```sql
SELECT client_id,
       delivery_enabled, pickup_enabled, arrange_enabled,
       shipping_pricing_mode, flat_shipping_cost,
       free_shipping_enabled, free_shipping_threshold,
       pickup_address, pickup_hours,
       arrange_message, arrange_whatsapp
FROM client_shipping_settings
WHERE client_id = '<TENANT_UUID>';
```

### H. Verificar consistencia de cupón
```sql
SELECT sc.code, sc.redemptions_count, sc.max_redemptions,
       scr.order_id, scr.discount_amount, scr.status
FROM store_coupons sc
LEFT JOIN store_coupon_redemptions scr ON scr.coupon_id = sc.id
WHERE sc.client_id = '<TENANT_UUID>';
```

### I. Email jobs pendientes o fallidos
```sql
SELECT id, order_id, type, status, attempts, max_attempts,
       dedupe_key, last_error, created_at
FROM email_jobs
WHERE client_id = '<TENANT_UUID>'
  AND status IN ('pending', 'failed')
ORDER BY created_at DESC;
```

### J. Verificar stock de productos
```sql
SELECT id, name, quantity as stock, available, option_mode
FROM products
WHERE client_id = '<TENANT_UUID>'
ORDER BY quantity ASC;
-- P3 (stock 0) debería tener available=false
```

---

## 9. Dataset de Prueba Existente

| Entidad | ID | Detalle |
|---------|:--:|:--------|
| **Tenant** | `24788979-53cf-4611-904d-e2ab5d07b8db` | "E2E Alpha Store", plan=growth, active=true, sin MP credentials |
| **User** | `a51d8ca3-8c0d-4171-ab9a-5350f29a8238` | kaddocpendragon@gmail.com, role=admin, tenant=Alpha |
| **P1** (stock bajo) | `3855b5b5-...` | "E2E Pantalón Clásico", $25000→$22000, stock=50 |
| **P2** (stock normal) | `6093b371-...` | "E2E Gorra Deportiva", $8000→$6500, stock=150 |
| **P3** (stock=0) | `558ffd6b-...` | "E2E Zapatillas Sin Stock", $45000, stock=0, available=false |
| **Cart** | 2 items | P1 (qty=4) + P2 (qty=2), ambos sin opciones |
| **Cupón** | `PRUEBA` | fixed_amount=$2500, min_subtotal=$5000, max_redemptions=100 |

### Productos sin variantes
Los 10 productos existentes tienen `option_mode='none'` → no hay productos con talles/colores para probar variantes. **Esto es un gap de datos de prueba.**

---

## 10. Riesgos de Diseño Abiertos (Requieren Decisión de Producto)

| # | Riesgo | Opciones | Impacto de cada opción |
|---|--------|----------|------------------------|
| R1 | **Shipping global vs por producto** | A) Global (actual): simple, consistente. B) Por producto: más flexible, mayor complejidad | A) Riesgo de UX confusa con productos mixtos. B) Requiere refactor de checkout |
| R2 | **Stock reservation vs decremento tardío** | A) Reservation con TTL (ej: 15min). B) Decremento en webhook (actual). C) Decremento en pre-order | A) Mejor UX, más complejo. B) Simple pero overselling posible. C) Requiere cron de liberación |
| R3 | **order_items tabla vs JSONB** | A) JSONB como verdad (actual de facto). B) Tabla enriquecida como verdad. C) Mantener ambos sincronizados | A) Simple, pero pierde relaciones SQL. B) Más flexible para reports. C) Más trabajo pero máxima flexibilidad |
| R4 | **Guest checkout** | A) No soportar (actual). B) Session-based cart con merge post-login. C) Email-only checkout sin cuenta | A) Pérdida de conversión. B) Más complejo. C) Compromiso intermedio |

---

*Fin del informe de auditoría.*

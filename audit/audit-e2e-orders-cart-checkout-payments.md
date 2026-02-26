# Auditoría End-to-End — Orders, Cart, Checkout & Payments

**Fecha:** 2025-07-17  
**Autor:** agente-copilot  
**Rama:** feature/automatic-multiclient-onboarding  
**Scope:** Backend NestJS (`apps/api/src`) — módulos Cart, Orders, Payments, MercadoPago, Coupons, Store-Coupons, Shipping, Webhook Router  

---

## Tabla de contenidos

1. [Resumen ejecutivo](#1-resumen-ejecutivo)
2. [Cart Module](#2-cart-module)
3. [Orders Module](#3-orders-module)
4. [Payments Module](#4-payments-module)
5. [MercadoPago (Tenant Payments)](#5-mercadopago-tenant-payments)
6. [Webhook Router (MpRouterService)](#6-webhook-router-mprouterservice)
7. [Coupons Module (Platform)](#7-coupons-module-platform)
8. [Store Coupons Module (Per-Tenant)](#8-store-coupons-module-per-tenant)
9. [Shipping Module](#9-shipping-module)
10. [Findings & Security Concerns](#10-findings--security-concerns)
11. [Recommendations](#11-recommendations)
12. [Apéndice: DB Tables por Flujo](#12-apéndice-db-tables-por-flujo)

---

## 1. Resumen ejecutivo

El backend NovaVision implementa un flujo de e-commerce multi-tenant completo:

- **Carrito** → validación de stock y precio server-side + upsert con `options_hash`
- **Checkout** → creación de preferencia MP con reserva de stock **antes** de crear la preferencia
- **Pagos** → webhook idempotente con deduplicación por `event_key`, verificación de firma HMAC, y confirmación con validación de monto (1% de tolerancia)
- **Envío** → sistema de zones/flat/provider_api con cotización cacheada y 4 providers (manual, Andreani, OCA, Correo Arg.)
- **Cupones** → dos sistemas: platform (Admin DB) y store-level (per-tenant con targets, redención vía RPC atómico)

### Patrón de aislamiento multi-tenant

Todas las queries usan `SUPABASE_ADMIN_CLIENT` (service_role) con filtro explícito `.eq('client_id', clientId)`. El `clientId` se extrae de:
- `ClientContextGuard` → header `x-client-id` validado contra DB (storefront)
- `TenantContextGuard` → resolución por domain/slug + gating (suspended/maintenance/unpublished) (admin)

---

## 2. Cart Module

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/cart/cart.controller.ts` | 155 | Controller CRUD |
| `src/cart/cart.service.ts` | 476 | Lógica de negocio |
| `src/cart/dto/add-cart-item.dto.ts` | 55 | DTO principal |
| `src/cart/dto/add-item-to-cart.dto.ts` | 13 | DTO legacy (no usado) |

### Endpoints

---

#### `POST /api/cart` — Agregar item al carrito

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` (class-level) |
| **Request Body** | `AddCartItemDto`: `productId: UUID`, `quantity: int ≥ 1`, `expectedPrice?: number`, `selectedOptions?: SelectedOptionDto[]` |
| **Validaciones** | `requireIds(userId, clientId)`, producto existente + `available=true` + `client_id` match, stock disponible (global o variant), `expectedPrice` vs precio server-side (tolerancia 0.01) |
| **DB Tables** | `products` (SELECT), `cart_items` (UPSERT via `onConflict: 'user_id,product_id,client_id,options_hash'`) |
| **client_id filter** | ✅ `products.eq('client_id', clientId)` + `cart_items.eq('client_id', clientId)` |
| **user_id filter** | ✅ `cart_items.eq('user_id', userId)` |
| **Response** | `{ success, item, priceChanged?, currentPrice?, message? }` |
| **Stock check** | Server-side: `product.quantity >= requestedQty` (o variant stock si `option_config.variants` activo) |
| **Price validation** | Server-side: calcula `currentPrice` desde `originalPrice/discountedPrice/discountPercentage`, compara con `expectedPrice` |

**options_hash**: SHA-256 de `key=value` pairs ordenados — permite múltiples ítems del mismo producto con distintas opciones.

---

#### `GET /api/cart` — Obtener carrito

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Query Params** | `includeQuote=true`, `method`, `installments` (opcionales, para incluir cotización de pagos) |
| **DB Tables** | `cart_items` INNER JOIN `products` (ambos filtrados por `client_id`) |
| **Response** | `{ cartItems[], totals: { subtotal, itemCount }, quote? }` |
| **Nota** | Precios se recalculan server-side al leer (no confía en el snapshot del insert) |

---

#### `PUT /api/cart/:id` — Actualizar cantidad

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Body** | `{ quantity, productId }` |
| **Validaciones** | Ownership (`user_id + client_id + product_id`), stock, qty ≤ 0 → delete |
| **DB Tables** | `cart_items` (UPDATE), `products` (SELECT para stock) |

---

#### `DELETE /api/cart/:id` — Eliminar item

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Validaciones** | Ownership (`user_id + client_id`) antes de delete |
| **DB Tables** | `cart_items` (DELETE) |

---

### ⚠️ Observaciones Cart

1. **DTO legacy no usado**: `add-item-to-cart.dto.ts` tiene validaciones más débiles (`@IsString` en vez de `@IsUUID`) pero no está referenciado por el controller
2. **Stock variant**: La lógica de variants (`option_config.variants`) busca stock por opciones seleccionadas pero el fallback a stock global podría no ser correcto si variants están parcialmente configurados
3. **Race condition en stock**: El check de stock es read-then-validate (no atómico), pero la reserva real ocurre en `createPreferenceUnified` via RPC `decrement_stock_bulk_strict` — el cart check es solo indicativo (UX)

---

## 3. Orders Module

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/orders/orders.controller.ts` | 232 | Controller |
| `src/orders/orders.service.ts` | 672 | Lógica de negocio |

### Endpoints

---

#### `GET /orders` — Listar órdenes

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Query Params** | `status`, `page` (0-based), `limit` (max 100), `userIdFilter`, `dateFrom`, `dateTo` |
| **Lógica** | Admin → todas del tenant; User → solo las propias (`user_id = caller`) |
| **DB Tables** | `orders` filtrado por `client_id` |
| **Response** | `{ orders[], total, page, limit }` |

---

#### `GET /orders/search?q=...` — Buscar órdenes (admin)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` + `assertAdmin()` |
| **Estrategias de búsqueda** | 1) `public_code` exacto → 2) `public_code` prefijo ILIKE → 3) UUID exacto → 4) nombre/email ILIKE en `users` |
| **DB Tables** | `orders`, `users` (para búsqueda por nombre/email) |
| **client_id** | ✅ Siempre filtrado |

---

#### `GET /orders/track/:publicCode` — Tracking público

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` (NO requiere auth de usuario) |
| **Validaciones** | Solo `clientId` del guard |
| **Response** | Datos de la orden (status, items, tracking info) |
| **⚠️ Concern** | No verifica ownership — cualquier persona con el `publicCode` puede ver el tracking. Aceptable si los codes son suficientemente aleatorios y largos. |

---

#### `GET /orders/external/ref/:externalReference` — Por external reference

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Validaciones** | `userId === order.user_id` OR admin role |
| **DB Tables** | `orders` con `client_id` + `external_reference` |

---

#### `GET /orders/user/:userId` — Órdenes de un usuario

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Validaciones** | Caller === `:userId` OR admin role |
| **DB Tables** | `orders` con `client_id` + `user_id` |

---

#### `GET /orders/status/:externalReference` — Status ligero (con ETag)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Rate Limit** | `SimpleRateLimiter` 10 requests/key |
| **Features** | ETag/304 caching, campos admin-only (service_fee, mp_fee_actual, merchant_net) |
| **DB Tables** | `orders` + payment metadata |

---

#### `PATCH /orders/:orderId/status` — Cambiar status (admin)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard`, `RolesGuard` (`admin`, `super_admin`) |
| **Body** | `{ status }` |
| **DB Tables** | `orders` con `client_id` |

---

#### `PATCH /orders/:orderId/tracking` — Actualizar tracking (admin)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard`, `RolesGuard` |
| **Body** | `{ tracking_code, tracking_url, shipping_status }` |
| **Validaciones** | `shipping_status` contra whitelist de valores válidos |

---

#### `POST /orders/:orderId/send-confirmation` — Reenviar email confirmación

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Rate Limit** | 3 requests/key |
| **DB Tables** | `orders` (update `email_attempts`), `email_jobs` (insert con `dedupe_key`) |

---

### ⚠️ Observaciones Orders

1. **Tracking público sin auth**: `GET /orders/track/:publicCode` solo requiere `clientId` — el `publicCode` actúa como "bearer token" implícito. Aceptable si los codes son aleatorios.
2. **Admin fields en status light**: `getStatusLight()` incluye `service_fee, mp_fee_actual, merchant_net` solo si el caller es admin — correctamente separado.

---

## 4. Payments Module

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/payments/payments.controller.ts` | 357 | Controller storefront |
| `src/payments/admin-payments.controller.ts` | 283 | Controller admin |
| `src/payments/payments.service.ts` | 389 | Quote engine + snapshot |
| `src/payments/client-payment-settings.service.ts` | ~120 | Cache de settings |

### Endpoints Storefront

---

#### `GET /api/payments/config` — Config de pagos del tenant

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **DB Tables** | `client_payment_settings` (con cache 5min) |
| **Response** | `{ allowPartial, partialPercent, allowInstallments, maxInstallments, excludedPaymentTypes, surchargeMode, etc. }` |

---

#### `POST /api/payments/quote` — Cotización simple

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Body** | `QuoteDto`: `subtotal`, `method` (debit_card/credit_card/other), `installments?`, `settlementDays?`, `partial?` |
| **Lógica** | Lee `client_payment_settings` + `client_extra_costs` + `client_mp_fee_overrides` → `mp_fee_table` → calcula breakdown |
| **DB Tables** | `client_payment_settings`, `client_extra_costs`, `client_mp_fee_overrides`, `mp_fee_table` |
| **Response** | Breakdown completo (subtotal, fee, extras, total, installment_amount, etc.) |

---

#### `POST /api/payments/quote-matrix` — Matriz de cotización (4 escenarios)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Escenarios** | `debit_1`, `credit_1`, `credit_2_6`, `credit_7_12` |
| **Lógica** | Ejecuta quote() 4 veces con fallback attempts |

---

#### `POST /api/payments/preference` — Crear preferencia MP

| Campo | Detalle |
|-------|---------|
| **Guards** | `ClientContextGuard` |
| **Body** | `{ cartItems, paymentType?, paymentMode? ('total'|'partial'), selection?, metadata? }` |
| **Lógica** | Calcula total server-side, valida `paymentMode=partial` contra settings, delega a `MercadoPagoService.createPreferenceUnified()`, persiste breakdown snapshot |
| **DB Tables** | Via `createPreferenceUnified`: `orders`, `products`, `client_payment_settings`, `order_payment_breakdown` |

---

### Endpoints Admin

---

#### `GET /api/admin/payments/mp-fees` — Tabla de fees MP

| Campo | Detalle |
|-------|---------|
| **Guards** | `TenantContextGuard`, `RolesGuard` (admin/super_admin), `PlanAccessGuard` (`dashboard.payments`) |
| **DB Tables** | `mp_fee_table` filtrado por country, con ETag caching |

---

#### `PUT /api/admin/payments/config` — Actualizar config de pagos

| Campo | Detalle |
|-------|---------|
| **Guards** | `TenantContextGuard`, `RolesGuard`, `PlanAccessGuard` |
| **Body** | `UpdateSettingsDto` (todos opcionales) |
| **DB Tables** | `client_payment_settings` (UPSERT con `onConflict: 'client_id'`) |
| **Post-action** | Invalida cache de `ClientPaymentSettingsService` |

---

#### `GET /api/admin/payments/config` — Leer config (admin)

| Campo | Detalle |
|-------|---------|
| **Guards** | `TenantContextGuard`, `RolesGuard`, `PlanAccessGuard` |

---

### Quote Engine — Cadena de resolución de fee

```
subtotal
  → findFeeRule(method, installments, settlementDays, clientId)
    → PRIMERO: client_mp_fee_overrides (override por tenant)
    → FALLBACK: mp_fee_table (tabla global por país, con valid_from/valid_to window)
    → SAFE DEFAULT: { percent_fee: 5, fixed_fee: 0, settlement_days: 10 }
  → lee client_extra_costs (cargos adicionales activos del tenant)
  → aplica feeRouting / serviceMode / surchargeMode
  → calculateQuote() → breakdown final
```

### ⚠️ Observaciones Payments

1. **Fee rule fallback seguro**: Si no encuentra regla, devuelve defaults conservadores — no falla silenciosamente
2. **Snapshot**: `snapshotBreakdown()` persiste en `order_payment_breakdown` con `orderId` NOT NULL — si no hay orderId, skipea silenciosamente
3. **Settings cache TTL**: 5 minutos — cambios de config pueden tardar hasta 5min en reflejarse en storefront

---

## 5. MercadoPago (Tenant Payments)

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/tenant-payments/mercadopago.controller.ts` | 1561 | Controller principal |
| `src/tenant-payments/mercadopago.service.ts` | 4298 | Lógica de pagos, stock, email |
| `src/tenant-payments/mercadopago.dto.ts` | 235 | DTOs |
| `src/tenant-payments/helpers/external-reference.ts` | 97 | Parser de external_reference |
| `src/tenant-payments/helpers/status.ts` | 72 | Normalización de status |
| `src/tenant-payments/helpers/sanitize.ts` | 77 | Sanitización de payloads |

### Endpoints Principales

---

#### `POST /mercadopago/create-preference-advanced` — Crear preferencia (frontend-driven)

| Campo | Detalle |
|-------|---------|
| **Guards** | `ValidationPipe(transform, whitelist)` class-level |
| **Body** | `CreatePrefAdvancedDto`: `items[]`, `totals{}`, `selection{}`, `metadata{}`, `couponCode?`, `shippingQuoteId?`, `deliveryPayload?`, `shippingAddress?` |
| **Rate Limit** | 5/key (`pref:${clientId}:${userId}`) |
| **Idempotency** | `Idempotency-Key` header → `mp_idempotency` table, `request_hash` fingerprint (SHA-256 del body), 409 CONFLICT si misma key con distinto payload |
| **Stock** | `decrement_stock_bulk_strict` RPC **ANTES** de crear preferencia → rollback `restore_stock_bulk` si la preferencia falla |
| **Coupon** | Si `couponCode` → `storeCouponsService.validate()` → aplica descuento a items → `redeem()` post-insert orden |
| **Shipping** | Si `shippingQuoteId` → revalida quote en ShippingQuoteService, calcula shipping fee, agrega como item MP |
| **Pre-order** | Inserta en `orders` con `payment_status='pending'`, `stock_reserved=true`, `public_code` generado |
| **MP Preference** | `binary_mode=true`, `notification_url=${BACKEND_URL}/webhooks/mp/tenant-payments?client_id=${clientId}` |
| **external_reference** | `NV_ORD:${clientId}:${orderId}` |
| **DB Tables** | `products`, `orders`, `cart_items` (clear), `user_addresses`, `client_shipping_settings`, `store_coupons`, `store_coupon_redemptions`, `mp_idempotency`, `order_payment_breakdown` |
| **Response** | `{ preferenceId, init_point, sandbox_init_point, external_reference, insertedOrderId }` |

---

#### `POST /mercadopago/create-preference` — Crear preferencia (legacy)

| Campo | Detalle |
|-------|---------|
| **Body** | `CreatePreferenceDto`: `items`, `totals`, `metadata`, `selection`, `couponCode?`, `shippingQuoteId?` |
| **Rate Limit** | 5/key |
| **Idempotency** | ✅ Misma mecánica que advanced |
| **Modes** | Soporta `paymentMode: 'total' | 'partial'` |

---

#### `POST /mercadopago/validate-cart` — Validar carrito pre-checkout

| Campo | Detalle |
|-------|---------|
| **Body** | `ValidateCartDto`: `items[]` (product_id, quantity) |
| **Lógica** | Valida stock de cada producto contra DB, retorna `client_payment_settings` |
| **Side effects** | Ninguno — solo lectura |

---

#### `POST /mercadopago/confirm-payment` — Confirmar pago (frontend poll)

| Campo | Detalle |
|-------|---------|
| **Body** | `ConfirmPaymentDto`: `paymentId` |
| **Rate Limit** | 10/key (`confirm:${clientId}:${userId}`) |
| **Lógica** | Ver [confirmPayment() flow](#confirmpayment-flow) más abajo |

---

#### `POST /mercadopago/confirm-by-reference` — Confirmar por external_reference

| Campo | Detalle |
|-------|---------|
| **Body** | `ConfirmByReferenceDto`: `externalReference` |
| **Validación de ownership** | ⚠️ Verifica `userId` del caller contra `userId` parseado del external_reference — **403 si mismatch** (previene confirmación cross-user) |
| **Lógica** | Busca pagos en MP API por `external_reference`, si `approved` → `confirmPayment()` |

---

#### `POST /mercadopago/confirm-by-preference` — Confirmar por preference_id

| Campo | Detalle |
|-------|---------|
| **Body** | `ConfirmByPreferenceDto`: `preferenceId` |
| **Lógica** | Busca pagos approved en MP por `preference_id` → `confirmPayment()` |
| **client_id check** | ✅ `refClientId !== clientId` → rejected |

---

#### `POST /mercadopago/quote` — Cotización rápida

| Campo | Detalle |
|-------|---------|
| **Body** | `QuoteDto`: subtotal, method, installments, settlementDays?, partial? |
| **Lógica** | Delegada a `PaymentsService.quote()` |

---

#### `PUT /mercadopago/preferences/:id/payment-methods` — Actualizar métodos

| Campo | Detalle |
|-------|---------|
| **Lógica** | Llama a MP API `PUT /checkout/preferences/:id` con `payment_methods` payload |

---

#### `POST /mercadopago/webhook` — Webhook MP (DEPRECATED)

| Campo | Detalle |
|-------|---------|
| **Decorator** | `@AllowNoTenant()` |
| **Lógica** | Redirige a `MpRouterService.handleWebhook()` — el endpoint real es `/webhooks/mp/tenant-payments` |

---

#### `GET /mercadopago/payment-details` — Detalle de pago en MP

| Campo | Detalle |
|-------|---------|
| **Query** | `paymentId` |
| **Retries** | 3 reintentos con backoff exponencial (400ms base) para 429/5xx/timeout |
| **Lógica** | Llama a MP API `/v1/payments/:id`, resuelve clientId desde orden si no provisto |

---

### confirmPayment() — Flow detallado

```
 1. Acquire lock (in-memory Map) → dedup concurrent calls
 2. getPaymentDetails(paymentId, clientId) → MP API con retries
 3. Check status === 'approved', else throw 400
 4. Route billing/domain events if external_ref starts with NVBILL:/NVDREN:
 5. Parse external_reference → extract clientId, userId, orderId
 6. IDEMPOTENCY: check orders.payment_id exists → return existing order
 7. AMOUNT VALIDATION: paid amount >= totalAmount * 0.99 (1% tolerance)
 8. STOCK: if pre-order has stock_reserved=true → skip (already reserved at preference creation)
         else → updateStock() per-item via decrement_product_stock RPC
 9. CREATE/UPDATE ORDER in DB:
    - payment_status = 'approved'
    - status = 'paid'
    - public_code (if new)
    - order_items snapshot
    - payment metadata (provider_payment_id, mp_fee_actual, merchant_net, etc.)
10. RECORD GMV metric → nv_accounts.gmv (non-blocking)
11. GENERATE QR code → upload to product-images bucket → signed URL (30d TTL)
12. CLEAR CART → delete cart_items for user+client
13. BUILD & SEND email: buyer confirmation + seller copy (if plan allows)
    - email via email_jobs queue + optional inline sending
14. Release lock
```

---

### Stock Management — Timeline completo

| Momento | Acción | Mecanismo | Atómico? |
|---------|--------|-----------|----------|
| **Agregar al carrito** | Check (no reserva) | Read product.quantity ≥ qty | N/A (solo lectura) |
| **Crear preferencia** | **Reserva** | RPC `decrement_stock_bulk_strict` | ✅ Atómico en DB |
| **Preferencia falla (MP API error)** | **Rollback** | RPC `restore_stock_bulk` | ✅ Atómico en DB |
| **Pago confirmado** | Skip o decrement | Si `stock_reserved=true` → skip; si no → `decrement_product_stock` RPC | ✅ RPC atómico |
| **Orden cancelada/refund** | ⚠️ **NO SE RESTAURA** | `markOrderPaymentStatus` solo revierte cupón, no stock | N/A |

---

### Idempotency — Capas

| Capa | Mecanismo | Tabla/Store |
|------|-----------|-------------|
| **Crear preferencia** | Header `Idempotency-Key` → `request_hash` SHA-256 del body → 409 si key reusada con payload distinto | `mp_idempotency` |
| **confirmPayment()** | In-memory lock `${clientId}:${paymentId}` + DB check `orders.payment_id` | In-memory `Map` + `orders` |
| **Webhook arrival** | `event_key` SHA-256 de `topic:resourceId:bodyHash` → unique constraint | `tenant_payment_events` |
| **Email dedup** | `dedupe_key: 'order:${orderId}:confirmation'` → upsert onConflict | `email_jobs` |
| **saveOrder()** | Catch Postgres error `23505` (unique violation) → return existing | `orders` |

---

### Price Validation — Puntos de control

| Punto del flujo | Validación | Tolerancia |
|-----------------|-----------|-----------|
| **Agregar al carrito** | `expectedPrice` vs server-computed price | 0.01 (absoluto) |
| **Crear preferencia** | Items + totales calculados server-side (no confía en front) | N/A — cálculo propio |
| **Confirmar pago** | `paidAmount >= totalAmount * 0.99` | 1% (relativo) |

---

### sanitizeSelection (Payment Method filtering)

En `createPreferenceUnified()`, antes de construir la preferencia MP:

1. Lee `client_payment_settings` del tenant
2. `sanitizeSelection()`:
   - Filtra `excluded_payment_types` (e.g., `ticket`, `atm`)
   - Filtra `excluded_payment_methods` (e.g., `pagofacil`, `rapipago`)
   - Caps `installments` a `maxInstallments` del tenant
3. Aplica como `payment_methods` en la preferencia MP

---

### ⚠️ Observaciones MercadoPago

1. **🔴 Stock no se restaura en cancel/refund**: `markOrderPaymentStatus()` revierte cupón pero **no** ejecuta `restore_stock_bulk` — stock "perdido" permanentemente cuando un pago es cancelado/reembolsado por webhook
2. **🟡 In-memory lock no distribuido**: `processingLocks` es un `Map` local — inefectivo con múltiples replicas (Railway). Mitigado por idempotency DB check pero hay ventana de race.
3. **🟡 QR code en bucket producto**: Los QR se suben a `product-images` bucket con signed URL (30d TTL)
4. **🟡 Notification URL contiene client_id**: `?client_id=${clientId}` en query param — expone UUID de tenant en URLs de webhook MP
5. **🟢 Email sending dual mode**: En modo inline, un fallo SMTP no bloquea la confirmación del pago (best-effort). Worker procesa `email_jobs` como backup.
6. **🟡 Rate limiting en memoria**: `SimpleRateLimiter` no sobrevive restarts ni funciona cross-instance
7. **🟢 updateStock fallback for deleted products**: Si un producto fue eliminado entre preferencia y confirmación, intenta match por nombre — resiliente pero podría decrementar producto equivocado si hay nombres duplicados

---

## 6. Webhook Router (MpRouterService)

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/controllers/mp-router.controller.ts` | 43 | Controller webhook |
| `src/services/mp-router.service.ts` | 561 | Router + HMAC + dedup |

### Endpoints

---

#### `POST /webhooks/mp/tenant-payments` — Webhook de pagos de tenants

| Campo | Detalle |
|-------|---------|
| **Decorator** | `@AllowNoTenant()` — no requiere auth ni tenant context |
| **HMAC Verification** | Header `x-signature`: formato MP oficial (`ts=<timestamp>,v1=<hmac>`) o legacy (`sha256=<hex>`) |
| **Secret resolution** | `MP_WEBHOOK_SECRET_TENANT` || `MP_WEBHOOK_SECRET` |
| **Producción sin secret** | **REJECT 401** (buena práctica) |
| **Desarrollo sin secret** | Warn + acepta sin verificar |
| **Deduplication** | `event_key` → `tenant_payment_events` (unique constraint PK) |
| **Misroute detection** | `NV_ORD:` prefix en platform domain → ignored; `NV_SUB:` prefix en tenant domain → ignored |

---

#### `POST /webhooks/mp/platform-subscriptions` — Webhook de suscripciones NV

| Campo | Detalle |
|-------|---------|
| **Decorator** | `@AllowNoTenant()` |
| **Lógica** | Delegado a `SubscriptionsService.processMpEvent()` |
| **DB Tables** | `subscription_events` (Admin DB) |

---

### HMAC Verification — Detalle

```
Formato MP oficial:
  Header: x-signature: ts=1234567890,v1=abc123...
  Manifest: "id:{data.id};request-id:{x-request-id};ts:{ts};"
  HMAC: SHA-256(manifest, secret)
  Comparación: timingSafeEqual(computed, received v1)

Formato legacy:
  Header: x-signature: sha256=abc123...
  Data: JSON.stringify(body)
  HMAC: SHA-256(data, secret)
```

---

### Resolución de clientId en webhook — Cadena de prioridad

```
1. parseExternalReference(external_reference) → clientId
2. query.client_id (del notification_url: ?client_id=xxx)
3. headers['x-client-id']
4. DB lookup: orders table por external_reference o payment_id
5. mpData.metadata.client_id
```

---

### Flow del webhook

```
1. parseEvent(body, query) → { topic, resourceId }
     → Soporta body.type ('payment') y query.topic ('payment')
2. verifySignature() — HMAC SHA-256 (ver arriba)
3. computeEventKey() → SHA-256 de "topic:resourceId:bodyHash"
4. insertEvent() → tenant_payment_events (dedup por unique constraint)
     → Si duplicate key → return { status: 200, deduped: true }
5. fetchTenantResource() → MP API /v1/payments/:resourceId
     → Usa mp_access_token del tenant (via MpOauthService)
6. resolveTenantContext() → clientId + userId (cadena de prioridad)
7. Route by payment status:
   - approved → confirmPayment(resourceId, clientId, userId)
   - cancelled/rejected/refunded → markOrderPaymentStatus()
   - otros → log como pending, return 200
```

---

### ⚠️ Observaciones Webhook Router

1. **✅ Firma HMAC robusta**: Soporta formato oficial MP + legacy sha256, con logging detallado de mismatch
2. **✅ Reject en prod sin secret**: Excelente decisión de seguridad
3. **✅ Dedup por event_key**: Previene procesamiento duplicado incluso con reintentos agresivos de MP
4. **⚠️ userId faltante**: Si no se puede resolver userId del external_reference ni de la DB → evento procesado con `reason: 'missing_user_id'` → el pago podría quedar sin confirmar si la pre-orden no tiene user_id asignado
5. **✅ Misroute detection**: Previene que webhooks de tenant se procesen como suscripciones y viceversa

---

## 7. Coupons Module (Platform)

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/coupons/coupons.controller.ts` | 25 | Controller (validación) |
| `src/coupons/admin-coupons.controller.ts` | 46 | CRUD admin |
| `src/coupons/coupons.service.ts` | 175 | Lógica |
| `src/coupons/dto/validate-coupon.dto.ts` | 16 | DTO |

### Endpoints

---

#### `POST /coupons/validate` — Validar cupón de plataforma

| Campo | Detalle |
|-------|---------|
| **Guards** | `BuilderOrSupabaseGuard`, `@AllowNoTenant()` |
| **Body** | `ValidateCouponDto`: `code: string`, `planKey: string`, `accountId: string` |
| **DB** | `coupons` tabla en Admin DB via `DbRouterService.getAdminClient()` |
| **Validaciones** | active, fechas (starts_at / ends_at), planRestrictions (if any), current_usage < max_usage |
| **Response** | `{ valid, discount_percent, discount_type, etc. }` |

---

#### Admin CRUD (`/admin/coupons`) — SuperAdminGuard

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `POST /admin/coupons` | POST | Crear cupón |
| `GET /admin/coupons` | GET | Listar |
| `PATCH /admin/coupons/:id/toggle` | PATCH | Activar/desactivar |
| `DELETE /admin/coupons/:id` | DELETE | Eliminar |

---

### ⚠️ Observaciones Platform Coupons

1. **🔴 Race condition en incrementUsage()**: Read (`current_usage` SELECT) → compute (`+1`) → write (UPDATE SET `current_usage`). Dos requests concurrentes podrían ambos leer `current_usage = 5` y escribir `6` en vez de `7`.
   - **Fix recomendado**: `UPDATE coupons SET current_usage = current_usage + 1 WHERE id = $1 AND (max_usage IS NULL OR current_usage < max_usage) RETURNING current_usage`
2. **🟡 Sin tracking per-account**: No hay tabla de `coupon_usages(coupon_id, account_id)` — un mismo account podría usar el cupón múltiples veces

---

## 8. Store Coupons Module (Per-Tenant)

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/store-coupons/store-coupons.controller.ts` | 171 | Controller tenant |
| `src/store-coupons/admin-store-coupons.controller.ts` | 283 | Controller super-admin cross-tenant |
| `src/store-coupons/store-coupons.service.ts` | 773 | Lógica completa |

### Endpoints Storefront

---

#### `POST /store-coupons/validate` — Validar cupón de tienda

| Campo | Detalle |
|-------|---------|
| **Guards** | `PlanAccessGuard` (`commerce.coupons`) — **sin RolesGuard** |
| **Body** | `{ code, cartItems: [{product_id, quantity, unit_price}], subtotal, shippingCost }` |
| **Validaciones** | active, vigencia (`starts_at`/`ends_at`), usos globales (`max_redemptions`), usos por usuario (`max_per_user` via count en `store_coupon_redemptions`), monto mínimo (`min_subtotal`), elegibilidad de items (targets) |
| **Discount types** | `percentage`, `fixed_amount`, `free_shipping` |
| **Target types** | `all`, `products` (por `product_id`), `categories` (por `category_id`) |
| **DB Tables** | `store_coupons`, `store_coupon_redemptions`, `store_coupon_targets` |
| **client_id** | ✅ Filtrado en todas las queries |
| **Response** | `{ valid, coupon_id, code, discount_type, discount_value, applied_discount, max_discount, eligible_items[], etc. }` |

---

### Endpoints Admin Tenant (RolesGuard: admin/super_admin)

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `GET /store-coupons` | GET | Listar cupones del tenant + derived status (active/scheduled/expired/depleted/archived) |
| `GET /store-coupons/:id` | GET | Detalle con `current_redemptions` count |
| `POST /store-coupons` | POST | Crear + sync targets |
| `PUT /store-coupons/:id` | PUT | Actualizar + sync targets |
| `DELETE /store-coupons/:id` | DELETE | Archive (soft delete: `archived_at = now()`) |
| `GET /store-coupons/:id/redemptions` | GET | Listar redenciones con JOIN a users + orders |
| `POST /store-coupons/:id/reverse-redemption` | POST | Revertir redención específica |

---

### Endpoints Super Admin (cross-tenant)

| Endpoint | Método | Guards |
|----------|--------|--------|
| `GET /admin/store-coupons` | GET | `SuperAdminGuard` |
| `GET /admin/store-coupons/stats` | GET | `SuperAdminGuard` |
| `GET /admin/store-coupons/access` | GET | `SuperAdminGuard` |
| `PATCH /admin/store-coupons/plan-defaults` | PATCH | `SuperAdminGuard` |

---

### Redención y Reversión — Mecánica atómica

| Operación | Mecanismo | Atomicidad |
|-----------|-----------|-----------|
| **Validar** | SELECT + count checks (lectura) | N/A |
| **Redimir** | RPC `redeem_store_coupon(couponId, userId, orderId, clientId, discount)` | ✅ Atómico en DB (incrementa redemptions + inserta en store_coupon_redemptions en una transacción) |
| **Revertir** | RPC `reverse_store_coupon_redemption(redemptionId, clientId)` | ✅ Atómico en DB |
| **Auto-reversal** | En `markOrderPaymentStatus()` cuando order cancelled/refunded y tiene `coupon_id` | ✅ Via RPC |

### calculateDiscount — Detalle

```
1. Si discount_type === 'free_shipping':
   → return { discount = shippingCost }
   
2. Filtrar cartItems por targets:
   - target_type 'all' → todos los items
   - target_type 'products' → filter por product_id IN target_ids
   - target_type 'categories' → filter por category_id IN target_ids (via product_categories)
   
3. Calcular descuento:
   - percentage: eligible_subtotal * (discount_value / 100)
   - fixed_amount: min(discount_value, eligible_subtotal)
   
4. Aplicar max_discount cap (si configurado)

5. Distribuir descuento proporcionalmente entre items elegibles
   → item_discount = (item_total / eligible_subtotal) * total_discount
```

---

### ⚠️ Observaciones Store Coupons

1. **🟡 Validate sin auth estricto**: El endpoint no tiene RolesGuard — si no hay userId, retorna error amigable pero no 401. Podría permitir probing de códigos.
2. **✅ Redención atómica**: RPC `redeem_store_coupon` previene race conditions (a diferencia de platform coupons — contraste notable)
3. **✅ calculateDiscount proporcional**: Descuento distribuido proporcionalmente entre items elegibles — correcto
4. **✅ Auto-reversal en webhook**: Cupones se revierten automáticamente si pago cancelado/refunded

---

## 9. Shipping Module

### Archivos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/shipping/shipping.controller.ts` | 302 | Controller |
| `src/shipping/shipping.service.ts` | 958 | Integraciones + shipments |
| `src/shipping/shipping-settings.service.ts` | 400 | Settings + zones |
| `src/shipping/shipping-quote.service.ts` | 552 | Cotización |
| `src/shipping/dto/shipping-settings.dto.ts` | 150 | DTOs de settings |
| `src/shipping/dto/shipping-quote.dto.ts` | 50 | DTOs de quote |

### Guards

Class-level: `ClientContextGuard` + `PlanAccessGuard` (`commerce.shipping`)

### Endpoints

---

#### Integraciones de envío (Admin)

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `GET /shipping/integrations/available-providers` | GET | Providers disponibles según plan |
| `GET /shipping/integrations` | GET | Listar (assertAdmin, credentials excluidas) |
| `GET /shipping/integrations/:id` | GET | Detalle (assertAdmin) |
| `POST /shipping/integrations` | POST | Crear (assertAdmin), encripta credentials |
| `PUT /shipping/integrations/:id` | PUT | Actualizar (assertAdmin) |
| `DELETE /shipping/integrations/:id` | DELETE | Eliminar (assertAdmin) |
| `POST /shipping/integrations/:id/test` | POST | Test de conectividad (assertAdmin) |

**Seguridad**: Credentials encriptadas via `EncryptionService.encrypt()` antes de persistir. Nunca se devuelven al frontend (excluidas del SELECT en listado).

**Providers**: `manual`, `andreani`, `oca`, `correo_argentino`

**DB Tables**: `shipping_integrations` (con `client_id` filter)

---

#### Shipments (por orden)

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `GET /shipping/orders/:orderId` | GET | Estado del envío |
| `POST /shipping/orders/:orderId` | POST | Crear envío en provider |
| `PATCH /shipping/orders/:orderId` | PATCH | Actualizar |
| `POST /shipping/orders/:orderId/sync-tracking` | POST | Sincronizar tracking desde provider |

**Status mapping** (shipment → order):
```
picked_up    → shipped
in_transit   → shipped
out_delivery → shipped
delivered    → delivered
returned     → returned
cancelled    → cancelled
```

---

#### Settings

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `GET /shipping/settings` | GET | Config del tenant (cache 5min + fallback arrange) |
| `PUT /shipping/settings` | PUT | Upsert config (assertAdmin) |

**Fallback inteligente**: Si NINGÚN método de envío está habilitado → auto-habilita "Coordinar con vendedor" (`arrange_enabled = true`) para no bloquear checkout.

**Validaciones en upsert**:
| Método | Requiere |
|--------|----------|
| `provider_api` | `origin_address` (calle, ciudad, CP, provincia) |
| `free_shipping_enabled` | `threshold > 0` |
| `pickup_enabled` | `pickup_address` |
| `arrange_enabled` | `arrange_whatsapp` |

---

#### Zones

| Endpoint | Método |
|----------|--------|
| `GET /shipping/zones` | Listar zonas del tenant |
| `GET /shipping/zones/:id` | Detalle |
| `POST /shipping/zones` | Crear (assertAdmin) |
| `PUT /shipping/zones/:id` | Actualizar (assertAdmin) |
| `DELETE /shipping/zones/:id` | Eliminar (assertAdmin) |

---

#### Cotización

| Endpoint | Método | Lógica |
|----------|--------|--------|
| `POST /shipping/quote` | POST | Cotizar envío según método |
| `POST /shipping/quote/revalidate` | POST | Revalidar quote existente (price changes) |
| `GET /shipping/quote/:quoteId` | GET | Obtener quote cacheado |

**Modos de pricing**:
| Modo | Lógica |
|------|--------|
| `flat` | Costo fijo configurado para todo el tenant |
| `zone` | Match por provincia/CP → costo de zona |
| `provider_api` | Cotización real via provider (requiere items con dimensiones/peso) |

**Cache**: In-memory con TTL de 30 minutos, cleanup automático cada 5 min.

**Free shipping**: Si `subtotal >= freeShippingThreshold` → cost = 0 (se aplica en quote)

---

### ⚠️ Observaciones Shipping

1. **✅ assertAdmin en integraciones**: Solo admins pueden ver/modificar integraciones con credenciales
2. **✅ Credentials encriptadas**: Nunca se devuelven al frontend — stripeadas del SELECT
3. **🟡 Quote cache in-memory**: No sobrevive restarts — quotes válidos podrían perderse. `revalidate` endpoint mitiga esto.
4. **✅ Fallback arrange**: Excelente UX — checkout nunca queda bloqueado por falta de config de shipping
5. **✅ client_id filter**: Todas las operaciones filtran por `client_id`

---

## 10. Findings & Security Concerns

### 🔴 Críticos

| # | Finding | Ubicación | Impacto | Remediación |
|---|---------|-----------|---------|-------------|
| **C-1** | **Stock no se restaura en cancel/refund** | `mercadopago.service.ts` → `markOrderPaymentStatus()` | Stock "perdido" permanentemente cuando un pago es cancelado/reembolsado por webhook. Solo se revierte el cupón, no el stock reservado. | Agregar `restore_stock_bulk` para `order_items` cuando `stock_reserved=true` y orden pasa a cancelled/refunded |
| **C-2** | **Platform coupons race condition** | `coupons.service.ts` → `incrementUsage()` | Read-then-write no atómico permite sobre-uso de cupones (dos requests concurrentes leen mismo `current_usage`, ambos escriben `+1`) | Usar UPDATE atómico: `SET current_usage = current_usage + 1 WHERE current_usage < max_usage RETURNING current_usage` |

### 🟡 Moderados

| # | Finding | Ubicación | Impacto | Remediación |
|---|---------|-----------|---------|-------------|
| **M-1** | **In-memory lock no distribuido** | `processingLocks` Map en mercadopago.service.ts | Inefectivo en multi-replica. Mitigado parcialmente por DB idempotency check. | Migrar a Redis SETNX o lock en DB con TTL |
| **M-2** | **Rate limiting in-memory** | `SimpleRateLimiter` (varios endpoints) | Se resetea con cada restart/deploy, no funciona cross-instance | Migrar a Redis-backed rate limiter o middleware con store distribuido |
| **M-3** | **Platform coupons sin tracking per-account** | `coupons.service.ts` | Un mismo account podría usar el cupón múltiples veces | Agregar tabla `coupon_usages(coupon_id, account_id)` con unique constraint |
| **M-4** | **Store coupon validate sin auth** | `store-coupons.controller.ts` | Permite probing de códigos sin autenticación — retorna valid/invalid | Requerir userId válido o devolver 401 genérico si no autenticado |
| **M-5** | **Notification URL expone client_id** | `createPreferenceUnified()` notification_url | UUID de tenant visible en URLs de webhook que pasan por infraestructura MP | Considerar usar token opaco mapeado a client_id en lugar del UUID directo |
| **M-6** | **Amount validation 1% tolerance** | `confirmPayment()` | Permite variación de ~1% en monto pagado vs esperado (suficiente para FX pero podría explotarse en montos grandes) | Documentar tolerancia y monitorear desviaciones; considerar threshold absoluto adicional |

### 🟢 Informativos

| # | Finding | Ubicación |
|---|---------|-----------|
| **I-1** | Quote/settings cache in-memory (shipping + payments) con 5-30min TTL | shipping-quote, shipping-settings, client-payment-settings |
| **I-2** | DTO legacy `add-item-to-cart.dto.ts` no referenciado | cart module |
| **I-3** | SMTP multi-provider fallback con 6+ candidatos de host/port | mercadopago.service.ts |
| **I-4** | QR code con signed URL (30d TTL) en bucket product-images | mercadopago.service.ts |
| **I-5** | Métodos deprecated no eliminados (`handleSubscriptionEvent`, `reconcileSubscriptions`) | mercadopago.service.ts |
| **I-6** | `updateStock()` hace fallback por nombre si producto fue eliminado | mercadopago.service.ts — correcto para resiliencia pero podría matchear producto equivocado si hay nombres duplicados |

---

## 11. Recommendations

### Prioridad Alta

#### 1. [C-1] Restaurar stock en cancel/refund

En `markOrderPaymentStatus()`, cuando `mappedOrderStatus === 'cancelled' || 'refunded'` y la orden tiene `stock_reserved=true`, ejecutar `restore_stock_bulk`:

```typescript
// En markOrderPaymentStatus(), junto al coupon reversal existente:
if (['cancelled', 'refunded'].includes(mappedOrderStatus)) {
  // Ya existe: reversión de cupón
  if (order.coupon_id) {
    await this.storeCouponsService.reverseRedemption(...);
  }
  // AGREGAR: restauración de stock
  if (order.stock_reserved && order.order_items?.length) {
    const stockItems = order.order_items
      .filter(i => !['service_fee','reserve_item','order_total'].includes(i.product_id))
      .map(i => ({ product_id: i.product_id, quantity: i.quantity }));
    if (stockItems.length) {
      await supabase.rpc('restore_stock_bulk', { items: stockItems });
    }
  }
}
```

#### 2. [C-2] Atomizar incrementUsage de platform coupons

```typescript
// En coupons.service.ts, reemplazar:
//   const coupon = await supabase.from('coupons')...select('current_usage')
//   await supabase.from('coupons')...update({ current_usage: coupon.current_usage + 1 })
// Por:
const { data, error } = await supabase.rpc('increment_coupon_usage', { 
  coupon_id: couponId 
});
// Donde el RPC es:
// CREATE OR REPLACE FUNCTION increment_coupon_usage(p_coupon_id uuid)
// RETURNS int AS $$
//   UPDATE coupons SET current_usage = current_usage + 1
//   WHERE id = p_coupon_id AND (max_usage IS NULL OR current_usage < max_usage)
//   RETURNING current_usage;
// $$ LANGUAGE sql;
```

### Prioridad Media

#### 3. [M-1/M-2] Migrar locks y rate limits a store distribuido

Para ambientes multi-replica:
- **Locks**: Redis `SETNX` con TTL o tabla `processing_locks(lock_key PK, expires_at)` con cleanup periódico
- **Rate limits**: Redis sliding window o middleware con store externo

#### 4. [M-3] Agregar tracking per-account en platform coupons

```sql
CREATE TABLE coupon_usages (
  coupon_id uuid REFERENCES coupons(id),
  account_id uuid NOT NULL,
  used_at timestamptz DEFAULT now(),
  PRIMARY KEY (coupon_id, account_id)
);
```

#### 5. [M-4] Agregar auth check al validate de store coupons

```typescript
// En store-coupons.controller.ts, antes de llamar validate:
if (!userId) {
  throw new UnauthorizedException('Se requiere autenticación para validar cupones');
}
```

### Prioridad Baja

#### 6. [I-2] Eliminar DTO legacy

Borrar `src/cart/dto/add-item-to-cart.dto.ts` para evitar confusión.

#### 7. [I-5] Eliminar deprecated methods

Remover `handleSubscriptionEvent()` y `reconcileSubscriptions()` del MercadoPagoService una vez confirmado que el migration a MpRouterService está completo.

---

## 12. Apéndice: DB Tables por Flujo

### A. Checkout completo (happy path)

```
FASE 1 — CREAR PREFERENCIA:
  cart_items ─── READ ──→ productos del carrito
  products ──── READ ──→ validar stock + calcular precios
  products ──── RPC  ──→ decrement_stock_bulk_strict (reserva atómica)
  store_coupons ── READ ──→ validar cupón (si aplica)
  store_coupon_targets ── READ ──→ targets del cupón
  user_addresses ── READ/WRITE ──→ dirección de envío
  client_shipping_settings ── READ ──→ config de envío
  client_payment_settings ── READ ──→ config de pagos
  orders ─────── INSERT ──→ pre-order (payment_status='pending', stock_reserved=true)
  order_payment_breakdown ── INSERT ──→ snapshot financiero
  mp_idempotency ── UPSERT ──→ registro de idempotencia
  ──→ MP API: create preference (externo)

FASE 2 — WEBHOOK (payment.approved):
  tenant_payment_events ── INSERT ──→ deduplicación
  ──→ MP API: GET /v1/payments/:id (externo)
  orders ─────── UPDATE ──→ payment_status='approved', status='paid'
  store_coupon_redemptions ── INSERT via RPC ──→ redimir cupón
  email_jobs ──── UPSERT ──→ programar email de confirmación
  cart_items ──── DELETE ──→ limpiar carrito del usuario
  product-images bucket ── UPLOAD ──→ QR code con signed URL

FASE 2b — WEBHOOK (payment.cancelled/refunded):
  tenant_payment_events ── INSERT ──→ deduplicación
  orders ─────── UPDATE ──→ payment_status, status
  store_coupon_redemptions ── UPDATE via RPC ──→ reversión del cupón
  ⚠️ products.quantity ── NOT RESTORED ──→ stock perdido (ver C-1)
```

### B. Tablas por módulo

| Módulo | Tablas DB |
|--------|-----------|
| **Cart** | `cart_items`, `products` |
| **Orders** | `orders`, `users`, `email_jobs` |
| **Payments** | `client_payment_settings`, `client_extra_costs`, `client_mp_fee_overrides`, `mp_fee_table`, `order_payment_breakdown` |
| **MercadoPago** | `orders`, `products`, `cart_items`, `user_addresses`, `mp_idempotency`, `email_jobs`, `nv_accounts`, `clients` |
| **Webhook Router** | `tenant_payment_events`, `subscription_events`, `orders` |
| **Platform Coupons** | `coupons` (Admin DB) |
| **Store Coupons** | `store_coupons`, `store_coupon_targets`, `store_coupon_redemptions`, `clients` |
| **Shipping** | `shipping_integrations`, `client_shipping_settings`, `shipping_zones`, `orders` |

### C. Guards por módulo

| Módulo | Guards | Roles requeridos |
|--------|--------|-----------------|
| Cart | `ClientContextGuard` | any authenticated |
| Orders (read) | `ClientContextGuard` | owner or admin |
| Orders (write) | `ClientContextGuard` + `RolesGuard` | admin, super_admin |
| Payments (storefront) | `ClientContextGuard` | any authenticated |
| Payments (admin) | `TenantContextGuard` + `RolesGuard` + `PlanAccessGuard` | admin, super_admin |
| MercadoPago | `ValidationPipe` (class-level, no auth en algunos) | varies per endpoint |
| Webhook Routes | `@AllowNoTenant()` | none (HMAC verified) |
| Platform Coupons | `BuilderOrSupabaseGuard` / `SuperAdminGuard` | super_admin (CRUD) |
| Store Coupons (admin) | `RolesGuard` + `PlanAccessGuard` | admin, super_admin |
| Store Coupons (validate) | `PlanAccessGuard` | any (⚠️ sin auth check) |
| Shipping | `ClientContextGuard` + `PlanAccessGuard` | admin (integrations), any (quote) |

---

*Fin de la auditoría. Documento generado por inspección de código sin ejecución de credenciales ni conexión a servicios externos.*

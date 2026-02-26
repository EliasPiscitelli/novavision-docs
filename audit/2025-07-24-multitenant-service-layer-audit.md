# Auditoría Multi-Tenant — Service Layer (client_id filtering)

**Fecha:** 2025-07-24
**Autor:** agente-copilot
**Alcance:** Capa de servicios NestJS (`src/**/*.service.ts`) — verificación de filtrado por `client_id` en **todas** las queries a Supabase.
**Rama:** `feature/automatic-multiclient-onboarding`

---

## Resumen Ejecutivo

Se auditaron **12 servicios críticos** de forma exhaustiva (lectura completa) y **6 servicios adicionales** mediante grep + lectura parcial. El backend opera con `SUPABASE_ADMIN_CLIENT` (service_role) que **bypasea RLS** en todas las tablas, por lo que el aislamiento multi-tenant depende **exclusivamente** del filtrado manual `.eq('client_id', clientId)` en cada query.

### Resultado global

| Severidad | Hallazgos |
|-----------|-----------|
| 🔴 CRÍTICO | 1 — `searchProductsWithRelevance()` sin client_id (código muerto, no invocado) |
| 🟠 MEDIO-ALTO | 1 — `validateStock()` con client_id opcional |
| 🟡 MEDIO | 2 — Queries a option_sets/size_guides sin client_id; `getHealthStatus()` sin scope |
| 🔵 BAJO | 2 — Updates por ID único sin client_id redundante |
| ✅ LIMPIO | 10+ servicios sin hallazgos |

---

## 1. Infraestructura Supabase

### Clientes Supabase (`src/supabase/supabase.module.ts`)

| Token | Tipo | Uso | Bypassea RLS |
|-------|------|-----|:---:|
| `SUPABASE_CLIENT` | anon key | No usado en services críticos | ❌ |
| `SUPABASE_ADMIN_CLIENT` | service_role | **Todos los services de negocio** | ✅ |
| `SUPABASE_ADMIN_DB_CLIENT` | service_role (Admin DB) | Onboarding, billing, accounts | ✅ |
| `SUPABASE_METERING_CLIENT` | service_role (Admin DB) | Métricas/usage | ✅ |

> **Implicancia:** Como TODOS los services usan `SUPABASE_ADMIN_CLIENT`, RLS no actúa como red de seguridad. La ÚNICA línea de defensa es el filtro manual `.eq('client_id', clientId)`.

### Request-Scoped Client (`src/supabase/request-client.helper.ts`)

`makeRequestSupabaseClient()` crea un cliente con JWT + `x-client-id`. Se usa opcionalmente en algunos métodos vía parámetro `cli?: SupabaseClient`, pero la mayoría de los services inyectan directamente el admin client.

---

## 2. Hallazgos por Servicio (detallados)

---

### 🔴 CRÍTICO — `products.service.ts` → `searchProductsWithRelevance()`

**Archivo:** `src/products/products.service.ts` (línea ~1760)
**Tipo:** Código muerto (no invocado actualmente desde ningún controller ni servicio)

```typescript
async searchProductsWithRelevance(
  query: string,
  categoryIds: string[] = [],
  limit: number = 10,
): Promise<any[]> {
  let queryBuilder = this.adminClient
    .from('products')
    .select('*')
    .or(`name.ilike.%${query}%,...`);
  // ❌ NO HAY .eq('client_id', clientId) en NINGUNA parte del método
  // ❌ product_categories también se consulta sin client_id
```

**Riesgo:** Si alguien conecta este método a un endpoint, expone **TODOS** los productos de **TODOS** los tenants en una búsqueda abierta.

**Estado:** NO invocado. Confirmado via grep que la única referencia es la definición del método y un doc de cambios previo.

**Recomendación:** Eliminar el método o agregar `clientId: string` como parámetro obligatorio con `.eq('client_id', clientId)`.

---

### 🟠 MEDIO-ALTO — `mercadopago.service.ts` → `validateStock()`

**Archivo:** `src/tenant-payments/mercadopago.service.ts` (línea ~1150)

```typescript
async validateStock(
  cartItems: any[],
  clientId?: string,    // ← OPCIONAL
  cli?: SupabaseClient,
): Promise<void> {
  // ...
  let q = db.from('products').select('id, name, quantity').eq('id', item.product_id);
  if (clientId) q = q.eq('client_id', clientId);  // ← solo si hay clientId
```

**Riesgo:** Si se invoca sin `clientId`, valida stock sin filtro de tenant → podría leer datos de productos de otro tenant.

**Uso actual:** El controller en `mercadopago.controller.ts` (línea ~600) **SÍ pasa clientId:**
```typescript
const clientIdForValidate = this.extractClientId(req);
await this.mercadoPagoService.validateStock(cartItems, clientIdForValidate, cli);
```

**Riesgo residual:** Medio. El parámetro opcional permite que futuros llamadores omitan client_id por error. La firma del método debería hacer `clientId` obligatorio.

**Recomendación:** Cambiar `clientId?: string` → `clientId: string` (parámetro requerido).

---

### 🟡 MEDIO — `products.service.ts` → `resolveOptionsForProduct()` / `resolveProductColors()`

**Archivo:** `src/products/products.service.ts` (líneas ~262, ~343)

```typescript
// resolveOptionsForProduct(): consulta option_sets por ID del producto
const { data: setData } = await cli
  .from('option_sets')
  .select('..., items:option_set_items(...)')
  .eq('id', product.option_set_id);  // ❌ sin .eq('client_id', ...)

// resolveProductColors(): consulta option_set_items por IDs del config
const { data: colorItems } = await cli
  .from('option_set_items')
  .select('...')
  .in('id', colorIds);  // ❌ sin client_id

// size_guides también se consulta sin client_id:
const { data: sizeGuideCheck } = await cli
  .from('size_guides')
  .select('id')
  .or(`product_id.eq.${product.id},option_set_id.eq.${product.option_set_id}`);
```

**Análisis:** `option_sets` son tablas híbridas con datos globales (presets, `client_id IS NULL`) y datos por tenant. Los IDs consultados provienen del producto que ya fue filtrado por `client_id`. El riesgo es **indirecto**: si un ID de option_set de otro tenant se inyectara en `product.option_set_id`, se resolvería correctamente.

**Riesgo real:** Bajo-medio. La cadena de confianza depende de que `product.option_config` y `product.option_set_id` siempre contengan IDs válidos del mismo tenant o globales.

**Recomendación:** Agregar filtro `.or(\`client_id.eq.${clientId},client_id.is.null\`)` en option_sets, y verificar `size_guides` tenga client_id en su query.

---

### 🟡 MEDIO — `shipping.service.ts` → `getHealthStatus()`

**Archivo:** `src/shipping/shipping.service.ts` (línea ~928)

```typescript
async getHealthStatus() {
  const { count: recentShipments } = await this.supabase
    .from('shipments').select('id', { count: 'exact', head: true })
    .gte('created_at', since);  // ❌ sin client_id

  const { count: activeIntegrations } = await this.supabase
    .from('shipping_integrations').select('id', { count: 'exact', head: true })
    .eq('is_active', true);  // ❌ sin client_id
```

**Análisis:** Claramente un endpoint de health/admin global — no debería estar scoped por tenant. Pero si se expone a usuarios no-admin, revela conteos cross-tenant.

**Recomendación:** Verificar que el controller que invoca este método solo lo permite a super_admin o rutas internas. Documentar la excepción.

---

### 🔵 BAJO — `payments.service.ts` → `processPaymentUpdate()`

**Archivo:** `src/payments/payments.service.ts` (línea ~316)

```typescript
// Lookup por payment_id sin client_id
const { data: order } = await this.supabase
  .from('orders').select('*').eq('payment_id', paymentId).maybeSingle();

// Lookup por provider_payment_id sin client_id
const { data: payment } = await this.supabase
  .from('payments').select('*').eq('provider_payment_id', providerId).maybeSingle();
```

**Análisis:** `payment_id` y `provider_payment_id` son identificadores de MercadoPago, globalmente únicos por su naturaleza. El riesgo de colisión cross-tenant es despreciable.

**Recomendación:** Agregar `.eq('client_id', clientId)` como defensa en profundidad si el clientId está disponible en el contexto.

---

### 🔵 BAJO — `orders.service.ts` → `sendConfirmation()`

**Archivo:** `src/orders/orders.service.ts` (línea ~664)

```typescript
// Actualización final de email_attempts sin client_id
await this.supabase.from('orders')
  .update({ email_attempts: order.email_attempts })
  .eq('id', order.id);  // ← solo por ID, sin .eq('client_id', clientId)
```

**Análisis:** El `order.id` es UUID único. La orden ya fue verificada con client_id en la query anterior del mismo método. Riesgo prácticamente nulo.

**Recomendación:** Agregar `.eq('client_id', clientId)` por consistencia.

---

### 🔵 BAJO / INTENCIONAL — `shipping.service.ts` → `handleProviderWebhook()`

**Archivo:** `src/shipping/shipping.service.ts` (línea ~780)

```typescript
// Webhook handler - NO tiene tenant context (diseño correcto para webhooks)
const { data: integrations } = await this.supabase
  .from('shipping_integrations')
  .select('id, client_id, credentials_enc')
  .eq('provider', providerName)
  .eq('active', true);  // ❌ sin client_id — INTENCIONAL

const { data: shipment } = await this.supabase
  .from('shipments')
  .select('*')
  .eq('provider', providerName)
  .eq('tracking_code', trackingCode);  // ❌ sin client_id — INTENCIONAL

await this.supabase.from('shipments')
  .update({ events: mergedEvents, status: latestStatus })
  .eq('id', shipment.id);  // Sin client_id — INTENCIONAL
```

**Análisis:** Los webhooks de providers de shipping llegan sin contexto de tenant. El shipment se identifica por `provider + tracking_code` (combinación única). Después de encontrar el shipment, `shipment.client_id` se usa para `syncOrderShipping`. Patrón correcto para webhooks.

**Recomendación:** Agregar `.eq('client_id', shipment.client_id)` al update final como defensa en profundidad.

---

### ✅ INTENCIONAL — `store-coupons.service.ts` → `listCrossTenant()` / `crossTenantStats()`

**Archivo:** `src/store-coupons/store-coupons.service.ts` (líneas ~682, ~740)

Funciones explícitamente diseñadas para Super Admin. Consultan sin client_id por diseño. El controller debe gates acceso con `role === 'super_admin'`.

---

## 3. Servicios Auditados — Sin Hallazgos (✅ LIMPIO)

| Servicio | Líneas | Queries | Resultado |
|----------|--------|---------|-----------|
| `cart.service.ts` | 476 | 10+ | ✅ Todas filtran por `client_id` + `user_id` |
| `orders.service.ts` | 672 | 12+ | ✅ Todas filtran por `client_id` (salvo hallazgo BAJO arriba) |
| `client-payment-settings.service.ts` | 133 | 1 | ✅ `.eq('client_id', clientId)` + cache |
| `shipping-settings.service.ts` | 400 | 8+ | ✅ Todas CRUD + zones con `client_id` |
| `store-coupons.service.ts` | 773 | 15+ | ✅ Todas con `client_id` (cross-tenant intencional para SA) |
| `categories.service.ts` | ~100 | 5 | ✅ Todas filtran por `client_id` |
| `users.service.ts` | ~310 | 12 | ✅ Todas filtran por `client_id` |
| `favorites.service.ts` | ~230 | 7+ | ✅ Todas filtran por `client_id` + `user_id` |
| `banner.service.ts` | ~250+ | 15+ | ✅ Todas filtran por `client_id` |
| `themes.service.ts` | ~140 | 5 | ✅ Verifica `user.client_id === clientId` + `.eq('client_id', clientId)` |
| `option-sets.service.ts` | ~230+ | 10+ | ✅ Dual: `.or(client_id.eq.X, and(client_id.is.null, is_preset.eq.true))` |
| `reviews.service.ts` | ~400+ | 10+ | ✅ Todas filtran por `client_id`, RPCs pasan `p_client_id` |

---

## 4. Servicios NO Auditados (fuera de scope crítico)

Los siguientes servicios usan `SUPABASE_ADMIN_DB_CLIENT` (Admin DB, no multi-tenant de tiendas) o son auxiliares:

- `onboarding.service.ts`, `billing.service.ts`, `accounts.service.ts` → operan sobre Admin DB
- `redis.service.ts`, `encryption.service.ts`, `captcha.service.ts` → sin queries a Supabase de negocio
- `seo-ai-*.service.ts`, `meta-capi.service.ts` → auxiliares de SEO/analytics
- `demo.service.ts`, `dev-seeding.service.ts` → solo dev/staging
- `outbox.service.ts`, `outbox-worker.service.ts` → event sourcing interno
- `support*.service.ts`, `legal*.service.ts` → módulos secundarios

Estos servicios deberían auditarse en una segunda pasada si se consideran de riesgo.

---

## 5. Cómo se Obtiene el Supabase Client

| Patrón | Frecuencia | Seguro |
|--------|:----------:|:------:|
| `@Inject('SUPABASE_ADMIN_CLIENT')` → `this.supabase` / `this.adminClient` | ~90% | ⚠️ Bypasea RLS — depende de filtro manual |
| `makeRequestSupabaseClient(req, adminClient)` → cli con JWT | ~5% (favorites, algunos métodos) | ✅ Propaga JWT + x-client-id |
| Parámetro `cli?: SupabaseClient` (request-scoped) | ~5% | ✅ Si se pasa; ⚠️ fallback a admin client |

---

## 6. RPCs y Raw SQL

| Servicio | RPC | Pasa `p_client_id` |
|----------|-----|:---:|
| `products.service.ts` | `search_products` | ✅ |
| `store-coupons.service.ts` | `redeem_store_coupon`, `reverse_store_coupon_redemption` | ✅ |
| `mercadopago.service.ts` | `decrement_product_stock` y otros | ✅ |
| `reviews.service.ts` | Varios RPCs | ✅ |
| `favorites.service.ts` | `merge_favorites` | ✅ |

No se encontró uso de raw SQL sin parámetros de tenant.

---

## 7. Recomendaciones Priorizadas

### P0 — Inmediato
1. **Eliminar o proteger `searchProductsWithRelevance()`** — Código muerto que expone cross-tenant si se conecta. Agregar `clientId: string` obligatorio o borrar.
2. **Hacer `clientId` obligatorio en `validateStock()`** — Cambiar `clientId?: string` → `clientId: string`.

### P1 — Corto plazo
3. **Agregar client_id filter a `resolveOptionsForProduct()`** — Uso de `.or(\`client_id.eq.${clientId},client_id.is.null\`)` en option_sets y size_guides.
4. **Proteger `getHealthStatus()`** — Verificar que solo super_admin accede; documentar excepción.
5. **Agregar client_id redundante en webhooks** — En `handleProviderWebhook()`, usar `shipment.client_id` en el update.

### P2 — Mejora continua
6. **Estandarizar patrón de defensa** — Donde hay updates por `id` único (orders, shipments, payments), agregar `.eq('client_id', clientId)` como defensa en profundidad.
7. **Auditar servicios secundarios** — Pasar por support, legal, seo-ai, home-sections/settings, social-links, contact-info, logos en segunda ronda.

---

## 8. Checklist de Validación (para PR de fixes)

- [ ] `searchProductsWithRelevance()`: eliminado o con clientId obligatorio
- [ ] `validateStock()`: clientId es parámetro requerido (no optional)
- [ ] `resolveOptionsForProduct()`: option_sets filtrado por client_id OR is_preset
- [ ] `resolveProductColors()`: size_guides y option_set_items con scope de tenant
- [ ] `getHealthStatus()`: gateway/guard solo super_admin
- [ ] `handleProviderWebhook()`: update con client_id del shipment
- [ ] `sendConfirmation()`: update final incluye `.eq('client_id', clientId)`
- [ ] `processPaymentUpdate()`: lookups incluyen client_id si disponible
- [ ] Tests: verificar que usuario de Tenant A no ve/modifica datos de Tenant B en cada fix

---

*Auditoría generada automáticamente. Validar hallazgos antes de aplicar fixes.*

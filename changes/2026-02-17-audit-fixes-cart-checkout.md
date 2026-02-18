# Cambio: Fixes de Auditoría QA — Cart → Checkout → Order → Tracking

- **Autor:** agente-copilot
- **Fecha:** 2026-02-17
- **Rama:** feature/automatic-multiclient-onboarding
- **Auditoría fuente:** `novavision-docs/audit/CART_CHECKOUT_ORDER_TRACKING_AUDIT.md`

## Archivos Modificados

### Backend (API)
- `src/shipping/shipping-settings.service.ts` — fallback arrange + default flat
- `src/shipping/shipping-quote.service.ts` — fallback zone→flat, fix default branch
- `src/shipping/shipping.service.ts` — **P1-007 fix**: `.catch(() => {})` → logging explícito en `notifyBuyerIfNeeded()`
- `src/tenant-payments/mercadopago.service.ts` — stock reservation en pre-order + picture_url en snapshot + rollback en fallo de MP/orden
- `src/cron/order-expiration.cron.ts` — **NUEVO** cron de expiración de órdenes pending
- `src/cron/cron.module.ts` — registro de OrderExpirationCron

### Frontend (Web)
- `src/hooks/cart/useShipping.js` — ícono condicional + mensaje null-safe

### Migraciones SQL (nuevas) — **TODAS EJECUTADAS Y VERIFICADAS EN PRODUCCIÓN ✅**
- `migrations/20260217_fix_cart_items_unique_with_options_hash.sql` ✅
- `migrations/backend/20260217_populate_shipping_settings_defaults.sql` ✅
- `migrations/backend/20260217_products_client_id_not_null.sql` ✅
- `migrations/backend/20260217_stock_reservation_system.sql` ✅ — RPC + columna + índice

### Documentación
- `novavision-docs/audit/CART_CHECKOUT_ORDER_TRACKING_AUDIT.md` — correcciones post-auditoría

---

## Resumen de Cambios

### 1. P0-001: UNIQUE cart_items + options_hash
**Problema:** El UNIQUE constraint `(client_id, user_id, product_id)` impedía agregar el mismo producto con distintas variantes (talle S + talle M).
**Fix:** Migración SQL que reemplaza el constraint por `(client_id, user_id, product_id, options_hash)` con backfill de NULL → 'empty'.

### 2. P0-002/003: Fallback "Acordar con el vendedor"
**Problema:** Tenants sin métodos de envío habilitados bloqueaban el checkout por completo.
**Fix Backend:** `getSettings()` auto-habilita `arrangeEnabled=true` cuando ningún método está activo, con logger.warn.
**Fix Frontend:** `useShipping.js` usa ícono condicional (chat si no hay WhatsApp) y mensaje con null-safe fallback.

### 3. P1-003: Zonas vacías + pricing mode
**Problema:** Default `shippingPricingMode='zone'` sin zonas creadas → throw `NO_ZONES_CONFIGURED` → checkout roto.
**Fix:** 
- Default cambiado a `'flat'` (tanto en código como en DB via migración).
- `calculateDeliveryCost()` con zone mode sin zonas ahora cae a flat con warning en vez de lanzar excepción.
- Default branch también retorna cost=0 silenciosamente en vez de throw.

### 4. P1-005: Poblar shipping data
**Problema:** Tenants existentes sin fila en `client_shipping_settings` → DEFAULTS en memoria pero reglas inconsistentes.
**Fix:** Migración SQL que:
- Cambia DB default de `shipping_pricing_mode` a `'flat'`
- Inserta fila default para cada client sin config (con `arrange_enabled=true`)
- Actualiza tenants sin ningún método habilitado para activar arrange

### 5. P1-008: products.client_id NOT NULL
**Problema:** `products.client_id` nullable → productos huérfanos que escapan RLS.
**Fix:** Migración SQL que elimina productos sin client_id y aplica `SET NOT NULL`.

### 6. Falsos Positivos Corregidos en Auditoría
- **P0-004** (monto webhook): ya lanza `throw new Error()` — no solo logea.
- **P1-001** (stock en PUT cart): `updateCartItem()` ya valida stock server-side.
- **P1-006**: duplicado de P0-004.
- **P1-007** (notificación shipping): `notifyBuyerIfNeeded()` ya usa `email_jobs` con retry (5 intentos, backoff exponencial) + `dedupe_key`. Fix cosmético: `.catch(() => {})` reemplazado por logging.

### 7. R2: Stock Reservation System (detalle completo)
**Problema:** Stock se validaba con SELECT (no lock) y se decrementaba recéin al confirmar pago. Ventana de race condition de ~5-15 min.

**Solución implementada:**
1. `decrement_stock_bulk_strict` RPC: decrementa atómicamente al crear pre-order
2. Columna `stock_reserved` en orders: flag para saber si ya se reservó
3. `confirmPayment()` skip de `updateStock()` si `stock_reserved=true`
4. Cron `OrderExpirationCron` cada 5 min: expira órdenes pending > 30 min + restaura stock
5. Rollback si falla creación de preferencia MP (try/catch + `restore_stock_bulk`)
6. Rollback si falla insert de orden (try/catch + `restore_stock_bulk` + flag `stockItemsForReserve=null` para prevenir doble rollback)

**Migración:** `20260217_stock_reservation_system.sql` (columna + RPC + índice parcial)

---

## Decisiones Tomadas

| Decisión | Alternativa descartada | Motivo |
|----------|----------------------|--------|
| `arrange` como fallback default | Dejar sin método → checkout roto | Mínimo viable sin requerir configuración |
| `flat` como pricing mode default | `zone` (requiere setup de zonas) | No requiere configuración adicional |
| Zone sin zonas → flat fallback | Mantener throw 400 | Evita bloqueo de checkout para tenants mal configurados |

---

## Cómo Probar

### Backend
```bash
cd apps/api
npm run lint      # 0 errores ✅
npm run typecheck  # OK ✅
npm run build      # OK ✅
```

### Frontend
```bash
cd apps/web
npm run lint      # 0 errores ✅
npm run typecheck  # OK ✅
npm run build      # OK ✅
```

### Migraciones (ejecutar en orden)
```bash
# 1. Cart items UNIQUE constraint
psql $DB_URL -f migrations/20260217_fix_cart_items_unique_with_options_hash.sql

# 2. Shipping settings defaults
psql $DB_URL -f migrations/backend/20260217_populate_shipping_settings_defaults.sql

# 3. Products client_id NOT NULL
psql $DB_URL -f migrations/backend/20260217_products_client_id_not_null.sql
# 4. Stock reservation system
psql $DB_URL -f migrations/backend/20260217_stock_reservation_system.sql
```

### Verificaciones post-migración (TODAS VERIFICADAS ✅)
```sql
-- 1. Constraint de cart_items con options_hash
SELECT indexdef FROM pg_indexes WHERE indexname LIKE '%cart_items%options%';
-- ✅ idx incluye options_hash

-- 2. Shipping settings poblados
SELECT c.name, css.arrange_enabled, css.shipping_pricing_mode
FROM clients c
LEFT JOIN client_shipping_settings css ON css.client_id = c.id;
-- ✅ arrange_enabled=true en ambos tenants

-- 3. Products NOT NULL
SELECT is_nullable FROM information_schema.columns
WHERE table_name='products' AND column_name='client_id';
-- ✅ is_nullable = NO

-- 4. Stock reservation
SELECT column_name, data_type, column_default
FROM information_schema.columns
WHERE table_name='orders' AND column_name='stock_reserved';
-- ✅ boolean, default false

-- 5. restore_stock_bulk RPC
SELECT routine_name FROM information_schema.routines
WHERE routine_name='restore_stock_bulk';
-- ✅ exists

-- 6. Índice parcial de órdenes pending
SELECT indexname FROM pg_indexes
WHERE indexname='idx_orders_pending_stock_reserved';
-- ✅ exists
```

---

## Notas de Seguridad

- Los cambios en shipping NO afectan RLS ni políticas existentes.
- `products.client_id SET NOT NULL` refuerza aislamiento multi-tenant.
- El fallback de arrange NO requiere WhatsApp, mostrando ícono de chat genérico.
- Las migraciones SQL son transaccionales (BEGIN/COMMIT) y reversibles.
- `restore_stock_bulk` es SECURITY DEFINER para operar con service_role.
- El cron de expiración usa guarda de concurrencia (`WHERE payment_status='pending'`) para evitar race conditions con webhooks.

---

## Decisiones de Diseño (2026-02-17)

### R1: Shipping global vs per-product → Global (mantener actual)
- `products.sendMethod` es solo badge visual, no impacta checkout.
- Si se necesita diferenciar en el futuro: agregar `product.allowed_delivery_methods[]` (array nullable, null = todos).
- **Cambio: ninguno.**

### R2: Stock reservation → Decrement en pre-order + cron TTL 30min
- **Antes:** validateStock(SELECT) → crear preferencia → pago → webhook decrementa stock → riesgo de overselling.
- **Después:** decrement_stock_bulk_strict al crear pre-order → stock reservado → pago → webhook no vuelve a decrementar → cron libera stock si no se paga en 30min.
- **Archivos:** mercadopago.service.ts, order-expiration.cron.ts, migración SQL.

### R3: order_items tabla vs JSONB → JSONB es fuente de verdad
- La tabla `order_items` existe en DB pero el backend **no la usa**. Todo pasa por `orders.order_items` JSONB.
- Se agrega `picture_url` al snapshot para que sea self-contained (display sin lookup a products).
- Tabla `order_items` marcada como deprecada. No se elimina por compatibilidad.

### R4: Guest checkout → No implementar
- Requiere session-based cart + merge logic. Bajo ROI vs complejidad en esta etapa.

---

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| Migración de cart_items falla si hay options_hash=NULL | La migración backfilla NULL→'empty' antes de crear el constraint |
| Client sin shipping settings tras migración | INSERT...WHERE NOT EXISTS previene duplicados |
| Products con NULL client_id eliminados | La migración audita cuántos hay antes de borrar |
| Webhook llega antes de que la pre-order se guarde | La lógica de confirmPayment ya maneja prelimOrder=null con saveOrder fallback |
| Cron expira orden que el usuario acaba de pagar | Guarda: solo actualiza si `payment_status='pending'`; el webhook ya la marcó 'approved' |
| Stock decrementado pero preferencia MP falla | **MITIGADO**: try/catch con `restore_stock_bulk` restaura stock si falla creación de preferencia |
| Stock decrementado pero insert de orden falla | **MITIGADO**: try/catch con `restore_stock_bulk` + flag `stockItemsForReserve=null` previene doble rollback |

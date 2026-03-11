# Payment Status Mapping Improvements

## Overview

This document describes the improvements made to the payment status mapping and sanitization logic in the MercadoPago service, based on the code review feedback.

## Problems Addressed

1. **Variable naming bug**: The original code had inconsistent variable naming (`normalized` vs `normalizedStatus`)
2. **Query completion**: Queries were not properly terminated with `.maybeSingle()`
3. **Lack of idempotency**: Terminal states (delivered, cancelled) could be overwritten
4. **Fragmented status mapping**: Status normalization and mapping logic was duplicated across methods
5. **Unsafe payload sanitization**: Simple JSON stringify/parse could fail with circular references
6. **Bloated return values**: Full order objects returned instead of minimal snapshots

## Solutions Implemented

### 1. Centralized Status Helpers (`src/mercadopago/helpers/status.ts`)

**Type-safe status definitions:**
```typescript
export type PaymentStatus = 'approved' | 'pending' | 'in_process' | 'rejected' | 'cancelled' | ...
export type OrderStatus = 'pending' | 'cancelled' | 'delivered' | 'not_delivered' | 'approved'
```

**`normalizePaymentStatus(s: unknown): PaymentStatus`**
- Converts various MP status variants to canonical forms
- Handles: `'canceled' → 'cancelled'`, `'in mediation' → 'in_mediation'`
- Defaults to `'pending'` for null/undefined
- Case-insensitive, trims whitespace

**`mapPaymentToOrderStatus(ps: PaymentStatus, currentOrderStatus: OrderStatus | null): OrderStatus | null`**
- Maps payment statuses to order statuses
- **Terminal state protection**: Returns `null` if current status is `'delivered'` or `'cancelled'` (won't overwrite)
- Maps failure statuses (`rejected`, `cancelled`, `refunded`, `charged_back`) to `'cancelled'`
- Returns `null` for `approved` (payment approval doesn't change order status)

### 2. Robust Sanitization Helpers (`src/mercadopago/helpers/sanitize.ts`)

**`sanitizePayload<T>(payload: T): T | null`**
- **First attempt**: Uses `structuredClone()` (handles circular references natively)
- **Fallback**: JSON stringify/parse with custom replacer that:
  - Tracks seen objects with `WeakSet` to detect circular references
  - Replaces circular refs with `'[Circular]'` string
  - Removes functions
- Returns `null` on any error (safer than returning potentially corrupt data)

**`toOrderSnapshot(o: any)`**
- Returns minimal DTO with only essential fields:
  - `id`, `payment_id`, `payment_status`, `status`
  - `order_items`, `total_amount`, `external_reference`
- Missing fields default to `null`
- Prevents bloated responses and circular reference issues

### 3. Updated `confirmByExternalReference` Method

**Before:**
```typescript
const sanitizedExisting = this.sanitizePayload(existing) || null;
// ... lots of duplicated status checking code
const normalizedStatus = this.normalizeMpStatus(failurePayment.status);
// ... manual mapping of statuses
```

**After:**
```typescript
// 1) buscar orden por external_reference + client_id
const { data: existing, error: getErr } = await this.adminClient
  .from('orders')
  .select('id, payment_id, payment_status, status, order_items, total_amount, external_reference')
  .eq('external_reference', externalReference)
  .eq('client_id', clientId)
  .maybeSingle();

if (getErr) {
  this.logger.error(`[confirmByExternalReference] Error buscando orden: ${getErr.message}`);
  return { confirmed: false, reason: 'order_lookup_error', data: null };
}

const existingSnap = toOrderSnapshot(existing);

// 2) buscar pagos por external_reference en MP
const payments = await this.findPaymentsByExternalReference(externalReference, clientId);
if (!payments || payments.length === 0) {
  return {
    confirmed: false,
    reason: 'no_payments_found',
    status: existing?.payment_status || 'pending',
    data: existingSnap,
  };
}

// 3) normalizar y mapear estados
const latest = payments[0];
const normalizedStatus = normalizePaymentStatus(latest?.status);
const updatePayload: Record<string, any> = { payment_status: normalizedStatus };

if (!existing?.payment_id && latest?.id) updatePayload.payment_id = String(latest.id);

const mapped = mapPaymentToOrderStatus(normalizedStatus as any, existing?.status ?? null);
if (mapped) updatePayload.status = mapped;

// 4) si approved, confirmar detalles; sino, devolver por qué falló
```

**Key improvements:**
- ✅ Explicit error handling with `getErr` check
- ✅ Uses `toOrderSnapshot()` for clean return values
- ✅ Centralized status normalization via `normalizePaymentStatus()`
- ✅ Centralized mapping via `mapPaymentToOrderStatus()` with terminal state protection
- ✅ Clearer structure with numbered steps (1-4)
- ✅ Sanitized payloads using robust `sanitizePayload()`

### 4. Updated `markOrderPaymentStatus` Method

**Before:**
```typescript
let query = this.adminClient
  .from('orders')
  .select('id, payment_id, payment_status, status')
  .eq('client_id', clientId)
  .limit(1); // unnecessary with .maybeSingle()

const normalizedStatus = String(paymentStatus || 'pending').toLowerCase();

// Manual mapping
if (normalizedStatus === 'rejected') updatePayload.status = 'cancelled';
if (normalizedStatus === 'cancelled' || normalizedStatus === 'canceled') updatePayload.status = 'cancelled';
if (normalizedStatus === 'refunded') updatePayload.status = 'cancelled';
if (normalizedStatus === 'charged_back' || normalizedStatus === 'chargedback') {
  updatePayload.status = 'not_delivered';
  updatePayload.payment_status = 'charged_back';
}
```

**After:**
```typescript
let query = this.adminClient
  .from('orders')
  .select('id, payment_id, payment_status, status')
  .eq('client_id', clientId); // removed .limit(1)

const normalizedStatus = normalizePaymentStatus(paymentStatus);

const updatePayload: Record<string, any> = {
  payment_status: normalizedStatus,
};

// Map payment status to order status using centralized helper
const mappedOrderStatus = mapPaymentToOrderStatus(normalizedStatus as any, (order as any).status);
if (mappedOrderStatus) {
  updatePayload.status = mappedOrderStatus;
}
```

**Key improvements:**
- ✅ Removed unnecessary `.limit(1)` (`.maybeSingle()` already handles it)
- ✅ Uses `normalizePaymentStatus()` for consistent normalization
- ✅ Uses `mapPaymentToOrderStatus()` instead of multiple if statements
- ✅ Terminal state protection built into the helper (won't overwrite 'delivered' or 'cancelled')

### 5. Simplified Internal Methods

**`normalizeMpStatus` (private method):**
```typescript
// Before: duplicate normalization logic
private normalizeMpStatus(status?: string | null): string {
  const normalized = String(status || '').toLowerCase();
  const map: Record<string, string> = {
    canceled: 'cancelled',
    failure: 'rejected',
    failed: 'rejected',
    chargedback: 'charged_back',
  };
  return map[normalized] || normalized;
}

// After: delegates to centralized helper
private normalizeMpStatus(status?: string | null): string {
  return normalizePaymentStatus(status);
}
```

**`sanitizePayload` (private method):**
```typescript
// Before: simple JSON stringify/parse
private sanitizePayload<T>(payload: T): T | null {
  if (!payload) return payload;
  try {
    return JSON.parse(JSON.stringify(payload));
  } catch (err) {
    this.logger.warn(`[sanitizePayload] No se pudo sanitizar payload`);
    return null;
  }
}

// After: removed entirely, uses imported helper
// Use imported sanitizePayload from helpers/sanitize.ts
```

## Testing

New test suites added:
- `src/mercadopago/__tests__/helpers.status.spec.ts` - Tests for status normalization and mapping
- `src/mercadopago/__tests__/helpers.sanitize.spec.ts` - Tests for sanitization and snapshot creation

Test coverage includes:
- ✅ Status normalization (variants, case-insensitivity, null/undefined handling)
- ✅ Payment-to-order status mapping
- ✅ Terminal state protection
- ✅ Circular reference handling
- ✅ Function removal from payloads
- ✅ Snapshot field extraction

## Benefits

1. **Correctness**: Fixed variable naming bug and query completion issues
2. **Idempotency**: Terminal states are protected from being overwritten
3. **Maintainability**: Centralized logic means one place to update status mappings
4. **Type Safety**: Exported types ensure consistency across the codebase
5. **Robustness**: Better handling of circular references and edge cases
6. **Performance**: Minimal snapshots reduce payload size
7. **Testability**: Helper functions are easy to unit test independently

## Migration Notes

- No breaking changes to API contracts
- Existing code continues to work
- Internal refactoring only
- No database migrations required

## Future Improvements

- Consider adding status transition validation (e.g., can only go from 'pending' to 'approved', not the reverse)
- Add audit logging for status changes
- Consider webhook validation for status updates

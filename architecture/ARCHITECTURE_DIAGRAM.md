# Payment Status Architecture

## File Structure

```
src/mercadopago/
├── helpers/
│   ├── status.ts              (39 lines) - Status normalization & mapping
│   └── sanitize.ts            (37 lines) - Payload sanitization & snapshots
├── __tests__/
│   ├── helpers.status.spec.ts    (62 lines) - Status helper tests
│   └── helpers.sanitize.spec.ts  (134 lines) - Sanitize helper tests
└── mercadopago.service.ts     (refactored) - Uses helpers for consistency
```

## Flow Diagram

### confirmByExternalReference Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                  confirmByExternalReference                      │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
                   ┌──────────────────────┐
                   │  Validate inputs &   │
                   │  extract client/user │
                   └──────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Query order by external_reference          │
        │  .eq('external_reference', ref)             │
        │  .eq('client_id', clientId)                 │
        │  .maybeSingle()                             │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Check error: if (getErr)                   │
        │  return { confirmed: false,                 │
        │          reason: 'order_lookup_error' }     │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Create snapshot: toOrderSnapshot(existing) │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Already approved?                          │
        │  if (payment_status === 'approved')         │
        │  return { confirmed: true, data: snapshot } │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Find payments by external_reference        │
        │  (calls MP API)                             │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  No payments?                               │
        │  return { confirmed: false,                 │
        │          reason: 'no_payments_found' }      │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Get latest payment                         │
        │  normalizedStatus =                         │
        │    normalizePaymentStatus(latest.status)    │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Build update payload:                      │
        │  { payment_status: normalizedStatus }       │
        └─────────────────────────────────────────────┘
                              │
                              ▼
        ┌─────────────────────────────────────────────┐
        │  Map to order status:                       │
        │  mapped = mapPaymentToOrderStatus(          │
        │    normalizedStatus, existing.status)       │
        │  if (mapped) updatePayload.status = mapped  │
        └─────────────────────────────────────────────┘
                              │
                   ┌──────────┴──────────┐
                   │                     │
                   ▼                     ▼
          ┌─────────────┐      ┌─────────────────┐
          │  Approved?  │      │  Failure/Other  │
          └─────────────┘      └─────────────────┘
                   │                     │
                   ▼                     ▼
    ┌──────────────────────┐   ┌─────────────────────┐
    │ confirmPayment()     │   │ Update order with   │
    │ Sanitize details     │   │ payment status      │
    │ Return success       │   │ Return failure      │
    └──────────────────────┘   └─────────────────────┘
```

## Helper Function Details

### normalizePaymentStatus(status: unknown): PaymentStatus

```
Input: 'canceled', 'APPROVED', 'in mediation', null, etc.
  │
  ▼
Convert to string, lowercase, trim
  │
  ▼
Check variants:
  • 'canceled' → 'cancelled'
  • 'in mediation' → 'in_mediation'
  • null/undefined → 'pending'
  │
  ▼
Return normalized PaymentStatus
```

### mapPaymentToOrderStatus(ps: PaymentStatus, currentStatus: OrderStatus): OrderStatus | null

```
Input: payment status + current order status
  │
  ▼
Check terminal state:
  if (currentStatus === 'delivered' || 'cancelled')
    return null  ← DON'T OVERWRITE
  │
  ▼
Check payment status:
  • 'approved' → null (no change)
  • 'rejected', 'cancelled', 'refunded', 'charged_back' → 'cancelled'
  • other → null
  │
  ▼
Return mapped OrderStatus or null
```

### sanitizePayload<T>(payload: T): T | null

```
Input: any payload (may have circular refs)
  │
  ▼
Try structuredClone (native circular handling)
  │
  ├─ Success → return cloned object
  │
  └─ Failure
      │
      ▼
    Try JSON.stringify with custom replacer:
      • Track seen objects (WeakSet)
      • Replace circular refs with '[Circular]'
      • Remove functions
      │
      ├─ Success → return parsed object
      │
      └─ Failure → return null
```

### toOrderSnapshot(order: any)

```
Input: full order object (may have 50+ fields)
  │
  ▼
Extract only essential fields:
  • id
  • payment_id
  • payment_status
  • status
  • order_items
  • total_amount
  • external_reference
  │
  ▼
Return minimal DTO (7 fields instead of 50+)
```

## Benefits Summary

| Aspect | Before | After |
|--------|--------|-------|
| **Status Normalization** | Duplicated logic in 3+ methods | Single `normalizePaymentStatus()` |
| **Status Mapping** | Manual if/else chains | Single `mapPaymentToOrderStatus()` |
| **Terminal Protection** | None | Built into mapper |
| **Circular Refs** | `JSON.stringify` fails | `structuredClone` + fallback |
| **Response Size** | Full objects (50+ fields) | Minimal snapshots (7 fields) |
| **Type Safety** | `string` types | `PaymentStatus`, `OrderStatus` |
| **Testability** | Hard to test (embedded) | Easy (isolated functions) |
| **Maintainability** | Update 3+ places | Update 1 place |

## Testing Coverage

```
helpers.status.spec.ts (62 lines)
├── normalizePaymentStatus
│   ├── ✓ Normalizes 'canceled' → 'cancelled'
│   ├── ✓ Normalizes 'in mediation' → 'in_mediation'
│   ├── ✓ Handles uppercase/whitespace
│   ├── ✓ Returns 'pending' for null/undefined
│   └── ✓ Passes through valid statuses
└── mapPaymentToOrderStatus
    ├── ✓ No change for 'approved'
    ├── ✓ Maps failures to 'cancelled'
    ├── ✓ Protects 'delivered' terminal state
    ├── ✓ Protects 'cancelled' terminal state
    └── ✓ Handles null current status

helpers.sanitize.spec.ts (134 lines)
├── sanitizePayload
│   ├── ✓ Returns null for null input
│   ├── ✓ Sanitizes simple objects
│   ├── ✓ Handles nested objects
│   ├── ✓ Handles arrays
│   ├── ✓ Handles circular references
│   └── ✓ Removes functions
└── toOrderSnapshot
    ├── ✓ Returns null for null input
    ├── ✓ Extracts key fields
    ├── ✓ Excludes extra fields
    └── ✓ Handles missing fields with null
```

## Integration Points

```
MercadoPagoService
├── confirmByExternalReference()
│   ├── Uses: normalizePaymentStatus()
│   ├── Uses: mapPaymentToOrderStatus()
│   ├── Uses: sanitizePayload()
│   └── Uses: toOrderSnapshot()
│
├── markOrderPaymentStatus()
│   ├── Uses: normalizePaymentStatus()
│   └── Uses: mapPaymentToOrderStatus()
│
└── normalizeMpStatus() [private]
    └── Delegates to: normalizePaymentStatus()
```

---

This architecture ensures:
- ✅ Single source of truth for status logic
- ✅ Terminal state protection
- ✅ Robust circular reference handling
- ✅ Minimal response payloads
- ✅ Easy testing and maintenance

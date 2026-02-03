# Flow Diagram: Single-Item Preference Creation

## Overview

This document visualizes the complete flow of the new single-item preference endpoint.

## Sequence Diagram

```
┌─────────┐         ┌──────────────┐         ┌──────────────────┐         ┌────────────┐         ┌──────────┐
│ Frontend│         │  Controller  │         │     Service      │         │  Payments  │         │ Mercado  │
│  (Cart) │         │              │         │   (MP Service)   │         │  Service   │         │   Pago   │
└────┬────┘         └──────┬───────┘         └────────┬─────────┘         └─────┬──────┘         └────┬─────┘
     │                     │                           │                         │                     │
     │ 1. Select Plan      │                           │                         │                     │
     │ (credit_2_6)        │                           │                         │                     │
     ├─────────────────────>                           │                         │                     │
     │                     │                           │                         │                     │
     │ 2. POST /create-preference-for-plan            │                         │                     │
     │    {baseAmount, selection}                     │                         │                     │
     ├─────────────────────>                           │                         │                     │
     │                     │                           │                         │                     │
     │                     │ 3. Validate input         │                         │                     │
     │                     │    Check idempotency      │                         │                     │
     │                     │    Check rate limit       │                         │                     │
     │                     ├─────────────────────────> │                         │                     │
     │                     │                           │                         │                     │
     │                     │                           │ 4. Get MP credentials   │                     │
     │                     │                           │    (per tenant)         │                     │
     │                     │                           ├─────────────────────────>                     │
     │                     │                           │                         │                     │
     │                     │                           │ 5. Get user data        │                     │
     │                     │                           │    (name, email, phone) │                     │
     │                     │                           ├────────────┐            │                     │
     │                     │                           │            │            │                     │
     │                     │                           <────────────┘            │                     │
     │                     │                           │                         │                     │
     │                     │                           │ 6. Call quote service   │                     │
     │                     │                           │    {subtotal, method,   │                     │
     │                     │                           │     installments,       │                     │
     │                     │                           │     settlementDays}     │                     │
     │                     │                           ├─────────────────────────>                     │
     │                     │                           │                         │                     │
     │                     │                           │ 7. Calculate breakdown  │                     │
     │                     │                           │    - Subtotal           │                     │
     │                     │                           │    - Service fee        │                     │
     │                     │                           │    - MP fee             │                     │
     │                     │                           │    - Total              │                     │
     │                     │                           │    - Merchant net       │                     │
     │                     │                           <─────────────────────────┤                     │
     │                     │                           │                         │                     │
     │                     │                           │ 8. Create single item   │                     │
     │                     │                           │    {quantity: 1,        │                     │
     │                     │                           │     unit_price: total}  │                     │
     │                     │                           ├────────────┐            │                     │
     │                     │                           │            │            │                     │
     │                     │                           <────────────┘            │                     │
     │                     │                           │                         │                     │
     │                     │                           │ 9. Build preference data│                     │
     │                     │                           │    - Items (single)     │                     │
     │                     │                           │    - Payer info         │                     │
     │                     │                           │    - Back URLs          │                     │
     │                     │                           │    - Payment methods    │                     │
     │                     │                           │    - External ref       │                     │
     │                     │                           ├────────────┐            │                     │
     │                     │                           │            │            │                     │
     │                     │                           <────────────┘            │                     │
     │                     │                           │                         │                     │
     │                     │                           │ 10. Create MP preference│                     │
     │                     │                           ├─────────────────────────────────────────────> │
     │                     │                           │                         │                     │
     │                     │                           │ 11. Receive init_point  │                     │
     │                     │                           <─────────────────────────────────────────────┤ │
     │                     │                           │                         │                     │
     │                     │                           │ 12. Persist pre-order   │                     │
     │                     │                           │     - payment_status: pending               │
     │                     │                           │     - settlement_days   │                     │
     │                     │                           │     - installments      │                     │
     │                     │                           │     - breakdown fields  │                     │
     │                     │                           ├────────────┐            │                     │
     │                     │                           │            │            │                     │
     │                     │                           <────────────┘            │                     │
     │                     │                           │                         │                     │
     │                     │                           │ 13. Snapshot breakdown  │                     │
     │                     │                           │     (audit trail)       │                     │
     │                     │                           ├─────────────────────────>                     │
     │                     │                           │                         │                     │
     │                     │                           │ 14. Save idempotency    │                     │
     │                     │                           │     (if key provided)   │                     │
     │                     │                           ├────────────┐            │                     │
     │                     │                           │            │            │                     │
     │                     │                           <────────────┘            │                     │
     │                     │                           │                         │                     │
     │                     │ 15. Return response       │                         │                     │
     │                     <─────────────────────────┤ │                         │                     │
     │                     │                           │                         │                     │
     │ 16. {redirect_url}  │                           │                         │                     │
     <─────────────────────┤                           │                         │                     │
     │                     │                           │                         │                     │
     │ 17. Redirect to MP  │                           │                         │                     │
     ├────────────────────────────────────────────────────────────────────────────────────────────────>
     │                     │                           │                         │                     │
     │ 18. User completes payment on MP               │                         │                     │
     │                     │                           │                         │                     │
     │ 19. MP sends webhook│                           │                         │                     │
     │                     <────────────────────────────────────────────────────────────────────────┤ │
     │                     │                           │                         │                     │
     │ 20. Confirm payment │                           │                         │                     │
     │     Update order    │                           │                         │                     │
     │     Update stock    │                           │                         │                     │
     │     Send email      │                           │                         │                     │
     │                     ├─────────────────────────> │                         │                     │
     │                     │                           │                         │                     │
     │ 21. MP redirects to success page               │                         │                     │
     <────────────────────────────────────────────────────────────────────────────────────────────────┤
     │                     │                           │                         │                     │
```

## Data Flow Details

### Step-by-Step Breakdown

#### 1-2. Frontend Request
```javascript
{
  baseAmount: 1000,
  selection: {
    method: 'credit_card',
    installmentsSeed: 6,
    settlementDays: 10,
    planKey: 'credit_2_6'
  }
}
```

#### 6-7. Quote Calculation
```javascript
// Input to quote service
{
  subtotal: 1000,
  method: 'credit_card',
  installments: 6,
  partial: false,
  settlementDays: 10
}

// Output from quote service
{
  breakdown: {
    total: 1152.37,          // Final amount buyer pays
    netToSeller: 1050.00,    // Amount seller receives
    mpFee: 45.50,            // MP commission
    platformFee: 0,          // Platform fee (if any)
    extras: [
      {
        name: 'Costo del Servicio',
        computed: 52.37,
        type: 'fixed'
      }
    ]
  },
  feeRule: {
    percent_fee: 4.0,
    fixed_fee: 0,
    method: 'credit_card',
    settlement_days: 10
  }
}
```

#### 8. Single Item Creation
```javascript
{
  id: 'order_1696512000000',
  title: 'Compra total',
  description: 'Total con financiación incluida',
  quantity: 1,
  currency_id: 'ARS',
  unit_price: 1152.37  // = breakdown.total (rounded to 2 decimals)
}
```

#### 9. Preference Data
```javascript
{
  items: [
    { /* single item from step 8 */ }
  ],
  payer: {
    name: 'Juan',
    surname: 'Pérez',
    email: 'juan@example.com'
  },
  back_urls: {
    success: 'https://tienda.com/success',
    failure: 'https://tienda.com/failure',
    pending: 'https://tienda.com/pending'
  },
  notification_url: 'https://api.tienda.com/mercadopago/webhook?client_id=123',
  auto_return: 'approved',
  external_reference: 'client_123_user_456_order_1696512000000',
  payment_methods: {
    excluded_payment_types: [{ id: 'debit_card' }],
    installments: 6,
    default_installments: 6
  },
  binary_mode: true
}
```

#### 12. Pre-order Record
```sql
INSERT INTO orders (
  user_id,
  client_id,
  payment_status,
  total_amount,
  external_reference,
  settlement_days,
  installments,
  subtotal,
  service_fee,
  customer_total,
  expected_mp_fee,
  merchant_net,
  fee_rate_used,
  order_items,
  ...
) VALUES (
  'user-456',
  'client-123',
  'pending',
  1152.37,
  'client_123_user_456_order_1696512000000',
  10,
  6,
  1000.00,
  52.37,
  1152.37,
  45.50,
  1050.00,
  4.0,
  '[{"product_id":null,"name":"Compra total","quantity":1,"unit_price":1152.37}]',
  ...
);
```

#### 16. Response to Frontend
```javascript
{
  redirect_url: 'https://www.mercadopago.com.ar/checkout/v1/redirect?pref_id=318182476-abc123',
  preference_id: '318182476-abc123',
  external_reference: 'client_123_user_456_order_1696512000000'
}
```

## Comparison: Old vs New Flow

### Old Flow (create-preference-advanced)
```
Items: [Product 1, Product 2, ..., Service Fee Item]
Total: Sum of all items
Risk: Fee calculation may differ from quote
```

### New Flow (create-preference-for-plan)
```
Items: [Single item with total price]
Total: Exactly what quote calculated
Risk: None - total is guaranteed
```

## Error Scenarios

### Rate Limiting
```
Request → Rate Limiter → Blocked
                       ↓
Response: {
  success: false,
  code: 'RATE_LIMITED_CREATE_PREFERENCE_FOR_PLAN',
  retry_after_ms: 45000
}
```

### Idempotency Hit
```
Request (with Idempotency-Key: abc123)
    ↓
Check mp_idempotency table
    ↓
Found existing preference
    ↓
Return cached response (no new preference created)
```

### Quote Failure
```
Request → Quote Service → Error
                        ↓
Log warning
    ↓
Return 500 error to client
```

## Database State Transitions

### Order Status Flow
```
Initial:        pending
                   ↓
After Payment:  approved
                   ↓
If Issue:       cancelled/refunded
```

### Tables Affected
```
orders                    ← Pre-order created (pending)
order_payment_breakdown   ← Snapshot created
mp_idempotency           ← Idempotency record (optional)
                             ↓ (after payment)
orders                    ← Updated to approved
products                  ← Stock decremented
```

## Key Decision Points

1. **Idempotency Check**: If key exists, return cached → Skip all processing
2. **Rate Limit**: If exceeded, reject → No DB writes
3. **Quote Success**: If fails, abort → No preference created
4. **MP Creation**: If fails, warn → Pre-order may exist (cleanup needed)
5. **Settlement Days**: Debit = 0, Credit = from selection or config

## Performance Hotspots

- **Quote calculation**: Can be slow (100-200ms)
- **MP API call**: Network latency (200-500ms)
- **DB inserts**: Usually fast (<50ms total)

## Monitoring Points

Mark these points for observability:

1. ⏱️ Request received
2. ⏱️ After idempotency check
3. ⏱️ After rate limit check
4. ⏱️ After quote service call
5. ⏱️ After MP preference creation
6. ⏱️ After pre-order persistence
7. ⏱️ Response sent

---

For implementation details, see:
- API Reference: `PREFERENCE_FOR_PLAN_ENDPOINT.md`
- Frontend Guide: `FRONTEND_INTEGRATION.md`
- Code: `src/mercadopago/mercadopago.service.ts:createPreferenceForPlan`

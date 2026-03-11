# Webhook Flow Comparison

## Before Fix

```
MercadoPago sends webhook notification
              ↓
   POST /mercadopago/webhook?client_id=XXX
              ↓
    ┌─────────────────────────────┐
    │ Missing client_id?          │
    │   → Return { ok: true }     │ ❌ Payment lost forever
    └─────────────────────────────┘
              ↓
    ┌─────────────────────────────┐
    │ Not payment event?          │
    │   → Return { ok: true }     │ ✅ Correct
    └─────────────────────────────┘
              ↓
    ┌─────────────────────────────┐
    │ getPaymentDetails() fails?  │
    │   → Return { ok: true }     │ ❌ MP won't retry, payment lost
    └─────────────────────────────┘
              ↓
    ┌─────────────────────────────┐
    │ Invalid external_reference? │
    │   → Return { ok: true }     │ ❌ Payment lost
    └─────────────────────────────┘
              ↓
    ┌─────────────────────────────┐
    │ Payment status=approved?    │
    │   NO  → Return { ok: true } │ ✅ Correct (will get next webhook)
    │   YES → confirmPayment()    │
    └─────────────────────────────┘
              ↓
    ┌─────────────────────────────┐
    │ confirmPayment() fails?     │
    │   → Return { ok: true }     │ ❌ MP won't retry, order not confirmed
    └─────────────────────────────┘
              ↓
         Success! ✅
```

### Problems:
- ❌ Missing client_id → payment ignored
- ❌ API errors → MP thinks it succeeded
- ❌ DB errors → order never confirmed
- ❌ No retry mechanism for failures

---

## After Fix

```
MercadoPago sends webhook notification
              ↓
   POST /mercadopago/webhook?client_id=XXX
              ↓
    ┌─────────────────────────────────────────┐
    │ Not payment event?                      │
    │   → Return { ok: true, ignored: true }  │ ✅ Correct
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ Missing data.id?                        │
    │   → Return { ok: true, ignored: true }  │ ✅ Correct
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ Missing client_id?                      │
    │   YES → Try fallback logic              │
    │         ├─ Check orders table           │
    │         └─ Parse external_reference     │
    │   Still missing?                        │
    │     → Return { ok: true, ignored: true }│ ✅ After exhausting options
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ getPaymentDetails() fails?              │
    │   → Throw HTTP 500                      │ ✅ MP WILL RETRY
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ Invalid external_reference?             │
    │   → Return { ok: true, ignored: true }  │ ✅ Log error, don't retry
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ Payment status=approved?                │
    │   NO  → Return { ok: true, pending }    │ ✅ Will get next webhook
    │   YES → confirmPayment()                │
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ confirmPayment() fails?                 │
    │   → Throw HTTP 500                      │ ✅ MP WILL RETRY
    └─────────────────────────────────────────┘
              ↓
    ┌─────────────────────────────────────────┐
    │ Update stock, clear cart, send email   │
    │ Return { ok: true, confirmed: true }    │ ✅ Success!
    └─────────────────────────────────────────┘
```

### Improvements:
- ✅ client_id fallback prevents lost payments
- ✅ HTTP 500 for API errors → MP retries
- ✅ HTTP 500 for DB errors → MP retries
- ✅ Comprehensive logging at each step
- ✅ Proper idempotency handling

---

## Key Behavioral Changes

| Scenario | Before | After | MP Retry? |
|----------|--------|-------|-----------|
| **Missing client_id** | Ignored immediately | Try fallback, then ignore | No (after fallback) |
| **API call fails** | Return 200 | Throw 500 | **YES** ✅ |
| **DB error** | Return 200 | Throw 500 | **YES** ✅ |
| **Invalid ref** | Return 200 "pending" | Return 200 "ignored" | No (correct) |
| **Pending payment** | Return 200 | Return 200 with status | No (correct) |
| **Approved payment** | Call confirmPayment | Call confirmPayment + better logs | N/A |

---

## Retry Behavior

### MercadoPago Webhook Retry Schedule

When webhook returns non-2xx status:
```
Attempt 1: Immediately
Attempt 2: After 15 minutes
Attempt 3: After 1 hour
Attempt 4: After 6 hours
Attempt 5: After 24 hours
```

With our fix, the webhook will keep retrying until:
- Payment is successfully confirmed (HTTP 200 confirmed=true)
- Payment is legitimately ignored (HTTP 200 ignored=true)
- Manual intervention resolves the issue

---

## Example Scenarios

### Scenario 1: Transient Network Error
```
1. Webhook arrives → getPaymentDetails() fails (network timeout)
2. Returns HTTP 500 → MP schedules retry in 15 min
3. Retry succeeds → confirmPayment() succeeds
4. Order confirmed, cart cleared, email sent ✅
```

### Scenario 2: Database Temporarily Down
```
1. Webhook arrives → getPaymentDetails() succeeds
2. confirmPayment() fails (DB connection error)
3. Returns HTTP 500 → MP schedules retry in 15 min
4. Retry succeeds (DB is back up)
5. Order confirmed ✅
```

### Scenario 3: Missing client_id
```
1. Webhook arrives without client_id parameter
2. Checks orders table → finds order with payment_id
3. Extracts client_id from order
4. Proceeds with confirmation ✅
```

### Scenario 4: Non-Payment Event
```
1. Webhook arrives with action=merchant_order
2. Returns { ok: true, ignored: true }
3. MP doesn't retry (correct) ✅
```

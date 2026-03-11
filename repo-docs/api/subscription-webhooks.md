# MercadoPago Webhook Integration

## Overview

NovaVision receives webhook events from MercadoPago to keep subscriptions synchronized in real-time.

---

## Webhook Endpoint

```
POST https://your-domain.com/subscriptions/webhook
```

### Configuration in MercadoPago

1. Go to [MercadoPago Developers](https://www.mercadopago.com.ar/developers/panel/app)
2. Select your application
3. Navigate to "Webhooks"
4. Add URL: `https://admin.novavision.lat/subscriptionswebhook`
5. Select events:
   - ✅ `preapproval`
   - ✅ `payment`

---

## Event Types

### 1. PreApproval Events

#### `preapproval.created`

Fired when user authorizes recurring payment.

**Payload:**

```json
{
  "id": 12345,
  "type": "preapproval",
  "action": "created",
  "data": {
    "id": "abc123xyz" // preapproval_id
  }
}
```

**Handler:** `handleSubscriptionCreated()`

- Fetches full PreApproval details from MP
- Updates `subscriptions.status` to `active`
- Stores `mp_payer_id`

---

#### `preapproval.updated`

Fired when subscription status changes (paused, cancelled, etc.).

**Payload:**

```json
{
  "id": 12346,
  "type": "preapproval",
  "action": "updated",
  "data": {
    "id": "abc123xyz"
  }
}
```

**Handler:** `handleSubscriptionUpdated()`

- Maps MP status to our status:
  - `authorized` → `active`
  - `paused` → `grace_period`
  - `cancelled` → `cancelled`

---

### 2. Payment Events

#### `payment.created`

Fired on each recurring charge.

**Payload:**

```json
{
  "id": 12347,
  "type": "payment",
  "action": "created",
  "data": {
    "id": "payment-uuid",
    "preapproval_id": "abc123xyz"
  }
}
```

**Handler:** Checks payment status

- If `approved` → `handlePaymentSuccess()`
- If `rejected/cancelled/refunded` → `handlePaymentFailed()`

---

## Handlers

### handlePaymentSuccess()

**Actions:**

1. Update subscription:

   ```sql
   UPDATE subscriptions SET
     status = 'active',
     last_payment_date = NOW(),
     next_payment_date = NOW() + INTERVAL '30 days',
     last_charged_ars = amount,
     consecutive_failures = 0,
     grace_period_ends_at = NULL
   WHERE id = subscription_id;
   ```

2. Record in price history:

   ```sql
   INSERT INTO subscription_price_history
   (subscription_id, charged_at, price_ars, blue_rate, ...)
   VALUES (...);
   ```

3. Update account:
   ```sql
   UPDATE nv_accounts SET
     subscription_status = 'active',
     status = 'active'
   WHERE id = account_id;
   ```

---

### handlePaymentFailed()

**Actions:**

1. Increment failure count
2. Record failure:

   ```sql
   INSERT INTO subscription_payment_failures
   (subscription_id, attempted_at, failure_reason, ...)
   VALUES (...);
   ```

3. Set grace period:

   ```sql
   UPDATE subscriptions SET
     status = (failures >= 3 ? 'suspended' : 'grace_period'),
     consecutive_failures = failures + 1,
     grace_period_ends_at = NOW() + INTERVAL '7 days'
   WHERE id = subscription_id;
   ```

4. Send notification:
   ```typescript
   await notificationService.sendPaymentFailedNotification({
     email,
     failureReason,
     retryDate,
     gracePeriodEnds,
     consecutiveFailures,
   });
   ```

---

## Retry Logic

MercadoPago automatically retries payments:

| Attempt   | Days After Failure |
| --------- | ------------------ |
| 1st retry | +3 days            |
| 2nd retry | +5 days            |
| 3rd retry | +7 days            |

Our system:

- Allows 3 failures before suspension
- 7-day grace period total
- After suspension: requires manual reactivation

---

## Security

### Signature Validation (TODO)

MercadoPago sends `X-Signature` header:

```typescript
// TODO: Implement in Phase 4
function validateWebhookSignature(payload, signature) {
  const secret = process.env.MP_WEBHOOK_SECRET;
  const hash = crypto
    .createHmac("sha256", secret)
    .update(JSON.stringify(payload))
    .digest("hex");

  return hash === signature;
}
```

### Current Implementation

**⚠️ No signature validation yet**

- Webhook is public (no auth required)
- Relies on idempotency
- Safe because operations are read-then-write from MP

**Production TODO:**

- Add signature validation
- Rate limit webhook endpoint
- Log all webhook attempts

---

## Idempotency

All webhook handlers are idempotent:

**Example:**

```typescript
// Safe to call multiple times
async handlePaymentSuccess(subscriptionId, payment) {
  // Always fetches latest state
  const subscription = await getSubscription(subscriptionId);

  // Updates are upserts
  await updateSubscription({
    last_payment_date: payment.date,  // overwrites
    consecutive_failures: 0            // resets
  });
}
```

MP may send duplicate webhooks - our code handles gracefully.

---

## Testing Webhooks

### Local Development (ngrok)

```bash
# 1. Start ngrok
ngrok http 3000

# 2. Update MP webhook URL to ngrok
https://abc123.ngrok.io/subscriptions/webhook

# 3. Monitor
curl http://localhost:4040/inspect/http
```

### Staging/Production

```bash
# Webhook URL
https://admin.novavision.lat/subscriptions/webhook

# Verify receiving
grep "Received webhook" api-logs.txt
```

### Manual Testing

```bash
# Simulate webhook
curl -X POST http://localhost:3000/subscriptions/webhook \
  -H "Content-Type: application/json" \
  -d '{
    "id": 12345,
    "type": "payment",
    "action": "created",
    "data": {
      "id": "test-payment-id",
      "preapproval_id": "your-preapproval-id"
    }
  }'
```

---

## Monitoring

### Success Indicators

```bash
# Webhook received
[SubscriptionsController] Received webhook: {...}

# Event processed
[SubscriptionsService] [Webhook] Processing event: created (preapproval)

# Payment recorded
[SubscriptionsService] [Webhook] Payment successful: $112,875 ARS
```

### Error Indicators

```bash
# Processing error
[SubscriptionsService] [Webhook] Error processing event: ...

# Unknown event type
[SubscriptionsService] [Webhook] Unknown event type: xyz
```

### Webhook Dashboard

MercadoPago provides webhook delivery stats:

- Delivery success rate
- Average response time
- Failed deliveries

**Target:** >99% success rate, <500ms response time

---

## Troubleshooting

### Issue: Webhooks not arriving

**Causes:**

1. Wrong URL in MP dashboard
2. Firewall blocking MP IPs
3. HTTPS certificate invalid

**Fix:**

1. Verify URL in MP dashboard
2. Check server firewall rules
3. Test with `curl` from external IP

---

### Issue: Webhook received but not processed

**Causes:**

1. Database connection failed
2. Subscription not found
3. MP API call failed (getting payment details)

**Fix:**

1. Check DB logs
2. Verify `mp_preapproval_id` matches
3. Check MP API credentials

---

### Issue: Duplicate processing

**Cause:** MP sends same webhook multiple times

**Fix:** Already handled via idempotency - safe to ignore

---

## API Reference

### Request Format

```typescript
interface MercadoPagoWebhook {
  id: number; // Event ID
  type: string; // 'preapproval' | 'payment'
  action: string; // 'created' | 'updated'
  data: {
    id: string; // Resource ID (preapproval_id or payment_id)
  };
}
```

### Response Format

```typescript
// Success
{
  ok: true,
  processed: true
}

// Error (still returns 200)
{
  ok: false,
  error: "error message"
}
```

**Note:** Always returns HTTP 200 to prevent MP retry storms.

---

## Production Checklist

- [ ] Configure webhook URL in MP dashboard
- [ ] Add signature validation
- [ ] Set up monitoring alerts
- [ ] Test with real MP sandbox account
- [ ] Verify all event types handled
- [ ] Check logs for webhook errors
- [ ] Monitor webhook delivery rate

# Subscription System - Admin Guide

## Overview

This guide explains how to manage subscriptions in the NovaVision admin dashboard.

---

## Before Approving a Store

### ✅ Subscription Requirements Checklist

Before approving a store for publication, verify:

1. **Subscription Exists**

   - Store must have a `subscription` record in database
   - Check via `GET /subscriptions/:accountId/status`

2. **Status is Active**

   - `subscription.status === 'active'`
   - Not `pending`, `grace_period`, or `suspended`

3. **No Payment Failures**

   - `subscription.consecutive_failures === 0`
   - Check `subscription_payment_failures` table for recent issues

4. **First Payment Completed**
   - `subscription.last_payment_date` is set
   - Verify in `subscription_price_history`

### Auto-Validation

The admin dashboard automatically validates these requirements:

```typescript
// In admin.service.ts
async approveStore(accountId, reviewedBy) {
  // 1. Fetch subscription
  const subscription = await getSubscription(accountId)

  // 2. Validate
  if (!subscription)
    throw "No subscription - must complete payment first"

  if (subscription.status !== 'active')
    throw "Subscription not active"

  if (subscription.consecutive_failures > 0)
    throw "Has payment failures"

  // 3. Approve
  ...
}
```

---

## Dashboard UI Indicators

### Subscription Status Badges

| Badge                  | Meaning                          | Can Approve? |
| ---------------------- | -------------------------------- | ------------ |
| 🟢 **Active**          | Subscription paid and current    | ✅ Yes       |
| 🟡 **Pending**         | Waiting for first payment        | ❌ No        |
| 🟠 **Grace Period**    | Payment failed, in retry period  | ❌ No        |
| 🔴 **Suspended**       | Too many failures, suspended     | ❌ No        |
| ⚪ **No Subscription** | User hasn't created subscription | ❌ No        |

### Example UI Flow

```
GET /admin/pending-approvals
↓
[
  {
    id: "abc-123",
    email: "user@example.com",
    slug: "tienda-ejemplo",
    subscription_summary: {
      status: "ok",              // ✅ green badge
      message: "Subscription active",
      blocking: false,           // can approve
      last_payment: "2026-01-10",
      next_payment: "2026-02-10"
    },
    can_approve: true            // enable button
  }
]
```

---

## Common Scenarios

### Scenario 1: User Completed Wizard but No Payment

**Symptoms:**

- Status: `incomplete` or `pending_approval`
- No subscription record
- Badge: ⚪ No Subscription

**Action:**

- ❌ Cannot approve
- Wait for user to complete checkout
- Or contact user to finish payment

---

### Scenario 2: Payment Failed

**Symptoms:**

- Status: `grace_period`
- `consecutive_failures` > 0
- Badge: 🟠 Grace Period

**Action:**

- ❌ Cannot approve
- Wait for automatic retry (3, 5, 7 days)
- Or contact user to update payment method

**Check Details:**

```sql
SELECT * FROM subscription_payment_failures
WHERE subscription_id = 'xxx'
ORDER BY attempted_at DESC;
```

---

### Scenario 3: Subscription Suspended

**Symptoms:**

- Status: `suspended`
- Grace period expired
- Badge: 🔴 Suspended

**Action:**

- ❌ Cannot approve
- User must reactivate subscription
- Contact user or wait for manual payment

---

### Scenario 4: Ready to Approve

**Symptoms:**

- Status: `active`
- No failures
- Badge: 🟢 Active

**Action:**

- ✅ Can approve
- Click "Approve" button
- Store will go live immediately

---

## Manual Checks

### Via API

```bash
# Check subscription status
curl -X GET http://localhost:3000/subscriptions/:accountId/status \
  -H "Authorization: Bearer YOUR_ADMIN_TOKEN"

# Response:
{
  "account_id": "uuid",
  "subscription_id": "uuid",
  "status": "active",
  "is_active": true,
  "current_period_end": "2026-02-11T00:00:00Z",
  "grace_until": null
}
```

### Via Database

```sql
-- Get store with subscription
SELECT
  a.id as account_id,
  a.email,
  a.slug,
  a.status as account_status,
  s.status as subscription_status,
  s.mp_preapproval_id,
  s.last_payment_date,
  s.next_payment_date,
  s.consecutive_failures,
  s.grace_period_ends_at
FROM nv_accounts a
LEFT JOIN subscriptions s ON s.account_id = a.id
WHERE a.id = 'account-uuid';

-- Check payment history
SELECT
  charged_at,
  price_ars,
  blue_rate,
  variation_pct,
  payment_status
FROM subscription_price_history
WHERE subscription_id = 'subscription-uuid'
ORDER BY charged_at DESC
LIMIT 5;

-- Check failures
SELECT
  attempted_at,
  attempted_amount_ars,
  failure_reason,
  retry_count,
  next_retry_at,
  resolved_at
FROM subscription_payment_failures
WHERE subscription_id = 'subscription-uuid'
AND resolved_at IS NULL;
```

---

## Handling Edge Cases

### User Wants to Skip Payment

**Not Allowed**

- All stores must have active subscription
- No exceptions or free trials after wizard

**Alternative:**

- Offer discount code for first month
- Or manually adjust price in MercadoPago

---

### Emergency Approval Needed

**If must bypass validation:**

1. Manually activate subscription in database:

```sql
UPDATE subscriptions
SET status = 'active',
    consecutive_failures = 0,
    last_payment_date = NOW(),
    next_payment_date = NOW() + INTERVAL '30 days'
WHERE account_id = 'uuid';
```

2. Then approve normally via dashboard

**⚠️ WARNING:** This skips payment - only for emergencies!

---

### Refund Scenario

If user requests refund after approval:

1. Suspend subscription in MercadoPago
2. Pause store in admin:

```bash
POST /admin/clients/:id/pause
```

3. Update subscription status:

```sql
UPDATE subscriptions
SET status = 'cancelled',
    cancelled_at = NOW()
WHERE account_id = 'uuid';
```

---

## Monitoring

### Cron Jobs

**Price Check (Daily 2 AM)**

- Updates prices based on blue dollar
- Sends notifications if increase >10%

**Reconciliation (Daily 3 AM)**

- Suspends expired grace periods
- Updates subscription statuses

**View Logs:**

```bash
# Search for cron executions
grep "\[Cron\]" api-logs.txt

# Example output:
[Cron] Starting price check job
[Cron] Checked 45 subscriptions, updated 12 prices
```

### Alerts to Monitor

- High failure rate (>10%)
- Many suspensions in one day
- Cron jobs not running
- Webhook errors

---

## Support Queries

### "Why can't I publish my store?"

Check:

1. Subscription status
2. Payment history
3. Failure logs

Provide specific error to user.

### "My payment was declined"

Guide user to:

1. Check card balance
2. Try different payment method
3. Wait for automatic retry (if within grace period)

### "I want to change my plan"

Currently not supported. Options:

1. Cancel and create new subscription
2. Manually adjust price in MP (admin only)

---

## API Reference

| Endpoint                     | Method | Description                     |
| ---------------------------- | ------ | ------------------------------- |
| `/subscriptions/me`          | GET    | Get own subscription            |
| `/subscriptions/:id/status`  | GET    | Check any subscription (admin)  |
| `/subscriptions/webhook`     | POST   | MP webhook (internal)           |
| `/subscriptions/reconcile`   | POST   | Trigger reconciliation (admin)  |
| `/admin/pending-approvals`   | GET    | List stores needing approval    |
| `/admin/clients/:id/approve` | POST   | Approve store (with validation) |

---

## Troubleshooting

### Issue: Approval button disabled

**Cause:** Subscription not active or has failures

**Fix:** Check `subscription_summary.blocking` reason

---

### Issue: Webhook not updating status

**Cause:** MP webhook URL misconfigured or firewalled

**Fix:**

1. Verify webhook URL in MP dashboard
2. Check API logs for webhook receives
3. Test with ngrok in development

---

### Issue: Price not updating

**Cause:** Cron job not running or dollar API down

**Fix:**

1. Check cron logs
2. Verify `PRICE_CHECK_DAYS_BEFORE` env var
3. Manually trigger: `POST /subscriptions/price-check`

---

## Best Practices

1. **Always check subscription before approving**

   - Don't bypass validation
   - Ensure payment completed

2. **Monitor grace period expirations**

   - Alert users proactively
   - Offer assistance before suspension

3. **Keep MP webhook healthy**

   - Monitor webhook delivery rate
   - Fix issues immediately

4. **Document manual interventions**
   - Log why you bypassed normal flow
   - Track in support tickets

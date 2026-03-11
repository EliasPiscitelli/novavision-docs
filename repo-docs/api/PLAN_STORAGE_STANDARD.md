# Plan Storage Standard (NovaVision)

**Date:** 2026-01-16  
**Version:** 1.0

## Schema Design

### Source of Truth

**`subscriptions.plan_key`** - This is the authoritative field for the plan a user has PAID for.

### Denormalized Cache

**`nv_accounts.plan_key`** - Cached copy from subscriptions for fast queries without JOINs.

### DEPRECATED ❌

- ~~`nv_accounts.plan_code`~~ - REMOVED (fully redundant)
- ~~`nv_onboarding.checkout_plan_id`~~ - Use `subscriptions.plan_key` instead

---

## Valid Plan Values

```typescript
type PlanKey = 'starter' | 'growth' | 'scale';
```

**Database Constraints:**

- Both `subscriptions.plan_key` and `nv_accounts.plan_key` have CHECK constraints
- Default value: `'starter'`
- NOT NULL enforced

---

## Read Operations

### ✅ CORRECT: Query Plan for Account

```typescript
// Option 1: From denormalized cache (fast, no JOIN)
const { data: account } = await adminClient
  .from('nv_accounts')
  .select('plan_key')
  .eq('id', accountId)
  .single();

const planKey = account.plan_key; // Cache value

// Option 2: From source of truth (accurate, requires JOIN)
const { data: subscription } = await adminClient
  .from('subscriptions')
  .select('plan_key')
  .eq('account_id', accountId)
  .eq('status', 'active')
  .single();

const planKey = subscription?.plan_key || 'starter'; // Authoritative
```

**Rule:** Use `nv_accounts.plan_key` for UI/display, use `subscriptions.plan_key` for billing/critical logic.

---

## Write Operations

### ✅ CORRECT: Update Plan After Payment

```typescript
// 1. ALWAYS update subscriptions first (source of truth)
await adminClient
  .from('subscriptions')
  .update({ plan_key: newPlanKey })
  .eq('id', subscriptionId);

// 2. THEN sync to nv_accounts (denormalized cache)
await adminClient
  .from('nv_accounts')
  .update({ plan_key: newPlanKey })
  .eq('id', accountId);
```

### ❌ INCORRECT: Update Only nv_accounts

```typescript
// DON'T DO THIS - creates inconsistency
await adminClient
  .from('nv_accounts')
  .update({ plan_key: newPlanKey })
  .eq('id', accountId);
// Missing: sync from subscriptions!
```

---

## Sync Strategy

### When to Sync

1. **Payment Confirmation** (`syncSubscriptionStatus`)
   - Fetch `plan_key` from `subscriptions`
   - Update `nv_accounts.plan_key`

2. **Plan Upgrade/Downgrade**
   - Update `subscriptions.plan_key` first
   - Then sync to `nv_accounts.plan_key`

3. **Subscription Webhook** (MercadoPago events)
   - Verify plan hasn't changed
   - Sync if different

### Periodic Reconciliation (Optional)

Run this query to find and fix drift:

```sql
-- Find accounts where cache is out of sync
SELECT
  a.id,
  a.plan_key as cached_plan,
  s.plan_key as actual_plan
FROM nv_accounts a
JOIN subscriptions s ON a.id = s.account_id
WHERE a.plan_key != s.plan_key
  AND s.status = 'active';

-- Fix drift
UPDATE nv_accounts a
SET plan_key = s.plan_key
FROM subscriptions s
WHERE a.id = s.account_id
  AND s.status = 'active'
  AND a.plan_key != s.plan_key;
```

---

## Migration Path

See: `/apps/api/migrations/20260116_consolidate_plan_fields.sql`

**Steps:**

1. Sync existing data from subscriptions → nv_accounts
2. Drop `plan_code` column
3. Add NOT NULL + CHECK constraints
4. Create indexes for performance

---

## Code Examples

### Creating Subscription

```typescript
// ALWAYS set plan_key when creating subscription
await adminClient.from('subscriptions').insert({
  account_id: accountId,
  plan_key: selectedPlan, // ← Source of truth
  status: 'pending',
  mp_preapproval_id: preapprovalId,
  // ...
});

// THEN update account cache
await adminClient
  .from('nv_accounts')
  .update({ plan_key: selectedPlan }) // ← Denormalized cache
  .eq('id', accountId);
```

### Displaying Plan in UI

```typescript
// Frontend: Use cached value for fast display
const { data: account } = await fetch('/api/account/me');
const planName = PLAN_LABELS[account.plan_key]; // "Growth Plan"
```

### Billing Logic

```typescript
// Backend: Use authoritative value for critical operations
const { data: sub } = await adminClient
  .from('subscriptions')
  .select('plan_key, status')
  .eq('account_id', accountId)
  .eq('status', 'active')
  .single();

if (sub.plan_key === 'starter') {
  // Apply starter limits
}
```

---

## Summary

| Field                       | Purpose                | When to Use                       |
| --------------------------- | ---------------------- | --------------------------------- |
| `subscriptions.plan_key`    | **Source of Truth**    | Billing, payments, critical logic |
| `nv_accounts.plan_key`      | **Denormalized Cache** | UI display, fast queries          |
| ~~`nv_accounts.plan_code`~~ | ❌ REMOVED             | N/A                               |

**Golden Rule:** Write to subscriptions first, then sync to nv_accounts.

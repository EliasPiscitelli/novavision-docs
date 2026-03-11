# Admin Dashboard - Finance & Metrics Definitions

This document defines the formulas, data sources, and API contracts for the NovaVision Admin Dashboard.

## 1. Common Specifications

### Time Standard

- **Timezone**: All business days/months are cut based on `America/Argentina/Buenos_Aires`.
- **Timestamps**: API inputs/outputs should use ISO 8601 with timezone offset (e.g. `2026-02-01T00:00:00-03:00`).

### Standard Filter Params

RPCs and Endpoints must accept:

- `range_start` (timestamptz)
- `range_end` (timestamptz)
- `timezone` (text, default 'America/Argentina/Buenos_Aires')
- `granularity` (text: 'day' | 'week' | 'month')

---

## 2. Finance Summary (CFO View)

**RPC**: `finance_summary`

### A. Cash Collected (Real)

- **Definition**: Money actually settled/approved in payment gateways.
- **Source**: `nv_billing_events` where `status = 'paid'` or `status = 'approved'`.
- **Formula**: `SUM(amount)` of valid events in range.
- **Note**: If `nv_billing_events` is empty, this MUST be 0. No estimates allowed here.

### B. Revenue Accrued (Estimated)

- **Definition**: Subscription revenue recognized proportionally day-by-day (devengado).
- **Source**: `subscriptions` table.
- **Formula**:
  - For a subscription active in the period: `Daily Rate * Active Days in Range`.
  - `Daily Rate` = `Plan Price / Days in Billing Cycle`.
  - `Plan Price` priority: `last_charged_ars` -> `original_price_ars` -> `initial_price_ars` -> `next_estimated_ars`.

### C. Accounts Receivable (AR)

- **Definition**: Revenue that has been accrued (devengado) but not yet collected (cash).
- **Formula**: `Accrued Revenue (Total Historical) - Cash Collected (Total Historical)`.
- **Aging Buckets**:
  - `0-7 days`: Past due for <= 7 days.
  - `8-15 days`: Past due for 8-15 days.
  - `16-30 days`: Past due for 16-30 days.
  - `30+ days`: Past due for > 30 days.

### D. Net Margin (Estimated)

- **Formula**: `Cash Collected - Payment Fees - Platform Costs`.
- **Fees**: Defaults to 5% if real data missing.
- **Platform Costs**: Derived from metering (if avail) or flat rate estimate per client.

---

## 3. Metrics (Business Ops)

**RPC**: `dashboard_metrics`

### Funnel

- **Started**: `onboarding_session` created.
- **Submitted**: `onboarding_session` status = 'submitted'.
- **Approved**: account status = 'active' (after approval).
- **Live**: account has custom domain active or > 0 orders.

### Health

- **Avg Time to Approved**: `approved_at - created_at` average.
- **Churn**: Count of subscriptions where `cancelled_at` is within range.

---

## 4. Metering (Usage & Costs)

**Endpoint**: `/admin/metering/summary` (v2)

### Cost Model (Version 2026-02)

- **Requests**: Free tier 10k, then $X/1k.
- **Storage**: Free tier 1GB, then $Y/GB.
- **Bandwidth**: Free tier 10GB, then $Z/GB.

### Output

- Must assume explicit default limits if not set in DB.
- Must return `cost_estimated` per client.

# NovaVision Reporting System (CFO-Grade)

Centralized, backend-driven reporting architecture for Metrics, Finance, and Metering.

## 1. Governance & Principles

- **Backend as Source of Truth**: No logic or calculations are performed in the frontend.
- **Stable Protocols**: Single stable RPCs and endpoints (`finance_summary`, `dashboard_metrics`).
- **Precision**: Monetary values use `numeric` types; timestamps use `timestamptz`.
- **Timezone**: All daily/period metrics use `America/Argentina/Buenos_Aires` unless specified.

## 2. Finance Taxonomy (Conciliation)

Located in `FinanceView` and driven by `finance_summary`.

| Metric                   | Definition                                         | Source                                    |
| ------------------------ | -------------------------------------------------- | ----------------------------------------- |
| **Cash In (Real)**       | Sum of successful billing events.                  | `nv_billing_events` (paid/approved)       |
| **Cash Out (Real)**      | Sum of refunds and chargebacks.                    | `nv_billing_events` (refunded/chargeback) |
| **Net Cash (Real)**      | `Cash In - Cash Out`.                              | Calculated in RPC                         |
| **Revenue Devengado**    | Prorated daily estimation of active subscriptions. | `subscriptions` x daily rate              |
| **AR (Acc. Receivable)** | Gap between accrued revenue and collected cash.    | `accrued - cash_in`                       |

### Aging Logic

- **Single Anchor**: `COALESCE(past_due_since, next_payment_date)`.
- **Buckets**: Current, 7d, 15d, 30d, 30d+.

## 3. Business Metrics (Funnel & Health)

Located in `MetricsView` and driven by `dashboard_metrics`.

### Funnel (Event-based)

- **Started**: Account/Onboarding created.
- **Submitted**: `submitted_at` timestamp.
- **Approved**: `state` transition to approved.
- **Live**: `provisioned_at` timestamp.

### Health

- **Active**: `active` status subscriptions.
- **At Risk**: `past_due` or `grace` status.
- **Churn**: Count of `cancelled_at` in range.

## 4. Usage & Costs (Metering)

Located in `UsageView` and driven by `/admin/metering/summary`.

### Taxonomy Separation

- **Infra Usage**: Requests, Egress GB, Storage.
- **Business Usage**: Orders, Conversion, GMV.

### Cost Model (Assumptions)

- Base Plan includes limits.
- Overage calculated per 1k requests, GB, or orders.
- Formulas documented in `FinanceController` and `MetricsService`.

## 5. API Reference

- `GET /admin/metrics/summary`: Funnel, Health, Alertas.
- `GET /admin/finance/summary`: Cash, Accrual, Aging.
- `GET /admin/metering/summary`: Infra vs Business usage.

---

## Contract Revision

- **Revision**: `2026-02-01`
- **Guarantees**:
  - Stable field names.
  - New fields are optional/additive.
  - Breaking changes require coordinated migrations.
- **Traceability**: All responses include a `contract` object with `name` and `revision`.

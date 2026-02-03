# Payment Configuration E2E Testing Guide

This document describes the scenarios to test for the payment configuration enforcement feature.

## Overview

The payment configuration now enforces admin settings across:
- UI display (PlanSelector)
- Cart quoting (`GET /api/cart?includeQuote=true`)
- Preference creation (`POST /mercadopago/create-preference-for-plan`)

## Test Scenarios

### Scenario 1: Debit-Only Mode

**Configuration:**
```json
{
  "allowInstallments": false,
  "maxInstallments": 12,
  "excludedPaymentTypes": [],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": null
}
```

**Alternative Configuration** (same result):
```json
{
  "allowInstallments": true,
  "maxInstallments": 12,
  "excludedPaymentTypes": ["credit_card"],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": null
}
```

**Expected UI:**
- ✅ Only shows: "Débito (1 cuota)"
- ✅ No credit options visible

**Expected Network Requests:**

Quote request:
```
GET /api/cart?includeQuote=true&method=debit_card&installments=1&settlementDays=0
```

Preference creation:
```json
POST /mercadopago/create-preference-for-plan
{
  "baseAmount": 1000.00,
  "selection": {
    "method": "debit_card",
    "installmentsSeed": 1,
    "settlementDays": 0,
    "planKey": "debit_1"
  }
}
```

**Backend Validation:**
- ✅ Should accept debit_card with installmentsSeed=1
- ❌ Should reject credit_card with `400 PAYMENT_METHOD_NOT_ALLOWED`

---

### Scenario 2: Cap at 6 Installments

**Configuration:**
```json
{
  "allowInstallments": true,
  "maxInstallments": 6,
  "excludedPaymentTypes": [],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": null
}
```

**Expected UI:**
- ✅ Shows: "Débito (1 cuota)"
- ✅ Shows: "Crédito (1 cuota)"
- ✅ Shows: "Crédito (2–6 cuotas)"
- ❌ Does NOT show: "Crédito (7–12 cuotas)"

**Expected Network Requests:**

When user selects "Crédito (2–6 cuotas)":
```
GET /api/cart?includeQuote=true&method=credit_card&installments=2&settlementDays=10
```

Preference creation:
```json
POST /mercadopago/create-preference-for-plan
{
  "baseAmount": 1000.00,
  "selection": {
    "method": "credit_card",
    "installmentsSeed": 2,
    "settlementDays": 10,
    "planKey": "credit_2_6"
  }
}
```

**Backend Validation:**
- ✅ Should accept installmentsSeed=2 (≤ 6)
- ✅ Should accept installmentsSeed=6 (≤ 6)
- ❌ Should reject installmentsSeed=7 with `400 INSTALLMENTS_EXCEEDED`

---

### Scenario 3: Cap at 3 Installments

**Configuration:**
```json
{
  "allowInstallments": true,
  "maxInstallments": 3,
  "excludedPaymentTypes": [],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": null
}
```

**Expected UI:**
- ✅ Shows: "Débito (1 cuota)"
- ✅ Shows: "Crédito (1 cuota)"
- ✅ Shows: "Crédito (2–3 cuotas)" ← **Note the dynamic label**
- ❌ Does NOT show: "Crédito (7–12 cuotas)"

**Expected Network Requests:**

When user selects "Crédito (2–3 cuotas)":
```
GET /api/cart?includeQuote=true&method=credit_card&installments=2&settlementDays=10
```

Preference creation:
```json
POST /mercadopago/create-preference-for-plan
{
  "baseAmount": 1000.00,
  "selection": {
    "method": "credit_card",
    "installmentsSeed": 2,
    "settlementDays": 10,
    "planKey": "credit_2_6"
  }
}
```

**Backend Validation:**
- ✅ Should accept installmentsSeed=2 (≤ 3)
- ✅ Should accept installmentsSeed=3 (≤ 3)
- ❌ Should reject installmentsSeed=4 with `400 INSTALLMENTS_EXCEEDED`

---

### Scenario 4: Settlement Days Whitelist

**Configuration:**
```json
{
  "allowInstallments": true,
  "maxInstallments": 12,
  "excludedPaymentTypes": [],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": [0, 10, 35]
}
```

**Expected Behavior:**
- All plans use settlementDays from the whitelist
- If a plan's default is not in the whitelist, it falls back to:
  1. `defaultSettlementDays` (if in whitelist)
  2. First value in `allowedSettlementDays`

**Expected Network Requests:**

For credit plans with settlementDays enforced:
```
GET /api/cart?includeQuote=true&method=credit_card&installments=2&settlementDays=10
```

**Backend Validation:**
- ✅ Should accept settlementDays=0, 10, or 35
- ❌ Should reject settlementDays=5 with `400 SETTLEMENT_NOT_ALLOWED`

---

### Scenario 5: No Payment Methods Available

**Configuration:**
```json
{
  "allowInstallments": true,
  "maxInstallments": 12,
  "excludedPaymentTypes": ["debit_card", "credit_card"],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": null
}
```

**Expected UI:**
- ❌ No payment method options shown
- ✅ Shows message: "No hay medios de pago disponibles para este comercio"
- ✅ Continue button is disabled
- ✅ Payment buttons are disabled

**Expected Network Requests:**
- Should not attempt to create preference
- Buttons remain disabled

---

## E2E Test Checklist

For each scenario above, verify:

### UI Validation
- [ ] Correct payment methods are displayed
- [ ] Labels show accurate installment ranges
- [ ] No excluded methods appear
- [ ] Disabled state is correct when no methods available

### Network Request Validation
- [ ] Quote requests send capped `installments` parameter
- [ ] Quote requests use correct `settlementDays`
- [ ] Preference creation payload has capped `installmentsSeed`
- [ ] Preference creation payload respects method restrictions

### Backend Validation
- [ ] Backend accepts valid requests
- [ ] Backend rejects invalid method with `PAYMENT_METHOD_NOT_ALLOWED`
- [ ] Backend rejects exceeded installments with `INSTALLMENTS_EXCEEDED`
- [ ] Backend rejects invalid settlement days with `SETTLEMENT_NOT_ALLOWED`

### Error Handling
- [ ] Frontend displays user-friendly error messages
- [ ] Idempotency-Key header is present
- [ ] x-client-id header is present

---

## Testing Tools

### Browser DevTools
1. Open Network tab
2. Filter by `cart` or `mercadopago`
3. Inspect request payloads and query parameters
4. Verify headers (Idempotency-Key, x-client-id)

### Admin Panel
Navigate to Payment Configuration (`/admin/payments/config`) to:
1. Toggle allowInstallments
2. Set maxInstallments to test different caps
3. Exclude payment types
4. Configure settlement days whitelist
5. Save and test in cart page

### Backend Logs
Check backend logs for:
- Validation errors with proper error codes
- Settings loaded for each request
- Selection object validation results

---

## Example Test Session

1. **Set config**: maxInstallments=3, allowInstallments=true
2. **Add item to cart**
3. **Open cart page** → Verify "Crédito (2–3 cuotas)" label
4. **Select "Crédito (2–3 cuotas)"**
5. **Open DevTools Network tab**
6. **Click "Continuar con el pago"**
7. **Verify**: Request shows `installments=2`
8. **Click "Pagar el total"**
9. **Verify**: Preference payload has `installmentsSeed=2`
10. **Check backend logs**: Should show validation passed

---

## Notes for Backend Team

The frontend now sends:
- `installmentsSeed`: The starting installment value for the selected band (2 for credit_2_6, 7 for credit_7_12)
- This is **NOT** the max installments, but the seed value used to calculate quotes

Backend should:
1. Validate `installmentsSeed ≤ maxInstallments`
2. Validate method against `excludedPaymentTypes`
3. Validate `settlementDays` against `allowedSettlementDays` (if provided)
4. Return clear error codes for violations

Example validation pseudocode:
```javascript
if (cfg.allowInstallments === false && selection.installmentsSeed > 1) {
  return 400: { code: 'INSTALLMENTS_EXCEEDED' }
}

if (cfg.excludedPaymentTypes.includes(selection.method)) {
  return 400: { code: 'PAYMENT_METHOD_NOT_ALLOWED' }
}

if (selection.installmentsSeed > cfg.maxInstallments) {
  return 400: { code: 'INSTALLMENTS_EXCEEDED' }
}

if (cfg.allowedSettlementDays && !cfg.allowedSettlementDays.includes(selection.settlementDays)) {
  return 400: { code: 'SETTLEMENT_NOT_ALLOWED' }
}
```

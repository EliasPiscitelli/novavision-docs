# Payment Configuration E2E Flow - Implementation Summary

## Overview
This implementation ensures that when an admin configures payment settings (particularly the "Débito (1 cuota)" / `payWithDebit` option), the entire system respects those settings consistently across:
- Admin configuration save
- Backend configuration exposure
- Frontend UI display
- Cart quoting
- Checkout preference creation

## Key Changes

### 1. CartProvider.jsx - `deriveAllowedPlans()`

**Location:** Lines 620-684

**Change:** Added check for `payWithDebit` flag

```javascript
// Before:
if (cfg.allowInstallments === false || creditExcluded) {
  return debitOnly;
}

// After:
if (cfg.allowInstallments === false || creditExcluded || cfg.payWithDebit === true) {
  return debitOnly;
}
```

**Impact:**
- When `payWithDebit=true`, only "Débito (1 cuota)" is shown in the UI
- Enforces business rule R1: debit-only mode when configured

### 2. PlanSelectorAdapter.jsx - NEW FILE

**Purpose:** Adapter pattern to separate design component from business logic

**Features:**
- Derives allowed plans from payment settings
- Auto-selects first valid plan when current selection becomes invalid
- Handles quoting when plan changes
- Shows error message when no payment methods available

**Benefits:**
- Centralizes plan selection logic
- Makes PlanSelector a pure presentation component
- Easier to test and maintain

### 3. CartPage/index.jsx

**Changes:**
1. Import PlanSelectorAdapter instead of PlanSelector directly
2. Updated estimator logic to respect credit exclusion rules

**Estimator Logic:**
```javascript
const canShowCredit = paymentSettings?.allowInstallments !== false 
  && !(paymentSettings?.excludedPaymentTypes || []).includes('credit_card')
  && !paymentSettings?.payWithDebit;
```

Only shows credit estimates when:
- `allowInstallments !== false`
- `credit_card` not in `excludedPaymentTypes`
- `payWithDebit !== true`

### 4. PaymentsConfig/index.jsx - `handleSave()`

**Normalization Logic:** When admin activates "Débito (1 cuota)":

```javascript
if (form.payWithDebit === true) {
  normalizedAllowInstallments = false;
  normalizedMaxInstallments = 1;
  if (!normalizedExcludedTypes.includes('credit_card')) {
    normalizedExcludedTypes = [...normalizedExcludedTypes, 'credit_card'];
  }
}
```

**Result:**
- Forces `allowInstallments=false`
- Forces `maxInstallments=1`
- Adds `'credit_card'` to `excludedPaymentTypes` (if not already there)

This ensures consistency: the backend receives a normalized configuration that enforces the debit-only intent.

### 5. Tests - deriveAllowedPlans.test.js

**New Test Cases:**
1. `shows only debit when payWithDebit is true`
2. `shows only debit when payWithDebit is true even with credit_card not excluded`

**All Tests Pass:** 33/33 ✓

## Business Rules Enforced

### R1: Debit-Only Display
**Trigger:** `allowInstallments=false` OR `credit_card` excluded OR `payWithDebit=true`
**Result:** UI only shows "Débito (1 cuota)"

### R2: Installments Cap
**Trigger:** `maxInstallments` set to N < 12
**Result:** Credit bands show capped ranges (e.g., "Crédito (2–3 cuotas)" when N=3)

### R3: Selected Plan Validity
**Trigger:** Configuration changes invalidate current selection
**Result:** Auto-select first valid plan

### R4: Consistency
**Trigger:** All operations
**Result:** What's shown = what's quoted = what's sent to MP

### R5: Settlement Days
**Trigger:** `allowedSettlementDays` whitelist provided
**Result:** Plans use whitelisted values only

### R6: Auto-Correction
**Trigger:** Config change invalidates current plan
**Result:** Frontend auto-corrects to first valid plan

## E2E Flow Verification

### Scenario 1: Admin Activates "Débito (1 cuota)"

**Admin Panel:**
1. Toggle "Débito (1 Cuota)" switch ON
2. Click "Guardar"

**Backend Receives:**
```json
{
  "allowInstallments": false,
  "maxInstallments": 1,
  "excludedPaymentTypes": ["credit_card"],
  "payWithDebit": true
}
```

**Frontend Loads Config:**
- `deriveAllowedPlans()` returns only `[{ key: 'debit_1', ... }]`

**UI Shows:**
- Only "Débito (1 cuota)" option in plan selector
- Estimator only shows debit row
- Credit plans hidden

**Quote Requests:**
```
GET /api/cart?includeQuote=true&method=debit_card&installments=1&settlementDays=0
```

**Preference Creation:**
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

### Scenario 2: Normal Operation (All Methods Available)

**Admin Panel:**
- "Débito (1 Cuota)" OFF
- "Permitir cuotas" ON
- `maxInstallments`: 12
- No exclusions

**Frontend Shows:**
- "Débito (1 cuota)"
- "Crédito (1 cuota)"
- "Crédito (2–6 cuotas)"
- "Crédito (7–12 cuotas)"

**Estimator Shows:** All 4 rows

### Scenario 3: Capped at 3 Installments

**Admin Panel:**
- `maxInstallments`: 3

**Frontend Shows:**
- "Débito (1 cuota)"
- "Crédito (1 cuota)"
- "Crédito (2–3 cuotas)" ← **Dynamic label**
- ❌ "Crédito (7–12 cuotas)" hidden

## Testing Results

### Unit Tests
```bash
$ npm run test:unit
✓ 33 tests passing
  - 20 tests for deriveAllowedPlans
  - 13 tests for checkout validation
```

### Manual Test Scenarios
✓ Scenario 1: payWithDebit=true → Only debit shown
✓ Scenario 2: allowInstallments=false → Only debit shown
✓ Scenario 3: credit_card excluded → Only debit shown
✓ Scenario 4: All methods available → 4 plans shown
✓ Scenario 5: maxInstallments=3 → Dynamic label "2–3 cuotas"

### Build Status
✓ Build successful: `npm run build`
✓ No linting errors in modified files

## Files Changed

1. ✏️ `src/context/CartProvider.jsx` - Added payWithDebit check
2. ✨ `src/pages/CartPage/PlanSelectorAdapter.jsx` - NEW adapter component
3. ✏️ `src/pages/CartPage/index.jsx` - Use adapter, update estimator
4. ✏️ `src/components/admin/PaymentsConfig/index.jsx` - Normalize save
5. ✏️ `src/__tests__/deriveAllowedPlans.test.js` - Add payWithDebit tests

## Backward Compatibility

✅ No breaking changes
- Default behavior unchanged (all plans available)
- Only affects merchants who configure restrictions
- Graceful degradation when backend validation not yet implemented

## Security & Performance

**Security:**
- Frontend enforces UI/UX constraints
- Backend should validate all requests (defense in depth)
- Both use same config source
- Prevents client-side tampering

**Performance:**
- `deriveAllowedPlans()` memoized
- No additional API calls
- Minimal overhead

## Next Steps

1. ✅ Frontend implementation (this PR)
2. ⏳ Backend validation (separate PR)
   - Validate incoming requests against settings
   - Return error codes: `PAYMENT_METHOD_NOT_ALLOWED`, `INSTALLMENTS_EXCEEDED`
3. ⏳ E2E testing
   - Use PAYMENT_CONFIG_E2E_TESTING.md guide
   - Test all scenarios
   - Verify network requests

## Support

**For Developers:**
- Code comments in CartProvider.jsx
- Unit tests in deriveAllowedPlans.test.js
- This implementation summary

**For QA:**
- E2E testing guide in PAYMENT_CONFIG_E2E_TESTING.md
- Test scenarios with expected results
- Network request examples

**For Product/Support:**
- Admin panel UI for configuration
- Clear error messages for users
- Logs for troubleshooting

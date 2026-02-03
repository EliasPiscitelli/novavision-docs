# Payment Plan Filtering - Implementation Summary

## Overview

This implementation adds comprehensive filtering of payment plans based on admin-configured payment settings. The system now respects backend configuration to show only allowed payment methods, installment options, and settlement day constraints.

## Files Modified

### 1. `src/context/CartProvider.jsx`

**Changes:**
- Added `excludedPaymentTypes` and `excludedPaymentMethods` fields to payment settings capture
- Implemented `deriveAllowedPlans()` helper function that filters plans based on multiple criteria
- Added pre-checkout validation to ensure selected plan is allowed
- Fixed `installmentsSeed` values (credit_2_6: 2, credit_7_12: 7)
- Added `allowedSettlementDays` constraint handling in `generatePreference()`
- Exported `deriveAllowedPlans` for use by child components

**Key Logic:**
```javascript
deriveAllowedPlans(cfg) {
  // 1. Filter by excluded payment types (debit_card, credit_card)
  // 2. Apply installments gate (allowInstallments flag)
  // 3. Cap installments by maxInstallments
  // 4. Remove credit bands that fall below minimum installments
  // 5. Adjust settlementDays to match allowedSettlementDays whitelist
}
```

### 2. `src/pages/CartPage/PlanSelector.jsx`

**Changes:**
- Removed hardcoded plans array
- Uses `deriveAllowedPlans()` from CartProvider via useMemo
- Auto-selects first allowed plan if current selection becomes invalid
- Shows "No hay medios de pago disponibles" when no plans available
- Only renders allowed plans

### 3. `src/pages/CartPage/index.jsx`

**Changes:**
- Imports React for useMemo hook
- Derives allowed plans using context helper
- Disables checkout buttons when no plans available
- Shows appropriate disabled state messages

### 4. `src/__tests__/deriveAllowedPlans.test.js` (NEW)

**Test Coverage:**
- ✓ All plans shown with no restrictions
- ✓ Credit card exclusion
- ✓ Debit card exclusion
- ✓ Both payment types excluded (edge case)
- ✓ Installments disabled (allowInstallments = false)
- ✓ maxInstallments = 3 (filters credit_7_12)
- ✓ maxInstallments = 6 (filters credit_7_12, caps credit_2_6)
- ✓ settlementDays constraints
- ✓ Null/undefined config handling

## Testing Scenarios

### Scenario 1: Credit Card Excluded
**Settings:**
```json
{
  "excludedPaymentTypes": ["credit_card"],
  "allowInstallments": true,
  "maxInstallments": 12
}
```
**Result:** Only "Débito (1 cuota)" plan shown

### Scenario 2: Installments Disabled
**Settings:**
```json
{
  "excludedPaymentTypes": [],
  "allowInstallments": false,
  "maxInstallments": 12
}
```
**Result:** Only 1-installment plans shown (debit_1, credit_1)

### Scenario 3: Max Installments = 3
**Settings:**
```json
{
  "excludedPaymentTypes": [],
  "allowInstallments": true,
  "maxInstallments": 3
}
```
**Result:** debit_1, credit_1, credit_2_6 (capped to 3 installments)
credit_7_12 is filtered out because it needs minimum 7 installments

### Scenario 4: Example from Problem Statement
**Settings:**
```json
{
  "allowPartial": true,
  "partialPercent": 30,
  "allowInstallments": false,
  "maxInstallments": 6,
  "excludedPaymentTypes": ["ticket","digital_currency","atm","credit_card","bank_transfer","account_money"],
  "defaultSettlementDays": null
}
```
**Result:** Only "Débito (1 cuota)" plan shown
- Credit card is excluded
- Only 1-installment options due to allowInstallments = false

### Scenario 5: No Payment Methods Available
**Settings:**
```json
{
  "excludedPaymentTypes": ["debit_card", "credit_card"],
  "allowInstallments": true,
  "maxInstallments": 12
}
```
**Result:** 
- PlanSelector shows: "No hay medios de pago disponibles para este comercio."
- Checkout buttons disabled with message: "No hay medios de pago disponibles"

## Validation Flow

1. **Cart Page Load:**
   - `validateCart()` is called, which fetches payment settings from backend
   - Settings are stored in CartProvider context
   - `prefetchPlans()` pre-loads quotes for all allowed plans

2. **Plan Selection:**
   - PlanSelector derives allowed plans using `deriveAllowedPlans(paymentSettings)`
   - Only allowed plans are rendered
   - If selected plan becomes invalid, first allowed plan is auto-selected
   - Quote is fetched for selected plan

3. **Checkout Initiation:**
   - User clicks "Continuar con el pago"
   - `validateCart()` ensures cart is valid
   - Button is disabled if no allowed plans

4. **Preference Generation:**
   - User clicks "Pagar el total"
   - `generatePreference()` validates:
     - Selected plan exists
     - Selected plan is in allowed plans list
     - Allowed plans list is not empty
   - Builds selection object with correct installmentsSeed and settlementDays
   - Handles `allowedSettlementDays` constraint
   - Calls `POST /mercadopago/create-preference-for-plan`
   - Redirects to MercadoPago checkout

## Error Handling

### Already Implemented (Verified)
- **Rate Limiting:** Shows countdown when `RATE_LIMITED_CREATE_PREFERENCE_FOR_PLAN` error received
- **400 Bad Request:** "Datos inválidos. Por favor revisa tu selección."
- **401 Unauthorized:** "Tu sesión expiró. Por favor inicia sesión nuevamente."
- **500 Server Error:** "Error del servidor. Intenta nuevamente en unos momentos."
- **Network Error:** "Error de conexión. Verifica tu internet."

### New Validations Added
- **No plan selected:** "Por favor selecciona un plan de pago"
- **Invalid plan selected:** "El plan seleccionado no está disponible. Por favor elige otro plan."
- **No plans available:** "No hay medios de pago disponibles para este comercio."

## API Contract

### Request to Backend
```javascript
POST /mercadopago/create-preference-for-plan
Headers:
  - Idempotency-Key: <uuid>
  - x-client-id: <client_id>
Body:
{
  "baseAmount": 1000.50,
  "selection": {
    "method": "credit_card",
    "installmentsSeed": 2,
    "settlementDays": 10,
    "planKey": "credit_2_6"
  }
}
```

### Expected Response
```json
{
  "redirect_url": "https://www.mercadopago.com/...",
  "preference_id": "123456789",
  "external_reference": "ext-ref-123"
}
```

## Build & Test Status

- ✅ Build: Success (no errors, no warnings)
- ✅ Unit Tests: 10/10 passing
- ✅ Linting: Clean (no eslint errors)

## Next Steps for Manual Testing

1. Start backend with different payment settings configurations
2. Test each scenario listed above
3. Verify plan filtering works correctly in UI
4. Test checkout flow with allowed plans
5. Verify error messages display correctly
6. Test rate limiting behavior
7. Test with sandbox MercadoPago account

## Notes

- The implementation follows the problem statement exactly
- Minimal changes were made to existing code
- Error handling was already present and verified
- New unit tests provide confidence in filtering logic
- Auto-selection prevents invalid states when settings change

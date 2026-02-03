# Test Suite Documentation

This document describes the automated test suite for payment validation flow (Admin → Cart → MercadoPago).

## Overview

The test suite ensures that:
1. The plan selector in the cart only shows plans allowed by `payments/config`
2. Preference requests use valid plans and send correct headers/shape
3. MercadoPago preferences respect `excluded_payment_types` and `excluded_payment_methods`
4. When `allowInstallments = false`, no plans with >1 installment are allowed
5. When `excludedPaymentTypes` contains `"credit_card"`, no credit plans are selectable
6. If no valid plans exist, checkout is disabled with an appropriate message

## Test Structure

### Unit Tests (Vitest)
Location: `src/__tests__/`

#### `deriveAllowedPlans.test.js`
Tests the core logic for deriving allowed payment plans from admin settings.

**Coverage (18 test cases):**
- ✓ Returns all plans when no restrictions
- ✓ Excludes credit card plans when credit_card is excluded
- ✓ Excludes debit card plans when debit_card is excluded
- ✓ Only allows 1-installment plans when allowInstallments is false
- ✓ Caps installments based on maxInstallments
- ✓ Filters out credit_7_12 when maxInstallments is 6
- ✓ Returns empty array when both debit and credit are excluded
- ✓ Adjusts settlementDays when allowedSettlementDays is provided
- ✓ Handles null or undefined config gracefully
- ✓ Validates type guards: installments must be positive integers
- ✓ Validates type guards: method must be valid card type
- ✓ Validates type guards: sd must be non-negative integer
- ✓ Handles the specific config from problem statement (credit blocked + installments off)
- ✓ Uses defaultSettlementDays when null falls back to 10
- ✓ Filters out credit_2_6 when maxInstallments is 1

#### `checkout.validate.spec.js`
Integration tests for preference generation and cart validation.

**Coverage (12 test cases):**
- ✓ Generates correct payload for debit_1 plan with restricted config
- ✓ Payload uses priceFinal as baseAmount (without service fee item)
- ✓ Validates Idempotency-Key and x-client-id headers are present
- ✓ Does not allow credit_card selection when credit is excluded
- ✓ Selection object has correct shape and types
- ✓ Should not quote credit_card if UI only shows debit
- ✓ Returns settings with excluded payment types
- ✓ Ignores credit bands in UI even if backend returns quotes
- ✓ Forces settlement days to allowed list when provided
- ✓ Uses defaultSettlementDays when in allowed list
- ✓ isUUIDv4 validates UUID v4 format
- ✓ expectSubset validates nested object structure

### E2E Tests (Playwright)
Location: `e2e/`

#### `cart-admin-rules.spec.ts`
End-to-end tests that validate the complete flow from cart to payment.

**Test Scenarios:**

##### Scenario A: Credit blocked + installments off
Mock config excludes credit cards and disables installments.

**Assertions:**
- Only "Débito (1 cuota)" option is visible
- No credit card options appear
- Preference request body contains:
  ```json
  {
    "baseAmount": <number>,
    "selection": {
      "method": "debit_card",
      "installmentsSeed": 1,
      "settlementDays": 0,
      "planKey": "debit_1"
    }
  }
  ```
- Headers include `Idempotency-Key` (UUID v4) and `x-client-id`

##### Scenario B: No valid plans
Mock config excludes both debit and credit cards.

**Assertions:**
- Plan selector shows 0 plans
- Payment button is disabled
- Error message: "No hay medios de pago disponibles para este comercio"

##### Scenario C: Credit 2-6 enabled
Mock config allows credit with maxInstallments=6.

**Assertions:**
- Plans visible: `debit_1`, `credit_1`, `credit_2_6`
- `credit_7_12` does NOT appear
- When `credit_2_6` selected, preference uses:
  - `method: "credit_card"`
  - `installmentsSeed: 2`
  - `planKey: "credit_2_6"`

## Running Tests

### Unit Tests
```bash
npm run test:unit
```

### E2E Tests
```bash
# Install Playwright browsers (first time only)
npm run playwright:install

# Run E2E tests
npm run test:e2e

# Run E2E tests in CI mode
npm run test:e2e:ci
```

### All Tests
```bash
npm run test:unit && npm run test:e2e
```

## Runtime Validation (Development)

A runtime validator is enabled automatically in development mode (`DEV_VALIDATION` flag).

**Features:**
- Logs effective config, selected plan, and payload before payment
- Validates selected plan is allowed by admin settings
- Checks for mismatches between admin rules and preference data
- Detects inconsistencies in `excludedPaymentTypes` and `allowInstallments`
- Aborts payment in dev if validation fails

**Console Output Example:**
```
[VALIDATION] Payment Flow Check
  Config efectiva: { allowInstallments: false, excludedPaymentTypes: [...] }
  Selected Plan: debit_1
  Payload to send: { baseAmount: 1000, selection: {...} }
  [VALIDATION] ✓ All checks passed
```

## Test Utilities

### Helper Functions

#### `expectSubset(obj, subset)`
Validates that an object contains a subset of properties.

```javascript
expectSubset(payload, { baseAmount: 1000 });
expectSubset(payload, { selection: { method: 'debit_card' } });
```

#### `isUUIDv4(str)`
Validates UUID v4 format.

```javascript
isUUIDv4('550e8400-e29b-41d4-a716-446655440000'); // true
isUUIDv4('invalid-uuid'); // false
```

## Mock Configuration

### Restricted Config (Credit blocked + installments off)
```json
{
  "allowPartial": true,
  "partialPercent": 30,
  "allowInstallments": false,
  "maxInstallments": 6,
  "excludedPaymentTypes": [
    "ticket","digital_currency","atm","credit_card","bank_transfer","account_money"
  ],
  "excludedPaymentMethods": [
    "pagofacil","rapipago","cabal","master","naranja","amex","mercado_credito"
  ],
  "defaultSettlementDays": null,
  "allowedSettlementDays": null
}
```

### No Plans Config
```json
{
  ...restrictedConfig,
  "excludedPaymentTypes": ["debit_card", "credit_card"]
}
```

### Credit 2-6 Config
```json
{
  "allowPartial": true,
  "allowInstallments": true,
  "maxInstallments": 6,
  "excludedPaymentTypes": ["ticket","digital_currency","atm","bank_transfer","account_money"],
  "defaultSettlementDays": 10,
  "allowedSettlementDays": [0, 10, 35]
}
```

## Acceptance Criteria

All tests validate these requirements:

✅ With restricted config (credit excluded + installments off):
- UI shows only "Débito (1 cuota)"
- Preference uses `method: "debit_card"`, `installmentsSeed: 1`, `settlementDays: 0`
- MercadoPago flow includes `excluded_payment_types` with `"credit_card"`

✅ With no valid plans:
- Checkout is disabled
- User sees error message

✅ Headers are always present:
- `Idempotency-Key` (UUID v4 format)
- `x-client-id`

✅ Plan selection respects admin rules:
- Credit plans hidden when `credit_card` excluded
- Multi-installment plans hidden when `allowInstallments: false`
- Settlement days constrained by `allowedSettlementDays`

## CI/CD Integration

Tests are configured to run in CI pipelines:

```yaml
# Example GitHub Actions workflow
- name: Run Unit Tests
  run: npm run test:unit

- name: Install Playwright
  run: npm run playwright:install

- name: Run E2E Tests
  run: npm run test:e2e:ci
```

## Troubleshooting

### E2E Tests Timing Out
- Increase timeout in `playwright.config.ts`
- Check that dev server is running on correct port
- Verify network routes are properly mocked

### Unit Tests Failing
- Check that `vitest` is installed: `npm list vitest`
- Ensure all dependencies are installed: `npm install`
- Run tests with verbose output: `npm run test:unit -- --reporter=verbose`

### Runtime Validation Errors
- Check browser console in development mode
- Verify payment settings are loaded correctly
- Ensure selected plan matches admin rules

## Contributing

When adding new payment features:
1. Add unit tests for business logic functions
2. Add integration tests for API interactions
3. Add E2E tests for complete user flows
4. Update this README with new test scenarios

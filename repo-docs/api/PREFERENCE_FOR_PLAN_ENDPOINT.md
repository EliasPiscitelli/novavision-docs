# Single-Item MP Preference Endpoint

## Overview

This endpoint creates a Mercado Pago preference with a single item whose `unit_price` equals the final quoted total (including all fees). This approach prevents "fee-on-fee" scenarios and ensures the buyer sees exactly the quoted amount.

## Endpoint

```
POST /mercadopago/create-preference-for-plan
```

## Headers

- `Authorization: Bearer <jwt>` - Required
- `x-client-id: <uuid>` - Required (tenant identifier)
- `Idempotency-Key: <uuid>` - Optional (recommended for preventing duplicate preferences)

## Request Body

```typescript
{
  baseAmount: number;        // Subtotal without fees (e.g., cart total)
  selection: {
    method: 'debit_card' | 'credit_card' | 'other';
    installmentsSeed: number;  // Number of installments (1 for debit)
    settlementDays?: number;   // Days until settlement (optional, defaults per plan)
    planKey?: string;          // Plan identifier (e.g., 'credit_2_6', 'debit_1')
  }
}
```

## Response

```typescript
{
  redirect_url: string;        // MP checkout URL (init_point)
  preference_id: string;       // MP preference ID
  external_reference: string;  // Unique order reference
}
```

## Example Request

```bash
curl -X POST https://api.example.com/mercadopago/create-preference-for-plan \
  -H "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9..." \
  -H "x-client-id: 123e4567-e89b-12d3-a456-426614174000" \
  -H "Idempotency-Key: 550e8400-e29b-41d4-a716-446655440000" \
  -H "Content-Type: application/json" \
  -d '{
    "baseAmount": 1000,
    "selection": {
      "method": "credit_card",
      "installmentsSeed": 6,
      "settlementDays": 10,
      "planKey": "credit_2_6"
    }
  }'
```

## Example Response

```json
{
  "redirect_url": "https://www.mercadopago.com.ar/checkout/v1/redirect?pref_id=123456789-abc123",
  "preference_id": "123456789-abc123",
  "external_reference": "client_123e4567_user_abc123_order_1696512000000"
}
```

## Flow

1. **Quote Calculation**: The endpoint calls `paymentsService.quote()` to calculate the total including all fees
2. **Single Item Creation**: Creates one MP item with:
   - `quantity: 1`
   - `unit_price: breakdown.total` (rounded to 2 decimals)
3. **Pre-order Persistence**: Saves preliminary order with:
   - `payment_status: 'pending'`
   - `settlement_days` and `installments` from selection
   - Full breakdown (subtotal, fees, expected MP fee, merchant net)
4. **Snapshot**: Creates audit record in `order_payment_breakdown` table
5. **MP Preference**: Creates preference via MP SDK and returns init_point

## Key Features

### Idempotency

If an `Idempotency-Key` header is provided, the endpoint:
- Checks if a preference with that key already exists
- Returns the existing preference instead of creating a new one
- Prevents accidental duplicate charges

### Rate Limiting

- **Key**: `mp:create:plan:{clientId}:{userId}`
- **Limit**: 5 requests per 60-second window
- **Response** (when limited):
  ```json
  {
    "success": false,
    "code": "RATE_LIMITED_CREATE_PREFERENCE_FOR_PLAN",
    "retry_after_ms": 45000
  }
  ```

### Settlement Days

- **Debit**: Always 0 days (immediate settlement)
- **Credit**: Configurable per plan (typically 10, 35, or custom)
- Stored in order record for audit purposes

### Installments

- **Debit**: Always 1
- **Credit**: Based on plan (e.g., 2-6, 7-12)
- Used for MP fee calculation and payment method restrictions

## Database Records Created

### orders table
```sql
INSERT INTO orders (
  user_id,
  client_id,
  payment_status,
  total_amount,
  external_reference,
  settlement_days,
  installments,
  subtotal,
  service_fee,
  customer_total,
  expected_mp_fee,
  merchant_net,
  fee_rate_used,
  order_items,
  first_name,
  last_name,
  email,
  phone_number
) VALUES (...)
```

### order_payment_breakdown table
```sql
INSERT INTO order_payment_breakdown (
  external_reference,
  client_id,
  order_id,
  base_amount,
  settlement_days,
  installments,
  extras,
  platform_fee_percent,
  mp_percent_fee,
  mp_fixed_fee,
  surcharge_mode,
  total_charged,
  net_to_seller,
  currency
) VALUES (...)
```

### mp_idempotency table (if Idempotency-Key provided)
```sql
INSERT INTO mp_idempotency (
  client_id,
  idempotency_key,
  preference_id,
  external_reference,
  response
) VALUES (...)
ON CONFLICT (client_id, idempotency_key) DO UPDATE ...
```

## Error Responses

### 400 Bad Request
```json
{
  "statusCode": 400,
  "message": "baseAmount y selection (method, installmentsSeed) son requeridos"
}
```

### 401 Unauthorized
```json
{
  "statusCode": 401,
  "message": "Falta client_id"
}
```

### 500 Internal Server Error
```json
{
  "statusCode": 500,
  "message": "Error creando preferencia para plan"
}
```

## Frontend Integration

The frontend should call this endpoint when the user selects a payment plan:

```javascript
// CartProvider.jsx
const generatePreference = async (selectedPlan) => {
  // Build selection from plan
  const selection = {
    method: selectedPlan.method, // 'debit_card' or 'credit_card'
    installmentsSeed: selectedPlan.installments, // e.g., 1, 6, 12
    settlementDays: selectedPlan.settlementDays, // e.g., 0, 10, 35
    planKey: selectedPlan.key, // e.g., 'debit_1', 'credit_2_6'
  };

  const payload = {
    baseAmount: totals.priceWithDiscount, // Cart total without fees
    selection,
  };

  const { data } = await axios.post(
    '/mercadopago/create-preference-for-plan',
    payload,
    {
      headers: {
        'Idempotency-Key': crypto.randomUUID(),
        'x-client-id': clientId,
        'Authorization': `Bearer ${token}`,
      },
    }
  );

  // Redirect to MP checkout
  if (data.redirect_url) {
    window.location.replace(data.redirect_url);
  }
};
```

## Differences from `/create-preference-advanced`

| Feature | create-preference-for-plan | create-preference-advanced |
|---------|---------------------------|----------------------------|
| Item structure | Single item (total) | Multiple items + fee item |
| Use case | Quote-based checkout | Cart-based checkout |
| Fee calculation | Via `quote()` first | During preference creation |
| Complexity | Simpler | More complex |
| Recommended for | New implementations | Legacy compatibility |

## Migration Notes

If migrating from `/create-preference-advanced`:

1. Replace endpoint URL in frontend
2. Change payload structure:
   - Remove: `items`, `totals`, `paymentMode`, `partialPercent`, `partialAmount`, `metadata`
   - Add: `baseAmount`, `selection`
3. Keep idempotency header
4. Redirect logic remains the same

## Testing

Run the test suite:

```bash
npm test -- preference-for-plan.spec.ts
```

Tests cover:
- Input validation
- Single-item structure
- Settlement days handling
- External reference format
- Idempotency behavior
- Quote integration

## Monitoring

Key metrics to monitor:

- **Success rate**: Preferences created successfully / total attempts
- **Idempotency hits**: Duplicate requests prevented
- **Rate limit hits**: Requests blocked due to rate limiting
- **Quote failures**: Failures in `paymentsService.quote()`
- **Average response time**: From request to preference creation

## Support

For issues or questions:
- Check server logs for `[createPreferenceForPlan]` entries
- Verify MP credentials are configured for the tenant
- Ensure `client_payment_settings` and fee tables are populated
- Check that quote service is working: `POST /mercadopago/quote`

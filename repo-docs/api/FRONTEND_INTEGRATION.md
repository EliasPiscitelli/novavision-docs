# Frontend Integration Guide: Single-Item Preference Endpoint

This guide explains how to integrate the new `create-preference-for-plan` endpoint in your React/Vite frontend.

## Overview

The new endpoint simplifies checkout by creating a single MP item with the total quoted price. This prevents fee calculation issues and ensures users see exactly what they'll pay.

## Prerequisites

- Backend deployed with `POST /mercadopago/create-preference-for-plan` endpoint
- CartProvider context with payment plan selection
- Axios configured with base URL and authentication

## Integration Steps

### 1. Update CartProvider

**File**: `src/contexts/CartProvider.jsx` (or similar)

#### Find the `generatePreference` function

```javascript
// BEFORE (old implementation)
const generatePreference = async () => {
  try {
    const items = cartItems.map(item => ({
      id: item.product_id,
      title: item.product.name,
      quantity: item.quantity,
      unit_price: item.product.discountedPrice || item.product.originalPrice,
      picture_url: item.product.imageUrl?.[0]?.url,
    }));

    const { data } = await axios.post('/mercadopago/create-preference-advanced', {
      items,
      totals: { total: totals.priceWithDiscount, currency: 'ARS' },
      paymentMode: 'total',
      selection: buildSelection(selectedPlan),
      metadata: { ... }
    }, {
      headers: {
        'Idempotency-Key': generateIdempotencyKey(),
        'x-client-id': resolvedClientId,
      }
    });

    if (data.redirect_url) {
      window.location.replace(data.redirect_url);
    }
  } catch (error) {
    console.error('Error generating preference:', error);
    setError('Error al crear la preferencia de pago');
  }
};
```

#### Replace with new implementation

```javascript
// AFTER (new implementation)
const generatePreference = async () => {
  try {
    // Validate that a plan is selected
    if (!selectedPlan) {
      setError('Por favor selecciona un plan de pago');
      return;
    }

    // Build selection from selected plan
    const selection = {
      method: selectedPlan.method, // 'debit_card' or 'credit_card'
      installmentsSeed: selectedPlan.installments, // 1, 6, 12, etc.
      settlementDays: selectedPlan.settlementDays ?? (
        selectedPlan.method === 'debit_card' ? 0 : paymentSettings?.defaultSettlementDays ?? 10
      ),
      planKey: selectedPlan.key || selectedPlan, // e.g., 'credit_2_6'
    };

    // Create payload with base amount and selection
    const payload = {
      baseAmount: totals.priceWithDiscount, // Cart subtotal without fees
      selection,
    };

    // Generate unique idempotency key (reuse existing if retrying)
    const idempotencyKey = currentIdempotencyKey || crypto.randomUUID();
    setCurrentIdempotencyKey(idempotencyKey);

    // Call new endpoint
    const { data } = await axios.post(
      '/mercadopago/create-preference-for-plan',
      payload,
      {
        headers: {
          'Idempotency-Key': idempotencyKey,
          'x-client-id': resolvedClientId,
        },
      }
    );

    // Handle response
    if (data.redirect_url) {
      // Save preference ID for later reference
      localStorage.setItem('pending_preference_id', data.preference_id);
      localStorage.setItem('pending_external_ref', data.external_reference);
      
      // Redirect to MP checkout
      window.location.replace(data.redirect_url);
    } else {
      throw new Error('No redirect URL received from server');
    }
  } catch (error) {
    console.error('Error generating preference:', error);
    
    // Handle specific error cases
    if (error.response?.data?.code === 'RATE_LIMITED_CREATE_PREFERENCE_FOR_PLAN') {
      const retryAfterMs = error.response.data.retry_after_ms;
      setError(`Demasiados intentos. Intenta nuevamente en ${Math.ceil(retryAfterMs / 1000)} segundos.`);
    } else {
      setError('Error al crear la preferencia de pago. Por favor intenta nuevamente.');
    }
  }
};
```

### 2. Add Helper Functions

```javascript
// Generate crypto UUID for idempotency (if not already available)
const generateIdempotencyKey = () => {
  // Modern browsers
  if (crypto?.randomUUID) {
    return crypto.randomUUID();
  }
  // Fallback
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
};
```

### 3. Update State Management

Add state for idempotency key:

```javascript
const [currentIdempotencyKey, setCurrentIdempotencyKey] = useState(null);

// Reset when plan changes
useEffect(() => {
  setCurrentIdempotencyKey(null);
}, [selectedPlan]);
```

### 4. Plan Selection Logic

Ensure your plan selection provides the required fields:

```javascript
// Example payment plans structure
const paymentPlans = [
  {
    key: 'debit_1',
    label: 'Débito (1 pago)',
    method: 'debit_card',
    installments: 1,
    settlementDays: 0,
    icon: '💳',
  },
  {
    key: 'credit_1',
    label: 'Crédito (1 pago)',
    method: 'credit_card',
    installments: 1,
    settlementDays: 10,
    icon: '💳',
  },
  {
    key: 'credit_2_6',
    label: 'Crédito (2-6 cuotas)',
    method: 'credit_card',
    installments: 6,
    settlementDays: 10,
    icon: '🔢',
  },
  {
    key: 'credit_7_12',
    label: 'Crédito (7-12 cuotas)',
    method: 'credit_card',
    installments: 12,
    settlementDays: 35,
    icon: '🔢',
  },
];
```

### 5. Error Handling

```javascript
const handleCheckoutError = (error) => {
  console.error('Checkout error:', error);

  // Rate limiting
  if (error.response?.data?.code === 'RATE_LIMITED_CREATE_PREFERENCE_FOR_PLAN') {
    const retryAfterMs = error.response.data.retry_after_ms;
    const retryAfterSec = Math.ceil(retryAfterMs / 1000);
    setError(`Demasiados intentos. Espera ${retryAfterSec}s antes de reintentar.`);
    
    // Optional: Show countdown
    let remaining = retryAfterSec;
    const interval = setInterval(() => {
      remaining--;
      if (remaining <= 0) {
        clearInterval(interval);
        setError(null);
      } else {
        setError(`Podrás reintentar en ${remaining}s`);
      }
    }, 1000);
    
    return;
  }

  // Invalid input
  if (error.response?.status === 400) {
    setError('Datos inválidos. Por favor revisa tu selección.');
    return;
  }

  // Authentication
  if (error.response?.status === 401) {
    setError('Tu sesión expiró. Por favor inicia sesión nuevamente.');
    // Redirect to login
    return;
  }

  // Server error
  if (error.response?.status === 500) {
    setError('Error del servidor. Intenta nuevamente en unos momentos.');
    return;
  }

  // Network error
  if (!error.response) {
    setError('Error de conexión. Verifica tu internet.');
    return;
  }

  // Generic error
  setError('Error inesperado. Por favor intenta nuevamente.');
};
```

### 6. Loading States

```javascript
const [isGeneratingPreference, setIsGeneratingPreference] = useState(false);

const generatePreference = async () => {
  setIsGeneratingPreference(true);
  setError(null);

  try {
    // ... (preference generation code)
  } catch (error) {
    handleCheckoutError(error);
  } finally {
    setIsGeneratingPreference(false);
  }
};

// In your JSX
<button
  onClick={generatePreference}
  disabled={isGeneratingPreference || !selectedPlan}
>
  {isGeneratingPreference ? 'Generando...' : 'Pagar con Mercado Pago'}
</button>
```

### 7. Success Page Handling

After payment, MP redirects to your success page. Handle the redirect:

```javascript
// SuccessPage.jsx
useEffect(() => {
  const confirmPayment = async () => {
    const urlParams = new URLSearchParams(window.location.search);
    const paymentId = urlParams.get('payment_id');
    const externalRef = urlParams.get('external_reference');

    // Verify payment status
    try {
      const { data } = await axios.post('/mercadopago/confirm-payment', {
        paymentId,
      });

      if (data.status === 'approved') {
        setPaymentStatus('success');
        // Clear cart
        // Show success message
      }
    } catch (error) {
      setPaymentStatus('error');
    }
  };

  confirmPayment();
}, []);
```

## Testing

### Local Testing

1. Use MP sandbox credentials in backend
2. Test with sandbox test cards: https://www.mercadopago.com.ar/developers/es/docs/checkout-pro/additional-content/test-cards
3. Verify redirect works
4. Check order created in database

### Test Cases

```javascript
// Test 1: Debit plan (1 installment, 0 settlement days)
const debitTest = {
  baseAmount: 1000,
  selection: {
    method: 'debit_card',
    installmentsSeed: 1,
    settlementDays: 0,
    planKey: 'debit_1',
  },
};

// Test 2: Credit plan (6 installments, 10 settlement days)
const creditTest = {
  baseAmount: 1000,
  selection: {
    method: 'credit_card',
    installmentsSeed: 6,
    settlementDays: 10,
    planKey: 'credit_2_6',
  },
};

// Test 3: Idempotency (same key should return same preference)
const idempotencyTest = async () => {
  const key = crypto.randomUUID();
  
  const response1 = await axios.post('/mercadopago/create-preference-for-plan', debitTest, {
    headers: { 'Idempotency-Key': key, 'x-client-id': clientId },
  });
  
  const response2 = await axios.post('/mercadopago/create-preference-for-plan', debitTest, {
    headers: { 'Idempotency-Key': key, 'x-client-id': clientId },
  });
  
  // Should be the same preference
  expect(response1.data.preference_id).toBe(response2.data.preference_id);
};
```

## Migration Checklist

- [ ] Update `CartProvider.jsx` with new `generatePreference` function
- [ ] Add idempotency key state management
- [ ] Update payment plans to include required fields
- [ ] Add error handling for rate limiting
- [ ] Test with sandbox environment
- [ ] Update success page to handle new flow
- [ ] Remove old `/create-preference-advanced` calls
- [ ] Deploy to production
- [ ] Monitor error rates and success rates

## Troubleshooting

### Issue: "baseAmount y selection son requeridos"
**Solution**: Ensure both `baseAmount` and `selection` are in the request body

### Issue: "Falta client_id"
**Solution**: Add `x-client-id` header to all requests

### Issue: Rate limiting triggered
**Solution**: Wait for the `retry_after_ms` period before retrying

### Issue: No redirect_url in response
**Solution**: Check server logs for preference creation errors

### Issue: Payment not confirmed
**Solution**: Ensure webhook is configured and accessible

## Support

- Backend documentation: `PREFERENCE_FOR_PLAN_ENDPOINT.md`
- Backend tests: `test/preference-for-plan.spec.ts`
- Changelog: `CHANGELOG.md`

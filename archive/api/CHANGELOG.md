# Changelog

## [2026-02-02] Onboarding “Completá tu tienda” + Import JSON

### Added

- **Endpoint**: `POST /client-dashboard/import-json` para importar catálogo y datos básicos con validación mínima e idempotencia.
- **Resumen de completitud**: `completion_summary` consistente con el porcentaje y el “X de Y”.

### Changed

- **Checklist de completitud**: usa requirements efectivos (defaults + override) y considera logo en draft o publicado.
- **UI onboarding**: header de pendientes, cards con regla + conteo y estado real del logo.


## [2024-10-06] Single-Item Preference Endpoint

### Added

- **New endpoint**: `POST /mercadopago/create-preference-for-plan`
  - Creates MP preferences with single item (`unit_price = total`)
  - Eliminates "fee-on-fee" issues
  - Simpler flow: quote → single item → redirect
  - Full integration with `paymentsService.quote()`
  
- **Service method**: `MercadoPagoService.createPreferenceForPlan()`
  - Accepts: `baseAmount`, `selection` (method, installments, settlementDays, planKey)
  - Returns: `init_point`, `preferenceId`, `external_reference`
  - Persists pre-order with breakdown
  - Creates audit snapshot in `order_payment_breakdown`

- **Tests**: 11 unit tests covering:
  - Input validation
  - Single-item structure
  - Settlement days and installments
  - External reference format
  - Idempotency
  - Quote integration

- **Documentation**: `PREFERENCE_FOR_PLAN_ENDPOINT.md`
  - Complete API reference
  - Frontend integration examples
  - Migration guide from `/create-preference-advanced`
  - Error handling and monitoring

### Technical Details

**Request format**:
```json
{
  "baseAmount": 1000,
  "selection": {
    "method": "credit_card",
    "installmentsSeed": 6,
    "settlementDays": 10,
    "planKey": "credit_2_6"
  }
}
```

**Response format**:
```json
{
  "redirect_url": "https://www.mercadopago.com.ar/checkout/...",
  "preference_id": "123456789-abc123",
  "external_reference": "client_xxx_user_yyy_order_zzz"
}
```

**Key features**:
- ✅ Idempotency via `Idempotency-Key` header
- ✅ Rate limiting (5 req/min per user)
- ✅ Rounding to 2 decimals
- ✅ Multi-tenant isolation
- ✅ Settlement days tracking
- ✅ Installments configuration
- ✅ Audit trail via `snapshotBreakdown()`

**Database impact**:
- Creates preliminary `orders` record with `pending` status
- Stores `settlement_days` and `installments` fields
- Records expected breakdown (subtotal, fees, merchant net)
- Creates audit record in `order_payment_breakdown`
- Optional idempotency record in `mp_idempotency`

### Modified

- `src/mercadopago/mercadopago.service.ts`: Added `createPreferenceForPlan()` method
- `src/mercadopago/mercadopago.controller.ts`: Added `POST /mercadopago/create-preference-for-plan` endpoint

### Frontend Changes Required

**Location**: `CartProvider.jsx` (in frontend repository)

**Before**:
```javascript
await axios.post('/mercadopago/create-preference-advanced', {
  items: cartItems,
  totals: { total: 1000, currency: 'ARS' },
  paymentMode: 'total',
  selection: { ... }
});
```

**After**:
```javascript
await axios.post('/mercadopago/create-preference-for-plan', {
  baseAmount: totals.priceWithDiscount,
  selection: {
    method: selectedPlan.method,
    installmentsSeed: selectedPlan.installments,
    settlementDays: selectedPlan.settlementDays,
    planKey: selectedPlan.key,
  }
});
```

### Migration Path

1. **Backend**: Deploy with new endpoint (✅ Done)
2. **Frontend**: Update `CartProvider.generatePreference()` to use new endpoint
3. **Testing**: Verify with sandbox environment
4. **Production**: Deploy frontend changes
5. **Deprecation**: Mark `/create-preference-advanced` as legacy (keep for compatibility)

### Benefits

- ✨ **Simpler**: One item instead of multiple items + fee items
- 🎯 **Accurate**: Uses quote service to calculate exact total
- 🔒 **Idempotent**: Prevents duplicate preferences
- 📊 **Auditable**: Full breakdown stored for each order
- 🚀 **Performant**: Minimal DB queries, efficient flow

### Breaking Changes

None - this is a new endpoint. Existing endpoints remain functional.

### Deprecations

None yet - `/create-preference-advanced` continues to work as before.

### Security

- Multi-tenant isolation via `client_id` filtering
- Rate limiting prevents abuse
- JWT authentication required
- Idempotency prevents replay attacks
- All DB operations tenant-scoped

### Performance

- Single DB round-trip for quote
- Optimized preference creation
- Minimal overhead vs existing endpoints
- Rate limiting prevents resource exhaustion

### Known Limitations

- Frontend integration pending (separate repository)
- No partial payment support (by design for this endpoint)
- Requires quote service to be functional

### Next Steps

- [ ] Update frontend `CartProvider.jsx`
- [ ] Add frontend tests for new flow
- [ ] Update frontend documentation
- [ ] Add monitoring dashboards
- [ ] Consider deprecating old endpoint after migration

### References

- Issue: Implementation of single-item preference flow
- Documentation: `PREFERENCE_FOR_PLAN_ENDPOINT.md`
- Tests: `test/preference-for-plan.spec.ts`
- Related: `paymentsService.quote()`, `snapshotBreakdown()`

# Shipping V2 — Plan de Implementación de Pendientes

**Fecha:** 2026-02-11  
**Autor:** agente-copilot  
**Rama API:** `feature/automatic-multiclient-onboarding`  
**Rama Web:** `feature/multitenant-storefront`

---

## Estado Actual: ~95% funcional

El shipping V2 tiene todos los bloques funcionales implementados (6/6).
Los pendientes son de **calidad, seguridad y robustez**.

---

## Tareas Ordenadas por Prioridad

### Fase A — Seguridad y Robustez (Prioridad Alta)

| # | Tarea | Esfuerzo | Archivos |
|---|-------|----------|----------|
| **A1** | Webhook signature validation | 1h | `andreani.provider.ts`, `oca.provider.ts`, `correo-argentino.provider.ts`, `shipping.service.ts` |
| **A2** | Rate limiting en endpoint de quote | 30min | `shipping.controller.ts`, `shipping.module.ts` |
| **A3** | Actualizar ShippingGuides — quitar "Próximamente" de OCA/Correo | 15min | `ShippingGuides.jsx` |

### Fase B — Tests Unitarios (Prioridad Alta)

| # | Tarea | Esfuerzo | Archivos |
|---|-------|----------|----------|
| **B1** | Tests ShippingSettingsService | 1.5h | `shipping-settings.service.spec.ts` (nuevo) |
| **B2** | Tests ShippingQuoteService | 1.5h | `shipping-quote.service.spec.ts` (nuevo) |
| **B3** | Tests ShippingService (core) | 2h | `shipping.service.spec.ts` (nuevo) |
| **B4** | Tests Providers (Andreani, OCA, Correo) | 2h | `providers/*.spec.ts` (nuevos) |
| **B5** | Tests AddressesService | 1h | `addresses.service.spec.ts` (nuevo) |

### Fase C — Mejoras de UX (Prioridad Media)

| # | Tarea | Esfuerzo | Archivos |
|---|-------|----------|----------|
| **C1** | Notificación email al comprador en cambios de tracking | 2h | `shipping.service.ts`, email templates |
| **C2** | Estimación de entrega en PDP (ficha de producto) | 30min | componentes de producto en web |

### Fase D — Mejoras Operativas (Prioridad Baja)

| # | Tarea | Esfuerzo | Archivos |
|---|-------|----------|----------|
| **D1** | Retry/DLQ para webhooks fallidos | 2h | `shipping.service.ts`, posible nueva tabla |
| **D2** | Vista shipping en Admin Panel (super_admin) | 3h | `apps/admin/src/` — nuevos archivos |
| **D3** | Checkout multi-page/stepper | 5h | `CartPage/index.jsx`, nuevas rutas |

---

## Detalle por Tarea

### A1 — Webhook Signature Validation

**Problema:** Los 3 providers (Andreani, OCA, Correo) reciben `secret?` como parámetro en `handleWebhook()` pero nunca lo validan. El endpoint `POST /shipping/webhooks/:provider` está abierto (`@AllowNoTenant()`).

**Solución:**
1. En `ShippingService.handleProviderWebhook()`: extraer header `x-signature` / `x-webhook-secret` del request
2. Antes de delegar al provider, validar el secreto contra el `webhook_secret` almacenado en `shipping_integrations.credentials`
3. Si no hay secreto configurado, logear warning pero permitir (backward compatible)
4. Si hay secreto y no coincide, rechazar con 401

**Archivos:**
- `shipping.service.ts` — agregar validación antes de `provider.handleWebhook()`
- `shipping.controller.ts` — pasar headers/raw body al service
- Cada provider opcionalmente puede validar firma específica (HMAC para Andreani, etc.)

### A2 — Rate Limiting QuoteEndpoint

**Problema:** `POST /shipping/quote` llama a APIs externas sin rate limit. Un usuario podría spammear cotizaciones.

**Solución:**
1. Usar `@nestjs/throttler` (ya debe estar disponible o instalar)
2. Aplicar `@Throttle({ default: { limit: 10, ttl: 60 } })` al endpoint de quote
3. Para provider_api quotes: el cache de 30min ya mitiga parcialmente

**Archivos:**
- `shipping.controller.ts` — decorador `@Throttle` en `quote()`
- `shipping.module.ts` — importar `ThrottlerModule` si no está global

### A3 — Actualizar ShippingGuides

**Problema:** OCA y Correo Argentino dicen "Próximamente — API en desarrollo" pero los providers ya están implementados.

**Solución:** Cambiar subtítulo a "Integración API completa" y quitar badge "Próximamente".

**Archivos:**
- `ShippingGuides.jsx` — 2 líneas a cambiar

### B1-B5 — Tests Unitarios

**Patrón de testing:**
- Mockear `SupabaseClient` con stubs de `.from().select().eq()...`
- Mockear `EncryptionService` con encrypt/decrypt transparente
- Mockear `PlansService` con feature checks
- Para providers: mockear `fetch` / `fetchWithTimeout`
- Cada test sigue: Given-When-Then

**Cobertura mínima por service:**
- Settings: CRUD + validaciones + cache
- Quote: flat/zone/provider_api + free shipping + edge cases
- Core: integrations CRUD + shipment lifecycle + webhook flow
- Providers: quoteRates, createShipment mock responses
- Addresses: CRUD + validation

---

## Orden de Ejecución

```
A1 → A2 → A3 → B1 → B2 → B3 → B4 → B5 → C1 → C2 → D1 → [commit/push]
```

Cada tarea se commitea individualmente tras verificar lint + typecheck.

---

## Criterio de Completitud

- [x] 0 errores de TypeScript (`npx tsc --noEmit`)
- [x] 0 errores de ESLint
- [x] Webhook endpoint valida secreto cuando está configurado — commit `46f4fc7`
- [x] Quote endpoint tiene rate limit (10 req/min) — commit `46f4fc7`
- [x] ShippingGuides sin "Próximamente" para providers implementados — commit `3136f49`
- [x] Tests unitarios: 124 tests en 5 suites — commit `7a2d7a1`
  - ShippingSettingsService: 26 tests
  - ShippingQuoteService: 22 tests
  - ShippingService: 40 tests
  - Providers (Manual/Andreani/OCA/CorreoArgentino): 26 tests
  - AddressesService: 10 tests
- [x] C1: Email notification al comprador en cambios de tracking — commit `ec1a09d`
  - ShippingNotificationService con templates HTML, deduplicación, fire-and-forget
  - Notifica en: picked_up, in_transit, out_for_delivery, delivered, failed, returned
- [x] C2: Estimación de entrega en PDP — commit `973871e` (web) + cherry-pick `6c64dbd` (develop)
  - ShippingEstimator component con input de CP + provincia
  - Llama POST /shipping/quote en tiempo real
  - Muestra costo, envío gratis, días estimados, zona
- [x] D1: Retry/DLQ para webhooks fallidos — commit `d7b5efe`
  - ShippingWebhookRetryService con backoff exponencial (1m/5m/15m)
  - Dead Letter Queue tras 3 intentos fallidos
  - Migración: tabla shipping_webhook_failures
  - Endpoints admin: GET /shipping/webhook-failures, POST .../retry
- [x] Commits atómicos con formato `feat(api):` / `fix(web):`
- [x] Push a ramas correspondientes + cherry-pick a develop (web)

### Completados (última sesión)
- [x] D2: Vista shipping en Admin Panel (super_admin) — API commit `26e3c8a` + Admin commit `2d3bca6`
  - AdminShippingController con 5 endpoints (settings, integrations, shipments, zones, webhook-failures)
  - ShippingView.jsx (~700 líneas) con 4 tabs: Configuración, Integraciones, Envíos, Webhook Failures
  - Ruta /admin/shipping en sidebar del admin panel
- [x] D3: Checkout multi-step stepper — Web commit `ebc6249` + cherry-pick `e2b01ab` (develop)
  - useCheckoutStepper hook (nav + validación por gate + sessionStorage)
  - CheckoutStepper container con header de progreso, sidebar resumen, nav footer
  - 4 pasos: CartStep, ShippingStep (reutiliza ShippingSection), PaymentStep (reutiliza PlanSelector), ConfirmationStep
  - CartPage reducido a wrapper de 16 líneas
  - Mobile responsive: nav fijo bottom, stacked layout ≤768px
  - Slide animations con dirección (forward/back)

### Phase 4 — Modelo de Configuración (sesión actual)
- [x] Seed shipping settings en onboarding — API commit `f19788b`
  - Flujo A (trial/draft): step 7.2 con upsert onConflict client_id
  - Flujo B (post-pago): step 9.2 con upsert onConflict client_id
  - Defaults: todos los métodos deshabilitados, pricing_mode=zone
- [x] Validación estricta de pricing mode — API commit `f19788b`
  - upsertSettings: rechaza valores != zone/flat/provider_api con 400
  - upsertSettings: origin_address obligatoria si provider_api + delivery habilitado
  - calculateDeliveryCost: default case lanza 400 en vez de retornar cost 0
- [x] Delivery method en OrderDashboard — Web commit `847f119` + cherry-pick `280c35c` (develop)
  - Labels: 🚚 Envío, 🏪 Retiro, 💬 Coordinar
  - Visible en columna Envío debajo del badge de shipping_status
- [x] Documentación completa del modelo: `architecture/SHIPPING_CONFIG_MODEL.md` — commit `a6c16dd`
  - Default/Opcional/Excluyente claramente definido
  - Feature gate por plan (starter vs growth+)
  - Schema de settings, lifecycle de tienda nueva, validaciones server

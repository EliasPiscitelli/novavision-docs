# PR4: Integración Mercado Pago para packs SEO AI + Webhook + UI Store Admin

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

## Archivos modificados / creados

### API (templatetwobe)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/seo-ai-billing/seo-ai-purchase.service.ts` | NUEVO | Servicio de compra: crea billing event + preferencia MP, procesa webhook con idempotencia |
| `src/seo-ai-billing/seo-ai-purchase.controller.ts` | NUEVO | Controller con 4 endpoints: `GET /seo-ai/packs`, `POST /seo-ai/purchase`, `GET /seo-ai/my-credits`, `POST /seo-ai/webhook` |
| `src/seo-ai-billing/seo-ai-billing.module.ts` | MODIFICADO | Agregados imports de ConfigModule, JwtModule, SubscriptionsModule (forwardRef) + nuevos providers/controllers |

### Web (templatetwo)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/components/admin/SeoAutopilotDashboard/index.jsx` | NUEVO | Dashboard con balance de créditos, grid de packs con botón "Comprar", historial de movimientos |
| `src/pages/AdminDashboard/index.jsx` | MODIFICADO | Agregada sección `seoAutopilot` a SECTION_DETAILS, SECTION_CATEGORIES ("Marca y Contenido"), SECTION_FEATURES, y switch case |

## Resumen de cambios

### Backend — Flujo de compra completo

1. **`POST /seo-ai/purchase`** (ClientDashboardGuard):
   - Valida pack en `addon_catalog`
   - Crea `nv_billing_events` (type=`one_time_service`) con metadata `{addon_key, credits_amount}`
   - Crea preferencia MP via `PlatformMercadoPagoService.createPreference()`
   - Retorna `{billing_event_id, init_point, sandbox_init_point}`

2. **`POST /seo-ai/webhook`** (AllowNoTenant, HttpCode 200):
   - Verifica HMAC signature (MP_WEBHOOK_SECRET_PLATFORM)
   - Obtiene payment de MP para verificar status + external_reference
   - Solo procesa `NVBILL:*` (ignora suscripciones/órdenes tenant)
   - Solo procesa status `approved`
   - Llama `BillingService.handlePaymentSuccess()` — idempotente (atomic CAS `neq('status','paid')`)
   - Si primera vez: agrega créditos al ledger `seo_ai_credits`

3. **`GET /seo-ai/packs`** (público, AllowNoTenant):
   - Retorna catálogo de packs activos desde `addon_catalog`

4. **`GET /seo-ai/my-credits`** (ClientDashboardGuard):
   - Retorna balance + historial paginado del account

### Frontend — Sección en Admin Dashboard

- Nueva card "🤖 SEO AI Autopilot" en categoría "Marca y Contenido"
- Feature-gated por `seo.ai_autopilot` (del featureCatalog)
- Muestra: balance prominente, grid de 3 packs con precio y botón "Comprar", historial de créditos
- Flujo de compra: click → `POST /seo-ai/purchase` → redirect a MP → return con `?status=success` → reload balance
- Detecta return de MP y refresca datos automáticamente

## Decisiones de arquitectura

1. **Webhook dedicado** (`POST /seo-ai/webhook`) en vez de reusar `POST /subscriptions/webhook` — evita acoplar con MpRouterService y reduce riesgo de regresión en suscripciones.

2. **Idempotencia dual**: `BillingService.handlePaymentSuccess()` ya es idempotente (CAS atómico). Si retorna `true` (ya pagado), no se agregan créditos duplicados. Si retorna el event object (primera vez), se agregan créditos.

3. **`forwardRef(() => SubscriptionsModule)`** en SeoAiBillingModule — para romper dependencia circular (BillingModule ya importa SubscriptionsModule).

4. **notification_url** usa `BACKEND_URL` (misma env var que tenant payments).

5. **back_urls**: el frontend envía su `origin` como `back_base_url`, el backend construye paths con `billing_event_id` y `status`.

## Cómo probar

### Backend (terminal back)
```bash
npm run lint && npm run typecheck && npm run build
# Levantar: npm run start:dev

# Test manual — listar packs (público):
curl http://localhost:3000/seo-ai/packs

# Test manual — comprar (requiere auth):
curl -X POST http://localhost:3000/seo-ai/purchase \
  -H "Authorization: Bearer <JWT>" \
  -H "X-Builder-Token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"addon_key":"seo_ai_pack_500"}'
```

### Frontend (terminal front)
```bash
npm run lint && npm run typecheck && npm run build
# Levantar: npm run dev

# Navegar a /admin-dashboard → click "SEO AI Autopilot"
# Verificar: balance, packs, botón comprar
```

### Verificar idempotencia webhook
```bash
# Enviar mismo webhook dos veces — segunda vez no debe duplicar créditos
curl -X POST http://localhost:3000/seo-ai/webhook \
  -H "Content-Type: application/json" \
  -d '{"type":"payment","data":{"id":"<MP_PAYMENT_ID>"}}'
```

## Notas de seguridad

- `POST /seo-ai/webhook` no requiere auth (es callback de MP), pero verifica firma HMAC en producción
- `POST /seo-ai/purchase` requiere autenticación (ClientDashboardGuard: builder token o Supabase JWT admin)
- La preferencia MP se crea con precios del backend (no se confía en el frontend)
- No se exponen tokens ni claves secretas en el frontend

## Riesgos

- **`BACKEND_URL` no configurada**: el webhook MP no recibirá la `notification_url`. Mitigación: log de warning en el servicio.
- **Circular dependency**: `forwardRef` en el import de SubscriptionsModule. Testeado: build compila sin problemas.
- **Feature gate `seo.ai_autopilot`**: todos los planes la tienen en `false` (featureCatalog PR2). La card aparecerá bloqueada hasta que se habilite por plan o se aplique un `feature_override` en el onboarding de la tienda.

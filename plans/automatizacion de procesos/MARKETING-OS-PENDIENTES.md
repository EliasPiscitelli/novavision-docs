# Marketing OS — Items Pendientes por Fase

**Fecha:** 2026-03-17
**Base:** PLAN_MARKETING_OS_v2.md (130 items totales, ~55% completado)
**Branch:** feature/multitenant-storefront
**Regla:** Cada fase se valida con datos de prueba y se limpian al terminar

---

## FASE 1 — Lifecycle & Cleanup (Prioridad ALTA, pre-lanzamiento)

Sin esto, las cuentas de prueba/trial acumulan infra sin pagar.

### 1A. Funcion SQL `delete_account_cascade(p_account_id UUID)`

**Ubicacion:** Admin DB (RPC)
**Dependencias:** Conocer FK order de ambas DBs

**Logica:**
1. Obtener `client_id` desde Backend DB via `clients.nv_account_id`
2. Backend DB — borrar en orden:
   - cart_items, favorites
   - order_items, orders, payments, mp_idempotency
   - products, categories, product_categories
   - banners, logos, faqs, services, social_links, contact_info
   - client_home_settings, home_sections, tenant_pages
   - client_payment_settings, client_extra_costs, client_mp_fee_overrides
   - client_design_overrides, client_slot_limits
   - client_secrets, client_usage, cors_origins, email_jobs
   - shipping_*, user_addresses
   - seo_settings
   - users
   - clients
3. Admin DB — borrar (CASCADE desde nv_accounts cubre la mayoria):
   - usage_ledger, usage_daily, usage_hourly
   - client_themes, custom_palettes
   - nv_accounts (CASCADE: subscriptions, lifecycle_events, provisioning_jobs, coupon_redemptions, nv_onboarding, etc.)
4. Supabase Auth — DELETE user via Admin API
5. INSERT en `client_tombstones` (nueva tabla): client_id, account_id, slug, email, plan_key, deleted_at, reason

**Validacion:**
- Crear cuenta de prueba completa (nv_accounts + clients + productos + ordenes)
- Ejecutar `delete_account_cascade`
- Verificar 0 filas residuales en ambas DBs
- Verificar registro en `client_tombstones`
- Limpiar tombstone de prueba

---

### 1B. Cleanup Cron (`lifecycle/cleanup.cron.ts`)

**Ubicacion:** `apps/api/src/lifecycle/cleanup.cron.ts`
**Trigger:** Cron diario 3:00 AM UTC
**Modulo:** Crear `LifecycleModule` con `CleanupCron` service

**6 Pasos:**
1. `suspendExpiredTrials()` — nv_accounts con status='provisioned' y trial_ends_at < NOW() - 3 dias → status='suspended'
2. `scheduleExpiredSuspensions()` — nv_accounts con status='suspended' hace >30 dias → status='scheduled_for_deletion'
3. `executeScheduledDeletions()` — Llamar `delete_account_cascade` para cuentas scheduled hace >7 dias
4. `detectAndNotifyZombies()` — Cuentas activas sin ordenes ni login en 90 dias → log + notificacion founder
5. `releaseDeletedSlugs()` — Liberar slugs de cuentas borradas
6. `logCleanupResult()` — Registrar en system_events

**Validacion:**
- Insertar cuentas de prueba en distintos estados (trial vencido, suspended >30d, zombie)
- Ejecutar cron manualmente
- Verificar transiciones correctas
- Verificar notificacion de zombie llega por WA
- Limpiar datos de prueba

---

### 1C. Tabla `client_tombstones`

**Ubicacion:** Admin DB

```sql
CREATE TABLE IF NOT EXISTS client_tombstones (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID,
  account_id UUID,
  slug TEXT,
  email TEXT,
  plan_key TEXT,
  deleted_at TIMESTAMPTZ DEFAULT NOW(),
  reason TEXT,
  metadata JSONB DEFAULT '{}'
);
```

**RLS:** service_role + is_super_admin

---

## FASE 2 — Notificaciones en Flujos de Negocio (Prioridad ALTA)

El modulo `FounderNotificationsModule` existe pero no esta integrado en los eventos de negocio.

### 2A. Notificacion: Cuenta nueva registrada

**Archivo:** `src/onboarding/onboarding.service.ts`
**Donde:** Despues de crear draft account (mismo bloque que CompleteRegistration CAPI ~761)
**Mensaje:** "Nueva cuenta: {email} | Plan: {plan_key} | Fuente: {utm_source}"

### 2B. Notificacion: Primer pago recibido

**Archivo:** `src/subscriptions/subscriptions.service.ts` o donde se procesa payment approved
**Donde:** Despues de confirmar pago MP exitoso
**Mensaje:** "Primer pago: {email} | Plan: {plan_key} | Monto: {amount} | MRR actual: {mrr}"

### 2C. Notificacion: Pago fallido

**Archivo:** Donde se procesa webhook MP con status != approved
**Donde:** Despues de detectar pago fallido
**Mensaje:** "Pago fallido: {email} | Plan: {plan_key} | Motivo: {status_detail}"

### 2D. Notificacion: Onboarding completado (submitForReview)

**Archivo:** `src/onboarding/onboarding.service.ts`
**Donde:** Mismo bloque que Lead CAPI (~2776)
**Mensaje:** "Onboarding completado: {email} | Template: {template} | Siguiente: revisar y aprobar"

**Validacion para toda la Fase 2:**
- Triggear cada flujo manualmente (crear cuenta, simular pago, simular fallo, submit review)
- Verificar que llegan 4 mensajes WA distintos al founder
- No dejar datos residuales (borrar cuentas de prueba)

---

## FASE 3 — Cupon FUNDADORES2026 (Prioridad MEDIA)

### 3A. Insertar cupon en Admin DB

```sql
INSERT INTO coupons (code, discount_type, discount_value, max_uses, valid_until, plan_restriction, description)
VALUES ('FUNDADORES2026', 'percentage', 40, 50, '2026-07-31', 'growth', '40% off primer mes Growth - Fundadores');
```

### 3B. Verificar que el checkout flow lo acepta

**Validacion:**
- Aplicar cupon en flujo de checkout
- Verificar que el monto se calcula correctamente (60 * 0.6 = USD 36)
- Verificar que no se puede usar en plan Starter
- Verificar que max_uses funciona
- Revertir datos de prueba

---

## FASE 4 — UTMs y Tracking (Prioridad MEDIA)

### 4A. Documentar UTM naming convention

Crear seccion en este doc o en doc separado:
```
utm_source:   meta | google | tiktok | whatsapp | email | organic
utm_medium:   paid_social | paid_search | outreach | referral
utm_campaign: tof_arg | retargeting | search_brand | search_problem | awareness
utm_content:  video_0comision | carrusel_5razones | demo_admin
utm_term:     (solo Google Search — keyword que triggeo el click)
```

### 4B. Agregar UTMs a links de outreach en n8n

**Archivos:** Workflows n8n de outreach existentes
**Accion:** Verificar que todos los links incluyan UTMs correctos

### 4C. Capturar UTMs en registro

**Archivo:** `src/onboarding/onboarding.service.ts`
**Accion:** Verificar que `utm_source`, `utm_medium`, `utm_campaign` se guardan en nv_accounts o nv_onboarding al crear cuenta

**Validacion:**
- Visitar URL con UTMs → registrarse → verificar que se guardaron en DB
- Limpiar cuenta de prueba

---

## FASE 5 — Growth HQ Completo (Prioridad BAJA)

### 5A. Bloque Outreach en Growth HQ

**API:** Agregar a `growth-hq.service.ts`
- Total leads contactados (del CRM)
- En conversacion
- Hot leads
- Cold/lost

**Admin:** Agregar bloque en GrowthHqView.jsx

### 5B. Bloque Infraestructura en Growth HQ

**API:** Agregar a `growth-hq.service.ts`
- Cuentas activas / suspendidas / scheduled_deletion
- Zombies detectados
- Proxima ejecucion de cleanup

**Admin:** Agregar bloque en GrowthHqView.jsx

### 5C. Funnel completo con drop-off

**API:** Extender metricas de funnel para incluir:
- Visitas (requiere analytics — puede venir de GA4 API o ad_performance_daily impressions)
- Plan seleccionado (paso intermedio entre onboarding y pago)
- Calcular drop-off % entre cada paso

**Validacion:**
- Verificar que Growth HQ muestra todos los bloques
- Datos reales o RPCs con datos de prueba
- Limpiar datos de prueba

---

## FASE 6 — Tracking Server-Side Unificado (Prioridad BAJA)

### 6A. `TrackingEventsService` unificado

**Archivo:** Crear `src/tracking/tracking-events.service.ts`
**Funcion:** `fireEvent(eventName, userData, eventData)` que dispara en paralelo a:
- Meta CAPI (ya existe via MetaCapiModule)
- TikTok Events API (nuevo)
- GA4 Measurement Protocol (nuevo)
- Log interno Supabase (nuevo)

### 6B. TikTok Events API server-side

**Endpoint:** `https://business-api.tiktok.com/open_api/v1.3/event/track/`
**Eventos:** CompleteRegistration, Subscribe, Lead (mismos que Meta CAPI)
**Requiere:** TIKTOK_ACCESS_TOKEN, TIKTOK_PIXEL_ID (Fase 2 de credenciales)

### 6C. GA4 Measurement Protocol server-side

**Endpoint:** `https://www.google-analytics.com/mp/collect`
**Requiere:** GA4_MEASUREMENT_ID, GA4_API_SECRET
**Eventos:** sign_up, begin_checkout, purchase

**Validacion:**
- Disparar evento de prueba
- Verificar que llega a Meta Events Manager, TikTok Events, GA4 Realtime
- Sin datos residuales (eventos de prueba se marcan con test_event_code)

---

## FASE 7 — Creatividades Automatizadas (Prioridad BAJA)

### 7A. Flujo upload → Meta API → borrador → activar

**Archivo:** Extender `ad_assets` CRUD en API + workflow n8n
**Flujo:**
1. Founder sube video en admin panel
2. API sube a Supabase Storage
3. Webhook a n8n
4. n8n crea Ad Creative en Meta API (estado PAUSED)
5. Notifica al founder con preview
6. Founder aprueba → n8n activa el anuncio

### 7B. Sugerencia IA de proximo video

**Workflow:** n8n cron semanal
**Logica:** Analizar ad_assets + ad_performance_daily → GPT-4o sugiere que tipo de video grabar basado en gaps y fatiga

**Validacion:**
- Subir video de prueba
- Verificar que se crea Creative en Meta (modo test)
- Verificar notificacion WA
- Borrar creative de prueba y asset

---

## FASE 8 — Landing y Pre-Lanzamiento (Prioridad MEDIA, pero requiere Web)

### 8A. Optimizar landing de registro

- Headline especifico: "Crea tu tienda sin pagar comisiones"
- CTA visible sin scroll
- Social proof: "X tiendas activas" o logos
- Precio visible: "Desde USD 20/mes"

### 8B. Test E2E completo

- Click en link con UTMs → registro → onboarding → pago con cupon → verificar tracking + notificaciones
- Usar datos de prueba de MP sandbox
- Limpiar todo al terminar

---

## Orden de ejecucion recomendado

| Orden | Fase | Esfuerzo | Bloquea lanzamiento? |
|-------|------|----------|---------------------|
| 1 | Fase 2 — Notificaciones en flujos | ~3 horas | Si — sin esto no sabes cuando alguien se registra/paga |
| 2 | Fase 3 — Cupon FUNDADORES2026 | ~1 hora | Si — herramienta de adquisicion del dia 1 |
| 3 | Fase 1 — Lifecycle & Cleanup | ~6 horas | Si — sin esto acumulas infra muerta |
| 4 | Fase 4 — UTMs | ~2 horas | Recomendado — sin esto no sabes de donde vienen los clientes |
| 5 | Fase 8 — Landing | ~4 horas | Recomendado — landing es la primera impresion |
| 6 | Fase 5 — Growth HQ completo | ~4 horas | No — funciona con lo que hay |
| 7 | Fase 6 — Tracking unificado | ~6 horas | No — CAPI Meta ya funciona |
| 8 | Fase 7 — Creatividades auto | ~6 horas | No — se puede subir manual mientras tanto |

# Marketing OS — Implementacion completa (DB + API + Admin + Web + n8n)

**Fecha:** 2026-03-17
**Alcance:** Admin DB, Backend DB, API (NestJS), Admin Dashboard, Web Storefront, n8n workflows
**Branch:** feature/multitenant-storefront
**Estado:** Implementado, pendiente credenciales de plataformas publicitarias para activar

---

## Contexto

Sistema completo de marketing automatizado que reemplaza los servicios de agencias TOU (ARS 1.2M setup + ARS 1.15M/mes) y FLY/VUZZ (USD 1.020/mes). Incluye reporting diario/semanal con IA, auto-optimizacion de presupuesto, publicacion de creatives, contenido organico y monitor de competidores.

---

## Bloque 2 — Migraciones SQL

### Admin DB (`erbfzlsznqsmwmjugspo`)

**Tablas creadas:**

| Tabla | Columnas clave | RLS |
|-------|---------------|-----|
| `ad_assets` | id, title, media_type, media_url, platform, hook_text, status, campaign_id, performance_score | service_role + is_super_admin |
| `ad_performance_daily` | id, date, platform, campaign_id, ad_id, ad_name, spend, impressions, clicks, conversions, cpl, cpc, ctr, roas | service_role + is_super_admin |
| `campaign_registry` | id, platform, campaign_id, campaign_name, objective, status, daily_budget, total_budget, start_date, end_date | service_role + is_super_admin |

**Indices:**
- `ad_performance_daily`: UNIQUE on (date, platform, ad_id)
- `campaign_registry`: UNIQUE on (platform, campaign_id)

**RPCs creadas:**
- `get_daily_funnel_metrics(p_date DATE)` RETURNS JSON — Metricas de funnel para una fecha (registros, onboardings, pagos, MRR)
- `get_weekly_funnel_metrics(p_days INTEGER DEFAULT 7)` RETURNS JSON — Metricas semanales (registros, onboardings, pagos, MRR, outreach, hot leads)

### Backend DB (`ulndkhijxtxvpmbbfrgp`)

- `ALTER TABLE seo_settings ADD COLUMN IF NOT EXISTS tiktok_pixel_id TEXT` — Soporte TikTok Pixel por tenant

---

## Bloque 4 — Nuevos modulos API (NestJS)

### `FounderNotificationsModule`

**Archivos:**
- `src/founder-notifications/founder-notifications.service.ts`
- `src/founder-notifications/founder-notifications.module.ts`

**Funcionalidad:** Envio de notificaciones WhatsApp al founder via WhatsApp Cloud API.

| Metodo | Descripcion |
|--------|-------------|
| `sendText(message)` | Texto plano al founder |
| `sendReport(title, body)` | Reporte formateado |
| `sendAlert(alertType, details)` | Alerta urgente con emoji |

**Env vars requeridas:** `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TOKEN`, `FOUNDER_WHATSAPP_NUMBER`

### `GrowthHqModule`

**Archivos:**
- `src/growth-hq/growth-hq.service.ts`
- `src/growth-hq/growth-hq.controller.ts`
- `src/growth-hq/growth-hq.module.ts`

**Endpoint:** `GET /admin/growth-hq/metrics?days=7`

**Response:** `GrowthMetrics` con funnel (registros, onboardings, pagos, MRR), ads (spend, clicks, impressions, CPL, CAC, ROAS), campaigns, top_ads, hot_leads.

**Registrados en:** `app.module.ts` (despues de CrmModule)

---

## Bloque 5 — Eventos CAPI adicionales

**Archivo modificado:** `src/onboarding/onboarding.service.ts`

| Evento | Donde se dispara | Linea aprox. |
|--------|-----------------|--------------|
| `CompleteRegistration` | Despues de crear draft account | ~759 |
| `Lead` | Al final de `submitForReview()` | ~2772 |

**Patron:** Fire-and-forget con try/catch. Usa `this.metaCapi.sendEvent()` existente. Se activa cuando se configuren `META_PIXEL_ID` y `META_ACCESS_TOKEN`.

---

## Bloque 7 — Vistas Admin Dashboard

**Archivos creados:**

| Vista | Archivo | Descripcion |
|-------|---------|-------------|
| Growth HQ | `src/pages/AdminDashboard/GrowthHqView.jsx` (445 lines) | KPI cards (MRR, CAC, CPL, ROAS), charts Recharts, periodo 7/14/30d |
| Ad Assets | `src/pages/AdminDashboard/AdAssetsView.jsx` (722 lines) | CRUD de creatives, grid/table toggle, status badges |
| Ad Performance | `src/pages/AdminDashboard/AdPerformanceView.jsx` (490 lines) | Tabla de metricas diarias, filtros fecha/plataforma |

**Archivos modificados:**
- `src/pages/AdminDashboard/index.jsx` — 3 nav items nuevos (superOnly: true)
- `src/App.jsx` — 3 rutas nuevas

**Tema visual:** Dark theme tokens (`#101322`, `#131627`, `#1c2033`, `#e2e6ff`, `#8c94c2`)

---

## Bloque 8 — Tracking Web completo

### Brechas cerradas

| Componente | Archivo | Evento agregado |
|-----------|---------|-----------------|
| SearchPage | `pages/SearchPage/index.jsx` | `trackSearch()` al cargar resultados con query |
| SearchPage/ProductCard | `pages/SearchPage/ProductCard.jsx` | `trackAddToCart()` al agregar desde card |
| CartPage | `pages/CartPage/index.jsx` | `trackBeginCheckout()` al iniciar pago |

### TikTok Pixel — Soporte completo

**`hooks/useEcommerceTracking.js`:**
- Nueva funcion `fireTikTokEvent()` — wrapper safe para `window.ttq.track()`
- Eventos TikTok en: ViewContent, AddToCart, InitiateCheckout, PlaceAnOrder, Search
- Nuevo flag `hasTikTok` en return

**`components/SEOHead/index.jsx`:**
- Snippet TikTok Pixel (`ttq.load()`) — gated por cookie consent y `tiktok_pixel_id`

### Cobertura de funnel completa

```
search → view_item → add_to_cart → begin_checkout → purchase
  GA4       GA4         GA4           GA4             GA4
  Meta      Meta        Meta          Meta            Meta
  GTM       GTM         GTM           GTM             GTM
  TikTok    TikTok      TikTok        TikTok          TikTok
```

---

## Bloque 6 — Workflows n8n (8 totales: 6 Meta + 2 Google)

**Instancia:** `n8n-production-c19d.up.railway.app` (n8n 2.12.2)
**Total workflows:** 22 (14 existentes + 6 Meta nuevos + 2 Google nuevos)
**Estado Meta:** Todos OFF, credenciales configuradas — activar al lanzar primera campana
**Estado Google:** JSONs listos, pendientes credenciales Google Ads

### Workflows Meta (6) — importados en n8n

| Workflow | Nodos | Trigger | Funcion |
|----------|-------|---------|---------|
| `NV Ads Daily Reporter` | 8 | Cron 8AM diario | Reporte Meta + funnel + IA + auto-pause |
| `NV Weekly AI Report` | 6 | Cron dom 8AM | Reporte estrategico semanal GPT-4o |
| `NV Ads Content Publisher` | 7 | Webhook POST | Publica creatives en Meta |
| `NV Smart Budget Optimizer` | 11 | Cron 9AM/5PM | 4 reglas auto de presupuesto |
| `NV Organic Content Scheduler` | 11 | Cron cada hora | Contenido organico IG/FB |
| `NV Competitor Monitor` | 10 | Cron lun/jue 10AM | Monitor ads competidores |

### Workflows Google Ads (2) — JSONs listos, importar cuando tenga credenciales

| Workflow | Nodos | Trigger | Funcion |
|----------|-------|---------|---------|
| `NV Google Ads Daily Reporter` | 7 | Cron 8:30AM diario | Reporte Google + funnel + IA + alerta (no auto-pause) |
| `NV Google Ads Optimizer` | 7 | Cron 9:30AM/5:30PM | 4 reglas: pausar, escalar, bid, copy — solo alertas WA |

**Diferencia clave Google vs Meta:** Google Ads NO se auto-modifica. El algoritmo de Google necesita mas tiempo de aprendizaje que Meta, asi que los workflows solo generan alertas por WhatsApp para que el founder decida.

**JSONs guardados en:** `novavision-docs/n8n-workflows/`

---

## Dependencias pendientes

### Meta — Credenciales LISTAS, pendiente activacion

1. ~~Crear cuentas Meta Business~~ HECHO
2. ~~Obtener tokens y configurar env vars~~ HECHO (11/11 permisos, Railway deployado)
3. ~~Configurar FOUNDER_PHONE y FOUNDER_WHATSAPP_NUMBER~~ HECHO
4. Activar workflows uno por uno al lanzar primera campana
5. ~~Crear tabla content_calendar en Admin DB~~ HECHO

### Google Ads — Pendiente credenciales (preparar antes del lanzamiento)

1. Crear cuenta Google Ads (https://ads.google.com/)
2. Habilitar Google Ads API en Google Cloud Console
3. Crear OAuth 2.0 Client ID (redirect URI: n8n callback)
4. Solicitar Developer Token (API Center, 1-3 dias)
5. Obtener Refresh Token via n8n OAuth
6. Cargar variables en Railway n8n: GOOGLE_ADS_CLIENT_ID, GOOGLE_ADS_CLIENT_SECRET, GOOGLE_ADS_REFRESH_TOKEN, GOOGLE_ADS_DEVELOPER_TOKEN, GOOGLE_ADS_CUSTOMER_ID
7. Importar 2 workflows Google en n8n

### TikTok Ads — Fase 2 (semana 6+)

1. Crear cuenta TikTok Business Center
2. Crear App de Marketing
3. Obtener tokens y Advertiser ID

---

## Post-implementacion (mismo dia)

### Tabla `content_calendar` en Admin DB
- 14 columnas: id, scheduled_at, platform, content_type, hook, caption, cta, media_url, status, published_at, external_post_id, error_message, created_at, updated_at
- CHECK constraints en `platform` y `content_type` y `status`
- RLS: service_role + is_super_admin
- Index optimizado para scheduler query: `idx_content_calendar_pending` (WHERE status = 'TO_GO')
- Usada por workflow `NV Organic Content Scheduler`

### FOUNDER_PHONE configurado
- n8n Railway: `FOUNDER_PHONE=5491133027458`
- API .env: `FOUNDER_WHATSAPP_NUMBER=5491133027458`

### Test end-to-end exitoso
- Supabase RPC `get_weekly_funnel_metrics` → datos reales (19 registros, MRR USD 60)
- OpenAI GPT-4o-mini → analisis CMO en 168 tokens
- WhatsApp Cloud API → mensaje entregado a 5491133027458 (wamid: 7F45185F39DA71BAD6)
- Datos demo insertados y borrados correctamente (0 filas residuales)

### Guia de credenciales actualizada
- Centralizada en app `NovaVision_Chat` (ID 1329707212512102) — no crear apps nuevas
- System User existente: "n8n-access" (ID 122117557977141981) — solo tiene permisos WA, necesita ads
- Archivo: `novavision-docs/plans/automatizacion de procesos/MARKETING-OS-CREDENTIALS-GUIDE.md`

---

## Validacion

- `npm run build` (API): OK — TypeScript compila limpio
- `vite build` (Admin): OK — 7.2s
- `vite build` (Web): OK — 7.23s
- SQL migrations: ejecutadas y validadas con datos demo (borrados)
- n8n import: 6/6 workflows importados exitosamente
- Test e2e Supabase → OpenAI → WhatsApp: OK

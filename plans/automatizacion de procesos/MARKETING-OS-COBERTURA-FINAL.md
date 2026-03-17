# Marketing OS — Cobertura Final vs Agencias

**Fecha:** 2026-03-17
**Estado:** Implementado y deployado. Workflows pendientes de activacion al lanzar primera campana.

---

## Cobertura comparada

| Capacidad | Agencia TOU (USD 2.150/mes) | Agencia FLY/VUZZ (USD 1.020/mes) | Marketing OS NovaVision (USD ~100/mes infra) |
|-----------|---------------------------|----------------------------------|----------------------------------------------|
| Meta Ads gestion | Manual | Manual | Automatizado |
| Google Ads | Extra (no incluido) | Excluido | Preparado, activar semana 3-4 |
| TikTok Ads | No | No | Fase 2 |
| Tracking Pixel (client-side) | Si | Basico | GA4 + Meta + TikTok + GTM |
| Tracking CAPI (server-side) | Si | No mencionan | 3 eventos (CompleteRegistration, Subscribe, Lead) |
| Reporte diario | No | No | Automatico 8AM + WhatsApp |
| Reporte semanal con IA | No | Mensual manual | GPT-4o domingos |
| Auto-pause ads malos | No (manual) | No (manual semanal) | Automatico |
| Auto-scale ads ganadores | No | No | 2x/dia |
| Monitor competidores | No | No | 2x/semana con IA |
| Content publishing organico | No | No | Automatico desde content_calendar |
| Dashboard funnel completo | No | Dashboard basico | Growth HQ (MRR, CAC, CPL, ROAS, funnel) |
| Creatividades/mes | 6-10 piezas | 8-10 piezas | Founder graba, sistema publica |
| Control de activos | Parcial | Parcial | 100% propio |
| Canales | Solo Meta | Solo Meta | Meta + Google (preparado) + TikTok (fase 2) |

---

## Componentes implementados

### API (NestJS)

| Componente | Estado | Detalle |
|-----------|--------|---------|
| `FounderNotificationsModule` | Implementado | 3 metodos: sendText, sendReport, sendAlert. WhatsApp Cloud API |
| `GrowthHqModule` | Implementado | `GET /admin/growth-hq/metrics?days=7`. Funnel + ads + campaigns + top_ads + hot_leads |
| `MetaCapiModule` | Implementado | Server-side pixel events |
| CAPI `CompleteRegistration` | Implementado | onboarding.service.ts ~761 |
| CAPI `Subscribe` | Implementado | onboarding.service.ts ~1378 |
| CAPI `Lead` | Implementado | onboarding.service.ts ~2776 |

### Web Storefront (tracking por tenant)

| Componente | Estado | Plataformas |
|-----------|--------|-------------|
| `useEcommerceTracking.js` | Implementado | GA4 + Meta + TikTok + GTM |
| SEOHead TikTok Pixel | Implementado | Gated por consent + tiktok_pixel_id |
| trackSearch (SearchPage) | Implementado | Con dedup |
| trackAddToCart (ProductCard) | Implementado | |
| trackBeginCheckout (CartPage) | Implementado | |
| trackViewItem (ProductPage) | Implementado | Ya existia |
| trackPurchase | Implementado | Ya existia |

**Funnel completo cubierto:**
```
search -> view_item -> add_to_cart -> begin_checkout -> purchase
  GA4       GA4         GA4           GA4             GA4
  Meta      Meta        Meta          Meta            Meta
  TikTok    TikTok      TikTok        TikTok          TikTok
  GTM       GTM         GTM           GTM             GTM
```

### Admin Dashboard

| Vista | Archivo | Funcion |
|-------|---------|---------|
| Growth HQ | GrowthHqView.jsx | KPI cards (MRR, CAC, CPL, ROAS), charts, periodo 7/14/30d |
| Ad Assets | AdAssetsView.jsx | CRUD de creatives, grid/table toggle |
| Ad Performance | AdPerformanceView.jsx | Tabla metricas diarias, filtros fecha/plataforma |

### Base de datos (Admin DB)

| Tabla | Estado |
|-------|--------|
| `ad_assets` | Creada, RLS activo |
| `ad_performance_daily` | Creada, index UNIQUE (date, platform, ad_id) |
| `campaign_registry` | Creada, index UNIQUE (platform, campaign_id) |
| `content_calendar` | Creada, index optimizado para scheduler |
| RPC `get_daily_funnel_metrics` | Creada |
| RPC `get_weekly_funnel_metrics` | Creada |

### n8n Workflows (6)

| Workflow | Nodos | Trigger | Funcion |
|----------|-------|---------|---------|
| NV Ads Daily Reporter | 8 | Cron 8AM diario | Reporte Meta + funnel + IA + auto-pause |
| NV Weekly AI Report | 6 | Cron dom 8AM | Reporte estrategico semanal GPT-4o |
| NV Ads Content Publisher | 7 | Webhook POST | Publica creatives en Meta |
| NV Smart Budget Optimizer | 11 | Cron 9AM/5PM | 4 reglas auto de presupuesto |
| NV Organic Content Scheduler | 11 | Cron cada hora | Contenido organico IG/FB |
| NV Competitor Monitor | 10 | Cron lun/jue 10AM | Monitor ads competidores |

**Estado:** Todos importados en n8n Railway. OFF hasta activacion.
**JSONs:** `novavision-docs/n8n-workflows/nv_*.json`

---

## Credenciales configuradas

### Railway API Service (`templatetwobe`)

| Variable | Estado |
|----------|--------|
| `META_ACCESS_TOKEN` | Configurada (11 permisos) |
| `META_PIXEL_ID` | `1672700600055618` |
| `WHATSAPP_PHONE_NUMBER_ID` | `889890894207625` |
| `FOUNDER_WHATSAPP_NUMBER` | `5491133027458` |
| `WHATSAPP_API_VERSION` | `v22.0` |

### Railway n8n Service

| Variable | Estado |
|----------|--------|
| `META_ACCESS_TOKEN` | Configurada (sincronizada con WHATSAPP_TOKEN) |
| `META_AD_ACCOUNT_ID` | `act_1766930843903464` |
| `META_PIXEL_ID` | `1672700600055618` |
| `META_PAGE_ID` | `680885328440333` |
| `INSTAGRAM_ACCOUNT_ID` | `17841474787534725` |
| `FOUNDER_PHONE` | `5491133027458` |

### Permisos del token (11/11)

ads_management, ads_read, business_management, read_insights, instagram_basic, instagram_content_publish, whatsapp_business_management, pages_read_engagement, pages_manage_posts, whatsapp_business_messaging, public_profile

---

## Ahorro proyectado

| Periodo | vs TOU | vs FLY/VUZZ |
|---------|--------|-------------|
| Mes 1 | -USD 1.575 | -USD 470 |
| 3 meses | -USD 3.525 | -USD 1.335 |
| 12 meses | -USD 14.100 | -USD 5.340 |

*(Considerando ~USD 125/mes de infra + misma pauta USD 450)*

---

## Ventajas sobre las agencias

1. **Reportes diarios** — las agencias dan reportes mensuales
2. **Auto-optimizacion de presupuesto** — las agencias lo hacen manual, semanal
3. **Monitor de competidores con IA** — ninguna agencia lo ofrecia
4. **CAPI server-side** — FLY/VUZZ ni lo mencionaba
5. **Multi-plataforma tracking** — GA4 + Meta + TikTok + GTM vs solo Meta Pixel
6. **Multi-canal** — Meta + Google (preparado) vs solo Meta
7. **100% control de activos** — cuentas, datos, tokens, todo propio

## Lo que no reemplaza

- **Produccion de creatividades** (6-10 piezas/mes). Grabar videos y disenar piezas sigue siendo manual o requiere freelancer UGC.
- **Experiencia creativa** — saber que hooks y angulos funcionan. El sistema te da los datos para iterar, pero la intuicion creativa se aprende con la practica.

---

## Roadmap de activacion

### Semana 0 (lanzamiento)
1. Crear primera campana en Meta Ads Manager
2. Activar workflows n8n uno por uno con datos reales
3. Verificar reportes diarios por WhatsApp

### Semana 2
1. Evaluar metricas iniciales (CPL, CPA, ROAS)
2. Iterar creatividades segun datos

### Semana 3-4
1. Configurar credenciales Google Ads (ver seccion abajo)
2. Activar campanas Google Search + PMAX
3. Evaluar TikTok Ads para semana 6+

---

## Google Ads — Preparacion anticipada

### Credenciales necesarias

| Variable | Descripcion | Donde obtenerla |
|----------|-------------|-----------------|
| `GOOGLE_ADS_CLIENT_ID` | OAuth Client ID | Google Cloud Console > Credentials |
| `GOOGLE_ADS_CLIENT_SECRET` | OAuth Client Secret | Google Cloud Console > Credentials |
| `GOOGLE_ADS_REFRESH_TOKEN` | OAuth Refresh Token | Via n8n OAuth flow |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | API Developer Token | Google Ads > Tools > API Center |
| `GOOGLE_ADS_CUSTOMER_ID` | ID de cuenta (sin guiones) | Google Ads > esquina superior derecha |

### Recursos existentes (Google Cloud — proyecto `novavision-462019`)

- **Proyecto GCP:** NovaVision (`novavision-462019`)
- **OAuth Client existente:** `novavision-n8n` (creado 18 Nov 2025, tipo Web App)
  - Client ID: `211650624476-qcdr...` (ver completo en GCP Console > Credentials)
  - **REUTILIZAR ESTE** — solo verificar que el Redirect URI incluya el callback de n8n
- **API Key:** `API key 1` (Jun 2025) — no sirve para Google Ads, se necesita OAuth
- **Otros OAuth clients:** `Sheets DB`, `n8n NovaVision`, `NovaVision Web Auth` — no tocar

### Pasos de configuracion

#### Paso 1 — Crear cuenta Google Ads (si no tenes)

Google Ads intenta llevarte al flujo guiado que pide medio de pago. Para evitarlo:

1. Ir a https://ads.google.com/
2. Si te pide crear una campana, busca el link **"Crear una cuenta sin una campana"** o **"Cambiar a modo experto"** (suele estar al pie de la primera pantalla, en texto chico)
3. Si no aparece ese link:
   - Opcion A: Ir directo a https://ads.google.com/aw/signup y buscar "Skip" o "Create account without a campaign"
   - Opcion B: Crear la cuenta con una campana dummy → pausarla inmediatamente → ir a Tools > API Center
   - Opcion C: Si ya tenes una cuenta de Google Ads vinculada a tu email, ir directo a https://ads.google.com/ — puede que ya exista
4. Configuracion: moneda USD, zona horaria Buenos Aires
5. **Customer ID:** el numero de 10 digitos en la esquina superior derecha (formato XXX-XXX-XXXX). Para las env vars, quitar los guiones.

#### Paso 2 — Habilitar Google Ads API

👉 https://console.cloud.google.com/apis/library/googleads.googleapis.com?project=novavision-462019

Click "Habilitar". Si ya esta habilitada, no hacer nada.

#### Paso 3 — Verificar OAuth Client `novavision-n8n`

👉 https://console.cloud.google.com/apis/credentials?project=novavision-462019

1. Click en `novavision-n8n` (el OAuth client del 18 Nov 2025)
2. Verificar que en "URIs de redireccionamiento autorizados" este incluida:
   ```
   https://n8n-production-c19d.up.railway.app/rest/oauth2-credential/callback
   ```
3. Si no esta, agregala y guardar
4. Copiar el **Client ID** completo y el **Client Secret**

#### Paso 4 — Solicitar Developer Token

1. Ir a Google Ads → icono de llave/herramientas → **API Center** (o Setup > API Center)
2. Si es la primera vez, te pide aceptar terminos
3. El Developer Token aparece ahi. Estado posible:
   - **Test account:** funciona solo con cuentas de prueba (suficiente para preparar)
   - **Basic access:** funciona con cuentas reales (se obtiene despues de la primera revision)
4. Copiar el Developer Token

#### Paso 5 — Conectar en n8n via OAuth

1. Ir a n8n: https://n8n-production-c19d.up.railway.app/
2. Settings → Credentials → New Credential → buscar "Google Ads"
3. Ingresar:
   - Client ID (de `novavision-n8n`)
   - Client Secret
   - Developer Token
4. Click "Sign in with Google" → autorizar con tu cuenta
5. n8n obtiene automaticamente el Refresh Token

#### Paso 6 — Cargar variables en Railway n8n

```env
GOOGLE_ADS_CUSTOMER_ID=XXXXXXXXXX        (sin guiones)
GOOGLE_ADS_DEVELOPER_TOKEN=XXXXX         (de API Center)
GOOGLE_ADS_ACCESS_TOKEN=ya-lo-maneja-n8n (si se usa credential nativa de n8n, no hace falta)
```

Nota: Si se usa la credential nativa de n8n para Google Ads (paso 5), los workflows pueden usar el nodo `Google Ads` nativo en vez de HTTP requests manuales. En ese caso, las env vars de OAuth no son necesarias — n8n maneja el refresh token internamente.

#### Paso 7 — Importar workflows Google en n8n

```bash
# Desde la maquina local, copiar los JSONs al container y importar
cat novavision-docs/n8n-workflows/nv_google_ads_daily_reporter.json | \
  railway ssh --service n8n -- n8n import:workflow --input=-

cat novavision-docs/n8n-workflows/nv_google_ads_optimizer.json | \
  railway ssh --service n8n -- n8n import:workflow --input=-
```

### Workflows Google Ads (ya creados, listos para importar)

| Workflow | Nodos | Trigger | Funcion |
|----------|-------|---------|---------|
| NV Google Ads Daily Reporter | 7 | Cron 8:30AM diario | Reporte Google + funnel + IA + alerta (no auto-pause) |
| NV Google Ads Optimizer | 7 | Cron 9:30AM/5:30PM | 4 reglas: pausar, escalar, bid, copy — solo alertas WA |

**Diferencia clave vs Meta:** Google Ads workflows solo envian alertas por WhatsApp — no modifican campanas automaticamente. Google necesita mas tiempo de aprendizaje.

**JSONs en:** `novavision-docs/n8n-workflows/nv_google_ads_*.json`

**Recomendacion:** Completar pasos 1-5 ANTES del lanzamiento (~30 min). Asi cuando llegue la semana 3-4 con datos de Meta, solo hay que importar workflows y activar campanas.

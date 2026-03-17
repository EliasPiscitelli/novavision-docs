# Marketing OS — Guia de Credenciales

**Fecha:** 2026-03-17 (actualizado)
**App centralizada:** NovaVision_Chat — ID `1329707212512102`
**Principio:** TODO se gestiona desde una sola app de Meta. No crear apps adicionales.

---

## Estado actual de credenciales

| Variable | n8n | API | Estado |
|----------|-----|-----|--------|
| `WHATSAPP_PHONE_NUMBER_ID` | `889890894207625` | ✅ | YA CONFIGURADA |
| `WHATSAPP_TOKEN` | `EAAS5XJ...` | ✅ | YA CONFIGURADA |
| `META_APP_SECRET` | `b1b3c729...` | ✅ (`WHATSAPP_APP_SECRET`) | YA CONFIGURADA |
| `META_GRAPH_VERSION` | `v25.0` | — | YA CONFIGURADA |
| `META_IG_ACCESS_TOKEN` | `IGAAUWQ...` | — | YA CONFIGURADA |
| `META_IG_REPLY_ENDPOINT_ID` | `17841474787534725` | — | YA CONFIGURADA |
| `OPENAI_API_KEY` | ✅ | — | YA CONFIGURADA |
| `SUPABASE_URL` | ✅ | ✅ | YA CONFIGURADA |
| `SUPABASE_SERVICE_ROLE` | ✅ | ✅ | YA CONFIGURADA |
| `META_AD_ACCOUNT_ID` | ❌ | — | **PENDIENTE** |
| `META_ACCESS_TOKEN` | ❌ | ❌ | **PENDIENTE** |
| `META_PIXEL_ID` | ❌ | ❌ | **PENDIENTE** |
| `META_PAGE_ID` | ❌ | — | **PENDIENTE** |
| `INSTAGRAM_ACCOUNT_ID` | ❌ | — | **PENDIENTE** |
| `FOUNDER_PHONE` | ❌ | — | **PENDIENTE** |
| `FOUNDER_WHATSAPP_NUMBER` | — | ❌ | **PENDIENTE** |
| `TIKTOK_*` | ❌ | — | FASE 2 (esperar datos Meta) |
| `GOOGLE_ADS_*` | ❌ | — | FASE 2 (esperar datos Meta) |

---

## PASO 1 — Agregar productos a la app existente (5 min)

La app `NovaVision_Chat` (1329707212512102) ya tiene WhatsApp, Messenger e Instagram.
Solo falta agregar **Marketing API** y **App Events**.

1. Ir a: https://developers.facebook.com/apps/1329707212512102/dashboard/
2. En la seccion "Agrega productos a tu app":
   - Click **"Configurar"** en **API de marketing** → seguir los pasos
   - Click **"Configurar"** en **App Events** → seguir los pasos
3. Listo. No se necesita aprobacion extra porque la app ya esta verificada.

---

## PASO 2 — Crear System User con permisos de ads (10 min)

El token `WHATSAPP_TOKEN` que ya tenes probablemente NO tiene permisos de ads.
Necesitas un token nuevo (o extender el existente) con los scopes de Marketing API.

1. Ir a: https://business.facebook.com/settings/system-users
2. **Si ya tenes un System User** (el que genero WHATSAPP_TOKEN):
   - Click en el user → "Generar nuevo token"
   - Seleccionar la app **NovaVision_Chat (1329707212512102)**
   - Marcar TODOS estos permisos:
     - `whatsapp_business_messaging` (ya lo tiene)
     - `whatsapp_business_management` (ya lo tiene)
     - `ads_management` ← **NUEVO**
     - `ads_read` ← **NUEVO**
     - `business_management` ← **NUEVO**
     - `pages_read_engagement` ← **NUEVO**
     - `pages_manage_posts` ← **NUEVO** (para organic publishing)
     - `instagram_basic` (ya lo tiene via IG)
     - `instagram_content_publish` ← **NUEVO**
     - `read_insights` ← **NUEVO** (para Meta Ads Library)
   - Click "Generar token"
   - **IMPORTANTE:** Este token nuevo reemplaza al anterior. Tener a mano el viejo por si hay que rollback.

3. **Si NO tenes System User**, crear uno:
   - Click "Agregar" → nombre: "NovaVision Marketing OS" → Rol: Admin
   - Asignar assets: la cuenta de anuncios, la pagina de FB, la cuenta de IG
   - Generar token con todos los permisos de arriba

4. Copiar el token → este valor va en:
   - **n8n:** `META_ACCESS_TOKEN`
   - **API (.env):** `META_ACCESS_TOKEN`
   - **n8n:** Actualizar `WHATSAPP_TOKEN` si el nuevo token reemplaza al viejo

> **Nota:** Un solo token con todos los permisos sirve para WhatsApp + Ads + CAPI + IG Publishing.
> No necesitas tokens separados.

---

## PASO 3 — Obtener Ad Account ID (2 min)

1. Ir a: https://business.facebook.com/settings/ad-accounts
2. Si no tenes cuenta de anuncios:
   - Click "Agregar" → "Crear una nueva cuenta publicitaria"
   - Nombre: "NovaVision Ads"
   - Moneda: USD, Zona horaria: Buenos Aires
3. El ID aparece con formato `act_XXXXXXXXXX` (con el prefijo `act_`)
4. Copiar → **n8n:** `META_AD_ACCOUNT_ID`

> **Alternativa rapida:** `https://business.facebook.com/settings/ad-accounts` → el numero debajo del nombre de la cuenta

---

## PASO 4 — Crear/Obtener Meta Pixel (3 min)

1. Ir a: https://business.facebook.com/events_manager2/overview
2. Si ya tenes un Pixel:
   - Click en el Pixel → "Settings" → copiar el Pixel ID (numero de ~16 digitos)
3. Si no tenes Pixel:
   - Click "Connect data" → "Web" → "Meta Pixel"
   - Nombre: "NovaVision Pixel"
   - Se crea automaticamente
   - Copiar el ID
4. El Pixel ID va en:
   - **n8n:** `META_PIXEL_ID`
   - **API (.env):** `META_PIXEL_ID`

> **El snippet del Pixel en el storefront ya esta implementado.** Lo carga SEOHead cuando el tenant tiene `meta_pixel_id` en `seo_settings`. El Pixel de aca es para CAPI (server-side events desde la API).

---

## PASO 5 — Obtener Page ID e Instagram Account ID (3 min)

### Page ID

Opcion A — Desde la UI:
1. Ir a tu pagina de Facebook de NovaVision
2. Click en "Acerca de" → "Transparencia de la pagina" → ahi esta el ID

Opcion B — Via API (mas rapido):
```bash
curl "https://graph.facebook.com/v25.0/me/accounts?access_token={TU_TOKEN_DEL_PASO_2}"
```
El campo `id` de la pagina es tu `META_PAGE_ID`.

### Instagram Account ID

```bash
curl "https://graph.facebook.com/v25.0/{META_PAGE_ID}?fields=instagram_business_account&access_token={TU_TOKEN}"
```
El campo `instagram_business_account.id` → **n8n:** `INSTAGRAM_ACCOUNT_ID`

> **Nota:** Ya tenes `META_IG_REPLY_ENDPOINT_ID=17841474787534725` en n8n.
> Es probable que `INSTAGRAM_ACCOUNT_ID` sea ese mismo valor o similar.
> Verificar con el curl de arriba.

---

## PASO 6 — Configurar FOUNDER_PHONE (1 min)

Tu numero de WhatsApp personal donde recibiras los reportes diarios/semanales.

1. Formato: `5491112345678` (codigo pais + area sin 0 + numero sin 15)
   - Ejemplo: si tu numero es 011-15-1234-5678 → `5491112345678`

2. Configurar en n8n Railway:
   - https://railway.com/project/828177bd-da44-40b3-ae37-197ad8e9b6f6
   - Service n8n → Variables → agregar `FOUNDER_PHONE=54XXXXXXXXXX`

3. Configurar en API Railway:
   - Service API → Variables → agregar `FOUNDER_WHATSAPP_NUMBER=54XXXXXXXXXX`

---

## PASO 7 — Cargar las variables en Railway (5 min)

### En n8n (service n8n):

```env
META_AD_ACCOUNT_ID=act_XXXXXXXXXX
META_ACCESS_TOKEN=EAA...   (token del paso 2)
META_PIXEL_ID=XXXXXXXXXX
META_PAGE_ID=XXXXXXXXXX
INSTAGRAM_ACCOUNT_ID=XXXXXXXXXX
FOUNDER_PHONE=54XXXXXXXXXX
```

> Si el nuevo token del paso 2 reemplaza al viejo, tambien actualizar:
> `WHATSAPP_TOKEN=EAA...` (mismo token nuevo)

### En API (service API):

```env
META_PIXEL_ID=XXXXXXXXXX
META_ACCESS_TOKEN=EAA...   (mismo token)
FOUNDER_WHATSAPP_NUMBER=54XXXXXXXXXX
```

### Acceso directo a Railway:
- Proyecto: https://railway.com/project/828177bd-da44-40b3-ae37-197ad8e9b6f6
- Environment: production

---

## PASO 8 — Verificar que todo funciona (5 min)

### Test 1: Token de Meta funciona para Ads

```bash
# Reemplazar {TOKEN} y {AD_ACCOUNT_ID} con tus valores
curl "https://graph.facebook.com/v25.0/act_{AD_ACCOUNT_ID}?fields=name,currency,timezone_name&access_token={TOKEN}"
```
Si devuelve el nombre de tu cuenta → funciona.

### Test 2: CAPI/Pixel funciona

```bash
curl "https://graph.facebook.com/v25.0/{PIXEL_ID}?fields=name,id&access_token={TOKEN}"
```

### Test 3: Page + IG funciona

```bash
curl "https://graph.facebook.com/v25.0/{PAGE_ID}?fields=name,instagram_business_account&access_token={TOKEN}"
```

### Test 4: WhatsApp funciona (ya deberia funcionar)

```bash
curl -X POST "https://graph.facebook.com/v25.0/889890894207625/messages" \
  -H "Authorization: Bearer {TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"messaging_product":"whatsapp","to":"{TU_NUMERO}","type":"text","text":{"body":"Test Marketing OS OK"}}'
```

---

## FASE 2 — Google Ads (cuando Meta ya tenga 2 semanas de datos)

### Variables necesarias

| Variable | Descripcion |
|----------|-------------|
| `GOOGLE_ADS_CLIENT_ID` | OAuth Client ID |
| `GOOGLE_ADS_CLIENT_SECRET` | OAuth Client Secret |
| `GOOGLE_ADS_REFRESH_TOKEN` | OAuth Refresh Token |
| `GOOGLE_ADS_DEVELOPER_TOKEN` | Developer Token de la API |
| `GOOGLE_ADS_CUSTOMER_ID` | ID de cuenta (sin guiones) |

### Paso a paso

1. **Crear cuenta Google Ads**: https://ads.google.com/
2. **Solicitar Developer Token**: Tools & Settings → API Center
   - Tarda 1-3 dias pero funciona en modo test mientras tanto
3. **Crear OAuth en Google Cloud Console**: https://console.cloud.google.com/apis/credentials
   - Habilitar Google Ads API: https://console.cloud.google.com/apis/library/googleads.googleapis.com
   - Crear "OAuth 2.0 Client ID" tipo Web Application
   - Redirect URI: `https://n8n-production-c19d.up.railway.app/rest/oauth2-credential/callback`
4. **Obtener Refresh Token** via n8n: Settings → Credentials → crear "Google Ads" → autorizar
5. **Customer ID**: esquina superior derecha en ads.google.com, formato XXXXXXXXXX (sin guiones)

---

## FASE 2 — TikTok Ads (cuando Meta ya tenga 3+ semanas de datos)

### Variables necesarias

| Variable | Descripcion |
|----------|-------------|
| `TIKTOK_ACCESS_TOKEN` | Long-lived token |
| `TIKTOK_ADVERTISER_ID` | ID de advertiser |

### Paso a paso

1. **Crear cuenta TikTok Business Center**: https://business.tiktok.com/
2. **Crear App de Marketing**: https://business-api.tiktok.com/portal/apps
   - Scopes: `ad.read`, `ad.write`, `report.read`, `campaign.read`, `campaign.write`
3. **Obtener Advertiser ID**: https://ads.tiktok.com/ → configuracion de cuenta
4. **Crear TikTok Pixel** (para web tracking):
   - https://ads.tiktok.com/ → Assets → Events → Web Events → crear Pixel
   - Guardar el ID en `seo_settings.tiktok_pixel_id` del tenant

### Verificar

```bash
curl -H "Access-Token: {TOKEN}" \
  "https://business-api.tiktok.com/open_api/v1.3/advertiser/info/?advertiser_ids=[{ID}]"
```

---

## Resumen: que hacer ahora (orden recomendado)

| # | Accion | Tiempo | Desbloquea |
|---|--------|--------|------------|
| 1 | Agregar Marketing API + App Events a la app | 5 min | Nada visible, prerequisito |
| 2 | Generar System User token con permisos de ads | 10 min | Todo Meta |
| 3 | Obtener Ad Account ID (o crear cuenta de anuncios) | 2 min | Workflows de ads |
| 4 | Crear/obtener Meta Pixel ID | 3 min | CAPI server-side |
| 5 | Obtener Page ID + IG Account ID | 3 min | Content publishing |
| 6 | Decidir tu FOUNDER_PHONE | 1 min | Reportes WA |
| 7 | Cargar todo en Railway (n8n + API) | 5 min | Activacion |
| 8 | Verificar con los 4 curl tests | 5 min | Confianza |
| **Total** | | **~35 min** | **Marketing OS activo** |

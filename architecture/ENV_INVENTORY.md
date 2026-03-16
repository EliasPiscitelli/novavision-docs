# Inventario de Variables de Entorno — NovaVision Platform

> Ultima actualizacion: 2026-03-16

Este documento lista las variables de entorno utilizadas en las 3 aplicaciones del monorepo (`api`, `web`, `admin`), agrupadas por servicio.

---

## API (NestJS — `@nv/api`)

Las variables se leen via `process.env.*` o `ConfigService.get()`.

### Supabase — Backend DB (multi-tenant)

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `SUPABASE_URL` | Si | — | URL del proyecto Supabase de backend (tiendas publicadas) |
| `SUPABASE_KEY` | No | — | Anon key de backend Supabase (usada en request-client helper) |
| `SUPABASE_ANON_KEY` | No | — | Alias de anon key para backend Supabase |
| `SUPABASE_SERVICE_ROLE_KEY` | Si | — | Service role key de backend Supabase (acceso elevado) |

### Supabase — Admin DB (onboarding / cuentas)

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `SUPABASE_ADMIN_URL` | Si | — | URL del proyecto Supabase de admin (nv_accounts) |
| `SUPABASE_ADMIN_SERVICE_ROLE_KEY` | Si | — | Service role key del proyecto admin |

### Base de Datos Directa

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `ADMIN_DB_URL` | No | — | Connection string PostgreSQL directa a la Admin DB (health check) |
| `BACKEND_DB_URL` | No | — | Connection string PostgreSQL directa a la Backend DB (health check) |
| `DEFAULT_BACKEND_CLUSTER_ID` | No | `'default'` | Cluster ID por defecto para el DbRouterService |
| `PGP_ENCRYPTION_KEY` | No | — | Clave de encriptacion PGP usada por el DbRouterService |

### Redis

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `REDIS_URL` | No | — | URL completa de conexion Redis (tiene prioridad sobre host/port) |
| `REDIS_HOST` | No | — | Host de Redis (fallback si no hay REDIS_URL) |
| `REDIS_PORT` | No | `6379` | Puerto de Redis |
| `REDIS_PASSWORD` | No | — | Password de Redis |
| `REDIS_DB` | No | `0` | Numero de base de datos Redis |
| `REDIS_TLS` | No | `'false'` | Habilitar TLS para Redis (`'true'` / `'false'`) |

### MercadoPago

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `PLATFORM_MP_ACCESS_TOKEN` | Si | — | Access token de la cuenta MP de la plataforma (suscripciones, dominios) |
| `MERCADO_PAGO_ACCESS_TOKEN` | No | — | Access token legacy (fallback) |
| `MP_WEBHOOK_SECRET` | No | — | Secret generico para validar webhooks de MP |
| `MP_WEBHOOK_SECRET_PLATFORM` | No | — | Secret especifico para webhooks de plataforma |
| `MP_WEBHOOK_SECRET_TENANT` | No | — | Secret especifico para webhooks de tenant |
| `MP_FEE_RATE` | No | — | Tasa de comision MP por defecto (fallback si no hay tabla) |
| `MP_FORCE_SANDBOX` | No | `'false'` | Forzar modo sandbox aun en produccion |
| `MP_SANDBOX_MODE` | No | `'false'` | Habilitar sandbox para suscripciones de plataforma |
| `MP_TEST_PAYER_EMAIL` | No | — | Email de pagador de prueba para sandbox |
| `MP_TOKEN_ENCRYPTION_KEY` | No | — | Clave hex para encriptar tokens MP de tenants |

### Netlify

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `NETLIFY_API_TOKEN` | Si | — | Token de API de Netlify para gestion de dominios custom |
| `NETLIFY_STOREFRONT_SITE_ID` | Si | — | Site ID del storefront en Netlify |
| `NETLIFY_SITE_ID` | No | — | Alias legacy de `NETLIFY_STOREFRONT_SITE_ID` |
| `NETLIFY_DEFAULT_DOMAIN` | No | — | Dominio por defecto de Netlify (e.g. `novavision-test.netlify.app`) |

### Namecheap (Dominios Gestionados)

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `NAMECHEAP_API_USER` | No | — | Usuario de API de Namecheap |
| `NAMECHEAP_API_KEY` | No | — | API key de Namecheap |

### URLs y Origenes

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `BACKEND_URL` | Si | — | URL publica del backend (webhooks MP, notificaciones) |
| `ADMIN_URL` | Si | `'https://admin.novavision.lat'` | URL del dashboard Admin (emails, redirects OAuth) |
| `ONBOARDING_URL` | No | `'http://localhost:5173'` | URL del flujo de onboarding |
| `STORES_URL` | No | — | URL base de los storefronts |
| `PUBLIC_BASE_URL` | No | — | URL publica del API (OAuth callbacks) |
| `PUBLIC_AUTH_HUB_BASE` | No | — | URL base del auth hub |
| `FRONTEND_BASE_URL` | No | — | URL del frontend (origenes permitidos) |
| `FRONTEND_ADMIN_URL` | No | `'https://admin.novavision.app'` | URL del admin para billing callbacks |
| `ALLOWED_ORIGINS` | No | — | Lista de origenes permitidos separados por coma |
| `ALLOWED_CLIENT_ORIGINS` | No | — | Origenes adicionales de clientes para CORS |
| `CORS_ORIGINS` | No | — | Origenes CORS adicionales |
| `SELF_URL` | No | `'http://localhost:3000'` | URL propia del API (outreach webhooks) |

### Autenticacion y Seguridad

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `JWT_SECRET` | Si | — | Secret para firmar/verificar JWT de sesiones builder |
| `OAUTH_STATE_SECRET` | Si | — | Secret para firmar estado OAuth (min 32 chars) |
| `AUTH_STATE_SECRET` | No | — | Alias de `OAUTH_STATE_SECRET` |
| `INTERNAL_ACCESS_KEY` | No | — | Key para endpoints internos (super admin, scripts) |
| `TURNSTILE_SECRET_KEY` | No | — | Secret de Cloudflare Turnstile para captcha |
| `PREVIEW_TOKEN_SECRET` | No | — | Secret para tokens de preview de tiendas |
| `DEBUG_TOKEN` | No | — | Token para endpoints de debug (solo no-produccion) |
| `ALLOW_TENANT_HOST_HEADER` | No | `'false'` | Permitir header `X-Tenant-Host` (solo dev) |
| `PUBLIC_FORCE_LOCAL_REDIRECT` | No | `'false'` | Forzar redirect local en OAuth |

### Email / SMTP

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `EMAIL_PROVIDER` | No | `'smtp'` | Proveedor de email (`smtp`, `postmark`, `sendgrid`) |
| `SMTP_HOST` | No | — | Host SMTP |
| `SMTP_PORT` | No | `587` | Puerto SMTP |
| `SMTP_USER` | No | — | Usuario SMTP |
| `SMTP_PASS` | No | — | Password SMTP |
| `SMTP_SECURE` | No | — | SMTP seguro (true/false) |
| `SMTP_URL` | No | — | URL SMTP completa (override) |
| `SMTP_TIMEOUT_MS` | No | `15000` | Timeout SMTP en ms |
| `SMTP_POOL` | No | `'false'` | Pool de conexiones SMTP |
| `SMTP_DEBUG` | No | `'false'` | Debug SMTP |
| `SMTP_AUTH_METHOD` | No | — | Metodo de autenticacion SMTP |
| `SMTP_CLIENT_NAME` | No | — | Nombre del cliente SMTP (EHLO) |
| `SMTP_REJECT_UNAUTHORIZED` | No | — | Rechazar certificados no autorizados |
| `SMTP_TEST_TO` | No | — | Email de prueba para SMTP |
| `SUPABASE_SMTP_USER` | No | — | Alias Supabase para SMTP user |
| `SUPABASE_SMTP_PASS` | No | — | Alias Supabase para SMTP pass |
| `SUPABASE_SMTP_HOST` | No | — | Alias Supabase para SMTP host |
| `SUPABASE_SMTP_PORT` | No | — | Alias Supabase para SMTP port |
| `SUPABASE_SMTP_SECURE` | No | — | Alias Supabase para SMTP secure |
| `SUPABASE_SMTP_REJECT_UNAUTHORIZED` | No | — | Alias Supabase para TLS |
| `MAIL_FROM` | No | Template default | Remitente de emails |
| `MAIL_REPLY_TO` | No | — | Reply-to de emails |
| `MAIL_RETURN_PATH` | No | — | Return path de emails |
| `POSTMARK_API_KEY` | No | — | API key de Postmark (si EMAIL_PROVIDER=postmark) |
| `SENDGRID_API_KEY` | No | — | API key de SendGrid (si EMAIL_PROVIDER=sendgrid) |
| `ADMIN_NOTIFICATION_EMAIL` | No | `'admin@novavision.lat'` | Email para notificaciones admin |
| `SUPER_ADMIN_EMAIL` | No | — | Email del super admin |

### Branding y Plataforma

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `PLATFORM_DOMAIN` | No | `'novavision.lat'` | Dominio principal de la plataforma |
| `NOVAVISION_EMAIL_BRAND_NAME` | No | `'NovaVision'` | Nombre de marca en emails |
| `NOVAVISION_EMAIL_LOGO_URL` | No | URL por defecto | Logo SVG en emails |
| `NOVAVISION_EMAIL_LOGO_PNG` | No | URL por defecto | Logo PNG en emails |
| `NOVAVISION_CONTACT_EMAIL` | No | `'novavision.contact@gmail.com'` | Email de contacto |
| `SERVICE_FEE_PICTURE_URL` | No | — | URL de imagen para item de service fee en MP |

### Outreach (WhatsApp / Instagram / n8n)

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `WHATSAPP_PHONE_NUMBER_ID` | No | — | Phone number ID de WhatsApp Business |
| `WHATSAPP_TOKEN` | No | — | Token de acceso de WhatsApp |
| `WHATSAPP_API_VERSION` | No | `'v22.0'` | Version de la API de WhatsApp |
| `WHATSAPP_VERIFY_TOKEN` | No | — | Token de verificacion de webhooks WhatsApp |
| `WHATSAPP_APP_SECRET` | No | — | App secret de WhatsApp (validacion HMAC) |
| `META_APP_SECRET` | No | — | App secret de Meta (Instagram) |
| `META_VERIFY_TOKEN` | No | — | Token de verificacion de webhooks Instagram |
| `META_PIXEL_ID` | No | — | Pixel ID de Meta CAPI |
| `META_ACCESS_TOKEN` | No | — | Access token de Meta CAPI |
| `META_TEST_EVENT_CODE` | No | — | Codigo de evento de prueba Meta |
| `N8N_INTERNAL_SECRET` | No | — | Secret HMAC para llamadas internas n8n |
| `N8N_HMAC_WINDOW_MS` | No | `300000` | Ventana de tiempo para HMAC n8n (ms) |
| `N8N_INBOUND_WEBHOOK_URL` | No | — | URL de webhook n8n para mensajes entrantes WA |
| `N8N_IG_INBOUND_WEBHOOK_URL` | No | — | URL de webhook n8n para mensajes entrantes IG |
| `N8N_IG_STATUS_WEBHOOK_URL` | No | — | URL de webhook n8n para delivery status IG |
| `OUTREACH_SENDER_NAME` | No | — | Nombre del remitente en outreach |
| `OUTREACH_CTA_LINK` | No | — | Link CTA en mensajes de outreach |

### AI / SEO

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `OPENAI_API_KEY` | No | — | API key de OpenAI para generacion SEO |

### Feature Flags y Crons

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `OVERRIDE_RECONCILE_ENABLED` | No | `'true'` | Habilitar reconciliacion de design overrides |
| `CREDIT_EXPIRATION_NOTIFY_ENABLED` | No | `'true'` | Habilitar notificaciones de expiracion de creditos |
| `ENABLE_QUOTA_ENFORCEMENT` | No | `'false'` | Habilitar enforcement de quotas de planes |
| `EMAIL_JOBS_ENABLED` | No | `'true'` | Habilitar worker de email jobs |
| `EMAIL_JOBS_BATCH_SIZE` | No | `10` | Tamano de batch del worker de emails |
| `EMAIL_JOBS_CLIENT_LIMIT` | No | `10` | Limite de clientes por ciclo |
| `EMAIL_JOBS_BACKOFF_BASE` | No | `5` | Base de backoff en segundos |
| `EMAIL_JOBS_BACKOFF_MAX` | No | `1800` | Max backoff en segundos |
| `RECOVERY_ENABLED` | No | `'true'` | Habilitar servicio de recovery |
| `ADMIN_BASE_URL` | No | `'https://novavision.lat'` | URL base para links de recovery |

### Suscripciones

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `PRICE_CHECK_DAYS_BEFORE` | No | `3` | Dias antes de renovacion para check de precios |
| `PRICE_ADJUSTMENT_THRESHOLD_PCT` | No | `10` | Umbral de ajuste de precio (%) |
| `GRACE_PERIOD_DAYS` | No | `7` | Dias de gracia para suscripciones vencidas |

### Infraestructura

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `NODE_ENV` | No | `'development'` | Entorno de ejecucion |
| `PORT` | No | `3000` | Puerto del servidor |
| `VERBOSE_LOGS` | No | `'false'` | Logs detallados |
| `VERBOSE_AUTH_LOGS` | No | `'false'` | Logs detallados de auth |

---

## Web (Storefront — Vite + React)

Las variables se leen via `import.meta.env.VITE_*`.

### Supabase — Backend DB

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_SUPABASE_URL` | Si | — | URL del proyecto Supabase de backend |
| `VITE_SUPABASE_ANON_KEY` | Si | — | Anon key del proyecto Supabase de backend |

### API Backend

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_BACKEND_API_URL` | Si | — | URL del backend NestJS (produccion) |
| `VITE_BACKEND_URL` | No | — | Alias legacy de `VITE_BACKEND_API_URL` |
| `VITE_API_URL` | No | — | Alias alternativo de URL del backend |
| `VITE_API_URL_LOCAL` | No | `'http://localhost:3000'` | URL del backend en desarrollo local |

### Plataforma y Tenant

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_PLATFORM_DOMAIN` | No | `'novavision.lat'` | Dominio raiz de la plataforma (tenant resolution) |
| `VITE_CLIENT_ID` | No | — | Client ID fijo (solo para dev/debugging) |
| `VITE_DEV_SLUG` | No | — | Slug de tenant para desarrollo local (sin query param) |

### Auth

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_AUTH_HUB_URL` | No | — | URL del hub de autenticacion centralizado |
| `VITE_HUB_ORIGIN` | No | — | Origen permitido del hub (postMessage) |

### Preview

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_PREVIEW_MODE` | No | `'false'` | Habilitar modo preview (`'true'` / `'false'`) |
| `VITE_PREVIEW_TOKEN` | No | — | Token de seguridad para acceso a preview |

### Netlify

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `NEXT_PUBLIC_NETLIFY_DEFAULT_DOMAIN` | No | `'novavision-test.netlify.app'` | Dominio default de Netlify (componente admin) |

### Otros

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_SUPER_ADMIN_EMAIL` | No | — | Email del super admin (plan limits) |

---

## Admin (Dashboard — Vite + React + TypeScript)

Las variables se leen via `import.meta.env.VITE_*` o `window.__RUNTIME__`.

### Supabase — Admin DB

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_ADMIN_SUPABASE_URL` | Si | — | URL del proyecto Supabase de admin |
| `VITE_ADMIN_SUPABASE_ANON_KEY` | Si | — | Anon key del proyecto admin |
| `VITE_SUPABASE_URL` | No | — | Fallback si no hay `VITE_ADMIN_SUPABASE_URL` |
| `VITE_SUPABASE_KEY` | No | — | Fallback si no hay `VITE_ADMIN_SUPABASE_ANON_KEY` |

### Supabase — Backend DB (lectura cruzada)

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_BACKEND_SUPABASE_URL` | No | — | URL del Supabase de backend (para lectura cruzada) |
| `VITE_BACKEND_SUPABASE_KEY` | No | — | Key del Supabase de backend |

### API Backend

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_BACKEND_API_URL` | Si | `'http://localhost:3000'` | URL del backend NestJS |
| `VITE_BACKEND_URL` | No | — | Alias legacy |

### Plataforma

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_PLATFORM_DOMAIN` | No | `'novavision.lat'` | Dominio de la plataforma |
| `VITE_CLIENT_ID` | No | `'platform'` | Client ID del admin (multi-deployment) |
| `VITE_WEB_APP_URL` | No | `'http://localhost:5173'` | URL del storefront (previews, links) |

### Auth

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_ADMIN_MAGIC_ORIGIN` | No | — | Origen permitido para magic links de login |

### EmailJS

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_EMAILJS_SERVICE_ID` | No | — | ID de servicio EmailJS |
| `VITE_EMAILJS_TEMPLATE_ID` | No | — | ID de template EmailJS (general) |
| `VITE_EMAILJS_TEMPLATE_WELCOME_ID` | No | — | ID de template EmailJS (bienvenida) |
| `VITE_EMAILJS_PUBLIC_KEY` | No | — | Public key de EmailJS |

### Calendly

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_CALENDLY_PUBLIC_URL` | No | — | URL de Calendly publica (30 min) |
| `VITE_CALENDLY_30MIN_URL` | No | — | Alias de URL Calendly 30 min |
| `VITE_CALENDLY_CONTRACT_URL` | No | — | URL Calendly para firma de contrato |
| `VITE_CALENDLY_DEMO_URL` | No | — | URL Calendly para demo |
| `VITE_CALENDLY_BOTH_URL` | No | — | URL Calendly combinada |

### Build Metadata

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_COMMIT_HASH` | No | `'dev'` | Hash del commit actual |
| `VITE_BUILD_TIMESTAMP` | No | `new Date().toISOString()` | Timestamp del build |
| `VITE_APP_VERSION` | No | `'0.0.0-local'` | Version de la app |

### Media y Assets

| Variable | Requerida | Default | Descripcion |
|----------|-----------|---------|-------------|
| `VITE_LANDING_VIDEO_URL` | No | — | URL del video del landing |
| `VITE_LANDING_ASSETS_BUCKET` | No | `'landing-assets'` | Bucket de Supabase para assets del landing |

---

## Notas Importantes

1. **Dos proyectos Supabase distintos**: La API usa `SUPABASE_*` (backend) y `SUPABASE_ADMIN_*` (admin). Son cuentas y proyectos diferentes.
2. **Admin usa `VITE_ADMIN_SUPABASE_*`** para la DB de admin, y `VITE_BACKEND_SUPABASE_*` para lectura cruzada a backend.
3. **Web usa `VITE_SUPABASE_*`** apuntando a la backend DB (donde viven los datos de tiendas).
4. **`NETLIFY_API_TOKEN`** es critico para gestion de dominios custom — sin el, el flujo de custom domains no funciona.
5. **`PLATFORM_MP_ACCESS_TOKEN`** es el token de la cuenta MP de NovaVision como plataforma, distinto de los tokens de cada tenant.
6. **Runtime injection**: Admin soporta `window.__RUNTIME__` para inyeccion de variables en runtime (sin rebuild).

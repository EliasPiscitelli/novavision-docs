# Plan de Implementación Pre-Lanzamiento — NovaVision

**Autor:** agente-copilot  
**Fecha:** 2026-02-23  
**Última validación contra codebase:** 2026-02-23 (incluye cambios no commiteados)  
**Estado:** PLAN — No ejecutar sin aprobación del TL  
**Refs cruzadas:**
- PLANS_LIMITS_ECONOMICS.md
- subscription-hardening-plan.md
- LATAM_INTERNATIONALIZATION_PLAN.md
- onboarding_complete_guide.md
- implementations (option-sets, cupones, shipping, etc.)

---

## Estado actual (inventario real — validado contra codebase 2026-02-23)

> ⚠️ Cada ítem fue verificado contra el código fuente de los tres repos (API, Admin, Web)
> incluyendo ~86 archivos modificados no commiteados en API, ~12 en Admin, ~30 en Web.

### ✅ Implementado y funcionando

**Core / multi-tenant:**
- Multi-tenant completo (RLS, `client_id` en todas las tablas, aislamiento estricto por tenant)
- Storefront multi-tenant (resolución por dominio/slug en `TenantProvider.jsx`)
- Storage con RLS y convención de paths por tenant (`{clientId}/{categoria}/{uuid}_{filename}`)

**Onboarding:**
- Onboarding automático completo (`OnboardingService` — 3.687 líneas: creación de cliente, MP, notificaciones, validación de slug)
- Pasos flexibles/salteables: el usuario puede completar onboarding con datos personales + pago; la IA genera catálogo en un click; imágenes se cargan post-publicación
- Aceptación de TOS en onboarding wizard (`Step9Terms.tsx` + `Step11Terms.tsx`, versión 2.0, via `POST /onboarding/session/accept-terms`)
- Edge Function `admin-create-client` (idempotente, con replicación a Multicliente DB para plan basic)

**Pagos y suscripciones:**
- Mercado Pago integrado para tiendas (`mercadopago.controller.ts` — 1.560 líneas: quote, create-preference, webhooks idempotentes con firma, confirm-payment)
- Mercado Pago para suscripciones NV (`PlatformMercadoPagoService` — pagos de plan)
- MP OAuth para credentials de tenant (`mp-oauth/`)
- Sistema de suscripciones hardened (`subscriptions.service.ts` — 3.679 líneas: distributed locks, grace period, lifecycle events, trial_days, coupon handling)
- Configuración de pagos avanzada (`client_payment_settings`, `client_mp_fee_overrides`, `client_extra_costs`)

**Panel admin (tenant):**
- Productos, categorías, banners, FAQs, servicios, colores, logo, redes sociales, contacto
- Option sets / variantes de productos
- Cupones de tienda (para compradores, `store-coupons/`)
- Analytics dashboard (métricas de tienda: órdenes, revenue, tendencias)
- SEO Autopilot (`seo-ai/` + `seo-ai-billing/`)
- Reviews y QA de productos
- Shipping settings
- Support tickets + WhatsApp inbox (`wa-inbox/`)
- Gestión de suscripción (`SubscriptionManagement.jsx`)
- Billing Hub para usuarios (`BillingHub.jsx`)

**Sistema de cupones (plataforma NV):**
- Tabla `coupons` + `coupon_redemptions` en Admin DB (NO los campos `free_months`/`promo_code` de `clients`)
- `CouponsService` integrado en suscripciones: `validateCoupon({ code, planKey, accountId })`
- Soporta `discount_type`: `percentage` y `fixed_amount`
- Promos temporales con `promo_config.duration = 'months'`
- TTL de 30 min en redemptions pendientes

**Email:**
- Sistema de emails (`email_jobs` con worker cron cada 5s, batch processing, backoff exponencial, configurable, desactivable)
- Templates con `wrapInLayout()` modo store y plataforma

**Billing NV:**
- Billing completo: cost-rollup, gmv-commission, usage-consolidation, quota-enforcement, overage
- Feature catalog (`featureCatalog.ts` — 763 líneas, 3 planes, 13 categorías, status live/beta/planned)
- Plans controller con entitlements y usage tracking
- FX service para conversión USD/ARS

**Landing / marketing (novavision.lat = Admin SPA):**
- PricingSection con toggle mensual/anual, toggle ARS/USD con tasa de cambio en vivo, planes cargados desde API
- FAQ section (5+ items, acordeón animado con framer-motion)
- SEO completo en index.html (title, description, keywords, OG, Twitter Card)
- Widget de Calendly integrado
- `trackEvent.js` helper existe (invoca `window.gtag()` y `dataLayer.push()`) — pero sin script GA4 cargado (detalle en gaps)

**SEO en storefronts:**
- GA4 dinámico por tenant (`SEOHead` inyecta `gtag.js` con `seo.ga4_measurement_id`, solo growth/enterprise)
- GTM dinámico por tenant (`SEOHead` inyecta GTM con `seo.gtm_container_id`)
- Google Search Console verification por tenant
- JSON-LD (Organization + WebSite), OG, Twitter Card, favicon, canonical URL
- `ProductSEO.jsx` para meta tags de producto

**Legal en storefronts:**
- `LegalPage` completa (637 líneas): TOS + Política de Privacidad + Derecho de Arrepentimiento
- Cumple Ley 24.240, 25.326, Disp. 954/2025
- Componente `TermsConditions` para aceptación inline

**Crons/scheduled tasks:**
- email-jobs worker (cada 5s)
- QR cleanup, order expiration, invariant check, custom domain verifier, support SLA

### ❌ NO implementado (gaps validados)

1. **GA4 en landing NV (novavision.lat)** — `trackEvent.js` existe y llama a `window.gtag()` pero NO hay `<script>` que cargue `gtag.js` → dispara al vacío. No se miden visitas ni eventos de onboarding de NV como empresa.
2. **Meta Pixel en landing NV** — `index.html` tiene comments `<!-- Meta Pixel Code -->` pero el contenido fue reemplazado por el OAuth handler. NO hay `fbq()` funcional. El tracking de conversiones de Facebook no funciona.
3. **Meta Pixel en storefronts** — Los tenants no tienen Pixel de Facebook. Solo GA4+GTM están implementados per-tenant.
4. **CAPI (Conversions API)** — No hay server-side events de Meta en ningún backend.
5. **Consent banner / CMP** — No hay implementación de cookies banner en ningún repo. Texto en TermsConditions dice "no utiliza cookies para seguimiento" — contradice la realidad cuando GA4 está activo.
6. **TOS / Privacy de NV como empresa** — Los TOS existentes (LegalPage, Step9Terms) son para tiendas de clientes/compradores. NO hay TOS/Privacy de NovaVision SaaS publicados en novavision.lat para clientes NV.
7. **Nudges de recovery** — Búsqueda exhaustiva: 0 resultados para "recovery", "abandoned", "reminder", "nudge" en todo el backend. No hay flujos automáticos de recuperación de onboarding.
8. **Evento de tracking en pago de suscripción NV** — No hay hook para disparar `Subscribe/Purchase` cuando MP aprueba pago de suscripción NV.
9. **Demo screen recording** — No existe.
10. **UGC / creatividades** — No existen.
11. **Comparativa vs competencia** — No verificada en la landing actual.

### ⚠️ Parcial / requiere atención
- **Promos:** Los campos `free_months`, `discount_percent`, `promo_code` existen en tabla `clients` pero el sistema real de promos usa `coupons` + `coupon_redemptions`. Verificar si los campos legacy se usan en algún flujo residual.
- **Footer de landing:** Verificar si tiene links a TOS/Privacy (probablemente no, dado que los TOS de NV como empresa no existen aún).

---

## Fase 0 — Preparación y decisiones (Día 1-2)

**Objetivo:** Alinear decisiones de negocio que bloquean implementación técnica.

| # | Tarea | Responsable | Entregable |
|---|-------|-------------|------------|
| 0.1 | Definir promo de lanzamiento (tipo, duración, límite) | Founder + Agencia | Decisión documentada |
| 0.2 | Definir si hay trial o no | Founder + Agencia | Decisión documentada |
| 0.3 | Confirmar pricing Enterprise = USD 390/mes, USD 3.500/año | Founder | Actualizar `PLANS_LIMITS_ECONOMICS.md` |
| 0.4 | Definir landing vs registro directo como destino de ads | Founder + Agencia | Decisión documentada |
| 0.5 | Crear cuentas: GA4 property, Meta Business Manager, Meta Pixel ID | Founder | IDs listos para implementar |
| 0.6 | Verificar dominio `novavision.lat` en Meta Business Manager | Founder | Dominio verificado |

**Riesgo:** Sin las cuentas de GA4/Meta creadas, las fases 1-2 no pueden avanzar.

---

## Fase 1 — Tracking y Consent (Día 2-5) 🔴 BLOCKER

**Objetivo:** Instalar tracking mínimo viable para poder medir desde el día 1 de paid.

### 1.1 — GA4 en la landing `novavision.lat` (Admin SPA)

**Estado actual verificado:**
- ✅ `src/utils/trackEvent.js` YA existe en Admin — invoca `window.gtag()` y `window.dataLayer.push()`
- ❌ PERO no hay `<script>` que cargue `gtag.js` → los eventos disparan al vacío
- ✅ Storefronts YA inyectan GA4 dinámicamente per-tenant via `SEOHead` (solo growth/enterprise)
- ❌ Lo que falta: cargar el script de gtag.js en `index.html` del Admin **con el Measurement ID de NV**

**Alcance:** Solo Admin frontend (landing/onboarding de NV). El storefront ya tiene GA4 per-tenant implementado.

**Archivos a tocar (Admin — `novavision/`):**
- `index.html` — agregar snippet de carga de `gtag.js` (el helper ya existe)
- `.env` / `.env.example` — agregar `VITE_GA_MEASUREMENT_ID`
- Opcionalmente: agregar eventos custom en pasos del onboarding wizard via el `trackEvent.js` existente

**Implementación — agregar en `index.html` dentro de `<head>`:**

````html
<!-- Google Analytics 4 — NV landing/onboarding tracking -->
<script async src="https://www.googletagmanager.com/gtag/js?id=G-XXXXXXXXXX"></script>
<script>
  window.dataLayer = window.dataLayer || [];
  function gtag(){dataLayer.push(arguments);}
  gtag('js', new Date());
  gtag('config', 'G-XXXXXXXXXX', {
    send_page_view: true,
    cookie_flags: 'SameSite=None;Secure'
  });
</script>
<!-- End GA4 -->
````

> Nota: El `trackEvent.js` existente ya sabe llamar a `window.gtag()`. Una vez que el script se cargue, 
> los event calls que ya existan en el código empezarán a funcionar automáticamente.

**Eventos a disparar en el onboarding (via `trackEvent.js` existente):**

| Evento GA4 | Cuándo | Params |
|------------|--------|--------|
| `registration_complete` | Post signup exitoso | `method: 'email'` |
| `onboarding_step` | Cada paso completado | `step_name, step_number` |
| `plan_selected` | Usuario selecciona plan | `plan_name, plan_price` |
| `payment_initiated` | Llega al checkout de MP | `plan_name, amount` |
| `payment_approved` | Webhook confirma pago | `plan_name, amount, payment_id` |
| `onboarding_complete` | Solicita publicación | `plan_name, steps_completed` |

**Verificar:** Si los pasos del wizard ya llaman a `trackEvent()` — si no, agregar llamadas en cada paso.

---

### 1.2 — Meta Pixel + CAPI

**Estado actual verificado:**
- ❌ Admin `index.html` tiene comments `<!-- Meta Pixel Code -->` pero el contenido fue reemplazado por el OAuth handler. NO hay `fbq()` funcional.
- ❌ No hay Meta Pixel en storefronts (solo GA4+GTM per-tenant)
- ❌ No hay CAPI server-side

**Alcance:** Ambos (Frontend para pixel browser + Backend para CAPI server-side)

**Frontend — Pixel browser en Admin (`novavision/` — landing/onboarding de NV):**

Reemplazar el bloque engañoso `<!-- Meta Pixel Code -->` en `index.html` con el script real:

````html
<!-- ...existing code... -->
<head>
  <!-- ...existing code... -->
  <!-- Meta Pixel -->
  <script>
    !function(f,b,e,v,n,t,s)
    {if(f.fbq)return;n=f.fbq=function(){n.callMethod?
    n.callMethod.apply(n,arguments):n.queue.push(arguments)};
    if(!f._fbq)f._fbq=n;n.push=n;n.loaded=!0;n.version='2.0';
    n.queue=[];t=b.createElement(e);t.async=!0;
    t.src=v;s=b.getElementsByTagName(e)[0];
    s.parentNode.insertBefore(t,s)}(window, document,'script',
    'https://connect.facebook.net/en_US/fbevents.js');
    fbq('init', 'PIXEL_ID_AQUI');
    fbq('track', 'PageView');
  </script>
  <noscript><img height="1" width="1" style="display:none"
    src="https://www.facebook.com/tr?id=PIXEL_ID_AQUI&ev=PageView&noscript=1"
  /></noscript>
  <!-- End Meta Pixel -->
</head>
````

**Frontend helper para eventos:**

````typescript
declare global {
  interface Window {
    fbq: (...args: unknown[]) => void;
  }
}

export function trackMetaEvent(eventName: string, params?: Record<string, unknown>) {
  if (typeof window.fbq === 'function') {
    window.fbq('track', eventName, params);
  }
}

// Eventos estándar de Meta
export const MetaEvents = {
  LEAD: 'Lead',                         // Registro completado
  INITIATE_CHECKOUT: 'InitiateCheckout', // Llega al paso de pago
  SUBSCRIBE: 'Subscribe',               // Pago aprobado
  COMPLETE_REGISTRATION: 'CompleteRegistration', // Onboarding completo
} as const;
````

**Backend — CAPI server-side (`templatetwobe/`):**

Nuevo módulo analytics en el backend NestJS:

````typescript
import { Module } from '@nestjs/common';
import { AnalyticsService } from './analytics.service';

@Module({
  providers: [AnalyticsService],
  exports: [AnalyticsService],
})
export class AnalyticsModule {}
````

````typescript
import { Injectable, Logger } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import * as crypto from 'crypto';

interface CAPIEvent {
  eventName: string;
  eventTime: number;
  userData: {
    email?: string;
    phone?: string;
    clientIpAddress?: string;
    clientUserAgent?: string;
    fbc?: string;
    fbp?: string;
  };
  customData?: Record<string, unknown>;
  eventSourceUrl?: string;
  actionSource: 'website';
}

@Injectable()
export class AnalyticsService {
  private readonly logger = new Logger(AnalyticsService.name);
  private readonly pixelId: string;
  private readonly accessToken: string;
  private readonly apiVersion = 'v19.0';

  constructor(private configService: ConfigService) {
    this.pixelId = this.configService.get<string>('META_PIXEL_ID', '');
    this.accessToken = this.configService.get<string>('META_CAPI_ACCESS_TOKEN', '');
  }

  async sendEvent(event: CAPIEvent): Promise<void> {
    if (!this.pixelId || !this.accessToken) {
      this.logger.warn('Meta CAPI not configured — skipping event');
      return;
    }

    const url = `https://graph.facebook.com/${this.apiVersion}/${this.pixelId}/events`;

    // Hash PII según requerimientos de Meta
    const hashedUserData = {
      ...event.userData,
      em: event.userData.email ? this.sha256(event.userData.email.toLowerCase().trim()) : undefined,
      ph: event.userData.phone ? this.sha256(event.userData.phone.replace(/\D/g, '')) : undefined,
      client_ip_address: event.userData.clientIpAddress,
      client_user_agent: event.userData.clientUserAgent,
      fbc: event.userData.fbc,
      fbp: event.userData.fbp,
    };

    const payload = {
      data: [
        {
          event_name: event.eventName,
          event_time: event.eventTime,
          user_data: hashedUserData,
          custom_data: event.customData,
          event_source_url: event.eventSourceUrl,
          action_source: event.actionSource,
        },
      ],
      access_token: this.accessToken,
    };

    try {
      const response = await fetch(url, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      });

      if (!response.ok) {
        const errorBody = await response.text();
        this.logger.error(`CAPI error: ${response.status} — ${errorBody}`);
      } else {
        this.logger.log(`CAPI event sent: ${event.eventName}`);
      }
    } catch (error) {
      this.logger.error(`CAPI request failed: ${error}`);
    }
  }

  private sha256(value: string): string {
    return crypto.createHash('sha256').update(value).digest('hex');
  }
}
````

**Dónde disparar CAPI events (puntos de integración en el backend):**

| Evento | Archivo/Módulo | Punto exacto |
|--------|---------------|--------------|
| `Lead` | auth o onboarding | Después de crear usuario exitosamente |
| `InitiateCheckout` | Flujo de pago de suscripción (cuando se crea preferencia MP para suscripción NV) | Antes de devolver `init_point` |
| `Subscribe` | Webhook de pago de suscripción NV (cuando `payments.status = approved` en Admin DB) | Después de confirmar pago |

**Env vars nuevas (backend):**
```env
META_PIXEL_ID=
META_CAPI_ACCESS_TOKEN=
GA_MEASUREMENT_ID=
```

---

### 1.3 — Consent Banner / CMP

**Alcance:** Frontend (landing + storefront)

Implementar un consent banner mínimo y funcional. No necesita ser un CMP enterprise — con un banner básico que bloquee cookies de tracking hasta aceptación es suficiente para cumplir Ley 25.326 y no ser penalizado por Meta.

**Nuevo componente:**

````tsx
import { useState, useEffect } from 'react';

const CONSENT_KEY = 'nv_cookie_consent';

interface CookieConsentProps {
  onAccept: () => void;
  onReject: () => void;
}

export function CookieConsent({ onAccept, onReject }: CookieConsentProps) {
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const stored = localStorage.getItem(CONSENT_KEY);
    if (!stored) {
      setVisible(true);
    } else if (stored === 'accepted') {
      onAccept();
    }
  }, [onAccept]);

  const handleAccept = () => {
    localStorage.setItem(CONSENT_KEY, 'accepted');
    setVisible(false);
    onAccept();
  };

  const handleReject = () => {
    localStorage.setItem(CONSENT_KEY, 'rejected');
    setVisible(false);
    onReject();
  };

  if (!visible) return null;

  return (
    <div style={{
      position: 'fixed', bottom: 0, left: 0, right: 0,
      background: '#1a1a2e', color: '#fff', padding: '16px 24px',
      display: 'flex', justifyContent: 'space-between', alignItems: 'center',
      zIndex: 9999, fontSize: '14px', boxShadow: '0 -2px 10px rgba(0,0,0,0.3)'
    }}>
      <p style={{ margin: 0, flex: 1, marginRight: '16px' }}>
        Usamos cookies para mejorar tu experiencia y medir el rendimiento del sitio.
        Podés aceptar o rechazar las cookies opcionales.{' '}
        <a href="/privacidad" style={{ color: '#7dd3fc', textDecoration: 'underline' }}>
          Más info
        </a>
      </p>
      <div style={{ display: 'flex', gap: '8px' }}>
        <button onClick={handleReject} style={{
          background: 'transparent', border: '1px solid #fff', color: '#fff',
          padding: '8px 16px', borderRadius: '4px', cursor: 'pointer'
        }}>
          Rechazar
        </button>
        <button onClick={handleAccept} style={{
          background: '#7dd3fc', border: 'none', color: '#1a1a2e',
          padding: '8px 16px', borderRadius: '4px', cursor: 'pointer', fontWeight: 'bold'
        }}>
          Aceptar
        </button>
      </div>
    </div>
  );
}
````

**Lógica de integración:** GA4 y Meta Pixel se inicializan SOLO si `localStorage.getItem('nv_cookie_consent') === 'accepted'`. Esto se controla cargando los scripts dinámicamente post-consent en lugar de en index.html estático.

**Archivo controlador:**

````typescript
import { GA_MEASUREMENT_ID } from './analytics';

export function initTracking() {
  const consent = localStorage.getItem('nv_cookie_consent');
  if (consent !== 'accepted') return;

  // GA4
  if (GA_MEASUREMENT_ID && !document.getElementById('ga4-script')) {
    const script = document.createElement('script');
    script.id = 'ga4-script';
    script.async = true;
    script.src = `https://www.googletagmanager.com/gtag/js?id=${GA_MEASUREMENT_ID}`;
    document.head.appendChild(script);

    window.dataLayer = window.dataLayer || [];
    window.gtag = function () {
      window.dataLayer.push(arguments);
    };
    window.gtag('js', new Date());
    window.gtag('config', GA_MEASUREMENT_ID);
  }

  // Meta Pixel
  const pixelId = import.meta.env.VITE_META_PIXEL_ID;
  if (pixelId && typeof window.fbq !== 'function') {
    /* eslint-disable */
    (function (f: any, b: any, e: any, v: any) {
      const n: any = (f.fbq = function () {
        n.callMethod ? n.callMethod.apply(n, arguments) : n.queue.push(arguments);
      });
      if (!f._fbq) f._fbq = n;
      n.push = n;
      n.loaded = true;
      n.version = '2.0';
      n.queue = [];
      const t = b.createElement(e);
      t.async = true;
      t.src = v;
      const s = b.getElementsByTagName(e)[0];
      s.parentNode.insertBefore(t, s);
    })(window, document, 'script', 'https://connect.facebook.net/en_US/fbevents.js');
    /* eslint-enable */
    window.fbq('init', pixelId);
    window.fbq('track', 'PageView');
  }
}
````

**Env vars nuevas (frontend):**
```env
VITE_GA_MEASUREMENT_ID=G-XXXXXXXXXX
VITE_META_PIXEL_ID=XXXXXXXXXX
```

---

**Entregable Fase 1:** Tracking completo (GA4 + Pixel + CAPI + Consent) listo para medir desde día 1.

**Validación:**
- [ ] GA4 real-time muestra PageView al abrir landing
- [ ] Meta Events Manager muestra PageView
- [ ] CAPI test event llega (usar Meta Events Manager > Test Events)
- [ ] Consent banner aparece en primera visita / no aparece si ya aceptó
- [ ] Sin consent = no se cargan scripts de tracking

---

## Fase 2 — TOS de NV como SaaS y Compliance (Día 3-5) 🟡 BLOCKER

**Objetivo:** Publicar TOS + Privacy Policy de NovaVision **como empresa SaaS** antes del primer peso en ads.

**Estado actual verificado:**
- ✅ `LegalPage` en storefront (637 líneas): TOS + Privacy + Arrepentimiento para tiendas de clientes → aplica a **compradores de tiendas**, NO a clientes NV
- ✅ `Step9Terms.tsx` + `Step11Terms.tsx` en onboarding: aceptación de TOS versión 2.0 durante wizard
- ❌ Lo que falta: página pública en novavision.lat con TOS y Privacy de NV como proveedor SaaS (dirigido a pymes/emprendedores que contratan NV)

### 2.1 — Textos legales de NV como SaaS

**Fuente:** `PLANS_LIMITS_ECONOMICS.md §12` tiene textos draft. Adaptar y publicar.

**Archivos a crear (en Admin SPA — novavision.lat):**

| URL | Archivo | Contenido |
|-----|---------|-----------|
| `novavision.lat/terminos` | Nueva ruta/página | Términos y Condiciones de Servicio SaaS de NV |
| `novavision.lat/privacidad` | Nueva ruta/página | Política de Privacidad de NV como procesador de datos |
| `novavision.lat/arrepentimiento` | Nueva ruta/página | Botón de arrepentimiento (Ley 24.240 AR) |

> Nota: Estos son DIFERENTES de los TOS que ya existen en `LegalPage` del storefront. 
> Los de `LegalPage` aplican a compradores de tiendas. Los nuevos aplican a client NV que contratan el servicio SaaS.

**Contenido mínimo TOS:**
- Descripción del servicio
- Planes y pricing (Starter, Growth, Enterprise)
- 0% comisión por venta
- Responsabilidad del contenido = del cliente
- Rubros prohibidos (lista de la sección 10)
- Cancelación: sin permanencia, inmediata, sin reembolso del período pagado
- Revisión manual antes de publicar
- Limitación de responsabilidad
- Jurisdicción: Argentina

**Contenido mínimo Privacy Policy:**
- Qué datos se recopilan (email, nombre, teléfono, datos de pago via MP)
- Cookies y tracking (GA4, Meta Pixel) — referencia al consent banner
- Ley 25.326 de Protección de Datos Personales
- Derechos ARCO (Acceso, Rectificación, Cancelación, Oposición)
- Contacto para ejercer derechos

**Implementación:** Páginas estáticas dentro de la landing de NovaVision. Se pueden hacer como componentes React simples con texto legal.

### 2.2 — Checkbox de aceptación en onboarding

**Estado actual verificado:**
- ✅ YA EXISTE — `Step9Terms.tsx` y `Step11Terms.tsx` implementan aceptación de TOS versión 2.0 en el wizard
- ✅ Persiste via `POST /onboarding/session/accept-terms` con `X-Builder-Token`
- ⚠️ Verificar: que el link en el checkbox apunte a las **nuevas URLs** de TOS/Privacy de NV (`/terminos`, `/privacidad`) una vez publicadas

**Acción:** Solo actualizar los links dentro de Step9Terms/Step11Terms para que apunten a las rutas públicas nuevas.

---

## Fase 3 — Emails de Recovery (Día 5-8) 🟠 IMPORTANTE

**Objetivo:** Recuperar usuarios que abandonan el onboarding antes de pagar.

**Estado actual verificado:**
- ✅ `email-jobs.worker.ts` (389 líneas) ejecuta cron cada 5s, batch processing, backoff exponencial
- ✅ `email-template.service.ts` con `wrapInLayout()` soporte store y plataforma
- ✅ Nodemailer configurado, SMTP diagnosticable con `npm run diagnose:smtp`
- ❌ **0 resultados** para "recovery", "abandoned", "reminder", "nudge" en todo el backend
- ❌ No hay detección de onboardings incompletos ni emails automáticos de recuperación

### 3.1 — Flujos automáticos de email

**Infraestructura existente aprovechable:** El worker `email_jobs` ya está funcionando con:
- `client_id`, `order_id`, `status`, `template`, `to_email`, `subject`, `body`
- Políticas RLS implementadas
- Insert permitido para service_role y admin

**Lo que falta:** Un servicio en el backend que:
1. Detecte onboardings incompletos (usuario registrado, sin pago aprobado después de X horas)
2. Cree registros en `email_jobs` con los emails de recovery
3. Un cron/scheduler que procese `email_jobs` pendientes y envíe

**Nuevo módulo en el backend:**

````typescript
import { Module } from '@nestjs/common';
import { RecoveryService } from './recovery.service';
import { ScheduleModule } from '@nestjs/schedule';

@Module({
  imports: [ScheduleModule.forRoot()],
  providers: [RecoveryService],
})
export class RecoveryModule {}
````

````typescript
import { Injectable, Logger } from '@nestjs/common';
import { Cron, CronExpression } from '@nestjs/schedule';

@Injectable()
export class RecoveryService {
  private readonly logger = new Logger(RecoveryService.name);

  // Cada hora, buscar usuarios registrados sin pago después de 24h, 48h, 72h
  @Cron(CronExpression.EVERY_HOUR)
  async checkAbandonedOnboardings() {
    this.logger.log('Checking abandoned onboardings...');

    // 1. Query Admin DB: clients con created_at > 24h, setup_paid = false, 
    //    que NO tengan ya un email_job de recovery
    // 2. Clasificar por tiempo:
    //    - 24h sin pagar → Email 1: "Tu tienda te está esperando"
    //    - 48h sin pagar → Email 2: "¿Necesitás ayuda? Te acompañamos"
    //    - 72h sin pagar → Email 3: "Última chance — escribinos por WhatsApp"
    // 3. Insertar en email_jobs con template correspondiente
    // 4. El procesador de email_jobs existente se encarga de enviar
  }
}
````

**Templates de email (3):**

| # | Trigger | Subject | Mensaje clave |
|---|---------|---------|---------------|
| 1 | 24h sin pagar | "Tu tienda te está esperando 🚀" | "Completaste el registro pero falta el último paso. Elegí tu plan y en minutos tenés tu tienda online." |
| 2 | 48h sin pagar | "¿Necesitás ayuda con tu tienda?" | "Vimos que empezaste a crear tu tienda. Si tenés alguna duda, respondé este mail o escribinos por WhatsApp." |
| 3 | 72h sin pagar | "Última oportunidad — te ayudamos a publicar" | "Tu tienda está casi lista. Si necesitás ayuda, respondé este mail. Si ya no te interesa, ignorá este mensaje." |

**Riesgo:** Requiere que el procesador de `email_jobs` esté funcionando (SMTP configurado). Verificar con `npm run diagnose:smtp` en el backend.

---

## Fase 4 — Landing Page Optimización (Día 5-10) 🟠 IMPORTANTE

**Objetivo:** Asegurar que la landing tenga los elementos mínimos para convertir tráfico paid.

### 4.1 — Elementos a verificar/agregar en `novavision.lat`

| Elemento | Estado verificado | Acción |
|----------|------------------|--------|
| Hero con claim principal | ✅ Existe | Verificar que diga "0% comisión" prominente |
| Pricing claro (3 planes) | ✅ `PricingSection` (529 líneas) con toggle USD/ARS, tasa de cambio en vivo, planes desde API | Verificar que Enterprise muestre USD 390/3.500 |
| FAQ (5-7 preguntas) | ✅ `Faqs/index.jsx` (147 líneas) con acordeón animado, importado en HomePage | Verificar que incluya las preguntas clave: comisión, precio, programar, cobrar, cancelar |
| Comparativa vs competencia | ❓ No verificado | Agregar sección: NV vs Tiendanube vs Shopify (comisión, setup, onboarding, soporte) |
| CTA único y claro | ❓ Verificar | "Creá tu tienda" → lleva a registro/wizard |
| Testimonios | ❌ No existen | Agregar placeholder / esperar beta users |
| WhatsApp visible | ✅ Existe (Calendly + probablemente chat) | OK |
| Footer con links legales | ❓ Verificar | Agregar links a /terminos, /privacidad (requiere Fase 2) |
| Claim de IA | ❓ Verificar | Destacar "Catálogo generado por IA en un click" |
| Responsive mobile | ❓ Verificar | Crítico — el tráfico Meta es 80%+ mobile |

> ✅ La landing ya tiene mucho más de lo que el plan original asumía. El foco debe estar en verificar contenido y agregar la comparativa.

### 4.2 — Meta tags y OG para sharing

**Estado actual verificado:**
- ✅ Admin `index.html` (241 líneas): SEO completo — title, description, keywords, OG (og:title, og:description, og:image), Twitter Card
- ✅ Storefront `SEOHead`: helmet con JSON-LD, OG, Twitter Card, canonical, favicon dinámico per-tenant
- ✅ `ProductSEO.jsx` para meta tags de producto

**Acción:** Solo verificar que el contenido actual sea el definitivo de lanzamiento (claims, pricing, imagen OG actualizada).

---

## Fase 5 — Evento de Suscripción NV (Día 8-12)

**Objetivo:** Cuando un usuario paga su suscripción a NovaVision (no una compra en una tienda), disparar eventos de tracking para medir CPA real.

### 5.1 — Hook en el flujo de pago de suscripción

**Contexto:** El pago de suscripción NV pasa por Mercado Pago. Cuando el webhook confirma `approved`:

1. Se actualiza `payments` en Admin DB
2. Se actualiza `clients.setup_paid`, `clients.plan_paid_until`, etc.

**En ese punto exacto, agregar:**

````typescript
// En el servicio que procesa pagos de suscripción NV (Admin DB)
// Después de confirmar pago aprobado:

// 1. CAPI event (server-side)
await this.analyticsService.sendEvent({
  eventName: 'Subscribe',
  eventTime: Math.floor(Date.now() / 1000),
  userData: {
    email: client.email_admin,
    phone: client.phone,
    clientIpAddress: request.ip,
    clientUserAgent: request.headers['user-agent'],
  },
  customData: {
    currency: 'USD',
    value: client.monthly_fee,
    predicted_ltv: client.monthly_fee * 6, // hipótesis Starter
    content_name: client.plan,
  },
  eventSourceUrl: 'https://novavision.lat',
  actionSource: 'website',
});

// 2. Log para auditoría
this.logger.log(`Subscription payment confirmed: client=${client.id}, plan=${client.plan}, amount=${client.monthly_fee}`);
````

### 5.2 — Frontend: redirect post-pago con evento

Cuando el usuario vuelve de MP con `status=approved` a la landing/onboarding de NV:

````typescript
// En el componente de resultado de pago de suscripción
useEffect(() => {
  const params = new URLSearchParams(window.location.search);
  if (params.get('status') === 'approved') {
    // GA4
    trackEvent('payment_approved', {
      plan: planName,
      value: planPrice,
      currency: 'USD',
    });
    // Meta Pixel
    trackMetaEvent('Subscribe', {
      value: planPrice,
      currency: 'USD',
      predicted_ltv: planPrice * 6,
    });
  }
}, []);
````

---

## Fase 6 — Creatividades y Assets (Día 5-12, paralelo) 🟠 IMPORTANTE

**Objetivo:** Tener el material mínimo para arrancar campañas.

| # | Asset | Quién | Cómo |
|---|-------|-------|------|
| 6.1 | Screen recording: IA generando catálogo en 1 click | Founder | Grabación de pantalla (OBS/QuickTime) del onboarding con IA, acelerado a 30-60seg |
| 6.2 | Screen recording: recorrida del admin dashboard | Founder | Tour rápido por productos, pedidos, banners, colores, cupones |
| 6.3 | UGC founder: "Por qué creé NovaVision" | Founder | Video corto cara a cámara, 30-60seg, tono cercano |
| 6.4 | UGC founder: "Mirá lo fácil que es" | Founder | Mostrando el celular con la tienda funcionando |
| 6.5 | Imagen comparativa: NV vs Tiendanube | Founder/Diseñador | Tabla visual: comisión, setup, soporte, precio |
| 6.6 | Imagen: "Sin comisión = más ganancia" | Founder/Diseñador | Cálculo visual: "$500K ventas → $0 comisión vs $10K en Tiendanube" |

**No requiere desarrollo.** Son assets de marketing que se producen en paralelo.

---

## Fase 7 — Audiencias y Setup Meta (Día 10-14)

**Objetivo:** Configurar Meta Ads Manager para lanzar campañas.

| # | Tarea | Quién |
|---|-------|-------|
| 7.1 | Verificar dominio en Meta Business Manager | Founder/Agencia |
| 7.2 | Configurar eventos prioritarios en Meta (Lead → Subscribe) | Agencia |
| 7.3 | Exportar base de emails/phones de `clients` (Admin DB) → hashear → Custom Audience | Equipo técnico + Agencia |
| 7.4 | Crear Lookalike audiences a partir de Custom Audience | Agencia |
| 7.5 | Crear estructura de campaña (CBO + 2-3 ad sets + 4-6 creatividades) | Agencia |
| 7.6 | Configurar eventos de conversión en campaña (empezar por Lead) | Agencia |

**Script para exportar audiencia seed:**

````sql
-- Ejecutar en Admin DB para obtener base de audiencias
SELECT 
  email_admin as email,
  phone,
  name
FROM clients 
WHERE email_admin IS NOT NULL
  AND is_active = true
ORDER BY created_at DESC;
````

---

## Fase 8 — Actualización de Docs y Pricing en DB (Día 1-3, paralelo)

**Objetivo:** Que la documentación y la base de datos reflejen el pricing correcto.

### 8.1 — Actualizar `PLANS_LIMITS_ECONOMICS.md`

````markdown
<!-- ...existing code... -->
<!-- Actualizar donde diga Enterprise USD 250 o USD 280: -->

| Plan | Mensual (USD) | Anual (USD) | Ahorro |
|------|--------------|-------------|--------|
| Starter | 20 | 200 | 2 meses |
| Growth | 60 | 600 | 2 meses |
| Enterprise | **390** | **3.500** | ~USD 1.180 |

<!-- ...existing code... -->
````

### 8.2 — Actualizar tabla plans en Admin DB (si existe)

````sql
-- Actualizar pricing Enterprise
UPDATE plans 
SET monthly_fee = 390, 
    annual_fee = 3500
WHERE plan_key = 'enterprise' OR plan_key = 'enterprise_annual';
````

### 8.3 — Crear doc de cambios

````markdown
# Cambio: Actualización pricing Enterprise

- **Autor:** agente-copilot
- **Fecha:** 2026-02-23
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos modificados
- PLANS_LIMITS_ECONOMICS.md — pricing Enterprise actualizado

## Resumen
Enterprise pasa de USD 250/mes (o USD 280) a **USD 390/mes**, **USD 3.500/año**.

## Por qué
Decisión del founder. El plan Enterprise incluye DB dedicada + desarrollos custom + SLA premium, justificando el precio mayor.

## Cómo probar
- Verificar que la landing muestre el precio correcto
- Verificar que el onboarding cobre el monto correcto al seleccionar Enterprise
````

---

## Resumen de fases y timeline

```
Día 1-2:   Fase 0 (Decisiones) + Fase 8 (Docs/DB)
Día 2-5:   Fase 1 (Tracking) 🔴 + Fase 2 (TOS) 🟡
Día 5-8:   Fase 3 (Recovery emails)
Día 5-10:  Fase 4 (Landing) + Fase 6 (Creatividades) ← paralelo
Día 8-12:  Fase 5 (Evento suscripción)
Día 10-14: Fase 7 (Setup Meta Ads)
─────────────────────────────────────────────────────
Día 14-15: GO/NO-GO → Lanzar pre-lanzamiento con paid
```

## Criterios de GO para lanzar paid

**Ya cumplidos (verificado 2026-02-23):**
- [x] Landing con pricing (PricingSection USD/ARS, 3 planes desde API) y FAQ (5+ items)
- [x] GA4 per-tenant en storefronts (`SEOHead` inyecta dinámicamente para growth/enterprise)
- [x] GTM per-tenant en storefronts
- [x] TOS aceptados en onboarding (Step9Terms + Step11Terms, v2.0)
- [x] Legal completo en storefronts (LegalPage: TOS + Privacy + Arrepentimiento)
- [x] SEO completo en landing (OG, Twitter Card, keywords)
- [x] Email worker funcionando (cron 5s, batch, backoff)
- [x] Sistema de cupones/promos para suscripciones ready

**Pendientes (bloqueantes):**
- [ ] Script GA4 cargado en landing NV (actualmente `trackEvent.js` dispara al vacío)
- [ ] Meta Pixel funcional en landing NV (`fbq()` script cargado)
- [ ] CAPI enviando eventos server-side
- [ ] Consent banner funcionando (crítico si se activan GA4 + Pixel)
- [ ] TOS + Privacy Policy **de NV como SaaS** publicados en novavision.lat
- [ ] Pricing Enterprise correcto en toda la plataforma (USD 390/3.500)

**Pendientes (importantes, no bloqueantes):**
- [ ] Emails de recovery activados (24h, 48h, 72h)
- [ ] Al menos 2-3 creatividades listas (screen recording + UGC)
- [ ] Comparativa vs competencia en landing
- [ ] Dominio verificado en Meta Business Manager
- [ ] Estructura de campaña configurada en Meta Ads Manager
- [ ] Meta Pixel per-tenant en storefronts (feature request para clientes)

## Riesgos principales

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| SMTP no configurado → emails de recovery no salen | Media | Alto | Correr `npm run diagnose:smtp` en Fase 3 |
| Meta rechaza dominio sin TOS publicado | Baja | Alto | Completar Fase 2 antes de Fase 7 |
| Budget USD 500/mes insuficiente para salir de learning phase | Media | Medio | Empezar optimizando por Lead (más volumen) |
| Onboarding tiene bugs post-pago | Media | Crítico | Hacer 5-10 test completos con pago sandbox antes de paid |
| Landing no convierte (bounce alto) | Media | Alto | Tener fallback: enviar directo a registro si landing no funciona |
| Consent banner ausente con GA4 activo = riesgo legal | Alta | Alto | Implementar consent ANTES de activar GA4/Pixel (Fase 1.3) |
| `trackEvent.js` ya tiene calls que disparan al vacío | Baja | Bajo | Se resuelve automáticamente al cargar script GA4 (Fase 1.1) |
| Refactor mayor en progreso (~86 archivos sin commitear en API) | Media | Alto | Validar que los cambios no rompan flujos de pago/suscripción antes de lanzar |

---

## Cambios no commiteados detectados (2026-02-23)

| Repo | Archivos | Impacto potencial |
|------|----------|-------------------|
| **API** | 86 archivos (30+ M, 10+ D) | Refactor mayor: eliminación de entities legacy (cart, categories, orders, products, users), eliminación de services redundantes (mercadopago viejo, payment-reconciliation, dolar-blue), modificaciones en billing, subscriptions, MPs, onboarding, auth |
| **Admin** | 12 archivos (6 M, 6 nuevos) | Nuevas vistas: CountryConfigs, FeeSchedules, FxRates, GmvCommissions, Quotas. Hook `useClientBilling`. Modificaciones en PlanEditor, PlansView, ClientDetails |
| **Web** | 30 archivos modificados | Modificaciones en SEOHead, BillingHub, CouponDashboard, PaymentsConfig, SubscriptionManagement, SupportTickets, LegalPage, cart hooks, TenantProvider, templates |

> ⚠️ Estos cambios no commiteados pueden afectar el comportamiento de features existentes.
> Verificar que el refactor de API no rompa suscripciones ni pagos antes de lanzar paid.

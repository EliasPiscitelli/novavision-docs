# NovaVision — Marketing OS v1.0
## Sistema Completamente Automatizado: Adquisición, Conversión e Infraestructura

**Estado:** Diseño completo pre-lanzamiento. Todo construible antes de activar.  
**Premisa:** Control total. Sin agencias. Sin freelancers. Mínimo tiempo diario del founder.  
**Notaciones:** `[AUTO]` = se ejecuta solo. `[NOTIF]` = te avisa y espera tu decisión. `[MANUAL]` = acción tuya.

---

## PARTE 1: SISTEMA DE INFRAESTRUCTURA LIMPIA
### "Que los curiosos no te cuesten"

El mayor riesgo de un SaaS en lanzamiento es acumular cuentas que consumen infra sin pagar.  
Este módulo resuelve eso antes de activar cualquier canal de adquisición.

---

### 1.1 — Política de Lifecycle de Cuentas (definir antes de lanzar)

```
TIER 0 — Trial (si lo activás)
├── Duración: 14 días desde registro
├── Límites duros: 30 órdenes, 1 tienda, sin custom domain
├── Al vencer: GRACE de 3 días → si no paga → SUSPENDED
└── A los 30 días sin pago desde vencimiento: SCHEDULED_FOR_DELETION

TIER 1 — Starter pagó al menos 1 mes
├── Si falla el pago: BILLING_HOLD → 14 días → SUSPENDED
├── Si sigue suspendido 30 días: SCHEDULED_FOR_DELETION
└── Datos retenidos 60 días tras borrado (tabla client_tombstones)

TIER 2 — Growth / Enterprise
├── Grace period extendido: 21 días
└── Notificación proactiva antes de suspender (no surprise)

ZOMBIE — Cuenta sin actividad 90 días (sin órdenes, sin login, plan activo)
└── [NOTIF] al founder → opción A: contactar, opción B: suspender, opción C: ignorar
```

---

### 1.2 — Cleanup Cron (NestJS, ya existe infra)

**Archivo a crear:** `apps/api/src/lifecycle/cleanup.cron.ts`

```typescript
// Ejecutar: diariamente 3:00 AM UTC

@Cron('0 3 * * *')
async runCleanupCycle() {

  // PASO 1: Accounts en trial vencido → SUSPENDED
  await this.suspendExpiredTrials();
  // Query: nv_accounts WHERE plan = 'trial' 
  //        AND trial_ends_at < NOW() - INTERVAL '3 days'
  //        AND subscription_status != 'suspended'

  // PASO 2: Cuentas suspendidas > 30 días → SCHEDULED_FOR_DELETION
  await this.scheduleExpiredSuspensions();
  // Query: nv_accounts WHERE subscription_status = 'suspended'
  //        AND suspended_at < NOW() - INTERVAL '30 days'

  // PASO 3: Ejecutar borrado de cuentas scheduled hace > 7 días
  await this.executeScheduledDeletions();
  // Borrar en orden: Backend DB primero (RLS), luego Admin DB
  // Preservar en client_tombstones: account_id, slug, email, plan, deleted_at

  // PASO 4: Detectar zombies (activas pero sin uso)
  await this.detectAndNotifyZombies();
  // Query: clients JOIN usage_daily WHERE last_activity < NOW() - INTERVAL '90 days'
  // → INSERT INTO system_events (type: 'zombie_detected')
  // → Fire webhook a n8n para notificación al founder

  // PASO 5: Liberar slugs de cuentas borradas
  await this.releaseDeletedSlugs();
  // DELETE FROM slug_reservations WHERE account_id IN (deleted_accounts)

  // PASO 6: Log del ciclo completo
  await this.logCleanupResult(results);
}
```

---

### 1.3 — Borrado ordenado por Foreign Keys

**Orden correcto de borrado (sin violar constraints):**

```sql
-- FUNCIÓN: delete_account_cascade(p_account_id UUID)
-- Ejecutar para cada cuenta en scheduled_for_deletion

BEGIN;

-- 1. Backend DB: borrar todo lo del tenant
DELETE FROM cart_items         WHERE client_id = :client_id;
DELETE FROM favorites          WHERE client_id = :client_id;
DELETE FROM order_items        WHERE order_id IN (SELECT id FROM orders WHERE client_id = :client_id);
DELETE FROM orders             WHERE client_id = :client_id;
DELETE FROM payments           WHERE client_id = :client_id;
DELETE FROM products           WHERE client_id = :client_id;
DELETE FROM categories         WHERE client_id = :client_id;
DELETE FROM services           WHERE client_id = :client_id;
DELETE FROM banners            WHERE client_id = :client_id;
DELETE FROM logos              WHERE client_id = :client_id;
DELETE FROM faqs               WHERE client_id = :client_id;
DELETE FROM social_links       WHERE client_id = :client_id;
DELETE FROM client_home_settings WHERE client_id = :client_id;
DELETE FROM client_assets      WHERE client_id = :client_id;
DELETE FROM client_payment_settings WHERE client_id = :client_id;
DELETE FROM client_secrets     WHERE client_id = :client_id;
DELETE FROM client_usage       WHERE client_id = :client_id;
DELETE FROM seo_settings       WHERE client_id = :client_id;
DELETE FROM users              WHERE client_id = :client_id; -- tenant users
DELETE FROM clients            WHERE id = :client_id;

-- 2. Admin DB: borrar cuenta y dependencias (muchas van por CASCADE)
DELETE FROM usage_ledger               WHERE client_id = :client_id;
DELETE FROM usage_daily                WHERE client_id = :client_id;
DELETE FROM usage_hourly               WHERE client_id = :client_id;
DELETE FROM usage_event                WHERE client_id = :client_id;
DELETE FROM client_themes              WHERE client_id = :client_id;
DELETE FROM custom_palettes            WHERE client_id = :client_id;
-- Las siguientes van por CASCADE desde nv_accounts:
-- subscriptions, lifecycle_events, provisioning_jobs, coupon_redemptions,
-- nv_onboarding, managed_domains, nv_account_settings, nv_billing_events
DELETE FROM nv_accounts WHERE id = :account_id;

-- 3. Supabase Auth: DELETE FROM auth.users WHERE id = :auth_user_id
-- (via Supabase Admin API, no SQL directo)

-- 4. Preservar registro
INSERT INTO client_tombstones (client_id, account_id, slug, email, plan_key, deleted_at, reason)
VALUES (:client_id, :account_id, :slug, :email, :plan_key, NOW(), :reason);

COMMIT;
```

---

### 1.4 — Política de promoción de lanzamiento (sin curiosos)

**Problema a resolver:** Una promo mal diseñada llena el sistema de gente que nunca paga.

**Promoción recomendada: "Fundadores"**

```
PROMO: FUNDADORES2026
- Descuento: 40% en el primer mes de Growth
  (USD 60 → USD 36, no USD 0)
- Requiere: tarjeta registrada desde el inicio (no free trial sin pago)
- Duración: 30 días desde registro, luego precio full
- Límite: 50 cupones (escasez real, no artificial)
- Beneficio extra: badge "Tienda Fundadora" en la plataforma (lifetime)
- Restricción técnica: 1 por cuenta, validado por email de registro

¿Por qué funciona?
→ El pago inicial (aunque sea reducido) filtra curiosos
→ USD 36 vs USD 0 = ratio de conversión real a pago full 5x mayor
→ Badge lifetime genera orgullo de pertenencia y reduce churn
→ Límite de 50 crea urgencia real

ALTERNATIVA para generar leads en top funnel (sin riesgo de infra):
- Lead magnet: "Calculadora de cuánto perdés por vender sin tienda propia"
  (captura email/WA sin crear cuenta en plataforma)
- Solo quien ingresa a la plataforma activa slot de infra
```

**SQL para crear el cupón:**
```sql
INSERT INTO coupons (
  code, discount_type, discount_value, max_uses, 
  valid_until, plan_restriction, description, is_active
) VALUES (
  'FUNDADORES2026',
  'percentage',
  40,
  50,
  '2026-07-31',
  'growth',
  'Cupón fundadores: 40% off Growth mes 1. Solo para las primeras 50 tiendas.',
  true
);
```

---

## PARTE 2: SISTEMA DE ADVERTISING OMNICANAL
### "El sistema compra medios, vos mirás números"

---

### 2.1 — Arquitectura de canales

```
┌─────────────────────────────────────────────────────────────────────┐
│                   NOVAVISION AD ENGINE                              │
├───────────┬───────────┬──────────────┬──────────────────────────────┤
│  META ADS │  GOOGLE   │   TIKTOK     │    TRACKING UNIFICADO        │
│ (FB + IG) │   ADS     │    ADS       │                              │
├───────────┼───────────┼──────────────┼──────────────────────────────┤
│ Awareness │ Search    │ Awareness    │ GA4 + BigQuery                │
│ Retarget  │ Display   │ Retarget     │ Pixel + CAPI (Meta)          │
│ LAL auds  │ YouTube   │ LAL auds     │ TikTok Pixel                 │
│           │ PMAX      │              │ Google Tag Manager           │
└───────────┴───────────┴──────────────┴──────────────────────────────┘
         ↓ todos los eventos fluyen hacia
┌─────────────────────────────────────────────────────────────────────┐
│              FUNNEL EVENTS (server-side via API NestJS)             │
│   page_view → registration → onboarding_start →                    │
│   onboarding_complete → plan_selected → purchase                   │
└─────────────────────────────────────────────────────────────────────┘
```

---

### 2.2 — Tracking unificado (implementar primero, antes de activar pauta)

**Archivo:** `apps/api/src/tracking/events.service.ts`

```typescript
// Server-side event firing — se llama desde los servicios existentes
// Beneficio: no depende del browser, funciona con bloqueadores de ads

export class TrackingEventsService {

  async fireEvent(event: TrackingEvent) {
    const payload = {
      event_name: event.name,
      event_time: Math.floor(Date.now() / 1000),
      user_data: {
        em: await this.hash(event.email),      // hashed
        ph: await this.hash(event.phone),      // hashed
        client_ip_address: event.ip,
        client_user_agent: event.userAgent,
        external_id: event.accountId,
      },
      custom_data: event.customData,
      event_source_url: event.sourceUrl,
      action_source: 'website',
    };

    // Disparar en paralelo a todos los canales activos
    await Promise.allSettled([
      this.fireMetaCAPI(payload),
      this.fireTikTokEvents(payload),
      this.logToGA4MeasurementProtocol(payload),
      this.logToSupabase(event), // audit interno siempre
    ]);
  }

  // Hook points en servicios existentes:
  // AccountsService.create()         → fire('CompleteRegistration')
  // OnboardingService.complete()     → fire('Lead')
  // SubscriptionsService.activate()  → fire('Purchase', {value, currency})
  // PaymentService.success()         → fire('Purchase', {value, currency})
}
```

**Variables de entorno a agregar:**
```
META_PIXEL_ID=
META_CAPI_ACCESS_TOKEN=
TIKTOK_PIXEL_ID=
TIKTOK_ACCESS_TOKEN=
GA4_MEASUREMENT_ID=
GA4_API_SECRET=
GTM_SERVER_CONTAINER_URL=   # opcional, para server-side GTM
```

---

### 2.3 — Estructura de campañas por plataforma

#### META ADS (Facebook + Instagram)

```
CUENTA PUBLICITARIA: NovaVision (a nombre de la empresa, nunca personal)

CAMPAÑA 1: TOF — Awareness/Registro (Starter Budget: USD 300/mes)
│
├── Ad Set A: Pymes que venden por Instagram (AR)
│   Audiencia: intereses [tienda online, emprendimiento, MercadoPago, MercadoLibre vendors]
│   + comportamientos [small business owners, online shoppers Argentina]
│   Optimización: CompleteRegistration (una vez con datos suficientes, iniciar con Link Clicks)
│   │
│   ├── [VIDEO 1] Hook: "0% de comisión — todos los meses"        → usar video ya grabado
│   ├── [VIDEO 2] Hook: "Armé mi tienda en 5 minutos"             → screen recording del onboarding
│   └── [CARRUSEL] "5 razones para dejar de vender por WhatsApp"  → [NOTIF] necesito 5 imágenes
│
├── Ad Set B: Emprendedores con negocio físico (AR)
│   Audiencia: LAL 2% de usuarios que completaron registro (una vez que tengas 100+)
│   Inicialmente: intereses [comercio, productos artesanales, moda AR, gastronomía]
│   │
│   ├── [VIDEO 3] Hook: "Tu negocio físico también puede vender online"
│   └── [ESTÁTICO] "Andreani + OCA integrados desde el primer día"  → [NOTIF] necesito diseño

CAMPAÑA 2: RETARGETING (Budget: USD 100/mes)
│
├── Ad Set A: Visitaron landing sin registrarse (últimos 7 días)
│   └── [VIDEO/ESTÁTICO] Recordatorio con social proof (primeras tiendas activas)
│
└── Ad Set B: Registraron pero no pagaron (últimos 14 días)
    └── [VIDEO] Demo del admin panel + cupón FUNDADORES2026

CAMPAÑA 3: CONVERSIÓN HOT (Budget: USD 100/mes — activar en mes 2)
│
└── Ad Set A: LAL de pagadores (una vez que tengas 50+ conversiones)
    └── Todo el creative arsenal optimizado para Purchase
```

#### GOOGLE ADS

```
CAMPAÑA 1: SEARCH — Intención alta (Budget: USD 150/mes)
│
├── Grupo 1: Branded + navegación
│   Keywords: "novavision tienda", "novavision.lat", "novavision argentina"
│   Anuncio: nombre + diferencial + CTA directo
│
├── Grupo 2: Competidores directos
│   Keywords: [tienda online argentina], [crear tienda online], [alternativa tiendanube]
│   Anuncio: "0% comisión por venta — probá gratis 14 días"
│   [NOTIF] Definir si ir agresivo contra marcas competidoras o solo genérico
│
└── Grupo 3: Problema/solución
    Keywords: [vender por instagram sin comision], [tienda propia argentina pyme],
              [mercadopago tienda online]
    Anuncio: "Tienda online con Mercado Pago. Sin comisiones. Lista en minutos."

CAMPAÑA 2: PERFORMANCE MAX (Budget: USD 100/mes — activar mes 2)
│
Activos requeridos:
  - 15 headlines (generados por IA desde los diferenciales)
  - 4 descriptions
  - 5 imágenes landscape (1.91:1)
  - 5 imágenes cuadradas (1:1)
  - 1-5 videos (YouTube o subir directo)  → usar videos ya grabados
  [NOTIF] Necesito que apruebes los assets antes de cargar

CAMPAÑA 3: YOUTUBE (Budget: USD 50/mes — activar cuando tengas 3+ videos)
│
└── In-stream skippable: demo del producto 60-90s
    Audiencias: in-market "Business software", "Online retail", "Entrepreneurs AR"
```

#### TIKTOK ADS

```
CUENTA: Business Center → Ad Account NovaVision

CAMPAÑA 1: AWARENESS (Budget: USD 100/mes)
│
├── Ad Group A: Emprendedores 25-45 AR
│   Intereses: small business, e-commerce, entrepreneurship, technology
│   │
│   ├── [SPARK AD] Contenido orgánico boosteado (si tenés perfil)
│   │   → [NOTIF] ¿Tenés perfil de TikTok activo para NovaVision? Si no, usar non-spark.
│   │
│   └── [IN-FEED VIDEO] Demo rápido 15-30s con hook en primer segundo
│       → usar videos ya grabados, cortar al formato vertical si es necesario
│
└── Ad Group B: Retargeting pixel (activar después de instalar pixel)
    └── Visitaron landing o page de pricing

NOTA SOBRE TIKTOK:
El ROI de TikTok en B2B Argentina aún no está probado para SaaS con tu ticket.
Inversión inicial conservadora (USD 100/mes) para testear. Si en 45 días el CPL
supera 3x el de Meta, pausar y reasignar el budget.
```

---

### 2.4 — UTM Naming Convention (implementar antes de activar cualquier pauta)

```
Estructura: utm_source / utm_medium / utm_campaign / utm_content / utm_term

EJEMPLOS:
Meta TOF video:     ?utm_source=meta&utm_medium=paid_social&utm_campaign=tof_arg&utm_content=video_comision_0pct&utm_term=pymes_instagram
Google Search:      ?utm_source=google&utm_medium=paid_search&utm_campaign=search_brand&utm_content=headline_sin_comision
TikTok:             ?utm_source=tiktok&utm_medium=paid_social&utm_campaign=awareness_arg&utm_content=demo_onboarding_15s
Outreach WA:        ?utm_source=whatsapp&utm_medium=outreach&utm_campaign=seed_v2&utm_content=template_novavision_seed
Email outreach:     ?utm_source=email&utm_medium=outreach&utm_campaign=seed_v2&utm_content=html_email_v1

AUTOMATIZACIÓN: el workflow n8n de seed debe incluir estos UTMs en el link 
de registro que envía por WhatsApp/email.
```

---

## PARTE 3: SISTEMA DE NOTIFICACIONES AL FOUNDER
### "El sistema hace, vos decidís"

---

### 3.1 — Centro de Notificaciones (n8n workflow: `founder_notifications`)

Todas las notificaciones van por **WhatsApp al número del founder** (no email, no Slack, no apps extra).

**Formato estándar de notificación:**
```
🔔 [TIPO] NOVAVISION
[Título corto]

[Datos relevantes]

👉 Acción requerida: [descripción]
Respondé: SI / NO / REVISAR
O accedé a: admin.novavision.lat/[path]
```

---

### 3.2 — Catálogo completo de notificaciones

#### GRUPO A: Decisiones creativas (no puede automatizarse)

```
[CREATIVO-001] — Necesito un nuevo video
Trigger: Anuncio activo > 14 días con frecuencia > 2.5 (fatiga)
Mensaje: "El anuncio [nombre] está mostrando fatiga (frecuencia 2.8).
          Ángulo original: [hook]. Necesito una nueva variación.
          Sugerencia IA: [propuesta de nuevo hook basada en mejor performer].
          ¿Lo grabamos esta semana?"
Acción: Vos grabás el video, el sistema lo sube como nuevo anuncio.

[CREATIVO-002] — Nuevo ángulo para testear
Trigger: Cron semanal + ningún anuncio nuevo en 10 días
Mensaje: "Hace 10 días sin creatividades nuevas. La IA sugiere testear:
          Ángulo: [propuesta basada en objeciones del AI Closer]
          Formato: [video/carrusel/estático]
          ¿Lo producimos?"

[CREATIVO-003] — Actualizar copy del anuncio ganador
Trigger: Anuncio con mejor CPA activo > 30 días
Mensaje: "El anuncio [nombre] lleva 30 días activo con CPA de USD X.
          Puede estar saturando. ¿Lo renovamos con el mismo ángulo?"
```

#### GRUPO B: Decisiones estratégicas

```
[ESTRATEGIA-001] — Lead caliente requiere atención
Trigger: AI Closer marca lead con score >= 85 O engagement >= 5 mensajes
Mensaje: "[Nombre] está muy interesado. Llevamos [N] intercambios.
          Última pregunta: '[texto]. Este lead tiene alta intención.
          ¿Lo contactás vos directamente? SI = te mando el número."

[ESTRATEGIA-002] — Presupuesto de pauta bajo
Trigger: Gasto mensual supera 85% del presupuesto definido
Mensaje: "Gastaste USD [X] de USD [Y] en pauta este mes (día [Z] del mes).
          Proyección: agotás presupuesto el día [fecha].
          Opciones: A) Aumentar budget (+USD 200), B) Pausar campaña menos eficiente,
          C) Seguir igual y pausar al llegar al límite."

[ESTRATEGIA-003] — Anuncio escalando muy rápido
Trigger: CPA < USD 15 por 3 días consecutivos, gasto > USD 20
Mensaje: "Anuncio [nombre] tiene CPA USD [X]. Señal muy positiva.
          ¿Escalo el presupuesto 30%? El sistema lo hace solo si confirmás."

[ESTRATEGIA-004] — Nuevo canal a activar
Trigger: Meta saturada (frecuencia > 3 promedio de cuenta) Y TikTok sin datos
Mensaje: "Las audiencias de Meta tienen frecuencia alta (3.2 promedio).
          TikTok todavía no tiene datos de tu cuenta.
          ¿Activamos TikTok Ads con USD 100 para probar?"

[ESTRATEGIA-005] — Zombie detectado
Trigger: cleanup.cron detecta cuenta activa sin uso 90 días
Mensaje: "La tienda [slug] lleva 90 días sin actividad (plan [X], USD Y/mes).
          Opciones: A) Contactar proactivamente (WA/email automático),
          B) Suspender y ofrecer reactivación, C) Mantener activa y monitorear."
```

#### GRUPO C: Alertas de sistema (no requieren decisión inmediata)

```
[SISTEMA-001] — Reporte semanal automático
Trigger: Cron domingo 8:00 AM
Contenido: Registros, pagos, MRR, leads outreach, CPA, CAC blended, highlight de la semana,
           1 recomendación accionable generada por IA

[SISTEMA-002] — Cuenta nueva registrada
Trigger: INSERT en nv_accounts
Mensaje: "Nueva tienda registrada: [email], plan seleccionado: [plan].
          Source: [utm_source]. Onboarding: [% completado]."

[SISTEMA-003] — Primer pago recibido
Trigger: Purchase event disparado
Mensaje: "🎉 PAGO RECIBIDO. [email], plan [X], USD [Y].
          CAC de este cliente: USD [cálculo si viene de pauta].
          MRR actualizado: USD [total]."

[SISTEMA-004] — Pago fallido (cliente existente)
Trigger: subscription_payment_failures INSERT
Mensaje: "Pago fallido: [email], plan [X]. El sistema ya envió recordatorio automático.
          Si falla de nuevo en 72hs, la cuenta entra en BILLING_HOLD."

[SISTEMA-005] — Infra alerta
Trigger: Railway/Supabase usage > 80% del plan actual
Mensaje: "Alerta de infra: [servicio] en [X]% de su límite.
          Proyección: alcanza el límite en [N] días con crecimiento actual."
```

---

### 3.3 — n8n workflow: `founder_notifications`

```json
// Estructura del workflow (pseudocódigo — importar como JSON en n8n)

TRIGGERS (múltiples):
├── Webhook desde API NestJS (para eventos de negocio en tiempo real)
├── Cron diario 9:00 AM (para chequeos diarios)
└── Cron domingo 8:00 AM (para reporte semanal)

NODOS:
1. Recibir evento con tipo + payload
2. Switch por tipo de evento → rama correspondiente
3. Para eventos que requieren IA: llamar OpenAI con contexto
4. Formatear mensaje WhatsApp
5. Enviar WA al founder (WHATSAPP_FOUNDER_NUMBER)
6. Registrar notificación en system_events (no perder historial)
```

**Endpoint en API para disparar notificaciones:**
```typescript
// apps/api/src/notifications/founder-notify.service.ts

@Injectable()
export class FounderNotifyService {
  async notify(type: NotificationType, payload: Record<string, unknown>) {
    // Fire and forget — no bloquear el flujo principal
    this.n8nWebhook.post('/founder-notifications', {
      type,
      payload,
      timestamp: new Date().toISOString(),
    }).catch(err => this.logger.error('Notify failed:', err));
  }
}
// Usar en: AccountsService, SubscriptionsService, PaymentService, CleanupCron
```

---

## PARTE 4: DASHBOARD DE CONTROL
### "Una pantalla, todo el negocio"

---

### 4.1 — Métricas del dashboard (en Admin Panel ya existente)

**Agregar sección "Growth" en `admin.novavision.lat`:**

```
┌──────────────────────────────────────────────────────────────────┐
│  NOVAVISION GROWTH HQ                              [hoy / 7d / 30d]
├──────────────────────────────────────────────────────────────────┤
│                                                                  │
│  MRR          REGISTROS     PAGOS HOY    CHURN MES              │
│  USD [X]      [N]           [N]          [N] ([%])              │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  FUNNEL                                                          │
│                                                                  │
│  Visitas   →  Registro  →  Onboarding  →  Plan sel.  →  Pago   │
│  [N]          [N]([%])     [N]([%])       [N]([%])     [N]([%]) │
│                                                                  │
│  Mayor drop-off: [tramo] → [%] de pérdida   [VER DETALLE]       │
│                                                                  │
├──────────────────────────────────────────────────────────────────┤
│  ADQUISICIÓN                    │  OUTREACH                     │
│                                 │                               │
│  Gasto pauta: USD [X]           │  Leads contactados: [N]       │
│  CPL: USD [X]                   │  En conversación: [N]         │
│  CPA: USD [X]                   │  Hot leads: [N] [ATENDER]     │
│  CAC blended: USD [X]           │  COLD/lost: [N]               │
│  Mejor canal: [meta/google/tk]  │                               │
│                                 │                               │
├──────────────────────────────────────────────────────────────────┤
│  INFRAESTRUCTURA                                                 │
│                                                                  │
│  Cuentas activas: [N]   Suspendidas: [N]   Scheduled del.: [N]  │
│  Supabase: [X]% usado   Railway: [X]% CPU   Zombies: [N]        │
│                                                                  │
│  Próxima limpieza automática: [fecha]   [FORZAR AHORA]          │
└──────────────────────────────────────────────────────────────────┘
```

---

### 4.2 — Endpoints de datos para el dashboard

**Nuevo controller:** `apps/api/src/admin/growth-hq.controller.ts`

```typescript
@Get('growth-hq/summary')
@UseGuards(SuperAdminGuard)
async getGrowthSummary(@Query('period') period: '1d' | '7d' | '30d') {
  return {
    mrr: await this.billingService.getCurrentMRR(),
    funnel: await this.funnelService.getFunnelMetrics(period),
    acquisition: await this.trackingService.getAdMetrics(period),
    outreach: await this.outreachService.getPipelineSummary(),
    infrastructure: await this.lifecycleService.getInfraMetrics(),
    topDropoff: await this.funnelService.getLargestDropoff(period),
  };
}
```

---

## PARTE 5: SISTEMA DE GESTIÓN DE VIDEOS Y CREATIVIDADES
### "Los videos que ya tenés, escalados en múltiples canales"

---

### 5.1 — Biblioteca de assets (tabla nueva en Admin DB)

```sql
CREATE TABLE ad_assets (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  type TEXT NOT NULL,              -- 'video' | 'image' | 'carousel' | 'copy'
  platform TEXT[],                 -- ['meta', 'google', 'tiktok', 'all']
  hook TEXT,                       -- Primer mensaje / hook principal
  angle TEXT,                      -- 'zero_commission' | 'speed' | 'logistics' | 'seo_ai'
  status TEXT DEFAULT 'pending',   -- 'pending' | 'active' | 'paused' | 'retired'
  storage_url TEXT,                -- URL en Supabase Storage o externo
  duration_seconds INTEGER,        -- Para videos
  aspect_ratio TEXT,               -- '9:16' | '1:1' | '16:9' | '4:5'
  campaign_id TEXT,                -- ID en la plataforma de ads
  metrics JSONB DEFAULT '{}',      -- {ctr, cpa, impressions, spend} updated por n8n
  created_at TIMESTAMPTZ DEFAULT NOW(),
  retired_at TIMESTAMPTZ,
  notes TEXT                       -- Instrucciones para uso / contexto
);
```

---

### 5.2 — Gestión de creatividades desde Admin Panel

**Vista en admin:** "Librería de Creatividades"

Desde ahí podés:
- Ver todos los assets con sus métricas actuales
- Marcar un asset como activo/pausado (el sistema lo refleja en los anuncios)
- Agregar nuevo video con metadata
- Ver sugerencia IA de "próximo video a producir" basado en gaps del portfolio

**Flujo cuando recibe notificación CREATIVO-001:**
```
1. [NOTIF] llega al WhatsApp: "Necesito video con ángulo X"
2. Vos grabás el video (con el script que el sistema te sugiere)
3. Subís el video en admin.novavision.lat/creatives/upload
4. El sistema:
   a. Sube a Supabase Storage
   b. Te pregunta: ¿Para qué plataforma? Meta / Google / TikTok / Todas
   c. Crea el anuncio en borrador via API de la plataforma
   d. Te envía preview para aprobación final
5. Vos aprobás con 1 click
6. El sistema activa el anuncio
```

---

## PARTE 6: FLUJO PRE-LANZAMIENTO
### "El orden correcto para no arrancar con deuda"

---

### Checklist ordenado por dependencias

#### SEMANA 1 — Base técnica (0 inversión, 0 leads llegando)

```
INFRA:
□ Implementar cleanup.cron.ts con los 6 pasos definidos en §1.2
□ Crear función SQL delete_account_cascade (§1.3) y testearla en staging
□ Insertar cupón FUNDADORES2026 (§1.4)
□ Crear tabla ad_assets (§5.1)

TRACKING:
□ Agregar TrackingEventsService a la API (§2.2)
□ Instalar GTM en Web (storefront) y en la landing de registro
□ Crear container GTM con los 6 eventos de funnel
□ Configurar Meta Pixel + CAPI (variables de entorno)
□ Configurar TikTok Pixel
□ Configurar GA4 + Measurement Protocol para eventos server-side
□ Verificar que todos los eventos llegan en Meta Events Manager

NOTIFICACIONES:
□ Crear workflow n8n `founder_notifications`
□ Agregar FounderNotifyService a la API
□ Testear con evento manual: simulate 'account_registered'
□ Confirmar que el WA llega al número del founder
```

#### SEMANA 2 — Cuentas publicitarias (0 inversión aún)

```
META:
□ Crear Business Manager a nombre de NovaVision (no cuenta personal)
□ Crear Ad Account dentro del BM
□ Vincular pixel al Ad Account
□ Subir primeros videos como assets (sin publicar como anuncios aún)
□ Crear estructura de campañas en BORRADOR (sin activar)
□ Configurar Custom Conversions con los eventos del funnel

GOOGLE:
□ Crear cuenta Google Ads a nombre de NovaVision
□ Vincular GA4 con Google Ads
□ Crear estructura Search en BORRADOR
□ Subir videos a YouTube (si no tenés canal, crearlo)
□ Keywords research: exportar 50 keywords más relevantes para Argentina

TIKTOK:
□ Crear TikTok Business Center
□ Crear Ad Account
□ Instalar TikTok Pixel (ya incluido en GTM si lo configuraste)
□ Subir videos adaptados a formato vertical (9:16)
```

#### SEMANA 3 — UTMs, landing y checkout flow

```
□ Definir y documentar UTM naming convention (§2.4)
□ Agregar UTMs a todos los links de outreach (n8n workflows)
□ Optimizar landing de registro:
   - Headline: específico, no genérico ("Creá tu tienda sin pagar comisiones")
   - CTA visible sin scroll
   - Social proof: "X tiendas activas en Argentina" (o logo de marca si es pública)
   - Precio visible: desde USD 20/mes — sin letra chica
□ Testear flow completo: click en anuncio → registro → onboarding → pago
□ Verificar que coupon FUNDADORES2026 funciona en checkout
□ Testear cleanup cron en modo dry-run (log sin ejecutar borrados reales)
□ Revisar Growth HQ dashboard con datos de test
```

#### SEMANA 4 — Activar pauta con presupuesto mínimo

```
□ Activar Meta Search primero (USD 200/mes, solo 2 ad sets, 3 anuncios cada uno)
□ Activar Google Search (USD 150/mes, solo grupo brand + problema/solución)
□ NO activar TikTok todavía (esperar datos de Meta para optimizar primero)
□ Configurar reglas automáticas en Meta (§2.3 reglas de pausa y escala)
□ Activar reporte diario de n8n (§PARTE 3 SISTEMA-001)
□ Primer checkpoint a los 7 días: ¿llegan eventos al pixel correctamente?
□ Segundo checkpoint a los 14 días: ¿hay registros? ¿cuál es el CPL real?
```

---

## RESUMEN EJECUTIVO — COSTOS DEL SISTEMA

### Infra del sistema automatizado (mensual recurrente)

| Componente | Costo |
|------------|-------|
| Railway (API + n8n) | ~USD 25/mes (ya existe) |
| Supabase (Admin + Backend) | ~USD 25/mes (ya existe, escala con uso real) |
| Netlify (Web + Admin) | ~USD 0-19/mes (ya existe, free tier aguanta hasta ~500K visitas) |
| OpenAI API (AI Closer + reportes + notificaciones) | ~USD 20-40/mes |
| Herramientas creativas (CapCut Pro / Canva) | ~USD 15/mes |
| **TOTAL SISTEMA** | **~USD 85-125/mes** |

### Inversión en pauta (separada, va a los canales)

| Canal | Mes 1 (validación) | Mes 2+ (si funciona) |
|-------|-------------------|---------------------|
| Meta Ads (FB + IG) | USD 300 | USD 500-1.000 |
| Google Ads | USD 150 | USD 250-500 |
| TikTok Ads | USD 0 (esperar) | USD 100-200 |
| **TOTAL PAUTA** | **USD 450** | **USD 850-1.700** |

### Tiempo tuyo por semana (en régimen)

| Actividad | Tiempo |
|-----------|--------|
| Revisar reporte semanal + tomar 1-3 decisiones | 30 min |
| Responder notificaciones del sistema | 15-20 min/día |
| Atender hot leads escalados por el AI Closer | 30 min/semana |
| Grabar 1 video/demo (cuando el sistema lo pida) | 30-45 min/semana |
| **TOTAL** | **~3-4 horas/semana** |

---

*Versión: 1.0. Actualizar en `novavision-docs/plans/PLAN_MARKETING_OS_v2.md` tras primer mes de datos reales.*
# PLAN: CRM Interno — Evolución del Super Admin Dashboard

> **Fecha:** 2026-03-16
> **Estado:** Propuesta — pendiente aprobación
> **Autor:** Claude (Principal Product Architect audit)
> **Alcance:** Admin Dashboard + API + n8n workflows
> **Dependencias:** Admin DB, Backend DB, n8n Pro ($100/mes)

---

## Resumen Ejecutivo

NovaVision ya tiene ~55-60% de un CRM funcional disperso en el Super Admin Dashboard y los workflows n8n de outreach. Este plan propone **consolidar y extender** — no rehacer — para transformar el dashboard en un CRM operativo interno completo.

**Decisión arquitectónica:** Evolucionar el Super Admin Dashboard existente. NO crear sistema CRM separado.

**Justificación:**
- Las entidades base (`nv_accounts`, `clients`, `subscriptions`, `outreach_leads`) ya existen
- La UI y navegación son extensibles (22 módulos, agregar más es trivial)
- n8n ya maneja outreach pre-venta con 6 workflows activos
- Backend NestJS soporta nuevos módulos sin fricciones
- Crear algo separado duplicaría entidades sin necesidad

---

## Tabla de Contenidos

1. [Auditoría del estado actual](#1-auditoría-del-estado-actual)
2. [Diagnóstico CRM](#2-diagnóstico-crm)
3. [Diseño objetivo](#3-diseño-objetivo)
4. [Integración con n8n](#4-integración-con-n8n)
5. [Modelo de datos](#5-modelo-de-datos)
6. [Automatizaciones](#6-automatizaciones)
7. [Permisos y roles](#7-permisos-y-roles)
8. [UX y vistas](#8-ux-y-vistas)
9. [KPIs y Health Score](#9-kpis-y-health-score)
10. [Roadmap por fases](#10-roadmap-por-fases)
11. [Mejoras de humanización de bots](#11-mejoras-de-humanización-de-bots)
12. [Riesgos y mitigaciones](#12-riesgos-y-mitigaciones)
13. [Bugs críticos pre-requisito](#13-bugs-críticos-pre-requisito)

---

## 1. Auditoría del estado actual

### 1.1 Módulos existentes en el Super Admin (22 páginas)

| Módulo | Ruta | Estado | Potencial CRM |
|--------|------|--------|---------------|
| Dashboard Home | `/dashboard` | Funcional | Punto de entrada CRM |
| Clientes | `/dashboard/clients` | Funcional | **CORE** — lista principal |
| Detalle Cliente | `/client/:id` | Funcional | **Embrión de Customer 360** |
| Leads/Outreach | `/dashboard/leads` | Funcional (131KB) | **Pipeline comercial ya existe** |
| Pending Approvals | `/dashboard/pending-approvals` | Funcional | Workflow operativo |
| Pending Completions | `/dashboard/pending-completions` | Funcional | Seguimiento onboarding |
| Billing Hub | `/dashboard/billing` | Funcional | Facturación centralizada |
| Finance | `/dashboard/finance` | Funcional | MRR / AR / margen |
| Métricas | `/dashboard/metrics` | Funcional | Funnel de negocio |
| Usage | `/dashboard/usage` | Funcional | Consumo por cliente |
| Subscription Events | `/dashboard/subscription-events` | Funcional | Log de lifecycle |
| Renewal Center | `/dashboard/renewal-center` | Funcional | Dominios y vencimientos |
| Inbox (WhatsApp) | `/dashboard/inbox` | Funcional | Canal de comunicación |
| Playbook | `/dashboard/playbook` | Funcional | Knowledge base ventas |
| Plans | `/dashboard/plans` | Funcional | Gestión de planes |
| SEO | `/dashboard/seo` | Funcional | Config por cliente |
| Emails | `/dashboard/emails` | Funcional | Monitoreo de envíos |
| Shipping | `/dashboard/shipping` | Funcional | Config logística |
| Coupons | `/dashboard/coupons` | Funcional | Descuentos |
| Design System | `/dashboard/design-system` | Funcional | Templates/paletas |
| Backend Clusters | `/dashboard/backend-clusters` | Funcional | Infraestructura |
| Dev Whitelist | `/dashboard/dev-whitelist` | Funcional | Acceso dev portal |

### 1.2 Entidades existentes relevantes para CRM

**Admin DB (Plano de Control):**

| Entidad | Tabla | Relevancia CRM |
|---------|-------|----------------|
| Cuentas | `nv_accounts` | Entidad raíz del cliente |
| Onboarding | `nv_onboarding` | Estado de activación |
| Planes | `plan_definitions`, `plan_catalog` | Segmentación por plan |
| Addons | `addon_catalog`, `account_addons` | Expansión comercial |
| Entitlements | `account_entitlements` | Snapshot de capacidades |
| Provisioning | `provisioning_jobs` | Estado operativo |
| Suscripciones | `subscriptions` | Billing recurrente |
| Eventos suscripción | `subscription_events` | Timeline parcial |
| Leads | `outreach_leads` | **Pipeline pre-venta YA EXISTE** |
| Logs outreach | `outreach_logs` | **Historial de interacciones** |
| Playbook | `nv_playbook` | Guiones de venta |
| Billing cycle | `billing_cycle` | Período de cobro |
| Usage ledger | `usage_ledger`, `usage_hourly`, `usage_daily` | Metering de consumo |
| Webhooks | `webhook_events` | Deduplicación |
| MP | `mp_connections`, `mp_events` | Pagos |
| Cupones | `coupons` | Comercial |

**Backend DB (Plano de Datos — Multi-tenant):**

| Entidad | Tabla | Relevancia CRM |
|---------|-------|----------------|
| Tiendas | `clients` | Entidad operativa |
| Productos | `products` | Nivel de activación |
| Órdenes | `orders` | Revenue del tenant |
| Pagos detalle | `order_payment_breakdown` | Detalle financiero |
| Config pagos | `client_payment_settings` | Config operativa |
| SEO | `seo_settings` | Nivel de setup |
| Reviews/Q&A | `product_reviews`, `product_questions` | Engagement |
| Email jobs | `email_jobs` | Comunicación |
| Usage events | `usage_event` | Actividad |
| Client usage | `client_usage` | Conteo productos |

### 1.3 Fortalezas reutilizables

1. **Pipeline de leads completo** — `outreach_leads` tiene estados (NEW → CONTACTED → QUALIFIED → ONBOARDING → WON → LOST), scoring AI, owner asignable, tags, pain_points, hot_lead flag, follow-up scheduling
2. **Historial de interacciones** — `outreach_logs` registra mensajes WhatsApp/Email con dirección, canal, estado
3. **Inbox WhatsApp** — Integrado en dashboard con búsqueda, filtros, envío
4. **Subscription Events** — Registro de lifecycle de suscripciones
5. **Usage metering robusto** — `usage_ledger` + agregados horarios/diarios
6. **Billing Hub** — Facturación centralizada con estados de cobro, pagos manuales, reintentos
7. **Finance Dashboard** — MRR, AR, cash collected, margen neto
8. **Provisioning Jobs** — Estado de provisioning con error tracking
9. **6 workflows n8n activos** — Outreach automatizado (ver sección 4)

### 1.4 Fallas y gaps detectados

| # | Falla | Severidad | Impacto |
|---|-------|-----------|---------|
| F1 | **No hay Customer 360** — La ficha `/client/:id` no consolida onboarding + billing + suscripción + uso + dominio + addons + timeline | CRÍTICA | No se puede evaluar un cliente de punta a punta |
| F2 | **No hay activity log / timeline por cliente** — No existe tabla `activity_log` ni vista de eventos cronológicos unificados | CRÍTICA | Imposible auditar historial completo |
| F3 | **No hay notas internas** — No existe tabla de notas | CRÍTICA | Pérdida de contexto comercial |
| F4 | **No hay tareas internas** — No hay sistema de tasks/reminders | CRÍTICA | Seguimiento imposible de escalar |
| F5 | **No hay owner/account manager en clientes activos** — `outreach_leads` tiene `assigned_to_user_id` pero `nv_accounts` y `clients` NO | ALTA | Sin responsabilidad post-venta |
| F6 | **Desconexión lead → cliente** — La transición no genera timeline continuo | ALTA | Gap en el journey completo |
| F7 | **No hay health score** — No existe scoring de salud de clientes activos | ALTA | Churn invisible |
| F8 | **No hay estado comercial separado del operativo** — `nv_accounts.status` mezcla estados técnicos con comerciales | ALTA | Confusión operativa |
| F9 | **No hay automatizaciones internas post-venta** — No existen crons ni triggers para alertas de riesgo o seguimiento | ALTA | Todo es manual |
| F10 | **Métricas dispersas** — Finance, Usage, Metrics y Billing son 4 vistas sin correlación por cliente | MEDIA | Análisis fragmentado |
| F11 | **No hay segmentación útil** — No se pueden filtrar clientes por health, riesgo, potencial | MEDIA | Imposible priorizar |
| F12 | **No hay vista "requiere acción hoy"** | MEDIA | Reactividad, no proactividad |
| F13 | **RBAC limitado** — Solo `is_super_admin` flag. No hay roles granulares | MEDIA | No escala con el equipo |
| F14 | **Cross-DB queries** — Datos partidos entre Admin DB y Backend DB requieren múltiples llamadas | MEDIA | Performance y complejidad |

### 1.5 Procesos manuales detectados

| Proceso | Cómo se hace hoy | Riesgo |
|---------|-------------------|--------|
| Seguimiento de onboarding frenado | Mirar Pending Completions y recordar | Se olvida |
| Detectar clientes en riesgo | No se hace | Churn sin aviso |
| Seguimiento de facturas impagas | Mirar Billing Hub manualmente | Sin priorización |
| Asignar responsable a una cuenta | No existe mecanismo | Nadie es dueño |
| Registrar nota de conversación | No se puede | Contexto perdido |
| Decidir a quién hacer upsell | Intuición | Sin datos |
| Saber si un cliente publicó y está activo | Cruzar múltiples vistas | Tedioso |
| Alertar por dominio con problemas | Renewal Center manual | Reactivo |

---

## 2. Diagnóstico CRM

### 2.1 Qué ya funciona como CRM

| Capacidad | Estado | Ubicación |
|-----------|--------|-----------|
| Pipeline de leads (pre-venta) | **Robusto** | `outreach_leads` + LeadsView + n8n |
| Lead scoring | AI-powered | `ai_engagement_score` + `computeScore()` |
| Historial de interacciones pre-venta | Funcional | `outreach_logs` |
| Canal WhatsApp integrado | Funcional | AdminInbox |
| AI Closer conversacional | Funcional | WF-INBOUND-V2 (n8n) |
| Outreach automatizado | Funcional | WF-SEED + WF-FOLLOWUP (n8n) |
| Playbook de ventas | Funcional | `nv_playbook` + PlaybookView |
| Lista de clientes con búsqueda | Básico | ClientsView |
| Detalle de cliente | Parcial | ClientDetails (sin 360) |
| Billing/facturación | Funcional | BillingView + FinanceView |
| Eventos de suscripción | Read-only | SubscriptionEventsView |
| Funnel de conversión | Funcional | MetricsView |
| Usage tracking | Funcional | UsageView |
| Gestión de dominios | Funcional | RenewalCenter |
| Sync lead↔onboarding | Funcional | WF-ONBOARDING-BRIDGE (n8n) |
| Reporte semanal | Funcional | WF-WEEKLY-REPORT (n8n) |

### 2.2 Qué falta para CRM real

| Capacidad | Prioridad | Esfuerzo |
|-----------|-----------|----------|
| **Customer 360 unificado** | P0 | Alto |
| **Activity log / timeline** | P0 | Alto |
| **Notas internas** | P0 | Bajo |
| **Tareas / recordatorios** | P0 | Medio |
| **Owner assignment (post-venta)** | P0 | Bajo |
| **Estado comercial del cliente** | P1 | Medio |
| **Health score** | P1 | Medio |
| **Alertas automáticas (NestJS → n8n)** | P1 | Medio |
| **Vistas accionables** | P1 | Medio |
| **Segmentación/filtros avanzados** | P2 | Medio |
| **Automatizaciones event-driven** | P2 | Alto |
| **RBAC granular** | P2 | Alto |
| **Dashboard CRM home** | P2 | Medio |

### 2.3 Qué no conviene hacer todavía

| Feature | Por qué NO ahora |
|---------|-------------------|
| CRM separado del dashboard | Duplicaría entidades y fragmentaría operación |
| Event bus (Kafka/RabbitMQ) | Sobreingeniería para <500 cuentas. Crons son suficientes |
| Integración HubSpot/Salesforce | El CRM interno cubre las necesidades. Agregar capa externa suma complejidad sin valor |
| Campañas masivas de email marketing | Resolver primero la operación 1:1 antes de escalar a masivo |
| Pipeline multi-etapa visual (Kanban) | Suena lindo pero el equipo es chico. Lista con filtros es más práctico |
| Scoring ML avanzado | El scoring manual/reglas es suficiente para el volumen actual |

---

## 3. Diseño objetivo

### 3.1 Customer 360 — Ficha unificada

```
┌─────────────────────────────────────────────────────────────┐
│ CUSTOMER 360 — [Nombre del Cliente]                         │
│                                                             │
│ ┌─────────────┐  Plan: Growth    Stage: ● Active Healthy    │
│ │   LOGO      │  Email: cliente@mail.com                    │
│ │             │  Slug: mi-tienda     Owner: @juanp          │
│ └─────────────┘  Desde: 15 ene 2026  País: AR              │
│                  Health: ████████░░ 78/100                   │
│                                                             │
│ ┌──────┬──────┬──────┬──────┬──────┬──────┐                 │
│ │RESUMEN│TIMELINE│BILLING│ USO  │NOTAS │TAREAS│  ← Tabs     │
│ └──────┴──────┴──────┴──────┴──────┴──────┘                 │
│                                                             │
│ TAB RESUMEN:                                                │
│ ┌─────────────────┐ ┌─────────────────┐                     │
│ │ Estado Comercial │ │ Estado Operativo│                     │
│ │ ● Active Healthy│ │ ● Published     │                     │
│ │ Upgrade: posible│ │ Domain: activo  │                     │
│ └─────────────────┘ └─────────────────┘                     │
│ ┌─────────────────┐ ┌─────────────────┐                     │
│ │ Facturación     │ │ Activación      │                     │
│ │ Al día          │ │ 342 productos   │                     │
│ │ MRR: $60 USD    │ │ 89 órdenes/mes  │                     │
│ │ Próx: 15 abr    │ │ Último login: 2d│                     │
│ └─────────────────┘ └─────────────────┘                     │
│                                                             │
│ ALERTAS: Dominio vence en 12 días                           │
│ OPORTUNIDAD: Uso alto, candidato a Enterprise               │
│                                                             │
│ TAB TIMELINE:                                               │
│ ┌ 16 mar 2026 ── Pago mensual acreditado ($60 USD)          │
│ ├ 14 mar 2026 ── Addon comprado: +500 productos             │
│ ├ 10 mar 2026 ── Nota: "Consultó por API pública"           │
│ ├ 01 mar 2026 ── Dominio custom activado                    │
│ ├ 15 feb 2026 ── Upgrade: Starter → Growth                  │
│ ├ 10 feb 2026 ── Tienda publicada                           │
│ ├ 05 feb 2026 ── Onboarding completado                      │
│ ├ 20 ene 2026 ── Pago inicial acreditado                    │
│ ├ 18 ene 2026 ── Lead convertido a cliente                  │
│ ├ 15 ene 2026 ── Cuenta creada                              │
│ └ 10 ene 2026 ── Lead capturado (fuente: Instagram)         │
└─────────────────────────────────────────────────────────────┘
```

### 3.2 Estados y pipeline

**Estado comercial (`lifecycle_stage` en `nv_accounts`):**

```
lead → trial → onboarding → active → [at_risk | expansion | enterprise] → churned
                    ↓
              onboarding_blocked
```

| Stage | Criterio de entrada | Criterio de salida |
|-------|--------------------|--------------------|
| `lead` | Lead capturado (outreach_leads) | Crea cuenta (nv_accounts) |
| `trial` | Cuenta creada, draft_builder | Inicia pago o expira |
| `onboarding` | Pago recibido, provisioning en curso | Tienda publicada |
| `onboarding_blocked` | Onboarding frenado >7 días sin progreso | Retoma o abandona |
| `active` | Tienda publicada + pagos al día | Se mantiene o transiciona |
| `at_risk` | Pago fallido OR baja actividad OR sin productos | Se recupera o churns |
| `expansion` | Usage >80% de límites del plan | Hace upgrade o estabiliza |
| `enterprise` | Plan enterprise o trato custom | Se mantiene |
| `churned` | Suscripción cancelada o suspendida definitiva | Se reactiva |

**Estado operativo (`nv_accounts.status`)** — se mantiene sin cambios:
```
draft → awaiting_payment → paid → provisioning → provisioned → [expired | failed]
```

**Estado de facturación (`subscriptions.status`)** — se mantiene:
```
pending → active → [paused | grace_period] → [cancelled | suspended]
```

---

## 4. Integración con n8n

### 4.1 Inventario de workflows existentes

| # | Workflow | Trigger | Frecuencia | Estado | Función |
|---|----------|---------|------------|--------|---------|
| 1 | WF-SEED-V2 | Cron | Diario 07:00 ART | Producción | Primer contacto WA + Email a leads NEW |
| 2 | WF-FOLLOWUP-V2 | Cron | 2x/día (08:00, 14:00 ART) | Producción | Follow-ups progresivos (3→5→7 días) |
| 3 | WF-INBOUND-V2 | Webhook | Real-time (WhatsApp) | Producción | AI Closer con GPT-4.1-mini |
| 4 | WF-HYGIENE-V2 | Cron | Diario 03:00 ART | Producción | Limpieza, dedup, marcar COLD |
| 5 | WF-ONBOARDING-BRIDGE-V2 | Cron | Cada 2 horas | Producción | Sync lead↔account↔onboarding |
| 6 | WF-WEEKLY-REPORT-V2 | Cron | Lunes 09:00 ART | Producción | Reporte semanal por WhatsApp |
| 7 | Chatbot Web | Chat trigger | Real-time | Producción (con deuda técnica) | Chatbot institucional novavision.lat |
| 8 | WF-IG-INBOUND-V1 | Webhook | Real-time (Instagram) | Staging | Procesamiento de DMs Instagram |
| 9 | WF-IG-DELIVERY-STATUS-V1 | Webhook | Real-time | Staging | Tracking delivery status IG |
| 10 | WF-IG-WEBHOOK-VERIFY-V1 | GET | Diagnóstico | Staging | Verificación webhook Meta |
| 11 | WF-CONTACT-FORM | Webhook | Real-time | Diseñado, NO implementado | Reemplazar EmailJS |

### 4.2 Regla de separación: n8n vs NestJS

| Responsabilidad | Motor | Justificación |
|-----------------|-------|---------------|
| Envío de WhatsApp/Email/IG | **n8n** | Ya tiene templates, tokens, cadencias |
| AI Closer / chatbot | **n8n** | OpenAI integrado, context window configurado |
| Lead scoring engagement | **n8n** | WF-INBOUND-V2 ya lo calcula |
| Follow-ups progresivos | **n8n** | WF-FOLLOWUP-V2 maduro |
| Hygiene / dedup leads | **n8n** | WF-HYGIENE-V2 maduro |
| Sync lead↔onboarding | **n8n** | WF-ONBOARDING-BRIDGE-V2 |
| Reporte semanal outreach | **n8n** | WF-WEEKLY-REPORT-V2 existente |
| **Health score cálculo** | **NestJS cron** | Requiere cross-DB, lógica de dominio compleja |
| **Lifecycle stage transitions** | **NestJS cron** | Lógica de negocio core |
| **Crear crm_tasks automáticas** | **NestJS cron** | Escritura directa a Admin DB |
| **Escribir crm_activity_log** | **NestJS** | Integrado con servicios existentes |
| **Alertas CRM → notificaciones** | **n8n via webhook** | NestJS detecta → POST webhook n8n → n8n envía por WA/email |
| Contact form processing | **n8n** | WF-CONTACT-FORM ya diseñado |
| Instagram DMs | **n8n** | WF-IG-INBOUND-V1 en staging |

### 4.3 Patrón de integración NestJS ↔ n8n

```
┌─────────────────────────────────────────────────────────┐
│                    NestJS API (CRM Core)                 │
│                                                         │
│  CrmHealthCron (diario)                                 │
│    → Calcula health_score por cuenta                    │
│    → Actualiza lifecycle_stage                          │
│    → Crea crm_tasks si detecta riesgo/oportunidad      │
│    → Escribe crm_activity_log                           │
│    → Si alerta urgente: POST webhook n8n ────────┐      │
│                                                  │      │
│  CrmActivityService                              │      │
│    → Instrumenta eventos en activity_log         │      │
│                                                  │      │
│  Customer360Service                              │      │
│    → Agrega datos cross-DB para UI               │      │
└──────────────────────────────────────────────────┘      │
                                                          │
┌──────────────────────────────────────────────────────────┘
│
▼
┌─────────────────────────────────────────────────────────┐
│                    n8n (Canales + Outreach)              │
│                                                         │
│  WF-CRM-ALERT-V1 (NUEVO)                               │
│    ← Webhook desde NestJS                               │
│    → Envía WA/Email al owner asignado                   │
│                                                         │
│  WF-CRM-WEEKLY-DIGEST-V1 (NUEVO)                       │
│    → Métricas CRM post-venta semanales                  │
│                                                         │
│  WF-BUILDER-DROPOUT-V1 (NUEVO)                          │
│    → Rescata leads que empezaron builder sin terminar   │
│                                                         │
│  [Workflows existentes sin cambios]                     │
│  WF-SEED, FOLLOWUP, INBOUND, HYGIENE, BRIDGE, REPORT   │
└─────────────────────────────────────────────────────────┘
```

### 4.4 Nuevos workflows n8n requeridos

#### WF-CRM-ALERT-V1

- **Trigger:** Webhook POST desde NestJS
- **Payload:** `{ account_id, account_name, alert_type, severity, message, owner_phone, owner_email }`
- **Tipos:** `onboarding_stale`, `payment_risk`, `inactive_store`, `expansion_candidate`, `task_overdue`, `domain_expiring`, `unpublished_store`
- **Acción:** Switch por `alert_type` → Template WA específico → Fallback email
- **Registro:** INSERT en `crm_activity_log` con `actor_type='automation'`
- **Fase:** 2

#### WF-CRM-WEEKLY-DIGEST-V1

- **Trigger:** Cron Lunes 09:30 ART (después del WEEKLY-REPORT de outreach)
- **Métricas:** Health distribution, cuentas en riesgo, tareas vencidas, onboardings bloqueados, MRR delta, nuevos activos, churn semanal
- **Destino:** WhatsApp a grupo de operaciones + email
- **Fase:** 2

#### WF-BUILDER-DROPOUT-V1

- **Trigger:** Cron cada 4 horas
- **Query:** `nv_accounts` con `status='draft'` AND `last_saved_at < now()-24h`
- **Acción:** Enviar WA: "Vi que empezaste a armar tu tienda pero no terminaste..."
- **Impacto:** Rescata leads con intención real demostrada
- **Fase:** 2

#### Modificación: WF-ONBOARDING-BRIDGE-V2

- **Agregar:** Cuando detecta conversión WON → INSERT en `crm_activity_log` con `event_type='lead_converted'`
- **Agregar:** Cuando detecta ONBOARDING → verificar si hay `crm_task` existente; si no, crear una
- **Fase:** 1

---

## 5. Modelo de datos

### 5.1 Columnas nuevas en `nv_accounts`

```sql
ALTER TABLE nv_accounts
  ADD COLUMN lifecycle_stage    text DEFAULT 'lead',
  ADD COLUMN commercial_owner   uuid REFERENCES auth.users(id),
  ADD COLUMN health_score       smallint,
  ADD COLUMN health_computed_at timestamptz,
  ADD COLUMN last_activity_at   timestamptz,
  ADD COLUMN tags               text[] DEFAULT '{}';

CREATE INDEX idx_nv_accounts_lifecycle ON nv_accounts(lifecycle_stage);
CREATE INDEX idx_nv_accounts_health ON nv_accounts(health_score);
CREATE INDEX idx_nv_accounts_owner ON nv_accounts(commercial_owner);
```

### 5.2 Tabla: `crm_notes`

```sql
CREATE TABLE crm_notes (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id   uuid NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,
  author_id    uuid NOT NULL REFERENCES auth.users(id),
  content      text NOT NULL,
  pinned       boolean DEFAULT false,
  created_at   timestamptz DEFAULT now(),
  updated_at   timestamptz DEFAULT now()
);

CREATE INDEX idx_crm_notes_account ON crm_notes(account_id, created_at DESC);
CREATE TRIGGER trg_crm_notes_updated_at
  BEFORE UPDATE ON crm_notes
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

### 5.3 Tabla: `crm_tasks`

```sql
CREATE TABLE crm_tasks (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id     uuid REFERENCES nv_accounts(id) ON DELETE SET NULL,
  title          text NOT NULL,
  description    text,
  status         text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending', 'in_progress', 'done', 'cancelled')),
  priority       text NOT NULL DEFAULT 'normal'
                   CHECK (priority IN ('low', 'normal', 'high', 'urgent')),
  due_date       timestamptz,
  assigned_to    uuid REFERENCES auth.users(id),
  created_by     uuid REFERENCES auth.users(id),
  source         text DEFAULT 'manual'
                   CHECK (source IN ('manual', 'automation', 'system')),
  automation_key text,
  completed_at   timestamptz,
  created_at     timestamptz DEFAULT now(),
  updated_at     timestamptz DEFAULT now()
);

CREATE INDEX idx_crm_tasks_account ON crm_tasks(account_id);
CREATE INDEX idx_crm_tasks_assigned ON crm_tasks(assigned_to, status);
CREATE INDEX idx_crm_tasks_due ON crm_tasks(due_date) WHERE status IN ('pending', 'in_progress');
CREATE INDEX idx_crm_tasks_automation ON crm_tasks(account_id, automation_key)
  WHERE status IN ('pending', 'in_progress');
```

### 5.4 Tabla: `crm_activity_log`

```sql
CREATE TABLE crm_activity_log (
  id           bigserial PRIMARY KEY,
  account_id   uuid NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,
  actor_type   text NOT NULL
                 CHECK (actor_type IN ('system', 'admin', 'automation', 'webhook', 'n8n')),
  actor_id     uuid,
  event_type   text NOT NULL,
  event_data   jsonb DEFAULT '{}',
  created_at   timestamptz DEFAULT now()
);

CREATE INDEX idx_activity_account_time ON crm_activity_log(account_id, created_at DESC);
CREATE INDEX idx_activity_event_type ON crm_activity_log(event_type);
```

**Tipos de evento a instrumentar:**

| Fuente | event_type | Fase |
|--------|-----------|------|
| nv_accounts | `account_created`, `status_changed`, `plan_changed`, `lifecycle_changed` | 1 |
| nv_onboarding | `onboarding_started`, `onboarding_completed`, `onboarding_blocked` | 1 |
| subscriptions | `subscription_created`, `payment_success`, `payment_failed`, `subscription_paused`, `subscription_cancelled` | 1 |
| provisioning_jobs | `provisioning_started`, `provisioning_completed`, `provisioning_failed` | 1 |
| account_addons | `addon_purchased` | 2 |
| clients (Backend) | `store_published`, `custom_domain_activated`, `domain_renewal` | 2 |
| crm_notes | `note_added`, `note_pinned` | 1 |
| crm_tasks | `task_created`, `task_completed`, `task_overdue` | 1 |
| Manual (admin) | `manual_contact`, `manual_status_override` | 1 |
| Automatizaciones | `alert_triggered`, `automation_fired` | 2 |
| n8n bridge | `lead_converted` | 1 |

### 5.5 Entidades que NO se crean (ya hay equivalentes)

| Descartada | Motivo |
|------------|--------|
| `crm_accounts` | Usar `nv_accounts` + columnas nuevas |
| `crm_contacts` | Usar `nv_accounts.email` + datos de `nv_onboarding.data` |
| `crm_opportunities` | Usar `lifecycle_stage = 'expansion'` + tareas |
| `crm_segments` | Usar `tags[]` en `nv_accounts` + queries dinámicas |

### 5.6 Migración: `ADMIN_030_crm_core.sql`

Archivo único que incluye:
1. ALTER TABLE nv_accounts (columnas + índices)
2. CREATE TABLE crm_notes
3. CREATE TABLE crm_tasks
4. CREATE TABLE crm_activity_log
5. Backfill lifecycle_stage:

```sql
UPDATE nv_accounts SET lifecycle_stage = CASE
  WHEN status = 'draft' THEN 'trial'
  WHEN status IN ('awaiting_payment', 'paid', 'provisioning') THEN 'onboarding'
  WHEN status = 'provisioned' THEN 'active'
  WHEN status = 'expired' THEN 'churned'
  WHEN status = 'failed' THEN 'onboarding_blocked'
  ELSE 'lead'
END
WHERE lifecycle_stage IS NULL OR lifecycle_stage = 'lead';
```

---

## 6. Automatizaciones

### 6.1 Motor: NestJS crons (detección) + n8n webhooks (notificación)

NestJS NUNCA envía por canales directamente. Siempre llama webhook de n8n. Single source of truth para credenciales de canales.

### 6.2 Crons en NestJS

```typescript
// CrmHealthCron — diario a las 05:00 ART
@Cron('0 8 * * *')  // 08:00 UTC = 05:00 ART
async recalculateHealthScores() {
  // Para cada nv_account activa:
  // 1. Calcular health_score (ver sección 9.2)
  // 2. Actualizar nv_accounts.health_score + health_computed_at
  // 3. Detectar transiciones de lifecycle_stage
  // 4. Si health < 40: crear tarea si no existe una abierta
  // 5. Si uso > 80%: marcar expansion si no está ya
  // 6. Log en crm_activity_log
}

// CrmLifecycleCron — cada 30 minutos
@Cron('*/30 * * * *')
async checkLifecycleTransitions() {
  // 1. Onboardings frenados >7 días → lifecycle_stage = 'onboarding_blocked', crear tarea
  // 2. Pagos en grace_period o failed → lifecycle_stage = 'at_risk', crear tarea urgente
  // 3. Tiendas publicadas sin actividad 14+ días → at_risk
  // 4. Tiendas sin publicar >14 días post-provisioning → crear tarea
  // 5. Si alerta urgente: POST webhook n8n WF-CRM-ALERT
}

// CrmTaskOverdueCron — cada 30 minutos
@Cron('15,45 * * * *')
async checkOverdueTasks() {
  // 1. Buscar crm_tasks con due_date < now() AND status IN (pending, in_progress)
  // 2. Log task_overdue en activity_log
  // 3. POST webhook n8n para notificar al owner
}
```

### 6.3 Tabla de automatizaciones detallada

| Automatización | Trigger | Condición | Acción | Prioridad | Idempotencia |
|----------------|---------|-----------|--------|-----------|--------------|
| Onboarding frenado | Cron 30min | `nv_onboarding.state != 'live'` AND `updated_at < now()-7d` | Crear tarea high, lifecycle→onboarding_blocked, log | Alta | No crear si ya existe tarea abierta con `automation_key='stale_onboarding'` |
| Pago en riesgo | Cron 30min | `subscriptions.consecutive_failures > 0` OR `status = 'grace_period'` | Crear tarea urgent, lifecycle→at_risk, log, webhook n8n | Urgente | Check por automation_key='payment_risk' |
| Tienda inactiva | Cron diario | Publicada + 0 órdenes en 30d + 0 login 14d | Crear tarea normal, lifecycle→at_risk, log | Normal | Check por automation_key='inactive_store' |
| Candidato expansión | Cron diario | `products_count > 80%` límite OR `orders > 80%` incluido | lifecycle→expansion, crear tarea upsell, log | Normal | Check por automation_key='expansion_candidate' |
| Tienda sin publicar | Cron diario | `status = 'provisioned'` AND `publication_status != 'published'` AND `>14d` | Crear tarea seguimiento, log | Normal | Check por automation_key='unpublished_store' |
| Tarea vencida | Cron 30min | `crm_tasks.due_date < now()` AND `status IN (pending, in_progress)` | Log, webhook n8n notificación | Alta | Solo una notificación por tarea |
| Dominio por vencer | Cron diario | Dominio vence en <30 días | Crear tarea, log | Normal | Check por automation_key='domain_expiring' |

---

## 7. Permisos y roles

### Fase 1: Simple (columna en auth.users)

```sql
ALTER TABLE auth.users ADD COLUMN admin_role text DEFAULT 'viewer'
  CHECK (admin_role IN ('super_admin', 'sales', 'customer_success', 'billing', 'operations', 'viewer'));
```

### Matriz de permisos

| Recurso | super_admin | sales | customer_success | billing | operations | viewer |
|---------|:-----------:|:-----:|:----------------:|:-------:|:----------:|:------:|
| CRM: ver clientes | W | R | R | R | R | R |
| CRM: notas | W | W | W | R | R | R |
| CRM: tareas | W | W | W | W | W | R |
| CRM: asignar owner | W | W (propias) | W (propias) | - | - | - |
| CRM: cambiar lifecycle | W | W | W | - | - | - |
| CRM: health score (ver) | R | R | R | R | R | R |
| Leads/outreach | W | W | R | - | - | R |
| Billing Hub | W | R | R | W | R | R |
| Finance | W | - | - | R | - | - |
| Plans/config | W | - | - | - | - | - |
| Clusters/infra | W | - | - | - | W | - |
| Settings globales | W | - | - | - | - | - |

W = Write, R = Read, - = Sin acceso

---

## 8. UX y vistas

### 8.1 Nuevas páginas

| Ruta | Componente | Descripción | Fase |
|------|-----------|-------------|------|
| `/dashboard/crm` | CrmHome | Landing CRM: alertas, tareas del día, métricas rápidas | 2 |
| `/dashboard/crm/customer/:accountId` | Customer360 | Ficha unificada (reemplaza `/client/:id`) | 1 |
| `/dashboard/crm/tasks` | TaskBoard | Tablero de tareas personal + equipo | 1 |
| `/dashboard/crm/alerts` | AlertsView | Alertas activas priorizadas | 2 |

### 8.2 Vistas accionables (filtros dentro de CRM)

| Vista | Filtro | Fase |
|-------|--------|------|
| Requiere acción hoy | Tareas vencidas + alertas críticas + health < 40 | 2 |
| Onboardings trabados | `lifecycle_stage = 'onboarding_blocked'` | 1 |
| Cuentas en riesgo | `health_score < 40` | 2 |
| Impagos | `subscriptions.status IN ('grace_period', 'suspended')` | 1 |
| Listos para expandir | `lifecycle_stage = 'expansion'` | 2 |
| Tiendas no publicadas | `publication_status != 'published'` AND >14 días | 1 |
| Dominios con problemas | Renewal vencido o fallido | 1 |
| Sin owner | `commercial_owner IS NULL` AND `lifecycle_stage NOT IN ('lead', 'churned')` | 1 |

### 8.3 Mejoras a vistas existentes

| Vista actual | Mejora | Fase |
|-------------|--------|------|
| ClientsView (`/dashboard/clients`) | Agregar columnas: lifecycle_stage, health_score badge, owner. Agregar filtros por stage, health, owner | 1 |
| DashboardHome | Agregar widget "Tareas pendientes hoy" y "Alertas CRM" | 2 |

---

## 9. KPIs y Health Score

### 9.1 KPIs operativos y comerciales

| KPI | Fuente de datos | Fase |
|-----|-----------------|------|
| Tiempo a publicación (mediana) | nv_accounts.created_at → clients.publication_date | 2 |
| Onboarding completion rate | nv_onboarding completados / total iniciados | 2 |
| Trial → published conversion | cuentas publicadas / cuentas creadas | 2 |
| Published → paying conversion | suscripciones activas / tiendas publicadas | 2 |
| Churn rate mensual | cancelled+suspended / total activas inicio mes | 2 |
| Cuentas con pagos vencidos | subscriptions en grace_period o suspended | 1 (filtro) |
| MRR por plan | SUM(plan_price_usd) GROUP BY plan_key | 2 |
| Revenue por cliente | subscriptions.plan_price_usd + addons | 2 |
| Cuentas health < 40 | COUNT WHERE health_score < 40 | 2 |
| Tareas vencidas sin cerrar | COUNT crm_tasks WHERE due_date < now() AND status != done | 1 |

### 9.2 Fórmula de Health Score

```
HEALTH_SCORE (0-100) =
  payment_score      × 0.30
+ activation_score   × 0.25
+ publishing_score   × 0.15
+ activity_score     × 0.15
+ onboarding_score   × 0.10
+ recency_score      × 0.05
```

**Componentes:**

| Score | 100 | 50 | 20 | 0 |
|-------|-----|----|----|---|
| payment_score | Suscripción active, al día | grace_period | consecutive_failures > 0 | suspended/cancelled |
| activation_score | products_count > 50% del límite | 20-50% del límite | 1-20% del límite | 0 productos |
| publishing_score | Publicada + custom domain | Publicada sin domain | En provisioning | No publicada |
| activity_score | >10 órdenes en 30 días | 1-10 órdenes en 30 días | 0 órdenes pero login reciente | 0 órdenes + sin login |
| onboarding_score | Completado al 100% | >50% completado | <50% completado | No iniciado |
| recency_score | Actividad en últimos 3 días | Últimos 7 días | Últimos 14 días | >14 días |

**Clasificación:**

| Rango | Etiqueta | Acción sugerida |
|-------|----------|-----------------|
| 80-100 | Healthy | Monitoreo pasivo, candidato a testimonio |
| 60-79 | Needs attention | Revisión proactiva mensual |
| 40-59 | At risk | Contacto proactivo, tarea urgente |
| 0-39 | Critical | Intervención inmediata, escalación |

---

## 10. Roadmap por fases

### Quick wins pre-CRM (2 días, independiente)

- [ ] Fix chatbot web: reemplazar placeholder `[AQUI_TU_LINK_DE_REGISTRO]` con URL real
- [ ] Fix contact form: template 4 hace `alert()` → hacerlo funcional
- [ ] Fix bugs A3 (attempt_count=0 post-seed) y A2/B2 (continueOnFail) en n8n

### Fase 1 — CRM Mínimo Útil (3-4 semanas)

**Semana 1:**
- [ ] Crear migración `ADMIN_030_crm_core.sql`
- [ ] Agregar `lifecycle_stage`, `commercial_owner`, `health_score`, `tags` a `nv_accounts`
- [ ] Crear tabla `crm_notes` + endpoints CRUD en NestJS
- [ ] Crear tabla `crm_tasks` + endpoints CRUD en NestJS
- [ ] Backfill `lifecycle_stage` basado en estado actual

**Semana 2:**
- [ ] Crear tabla `crm_activity_log`
- [ ] Instrumentar activity log en: creación de cuenta, cambio de estado, pago recibido/fallido, tienda publicada
- [ ] Crear endpoint `GET /admin/crm/customer-360/:accountId` (agregador cross-DB)
- [ ] Modificar WF-ONBOARDING-BRIDGE-V2 para escribir en `crm_activity_log` al convertir lead

**Semana 3:**
- [ ] Construir UI Customer 360: tabs (resumen, timeline, billing, uso, notas, tareas)
- [ ] Panel de notas: crear, editar, pin, eliminar
- [ ] Panel de tareas: crear, asignar, completar, filtrar
- [ ] Timeline: renderizar `crm_activity_log` cronológicamente

**Semana 4:**
- [ ] Mejorar ClientsView: agregar columnas lifecycle_stage, owner, health badge
- [ ] Agregar filtros: por stage, por owner, por health range
- [ ] Asignación de owner desde lista y desde Customer 360
- [ ] Vista "Sin owner" y "Onboardings trabados"
- [ ] Crear `/dashboard/crm/tasks` (tablero de tareas personal + equipo)

### Fase 2 — Automatización Operativa (3-4 semanas)

- [ ] Implementar `CrmHealthCron` — cálculo diario de health score
- [ ] Implementar `CrmLifecycleCron` — transiciones automáticas + creación de tareas
- [ ] Implementar `CrmTaskOverdueCron` — detección de tareas vencidas
- [ ] Crear WF-CRM-ALERT-V1 en n8n (webhook para alertas)
- [ ] Crear WF-CRM-WEEKLY-DIGEST-V1 en n8n (resumen CRM semanal)
- [ ] Crear WF-BUILDER-DROPOUT-V1 en n8n (rescatar abandonos de builder)
- [ ] Implementar WF-CONTACT-FORM (diseño ya existe)
- [ ] Mover Instagram DM workflows a producción
- [ ] Vista "Requiere acción hoy" en dashboard
- [ ] Badges de alertas en navegación
- [ ] 7 automatizaciones core (ver sección 6.3)

### Fase 3 — Inteligencia y Escala (4-6 semanas)

- [ ] RBAC granular (columna admin_role + guards en API + filtros en UI)
- [ ] Dashboard CRM Home con KPIs agregados
- [ ] Extender WF-WEEKLY-REPORT-V2 con métricas CRM
- [ ] Segmentación avanzada con tags + queries dinámicas
- [ ] Vistas especializadas: riesgo, impagos, expansión, dominios
- [ ] Error handling uniforme en todos los workflows n8n
- [ ] Reporting: export de clientes por cohorte, tendencias
- [ ] Evaluar migración a event-driven si volumen lo justifica

---

## 11. Mejoras de humanización de bots

### Contexto: plan n8n Pro ($100/mes)

| Recurso | Incluido | Uso actual | Margen |
|---------|----------|------------|--------|
| Ejecuciones | 40,000/mes | ~3,000-5,000 | ~80% libre |
| AI Credits n8n | 10,000/mes | ~0 (usa API key OpenAI propia) | 100% libre |
| Workflows activos | Ilimitados | 9-10 | Sin límite |

**Costo de OpenAI separado:** GPT-4.1-mini ~$0.40/M input, ~$1.60/M output. Centavos por conversación.

### 12 mejoras concretas (costo adicional: ~$2-6/mes en OpenAI)

#### A. AI Closer (WF-INBOUND-V2)

| # | Mejora | Impacto | Esfuerzo |
|---|--------|---------|----------|
| 1 | **Partir mensajes largos** en 2-3 envíos con delays 2-4s (humanos no escriben párrafos) | Alto | Nodo Code + loop |
| 2 | **Typing indicator** — enviar `typing_on` via API WA antes del delay | Alto | 1 nodo HTTP Request |
| 3 | **Delay proporcional** al largo — `baseDelay + (charCount × 50ms)` | Medio | Ajustar Humanize Delay |
| 4 | **Personalidad argentina** marcada — "dale", "de una", "mirá", "fijate". Prohibir "¡Excelente pregunta!" y similares | Alto | Modificar system prompt |
| 5 | **Referenciar historial** — mencionar lo que el lead dijo antes naturalmente | Alto | Agregar instrucción al prompt |
| 6 | **Audios de voz** — TTS de OpenAI en momentos clave (primera respuesta, closing). $0.015/audio | MUY ALTO | Nodo HTTP → TTS → upload WA media |

#### B. Seed y Follow-ups

| # | Mejora | Impacto | Esfuerzo |
|---|--------|---------|----------|
| 7 | **Templates WA más casuales** — rotar entre formal y conversacional | Medio | Crear + aprobar templates Meta |
| 8 | **Horario inteligente** — enviar 09-11 o 14-16 con jitter ±30min | Medio | Modificar cron + delay |
| 9 | **FU3 empático** — cierre que deja puerta abierta, no solo marca COLD | Medio | Nuevo template |

#### C. Conversión a suscripción

| # | Mejora | Impacto | Esfuerzo |
|---|--------|---------|----------|
| 10 | **Deep link pre-cargado** — `builder?name=X&email=Y&slug=Z&lead_id=W` reduce fricción | Alto | Nodo Code genera URL |
| 11 | **Cupón en DISCOVERY** si engagement >60 y menciona precio — no esperar a CLOSING | Alto | Ajustar condición en prompt |
| 12 | **WF-BUILDER-DROPOUT** — rescatar drafts abandonados >24h con WA personalizado | MUY ALTO | Nuevo workflow n8n |

### Priorización por ROI

| Prioridad | Mejoras | Justificación |
|-----------|---------|---------------|
| P0 (esta semana) | Fix bugs A2, A3, B1, B2 | Sin esto, follow-ups no funcionan correctamente |
| P1 (semana 1-2) | #6 (audios TTS), #10 (deep link), #12 (builder dropout) | Mayor impacto en conversión |
| P2 (semana 2-3) | #1 (split msgs), #2 (typing), #4 (personalidad), #5 (historial) | Humanización del AI Closer |
| P3 (semana 3-4) | #3 (delay prop), #7 (templates), #8 (horarios), #9 (FU3), #11 (cupón) | Optimización incremental |

---

## 12. Riesgos y mitigaciones

| Riesgo | Severidad | Mitigación |
|--------|-----------|------------|
| **Cross-DB queries lentas** — Customer 360 lee Admin DB + Backend DB | Alta | Endpoint server-side que hace ambas queries y cachea 5 min |
| **Activity log crece rápido** — sin partición se vuelve lenta | Media | Particionar por `created_at` (mensual). Retención 12 meses activa |
| **Backfill incompleto** — lifecycle_stage puede no cubrir edge cases | Media | Ejecutar + revisión manual de primeras 50 cuentas |
| **Automatizaciones duplican tareas** — cron crea tarea repetida | Alta | Check idempotencia: no crear si existe tarea abierta con mismo `automation_key` para esa cuenta |
| **Datos inconsistentes entre DBs** — Admin dice provisioned pero Backend no tiene tienda | Media | Customer 360 muestra inconsistencias explícitamente |
| **Scope creep** — querer Salesforce en vez de CRM operativo | Alta | Filtro: "¿el equipo lo va a usar esta semana?" Si no → backlog |
| **Owner vacío** — sin owners asignados el CRM no sirve | Media | Default: super admin es owner. Vista "sin owner" para asignar |
| **n8n como SPOF** — si cae, no hay alertas | Media | Health check desde NestJS (cron horario). Fallback: log alertas con flag `notification_pending` |
| **Doble escritura logs** — `outreach_logs` (n8n) y `crm_activity_log` (NestJS) | Media | Mantener separadas: pre-venta vs post-venta. Customer 360 lee ambas |
| **LeadsView 131KB** — deuda técnica difícil de mantener | Media | No refactorear ahora. CRM nuevo es modular desde inicio |

---

## 13. Bugs críticos pre-requisito

Antes de implementar CRM o mejoras de humanización, resolver los bugs documentados en `architecture/n8n-outreach-system-v2.md`:

### Workflow A — Seed (5 bugs)

| # | Sev | Bug | Fix |
|---|-----|-----|-----|
| A1 | CRÍTICO | `phone_number_id` hardcodeado | Mover a variable de entorno o credencial |
| A2 | CRÍTICO | `continueOnFail: true` en Send + Update | Desactivar, agregar error branch |
| A3 | CRÍTICO | `attempt_count` se resetea a 0 post-seed | Setear `attempt_count = 1` en seed |
| A4 | ALTO | Race condition WA/Email en paralelo | Serializar o usar merge node |
| A5 | ALTO | Log ejecuta después de UPDATE, no atómico | Envolver en transacción o invertir orden |

### Workflow B — Follow-ups (4 bugs)

| # | Sev | Bug | Fix |
|---|-----|-----|-----|
| B1 | CRÍTICO | Dispatch por `attempt_count \|\| 1` nunca llega a FU2 | Fix A3 primero, luego ajustar dispatch |
| B2 | CRÍTICO | `continueOnFail: true` en todos Send | Desactivar, agregar error branch |
| B3 | ALTO | Update y Log corren en paralelo | Serializar |
| B4 | ALTO | No hay backoff entre FU1/FU2/FU3 | Ajustar cadencia a 3→5→7 días (ya documentado pero no implementado) |

---

## Apéndice: Recursos de n8n

**Plan actual:** n8n Cloud Pro — $100/mes
- 40,000 ejecuciones/mes (uso actual ~3,000-5,000)
- 10,000 AI credits (sin usar — API key OpenAI propia)
- Workflows ilimitados
- 5 usuarios
- SSO + 99.5% SLA

**Costo OpenAI adicional:** ~$2-8/mes (GPT-4.1-mini + TTS si se implementa)

**Total operativo mensual:** ~$102-108/mes (sin cambio en plan n8n)

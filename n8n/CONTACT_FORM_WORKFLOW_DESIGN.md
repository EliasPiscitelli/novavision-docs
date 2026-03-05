# NovaVision — Diseño de Workflow n8n: Formulario de Contacto

**Autor:** Copilot Agent (Senior Automation Engineer)
**Fecha:** 2026-03-03
**Estado:** Propuesta — pendiente confirmación del TL

---

## 0. Hallazgo Crítico: NO EXISTE un workflow de contacto hoy

Tras analizar el codebase completo y el único workflow n8n existente (`chatbotweb/module.json`), la situación es:

| Canal de contacto | Implementación actual | Problemas |
|---|---|---|
| **Chat widget** (novavision.lat) | Workflow n8n con AI Agent + FAQs + Calendar + Sheets | Funciona, pero sin anti-spam, sin dedup, sin error handling, sin alertas |
| **Contact form** (storefronts tiendas) | EmailJS client-side (templates 1-3). Template 4: `alert()` stub | Sin persistencia, sin auditoría, sin routing multi-tenant, credenciales compartidas |

**El workflow que me pasaste (`module.json`) es el CHATBOT del sitio institucional, NO un workflow de formulario de contacto.**

El formulario de contacto de las tiendas envía emails directo desde el browser vía EmailJS → sin pasar por n8n, sin backend, sin logs.

---

## 1. Preguntas Clave (máx. 7)

Antes de ejecutar, necesito confirmar estos puntos. Mientras tanto, avanzo con supuestos marcados.

| # | Pregunta | Supuesto si no contestás |
|---|---|---|
| **Q1** | ¿Querés mejorar el **chatbot** existente (novavision.lat), crear un **workflow NUEVO para el formulario de contacto** de las tiendas, o **ambos**? | **Supuesto A: Ambos** — mejoro el chatbot Y creo workflow de contacto |
| **Q2** | ¿Los mensajes del formulario de contacto deben llegar al **dueño de cada tienda** (multi-tenant) o solo al **equipo NovaVision** interno? | **Supuesto: Al equipo NovaVision** (routing por tags), ya que hoy EmailJS va todo a `novavision.contact@gmail.com` |
| **Q3** | ¿Canal de notificación interna preferido? (Slack, Telegram, WhatsApp Business API, email, o combinación) | **Supuesto: Email + Telegram** (menor setup, Slack no detectado en el stack) |
| **Q4** | ¿Querés mantener EmailJS como fallback/legacy, o migrar 100% a n8n webhook? | **Supuesto: Migrar 100% a n8n** (EmailJS queda deprecado) |
| **Q5** | ¿Tenés un bot de Telegram ya creado para el equipo, o hay que crear uno? | **Supuesto: Hay que crearlo** (incluyo pasos) |
| **Q6** | ¿La Google Sheet `1dzeZJfrpEz5SbbpzB_Eo_qaQpA4U-1ftqHJKczvvhJw` sigue activa y querés seguir usándola para leads, o preferís persistir en Supabase? | **Supuesto: Supabase** (single source of truth, ya tenés la infra) |
| **Q7** | ¿El envío de auto-respuesta al usuario (confirmación de recepción) debe ser por email, o solo el ACK en el form basta? | **Supuesto: Solo ACK en el form** (sin auto-email por ahora) |

---

## 2. Diagnóstico del Chatbot Actual (`chatbotweb/module.json`)

### 2.1 Mapa de Nodos

| # | Nodo | Tipo | Propósito | Credenciales | Problemas detectados |
|---|---|---|---|---|---|
| 1 | `When chat message received` | chatTrigger | Recibe mensajes del widget embebido en novavision.lat | — | `allowedOrigins: "https://novavision.lat"` ✅ solo ese origen. Falta rate-limit. |
| 2 | `AI Agent1` | agent (LangChain) | Orquesta tools según System Prompt. Clasifica entre self-serve y Enterprise | — | System prompt tiene `[AQUI_TU_LINK_DE_REGISTRO]` **sin reemplazar** → UX rota. maxTokens=200 es MUY bajo → respuestas cortadas. |
| 3 | `OpenAI Chat Model1` | lmChatOpenAi | GPT-3.5-turbo | `OpenAi account (2OjaIwTnrQ68U89v)` | **gpt-3.5-turbo está deprecado** por OpenAI. Migrar a gpt-4o-mini (más barato y mejor). maxTokens=200 insuficiente. |
| 4 | `Window Buffer Memory1` | memoryBufferWindow | Mantiene historial de conversación | — | Default window size (probablemente 5). OK para chat corto. |
| 5 | `FAQsTool1` | toolCode (JS) | Fuzzy search sobre array en memoria | — | ✅ Actualizado correctamente con 24 FAQs y precios correctos ($390 Enterprise). Scoring básico pero funcional. |
| 6 | `Check Availability1` | googleCalendarTool | Consulta disponibilidad en Google Calendar | `Google Calendar (qyWKJIqHbsWNkbN8)` | Calendario `novavision.contact@gmail.com`. OK. |
| 7 | `Creat event1` | googleCalendarTool | Crea evento con Google Meet | `Google Calendar (qyWKJIqHbsWNkbN8)` | Genera link de Meet automáticamente ✅. Depende del JSON que genera el LLM → frágil si el modelo no lo produce exacto. |
| 8 | `Add data1` | googleSheetsTool | Registra turno en spreadsheet "turnos" | `Google Sheets (4sWYTGtyCqs604Mk)` | Sheet ID hardcodeado. Sin dedup → si Calendar crea y Sheets falla, dato inconsistente. |
| — | Sticky Notes 5-9 | stickyNote | Documentación visual | — | Solo notas, sin impacto funcional |

### 2.2 Tabla de Problemas

| # | Problema | Evidencia | Impacto | Fix propuesto |
|---|---|---|---|---|
| **P1** | **Link de registro sin reemplazar** | System prompt: `[AQUI_TU_LINK_DE_REGISTRO]` | Usuarios Starter/Growth reciben un placeholder en vez del link real → pierden leads | Reemplazar por `https://novavision.lat/builder` |
| **P2** | **GPT-3.5-turbo deprecado** | `"value": "gpt-3.5-turbo"` | Modelo legacy, menor calidad, OpenAI puede retirarlo | Migrar a `gpt-4o-mini` (igual o menor costo, superior calidad) |
| **P3** | **maxTokens=200 insuficiente** | `"maxTokens": 200` | Respuestas cortadas, información incompleta en planes o features | Subir a 600-800 (cubre respuestas complejas sin explotar costos) |
| **P4** | **Sin manejo de errores** | No hay Error Workflow ni branches de error | Si Calendar/Sheets falla → error silencioso, turno perdido | Agregar Error Workflow con notificación + dead-letter |
| **P5** | **Sin anti-spam** | Chat público sin rate limit ni captcha | Bots pueden bombardear el endpoint → costos OpenAI + ruido | Rate limit por IP (en Railway/Cloudflare) + detección de spam en prompt |
| **P6** | **Sin deduplicación** | No hay lógica de dedup | Usuario que reintenta → múltiples turnos agendados | Hash de datos + check en Sheets antes de crear evento |
| **P7** | **Sin auditoría/logs** | No hay nodo de logging | No hay trazabilidad de conversaciones para mejora contínua | Agregar persistencia de sesiones (Sheets/Supabase) |
| **P8** | **Calendly duplica Calendar** | Ya tienen `https://calendly.com/novavision-contact/30min` configurado | 2 sistemas de agenda en paralelo → confusión, conflictos de horarios | Decidir: ¿Calendar via chatbot O Calendly? Recomiendo Calendly (más robusto, auto-maneja disponibilidad) |
| **P9** | **Sin correlationId** | No hay tracking por sesión | No se puede trazar un lead desde chat → evento → sheet | Generar UUID al inicio de sesión |
| **P10** | **Credenciales OAuth pueden expirar** | Calendar + Sheets usan OAuth2 | Si expiran → flujo muere silenciosamente | Configurar alerta de refresh token + test periódico |

### 2.3 Diagnóstico del Formulario de Contacto (Storefronts)

| # | Problema | Evidencia | Impacto | Fix propuesto |
|---|---|---|---|---|
| **F1** | **Sin persistencia** | EmailJS solo envía email, no guarda nada | Si el email falla → mensaje perdido para siempre | Migrar a webhook n8n con persistencia en DB |
| **F2** | **Sin multi-tenant** | Todas las tiendas usan las mismas credenciales EmailJS (`service_fypyscx`) | Todos los mensajes van al equipo NV, no al dueño de la tienda | Agregar `client_id` al payload → routing condicional |
| **F3** | **Template 4 no funciona** | `alert("Formulario enviado!")` | Usuarios de ese template pierden todos los mensajes | Unificar todos los templates con el mismo webhook |
| **F4** | **Credenciales expuestas** | `VITE_EMAILJS_PUBLIC_KEY=JzeKVwvKUxAkQ-9GF` en `.env` (Vite las expone en el bundle) | Las public keys son diseñadas para ser públicas, pero combinadas con service ID permiten spam | Migrar a backend → eliminar EmailJS del frontend |
| **F5** | **Sin validación server-side** | Solo `react-hook-form` en el cliente | Cualquiera puede enviar payload malformado directo al EmailJS | Validar en el webhook n8n |
| **F6** | **Sin rate limit** | No hay throttling | Bot puede enviar miles de emails | Rate limit en webhook |
| **F7** | **Sin tags/clasificación** | No se categoriza el mensaje | No se puede priorizar ventas vs soporte | Auto-tag en n8n con keywords |

---

## 3. Diseño del Flujo Objetivo

### 3.1 Arquitectura General (2 workflows)

```
┌─────────────────────────────────────────────────────────┐
│  WORKFLOW 1: CHATBOT (EXISTENTE — MEJORAR)              │
│  Trigger: Chat Widget (novavision.lat)                   │
│  → Ya funciona, aplicar fixes P1-P10                     │
└─────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────┐
│  WORKFLOW 2: CONTACT FORM (NUEVO — CREAR)               │
│  Trigger: Webhook POST desde storefronts                 │
│  → Reemplaza EmailJS                                     │
│  → Toda la lógica de validación/routing/notificación     │
└─────────────────────────────────────────────────────────┘
```

### 3.2 Workflow 2: Contact Form — Diagrama del Flujo

```
                    ┌──────────────────────┐
                    │   A. WEBHOOK TRIGGER  │
                    │   POST /contact-form  │
                    │   + Respond to Webhook│
                    │   (ACK inmediato)     │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  B. GENERATE IDs      │
                    │  correlationId (UUID) │
                    │  timestamp ISO        │
                    │  extract IP/UA/ref    │
                    └──────────┬───────────┘
                               │
                    ┌──────────▼───────────┐
                    │  C. VALIDATE PAYLOAD  │
                    │  - email format       │
                    │  - required fields    │
                    │  - sanitize strings   │
                    │  - trim/normalize     │
                    └───┬──────────────┬───┘
                        │              │
                   ✅ Valid        ❌ Invalid
                        │              │
                        │    ┌─────────▼─────────┐
                        │    │ D. LOG REJECTED    │
                        │    │ (Supabase: status  │
                        │    │  = "rejected")     │
                        │    │ → END              │
                        │    └───────────────────┘
                        │
             ┌──────────▼───────────┐
             │  E. ANTI-SPAM CHECK  │
             │  - honeypot field    │
             │  - link density      │
             │  - rate limit check  │
             │  (IP+email window)   │
             └───┬─────────────┬───┘
                 │             │
            ✅ Clean      🚫 Spam
                 │             │
                 │    ┌────────▼────────┐
                 │    │ F. LOG SPAM     │
                 │    │ status="spam"   │
                 │    │ → END           │
                 │    └────────────────┘
                 │
      ┌──────────▼───────────┐
      │  G. DEDUP CHECK      │
      │  SHA-256 hash of     │
      │  (email+msg+10min    │
      │   window)            │
      └───┬──────────────┬───┘
          │              │
     ✅ Unique     🔁 Duplicate
          │              │
          │    ┌─────────▼─────────┐
          │    │ H. LOG DUPLICATE  │
          │    │ status="duplicate"│
          │    │ → END             │
          │    └───────────────────┘
          │
┌─────────▼──────────┐
│  I. AUTO-TAG LEAD  │
│  Keywords →        │
│  venta/soporte/    │
│  partnership/otro  │
└─────────┬──────────┘
          │
┌─────────▼──────────┐
│  J. PERSIST (DB)   │
│  Supabase:         │
│  contact_leads     │
│  status="received" │
│  + correlationId   │
│  + tag + metadata  │
└─────────┬──────────┘
          │
┌─────────▼──────────────┐
│  K. NOTIFY INTERNAL    │
│  ┌───────────────────┐ │
│  │ Email to team     │ │
│  │ + Telegram bot    │ │
│  │ (formatted msg    │ │
│  │  with context)    │ │
│  └───────────────────┘ │
│  → Update status       │
│    = "notified"        │
└─────────┬──────────────┘
          │
┌─────────▼──────────┐
│  L. UPDATE STATUS  │
│  status="processed"│
│  processed_at = now│
└────────────────────┘

  ┌──────────────────────┐
  │  ERROR WORKFLOW       │
  │  (Branch paralela)    │
  │  → Log error + stack  │
  │  → Alerta Telegram    │
  │  → Dead-letter store  │
  └──────────────────────┘
```

### 3.3 Lista de Nodos n8n Propuestos

| # | Nodo | Tipo n8n | Propósito |
|---|---|---|---|
| 1 | `Webhook Contact Form` | `n8n-nodes-base.webhook` | POST trigger con path `/contact-form` |
| 2 | `ACK Response` | `n8n-nodes-base.respondToWebhook` | Respuesta inmediata `{ status: "received", correlationId }` |
| 3 | `Generate IDs & Metadata` | `n8n-nodes-base.code` | UUID, timestamp, extract headers (IP, UA, Referer) |
| 4 | `Validate Payload` | `n8n-nodes-base.code` | Validar email, required fields, sanitizar, normalizar |
| 5 | `IF Valid` | `n8n-nodes-base.if` | Branch: valid → continue, invalid → log rejected |
| 6 | `Log Rejected` | `n8n-nodes-base.supabase` | INSERT en `contact_leads` con status=rejected |
| 7 | `Anti-Spam Check` | `n8n-nodes-base.code` | Honeypot, link density, rate limit lookup |
| 8 | `IF Not Spam` | `n8n-nodes-base.if` | Branch: clean → continue, spam → log |
| 9 | `Log Spam` | `n8n-nodes-base.supabase` | INSERT con status=spam |
| 10 | `Dedup Check` | `n8n-nodes-base.code` + Supabase SELECT | Hash + query ventana temporal |
| 11 | `IF Unique` | `n8n-nodes-base.if` | Branch: unique → persist, duplicate → log |
| 12 | `Log Duplicate` | `n8n-nodes-base.supabase` | INSERT con status=duplicate |
| 13 | `Auto-Tag Lead` | `n8n-nodes-base.code` | Keyword matching para tag (venta/soporte/partnership) |
| 14 | `Persist Lead` | `n8n-nodes-base.supabase` | INSERT en `contact_leads` con status=received + todo el contexto |
| 15 | `Send Email Notification` | `n8n-nodes-base.emailSend` | Email formateado al equipo |
| 16 | `Send Telegram Notification` | `n8n-nodes-base.telegram` | Mensaje Telegram con resumen |
| 17 | `Update Status Processed` | `n8n-nodes-base.supabase` | UPDATE status=processed |
| 18 | `Error Trigger` | `n8n-nodes-base.errorTrigger` | Captura errores de cualquier nodo |
| 19 | `Log Error` | `n8n-nodes-base.supabase` | INSERT en `contact_leads_errors` |
| 20 | `Alert Error Telegram` | `n8n-nodes-base.telegram` | Alerta de error al equipo |

---

## 4. Contrato de Payload (Frontend → Webhook)

### 4.1 Request

```
POST https://n8n-production-6cac.up.railway.app/webhook/contact-form
Content-Type: application/json
X-NV-Shared-Secret: <shared_secret>   ← validación de origen

{
  "fullName": "Juan Pérez",
  "email": "juan@example.com",
  "phone": "+5491130001234",          // opcional
  "company": "Mi Negocio SRL",        // opcional
  "message": "Quiero saber sobre el plan Growth...",
  "pageUrl": "https://mi-tienda.novavision.lat/contacto",
  "referrer": "https://google.com",   // document.referrer
  "clientId": "1fad8213-...",          // UUID del tenant
  "clientSlug": "mi-tienda",          // slug del tenant
  "honeypot": "",                      // campo oculto, si tiene valor → spam
  "consentAccepted": true,             // GDPR/disclaimer
  "timestamp": "2026-03-03T14:30:00-03:00"
}
```

### 4.2 Response (ACK inmediato)

```json
{
  "status": "received",
  "correlationId": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "message": "Tu mensaje fue recibido. Te contactaremos a la brevedad."
}
```

### 4.3 Errores

```json
// 400 - Validación
{ "status": "error", "code": "VALIDATION_FAILED", "details": ["email format invalid"] }

// 429 - Rate limit
{ "status": "error", "code": "RATE_LIMITED", "message": "Demasiados mensajes. Intentá en unos minutos." }

// 403 - Auth
{ "status": "error", "code": "UNAUTHORIZED", "message": "Request no autorizado." }
```

---

## 5. Implementación Concreta — Nodo por Nodo

### Nodo 1: Webhook Trigger

```json
{
  "name": "Webhook Contact Form",
  "type": "n8n-nodes-base.webhook",
  "parameters": {
    "httpMethod": "POST",
    "path": "contact-form",
    "responseMode": "responseNode",
    "options": {
      "rawBody": false
    }
  }
}
```

**Nota:** `responseMode: "responseNode"` permite que el nodo `Respond to Webhook` envíe la respuesta, no este trigger.

### Nodo 2: Generate IDs & Metadata (Code Node)

```javascript
// Nodo: Generate IDs & Metadata
const crypto = require('crypto');

const correlationId = crypto.randomUUID();
const receivedAt = new Date().toISOString();

// Extraer headers
const headers = $input.first().json.headers || {};
const ip = headers['x-forwarded-for']
  || headers['x-real-ip']
  || headers['cf-connecting-ip']
  || 'unknown';
const userAgent = headers['user-agent'] || 'unknown';

// Extraer body
const body = $input.first().json.body || $input.first().json;

return [{
  json: {
    correlationId,
    receivedAt,
    ip: typeof ip === 'string' ? ip.split(',')[0].trim() : 'unknown',
    userAgent,
    // Payload
    fullName: body.fullName || '',
    email: body.email || '',
    phone: body.phone || '',
    company: body.company || '',
    message: body.message || '',
    pageUrl: body.pageUrl || '',
    referrer: body.referrer || '',
    clientId: body.clientId || '',
    clientSlug: body.clientSlug || '',
    honeypot: body.honeypot || '',
    consentAccepted: body.consentAccepted || false,
    clientTimestamp: body.timestamp || '',
    sharedSecret: headers['x-nv-shared-secret'] || '',
  }
}];
```

### Nodo 3: Validate & Sanitize (Code Node)

```javascript
// Nodo: Validate Payload
const d = $input.first().json;
const errors = [];

// -- Shared secret validation --
const EXPECTED_SECRET = 'NV_CONTACT_2026_SECURE'; // Configurar en n8n credentials/env
if (d.sharedSecret !== EXPECTED_SECRET) {
  return [{ json: { valid: false, reason: 'unauthorized', errors: ['Invalid shared secret'] } }];
}

// -- Honeypot --
if (d.honeypot && d.honeypot.trim() !== '') {
  return [{ json: { valid: false, reason: 'spam_honeypot', errors: ['Bot detected'] } }];
}

// -- Required fields --
if (!d.fullName || d.fullName.trim().length < 2) errors.push('fullName required (min 2 chars)');
if (!d.email) errors.push('email required');
if (!d.message || d.message.trim().length < 5) errors.push('message required (min 5 chars)');

// -- Email format --
const emailRegex = /^[^\s@]+@[^\s@]+\.[^\s@]{2,}$/;
if (d.email && !emailRegex.test(d.email.trim().toLowerCase())) {
  errors.push('email format invalid');
}

// -- Sanitize: strip HTML, limit lengths --
const sanitize = (str, maxLen = 500) => {
  if (!str) return '';
  return String(str)
    .replace(/<[^>]*>/g, '') // strip HTML
    .replace(/[<>]/g, '')    // extra safety
    .trim()
    .substring(0, maxLen);
};

// -- Normalize --
const normalized = {
  correlationId: d.correlationId,
  receivedAt: d.receivedAt,
  ip: d.ip,
  userAgent: sanitize(d.userAgent, 300),
  fullName: sanitize(d.fullName, 100),
  email: d.email?.trim().toLowerCase() || '',
  phone: sanitize(d.phone, 30).replace(/[^0-9+\-() ]/g, ''),
  company: sanitize(d.company, 150),
  message: sanitize(d.message, 2000),
  pageUrl: sanitize(d.pageUrl, 500),
  referrer: sanitize(d.referrer, 500),
  clientId: d.clientId || '',
  clientSlug: sanitize(d.clientSlug, 50),
  consentAccepted: Boolean(d.consentAccepted),
  clientTimestamp: d.clientTimestamp || '',
};

// -- Anti-spam: link density --
const linkCount = (normalized.message.match(/https?:\/\//gi) || []).length;
if (linkCount > 3) errors.push('Too many links in message');

// -- Anti-spam: suspicious patterns --
const spamPatterns = /\b(viagra|casino|crypto.*invest|buy.*followers|SEO.*service.*cheap)\b/i;
if (spamPatterns.test(normalized.message)) errors.push('Spam content detected');

// -- Message length sanity --
if (normalized.message.length > 2000) errors.push('Message too long (max 2000 chars)');

if (errors.length > 0) {
  return [{ json: { valid: false, reason: 'validation_failed', errors, ...normalized } }];
}

return [{ json: { valid: true, reason: 'ok', errors: [], ...normalized } }];
```

### Nodo 4: IF Valid (Switch)

- Condición: `{{ $json.valid }}` === `true`
- True → Dedup Check
- False → Respond Error + Log Rejected

### Nodo 5: ACK Response — Success (Respond to Webhook)

```json
{
  "respondWith": "json",
  "responseBody": "={{ JSON.stringify({ status: 'received', correlationId: $json.correlationId, message: 'Tu mensaje fue recibido. Te contactaremos a la brevedad.' }) }}",
  "responseCode": 200,
  "responseHeaders": {
    "Content-Type": "application/json",
    "X-Correlation-Id": "={{ $json.correlationId }}"
  }
}
```

**IMPORTANTE:** Este nodo va JUSTO DESPUÉS de la validación exitosa, ANTES de dedup/persist/notify.
Así el frontend recibe respuesta rápida sin esperar integraciones lentas.

### Nodo 5b: Error Response (Respond to Webhook)

```json
{
  "respondWith": "json",
  "responseBody": "={{ JSON.stringify({ status: 'error', code: $json.reason === 'unauthorized' ? 'UNAUTHORIZED' : 'VALIDATION_FAILED', details: $json.errors }) }}",
  "responseCode": "={{ $json.reason === 'unauthorized' ? 403 : 400 }}"
}
```

### Nodo 6: Dedup Check (Code Node)

```javascript
// Nodo: Dedup Check
// Genera hash y verifica contra Supabase en los últimos 10 minutos
const crypto = require('crypto');
const d = $input.first().json;

// Hash determinístico: email + message (normalizado)
const dedupPayload = `${d.email}|${d.message.replace(/\s+/g, ' ').toLowerCase()}`;
const dedupHash = crypto.createHash('sha256').update(dedupPayload).digest('hex');

// Ventana de deduplicación: 10 minutos
const windowStart = new Date(Date.now() - 10 * 60 * 1000).toISOString();

return [{ json: { ...d, dedupHash, dedupWindowStart: windowStart } }];
```

Luego un nodo **Supabase SELECT**:
```sql
SELECT id FROM contact_leads
WHERE dedup_hash = '{{ $json.dedupHash }}'
AND created_at > '{{ $json.dedupWindowStart }}'
LIMIT 1
```

### Nodo 7: Auto-Tag Lead (Code Node)

```javascript
// Nodo: Auto-Tag Lead
const d = $input.first().json;
const msg = `${d.message} ${d.company}`.toLowerCase();

let tag = 'general';
let priority = 'normal';

// Clasificación por keywords
const salesKeywords = /\b(precio|plan|demo|cotizaci[oó]n|presupuesto|contratar|enterprise|growth|starter|tienda|negocio|vender|costo|cuánto|cuanto|comprar|online)\b/i;
const supportKeywords = /\b(bug|error|problema|no funciona|soporte|ayuda|reclamo|falla|caído|caido|ticket|no carga|lento)\b/i;
const partnerKeywords = /\b(partner|alianza|integración|api|desarrollador|agencia|revender|white.?label)\b/i;

if (salesKeywords.test(msg)) {
  tag = 'ventas';
  priority = msg.includes('enterprise') ? 'high' : 'normal';
} else if (supportKeywords.test(msg)) {
  tag = 'soporte';
  priority = /\b(caído|no funciona|urgente)\b/i.test(msg) ? 'high' : 'normal';
} else if (partnerKeywords.test(msg)) {
  tag = 'partnership';
  priority = 'normal';
}

return [{ json: { ...d, tag, priority } }];
```

### Nodo 8: Persist Lead (Supabase INSERT)

Tabla: `contact_leads` (crear en Admin DB o Multicliente DB)

```sql
-- Migración SQL para crear la tabla
CREATE TABLE IF NOT EXISTS contact_leads (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  correlation_id UUID NOT NULL,
  dedup_hash TEXT NOT NULL,
  
  -- Datos del contacto
  full_name TEXT NOT NULL,
  email TEXT NOT NULL,
  phone TEXT,
  company TEXT,
  message TEXT NOT NULL,
  
  -- Contexto
  page_url TEXT,
  referrer TEXT,
  client_id UUID,          -- tenant (si aplica)
  client_slug TEXT,
  ip_address TEXT,
  user_agent TEXT,
  consent_accepted BOOLEAN DEFAULT false,
  
  -- Clasificación
  tag TEXT DEFAULT 'general',   -- ventas/soporte/partnership/general
  priority TEXT DEFAULT 'normal', -- normal/high
  
  -- Estado y tracking
  status TEXT DEFAULT 'received', -- received/notified/processed/spam/duplicate/rejected
  processed_at TIMESTAMPTZ,
  
  -- Timestamps
  client_timestamp TIMESTAMPTZ,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now(),
  
  -- Error info (si falló)
  error_details JSONB
);

-- Índices
CREATE INDEX idx_contact_leads_dedup ON contact_leads (dedup_hash, created_at);
CREATE INDEX idx_contact_leads_email ON contact_leads (email, created_at);
CREATE INDEX idx_contact_leads_status ON contact_leads (status);
CREATE INDEX idx_contact_leads_tag ON contact_leads (tag);
CREATE INDEX idx_contact_leads_client ON contact_leads (client_id);

-- RLS
ALTER TABLE contact_leads ENABLE ROW LEVEL SECURITY;

CREATE POLICY "server_bypass" ON contact_leads
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');

-- Solo super_admin puede leer leads
CREATE POLICY "leads_select_super" ON contact_leads
  FOR SELECT USING (
    EXISTS (SELECT 1 FROM users WHERE id = auth.uid() AND role = 'super_admin')
  );
```

### Nodo 9: Notify — Email (SMTP Send)

**Subject:** `[{{$json.tag.toUpperCase()}}] {{$json.priority === 'high' ? '🔴' : '🟢'}} Nuevo contacto: {{$json.fullName}}`

**Body (HTML):**
```html
<h2>📨 Nuevo Lead de Contacto</h2>
<table style="border-collapse:collapse; width:100%;">
  <tr><td><strong>Nombre</strong></td><td>{{$json.fullName}}</td></tr>
  <tr><td><strong>Email</strong></td><td><a href="mailto:{{$json.email}}">{{$json.email}}</a></td></tr>
  <tr><td><strong>Teléfono</strong></td><td>{{$json.phone || 'No proporcionado'}}</td></tr>
  <tr><td><strong>Empresa</strong></td><td>{{$json.company || 'No proporcionado'}}</td></tr>
  <tr><td><strong>Tag</strong></td><td>{{$json.tag}}</td></tr>
  <tr><td><strong>Prioridad</strong></td><td>{{$json.priority}}</td></tr>
  <tr><td><strong>Origen</strong></td><td>{{$json.pageUrl}}</td></tr>
  <tr><td><strong>Tenant</strong></td><td>{{$json.clientSlug || 'Sitio institucional'}}</td></tr>
</table>
<h3>Mensaje:</h3>
<blockquote>{{$json.message}}</blockquote>
<p><small>correlationId: {{$json.correlationId}} | IP: {{$json.ip}} | {{$json.receivedAt}}</small></p>
```

### Nodo 10: Notify — Telegram

**Chat ID:** configurar en credenciales.
**Message (Markdown):**

```
📨 *Nuevo Lead [{{$json.tag}}]*
{{$json.priority === 'high' ? '🔴 PRIORIDAD ALTA' : ''}}

👤 *{{$json.fullName}}*
📧 {{$json.email}}
📱 {{$json.phone || 'Sin teléfono'}}
🏢 {{$json.company || 'Sin empresa'}}
🏷️ Tag: {{$json.tag}}
🌐 Origen: {{$json.clientSlug || 'novavision.lat'}}

💬 _{{$json.message.substring(0, 300)}}{{$json.message.length > 300 ? '...' : ''}}_

🆔 `{{$json.correlationId}}`
```

### Nodo 11: Update Status → "processed"

Supabase UPDATE:
```
UPDATE contact_leads SET status = 'processed', processed_at = now()
WHERE correlation_id = '{{ $json.correlationId }}'
```

### Nodo 12: Error Workflow

```json
{
  "name": "Error Handler",
  "type": "n8n-nodes-base.errorTrigger"
}
```

→ Conecta a:
1. **Log Error en Supabase:** INSERT en `contact_leads` con `status='error'`, `error_details=<stack>`
2. **Alerta Telegram:** `🚨 ERROR en Contact Form workflow\nCorrelationId: ...\nError: ...\nNodo: ...`

---

## 6. Fixes para el Chatbot Existente (Quick Wins)

### Fix P1: Reemplazar placeholder del link

En el System Prompt del nodo `AI Agent1`, reemplazar:
```
[AQUI_TU_LINK_DE_REGISTRO]
```
por:
```
https://novavision.lat/builder
```

### Fix P2: Migrar modelo

En nodo `OpenAI Chat Model1`:
```json
"model": "gpt-4o-mini"      // antes: gpt-3.5-turbo
```

### Fix P3: Subir maxTokens

```json
"maxTokens": 700            // antes: 200
```

### Fix P8: Resolución Calendly vs Calendar

**Recomendación:** Usar **Calendly** como único sistema de agenda.

Motivo:
- Calendly ya maneja disponibilidad, buffering, reminders, y cancellations automáticamente
- Google Calendar via n8n es frágil (depende del JSON exacto del LLM)
- Calendly genera su propio link de Meet/Zoom
- Reduce complejidad del chatbot

**Cambio en System Prompt:**
```
🚀 Flujo de Videollamada (SOLO PARA PLAN ENTERPRISE)
Si el perfil es Enterprise y quiere agendar, pasale directamente este link de Calendly:
https://calendly.com/novavision-contact/30min

IMPORTANTE: NO intentes crear eventos. Solo pasale el link y explicale que ahí puede elegir día y horario disponible.
```

Si se migra a Calendly, se pueden **eliminar** los nodos:
- `Check Availability1`
- `Creat event1`
- `Add data1` (la Sheet)

Esto simplifica el workflow dramáticamente y elimina riesgos de OAuth vencido + JSON mal formado.

---

## 7. Cambios en Frontend (Storefronts)

Para conectar los formularios de contacto al nuevo webhook n8n, reemplazar EmailJS con:

```javascript
// Nuevo: enviar a n8n webhook en vez de EmailJS
const CONTACT_WEBHOOK_URL = import.meta.env.VITE_CONTACT_WEBHOOK_URL
  || 'https://n8n-production-6cac.up.railway.app/webhook/contact-form';
const CONTACT_SHARED_SECRET = import.meta.env.VITE_CONTACT_SHARED_SECRET;

async function submitContactForm(data, clientId, clientSlug) {
  const response = await fetch(CONTACT_WEBHOOK_URL, {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'X-NV-Shared-Secret': CONTACT_SHARED_SECRET,
    },
    body: JSON.stringify({
      fullName: data.name || `${data.name} ${data.surname || ''}`.trim(),
      email: data.email,
      phone: data.cellphone || data.number || '',
      company: '',
      message: data.message || data.description || '',
      pageUrl: window.location.href,
      referrer: document.referrer,
      clientId: clientId,
      clientSlug: clientSlug,
      honeypot: data._hp || '',           // campo oculto en el form
      consentAccepted: true,
      timestamp: new Date().toISOString(),
    }),
  });

  if (!response.ok) {
    const err = await response.json().catch(() => ({}));
    throw new Error(err.message || `HTTP ${response.status}`);
  }

  return response.json();
}
```

**Agregar campo honeypot oculto en cada form:**
```jsx
{/* Honeypot - invisible para usuarios, visible para bots */}
<input
  type="text"
  name="_hp"
  style={{ position: 'absolute', left: '-9999px', opacity: 0 }}
  tabIndex={-1}
  autoComplete="off"
  {...register('_hp')}
/>
```

---

## 8. Runbook

### 8.1 Deploy del workflow

1. Abrir n8n: `https://n8n-production-6cac.up.railway.app`
2. Crear nuevo workflow "Contact Form Handler"
3. Importar nodos según diseño (o crear manualmente)
4. Configurar credenciales:
   - Supabase (Admin o Multicliente) con service_role_key
   - SMTP (o SendGrid/Resend)
   - Telegram Bot (BotFather → nuevo bot → token)
5. Ejecutar migración SQL en la DB
6. Activar workflow
7. Probar con curl (ver abajo)

### 8.2 Test Manual

```bash
# Caso feliz
curl -X POST https://n8n-production-6cac.up.railway.app/webhook/contact-form \
  -H "Content-Type: application/json" \
  -H "X-NV-Shared-Secret: NV_CONTACT_2026_SECURE" \
  -d '{
    "fullName": "Test User",
    "email": "test@example.com",
    "phone": "+5491130001234",
    "company": "Test Corp",
    "message": "Quiero saber sobre el plan Growth",
    "pageUrl": "https://test.novavision.lat/contacto",
    "referrer": "",
    "clientId": "",
    "clientSlug": "test-store",
    "honeypot": "",
    "consentAccepted": true,
    "timestamp": "'$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")'"
  }'

# Esperar: 200 + { status: "received", correlationId: "..." }
```

```bash
# Caso spam (honeypot)
curl -X POST ... \
  -d '{ ..., "honeypot": "I am a bot", ... }'
# Esperar: 400 + { status: "error", code: "VALIDATION_FAILED" }

# Caso duplicate (enviar 2 veces en <10 min con mismo email+message)
# Esperar: segundo request → status "received" (se loguea como duplicate pero no notifica)

# Caso sin shared secret
curl -X POST ... (sin header X-NV-Shared-Secret)
# Esperar: 403 + { code: "UNAUTHORIZED" }

# Caso rate limit (enviar 5+ en 5 min desde mismo email)
# Esperar: 429 o se loguea como rate_limited
```

### 8.3 Monitoreo

```sql
-- Leads del último día
SELECT tag, status, COUNT(*), MIN(created_at), MAX(created_at)
FROM contact_leads
WHERE created_at > now() - interval '1 day'
GROUP BY tag, status
ORDER BY COUNT(*) DESC;

-- Leads pendientes (no procesados)
SELECT * FROM contact_leads
WHERE status NOT IN ('processed', 'spam', 'duplicate', 'rejected')
AND created_at > now() - interval '1 hour'
ORDER BY created_at DESC;

-- Errores recientes
SELECT * FROM contact_leads
WHERE status = 'error'
ORDER BY created_at DESC
LIMIT 20;
```

---

## 9. Plan de Pruebas

| # | Caso | Input | Expected | Verificar |
|---|---|---|---|---|
| 1 | **Happy path** | Payload válido completo | 200 + correlationId + lead en DB + email + telegram | Todo el flujo end-to-end |
| 2 | **Campos mínimos** | Solo fullName, email, message | 200 + lead guardado sin phone/company | Normalización OK |
| 3 | **Email inválido** | `email: "notanemail"` | 400 VALIDATION_FAILED | No se persiste en DB |
| 4 | **Honeypot** | `honeypot: "bot text"` | 400, status=spam en DB | Log spam sin notificar |
| 5 | **Spam content** | message con "buy followers cheap" | 400, status=spam | Detección de patterns |
| 6 | **Muchos links** | message con 5+ URLs | 400, status=spam | Link density check |
| 7 | **Duplicado** | Mismo email+message en <10 min | 200 (ACK), pero status=duplicate en DB, sin notificación | Dedup hash funciona |
| 8 | **Sin shared secret** | Sin header `X-NV-Shared-Secret` | 403 UNAUTHORIZED | No se procesa |
| 9 | **Secret incorrecto** | Header con valor incorrecto | 403 UNAUTHORIZED | No se procesa |
| 10 | **HTML injection** | `message: "<script>alert(1)</script>"` | 200, message sanitizado sin tags | XSS prevenido |
| 11 | **Mensaje largo** | message de 5000 chars | 200, truncado a 2000 | Límite respetado |
| 12 | **Auto-tag ventas** | message: "quiero saber el precio" | tag=ventas | Keyword matching |
| 13 | **Auto-tag soporte** | message: "mi tienda no carga" | tag=soporte | Keyword matching |
| 14 | **Auto-tag enterprise** | message: "plan enterprise" | tag=ventas, priority=high | Priority upgrade |
| 15 | **Email/Telegram down** | Simular timeout (desconectar cred) | Lead en DB con status=error + alerta | Error workflow activa |
| 16 | **Supabase down** | Simular error de DB | Error capturado + dead-letter | Error workflow + log |
| 17 | **Rate limit** | 10 requests en 5 min desde mismo email | Últimos N rechazados como rate_limited | Protección anti-abuso |
| 18 | **CORS preflight** | OPTIONS request | 204 con headers correctos | CORS configurado |
| 19 | **Consent false** | `consentAccepted: false` | 200 pero log warning | Se guarda el valor |
| 20 | **Multi-tenant** | Con clientId + clientSlug | Lead asociado al tenant | Filtro por client_id |

---

## 10. Checklist de Seguridad

- [ ] Shared secret en header (no en body ni query params)
- [ ] Shared secret almacenado en n8n credentials/env, no hardcodeado en nodos
- [ ] No loguear PII sensible (no incluir email/phone en logs de error a Telegram; sí el correlationId)
- [ ] Webhook URL no predecible (usar path custom, no el auto-generado por n8n)
- [ ] Rate limit por IP y por email
- [ ] Honeypot para bots
- [ ] Input sanitization (strip HTML, limit lengths)
- [ ] CORS: `allowedOrigins` restrictivo (solo dominios `*.novavision.lat`)
- [ ] RLS en tabla `contact_leads`: solo `service_role` puede escribir, solo `super_admin` puede leer
- [ ] No exponer stack traces en respuestas HTTP al frontend
- [ ] Credenciales OAuth (Calendar/Sheets) tienen refresh token monitoring
- [ ] Auditoría: toda acción queda con correlationId, timestamp, IP

---

## 11. Extras (Optimización de Ventas)

### 11.1 Auto-respuesta al usuario

Opcional: enviar email de confirmación al contacto.

**Template sugerido:**
```
Subject: Recibimos tu mensaje — NovaVision
Body:
Hola {{fullName}},

Gracias por contactarnos. Recibimos tu mensaje y lo estamos revisando.

⏰ No prometemos tiempos exactos, pero hacemos nuestro mejor esfuerzo para responder rápido.

📱 Si tu consulta es urgente, podés escribirnos por WhatsApp: +54 9 11 3930-6801

Referencia de tu consulta: {{correlationId}}

Saludos,
Equipo NovaVision
---
Este es un mensaje automático. No respondas a este email.
```

### 11.2 Dashboard de Leads (SQL views)

```sql
-- View: leads por día y tag
CREATE VIEW v_leads_daily AS
SELECT
  date_trunc('day', created_at) AS day,
  tag,
  status,
  COUNT(*) as count
FROM contact_leads
WHERE status NOT IN ('spam', 'rejected')
GROUP BY 1, 2, 3
ORDER BY 1 DESC, 2;

-- View: leads por cliente (multi-tenant)
CREATE VIEW v_leads_by_client AS
SELECT
  client_slug,
  tag,
  COUNT(*) as total,
  COUNT(*) FILTER (WHERE status = 'processed') as processed,
  COUNT(*) FILTER (WHERE created_at > now() - interval '7 days') as last_7d
FROM contact_leads
WHERE status NOT IN ('spam', 'rejected', 'duplicate')
GROUP BY 1, 2
ORDER BY total DESC;
```

### 11.3 Integración CRM futura

El correlationId y la tabla `contact_leads` permiten integrar con cualquier CRM (HubSpot, Pipedrive) agregando un nodo HTTP Request después del persist. El auto-tag ya clasifica el lead para el pipeline correcto.

---

## 12. Priorización Recomendada

| Fase | Qué hacer | Esfuerzo | Impacto |
|------|-----------|----------|---------|
| **Fase 0 (Hoy)** | Fix P1 (link placeholder) + Fix P2 (modelo) + Fix P3 (tokens) en chatbot | 5 min | Alto — se pierden leads ahora mismo |
| **Fase 1 (1-2 días)** | Fix P8 (migrar a Calendly, eliminar Calendar/Sheets del chatbot) | 30 min | Alto — elimina fragilidad |
| **Fase 2 (2-3 días)** | Crear workflow Contact Form + migración DB + conectar 1 template de prueba | 4-6 hrs | Alto — elimina pérdida de mensajes |
| **Fase 3 (1 semana)** | Migrar todos los templates a webhook + eliminar EmailJS + env vars | 2-3 hrs | Medio — unifica canales |
| **Fase 4 (opcional)** | Auto-respuesta email + dashboard + CRM integration | 2-4 hrs | Medio — mejora ventas |

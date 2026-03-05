# Outreach Gateway Pattern — Arquitectura

> Fecha: 2025-07-18  
> Autor: agente-copilot  
> Rama: feature/automatic-multiclient-onboarding  

## Resumen

Implementación del **Gateway Pattern (Opción A)**: "n8n orquesta, backend valida, envía y persiste."

Se movieron todas las operaciones sensibles (envío de WhatsApp, persistencia en DB, lógica de cupones) de acceso directo por n8n a endpoints internos del backend NestJS. n8n solo lee payloads sanitizados y llama HTTP endpoints protegidos con HMAC-SHA256.

## Principio de Diseño

```
n8n orquesta    →  decide QUÉ hacer (flujo, decisiones, nodos)
backend valida  →  valida reglas y state machine
backend envía   →  envía WhatsApp, emails, etc.
backend persiste→  escribe en Supabase (Admin DB)
```

## Archivos Creados

### Módulo NestJS: `src/outreach/`

| Archivo | Propósito |
|---------|-----------|
| `outreach.module.ts` | Registro del módulo NestJS |
| `outreach.controller.ts` | 5 endpoints internos bajo `/internal/outreach/*` |
| `whatsapp-webhook.controller.ts` | Webhook público Meta WA bajo `/webhooks/whatsapp` |
| `outreach.service.ts` | Toda la lógica de negocio (~370 líneas) |
| `guards/hmac-internal.guard.ts` | Guard HMAC-SHA256 para autenticación n8n→backend |
| `decorators/internal-outreach.decorator.ts` | Decorator de metadata para rutas internas |
| `dto/outreach.dto.ts` | DTOs y interfaces para todos los endpoints |

### Modificados

| Archivo | Cambio |
|---------|--------|
| `app.module.ts` | Import OutreachModule + exclusiones de AuthMiddleware |

## Endpoints

### Internos (HMAC Guard)

| Método | Path | Propósito |
|--------|------|-----------|
| POST | `/internal/outreach/leads/claim` | Reclamar leads para seed o followup |
| POST | `/internal/outreach/attempt/commit` | Enviar WA + persistir intento |
| POST | `/internal/outreach/offers/evaluate` | Evaluar elegibilidad de cupón |
| POST | `/internal/outreach/offers/commit` | Confirmar cupón ofrecido |
| POST | `/internal/outreach/onboarding/start` | Bridge a `/onboarding/builder/start` |

### Públicos

| Método | Path | Propósito |
|--------|------|-----------|
| GET | `/webhooks/whatsapp` | Verification challenge de Meta |
| POST | `/webhooks/whatsapp` | Recibir mensajes entrantes de WA |

## Autenticación

### Endpoints Internos (/internal/outreach/*)

**HMAC-SHA256** con headers requeridos:
- `X-NV-Timestamp`: unix epoch en ms
- `X-NV-Signature`: `sha256=<hex>` donde hex = HMAC_SHA256(secret, payload)
- `X-Correlation-Id`: UUID para trazabilidad
- `Idempotency-Key`: (opcional) para operaciones idempotentes

**Payload para firma:**
```
timestamp + "\n" + METHOD + "\n" + path + "\n" + SHA256(rawBody)
```

**Ventana de validez:** 5 minutos (configurable vía `N8N_HMAC_WINDOW_MS`).

### Webhook WhatsApp (/webhooks/whatsapp)

- GET: Validación de `hub.verify_token` vs `WHATSAPP_VERIFY_TOKEN`
- POST: Validación de `x-hub-signature-256` con `WHATSAPP_APP_SECRET`

## State Machine

```
NEW → CONTACTED → IN_CONVERSATION → QUALIFIED → ONBOARDING → WON
                                              ↓
                                           COLD / LOST / DISCARDED
```

**Transiciones válidas:**
```typescript
NEW           → [CONTACTED, DISCARDED]
CONTACTED     → [IN_CONVERSATION, COLD, LOST, DISCARDED]
IN_CONVERSATION → [QUALIFIED, COLD, LOST, DISCARDED]
QUALIFIED     → [ONBOARDING, COLD, LOST, DISCARDED]
COLD          → [CONTACTED, DISCARDED]
ONBOARDING    → [WON, LOST, DISCARDED]
```

WON y DISCARDED son terminales (sin transiciones de salida).

## Variables de Entorno Nuevas

| Variable | Requerido | Default | Descripción |
|----------|-----------|---------|-------------|
| `N8N_INTERNAL_SECRET` | ✅ | — | Secreto compartido para HMAC entre n8n y backend |
| `N8N_HMAC_WINDOW_MS` | ❌ | `300000` | Ventana de validez del timestamp (5 min) |
| `N8N_INBOUND_WEBHOOK_URL` | ✅ | — | URL del webhook de n8n para mensajes entrantes sanitizados |
| `WHATSAPP_PHONE_NUMBER_ID` | ✅ | — | Phone Number ID de Meta Cloud API |
| `WHATSAPP_TOKEN` | ✅ | — | Token de acceso de Meta Cloud API |
| `WHATSAPP_APP_SECRET` | ✅ | — | App Secret de Meta para validar webhooks (x-hub-signature-256) |
| `WHATSAPP_VERIFY_TOKEN` | ✅ | — | Token de verificación para webhook subscribe de Meta |
| `WHATSAPP_API_VERSION` | ❌ | `v22.0` | Versión de la API de Meta |
| `SELF_URL` | ✅ | — | URL base del backend para llamadas a sí mismo (onboarding bridge) |

## Seguridad

- **Secretos nunca en n8n:** WA token, Supabase service key, etc. solo viven como env vars del backend
- **HMAC con timing-safe comparison:** Previene timing attacks
- **Ventana de timestamp:** Previene replay attacks
- **Validación de state machine:** El backend autoriza transiciones; n8n solo sugiere
- **Idempotencia:** Dedupe por wamid (inbound WA), por lead_id+coupon_id (offers)
- **Sanitización de inbound:** Solo se reenvía a n8n un payload limpio sin datos sensibles

## Tablas Utilizadas (Admin DB)

- `outreach_leads` — leads del pipeline
- `outreach_logs` — log de todas las interacciones
- `outreach_config` — configuración key/value con cache 60s
- `outreach_coupons` — cupones disponibles
- `outreach_coupon_offers` — ofertas de cupones realizadas

## Migración (Fases)

### Fase 0 — Proxy (actual)
Backend expone endpoints, n8n los llama. Coexisten con acceso directo de n8n a Supabase.

### Fase 1 — WA/Email pasa por backend
n8n deja de tener WHATSAPP_TOKEN. Todo envío pasa por `/internal/outreach/attempt/commit`.

### Fase 2 — Webhook WA en backend
Meta apunta a `backend/webhooks/whatsapp`. Backend recibe, persiste, y reenvía sanitizado a n8n.

### Fase 3 — Cupones + dynamic offers
n8n llama a `offers/evaluate` y `offers/commit` en lugar de acceder directo a tablas de cupones.

## Cómo Probar

```bash
# 1. Configurar env vars en .env o Railway
N8N_INTERNAL_SECRET=un-secreto-seguro-compartido
WHATSAPP_PHONE_NUMBER_ID=123456789
WHATSAPP_TOKEN=EAAxxxxxxx
WHATSAPP_APP_SECRET=xxxx
WHATSAPP_VERIFY_TOKEN=mi-verify-token
N8N_INBOUND_WEBHOOK_URL=https://n8n.example.com/webhook/inbound
SELF_URL=https://api.example.com

# 2. Levantar el backend
npm run start:dev

# 3. Test de health del endpoint (debería dar 403 sin HMAC)
curl -X POST http://localhost:3000/internal/outreach/leads/claim \
  -H "Content-Type: application/json" \
  -d '{"kind":"seed","batch_size":5}'
# → 403 Forbidden (sin HMAC headers)

# 4. Test con HMAC firmado (ver scripts/test-outreach-hmac.sh)
```

## Riesgos

1. **Raw body para HMAC**: NestJS necesita `rawBody: true` en bootstrap para que `req.rawBody` esté disponible. Verificar en `main.ts`.
2. **WhatsApp webhook**: Meta requiere respuesta HTTP 200 en < 20 segundos. El handler delega async a n8n después de persistir.
3. **Config cache**: Cache de 60s en outreach_config. Cambios de config tardan hasta 60s en reflejarse.

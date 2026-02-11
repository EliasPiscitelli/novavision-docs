# PR7: Observabilidad + Hardening — Shipping Module

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Commit:** `f8c504a`

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/shipping/dto/index.ts` | Reescrito con class-validator decorators |
| `src/shipping/providers/andreani.provider.ts` | Retry, timeout, webhook handler |
| `src/shipping/shipping.controller.ts` | 3 endpoints nuevos (webhook, sync, health) |
| `src/shipping/shipping.service.ts` | 3 métodos nuevos + ~230 líneas |

## Resumen de cambios

### 1. DTOs con class-validator

Todos los DTOs de shipping ahora tienen validación estricta:

- **Provider whitelist:** solo `manual`, `andreani`, `oca`, `correo_argentino`, `custom`
- **Status enum:** solo los 10 estados válidos de shipment
- **Tipos numéricos:** `@IsNumber()` + `@Min(0)` para cost
- **Nested validation:** `@ValidateNested()` + `@Type()` para `event` en UpdateShipmentDto
- **Boolean/Object:** campos explícitamente tipados

### 2. Retry + Timeout en Andreani

- **`fetchWithTimeout()`:** Cada request HTTP usa `AbortController` con timeout de 15s
- **`withRetry()`:** Retry con backoff exponencial (2 reintentos, base 500ms → 500ms, 1000ms)
- No reintenta errores 4xx (solo 5xx / network)
- Aplicado a: login, cotización, crear orden, consultar trazas

### 3. Webhook endpoint

```
POST /shipping/webhooks/:provider
```

- `@AllowNoTenant()` — no requiere contexto de tenant (el provider externo no lo tiene)
- El service busca el shipment por `tracking_code` + `provider`
- Merge idempotente de eventos (por `provider_event_id`)
- El provider de Andreani implementa `handleWebhook()` parseando su payload

### 4. Tracking sync

```
POST /shipping/orders/:orderId/sync-tracking
```

- Admin-only: refresca las trazas consultando el provider
- Merge inteligente: solo agrega eventos nuevos (filtra por provider_event_id)
- Actualiza status del shipment y sincroniza a la orden

### 5. Health check

```
GET /shipping/health
```

- `@AllowNoTenant()`
- Retorna: providers registrados, integraciones activas, shipments últimas 24h, shipments pendientes

## Endpoints nuevos

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/shipping/webhooks/:provider` | No (AllowNoTenant) | Recibe webhooks de providers |
| POST | `/shipping/orders/:orderId/sync-tracking` | Admin | Sync tracking desde provider |
| GET | `/shipping/health` | No (AllowNoTenant) | Health check del módulo |

## Cómo probar

### Health check
```bash
curl http://localhost:3001/shipping/health
```

### Sync tracking (requiere shipment con provider Andreani)
```bash
curl -X POST http://localhost:3001/shipping/orders/<ORDER_ID>/sync-tracking \
  -H "Authorization: Bearer <JWT_ADMIN>" \
  -H "x-client-id: <UUID>"
```

### Webhook simulado
```bash
curl -X POST http://localhost:3001/shipping/webhooks/andreani \
  -H "Content-Type: application/json" \
  -d '{"numeroDeEnvio":"360000012345","estado":"Entregado","fecha":"2026-02-11T14:00:00Z","motivo":"Entrega normal"}'
```

### Validación de DTOs (debería fallar con 400)
```bash
curl -X POST http://localhost:3001/shipping/integrations \
  -H "Authorization: Bearer <JWT>" \
  -H "x-client-id: <UUID>" \
  -H "Content-Type: application/json" \
  -d '{"provider": "invalido", "display_name": ""}'
```

## Notas de seguridad

- El webhook endpoint no valida firma (Andreani no envía firma HMAC). Se recomienda IP allowlist en proxy/CDN.
- El retry no reintenta errores 4xx para evitar loops en credenciales inválidas.
- El timeout previene que requests colgados bloqueen el event loop.

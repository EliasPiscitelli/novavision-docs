# PR6: Provider Andreani — Integración Shipping

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Commit:** `b06eb66`

## Archivos modificados

| Archivo | Acción |
|---------|--------|
| `src/shipping/providers/andreani.provider.ts` | **Nuevo** — Provider completo de Andreani |
| `src/shipping/providers/index.ts` | Modificado — exporta `AndreaniProvider` |
| `src/shipping/shipping.service.ts` | Modificado — registra `AndreaniProvider` en constructor |

## Resumen

Implementación completa del provider de envíos **Andreani** sobre la interfaz `ShippingProvider`:

### Funcionalidades

| Método | Endpoint Andreani | Descripción |
|--------|-------------------|-------------|
| `testConnection()` | `GET /login` | Valida credenciales con Basic auth |
| `quoteRates()` | `GET /v1/tarifas` | Cotización de envío por CP destino |
| `createShipment()` | `POST /v2/ordenes-de-envio` | Crea orden de envío, devuelve número y label |
| `getTracking()` | `GET /v1/envios/{num}/trazas` | Consulta eventos de tracking |

### Auth Flow

1. `GET /login` con header `Authorization: Basic base64(user:pass)`
2. La respuesta incluye header `x-authorization-token`
3. Ese token se usa en el header `x-authorization-token` de las demás llamadas

### Credenciales (almacenadas encriptadas en `shipping_integrations.credentials_enc`)

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `user` | string | Usuario de Andreani |
| `password` | string | Contraseña |
| `contrato_domicilio` | string | Nro de contrato a domicilio |
| `contrato_sucursal` | string? | Nro de contrato a sucursal |
| `codigo_cliente` | string | Código de cliente Andreani |
| `environment` | `'qa'` \| `'prod'` | Ambiente (default: `prod`) |

### Base URLs

- **QA:** `https://api.qa.andreani.com`
- **Prod:** `https://api.andreani.com`

### Mapeo de estados

Los estados de Andreani (en español descriptivo) se normalizan a `ShipmentStatus`:

| Andreani | → ShipmentStatus |
|----------|------------------|
| pendiente, creado | `pending` |
| recibido, admitido, retirado | `picked_up` |
| en tránsito, en camino, en sucursal | `in_transit` |
| en distribución | `out_for_delivery` |
| entregado, entrega efectiva | `delivered` |
| no entregado, visita infructuosa | `failed` |
| devuelto, devolución | `returned` |

### Fallback graceful

- Si no se pasan `origin`/`destination`, `createShipment()` opera en modo manual (solo tracking code/url)
- `quoteRates()` retorna `[]` en caso de error (no es crítico)
- `getTracking()` retorna `[]` si falla la consulta

## Por qué

Andreani es el carrier más usado en Argentina para e-commerce. Es el primer provider real (no manual) del sistema de envíos, permitiendo a los clientes NovaVision automatizar la creación de envíos, obtener etiquetas y tracking en tiempo real.

## Cómo probar

1. Crear una integración de tipo `andreani` con credenciales QA:
```bash
curl -X POST http://localhost:3001/shipping/integrations \
  -H "Authorization: Bearer <JWT>" \
  -H "x-client-id: <UUID>" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "andreani",
    "display_name": "Andreani QA",
    "credentials": {
      "user": "<USER_QA>",
      "password": "<PASS_QA>",
      "contrato_domicilio": "<CONTRATO>",
      "codigo_cliente": "<CODIGO>",
      "environment": "qa"
    }
  }'
```

2. Testear conexión:
```bash
curl -X POST http://localhost:3001/shipping/integrations/<ID>/test \
  -H "Authorization: Bearer <JWT>" \
  -H "x-client-id: <UUID>"
```

3. Para crear envío (requiere datos de dirección):
```bash
curl -X POST http://localhost:3001/shipping/orders/<ORDER_ID> \
  -H "Authorization: Bearer <JWT>" \
  -H "x-client-id: <UUID>" \
  -H "Content-Type: application/json" \
  -d '{"provider": "andreani"}'
```

## Notas de seguridad

- Las credenciales de Andreani se almacenan encriptadas (AES-256-GCM) via `EncryptionService`
- El token de sesión de Andreani es efímero (se obtiene por request, no se cachea)
- El environment `qa` permite pruebas sin impacto real

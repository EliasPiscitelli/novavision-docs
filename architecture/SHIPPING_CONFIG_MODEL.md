# Modelo de Configuración de Shipping — NovaVision

> Documento técnico: qué es DEFAULT, qué es OPCIONAL, qué es EXCLUYENTE.

---

## 1. Feature Gate (por plan)

| Feature | starter | growth | enterprise |
|---------|---------|--------|------------|
| `commerce.shipping` — Gestión de envíos (flat/zone, pickup, arrange) | ✅ | ✅ | ✅ |
| `commerce.shipping_api_providers` — Providers API (Andreani, OCA, Correo Arg.) | ❌ | ✅ | ✅ |

**Comportamiento:** Si un tenant con plan `starter` intenta crear una integración con provider API, recibe `403 FEATURE_GATED` con mensaje `"Integraciones con API de envío requieren plan Growth o superior."`.

---

## 2. Métodos de envío — OPCIONALES e INDEPENDIENTES

Cada tenant elige cuáles activar. Se pueden combinar libremente.

| Método | Campo DB | Default | Descripción |
|--------|----------|---------|-------------|
| **Delivery** | `delivery_enabled` | `false` | Envío a domicilio. Requiere config de pricing + zonas |
| **Pickup** | `pickup_enabled` | `false` | Retiro en local. Requiere `pickup_address` |
| **Arrange** | `arrange_enabled` | `false` | Coordinación vía WhatsApp/email |

### Comportamiento default (tenant nuevo)

- **Todos deshabilitados** → El checkout no muestra sección de envío.
- El admin activa los métodos que necesite desde **Panel Admin > Envío**.
- Al menos uno debe estar activo para que el buyer vea opciones de envío.

### Combinaciones válidas

| Delivery | Pickup | Arrange | Escenario |
|----------|--------|---------|-----------|
| ❌ | ❌ | ❌ | Sin envío configurado. Checkout sin paso de envío. |
| ✅ | ❌ | ❌ | Solo envío a domicilio |
| ❌ | ✅ | ❌ | Solo retiro en local |
| ❌ | ❌ | ✅ | Solo coordinación por WhatsApp |
| ✅ | ✅ | ❌ | Envío o retiro |
| ✅ | ❌ | ✅ | Envío o coordinación |
| ❌ | ✅ | ✅ | Retiro o coordinación |
| ✅ | ✅ | ✅ | Las 3 opciones disponibles |

---

## 3. Pricing Mode — MUTUAMENTE EXCLUYENTES

Cuando `delivery_enabled = true`, el tenant elige **exactamente uno** de estos modos para calcular el costo de envío:

| Modo | Valor DB | Disponible en | Descripción |
|------|----------|---------------|-------------|
| **Por zonas** | `zone` | Todos los planes | Costo fijo por zona geográfica (provincias/CPs). **Default** |
| **Costo fijo** | `flat` | Todos los planes | Un único costo para cualquier destino |
| **Provider API** | `provider_api` | Growth+ | Cotización automática via Andreani/OCA/Correo Arg. |

### Reglas de exclusión

- `zone`, `flat` y `provider_api` son **mutuamente excluyentes** — solo un modo activo a la vez.
- Si el tenant tiene plan `starter` y elige `provider_api`, el server rechaza con error.
- El campo `shipping_pricing_mode` en `client_shipping_settings` almacena el modo activo.
- Valores inválidos en `shipping_pricing_mode` son rechazados con `400 INVALID_PRICING_MODE`.

### Switch de modo: no hay pérdida de datos

- Al cambiar de `zone` a `flat`, las zonas no se eliminan — solo dejan de usarse en cotización.
- Al cambiar de `flat` a `zone`, el `flat_shipping_cost` se preserva.
- Esto permite experimentar sin perder configuración.

---

## 4. Envío Gratis — OPCIONAL (aplica sobre cualquier pricing mode)

| Campo | Default | Descripción |
|-------|---------|-------------|
| `free_shipping_enabled` | `false` | Si `true`, envío gratis cuando el subtotal supera el threshold |
| `free_shipping_threshold` | `0` | Monto mínimo para envío gratis. **Debe ser > 0 si enabled** |

- Compatible con `zone`, `flat` y `provider_api`.
- **Validación server:** Si `free_shipping_enabled = true` pero `threshold ≤ 0`, se rechaza con `400`.
- En el storefront, muestra banner: `"Sumá $X más para envío gratis"`.

---

## 5. Configuración por método — CONDICIONAL

### Delivery (solo si `delivery_enabled = true`)
| Campo | Obligatorio | Default |
|-------|-------------|---------|
| `shipping_pricing_mode` | Sí | `zone` |
| `shipping_label` | No | `"Envío a domicilio"` |
| `estimated_delivery_text` | No | `null` |
| `origin_address` (JSONB) | Solo si `provider_api` | `null` |

### Pickup (solo si `pickup_enabled = true`)
| Campo | Obligatorio | Default |
|-------|-------------|---------|
| `pickup_address` | **Sí** | `null` — validado en server |
| `pickup_label` | No | `"Retiro en local"` |
| `pickup_hours` | No | `null` |
| `pickup_instructions` | No | `null` |

### Arrange (solo si `arrange_enabled = true`)
| Campo | Obligatorio | Default |
|-------|-------------|---------|
| `arrange_label` | No | `"Coordinar con vendedor"` |
| `arrange_message` | No | `"Coordinamos el envío por WhatsApp"` |
| `arrange_whatsapp` | No | `null` — si no se provee, se muestra email |

---

## 6. Provider API — OPCIONAL (Growth+ only)

### Requisitos para usar `provider_api`:
1. Plan **Growth** o **Enterprise**
2. Al menos una **integración activa** en `shipping_integrations` (Andreani, OCA, Correo Argentino)
3. **Dirección de origen** (`origin_address`) completa: `street`, `city`, `state`, `zip` obligatorios
4. Credenciales de API del provider configuradas y testeadas (endpoint `POST /shipping/integrations/:id/test`)

### Providers soportados

| Provider | Provider Key | API | Capacidades |
|----------|-------------|-----|------------|
| Andreani | `andreani` | REST v1 | quoteRates, createShipment, getTracking, webhook |
| OCA | `oca` | SOAP | quoteRates, createShipment, getTracking, webhook |
| Correo Argentino | `correo_argentino` | REST | quoteRates, createShipment, getTracking, webhook |
| Manual | `manual` | — | Solo trackeo manual (no cotiza, no genera envío) |

### Weight (peso de productos)
- `products.weight_grams`: `INT`, nullable.
- Si un producto no tiene peso, se usa **500g por defecto** para cotizaciones API.
- Tooltip en el form de producto: _"Peso del producto en gramos. Necesario para calcular envío automático con transportistas. Si no se completa, se estima un peso por defecto."_

---

## 7. Tabla de Settings — Schema Completo

```
client_shipping_settings
├── id UUID (PK)
├── client_id UUID (FK → clients, UNIQUE)
│
│   ── Métodos (OPCIONALES, independientes) ──
├── delivery_enabled BOOL (default false)
├── pickup_enabled BOOL (default false)
├── arrange_enabled BOOL (default false)
│
│   ── Pricing mode (EXCLUYENTES, solo delivery) ──
├── shipping_pricing_mode TEXT ('zone' | 'flat' | 'provider_api', default 'zone')
├── flat_shipping_cost NUMERIC (default 0)
│
│   ── Free shipping (OPCIONAL) ──
├── free_shipping_enabled BOOL (default false)
├── free_shipping_threshold NUMERIC (default 0)
│
│   ── Labels (OPCIONALES, customizables) ──
├── shipping_label TEXT (default 'Envío a domicilio')
├── pickup_label TEXT (default 'Retiro en local')
├── arrange_label TEXT (default 'Coordinar con vendedor')
├── estimated_delivery_text TEXT (nullable)
│
│   ── Pickup config ──
├── pickup_address TEXT (nullable, obligatorio si pickup_enabled)
├── pickup_instructions TEXT (nullable)
├── pickup_hours TEXT (nullable)
│
│   ── Arrange config ──
├── arrange_message TEXT (default 'Coordinamos el envío por WhatsApp')
├── arrange_whatsapp TEXT (nullable)
│
│   ── Provider API config ──
├── origin_address JSONB (nullable, obligatorio si provider_api)
│   { street, city, state, zip, phone?, name? }
│
└── updated_at TIMESTAMPTZ
```

---

## 8. Lifecycle de una tienda nueva

```
1. Onboarding completo → provisioning worker
2. → Seed client_shipping_settings con TODOS los métodos DESHABILITADOS
3. Admin abre Panel > Envío
4. → Activa método(s): delivery, pickup, y/o arrange
5. → Configura pricing mode (zone/flat/provider_api)
6. → Si zone: crea zonas con provincias, CPs y costos
7. → Si flat: define costo fijo
8. → Si provider_api: configura dirección de origen + crea integración
9. → Opcionalmente activa envío gratis con threshold
10. Buyer en checkout → ve métodos habilitados → cotiza → checkout incluye shipping
```

---

## 9. Validaciones Server (resumen)

| Validación | Dónde | Qué rechaza |
|------------|-------|-------------|
| Pricing mode válido | `upsertSettings` | Valores distintos de `zone`/`flat`/`provider_api` → 400 |
| Origin address completo | `upsertSettings` | `provider_api` sin street/city/zip → 400 |
| Free shipping threshold | `upsertSettings` | `enabled=true` con `threshold ≤ 0` → 400 |
| Pickup address requerida | `upsertSettings` | `pickup_enabled=true` sin dirección → 400 |
| Feature gate providers | `createIntegration` | Plan starter con API provider → 403 |
| Zona sin match | `calculateDeliveryCost` | CP/provincia sin zona → 400 |
| Método deshabilitado | `validateMethodEnabled` | Método no habilitado → 400 |

---

## 10. Resumen ejecutivo

| Concepto | Clasificación | Nota |
|----------|--------------|------|
| Delivery / Pickup / Arrange | **OPCIONAL** (independiente) | Activar 0 a 3 |
| zone / flat / provider_api | **EXCLUYENTE** (uno a la vez) | Solo aplica a delivery |
| Envío gratis | **OPCIONAL** (aditivo) | Aplica sobre cualquier pricing mode |
| Labels personalizados | **OPCIONAL** (con default) | Se muestran en checkout |
| Weight de productos | **OPCIONAL** (con default 500g) | Solo necesario para provider_api |
| Integraciones de provider | **OPCIONAL** (Growth+ only) | Solo necesario para provider_api |
| Dirección de origen | **CONDICIONAL** | Obligatoria solo si provider_api activo |

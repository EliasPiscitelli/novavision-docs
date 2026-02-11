# Anexo: Validaciones Exhaustivas por Campo — Shipping V2

**Fecha:** 2026-02-11  
**Complementa:** `2026-02-11-shipping-v2-complete-plan.md`

---

## Principio Rector

> **Cada dato que se configura en el admin, se selecciona en el checkout, se persiste en la orden, se muestra en el OrderDetail, y se envía en el email.**
>
> Si un campo existe en algún punto del flujo, existe en TODOS.

---

## 1. Trazabilidad completa por dato

### Flujo de cada campo de shipping

```
Admin Config → DB Settings → Checkout UI → Request body → Pre-orden (insert) → 
  → Webhook confirm (update) → Email template → OrderDetail (buyer) → OrderDetail (admin)
```

Cada campo se valida en **7 puntos de control**:

| # | Punto | Responsable | Tipo |
|---|-------|-------------|------|
| P1 | **Admin Config** | Frontend admin (ShippingPanel) | UI validation |
| P2 | **API Save** | Backend endpoint (PUT /shipping/settings) | DTO + service |
| P3 | **Checkout UI** | Frontend buyer (CartPage steps) | UI validation |
| P4 | **API Checkout** | Backend (createPreferenceForPlan) | DTO + service |
| P5 | **DB Insert** | Backend (orders table insert/update) | Column constraint + NOT NULL |
| P6 | **Email Render** | Backend (buildOrderEmailData + renderOrderEmailHTML) | Template logic |
| P7 | **Frontend Display** | Web (OrderDetail, PaymentResultPage) | Render logic |

---

## 2. Configuración del Admin — `client_shipping_settings`

### Método: Retiro en Tienda (`pickup_enabled`)

| Campo | Obligatorio si `pickup_enabled=true` | Validación P1 (Admin UI) | Validación P2 (API) | Por qué |
|-------|--------------------------------------|--------------------------|---------------------|---------|
| `pickup_address` | **SÍ — EXCLUYENTE** | Disable "Guardar" si vacío. Error: "Ingresá la dirección de retiro" | `if (pickup_enabled && !pickup_address?.trim()) throw 400` | El comprador necesita saber DÓNDE retirar |
| `pickup_instructions` | **SÍ — EXCLUYENTE** | Disable "Guardar" si vacío. Error: "Ingresá horarios de retiro" | `if (pickup_enabled && !pickup_instructions?.trim()) throw 400` | El comprador necesita saber CUÁNDO retirar |
| `pickup_lat` | Opcional | Autocompletado desde mapa; si vacío, no se muestra mapa | No valida (geocoding es best-effort) | Mejora UX pero no bloquea |
| `pickup_lng` | Opcional | Mismo que lat | Mismo | Mejora UX pero no bloquea |

**Edge case validado:**
```
Escenario: Admin activa "Retiro en tienda" pero NO pone dirección
→ P1: Botón "Guardar" deshabilitado + mensaje inline "La dirección de retiro es obligatoria"
→ P2: Si llega al backend sin dirección → 400 BAD_REQUEST { code: 'PICKUP_ADDRESS_REQUIRED' }
→ P3: Imposible — el comprador nunca ve la opción pickup porque la configuración no se guardó
```

### Método: Coordinar por mensaje (`arrange_enabled`)

| Campo | Obligatorio si `arrange_enabled=true` | Validación P1 | Validación P2 | Por qué |
|-------|---------------------------------------|--------------|---------------|---------|
| `arrange_message` | No (tiene default: "Nos pondremos en contacto...") | Prefilled; si borra, vuelve al default | Coalesce a default si vacío | Siempre hay un mensaje para mostrar |
| `arrange_whatsapp` | Opcional | Si pone número, validar formato (+54...) | Regex optional: `^\+?\d{10,15}$` | Mejora UX si hay WA, pero no bloquea |

**Edge case validado:**
```
Escenario: Admin activa "Coordinar" sin WhatsApp ni mensaje custom
→ P1: OK — se guarda con el mensaje default
→ P6: Email muestra: "Coordinaremos la entrega por este medio."
→ P7: OrderDetail muestra: "El vendedor se comunicará para coordinar la entrega"
```

### Método: Envío a domicilio (`delivery_enabled`)

| Campo | Obligatorio si `delivery_enabled=true` | Validación P1 | Validación P2 | Por qué |
|-------|---------------------------------------|--------------|---------------|---------|
| `shipping_pricing_mode` | **SÍ — EXCLUYENTE** | Select required (default: 'manual') | Enum check: `['manual', 'flat', 'provider_api']` | Define cómo se cobra |
| `flat_shipping_cost` | **SÍ si mode='flat'** | Visible+required solo si flat. Min: 0. Error: "Ingresá un costo" | `if (mode === 'flat' && (cost === null || cost < 0)) throw 400` | El comprador necesita ver un precio |
| `default_delivery_days_min` | Recomendado | Default: 3. Input numérico ≥ 1 | `min >= 1, max >= min` | Mejora UX |
| `default_delivery_days_max` | Recomendado | Default: 7. Input numérico ≥ min | `max >= min` | Mejora UX |
| `free_shipping_threshold` | **SÍ si `free_shipping_enabled=true`** | Visible+required solo si toggle activo. Min: 1 | `if (free_shipping_enabled && threshold <= 0) throw 400` | threshold=0 significaría SIEMPRE gratis (probablemente error) |

**Validación cruzada de modos:**

| `shipping_pricing_mode` | Requiere zonas | Requiere provider activo | Requiere flat_cost |
|--------------------------|---------------|-------------------------|-------------------|
| `flat` | NO | NO | **SÍ** |
| `manual` (por zona) | **SÍ (≥1 zona activa)** | NO | NO |
| `provider_api` | NO | **SÍ (≥1 integración con quoteRates)** | NO |

```
Escenario: Admin elige mode='manual' pero no tiene ninguna zona creada
→ P1: Warning: "Creá al menos una zona de envío para poder cobrar"
→ P2: Se guarda el modo pero se loggea warning
→ P3: En checkout, si no matchea zona → se muestra "Envío no disponible para tu zona"
→ P4: API retorna quote con error: { available: false, reason: 'NO_ZONE_MATCH' }

Escenario: Admin elige mode='provider_api' pero no tiene Andreani/OCA activo
→ P1: Warning: "Configurá al menos un proveedor con tarifa automática"
→ P2: Se guarda pero loggea warning
→ P3: En checkout, si provider falla → fallback a flat_shipping_cost (si >0) o error
→ P4: API intenta quoteRates → catch → fallback o 422 UNPROCESSABLE
```

### Envío gratis

```
Escenario: Admin pone free_shipping_enabled=true, threshold=0
→ P1: Error inline: "El monto mínimo para envío gratis debe ser mayor a $0"
→ P2: 400 BAD_REQUEST { code: 'INVALID_FREE_SHIPPING_THRESHOLD' }

Escenario: Admin pone threshold=50000, subtotal del comprador = 50001
→ P4: shipping_cost = 0, etiqueta "Envío gratis"
→ P5: orders.shipping_cost = 0
→ P6: Email: "Envío: Gratis 🎉"
→ P7: OrderDetail: "Envío: Gratis"
```

---

## 3. Zonas de Envío — `shipping_zones`

| Campo | Obligatorio | Validación P1 (Admin) | Validación P2 (API) |
|-------|-------------|----------------------|---------------------|
| `name` | **SÍ** | Input required. Error: "Ingresá un nombre" | `if (!name?.trim()) throw 400` |
| `cost` | **SÍ** | Input numérico ≥ 0. Error: "Ingresá un costo" | `if (cost === null || cost < 0) throw 400` |
| `zip_codes` **O** `provinces` | **Al menos uno** | Si ambos vacíos: "Ingresá CPs o provincias" | `if (!zip_codes?.length && !provinces?.length) throw 400` |
| `delivery_days_min` | Opcional (default: global) | Input ≥ 1 si se completa | Coalesce a `client_shipping_settings.default_delivery_days_min` |
| `delivery_days_max` | Opcional (default: global) | Input ≥ min si se completa | Coalesce a `client_shipping_settings.default_delivery_days_max` |

**Edge case: Zonas solapadas:**
```
Escenario: Zona "CABA" (CP 1000-1499) y Zona "Capital" (CP 1000-1200) 
→ P2: Se permite (el admin decide el pricing por zona)
→ P4: Al cotizar, se usa la PRIMERA zona que matchee (por `position ASC`)
→ Recomendación P1: Warning si hay solapamiento: "Los CP 1000-1200 también están en 'CABA'"
```

**Edge case: CP del comprador no matchea ninguna zona:**
```
→ P3: "Envío no disponible para tu zona. Código postal: C1043"
→ P4: Response: { available: false, reason: 'NO_ZONE_MATCH', zip_code: 'C1043' }
→ El comprador NO puede proceder con "Envío a domicilio"
→ Puede elegir "Retiro" o "Coordinar" si están habilitados
```

---

## 4. Checkout del Comprador — Validación por Step

### Step 1: Selección de Método de Entrega

| Validación | Regla | Si falla |
|------------|-------|----------|
| ¿Hay al menos 1 método habilitado? | `delivery_enabled OR pickup_enabled OR arrange_enabled` | No se muestra step de envío (checkout sin shipping, como ahora) |
| ¿El comprador eligió un método? | `delivery_method != null` | Botón "Continuar" deshabilitado |
| Si solo hay 1 método | Auto-seleccionar ese método | Skip del step (UX: no preguntar lo obvio) |

**Edge case: Ningún método habilitado:**
```
Escenario: El admin deshabilitó los 3 métodos
→ P3: El checkout funciona como ahora (sin paso de envío)
→ P4: delivery_method = null, shipping_cost = 0
→ P5: Columnas de shipping quedan con defaults (null/0)
→ P6: Email muestra fallback: "Coordinaremos la entrega por este medio."
→ P7: OrderDetail no muestra sección de envío
```

### Step 2: Dirección (solo si method = 'delivery')

| Campo | Obligatorio | Validación P3 (Frontend) | Validación P4 (Backend) |
|-------|-------------|-------------------------|------------------------|
| `full_name` | **SÍ** | Input required. "Ingresá tu nombre completo" | `if (!full_name?.trim()) throw 400` |
| `street` | **SÍ** | Input required. "Ingresá la calle" | `if (!street?.trim()) throw 400` |
| `street_number` | **SÍ** | Input required. "Ingresá la altura" | `if (!street_number?.trim()) throw 400` |
| `floor_apt` | No | Libre | Sanitize |
| `city` | **SÍ** | Input required. "Ingresá la ciudad" | `if (!city?.trim()) throw 400` |
| `province` | **SÍ** | Select required. "Seleccioná la provincia" | Enum check (24 provincias AR) |
| `zip_code` | **SÍ** | Input required + format hint. "Ingresá el CP" | `if (!zip_code?.trim()) throw 400` Regex: `/^[A-Z]?\d{4}[A-Z]{0,3}$/i` |
| `phone` | **SÍ** | Input required. "Ingresá tu teléfono" | Regex: `/^\+?\d{8,15}$/` |
| `country` | No (default 'AR') | Hidden, hardcodeado | Default 'AR' |
| `notes` | No | Textarea libre (max 500 chars) | Max 500, sanitize |
| `lat`/`lng` | No | Auto-filled por geocoding; si falla, OK | Opcionales

**Edge case: Dirección no valida con Nominatim:**
```
Escenario: El comprador pone "Calle inventada 999, Localidad X"
→ P3: Nominatim no devuelve resultado → NO bloquea, se muestra warning:
      "No pudimos verificar la dirección. Asegurate de que sea correcta."
→ P4: Address se acepta sin lat/lng → se guarda en la orden tal cual
→ P6: Email muestra la dirección ingresada por el comprador
→ DECISIÓN: NO bloquear checkout por geocoding fallido (muchas calles válidas no están en OSM)
```

**Edge case: Nominatim rate limit (>1 req/sec):**
```
→ P3: Frontend debounce 500ms + retry 1 vez → si falla, disable autocomplete
→ P3: El comprador puede completar manualmente sin autocomplete
→ NO se bloquea ninguna operación
```

### Step 2b: Dirección para method = 'pickup'

**NO se pide dirección al comprador.** Se muestra la dirección de retiro del admin:

```
┌─────────────────────────────────────────────────────┐
│ 🏪 Retiro en tienda                                 │
│                                                       │
│ 📍 Av. Corrientes 1234, CABA                        │  ← De client_shipping_settings.pickup_address
│ 🕐 Lunes a viernes de 9 a 18hs                      │  ← De client_shipping_settings.pickup_instructions
│                                                       │
│ [🗺️ Ver en mapa]  (si hay lat/lng)                   │
└─────────────────────────────────────────────────────┘
```

| Campo mostrado | Fuente | Obligatorio en config |
|----------------|--------|----------------------|
| Dirección | `pickup_address` | **SÍ** |
| Horarios | `pickup_instructions` | **SÍ** |
| Mapa | `pickup_lat/lng` | No |

### Step 2c: Info para method = 'arrange'

```
┌─────────────────────────────────────────────────────┐
│ 💬 Coordinar con el vendedor                         │
│                                                       │
│ "Nos pondremos en contacto para coordinar la entrega" │  ← De client_shipping_settings.arrange_message
│                                                       │
│ [📱 Contactar por WhatsApp]  (si hay WA)              │
└─────────────────────────────────────────────────────┘
```

---

## 5. Request de Checkout → Backend

### Payload de `POST /mercadopago/create-preference-for-plan`

```typescript
// Nuevo campo "delivery" en el body
interface CreatePreferenceBody {
  baseAmount: number;
  selection: PaymentSelection;
  cartItems: CartItem[];
  delivery?: {                           // ← NUEVO (nullable si no hay shipping config)
    method: 'delivery' | 'pickup' | 'arrange';
    address?: ShippingAddressInput;      // Solo si method='delivery'
    save_address?: boolean;              // Guardar para futuras compras
    address_id?: string;                 // UUID si usa dirección guardada
  };
}

interface ShippingAddressInput {
  full_name: string;    // required
  street: string;       // required
  street_number: string; // required
  floor_apt?: string;
  city: string;          // required
  province: string;      // required (enum 24 provincias)
  zip_code: string;      // required
  phone: string;         // required
  country?: string;      // default 'AR'
  lat?: number;
  lng?: number;
  notes?: string;        // max 500
}
```

### Validación P4 completa en el backend

```typescript
// En createPreferenceUnified(), ANTES de crear la pre-orden:

function validateDeliveryPayload(delivery, clientSettings) {
  // Si no hay delivery y no hay shipping config → OK (checkout sin shipping)
  if (!delivery && !clientSettings) return { shipping_cost: 0 };
  
  // Si hay settings pero no hay delivery → el comprador DEBE elegir
  if (clientSettings && hasAnyMethodEnabled(clientSettings) && !delivery) {
    throw new BadRequestException({ code: 'DELIVERY_METHOD_REQUIRED' });
  }

  const { method, address, address_id } = delivery;

  // Validar que el método exista
  if (!['delivery', 'pickup', 'arrange'].includes(method)) {
    throw new BadRequestException({ code: 'INVALID_DELIVERY_METHOD' });
  }

  // Validar que el método esté habilitado para este tenant
  if (method === 'delivery' && !clientSettings.delivery_enabled) {
    throw new BadRequestException({ code: 'DELIVERY_NOT_ENABLED' });
  }
  if (method === 'pickup' && !clientSettings.pickup_enabled) {
    throw new BadRequestException({ code: 'PICKUP_NOT_ENABLED' });
  }
  if (method === 'arrange' && !clientSettings.arrange_enabled) {
    throw new BadRequestException({ code: 'ARRANGE_NOT_ENABLED' });
  }

  // Si es delivery, validar dirección
  if (method === 'delivery') {
    if (!address && !address_id) {
      throw new BadRequestException({ code: 'ADDRESS_REQUIRED' });
    }
    if (address) {
      validateAddressFields(address); // requiered fields check
    }
    // Si address_id: buscar en user_addresses, validar que exista y pertenezca al user+client
  }

  // Cotizar shipping
  const quote = await quoteShipping(method, address || resolvedAddress, clientSettings);
  
  return {
    shipping_cost: quote.cost,
    shipping_label: quote.label,
    delivery_method: method,
    estimated_delivery_min: quote.estimated_days?.min,
    estimated_delivery_max: quote.estimated_days?.max,
  };
}
```

---

## 6. Persistencia en la Orden — Campos EXACTOS

### Insert de pre-orden (`orders` table)

```diff
  const { data, error } = await this.adminClient
    .from('orders')
    .insert({
      id: orderId,
      user_id: userId,
      client_id: clientId,
      payment_status: 'pending',
      status: 'pending',
      total_amount: totalToMp,           // ← AHORA incluye shipping_cost
      external_reference: externalRef,
      order_items: prelimOrderItems,
      payment_mode: paymentMode || 'total',
      first_name: firstName,
      last_name: lastName,
      email: user.email,
      phone_number: phoneNumber,
      settlement_days: settleDays ?? 0,
      installments: instSeed,
      method,
      plan_key: selection?.planKey || null,
      subtotal: this.round2(subtotalBase),
      ...(publicCode ? { public_code: publicCode } : {}),
+     // ── SHIPPING V2 ──
+     delivery_method: deliveryData.delivery_method || null,  // 'delivery'|'pickup'|'arrange'|null
+     shipping_cost: deliveryData.shipping_cost || 0,
+     shipping_label: deliveryData.shipping_label || null,     // "Envío a CABA - $1.500"
+     shipping_address: method === 'delivery'                   // JSON del address completo
+       ? JSON.stringify(resolvedAddress)
+       : null,
+     delivery_address: deliveryData.delivery_address_text || null, // "Av. Corrientes 1234, CABA"
+     pickup_info: method === 'pickup'                           // "Av. Corrientes 1234 | L-V 9-18hs"
+       ? `${settings.pickup_address} | ${settings.pickup_instructions}`
+       : null,
+     estimated_delivery_min: deliveryData.estimated_delivery_min || null,
+     estimated_delivery_max: deliveryData.estimated_delivery_max || null,
    })
```

### Migración requerida — `orders` nuevas columnas

```sql
-- 20260212_order_shipping_v2_cols.sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_method TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_cost NUMERIC(12,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_label TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_info TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_min DATE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_max DATE;
-- shipping_address ya existe (pero nunca se usa)
-- billing_address ya existe (futuro)
```

---

## 7. Email — Mapeo EXACTO de cada campo

### Template actual (`renderOrderEmailHTML`)

El template tiene una sección **"Entrega"** que ya contempla 3 casos:

```typescript
// ACTUAL (líneas 1227-1231)
const deliveryBlock = Data.delivery_address
  ? `<p>…${Data.delivery_address}</p>`                           // Caso 1: Envío
  : Data.pickup_info
    ? `<p>…Retiro en tienda: ${Data.pickup_info}</p>`            // Caso 2: Pickup
    : `<p>…Coordinaremos la entrega por este medio.</p>`;        // Caso 3: Fallback
```

### Cómo cambia con Shipping V2

```typescript
// NUEVO buildOrderEmailData (referencia)
const deliveryMethod = order.delivery_method;

// Construir deliveryBlock con más contexto:
let deliveryBlock = '';

switch (deliveryMethod) {
  case 'delivery':
    // Dirección del comprador + costo + tiempo estimado
    deliveryBlock = [
      `<p style="…;color:#d8e6f2;"><strong>📦 Envío a domicilio</strong></p>`,
      `<p style="…;color:#d8e6f2;">${order.delivery_address}</p>`,
      order.shipping_cost > 0
        ? `<p style="…;color:#8ea6bd;">Costo: ${formatCurrency(order.shipping_cost)}</p>`
        : `<p style="…;color:#27b3e1;">Envío gratis 🎉</p>`,
      order.estimated_delivery_min && order.estimated_delivery_max
        ? `<p style="…;color:#8ea6bd;">Estimado: ${formatDate(order.estimated_delivery_min)} - ${formatDate(order.estimated_delivery_max)}</p>`
        : null,
    ].filter(Boolean).join('\n');
    break;

  case 'pickup':
    // Dirección de retiro del vendedor + horarios
    deliveryBlock = [
      `<p style="…;color:#d8e6f2;"><strong>🏪 Retiro en tienda</strong></p>`,
      `<p style="…;color:#d8e6f2;">${order.pickup_info}</p>`,
      `<p style="…;color:#27b3e1;">Gratis</p>`,
    ].join('\n');
    break;

  case 'arrange':
    // Mensaje de coordinación
    deliveryBlock = [
      `<p style="…;color:#d8e6f2;"><strong>💬 Coordinar entrega</strong></p>`,
      `<p style="…;color:#8ea6bd;">El vendedor se comunicará para coordinar la entrega.</p>`,
      whatsappUrl
        ? `<p><a href="${whatsappUrl}" style="color:#9bd8ff;">Contactar por WhatsApp</a></p>`
        : null,
    ].filter(Boolean).join('\n');
    break;

  default:
    // Sin shipping configurado (retrocompatible)
    deliveryBlock = `<p style="…;color:#8ea6bd;">Coordinaremos la entrega por este medio.</p>`;
}
```

### Sección de totales del email — agregar shipping

```typescript
// ACTUAL (tfoot del email):
// Subtotal | Costo del servicio | Total pagado

// NUEVO (agregar entre subtotal y servicio):
const shippingRow = order.shipping_cost > 0
  ? `<tr>
       <td colspan="3" align="right" style="…;color:#8ea6bd;">Envío (${order.shipping_label || 'Domicilio'})</td>
       <td align="right" style="…;color:#d8e6f2;">${formatCurrency(order.shipping_cost)}</td>
     </tr>`
  : order.delivery_method === 'delivery'
    ? `<tr>
         <td colspan="3" align="right" style="…;color:#8ea6bd;">Envío</td>
         <td align="right" style="…;color:#27b3e1;">Gratis</td>
       </tr>`
    : ''; // No mostrar fila si es pickup/arrange/null
```

### Tipo actualizado `OrderEmailTotals`

```typescript
type OrderEmailTotals = {
  subtotal_formatted: string;
  shipping_formatted?: string | null;    // ← YA EXISTE en el type, ahora se popula
  service_fee_formatted?: string | null;
  discount_formatted?: string | null;    // ← YA EXISTE, futuro
  total_formatted: string;
};
```

---

## 8. Frontend OrderDetail — Mapeo de cada campo

### Sección actual "Entrega y Seguimiento"

Solo muestra tracking_code + tracking_url. **No muestra:**
- Método de entrega
- Dirección del comprador
- Costo de envío
- Tiempo estimado
- Info de pickup

### Sección nueva (propuesta)

```
┌─────────────────────────────────────────────────────────────┐
│ ▼ Entrega y seguimiento                                      │
│                                                               │
│ Método:     📦 Envío a domicilio                              │ ← order.delivery_method
│ Dirección:  Av. Corrientes 1234, 3°B, CABA (C1043AAZ)        │ ← order.delivery_address
│ Teléfono:   +54 11 1234-5678                                  │ ← del address JSON
│ Notas:      Timbre 3B, portero eléctrico                      │ ← del address JSON
│ Costo:      $1.500,00                                         │ ← order.shipping_cost
│ Estimado:   15/02 - 20/02                                     │ ← order.estimated_delivery_*
│                                                               │
│ Estado:     [🟢 En tránsito]                                  │ ← order.shipping_status
│ Tracking:   OCA-123456 (🔗 Ver seguimiento)                   │ ← order.tracking_code/url
│                                                               │
│ [Admin: formulario de tracking]                               │
│ [Admin: historial de eventos]                                 │
└─────────────────────────────────────────────────────────────┘
```

Para **pickup**:
```
│ Método:     🏪 Retiro en tienda                              │
│ Dirección:  Av. Corrientes 1234, CABA                        │ ← order.pickup_info (parte 1)
│ Horarios:   Lunes a viernes de 9 a 18hs                      │ ← order.pickup_info (parte 2)
│ Costo:      Gratis                                           │
```

Para **arrange**:
```
│ Método:     💬 Coordinar con vendedor                        │
│ Info:       El vendedor se comunicará para coordinar          │
│ Costo:      Gratis                                           │
│ [📱 Contactar por WhatsApp]                                  │
```

---

## 9. PaymentResultPage — Agregar info de envío

### Estado actual
Solo muestra productos, totales y tracking. NO muestra nada de shipping.

### Estado propuesto
Después del desglose de totales, agregar sección "Entrega":

```
✅ Compra confirmada

Productos:
  Remera XL            x1    $5.000
  Pantalón             x2    $12.000

Subtotal:              $29.000
Envío (CABA):          $1.500          ← NUEVO
Costo del servicio:    $915
Total pagado:          $31.415

📦 Envío a domicilio                    ← NUEVO
📍 Av. Corrientes 1234, CABA           ← NUEVO
📅 Estimado: 15/02 - 20/02             ← NUEVO
```

---

## 10. Preferencia de Mercado Pago — Shipping como ítem

### Estado actual
Los items de la preferencia MP son solo productos + service_fee (si aplica).

### Cambio propuesto

```typescript
// En createPreferenceUnified(), al armar mpItems:
if (shippingCost > 0) {
  mpItems.push({
    id: 'shipping_fee',
    title: `Envío – ${shippingLabel || 'Domicilio'}`,
    description: `Envío ${deliveryMethod === 'delivery' ? 'a domicilio' : ''}`,
    quantity: 1,
    currency_id: 'ARS',
    unit_price: shippingCost,
    category_id: 'shipping',
  });
}
```

### Validación anti-fraude (webhook)
```
Al confirmar pago (confirmPayment):
  totalEsperado = subtotal + serviceFee + shippingCost
  totalMp = paymentDetails.transaction_amount
  
  if (Math.abs(totalEsperado - totalMp) > threshold) {
    → Log alert + marcar como sospechoso
  }
```

---

## 11. Tabla Resumen — Trazabilidad Completa por Método

### Envío a domicilio (delivery)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB orders | P6 Email | P7 OrderDetail | P7 PaymentResult |
|------|----------|------------|--------|-------------|----------|----------------|-----------------|
| `delivery_method='delivery'` | Config toggle | Radio selected | Validado | `delivery_method` | Switch template | Badge "📦 Envío" | Sección "📦" |
| Dirección completa | — | Form required | DTO validated | `shipping_address` (JSON) | — (no muestra JSON) | Parse JSON → campos | — |
| Dirección formateada | — | Computada | Computada | `delivery_address` (text) | Sección "Entrega" | Texto legible | Texto legible |
| Costo | Config (flat/zona/api) | Mostrado en desglose | Cotizado | `shipping_cost` | Fila "$X" o "Gratis" | Fila en totales | Fila en totales |
| Tiempo estimado | Config (días) | Badge "3-7 días" | Calculado | `estimated_delivery_*` | "Estimado: dd/mm" | "Estimado: dd/mm" | "Estimado: dd/mm" |
| Label | — | Generado | Generado | `shipping_label` | Título fila | Null (no necesita) | Null |

### Retiro en tienda (pickup)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB orders | P6 Email | P7 OrderDetail | P7 PaymentResult |
|------|----------|------------|--------|-------------|----------|----------------|-----------------|
| `delivery_method='pickup'` | Config toggle | Radio selected | Validado | `delivery_method` | Switch template | Badge "🏪 Retiro" | "🏪 Retiro" |
| Dirección tienda | **REQUIRED** | Mostrada (readonly) | Leída de settings | `pickup_info` (parte 1) | "Retiro: {dirección}" | Texto | Texto |
| Horarios tienda | **REQUIRED** | Mostrado (readonly) | Leído de settings | `pickup_info` (parte 2) | "{horarios}" | Texto | — |
| Costo | $0 (siempre gratis) | "Gratis" | 0 | `shipping_cost=0` | "Gratis" | "Gratis" | — |
| Mapa | Opcional (lat/lng) | Link "Ver en mapa" | — | — | — | — | — |

### Coordinar por mensaje (arrange)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB orders | P6 Email | P7 OrderDetail | P7 PaymentResult |
|------|----------|------------|--------|-------------|----------|----------------|-----------------|
| `delivery_method='arrange'` | Config toggle | Radio selected | Validado | `delivery_method` | Switch template | Badge "💬 Coordinar" | "💬" |
| Mensaje | Default/custom | Mostrado | — | — | "Coordinaremos…" | Texto | — |
| WhatsApp | Opcional | Botón WA | — | — | Link WA | Botón WA | — |
| Costo | $0 | "Gratis" | 0 | `shipping_cost=0` | — | "Gratis" | — |

### Sin shipping configurado (retrocompatible)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB orders | P6 Email | P7 OrderDetail | P7 PaymentResult |
|------|----------|------------|--------|-------------|----------|----------------|-----------------|
| `delivery_method=null` | Ningún toggle | Sin step de envío | Acepta sin delivery | Nulls/defaults | Fallback "Coordinaremos…" | Sin sección shipping | Sin sección |
| Costo | — | — | 0 | 0 | — | — | — |

---

## 12. Resumen de Validaciones Cruzadas (Edge Cases)

| # | Escenario | P1 | P2 | P3 | P4 | P5 | P6 | P7 |
|---|-----------|----|----|----|----|----|----|-----|
| 1 | Pickup SIN dirección de retiro | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 2 | Pickup SIN horarios de retiro | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 3 | Envío gratis con threshold=0 | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 4 | Flat mode pero flat_cost vacío | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 5 | Manual mode pero 0 zonas | ⚠️ Warn | ✅ Save+log | ❌ "No disponible" | ❌ 422 | N/A | N/A | N/A |
| 6 | API mode pero 0 providers activos | ⚠️ Warn | ✅ Save+log | ❌ fallback o error | ❌/fallback | N/A | N/A | N/A |
| 7 | CP sin zona match | N/A | N/A | ❌ "No disponible" | ❌ 422 | N/A | N/A | N/A |
| 8 | Geocoding falla (Nominatim down) | N/A | N/A | ⚠️ Warn | ✅ Accept | ✅ sin lat/lng | ✅ | ✅ |
| 9 | Comprador elige delivery sin dirección | N/A | N/A | ❌ Block | ❌ 400 | N/A | N/A | N/A |
| 10 | Orden vieja sin shipping_cost (retrocompat) | N/A | N/A | N/A | N/A | ✅ null→0 | ✅ fallback | ✅ no muestra shipping |
| 11 | Provider API devuelve error al cotizar | N/A | N/A | ⚠️ "Error cotizando" | Retry/fallback flat | N/A | N/A | N/A |
| 12 | Webhook: monto MP ≠ total esperado con shipping | N/A | N/A | N/A | ⚠️ Alert+log | ✅ flag | N/A | N/A |
| 13 | Admin desactiva método DESPUÉS de que un comprador tenía una orden con ese método | N/A | N/A | N/A | N/A | ✅ orden ya creada | ✅ texto estático | ✅ |
| 14 | Solo 1 método habilitado | N/A | N/A | ✅ Auto-select | ✅ Accept | ✅ | ✅ | ✅ |
| 15 | 0 métodos habilitados | N/A | N/A | ✅ Skip step | ✅ method=null, cost=0 | ✅ | ✅ fallback | ✅ |

---

## 13. Checklist para el Desarrollador (por componente)

### Al tocar `client_shipping_settings`:
- [ ] Si `pickup_enabled=true` → `pickup_address` y `pickup_instructions` son NOT NULL
- [ ] Si `free_shipping_enabled=true` → `free_shipping_threshold > 0`
- [ ] Si `shipping_pricing_mode='flat'` → `flat_shipping_cost >= 0` (0 = gratis)
- [ ] Si `shipping_pricing_mode='manual'` → minimo 1 `shipping_zone` activa (warning, no hard-block)
- [ ] Si `shipping_pricing_mode='provider_api'` → mínimo 1 `shipping_integration` con `quoteRates` (warning)

### Al tocar `createPreferenceForPlan`:
- [ ] `delivery.method` validado contra settings habilitados
- [ ] Si `method=delivery` → `address` validada (6 campos required)
- [ ] Shipping cost cotizado (no del frontend)
- [ ] Shipping_cost incluido en `totalToMp`
- [ ] Shipping como ítem en `mpItems` si > 0
- [ ] Columnas `delivery_method`, `shipping_cost`, `shipping_address`, `delivery_address`, `pickup_info`, `estimated_delivery_*` insertadas en la pre-orden

### Al tocar `confirmPayment`:
- [ ] Si la orden ya tiene `shipping_cost`, incluirlo en la validación de monto
- [ ] `buildOrderEmailData` lee: `delivery_method`, `delivery_address`, `pickup_info`, `shipping_cost`
- [ ] `OrderEmailTotals.shipping_formatted` se popula si `shipping_cost > 0`

### Al tocar `renderOrderEmailHTML`:
- [ ] `deliveryBlock` cubre los 4 casos (delivery/pickup/arrange/null)
- [ ] Si delivery: muestra dirección + costo + estimado
- [ ] Si pickup: muestra dirección tienda + horarios + "Gratis"
- [ ] Si arrange: muestra mensaje + link WhatsApp
- [ ] Si null: fallback "Coordinaremos…" (retrocompatible)
- [ ] Fila de shipping en tfoot (entre subtotal y servicio)

### Al tocar `OrderDetail` (frontend):
- [ ] Muestra `delivery_method` con badge+ícono
- [ ] Si delivery: dirección, costo, estimado
- [ ] Si pickup: dirección tienda, horarios
- [ ] Si arrange: mensaje + botón WA
- [ ] Costo de envío en desglose de totales
- [ ] Tracking + historial (no cambia, ya existe)

### Al tocar `PaymentResultPage`:
- [ ] Fila de envío en desglose
- [ ] Sección "Entrega" con info del método elegido

# Plan Completo: Shipping V2 — Envío Integrado al Checkout

**Fecha:** 2026-02-11  
**Autor:** agente-copilot  
**Rama API:** `feature/automatic-multiclient-onboarding`  
**Rama Web:** `feature/multitenant-storefront`  
**Estado:** PLAN (pendiente aprobación del TL)

---

## Resumen Ejecutivo

La infraestructura de shipping V1 (integraciones, tracking, providers) está completa, pero **opera solo post-orden**: el admin crea envíos manualmente después de que el cliente pagó. No hay ningún enlace entre el envío y el checkout del comprador.

Este plan describe **6 bloques** para transformar el shipping en un sistema completo que impacte directamente en la experiencia de compra: opciones de entrega, costos, direcciones, tiempos, y operativa del vendedor.

---

## Diagnóstico del Estado Actual

### Lo que YA existe (hooks construidos)

| Hook | Dónde | Qué hace |
|------|-------|----------|
| `ShippingProvider.quoteRates()` | Interface + Andreani impl | Cotiza envío por CP — **nunca se llama desde checkout** |
| `apply_to: 'shipping'` en `ExtraLine` | `payment-calculator.ts` | La calculadora soporta extras sobre shipping — **nunca recibe shippingCost** |
| `shipping_address / billing_address` | Tabla `orders` (columnas) | Existen pero **nunca se populan** en checkout |
| `delivery_address` en email templates | `mercadopago.service.ts` | Placeholder en email de confirmación — **siempre null** |
| `shipments.cost` y `estimated_delivery_at` | Tabla `shipments` | Campos listos — **nunca se muestran al comprador** |
| `PlanFeature('commerce.shipping')` | Controller guard | Gating por plan — funciona OK |
| Hooks modulares del CartProvider | `useCheckout`, `useCartQuotes` | Arquitectura preparada para agregar `useShipping` |

### Lo que FALTA (gaps críticos)

```
CHECKOUT SIN SHIPPING:
  Cart → Seleccionar plan de pago → Pagar → MP → Confirm
  ❌ No hay paso de dirección
  ❌ No hay selección de método de envío  
  ❌ No hay costo de envío en el total
  ❌ No se persiste dirección en la orden
  ❌ No hay opción "retiro en tienda" ni "coordinar por mensaje"

CHECKOUT CON SHIPPING (objetivo):
  Cart → Dirección → Método de envío → Desglose con shipping → Pagar → MP → Confirm
  ✅ Dirección validada con autocompletado
  ✅ Opciones: envío a domicilio / retiro en tienda / coordinar
  ✅ Costo real del envío (cotizado o manual)  
  ✅ Tiempo estimado de entrega
  ✅ Shipping incluido en preferencia MP
  ✅ Dirección persistida en la orden
```

---

## Bloque 1 — Métodos de Entrega por Tenant

### Objetivo
Cada tenant configura qué opciones de entrega ofrece a sus compradores.

### Nuevas opciones de entrega

| Opción | Slug | Descripción |
|--------|------|-------------|
| Envío a domicilio | `delivery` | Envío por correo/transporte a la dirección del comprador |
| Retiro en tienda | `pickup` | El comprador retira en la dirección del vendedor |
| Coordinar por mensaje | `arrange` | Se acuerda el método de entrega por WhatsApp/chat |

### Cambios en DB

**Tabla `client_shipping_settings`** (nueva):

```sql
CREATE TABLE IF NOT EXISTS client_shipping_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  
  -- ── Opciones de entrega habilitadas ──
  delivery_enabled BOOLEAN NOT NULL DEFAULT true,        -- Envío a domicilio
  pickup_enabled BOOLEAN NOT NULL DEFAULT false,         -- Retiro en tienda
  arrange_enabled BOOLEAN NOT NULL DEFAULT false,        -- Coordinar por mensaje
  
  -- ── Datos de retiro en tienda ──
  pickup_address TEXT,                                    -- "Av. Corrientes 1234, CABA"
  pickup_instructions TEXT,                               -- "Lunes a viernes de 9 a 18hs"
  pickup_lat NUMERIC(10,7),                               -- Latitud
  pickup_lng NUMERIC(10,7),                               -- Longitud
  
  -- ── Datos de "coordinar" ──
  arrange_message TEXT DEFAULT 'Nos pondremos en contacto para coordinar la entrega.',
  arrange_whatsapp TEXT,                                  -- Número de WhatsApp (opcional)
  
  -- ── Configuración de envío ──
  free_shipping_enabled BOOLEAN NOT NULL DEFAULT false,   -- ¿Habilitar envío gratis?
  free_shipping_threshold NUMERIC(12,2) DEFAULT 0,        -- Envío gratis a partir de $X
  
  -- ── Pricing de envío (Manual) ──
  shipping_pricing_mode TEXT NOT NULL DEFAULT 'manual',   -- 'manual' | 'provider_api' | 'flat'
  flat_shipping_cost NUMERIC(12,2) DEFAULT 0,             -- Costo fijo global ($)
  
  -- ── Tiempo estimado ──
  default_delivery_days_min INT DEFAULT 3,                -- Días mín estimados
  default_delivery_days_max INT DEFAULT 7,                -- Días máx estimados
  
  -- ── Meta ──
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID
);

-- Unique one per client
CREATE UNIQUE INDEX idx_css_client ON client_shipping_settings(client_id);

-- RLS
ALTER TABLE client_shipping_settings ENABLE ROW LEVEL SECURITY;

CREATE POLICY css_select_tenant ON client_shipping_settings
  FOR SELECT USING (client_id = current_client_id());

CREATE POLICY css_write_admin ON client_shipping_settings
  FOR ALL USING (client_id = current_client_id() AND is_admin())
  WITH CHECK (client_id = current_client_id() AND is_admin());

CREATE POLICY server_bypass ON client_shipping_settings
  FOR ALL USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

**Tabla `shipping_zones`** (nueva, para pricing por zona):

```sql
CREATE TABLE IF NOT EXISTS shipping_zones (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  
  name TEXT NOT NULL,                              -- "CABA", "GBA Norte", "Interior"
  zip_codes TEXT[],                                -- ["1000-1499", "1600", "1605"]
  provinces TEXT[],                                -- ["Buenos Aires", "CABA"]
  cost NUMERIC(12,2) NOT NULL DEFAULT 0,           -- Costo del envío para esta zona
  delivery_days_min INT DEFAULT 1,
  delivery_days_max INT DEFAULT 5,
  is_active BOOLEAN NOT NULL DEFAULT true,
  position INT NOT NULL DEFAULT 0,                 -- Orden de evaluación
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sz_client ON shipping_zones(client_id);

-- RLS (mismo patrón)
ALTER TABLE shipping_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY sz_select_tenant ON shipping_zones FOR SELECT USING (client_id = current_client_id());
CREATE POLICY sz_write_admin ON shipping_zones FOR ALL USING (client_id = current_client_id() AND is_admin()) WITH CHECK (client_id = current_client_id() AND is_admin());
CREATE POLICY server_bypass ON shipping_zones FOR ALL USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');
```

### Endpoints nuevos (Backend)

```
GET  /shipping/settings              → Lee client_shipping_settings (público, filtrado por tenant)
PUT  /shipping/settings              → Actualiza settings (admin)
GET  /shipping/zones                 → Lista zonas del tenant (público)
POST /shipping/zones                 → Crear zona (admin)
PUT  /shipping/zones/:id             → Editar zona (admin)
DELETE /shipping/zones/:id           → Eliminar zona (admin)
```

### UI Admin (Frontend — panel de Envíos)

Agregar una 3ra tab: **"Configuración"** al `ShippingPanel`:
- Toggle: Envío a domicilio (sí/no)
- Toggle: Retiro en tienda (sí/no) → campos: dirección, instrucciones, mapa
- Toggle: Coordinar por mensaje (sí/no) → campos: mensaje, WhatsApp
- Toggle: Envío gratis a partir de $X
- Modo de pricing: Manual (fijo) / Por zona / Cotización API del provider
- Gestión de zonas de envío (tabla editable si modo = "por zona")
- Tiempo estimado por defecto (días mín/máx)

### Impacto en la tienda (comprador)

En el checkout (CartPage o nuevo step), el comprador ve:
- **Envío a domicilio** ($X.XX — 3-7 días hábiles)  
- **Retiro en tienda** (Gratis — Av. Corrientes 1234, L-V 9-18hs)  
- **Coordinar con el vendedor** (Gratis — Te contactaremos por WhatsApp)

---

## Bloque 2 — Costos de Envío en el Checkout

### Objetivo
Incluir el costo de envío en el total de la orden, la preferencia de Mercado Pago, y el desglose.

### Flujo de cotización

```
1. Comprador ingresa dirección (o selecciona "retiro" / "coordinar")
2. Si eligió "delivery":
   a. Modo FLAT:     → shipping_cost = flat_shipping_cost
   b. Modo MANUAL:   → shipping_cost = matchZone(zip_code).cost
   c. Modo API:      → shipping_cost = provider.quoteRates(address, items)
3. Si free_shipping_enabled && subtotal >= threshold → shipping_cost = 0
4. shipping_cost se suma al total y se incluye en la preferencia MP
```

### Endpoint nuevo

```
POST /shipping/quote
Body: {
  delivery_method: 'delivery' | 'pickup' | 'arrange',
  zip_code?: string,        -- requerido si delivery
  province?: string,
  cart_items: [...],        -- para calcular peso/volumen (futuro)
}
Response: {
  method: 'delivery',
  cost: 1500.00,
  free_shipping: false,
  free_shipping_threshold: 50000,
  estimated_days: { min: 3, max: 7 },
  zone_name: "GBA Norte",
  provider_quotes?: [       -- si modo=api
    { provider: 'andreani', service: 'Express', cost: 2100, days: 2 },
    { provider: 'andreani', service: 'Standard', cost: 1200, days: 5 },
  ]
}
```

### Cambios en el flujo de preferencia MP

**`mercadopago.service.ts` → `createPreferenceForPlan()`:**

```diff
+ // Agregar shipping como ítem en la preferencia
+ if (shippingCost > 0) {
+   items.push({
+     id: 'shipping_fee',
+     title: `Envío - ${shippingMethodLabel}`,
+     quantity: 1,
+     unit_price: shippingCost,
+     currency_id: 'ARS',
+   });
+ }
```

**Columnas nuevas en `orders`:**

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS
  delivery_method TEXT DEFAULT 'delivery',           -- 'delivery' | 'pickup' | 'arrange'
  shipping_cost NUMERIC(12,2) DEFAULT 0,
  shipping_zone_id UUID,
  shipping_label TEXT;                                -- "Envío a CABA - $1500" (display)
```

### Cambios en `calculateQuote()`

```diff
  interface QuoteInput {
    baseAmount: number;
+   shippingCost?: number;      // ← ya está tipado, solo falta pasarlo
    selection: PaymentSelection;
    extras: ExtraLine[];
    feeRule: FeeRule;
    settings: ClientPaymentSettings;
  }
```

El campo `apply_to: 'shipping'` de `ExtraLine` **ya está implementado** en la calculadora. Solo necesitamos:
1. Pasar `shippingCost` al llamar `calculateQuote()`
2. Incluirlo en el `baseAmount` total de la preferencia MP

### Frontend — nuevo hook `useShipping()`

```javascript
// src/hooks/cart/useShipping.js
export function useShipping({ cartItems, subtotal }) {
  const [deliveryMethod, setDeliveryMethod] = useState(null); // delivery|pickup|arrange
  const [address, setAddress] = useState(null);
  const [shippingQuote, setShippingQuote] = useState(null);
  const [settings, setSettings] = useState(null);
  
  // GET /shipping/settings al mount
  // POST /shipping/quote cuando cambia deliveryMethod o address.zip_code
  // Retorna: { deliveryMethod, setDeliveryMethod, address, setAddress, 
  //            shippingCost, estimatedDays, isFreeShipping, availableMethods, ... }
}
```

### Impacto visual en el desglose del carrito

```
Subtotal                     $45.000
Descuento                    -$5.000
Envío a domicilio (GBA)      +$1.500    ← NUEVO
  └─ Envío gratis a partir de $50.000
Costo del servicio (3%)       $1.215
──────────────────────────────────────
TOTAL                        $42.715
```

---

## Bloque 3 — Dirección del Comprador

### Objetivo
Capturar dirección de envío (o confirmar punto de retiro), persistirla en la orden, y usarla para cotizar y crear el shipment.

### Tabla `user_addresses` (nueva)

```sql
CREATE TABLE IF NOT EXISTS user_addresses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  label TEXT DEFAULT 'Casa',                        -- "Casa", "Trabajo", "Otro"
  full_name TEXT NOT NULL,
  phone TEXT,
  street TEXT NOT NULL,                              -- "Av. Corrientes"
  street_number TEXT NOT NULL,                       -- "1234"
  floor_apt TEXT,                                    -- "3° B"
  city TEXT NOT NULL,                                -- "CABA"
  province TEXT NOT NULL,                            -- "Buenos Aires"
  zip_code TEXT NOT NULL,                            -- "C1043AAZ"
  country TEXT NOT NULL DEFAULT 'AR',
  lat NUMERIC(10,7),
  lng NUMERIC(10,7),
  notes TEXT,                                        -- "Timbre 3B, portero eléctrico"
  is_default BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ua_user ON user_addresses(user_id, client_id);

-- RLS: owner-only
ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY ua_owner ON user_addresses FOR ALL
  USING (client_id = current_client_id() AND user_id = auth.uid())
  WITH CHECK (client_id = current_client_id() AND user_id = auth.uid());
CREATE POLICY server_bypass ON user_addresses FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

### Endpoints

```
GET    /addresses              → Listar direcciones del usuario
POST   /addresses              → Crear nueva dirección
PUT    /addresses/:id          → Editar
DELETE /addresses/:id          → Eliminar
POST   /addresses/validate     → Validar con geocoding (Nominatim/OSM)
```

### Validación de dirección (Nominatim — gratis, sin API key)

```
POST /addresses/validate
Body: { street: "Av. Corrientes 1234", city: "CABA", province: "Buenos Aires", zip_code: "C1043" }
Response: {
  valid: true,
  formatted: "Avenida Corrientes 1234, C1043 AAZ, CABA, Argentina",
  lat: -34.6037,
  lng: -58.3816,
  confidence: 0.92,
  suggestions: []  // si hay ambigüedad, devuelve alternativas
}
```

**Implementación con Nominatim (OpenStreetMap):**
- URL: `https://nominatim.openstreetmap.org/search`
- Gratis, sin API key, rate limit 1 req/sec (suficiente para checkout)
- User-Agent header requerido (NovaVision/1.0)
- Fallback: si Nominatim no responde, se acepta la dirección sin validar

### UI del formulario de dirección

```
┌──────────────────────────────────────────────────────┐
│ Dirección de envío                                    │
│                                                        │
│ ┌─ Direcciones guardadas ──────────────────────────┐  │
│ │ 🏠 Casa — Av. Corrientes 1234, CABA       [Usar] │  │
│ │ 🏢 Trabajo — Av. Santa Fe 987, CABA       [Usar] │  │
│ └──────────────────────────────────────────────────┘  │
│                                                        │
│ ○ Usar otra dirección                                  │
│                                                        │
│ Calle *         [Av. Corrientes          ]  Número * [1234]  │
│ Piso/Depto      [3° B                    ]                    │
│ Ciudad *        [CABA                    ]                    │
│ Provincia *     [Buenos Aires     ▾      ]                    │
│ Código Postal * [C1043AAZ               ]                    │
│ Teléfono        [+54 11 1234-5678       ]                    │
│ Notas           [Timbre 3B, portero ...  ]                    │
│                                                        │
│ 🗺️ [Mapa de confirmación — Leaflet/OSM]               │
│                                                        │
│ ☐ Guardar esta dirección para futuras compras         │
└──────────────────────────────────────────────────────┘
```

**Mapa:** Usar **Leaflet + OpenStreetMap** (gratis, sin API key). Muestra un pin con la ubicación geocodificada. El comprador puede corregir arrastrando el pin.

### Persistencia en la orden

Cuando se crea la pre-orden en `createPreferenceForPlan`, además de los campos actuales:

```diff
+ shipping_address: JSON.stringify({
+   full_name, street, street_number, floor_apt, city, province, zip_code, country, lat, lng, phone, notes
+ }),
+ delivery_method: 'delivery',  // o 'pickup' o 'arrange'
+ shipping_cost: 1500.00,
+ shipping_label: 'Envío a CABA - $1.500',
```

---

## Bloque 4 — Tiempo Estimado de Entrega

### Objetivo
Mostrar al comprador cuándo recibiría su pedido, basado en el método de envío y la zona.

### Fuentes de datos del tiempo estimado

| Modo pricing | Fuente | Ejemplo |
|---|---|---|
| `manual` / `flat` | `client_shipping_settings.default_delivery_days_min/max` | "3-7 días hábiles" |
| Por zona | `shipping_zones.delivery_days_min/max` | "1-2 días hábiles (CABA)" |
| API del provider | `RateQuote.estimated_days` de `quoteRates()` | "2 días hábiles (Express)" |
| Retiro en tienda | Instantáneo (o texto del admin) | "Disponible en 24hs" |
| Coordinar | N/A | "A coordinar" |

### Dónde se muestra

1. **Checkout** — junto a cada opción de envío
2. **Ficha de producto (PDP)** — si el comprador ya tiene dirección guardada
3. **Confirmación de orden** — "Tu pedido llegará entre el 15/02 y el 20/02"
4. **Email de confirmación** — mismo dato

### Cálculo

```javascript
function estimateDelivery(shippingQuote) {
  const today = new Date();
  // Sumar solo días hábiles (excluir sáb/dom)
  const minDate = addBusinessDays(today, shippingQuote.estimated_days.min);
  const maxDate = addBusinessDays(today, shippingQuote.estimated_days.max);
  return { minDate, maxDate, 
    label: `${format(minDate, 'dd/MM')} - ${format(maxDate, 'dd/MM')}` };
}
```

### Columna nueva en `orders`

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS
  estimated_delivery_min DATE,
  estimated_delivery_max DATE;
```

---

## Bloque 5 — Instrucciones Operativas para Vendedores

### Objetivo
Guías paso a paso dentro del admin dashboard que expliquen al vendedor cómo gestionar envíos según cada método/provider.

### Contenido por método de entrega

#### Envío a domicilio — Manual
```
1. El comprador paga y la orden queda en estado "Pendiente"
2. Vos preparás el paquete
3. Vas al correo / agencia y despachás
4. Desde el panel → Pedidos → la orden → ingresás:
   - Código de seguimiento
   - URL de tracking (si la tenés)
5. El comprador recibe email con el tracking
6. Cuando figura "Entregado" en el correo, marcás como "Entregado"
```

#### Envío a domicilio — Andreani
```
1. El comprador paga → la orden queda "Pendiente"
2. Desde Pedidos → la orden → click "Crear envío"
3. Se genera automáticamente:
   - Etiqueta de despacho (PDF)
   - Código de seguimiento
4. Imprimí la etiqueta y pegala en el paquete
5. Opciones de despacho:
   a. Llevarlo a una sucursal Andreani
   b. Programar retiro en tu domicilio (desde el panel de Andreani)
6. El tracking se actualiza automáticamente
7. El comprador recibe notificaciones por email en cada cambio de estado
```

#### Retiro en tienda
```
1. El comprador paga → la orden queda "Pendiente"  
2. Preparás el pedido
3. Desde Pedidos → la orden → marcás "Preparando"
4. El comprador recibe email: "Tu pedido está listo para retirar"
   Con la dirección y horarios configurados
5. Cuando retira → marcás "Entregado"
```

#### Coordinar por mensaje
```
1. El comprador paga → la orden queda "Pendiente"
2. Recibís notificación (email + panel)
3. Contactás al comprador por WhatsApp/email
4. Coordinás la entrega
5. Actualizás el estado del pedido según corresponda
```

### Dónde se muestra
- Tab "Guías y tutoriales" del ShippingPanel (ya existe — extender `ShippingGuides.jsx`)
- Contextual: cuando el admin abre una orden, un tooltip/banner le indica el paso siguiente según el state

### Costos del proveedor

| Proveedor | Costo para el vendedor | Observaciones |
|-----------|----------------------|---------------|
| **Manual** | Solo el costo real del correo/transporte | NovaVision no cobra nada extra |
| **Andreani** | Tarifa de Andreani según contrato | Se paga directo a Andreani; NovaVision no intermediará en el cobro |
| **OCA** | Tarifa de OCA según convenio | Ídem — pago directo al proveedor |
| **Correo Argentino** | Tarifa oficial según peso/destino | Ídem |
| **Custom** | Depende de la API configurada | El vendedor gestiona su propio convenio |
| **NovaVision** | Sin cargo adicional por usar la feature de envío | Incluido en el plan Growth+ |

> **Nota:** NovaVision no cobra comisión sobre el envío. El costo del proveedor lo paga el vendedor directamente (o lo traslada al comprador).

---

## Bloque 6 — Flujo Completo de Checkout Rediseñado

### Flujo actual (sin shipping)

```
CartPage
  └→ Seleccionar plan de pago
  └→ Click "Pagar"
  └→ Modal: Pagar total / Pagar reserva
  └→ Redirect a Mercado Pago
  └→ PaymentResultPage → SuccessPage
```

### Flujo propuesto (con shipping)

```
CartPage (resumen de productos)
  └→ Step 1: Método de entrega
      ├─ 📦 Envío a domicilio ($X.XX — 3-7 días)
      ├─ 🏪 Retiro en tienda (Gratis — Av. Corrientes 1234)
      └─ 💬 Coordinar con vendedor (Gratis)
      
  └→ Step 2: Dirección (solo si eligió "delivery")
      ├─ Direcciones guardadas (click para usar)
      ├─ Formulario nueva dirección
      ├─ Autocompletado (Nominatim/OSM)
      ├─ Mapa de confirmación (Leaflet)
      └─ Checkbox "Guardar para futuras compras"
      
  └→ Step 3: Desglose y pago
      ├─ Resumen de productos
      ├─ Línea de envío (método + costo + tiempo estimado)
      ├─ Costo de servicio
      ├─ Total final
      ├─ Selector plan de pago (débito/crédito/cuotas)
      └─ Botón "Pagar $TOTAL"
      
  └→ Redirect a Mercado Pago
  └→ PaymentResultPage (+ info de envío en el recibo)
  └→ SuccessPage (+ tracking link si es delivery)
```

### Opciones de implementación del layout

**Opción A — Steps dentro del CartPage (recomendada para MVP):**
- Mantener la CartPage como single page
- Agregar un stepper/accordion debajo del resumen de productos
- Steps colapsables: Entrega → Dirección → Pago
- Mínimo cambio en routing

**Opción B — Multi-page checkout:**  
- Ruta `/checkout` separada del `/cart`
- Steps: `/checkout/shipping` → `/checkout/address` → `/checkout/payment`
- Más limpio pero mayor refactor de routing

### Componentes nuevos (Web/Frontend)

```
src/hooks/cart/
  useShipping.js                    ← Quote de envío, métodos disponibles
  useAddresses.js                   ← CRUD direcciones usuario

src/components/checkout/
  DeliveryMethodSelector.jsx        ← Radio cards: delivery/pickup/arrange
  AddressForm.jsx                   ← Formulario de dirección
  AddressAutocomplete.jsx           ← Input con sugerencias (Nominatim)
  AddressMap.jsx                    ← Mapa Leaflet con pin draggable
  SavedAddressList.jsx              ← Cards de direcciones guardadas
  ShippingCostSummary.jsx           ← Línea de shipping en desglose
  DeliveryEstimate.jsx              ← Badge "3-7 días hábiles"
  
src/pages/CartPage/
  index.jsx                         ← Refactorizar para incluir steps de shipping
```

### Detalle de request a `createPreferenceForPlan`

```diff
  POST /mercadopago/create-preference-for-plan
  Body: {
    baseAmount: 45000,
    selection: { method: 'credit_card', installmentsSeed: 1, ... },
    cartItems: [...],
+   delivery: {
+     method: 'delivery',            // 'delivery' | 'pickup' | 'arrange'
+     shipping_cost: 1500,
+     address: {                      // solo si method=delivery
+       full_name: "Juan Pérez",
+       street: "Av. Corrientes",
+       street_number: "1234",
+       floor_apt: "3°B",
+       city: "CABA",
+       province: "Buenos Aires",
+       zip_code: "C1043AAZ",
+       phone: "+5411...",
+       lat: -34.6037,
+       lng: -58.3816,
+       notes: "Timbre 3B"
+     },
+     save_address: true,            // guardar para futuras compras
+     address_id: null,              // o UUID si usa una guardada
+   }
  }
```

---

## Resumen de Archivos a Crear/Modificar por Bloque

### Backend (API)

| Bloque | Archivo | Acción |
|--------|---------|--------|
| 1 | `migrations/backend/20260212_shipping_settings.sql` | Crear tablas |
| 1 | `src/shipping/shipping.controller.ts` | Agregar endpoints settings/zones |
| 1 | `src/shipping/shipping.service.ts` | Lógica de settings y zones |
| 1 | `src/shipping/dto/index.ts` | DTOs de settings/zones |
| 2 | `src/shipping/shipping-quote.service.ts` | **Nuevo** — cotización de envío |
| 2 | `src/shipping/shipping.controller.ts` | Endpoint POST /shipping/quote |
| 2 | `src/tenant-payments/mercadopago.service.ts` | Incluir shipping en preferencia+orden |
| 2 | `src/payments/payment-calculator.ts` | Pasar shippingCost |
| 3 | `migrations/backend/20260212_user_addresses.sql` | Crear tabla |
| 3 | `src/addresses/addresses.module.ts` | **Nuevo módulo** |
| 3 | `src/addresses/addresses.controller.ts` | CRUD + validate |
| 3 | `src/addresses/addresses.service.ts` | Lógica + Nominatim |
| 3 | `src/addresses/nominatim.service.ts` | **Nuevo** — geocoding |
| 4 | `src/shipping/shipping-quote.service.ts` | Incluir estimated_days |
| 4 | `migrations/backend/20260212_order_shipping_cols.sql` | Agregar columnas |
| 5 | N/A (solo frontend) | — |
| 6 | `src/tenant-payments/mercadopago.service.ts` | Refactor principal |

### Frontend (Web)

| Bloque | Archivo | Acción |
|--------|---------|--------|
| 1 | `src/components/admin/ShippingPanel/ShippingSettings.jsx` | **Nuevo** — config admin |
| 1 | `src/components/admin/ShippingPanel/ShippingZones.jsx` | **Nuevo** — zonas admin |
| 1 | `src/components/admin/ShippingPanel/index.jsx` | Agregar 3ra tab |
| 2 | `src/hooks/cart/useShipping.js` | **Nuevo hook** |
| 2 | `src/components/checkout/ShippingCostSummary.jsx` | **Nuevo** |
| 2 | `src/pages/CartPage/index.jsx` | Incluir shipping en desglose |
| 3 | `src/hooks/cart/useAddresses.js` | **Nuevo hook** |
| 3 | `src/components/checkout/AddressForm.jsx` | **Nuevo** |
| 3 | `src/components/checkout/AddressAutocomplete.jsx` | **Nuevo** (Nominatim) |
| 3 | `src/components/checkout/AddressMap.jsx` | **Nuevo** (Leaflet) |
| 3 | `src/components/checkout/SavedAddressList.jsx` | **Nuevo** |
| 4 | `src/components/checkout/DeliveryEstimate.jsx` | **Nuevo** |
| 5 | `src/components/admin/ShippingPanel/ShippingGuides.jsx` | Extender guías |
| 6 | `src/components/checkout/DeliveryMethodSelector.jsx` | **Nuevo** |
| 6 | `src/pages/CartPage/index.jsx` | Integrar steps de checkout |
| 6 | `src/context/CartProvider.jsx` | Agregar useShipping + useAddresses |

### Dependencias nuevas (Web)

```
leaflet          — Mapas OpenStreetMap (gratis, sin API key)
react-leaflet    — Wrapper React para Leaflet
```

No se necesita API key de Google. Nominatim (geocoding) y Leaflet (mapas) son gratuitos.

---

## Orden de Implementación Recomendado

```
FASE 1 (MVP — funcional sin API de providers):
  Bloque 1 → Settings de entrega por tenant (DB + admin UI + endpoints)
  Bloque 5 → Instrucciones operativas extendidas (solo frontend)
  
FASE 2 (Checkout con shipping):
  Bloque 3 → Direcciones del comprador (DB + endpoints + formulario)
  Bloque 2 → Costos de envío en checkout (quote + desglose + MP preference)
  Bloque 4 → Tiempo estimado
  
FASE 3 (Integración completa):
  Bloque 6 → Checkout rediseñado con steps
```

**Estimación total:** ~15-20 PRs, ~3000-5000 líneas nuevas entre API y Web.

---

## Riesgos y Consideraciones

| Riesgo | Mitigación |
|--------|-----------|
| Nominatim rate limit (1 req/sec) | Cache de geocoding por CP; debounce en frontend de 500ms |
| Leaflet bundle size (~140KB gzip) | Lazy load con `React.lazy()` solo en checkout |
| Comprador sin dirección guardada → fricción | Permitir checkout sin validación de mapa (solo formulario) |
| Provider API caído al cotizar | Fallback a costo manual / flat del tenant |
| Envío gratis mal configurado (threshold=0) | Validación: si `free_shipping_enabled=true`, threshold debe ser >0 |
| Orders existentes sin campos de shipping | Migración non-breaking: todas las columnas nuevas son nullable/default |
| CartPage se vuelve muy larga | Stepper colapsable o split en multipage (decidir en Bloque 6) |

---

## Preguntas Abiertas para el TL

1. **¿Layout del checkout?** — Steps en CartPage (más rápido) o multi-page `/checkout/*` (más limpio)?
2. **¿Envío obligatorio?** — ¿El comprador siempre debe elegir un método, o algunos tenants pueden tener checkout sin opciones de envío (como ahora)?
3. **¿Leaflet o alternativa más liviana?** — Leaflet es ~140KB. Si el mapa no es crítico para MVP, se puede usar solo el formulario + un link a Google Maps externo.
4. **¿Prioridad de Bloque 1 vs 2?** — ¿Empezamos con la configuración del admin o directo con el checkout?

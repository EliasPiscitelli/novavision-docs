# Shipping V2 — Documento Unificado de Análisis

**Fecha:** 2026-02-11  
**Autor:** agente-copilot  
**Rama API:** `feature/automatic-multiclient-onboarding`  
**Rama Web:** `feature/multitenant-storefront`  
**Estado:** PLAN — pendiente aprobación del TL

---

## Índice

1. [Resumen Ejecutivo](#1-resumen-ejecutivo)
2. [Diagnóstico del Estado Actual](#2-diagnóstico-del-estado-actual)
3. [Bloque 1 — Métodos de Entrega por Tenant](#3-bloque-1--métodos-de-entrega-por-tenant)
4. [Bloque 2 — Costos de Envío en el Checkout](#4-bloque-2--costos-de-envío-en-el-checkout)
5. [Bloque 3 — Dirección del Comprador](#5-bloque-3--dirección-del-comprador)
6. [Bloque 4 — Tiempo Estimado de Entrega](#6-bloque-4--tiempo-estimado-de-entrega)
7. [Bloque 5 — Instrucciones Operativas para Vendedores](#7-bloque-5--instrucciones-operativas-para-vendedores)
8. [Bloque 6 — Flujo Completo de Checkout Rediseñado](#8-bloque-6--flujo-completo-de-checkout-rediseñado)
9. [Validaciones Exhaustivas — Principio Rector](#9-validaciones-exhaustivas--principio-rector)
10. [Admin Config — Validación por Método](#10-admin-config--validación-por-método)
11. [Zonas de Envío — Validaciones](#11-zonas-de-envío--validaciones)
12. [Checkout del Comprador — Validación por Step](#12-checkout-del-comprador--validación-por-step)
13. [Request de Checkout → Backend](#13-request-de-checkout--backend)
14. [Persistencia en la Orden — Campos EXACTOS](#14-persistencia-en-la-orden--campos-exactos)
15. [Email — Mapeo EXACTO de cada Campo](#15-email--mapeo-exacto-de-cada-campo)
16. [Frontend OrderDetail + PaymentResult](#16-frontend-orderdetail--paymentresult)
17. [Preferencia de Mercado Pago — Shipping como Ítem](#17-preferencia-de-mercado-pago--shipping-como-ítem)
18. [Tabla Resumen — Trazabilidad por Método](#18-tabla-resumen--trazabilidad-por-método)
19. [Resumen de Edge Cases](#19-resumen-de-edge-cases)
20. [Archivos a Crear/Modificar](#20-archivos-a-crearmodificar)
21. [Orden de Implementación](#21-orden-de-implementación)
22. [Riesgos y Mitigaciones](#22-riesgos-y-mitigaciones)
23. [Checklist por Componente](#23-checklist-por-componente)
24. [Preguntas Abiertas para el TL](#24-preguntas-abiertas-para-el-tl)

---

## 1. Resumen Ejecutivo

La infraestructura de shipping V1 (integraciones, tracking, providers) está completa, pero **opera solo post-orden**: el admin crea envíos manualmente después de que el cliente pagó. No hay ningún enlace entre el envío y el checkout del comprador.

Este plan describe **6 bloques** para transformar el shipping en un sistema completo que impacte directamente en la experiencia de compra: opciones de entrega, costos, direcciones, tiempos, y operativa del vendedor.

**Principio rector de validación:**

> Cada dato que se configura en el admin, se selecciona en el checkout, se persiste en la orden, se muestra en el OrderDetail, y se envía en el email. Si un campo existe en algún punto del flujo, existe en TODOS.

---

## 2. Diagnóstico del Estado Actual

### 2.1 Hooks ya construidos (V1)

| Hook | Dónde | Qué hace | Estado |
|------|-------|----------|--------|
| `ShippingProvider.quoteRates()` | Interface + Andreani impl | Cotiza envío por CP | **Nunca se llama desde checkout** |
| `apply_to: 'shipping'` en `ExtraLine` | `payment-calculator.ts` | La calculadora soporta extras sobre shipping | **Nunca recibe shippingCost** |
| `shipping_address / billing_address` | Tabla `orders` (columnas) | Existen en DB | **Nunca se populan** en checkout |
| `delivery_address` en email templates | `mercadopago.service.ts` | Placeholder en email de confirmación | **Siempre null** |
| `shipments.cost` y `estimated_delivery_at` | Tabla `shipments` | Campos listos | **Nunca se muestran al comprador** |
| `PlanFeature('commerce.shipping')` | Controller guard | Gating por plan | ✅ Funciona OK |
| Hooks modulares del CartProvider | `useCheckout`, `useCartQuotes` | Arquitectura preparada para agregar `useShipping` | ✅ Listo |

### 2.2 Gaps críticos

```
CHECKOUT ACTUAL (sin shipping):
  Cart → Seleccionar plan de pago → Pagar → MP → Confirm
  ❌ No hay paso de dirección
  ❌ No hay selección de método de envío  
  ❌ No hay costo de envío en el total
  ❌ No se persiste dirección en la orden
  ❌ No hay opción "retiro en tienda" ni "coordinar por mensaje"

CHECKOUT OBJETIVO (con shipping):
  Cart → Dirección → Método de envío → Desglose con shipping → Pagar → MP → Confirm
  ✅ Dirección validada con autocompletado
  ✅ Opciones: envío a domicilio / retiro en tienda / coordinar
  ✅ Costo real del envío (cotizado o manual)  
  ✅ Tiempo estimado de entrega
  ✅ Shipping incluido en preferencia MP
  ✅ Dirección persistida en la orden
```

### 2.3 Puntos de Control (P1-P7)

Cada campo de shipping se valida en **7 puntos**:

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

## 3. Bloque 1 — Métodos de Entrega por Tenant

### 3.1 Opciones de entrega

| Opción | Slug | Descripción | Costo |
|--------|------|-------------|-------|
| Envío a domicilio | `delivery` | Envío por correo/transporte a la dirección del comprador | Según config |
| Retiro en tienda | `pickup` | El comprador retira en la dirección del vendedor | Gratis |
| Coordinar por mensaje | `arrange` | Se acuerda el método de entrega por WhatsApp/chat | Gratis |

### 3.2 Nueva tabla `client_shipping_settings`

```sql
CREATE TABLE IF NOT EXISTS client_shipping_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  
  -- ── Opciones de entrega habilitadas ──
  delivery_enabled BOOLEAN NOT NULL DEFAULT true,
  pickup_enabled BOOLEAN NOT NULL DEFAULT false,
  arrange_enabled BOOLEAN NOT NULL DEFAULT false,
  
  -- ── Datos de retiro en tienda ──
  pickup_address TEXT,
  pickup_instructions TEXT,
  pickup_lat NUMERIC(10,7),
  pickup_lng NUMERIC(10,7),
  
  -- ── Datos de "coordinar" ──
  arrange_message TEXT DEFAULT 'Nos pondremos en contacto para coordinar la entrega.',
  arrange_whatsapp TEXT,
  
  -- ── Configuración de envío ──
  free_shipping_enabled BOOLEAN NOT NULL DEFAULT false,
  free_shipping_threshold NUMERIC(12,2) DEFAULT 0,
  
  -- ── Pricing de envío ──
  shipping_pricing_mode TEXT NOT NULL DEFAULT 'zone',  -- 'zone' | 'flat' | 'provider_api'
  flat_shipping_cost NUMERIC(12,2) DEFAULT 0,
  
  -- ── Tiempo estimado ──
  default_delivery_days_min INT DEFAULT 3,
  default_delivery_days_max INT DEFAULT 7,
  
  -- ── Meta ──
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID
);

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

### 3.3 Nueva tabla `shipping_zones`

```sql
CREATE TABLE IF NOT EXISTS shipping_zones (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL REFERENCES clients(id) ON DELETE CASCADE,
  
  name TEXT NOT NULL,
  zip_codes TEXT[],
  provinces TEXT[],
  cost NUMERIC(12,2) NOT NULL DEFAULT 0,
  delivery_days_min INT DEFAULT 1,
  delivery_days_max INT DEFAULT 5,
  is_active BOOLEAN NOT NULL DEFAULT true,
  position INT NOT NULL DEFAULT 0,
  
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_sz_client ON shipping_zones(client_id);

ALTER TABLE shipping_zones ENABLE ROW LEVEL SECURITY;
CREATE POLICY sz_select_tenant ON shipping_zones FOR SELECT USING (client_id = current_client_id());
CREATE POLICY sz_write_admin ON shipping_zones FOR ALL
  USING (client_id = current_client_id() AND is_admin())
  WITH CHECK (client_id = current_client_id() AND is_admin());
CREATE POLICY server_bypass ON shipping_zones FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

### 3.4 Endpoints nuevos

```
GET  /shipping/settings              → Lee client_shipping_settings (público por tenant)
PUT  /shipping/settings              → Actualiza settings (admin)
GET  /shipping/zones                 → Lista zonas del tenant (público)
POST /shipping/zones                 → Crear zona (admin)
PUT  /shipping/zones/:id             → Editar zona (admin)
DELETE /shipping/zones/:id           → Eliminar zona (admin)
```

### 3.5 Validaciones del Admin (P1 + P2) — por método

#### Retiro en Tienda (`pickup_enabled`)

| Campo | ¿Obligatorio si `pickup_enabled=true`? | P1 (Admin UI) | P2 (API) | Motivo |
|-------|----------------------------------------|---------------|----------|--------|
| `pickup_address` | **SÍ — EXCLUYENTE** | Disable "Guardar" si vacío. Error: "Ingresá la dirección de retiro" | `if (pickup_enabled && !pickup_address?.trim()) throw 400` | El comprador necesita saber DÓNDE retirar |
| `pickup_instructions` | **SÍ — EXCLUYENTE** | Disable "Guardar" si vacío. Error: "Ingresá horarios de retiro" | `if (pickup_enabled && !pickup_instructions?.trim()) throw 400` | El comprador necesita saber CUÁNDO retirar |
| `pickup_lat` | Opcional | Autocompletado desde mapa; si vacío, no se muestra mapa | No valida | Mejora UX pero no bloquea |
| `pickup_lng` | Opcional | Mismo que lat | Mismo | Mejora UX pero no bloquea |

**Edge case:**
```
Escenario: Admin activa "Retiro en tienda" pero NO pone dirección
→ P1: Botón "Guardar" deshabilitado + "La dirección de retiro es obligatoria"
→ P2: 400 BAD_REQUEST { code: 'PICKUP_ADDRESS_REQUIRED' }
→ P3: Imposible — la opción pickup nunca se guardó, no aparece en el checkout
```

#### Coordinar por mensaje (`arrange_enabled`)

| Campo | ¿Obligatorio? | P1 | P2 | Motivo |
|-------|---------------|----|----|--------|
| `arrange_message` | No (tiene default) | Prefilled; si borra, vuelve al default | Coalesce a default si vacío | Siempre hay mensaje |
| `arrange_whatsapp` | Opcional | Si pone número, validar formato (+54...) | Regex optional: `^\+?\d{10,15}$` | Mejora UX |

**Edge case:**
```
Escenario: Admin activa "Coordinar" sin WhatsApp ni mensaje custom
→ P1: OK — se guarda con el mensaje default
→ P6: Email muestra: "Coordinaremos la entrega por este medio."
→ P7: OrderDetail muestra: "El vendedor se comunicará para coordinar la entrega"
```

#### Envío a domicilio (`delivery_enabled`)

| Campo | ¿Obligatorio? | P1 | P2 | Motivo |
|-------|---------------|----|----|--------|
| `shipping_pricing_mode` | **SÍ — EXCLUYENTE** | Select required (default: 'zone') | Enum: `['zone','flat','provider_api']` | Define cómo se cobra |
| `flat_shipping_cost` | **SÍ si mode='flat'** | Visible+required solo si flat. Min: 0 | `if (mode === 'flat' && cost < 0) throw 400` | Comprador necesita precio |
| `default_delivery_days_min` | Recomendado | Default: 3. Numérico ≥ 1 | `min >= 1, max >= min` | Mejora UX |
| `default_delivery_days_max` | Recomendado | Default: 7. Numérico ≥ min | `max >= min` | Mejora UX |
| `free_shipping_threshold` | **SÍ si free_shipping=true** | Visible+required. Min: 1 | `if (enabled && threshold <= 0) throw 400` | threshold=0 = siempre gratis (error) |

**Validación cruzada de modos de pricing:**

| `shipping_pricing_mode` | Requiere zonas | Requiere provider activo | Requiere flat_cost |
|--------------------------|---------------|-------------------------|-------------------|
| `flat` | NO | NO | **SÍ** |
| `zone` | **SÍ (≥1 zona activa)** | NO | NO |
| `provider_api` *(diferido post-MVP)* | NO | **SÍ (≥1 integración con quoteRates)** | NO |

**Edge cases:**
```
Admin elige mode='zone' pero no tiene ninguna zona creada
→ P1: Warning: "Creá al menos una zona de envío para poder cobrar"
→ P2: Se guarda el modo pero se loggea warning
→ P3: En checkout, si no matchea zona → "Envío no disponible para tu zona"
→ P4: API retorna { available: false, reason: 'NO_ZONE_MATCH' }

Admin elige mode='provider_api' pero no tiene Andreani/OCA activo (DIFERIDO POST-MVP)
→ P1: Warning: "Configurá al menos un proveedor con tarifa automática"
→ P2: Se guarda pero loggea warning
→ P3: En checkout, si provider falla → fallback a flat o zone cost
→ P4: API intenta quoteRates → catch → fallback o 422
→ NOTA: provider_api queda como feature flag "beta". Requiere product.weight_grams.

Admin pone free_shipping_enabled=true, threshold=0
→ P1: Error inline: "El monto mínimo para envío gratis debe ser mayor a $0"
→ P2: 400 BAD_REQUEST { code: 'INVALID_FREE_SHIPPING_THRESHOLD' }
```

### 3.6 UI Admin — tab "Configuración" en ShippingPanel

Agregar 3ra tab al ShippingPanel existente:
- Toggle: Envío a domicilio (sí/no)
- Toggle: Retiro en tienda (sí/no) → campos: dirección, instrucciones, mapa
- Toggle: Coordinar por mensaje (sí/no) → campos: mensaje, WhatsApp
- Toggle: Envío gratis a partir de $X
- Modo de pricing: Manual (fijo) / Por zona / Cotización API del provider
- Gestión de zonas de envío (tabla editable si modo = "por zona")
- Tiempo estimado por defecto (días mín/máx)

---

## 4. Bloque 2 — Costos de Envío en el Checkout

### 4.1 Flujo de cotización

```
1. Comprador ingresa CP (pedido en Step 1 junto con método)
2. Si eligió "delivery":
   a. Modo FLAT:     → shipping_cost = flat_shipping_cost
   b. Modo ZONE:     → shipping_cost = matchZone(zip_code).cost
   c. Modo API:      → shipping_cost = provider.quoteRates(address, items) (diferido post-MVP)
3. Si free_shipping_enabled && subtotal_con_descuento >= threshold → shipping_cost = 0
4. Backend devuelve quote_id + valid_until (TTL 15 min)
5. shipping_cost se suma al total y se incluye en la preferencia MP
```

> **Definición clave:** El umbral de envío gratis se calcula sobre **subtotal después de descuentos, antes de service fee**.

### 4.2 Endpoint de cotización

```
POST /shipping/quote
Body: {
  delivery_method: 'delivery' | 'pickup' | 'arrange',
  zip_code?: string,
  province?: string,
  subtotal: number,          // para calcular envío gratis
  cart_items: [...],
}
Response: {
  quote_id: "uuid",           // ← NUEVO: para validar en checkout
  valid_until: "ISO8601",     // ← NUEVO: TTL 15 min
  method: 'delivery',
  cost: 1500.00,
  free_shipping_applied: false,
  free_shipping_threshold: 50000,
  amount_for_free_shipping: 5000,  // ← NUEVO: falta para llegar a envío gratis
  estimated_days: { min: 3, max: 7 },
  zone_name: "GBA Norte",
}
```

> El `quote_id` se envía en `createPreferenceForPlan`. El backend revalida: si expiró o cambió el precio, recalcula y devuelve error `QUOTE_EXPIRED` para que el FE reconfirme.

### 4.3 Cambios en preferencia MP

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

### 4.4 Impacto visual en desglose del carrito

```
Subtotal                     $45.000
Descuento                    -$5.000
Envío a domicilio (GBA)      +$1.500    ← NUEVO
  └─ Envío gratis a partir de $50.000
Costo del servicio (3%)       $1.215
──────────────────────────────────────
TOTAL                        $42.715
```

### 4.5 Nuevo hook `useShipping()`

```javascript
// src/hooks/cart/useShipping.js
export function useShipping({ cartItems, subtotal }) {
  const [deliveryMethod, setDeliveryMethod] = useState(null);
  const [address, setAddress] = useState(null);
  const [shippingQuote, setShippingQuote] = useState(null);
  const [settings, setSettings] = useState(null);
  
  // GET /shipping/settings al mount
  // POST /shipping/quote cuando cambia deliveryMethod o address.zip_code
  // Retorna: { deliveryMethod, setDeliveryMethod, address, setAddress, 
  //            shippingCost, estimatedDays, isFreeShipping, availableMethods, ... }
}
```

---

## 5. Bloque 3 — Dirección del Comprador

### 5.1 Nueva tabla `user_addresses`

```sql
CREATE TABLE IF NOT EXISTS user_addresses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  client_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  
  label TEXT DEFAULT 'Casa',
  full_name TEXT NOT NULL,
  phone TEXT,
  street TEXT NOT NULL,
  street_number TEXT NOT NULL,
  floor_apt TEXT,
  city TEXT NOT NULL,
  province TEXT NOT NULL,
  zip_code TEXT NOT NULL,
  country TEXT NOT NULL DEFAULT 'AR',
  lat NUMERIC(10,7),
  lng NUMERIC(10,7),
  notes TEXT,
  is_default BOOLEAN DEFAULT false,
  
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_ua_user ON user_addresses(user_id, client_id);

ALTER TABLE user_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY ua_owner ON user_addresses FOR ALL
  USING (client_id = current_client_id() AND user_id = auth.uid())
  WITH CHECK (client_id = current_client_id() AND user_id = auth.uid());
CREATE POLICY server_bypass ON user_addresses FOR ALL
  USING (auth.role() = 'service_role')
  WITH CHECK (auth.role() = 'service_role');
```

### 5.2 Endpoints

```
GET    /addresses              → Listar direcciones del usuario
POST   /addresses              → Crear nueva dirección
PUT    /addresses/:id          → Editar
DELETE /addresses/:id          → Eliminar
POST   /addresses/validate     → Validar con geocoding (Nominatim/OSM)
```

### 5.3 Geocoding — Nominatim (gratis, sin API key)

```
POST /addresses/validate
Body: { street: "Av. Corrientes 1234", city: "CABA", province: "Buenos Aires", zip_code: "C1043" }
Response: {
  valid: true,
  formatted: "Avenida Corrientes 1234, C1043 AAZ, CABA, Argentina",
  lat: -34.6037, lng: -58.3816,
  confidence: 0.92,
  suggestions: []
}
```

- URL: `https://nominatim.openstreetmap.org/search`
- Gratis, sin API key, rate limit 1 req/sec
- User-Agent header requerido
- Fallback: si no responde, se acepta la dirección sin validar

### 5.4 UI del formulario de dirección

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

---

## 6. Bloque 4 — Tiempo Estimado de Entrega

### 6.1 Fuentes de datos

| Modo pricing | Fuente | Ejemplo |
|---|---|---|
| `manual` / `flat` | `client_shipping_settings.default_delivery_days_min/max` | "3-7 días hábiles" |
| Por zona | `shipping_zones.delivery_days_min/max` | "1-2 días hábiles (CABA)" |
| API del provider | `RateQuote.estimated_days` de `quoteRates()` | "2 días hábiles (Express)" |
| Retiro en tienda | Instantáneo (o texto del admin) | "Disponible en 24hs" |
| Coordinar | N/A | "A coordinar" |

### 6.2 Dónde se muestra

1. **Checkout** — junto a cada opción de envío
2. **Ficha de producto (PDP)** — si el comprador ya tiene dirección guardada
3. **Confirmación de orden** — "Tu pedido llegará entre el 15/02 y el 20/02"
4. **Email de confirmación** — mismo dato

### 6.3 Columnas nuevas en `orders`

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_min DATE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_max DATE;
```

---

## 7. Bloque 5 — Instrucciones Operativas para Vendedores

### 7.1 Guías por método de entrega

#### Envío a domicilio — Manual
```
1. El comprador paga → la orden queda "Pendiente"
2. Preparás el paquete
3. Vas al correo/agencia y despachás
4. Desde el panel → Pedidos → la orden → ingresás:
   - Código de seguimiento
   - URL de tracking
5. El comprador recibe email con el tracking
6. Cuando figura "Entregado", marcás como "Entregado"
```

#### Envío a domicilio — Andreani
```
1. El comprador paga → la orden queda "Pendiente"
2. Desde Pedidos → la orden → click "Crear envío"
3. Se genera automáticamente: etiqueta PDF + código de seguimiento
4. Imprimí la etiqueta y pegala en el paquete
5. Opciones: llevar a sucursal o programar retiro en domicilio
6. El tracking se actualiza automáticamente
7. El comprador recibe notificaciones por email
```

#### Retiro en tienda
```
1. El comprador paga → la orden queda "Pendiente"
2. Preparás el pedido
3. Desde Pedidos → la orden → marcás "Preparando"
4. El comprador recibe email: "Tu pedido está listo para retirar"
   con dirección y horarios
5. Cuando retira → marcás "Entregado"
```

#### Coordinar por mensaje
```
1. El comprador paga → la orden queda "Pendiente"
2. Recibís notificación (email + panel)
3. Contactás al comprador por WhatsApp/email
4. Coordinás la entrega
5. Actualizás el estado del pedido
```

### 7.2 Costos por proveedor

| Proveedor | Costo para el vendedor | Observaciones |
|-----------|----------------------|---------------|
| **Manual** | Solo el costo real del correo | NovaVision no cobra extra |
| **Andreani** | Tarifa de Andreani según contrato | Pago directo al proveedor |
| **OCA** | Tarifa de OCA según convenio | Pago directo al proveedor |
| **Correo Argentino** | Tarifa oficial según peso/destino | Pago directo al proveedor |
| **Custom** | Depende de la API configurada | El vendedor gestiona su convenio |
| **NovaVision** | Sin cargo adicional | Incluido en el plan Growth+ |

---

## 8. Bloque 6 — Flujo Completo de Checkout Rediseñado

### 8.1 Flujo propuesto

```
CartPage (resumen de productos)
  └→ Step 1: Método de entrega + CP rápido
      ├─ 📦 Envío a domicilio → pedir CP inline → cotizar → mostrar precio+días
      │     "$1.500 — 3-7 días hábiles" / "Envío gratis 🎉" / "Te faltan $7.300 para envío gratis"
      ├─ 🏪 Retiro en tienda (Gratis — Av. Corrientes 1234, L-V 9-18hs)
      │     "Retirás en el local, sin costo."
      └─ 💬 Coordinar con vendedor (Gratis)
            "Pagás ahora y coordinás entrega por WhatsApp."
            (si no hay WA: "El vendedor te contactará por email.")
      
  └→ Step 2: Dirección completa (solo si eligió "delivery")
      ├─ Direcciones guardadas (modal/bottom-sheet en mobile)
      ├─ Formulario nueva dirección (CP ya pre-filled del Step 1)
      ├─ Validación Nominatim on-demand (botón, no autocomplete)
      ├─ Mapa colapsado por default ("Ver en mapa" abre — lazy load)
      └─ Checkbox "Guardar para futuras compras" (solo si logueado)
      
  └→ Step 3: Desglose y pago
      ├─ Resumen de productos
      ├─ Línea de envío (método + costo + tiempo)
      ├─ Costo de servicio
      ├─ Total final
      ├─ Selector plan de pago
      └─ Botón "Pagar $TOTAL"
      
  └→ Redirect a Mercado Pago
  └→ PaymentResultPage (+ info de envío)
  └→ SuccessPage (+ tracking si es delivery)
```

### 8.2 Opciones de layout

**Opción A — Steps dentro del CartPage (recomendada para MVP):**
- Single page con stepper/accordion
- Steps colapsables: Entrega → Dirección → Pago
- Mínimo cambio en routing

**Opción B — Multi-page checkout:**
- Ruta `/checkout` separada
- `/checkout/shipping` → `/checkout/address` → `/checkout/payment`
- Más limpio pero mayor refactor

### 8.3 Detalle request a `createPreferenceForPlan`

```diff
  POST /mercadopago/create-preference-for-plan
  Body: {
    baseAmount: 45000,
    selection: { method: 'credit_card', installmentsSeed: 1, ... },
    cartItems: [...],
+   delivery: {
+     method: 'delivery',
+     shipping_cost: 1500,
+     address: {
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
+     save_address: true,
+     address_id: null,
+   }
  }
```

### 8.4 Componentes nuevos

```
src/hooks/cart/
  useShipping.js
  useAddresses.js

src/components/checkout/
  DeliveryMethodSelector.jsx
  AddressForm.jsx
  AddressAutocomplete.jsx
  AddressMap.jsx
  SavedAddressList.jsx
  ShippingCostSummary.jsx
  DeliveryEstimate.jsx
```

### 8.5 Dependencias nuevas

```
leaflet          — Mapas OpenStreetMap (gratis, sin API key)
react-leaflet    — Wrapper React para Leaflet
```

---

## 9. Validaciones Exhaustivas — Principio Rector

Cada campo se rastrea desde P1 (admin config) hasta P7 (render en buyer frontend):

```
Admin Config → DB Settings → Checkout UI → Request body → Pre-orden (insert) → 
  → Webhook confirm → Email template → OrderDetail (buyer) → OrderDetail (admin)
```

---

## 10. Admin Config — Validación por Método

*(Detallado en sección 3.5 arriba)*

**Resumen de campos excluyentes:**

| Si está activo... | Campo | ¿Requisito excluyente? |
|-------------------|-------|------------------------|
| `pickup_enabled` | `pickup_address` | **SÍ** |
| `pickup_enabled` | `pickup_instructions` | **SÍ** |
| `free_shipping_enabled` | `free_shipping_threshold > 0` | **SÍ** |
| `delivery_enabled` + mode `flat` | `flat_shipping_cost >= 0` | **SÍ** |
| `delivery_enabled` + mode `zone` | ≥1 zona activa | **Warning** (no hard-block) |
| `delivery_enabled` + mode `provider_api` | ≥1 integración con quoteRates | **Warning** |

---

## 11. Zonas de Envío — Validaciones

| Campo | Obligatorio | P1 (Admin) | P2 (API) |
|-------|-------------|-----------|----------|
| `name` | **SÍ** | Required. "Ingresá un nombre" | `if (!name?.trim()) throw 400` |
| `cost` | **SÍ** | Numérico ≥ 0. "Ingresá un costo" | `if (cost < 0) throw 400` |
| `zip_codes` ó `provinces` | **Al menos uno** | Si ambos vacíos: error | `if (!zip_codes?.length && !provinces?.length) throw 400` |
| `delivery_days_min/max` | Opcional | Default: global settings | Coalesce a global |

**Edge cases:**
```
Zonas solapadas (CABA 1000-1499 + Capital 1000-1200)
→ P2: Se permite (admin decide). Se usa la primera que matchee (por position ASC)
→ P1: Warning si hay solapamiento

CP del comprador no matchea ninguna zona
→ P3: "Envío no disponible para tu zona. Código postal: C1043"
→ P4: { available: false, reason: 'NO_ZONE_MATCH' }
→ El comprador puede elegir "Retiro" o "Coordinar" si están habilitados
```

---

## 12. Checkout del Comprador — Validación por Step

### Step 1: Selección de Método

| Validación | Regla | Si falla |
|------------|-------|----------|
| ¿Hay ≥1 método habilitado? | `delivery OR pickup OR arrange` | No se muestra step (sin shipping, como ahora) |
| ¿Comprador eligió método? | `delivery_method != null` | Botón "Continuar" deshabilitado |
| Solo 1 método habilitado | Auto-seleccionar | Skip del step |

**Edge case — 0 métodos:**
```
→ P3: Checkout funciona como ahora (sin paso de envío)
→ P4: delivery_method = null, shipping_cost = 0
→ P5: Columnas de shipping con defaults
→ P6: Email fallback: "Coordinaremos la entrega por este medio."
→ P7: Sin sección de envío
```

### Step 2: Dirección (solo si method = 'delivery')

| Campo | Obligatorio | P3 (Frontend) | P4 (Backend) |
|-------|-------------|---------------|--------------|
| `full_name` | **SÍ** | Required. "Ingresá tu nombre completo" | `if (!trim()) throw 400` |
| `street` | **SÍ** | Required. "Ingresá la calle" | `if (!trim()) throw 400` |
| `street_number` | **SÍ** | Required. "Ingresá la altura" | `if (!trim()) throw 400` |
| `floor_apt` | No | Libre | Sanitize |
| `city` | **SÍ** | Required. "Ingresá la ciudad" | `if (!trim()) throw 400` |
| `province` | **SÍ** | Select required. "Seleccioná provincia" | Enum (24 provincias AR) |
| `zip_code` | **SÍ** | Required + hint. "Ingresá el CP" | Regex: `/^[A-Z]?\d{4}[A-Z]{0,3}$/i` |
| `phone` | **SÍ** | Required. "Ingresá tu teléfono" | Regex: `/^\+?\d{8,15}$/` |
| `country` | No (default 'AR') | Hidden | Default 'AR' |
| `notes` | No | Textarea (max 500) | Max 500, sanitize |
| `lat`/`lng` | No | Auto-filled por geocoding | Opcionales |

**Edge case — Geocoding falla:**
```
→ P3: Nominatim no devuelve resultado → NO bloquea. Warning:
      "No pudimos verificar la dirección. Asegurate de que sea correcta."
→ P4: Se acepta sin lat/lng
→ P6: Email muestra la dirección ingresada tal cual
→ DECISIÓN: NO bloquear checkout por geocoding fallido
```

### Step 2b: Info para pickup (readonly)

```
┌─────────────────────────────────────────┐
│ 🏪 Retiro en tienda                     │
│ 📍 Av. Corrientes 1234, CABA           │  ← pickup_address
│ 🕐 Lunes a viernes de 9 a 18hs         │  ← pickup_instructions
│ [🗺️ Ver en mapa]                        │  ← si hay lat/lng
└─────────────────────────────────────────┘
```

### Step 2c: Info para arrange (readonly)

```
┌─────────────────────────────────────────┐
│ 💬 Coordinar con el vendedor            │
│ "Nos pondremos en contacto..."          │  ← arrange_message
│ [📱 Contactar por WhatsApp]             │  ← si hay WA
└─────────────────────────────────────────┘
```

---

## 13. Request de Checkout → Backend

### 13.1 Payload TypeScript

```typescript
interface CreatePreferenceBody {
  baseAmount: number;
  selection: PaymentSelection;
  cartItems: CartItem[];
  delivery?: {
    method: 'delivery' | 'pickup' | 'arrange';
    quote_id?: string;              // ← NUEVO: del quote previo, para revalidar
    address?: ShippingAddressInput; // solo si method='delivery'
    save_address?: boolean;         // solo si usuario logueado
    address_id?: string;            // UUID si usa dirección guardada
  };
}

interface ShippingAddressInput {
  full_name: string;
  street: string;
  street_number: string;
  floor_apt?: string;
  city: string;
  province: string;
  zip_code: string;
  phone: string;
  country?: string;
  lat?: number;
  lng?: number;
  notes?: string;
}
```

### 13.2 Validación P4 completa

```typescript
function validateDeliveryPayload(delivery, clientSettings) {
  // Si no hay delivery y no hay shipping config → OK (sin shipping)
  if (!delivery && !clientSettings) return { shipping_cost: 0 };
  
  // Si hay settings pero no hay delivery → DEBE elegir
  if (clientSettings && hasAnyMethodEnabled(clientSettings) && !delivery) {
    throw new BadRequestException({ code: 'DELIVERY_METHOD_REQUIRED' });
  }

  const { method, address, address_id } = delivery;

  // Validar método existe
  if (!['delivery', 'pickup', 'arrange'].includes(method))
    throw 400 'INVALID_DELIVERY_METHOD';

  // Validar método habilitado
  if (method === 'delivery' && !clientSettings.delivery_enabled) throw 400;
  if (method === 'pickup' && !clientSettings.pickup_enabled) throw 400;
  if (method === 'arrange' && !clientSettings.arrange_enabled) throw 400;

  // Si delivery → dirección obligatoria
  if (method === 'delivery' && !address && !address_id)
    throw 400 'ADDRESS_REQUIRED';

  // Cotizar shipping (desde backend, NO del frontend)
  const quote = await quoteShipping(method, resolvedAddress, clientSettings);
  
  return { shipping_cost, shipping_label, delivery_method, estimated_delivery_min/max };
}
```

---

## 14. Persistencia en la Orden — Campos EXACTOS

### 14.1 Insert de pre-orden

```diff
  .from('orders')
  .insert({
    id, user_id, client_id, payment_status: 'pending', status: 'pending',
    total_amount: totalToMp,           // ← AHORA incluye shipping_cost
    external_reference, order_items, payment_mode,
    first_name, last_name, email, phone_number,
    settlement_days, installments, method, plan_key, subtotal, public_code,
+   // ── SHIPPING V2 ──
+   delivery_method,                   // 'delivery'|'pickup'|'arrange'|null
+   shipping_cost,                     // 0 si pickup/arrange/null
+   shipping_label,                    // "Envío a CABA - $1.500"
+   shipping_address: address,                // JSONB (no stringify)
+   delivery_address: "Av. Corrientes 1234, CABA", // texto legible
+   pickup_info: "Av. Corrientes 1234 | L-V 9-18hs", // solo si pickup
+   estimated_delivery_min,
+   estimated_delivery_max,
  })
```

### 14.2 Migración

```sql
-- 20260212_order_shipping_v2_cols.sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_method TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_cost NUMERIC(12,2) DEFAULT 0;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_label TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS delivery_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS pickup_info TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_min DATE;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS estimated_delivery_max DATE;
-- shipping_address: migrar de TEXT a JSONB si existe, o crear como JSONB
ALTER TABLE orders ALTER COLUMN shipping_address TYPE JSONB USING shipping_address::jsonb;
-- billing_address también (futuro).
```

---

## 15. Email — Mapeo EXACTO de cada Campo

### 15.1 Template actual (situación)

El template inline (`renderOrderEmailHTML`) tiene `deliveryBlock` con 3 ramas:

```typescript
// ACTUAL (siempre cae al fallback porque delivery_address y pickup_info son null)
const deliveryBlock = Data.delivery_address
  ? `<p>…${Data.delivery_address}</p>`           // Nunca entra
  : Data.pickup_info
    ? `<p>…Retiro: ${Data.pickup_info}</p>`       // Nunca entra
    : `<p>…Coordinaremos la entrega…</p>`;        // SIEMPRE este
```

### 15.2 Template nuevo — deliveryBlock

```typescript
switch (deliveryMethod) {
  case 'delivery':
    deliveryBlock = [
      `<p><strong>📦 Envío a domicilio</strong></p>`,
      `<p>${order.delivery_address}</p>`,
      order.shipping_cost > 0
        ? `<p>Costo: ${formatCurrency(order.shipping_cost)}</p>`
        : `<p>Envío gratis 🎉</p>`,
      order.estimated_delivery_min && order.estimated_delivery_max
        ? `<p>Estimado: ${formatDate(min)} - ${formatDate(max)}</p>`
        : null,
    ].filter(Boolean).join('\n');
    break;

  case 'pickup':
    deliveryBlock = [
      `<p><strong>🏪 Retiro en tienda</strong></p>`,
      `<p>${order.pickup_info}</p>`,
      `<p>Gratis</p>`,
    ].join('\n');
    break;

  case 'arrange':
    deliveryBlock = [
      `<p><strong>💬 Coordinar entrega</strong></p>`,
      `<p>El vendedor se comunicará para coordinar.</p>`,
      whatsappUrl ? `<p><a href="${whatsappUrl}">Contactar por WhatsApp</a></p>` : null,
    ].filter(Boolean).join('\n');
    break;

  default:
    deliveryBlock = `<p>Coordinaremos la entrega por este medio.</p>`;
}
```

### 15.3 Fila de shipping en totales del email

```typescript
// ACTUAL tfoot: Subtotal | Servicio | Total
// NUEVO: Subtotal | Envío | Servicio | Total

const shippingRow = order.shipping_cost > 0
  ? `<tr><td>Envío (${order.shipping_label})</td><td>${formatCurrency(shipping_cost)}</td></tr>`
  : order.delivery_method === 'delivery'
    ? `<tr><td>Envío</td><td>Gratis</td></tr>`
    : ''; // No mostrar fila si pickup/arrange/null
```

### 15.4 `OrderEmailTotals` actualizado

```typescript
type OrderEmailTotals = {
  subtotal_formatted: string;
  shipping_formatted?: string | null;    // ← YA EXISTE, ahora se popula
  service_fee_formatted?: string | null;
  discount_formatted?: string | null;
  total_formatted: string;
};
```

---

## 16. Frontend OrderDetail + PaymentResult

### 16.1 OrderDetail — sección nueva

**Envío a domicilio:**
```
│ Método:     📦 Envío a domicilio                              │
│ Dirección:  Av. Corrientes 1234, 3°B, CABA (C1043AAZ)        │
│ Teléfono:   +54 11 1234-5678                                  │
│ Notas:      Timbre 3B, portero eléctrico                      │
│ Costo:      $1.500,00                                         │
│ Estimado:   15/02 - 20/02                                     │
│ Estado:     [🟢 En tránsito]                                  │
│ Tracking:   OCA-123456 (🔗 Ver seguimiento)                   │
```

**Retiro en tienda:**
```
│ Método:     🏪 Retiro en tienda                              │
│ Dirección:  Av. Corrientes 1234, CABA                        │
│ Horarios:   Lunes a viernes de 9 a 18hs                      │
│ Costo:      Gratis                                           │
```

**Coordinar:**
```
│ Método:     💬 Coordinar con vendedor                        │
│ Info:       El vendedor se comunicará para coordinar          │
│ Costo:      Gratis                                           │
│ [📱 Contactar por WhatsApp]                                  │
```

### 16.2 PaymentResultPage — agregar sección

```
✅ Compra confirmada

Subtotal:              $29.000
Envío (CABA):          $1.500          ← NUEVO
Costo del servicio:    $915
Total pagado:          $31.415

📦 Envío a domicilio                    ← NUEVO
📍 Av. Corrientes 1234, CABA           ← NUEVO
📅 Estimado: 15/02 - 20/02             ← NUEVO
```

---

## 17. Preferencia de Mercado Pago — Shipping como Ítem

### 17.1 Agregar ítem de shipping

```typescript
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

### 17.2 Validación anti-fraude (webhook)

```
Al confirmar pago (confirmPayment):
  totalEsperado = subtotal + serviceFee + shippingCost
  totalMp = paymentDetails.transaction_amount
  
  if (abs(totalEsperado - totalMp) > threshold)
    → Log alert + marcar sospechoso
```

---

## 18. Tabla Resumen — Trazabilidad por Método

### Envío a domicilio (`delivery`)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB | P6 Email | P7 OrderDetail | P7 PayResult |
|------|----------|------------|--------|-------|----------|----------------|-------------|
| `delivery_method='delivery'` | Toggle | Radio | Validado | Column | Switch template | Badge 📦 | Sección 📦 |
| Dirección completa | — | Form required | DTO validated | `shipping_address` JSON | — | Parse JSON | — |
| Dirección formateada | — | Computada | Computada | `delivery_address` text | Sección Entrega | Texto | Texto |
| Costo | Config | Desglose | Cotizado | `shipping_cost` | "$X" o "Gratis" | Fila totales | Fila totales |
| Tiempo estimado | Config días | Badge | Calculado | `estimated_delivery_*` | "dd/mm" | "dd/mm" | "dd/mm" |
| Label | — | Generado | Generado | `shipping_label` | Título fila | — | — |

### Retiro en tienda (`pickup`)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB | P6 Email | P7 OrderDetail | P7 PayResult |
|------|----------|------------|--------|-------|----------|----------------|-------------|
| `delivery_method='pickup'` | Toggle | Radio | Validado | Column | Switch | Badge 🏪 | 🏪 |
| Dirección tienda | **REQUIRED** | Readonly | De settings | `pickup_info` (parte 1) | Texto | Texto | Texto |
| Horarios tienda | **REQUIRED** | Readonly | De settings | `pickup_info` (parte 2) | Texto | Texto | — |
| Costo | $0 siempre | "Gratis" | 0 | `shipping_cost=0` | "Gratis" | "Gratis" | — |

### Coordinar (`arrange`)

| Dato | P1 Admin | P3 Checkout | P4 API | P5 DB | P6 Email | P7 OrderDetail | P7 PayResult |
|------|----------|------------|--------|-------|----------|----------------|-------------|
| `delivery_method='arrange'` | Toggle | Radio | Validado | Column | Switch | Badge 💬 | 💬 |
| Mensaje | Default/custom | Mostrado | — | — | "Coordinaremos…" | Texto | — |
| WhatsApp | Opcional | Botón WA | — | — | Link WA | Botón WA | — |
| Costo | $0 | "Gratis" | 0 | `shipping_cost=0` | — | "Gratis" | — |

### Sin shipping (retrocompatible)

| Dato | P1 | P3 | P4 | P5 | P6 | P7 |
|------|----|----|----|----|----|----|
| `delivery_method=null` | Sin toggles | Sin step | Acepta | Nulls/defaults | Fallback "Coordinaremos…" | Sin sección |

---

## 19. Resumen de Edge Cases

| # | Escenario | P1 | P2 | P3 | P4 | P5 | P6 | P7 |
|---|-----------|----|----|----|----|----|----|-----|
| 1 | Pickup SIN dirección de retiro | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 2 | Pickup SIN horarios de retiro | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 3 | Envío gratis con threshold=0 | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 4 | Flat mode pero flat_cost vacío | ❌ Block | ❌ 400 | N/A | N/A | N/A | N/A | N/A |
| 5 | Zone mode pero 0 zonas | ⚠ Warn | ✅ Log | ❌ "No disponible" | ❌ 422 | N/A | N/A | N/A |
| 6 | API mode pero 0 providers *(post-MVP)* | ⚠ Warn | ✅ Log | ❌/fallback | ❌/fallback | N/A | N/A | N/A |
| 7 | CP sin zona match | N/A | N/A | ❌ "No disponible" | ❌ 422 | N/A | N/A | N/A |
| 8 | Geocoding falla (Nominatim down) | N/A | N/A | ⚠ Warn | ✅ Accept | ✅ sin lat/lng | ✅ | ✅ |
| 9 | Delivery sin dirección | N/A | N/A | ❌ Block | ❌ 400 | N/A | N/A | N/A |
| 10 | Orden vieja sin shipping (retrocompat) | N/A | N/A | N/A | N/A | ✅ null→0 | ✅ fallback | ✅ no muestra |
| 11 | Provider API error al cotizar | N/A | N/A | ⚠ "Error" | Retry/fallback | N/A | N/A | N/A |
| 12 | Webhook: monto MP ≠ total con shipping | N/A | N/A | N/A | ⚠ Alert+log | ✅ flag | N/A | N/A |
| 13 | Admin desactiva método post-orden | N/A | N/A | N/A | N/A | ✅ orden creada | ✅ estático | ✅ |
| 14 | Solo 1 método habilitado | N/A | N/A | ✅ Auto-select | ✅ | ✅ | ✅ | ✅ |
| 15 | 0 métodos habilitados | N/A | N/A | ✅ Skip step | ✅ null/0 | ✅ | ✅ fallback | ✅ |

---

## 20. Archivos a Crear/Modificar

### Backend (API)

| Bloque | Archivo | Acción |
|--------|---------|--------|
| 1 | `migrations/backend/20260212_shipping_settings.sql` | Crear tablas |
| 1 | `src/shipping/shipping.controller.ts` | Agregar endpoints settings/zones |
| 1 | `src/shipping/shipping.service.ts` | Lógica de settings y zones |
| 1 | `src/shipping/dto/index.ts` | DTOs de settings/zones |
| 2 | `src/shipping/shipping-quote.service.ts` | **Nuevo** — cotización |
| 2 | `src/shipping/shipping.controller.ts` | POST /shipping/quote |
| 2 | `src/tenant-payments/mercadopago.service.ts` | Shipping en preferencia+orden |
| 2 | `src/payments/payment-calculator.ts` | Pasar shippingCost |
| 3 | `migrations/backend/20260212_user_addresses.sql` | Crear tabla |
| 3 | `src/addresses/addresses.module.ts` | **Nuevo módulo** |
| 3 | `src/addresses/addresses.controller.ts` | CRUD + validate |
| 3 | `src/addresses/addresses.service.ts` | Lógica + Nominatim |
| 3 | `src/addresses/nominatim.service.ts` | **Nuevo** — geocoding |
| 4 | `src/shipping/shipping-quote.service.ts` | Incluir estimated_days |
| 4 | `migrations/backend/20260212_order_shipping_cols.sql` | Columnas orders |
| 6 | `src/tenant-payments/mercadopago.service.ts` | Refactor principal |

### Frontend (Web)

| Bloque | Archivo | Acción |
|--------|---------|--------|
| 1 | `src/components/admin/ShippingPanel/ShippingSettings.jsx` | **Nuevo** |
| 1 | `src/components/admin/ShippingPanel/ShippingZones.jsx` | **Nuevo** |
| 1 | `src/components/admin/ShippingPanel/index.jsx` | 3ra tab |
| 2 | `src/hooks/cart/useShipping.js` | **Nuevo hook** |
| 2 | `src/components/checkout/ShippingCostSummary.jsx` | **Nuevo** |
| 2 | `src/pages/CartPage/index.jsx` | Shipping en desglose |
| 3 | `src/hooks/cart/useAddresses.js` | **Nuevo hook** |
| 3 | `src/components/checkout/AddressForm.jsx` | **Nuevo** |
| 3 | `src/components/checkout/AddressAutocomplete.jsx` | **Nuevo** |
| 3 | `src/components/checkout/AddressMap.jsx` | **Nuevo** (Leaflet) |
| 3 | `src/components/checkout/SavedAddressList.jsx` | **Nuevo** |
| 4 | `src/components/checkout/DeliveryEstimate.jsx` | **Nuevo** |
| 5 | `src/components/admin/ShippingPanel/ShippingGuides.jsx` | Extender |
| 6 | `src/components/checkout/DeliveryMethodSelector.jsx` | **Nuevo** |
| 6 | `src/pages/CartPage/index.jsx` | Steps de checkout |
| 6 | `src/context/CartProvider.jsx` | useShipping + useAddresses |

---

## 21. Orden de Implementación

```
FASE 1 — MVP funcional (solo flat + zone, sin provider_api):
  Bloque 1 → Settings de entrega por tenant (DB + admin UI + endpoints)
  Bloque 5 → Instrucciones operativas extendidas (solo frontend)
  
FASE 2 — Checkout con shipping:
  Bloque 3 → Direcciones del comprador (DB + endpoints + formulario SIN mapa)
  Bloque 2 → Costos de envío en checkout (quote + desglose + MP preference)
  Bloque 4 → Tiempo estimado
  
FASE 3 — Integración completa:
  Bloque 6 → Checkout rediseñado con steps

FASE 4 — Post-MVP (iteración):
  provider_api real (requiere product.weight_grams)
  Mapa Leaflet (lazy load)
  Validación geocoding on-demand
  Autocompletado de dirección
```

**Estimación total:** ~15-20 PRs, ~3000-5000 líneas nuevas entre API y Web.

---

## 22. Riesgos y Mitigaciones

| Riesgo | Mitigación |
|--------|-----------|
| Nominatim rate limit (1 req/sec) | NO autocomplete. Solo validación on-demand (botón). Cache server-side por street+city+zip (in-memory TTL) |
| Leaflet bundle size (~140KB gzip) | **Diferido post-MVP**. En MVP: solo formulario + link Google Maps externo |
| Comprador sin dirección → fricción | CP rápido en Step 1 para cotizar antes de pedir dirección completa |
| Provider API caído al cotizar | Fallback a costo zone/flat. provider_api diferido post-MVP |
| Envío gratis mal config (threshold=0) | P1+P2: validación threshold > 0 si enabled |
| Orders existentes sin campos shipping | Migración non-breaking: todas nullable/default |
| CartPage muy larga en mobile | Totales sticky abajo. Mapa colapsado. Direcciones en modal/bottom-sheet |
| Precio visto ≠ precio cobrado | quote_id + valid_until. Backend revalida; si expiró, recalcula y obliga reconfirmar |
| provider_api sin peso en productos | Diferido post-MVP. Requiere `product.weight_grams` mínimo |
| Inyección HTML en campos admin | Escapar `pickup_instructions`, `arrange_message`, `shipping_label` antes de email |
| PII en direcciones | Límite 10 por usuario. No loguear address en errores. Soft/hard delete consistente |

---

## 23. Checklist por Componente

### Al tocar `client_shipping_settings`:
- [ ] Si `pickup_enabled=true` → `pickup_address` y `pickup_instructions` NOT NULL
- [ ] Si `free_shipping_enabled=true` → `free_shipping_threshold > 0`
- [ ] Si `shipping_pricing_mode='flat'` → `flat_shipping_cost >= 0`
- [ ] Si `shipping_pricing_mode='zone'` → mínimo 1 zona activa (warning)
- [ ] Si `shipping_pricing_mode='provider_api'` → mínimo 1 integración con quoteRates (warning) *(post-MVP)*
- [ ] Escapar HTML en `pickup_instructions`, `arrange_message`, `shipping_label` antes de insertar/actualizar
- [ ] Validar `arrange_whatsapp` formato E.164 si no vacío

### Al tocar `createPreferenceForPlan`:
- [ ] `delivery.method` validado contra settings habilitados
- [ ] Si `method=delivery` → address validada (6 campos required)
- [ ] Shipping cost cotizado desde backend (no del frontend)
- [ ] Shipping_cost incluido en `totalToMp`
- [ ] Shipping como ítem en `mpItems` si > 0
- [ ] Columnas `delivery_method`, `shipping_cost`, `shipping_address`, `delivery_address`, `pickup_info`, `estimated_delivery_*` insertadas

### Al tocar `confirmPayment`:
- [ ] Si la orden ya tiene `shipping_cost`, incluirlo en validación de monto
- [ ] `buildOrderEmailData` lee: `delivery_method`, `delivery_address`, `pickup_info`, `shipping_cost`
- [ ] `OrderEmailTotals.shipping_formatted` se popula si cost > 0

### Al tocar `renderOrderEmailHTML`:
- [ ] `deliveryBlock` cubre 4 casos (delivery/pickup/arrange/null)
- [ ] Si delivery: dirección + costo + estimado
- [ ] Si pickup: dirección tienda + horarios + "Gratis"
- [ ] Si arrange: mensaje + link WhatsApp
- [ ] Si null: fallback "Coordinaremos…" (retrocompatible)
- [ ] Fila de shipping en tfoot (entre subtotal y servicio)
- [ ] **Escapar HTML** en todos los campos de texto del tenant (`pickup_instructions`, `arrange_message`, `shipping_label`) con `escapeHtml()` antes de interpolar

### Al tocar `user_addresses` / direcciones:
- [ ] Límite de 10 direcciones por usuario por client_id (check en INSERT)
- [ ] No loguear dirección completa en error messages (PII)
- [ ] Soft delete (`is_active=false`) o hard delete consistente — definir y documentar
- [ ] `GET /shipping/settings` valida tenant scope via `TenantContextGuard` (no solo header manipulable)

### Al tocar `OrderDetail`:
- [ ] `delivery_method` con badge+ícono
- [ ] Si delivery: dirección, costo, estimado
- [ ] Si pickup: dirección tienda, horarios
- [ ] Si arrange: mensaje + botón WA
- [ ] Costo de envío en desglose de totales
- [ ] Tracking + historial (no cambia)

### Al tocar `PaymentResultPage`:
- [ ] Fila de envío en desglose
- [ ] Sección "Entrega" con info del método elegido

### Seguridad y PII (transversal):
- [ ] `escapeHtml()` helper creado y usado en email templates para campos de tenant
- [ ] Rate limiting en `/shipping/quote` (max 10 req/min por user)
- [ ] No exponer lat/lng de dirección del comprador en responses públicos
- [ ] Si `arrange_enabled && !arrange_whatsapp` → backend responde mensaje alternativo ("El vendedor te contactará por email"), no botón WA muerto

---

## 24. Post-Review: Decisiones y Ajustes del TL

> Revisión realizada por el TL sobre el plan completo. Todas las decisiones aquí son **definitivas** para la implementación.

---

### 24.1 UX — CP primero, zero-friction

**Decisión:** El checkout pregunta CP **antes** de elegir método de entrega.

**Flujo definitivo Step 1 → 3:**

| Step | Contenido | Cuándo se muestra |
|------|-----------|-------------------|
| **1 — ¿Cómo querés recibirlo?** | Cards: 🚚 Envío a domicilio · 🏪 Retiro en local · 📲 Coordinar con vendedor. Si solo hay 1 habilitado → auto-seleccionado + skip. Input CP si elegió "envío" (inline, sin navegar). | Siempre |
| **2 — Dirección de entrega** | Form completo: calle, número, piso/depto, ciudad, provincia. Si user logueado → selector de dirección guardada + "Agregar nueva". Si guest → form directo. Mapa: **diferido post-MVP** (solo link Google Maps con CP+calle). | Solo si method=delivery |
| **3 — Confirmar y pagar** | Resumen con desglose: subtotal, envío (quote_id), descuento, servicio, total. Botón MP. Totales sticky en mobile. | Siempre |

**Microcopy clave:**
- Progress bar arriba: "Envío → Dirección → Pago" con upsell "¡Te faltan $X para envío gratis!"
- Si free_shipping_threshold está configurado: mostrar barra de progreso `subtotal_post_discount / threshold`
- Base del cálculo: **subtotal con descuento, antes del fee de servicio** = `sum(unit_price * qty) - discount`

**Mobile optimizaciones:**
- Totales sticky bottom (siempre visibles)
- Dirección guardada en bottom-sheet/modal (no scroll largo)
- Cards de método son tap-friendly (mín 48px touch target)
- Mapa: **NO** en MVP. Solo "Ver en Google Maps" link externo.

---

### 24.2 Data Modeling — Ajustes finales

#### `pricing_mode` renombrado: `manual` → `zone`

| Modo | Descripción | Cuándo aplica |
|------|-------------|---------------|
| `zone` | Admin define zonas manuales con rangos de CP/provincias y costos | Plan starter+ (MVP) |
| `flat` | Costo fijo para todos los envíos | Plan starter+ (MVP) |
| `provider_api` | Cotización real via Andreani/OCA/etc | Plan growth+ (**post-MVP**) |

El default en `CREATE TABLE` es `'zone'` (no `'manual'`).

#### `shipping_zones.zip_codes` — escalabilidad

**Problema identificado:** Un TEXT[] con miles de CPs escala mal en queries.

**Decisión MVP:** Las zonas se definen **por provincia** (array de nombres) como criterio principal. El campo `zip_codes` se mantiene opcional para matching fino (ej: "CABA solo 1000-1100"). Lógica de match:

```
1. Si la zona tiene zip_codes[] → match por CP primero (exacto o prefijo)
2. Si no matchea por CP o no tiene zip_codes → match por province
3. Si múltiples zonas matchean → tomar la de menor `position` (prioridad)
4. Si ninguna matchea → error "No hay envío disponible para tu zona"
```

**Post-MVP:** Evaluar tabla `shipping_zone_zips (zone_id, zip_code)` normalizada con GIN index si algún tenant necesita granularidad masiva.

#### `shipping_address` — JSONB directo

**Decisión:** La columna `shipping_address` en `orders` es `JSONB`, no TEXT.

```sql
ALTER TABLE orders ADD COLUMN IF NOT EXISTS shipping_address JSONB;
```

Insertamos directo el objeto, sin `JSON.stringify`:
```typescript
shipping_address: delivery.method === 'delivery' ? delivery.address : null,
```

Beneficios: queryable para reportes, sin doble parse, sin riesgo de escape roto.

#### `free_shipping_threshold` — base de cálculo

**Definitivo:** El threshold se compara contra `subtotal_post_discount`:
```
subtotal_post_discount = sum(unit_price × quantity) – discount_amount
```
**NO** incluye fee de servicio, **NO** incluye el propio costo de envío.

Si `subtotal_post_discount >= free_shipping_threshold` → shipping_cost = 0, label "🎉 ¡Envío gratis!"

---

### 24.3 Nominatim — Sin autocomplete

**Decisión:** NO usar Nominatim para autocomplete de direcciones.

**Razones:**
- Rate limit 1 req/sec (hard limit, IP ban si excedemos)
- Calidad de datos para Argentina: irregular
- Falsos positivos generan direcciones inválidas
- Complejidad de debounce + UX de sugerencias no justificada en MVP

**Enfoque MVP:**
- Formulario plano: calle, número, piso/depto, ciudad, CP, provincia
- Validación: solo que CP sea numérico 4 dígitos y provincia sea de la lista fija (24 provincias AR)
- Sin mapa, sin geocoding
- Link "Ver en Google Maps" con query `street+city+province` (externo, nueva pestaña)

**Post-MVP (si se necesita):**
- Validación de dirección on-demand (botón "Verificar dirección") con Nominatim, cacheado server-side
- Mapa con Leaflet (lazy loaded) como confirmación visual
- Ambos opcionales y progresivos

---

### 24.4 Consistencia de precios — quote_id + valid_until

**Problema:** Entre cotizar y pagar pueden pasar minutos/horas. Si el admin cambia la config, el precio mostrado difiere del cobrado.

**Solución:**
```typescript
// POST /shipping/quote response
{
  quote_id: 'q_abc123',           // UUID o nanoid
  valid_until: '2025-02-11T15:30:00Z',  // +30 min por defecto
  method: 'delivery',
  cost: 1500,
  currency: 'ARS',
  zone_name: 'CABA',
  amount_for_free_shipping: 3500,  // null si no aplica
  free_shipping_applied: false
}
```

**En `createPreferenceForPlan`:**
```typescript
// 1. Recibir quote_id del frontend
const { delivery } = body;  // delivery.quote_id

// 2. Revalidar la cotización
const reQuote = await this.shippingService.revalidateQuote(delivery.quote_id, clientId);
if (reQuote.expired || reQuote.priceChanged) {
  throw new BadRequestException({
    code: 'QUOTE_EXPIRED',
    message: 'El costo de envío cambió. Revisá el nuevo precio.',
    newCost: reQuote.newCost,
  });
}
// 3. Usar reQuote.cost como shipping_cost definitivo
```

**Almacenamiento de quotes:** In-memory cache (Map/Redis) con TTL 30min. No necesita tabla en DB para MVP.

---

### 24.5 Provider API — Diferido post-MVP

**Motivo:** Cotizar con Andreani/OCA requiere `weight_grams` por producto, que hoy no existe en la tabla `products`.

**Plan post-MVP:**
1. Agregar `weight_grams INT` (nullable) a `products` en multi-cliente
2. Admin UI para cargar peso por producto (con validación: si `shipping_pricing_mode='provider_api'` → `weight_grams` required)
3. Feature flag: `shipping_provider_api_beta: true` en `client_shipping_settings`
4. Quote endpoint: si mode=provider_api → sumar pesos del carrito → llamar provider → fallback a zone/flat si falla

**MVP:** Solo `flat` y `zone`. El enum en DB incluye `'provider_api'` pero la UI lo muestra grisado con tooltip "Próximamente — requiere peso por producto".

---

### 24.6 Seguridad y PII

**Reglas obligatorias:**

| Aspecto | Regla |
|---------|-------|
| HTML injection en emails | `escapeHtml()` en `pickup_instructions`, `arrange_message`, `shipping_label` antes de interpolar en `renderOrderEmailHTML` |
| Límite de direcciones | Max 10 `user_addresses` por `(user_id, client_id)`. CHECK en INSERT o trigger |
| PII en logs | **Nunca** loguear dirección completa en error messages. Solo `city + province` para debug |
| Soft delete | `user_addresses` usa `is_active=false` (el user puede "borrar" y recuperar). Hard delete solo por request explícito o GDPR |
| Tenant scope | `GET /shipping/settings` y `GET /shipping/quote` pasan por `TenantContextGuard` — el `client_id` se resuelve server-side (no solo por header manipulable) |
| Arrange sin WhatsApp | Si `arrange_enabled=true && !arrange_whatsapp` → responder "El vendedor te contactará por email" (no botón WA muerto en UI) |
| Rate limiting quotes | Max 10-20 req/min por user en `/shipping/quote` para evitar abuse |

---

### 24.7 Admin UX — Presets + Advanced

**Enfoque para ShippingPanel V2:**

**Vista por defecto:** Presets rápidos
```
┌─────────────────────────────────────────────┐
│  ¿Cómo enviás tus productos?                │
│                                              │
│  [🚚 Envío con costo fijo]  → config flat   │
│  [🗺️ Envío por zonas]      → config zones   │
│  [🏪 Solo retiro en local]  → config pickup  │
│  [📲 Coordinar por WA]     → config arrange  │
│                                              │
│  ⚙️ Configuración avanzada                   │
└─────────────────────────────────────────────┘
```

**Configuración avanzada:** Muestra todos los toggles (pickup, delivery, arrange, zonas, flat, free_shipping, etc.) como hoy pero con mejor UX:
- Cada sección colapsable
- Preview: "Así lo verá tu comprador en el checkout" (mini mockup)
- Guardar valida coherencia (no habilitar delivery sin al menos 1 zona o flat cost)

**Preview del checkout:** Sección visual que muestra cómo se ve el Step 1 con las opciones habilitadas. Esto reduce soporte ("¿por qué mi cliente no ve envío?").

---

### 24.8 MVP Scope — Recorte definitivo

**INCLUIDO en MVP (Fases 1-3):**
- ✅ `client_shipping_settings` con `flat` y `zone`
- ✅ `shipping_zones` con matching por provincia + CP opcional
- ✅ `user_addresses` (CRUD, límite 10)
- ✅ Checkout Step 1-3 (CP primero, form, confirmar)
- ✅ Inserción de shipping en orders (7 columnas)
- ✅ Email con bloque de entrega (4 variantes)
- ✅ OrderDetail con info de entrega
- ✅ PaymentResult con desglose de envío
- ✅ `quote_id + valid_until` para consistencia de precios
- ✅ Free shipping con threshold y progress bar
- ✅ Pickup + Arrange como métodos
- ✅ Admin presets + advanced config
- ✅ Seguridad: HTML escape, PII limits, rate limiting

**EXCLUIDO de MVP (Fase 4 — Post-MVP):**
- ❌ Provider API (Andreani/OCA/Correo Argentino) — requiere `weight_grams`
- ❌ Mapa Leaflet en checkout — solo link Google Maps
- ❌ Nominatim autocomplete — solo validación básica de CP
- ❌ Geocoding/lat-lng storage — no necesario sin mapa
- ❌ Tracking embebido en storefront (ya existe V1 pero no vinculado a delivery)

---

### 24.9 Decisiones pendientes de confirmar

#### A) Guest Checkout

**Pregunta:** `user_addresses` asume usuario logueado (`user_id FK`). ¿Existe guest checkout?

**Opciones:**
1. **No existe guest checkout** (actual): todo OK. Address book solo para logueados.
2. **Sí existe**: la dirección se guarda solo en `orders.shipping_address` (JSONB). No se persiste en `user_addresses`. El form pide los mismos campos pero sin "guardar dirección".

**Recomendación:** Confirmar el flujo actual. Si es solo logueados, no hay cambio. Si hay guests, agregar flag `isGuest` al flujo de checkout.

#### B) Zone Match Logic — AND vs OR

**Pregunta:** Cuando una zona tiene tanto `zip_codes[]` como `provinces[]`, ¿cómo matchear?

**Decisión propuesta (arriba en 24.2):**
```
1. zip_codes primero (exacto o prefijo) → si matchea, es ESA zona
2. Si no hay zip_codes o no matchea → fallback a provinces
3. Múltiples matches → menor position gana
```

Esto es **OR con prioridad**: zip_code es más específico, province es fallback. El admin puede definir zonas solo con provinces (simple) o agregar zip_codes para excepciones (avanzado).

**Confirmar:** ¿Este approach es correcto o preferís AND (ambos deben matchear)?

---

### 24.10 Orden de implementación actualizado

| Fase | Bloques | Entregable | Estimación |
|------|---------|------------|------------|
| **1** | B1 (Settings/Zones) + B5 (Admin Panel V2) | Admin puede configurar envío completo | 2-3 días |
| **2** | B2 (Quote) + B3 (Checkout) + Addresses | Comprador elige método y paga con envío | 3-4 días |
| **3** | B4 (Pre-order) + B6 (Email/OrderDetail/PaymentResult) | Orden persiste shipping, email, confirmación | 2-3 días |
| **4 (Post-MVP)** | Provider API + Mapa Leaflet + Nominatim | Cotización real + UX avanzada | 5-8 días |

**Total MVP (Fases 1-3):** ~7-10 días de desarrollo.

---

*Documento actualizado post-review del TL — todas las correcciones incorporadas.*

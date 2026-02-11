# Plan: Seguimiento de Órdenes Default Low-Cost + Public Code

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama BE:** feature/automatic-multiclient-onboarding
- **Rama FE:** feature/multitenant-storefront

---

## 1. Objetivo

Implementar un sistema de seguimiento de órdenes **default, simple y low-cost** que funcione out-of-the-box para todos los tenants sin configuración adicional. Incluye:

- **`public_code`**: código legible para identificar órdenes (reemplaza la exposición del UUID).
- **Tracking manual**: el admin puede cargar código de seguimiento, URL y estado de envío.
- **Búsqueda server-side**: buscar órdenes por `public_code`, email o nombre.
- **Tracking público**: endpoint sin auth donde el comprador consulta el estado de su orden.
- **QR mejorado**: el QR codifica el `public_code` en vez del UUID.
- **UI actualizada**: tabla con `public_code`, badge de envío, formulario de tracking para admin.

---

## 2. Estado Actual (Auditoría)

### Base de datos (tabla `orders` en Multicliente DB)

Columnas relevantes existentes:
- `id` (uuid, PK)
- `client_id` (uuid, FK)
- `user_id`, `external_reference`, `payment_id`
- `status`: `pending | delivered | not_delivered | cancelled`
- `payment_status`: `pending | approved | rejected | ...`
- `total_amount`, `subtotal`, `service_fee`, `customer_total`
- `tracking_code` (text) — existe pero **nunca se escribe programáticamente**
- `tracking_url` (text) — existe pero **nunca se escribe programáticamente**
- `qr_hash` (text) — hash del QR, se persiste en confirmPayment
- `order_items` (jsonb), `shipping_address`, `billing_address`, `metadata`
- `email_sent`, `email_attempts`, `fulfillment_status`

**No existe:** `public_code`, `shipping_status`

### Backend (apps/api)

- `orders.service.ts` (487 líneas): CRUD con filtro `client_id`. Usa `SUPABASE_ADMIN_CLIENT`.
- `orders.controller.ts` (161 líneas): Endpoints `GET /orders`, `GET /:orderId`, `PATCH /:orderId/status`, etc.
- `mercadopago.service.ts` (4833 líneas): `createPreferenceUnified()` inserta pre-orden. `confirmPayment()` actualiza y genera QR con UUID.
- `generateQrCode()` codifica el UUID del orderId → ilegible para humanos.

### Frontend (apps/web)

- `OrderDashboard/index.jsx` (552 líneas): Tabla con UUID, búsqueda local Fuse.js, paginación server-side.
- `OrderDetail/index.jsx` (556 líneas): Muestra tracking_code/url si existen, pero no hay forma de cargarlos.
- `statusTokens.js`: Tokens para `order.status` y `payment_status`. No hay tokens de envío.
- `PaymentResultPage/index.jsx`: Muestra tracking_code/url del response.

### Problemas identificados

1. UUID como identificador público → ilegible, no se puede dictar por teléfono.
2. QR codifica UUID → no se puede buscar manualmente.
3. No hay endpoint para que admin cargue tracking manualmente.
4. No existe `shipping_status` → no se puede indicar "preparando / enviado / entregado".
5. Búsqueda solo local (Fuse.js) → no encuentra órdenes de otras páginas.
6. No hay endpoint público de tracking para compradores.

---

## 3. Diseño de la Solución

### 3.1 Formato del `public_code`

```
NV-YYMM-XXXX
```

- `NV` → prefijo fijo NovaVision
- `YYMM` → año (2 dígitos) + mes (2 dígitos)
- `XXXX` → 4 caracteres alfanuméricos (alfabeto sin ambiguos: sin 0/O, 1/I/L)

**Alfabeto (30 chars):** `23456789ABCDEFGHJKMNPQRSTUVWXYZ`

**Capacidad:** 30^4 = 810.000 combinaciones por mes por tenant. Suficiente para >99.9% de los clientes NovaVision.

**Colisión:** Retry hasta 5 intentos + fallback a 6 chars (`NV-YYMM-XXXX-XX`).

### 3.2 Estados de envío (`shipping_status`)

| Estado | Label UI | Color |
|--------|----------|-------|
| `none` | Sin envío | gris |
| `preparing` | Preparando | naranja |
| `shipped` | Enviado | azul |
| `in_transit` | En tránsito | azul oscuro |
| `delivered` | Entregado | verde |
| `returned` | Devuelto | rojo |

### 3.3 Nuevos endpoints

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `GET` | `/orders/search?q=&page=&limit=` | Admin | Búsqueda server-side por public_code, email, nombre |
| `GET` | `/orders/track/:publicCode` | Tenant context (sin user auth) | Tracking público: status + shipping + tracking |
| `PATCH` | `/orders/:orderId/tracking` | Admin | Cargar tracking_code, tracking_url, shipping_status |

### 3.4 Cambios en QR

- `generateQrCode()` recibe `publicCode` opcional.  
- Si existe, el QR codifica el `public_code` en vez del UUID.
- El admin escanea → busca por `public_code` → encuentra la orden.

---

## 4. Archivos a crear/modificar

### Backend (apps/api)

| Archivo | Operación | Descripción |
|---------|-----------|-------------|
| `migrations/20260211_add_public_code_and_shipping.sql` | **CREAR** | ALTER TABLE orders ADD public_code, shipping_status + índices |
| `src/orders/helpers/public-code.ts` | **CREAR** | Generador de public_code con retry anti-colisión |
| `src/orders/orders.service.ts` | **MODIFICAR** | +4 métodos: generatePublicCodeForOrder, updateOrderTracking, searchOrders, getPublicTracking. Actualizar getStatusLight. |
| `src/orders/orders.controller.ts` | **MODIFICAR** | +3 endpoints: GET /search, GET /track/:publicCode, PATCH /:orderId/tracking. Reordenar rutas. |
| `src/tenant-payments/mercadopago.service.ts` | **MODIFICAR** | Asignar public_code en createPreferenceUnified. Pasar public_code a generateQrCode. |

### Frontend (apps/web)

| Archivo | Operación | Descripción |
|---------|-----------|-------------|
| `src/utils/statusTokens.js` | **MODIFICAR** | Agregar getShippingStatusToken() |
| `src/components/admin/OrderDashboard/index.jsx` | **MODIFICAR** | Mostrar public_code, búsqueda server-side, columna shipping_status |
| `src/components/OrderDetail/index.jsx` | **MODIFICAR** | Formulario de tracking para admin, mostrar public_code |

---

## 5. Detalle de migración SQL

```sql
BEGIN;

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS public_code text,
  ADD COLUMN IF NOT EXISTS shipping_status text DEFAULT 'none';

CREATE UNIQUE INDEX IF NOT EXISTS orders_client_public_code_uidx
  ON public.orders (client_id, public_code)
  WHERE public_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_public_code_pattern_idx
  ON public.orders (public_code text_pattern_ops)
  WHERE public_code IS NOT NULL;

CREATE INDEX IF NOT EXISTS orders_client_shipping_status_idx
  ON public.orders (client_id, shipping_status);

COMMIT;
```

---

## 6. Detalle helper public-code.ts

- `generatePublicCode()`: genera `NV-YYMM-XXXX` con crypto.randomBytes.
- `generateUniquePublicCode(existsChecker)`: retry loop (max 5) + fallback a 6 chars.
- Alfabeto sin ambiguos: `23456789ABCDEFGHJKMNPQRSTUVWXYZ` (30 chars).

---

## 7. Detalle cambios en orders.service.ts

### Nuevos métodos

1. **`generatePublicCodeForOrder(clientId)`** → genera código único verificando contra DB.
2. **`updateOrderTracking(orderId, userId, clientId, {tracking_code, tracking_url, shipping_status})`** → PATCH admin-only. Valida shipping_status contra set permitido.
3. **`searchOrders(userId, clientId, query, page, limit)`** → busca por public_code (ilike prefix), fallback a email/nombre.
4. **`getPublicTracking(publicCode, clientId)`** → retorna datos no sensibles: public_code, status, shipping_status, tracking_code, tracking_url, created_at.

### Modificaciones

- `getStatusLight()`: agregar `public_code` y `shipping_status` al response.
- Set de shipping statuses válidos: `none | preparing | shipped | in_transit | delivered | returned`.

---

## 8. Detalle cambios en orders.controller.ts

### Nuevos endpoints

```
GET  /orders/search?q=NV-2602&page=1     → searchOrders (admin)
GET  /orders/track/:publicCode            → getPublicTracking (tenant context, sin user auth)
PATCH /orders/:orderId/tracking           → updateOrderTracking (admin)
```

### Reordenamiento de rutas (CRÍTICO)

NestJS resuelve rutas en orden de declaración. Las rutas estáticas deben ir ANTES de las paramétrizadas:

```
@Get('search')              ← PRIMERO (estática)
@Get('track/:publicCode')   ← SEGUNDO (estática con param)
@Get(':orderId')             ← TERCERO (param genérico)
@Get('external/ref/:ref')
@Get('user/:userId')
@Get('status/:extRef')
@Patch(':orderId/status')
@Patch(':orderId/tracking')  ← NUEVO
@Post(':orderId/send-confirmation')
```

---

## 9. Detalle cambios en mercadopago.service.ts

### En createPreferenceUnified() (~L590, después del insert exitoso)

```typescript
if (insertedOrder?.id) {
  const publicCode = await this.generatePublicCodeForOrder(clientId);
  if (publicCode) {
    await this.adminClient.from('orders')
      .update({ public_code: publicCode })
      .eq('id', insertedOrder.id);
  }
}
```

**Nota:** Para evitar dependencia circular con OrdersService, se replica la lógica de generación directamente usando el helper `generateUniquePublicCode`.

### En generateQrCode() (~L860)

Agregar parámetro `publicCode?: string | null`. Si existe, el QR codifica el `publicCode` en vez del `orderId`.

### En confirmPayment() (~L1790)

Pasar `finalOrder.public_code` a `generateQrCode()` para que el QR post-pago use el código legible.

---

## 10. Detalle cambios en Frontend

### statusTokens.js

Agregar función `getShippingStatusToken(theme, status)` con mapa de 6 estados → {text, color, background}.

### OrderDashboard/index.jsx

1. Reemplazar UUID por `order.public_code` en la tabla (fallback a UUID truncado).
2. Reemplazar búsqueda Fuse.js por búsqueda server-side (`GET /orders/search?q=`).
3. Agregar columna "Envío" con badge de `shipping_status`.
4. El QR scanner ahora busca por public_code: `GET /orders/search?q={scannedCode}`.

### OrderDetail/index.jsx

1. Mostrar `public_code` en el header de la orden (en vez de UUID crudo).
2. En el accordion "Entrega y seguimiento", agregar formulario para admin:
   - Input: código de seguimiento
   - Input: URL de seguimiento
   - Select: estado de envío
   - Botón "Guardar envío" → `PATCH /orders/:orderId/tracking`
3. Agregar badge de `shipping_status` al lado del estado del pedido.

---

## 11. Riesgos y mitigación

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|-----------|
| Colisión de public_code | Muy baja | Bajo | Retry 5x + fallback 6 chars |
| Órdenes existentes sin public_code | 100% | Bajo | UI muestra UUID truncado como fallback |
| Ruta `search` matchea como `:orderId` | Alta si no se reordena | Alto | Declarar rutas estáticas ANTES de param |
| Dependencia circular MercadopagoService ↔ OrdersService | Media | Medio | Usar helper standalone, no inyectar service |
| tracking_code/tracking_url ya existen como columnas | Ninguno | Ninguno | Se reutilizan, no se crean nuevas |

---

## 12. Comandos de validación

### Backend
```bash
cd apps/api
npm run lint
npm run typecheck
npm run start:dev
```

### Frontend
```bash
cd apps/web
npm run lint
npm run dev
```

### Migración
```bash
psql "$BACKEND_DB_URL" -f migrations/20260211_add_public_code_and_shipping.sql
```

---

## 13. Tests sugeridos (futuro)

### BE unit
- `generatePublicCode()`: formato correcto, sin caracteres ambiguos.
- `generateUniquePublicCode()`: retry funciona, fallback genera 6 chars.
- `updateOrderTracking()`: valida shipping_status inválido, requiere admin.
- `searchOrders()`: busca por public_code prefix, email, nombre.
- `getPublicTracking()`: retorna solo datos no sensibles.

### FE unit
- `getShippingStatusToken()`: retorna tokens correctos para cada estado.
- OrderDashboard: muestra public_code en vez de UUID.
- OrderDetail: formulario de tracking visible solo para admin.

---

## 14. Checklist de implementación

- [ ] Migración SQL creada y ejecutada
- [ ] Helper public-code.ts creado
- [ ] OrdersService: 4 métodos nuevos + getStatusLight actualizado
- [ ] OrdersController: 3 endpoints nuevos + rutas reordenadas
- [ ] MercadopagoService: public_code en pre-orden + QR mejorado
- [ ] statusTokens.js: getShippingStatusToken agregado
- [ ] OrderDashboard: public_code, búsqueda server-side, columna envío
- [ ] OrderDetail: formulario tracking admin, badge shipping_status
- [ ] Lint + typecheck BE OK
- [ ] Lint FE OK
- [ ] Migración ejecutada en DB multicliente

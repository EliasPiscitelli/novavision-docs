# 🚀 Mejoras Futuras — NovaVision E-Commerce

**Origen:** Auditoría QA Cart → Checkout → Order → Tracking (2026-02-17)  
**Estado:** Todos los P0 y P1 fueron resueltos. Este documento lista los P2 diferidos y mejoras estructurales planificadas.  
**Prioridad:** Baja — ninguno es bloqueante para go-live.

---

## Índice

1. [Mejoras de UX (P2)](#1-mejoras-de-ux-p2)
2. [Mejoras Estructurales (S1-S5)](#2-mejoras-estructurales-s1-s5)
3. [Datos de Prueba](#3-datos-de-prueba)
4. [Decisiones de Diseño Extensibles](#4-decisiones-de-diseño-extensibles)

---

## 1. Mejoras de UX (P2)

Hallazgos de la auditoría clasificados como P2 — impacto medio, no bloqueantes.

| ID | Descripción | Contexto | Esfuerzo Est. |
|----|-------------|----------|:---:|
| P2-C2 | Probar variantes con productos reales (option_mode != 'none') | Los 10 productos existentes tienen `option_mode='none'`. No se pudo validar el flujo completo de variantes con talles/colores | 2h (datos de prueba) |
| P2-C4 | Validación client-side de stock al incrementar qty en carrito | Actualmente `updateCartItem()` valida server-side, pero el toast de UX podría mejorar. Validación client-side ayudaría a evitar roundtrips innecesarios | 1h |
| P2-K2 | CHECK constraint de formato para `zip_code` | `zip_code` es NOT NULL pero no valida formato (ej: solo numérico, 4 dígitos para Argentina). Podría aceptar valores inválidos | 30min |
| P2-K4 | Poblar `pickup_address` y `pickup_hours` con datos reales | Los tenants tienen valores placeholder. Cuando un admin habilite pickup, la UX mostrará "Retiro en: (placeholder)" | 15min (config admin) |
| P2-K5 | Poblar `arrange_whatsapp` con número real | Si se habilita "Acordar con vendedor", el link de WhatsApp necesita un número válido | 5min (config admin) |
| P2-E4 | Tabla `branches` para sucursales de pickup | No existe tabla de sucursales. Pickup usa campo texto `pickup_address`. Si se quiere soportar múltiples puntos de retiro, se necesita una tabla dedicada | 3 días |
| P2-E9 | Guest checkout → merge con cuenta | `cart_items.user_id` es nullable (guest cart posible), pero no hay lógica de merge al loguearse | 3 días |
| P2-O6 | Monitoreo de email_jobs procesados | Existe 1 email_job en DB. Verificar que se procesa correctamente con un dashboard o alerta si hay jobs fallidos acumulados | 2h |
| P2-T1 | Tracking público con más detalle | `GET /orders/track/:publicCode` existe pero podría enriquecerse con timeline visual y estimated delivery | 2 días |
| P2-MT | Tabla `order_items` sin `client_id` | La tabla `order_items` (deprecada, R3) no tiene `client_id`. Si se rehabilita en el futuro, agregar la columna y RLS | 1h |

---

## 2. Mejoras Estructurales (S1-S5)

Cambios que requieren más de 3 días de desarrollo. Planificados para fases futuras.

### S1: Address Book Completo
- **Qué:** Selección de dirección default, autocompletado con Google Places/Nominatim, normalización de calles
- **Por qué:** UX premium — evita que el usuario reescriba su dirección en cada compra
- **Esfuerzo:** 3 días
- **Dependencias:** API de geocoding, posible costo

### S2: Selector de Sucursal con Mapa
- **Qué:** Tabla `branches` con lat/lng, mapa interactivo, búsqueda por cercanía, horarios por sucursal
- **Por qué:** Hoy pickup usa un solo campo texto. Multi-sucursal requiere estructura
- **Esfuerzo:** 5 días
- **Dependencias:** Tabla `branches`, map tiles, geolocation

### S3: Timeline de Orden en Admin
- **Qué:** Activity log con actor, timestamp, acción (ej: "Admin cambió estado a 'preparing' el 17/02 a las 14:30")
- **Por qué:** Soporte y auditoría — hoy solo se ve el estado actual, no el historial
- **Esfuerzo:** 3 días
- **Dependencias:** Tabla `order_events` o campo JSONB

### S4: Notificaciones Multi-Canal
- **Qué:** Email + WhatsApp en cada cambio de estado (preparing → shipped → delivered)
- **Por qué:** Comunicación post-venta — reduce consultas al seller
- **Esfuerzo:** 3 días
- **Dependencias:** Templates de email, API de WhatsApp Business (opcional)
- **Nota:** El pipeline de `email_jobs` ya soporta esto. Solo falta agregarle los triggers en cada transición de estado

### S5: UI Countdown de Stock Reservado
- **Qué:** Mostrar timer en el frontend "Tu carrito se reserva por X minutos"
- **Por qué:** El backend ya implementa stock reservation con TTL 30min (R2). Falta la representación visual
- **Esfuerzo:** 2 días
- **Dependencias:** Endpoint para consultar TTL restante, componente React con countdown
- **Nota:** Backend completo (cron `OrderExpirationCron` + `stock_reserved` flag + `restore_stock_bulk` RPC). Solo falta UI

---

## 3. Datos de Prueba

Gaps detectados en el dataset de testing:

| Gap | Impacto | Acción |
|-----|---------|--------|
| No hay productos con `option_mode != 'none'` | No se puede testear variantes (talles, colores) end-to-end | Crear 2-3 productos con option_sets en ambos tenants |
| No hay productos de "solo retiro" vs "solo envío" | No se puede testear carrito mixto (aunque R1 decidió shipping global) | Agregar `sendMethod` variado para test manual |
| Cupón `PRUEBA` es el único | Falta testear: porcentaje, mín. compra, expirado, agotado | Crear cupones de cada tipo |
| Solo 2 tenants de prueba | Falta tenant con plan `basic` vs `growth` para diferenciar funcionalidad | Crear tenant básico para comparación |

---

## 4. Decisiones de Diseño Extensibles

Decisiones tomadas en la auditoría que se diseñaron con extensibilidad futura:

### R1: Shipping Global → Per-Product (futuro)
- **Decisión actual:** Shipping es global por tenant. `products.sendMethod` es solo badge visual.
- **Extensión futura:** Agregar `product.allowed_delivery_methods[]` (array nullable, null = todos). En checkout, calcular intersección de métodos compatibles para todos los items del carrito.
- **Cuándo:** Cuando un cliente tenga productos mixtos (físicos + digitales, o muebles + accesorios).

### R2: Stock Reservation → TTL Configurable (futuro)
- **Decisión actual:** TTL fijo de 30 minutos, cron cada 5 minutos.
- **Extensión futura:** TTL configurable por tenant (`client_settings.stock_reservation_ttl_minutes`). Notificación al usuario 5 min antes de expirar.
- **Cuándo:** Cuando algún cliente requiera ventanas diferentes (ej: 15 min para flash sales).

### R3: JSONB → Hybrid (futuro)
- **Decisión actual:** `orders.order_items` JSONB es fuente de verdad. Tabla `order_items` deprecada.
- **Extensión futura:** Si se necesitan queries SQL complejas sobre items (reports, analytics), rehabilitar tabla `order_items` con `client_id`, `selected_options`, `product_name`, `image_url` y trigger de sync desde JSONB.
- **Cuándo:** Cuando el volumen de órdenes requiera reports SQL nativos en vez de parsear JSONB.

### R4: Guest Checkout (futuro)
- **Decisión actual:** No implementado. Bajo ROI vs complejidad.
- **Extensión futura:** Session-based cart con merge post-login. `cart_items.user_id` ya es nullable, lo que facilitaría la implementación.
- **Cuándo:** Cuando métricas muestren abandono significativo en el paso de registro.

---

## Priorización Sugerida

| Prioridad | Items | Justificación |
|:---------:|-------|---------------|
| 1 | S4 (Notificaciones multi-canal) | Más impacto en UX post-venta con menor complejidad (pipeline ya existe) |
| 2 | S5 (UI countdown) | Backend ya hecho, solo falta frontend. Diferenciador visual |
| 3 | S3 (Timeline admin) | Reduce tickets de soporte "¿qué pasó con mi pedido?" |
| 4 | S1 (Address book) | Mejora conversión en compras recurrentes |
| 5 | S2 (Sucursales) | Solo si algún cliente tiene multi-sucursal |

---

*Documento generado a partir de la auditoría QA 2026-02-17. Actualizar conforme se implementen las mejoras.*

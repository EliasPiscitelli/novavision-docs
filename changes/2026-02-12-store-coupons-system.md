# Cambio: Sistema completo de cupones de descuento para tiendas

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Rama:** feature/automatic-multiclient-onboarding
- **Alcance:** Backend (API) + Frontend (Web admin + checkout)

---

## Resumen

Implementación end-to-end del sistema de cupones de descuento para las tiendas NovaVision. Permite a los administradores de cada tienda (tenant) crear, gestionar y aplicar cupones desde su dashboard, y a los compradores aplicarlos en el checkout.

---

## Archivos creados / modificados

### Documentación

| Archivo | Acción |
|---------|--------|
| `novavision-docs/architecture/STORE_COUPONS_DESIGN.md` | NUEVO – Diseño completo (DB, API, FE, flujos) |

### Backend (apps/api)

| Archivo | Acción |
|---------|--------|
| `migrations/backend/20260210_store_coupons.sql` | NUEVO – 3 tablas, 9 índices, 4 ALTER, 11 políticas RLS, 3 funciones RPC, 1 trigger |
| `src/store-coupons/store-coupons.module.ts` | NUEVO – Módulo NestJS |
| `src/store-coupons/store-coupons.service.ts` | NUEVO – Servicio (~430 líneas): CRUD, validate, redeem, reverse, deriveStatus |
| `src/store-coupons/store-coupons.controller.ts` | NUEVO – 8 endpoints REST |
| `src/store-coupons/dto/create-store-coupon.dto.ts` | NUEVO – DTO de creación |
| `src/store-coupons/dto/update-store-coupon.dto.ts` | NUEVO – DTO de actualización |
| `src/store-coupons/dto/validate-coupon.dto.ts` | NUEVO – DTO de validación |
| `src/store-coupons/__tests__/store-coupons.service.spec.ts` | NUEVO – 28 tests unitarios del servicio |
| `src/store-coupons/__tests__/store-coupons.controller.spec.ts` | NUEVO – 9 tests unitarios del controlador |
| `src/app.module.ts` | MODIFICADO – Importa StoreCouponsModule |
| `src/tenant-payments/mercadopago.module.ts` | MODIFICADO – Importa StoreCouponsModule |
| `src/tenant-payments/mercadopago.service.ts` | MODIFICADO – Aplica descuento en checkout + reversión en webhook |
| `src/tenant-payments/dto/mercadopago.dto.ts` | MODIFICADO – Campos de cupón en CreatePreferenceDto |
| `src/common/featureCatalog.ts` | MODIFICADO – Feature flag `store_coupons` |

### Frontend – Web (apps/web)

| Archivo | Acción |
|---------|--------|
| `src/components/admin/CouponDashboard/index.jsx` | NUEVO – Dashboard CRUD admin con selector de targets |
| `src/components/admin/CouponDashboard/style.jsx` | NUEVO – Estilos styled-components |
| `src/components/checkout/CouponInput/index.jsx` | NUEVO – Input de cupón en checkout |
| `src/components/checkout/CouponInput/style.jsx` | NUEVO – Estilos styled-components |
| `src/context/CartProvider.jsx` | MODIFICADO – Estado de cupón aplicado |
| `src/hooks/useCheckout.js` | MODIFICADO – Envía cupón al crear preferencia MP |
| `src/pages/CheckoutStepper/index.jsx` | MODIFICADO – Renderiza CouponInput |
| `src/pages/AdminDashboard/index.jsx` | MODIFICADO – Ruta /admin/coupons |

---

## Diseño de base de datos

### Tablas nuevas

1. **`store_coupons`** – Definición del cupón (code, discount_type, discount_value, target_type, min_subtotal, max_uses, starts_at, ends_at, is_active, archived_at, etc.)
2. **`store_coupon_targets`** – Relación M:N para scope products/categories (coupon_id, target_id, target_type)
3. **`store_coupon_redemptions`** – Registro de cada uso (coupon_id, order_id, user_id, discount_amount, breakdown JSONB)

### Columnas agregadas a tablas existentes

- `orders.coupon_id` (FK → store_coupons.id, nullable)
- `orders.coupon_code` (text, nullable)
- `orders.coupon_discount` (numeric, default 0)
- `orders.coupon_breakdown` (jsonb, nullable)

### Funciones RPC

- `redeem_store_coupon(...)` – Redención atómica (check + insert + increment en una transacción)
- `reverse_store_coupon_redemption(...)` – Reversión atómica (delete redemption + decrement)
- `fn_check_coupon_targets(...)` – Valida que los items del carrito cumplan con los targets del cupón

### RLS

- 11 políticas con patrón: `server_bypass` + `select_tenant` (client_id = current_client_id()) + `write_admin` (is_admin())

---

## Endpoints API

| Método | Ruta | Rol | Descripción |
|--------|------|-----|-------------|
| GET | `/store-coupons` | admin | Listar cupones (paginado) |
| GET | `/store-coupons/:id` | admin | Detalle con targets y stats |
| POST | `/store-coupons` | admin | Crear cupón |
| PUT | `/store-coupons/:id` | admin | Actualizar cupón |
| DELETE | `/store-coupons/:id` | admin | Archivar (soft delete) |
| POST | `/store-coupons/validate` | user/admin | Validar código en checkout |
| GET | `/store-coupons/:id/redemptions` | admin | Historial de usos |
| POST | `/store-coupons/:id/reverse-redemption` | admin | Revertir uso |

---

## Flujos principales

### Aplicación en checkout
1. Usuario ingresa código → `POST /store-coupons/validate` con items del carrito
2. Si válido, FE muestra descuento y actualiza totales
3. Al confirmar → `POST /payments/create-preference` incluye `coupon_id`, `coupon_code`, `coupon_discount`, `coupon_breakdown`
4. Backend aplica descuento al total de la preferencia MP y redime el cupón atómicamente

### Reversión automática en webhook
1. MP notifica pago fallido/rechazado/reembolsado
2. `MpRouterService.handleWebhook()` → `markOrderPaymentStatus()`
3. Si la orden tiene `coupon_id` y el status mapeado es `cancelled` → llama `storeCouponsService.reverseRedemption()`
4. Se decrementa `times_redeemed` y se elimina el registro de redención (non-blocking, try/catch)

---

## Tests

- **Controller:** 9 tests (todos los endpoints)
- **Service:** 28 tests (list, getById, create, update, archive, validate, redeem, reverse, deriveStatus)
- **Total:** 37/37 passing ✅

---

## Cómo probar

### Backend
```bash
cd apps/api
npx jest --testPathPattern="store-coupons" --no-coverage --verbose
npm run lint
npm run typecheck
npm run build
```

### Frontend
```bash
cd apps/web
npm run build
```

### Migración
Ejecutar `migrations/backend/20260210_store_coupons.sql` contra la DB multicliente.

### Flujo manual
1. Admin: crear cupón desde /admin/coupons con tipo percentage/fixed, scope all/products/categories
2. Comprador: ingresar código en checkout, verificar descuento aplicado
3. Confirmar pago → verificar redención en historial
4. (Opcional) Simular webhook de rechazo → verificar reversión

---

## Notas de seguridad

- Todas las tablas nuevas tienen RLS habilitado con `server_bypass` + filtro por `client_id`
- La redención es atómica (función RPC con transacción) para evitar race conditions
- Los precios se calculan server-side (nunca se confía en el monto del frontend)
- La reversión en webhook es non-blocking para no afectar el flujo principal del webhook
- Feature flag `store_coupons` permite habilitar/deshabilitar por cliente

---

## Riesgos y consideraciones

- **Migración:** Requiere ejecutar el SQL de migración antes del deploy
- **Feature flag:** La feature está gateada por `store_coupons` en `featureCatalog` — activar por cliente
- **Concurrencia:** La función RPC `redeem_store_coupon` usa transacción para evitar sobre-redención
- **Rollback:** Las tablas y funciones pueden eliminarse sin afectar el flujo existente (las columnas en `orders` son nullable con default 0/null)

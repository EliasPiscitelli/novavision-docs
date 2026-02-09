# Cambio: Security & Robustness Audit Fixes

- **Autor:** agente-copilot
- **Fecha:** 2025-07-22
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos modificados

### P0 — RolesGuard en controllers admin (seguridad crítica)
- `src/products/products.controller.ts`
- `src/categories/categories.controller.ts`
- `src/banner/banner.controller.ts`
- `src/logo/logo.controller.ts`
- `src/faq/faq.controller.ts`
- `src/service/service.controller.ts`
- `src/contact-info/contact-info.controller.ts`
- `src/social-links/social-links.controller.ts`
- `src/home/settings.controller.ts`
- `src/home/home-settings.controller.ts`

### Fixes de lógica de pagos y carrito
- `src/tenant-payments/mercadopago.service.ts`
- `src/tenant-payments/mercadopago.controller.ts`
- `src/cart/cart.service.ts`

## Resumen de cambios

### FIX 1 — P0: RolesGuard en 10 controllers (SEGURIDAD CRÍTICA)
**Problema:** Las operaciones de escritura (POST/PUT/PATCH/DELETE) en 10 controllers admin no tenían protección de roles. Cualquier usuario autenticado con `role: 'user'` podía crear/editar/eliminar productos, banners, categorías, FAQs, servicios, contacto, social links y settings.

**Solución:** Se agregó `@UseGuards(RolesGuard)` + `@Roles('admin', 'super_admin')` en los 20+ métodos de escritura afectados. Los endpoints de lectura (GET) siguen públicos por diseño (catálogo).

**Impacto:** Un comprador ya no puede modificar la tienda. Solo admin y super_admin tienen permisos de escritura.

### FIX 2 — validateStock: no swallowing errors
**Problema:** En `createPreferenceUnified`, el `validateStock()` estaba dentro de un `try/catch` que solo logueaba un warning. Resultado: los usuarios podían comprar items con stock=0.

**Solución:** Se removió el try/catch. Ahora `validateStock` propaga la excepción y el usuario recibe un error 400 claro indicando que no hay stock.

### FIX 3 — Amount validation en confirmPayment
**Problema:** No se validaba que `paymentDetails.transaction_amount` fuera >= al `totalAmount` de la orden. Un atacante podía pagar menos manipulando la preferencia.

**Solución:** Se agregó validación post-idempotency-check: si `paidAmount < totalAmount * 0.99` (tolerancia 1% por redondeos de cuotas), se lanza error y se loguea como posible fraude.

### FIX 4 — confirm-by-reference: user check
**Problema:** El endpoint `POST /mercadopago/confirm-by-reference` permitía que un usuario B confirmara la orden de un usuario A si conocía el `external_reference`. Solo logueaba un warning y devolvía la confirmación sin detalles.

**Solución:** Ahora devuelve `403 FORBIDDEN` con code `USER_MISMATCH` cuando el caller no es el dueño de la orden.

### FIX 5 — Email query missing fields
**Problema:** La query que carga datos del cliente para el template de email post-compra no incluía `support_email, contact_phone, address, whatsapp_url`. Resultado: el bloque "¿Necesitás ayuda?" del email siempre aparecía vacío.

**Solución:** Se agregaron los 4 campos faltantes al SELECT de la query en `confirmPayment`.

### FIX 6 — Cart product availability check
**Problema:** `cart.service.ts` no filtraba por `available=true` al agregar items al carrito. Un usuario podía agregar productos inactivos/deshabilitados.

**Solución:** Se agregó `.eq('available', true)` a la query del producto en `addItemToCart`.

## Cómo probar

```bash
# Typecheck
cd apps/api && npx tsc --noEmit

# Lint
npm run lint

# Verificación funcional:
# 1. Login como user → intentar POST /products → debe dar 403
# 2. Login como admin → POST /products → debe funcionar
# 3. Intentar comprar con stock=0 → debe dar error en create-preference
# 4. Verificar que emails post-compra muestren datos de contacto
# 5. Intentar agregar producto con available=false al carrito → debe dar error
```

## Notas de seguridad

- **FIX 1 es P0**: resuelve la vulnerabilidad más crítica. Sin este fix, cualquier comprador registrado podía alterar la tienda completa.
- **FIX 3** previene fraude por manipulación de montos. La tolerancia del 1% es conservadora (por redondeos de cuotas/fees de MP).
- **FIX 4** cierra un vector donde un usuario podía forzar la confirmación de órdenes ajenas.
- Todos los cambios son backward-compatible. No hay breaking changes para los clientes admin existentes.

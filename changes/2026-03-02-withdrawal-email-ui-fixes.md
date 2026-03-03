# Cambio: Emails de devolución, detalle de pedido y logo NovaVision

- **Autor:** agente-copilot
- **Fecha:** 2026-03-02
- **Rama BE:** feature/automatic-multiclient-onboarding
- **Rama FE:** develop → cherry-pick a feature/multitenant-storefront

---

## Archivos modificados

### Backend (templatetwobe)

| Archivo | Cambio |
|---|---|
| `src/common/email/email-branding.constants.ts` | `PLATFORM_LOGO_URL` → `logo-name.svg` (logo completo con nombre) |
| `src/common/email/email-template.service.ts` | Headers y footers de email usan `PLATFORM_LOGO_URL` (logo con nombre) en vez de `PLATFORM_LOGO_PNG` (solo ícono). Platform header: 200px ancho. Powered-by footer: 120px. Platform footer: 140px. |
| `src/legal/legal-notification.service.ts` | Email comprador: reescrito con tema oscuro (#0f121a/#10131b) igualando confirmación de pedido; logo de la tienda grande; disclaimer legal reemplaza referencia a `novavision.contact@gmail.com`. Email vendedor: incluye nombre del comprador, teléfono, total del pedido, botón WhatsApp. |
| `src/legal/legal.service.ts` | Query de orden ampliada con `first_name, last_name, phone_number, total_amount, customer_total`. Pasa datos del comprador al servicio de notificación. |
| `src/tenant-payments/mercadopago.service.ts` | Eliminado fallback teléfono `'0000000000'`. Nuevo flujo: MP phone → perfil auth Supabase → null. |

### Frontend (templatetwo)

| Archivo | Cambio |
|---|---|
| `src/components/OrderDetail/index.jsx` | **Double `$$`:** 14 ubicaciones corregidas (se eliminó `$` literal redundante, `fmt()` ya incluye el signo). **Crash post-devolución:** `onRefreshOrder` recibe objeto completo + guard en `OrderDashboard`. **Tracking para comprador:** la carga de withdrawal funciona para admin y buyer (antes solo admin); el buyer ve código de seguimiento, estado detallado y motivo de rechazo si aplica. **Botones centrados:** `justifyContent: "center"` en contenedores de acción. **Cupón en detalle de costos:** nueva fila verde con código de cupón y monto de descuento. |

---

## Resumen

### Emails de devolución
- Email al comprador ahora usa tema oscuro consistente con confirmación de pedido
- Eliminada referencia a `novavision.contact@gmail.com`, reemplazada con disclaimer legal
- Email al vendedor incluye nombre, teléfono y total del comprador + botón WhatsApp

### Logo NovaVision en emails
- Todos los headers y footers de email ahora usan `logo-name.svg` (logo completo con nombre "NOVAVISION")
- URL estable: `https://novavision.lat/logo/logo-name.svg`

### Detalle de pedido (UI)
- Eliminados signos `$$` duplicados (14 ubicaciones)
- Arreglado crash al aprobar/rechazar devolución
- Comprador puede ver tracking de devolución, estado y motivo de rechazo
- Botones de acción centrados
- Cupón visible en detalle de costos (`🏷️ Cupón (CÓDIGO) - $monto`)

### Teléfono
- Eliminado fallback `0000000000` en webhook de MP. Ahora se intenta phone de MP → phone de auth profile → null.

---

## Por qué

- UX: corregir inconsistencias visuales en emails y detalle de pedido
- Branding: logo con nombre completo identifica mejor a NovaVision
- Legal: disclaimer correcto reemplaza email de contacto de plataforma
- DX: comprador necesita ver el estado de su devolución sin contactar al vendedor

## Cómo probar

1. **Email de devolución:** crear orden pagada → solicitar devolución → verificar emails enviados (comprador: tema oscuro con logo de tienda; vendedor: datos del comprador + WhatsApp)
2. **Logo:** verificar header y footer de emails de platform/lifecycle muestran logo con nombre
3. **Detalle de pedido:** abrir cualquier orden → verificar que no hay `$$` → verificar cupón visible → verificar botones centrados en panel admin
4. **Tracking buyer:** como comprador, abrir orden con devolución → verificar código de seguimiento y estado

## Notas de seguridad

- El endpoint `GET /legal/withdrawal/order/:orderId` ahora es accesible por buyer (antes solo admin). Seguro porque: filtra por `client_id` y el buyer solo accede a órdenes propias via OrderDetail.
- No se exponen credenciales ni service keys.

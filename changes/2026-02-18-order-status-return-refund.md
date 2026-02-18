# Order Status — Nuevos estados return_requested y refunded

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

## Resumen

Se agregaron dos nuevos estados al ciclo de vida de órdenes para soportar el flujo de devolución (Ley 24.240):

- `return_requested`: comprador solicitó devolución/arrepentimiento
- `refunded`: orden reembolsada exitosamente

### Máquina de estados actualizada
```
pending → paid → shipped → delivered → return_requested → refunded
       → cancelled
```

## Archivos modificados

### Backend
- `src/tenant-payments/helpers/status.ts` — OrderStatus enum con nuevos valores
- `src/orders/orders.service.ts` — Lógica para transiciones de estado
- `src/tenant-payments/mercadopago.service.ts` — Mapeo de estados MP

### Web
- `src/utils/statusTokens.js` — Tokens visuales (color, label, icono) para los nuevos estados
- `src/components/admin/OrderDashboard/index.jsx` — Dashboard admin muestra nuevos estados
- `src/components/OrderDetail/index.jsx` — Detalle de orden con acciones de devolución

## Tokens visuales

| Estado | Color | Label | Icono |
|--------|-------|-------|-------|
| return_requested | amber/warning | Devolución solicitada | ↩️ |
| refunded | purple/info | Reembolsado | 💰 |

## Cómo probar
1. Crear orden y pagarla (estado: paid)
2. Solicitar devolución (estado: return_requested)
3. Admin aprueba (estado: refunded)
4. Verificar labels y colores en OrderDashboard y OrderDetail

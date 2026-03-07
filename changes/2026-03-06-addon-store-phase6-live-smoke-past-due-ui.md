# Cambio: addon store live smoke, notificación past_due y operación super admin

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama: sin commit en esta sesión
- Archivos:
  - apps/api/src/addons/addons-notification.service.ts
  - apps/api/src/addons/addons.service.ts
  - apps/api/src/addons/addons.admin.controller.ts
  - apps/api/src/addons/addons.module.ts
  - apps/api/src/addons/addons.service.spec.ts
  - apps/api/scripts/addon-store-live-smoke.js
  - apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx
  - apps/admin/src/__tests__/AddonPurchasesView.test.tsx

## Resumen

Se agregó notificación al tenant cuando un uplift recurrente entra en `past_due`, una superficie super admin para listar estados recurrentes y disparar la reconciliación desde UI, y un script reproducible de smoke live para sembrar compras reales de addon store en ambiente.

En una iteración posterior de la misma fase también se sumó la acción manual para generar `billing_adjustments` mensuales desde el admin y se refinó el copy del email `addon_past_due` para dejarlo listo para operación real.

## Por qué

La fase previa ya tenía purchases, fulfillments y reconciliación, pero faltaba validación con datos vivos y una salida operativa visible para el caso crítico de deuda vencida. Esta subfase cierra ese gap con evidencia real, notificación merchant-facing y operación centralizada desde el admin.

## Cambios principales

- API:
  - Nuevo `AddonsNotificationService` que encola `email_jobs` tipo `addon_past_due` con `dedupe_key` por cuenta, addon y período.
  - `AddonsService.reconcileRecurringAddonStatuses()` ahora marca `past_due`, resincroniza entitlements y dispara la notificación.
  - Nuevo endpoint `GET /admin/addons/recurring/statuses` para exponer uplifts recurrentes con deuda vencida y contexto de cuenta.
  - Nuevo script `scripts/addon-store-live-smoke.js` para crear una compra de servicio, completar fulfillment, comprar un uplift y forzar su paso a `past_due`.
  - Compatibilidad agregada para esquemas legacy de `account_addons` que todavía exigen `addon_id` además de `addon_key`.
- Admin:
  - `AddonPurchasesView` ahora lista uplifts recurrentes, permite filtrar por `active/past_due` y ejecutar la reconciliación manual desde la misma pantalla.
  - La misma vista ahora permite generar `billing_adjustments` del período operativo antes de reconciliar estados.
  - Test puntual agregado para cubrir la carga combinada de purchases + recurrentes.
- Notificación:
  - El email `addon_past_due` ahora incluye pasos concretos, CTA directo a facturación y texto plano para el worker de emails.

## Evidencia de smoke live

Cuenta usada: `f6740bf8-9a6d-495f-ae61-9e61aeeceea9` (`farma`)

Resultado observado:

- Compra service creada y finalizada con fulfillment `done`.
- Compra uplift `extra_products_5k` aprobada y luego marcada `past_due` por ajuste vencido.
- `email_jobs` recibió una fila `addon_past_due` con `dedupe_key` `addon_past_due:f6740bf8-9a6d-495f-ae61-9e61aeeceea9:extra_products_5k:2026-03-01`.
- `account_addons` quedó en `past_due` con `past_due_adjustment_ids` y trazabilidad del pago manual del smoke.

## Cómo probar

API:

```bash
cd apps/api
npm run typecheck
npm run build
npx jest src/addons/addons.service.spec.ts --runInBand
node scripts/addon-store-live-smoke.js f6740bf8-9a6d-495f-ae61-9e61aeeceea9 mariabelenlauria@gmail.com
```

Admin:

```bash
cd apps/admin
npm run lint
npm run typecheck -- --pretty false
npm run build
npx vitest run src/__tests__/AddonPurchasesView.test.tsx
```

## Notas de seguridad

- No se expusieron credenciales nuevas ni se tocaron claves de servicio en frontend.
- La notificación reutiliza `email_jobs`, por lo que mantiene el worker y el patrón de deduplicación existentes.
- El soporte legacy de `addon_id` en `account_addons` evita romper ambientes mixtos mientras la tabla no quede homogeneizada.
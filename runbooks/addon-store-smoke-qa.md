# Addon Store Smoke QA

## Objetivo

Validar el flujo completo del addon store después de cambios en catálogo, cupones, purchases, fulfillments y uplifts mensuales.

## Precondiciones

- API levantada con acceso a Admin DB y Backend DB.
- Admin y Web levantados localmente o en un ambiente QA estable.
- Cuenta tenant de prueba con plan `growth` o superior.
- Un cupón activo con `promo_config.scopes = ['addon_store']` y, si aplica, `target_addon_keys` configurado.
- La migración `20260306_addon_store_purchases_and_fulfillment.sql` aplicada.

## Caso 1: compra SEO o servicio con cupón

1. Entrar al dashboard tenant y abrir `Addon Store`.
2. Elegir un addon SEO o de servicio y cargar un cupón válido.
3. Iniciar checkout.
4. Confirmar que la preferencia se crea sin error y que el historial tenant muestra una compra `pending`.
5. Simular o completar el pago.
6. Verificar que el historial tenant actualiza estado a `paid`, `pending_fulfillment` o `fulfilled` según el tipo de addon.
7. Verificar en super admin que la compra aparece en `Addon Store Ops` con metadata de cupón.

Resultado esperado:

- El cupón se valida sólo si su scope incluye `addon_store`.
- El historial tenant y la vista global de super admin muestran el mismo purchase.
- Si es un servicio, debe existir o poder crearse el fulfillment asociado.

## Caso 2: fulfillment manual de servicio

1. Desde super admin abrir `Addon Store Ops`.
2. Filtrar la compra de servicio por `pending_fulfillment`.
3. Completar campos operativos y actualizar el fulfillment.
4. Confirmar que el estado cambia y que la compra refleja la actualización.

Resultado esperado:

- El detalle de la compra carga sin error.
- El fulfillment queda persistido y visible en recarga.

## Caso 3: compra de uplift mensual

1. Desde tenant comprar `extra_products_5k`.
2. Completar o simular el pago aprobado.
3. Verificar que se crea una fila activa en `account_addons`.
4. Verificar que `clients.entitlement_overrides.products_limit` refleja el delta del addon.

Consultas sugeridas:

```sql
select account_id, addon_key, status, purchased_at, metadata
from account_addons
where account_id = '<ACCOUNT_ID>';

select id, nv_account_id, entitlement_overrides
from clients
where nv_account_id = '<ACCOUNT_ID>';
```

Resultado esperado:

- El uplift queda activo una sola vez.
- El override efectivo se sincroniza en backend.

## Caso 4: cargo mensual del uplift

1. Ejecutar el cron o método manual que genera `billing_adjustments` mensuales para addons recurrentes.
2. Verificar que se crea un `billing_adjustment` de tipo `addon_subscription` para el periodo actual.
3. Si la cuenta tiene `auto_charge=true`, verificar que el cargo pueda entrar al pipeline normal de cobranza.

Consulta sugerida:

```sql
select tenant_id, period_start, type, resource, amount_usd, status, notes
from billing_adjustments
where tenant_id = '<ACCOUNT_ID>'
  and type = 'addon_subscription'
order by created_at desc;
```

Resultado esperado:

- Sólo una fila por addon/período.
- No se duplica el primer mes de un uplift recién comprado.

## Caso 5: política past_due de uplifts

1. Dejar un `billing_adjustment` de tipo `addon_subscription` impago para un período anterior al actual.
2. Ejecutar la reconciliación manual o esperar el cron diario.
3. Verificar que `account_addons.status` pasa a `past_due`.
4. Confirmar que el `entitlement_overrides` del cliente deja de incluir el delta del uplift.
5. Marcar el ajuste como cobrado y volver a ejecutar la reconciliación.
6. Verificar que el addon vuelve a `active` y que el override reaparece.

Consultas sugeridas:

```sql
select account_id, addon_key, status, metadata
from account_addons
where account_id = '<ACCOUNT_ID>';

select tenant_id, period_start, type, resource, status, amount_usd
from billing_adjustments
where tenant_id = '<ACCOUNT_ID>'
  and type = 'addon_subscription'
order by period_start desc;
```

Resultado esperado:

- Un uplift con deuda vencida pierde capacidad efectiva hasta regularizar el pago.
- Una vez regularizado, la reconciliación devuelve el addon a `active` y recompone los entitlements.

## Validación mínima técnica

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm run test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build

cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npx vitest run src/__tests__/AddonPurchasesView.test.tsx
npm run typecheck
npm run build

cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web
npm run typecheck
npm run build
```

## Riesgos conocidos

- El typecheck de admin depende de aliases cross-repo; debe correrse con los shims de typecheck locales.
- Si la base no tiene datos reales de addon store, el smoke QA queda acotado a validaciones estructurales, queries vacías y ejecución segura de los triggers manuales.
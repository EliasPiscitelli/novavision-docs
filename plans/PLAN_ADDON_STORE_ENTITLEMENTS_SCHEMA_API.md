# Plan: Addon Store Entitlements Schema and API Design

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Estado: diseño previo a implementación

## 1. Objetivo

Definir el contrato de datos y API necesario para soportar hard entitlements nuevos antes de tocar enforcement en FAQ, Services, Media, Storage, Support y Domains.

## 2. Principios

1. Backend manda sobre frontend.
2. `plans.entitlements` sigue siendo la base.
3. `clients.entitlement_overrides` sigue siendo la capa efectiva de override.
4. `client_usage` o la fuente equivalente debe poder responder uso real por capacidad.
5. El Addon Store solo provisiona lo que el runtime backend puede enforcear.

## 3. Entitlements efectivos propuestos

## 3.1 Estructura objetivo

```ts
type Entitlements = {
  products_limit: number;
  images_per_product: number;
  banners_active_limit: number;
  coupons_active_limit: number;
  storage_gb_quota: number;
  egress_gb_quota: number;
  custom_domain: boolean;
  domain_slots: number;
  max_monthly_orders: number;
  is_dedicated: boolean;
  max_faqs: number;
  max_services: number;
  support_tier: 'standard' | 'plus' | 'priority' | 'enterprise';
  monthly_support_ticket_limit: number;
  first_response_sla_hours: number;
}
```

## 3.2 Observaciones

- `custom_domain` puede convivir con `domain_slots` para una transición segura.
- `support_tier` no debe derivarse solo por nombre comercial; debe ser entitlement explícito.
- `storage_gb_quota` puede mantenerse en GB a nivel entitlement y convertirse a bytes en runtime.

## 4. Uso actual propuesto

## 4.1 Estructura objetivo

```ts
type ClientUsage = {
  products_count: number;
  banners_active_count: number;
  active_coupons_count: number;
  storage_bytes_used: number;
  orders_month_count: number;
  faqs_count: number;
  services_count: number;
  support_tickets_month_count: number;
  domains_count: number;
}
```

## 4.2 Caso especial: imágenes por producto

`images_per_product` no se expresa bien como contador global de cuenta. La validación necesita:

- `product_id`
- cantidad actual de imágenes del producto
- límite efectivo de `images_per_product`

Por eso debe mantenerse como chequeo contextual en `validateAction(clientId, 'upload_image', { productId, sizeBytes })`.

## 5. Deltas de addons propuestos

## 5.1 Estructura de `delta_entitlements`

```json
{
  "products_limit_delta": 0,
  "banners_active_limit_delta": 0,
  "faqs_limit_delta": 0,
  "services_limit_delta": 0,
  "images_per_product_delta": 0,
  "storage_bytes_delta": 0,
  "domain_slots_delta": 0,
  "monthly_support_ticket_limit_delta": 0,
  "support_tier_override": "plus",
  "first_response_sla_hours_override": 48
}
```

## 5.2 Reglas

- Los campos `*_delta` deben ser numéricos y no negativos.
- Los `*_override` deben validarse contra enums o catálogos explícitos.
- Un addon no puede mezclar override enterprise-only en planes self-serve.

## 6. Evolución de API

## 6.1 Endpoint existente a extender

### `GET /plans/my-limits`

Hoy ya devuelve:

- `planKey`
- `entitlements`
- `usage`
- `percentages`
- `aiImport`

Debe extenderse para incluir los nuevos entitlements y nuevos usos medibles.

### Respuesta objetivo

```json
{
  "planKey": "starter",
  "entitlements": {
    "products_limit": 300,
    "images_per_product": 1,
    "banners_active_limit": 3,
    "storage_gb_quota": 2,
    "max_faqs": 6,
    "max_services": 3,
    "custom_domain": false,
    "domain_slots": 0,
    "support_tier": "standard",
    "monthly_support_ticket_limit": 0,
    "first_response_sla_hours": 999
  },
  "usage": {
    "products_count": 120,
    "banners_active_count": 2,
    "storage_bytes_used": 734003200,
    "faqs_count": 4,
    "services_count": 2,
    "support_tickets_month_count": 0,
    "domains_count": 0
  },
  "percentages": {
    "products": 40,
    "banners": 66.6,
    "storage": 34.2,
    "faqs": 66.6,
    "services": 66.6,
    "support": 0,
    "domains": 0
  }
}
```

## 6.2 Endpoint nuevo recomendado para addons activos

### `GET /addons/active`

Debe devolver addons activos con efecto visible para el tenant:

- familia,
- delta aplicado,
- estado,
- fecha de renovación,
- política de cancelación,
- impacto si deja de pagarlo.

## 6.3 Endpoint nuevo recomendado para cancelación

### `POST /addons/:purchaseId/cancel`

Semántica recomendada V1:

- default: `cancel_at_period_end = true`
- respuesta incluye `effective_until`
- no elimina capacidad de forma inmediata salvo que sea refund o cancelación manual extraordinaria

## 6.4 Endpoint nuevo recomendado para admin ops

### `POST /admin/addons/purchases/:purchaseId/refund`

Debe:

- marcar refund en compra,
- registrar auditoría,
- recomputar entitlements si aplica,
- exponer si la provisión ya había sido entregada.

## 7. Cambios en `PlansService`

## 7.1 `Entitlements`

Extender interface con los nuevos campos.

## 7.2 `ClientUsage`

Extender interface con los nuevos contadores.

## 7.3 `validateAction()`

Agregar acciones nuevas:

- `create_faq`
- `create_service`
- `upload_logo` si se decide monetizar branding duro
- `attach_domain`
- `create_support_ticket`

## 7.4 `getUsagePercentages()`

Agregar:

- `faqs`
- `services`
- `support`
- `domains`

## 8. Cambios en `addon_catalog`

## 8.1 Columnas nuevas sugeridas

- `family` text
- `max_units_per_plan` jsonb
- `max_active_family_units_per_plan` jsonb nullable
- `cancel_policy` text
- `refund_policy` text
- `impact_copy` text
- `sort_order` int

## 8.2 Ejemplo de fila para FAQ pack

```json
{
  "addon_key": "faq_pack_10",
  "display_name": "FAQ Pack +10",
  "family": "content",
  "addon_type": "uplift",
  "billing_mode": "monthly",
  "delta_entitlements": {
    "faqs_limit_delta": 10
  },
  "allowed_plans": ["starter", "growth"],
  "max_units_per_plan": {
    "starter": 1,
    "growth": 2
  },
  "cancel_policy": "period_end",
  "refund_policy": "manual_review"
}
```

## 9. Compatibilidad y migración

## 9.1 Compatibilidad hacia atrás

- Los addons existentes de productos y banners deben seguir funcionando sin cambios de contrato rotos.
- Los nuevos campos deben ser opcionales al migrar schema.

## 9.2 Estrategia de rollout

1. Agregar campos nuevos en schema.
2. Extender `PlansService` y `GET /plans/my-limits`.
3. Exponer nuevo shape en UI sin enforcement nuevo.
4. Activar enforcement por flujo uno a uno.
5. Publicar addons nuevos solo al terminar el enforcement de su familia.

## 10. Riesgos

### Riesgo 1

Agregar entitlements que el runtime no usa todavía.

Mitigación:

- flaggear en docs qué entitlements son informativos vs enforceados.

### Riesgo 2

Modelar support o domains sin proceso operativo real.

Mitigación:

- no publicar esos SKUs hasta que haya owner operativo y SLA/flujo definidos.

### Riesgo 3

Acumular stacking que acerque demasiado Starter a Growth.

Mitigación:

- `max_units_per_plan`
- `family`
- policy de aproximación al plan superior.
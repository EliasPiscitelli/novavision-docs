# Plan: Tenant Addon Store Technical Design

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Rama base: feature/automatic-multiclient-onboarding / feature/multitenant-storefront
- Repos involucrados: API (templatetwobe), Admin (novavision), Web (templatetwo), Docs

## 1. Objetivo técnico

Diseñar un motor genérico de store de addons para tenant admins reutilizando el patrón ya probado por SEO AI billing, sin duplicar lógica de pagos, sin desalinear los límites por plan y sin introducir una segunda fuente de verdad para entitlements.

## 2. Base actual reutilizable

### 2.1 API

- `SeoAiBillingService` ya usa `addon_catalog` para packs.
- `SeoAiPurchaseService` ya crea eventos en `nv_billing_events`, arma checkout de Mercado Pago y procesa webhooks.
- `BillingService` ya resuelve eventos one-time e idempotencia básica de pago.
- `PlansService` ya calcula entitlements efectivos con merge de `plans.entitlements + clients.entitlement_overrides`.

### 2.2 Web tenant admin

- `SeoAutopilotDashboard` ya expone catálogo, saldo, compra y retorno post-redirect.
- El tenant ya tiene patrones UI para barras de uso, banners de límite y upsell.

### 2.3 Admin super admin

- Ya existe administración de pricing para SEO AI packs.
- Ya existe gestión de límites y overrides por cliente.

## 3. Decisión de arquitectura

### 3.1 No reemplazar el sistema SEO AI actual

El sistema SEO AI debe mantenerse como primer vertical funcionando.

La estrategia correcta es extraer un patrón común y dejar que SEO siga siendo un tipo de addon soportado por ese patrón.

### 3.2 Fuentes de verdad

- Catálogo comercial: `addon_catalog`
- Estado de cobro: `nv_billing_events`
- Entitlements efectivos: `clients.entitlement_overrides` + `plans.entitlements`
- Consumo por créditos: ledger especializado, como `seo_ai_credits`

No se debe crear una fuente paralela de límites efectivos fuera de `entitlement_overrides`.

## 4. Modelo de datos propuesto

### 4.1 Evolución de `addon_catalog`

La tabla actual es insuficiente para un store multi-producto. Debería crecer con columnas como:

| Campo | Tipo | Propósito |
|------|------|-----------|
| `addon_key` | text pk | clave estable |
| `display_name` | text | nombre comercial |
| `description` | text | resumen para UI |
| `addon_type` | text | `consumable`, `service`, `uplift` |
| `billing_mode` | text | `one_time`, `monthly` |
| `provider` | text | `mercadopago`, `internal` |
| `allowed_plans` | jsonb | planes habilitados |
| `delta_entitlements` | jsonb | cambios a aplicar si corresponde |
| `delta_credits` | jsonb | créditos por ledger si corresponde |
| `country_overrides` | jsonb | precios por país opcionales |
| `price_usd_cents` | integer | precio base |
| `is_active` | boolean | disponibilidad |
| `sort_order` | integer | orden de UI |
| `metadata` | jsonb | flags extra |

### 4.2 Nueva tabla: `account_addon_purchases`

Registrar cada compra o suscripción de addon.

Campos mínimos:

| Campo | Tipo | Propósito |
|------|------|-----------|
| `id` | uuid pk | compra |
| `account_id` | uuid | tenant account |
| `client_id` | uuid nullable | tenant operativo |
| `addon_key` | text fk | addon comprado |
| `billing_mode` | text | snapshot comercial |
| `purchase_status` | text | `pending`, `paid`, `failed`, `cancelled`, `fulfilled`, `active`, `expired` |
| `billing_event_id` | uuid nullable | referencia a `nv_billing_events` |
| `provider_payment_id` | text nullable | id externo |
| `started_at` | timestamptz | inicio |
| `expires_at` | timestamptz nullable | fin si aplica |
| `metadata` | jsonb | snapshot de precio y provisión |
| `created_at` | timestamptz | auditoría |
| `updated_at` | timestamptz | auditoría |

### 4.3 Nueva tabla opcional: `account_addon_fulfillments`

Solo necesaria para servicios manuales o procesos con entrega diferida.

Campos sugeridos:

- `purchase_id`
- `fulfillment_status`: `pending`, `in_progress`, `done`, `cancelled`
- `assigned_to`
- `notes`
- `completed_at`

### 4.4 Ledger de consumibles

Para V1 no conviene forzar un ledger genérico si solo SEO AI lo usa productivamente.

Se recomienda:

1. Mantener `seo_ai_credits` como ledger especializado.
2. Diseñar el motor de provisión para aceptar un `provision_strategy` por addon.
3. Recién cuando exista un segundo caso real de créditos, evaluar una tabla genérica de ledgers.

## 5. Estrategia de provisión

Cada addon debe declarar una estrategia de provisión.

### 5.1 `grant_credits`

Uso: packs SEO AI u otros consumibles.

Acción:

- luego del webhook exitoso,
- insertar en el ledger especializado,
- con idempotencia por `purchase_id` o `billing_event_id`.

### 5.2 `grant_service`

Uso: servicios one-time.

Acción:

- luego del pago,
- crear fila de fulfillment,
- marcar compra como `pending_fulfillment`.

### 5.3 `grant_entitlement_override`

Uso: uplifts mensuales.

Acción:

- resolver override acumulado permitido,
- escribir o recomputar `clients.entitlement_overrides`,
- dejar auditoría del motivo y purchase activa.

### 5.4 `revoke_entitlement_override`

Uso: vencimiento, cancelación o deuda.

Acción:

- recalcular overrides activos,
- volver a escribir `clients.entitlement_overrides` con el estado vigente.

## 6. Endpoints propuestos

### 6.1 Tenant admin

| Método | Path | Propósito |
|--------|------|-----------|
| `GET` | `/addons/catalog` | catálogo disponible para el tenant según plan y país |
| `POST` | `/addons/purchase` | iniciar checkout de addon one-time |
| `GET` | `/addons/purchases` | historial de compras del tenant |
| `GET` | `/addons/active` | addons activos y uplifts vigentes |
| `POST` | `/addons/:purchaseId/cancel` | cancelar addon mensual cuando aplique |

### 6.2 Super admin

| Método | Path | Propósito |
|--------|------|-----------|
| `GET` | `/admin/addons/catalog` | listar catálogo completo |
| `PATCH` | `/admin/addons/catalog/:addonKey` | editar pricing, flags y disponibilidad |
| `GET` | `/admin/addons/purchases` | vista global de compras |
| `GET` | `/admin/addons/purchases/:id` | detalle y auditoría |
| `PATCH` | `/admin/addons/purchases/:id` | ajuste operativo o fulfilment |
| `POST` | `/admin/addons/accounts/:accountId/entitlements/recompute` | recomputar overrides desde addons activos |

## 7. Flujo de compra recomendado

### 7.1 One-time

1. Tenant consulta `/addons/catalog`.
2. Selecciona addon consumible o servicio.
3. API valida plan, país y disponibilidad.
4. API crea `nv_billing_events` con metadata snapshot.
5. API crea `account_addon_purchases` en `pending`.
6. API arma checkout Mercado Pago.
7. Webhook confirma pago.
8. Se ejecuta provisión según `provision_strategy`.
9. Compra queda en `paid` + estado final de provisión.

### 7.2 Uplifts mensuales

No conviene tratarlos como un checkout one-time aislado.

Recomendación:

1. Primer cobro inmediato vía Mercado Pago o billing event.
2. Alta del uplift como componente recurrente de cuenta.
3. Renovación posterior dentro del pipeline de suscripción/billing de NovaVision.
4. Si el uplift cae en mora o se cancela, recomputar `entitlement_overrides`.

Esto evita que un cliente compre una vez más capacidad y la conserve para siempre.

## 8. Reglas anti-abuso

### 8.1 Por plan

- Starter no puede autocomprar uplifts estructurales en V1.
- Growth puede comprar uplifts con topes.
- Enterprise queda en flujo asistido para cambios grandes.

### 8.2 Por familia de entitlement

Topes sugeridos Growth:

- productos extra: hasta +2000
- banners extra: hasta +6
- storage extra: hasta +20 GB
- imágenes por producto: hasta +6 extra

Si se supera ese umbral, el sistema debe exigir intervención comercial o upgrade.

### 8.3 Por pricing acumulado

Si el MRR adicional acumulado por uplifts supera 70% del gap al siguiente plan, mostrar camino preferente de upgrade y bloquear nuevos uplifts automáticos.

### 8.4 Por estado de cuenta

No habilitar compra de uplifts si:

- la cuenta está suspendida,
- existe deuda vencida grave,
- la suscripción base no está activa.

## 9. Impacto por repo

### 9.1 API

- Generalizar SEO AI purchase flow hacia un `AddonPurchaseService` reutilizable.
- Mantener `SeoAiPurchaseService` como wrapper o vertical específico.
- Agregar recomputación segura de `entitlement_overrides`.

### 9.2 Web

- Crear sección `AddonStore` dentro del admin dashboard del tenant.
- Reutilizar patrones visuales de `SeoAutopilotDashboard`, `PlanLimitBanner` y upsell modals.
- Mostrar claramente si el item es consumible, servicio o adicional mensual.

### 9.3 Admin

- Agregar gestión global de catálogo.
- Agregar vista de compras y fulfillment.
- Mantener ajustes manuales y overrides como herramientas de soporte, no como flujo principal.

## 10. Fases sugeridas

### Fase 1

- Normalizar `addon_catalog`.
- Implementar `GET /addons/catalog`.
- Reusar SEO AI como primer vertical visible dentro del store.

### Fase 2

- Agregar 2 servicios one-time con fulfillment manual.
- Panel super admin para compras y cumplimiento.

### Fase 3

- Implementar uplifts mensuales Growth.
- Recomputación segura de `entitlement_overrides`.
- Reglas de tope por plan y por gap económico.

### Fase 4

- Si aparecen más consumibles reales, evaluar ledger genérico.
- Recién entonces decidir si SEO AI se migra o convive con ese ledger.

## 11. Decisión recomendada para implementación

La mejor implementación no es una tienda de tokens genérica, sino un store de addons con 3 estrategias de provisión. El checkout directo con Mercado Pago encaja perfecto para consumibles y servicios one-time. Los uplifts mensuales deben integrarse al motor de billing/suscripción y no quedar como compra eterna.
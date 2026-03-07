# Plan: Addon Store Hard Entitlements Implementation

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Rama base: feature/automatic-multiclient-onboarding / feature/multitenant-storefront
- Repos involucrados: API (templatetwobe), Web (templatetwo), Admin (novavision), Docs, E2E
- Estado: plan de implementación

## 1. Objetivo

Convertir el Addon Store en un sistema serio de extensiones monetizables basado en entitlements backend duros, límites por plan, stacking controlado y lifecycle completo, evitando pseudo-upgrades y manteniendo la identidad comercial de cada plan.

## 2. Regla madre

Un addon solo puede existir si cumple las 5 condiciones:

1. Tiene entitlement real en backend.
2. Se puede medir uso actual vs límite.
3. Tiene tope por plan.
4. Tiene comportamiento claro al vencer, impagarse o cancelarse.
5. No entrega la identidad del plan superior.

Si no cumple estas condiciones, no debe venderse como addon self-serve.

## 3. Estado verificado hoy

### 3.1 Lo que ya existe y sirve de base

- `PlansService` ya resuelve entitlements efectivos desde `plans.entitlements + clients.entitlement_overrides`.
- El Addon Store ya soporta compras `consumable`, `service` y `uplift`.
- Existe lifecycle operativo para uplifts recurrentes con:
  - activación,
  - generación mensual de `billing_adjustments`,
  - reconciliación `past_due`,
  - reactivación,
  - resincronización de `entitlement_overrides`.
- Productos y banners ya tienen enforcement backend duro con `PlanLimitsGuard`.

### 3.2 Lo que hoy está roto o incompleto

- FAQ y Services no tienen enforcement backend duro.
- El tenant admin usa límites legacy de frontend que no coinciden con el backend ni con pricing público.
- El catalog manager del Addon Store hoy solo soporta:
  - `products_limit_delta`
  - `banners_active_limit_delta`
- No está formalizado un lifecycle de cancelación/refund para uplifts del Addon Store.
- No hay política declarativa de stacking por plan, familia o aproximación al plan superior.

## 4. Entitlements a introducir

### 4.1 Nuevos entitlements base

Agregar al modelo efectivo de entitlements:

- `max_faqs`
- `max_services`
- `max_images_per_product`
- `storage_bytes_limit`
- `support_tier`
- `monthly_support_ticket_limit`
- `first_response_sla_hours`
- `custom_domain_enabled`
- `domain_slots`

### 4.2 Nuevos deltas para addons

Agregar soporte en `delta_entitlements` para:

- `faqs_limit_delta`
- `services_limit_delta`
- `images_per_product_delta`
- `storage_bytes_delta`
- `support_tier_override`
- `monthly_support_ticket_limit_delta`
- `first_response_sla_hours_override`
- `domain_slots_delta`

### 4.3 Política de diseño

- Los deltas numéricos suman capacidad.
- Los deltas booleanos o de tier deben tratarse como overrides explícitos, no como suma libre.
- Ningún delta puede otorgar por self-serve una capacidad identitaria de Enterprise.

## 5. Familias de addons objetivo

### 5.1 Content

- `FAQ Pack +10`
- `Content Pack (+10 FAQs, +2 services)`

### 5.2 Media

- `Media Pack (+2 images_per_product, +5 GB storage)`
- `Storage Pack +5 GB`

### 5.3 Support

- `Support Plus`
- `Support Priority`

### 5.4 Bridge

- `Custom Domain Bridge`
- `Domain Setup Assist` como servicio one-time separado

## 6. Reglas de stacking y anti-cannibalización

### 6.1 Techo por addon

Cada addon debe tener `max_units_per_plan`.

Ejemplo inicial:

- Starter:
  - FAQ Pack +10: máximo 1
  - Services boost: máximo 1
  - Storage Pack +5 GB: máximo 1
  - Media Pack: máximo 1
  - Custom Domain Bridge: máximo 1
- Growth:
  - FAQ Pack +25: máximo 2
  - Services boost: máximo 1 o 2 según pricing
  - Storage Pack: máximo 2
  - Media Pack: máximo 1
- Enterprise:
  - sin self-serve para addons estructurales; flujo custom

### 6.2 Techo por familia

Cada plan debe tener `max_active_family_units_per_plan`.

Ejemplo inicial:

- Starter: máximo 2 uplifts cuantitativos activos entre `content`, `media`, `bridge`
- Growth: máximo 3 uplifts cuantitativos activos

### 6.3 Techo por aproximación al plan superior

Agregar una policy de elegibilidad que corte nuevas compras cuando la suma de uplifts deje al cliente por encima de 60% a 70% del valor incremental del plan siguiente.

Para V1 no hace falta un motor financiero perfecto. Basta una policy explícita por SKU:

- si Starter ya activó `Custom Domain Bridge` y `Media Pack`, no ofrecer más addons de capacidad que acerquen demasiado a Growth;
- si Growth acumula enough deltas de catálogo/media, empujar upgrade comercial en vez de permitir nuevos uplifts.

### 6.4 Features identitarias no vendibles como addon libre

No vender como addon self-serve:

- infra dedicada,
- branding enterprise,
- multi-domain avanzado,
- soporte premium enterprise,
- analytics o integraciones identitarias del plan superior.

## 7. Lifecycle esperado por familia

### 7.1 Consumables

- Compra aprobada → provisión inmediata.
- No hay cancelación con efecto sobre entitlements.
- Refund, si existe, debe afectar ledger/benefit entregado según política del producto.

### 7.2 Uplifts recurrentes

- Compra aprobada → entitlement activo.
- Impago → `past_due`.
- `past_due`:
  - se conserva lectura,
  - se bloquean nuevas operaciones que incrementen uso de esa capacidad,
  - no se permite recomprar el mismo uplift hasta regularizar.
- Cancelación:
  - puede ser `cancel_at_period_end` en V1,
  - al finalizar período se recalculan entitlements.
- Refund:
  - si hay refund antes de provisión efectiva, no activar entitlement;
  - si hay refund posterior, debe recomputarse entitlement y registrarse auditoría.

### 7.3 Storage uplift

Si el addon vence y la cuenta queda pasada de storage:

- no cortar lectura,
- marcar `over_quota`,
- bloquear nuevas subidas,
- habilitar período de gracia para limpiar o regularizar.

### 7.4 Domain bridge

- Cancelación nunca debe borrar automáticamente el dominio activo.
- Debe pasar a estado operativamente gestionable:
  - bloqueo de nuevos cambios,
  - aviso al cliente,
  - ventana de regularización o migración a upgrade.

### 7.5 Support tier

- El entitlement debe expresarse como SLA simple y medible.
- Nunca vender soporte “ilimitado” o sin fair use.

## 8. Flujos impactados

### 8.1 Pricing y plan truth

Impacto:

- `plans` seed
- `/plans/pricing`
- tenant admin limits
- upsell copy

Validación:

- el mismo límite debe verse igual en backend, pricing público y UI del tenant.

### 8.2 Addon catalog y checkout

Impacto:

- catálogo elegible según plan
- checkout one-time vs recurrente
- pricing por SKU
- copy de impacto y stacking

Validación:

- un addon no elegible no debe aparecer ni comprarse.

### 8.3 Entitlements y uso

Impacto:

- recompute de `clients.entitlement_overrides`
- medición de `client_usage`
- barras de uso y límites efectivos

Validación:

- base limit + uplift activo = límite efectivo visible y enforceado.

### 8.4 FAQ y Services

Impacto:

- controllers y services backend
- tenant UI de alta/edición
- errores coherentes de límite excedido

Validación:

- no se puede bypassear el límite por API.

### 8.5 Media y uploads

Impacto:

- uploads manuales
- edición de producto
- importaciones masivas
- cálculo de storage

Validación:

- se rechazan subidas que excedan `max_images_per_product` o `storage_bytes_limit`.

### 8.6 Domains

Impacto:

- alta de dominio
- edición DNS/config
- bridge addon
- setup asistido

Validación:

- Starter no puede terminar con un dominio no permitido sin el addon o upgrade.

### 8.7 Support

Impacto:

- intake de tickets
- SLA visible
- límites mensuales
- escalaciones

Validación:

- no se promete en UI nada que el sistema operativo no pueda medir.

### 8.8 Billing y webhooks

Impacto:

- `nv_billing_events`
- `account_addon_purchases`
- `account_addons`
- `billing_adjustments`
- webhook approved / failed / refunded / cancelled

Validación:

- cada transición de billing tiene efecto coherente sobre compra, entitlement y auditoría.

### 8.9 Operación interna

Impacto:

- reconciliación manual
- cancelación manual
- refunds
- fulfillments
- observabilidad

Validación:

- el equipo interno puede explicar y corregir el estado de cualquier addon sin tocar DB manualmente.

## 9. Implementación por etapas

## Etapa 0. Alinear la fuente de verdad

### Objetivo

Eliminar la desalineación entre backend, pricing y tenant admin antes de monetizar nuevos addons.

### Trabajo

- Reemplazar límites frontend legacy por datos efectivos del backend.
- Revisar seeds de `plans.entitlements` y naming de campos.
- Exponer en UI límites base, uso actual y límite efectivo.

### Repos impactados

- API
- Web
- Docs

### Riesgo

Alto. Si esto no se corrige primero, cualquier addon nuevo se vende sobre una verdad comercial inconsistente.

### Gate de salida

- un snapshot del plan Starter/Growth/Enterprise coincide en:
  - backend,
  - pricing público,
  - tenant admin.

## Etapa 1. Hard entitlements y usage backend

### Objetivo

Introducir los nuevos entitlements y las métricas de uso necesarias.

### Trabajo

- Extender `Entitlements` en backend.
- Extender `client_usage` o la fuente equivalente para exponer:
  - `faqs_count`
  - `services_count`
  - `storage_bytes_used`
  - `images_per_product_count`
  - `support_tickets_month_count`
  - `domains_count`
- Definir cómo se computa cada métrica y dónde se refresca.

### Repos impactados

- API
- migrations
- Docs

### Riesgo

Medio/alto. Si la medición no es determinística, el enforcement va a ser arbitrario.

### Gate de salida

- existe una forma backend única de responder “uso actual vs límite” para cada nuevo addon.

## Etapa 2. Enforcement backend por flujo

### Objetivo

Hacer cumplir los límites en todos los puntos de entrada reales.

### Trabajo

- FAQ:
  - agregar guard o validación de límite duro.
- Services:
  - agregar guard o validación de límite duro.
- Media:
  - validar imágenes por producto y storage en upload, update e import.
- Domains:
  - validar slot o flag antes de alta/cambio.
- Support:
  - validar tier y cuota mensual en el intake.

### Repos impactados

- API
- Web
- E2E

### Riesgo

Alto. Acá es donde se rompe UX si los mensajes y edge cases no están claros.

### Gate de salida

- no existe bypass por API para exceder un entitlement nuevo.

## Etapa 3. Extender el Addon Store

### Objetivo

Permitir que el catálogo admin y el motor de provisión soporten nuevas familias de addons.

### Trabajo

- Extender `delta_entitlements` y su normalización.
- Soportar `max_units_per_plan` y `family` en catálogo.
- Soportar políticas de stacking.
- Modelar `cancel_at_period_end` para uplifts.
- Modelar `refund` y efectos operativos.

### Repos impactados

- API
- Admin
- Docs

### Riesgo

Alto. Es la capa que evita pseudo-upgrades.

### Gate de salida

- ningún addon nuevo puede publicarse si no define:
  - delta,
  - plan eligibility,
  - max units,
  - family,
  - lifecycle.

## Etapa 4. UX de límites efectivos y cancelación

### Objetivo

Hacer visible al cliente qué compró, qué ganó, cuánto usa y qué pasa si lo cancela.

### Trabajo

- Mostrar en tenant admin:
  - límite base,
  - uplift activo,
  - límite efectivo,
  - uso actual,
  - estado del addon,
  - efecto de cancelación o impago.
- Mostrar CTA de upgrade cuando stacking ya no sea sano.

### Repos impactados

- Web
- Admin
- Docs

### Riesgo

Medio. Si la UI no explica bien, el cliente interpreta el addon como upgrade de plan.

### Gate de salida

- un usuario entiende sin soporte humano:
  - qué extiende el addon,
  - qué no extiende,
  - qué pasa si deja de pagarlo.

## Etapa 5. Catálogo priorizado

### Objetivo

Lanzar primero los SKUs con menor riesgo y mayor claridad operativa.

### Orden recomendado

1. `FAQ Pack +10`
2. `Storage Pack +5 GB`
3. `Media Pack`
4. `Content Pack`
5. `Support Plus`
6. `Custom Domain Bridge`

### Criterios de go-live por SKU

Cada SKU solo sale si cumple:

- entitlement implementado,
- usage medible,
- enforcement backend,
- lifecycle validado,
- pricing anti-cannibalización aprobado,
- pruebas E2E verdes.

## 10. Matriz de impacto por flujo y etapa

| Flujo | Etapa 0 | Etapa 1 | Etapa 2 | Etapa 3 | Etapa 4 | Etapa 5 |
|------|---------|---------|---------|---------|---------|---------|
| Pricing público | Sí | No | No | Sí | Sí | Sí |
| Tenant admin limits | Sí | Sí | Sí | Sí | Sí | Sí |
| Addon catalog | No | No | No | Sí | Sí | Sí |
| Checkout MP | No | No | No | Sí | Sí | Sí |
| Webhooks | No | No | No | Sí | No | Sí |
| FAQ flow | No | Sí | Sí | Sí | Sí | Sí |
| Services flow | No | Sí | Sí | Sí | Sí | Sí |
| Upload/media flow | No | Sí | Sí | Sí | Sí | Sí |
| Domains flow | No | Sí | Sí | Sí | Sí | Sí |
| Support flow | No | Sí | Sí | Sí | Sí | Sí |
| Billing adjustments | No | No | No | Sí | Sí | Sí |
| Reconciliation | No | No | No | Sí | Sí | Sí |
| Admin ops | No | No | No | Sí | Sí | Sí |
| E2E suite | No | Sí | Sí | Sí | Sí | Sí |

## 11. Suite mínima de validación por etapa

### Etapa 0

- comparar Starter/Growth/Enterprise entre seed, API y UI.

### Etapa 1

- test unitario de merge de entitlements nuevos.
- test unitario de cálculo de usage.

### Etapa 2

- FAQ create/update bloquea por límite.
- Services create/update bloquea por límite.
- Upload bloquea por imágenes o storage.
- Domain flow bloquea sin slot.
- Support intake bloquea sin tier/capacidad.

### Etapa 3

- compra recurrente crea addon activo correcto.
- impago mueve a `past_due`.
- cancelación agenda baja.
- refund revierte entitlement cuando corresponda.
- stacking corta nuevos addons según policy.

### Etapa 4

- UI muestra límite base + uplift + efectivo + uso.
- UI explica cancelación/impago.

### Etapa 5

- smoke por SKU publicado.
- QA regresiva sobre plan upgrade vs addon bridge.

## 12. Riesgos principales

### 12.1 Riesgo comercial

Que Starter + demasiados addons se perciba como Growth barato.

Mitigación:

- techos por addon,
- techos por familia,
- corte por aproximación al plan superior,
- no vender features identitarias.

### 12.2 Riesgo técnico

Que existan varios puntos de entrada sin enforcement.

Mitigación:

- validar por controller/service,
- cubrir imports y uploads,
- cubrir flows internos/admin.

### 12.3 Riesgo operativo

Vender support o domains sin capacidad real de cumplimiento.

Mitigación:

- no publicar SKUs sin proceso y ownership claros.

## 13. Criterio de salida final

El Addon Store puede considerarse sano cuando:

- todos los addons publicados tienen entitlement duro,
- todos los usos son medibles,
- no existe bypass por API,
- el lifecycle de impago/cancelación/refund está definido,
- la UI muestra límites efectivos y consecuencias,
- ningún addon publicado entrega identidad del plan superior.

## 14. Recomendación ejecutiva

La implementación correcta no es abrir catálogo primero. La implementación correcta es:

1. alinear truth sources,
2. endurecer entitlements backend,
3. cerrar lifecycle,
4. recién después ampliar catálogo.

Si se respeta este orden, NovaVision puede vender `FAQ`, `Content`, `Media`, `Storage`, `Support` y `Bridge` sin convertir el Addon Store en un pseudo-upgrade caótico.
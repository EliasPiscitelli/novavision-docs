# Plan: Tenant Addon Store Phased Backlog

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Repos involucrados: API (templatetwobe), Web (templatetwo), Admin (novavision), Docs

## Objetivo

Bajar la propuesta del tenant addon store a entregables concretos por fase, con migraciones, endpoints y superficies de UI identificadas.

## Fase 1: Catálogo tenant + checkout delegando a SEO AI

### API

1. Crear fachada `GET /addons/catalog`.
2. Crear fachada `POST /addons/purchase`.
3. Delegar compras `seo_ai_pack_*` a `SeoAiPurchaseService`.
4. Permitir `return_section` para volver al dashboard correcto post-MP.

### Web

1. Crear sección `Addon Store` dentro de `AdminDashboard`.
2. Mostrar catálogo consumible inicial.
3. Disparar checkout vía `/addons/purchase`.
4. Mostrar retorno básico post-pago.

### Docs

1. Registrar arquitectura y decisión comercial.
2. Registrar inicio de Fase 1.

### Estado

- Iniciado el 2026-03-06.
- Implementación base realizada.

## Fase 2: Servicios one-time con fulfillment manual

### Migraciones

1. Crear `account_addon_purchases`.
2. Crear `account_addon_fulfillments`.
3. Extender `addon_catalog` con `addon_type`, `billing_mode`, `description`, `allowed_plans`, `metadata`.

### API

1. Persistir compra de addon con vínculo a `nv_billing_events`.
2. Crear `GET /addons/purchases` para tenant.
3. Crear `GET /admin/addons/purchases` para super admin.
4. Agregar estado `pending_fulfillment` para servicios pagados.

### Admin

1. Vista de fulfillment manual.
2. Cambio de estado: pendiente, en curso, completado, cancelado.

## Fase 3: Uplifts mensuales de capacidad

### Migraciones

1. Extender `account_addon_purchases` para renovaciones, vigencia y cancelación.
2. Agregar campos de pricing recurrente si no viven en `addon_catalog`.

### API

1. Implementar estrategia `grant_entitlement_override`.
2. Implementar recomputación segura de `clients.entitlement_overrides`.
3. Integrar alta/baja del uplift con el motor de billing recurrente.
4. Bloquear uplifts al superar umbrales por plan y por gap económico.

### Web

1. Diferenciar visualmente `one_time` vs `monthly`.
2. Mostrar addons activos y próximos vencimientos.
3. Permitir cancelación cuando aplique.

## Fase 4: Super admin catálogo completo

### Admin

1. CRUD completo de `addon_catalog`.
2. Pricing por país y activación por plan.
3. Auditoría de compras, provisión y fallos.
4. Ajustes manuales sobre créditos o fulfilment.

### API

1. Endpoints `/admin/addons/catalog`.
2. Endpoints `/admin/addons/purchases/:id`.
3. Endpoint de recomputación de entitlements por cuenta.

## Fase 5: Ledger genérico de consumibles

### Condición de entrada

Solo si aparece un segundo caso real de créditos o consumo además de SEO AI.

### Trabajo

1. Diseñar ledger genérico.
2. Evaluar migración o convivencia con `seo_ai_credits`.
3. Homologar reportes y ajustes manuales.

## Riesgos a controlar

1. No crear una segunda fuente de verdad para límites distintos de `entitlement_overrides`.
2. No vender capacidad estructural como compra eterna.
3. No desdibujar la escalera Starter → Growth → Enterprise.
4. No mezclar fulfillment manual con acreditación automática sin auditoría.
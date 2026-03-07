# Plan: Addon Store Hard Entitlements Backlog

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Repos involucrados: API (templatetwobe), Web (templatetwo), Admin (novavision), Docs, E2E
- Estado: backlog ejecutable

## Objetivo

Convertir el plan conceptual del Addon Store con hard entitlements en trabajo concreto por prioridad, repo y archivo probable de impacto.

## P0

## P0.1 Unificar source of truth de límites en tenant admin

### Resultado esperado

El tenant admin deja de depender de mirrors legacy para límites críticos de productos, imágenes, banners y AI import.

### Repos

- Web
- Docs

### Archivos

- `apps/web/src/hooks/usePlanLimits.js`
- `apps/web/src/hooks/useEffectivePlanConfig.js`
- `apps/web/src/components/admin/ProductDashboard/index.jsx`
- `apps/web/src/components/ProductModal/index.jsx`
- `apps/web/src/components/admin/BannerSection/index.jsx`
- `apps/web/src/components/admin/FaqSection/index.jsx`
- `apps/web/src/components/admin/ServiceSection/index.jsx`
- `apps/web/src/components/CategoryManager/index.jsx`
- `apps/web/src/components/admin/UserDashboard/index.jsx`
- `apps/web/src/components/admin/LogoSection/index.jsx`

### Estado

- Iniciado en esta sesión.
- Primer paso aplicado: helper `useEffectivePlanConfig` con merge backend + fallback legacy.

### Riesgo

Medio. Los componentes siguen necesitando fallback para campos no modelados aún en backend.

## P0.2 Cerrar drift remanente de plan limits hardcodeados

### Resultado esperado

No quedan límites legacy divergentes para recursos que ya tienen entitlement real en backend.

### Repos

- API
- Web
- Admin
- Docs

### Archivos a revisar

- `apps/web/src/config/basicPlanLimits.jsx`
- `apps/web/src/config/professionalPlanLimits.jsx`
- `apps/web/src/config/premiumPlanLimits.jsx`
- `apps/api/src/onboarding/onboarding.service.ts`
- `apps/api/src/onboarding/validators/design.validator.ts`
- `apps/admin/src/utils/sectionMigration.ts`
- `apps/admin/src/registry/sections.ts`
- `apps/api/src/home/registry/sections.ts`

### Riesgo

Alto. Hay mirrors legacy fuera del tenant admin principal.

## P0.3 Diseñar y migrar nuevos entitlements backend

### Resultado esperado

Existen en backend los campos base para FAQ, Services, Media, Storage, Support y Domains.

### Repos

- API
- Docs

### Archivos objetivo

- `apps/api/src/plans/plans.service.ts`
- `apps/api/src/plans/plans.controller.ts`
- `apps/api/migrations/admin/*plans*`
- `apps/api/migrations/backend/*client_usage*`

### Riesgo

Alto. Cambia contrato de entitlements y usage.

## P0.4 Medición real de uso por capacidad nueva

### Resultado esperado

Backend puede responder uso actual vs límite para:

- FAQs
- Services
- Images per product
- Storage
- Support tickets del mes
- Domain slots

### Repos

- API
- Docs
- E2E

### Archivos probables

- `apps/api/src/plans/plans.service.ts`
- `apps/api/migrations/backend/BACKEND_012_client_usage_counter.sql`
- `apps/api/migrations/backend/BACKEND_027_extend_client_usage.sql`
- nuevos migrations/backend para contadores faltantes

### Riesgo

Alto. Sin esto no hay enforcement serio.

## P0.5 Lifecycle formal de uplifts

### Resultado esperado

Existe contrato claro y código para:

- `cancel_at_period_end`
- `cancelled`
- `refunded`
- `past_due`
- recompute de entitlements en cada transición

### Repos

- API
- Admin
- Docs
- E2E

### Archivos probables

- `apps/api/src/addons/addons.controller.ts`
- `apps/api/src/addons/addons.admin.controller.ts`
- `apps/api/src/addons/addons.service.ts`
- `apps/api/migrations/admin/20260306_addon_store_purchases_and_fulfillment.sql`
- `apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx`

### Riesgo

Alto. Hoy es el mayor gap funcional del Addon Store recurrente.

## P1

## P1.1 Enforcement backend de FAQ

### Resultado esperado

FAQ deja de depender de límites visuales del frontend.

### Repos

- API
- Web
- E2E

### Archivos probables

- `apps/api/src/faq/faq.controller.ts`
- `apps/api/src/faq/faq.service.ts`
- `apps/web/src/components/admin/FaqSection/index.jsx`

## P1.2 Enforcement backend de Services

### Resultado esperado

Services deja de depender de límites visuales del frontend.

### Archivos probables

- `apps/api/src/service/service.controller.ts`
- `apps/api/src/service/service.service.ts`
- `apps/web/src/components/admin/ServiceSection/index.jsx`

## P1.3 Enforcement backend de media

### Resultado esperado

Se valida en backend:

- imágenes por producto,
- storage total,
- casos de edición e import masivo.

### Archivos probables

- `apps/api/src/plans/plans.service.ts`
- `apps/api/src/products/products.controller.ts`
- `apps/web/src/components/ProductModal/index.jsx`
- `apps/web/src/components/admin/ImportWizard/index.jsx`

## P1.4 Stacking policy engine

### Resultado esperado

Cada addon define:

- `family`
- `max_units_per_plan`
- `max_active_family_units_per_plan`
- regla de aproximación al plan superior

### Archivos probables

- `apps/api/src/addons/addons.service.ts`
- `apps/api/src/addons/addons.admin.controller.ts`
- migrations/admin de `addon_catalog`

## P1.5 UI de límites efectivos y consecuencias

### Resultado esperado

El tenant ve:

- límite base,
- uplift activo,
- límite efectivo,
- uso actual,
- qué pasa si cancela o cae en `past_due`.

### Repos

- Web
- Admin

## P2

## P2.1 Support tier self-serve

Condición de entrada:

- existe intake de tickets medible,
- existe SLA mínimo operable.

## P2.2 Domain bridge self-serve

Condición de entrada:

- dominio propio modelado como bridge controlado,
- lifecycle operativo definido.

## P2.3 Catálogo ampliado

Orden recomendado:

1. `FAQ Pack +10`
2. `Storage Pack +5 GB`
3. `Media Pack`
4. `Content Pack`
5. `Support Plus`
6. `Custom Domain Bridge`

## Dependencias críticas

### Bloqueantes absolutos

- source of truth alineada,
- nuevos entitlements modelados,
- uso medible,
- lifecycle de uplifts recurrentes.

### No bloqueantes para launch de P0

- support tier self-serve,
- domain bridge self-serve,
- catálogo ampliado.

## Criterio de priorización

Un ticket entra en P0 si desbloquea alguna de estas condiciones:

1. elimina drift entre backend y frontend,
2. agrega enforcement backend duro,
3. agrega medición real,
4. cierra lifecycle recurrente,
5. evita canibalización por stacking descontrolado.
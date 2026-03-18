# Plan: Registro Unificado de Componentes en BD + Token Pricing Variable

**Estado:** Implementado
**Fecha:** 2026-03-18
**Changelog:** `changes/2026-03-18-component-catalog-token-pricing.md`

---

## Problema

Existen **3 registros paralelos** de componentes de storefront, todos hardcodeados en codigo:

1. `SECTION_CATALOG` en `admin/src/registry/sectionCatalog.ts` (~140 variantes con `planTier`)
2. `SECTION_CATALOG` en `web/src/registry/sectionCatalog.ts` (copia identica)
3. `VARIANT_REGISTRY` en `api/src/home/registry/sections.ts` (~90 variantes con `planMin`)

Ademas, el `DEFAULT_COMPONENTS` en `DesignSystemView.jsx` vivia solo en localStorage.

Cambiar el plan minimo o el precio de un componente requeria deploys en 3 repos.

## Solucion

Tabla `component_catalog` en Admin DB como fuente unica de verdad, consumida por API, Admin y Web. Con `token_cost` variable por componente.

---

## Arquitectura

### Tabla `component_catalog` (Admin DB)

```sql
CREATE TABLE component_catalog (
  component_key  text PRIMARY KEY,       -- 'hero.first', 'hero.video.background'
  label          text NOT NULL,
  type           text NOT NULL,          -- header, hero, banner, catalog, features, faq, contact, footer, testimonials
  category       text NOT NULL DEFAULT 'content',
  description    text,
  thumbnail_url  text,
  min_plan       text NOT NULL DEFAULT 'starter',
  token_cost     integer NOT NULL DEFAULT 1,
  is_active      boolean NOT NULL DEFAULT true,
  sort_order     integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
```

**RLS:**
- Lectura publica de componentes activos (`is_active = true`)
- Full access para `service_role` (backend API)

### Modulo API: `component-catalog/`

| Archivo | Rol |
|---------|-----|
| `component-catalog.module.ts` | Modulo NestJS, exporta `ComponentCatalogService` |
| `component-catalog.service.ts` | CRUD: getActiveCatalog, getFullCatalog, updateComponent, getTokenCost, getComponentsByKeys |
| `component-catalog.controller.ts` | Endpoints publicos y super-admin |

### Endpoints

| Endpoint | Metodo | Auth | Proposito |
|----------|--------|------|-----------|
| `GET /components/catalog` | GET | AllowNoTenant (publico) | Catalogo activo con token_cost |
| `GET /admin/components/catalog` | GET | SuperAdminGuard | Catalogo completo (incluye inactivos) |
| `PATCH /admin/components/:key` | PATCH | SuperAdminGuard | Editar min_plan, token_cost, is_active, etc. |

---

## Bloques de Implementacion

### Bloque 1: Migracion BD (tabla + seed)

- **Archivo:** `api/migrations/admin/20260318_01_component_catalog.sql`
- Tabla con trigger `updated_at`, indices, RLS
- Seed de ~70 variantes desde `VARIANT_REGISTRY` enriquecidas con labels/descriptions de `SECTION_CATALOG`
- Token cost: starter=1, growth=2, enterprise=3

### Bloque 2: API — Modulo ComponentCatalog

- Modulo, service y controller NestJS
- Registrado en `app.module.ts`
- `/components/catalog` excluido de AuthMiddleware (publico)

### Bloque 3: Token Cost Variable en Consumo de Creditos

- **Archivo modificado:** `storefront-action-credits.service.ts`
- `assertComponentChangeAvailable(clientId, requiredCredits)` — acepta creditos requeridos
- Nuevo metodo `consumeComponentChangeWithCost({ tokenCost })` — usa `credits_delta: -tokenCost`
- `consumeCredits` acepta `creditsDelta` opcional (antes hardcoded `-1`)
- **Archivo modificado:** `home.controller.ts` — `replaceSection` busca `token_cost` del componente destino

### Bloque 4: Onboarding — Exploracion Libre + Checkout Validation

**4A — Admin Step4TemplateSelector:**
- Componentes de plan superior ya no bloquean insercion
- Solo muestran aviso informativo: "Requiere plan X. Se validara al pagar."
- Editor de video disponible para todos (con banner warning si plan insuficiente)

**4B — API startCheckout:**
- Nueva validacion de `design_config.sections` contra `component_catalog.min_plan`
- Si componente requiere plan superior, incrementa `minRequiredPlan` → error `PLAN_INCOMPATIBLE`

### Bloque 5: Admin DesignSystemView → API

- `ComponentManager` fetch desde `GET /admin/components/catalog`
- Cambios de `min_plan` y `token_cost` → `PATCH /admin/components/:key`
- Input numerico editable para `token_cost` con badge visual
- Stats: total, por plan, token cost promedio
- Eliminado: `DEFAULT_COMPONENTS`, localStorage

### Bloque 6: Web DesignStudio — Token Display

- Fetch `GET /components/catalog` al montar (junto con addons/credits)
- `componentCatalogMap` indexado por `component_key`
- `buildStructureActionPlan` calcula `totalTokenCost` (adds/replaces usan token_cost del componente)
- `missingStructureCredits` basado en `totalTokenCost` en vez de `totalActions`
- Badges de token cost en `AccordionGroup` con colores semaforicos

### Bloque 7: Creditos Iniciales por Plan

- **Provisioning worker:** Grant de creditos `component_change` post-provisioning
- Usa patron existente de `runStep()` (como AI welcome credits)

| Plan | Creditos iniciales |
|------|--------------------|
| Starter | 2 |
| Growth | 5 |
| Enterprise | 15 |

---

## Token Pricing

| Plan del componente | token_cost por defecto |
|--------------------|-----------------------|
| Starter | 1 |
| Growth | 2 |
| Enterprise | 3 |

Editable en tiempo real desde Admin Dashboard > Sistema de Diseno > Componentes.

---

## Flujo Completo

### Onboarding (pre-pago)

```
1. Usuario explora TODOS los componentes (sin bloqueo)
2. Arrastra componentes premium → aviso informativo
3. Checkout: startCheckout valida design_config.sections vs component_catalog
4. Si componente requiere plan superior → PLAN_INCOMPATIBLE → prompt upgrade
5. Provisioning: grant creditos iniciales segun plan
```

### DesignStudio (post-pago)

```
1. Fetch /components/catalog → mapa de token costs
2. Usuario ve badges de token cost por componente (1tk, 2tk, 3tk)
3. buildStructureActionPlan calcula totalTokenCost
4. Si totalTokenCost > availableCredits → bloqueo + "Comprar creditos"
5. Al aplicar: replaceSection busca token_cost → consumeComponentChangeWithCost
```

---

## Archivos Clave

### Creados

| Archivo | Descripcion |
|---------|-------------|
| `api/migrations/admin/20260318_01_component_catalog.sql` | Tabla + seed |
| `api/migrations/admin/20260318_02_plan_initial_credits.sql` | Documentacion de politica |
| `api/src/component-catalog/component-catalog.module.ts` | Modulo NestJS |
| `api/src/component-catalog/component-catalog.service.ts` | Service CRUD + getTokenCost |
| `api/src/component-catalog/component-catalog.controller.ts` | Controller publico + admin |

### Modificados

| Archivo | Cambio |
|---------|--------|
| `api/src/app.module.ts` | Registro modulo + exclusion AuthMiddleware |
| `api/src/storefront-actions/storefront-action-credits.service.ts` | Token cost variable |
| `api/src/home/home.module.ts` | Import ComponentCatalogModule |
| `api/src/home/home.controller.ts` | Replace con token_cost |
| `api/src/onboarding/onboarding.service.ts` | Validacion checkout |
| `api/src/worker/provisioning-worker.service.ts` | Grant creditos iniciales |
| `admin/src/pages/AdminDashboard/DesignSystemView.jsx` | Conectado a API |
| `admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | Exploracion libre |
| `web/src/components/admin/StoreDesignSection/DesignStudio.jsx` | Token cost display |
| `web/src/components/admin/StoreDesignSection/AccordionGroup.jsx` | Badge de tokens |

---

## Verificacion

### API
- `npm run typecheck` — 0 errores nuevos
- `npm run lint` — 0 errores nuevos
- `GET /components/catalog` retorna catalogo con token_cost
- `PATCH /admin/components/hero.video.background` actualiza token_cost

### Admin
- DesignSystemView > Componentes carga desde API
- Step4 muestra todos los componentes sin bloqueo

### Onboarding E2E
- Cuenta starter con componente growth → checkout retorna PLAN_INCOMPATIBLE
- Cuenta growth con componente growth → checkout OK

### DesignStudio
- Componentes muestran badge de tokens
- Replace con componente de 3 tokens consume 3 creditos
- Sin creditos suficientes → error + prompt de compra

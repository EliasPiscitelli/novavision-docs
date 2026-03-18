# 2026-03-18 — Registro Unificado de Componentes + Token Pricing Variable

## Resumen

Centralización de los 3 registros paralelos de componentes de storefront (API `VARIANT_REGISTRY`, Admin `SECTION_CATALOG`, Web `SECTION_CATALOG`) en una tabla `component_catalog` en Admin DB. Implementación de `token_cost` variable por componente para monetización granular.

## Cambios

### API (`@nv/api`)

| Archivo | Cambio |
|---------|--------|
| `migrations/admin/20260318_01_component_catalog.sql` | **Nuevo** — Tabla `component_catalog` con RLS + seed de ~70 variantes |
| `migrations/admin/20260318_02_plan_initial_credits.sql` | **Nuevo** — Documentación de política de créditos iniciales |
| `src/component-catalog/component-catalog.module.ts` | **Nuevo** — Módulo NestJS |
| `src/component-catalog/component-catalog.service.ts` | **Nuevo** — Service con CRUD + getTokenCost() |
| `src/component-catalog/component-catalog.controller.ts` | **Nuevo** — `GET /components/catalog` (público) + `GET/PATCH /admin/components/*` (super-admin) |
| `src/app.module.ts` | Registro de `ComponentCatalogModule` + exclusión de `/components/catalog` en AuthMiddleware |
| `src/storefront-actions/storefront-action-credits.service.ts` | `assertComponentChangeAvailable` acepta `requiredCredits`; nuevo `consumeComponentChangeWithCost`; `consumeCredits` acepta `creditsDelta` variable |
| `src/home/home.module.ts` | Import de `ComponentCatalogModule` |
| `src/home/home.controller.ts` | `replaceSection` busca `token_cost` del componente destino y usa `consumeComponentChangeWithCost` |
| `src/onboarding/onboarding.service.ts` | `startCheckout` valida `design_config.sections` contra `component_catalog.min_plan` |
| `src/worker/provisioning-worker.service.ts` | Grant de créditos iniciales `component_change` post-provisioning (Starter=2, Growth=5, Enterprise=15) |

### Admin (`@nv/admin`)

| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/DesignSystemView.jsx` | `ComponentManager` conectado a API; elimina `DEFAULT_COMPONENTS`/localStorage; muestra `token_cost` editable por componente |
| `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | Exploración libre: componentes de plan superior ya no bloquean inserción, solo muestran aviso informativo. Validación real en checkout. |

### Web (`@nv/web`)

| Archivo | Cambio |
|---------|--------|
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | Fetch de `/components/catalog`; `buildStructureActionPlan` calcula `totalTokenCost`; UI muestra tokens en vez de acciones; `missingStructureCredits` basado en `totalTokenCost` |
| `src/components/admin/StoreDesignSection/AccordionGroup.jsx` | Badge de `tokenCost` con colores semafóricos (verde/amarillo/rojo) |

## Endpoints nuevos

| Endpoint | Método | Auth | Descripción |
|----------|--------|------|-------------|
| `/components/catalog` | GET | Público (AllowNoTenant) | Catálogo activo con token_cost |
| `/admin/components/catalog` | GET | SuperAdminGuard | Catálogo completo (incluye inactivos) |
| `/admin/components/:key` | PATCH | SuperAdminGuard | Editar min_plan, token_cost, is_active |

## Token pricing

| Plan componente | token_cost |
|-----------------|------------|
| Starter | 1 |
| Growth | 2 |
| Enterprise | 3 |

## Créditos iniciales por plan

| Plan | Créditos component_change |
|------|---------------------------|
| Starter | 2 |
| Growth | 5 |
| Enterprise | 15 |

## Fixes post-test-cases (gaps corregidos)

| TC | Gap | Fix |
|----|-----|-----|
| TC-04 | No CHECK constraint para `token_cost > 0` | Agregado `CHECK (token_cost > 0)` en migración + validación en controller |
| TC-05 | No CHECK constraint para `min_plan` válido | Agregado `CHECK (min_plan IN ('starter','growth','enterprise'))` en migración + validación en controller |
| TC-18 | `getTokenCost()` retornaba fallback 1 para componente inexistente | Ahora lanza `NotFoundException` |
| TC-19 | `getTokenCost()` retornaba fallback 1 para componente inactivo | Ahora lanza `BadRequestException` |
| TC-01 | Seed tenía 69 rows (esperado ≥ 70) | Agregado `banner.simple` al seed |
| TC-43 | Backend no validaba `token_cost` en PATCH | Validación `Number.isInteger(tc) && tc >= 1` en controller |
| TC-69 | Sin sort secundario cuando `sort_order` iguales | Agregado `.order('component_key', { ascending: true })` como sort secundario |

## Validación

- `npm run typecheck` — 0 errores nuevos (errores pre-existentes en ai-credits/import-wizard)
- `npm run lint` — 0 errores nuevos
- Archivos nuevos del módulo component-catalog pasan lint sin issues
- **75 test cases validados**: 62 PASS, 7 corregidos (ver tabla arriba), 6 N/A (E2E runtime)

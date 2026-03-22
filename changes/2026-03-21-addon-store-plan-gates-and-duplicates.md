# 2026-03-21 — Fix addon store: duplicados, AI packs invisibles, plan gates

## Contexto

El addon store mostraba 3 problemas:
1. Addons duplicados (28 capacity en vez de ~14)
2. Los 12 packs de créditos IA no aparecían (solo se veían SEO AI)
3. Cards mostraban "Exclusivo desde Plan superior" y "Enterprise" (no aplica en multi-tenant)

## Cambios

### API (`addons.service.ts`)

| Fix | Detalle |
|-----|---------|
| Duplicados | `listCatalog()` llamaba `listRecurringUplifts()` + `listManagedCatalogRows()` por separado, pero `listRecurringUplifts()` internamente ya llama a `listManagedCatalogRows()`. Se removió la llamada redundante |
| AI packs invisibles | Se removió filtro `.filter(item => item.ui_scope !== 'admin_only')` que ocultaba los 12 packs IA con `ui_scope='admin_only'`. El addon store ES parte del admin dashboard |
| Family mapping | `mapManagedCatalogRowToItem()` no reconocía `family='ai'`, mapeando packs IA como 'capacity'. Agregado 'ai' al check |
| SEO AI Growth-only | Removido 'starter' de `allowed_plans` en los packs SEO AI dinámicos (regla de negocio: SEO AI automatizado es solo para Growth) |

### Web (`AddonStoreDashboard/index.jsx`)

| Fix | Detalle |
|-----|---------|
| PLAN_LABELS | Eliminado 'enterprise' (no existe en multi-tenant) |
| getRequiredPlanLabel() | Solo retorna 'Growth' o null. Nunca 'Enterprise' ni 'Plan superior' |
| getAudienceHint() | "Solo plan Growth" en vez de "Exclusivo desde..." |
| PlanGate | "Disponible con plan Growth" en vez de "Solo planes X o superiores" |
| Botones | "Requiere plan Growth" en vez de "plan superior" |

## Regla de negocio documentada

- Enterprise = BDs separadas, NO accede al addon store multi-tenant
- Growth = plan máximo en multi-tenant storefront
- Todos los planes pueden comprar y usar IA
- SEO AI automatizado = solo Growth
- `enterprise` se mantiene en `allowed_plans` de la BD para forward-compat (cuando se copie BD a entorno Enterprise)

## Commits

- API: `24245db` en `feature/automatic-multiclient-onboarding`
- Web: `6a2d45e` en `develop` → cherry-picked a `feature/multitenant-storefront` (`3303361`) y `feature/onboarding-preview-stable` (`e3bbe06`)
- Monorepo: `a970591` en `develop`

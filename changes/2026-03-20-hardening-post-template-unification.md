# 2026-03-20 — Hardening Post-Template-Unification

## Contexto
Implementacion de fixes criticos y mejoras UX detectados en la auditoria T0-T16.

## Fase 1 — Bugs criticos de produccion

### C-1: CSS Design Overrides nunca se aplicaban (CRITICO)
- **Archivo:** `apps/web/src/App.jsx`
- **Fix:** Agregar `className={nv-store-${tenant?.clientId}}` a `GeneralContainer`
- **Root cause:** `scopeCssToTenant()` envuelve CSS en `.nv-store-{clientId}` pero el contenedor no tenia esa clase

### H-1: Cron borraba Custom CSS cada noche (ALTO)
- **Archivo:** `apps/api/src/design-overrides/design-overrides.service.ts`
- **Fix:** Set `VIRTUAL_ADDON_KEYS` con `custom_css` y `ai_generated_css` — skip en `reconcileOverrides()`
- **Root cause:** `custom_css` no es addon real en `account_addons` → siempre revocado

### H-2: fontKey sin validacion server-side (ALTO)
- **Archivos:** `apps/api/src/common/constants/fonts.ts` (nuevo), `apps/api/src/home/home-settings.service.ts`
- **Fix:** Allowlist `VALID_FONT_KEYS` + plan-gating `FONT_PLAN_MIN` — validacion antes de persistir
- **Root cause:** `upsertTemplate()` aceptaba cualquier string como fontKey

### BUG-4: GET /palettes 401 desde Admin Dashboard (ALTO)
- **Archivos:** `apps/api/src/palettes/palettes.controller.ts`, `apps/api/src/palettes/palettes.module.ts`
- **Fix:** `BuilderSessionGuard` → `ClientDashboardGuard` en todos los endpoints
- **Root cause:** `BuilderSessionGuard` no popula `req.user`, solo `req.account_id`

## Fase 2 — Quick wins UX

### BUG-5: Fonts en Preview
- **Archivo:** `apps/web/src/components/storefront/FontLoader.tsx`
- **Fix:** `fetchPriority: 'high'` en el `<link>` de Google Fonts
- **Verificado:** `--nv-font` ya se incluye en `rootCssVarsBlock` via `paletteToCssVars()`

### MEJORA-1: Banner condicional para tenants publicados
- **Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- **Fix:** Ocultar banner "imagenes ilustrativas" cuando `homeData.products.length > 0`

### MEJORA-4: Reglas de estructura colapsables
- **Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- **Fix:** `<div>` → `<details>/<summary>` colapsado por defecto

### MEJORA-5: CSS Editor textarea monospace
- **Archivo:** `apps/web/src/components/admin/StoreDesignSection/CssOverrideEditor.jsx`
- **Fix:** Reemplazo completo — grid de select+input → textarea monospace con parseo bidireccional

## Fase 3 — Overhauls UX

### MEJORA-2: Template Selector con thumbnails + personalidad
- **Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- **Fix:** Thumbnails `<img>` con fallback + constante `TEMPLATE_PERSONALITY` por key
- **Assets:** 8 thumbnails webp generados en `web/public/templates/` y `admin/public/templates/` via sharp (SVG→webp)

### MEJORA-3: Layout mas ancho para Store Design
- **Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- **Fix:** Grid `minmax(320px, 1fr) minmax(420px, previewWidth)` + preview sticky

### MEJORA-6: SectionPropsDrawer (drawer slide-from-right)
- **Archivo nuevo:** `apps/web/src/components/admin/StoreDesignSection/SectionPropsDrawer.jsx`
- **Fix:** SectionPropsEditor ahora se abre en drawer lateral en lugar de inline

## Fase 4 — Onboarding

### MEJORA-8: Thumbnails en wizard Step4
- **Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
- **Fix:** Misma estructura de thumbnails que MEJORA-2

### MEJORA-9: Reglas colapsables en wizard
- **Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
- **Fix:** `<div>` → `<details>/<summary>` colapsado por defecto

### MEJORA-7: Drag & drop en Excel importer
- **Archivo:** `apps/admin/src/pages/BuilderWizard/components/ExcelProductImporter.tsx`
- **Fix:** Zona de drag & drop con feedback visual + input file oculto

## Commits

| Repo | Branch | Hash | Descripcion |
|------|--------|------|-------------|
| Web | `develop` | `bb98654` | 13 archivos (5 src + 8 webp) |
| Web | `feature/multitenant-storefront` | `63d18b7` | cherry-pick limpio, build OK |
| Web | `feature/onboarding-preview-stable` | `2fc2734` | cherry-pick limpio, build OK |
| API | `feature/automatic-multiclient-onboarding` | `a25155c` | 5 archivos (4 mod + 1 nuevo) |
| Admin | `feature/automatic-multiclient-onboarding` | `62d1510` | 10 archivos (2 src + 8 webp) |

## Validacion
- API: lint (0 errors), typecheck, build — fixes verificados via grep
- Web develop: typecheck, build
- Web multitenant-storefront: build OK post cherry-pick
- Web onboarding-preview-stable: build OK post cherry-pick
- Admin: typecheck, build
- Cross-branch sync: diff vacio entre develop y ambas ramas prod (excl dev-only files)
- C-1 verificado en las 3 ramas Web (grep `nv-store`)
- H-1, H-2, BUG-4 verificados en API (grep VIRTUAL_ADDON_KEYS, VALID_FONT_KEYS, ClientDashboardGuard)

## Estado
- Todos los commits son **locales** — push pendiente de confirmacion

# Plan: Hardening Post-Template-Unification — NovaVision

## Context

La auditoría arquitecto+QA sobre el sistema Template Unification (T0-T16) reveló **3 bugs** (1 crítico, 2 altos), a los que se suman **2 bugs adicionales** reportados y **9 mejoras UX/UI** para admin dashboard y wizard de onboarding. Este plan consolida todo en 4 fases priorizadas para blindar el sistema.

**Audit report:** `novavision-docs/architecture/add_templates/AUDIT_REPORT_T0_T16.md`
**Fecha:** 2026-03-20

---

## Validación Cross-Branch (pre-implementación)

Auditoría realizada 2026-03-20 sobre las 4 ramas productivas:

### Web — 3 ramas

| Criterio | `develop` | `feature/multitenant-storefront` | `feature/onboarding-preview-stable` |
|----------|:---------:|:--------------------------------:|:-----------------------------------:|
| C-1: clase `.nv-store-{clientId}` en GeneralContainer | ❌ FALTA | ❌ FALTA | ❌ FALTA |
| T10: CssOverrideEditor con AI generation | ✅ | ✅ | ✅ |
| T10: DesignStudio pasa currentPalette/currentFont | ✅ | ✅ | ✅ |
| T15: FontLoader.tsx existe | ✅ | ✅ | ✅ |
| T9: useDesignOverrides.js inyecta `<style>` | ✅ | ✅ | ✅ |
| Sync productivo (excl. .claude/, __dev/) | — | ✅ solo diffs intencionales | ✅ solo diffs intencionales |

**Diffs intencionales** entre develop y ramas prod:
- DevPortal: deshabilitado en prod (comentado, correcto)
- Hydration extras: storeName marquee, catalog section, testimonials (prod-only enhancements)

**Conclusión Web:** Las 3 ramas están sincronizadas para T9/T10/T15. El bug C-1 es activo en PRODUCCIÓN — afecta a todas las tiendas publicadas y al preview de onboarding.

### API — rama `feature/automatic-multiclient-onboarding`

| Criterio | Estado |
|----------|:------:|
| H-1: excepción `custom_css` en reconcileOverrides() | ❌ NO EXISTE — bug activo, revoca CSS cada noche |
| H-2: validación fontKey en home-settings.service.ts | ❌ NO EXISTE — acepta cualquier string |
| H-2: archivo `common/constants/fonts.ts` | ❌ NO EXISTE — debe crearse |
| BUG-4: guard en GET /palettes | ❌ BuilderSessionGuard — lee `req.user` que no se setea |
| BUG-4: PalettesModule imports | DbModule + JwtModule (necesita ClientDashboardGuard deps) |
| T10: AI CSS generation endpoint | ✅ commit `c65ffa1` |
| T9: CSS overrides CRUD | ✅ commit `4cb05c1` |
| T15: fontKey en PUT /settings/home | ✅ commit `1cda7a0` |

**Conclusión API:** Los 4 bugs de Fase 1 están confirmados como activos en producción. Requieren fix inmediato.

---

## FASE 1: CRÍTICA — Bugs bloqueantes de producción

### C-1: CSS Design Overrides nunca se aplican (CRÍTICO)

**Root cause:** `GeneralContainer` en `App.jsx:245` se renderiza SIN la clase `.nv-store-{clientId}`. Pero `scopeCssToTenant()` (`css.validator.ts:174`) envuelve TODO el CSS en `.nv-store-{clientId} { ... }`. El selector nunca matchea → **todos los overrides son invisibles**.

**Archivo:** `apps/web/src/App.jsx` — línea 245

**Fix:**
```jsx
<GeneralContainer
  className={`nv-store-${tenant?.clientId || ''}`}   // ← AGREGAR
  $isHome={isHomeRoute}
  $isPreview={isPreviewRoute}
  ...
>
```

`tenant` ya disponible via `useTenant()` (usado en línea 177).

**Complejidad:** S · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas ramas prod

**Verificación:**
1. Inspeccionar DOM: `GeneralContainer` debe tener clase `nv-store-{uuid}`
2. Los CSS overrides activos deben aplicarse visualmente
3. `npm run typecheck && npm run build`

---

### H-1: El cron de reconciliación borra Custom CSS cada noche (ALTO)

**Root cause:** `reconcileOverrides()` (`design-overrides.service.ts:411`) verifica `activeAddonKeys.has(source_addon_key)`. Custom CSS se guarda con `source_addon_key: 'custom_css'` (línea 186), pero `'custom_css'` NO es addon real en `account_addons` → siempre se revoca a las 03:00 UTC.

**Archivo:** `apps/api/src/design-overrides/design-overrides.service.ts` — método `reconcileOverrides()`, línea ~408

**Fix:**
```typescript
// Al inicio del archivo
const VIRTUAL_ADDON_KEYS = new Set(['custom_css', 'ai_generated_css']);

// En el for loop:
if (VIRTUAL_ADDON_KEYS.has(typed.source_addon_key)) {
  details.push({ override_id: typed.id, addon_key: typed.source_addon_key, action: 'kept' });
  continue;  // ← nunca revocar virtual addon keys
}
```

**Complejidad:** S · **Deps:** ninguna · **Repos:** API

**Verificación:**
1. Override con `source_addon_key: 'custom_css'` → NO se revoca
2. Override con addon real expirado → SÍ se revoca
3. `npm run lint && npm run typecheck && npm run build && npm run test`

---

### H-2: fontKey no se valida server-side (ALTO)

**Root cause:** `home-settings.service.ts:326` acepta cualquier `fontKey` sin validar contra catálogo ni plan.

**Archivos:**
- Crear: `apps/api/src/common/constants/fonts.ts` — allowlist + plan-gating
- Modificar: `apps/api/src/home/home-settings.service.ts` — líneas 325-333

**Fix:**
```typescript
// fonts.ts (nuevo)
export const VALID_FONT_KEYS = new Set([
  'inter','poppins','dm_sans','space_grotesk','outfit',
  'playfair','lora','merriweather','jetbrains','fira_code',
]);
export const FONT_PLAN_MIN: Record<string, string> = {
  inter:'starter', poppins:'starter', playfair:'starter',
  dm_sans:'growth', space_grotesk:'growth', outfit:'growth',
  lora:'growth', merriweather:'growth', jetbrains:'growth', fira_code:'growth',
};

// home-settings.service.ts — antes del merge
if (fontKey) {
  if (!VALID_FONT_KEYS.has(fontKey))
    throw new BadRequestException(`fontKey inválido: "${fontKey}"`);
  // + validar plan eligibility
}
```

**Complejidad:** M · **Deps:** ninguna · **Repos:** API

**Verificación:**
1. PUT /settings/home con `fontKey: 'invalid'` → 400
2. PUT con `fontKey: 'dm_sans'` + plan `starter` → 400
3. PUT con `fontKey: 'inter'` + plan `starter` → OK

---

### BUG-4: GET /palettes retorna 401 desde Admin Dashboard (ALTO)

**Root cause:** `palettes.controller.ts:56-64` usa `BuilderSessionGuard` pero lee `req.user.plan`. El guard setea `req.account_id`, NO `req.user`. El admin dashboard usa Supabase JWT (vía `ClientDashboardGuard`).

**Archivo:** `apps/api/src/palettes/palettes.controller.ts` — líneas 56-64 + POST/PUT/DELETE endpoints

**Fix:** Cambiar `BuilderSessionGuard` → `ClientDashboardGuard` en todos los endpoints:
```typescript
@Get()
@UseGuards(ClientDashboardGuard)
async getPalettes(@Request() req) {
  const user = req.user;
  const userPlan = user?.plan || user?.plan_key || 'starter';
  const clientId = user?.client_id || user?.resolvedClientId || null;
  return this.palettesService.getPalettes(userPlan, clientId);
}
```

Verificar que `PalettesModule` importa dependencias de `ClientDashboardGuard`.

**Complejidad:** M · **Deps:** ninguna · **Repos:** API

**Verificación:**
1. Admin dashboard (Supabase JWT): GET /palettes → 200
2. Onboarding (X-Builder-Token): GET /palettes → 200
3. Sin auth → 401

---

## FASE 2: ALTA — Quick wins UX

### BUG-5: Fonts no se aplican en Preview

**Estado:** Parcialmente desmentido. `PreviewHost` (index.tsx:375-403) SÍ maneja fontKey correctamente. Posible race condition entre carga de Google Font `<link>` y aplicación de `--nv-font`.

**Archivo:** `apps/web/src/pages/PreviewHost/index.tsx` — líneas 375-403, 497-518

**Fix:** Verificar que `--nv-font` se incluye en `rootCssVarsBlock` via `paletteToCssVars()`. Agregar `font-display: swap` explícito.

**Complejidad:** S · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas

---

### MEJORA-1: Remover banner "Elegí tu template" para tenants publicados

El banner ilustrativo (DesignStudio.jsx:1285-1295) es confuso para tenants ya publicados.

**Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx` — líneas ~1283-1301

**Fix:**
```jsx
{!isPublishedTenant && (
  <div style={{ /* banner informativo */ }}>ℹ️ Las imágenes son ilustrativas...</div>
)}
<h5>{isPublishedTenant ? '🧩 Cambiar template' : '🧩 Elegí tu template'}</h5>
```

Determinar `isPublishedTenant` desde contexto del tenant.

**Complejidad:** S · **Deps:** ninguna · **Repos:** Web → cherry-pick `multitenant-storefront`

---

### MEJORA-4: Reglas de estructura en accordion colapsable

Las 8 `STRUCTURE_RULES` (DesignStudio.jsx:1498-1510) ocupan demasiado espacio vertical.

**Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx` — líneas 1498-1510

**Fix:** Reemplazar wrapper `<div>` por `<details>/<summary>` colapsado por defecto.

**Complejidad:** S · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas

---

### MEJORA-5: CSS Editor → textarea monospace auto-expandible

Reemplazar grilla property/value del `CssOverrideEditor.jsx` por `<textarea>` monospace.

**Archivo:** `apps/web/src/components/admin/StoreDesignSection/CssOverrideEditor.jsx`

**Fix:**
- Nuevo state `cssText` (string multilinea `"prop: value;\n..."`)
- `<textarea>` monospace con `resize: vertical`, `minHeight: 120`
- Parsear a `{ prop: value }` al guardar
- AI output se convierte a texto CSS

**Complejidad:** M · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas

---

## FASE 3: MEDIA — Overhauls UX mayores

### MEJORA-2: Template Selector con thumbnails + personalidad

**Archivos:**
- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx` — líneas 1303-1370
- `apps/web/src/components/admin/StoreDesignSection/Step4TemplateSelector.css`
- Assets: `apps/web/public/templates/` — screenshots webp

**Cambio:** `<img>` thumbnail + personalidad + badge de plan en cada `.template-card`.

**Complejidad:** L · **Deps:** requiere generar 8 screenshots · **Repos:** Web → cherry-pick ambas

---

### MEJORA-3: Layout más ancho para Store Design

**Archivo:** `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx` — línea 1182

**Cambio:** Grid de `minmax(320px, 1fr) minmax(420px, ${previewWidth}px)`. Preview sticky.

**Complejidad:** M · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas

---

### MEJORA-6: Advanced Props en drawer por bloque

**Archivos:**
- Crear: `apps/web/src/components/admin/StoreDesignSection/SectionPropsDrawer.jsx`
- Modificar: `DesignStudio.jsx` — click en sección → abrir drawer

**Cambio:** `SectionPropsEditor` envuelto en panel slide-from-right.

**Complejidad:** L · **Deps:** ninguna · **Repos:** Web → cherry-pick ambas

---

### MEJORA-8: Thumbnails de templates en wizard de onboarding

**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`

**Cambio:** Mismo patrón que MEJORA-2 en @nv/admin con MUI. Reutilizar assets.

**Complejidad:** M · **Deps:** MEJORA-2 (assets) · **Repos:** Admin

---

## FASE 4: BAJA — Mejoras de onboarding

### MEJORA-7: Fixes UX en Step 3 (Catálogo/Excel)

**Archivos:**
- `apps/admin/src/pages/BuilderWizard/components/CatalogLoader.tsx`
- `apps/admin/src/pages/BuilderWizard/components/ExcelProductImporter.tsx`

**Cambios:** Dark theme (vars CSS NV), drag&drop feedback, botón Continuar disabled sin datos.

**Complejidad:** M · **Deps:** ninguna · **Repos:** Admin

---

### MEJORA-9: Reglas de estructura colapsables en wizard

**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`

**Cambio:** Mismo patrón que MEJORA-4, usando `<Accordion>` MUI 7.

**Complejidad:** S · **Deps:** MEJORA-4 · **Repos:** Admin

---

## Secuenciación

```
FASE 1 (día 1-2):    C-1 → H-1 → H-2 → BUG-4    (independientes, deploy inmediato)
FASE 2 (día 3-5):    BUG-5 → MEJORA-1 → MEJORA-4 → MEJORA-5
FASE 3 (semana 2):   MEJORA-2 → MEJORA-8 (dep assets) | MEJORA-3 | MEJORA-6
FASE 4 (semana 3):   MEJORA-7 | MEJORA-9 (dep MEJORA-4)
```

## Matriz repos × ramas

| Item | API | Web develop | Web multitenant | Web onboarding | Admin |
|------|:---:|:-----------:|:---------------:|:--------------:|:-----:|
| C-1 | | X | cherry-pick | cherry-pick | |
| H-1 | X | | | | |
| H-2 | X | | | | |
| BUG-4 | X | | | | |
| BUG-5 | | X | cherry-pick | cherry-pick | |
| MEJORA-1 | | X | cherry-pick | | |
| MEJORA-4 | | X | cherry-pick | cherry-pick | |
| MEJORA-5 | | X | cherry-pick | cherry-pick | |
| MEJORA-2 | | X | cherry-pick | cherry-pick | |
| MEJORA-3 | | X | cherry-pick | cherry-pick | |
| MEJORA-6 | | X | cherry-pick | cherry-pick | |
| MEJORA-8 | | | | | X |
| MEJORA-7 | | | | | X |
| MEJORA-9 | | | | | X |

## Verificación global

```bash
# API
cd apps/api && npm run lint && npm run typecheck && npm run build && npm run test

# Web
cd apps/web && npm run typecheck && npm run build && npx vitest run

# Admin
cd apps/admin && npm run typecheck && npm run build
```

**Smoke tests:**
- CSS overrides visibles en storefront publicada (C-1)
- Palettes cargables desde admin dashboard (BUG-4)
- Font válida persiste, font inválida rechazada 400 (H-2)
- Cron no borra custom CSS — verificar logs después de 03:00 UTC (H-1)

## Validación Cross-Branch Post-Implementación

Después de CADA fix en Web, verificar las 3 ramas:

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web

# 1. Verificar que el fix existe en las 3 ramas
for BRANCH in develop feature/multitenant-storefront feature/onboarding-preview-stable; do
  echo "=== $BRANCH ==="
  git show $BRANCH:src/App.jsx | grep -n "nv-store" || echo "❌ C-1 NOT FIXED"
done

# 2. Verificar sync productivo (debe estar vacío excepto diffs intencionales)
git diff develop feature/multitenant-storefront -- \
  ':!.claude/' ':!src/__dev/' ':!scripts/audit-css-contrast.mjs' ':!CLAUDE.md' \
  --stat

git diff develop feature/onboarding-preview-stable -- \
  ':!.claude/' ':!src/__dev/' ':!scripts/audit-css-contrast.mjs' ':!CLAUDE.md' \
  --stat

# 3. Build validation en cada rama prod
for BRANCH in feature/multitenant-storefront feature/onboarding-preview-stable; do
  echo "=== Validando $BRANCH ==="
  git stash && git checkout $BRANCH
  npm run typecheck && npm run build
  git checkout develop && git stash pop
done
```

Para API, verificar en rama única:
```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api

# Verificar fixes
grep -n "VIRTUAL_ADDON_KEYS" src/design-overrides/design-overrides.service.ts || echo "❌ H-1 NOT FIXED"
grep -n "VALID_FONT_KEYS" src/home/home-settings.service.ts || echo "❌ H-2 NOT FIXED"
grep -n "ClientDashboardGuard" src/palettes/palettes.controller.ts || echo "❌ BUG-4 NOT FIXED"

npm run lint && npm run typecheck && npm run build && npm run test
```

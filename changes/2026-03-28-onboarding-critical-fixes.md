# Fixes Críticos del Onboarding — 8 Issues de Producción

**Fecha:** 2026-03-28
**Apps afectadas:** API (BD), Admin
**Tipo:** fix (BLOCKER + CRITICAL + HIGH + MEDIUM)
**Plan origen:** `plans/PLAN_ONBOARDING_CRITICAL_FIXES.md`

## Resumen

Se resolvieron los 8 issues detectados durante testing real del onboarding en producción. El más grave era un error de BD que causaba 500 en cada interacción con el Step 4.

## Cambios

### Issue #1 — BLOCKER: Columna `selected_font_key` no existe en BD

**Fix:** Migración SQL ejecutada en Admin DB:
```sql
ALTER TABLE nv_onboarding ADD COLUMN IF NOT EXISTS selected_font_key text;
```
**Migración formal:** `apps/api/migrations/admin/ADMIN_037_add_selected_font_key.sql`
**Verificación:** Confirmada con query a `information_schema.columns`.
**Impacto:** Desbloquea todo el Step 4 — eliminados los 500 en `PATCH /onboarding/preferences`.

### Issue #2 — CRITICAL: White flash en primer render del builder

**Archivo:** `apps/admin/index.html`
**Fix:** Agregado bloque `<style>` inline que pre-define las CSS variables del tema dark para `[data-nv-route='builder']` ANTES de que React monte. Variables: `--nv-bg-canvas`, `--nv-bg-surface`, `--nv-text-primary`, `--nv-border`, `--nv-brand-primary`, etc.

### Issue #3 — CRITICAL: Cards Growth opacas

**Archivo:** `apps/admin/src/pages/BuilderWizard/components/AccordionGroup.tsx`
**Fix:** Removida lógica de `opacity: 0.55` y `cursor: not-allowed` para componentes de plan superior. Ahora todas las cards son interactuables. Badge informativo discreto "Plan growth" reemplaza el bloqueo visual.

### Issue #4 — CRITICAL: 33 componentes con `enterprise` erróneo

**Archivo:** `apps/admin/src/registry/sectionCatalog.ts`
**Fix:** Todos los items `enterprise` cambiados a `growth` para alinearse con la tabla `component_catalog` de la BD (que ya tenía los valores correctos). La tabla `component_catalog` es la fuente de verdad del backend — el frontend estaba desincronizado.

### Issue #5 — HIGH: Click en card locked saltaba a Step 6 (Paywall)

**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` (línea 1516)
**Fix:** Removido `updateState({ currentStep: 6 })`. Reemplazado por toast informativo: "Este componente requiere plan X. Podés seleccionarlo y se te informará en el paso de pago." El componente ahora se inserta normalmente.

### Issue #6 — MEDIUM: Drag & Drop siempre agregaba al final

**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` (onDrop handler)
**Fix:** Implementado cálculo de drop position basado en `e.clientY` vs midpoint de cada `.structure-item`. El `insertIndex` calculado se pasa a `insertSection()`, que ya lo soportaba.

### Issue #7 — MEDIUM: Footers todos idénticos visualmente

**Archivo:** `apps/admin/src/registry/sectionCatalog.ts`
**Fix:** Diferenciados los 8 footers con props distintas:
- `footer.first-third` → `layoutVariant: "columns"` con distinto `columnCount` (4, 3, 2) y combinaciones de `showNewsletter`/`showBranding`
- `footer.fourth-fifth` → `layoutVariant: "stacked"` con variantes
- `footer.sixth-eighth` → `layoutVariant: "branded"` (Drift/Vanguard/Lumina)
- Cada footer tiene su propia función `describe()` para identificación en UI.

### Issue #8 — MEDIUM: Excel import tab ilegible (dark mode)

**Archivo:** `apps/admin/src/pages/BuilderWizard/components/ExcelProductImporter.css`
**Fix:** Agregado `background` y `color` con CSS variables a `.preview-row`, `th`, `td` y `.error-details`. Cambiados fallbacks hardcodeados claros por valores con `var()` que respetan el tema.

## Otros fixes menores

- **Import duplicado:** Removido `import './Step1Slug.css'` duplicado en `Step1Slug.tsx`
- **Test actualizado:** `Step4TemplateSelector.gating.test.tsx` actualizado para reflejar nuevo comportamiento (exploración libre sin bloqueo ni redirección)

## Validación

- Admin: lint ✓, typecheck ✓, build ✓, tests ✓ (148/148 pass)
- API: lint ✓, typecheck ✓, build ✓ (pre-push hook)
- SQL: Columna `selected_font_key` verificada en BD real
- Catálogo: 0 items `enterprise` en `sectionCatalog.ts`, alineado con `component_catalog` de BD

## Commits

- **Admin** (`feature/automatic-multiclient-onboarding`): `fa2444c` — 8 fixes frontend
- **API** (`feature/automatic-multiclient-onboarding`): `98570d9` — migración ADMIN_037
- **Docs** (`main`): changelog

# Fix: UX de Exploración Libre en Onboarding — 8 Issues

**Fecha:** 2026-03-28
**Apps afectadas:** Admin
**Tipo:** fix (CRITICAL + HIGH + MEDIUM)
**Plan origen:** `plans/PLAN_ONBOARDING_EXPLORATION_UX.md`

## Resumen

Se removieron todos los bloqueos visuales y de interacción que impedían a usuarios con plan Starter explorar libremente componentes Growth durante el onboarding. La validación real ocurre en PaywallPlans (Step 6).

## Cambios

### Issue A — GalleryModal: cards Growth bloqueadas (CRITICAL)

**Archivo:** `GalleryModal.tsx` + `GalleryModal.css`
**Fix:** Removido `PLAN_RANK`, `isLocked`, `.locked-overlay`, opacity 0.6 y `cursor: not-allowed`. Todas las cards del modal son clickeables. Prop `userPlan` eliminada (ya no necesaria). Badge de plan se mantiene como indicador informativo.

### Issue B — FontSelector: fonts Growth no seleccionables (HIGH)

**Archivo:** `FontSelector.tsx`
**Fix:** Removido `opacity: 0.5` y `cursor: not-allowed`. Eliminada dependencia de `canAccessFont`. Badge "Growth" ahora siempre azul informativo. Todas las fonts seleccionables.

### Issue C — Toast warning redundante en insertSection (MEDIUM)

**Archivo:** `Step4TemplateSelector.tsx`
**Fix:** Removido `showToast` de warning al insertar componentes Growth. El tracking de analytics se mantiene silenciosamente para métricas.

### Issue D — Handler onLockedComponentClick muerto (MEDIUM)

**Archivo:** `Step4TemplateSelector.tsx`
**Fix:** Removido `onLockedComponentClick` handler del AccordionGroup. Limpiado import `buildPlanRestrictionMessage` que ya no se usaba.

### Issue E — Mensaje de límite sin guía (HIGH)

**Archivo:** `designSystem.ts` (`validateInsert`)
**Fix:** Mensaje mejorado: "Para agregar otro, reemplazá o eliminá uno existente. Después de publicar, podés comprar stock de componentes extra."

### Issue F — Botón reemplazar en body sections (HIGH)

**Archivo:** `Step4TemplateSelector.tsx`
**Fix:** `replacingType` expandido de `string | null` a `{ type: SectionType; sectionId?: string } | null`. Body sections ahora tienen botón 🔄 junto al 🗑️. El modal de reemplazo filtra por tipo y reemplaza la sección específica por `sectionId`.

### Issue H — Tutorial trigger ocupa mucho espacio (MEDIUM)

**Archivo:** `stepTour.css`
**Fix:** `.nv-tour-trigger` ahora es icon-only (40px círculo con ✨). En hover se expande mostrando label ("Reactivar tutorial" / "Ver tutorial") con transición suave. En mobile (≤640px) el label permanece oculto.

### Issue I — Header/Footer Design Studio no sticky (HIGH)

**Archivo:** `Step4TemplateSelector.css`
**Fix:** `.ds-header` con `position: sticky; top: 0;` y `.ds-footer` con `position: sticky; bottom: 0;`. Crea efecto "marco" que contiene el scroll dentro del área de contenido.

## Validación

- Admin: lint ✓, typecheck ✓, build ✓, tests ✓ (148/148 pass)

## Commits

- **Admin** (`feature/automatic-multiclient-onboarding`): `bfcfbc6`

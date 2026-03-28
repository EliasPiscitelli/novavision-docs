# Plan: UX de Exploración Libre en Onboarding — Step 4

**Fecha:** 2026-03-28
**Origen:** Testing en producción — issues UX post-fix anterior
**Apps afectadas:** Admin
**Prioridad:** ALTA — el onboarding sigue bloqueando exploración

---

## Principio de Diseño

**Durante el onboarding, el usuario PUEDE explorar y seleccionar CUALQUIER componente, font o template de CUALQUIER plan.** La validación real ocurre en el paso de pago (Step 6 PaywallPlans). Si el usuario eligió items Growth, al pagar se le muestra que necesita ese plan. NO se bloquea visualmente ni con toasts innecesarios durante la exploración.

---

## Issue A — GalleryModal: Cards con opacity + locked overlay

**Severidad:** CRITICAL (el usuario no puede ni hacer click en componentes Growth)
**Archivo:** `apps/admin/src/pages/BuilderWizard/components/GalleryModal.tsx`

### Causa raíz

```tsx
// Línea 45-46
const PLAN_RANK = { starter: 1, growth: 2, pro: 3 };
const userRank = PLAN_RANK[userPlan] || 1;

// Línea 148
const isLocked = userRank < minRank;

// Línea 153-154
className={`component-card ${isLocked ? "locked" : ""}`}
onClick={() => !isLocked && onSelect(comp)}
```

El `!isLocked &&` previene el click. El CSS `.component-card.locked` aplica `opacity: 0.6` y `cursor: not-allowed`.

### Fix

1. Remover el concepto de `isLocked` del GalleryModal
2. Todas las cards son clickeables (`onClick={() => onSelect(comp)}`)
3. Mantener el badge de plan como indicador informativo (sin opacity ni overlay)
4. Remover `.component-card.locked` del CSS y `.locked-overlay`

**Riesgo:** Bajo — solo UX, la validación real está en PaywallPlans

---

## Issue B — FontSelector: Fonts Growth con opacity 0.5 y no seleccionables

**Severidad:** HIGH (fonts Growth no se pueden elegir)
**Archivo:** `apps/admin/src/theme/fontCatalog.ts` + componente FontSelector

### Causa raíz

`FontSelector.tsx` líneas 112-113:
```tsx
cursor: accessible ? 'pointer' : 'not-allowed',
opacity: accessible ? 1 : 0.5,
```

Y en Step4TemplateSelector.tsx líneas 1251-1261, el `canAccessFont` check muestra toast pero SÍ permite la selección (el `updateState` ocurre antes del check). Sin embargo, el FontSelector **visualmente bloquea** los botones no accesibles.

### Fix

1. En FontSelector: remover opacity y cursor gating. Todas las fonts son seleccionables.
2. Mantener badge "Growth" como indicador, sin bloqueo visual.
3. En Step4TemplateSelector: el toast informativo está bien pero cambiar status de `'info'` a solo mostrar badge, sin toast repetitivo cada click.

**Riesgo:** Bajo

---

## Issue C — insertSection: Toast warning innecesario en cada inserción Growth

**Severidad:** MEDIUM (molesto, no bloqueante)
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` líneas 626-646

### Causa raíz

```tsx
if (!canAccessPlanTier(currentPlan, def.planTier)) {
  showToast({
    message: `${def.name} requiere plan ${planLabel}. Se validará al momento de pagar.`,
    status: 'warning',
  });
}
```

Cada vez que el usuario inserta un componente Growth, ve un toast amarillo. Esto es redundante — el badge en la card ya informa del plan, y el PaywallPlans hace la validación final.

### Fix

1. Remover el toast del `insertSection` para componentes de plan superior
2. Mantener el `trackEvent` para analytics (sin toast)
3. La sección se inserta normalmente (ya funciona así)

**Riesgo:** Bajo

---

## Issue D — onLockedComponentClick todavía muestra toast en AccordionGroup

**Severidad:** MEDIUM
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` líneas 1503-1517

### Causa raíz

El `onLockedComponentClick` handler todavía existe y muestra toast "Este componente requiere plan...". Pero como AccordionGroup ya no llama `onLockedComponentClick` (lo arreglamos antes), este handler es código muerto. Sin embargo, si hay OTRO componente que lo llama, sigue mostrando el toast.

### Fix

1. Limpiar el handler `onLockedComponentClick` — ya no se necesita
2. Remover la prop `onLockedComponentClick` del AccordionGroup (ya no la usa)

**Riesgo:** Bajo

---

## Issue E — Límite de componentes: sin guía para el usuario

**Severidad:** HIGH (usuario no entiende por qué no puede agregar más)
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` (función `validateInsert`)

### Causa raíz

Cuando se alcanza el máximo de secciones (ej: max 3 catalog), `validateInsert` retorna `{ valid: false, error: '...' }` y muestra un toast de error genérico. No guía al usuario sobre qué hacer.

### Fix

1. Mejorar el mensaje de error en `validateInsert` para incluir guía:
   - "Ya tenés el máximo de [tipo]. Para agregar otro, eliminá o reemplazá uno existente. Después de publicar, podés comprar stock de componentes extra."
2. NO cambiar los límites, solo mejorar el mensaje

**Riesgo:** Bajo

---

## Issue F — Botón Reemplazar en secciones del body (estructura)

**Severidad:** HIGH (header/footer tienen reemplazo pero el body no)
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` líneas 1778-1789

### Causa raíz

Las secciones del body solo tienen botón "eliminar" (🗑️). Header y footer tienen botón "reemplazar" (🔄) que abre un modal filtrado por tipo. El usuario necesita la misma funcionalidad en body sections.

### Fix

1. Expandir `replacingType` state de `'header' | 'footer' | null` a `{ type: SectionType; sectionId: string } | null`
2. Agregar botón 🔄 a cada body section item (junto al 🗑️ existente)
3. Al hacer click, setear `replacingType` con el type y sectionId de ESA sección
4. Modificar `handleReplaceSection` para:
   - Si es header/footer: comportamiento actual (reemplaza por type)
   - Si es body section: reemplaza la sección con ese `sectionId` específico
5. El modal de reemplazo ya existe y filtra por type — funciona igual

**Riesgo:** Medio — requiere cambio en state y handler de reemplazo

---

## Issue G — GalleryModal: Plan rank no incluye "enterprise" (obsoleto)

**Severidad:** LOW
**Archivo:** `apps/admin/src/pages/BuilderWizard/components/GalleryModal.tsx` línea 45

### Causa raíz

```tsx
const PLAN_RANK = { starter: 1, growth: 2, pro: 3 };
```

No tiene `enterprise` ni `growth` en posición correcta. Pero con el fix del Issue A (remover isLocked), esto se vuelve irrelevante.

### Fix

Se resuelve automáticamente con Issue A (remover todo el plan gating del modal).

---

## Issue H — FAB "?" del tutorial ocupa mucho espacio

**Severidad:** MEDIUM (UX visual)
**Archivo:** `apps/admin/src/pages/BuilderWizard/BuilderWizard.css` + `index.tsx`

### Causa raíz

El FAB es un círculo de 48px fijo con "?" siempre visible. En mobile ocupa espacio visual significativo y no tiene contexto de qué hace.

### Fix

1. Cambiar el FAB a icon-only por defecto (solo "?", tamaño reducido)
2. En hover (desktop) expandir el botón con label "Ver guía" usando transición CSS
3. En mobile: mantener compacto, el tap lo activa directamente (no necesita hover-expand)
4. Usar `overflow: hidden` + `max-width` transition para el efecto de expansión

**Riesgo:** Bajo — solo CSS + minor JSX

---

## Issue I — Header y Footer del Design Studio sticky (efecto marco)

**Severidad:** HIGH (UX de navegación — el usuario se pierde en scrolls anidados)
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.css`

### Causa raíz

`.ds-header` y `.ds-footer` son flex children normales. El scroll del contenido se mezcla con el scroll general, desorientando al usuario.

### Fix

1. `.ds-header`: agregar `position: sticky; top: 0;` (ya tiene `z-index: 10`)
2. `.ds-footer`: agregar `position: sticky; bottom: 0;` (ya tiene `z-index: 20`)
3. `.ds-content` ya tiene `flex: 1; overflow: hidden;` — el scroll queda contenido ahí
4. La mobile override (≤420px) ya tiene footer sticky — solo verificar que header también lo sea

**Riesgo:** Bajo — cambios CSS puros, la estructura flex ya lo soporta

---

## Orden de Ejecución

| Orden | Issue | Impacto | Archivos |
|-------|-------|---------|----------|
| 1 | A — GalleryModal locked | Desbloquea exploración en modal | GalleryModal.tsx + .css |
| 2 | B — FontSelector opacity | Desbloquea fonts Growth | FontSelector.tsx |
| 3 | C — Toast warning en insertSection | Elimina ruido UX | Step4TemplateSelector.tsx |
| 4 | D — Handler onLockedComponentClick | Limpieza código muerto | Step4TemplateSelector.tsx |
| 5 | F — Botón reemplazar en body | Nueva funcionalidad UX | Step4TemplateSelector.tsx |
| 6 | E — Mensaje límite componentes | Mejora guía | designSystem.ts (validateInsert) |
| 7 | H — FAB hover-expand | Reduce ruido visual | BuilderWizard.css + index.tsx |
| 8 | I — Sticky header/footer | Efecto marco en Design Studio | Step4TemplateSelector.css |

---

## Validación

1. Hacer onboarding con plan `starter`
2. Verificar que TODAS las cards (incluso Growth) se pueden seleccionar en AccordionGroup, GalleryModal y FontSelector
3. Verificar que NO hay toasts de warning al seleccionar componentes Growth
4. Verificar que el botón 🔄 aparece en body sections y abre modal filtrado
5. Verificar que al alcanzar límite, el mensaje guía al usuario
6. Verificar que el FAB "?" se expande con hover y es compacto en mobile
7. Verificar que header/footer del Design Studio quedan fijos al scrollear
8. `npm run lint && npm run typecheck && npm run build`
9. `npx vitest run` — todos los tests pasan

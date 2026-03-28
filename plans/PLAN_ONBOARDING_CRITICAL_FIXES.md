# Plan: Fixes Críticos del Onboarding — Detección en Producción

**Fecha:** 2026-03-28
**Origen:** Testing manual en producción por el usuario
**Apps afectadas:** API, Admin
**Prioridad:** URGENTE — el onboarding está roto en producción

---

## Resumen Ejecutivo

Se detectaron **8 issues** durante testing real del onboarding. El más grave es un error de BD que causa **500 en cada interacción** con el Step 4 (Template/Diseño). Esto bloquea completamente el flujo.

---

## Issue #1 — BLOCKER: Columna `selected_font_key` no existe en BD

**Severidad:** BLOCKER (rompe todo el Step 4)
**Error:** `Could not find the 'selected_font_key' column of 'nv_onboarding' in the schema cache`
**Frecuencia:** Se dispara en CADA click en Step4 (20+ veces en los logs)

### Causa raíz

El código en `onboarding.service.ts:2229` escribe `selected_font_key` en `nv_onboarding`, pero la columna **nunca fue creada** con una migración SQL. Se agregó al código en la fase de Design Studio (2026-03-21) pero faltó la migración.

### Evidencia BD

```
psql> SELECT column_name FROM information_schema.columns WHERE table_name = 'nv_onboarding';
-- 42 columnas listadas, selected_font_key NO está
```

### Fix

**API** (`apps/api/`):
1. Ejecutar SQL en Admin DB:
   ```sql
   ALTER TABLE nv_onboarding ADD COLUMN selected_font_key text;
   ```
2. Verificar que `onboarding.service.ts:2229` funciona post-migración

**Archivos:** Ninguno — es solo migración SQL en BD real
**Riesgo:** Bajo — es un `ADD COLUMN` nullable, sin default

---

## Issue #2 — CRITICAL: Theme blanco sobre blanco en primer render

**Severidad:** CRITICAL (toda la UI ilegible al entrar)
**Síntoma:** Al entrar al builder, todo se ve blanco con letras blancas. Si se recarga, se ve bien.

### Causa raíz

- `index.html` (línea 43) setea `background: #0f172a` en el `documentElement` para el builder
- Pero las **CSS variables** (`--nv-bg-canvas`, `--nv-text-primary`, etc.) se definen en componentes React que cargan DESPUÉS del primer paint
- `.wizard-app` usa `var(--nv-bg-canvas, #f8fafc)` — el fallback es **blanco claro**
- Resultado: flash blanco hasta que React monta y define las variables

### Fix

**Admin** (`apps/admin/`):
1. En `index.html`, agregar un bloque `<style>` inline que defina las CSS variables del tema dark para la ruta builder ANTES de que React cargue:
   ```html
   <style id="nv-builder-preload">
     [data-nv-route="builder"] {
       --nv-bg-canvas: #0f172a;
       --nv-bg-surface: #1e293b;
       --nv-text-primary: #f8fafc;
       --nv-text-secondary: #94a3b8;
       --nv-text-muted: #64748b;
       --nv-border-default: #334155;
       --nv-brand-primary: #6366f1;
       /* ... demás variables del tema */
     }
   </style>
   ```
2. Verificar que el `data-nvRoute` ya se setea en el `<script>` del `index.html`

**Archivos:** `apps/admin/index.html`
**Riesgo:** Bajo — solo CSS, no rompe funcionalidad

---

## Issue #3 — CRITICAL: Cards Growth opacas — bloquean exploración

**Severidad:** CRITICAL (UX rota — usuario piensa que no puede usarlas)
**Síntoma:** Todas las cards Growth en Step4 (template selector y estructura) aparecen con opacidad 0.55 y cursor not-allowed

### Causa raíz

`AccordionGroup.tsx:56-92`:
```tsx
const isLocked = !canAccessPlanTier(selectedPlan, comp.planTier);
// ...
style={{ opacity: isLocked ? 0.55 : 1, cursor: isLocked ? 'not-allowed' : 'pointer' }}
```

El plan durante el onboarding es `starter` por defecto (aún no pagó), así que TODAS las cards Growth/Enterprise se ven deshabilitadas. Pero la regla de negocio es que el usuario debe poder **explorar y seleccionar cualquier componente** durante el onboarding, y al momento del pago se le informa si necesita upgrade.

### Fix

**Admin** (`apps/admin/`):
1. En `AccordionGroup.tsx`: Remover opacity y cursor lock. En su lugar, mostrar un **badge** discreto con el plan requerido (ej: "Growth") sin deshabilitar la card
2. Alternativa: Agregar prop `allowExploration` que, cuando es `true` (en onboarding), permite interacción completa con badge informativo en lugar de bloqueo visual

**Archivos:** `apps/admin/src/pages/BuilderWizard/components/AccordionGroup.tsx`
**Riesgo:** Medio — cambio de UX policy, necesita validación visual

---

## Issue #4 — CRITICAL: 33 componentes etiquetados `enterprise` que no existen

**Severidad:** CRITICAL (componentes inaccesibles sin motivo real)
**Síntoma:** Testimonios dice "Enterprise", footers, banners, etc. muestran enterprise cuando deberían ser growth o starter

### Causa raíz

`sectionCatalog.ts` tiene **33 items con `planTier: "enterprise"`**, pero según el registro canónico `sections.ts` (fuente de verdad), los planes correctos son:

| Tipo | `sections.ts` (correcto) | `sectionCatalog.ts` (erróneo) |
|------|--------------------------|-------------------------------|
| testimonials (6th,7th,8th) | **growth** | enterprise |
| hero variants (4th+) | **starter** | enterprise |
| product_carousel variants | **starter** | enterprise |
| product_grid variants | **starter** | enterprise |
| services_grid variants | **starter** | enterprise |
| contact_form variants | **starter** | enterprise |
| footer variants (4th+) | **starter/growth** | enterprise |

Solo `video_banner` y `team_gallery` son legítimamente `enterprise` según `sections.ts`.

### Fix

**Admin** (`apps/admin/`):
1. Recorrer `sectionCatalog.ts` y alinear CADA `planTier` con el `planMin` de `sections.ts`
2. Regla: las variantes de un tipo heredan el `planMin` del tipo base
3. Variantes premium de un tipo base starter pueden ser `growth`, pero NUNCA `enterprise` salvo `video_banner` y `team_gallery`

**Archivos:** `apps/admin/src/registry/sectionCatalog.ts`
**Riesgo:** Bajo — solo data, no lógica

---

## Issue #5 — HIGH: Click en card locked salta al Step 6 (Paywall)

**Severidad:** HIGH (interrumpe flujo de diseño bruscamente)
**Síntoma:** Al tocar una card de componente, salta a PaywallPlans sin confirmación

### Causa raíz

`Step4TemplateSelector.tsx:1516`:
```tsx
onLockedComponentClick={(component) => {
  // ...
  updateState({ currentStep: 6 }); // ← Salta directo sin confirmar
}}
```

### Fix

**Admin** (`apps/admin/`):
1. Remover `updateState({ currentStep: 6 })` del handler
2. Solo mostrar toast informativo: "Este componente requiere plan Growth. Podés seleccionarlo y se te informará en el paso de pago."
3. Permitir la inserción del componente (el PaywallPlans ya detecta incompatibilidades)

**Archivos:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
**Riesgo:** Bajo — simplifica el handler

---

## Issue #6 — MEDIUM: Drag & Drop siempre agrega al final

**Severidad:** MEDIUM (funcional pero UX pobre)
**Síntoma:** Arrastrar card del panel izquierdo al centro siempre coloca al final

### Causa raíz

`Step4TemplateSelector.tsx:1542-1554`: El `onDrop` handler llama `insertSection(parsed.componentId)` sin pasar `insertIndex`. La función `insertSection()` (línea 619) tiene soporte para `insertIndex?` pero nunca lo recibe del drop handler.

### Fix

**Admin** (`apps/admin/`):
1. Implementar cálculo de drop position basado en `e.clientY` y las posiciones de los items del panel central
2. Pasar el índice calculado a `insertSection(componentId, dropIndex)`
3. Alternativa simple: usar drop zones entre cada item (como separadores invisibles que se activan al arrastrar)

**Archivos:** `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
**Riesgo:** Medio — requiere lógica de hit-testing o drop zones intermedias

---

## Issue #7 — MEDIUM: Footers todos idénticos visualmente

**Severidad:** MEDIUM (confunde al usuario)
**Síntoma:** Los 8 footers se ven exactamente iguales

### Causa raíz

`sectionCatalog.ts` define 8 footers pero todos con `defaultProps: { contact: DEMO_CONTACT }` sin diferenciación visual. Los thumbnails son placeholders genéricos de placehold.co. No hay props de layout/estilo que diferencien un footer de otro.

### Fix

**Admin** (`apps/admin/`):
1. Agregar `layoutVariant` a cada footer (ej: `"classic"`, `"modern"`, `"minimal"`, `"columns"`)
2. Diferenciar props: `columnCount`, `showNewsletter`, `showSocialLinks`, `showBranding`
3. Generar thumbnails reales o al menos diferenciados por color/layout

**Archivos:** `apps/admin/src/registry/sectionCatalog.ts`
**Riesgo:** Medio — requiere que el storefront (web) tenga renderer para cada variante

---

## Issue #8 — MEDIUM: Excel import tab ilegible (tema blanco)

**Severidad:** MEDIUM (funcionalidad ilegible)
**Síntoma:** Tab de subir con Excel no tomó el theme, se ve todo claro con letras claras

### Causa raíz

`ExcelProductImporter.css` (líneas 264-302):
- `.preview-row` no tiene `background` definido
- `.excel-preview-table th` usa `var(--nv-bg-secondary, #f1f5f9)` (fallback claro)
- `.preview-row:hover` usa `var(--nv-bg-secondary, #f8fafc)` (fallback claro)
- En dark mode, los fallbacks claros se aplican → texto oscuro sobre fondo claro, o viceversa

### Fix

**Admin** (`apps/admin/`):
1. Agregar `background: var(--nv-bg-surface, #1e293b)` a `.preview-row`
2. Actualizar fallbacks de `th` y `td` para que sean dark-aware
3. Asegurar que `.excel-preview-table` hereda correctamente las CSS variables del tema

**Archivos:** `apps/admin/src/pages/BuilderWizard/components/ExcelProductImporter.css`
**Riesgo:** Bajo — solo CSS

---

## Orden de Ejecución Recomendado

| Orden | Issue | Tipo | App | Impacto |
|-------|-------|------|-----|---------|
| **1** | #1 — Columna `selected_font_key` | SQL migration | API (BD) | Desbloquea todo Step 4 |
| **2** | #4 — 33 items `enterprise` erróneos | Data fix | Admin | Desbloquea componentes |
| **3** | #5 — Click salta a Step 6 | Logic fix | Admin | Elimina salto brusco |
| **4** | #3 — Cards Growth opacas | UX fix | Admin | Permite exploración |
| **5** | #2 — White flash en primer render | CSS fix | Admin | Fix visual inicial |
| **6** | #8 — Excel tab ilegible | CSS fix | Admin | Fix legibilidad |
| **7** | #6 — Drag & Drop posición | UX enhancement | Admin | Mejora usabilidad |
| **8** | #7 — Footers idénticos | Content/Design | Admin + Web | Requiere más diseño |

Los primeros 6 son fixes directos que se pueden implementar en una sesión.
Los últimos 2 (#6 y #7) requieren más diseño/implementación.

---

## Validación End-to-End

1. Ejecutar migración SQL en Admin DB
2. Hacer onboarding completo desde Step 1 hasta Step 12
3. Verificar que cada font/template/palette persiste sin 500
4. Verificar que todas las cards son interactuables (sin opacidad bloqueante)
5. Verificar que ningún componente dice "Enterprise" excepto video_banner y team_gallery
6. Verificar que el Excel import es legible
7. Verificar que no hay flash blanco al entrar
8. `npm run lint && npm run typecheck && npm run build` en API y Admin

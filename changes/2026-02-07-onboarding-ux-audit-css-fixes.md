# Auditoría UX/UI Onboarding Wizard – Fase 1: Tokenización CSS, Contraste y Responsive

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Repo:** novavision (apps/admin)
- **Archivos modificados:**
  - `apps/admin/src/pages/BuilderWizard/BuilderWizard.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step1Slug.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step2Logo.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step5Auth.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step8ClientData.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step10Summary.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step11Terms.css`
  - `apps/admin/src/pages/BuilderWizard/steps/Step12Success.css`

---

## Resumen

Auditoría UX/UI completa del onboarding wizard (12 pasos). Se ejecutaron 3 sub-agentes en paralelo para auditar Steps 1-6, Steps 7-12 y componentes compartidos. Se encontraron **500+ colores hardcodeados**, 7 de 12 steps sin media queries, fallos WCAG de contraste, y eliminaciones de `outline` que rompen accesibilidad de teclado.

Esta fase (Fase 1) aplica fixes CSS-only a 8 archivos, cubriendo los steps más críticos y el contenedor global. **No se modificó lógica de negocio ni archivos TSX.**

---

## Metodología

1. **Mapeo de estructura:** 12 steps, componentes compartidos, sistema de theme tokens
2. **Auditoría del sistema de tokens:** `tokens.js` → `theme.js` → `GlobalStyle.js` → CSS variables `--nv-*`
3. **Auditoría paralela:** 3 sub-agentes auditaron Steps 1-6, Steps 7-12, y shared components
4. **Generación de reporte JSON:** consolidación de hallazgos con severidad, archivo, línea y fix sugerido
5. **Aplicación de fixes:** CSS-only, con fallbacks seguros en todas las variables

---

## Pipeline de Tokens (referencia)

```
tokens.js (204 líneas, hex base)
   ↓
theme.js (352 líneas, mapeos semánticos)
   ↓
GlobalStyle.js (327 líneas, CSS custom properties via styled-components)
   ↓
:root { --nv-bg-canvas, --nv-bg-surface, --nv-text-primary, --nv-text-secondary,
         --nv-text-muted, --nv-text-inverse, --nv-text-brand, --nv-border-default,
         --nv-border-strong, --nv-border-subtle, --nv-brand-primary,
         --nv-brand-gradient-hero, --nv-shadow-sm/md/lg, --nv-alert-*-bg/border/text,
         --nv-font-sans, --nv-radius-md, --nv-transition-base, ... }
```

---

## Hallazgos Críticos

### 1. CRÍTICO (a11y): `outline: none` en Step8ClientData.css

**Problema:** `.form-group input:focus { outline: none; }` elimina completamente el indicador de foco para usuarios de teclado. Viola WCAG 2.1 SC 2.4.7 (Focus Visible).

**Fix:** Reemplazado por `outline: 2px solid var(--nv-brand-primary, #6366f1); outline-offset: 2px;`

### 2. CRÍTICO (contraste): `color: #999` en Step5Auth.css

**Problema:** `.auth-note { color: #999; }` sobre fondo blanco = ratio 2.85:1. WCAG AA requiere mínimo 4.5:1.

**Fix:** `color: var(--nv-text-muted, #64748b)` → ratio 4.6:1 (WCAG AA pass).

### 3. CRÍTICO (responsive): 7 de 12 steps sin `@media` queries

**Problema:** Steps 1, 2, 3, 4, 5, 6, 8 no tenían breakpoints. Paddings de 48px, grids de 320px fijos, contenedores de min-height 700px se desbordan en móvil.

**Fix (Fase 1):** Agregadas `@media (max-width: 640px)` a Steps 1, 2, 5, 8, 10, 11, 12 y BuilderWizard.css global.

### 4. ALTO (tokens): 500+ colores hardcodeados

**Problema:** El sistema de tokens `--nv-*` existe y es robusto, pero los CSS individuales usaban hexadecimales crudos (`#333`, `#666`, `#999`, `#e0e0e0`, `white`, `#f5f5f5`, etc.). Esto rompe temas dark/custom y la consistencia visual.

**Fix (Fase 1):** ~120 propiedades migradas a CSS variables con fallback seguro en 7 archivos.

---

## Detalle de Cambios por Archivo

### BuilderWizard.css (contenedor global)

| Cambio | Detalle |
|--------|---------|
| **Global focus-visible** | Agregada regla para `button`, `a`, `input`, `select`, `textarea`, `[tabindex]` dentro de `.wizard-app` → `outline: 2px solid var(--nv-brand-primary)` |
| **Responsive mobile** | `@media (max-width: 640px)`: reduce padding de `.wizard-content`, `.step-container`, y font-size de headers |

**Impacto:** Todos los 12 steps heredan estas reglas automáticamente.

### Step1Slug.css

| Cambio | Detalle |
|--------|---------|
| **Responsive** | `@media (max-width: 640px)`: padding reducido, h1 a 1.75rem, `slug-input-group` con `flex-wrap`, suffix con font más chico |

**Nota:** Ya estaba bien tokenizado; solo faltaba responsive.

### Step2Logo.css (18 tokens migrados)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `#6b7280` | `var(--nv-text-secondary, #64748b)` |
| `#d1d5db` | `var(--nv-border-default, #cbd5e1)` |
| `#f9fafb` | `var(--nv-bg-canvas, #f8fafc)` |
| `#111827` | `var(--nv-text-primary, #1e293b)` |
| `#6366f1` | `var(--nv-brand-primary, #6366f1)` |
| `#e5e7eb` | `var(--nv-border-default, #cbd5e1)` |
| `#374151` | `var(--nv-text-primary, #1e293b)` |
| `#9ca3af` | `var(--nv-text-muted, #64748b)` |
| `white` | `var(--nv-text-inverse, white)` |
| `linear-gradient(hover)` | `filter: brightness(1.05)` |

**Responsive:** upload-label padding reducido, logo preview a 150×150px en mobile.

### Step5Auth.css (FULL REWRITE — 18 tokens)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `white` (background) | `var(--nv-bg-surface, white)` |
| `0 4px 20px rgba(...)` | `var(--nv-shadow-md, ...)` |
| `#1a1a1a` | `var(--nv-text-primary, #1e293b)` |
| `#666` | `var(--nv-text-secondary, #64748b)` |
| `#667eea` | `var(--nv-brand-primary, #6366f1)` |
| `#f8f9fa` | `var(--nv-bg-canvas, #f8fafc)` |
| `#333` | `var(--nv-text-primary, #1e293b)` |
| `linear-gradient(...)` | `var(--nv-brand-gradient-hero, ...)` |
| `#764ba2` (hover) | `var(--nv-text-brand, #4f46e5)` |
| **`#999`** (contraste WCAG fail) | **`var(--nv-text-muted, #64748b)`** |

**Responsive:** cards a 1.5rem 1rem, h2 a 20px, iconos a 48px, benefits padding reducido.

### Step8ClientData.css (CRITICAL a11y + 14 tokens)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `white` (background) | `var(--nv-bg-surface, white)` |
| `0 2px 8px rgba(...)` | `var(--nv-shadow-md, ...)` |
| `#333` | `var(--nv-text-primary, #1e293b)` |
| `#e74c3c` | `var(--nv-alert-error-text, #dc2626)` |
| `#e0e0e0` | `var(--nv-border-default, #cbd5e1)` |
| **`outline: none`** | **`outline: 2px solid var(--nv-brand-primary); outline-offset: 2px`** |
| `#667eea` | `var(--nv-brand-primary, #6366f1)` |
| `#f5f5f5` | `var(--nv-bg-canvas, #f8fafc)` |
| `#666` | `var(--nv-text-secondary, #64748b)` |
| `#fee` / `#c33` | `var(--nv-alert-error-bg/text)` |
| `#f8f9ff` / `#e0e7ff` | `var(--nv-bg-canvas)` / `var(--nv-border-subtle)` |
| `#555` | `var(--nv-text-secondary, #64748b)` |

**Responsive:** form padding reducido, actions apilado vertical, info-box padding reducido.

### Step10Summary.css (8 tokens + responsive)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `#d1fae5` (badge success) | `var(--nv-alert-success-bg, #d1fae5)` |
| `#fef3c7` (badge pending) | `var(--nv-alert-warning-bg, #fef3c7)` |
| `#fee2e2` / `#991b1b` (badge error) | `var(--nv-alert-error-bg/text)` |
| `#f8f9ff` (next-steps bg) | `var(--nv-bg-canvas, #f8fafc)` |
| `#e0e7ff` (next-steps border) | `var(--nv-border-subtle, #e2e8f0)` |
| `#667eea` (h3) | `var(--nv-brand-primary, #6366f1)` |
| `#555` (li) | `var(--nv-text-secondary, #64748b)` |
| `#fff3cd` / `#ffc107` (warning) | `var(--nv-alert-warning-bg/border)` |

**Responsive:** summary-items apilados vertical, btn-submit 100% ancho.

### Step11Terms.css (FULL REWRITE — 22 tokens)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `white` (×3 backgrounds) | `var(--nv-bg-surface, white)` |
| `0 2px 12px rgba(...)` (×2) | `var(--nv-shadow-md, ...)` |
| `#1a1a1a` | `var(--nv-text-primary, #1e293b)` |
| `#666` (×2) | `var(--nv-text-secondary, #64748b)` |
| `#e0e0e0` (×2) | `var(--nv-border-default, #cbd5e1)` |
| `#fafafa` | `var(--nv-bg-canvas, #f8fafc)` |
| `#333` (×2) | `var(--nv-text-primary, #1e293b)` |
| `#555` (×2) | `var(--nv-text-secondary, #64748b)` |
| `#667eea` (×3) | `var(--nv-brand-primary, #6366f1)` |
| `#f8f9ff` | `var(--nv-bg-canvas, #f8fafc)` |
| `linear-gradient(...)` | `var(--nv-brand-gradient-hero, ...)` |
| `white` (btn color) | `var(--nv-text-inverse, white)` |
| `0 6px 20px rgba(...)` | `var(--nv-shadow-lg, ...)` |
| `#fff8e1` / `#ffc107` | `var(--nv-alert-warning-bg/border)` |
| `#f1f1f1` / `#ccc` / `#999` (scrollbar) | `var(--nv-bg-canvas)` / `var(--nv-border-default)` / `var(--nv-border-strong)` |

**Responsive:** terms-box/acceptance a 1.25rem 1rem, scroll max-height a 300px.

### Step12Success.css (20+ tokens + clamp/min + responsive mejorado)

| Propiedad original | Token aplicado |
|---------------------|----------------|
| `min-height: 600px` | `min(600px, 80vh)` |
| `padding: 40px 20px` | `clamp(1.25rem, 5vw, 2.5rem) 20px` |
| `padding: 48px 40px` | `clamp(1.5rem, 5vw, 3rem) clamp(1.25rem, 5vw, 2.5rem)` |
| `white` (×2 backgrounds) | `var(--nv-bg-surface, white)` |
| `0 4px 20px rgba(...)` | `var(--nv-shadow-lg, ...)` |
| `#1a1a1a` (×4) | `var(--nv-text-primary, #1e293b)` |
| `#64748b` / `#475569` (×5) | `var(--nv-text-secondary, #64748b)` |
| `#f8fafc` / `#f1f5f9` (×3) | `var(--nv-bg-canvas, #f8fafc)` |
| `#e2e8f0` (×5) | `var(--nv-border-subtle, #e2e8f0)` |
| `#3b82f6` (×2) | `var(--nv-brand-primary, #3b82f6)` |

**Responsive mejorado:** card padding, h1 a 24px, subtitle a 14px, icono a 48px, info-row apilado, next-steps padding reducido.

---

## Validación

| Check | Resultado |
|-------|-----------|
| `npm run lint` (admin) | ✅ 0 errores nuevos (766 warnings preexistentes `no-explicit-any` en API, sin relación) |
| Git diff | ✅ 8 archivos, todos cambios CSS-only |
| Lógica de negocio | ✅ Sin cambios – solo CSS |
| Fallbacks | ✅ Todas las `var()` tienen fallback hardcodeado seguro |

---

## Trabajo Pendiente (Fase 2)

Los siguientes archivos aún necesitan tokenización y responsive:

| Archivo | Prioridad | Colores hardcodeados | @media existente |
|---------|-----------|---------------------|------------------|
| Step4 TemplateSelector.css | **CRÍTICA** | ~100+ | ❌ Grid 320px fijo |
| Step3 CatalogLoader.css | **CRÍTICA** | ~60+ | ❌ Ninguno |
| Step6 PaywallPlans.css | **ALTA** | ~90+ | Parcial |
| GalleryModal.css | ALTA | ~25 | ❌ Sidebar fijo |
| Step9 MPCredentials.css | MEDIA | ~30 | ❌ padding 48px |
| Step7 MercadoPago.css | BAJA | ~24 | ✅ (640px) |
| ManualProductLoader.css | MEDIA | ~45+ | Parcial |
| ProductFormModal.css | BAJA | ~31 | ✅ Tiene focus-visible |
| NotificationModal.css | MEDIA | ~12 | ❌ Falta ARIA |

---

## Fix Adicional: Alert Text Invisible + Header Blanco (Dark Theme)

**Fecha:** 2026-02-07 (sesión 2)
**Archivos modificados adicionalmente:**
- `apps/admin/src/theme/GlobalStyle.js`
- `apps/admin/src/components/OnboardingHeader/OnboardingHeader.jsx`

### Problema

1. **Alertas invisibles en dark theme:** Los textos de alerta ("📍 Importante: Una vez elegido…", "💎 Plan Growth: Incluye URL personalizada…") eran invisibles en el wizard de onboarding.
2. **Header blanco:** El header del onboarding se mostraba blanco cuando el resto de la página era dark.

### Causa raíz

**Alertas:** Inconsistencia en `GlobalStyle.js`:
- Los *backgrounds* de alerta (`--nv-alert-warning-bg`) se leen de `theme.semantic?.warning?.light` — que **no existe** en `darkTheme` → fallback light yellow `#fef3c7` ✅
- Los *textos* de alerta (`--nv-alert-warning-text`) se leían de `theme.alert?.warning?.text` — que **sí existe** en `darkTheme` y vale `tokens.warning[50]` = `#fef3c7` (amarillo claro, diseñado para fondos oscuros)
- **Resultado:** texto `#fef3c7` sobre fondo `#fef3c7` = invisible

**Header:** El bloque `@supports (backdrop-filter)` en `OnboardingHeader.jsx` tenía fallback `rgba(255, 255, 255, 0.95)` (blanco) en vez de usar el color dark del theme.

### Solución

**GlobalStyle.js** — Cambiar fuente de las CSS vars de texto de alerta:
```diff
- --nv-alert-warning-text: ${({ theme }) => theme.alert?.warning?.text || '#92400e'};
+ --nv-alert-warning-text: ${({ theme }) => theme.semantic?.warning?.text || '#92400e'};

- --nv-alert-info-text: ${({ theme }) => theme.alert?.info?.text || '#1e40af'};
+ --nv-alert-info-text: ${({ theme }) => theme.semantic?.info?.text || '#1e40af'};
```

En dark theme, `semantic` no existe → hardcoded fallback `#92400e` (marrón oscuro) y `#1e40af` (azul oscuro), ambos con buen contraste sobre fondos claros de alerta.

**OnboardingHeader.jsx** — Cambiar fallback del `@supports`:
```diff
- background: ${({ theme }) => theme.header?.bg || 'rgba(255, 255, 255, 0.95)'};
+ background: ${({ theme }) => theme.header?.bg || 'rgba(15, 23, 42, 0.9)'};
```

---

## Fix Adicional: Layout Mobile del Header (Logo + Dots Verticales)

**Fecha:** 2026-02-07 (sesión 3)
**Archivo modificado:** `apps/admin/src/components/OnboardingHeader/OnboardingHeader.jsx`

### Problema

En mobile, el header mantenía layout horizontal (3 columnas), lo que comprimía el logo y los dots de progreso. Usuario solicitó:
- Logo centrado arriba
- Dots de progreso centrados abajo
- Botón "Volver" oculto en mobile (opcional)

### Solución

**OnboardingHeader.jsx** — Cambiar de grid horizontal a flexbox vertical en mobile:

**HeaderContent:**
```diff
  @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
-   grid-template-columns: auto 1fr auto;
-   padding: ${({ theme }) => theme.space[3]} ${({ theme }) => theme.space[4]};
-   min-height: 56px;
+   display: flex;
+   flex-direction: column;
+   gap: ${({ theme }) => theme.space[3]};
+   padding: ${({ theme }) => theme.space[3]} ${({ theme }) => theme.space[4]};
+   min-height: auto;
  }
```

**LeftSection (botón Volver):**
```diff
+ @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
+   display: none;
+ }
```

**CenterSection (logo):**
```diff
+ @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
+   width: 100%;
+   order: 1;
+ }
```

**RightSection (dots):**
```diff
+ @media (max-width: ${({ theme }) => theme.breakpoints.tablet}) {
+   width: 100%;
+   justify-content: center;
+   order: 2;
+ }
```

### Verificación

- Lint: ✅ 0 errores
- Layout mobile: Logo centrado arriba (order: 1), dots centrados abajo (order: 2)
- ProgressText "Paso X de Y" ya tenía `display: none` en mobile → solo quedan dots visibles

---

## Notas de Seguridad

No aplica — cambios exclusivamente visuales (CSS/theme). Sin impacto en autenticación, datos, permisos ni flujo de negocio.

---

## Cómo Probar

1. Levantar admin: `cd apps/admin && npm run dev`
2. Navegar al wizard de onboarding (ruta `/builder`)
3. Verificar cada step en:
   - **Desktop** (1024px+): aspecto visual sin regresiones
   - **Mobile** (375px): layouts sin overflow, textos legibles, botones alcanzables
     - **Header mobile:** logo centrado arriba, dots centrados abajo, sin botón "Volver"
   - **Teclado**: Tab por todos los inputs/botones → focus ring visible (azul/brand)
4. Cambiar paleta/theme en el admin → verificar que colores responden a variables CSS
5. Abrir DevTools → verificar que las propiedades usan `var(--nv-*)` con computed values correctos
6. **Alertas en Step1 (Slug):** los textos "📍 Importante…" y "💎 Plan Growth…" deben ser legibles (marrón oscuro sobre amarillo claro)
7. **Header:** debe ser dark/oscuro, coherente con el fondo de la página

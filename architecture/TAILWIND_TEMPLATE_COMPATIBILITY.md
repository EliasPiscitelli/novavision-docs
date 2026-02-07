# 🎨 Compatibilidad de Templates Tailwind con el Sistema de Temas NovaVision

> **Fecha:** 2025-07-24  
> **Autor:** Copilot Agent  
> **Rama:** feature/automatic-multiclient-onboarding  
> **Estado:** Referencia activa

---

## 1. Resumen Ejecutivo

NovaVision tiene **4 fuentes** que producen o consumen CSS custom properties (`--nv-*`):

| Sistema | Archivo | Rol | Cantidad de vars |
|---------|---------|-----|------------------|
| `paletteToCssVars()` | `apps/web/src/theme/palettes.ts` | Preview (admin) — genera vars | 31 |
| `normalizeThemeVars()` | `apps/api/src/palettes/palettes.service.ts` | API producción — genera vars | 28 |
| `ThemeProvider` | `apps/web/src/theme/ThemeProvider.jsx` | Storefront producción — inyecta en `:root` | ~12 |
| `tailwind.config.js` | `apps/web/tailwind.config.js` | Templates Tailwind — consume vars | 28+ refs |

**Problema:** Hay **17 variables** referenciadas en `tailwind.config.js` que **ningún sistema produce**, y **3 inconsistencias de naming** que rompen la cadena de colores.

---

## 2. Contrato Canónico (28 tokens — API)

Estos son los tokens que la API (`normalizeThemeVars`) garantiza en producción:

| # | Variable CSS | Categoría | Descripción | Ejemplo Light | Ejemplo Dark |
|---|---|---|---|---|---|
| 1 | `--nv-bg` | Fondo | Background de página | `#FFFFFF` | `#0F172A` |
| 2 | `--nv-surface` | Fondo | Background de cards/panels | `#F8FAFC` | `#1E293B` |
| 3 | `--nv-card-bg` | Fondo | Alias de surface para cards | `#F8FAFC` | `#1E293B` |
| 4 | `--nv-text` | Tipografía | Color de texto principal | `#0F172A` | `#F1F5F9` |
| 5 | `--nv-text-muted` | Tipografía | Texto secundario (opaco) | `#64748B` | `#94A3B8` |
| 6 | `--nv-border` | Borde | Borde estándar | `rgba(15,23,42,0.10)` | `rgba(241,245,249,0.10)` |
| 7 | `--nv-shadow` | Sombra | Color base de sombra | `rgba(15,23,42,0.08)` | `rgba(0,0,0,0.30)` |
| 8 | `--nv-primary` | Marca | Color principal de marca | `#2563EB` | `#818CF8` |
| 9 | `--nv-primary-hover` | Marca | Primary al hacer hover | `#1D4ED8` | `#A5B4FC` |
| 10 | `--nv-primary-fg` | Marca | Texto sobre primary (contraste) | `#FFFFFF` | `#000000` |
| 11 | `--nv-accent` | Marca | Color de acento | `#F59E0B` | `#22D3EE` |
| 12 | `--nv-accent-fg` | Marca | Texto sobre accent (contraste) | `#000000` | `#000000` |
| 13 | `--nv-link` | Enlaces | Color de links (= primary) | `#2563EB` | `#818CF8` |
| 14 | `--nv-link-hover` | Enlaces | Link hover (= primary-hover) | `#1D4ED8` | `#A5B4FC` |
| 15 | `--nv-info` | Estado | Color informativo | `#3B82F6` | `#60A5FA` |
| 16 | `--nv-success` | Estado | Color éxito | `#22C55E` | `#4ADE80` |
| 17 | `--nv-warning` | Estado | Color advertencia | `#F59E0B` | `#FBBF24` |
| 18 | `--nv-error` | Estado | Color error | `#EF4444` | `#F87171` |
| 19 | `--nv-ring` | Focus | Anillo de foco | `rgba(37,99,235,0.40)` | `rgba(129,140,248,0.40)` |
| 20 | `--nv-input-bg` | Inputs | Fondo de inputs | `#FFFFFF` | `#1E293B` |
| 21 | `--nv-input-text` | Inputs | Texto de inputs | `#0F172A` | `#F1F5F9` |
| 22 | `--nv-input-border` | Inputs | Borde de inputs | `rgba(15,23,42,0.15)` | `rgba(241,245,249,0.15)` |
| 23 | `--nv-navbar-bg` | Navegación | Fondo del navbar | `#F8FAFC` | `#1E293B` |
| 24 | `--nv-footer-bg` | Navegación | Fondo del footer | `#FFFFFF` | `#0F172A` |
| 25 | `--nv-muted` | Compat | Capa de fondo atenuado | `rgba(15,23,42,0.06)` | `rgba(241,245,249,0.06)` |
| 26 | `--nv-hover` | Compat | Color de hover (= primary) | `#2563EB` | `#818CF8` |
| 27 | `--nv-radius` | Layout | Border radius base | `0.5rem` | `0.5rem` |
| 28 | `--nv-font` | Layout | Font family | `Inter, system-ui, sans-serif` | ídem |

### Extras en `paletteToCssVars()` (solo Preview)

| Variable | Descripción | Nota |
|---|---|---|
| `--nv-surface-fg` | Contraste sobre surface | Solo preview |
| `--nv-bg-fg` | Contraste sobre bg | Solo preview |
| `--nv-input` | Alias de input-bg | Solo preview |

---

## 3. Gaps Identificados

### 3.1 Inconsistencias de Naming (🔴 CRÍTICO)

| Propósito | `paletteToCssVars` + API | `tailwind.config.js` | `ThemeProvider` | Problema |
|---|---|---|---|---|
| **Fondo de página** | `--nv-bg` | `--nv-background` ❌ | `--nv-background` | Tailwind y ThemeProvider usan `background`, API/palettes usan `bg` |
| **Color secundario** | *(no existe)* | `--nv-secondary` ❌ | `--nv-secondary` | No forma parte del contrato canónico de 28 tokens |
| **Font family** | `--nv-font` | `--nv-font-sans` ❌ | *(no inyecta)* | Tailwind espera `font-sans`, API emite `font` |

### 3.2 Variables Tailwind sin Productor (🟡 MEDIO)

Estas 14 variables se referencian en `tailwind.config.js` pero ningún sistema las genera:

| Variable | Uso Tailwind | Solución Propuesta |
|---|---|---|
| `--nv-font-mono` | `fontFamily.mono` | Agregar con fallback `"JetBrains Mono", monospace` |
| `--nv-font-display` | `fontFamily.display` | Agregar con fallback `var(--nv-font)` |
| `--nv-shadow-sm` | `boxShadow.nv-sm` | Derivar de `--nv-shadow` con opacidad menor |
| `--nv-shadow-md` | `boxShadow.nv-md` | Derivar de `--nv-shadow` |
| `--nv-shadow-lg` | `boxShadow.nv-lg` | Derivar de `--nv-shadow` con blur mayor |
| `--nv-shadow-xl` | `boxShadow.nv-xl` | Derivar de `--nv-shadow` con blur máximo |
| `--nv-radius-sm` | `borderRadius.nv-sm` | `calc(var(--nv-radius) * 0.5)` |
| `--nv-radius-lg` | `borderRadius.nv-lg` | `calc(var(--nv-radius) * 1.5)` |
| `--nv-radius-xl` | `borderRadius.nv-xl` | `calc(var(--nv-radius) * 2)` |
| `--nv-transition-fast` | `transitionDuration.nv-fast` | `150ms` |
| `--nv-transition` | `transitionDuration.nv` | `200ms` |
| `--nv-transition-slow` | `transitionDuration.nv-slow` | `500ms` |
| `--nv-easing` | `transitionTimingFunction.nv` | `cubic-bezier(0.4, 0, 0.2, 1)` |

### 3.3 Clash Semántico de `--nv-muted` (🟡 MEDIO)

| Contexto | Valor | Tipo |
|---|---|---|
| `paletteToCssVars` / API | `rgba(text, 0.06)` | Capa de **fondo** semitransparente |
| `tokens.js` / ThemeProvider legacy | `#64748B` | Color de **texto** atenuado |
| Tailwind `text-nv-muted` | ¿? | Ambiguo — ¿es texto o fondo? |

**Resultado:** Si un template Tailwind usa `text-nv-muted` para texto secundario, en producción recibiría un rgba semitransparente de fondo en vez de un color de texto legible.

---

## 4. Plan de Corrección

### Paso 1: Agregar Aliases en `paletteToCssVars()` y `normalizeThemeVars()` (API)

```typescript
// En paletteToCssVars() — apps/web/src/theme/palettes.ts
// Agregar aliases para compatibilidad Tailwind:
'--nv-background':     vars['--nv-bg'],          // alias
'--nv-secondary':      vars['--nv-accent'],       // mapear a accent como fallback
'--nv-secondary-fg':   vars['--nv-accent-fg'],    // idem
'--nv-font-sans':      vars['--nv-font'],         // alias
'--nv-font-mono':      '"JetBrains Mono", "Fira Code", monospace',
'--nv-font-display':   vars['--nv-font'],         // alias (override por template)

// Derivados de sombra:
'--nv-shadow-sm':  `0 1px 2px ${vars['--nv-shadow']}`,
'--nv-shadow-md':  `0 4px 6px -1px ${vars['--nv-shadow']}`,
'--nv-shadow-lg':  `0 10px 15px -3px ${vars['--nv-shadow']}`,
'--nv-shadow-xl':  `0 20px 25px -5px ${vars['--nv-shadow']}`,

// Derivados de radius:
'--nv-radius-sm':  `calc(${vars['--nv-radius']} * 0.5)`,
'--nv-radius-lg':  `calc(${vars['--nv-radius']} * 1.5)`,
'--nv-radius-xl':  `calc(${vars['--nv-radius']} * 2)`,

// Transiciones (estáticas, no dependen de paleta):
'--nv-transition-fast': '150ms',
'--nv-transition':      '200ms',
'--nv-transition-slow':  '500ms',
'--nv-easing':          'cubic-bezier(0.4, 0, 0.2, 1)',
```

### Paso 2: Resolver `--nv-muted` Semántico

**Opción Recomendada:** Separar en dos tokens:

```css
--nv-muted:       /* mantener como color de TEXTO atenuado (#64748B / #94A3B8) */
--nv-muted-bg:    /* nuevo token para capa de fondo semitransparente */
```

Actualizar `paletteToCssVars`:
```typescript
'--nv-muted':    isDark ? '#94A3B8' : '#64748B',           // texto atenuado
'--nv-muted-bg': rgbaFrom(isDark ? textLight : text, 0.06), // fondo semitransparente
```

### Paso 3: Actualizar `tailwind.config.js`

```javascript
// NO cambiar nada de los mapeos existentes.
// Solo asegurarse de que content incluya los templates:
module.exports = {
  content: [
    './src/__dev/**/*.{js,ts,jsx,tsx}',
    './src/templates/**/*.{js,ts,jsx,tsx}',  // ← AGREGAR
  ],
  // ...resto sin cambios
}
```

### Paso 4: Actualizar ThemeProvider (opcional)

Agregar inyección de `--nv-bg` como alias de `--nv-background` para retrocompatibilidad:

```javascript
// En ThemeProvider.jsx, después de inyectar los colores:
if (colors.background) {
  root.style.setProperty('--nv-bg', colors.background);
}
```

---

## 5. Tabla de Mapeo Final (Post-Corrección)

### Colores Core (obligatorios en todo template)

| Tailwind Class | CSS Variable | Descripción |
|---|---|---|
| `bg-nv-background` | `var(--nv-background)` | Fondo de página |
| `bg-nv-surface` | `var(--nv-surface)` | Fondo de cards/panels |
| `text-nv-text` | `var(--nv-text)` | Texto principal |
| `text-nv-muted` | `var(--nv-muted)` | Texto secundario |
| `bg-nv-primary` | `var(--nv-primary)` | Color de marca |
| `text-nv-primary` | `var(--nv-primary)` | Texto/ícono primary |
| `bg-nv-secondary` | `var(--nv-secondary)` | Color secundario |
| `bg-nv-accent` | `var(--nv-accent)` | Color de acento |
| `border-nv-border` | `var(--nv-border)` | Borde estándar |

### Colores de Estado

| Tailwind Class | CSS Variable |
|---|---|
| `text-nv-success` / `bg-nv-success` | `var(--nv-success)` |
| `text-nv-warning` / `bg-nv-warning` | `var(--nv-warning)` |
| `text-nv-error` / `bg-nv-error` | `var(--nv-error)` |
| `text-nv-info` / `bg-nv-info` | `var(--nv-info)` |

### Tokens Extendidos (Tailwind-only)

| Utilidad | Fallback |
|---|---|
| `shadow-nv-sm` … `shadow-nv-xl` | Derivados de `--nv-shadow` |
| `rounded-nv-sm` … `rounded-nv-xl` | Derivados de `--nv-radius` |
| `duration-nv-fast` / `duration-nv` / `duration-nv-slow` | Valores estáticos |
| `ease-nv` | `cubic-bezier(0.4, 0, 0.2, 1)` |
| `font-sans` / `font-mono` / `font-display` | De `--nv-font-*` |

---

## 6. Checklist de Validación para Nuevos Templates Tailwind

- [ ] **Todos los colores** usan `var(--nv-*)` o `nv-*` (Tailwind utility classes)
- [ ] **Cero colores hardcodeados** (`bg-blue-500`, `#3b82f6`, `rgb(...)`)
- [ ] **Dark mode** se resuelve automáticamente vía las CSS vars (no usar `dark:` en Tailwind)
- [ ] `responsive` con breakpoints Tailwind (`sm:`, `md:`, `lg:`, `xl:`)
- [ ] `--nv-muted` se usa para **texto** secundario, NO como fondo
- [ ] Cards usan `bg-nv-surface`, página general usa `bg-nv-background`
- [ ] Botones primarios: `bg-nv-primary text-[var(--nv-primary-fg)]`
- [ ] Focus rings: `focus:ring-2 focus:ring-[var(--nv-ring)]`
- [ ] Inputs: `bg-[var(--nv-input-bg)] text-[var(--nv-input-text)] border-[var(--nv-input-border)]`
- [ ] No usar `theme.colors.*` (es el sistema legacy de styled-components)
- [ ] No usar `styled-components` (deprecado para templates nuevos)

---

## 7. Cómo Interactúa el Dark Mode

NovaVision **NO usa la clase `dark:` de Tailwind** para dark mode. En su lugar:

1. La API detecta si `--nv-bg` es oscuro via `isDarkHex()`
2. Automáticamente ajusta TODOS los tokens (texto claro, bordes claros, sombras fuertes)
3. El storefront recibe **un solo set de vars** ya resueltas para light O dark

**Esto significa:** No necesitás `dark:bg-gray-900` — simplemente usás `bg-nv-background` y el valor correcto se inyecta según la paleta elegida.

```jsx
// ✅ Correcto — funciona en light Y dark automáticamente
<div className="bg-nv-background text-nv-text">
  <div className="bg-nv-surface border border-nv-border">
    <h2 className="text-nv-text">Título</h2>
    <p className="text-nv-muted">Subtítulo</p>
  </div>
</div>

// ❌ Incorrecto — NO hace falta esto
<div className="bg-white dark:bg-gray-900 text-gray-900 dark:text-white">
```

---

## 8. Resumen de Prioridades

| Prioridad | Acción | Impacto | Esfuerzo |
|---|---|---|---|
| 🔴 Alta | Agregar alias `--nv-background` en API + palettes | Templates Tailwind ven fondo | 30 min |
| 🔴 Alta | Agregar `--nv-secondary` (= accent fallback) | Templates no quedan sin secondary | 15 min |
| 🔴 Alta | Corregir semántica de `--nv-muted` (texto vs fondo) | Texto muted legible | 45 min |
| 🟡 Media | Agregar alias `--nv-font-sans` | Tipografía Tailwind funciona | 10 min |
| 🟡 Media | Agregar shadow/radius/transition vars derivados | Utilidades Tailwind completas | 30 min |
| 🟢 Baja | Agregar `--nv-font-mono/display` | Tipografía de código/títulos | 10 min |
| 🟢 Baja | Actualizar `content` en tailwind.config.js | Purge correcto para templates | 5 min |

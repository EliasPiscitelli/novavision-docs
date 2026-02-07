# 📝 Guía de Corrección de Prompts para Generación de Templates

> **Fecha:** 2025-07-24  
> **Autor:** Copilot Agent  
> **Rama:** feature/automatic-multiclient-onboarding  
> **Aplica a:** `apps/web/src/ai/prompts/template.prompt.md` y `component.prompt.md`

---

## 1. Contexto

NovaVision usa prompts de IA para generar templates de e-commerce (React + Tailwind). Actualmente hay **3 archivos de prompts**:

| Archivo | Propósito |
|---|---|
| `apps/web/src/ai/prompts/template.prompt.md` | Genera un template completo (9 componentes + Home) |
| `apps/web/src/ai/prompts/component.prompt.md` | Genera un componente individual |
| `apps/web/src/ai/prompts/audit.prompt.md` | Audita código existente |

---

## 2. Errores Encontrados en los Prompts Actuales

### 2.1 Variables CSS Fantasma (🔴 CRÍTICO)

Los prompts listan variables que **no existen** en el contrato canónico de producción:

| Variable en el prompt | ¿Existe? | Problema | Corrección |
|---|---|---|---|
| `--nv-secondary` | ❌ No en API/palettes | Templates generados usan un color que no se inyecta | Reemplazar por `--nv-accent` o agregar alias |
| `--nv-secondary-fg` | ❌ No existe en ningún lado | Texto invisible | Reemplazar por `--nv-accent-fg` |
| `--nv-surface-hover` | ❌ No existe en ningún lado | Hover sin efecto | Eliminar — usar opacity/filter de Tailwind |
| `--nv-border-focus` | ❌ No existe en ningún lado | Focus roto | Reemplazar por `--nv-ring` |

### 2.2 Variables Faltantes en los Prompts (🟡 MEDIO)

Tokens que SÍ existen pero los prompts NO mencionan:

| Variable omitida | Categoría | Importancia |
|---|---|---|
| `--nv-primary-hover` | Marca | Alta — hover de botones primarios |
| `--nv-primary-fg` | Marca | Alta — texto sobre botones primarios |
| `--nv-accent-fg` | Marca | Media — texto sobre accent |
| `--nv-link` / `--nv-link-hover` | Enlaces | Media — color de links |
| `--nv-ring` | Focus | Alta — anillos de foco accesibles |
| `--nv-input-bg/text/border` | Inputs | Alta — formularios de contacto/búsqueda |
| `--nv-navbar-bg` / `--nv-footer-bg` | Layout | Alta — fondos de header/footer |
| `--nv-card-bg` | Layout | Media — alias para cards |
| `--nv-shadow` | Elevación | Media — sombra de cards |
| `--nv-text-muted` | Tipografía | Alta — texto secundario real (vs `--nv-muted`) |
| `--nv-hover` | Interacción | Baja — alias de primary |
| `--nv-radius` / `--nv-font` | Layout | Media — consistencia de diseño |

### 2.3 Clash Semántico de `--nv-muted` (🔴 CRÍTICO)

El prompt dice:
```css
--nv-muted   /* Texto secundario/muted */
```

Pero en producción, `--nv-muted` es `rgba(text, 0.06)` — una capa de **fondo** semitransparente, **no un color de texto**.

**Resultado:** Los templates generados usan `text-[var(--nv-muted)]` para párrafos secundarios → texto prácticamente invisible.

**Corrección:** Usar `--nv-text-muted` para texto secundario.

### 2.4 Ejemplos con Inline var() Innecesarios

El prompt muestra:
```jsx
<button className="bg-[var(--nv-primary)] text-[var(--nv-primary-fg)]">
```

Esto funciona, pero con el `tailwind.config.js` ya configurado, se puede simplificar:
```jsx
<button className="bg-nv-primary text-[var(--nv-primary-fg)]">
```

Solo se necesita `[var(--nv-*)]` para tokens que NO tienen mapeo en `tailwind.config.js` (como `--nv-primary-fg`).

---

## 3. Prompt Corregido — `template.prompt.md`

### Sección "Variables CSS Disponibles" — REEMPLAZAR con:

````markdown
## Variables CSS Disponibles (OBLIGATORIO usar estas)

### Colores Core (mapean a utilidades Tailwind `nv-*`)

```css
/* Fondos */
--nv-bg                /* Fondo principal de la página → bg-nv-background */
--nv-surface           /* Fondo de cards, panels, modals → bg-nv-surface */
--nv-card-bg           /* Alias de surface para cards */
--nv-navbar-bg         /* Fondo del header/navbar */
--nv-footer-bg         /* Fondo del footer */

/* Texto */
--nv-text              /* Texto principal → text-nv-text */
--nv-text-muted        /* Texto secundario/gris → usar SIEMPRE para subtítulos */

/* Marca */
--nv-primary           /* Color principal → bg-nv-primary, text-nv-primary */
--nv-primary-hover     /* Primary al hacer hover */
--nv-primary-fg        /* Texto sobre primary (contraste auto) */
--nv-accent            /* Color de acento → bg-nv-accent */
--nv-accent-fg         /* Texto sobre accent (contraste auto) */

/* Bordes y sombras */
--nv-border            /* Borde estándar → border-nv-border */
--nv-shadow            /* Sombra base */
--nv-ring              /* Anillo de foco (focus) */

/* Enlaces */
--nv-link              /* Color de links */
--nv-link-hover        /* Link en hover */

/* Inputs/Formularios */
--nv-input-bg          /* Fondo de inputs */
--nv-input-text        /* Texto de inputs */
--nv-input-border      /* Borde de inputs */

/* Estados */
--nv-success           /* Verde éxito */
--nv-warning           /* Amarillo advertencia */
--nv-error             /* Rojo error */
--nv-info              /* Azul informativo */

/* Utilidades */
--nv-radius            /* Border radius base */
--nv-font              /* Font family */
```

### ⚠️ Variables que NO EXISTEN (no usar)

```css
/* ❌ PROHIBIDO — No existen en producción */
--nv-secondary         /* Usar --nv-accent en su lugar */
--nv-secondary-fg      /* Usar --nv-accent-fg en su lugar */
--nv-surface-hover     /* Usar hover:opacity-90 o hover:brightness-95 */
--nv-border-focus      /* Usar --nv-ring */
--nv-foreground        /* Usar --nv-text */
```
````

### Sección "Reglas de Diseño — Colores" — REEMPLAZAR con:

````markdown
### 3. Colores con CSS Variables

```jsx
// ✅ Correcto — Utilidades Tailwind mapeadas
<div className="bg-nv-background text-nv-text">
<div className="bg-nv-surface border border-nv-border">
<button className="bg-nv-primary text-[var(--nv-primary-fg)]">

// ✅ Correcto — Notación var() para tokens sin mapeo Tailwind
<input className="bg-[var(--nv-input-bg)] text-[var(--nv-input-text)] border-[var(--nv-input-border)]">
<a className="text-[var(--nv-link)] hover:text-[var(--nv-link-hover)]">

// ✅ Correcto — Texto secundario
<p className="text-[var(--nv-text-muted)]">Descripción secundaria</p>

// ✅ Correcto — Focus accesible
<button className="focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none">

// ✅ Correcto — Hover con Tailwind
<div className="bg-nv-surface hover:opacity-90 transition-opacity">

// ❌ Incorrecto — Color hardcodeado
<button className="bg-blue-500 text-white">
<div style={{ background: '#3b82f6' }}>

// ❌ Incorrecto — Variable fantasma
<div className="bg-[var(--nv-surface-hover)]">
<p className="text-[var(--nv-secondary)]">

// ❌ Incorrecto — Usar --nv-muted para texto (es un fondo rgba)
<p className="text-[var(--nv-muted)]">  <!-- ¡NO! Es rgba semitransparente -->
```
````

### Sección "Precios con Descuento" — CORREGIR:

````markdown
### 7. Precios con Descuento
```jsx
{hasDiscount ? (
  <>
    <span className="text-nv-success font-bold">
      ${product.discountedPrice}
    </span>
    <span className="line-through text-[var(--nv-text-muted)]">
      ${product.originalPrice}
    </span>
    <span className="bg-nv-error text-white px-2 py-1 rounded-[var(--nv-radius)] text-sm">
      -{discount}%
    </span>
  </>
) : (
  <span className="text-nv-text font-bold">${product.originalPrice}</span>
)}
```
````

---

## 4. Prompt Corregido — `component.prompt.md`

### Sección "Variables CSS Disponibles" — REEMPLAZAR con:

````markdown
## Variables CSS Disponibles

### Core (siempre disponibles en producción)
```css
--nv-bg, --nv-surface, --nv-card-bg, --nv-navbar-bg, --nv-footer-bg
--nv-text, --nv-text-muted
--nv-primary, --nv-primary-hover, --nv-primary-fg
--nv-accent, --nv-accent-fg
--nv-border, --nv-shadow, --nv-ring
--nv-link, --nv-link-hover
--nv-input-bg, --nv-input-text, --nv-input-border
--nv-success, --nv-warning, --nv-error, --nv-info
--nv-radius, --nv-font
```

### ⚠️ NO usar (no existen en producción)
```css
--nv-secondary, --nv-secondary-fg   → usar --nv-accent / --nv-accent-fg
--nv-surface-hover                   → usar hover:opacity-90
--nv-border-focus                    → usar --nv-ring
```
````

---

## 5. Prompt Corregido — `audit.prompt.md`

### Sección "Checklist Estilos" — AGREGAR:

````markdown
### ❌ Detectar como ERROR (adicional):

- Uso de `--nv-secondary` (no existe en producción — usar `--nv-accent`)
- Uso de `--nv-surface-hover` (no existe — usar hover utilities)
- Uso de `--nv-border-focus` (no existe — usar `--nv-ring`)
- Uso de `text-[var(--nv-muted)]` para texto (es rgba de fondo — usar `--nv-text-muted`)
- Uso de `theme.colors.*` o `useTheme()` (legacy styled-components)
- Uso de `styled-components` en templates nuevos
````

---

## 6. Reglas para Generación de Templates (resumen para IA)

### SIEMPRE:

1. **Usar `var(--nv-*)` para todos los colores** — Nunca hardcodear hex/rgb/hsl
2. **Texto secundario = `--nv-text-muted`** — NUNCA `--nv-muted` (es rgba de fondo)
3. **Botones primarios:**
   ```jsx
   className="bg-nv-primary text-[var(--nv-primary-fg)] 
              hover:bg-[var(--nv-primary-hover)] 
              focus:ring-2 focus:ring-[var(--nv-ring)]"
   ```
4. **Cards:**
   ```jsx
   className="bg-nv-surface border border-nv-border 
              rounded-[var(--nv-radius)] shadow-[var(--nv-shadow)]"
   ```
5. **Header:** usar `bg-[var(--nv-navbar-bg)]`
6. **Footer:** usar `bg-[var(--nv-footer-bg)]`
7. **Inputs:**
   ```jsx
   className="bg-[var(--nv-input-bg)] text-[var(--nv-input-text)] 
              border border-[var(--nv-input-border)] 
              focus:ring-2 focus:ring-[var(--nv-ring)]
              rounded-[var(--nv-radius)]"
   ```
8. **Dark mode es automático** — NO usar `dark:` prefix de Tailwind
9. **Responsive** — Mobile-first con `sm:`, `md:`, `lg:`, `xl:`
10. **Animaciones** — framer-motion para entradas, Tailwind `transition-*` para hover/focus

### NUNCA:

1. `--nv-secondary` / `--nv-secondary-fg` → usar `--nv-accent` / `--nv-accent-fg`
2. `--nv-surface-hover` → usar `hover:opacity-90` o `hover:brightness-95`
3. `--nv-border-focus` → usar `--nv-ring` con `focus:ring-2`
4. `--nv-foreground` → usar `--nv-text`
5. `text-[var(--nv-muted)]` para texto → usar `text-[var(--nv-text-muted)]`
6. Clases de color Tailwind nativas (`bg-blue-500`, `text-gray-600`)
7. `styled-components` / `theme.colors.*` / `useTheme()`
8. `dark:` prefix (dark mode se resuelve por CSS vars)
9. Colores inline (`style={{ color: '#333' }}`)

---

## 7. Contrato de Variables — Referencia Rápida

```
┌─────────────────────────────────────────────────────┐
│               VARIABLES PRODUCCIÓN (28)               │
├──────────────┬──────────────────────────────────────┤
│ Fondos       │ --nv-bg, --nv-surface, --nv-card-bg  │
│              │ --nv-navbar-bg, --nv-footer-bg        │
├──────────────┼──────────────────────────────────────┤
│ Texto        │ --nv-text, --nv-text-muted            │
├──────────────┼──────────────────────────────────────┤
│ Marca        │ --nv-primary, --nv-primary-hover      │
│              │ --nv-primary-fg                        │
│              │ --nv-accent, --nv-accent-fg            │
├──────────────┼──────────────────────────────────────┤
│ Interacción  │ --nv-link, --nv-link-hover            │
│              │ --nv-ring, --nv-hover                  │
├──────────────┼──────────────────────────────────────┤
│ Bordes       │ --nv-border, --nv-shadow              │
├──────────────┼──────────────────────────────────────┤
│ Inputs       │ --nv-input-bg, --nv-input-text        │
│              │ --nv-input-border                      │
├──────────────┼──────────────────────────────────────┤
│ Estados      │ --nv-success, --nv-warning             │
│              │ --nv-error, --nv-info                  │
├──────────────┼──────────────────────────────────────┤
│ Layout       │ --nv-radius, --nv-font                │
├──────────────┼──────────────────────────────────────┤
│ Compat       │ --nv-muted (⚠️ fondo rgba, NO texto) │
└──────────────┴──────────────────────────────────────┘
```

---

## 8. Ejemplo Completo: Header Correcto

```jsx
import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { FiMenu, FiX, FiShoppingCart, FiSearch } from 'react-icons/fi';

export default function Header({ logo, socialLinks }) {
  const [menuOpen, setMenuOpen] = useState(false);

  return (
    <header 
      className="sticky top-0 z-50 
                 bg-[var(--nv-navbar-bg)] 
                 border-b border-[var(--nv-border)]
                 shadow-[var(--nv-shadow)]"
    >
      <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
        {/* Logo */}
        {logo?.show_logo && logo?.url && (
          <img 
            src={logo.url} 
            alt="Logo" 
            className="h-10 object-contain"
          />
        )}

        {/* Nav Desktop */}
        <nav className="hidden md:flex gap-6">
          {['Inicio', 'Productos', 'Contacto'].map(item => (
            <a
              key={item}
              href={`#${item.toLowerCase()}`}
              className="text-[var(--nv-text)] 
                         hover:text-[var(--nv-primary)] 
                         transition-colors duration-200
                         font-medium"
            >
              {item}
            </a>
          ))}
        </nav>

        {/* Actions */}
        <div className="flex items-center gap-3">
          <button 
            aria-label="Buscar"
            className="p-2 rounded-[var(--nv-radius)] 
                       text-[var(--nv-text)] 
                       hover:bg-[var(--nv-muted)]
                       focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none
                       transition-colors"
          >
            <FiSearch size={20} />
          </button>
          <button 
            aria-label="Carrito"
            className="p-2 rounded-[var(--nv-radius)] 
                       text-[var(--nv-text)] 
                       hover:bg-[var(--nv-muted)]
                       focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none
                       transition-colors"
          >
            <FiShoppingCart size={20} />
          </button>

          {/* Hamburger Mobile */}
          <button 
            aria-label={menuOpen ? 'Cerrar menú' : 'Abrir menú'}
            className="md:hidden p-2"
            onClick={() => setMenuOpen(!menuOpen)}
          >
            {menuOpen ? <FiX size={24} /> : <FiMenu size={24} />}
          </button>
        </div>
      </div>

      {/* Mobile Menu */}
      <AnimatePresence>
        {menuOpen && (
          <motion.nav
            initial={{ height: 0, opacity: 0 }}
            animate={{ height: 'auto', opacity: 1 }}
            exit={{ height: 0, opacity: 0 }}
            className="md:hidden overflow-hidden 
                       bg-[var(--nv-navbar-bg)] 
                       border-t border-[var(--nv-border)]"
          >
            <div className="px-4 py-3 flex flex-col gap-3">
              {['Inicio', 'Productos', 'Contacto'].map(item => (
                <a
                  key={item}
                  href={`#${item.toLowerCase()}`}
                  className="text-[var(--nv-text)] 
                             hover:text-[var(--nv-primary)] 
                             py-2 text-lg"
                  onClick={() => setMenuOpen(false)}
                >
                  {item}
                </a>
              ))}
            </div>
          </motion.nav>
        )}
      </AnimatePresence>
    </header>
  );
}
```

**Nota:** Este ejemplo usa correctamente:
- `--nv-navbar-bg` para fondo de header (no `--nv-surface`)
- `--nv-text` para texto de nav
- `--nv-primary` para hover de links
- `--nv-border` para separadores
- `--nv-ring` para focus accesible
- `--nv-muted` como fondo hover de iconos (uso correcto: es rgba de fondo)
- `--nv-shadow` para elevación
- `transition-colors` de Tailwind (no `--nv-transition`)
- framer-motion para animaciones de menú mobile

# NovaVision Dev Portal - Design System

> Documentación técnica del sistema de diseño del Dev Portal.

---

## 📖 Índice

1. [Visión General](#visión-general)
2. [Tokens de Diseño](#tokens-de-diseño)
3. [Componentes Atómicos](#componentes-atómicos)
4. [Patrones de Uso](#patrones-de-uso)
5. [Animaciones](#animaciones)
6. [Accesibilidad](#accesibilidad)

---

## Visión General

El Design System del Dev Portal está construido con:

- **Tailwind CSS** para utilidades
- **Framer Motion** para animaciones
- **CSS Variables** para theming dinámico
- **React 18** como framework

### Filosofía

- **Dark Mode First:** Todo el portal usa un tema oscuro basado en Slate
- **Componentes Atómicos:** Componentes pequeños y reutilizables
- **Tokens Centralizados:** Todos los valores de diseño en un solo lugar
- **Animaciones Sutiles:** Transiciones suaves que no distraen

---

## Tokens de Diseño

### Ubicación

```
src/__dev/design-system/tokens.js
```

### Colores

#### Backgrounds

| Token | Valor | Uso |
|-------|-------|-----|
| `bg.app` | `#0F172A` | Fondo principal de la aplicación |
| `bg.surface` | `#1E293B` | Fondo de cards y paneles |
| `bg.surfaceHover` | `#334155` | Hover en superficies |
| `bg.elevated` | `#475569` | Elementos elevados |

#### Borders

| Token | Valor | Uso |
|-------|-------|-----|
| `border.default` | `#334155` | Bordes por defecto |
| `border.muted` | `#1E293B` | Bordes sutiles |
| `border.focus` | `#3B82F6` | Estado focus |

#### Text

| Token | Valor | Uso |
|-------|-------|-----|
| `text.primary` | `#F8FAFC` | Texto principal |
| `text.secondary` | `#94A3B8` | Texto secundario |
| `text.muted` | `#64748B` | Texto deshabilitado |
| `text.inverse` | `#0F172A` | Texto sobre fondos claros |

#### Accent Colors

| Token | Valor | Uso |
|-------|-------|-----|
| `accent.success` | `#22C55E` | Éxito, stable |
| `accent.warning` | `#EAB308` | Advertencias, beta |
| `accent.error` | `#EF4444` | Errores |
| `accent.info` | `#3B82F6` | Información |
| `accent.pro` | `#A855F7` | Features Pro |

### Espaciado

| Token | Valor |
|-------|-------|
| `spacing.xs` | `4px` |
| `spacing.sm` | `8px` |
| `spacing.md` | `16px` |
| `spacing.lg` | `24px` |
| `spacing.xl` | `32px` |
| `spacing.2xl` | `48px` |

### Border Radius

| Token | Valor | Uso |
|-------|-------|-----|
| `radius.sm` | `4px` | Elementos pequeños |
| `radius.md` | `8px` | Botones, inputs |
| `radius.lg` | `12px` | Cards |
| `radius.xl` | `16px` | Modales |
| `radius.full` | `9999px` | Pills, avatares |

### Sombras

| Token | Valor |
|-------|-------|
| `shadow.sm` | `0 1px 2px rgba(0,0,0,0.3)` |
| `shadow.md` | `0 4px 6px rgba(0,0,0,0.4)` |
| `shadow.lg` | `0 10px 15px rgba(0,0,0,0.5)` |
| `shadow.glow.blue` | `0 0 20px rgba(59,130,246,0.3)` |
| `shadow.glow.green` | `0 0 20px rgba(34,197,94,0.3)` |

### Tipografía

| Token | Valor |
|-------|-------|
| `font.family` | `Inter, system-ui, sans-serif` |
| `font.mono` | `JetBrains Mono, Fira Code, monospace` |
| `fontSize.xs` | `12px` |
| `fontSize.sm` | `14px` |
| `fontSize.base` | `16px` |
| `fontSize.lg` | `18px` |
| `fontSize.xl` | `20px` |
| `fontSize.2xl` | `24px` |

---

## Componentes Atómicos

### Ubicación

```
src/__dev/design-system/components.jsx
```

### Badge

Indicadores de estado compactos.

```jsx
import { Badge } from '../design-system/components';

// Variantes
<Badge variant="stable">Stable</Badge>
<Badge variant="beta">Beta</Badge>
<Badge variant="info">Info</Badge>
<Badge variant="error">Error</Badge>
<Badge variant="pro">Pro</Badge>

// Tamaños
<Badge size="sm">Small</Badge>
<Badge size="md">Medium</Badge>
```

**Props:**
| Prop | Tipo | Default | Descripción |
|------|------|---------|-------------|
| `variant` | `'stable' \| 'beta' \| 'info' \| 'error' \| 'pro'` | `'stable'` | Estilo visual |
| `size` | `'sm' \| 'md'` | `'md'` | Tamaño |
| `children` | `ReactNode` | - | Contenido |

### Pill

Pills para indicar entorno o estado.

```jsx
import { Pill } from '../design-system/components';

<Pill icon="🌿" label="Branch" value="develop" color="green" />
<Pill icon="⚡" label="Env" value="development" color="yellow" />
```

**Props:**
| Prop | Tipo | Default | Descripción |
|------|------|---------|-------------|
| `icon` | `string` | - | Emoji o icono |
| `label` | `string` | - | Etiqueta |
| `value` | `string` | - | Valor a mostrar |
| `color` | `'green' \| 'yellow' \| 'blue' \| 'red'` | `'blue'` | Color del acento |

### Card

Contenedor con fondo y bordes.

```jsx
import { Card } from '../design-system/components';

<Card>Contenido básico</Card>
<Card hover>Con efecto hover</Card>
<Card padding="sm">Padding pequeño</Card>
<Card padding="none">Sin padding</Card>
```

**Props:**
| Prop | Tipo | Default | Descripción |
|------|------|---------|-------------|
| `hover` | `boolean` | `false` | Activa efecto hover |
| `padding` | `'none' \| 'sm' \| 'md' \| 'lg'` | `'md'` | Espaciado interno |
| `className` | `string` | - | Clases adicionales |

### SectionCard

Card para secciones del dashboard.

```jsx
import { SectionCard } from '../design-system/components';

<SectionCard
  icon="📄"
  title="Templates"
  description="Catálogo de templates"
  to="/__dev/templates"
  badge={{ text: "5", variant: "info" }}
/>
```

**Props:**
| Prop | Tipo | Descripción |
|------|------|-------------|
| `icon` | `string` | Emoji del icono |
| `title` | `string` | Título de la sección |
| `description` | `string` | Descripción breve |
| `to` | `string` | Ruta de navegación |
| `badge` | `{ text, variant }` | Badge opcional |

### Button

Botón con múltiples variantes.

```jsx
import { Button } from '../design-system/components';

<Button>Primary</Button>
<Button variant="secondary">Secondary</Button>
<Button variant="ghost">Ghost</Button>
<Button variant="success">Success</Button>
<Button variant="danger">Danger</Button>

<Button size="sm">Small</Button>
<Button size="md">Medium</Button>
<Button size="lg">Large</Button>

<Button disabled>Disabled</Button>
```

**Props:**
| Prop | Tipo | Default | Descripción |
|------|------|---------|-------------|
| `variant` | `'primary' \| 'secondary' \| 'ghost' \| 'success' \| 'danger'` | `'primary'` | Estilo |
| `size` | `'sm' \| 'md' \| 'lg'` | `'md'` | Tamaño |
| `disabled` | `boolean` | `false` | Estado deshabilitado |

### Input

Campo de texto estilizado.

```jsx
import { Input } from '../design-system/components';

<Input 
  label="Email"
  placeholder="tu@email.com"
  value={email}
  onChange={handleChange}
/>

<Input 
  leftIcon={<span>🔍</span>}
  placeholder="Buscar..."
/>
```

**Props:**
| Prop | Tipo | Descripción |
|------|------|-------------|
| `label` | `string` | Etiqueta del campo |
| `leftIcon` | `ReactNode` | Icono a la izquierda |
| `...rest` | - | Props de `<input>` |

### ServiceStatus

Indicador de estado de servicios.

```jsx
import { ServiceStatus } from '../design-system/components';

<ServiceStatus 
  name="API" 
  status="online"  // 'online' | 'offline' | 'loading'
/>
```

---

## Patrones de Uso

### Layout de Página

```jsx
export default function MyPage() {
  return (
    <div className="h-full">
      {/* Header */}
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-slate-50 mb-2 flex items-center gap-3">
          <span>📄</span> Título
        </h1>
        <p className="text-slate-400">Descripción de la página.</p>
      </div>

      {/* Content */}
      <div className="flex gap-6 h-[calc(100%-100px)]">
        {/* Left Panel */}
        <div className="w-80 flex-shrink-0">
          <Card>...</Card>
        </div>

        {/* Main Content */}
        <div className="flex-1">
          <Card>...</Card>
        </div>
      </div>
    </div>
  );
}
```

### Grid de Cards

```jsx
<div className="grid grid-cols-2 gap-4">
  <SectionCard ... />
  <SectionCard ... />
  <SectionCard ... />
  <SectionCard ... />
</div>
```

### Lista con Selección

```jsx
{items.map(item => (
  <button
    key={item.id}
    onClick={() => setSelected(item)}
    className={`w-full text-left p-4 border-b border-slate-700 transition-colors ${
      selected?.id === item.id
        ? 'bg-blue-600/10 border-l-2 border-l-blue-500'
        : 'hover:bg-slate-700/50'
    }`}
  >
    ...
  </button>
))}
```

---

## Animaciones

Usamos Framer Motion para animaciones consistentes.

### Transiciones de Página

```jsx
import { motion, AnimatePresence } from 'framer-motion';

<AnimatePresence mode="wait">
  <motion.div
    key={currentPage}
    initial={{ opacity: 0, x: 20 }}
    animate={{ opacity: 1, x: 0 }}
    exit={{ opacity: 0, x: -20 }}
    transition={{ duration: 0.2 }}
  >
    {children}
  </motion.div>
</AnimatePresence>
```

### Hover Effects

```jsx
<motion.button
  whileHover={{ scale: 1.02 }}
  whileTap={{ scale: 0.98 }}
>
  Click me
</motion.button>
```

### Entrada Escalonada

```jsx
{items.map((item, i) => (
  <motion.div
    key={item.id}
    initial={{ opacity: 0, y: 20 }}
    animate={{ opacity: 1, y: 0 }}
    transition={{ delay: i * 0.1 }}
  >
    ...
  </motion.div>
))}
```

### Timing Tokens

| Token | Valor | Uso |
|-------|-------|-----|
| `animation.fast` | `150ms` | Hovers, pequeños cambios |
| `animation.normal` | `200ms` | Transiciones estándar |
| `animation.slow` | `300ms` | Modales, overlays |
| `animation.easing` | `ease-out` | Curva de animación |

---

## Accesibilidad

### Focus States

Todos los elementos interactivos tienen estados de focus visibles:

```jsx
className="focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2 focus:ring-offset-slate-900"
```

### Keyboard Navigation

- Todos los botones son accesibles via Tab
- Los shortcuts usan `⌘` (Cmd en Mac, Ctrl en Windows)
- El Command Palette soporta navegación con flechas

### Contrast

Los colores cumplen WCAG AA:
- Texto primario (#F8FAFC) sobre fondo (#0F172A): ratio 16.1:1
- Texto secundario (#94A3B8) sobre fondo (#0F172A): ratio 7.2:1

---

## Ejemplo Completo

```jsx
import { useState } from 'react';
import { motion, AnimatePresence } from 'framer-motion';
import { Card, Badge, Button, Input } from '../design-system/components';

export default function ExamplePage() {
  const [selected, setSelected] = useState(null);

  return (
    <div className="h-full">
      <div className="mb-6">
        <h1 className="text-2xl font-bold text-slate-50 mb-2 flex items-center gap-3">
          <span>✨</span> Example Page
        </h1>
        <p className="text-slate-400">Demostración del design system.</p>
      </div>

      <div className="flex gap-6 h-[calc(100%-100px)]">
        <div className="w-80">
          <Card>
            <Input 
              placeholder="Buscar..." 
              leftIcon={<span>🔍</span>}
            />
            <div className="mt-4 space-y-2">
              <Button className="w-full">Primary</Button>
              <Button variant="secondary" className="w-full">Secondary</Button>
            </div>
          </Card>
        </div>

        <Card className="flex-1">
          <div className="flex items-center gap-2 mb-4">
            <Badge variant="stable">Stable</Badge>
            <Badge variant="beta">Beta</Badge>
            <Badge variant="pro">Pro</Badge>
          </div>
          <p className="text-slate-400">
            Contenido principal aquí.
          </p>
        </Card>
      </div>
    </div>
  );
}
```

---

*Última actualización: 2026-02-05*

# NovaVision Onboarding Design System

## Principios de Diseño

### 1. **Consistencia Total**

- Un solo token para cada decisión visual
- Naming semántico que describe uso, no apariencia
- Jerarquía clara: Base → Semantic → Component tokens

### 2. **Accesibilidad AA/AAA**

- Contraste mínimo 4.5:1 para texto normal
- Contraste 7:1 para texto crítico (títulos, CTAs)
- Focus visible con outline 2px
- Estados hover/active/disabled claramente diferenciables

### 3. **Editabilidad Extrema**

- CERO hex hardcodeados en componentes
- Cambiar color primario = 1 línea en tokens.js
- Preparado para multi-tenant (theme switching)

### 4. **Identidad NovaVision**

- Dark/tech aesthetic con energía premium
- Gradientes sutiles azul→cyan
- Glass morphism en cards
- Sombras profundas con glow sutil

---

## Paleta de Tokens

### Base Tokens - NovaVision Light (Onboarding Mode)

#### Neutrals (scale 0-1000)

```js
neutral: {
  0: '#ffffff',      // Pure white
  50: '#f8fafc',     // Lightest gray (backgrounds)
  100: '#f1f5f9',    // Subtle backgrounds
  200: '#e2e8f0',    // Borders light
  300: '#cbd5e1',    // Borders default
  400: '#94a3b8',    // Muted text
  500: '#64748b',    // Secondary text
  600: '#475569',    // Body text
  700: '#334155',    // Headings
  800: '#1e293b',    // Strong emphasis
  900: '#0f172a',    // Maximum contrast
  1000: '#020617',   // Pure black
}
```

#### Brand Colors

```js
brand: {
  primary: {
    50: '#eff6ff',   // Lightest blue
    100: '#dbeafe',  // Light blue bg
    200: '#bfdbfe',  // Light blue border
    300: '#93c5fd',  // Light blue accent
    400: '#60a5fa',  // Medium blue
    500: '#3b82f6',  // PRIMARY BLUE (main brand)
    600: '#2563eb',  // Deep blue
    700: '#1d4ed8',  // Darker blue
    800: '#1e40af',  // Navy blue
    900: '#1e3a8a',  // Deepest blue
  },
  secondary: {
    50: '#ecfeff',   // Lightest cyan
    100: '#cffafe',  // Light cyan bg
    200: '#a5f3fc',  // Light cyan border
    300: '#67e8f9',  // Light cyan accent
    400: '#22d3ee',  // Medium cyan
    500: '#06b6d4',  // ACCENT CYAN (secondary brand)
    600: '#0891b2',  // Deep cyan
    700: '#0e7490',  // Darker cyan
    800: '#155e75',  // Teal
    900: '#164e63',  // Deepest teal
  },
  gradient: {
    primary: 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)',
    accent: 'linear-gradient(135deg, #0891b2 0%, #0e7490 100%)',
    hero: 'linear-gradient(135deg, #1e40af 0%, #0e7490 100%)',  // Safe con texto blanco
    subtle: 'linear-gradient(180deg, rgba(37, 99, 235, 0.05) 0%, rgba(14, 116, 144, 0.05) 100%)',
  }
}

// NOTA CRÍTICA: secondary[500] (#06b6d4) NO pasa AA con texto blanco (≈2.43:1)
// Usar solo para acentos/bordes/iconos sobre fondos claros/oscuros
// Para fondos con texto blanco: usar secondary[700] (#0e7490) o secondary[800] (#155e75)
```

#### Semantic Colors

```js
semantic: {
  success: {
    light: '#d1fae5',
    DEFAULT: '#10b981',
    dark: '#059669',
    text: '#065f46',
  },
  warning: {
    light: '#fef3c7',
    DEFAULT: '#f59e0b',
    dark: '#d97706',
    text: '#92400e',
  },
  error: {
    light: '#fee2e2',
    DEFAULT: '#ef4444',
    dark: '#dc2626',
    text: '#991b1b',
  },
  info: {
    light: '#dbeafe',
    DEFAULT: '#2563eb',  // Más oscuro para mejor contraste
    dark: '#1d4ed8',
    text: '#1e40af',
  }
}
```

#### Effects

```js
shadow: {
  xs: '0 1px 2px rgba(0, 0, 0, 0.05)',
  sm: '0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.08)',
  md: '0 8px 20px rgba(15, 23, 42, 0.10)',
  lg: '0 14px 34px rgba(15, 23, 42, 0.14)',
  xl: '0 20px 40px rgba(15, 23, 42, 0.18)',
  glowBlue: '0 0 20px rgba(37, 99, 235, 0.30)',
  glowCyan: '0 0 20px rgba(14, 116, 144, 0.28)',  // Ajustado a cyan safe
}

blur: {
  glass: '12px',    // Solo el valor, no el string completo
  subtle: '8px',
}

transition: {
  fast: '120ms ease',
  base: '180ms ease',
  slow: '240ms ease',
}

zIndex: {
  header: 100,
  modal: 1000,
  toast: 1100,
}

sizes: {
  headerHeight: {
    desktop: '64px',
    mobile: '56px',
  },
  hitAreaMin: '44px',  // WCAG minimum touch target
}

radius: {
  sm: '0.375rem',   // 6px
  md: '0.5rem',     // 8px
  lg: '0.75rem',    // 12px
  xl: '1rem',       // 16px
  full: '9999px',
}
```

#### Typography

```js
font: {
  family: {
    sans: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
    display: "'Inter', sans-serif",
    mono: "'Fira Code', 'Courier New', monospace",
  },
  size: {
    xs: '0.75rem',     // 12px
    sm: '0.875rem',    // 14px
    base: '1rem',      // 16px
    lg: '1.125rem',    // 18px
    xl: '1.25rem',     // 20px
    '2xl': '1.5rem',   // 24px
    '3xl': '1.875rem', // 30px
    '4xl': '2.25rem',  // 36px
  },
  weight: {
    normal: 400,
    medium: 500,
    semibold: 600,
    bold: 700,
  },
  lineHeight: {
    tight: 1.25,
    normal: 1.5,
    relaxed: 1.75,
  }
}
```

#### Spacing

```js
space: {
  0: '0',
  1: '4px',
  2: '8px',
  3: '12px',
  4: '16px',
  5: '20px',
  6: '24px',
  8: '32px',
  10: '40px',
  12: '48px',
  16: '64px',
  20: '80px',
  24: '96px',
}
```

---

## Semantic Token Mapping

### Layout

```js
bg: {
  canvas: neutral[50],           // Main background (subtle gray)
  surface: neutral[0],           // Cards, panels (white)
  surfaceHover: neutral[100],    // Hover state
  overlay: 'rgba(15, 23, 42, 0.8)', // Modals backdrop
}

border: {
  subtle: neutral[200],
  default: neutral[300],
  strong: neutral[400],
  brand: brand.primary[300],
}

text: {
  primary: neutral[800],         // Main text
  secondary: neutral[600],       // Body text
  muted: neutral[500],           // Helper text
  disabled: neutral[400],
  inverse: neutral[0],           // On dark bg
  brand: brand.primary[700],     // Mejor contraste que 600
  link: brand.primary[700],      // Mejor contraste en fondos claros
  linkHover: brand.primary[800],
}
```

### Interactive

```js
focus: {
  ring: brand.primary[500],
  ringWidth: '2px',
  ringOffset: '2px',
  ringOffsetColor: neutral[0],
}

interactive: {
  hover: 'rgba(59, 130, 246, 0.08)',
  active: 'rgba(59, 130, 246, 0.12)',
}
```

---

## Component Tokens

### Button

```js
button: {
  // Primary (CTA)
  primary: {
    bg: brand.primary[600],         // Base token OK aquí (es el mapping)
    bgHover: brand.primary[700],
    bgActive: brand.primary[800],
    bgDisabled: neutral[300],
    text: text.inverse,             // Usa semantic token
    textDisabled: neutral[500],
    border: 'transparent',
    shadow: shadow.md,
    shadowHover: shadow.lg,
  },

  // Secondary
  secondary: {
    bg: bg.surface,                 // Usa semantic token
    bgHover: neutral[100],
    bgActive: neutral[200],
    bgDisabled: neutral[100],
    text: text.primary,             // Usa semantic token
    textDisabled: text.disabled,    // Usa semantic token
    border: border.default,         // Usa semantic token
    shadow: shadow.sm,
  },

  // Ghost
  ghost: {
    bg: 'transparent',
    bgHover: interactive.hover,
    bgActive: interactive.active,
    text: text.brand,               // Usa semantic token
    textHover: brand.primary[700],
  },
}
```

### Input

```js
input: {
  bg: bg.surface,                    // Usa semantic token
  bgDisabled: neutral[100],
  bgFocus: bg.surface,               // Usa semantic token
  border: border.default,            // Usa semantic token
  borderHover: border.strong,        // Usa semantic token
  borderFocus: brand.primary[500],
  borderError: semantic.error.DEFAULT,
  text: text.primary,                // Usa semantic token
  textPlaceholder: text.muted,       // Usa semantic token
  label: text.primary,               // Usa semantic token
  helper: text.secondary,            // Usa semantic token
  error: semantic.error.text,
  shadow: shadow.sm,
  shadowFocus: `0 0 0 3px ${brand.primary[100]}`,
}
```

### Card

```js
card: {
  bg: bg.surface,                       // Usa semantic token
  bgHover: neutral[50],
  border: border.subtle,                // Usa semantic token
  shadow: shadow.md,
  shadowHover: shadow.xl,
  // Glass variant
  glass: {
    bg: 'rgba(255, 255, 255, 0.88)',
    backdropBlur: blur.glass,           // Ahora es solo el valor '12px'
    border: 'rgba(255, 255, 255, 0.20)',
  }
}

// Uso correcto del blur:
// backdrop-filter: blur(${({ theme }) => theme.card.glass.backdropBlur});
```

### Progress / Stepper

```js
progress: {
  track: neutral[200],
  fill: brand.gradient.hero,          // Ahora es safe con texto blanco
  fillAlt: brand.primary[500],
  text: text.secondary,               // Usa semantic token
  textActive: brand.primary[600],
  textCompleted: semantic.success.DEFAULT,
  iconCompleted: semantic.success.DEFAULT,
  iconActive: brand.primary[500],
  iconPending: neutral[400],
}
```

### Alert / Badge

```js
alert: {
  info: {
    bg: semantic.info.light,
    border: semantic.info.DEFAULT,
    text: semantic.info.text,
    icon: semantic.info.DEFAULT,
  },
  success: {
    bg: semantic.success.light,
    border: semantic.success.DEFAULT,
    text: semantic.success.text,
    icon: semantic.success.DEFAULT,
  },
  warning: {
    bg: semantic.warning.light,
    border: semantic.warning.DEFAULT,
    text: semantic.warning.text,
    icon: semantic.warning.DEFAULT,
  },
  error: {
    bg: semantic.error.light,
    border: semantic.error.DEFAULT,
    text: semantic.error.text,
    icon: semantic.error.DEFAULT,
  }
}

badge: {
  enterprise: {
    bg: brand.gradient.hero,      // Ahora es safe con texto blanco
    text: text.inverse,           // Usa semantic token
    shadow: shadow.glowBlue,      // Renombrado para claridad
  },
  default: {
    bg: neutral[100],
    text: text.primary,           // Usa semantic token
    border: border.default,       // Usa semantic token
  }
}
```

---

## Header Specifications

### OnboardingHeader Component

```
┌─────────────────────────────────────────────────┐
│ [← Volver] [Logo NovaVision]  [Paso 1 de 3] ●●○ │
└─────────────────────────────────────────────────┘

Layout:
- Height: 64px (desktop), 56px (mobile)
- Sticky top
- Background: neutral[0] with shadow.sm
- Border bottom: 1px solid border.subtle

Sections:
1. Left: Back button (icon + text)
   - Desktop: Icon + "Volver"
   - Mobile: Icon only
   - Color: text.secondary
   - Hover: text.primary + bg interactive.hover

2. Center: Logo + Brand
   - Logo: 32px height
   - Text: "NovaVision" font.lg font.semibold
   - Color: text.primary
   - Optional tagline: text.muted font.sm

3. Right: Progress indicator
   - Text: "Paso X de Y" font.sm text.secondary
   - Dots: 3 circles (8px diameter)
     - Completed: brand.primary[500] filled
     - Active: brand.primary[500] outline
     - Pending: neutral[300] outline
   - Mobile: Hide text, show only dots
```

---

## Responsive Breakpoints

```js
breakpoints: {
  mobile: '0px',
  tablet: '768px',
  desktop: '1024px',
  wide: '1440px',
}
```

---

## Implementación Correcta

### Estructura de Archivos

```
theme/
  ├── tokens.ts        // Base tokens (colores raw, spacing, etc.)
  ├── theme.ts         // Semantic + component mapping
  ├── GlobalStyle.ts   // CSS vars para legacy + reset básico
  └── index.ts         // Re-exports
```

### `theme/tokens.ts` (Base tokens)

```typescript
export const tokens = {
  neutral: {
    0: '#ffffff',
    50: '#f8fafc',
    100: '#f1f5f9',
    200: '#e2e8f0',
    300: '#cbd5e1',
    400: '#94a3b8',
    500: '#64748b',
    600: '#475569',
    700: '#334155',
    800: '#1e293b',
    900: '#0f172a',
    1000: '#020617',
  },
  brand: {
    primary: {
      50: '#eff6ff',
      100: '#dbeafe',
      200: '#bfdbfe',
      300: '#93c5fd',
      400: '#60a5fa',
      500: '#3b82f6',
      600: '#2563eb', // Main brand color (AA safe con blanco)
      700: '#1d4ed8',
      800: '#1e40af',
      900: '#1e3a8a',
    },
    secondary: {
      50: '#ecfeff',
      100: '#cffafe',
      200: '#a5f3fc',
      300: '#67e8f9',
      400: '#22d3ee',
      500: '#06b6d4', // NO usar como bg con texto blanco
      600: '#0891b2',
      700: '#0e7490', // Safe con texto blanco
      800: '#155e75',
      900: '#164e63',
    },
    gradient: {
      primary: 'linear-gradient(135deg, #2563eb 0%, #1d4ed8 100%)',
      accent: 'linear-gradient(135deg, #0891b2 0%, #0e7490 100%)',
      hero: 'linear-gradient(135deg, #1e40af 0%, #0e7490 100%)',
      subtle:
        'linear-gradient(180deg, rgba(37, 99, 235, 0.05) 0%, rgba(14, 116, 144, 0.05) 100%)',
    },
  },
  semantic: {
    success: {
      light: '#d1fae5',
      DEFAULT: '#10b981',
      dark: '#059669',
      text: '#065f46',
    },
    warning: {
      light: '#fef3c7',
      DEFAULT: '#f59e0b',
      dark: '#d97706',
      text: '#92400e',
    },
    error: {
      light: '#fee2e2',
      DEFAULT: '#ef4444',
      dark: '#dc2626',
      text: '#991b1b',
    },
    info: {
      light: '#dbeafe',
      DEFAULT: '#2563eb',
      dark: '#1d4ed8',
      text: '#1e40af',
    },
  },
  shadow: {
    xs: '0 1px 2px rgba(0, 0, 0, 0.05)',
    sm: '0 1px 3px rgba(0, 0, 0, 0.1), 0 1px 2px rgba(0, 0, 0, 0.08)',
    md: '0 8px 20px rgba(15, 23, 42, 0.10)',
    lg: '0 14px 34px rgba(15, 23, 42, 0.14)',
    xl: '0 20px 40px rgba(15, 23, 42, 0.18)',
    glowBlue: '0 0 20px rgba(37, 99, 235, 0.30)',
    glowCyan: '0 0 20px rgba(14, 116, 144, 0.28)',
  },
  blur: { glass: '12px', subtle: '8px' },
  radius: { sm: '6px', md: '8px', lg: '12px', xl: '16px', full: '9999px' },
  space: {
    0: '0',
    1: '4px',
    2: '8px',
    3: '12px',
    4: '16px',
    5: '20px',
    6: '24px',
    8: '32px',
    10: '40px',
    12: '48px',
    16: '64px',
    20: '80px',
  },
  font: {
    family: {
      sans: "'Inter', -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif",
      mono: "'Fira Code', ui-monospace, monospace",
    },
    size: {
      xs: '12px',
      sm: '14px',
      base: '16px',
      lg: '18px',
      xl: '20px',
      '2xl': '24px',
      '3xl': '30px',
      '4xl': '36px',
    },
    weight: { normal: 400, medium: 500, semibold: 600, bold: 700 },
    lineHeight: { tight: 1.25, normal: 1.5, relaxed: 1.75 },
  },
  breakpoints: { tablet: '768px', desktop: '1024px', wide: '1440px' },
  transition: { fast: '120ms ease', base: '180ms ease', slow: '240ms ease' },
  zIndex: { header: 100, modal: 1000, toast: 1100 },
} as const;
```

### `theme/theme.ts` (Semantic + Component mapping)

```typescript
import { tokens } from './tokens';

export const createTheme = () => {
  const t = tokens;

  // Semantic Layer
  const bg = {
    canvas: t.neutral[50],
    surface: t.neutral[0],
    surfaceHover: t.neutral[100],
    overlay: 'rgba(15, 23, 42, 0.80)',
  };

  const text = {
    primary: t.neutral[800],
    secondary: t.neutral[600],
    muted: t.neutral[500],
    disabled: t.neutral[400],
    inverse: t.neutral[0],
    link: t.brand.primary[700],
    linkHover: t.brand.primary[800],
    brand: t.brand.primary[700],
  };

  const border = {
    subtle: t.neutral[200],
    default: t.neutral[300],
    strong: t.neutral[400],
    brand: t.brand.primary[300],
  };

  const focus = {
    ring: t.brand.primary[500],
    ringWidth: '2px',
    ringOffset: '2px',
    ringOffsetColor: t.neutral[0],
  };

  // Component Layer (depende de semantic, no de base)
  const components = {
    button: {
      primary: {
        bg: t.brand.primary[600],
        bgHover: t.brand.primary[700],
        bgActive: t.brand.primary[800],
        bgDisabled: t.neutral[300],
        text: text.inverse,
        textDisabled: t.neutral[500],
        shadow: t.shadow.md,
      },
      secondary: {
        bg: bg.surface,
        bgHover: t.neutral[100],
        bgActive: t.neutral[200],
        text: text.primary,
        textDisabled: text.disabled,
        border: border.default,
        shadow: t.shadow.sm,
      },
      ghost: {
        bg: 'transparent',
        bgHover: 'rgba(37, 99, 235, 0.08)',
        bgActive: 'rgba(37, 99, 235, 0.12)',
        text: text.brand,
      },
    },
    input: {
      bg: bg.surface,
      bgDisabled: t.neutral[100],
      border: border.default,
      borderHover: border.strong,
      borderFocus: t.brand.primary[500],
      borderError: t.semantic.error.DEFAULT,
      text: text.primary,
      placeholder: text.muted,
      helper: text.secondary,
      error: t.semantic.error.text,
      shadow: t.shadow.sm,
      shadowFocus: `0 0 0 3px ${t.brand.primary[100]}`,
    },
    card: {
      bg: bg.surface,
      border: border.subtle,
      shadow: t.shadow.md,
      glass: {
        bg: 'rgba(255, 255, 255, 0.88)',
        border: 'rgba(255, 255, 255, 0.20)',
        backdropBlur: t.blur.glass,
      },
    },
    progress: {
      track: t.neutral[200],
      fill: t.brand.gradient.hero,
      text: text.secondary,
      active: t.brand.primary[600],
      completed: t.semantic.success.DEFAULT,
    },
    header: {
      bg: bg.surface,
      border: border.subtle,
      shadow: t.shadow.sm,
      heightDesktop: '64px',
      heightMobile: '56px',
    },
  };

  return {
    tokens: t,
    bg,
    text,
    border,
    focus,
    components,
    transition: t.transition,
    radius: t.radius,
    space: t.space,
    font: t.font,
    breakpoints: t.breakpoints,
    zIndex: t.zIndex,
  };
};

export type AppTheme = ReturnType<typeof createTheme>;
```

### `theme/GlobalStyle.ts` (CSS vars para legacy)

```typescript
import { createGlobalStyle } from 'styled-components';

export const GlobalStyle = createGlobalStyle`
  :root {
    /* Semantic tokens como CSS vars para archivos .css legacy */
    --nv-bg-canvas: ${({ theme }) => theme.bg.canvas};
    --nv-bg-surface: ${({ theme }) => theme.bg.surface};
    --nv-text-primary: ${({ theme }) => theme.text.primary};
    --nv-text-secondary: ${({ theme }) => theme.text.secondary};
    --nv-text-muted: ${({ theme }) => theme.text.muted};
    --nv-border-subtle: ${({ theme }) => theme.border.subtle};
    --nv-border-default: ${({ theme }) => theme.border.default};
    --nv-brand-primary: ${({ theme }) => theme.tokens.brand.primary[600]};
    --nv-brand-gradient-hero: ${({ theme }) => theme.tokens.brand.gradient.hero};
    --nv-focus-ring: ${({ theme }) => theme.focus.ring};
    --nv-shadow-md: ${({ theme }) => theme.tokens.shadow.md};
  }

  * {
    box-sizing: border-box;
    margin: 0;
    padding: 0;
  }

  body {
    background: ${({ theme }) => theme.bg.canvas};
    color: ${({ theme }) => theme.text.primary};
    font-family: ${({ theme }) => theme.font.family.sans};
    font-size: ${({ theme }) => theme.font.size.base};
    line-height: ${({ theme }) => theme.font.lineHeight.normal};
    -webkit-font-smoothing: antialiased;
    -moz-osx-font-smoothing: grayscale;
  }

  /* Focus visible global (fallback) */
  *:focus-visible {
    outline: ${({ theme }) => `${theme.focus.ringWidth} solid ${theme.focus.ring}`};
    outline-offset: ${({ theme }) => theme.focus.ringOffset};
  }

  /* Eliminar outline default */
  *:focus:not(:focus-visible) {
    outline: none;
  }
`;
```

### Uso en Componentes

```typescript
import styled from 'styled-components';

// ✅ CORRECTO: Usa semantic/component tokens
const Button = styled.button`
  background: ${({ theme }) => theme.components.button.primary.bg};
  color: ${({ theme }) => theme.components.button.primary.text};
  padding: ${({ theme }) => `${theme.space[3]} ${theme.space[6]}`};
  border-radius: ${({ theme }) => theme.radius.md};
  font-weight: ${({ theme }) => theme.font.weight.semibold};
  transition: all ${({ theme }) => theme.transition.base};
  box-shadow: ${({ theme }) => theme.components.button.primary.shadow};

  &:hover {
    background: ${({ theme }) => theme.components.button.primary.bgHover};
    box-shadow: ${({ theme }) => theme.tokens.shadow.lg};
  }

  &:focus-visible {
    outline: ${({ theme }) =>
      `${theme.focus.ringWidth} solid ${theme.focus.ring}`};
    outline-offset: ${({ theme }) => theme.focus.ringOffset};
  }
`;

// ❌ INCORRECTO: No usar hex hardcodeado
const BadButton = styled.button`
  background: #3b82f6; /* ❌ */
  color: #ffffff; /* ❌ */
  padding: 12px 24px; /* ❌ usar theme.space */
`;

// ❌ INCORRECTO: No usar base tokens directamente en componentes
const AlsoBadButton = styled.button`
  background: ${({ theme }) => theme.tokens.brand.primary[600]}; /* ❌ */
  /* Debería usar: theme.components.button.primary.bg */
`;
```

---

## Guard Rails para Evitar Regresiones

### 1. Script de detección de hex hardcodeados

```bash
#!/bin/bash
# scripts/check-hardcoded-colors.sh

echo "🔍 Buscando colores hardcodeados..."
grep -rn "#[0-9a-fA-F]\{3,8\}" apps/admin/src \
  --include="*.jsx" \
  --include="*.tsx" \
  --include="*.js" \
  --include="*.ts" \
  --exclude-dir=node_modules \
  --exclude-dir=dist

if [ $? -eq 0 ]; then
  echo "❌ Se encontraron colores hardcodeados"
  exit 1
else
  echo "✅ No se encontraron colores hardcodeados"
  exit 0
fi
```

### 2. Pre-commit hook

```json
// package.json
{
  "husky": {
    "hooks": {
      "pre-commit": "bash scripts/check-hardcoded-colors.sh"
    }
  }
}
```

### 3. CI Check

```yaml
# .github/workflows/theme-check.yml
name: Theme Consistency Check
on: [pull_request]
jobs:
  check-hardcoded:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - name: Check for hardcoded colors
        run: bash scripts/check-hardcoded-colors.sh
```

---

## Usage Rules

### DO ✅

- Use **component tokens** primero: `theme.components.button.primary.bg`
- Si no existe component token, usa **semantic**: `theme.text.primary`
- Base tokens **solo** en `theme.ts` al crear el mapping
- Usa `backdrop-filter: blur(${theme.blur.glass})` (no `blur(12px)` directo)
- Mantén ritmo de spacing (múltiplos de 4px)
- Prueba todos los estados: default, hover, active, focus, disabled
- Asegura contraste AA mínimo (4.5:1 texto normal, 3:1 texto grande)
- Documenta por qué necesitás un nuevo token si lo agregás

### DON'T ❌

- **NUNCA** hardcodear hex en componentes: `#3b82f6` ❌
- **NUNCA** usar base tokens en componentes: `theme.tokens.neutral[300]` ❌
- No usar `secondary[500]` (#06b6d4) como bg con texto blanco (no pasa AA)
- No saltear estados de focus (accessibility crítico)
- No usar valores arbitrarios de spacing: `padding: 13px` ❌
- No crear colores nuevos sin agregarlos al sistema de tokens
- No usar `blur.glass` como string completo, solo el valor

---

## Accessibility Checklist

### Contraste

- [ ] Texto normal: mínimo 4.5:1 (AA) o 7:1 (AAA)
- [ ] Texto grande (18px+ o 14px+ bold): mínimo 3:1 (AA)
- [ ] Elementos gráficos e UI components: mínimo 3:1
- [ ] **Validado**: `secondary[500]` (#06b6d4) NO se usa como bg con texto blanco
- [ ] Gradientes verificados con herramientas (WebAIM, Coolors)

### Focus

- [ ] Todos los elementos interactivos tienen focus visible (2px ring)
- [ ] Focus ring tiene contraste 3:1 con el fondo
- [ ] Focus offset de 2px para claridad
- [ ] Focus no se remueve con `outline: none` sin alternativa

### Estados

- [ ] Disabled visualmente distinto (no solo por color)
- [ ] Hover/active tienen feedback claro
- [ ] Loading states con indicador animado + aria-busy

### Semántica

- [ ] Mensajes de error asociados con inputs (aria-describedby)
- [ ] Progress indicators tienen aria-label/aria-valuenow
- [ ] Botones tienen labels descriptivos (no "Click aquí")
- [ ] Imágenes decorativas tienen alt="" (no omitir)

### Interacción

- [ ] Hit area mínimo 44x44px (WCAG 2.1)
- [ ] Funciona con teclado: Tab, Enter, Escape, flechas
- [ ] Back button accesible y con label claro
- [ ] Modals trappean focus y tienen close con Escape

### Información

- [ ] Color NO es el único diferenciador (usar iconos/texto)
- [ ] Instrucciones no dependen solo de forma/ubicación
- [ ] Timeouts tienen opción de extender (si aplica)

---

## Future Enhancements (Multi-tenant)

### Theming por Cliente

Este sistema está diseñado para **zero refactoring** al cambiar temas.

#### 1. Estructura para multi-tenant

```
theme/
  ├── tokens/
  │   ├── base.ts              // Tokens comunes (spacing, shadows, etc.)
  │   └── clients/
  │       ├── novavision.ts    // Paleta NovaVision (default)
  │       ├── client-a.ts      // Paleta Cliente A
  │       └── client-b.ts      // Paleta Cliente B
  ├── theme.ts                 // createTheme() (igual, no cambia)
  ├── GlobalStyle.ts
  └── ThemeProvider.tsx        // Selecciona tokens según client_id
```

#### 2. Implementación

```typescript
// tokens/clients/client-a.ts
import { baseTokens } from '../base';

export const clientATokens = {
  ...baseTokens,
  brand: {
    primary: {
      50: '#faf5ff',
      100: '#f3e8ff',
      200: '#e9d5ff',
      300: '#d8b4fe',
      400: '#c084fc',
      500: '#a855f7', // Purple principal
      600: '#9333ea',
      700: '#7e22ce',
      800: '#6b21a8',
      900: '#581c87',
    },
    secondary: {
      // ... Pink accent
      500: '#ec4899',
      700: '#be185d', // Safe con blanco
    },
    gradient: {
      hero: 'linear-gradient(135deg, #7e22ce 0%, #be185d 100%)',
      // Validar contraste!
    },
  },
};
```

#### 3. ThemeProvider dinámico

```typescript
// ThemeProvider.tsx
import { ThemeProvider as StyledThemeProvider } from 'styled-components';
import { createTheme } from './theme';
import { novavisionTokens } from './tokens/clients/novavision';
import { clientATokens } from './tokens/clients/client-a';

const clientTokensMap = {
  novavision: novavisionTokens,
  'client-a': clientATokens,
};

export function AppThemeProvider({ clientId, children }) {
  const tokens = clientTokensMap[clientId] || novavisionTokens;
  const theme = createTheme(tokens);  // createTheme recibe tokens como param

  return (
    <StyledThemeProvider theme={theme}>
      {children}
    </StyledThemeProvider>
  );
}
```

#### 4. Componentes NO cambian

```typescript
// Button.tsx (igual para todos los clientes)
const Button = styled.button`
  background: ${({ theme }) => theme.components.button.primary.bg};
  /* El color cambia automáticamente según el tema inyectado */
`;
```

### Consideraciones Multi-tenant

- **Validar contraste** en cada paleta de cliente (usar herramienta automatizada)
- **Documentar** excepciones por cliente si las hay
- **Testing**: Storybook con selector de tema para previsualizar
- **Performance**: Lazy load de tokens por cliente (solo cargar el necesario)
- **Branding**: Permitir override de logo, fonts y radius por cliente

### Tech Vibe para Onboarding (opcional)

Para darle "identidad NovaVision" sin hacerlo oscuro:

```typescript
// En theme.ts
const bg = {
  canvas: `
    linear-gradient(to bottom, 
      ${t.neutral[50]} 0%, 
      ${t.neutral[100]} 100%
    ),
    ${t.brand.gradient.subtle}
  `, // Background con gradiente sutil
};

const components = {
  header: {
    // ...
    borderTop: `2px solid transparent`,
    backgroundImage: t.brand.gradient.hero, // Línea superior con gradiente
    backgroundClip: 'border-box',
  },
};
```

Esto da tech aesthetic sin comprometer legibilidad.

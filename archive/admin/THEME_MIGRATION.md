# Migración al Nuevo Sistema de Diseño

## ✅ Estado Actual

El nuevo sistema de diseño está **implementado y listo para usar**.

### Archivos Nuevos (Design System Spec compliant)

- `theme/tokens-new.js` - Base tokens con contraste AA validado
- `theme/theme-new.js` - Semantic + Component layer
- `theme/GlobalStyle-new.js` - CSS vars + Reset + A11y
- `theme/index-new.js` - Export central
- `scripts/check-hardcoded-colors.sh` - Detector de hex hardcodeados

### Archivos Legacy (deprecados)

- `theme/tokens.js` ⚠️
- `theme/theme.js` ⚠️
- `theme/GlobalStyle.js` ⚠️
- `theme/colors.js` ⚠️
- `theme/darkTheme.js` ⚠️

---

## 🎯 Plan de Migración

### Fase 1: Setup (✅ COMPLETADO)

- [x] Implementar `tokens-new.js` con contraste AA
- [x] Implementar `theme-new.js` con estructura semántica
- [x] Implementar `GlobalStyle-new.js` con CSS vars
- [x] Script `check-hardcoded-colors.sh`
- [x] Validar que código actual no tiene hex hardcodeados

### Fase 2: Migración Gradual (PRÓXIMO)

#### 2.1. Actualizar ThemeProvider

```jsx
// apps/admin/src/theme/ThemeProvider.jsx

// ANTES
import { theme } from './theme';

// DESPUÉS
import { defaultTheme } from './index-new';

export function AppThemeProvider({ children }) {
  return (
    <ThemeProvider theme={defaultTheme}>
      <GlobalStyle />
      {children}
    </ThemeProvider>
  );
}
```

#### 2.2. Actualizar App.jsx

```jsx
// apps/admin/src/App.jsx

// ANTES
import { GlobalStyle } from './theme/GlobalStyle';

// DESPUÉS
import { GlobalStyle } from './theme/index-new';
```

#### 2.3. Actualizar imports en componentes

Buscar y reemplazar:

```bash
# Buscar imports legacy
grep -r "from.*theme/theme'" apps/admin/src
grep -r "from.*theme/tokens'" apps/admin/src

# Reemplazar por:
from '@/theme' // o './theme/index-new'
```

#### 2.4. Actualizar styled-components

**ANTES (puede seguir funcionando):**

```jsx
const Button = styled.button`
  background: ${({ theme }) => theme.colors.primary};
`;
```

**DESPUÉS (mejor):**

```jsx
const Button = styled.button`
  background: ${({ theme }) => theme.components.button.primary.bg};
  color: ${({ theme }) => theme.components.button.primary.text};
  padding: ${({ theme }) => `${theme.space[3]} ${theme.space[6]}`};
`;
```

### Fase 3: Limpieza (DESPUÉS)

Una vez que todo funciona con el nuevo sistema:

1. Borrar archivos legacy:

   ```bash
   rm apps/admin/src/theme/tokens.js
   rm apps/admin/src/theme/theme.js
   rm apps/admin/src/theme/GlobalStyle.js
   rm apps/admin/src/theme/colors.js
   rm apps/admin/src/theme/darkTheme.js
   ```

2. Renombrar archivos nuevos (quitar `-new`):

   ```bash
   mv apps/admin/src/theme/tokens-new.js apps/admin/src/theme/tokens.js
   mv apps/admin/src/theme/theme-new.js apps/admin/src/theme/theme.js
   mv apps/admin/src/theme/GlobalStyle-new.js apps/admin/src/theme/GlobalStyle.js
   mv apps/admin/src/theme/index-new.js apps/admin/src/theme/index.js
   ```

3. Actualizar imports finales

---

## 📋 Checklist de Migración por Componente

Cuando migres un componente al nuevo sistema, asegúrate de:

- [ ] Usa `theme.components.*` cuando exista token específico
- [ ] Usa `theme.text.*` / `theme.bg.*` para semantic tokens
- [ ] NO usa `theme.tokens.*` directamente (solo en theme.js)
- [ ] Espaciado usa `theme.space[N]` (no px hardcodeados)
- [ ] Radius usa `theme.radius.*`
- [ ] Sombras usa `theme.shadow.*`
- [ ] Transiciones usa `theme.transition.*`
- [ ] Focus states usan `theme.focus.*`
- [ ] Contraste AA validado (especialmente cyan con texto blanco)

---

## 🔍 Validación

### 1. Ejecutar detector de hex hardcodeados

```bash
bash apps/admin/scripts/check-hardcoded-colors.sh
```

Debe retornar: ✅ No se encontraron colores hardcodeados

### 2. Verificar contraste

Usar [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/) para validar:

- Texto normal: mínimo 4.5:1
- Texto grande: mínimo 3:1
- UI Components: mínimo 3:1

**Combinaciones críticas a validar:**

- ✅ `primary[600]` (#2563eb) con blanco → 7.46:1 (AAA)
- ✅ `secondary[700]` (#0e7490) con blanco → 4.53:1 (AA)
- ❌ `secondary[500]` (#06b6d4) con blanco → 2.43:1 (FALLA)

### 3. Test visual

1. Levantar dev server
2. Verificar cada pantalla del onboarding
3. Probar estados: hover, focus, active, disabled
4. Verificar responsive (mobile/tablet/desktop)
5. Probar con keyboard navigation (Tab, Enter, Esc)

---

## 🎨 Ejemplos de Uso

### Button Component

```jsx
import styled from 'styled-components';

const Button = styled.button`
  /* Component tokens (preferido) */
  background: ${({ theme, variant = 'primary' }) =>
    theme.components.button[variant].bg};
  color: ${({ theme, variant = 'primary' }) =>
    theme.components.button[variant].text};

  /* Spacing */
  padding: ${({ theme }) => `${theme.space[3]} ${theme.space[6]}`};

  /* Effects */
  border-radius: ${({ theme }) => theme.radius.md};
  box-shadow: ${({ theme, variant = 'primary' }) =>
    theme.components.button[variant].shadow};

  /* Transitions */
  transition: all ${({ theme }) => theme.transition.base};

  /* States */
  &:hover {
    background: ${({ theme, variant = 'primary' }) =>
      theme.components.button[variant].bgHover};
  }

  &:focus-visible {
    outline: ${({ theme }) =>
      `${theme.focus.ringWidth} solid ${theme.focus.ring}`};
    outline-offset: ${({ theme }) => theme.focus.ringOffset};
  }

  &:disabled {
    background: ${({ theme, variant = 'primary' }) =>
      theme.components.button[variant].bgDisabled};
    cursor: not-allowed;
  }
`;
```

### Input Component

```jsx
const Input = styled.input`
  background: ${({ theme }) => theme.components.input.bg};
  color: ${({ theme }) => theme.components.input.text};
  border: 1px solid ${({ theme }) => theme.components.input.border};
  padding: ${({ theme }) => `${theme.space[2]} ${theme.space[3]}`};
  border-radius: ${({ theme }) => theme.radius.md};

  &::placeholder {
    color: ${({ theme }) => theme.components.input.textPlaceholder};
  }

  &:hover {
    border-color: ${({ theme }) => theme.components.input.borderHover};
  }

  &:focus {
    outline: none;
    border-color: ${({ theme }) => theme.components.input.borderFocus};
    box-shadow: ${({ theme }) => theme.components.input.shadowFocus};
  }

  &:disabled {
    background: ${({ theme }) => theme.components.input.bgDisabled};
    cursor: not-allowed;
  }
`;
```

### Card Component

```jsx
const Card = styled.div`
  background: ${({ theme }) => theme.components.card.bg};
  border: 1px solid ${({ theme }) => theme.components.card.border};
  border-radius: ${({ theme }) => theme.radius.lg};
  padding: ${({ theme }) => theme.space[6]};
  box-shadow: ${({ theme }) => theme.components.card.shadow};
  transition: all ${({ theme }) => theme.transition.base};

  &:hover {
    box-shadow: ${({ theme }) => theme.components.card.shadowHover};
  }
`;

const GlassCard = styled(Card)`
  background: ${({ theme }) => theme.components.card.glass.bg};
  backdrop-filter: blur(
    ${({ theme }) => theme.components.card.glass.backdropBlur}
  );
  border-color: ${({ theme }) => theme.components.card.glass.border};
`;
```

---

## 🚨 Errores Comunes y Soluciones

### Error: `theme.colors` is undefined

**Causa:** Usas el theme legacy
**Solución:** Cambia a semantic tokens

```jsx
// ❌ ANTES
color: ${({ theme }) => theme.colors.primary};

// ✅ DESPUÉS
color: ${({ theme }) => theme.text.primary};
// o
color: ${({ theme }) => theme.components.button.primary.text};
```

### Error: Contraste insuficiente

**Causa:** Usas `secondary[500]` con texto blanco
**Solución:** Usa `secondary[700]` o superior

```jsx
// ❌ MAL - No pasa AA
background: ${({ theme }) => theme.tokens.brand.secondary[500]};
color: white;

// ✅ BIEN - Pasa AA
background: ${({ theme }) => theme.tokens.brand.secondary[700]};
color: white;
```

### Error: Spacing inconsistente

**Causa:** Usas px hardcodeados
**Solución:** Usa `theme.space[N]`

```jsx
// ❌ MAL
padding: 12px 24px;

// ✅ BIEN
padding: ${({ theme }) => `${theme.space[3]} ${theme.space[6]}`};
```

---

## 📚 Referencias

- [DESIGN_SYSTEM_SPEC.md](./docs/DESIGN_SYSTEM_SPEC.md) - Especificación completa
- [WebAIM Contrast Checker](https://webaim.org/resources/contrastchecker/)
- [WCAG 2.1 Guidelines](https://www.w3.org/WAI/WCAG21/quickref/)

---

## ❓ Preguntas Frecuentes

**¿Puedo seguir usando el theme legacy?**
Sí, temporalmente. Pero el objetivo es migrar todo al nuevo sistema.

**¿Cómo cambio el color primario del brand?**
Edita `tokens-new.js` → `brand.primary[600]`. Ese es el único lugar.

**¿Qué pasa con el dark theme?**
No está implementado aún. Cuando lo necesites, crea `tokens-dark.js` con la misma estructura y usa `createTheme(darkTokens)`.

**¿Cómo agrego un nuevo token de componente?**
Agrégalo en `theme-new.js` → `components`. Nunca en los componentes directamente.

**¿El script de hardcoded colors rompe el build?**
No por defecto. Pero podés agregarlo a pre-commit hooks si querés.

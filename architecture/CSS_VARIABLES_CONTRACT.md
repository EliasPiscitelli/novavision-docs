# Contrato de CSS Variables NovaVision

> **Versión:** 1.0.0  
> **Fecha:** 2026-02-03  
> **Aplica a:** Admin (novavision), Web (templatetwo)

---

## 🎯 Objetivo

Definir un contrato de naming de CSS variables que todos los repos deben seguir para garantizar:
- Consistencia visual entre Admin y Storefronts
- Facilidad de theming por tenant
- Mantenibilidad del código

---

## 📋 Variables Obligatorias

Estas variables **DEBEN** existir en el `:root` de cualquier app NovaVision.

```css
:root {
  /* ===== COLORES BASE ===== */
  --nv-primary: #2563EB;        /* Color principal de marca */
  --nv-primary-fg: #FFFFFF;     /* Texto sobre primary */
  --nv-secondary: #1E293B;      /* Color secundario */
  --nv-secondary-fg: #F8FAFC;   /* Texto sobre secondary */
  --nv-accent: #F59E0B;         /* Color de acento/CTA */

  /* ===== FONDOS ===== */
  --nv-bg: #FFFFFF;             /* Fondo principal de la app */
  --nv-surface: #F8FAFC;        /* Fondo de cards, modales, dropdowns */

  /* ===== TEXTO ===== */
  --nv-text: #0F172A;           /* Texto principal */
  --nv-muted: #64748B;          /* Texto secundario, placeholders */

  /* ===== BORDES ===== */
  --nv-border: #E2E8F0;         /* Bordes de elementos */
}
```

---

## 📋 Variables Opcionales (Derivadas)

Estas variables son opcionales pero recomendadas para casos de uso específicos.

```css
:root {
  /* ===== ESTADOS ===== */
  --nv-hover: var(--nv-primary);      /* Estado hover genérico */
  --nv-primary-hover: #1D4ED8;        /* Hover específico de primary */
  --nv-accent-fg: #FFFFFF;            /* Texto sobre accent */

  /* ===== ALIASES ===== */
  --nv-card-bg: var(--nv-surface);    /* Alias para fondo de cards */
  --nv-text-muted: var(--nv-muted);   /* Alias de muted */

  /* ===== SEMÁNTICOS ===== */
  --nv-success: #10B981;
  --nv-warning: #F59E0B;
  --nv-error: #EF4444;
  --nv-info: #3B82F6;
}
```

---

## 🚫 Variables Deprecadas

**NO USAR** estas variables. Migrar a las equivalentes `--nv-*`.

| Deprecada | Reemplazo |
|-----------|-----------|
| `--color-primary` | `--nv-primary` |
| `--color-bg-surface` | `--nv-surface` |
| `--color-text` | `--nv-text` |
| `--primary-color` | `--nv-primary` |
| `--background-color` | `--nv-bg` |

---

## 🔄 Cómo se aplican los tokens por tenant

### 1. Onboarding guarda tokens en DB

```json
{
  "theme_tokens": {
    "--nv-primary": "#8B5CF6",
    "--nv-bg": "#0F172A",
    "--nv-text": "#F8FAFC"
  }
}
```

### 2. Storefront carga tokens y los aplica al `:root`

```javascript
// apps/web/src/theme/ThemeProvider.jsx
function applyTokens(tokens) {
  const root = document.documentElement;
  Object.entries(tokens).forEach(([key, value]) => {
    root.style.setProperty(key, value);
  });
}
```

### 3. Componentes usan `var(--nv-*)`

```jsx
const Button = styled.button`
  background-color: var(--nv-primary);
  color: var(--nv-primary-fg);
  
  &:hover {
    background-color: var(--nv-primary-hover, var(--nv-primary));
  }
`;
```

---

## 📁 Ubicación de tokens por repo

| Repo | Archivo | Descripción |
|------|---------|-------------|
| **Web** | `src/theme/tokens.js` | Paletas predefinidas |
| **Web** | `src/theme/ThemeProvider.jsx` | Aplicación de tokens |
| **Admin** | `src/theme/colors.js` | Tema de Admin (legacy) |
| **Admin** | `src/theme/GlobalStyle.js` | CSS vars globales |
| **Admin** | `src/services/builder/paletteConstants.ts` | Generación de paletas |

---

## ✅ Checklist de Migración

### Admin (novavision)

- [ ] Agregar CSS vars `--nv-*` en `GlobalStyle.js`
- [ ] Mapear `lightTheme.bgPrimary` → `var(--nv-bg)` en componentes
- [ ] Eliminar referencias a `--color-primary`
- [ ] Actualizar `PaletteManager.jsx` para usar solo `--nv-*`

### Web (templatetwo)

- [x] CSS vars `--nv-*` implementadas en `tokens.js`
- [x] `ThemeProvider.jsx` aplica tokens al `:root`
- [ ] Limpiar variables legacy (`--color-*`)
- [ ] Verificar que todos los templates usen `var(--nv-*)`

---

## 🧪 Testing de Tokens

### Verificar que tokens se aplican correctamente

```javascript
// En DevTools Console
const styles = getComputedStyle(document.documentElement);
console.log('--nv-primary:', styles.getPropertyValue('--nv-primary'));
console.log('--nv-bg:', styles.getPropertyValue('--nv-bg'));
```

### Script de auditoría

```bash
# Buscar variables no estándar en Web
grep -r "var(--color-" apps/web/src/ --include="*.jsx" --include="*.js"

# Buscar variables no estándar en Admin
grep -r "var(--color-" apps/admin/src/ --include="*.jsx" --include="*.js"
```

---

## 📚 Referencia: Paletas Predefinidas

Ver [apps/web/src/theme/tokens.js](../../apps/web/src/theme/tokens.js) para paletas disponibles:

- `starter_default` - Azul clásico
- `starter_dark` - Modo oscuro con violeta
- `starter_elegant` - Dorado lujoso

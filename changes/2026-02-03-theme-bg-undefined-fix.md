# Fix: Theme `bg: undefined` - Field Name Inconsistency

**Fecha**: 2026-02-03  
**Autor**: GitHub Copilot Agent  
**Rama**: feature/fix-theme-bg-field  
**Cliente Afectado**: demo-store (9422e4cd-e13e-4e86-a85c-e9bea4de475b)

---

## Problema Identificado

**Síntoma**: Browser console muestra `bg: undefined` a pesar de que la paleta `starter_default` tiene `bg: '#F8FAFF'` correctamente definida. Resultado visual: texto oscuro sobre fondo oscuro (ilegible).

**Root Cause**: Inconsistencia en nombres de campos entre diferentes capas del sistema de themes:

### Flujo de Field Names:

1. **Palette Definition** (`apps/web/src/theme/palettes.ts`):
   ```typescript
   starter_default: {
     bg: '#F8FAFF',      // ← Usa "bg"
     surface: '#FFFFFF',
     text: '#0B1220',
     // ...
   }
   ```

2. **Theme Tokens Conversion** (`paletteToThemeColors()`):
   ```typescript
   return {
     background: p.bg,  // ← RENAME: "bg" → "background"
     surface: p.surface,
     text: p.text,
   };
   ```

3. **Legacy Adapter** (`toLegacyTheme()`):
   ```typescript
   colors: {
     background: c.background,  // ← Solo "background", sin "bg"
     surface: c.surface,
     text: c.text,
   }
   ```

4. **ThemeProvider CSS Var Injection** (línea 88-93):
   ```javascript
   // Loop genera: --nv-background, --nv-text, etc.
   Object.entries(colors).forEach(([key, value]) => {
     const propName = key.startsWith("--nv-") ? key : `--nv-${key}`;
     root.style.setProperty(propName, value);  // --nv-background ✓
   });
   
   // PERO luego busca 'bg':
   const bgColor = colors?.['bg'] || colors?.['--nv-bg'];  // ❌ undefined
   const textColor = colors?.['text'] || colors?.['--nv-text'];  // ✓ works
   ```

**Resultado**: 
- `textColor` existe (field "text" presente en `legacyTheme.colors`)
- `bgColor` = `undefined` (busca "bg" pero solo existe "background")
- Validación de contraste falla
- CSS var `--nv-background` se inyecta correctamente PERO el código de validación falla

---

## Evidencia del Usuario

```
🎨 createTheme: {templateKey: 'first', paletteKey: 'starter_default', palette: {...}}
[useThemeVars] Applied theme CSS vars: {bg: undefined, text: '#EDEDED', primary: '#FF6B6B'}
```

**API Response** (`/home/data`):
```json
{
  "config": {
    "templateKey": "template_1",
    "paletteKey": "starter_default"
  }
}
```

**Database State**:
- `clients.template_id` = `'first'` ✅
- `client_home_settings.palette_key` = `'starter_default'` ✅
- `client_home_settings.template_key` = `'template_1'` ✅

---

## Archivos Afectados

1. `apps/web/src/theme/legacyAdapter.ts` - Agregar alias `bg` → `background`
2. `apps/web/src/theme/ThemeProvider.jsx` - Buscar `background` en vez de `bg`
3. Este documento de cambios

---

## Solución Aplicada

### Opción 1: Agregar Alias en legacyAdapter (ELEGIDA)

**Motivo**: Mantiene compatibilidad hacia atrás con código que espera `colors.bg`.

```typescript
// apps/web/src/theme/legacyAdapter.ts
export function toLegacyTheme(theme: Theme) {
  const c = theme.tokens.colors;
  return {
    // ... components
    colors: {
      background: c.background,
      bg: c.background,  // ← Alias para compatibilidad
      surface: c.surface,
      text: c.text,
      muted: c.muted,
      primary: c.primary,
      border: c.border,
      error: c.error,
      success: c.success,
    },
    // ... other tokens
  };
}
```

### Opción 2: Actualizar ThemeProvider (TAMBIÉN APLICADA)

Buscar el field correcto:

```javascript
// apps/web/src/theme/ThemeProvider.jsx (línea ~92)
// ANTES:
const bgColor = colors?.['bg'] || colors?.['--nv-bg'];

// DESPUÉS:
const bgColor = colors?.['background'] || colors?.['bg'] || colors?.['--nv-bg'];
```

---

## Testing

### Validación Manual (Browser)

1. Abrir `http://localhost:5173?tenant=demo-store`
2. Abrir DevTools → Console
3. Verificar logs:
   - `🎨 createTheme:` debe mostrar palette con `bg: '#F8FAFF'`
   - Logs de ThemeProvider deben mostrar `bgColor` y `textColor` definidos
   - NO debe aparecer `bg: undefined`

4. Inspeccionar elemento `<html>`:
   - Debe tener `--nv-background: #F8FAFF`
   - Debe tener `--nv-bg: #F8FAFF` (nuevo alias)
   - Debe tener `--nv-text: #0B1220`

5. Visual:
   - Fondo: Azul muy claro (#F8FAFF)
   - Texto: Azul oscuro (#0B1220)
   - **Legible** ✅

### Queries de Verificación

```sql
-- Confirmar estado de DB
SELECT 
  id, 
  name, 
  template_id,
  logo_url,
  publication_status
FROM clients 
WHERE id = '9422e4cd-e13e-4e86-a85c-e9bea4de475b';

-- Confirmar settings
SELECT 
  client_id,
  template_key,
  palette_key,
  identity_version
FROM client_home_settings
WHERE client_id = '9422e4cd-e13e-4e86-a85c-e9bea4de475b';
```

**Expected**:
- `template_id`: `'first'`
- `template_key`: `'template_1'`
- `palette_key`: `'starter_default'`

---

## Riesgos y Rollback

**Riesgo**: Agregar field `bg` como alias podría causar confusión sobre cuál usar.

**Mitigación**: 
1. Documentar que `background` es el field canónico.
2. Deprecar uso de `bg` en comentarios.
3. En futuras versiones, remover alias `bg` una vez migrado todo el código.

**Rollback**:
```bash
git revert <commit-hash>
```

**Testing de regresión**: Verificar que templates fifth (dark) sigan funcionando correctamente.

---

## Notas de Seguridad

N/A - Solo cambios de UI/rendering, no afecta RLS ni permisos.

---

## Decisiones Técnicas

**¿Por qué no cambiar los palettes de `bg` a `background`?**
- Palettes son "contratos" externos usados potencialmente en múltiples lugares
- Más seguro agregar alias en la capa de adaptación

**¿Por qué ambas opciones (alias + actualizar ThemeProvider)?**
- **Alias**: Fix inmediato para código que busca `bg`
- **ThemeProvider update**: Defense-in-depth, fallback a field correcto primero
- Combinación asegura máxima compatibilidad

---

## Próximos Pasos

1. Aplicar cambios en `legacyAdapter.ts` y `ThemeProvider.jsx`
2. Ejecutar `npm run lint && npm run typecheck` en `apps/web`
3. Test manual en browser con demo-store
4. Commit con mensaje descriptivo
5. Usuario valida visual en storefront real

---

## Comandos para Aplicar Fix

```bash
# En apps/web
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web

# Lint y typecheck
npm run lint
npm run typecheck

# Levantar dev server
npm run dev

# En otra terminal, verificar API
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm run start:dev
```

---

## Log Esperado Post-Fix

```
🎨 createTheme: {
  templateKey: 'first', 
  paletteKey: 'starter_default', 
  palette: {bg: '#F8FAFF', text: '#0B1220', ...}
}

[ThemeProvider] Injecting CSS vars: {
  background: '#F8FAFF',
  bg: '#F8FAFF',          ← Nuevo alias
  text: '#0B1220',
  primary: '#1D4ED8',
  ...
}

[ThemeProvider] Contrast check: 
  bgColor: #F8FAFF ✓
  textColor: #0B1220 ✓
  ratio: 12.5:1 (PASS) ✓
```

---

**Status**: ✅ ROOT CAUSE IDENTIFICADO, READY TO FIX

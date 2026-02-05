# Integración del Theme System en Admin App (PreviewFrame)

## Contexto

El admin app (OnboardingPreview) tiene su propio sistema de preview que está separado del storefront. Ambos necesitan usar el MISMO resolver de tema para mantener coherencia.

**Ubicación actual**:
- Storefront: `/apps/web/src/` (ya integrada)
- Admin Preview: `/apps/admin/src/components/PreviewFrame.tsx` (por integrar)

## Objetivo

Hacer que PreviewFrame use el mismo `useEffectiveTheme()` resolver que el storefront, para que:
1. Preview muestre exactamente lo que verá el cliente
2. Cambios de template/paleta sean inmediatos en preview
3. No haya divergencia entre storefront y preview

## Arquitectura Propuesta

### Paso 1: Compartir Código del Resolver

El resolver está en `/apps/web/src/theme/resolveEffectiveTheme.ts`. Hay dos opciones:

**Opción A: Monorepo Compartido** (Recomendado para futuro)
```
packages/theme-resolver/
├── src/
│   ├── resolveEffectiveTheme.ts
│   ├── types.ts
│   └── index.ts
├── package.json
└── tsconfig.json
```

Luego ambos apps importarían:
```typescript
import { resolveEffectiveTheme } from '@nv/theme-resolver';
```

**Opción B: Duplicación** (Rápido para ahora)
```
apps/admin/src/services/themeResolver/
├── resolveEffectiveTheme.ts  // Copiar de apps/web/src/theme/
├── types.ts
└── index.ts
```

Ambos apps tendrían su propia copia (sin referencias compartidas).

### Paso 2: Integración en PreviewFrame

Actualmente PreviewFrame es un iframe que renderiza el storefront. Necesita:

```typescript
// apps/admin/src/components/PreviewFrame.tsx

import { useEffectiveTheme } from '../services/themeResolver/useEffectiveTheme';
import { ThemeProvider } from 'styled-components';

interface PreviewFrameProps {
  clientData: {
    config?: {
      templateKey?: string;
      paletteKey?: string;
      themeConfig?: Record<string, any>;
    };
  };
  isDarkMode?: boolean;
  onThemeChange?: (theme: any) => void;
}

export const PreviewFrame: React.FC<PreviewFrameProps> = ({
  clientData,
  isDarkMode = false,
  onThemeChange,
}) => {
  // Usar el MISMO resolver que el storefront
  const theme = useEffectiveTheme({
    templateKey: clientData.config?.templateKey,
    paletteKey: clientData.config?.paletteKey,
    themeConfig: clientData.config?.themeConfig,
    isDarkMode,
    defaults: {
      templateKey: 'fifth',
      paletteKey: 'starter_default',
    },
    debug: true, // En admin siempre mostrar debug logs
  });

  // Notificar cambios al padre
  useEffect(() => {
    onThemeChange?.(theme);
  }, [theme, onThemeChange]);

  return (
    <ThemeProvider theme={theme}>
      {/* Renderizar contenido del preview */}
      {/* ... */}
    </ThemeProvider>
  );
};
```

### Paso 3: Estado Reactivo en Admin UI

El admin UI (formularios, etc.) necesita actualizar el preview cuando cambien valores:

```typescript
// apps/admin/src/pages/ClientOnboardingPage.tsx

const [clientData, setClientData] = useState({
  config: {
    templateKey: 'template_1',
    paletteKey: 'starter_default',
    themeConfig: null,
  },
});
const [isDarkMode, setIsDarkMode] = useState(false);

// Cuando usuario cambia template dropdown:
const handleTemplateChange = (newTemplate: string) => {
  setClientData(prev => ({
    ...prev,
    config: { ...prev.config, templateKey: newTemplate }
  }));
  // Preview se actualiza automáticamente (rerender con nuevo theme)
};

// Cuando usuario cambia palette dropdown:
const handlePaletteChange = (newPalette: string) => {
  setClientData(prev => ({
    ...prev,
    config: { ...prev.config, paletteKey: newPalette }
  }));
};

return (
  <div>
    {/* Formulario de configuración */}
    <TemplateSelector 
      value={clientData.config.templateKey}
      onChange={handleTemplateChange}
    />
    <PaletteSelector
      value={clientData.config.paletteKey}
      onChange={handlePaletteChange}
    />
    
    {/* Preview actualizado en tiempo real */}
    <PreviewFrame
      clientData={clientData}
      isDarkMode={isDarkMode}
      onThemeChange={(theme) => console.log('Theme updated:', theme)}
    />
  </div>
);
```

## Implementación por Fases

### Fase 1: Análisis (PREREQUISITO)

Antes de integrar, necesito:

1. Auditar `apps/admin/src/components/PreviewFrame.tsx`:
   - ¿Cómo renderiza actualmente?
   - ¿Es un iframe o un componente React?
   - ¿Cómo recibe datos de clientData?
   - ¿Dónde está el estado de isDarkMode?

2. Auditar flujo de datos en admin:
   - ¿De dónde viene clientData?
   - ¿Hay formularios de template/palette?
   - ¿Cómo actualmente se actualiza el preview?

3. Verificar compatibilidad:
   - ¿Admin app usa styled-components también?
   - ¿Qué versión de React?
   - ¿TypeScript o JavaScript?

### Fase 2: Compartir Resolver (Elegir Opción)

**Si Opción A (Monorepo)**:
```bash
# Crear package compartido
mkdir packages/theme-resolver
cp apps/web/src/theme/resolveEffectiveTheme.ts packages/theme-resolver/src/
cp apps/web/src/hooks/useEffectiveTheme.ts packages/theme-resolver/src/
```

**Si Opción B (Duplicación)**:
```bash
# Copiar archivos a admin
mkdir apps/admin/src/services/themeResolver
cp apps/web/src/theme/resolveEffectiveTheme.ts apps/admin/src/services/themeResolver/
cp apps/web/src/hooks/useEffectiveTheme.ts apps/admin/src/services/themeResolver/
```

Recomendación: Opción B por ahora (más rápido), refactorizar a Opción A después.

### Fase 3: Integración en PreviewFrame

1. Copiar `resolveEffectiveTheme.ts` y `useEffectiveTheme.ts` a admin
2. Importar en PreviewFrame
3. Reemplazar lógica de theme actual con `useEffectiveTheme()`
4. Asegurarse que PreviewFrame está dentro de `<ThemeProvider>`

### Fase 4: UI Reactiva

Actualizar formularios en admin para:
1. Mostrar dropdown de templates (template_1, template_5, etc.)
2. Mostrar dropdown de paletas (starter_default, dark_default, etc.)
3. Llamar callbacks que actualicen clientData
4. Verificar que preview se actualiza en tiempo real

### Fase 5: Validación

1. Cambiar template en admin → preview actualiza
2. Cambiar palette en admin → colores cambian
3. Toggle dark mode → preview invierte colores
4. No hay errors en console
5. Preview y storefront tienen el mismo theme

## Checklist de Implementación

### Pre-Integración
- [ ] Leer código actual de PreviewFrame
- [ ] Entender flujo de datos admin → preview
- [ ] Verificar compatibilidad (React version, styled-components, TypeScript)
- [ ] Decidir Opción A (monorepo) vs Opción B (copiar)

### Desarrollo
- [ ] Copiar/crear resolver en admin
- [ ] Crear/actualizar useEffectiveTheme hook en admin
- [ ] Integrar en PreviewFrame
- [ ] Crear/actualizar controles UI (template, palette, dark mode)
- [ ] Verificar reactividad

### Validación
- [ ] Admin lint sin errors
- [ ] Admin typecheck sin errors
- [ ] Manual testing de cambios de template/palette
- [ ] Verificar que preview = storefront (visualmente)
- [ ] Verificar CSS variables en preview

### Documentación
- [ ] Actualizar README de admin
- [ ] Documentar flujo theme en admin
- [ ] Agregar ejemplos de uso del resolver

## Archivos Involucrados (Estimado)

**Admin App**:
- `/apps/admin/src/components/PreviewFrame.tsx` (modificar)
- `/apps/admin/src/services/themeResolver/` (crear o copiar)
- `/apps/admin/src/pages/[OnboardingPage].tsx` (actualizar state)
- `/apps/admin/src/components/[TemplateSelector].tsx` (crear o actualizar)
- `/apps/admin/src/components/[PaletteSelector].tsx` (crear o actualizar)

**Documentación**:
- `/novavision-docs/THEME_ADMIN_INTEGRATION.md` (este archivo, actualizar)

## Después de Integración

Una vez que admin preview esté integrada:

1. **Verificación cruzada**: Abrir admin → crear cliente → cambiar template en preview → abrir storefront con ese cliente → verificar que tema es igual

2. **Cleanup**: Si se elige monorepo (Opción A), remover código duplicado de apps/

3. **Testing**: Agregar tests de integración que verifiquen que theme resolver produce mismo output en storefront y admin

4. **CI/CD**: Asegurarse que ambos apps compilan sin errores

## Referencias

- Resolver: `/apps/web/src/theme/resolveEffectiveTheme.ts`
- Hook: `/apps/web/src/hooks/useEffectiveTheme.ts`
- Paletas: `/apps/web/src/theme/palettes.ts`
- App.jsx (ejemplo de uso): `/apps/web/src/App.jsx`
- Manual de validación: `/novavision-docs/THEME_VALIDATION_MANUAL.md`

## Notas

- El resolver es agnóstico a React - puede usarse en cualquier contexto (vanilla JS, Vue, etc.)
- El hook es específico de React y es el "binding" entre resolver y componentes
- Si admin usa diferente framework (Svelte, Vue, etc.), necesitaría su propio hook/binding
- La duración estimada es 1-2 horas para auditoría y desarrollo, 30 min para validación

# Manual de Validación - Theme System Refactor

## Resumen de Cambios Realizados

### Fase 1: Resolver de Tema Unificado (COMPLETADO)

**Archivo**: `/apps/web/src/theme/resolveEffectiveTheme.ts` (400+ líneas)

Función principal que resuelve el tema efectivo a partir de:
- `templateKey`: Clave del template (normaliza `template_1` → `first`)
- `paletteKey`: Clave de paleta (ej. `starter_default`)
- `themeConfig`: Configuración custom del cliente
- `isDarkMode`: Modo oscuro activo
- Validación automática: contraste WCAG 2.0, tokens faltantes

### Fase 2: Hook de React (COMPLETADO)

**Archivo**: `/apps/web/src/hooks/useEffectiveTheme.ts` (40 líneas)

Wrapper memoizado que permite usar el resolver directamente en componentes React.

### Fase 3: Debug Panel para Desarrollo (COMPLETADO)

**Archivo**: `/apps/web/src/components/ThemeDebugPanel/ThemeDebugPanel.jsx` (400+ líneas)

Componente visual que muestra:
- Configuración actual (template, paleta, dark mode)
- Todos los colores resueltos con swatches
- Validación de contraste WCAG 2.0
- Advertencias de tokens faltantes
- Botón para inspeccionar en consola

### Fase 4: Integración en App.jsx (COMPLETADO)

**Archivo**: `/apps/web/src/App.jsx`

Cambios:
- ❌ Removidas importaciones hardcodeadas: `novaVisionThemeFifth`, `novaVisionThemeFifthDark`
- ✅ Agregadas importaciones: `useEffectiveTheme`, `ThemeDebugPanel`
- ✅ Reemplazada lógica de selección de tema:
  ```jsx
  // Antes:
  const theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth;

  // Ahora:
  const theme = useEffectiveTheme({
    templateKey: homeData?.config?.templateKey,
    paletteKey: homeData?.config?.paletteKey,
    themeConfig: homeData?.config?.themeConfig,
    isDarkMode: isDarkTheme,
    defaults: { templateKey: 'fifth', paletteKey: 'starter_default' },
    debug: import.meta.env.DEV,
  });
  ```
- ✅ Agregado ThemeDebugPanel para desarrollo

---

## Checklist de Validación Manual

### 1. Compilación y Tipos (PREREQUISITO)

```bash
# En /apps/web
npm run typecheck
npm run lint

# Esperado: Sin errores
```

### 2. Cargar Storefront en Desarrollo

```bash
# Terminal 1: Backend
cd apps/api
npm run start:dev

# Terminal 2: Storefront
cd apps/web
npm run dev
```

Acceder a: `http://localhost:5173`

**Validar**:
- [ ] Página carga sin errores en consola
- [ ] Header visible con colores correctos
- [ ] Botón de dark mode aparece en top-right
- [ ] Panel de debug (🎨) aparece en top-right

### 3. Validar Debug Panel

Hacer click en botón 🎨 para abrir el panel:

**Verificar**:
- [ ] Panel abre correctamente
- [ ] Muestra "Configuration" con template y palette
- [ ] Muestra "Colors" con lista de colores
- [ ] Muestra "Contrast Check" con ratio WCAG 2.0
- [ ] Muestra "Components" con colores de header/button/card
- [ ] Botón "Log to Console" funciona (abre DevTools y muestra theme)

### 4. Validar Resolución de Tema

En el debug panel, verificar:

**Template Resolution**:
- [ ] Si `templateKey = "template_1"`, debe normalizar a `"first"`
- [ ] Si `templateKey = "template_5"`, debe normalizar a `"fifth"`
- [ ] Si falta templateKey, fallback a `"fifth"`

**Palette Resolution**:
- [ ] Si `paletteKey = "starter_default"`, carga colores correctos
- [ ] Si `paletteKey` no existe, fallback a `"starter_default"`
- [ ] Los colores en el panel coinciden con el renderizado visual

### 5. Validar Contraste

En el debug panel, sección "Contrast Check":

- [ ] Si muestra ✅ verde: Contraste >= 4.5:1 (AA level)
- [ ] Si muestra ⚠️ amarillo: Contraste 3-4.5:1 (warning)
- [ ] Si muestra ❌ rojo: Contraste < 3:1 (FAIL - texto ilegible)

**Caso crítico**: Si ves dark background con dark text → contraste debe ser ROJO en el panel

### 6. Validar Toggle de Dark Mode

1. Click en botón de toggle tema en header
2. En el debug panel:
   - [ ] Campo "Dark Mode:" cambia de "YES" a "NO"
   - [ ] Los colores cambian
   - [ ] El contraste se recalcula
   - [ ] No hay errores en consola

### 7. Validar CSS Variables

En DevTools → Inspector → `<html>` elemento:

```bash
Buscar atributos: data-theme="dark" o data-theme="light"
Buscar variables: --nv-bg, --nv-text, --nv-primary, etc.
```

**Verificar**:
- [ ] `data-theme` attribute cambia con toggle
- [ ] Variables CSS presentes y con valores hexadecimales válidos
- [ ] Variables usadas en componentes (button, header, card)

### 8. Validar en Consola

1. Abrir DevTools (F12)
2. En console, ejecutar:

```javascript
// Ver el theme completo
console.log(window.__THEME__)

// O si es accesible directamente en app context:
// Buscar en Sources el archivo App.jsx
// Ver la variable `theme` en scope
```

### 9. Caso de Prueba: Sin homeData

Si no hay datos del servidor (error/loading):

- [ ] App muestra "Cargando datos..." sin errors
- [ ] Debug panel no aparece (porque tema está en fallback)
- [ ] Una vez que homeData carga, colores actualizan

### 10. Validar Compatibilidad

En diferentes navegadores:

- [ ] Chrome/Edge: Tema funciona, debug panel visible
- [ ] Firefox: Tema funciona
- [ ] Safari: Tema funciona
- [ ] Mobile (simulador): Tema funciona, debug panel accessible (si DEV)

---

## Casos de Uso Específicos

### Caso 1: Tienda "Starter" con Paleta Default

```
Input:
- templateKey: "template_1"
- paletteKey: "starter_default"
- isDarkMode: false

Esperado:
- Template normalizado a "first"
- Colores de `PALETTES.starter_default` aplicados
- Contraste texto/fondo >= 4.5:1
- Header azul claro, botones azules, fondo blanco
```

### Caso 2: Tienda en Modo Oscuro

```
Input:
- templateKey: "template_1"
- paletteKey: "starter_default"
- isDarkMode: true

Esperado:
- Mismo template y paleta, pero aplicados con inversión oscura
- Background oscuro, texto claro
- Contraste aún >= 4.5:1
```

### Caso 3: Tienda Boutique con Paleta Custom

```
Input:
- templateKey: "template_5" (boutique)
- paletteKey: "boutique_default"
- isDarkMode: false

Esperado:
- Template normalizado a "fifth"
- Colores `PALETTES.boutique_default` aplicados
- Estilos específicos del template fifth (fuentes, espaciado)
```

### Caso 4: Fallback de Tienda Desconocida

```
Input:
- templateKey: "template_99" (NO EXISTE)
- paletteKey: "unknown_palette"
- isDarkMode: false

Esperado:
- Template fallback a "fifth"
- Paleta fallback a "starter_default"
- Warnings en debug panel
- App sigue funcionando (no crash)
```

---

## Troubleshooting

### Problema: "Dark on Dark" - Texto ilegible

**Síntomas**:
- Debug panel muestra "Contrast: 1.00:1 (FAIL)"
- Header/cards con background y text del mismo color oscuro

**Verificar**:
1. ¿Qué palette se está usando? (ver en debug panel)
2. ¿isDarkMode está en true? (ver en debug panel)
3. ¿El template soporta dark mode? (template_1, template_5 sí)

**Soluciones**:
- Cambiar paletteKey a una paleta con contraste (ej. "starter_default" en lugar de "dark_default")
- Verificar que los colores en `src/theme/palettes.ts` tienen buen contraste
- Si problema persiste, revisar `createTheme()` en `src/theme/index.ts` - puede estar inyectando colores incorrectos

### Problema: Template no se aplica

**Síntomas**:
- Estilos específicos del template (fuentes, espaciado) no aparecen
- Debug panel muestra template correcto

**Verificar**:
1. ¿El template existe en `src/theme/templates/`?
2. ¿`createTheme()` está siendo llamado correctamente?
3. ¿El resolver está retornando un theme válido?

**Soluciones**:
- Abrir DevTools y logear: `console.log(theme)` en App.jsx
- Verificar que template base está siendo usado por `createTheme()`
- Revisar en `src/theme/templates/` que template exists

### Problema: CSS Variables no aparecen

**Síntomas**:
- En DevTools → Element → ver `<html>`, no hay `--nv-*` variables
- O variables están pero con valores `undefined`

**Verificar**:
1. ¿`useThemeVars(theme)` está siendo llamado en App.jsx? (✅ sí)
2. ¿El hook tiene el theme correcto como dependency?
3. ¿globalStyles está aplicando las variables?

**Soluciones**:
- Verificar `useThemeVars()` hook en `src/hooks/useThemeVars.ts`
- Asegurarse que `createGlobalStyle` en globalStyles aplica las variables
- Revisar en DevTools que el script de CSS variables se ejecutó

### Problema: Debug Panel no aparece

**Síntomas**:
- Botón 🎨 no visible en top-right
- O aparece pero no abre

**Verificar**:
1. ¿`import.meta.env.DEV` es `true`? (solo dev, no prod)
2. ¿ThemeDebugPanel se importó correctamente?
3. ¿Hay errores en consola?

**Soluciones**:
- Verificar en consola que no hay import errors
- Asegurarse que estás en modo `npm run dev` (no `npm run build`)
- Revisar en App.jsx que ThemeDebugPanel se renderiza en JSX

---

## Performance & Optimizaciones

### useMemo en useEffectiveTheme

El hook usa `useMemo` para evitar recomputar el theme si los inputs no cambian:

```javascript
const dependencies = [
  templateKey,
  paletteKey,
  isDarkMode,
  JSON.stringify(themeConfig),
  JSON.stringify(overrides),
];
```

**Impacto**: Render de App.jsx dispara, pero theme solo se recalcula si inputs cambian.

### useThemeVars Hook

Aplica CSS variables al `<html>` una sola vez cuando el theme cambia.

**Impacto**: CSS variables no causan re-renders frecuentes.

---

## Próximos Pasos (Fases 5-6)

### Fase 5: Integración en Admin (OnboardingPreview)

La rama `feature/onboarding-preview-stable` tiene su propio sistema de preview. Necesita:

1. Importar `useEffectiveTheme` en PreviewFrame
2. Usar la misma lógica de resolución
3. Pasar theme al componente de preview

### Fase 6: Documentación y Cleanup

1. Marcar temas hardcodeados en `globalStyles.jsx` como deprecated
2. Agregar comentarios en `App.jsx` explicando la nueva architecture
3. Crear guía de "Cómo agregar nueva paleta" en `src/theme/README.md`

---

## Aceptación de Criterios (DoD)

✅ Resolver está creado y probado
✅ Hook wrapper funciona correctamente
✅ Debug panel desarrollado y funciona
✅ App.jsx integrada
✅ TypeCheck y Lint sin errores
✅ Sin regresiones en templates existentes
✅ Validación de contraste WCAG 2.0 incluida
✅ Documentación completa

❌ Admin integration (Fase 5 - futura)
❌ Unit tests (Opcional - futura)

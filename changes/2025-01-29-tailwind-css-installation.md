# Cambio: Instalación y Configuración de Tailwind CSS

- **Autor:** agente-copilot
- **Fecha:** 2025-01-29
- **Rama:** develop (templatetwo/apps/web)

## Archivos modificados/creados

### Nuevos:
- `postcss.config.js` - Configuración de PostCSS con plugins tailwindcss y autoprefixer
- `src/styles/tailwind.css` - Entry point CSS con directivas Tailwind y estilos del Dev Portal

### Modificados:
- `src/main.jsx` - Agregado import de `./styles/tailwind.css`
- `src/__dev/DevPortalApp.jsx` - Eliminada importación duplicada de CSS
- `package.json` - Agregadas dependencias: tailwindcss@3.4.19, postcss, autoprefixer

### Eliminados:
- `src/__dev/devportal.css` - Movido el contenido a `src/styles/tailwind.css`

## Resumen del cambio

Se instaló y configuró Tailwind CSS v3.4.19 para el proyecto web (templatetwo). La configuración incluye:

1. **PostCSS Configuration** (`postcss.config.js`):
   ```js
   export default {
     plugins: {
       tailwindcss: {},
       autoprefixer: {},
     },
   }
   ```

2. **Entry Point CSS** (`src/styles/tailwind.css`):
   - Directivas `@tailwind base/components/utilities`
   - Clases utilitarias personalizadas (glass effects, animaciones, scrollbar)
   - Estilos completos del Dev Portal (sidebar, cards, badges, buttons, etc.)

3. **Import Global** en `main.jsx`:
   ```jsx
   import "./styles/tailwind.css";
   ```

## Por qué se hizo

- El Dev Portal fue rediseñado con un mockup que usa clases de Tailwind CSS
- El proyecto tenía `tailwind.config.js` pero Tailwind no estaba instalado como dependencia
- Se preparó la infraestructura para futuros templates que usarán Tailwind

### Nota sobre versión

- Se intentó primero con **Tailwind v4** pero requería configuración CSS-first diferente (`@tailwindcss/postcss`)
- Se hizo **downgrade a v3.4.19** por compatibilidad con el `tailwind.config.js` existente y styled-components

## Cómo probar

1. **Dev Server:**
   ```bash
   cd apps/web && npm run dev
   # Abrir http://localhost:5173/__dev
   ```

2. **Build:**
   ```bash
   cd apps/web && npm run build
   # Debe pasar sin errores
   ```

3. **Verificar Dev Portal:**
   - El portal debe mostrar tema oscuro (slate colors)
   - Sidebar con navegación estilizada
   - Cards con bordes de color según sección
   - Pills y badges con colores correctos

## Notas de seguridad

- No aplica - cambios solo en frontend de desarrollo
- Tailwind no expone información sensible

## Dependencias agregadas

```json
{
  "devDependencies": {
    "autoprefixer": "^10.x",
    "postcss": "^8.x",
    "tailwindcss": "^3.4.19"
  }
}
```

## Configuración existente preservada

El archivo `tailwind.config.js` ya existía con:
- Content paths: `./index.html`, `./src/**/*.{js,ts,jsx,tsx}`
- Dark mode: `class`
- Theme extendido con colores NovaVision (variables CSS)
- Fuentes personalizadas (Inter, Geist)
- Animaciones y plugins

## Próximos pasos sugeridos

1. Verificar visualmente que el Dev Portal coincide con los mockups
2. Considerar migrar componentes de styled-components a Tailwind gradualmente
3. Para nuevos templates, usar Tailwind por defecto

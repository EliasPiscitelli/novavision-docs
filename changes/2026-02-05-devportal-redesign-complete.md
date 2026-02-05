# Cambio: Dev Portal Redesign Completo

- **Autor:** Copilot Agent
- **Fecha:** 2026-02-05
- **Rama:** develop (templatetwo)
- **Tipo:** Feature / UI Redesign

---

## Resumen

Rediseño completo del NovaVision Dev Portal basado en mockups de alta fidelidad. Se implementó un nuevo sistema de diseño (Design System), componentes atómicos, y se actualizaron todas las páginas principales con el nuevo look & feel.

---

## Archivos Modificados

### Nuevos Archivos
- `src/__dev/design-system/tokens.js` - Design tokens (colores, espaciados, tipografía)
- `src/__dev/design-system/components.jsx` - Componentes atómicos reutilizables
- `src/__dev/design-system/index.js` - Barrel export

### Archivos Actualizados
- `src/__dev/components/DevPortalLayout.jsx` - Layout principal rediseñado
- `src/__dev/pages/IndexPage/index.jsx` - Dashboard rediseñado
- `src/__dev/pages/TemplatesPage/index.jsx` - Catálogo de templates rediseñado
- `src/__dev/pages/GeneratorPage/index.jsx` - AI Generator con wizard
- `src/__dev/pages/StagingPage/index.jsx` - Staging con Git integration

---

## Decisiones Técnicas

### 1. Design System
Se creó un sistema de diseño centralizado con:
- **Paleta Dark Mode:** Slate 900 (#0F172A) como fondo, Slate 800 (#1E293B) como superficie
- **Colores de acento:** Green (stable), Yellow (beta), Blue (info), Red (error)
- **Tipografía:** Inter como fuente principal
- **Animaciones:** Framer Motion para transiciones suaves

### 2. Componentes Atómicos
Se implementaron componentes reutilizables siguiendo atomic design:
- `Badge` - Indicadores de estado (stable, beta, pro, etc.)
- `Pill` - Pills de entorno (branch, env)
- `Card` - Contenedores con hover effects
- `Button` - Botones con variantes (primary, secondary, ghost, success, danger)
- `Input`, `Select` - Campos de formulario estilizados
- `ProgressStep` - Pasos del Quick Start
- `ServiceStatus` - Indicadores de health check

### 3. Layout Mejorado
- Sidebar fijo de 260px con navegación
- Atajos de teclado (⌘1-7 para navegación, ⌘K para Command Palette)
- Panel de Health Check para monitoreo de servicios
- Transiciones de página con AnimatePresence

### 4. Nuevas Funcionalidades
- **Git Integration en Staging:** Selector de branch, push, crear PR
- **Command Palette:** Búsqueda rápida con ⌘K
- **Quick Start:** Wizard de pasos para onboarding
- **Template Filters:** Filtros por categoría en catálogo

---

## Por Qué

El Dev Portal anterior tenía un diseño básico y carecía de consistencia visual. Los mockups de alta fidelidad proporcionados definían:
- Una experiencia más pulida y profesional
- Mejor organización de la información
- Funcionalidades nuevas (Git, Command Palette)
- Sistema de diseño escalable para futuras extensiones

---

## Cómo Probar

1. Levantar el servidor de desarrollo:
```bash
cd apps/web
npm run dev
```

2. Acceder al Dev Portal:
```
http://localhost:5173/__dev
```

3. Verificar:
- [ ] Dashboard carga correctamente con cards y quick start
- [ ] Navegación con sidebar funciona
- [ ] Atajos de teclado funcionan (⌘1-7, ⌘K)
- [ ] Templates page muestra filtros y grid
- [ ] Generator page tiene wizard de 3 pasos
- [ ] Staging page muestra Git controls

---

## Notas de Seguridad

- El Dev Portal está protegido por la ruta `/__dev` que solo es accesible en desarrollo
- No se exponen credenciales ni tokens en el frontend
- Las funciones de Git/PR son simuladas (no hay integración real aún)

---

## Dependencias

- `framer-motion` v12.4.10 (ya instalada)
- Tailwind CSS (ya configurado)
- React Router (ya configurado)

---

## Screenshots

> Las capturas se tomarán una vez el dev server esté corriendo.

---

## Próximos Pasos

1. Implementar integración real con GitHub API para PRs
2. Agregar Client Context Simulator
3. Implementar Asset/Icon browser
4. Agregar validación TypeScript en JSON editor
5. Crear Sandbox para código AI generado

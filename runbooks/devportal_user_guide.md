# 🚀 NovaVision Dev Portal - Guía de Usuario

> Guía interactiva completa para usar el Dev Portal de NovaVision.

---

## 📖 Índice

1. [Introducción](#introducción)
2. [Acceso al Dev Portal](#acceso-al-dev-portal)
3. [Dashboard (Inicio)](#dashboard-inicio)
4. [Templates (Catálogo)](#templates-catálogo)
5. [AI Generator (Prompts IA)](#ai-generator-prompts-ia)
6. [Components (Playground)](#components-playground)
7. [Staging Area](#staging-area)
8. [Auditor (Code Review)](#auditor-code-review)
9. [Atajos de Teclado](#atajos-de-teclado)
10. [Troubleshooting](#troubleshooting)

---

## Introducción

El **NovaVision Dev Portal** es un entorno de desarrollo interno diseñado para:

- 📄 **Previsualizar templates** con datos demo o de clientes reales
- 🤖 **Generar código** con prompts optimizados para Magic Patterns
- 🧩 **Probar componentes** de forma aislada
- 📦 **Gestionar staging** de archivos antes de commit
- ✅ **Auditar código** generado por IA

### Requisitos

- Node.js 18+
- npm o pnpm
- Navegador moderno (Chrome, Firefox, Safari, Edge)

---

## Acceso al Dev Portal

### 1. Levantar el servidor de desarrollo

```bash
cd apps/web
npm run dev
```

### 2. Abrir en el navegador

```
http://localhost:5173/__dev
```

> ⚠️ La ruta `/__dev` solo está disponible en modo desarrollo (`NODE_ENV=development`).

### 3. Verificar que todo funciona

Deberías ver el Dashboard con:
- Panel de Quick Start
- Grid de secciones (Templates, Generator, Components, Staging)
- Sidebar de navegación a la izquierda

---

## Dashboard (Inicio)

El Dashboard es la página principal del Dev Portal. Desde aquí puedes:

### 🎯 Quick Start

Pasos para comenzar a usar el portal:

| Paso | Descripción | Estado |
|------|-------------|--------|
| 1 | Seleccionar un template | ⏳ Pendiente |
| 2 | Personalizar con datos | ⏳ Pendiente |
| 3 | Generar código con IA | ⏳ Pendiente |
| 4 | Auditar y aprobar | ⏳ Pendiente |
| 5 | Commit al repo | ⏳ Pendiente |

### 📊 Panel de Estadísticas

- **Templates:** Cantidad disponibles
- **Staged Files:** Archivos en staging
- **Health:** Estado de servicios

### 🖥️ Responsive Frame

Preview en tiempo real de la tienda en diferentes viewports:
- Mobile (375px)
- Tablet (768px)
- Desktop (1440px)

### 📝 Data Editor

Editor JSON para modificar datos de prueba en tiempo real.

---

## Templates (Catálogo)

**Ruta:** `/__dev/templates`  
**Atajo:** `⌘2`

### Funcionalidades

#### Filtros por Categoría

```
[All] [Store] [Fashion] [Food]
```

Filtra los templates según el tipo de negocio.

#### Búsqueda

Usa el campo de búsqueda para encontrar templates por nombre o descripción.

#### Grid de Templates

Cada tarjeta muestra:
- Thumbnail (preview visual)
- Nombre del template
- Badge de estado (Stable / Beta)
- Badge de plan (si es Pro)
- Versión

#### Panel de Detalle

Al seleccionar un template:

1. **Header:** Nombre, descripción, data source selector
2. **Preview:** Vista previa del template
3. **Features:** Lista de características incluidas
4. **Archivos:** Estructura de archivos del template
5. **Acciones:** Usar Template, Ver Código

### Cómo usar un Template

1. Selecciona un template del grid
2. Elige "Demo Data" o "Client Data" como fuente
3. Si elegiste Client Data, selecciona el cliente
4. Click en "Usar Template"

---

## AI Generator (Prompts IA)

**Ruta:** `/__dev/generator`  
**Atajo:** `⌘3`

### Wizard de 3 Pasos

#### Paso 1: Tipo de Generación

Elige qué quieres generar:

| Tipo | Descripción | Ejemplo |
|------|-------------|---------|
| 📄 Full Template | Template completo | Tienda de ropa |
| 🧩 Component | Componente individual | ProductCard |
| 📦 Section | Sección de página | HeroSection |
| 🚀 Landing | Landing page | Promo Black Friday |

#### Paso 2: Detalles

Según el tipo elegido, completa:

**Para Templates/Landings:**
- Tipo de negocio (Fashion, Tech, Food, etc.)
- Estilo visual (Minimalista, Elegante, Colorido, etc.)
- Paleta de colores (opcional)
- Features especiales (Dark mode, animaciones, etc.)

**Para Components/Sections:**
- Nombre del componente
- Descripción detallada
- Features especiales

#### Paso 3: Resultado

El prompt generado aparece en el panel derecho. Puedes:

- **📋 Copiar:** Copia el prompt al clipboard
- **🔮 Abrir Magic Patterns:** Abre Magic Patterns en una nueva pestaña
- **🔄 Generar otro:** Vuelve al paso 1

### Tips para Buenos Prompts

1. Sé específico con el tipo de negocio
2. Menciona colores si tienes preferencia
3. Incluye features que necesitas (carrusel, dark mode, etc.)
4. El prompt ya incluye reglas de NovaVision (CSS vars, Tailwind, etc.)

---

## Components (Playground)

**Ruta:** `/__dev/components`  
**Atajo:** `⌘4`

### Funcionalidades

- **Catálogo de componentes:** Lista de todos los componentes disponibles
- **Props editor:** Modifica props en tiempo real
- **Preview:** Visualiza el componente con los props actuales
- **Código:** Ver el código fuente del componente

### Cómo probar un Componente

1. Selecciona un componente del catálogo
2. Modifica los props en el panel derecho
3. Observa los cambios en tiempo real en el preview
4. Copia el código si lo necesitas

---

## Staging Area

**Ruta:** `/__dev/staging`  
**Atajo:** `⌘5`

El Staging Area es donde revisas y apruebas código antes de hacer commit.

### Panel de Git

En el header encontrarás:

| Control | Descripción |
|---------|-------------|
| 🌿 Branch | Selector de rama activa |
| ↑ Push | Push commits al remoto |
| 📤 Create PR | Crear Pull Request |

### Estados de Archivo

| Estado | Significado |
|--------|-------------|
| ⏳ Pending | Pendiente de revisión |
| 👀 Reviewed | Revisado |
| ✅ Approved | Aprobado para commit |
| ❌ Rejected | Rechazado |

### Flujo de Trabajo

```
Generar código → Agregar a Staging → Revisar → Aprobar → Commit → Push → Create PR
```

1. **Agregar archivos:** Desde el Generator o importando
2. **Revisar:** Click en cada archivo para ver el código
3. **Cambiar estado:** Usa los botones de estado
4. **Commit:** Cuando hay archivos aprobados, aparece el panel de commit
5. **Push:** Envía los commits al remoto
6. **Create PR:** Abre modal para crear Pull Request

### Crear un Pull Request

1. Click en "📤 Create PR"
2. Completa:
   - **From → To:** Rama origen y destino
   - **Title:** Título descriptivo
   - **Description:** Descripción de los cambios
3. Click en "Create PR"

---

## Auditor (Code Review)

**Ruta:** `/__dev/auditor`  
**Atajo:** `⌘6`

### Funcionalidades

- **Pegar código:** Pega código generado por IA
- **Análisis automático:** Detecta problemas y warnings
- **Reglas NovaVision:** Valida contra nuestras convenciones
- **Staging:** Agrega código auditado al staging

### Reglas que Valida

| Regla | Descripción |
|-------|-------------|
| CSS Variables | Usa `var(--nv-*)` en lugar de colores hardcodeados |
| Tailwind | No mezclar con styled-components |
| Framer Motion | Importar correctamente |
| PropTypes | Definir para todos los props |
| Responsive | Mobile-first approach |

### Cómo Auditar Código

1. Pega el código en el editor
2. Click en "Auditar"
3. Revisa los resultados:
   - ✅ Pass: Código correcto
   - ⚠️ Warning: Mejoras sugeridas
   - ❌ Error: Problemas que corregir
4. Si está todo bien, click en "Add to Staging"

---

## Atajos de Teclado

### Navegación

| Atajo | Acción |
|-------|--------|
| `⌘1` | Ir a Dashboard |
| `⌘2` | Ir a Templates |
| `⌘3` | Ir a Generator |
| `⌘4` | Ir a Components |
| `⌘5` | Ir a Staging |
| `⌘6` | Ir a Auditor |

### Command Palette

| Atajo | Acción |
|-------|--------|
| `⌘K` | Abrir Command Palette |
| `Esc` | Cerrar Command Palette |
| `↑↓` | Navegar opciones |
| `Enter` | Ejecutar comando |

### Editor

| Atajo | Acción |
|-------|--------|
| `⌘S` | Guardar cambios |
| `⌘C` | Copiar código |
| `⌘V` | Pegar código |

---

## Troubleshooting

### El Dev Portal no carga

1. Verifica que el servidor esté corriendo:
```bash
npm run dev
```

2. Verifica la URL:
```
http://localhost:5173/__dev
```

3. Limpia caché del navegador

### Los estilos se ven rotos

1. Verifica que Tailwind esté compilando:
```bash
npm run build
```

2. Reinicia el servidor de desarrollo

### Los templates no cargan

1. Verifica la consola del navegador por errores
2. Verifica que los datos demo existan en `public/demo/`

### El Staging no guarda

1. Los cambios son en memoria (no persisten entre recargas)
2. Usa commit para guardar permanentemente

### Framer Motion no funciona

1. Verifica la instalación:
```bash
npm ls framer-motion
```

2. Debería mostrar: `framer-motion@12.4.10`

---

## 📚 Recursos Adicionales

- [Design System Tokens](../architecture/devportal-design-system.md)
- [API de Componentes](../architecture/devportal-components-api.md)
- [Changelog](../changes/)

---

## 💬 Soporte

Si encontrás problemas:

1. Revisá esta guía
2. Chequeá los logs en la consola
3. Consultá el canal de Slack #novavision-dev
4. Abrí un issue en GitHub

---

*Última actualización: 2026-02-05*

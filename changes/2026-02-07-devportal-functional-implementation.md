# Cambio: Dev Portal — Implementación Funcional Completa

- **Autor:** Copilot Agent
- **Fecha:** 2026-02-07
- **Rama:** develop (templatetwo)
- **Tipo:** Feature / Functionality

---

## Resumen

El Dev Portal tenía un excelente diseño visual pero casi ningún botón funcionaba realmente. Se auditaron las 7 páginas + layout, se identificaron todos los handlers falsos (console.log + alert), botones sin onClick, datos mock hardcodeados y falta de persistencia, y se implementó funcionalidad real en cada uno.

**Motivación:** Que un dev externo pueda usar el portal sin acceso al código fuente, reduciendo riesgo de copia del sistema y vulnerabilidades.

---

## Archivos Modificados

### Context y Layout
- `src/__dev/context/DevPortalContext.tsx`
  - Persistencia en localStorage (clave `novavision-devportal-state`)
  - Nuevo state: `promptHistory[]`, `notifications[]`
  - Nuevas acciones: `ADD_PROMPT_HISTORY`, `CLEAR_PROMPT_HISTORY`, `ADD_NOTIFICATION`, `REMOVE_NOTIFICATION`, `LOAD_PERSISTED_STATE`
  - Nuevos helpers: `addPromptHistory()`, `clearPromptHistory()`, `notify()` (auto-dismiss 4s), `dismissNotification()`

- `src/__dev/components/DevPortalLayout.jsx`
  - Health checks **reales**: fetch a `localhost:3000/health` y `${VITE_SUPABASE_URL}/rest/v1/` con AbortSignal.timeout(5000) y medición de latencia vía performance.now()
  - Sistema de notificaciones toast (fixed bottom-right, AnimatePresence, color-coded por tipo)
  - Se removió servicio hardcodeado de OpenAI

- `src/__dev/design-system/components.jsx`
  - ServiceStatus: nuevos estados `checking`, `no-config` con colores y fallback a `unknown`

### Páginas

- `src/__dev/pages/IndexPage/index.jsx`
  - Quick Start: pasos clickeables que navegan a la ruta correspondiente (templates → generator → auditor → staging)
  - Viewport buttons: onClick real → `setViewport('desktop'|'tablet'|'mobile')` con highlighting activo
  - Botón tema: toggle light/dark con ícono dinámico (sol/luna)
  - Reset JSON: resetea previewData al default + notificación
  - Apply JSON: parsea JSON, valida, aplica vía setPreviewData + notificación success/error
  - Stats dinámicas: templateCount=5, componentCount desde COMPONENT_REGISTRY, staging desde state, historial de prompts

- `src/__dev/pages/TemplatesPage/index.jsx`
  - "Usar como base": navega a `/__dev/generator?type=template&template={id}` + notificación
  - "Ver código fuente": abre modal con árbol de archivos del template (estructura de carpetas/componentes)
  - Modal: botón "Copiar info" (portapapeles) + "Generar con IA" (navega a Generator)

- `src/__dev/pages/GeneratorPage/index.jsx`
  - `stageFile` conectado (ya no es `_stageFile` sin usar)
  - URL params: al llegar desde Templates con `?template=X`, pre-completa businessType
  - Historial real: usa `state.promptHistory` del contexto (persistido en localStorage) en vez de mock
  - Items del historial clickeables: cargan el prompt anterior
  - Al generar: guarda en historial + notificación
  - Nuevo botón **"📦 Enviar a Staging"** en paso 3: hace stageFile()
  - "Copiar" muestra notificación
  - Se eliminó variable `BUSINESS_TYPES_LOOKUP` sin uso

- `src/__dev/pages/StagingPage/index.jsx`
  - **Commit**: genera bundle .txt descargable con todos los archivos aprobados (metadatos + código)
  - **Push**: copia todos los archivos al portapapeles como bundle formateado
  - **Create PR**: auto-genera descripción de PR en Markdown (título, archivos, checklist, fecha) y la copia al portapapeles
  - Copiar código del preview → notificación
  - Todas las validaciones con notify() en vez de alert()

- `src/__dev/pages/AuditorPage/index.jsx`
  - Reemplazados todos los alert() por notify() del contexto

- `src/__dev/pages/ComponentsPage/index.jsx`
  - Preview tab: muestra nombre, descripción, estructura JSX, props activas con tipos, botón "Copiar info"
  - Code tab: botón "📋 Copiar" que copia snippet de uso al portapapeles

---

## Qué se eliminó

- Todos los `alert()` del portal (0 restantes)
- Todos los `console.log()` en handlers (0 restantes)
- Datos mock hardcodeados: `PROMPT_HISTORY` (reemplazado por contexto real), `BUSINESS_TYPES_LOOKUP` (eliminado)
- Health checks con `Math.random()` (reemplazados por fetch reales)
- Stats hardcodeadas en Dashboard (reemplazadas por valores dinámicos)

---

## Flujo funcional completo (ahora operativo)

```
1. IndexPage → Quick Start guía al dev paso a paso
2. TemplatesPage → Elige template → "Usar como base" → navega a Generator con params
3. GeneratorPage → Completa wizard → Genera prompt → Copia o envía a Staging
4. AuditorPage → Pega código → Audita → Envía a Staging
5. StagingPage → Revisa archivos → Aprueba → Commit (descarga) / Push (clipboard) / PR (genera markdown)
6. ComponentsPage → Explora componentes → Prueba props → Copia snippets
```

---

## Persistencia

Se persisten en localStorage (clave `novavision-devportal-state`):
- `stagedFiles` — archivos en staging
- `promptHistory` — historial de prompts generados (últimos 50)
- `lastGeneratedCode` — último código generado
- `selectedClientSlug` — slug del cliente activo
- `previewTheme` — tema de preview ('light'|'dark')
- `viewport` — viewport activo ('desktop'|'tablet'|'mobile')

---

## Cómo probar

```bash
# Levantar API (para health checks reales)
cd apps/api && npm run start:dev

# Levantar Web
cd apps/web && npm run dev

# Ir al Dev Portal
http://localhost:5173/__dev
```

### Flujo de prueba:
1. Dashboard: verificar health checks verdes, stats dinámicas, Quick Start clickeable
2. Templates: elegir uno → "Usar como base" → verificar que navega al Generator
3. Templates: "Ver código fuente" → verificar que abre modal con árbol
4. Generator: completar wizard → generar → verificar historial + "Enviar a Staging"
5. Staging: verificar archivos recibidos → aprobar → Commit → verificar descarga .txt
6. Auditor: pegar código → auditar → enviar a staging → verificar notificación
7. Components: seleccionar componente → verificar preview mejorado + "Copiar"

---

## Notas de seguridad

- El Dev Portal solo es accesible en modo desarrollo (`src/__dev/` excluido de build prod)
- No se exponen tokens ni SERVICE_ROLE_KEY
- Los health checks usan timeout de 5s para evitar bloqueos
- La persistencia es localStorage del navegador (datos locales del dev, no sensibles)

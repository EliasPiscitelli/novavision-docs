# 🛠️ Dev Portal Update — Plan de Ejecución por PRs

> **Fecha:** 2026-02-07  
> **Repo:** `templatetwo` (apps/web)  
> **Rama base:** `develop`  
> **Ramas feature:** `feature/devportal-section-builder-*`  
> **Scope:** Solo frontend (apps/web/src/__dev/). No requiere cambios en backend.

---

## 📊 Estado Actual vs Objetivo

| Capacidad | Hoy | Objetivo |
|---|---|---|
| Selector de cliente real (multi-tenant) | ❌ Mock (3 clientes hardcoded) | ✅ Fetch real desde API `/clients` |
| Fetch de datos de tenant (productos, categorías, banners) | ❌ No existe | ✅ APIs `/products`, `/categories`, `/banners` |
| Catálogo de plantillas de sección | ❌ Solo templates completos | ✅ Secciones individuales (FAQ, Banner, Carousel, Hero, Testimonios) |
| Editor visual de sección con formularios | ❌ No existe | ✅ Formulario dinámico por tipo de sección |
| Validación Zod de secciones | 🟡 Solo homeData | ✅ Schema por tipo de sección |
| Generación con IA (autocompletar campos) | ❌ Solo genera prompt para copiar | ✅ Botón que llama API de IA y rellena campos |
| Preview en tiempo real | ❌ CSS mockups estáticos | ✅ Render del componente real o iframe sandbox |
| Guardar/publicar sección | ❌ No existe | ✅ Persiste config de sección en staging + deploy |
| Canvas de layout (orden de secciones) | ❌ No existe | ✅ Vista de página con secciones drag & drop |

---

## 🗺️ Diagrama de Dependencias entre PRs

```
PR-1 (Infraestructura)
  ├── PR-2 (Schemas Zod)
  │     └── PR-4 (Editor Visual)
  │           ├── PR-5 (IA Autocompletar)
  │           └── PR-6 (Preview en Tiempo Real)
  │                 └── PR-7 (Canvas de Layout)
  └── PR-3 (Client Selector + Fetch Real)
        └── PR-4 (Editor Visual usa datos reales)

PR-8 (Polish, tests, documentación) — independiente, al final
```

---

## 📋 PRs Detallados

---

### PR-1: Infraestructura — Nueva página `SectionBuilderPage` + routing + context

**Rama:** `feature/devportal-section-builder-infra`  
**Estimación:** 1-2 días  
**Riesgo:** Bajo  
**Dependencias:** Ninguna

#### Qué se hace

1. **Nueva ruta** `/__dev/sections` en `DevPortalRouter.jsx`
2. **Nueva página** `src/__dev/pages/SectionBuilderPage/index.jsx` con layout base (wizard skeleton)
3. **Actualizar sidebar** en `DevPortalLayout.jsx`: agregar item "Constructor de Secciones" con icono 🧱 y badge "Nuevo"
4. **Extender `DevPortalContext.tsx`:**
   - Nuevo slice: `sectionBuilder: { selectedClientId, sectionType, sectionConfig, sectionsList }`
   - Actions: `SET_BUILDER_CLIENT`, `SET_SECTION_TYPE`, `SET_SECTION_CONFIG`, `ADD_SECTION_TO_LIST`, `REORDER_SECTIONS`, `REMOVE_SECTION`
   - Persistencia en localStorage
5. **Agregar shortcut** `⌘7` para la nueva página
6. **Agregar a Command Palette** (`⌘K`)

#### Archivos a tocar

| Archivo | Cambio |
|---|---|
| `src/__dev/DevPortalRouter.jsx` | Nueva ruta lazy |
| `src/__dev/pages/SectionBuilderPage/index.jsx` | **Nuevo** — Shell de la página |
| `src/__dev/components/DevPortalLayout.jsx` | Nav item + shortcut |
| `src/__dev/context/DevPortalContext.tsx` | Slice sectionBuilder + actions |
| `src/__dev/pages/IndexPage/index.jsx` | Nueva SectionCard en dashboard |

#### Criterios de aceptación

- [ ] Navegar a `/__dev/sections` renderiza la nueva página
- [ ] Sidebar muestra "Constructor de Secciones" con badge "Nuevo"
- [ ] `⌘7` navega a la página
- [ ] Estado sectionBuilder persiste en localStorage
- [ ] No rompe ninguna ruta existente

---

### PR-2: Esquemas Zod por tipo de sección

**Rama:** `feature/devportal-section-schemas`  
**Estimación:** 1 día  
**Riesgo:** Bajo  
**Dependencias:** Ninguna (puede ir en paralelo con PR-1)

#### Qué se hace

1. **Nuevo directorio** `src/__dev/schemas/`
2. **Schemas Zod** para cada tipo de sección:
   - `faqSchema.ts` — `z.object({ items: z.array(z.object({ question: z.string().min(1), answer: z.string().min(1) })).min(1) })`
   - `bannerSchema.ts` — `z.object({ title, subtitle?, imageUrl: z.string().url(), ctaText, ctaLink: z.string().url() })`
   - `carouselSchema.ts` — `z.object({ title, categoryId: z.string().uuid(), limit: z.number().int().min(1).max(20).default(8) })`
   - `heroSchema.ts` — `z.object({ headline, subheadline?, backgroundImage?, ctaText?, ctaLink? })`
   - `testimonialsSchema.ts` — `z.object({ items: z.array(z.object({ name, role?, text, avatarUrl? })).min(1) })`
   - `index.ts` — barrel export + `SECTION_TYPES` registry con metadata (nombre, icono, descripción, schema)
3. **Tests unitarios** para cada schema (validación positiva/negativa)

#### Archivos a crear

| Archivo | Descripción |
|---|---|
| `src/__dev/schemas/faqSchema.ts` | Schema FAQ |
| `src/__dev/schemas/bannerSchema.ts` | Schema Banner con CTA |
| `src/__dev/schemas/carouselSchema.ts` | Schema Carousel de Productos |
| `src/__dev/schemas/heroSchema.ts` | Schema Hero Section |
| `src/__dev/schemas/testimonialsSchema.ts` | Schema Testimonios |
| `src/__dev/schemas/index.ts` | Registry de secciones + tipos exportados |
| `src/__dev/schemas/__tests__/schemas.test.ts` | Tests |

#### Criterios de aceptación

- [ ] Cada schema valida datos correctos sin error
- [ ] Cada schema rechaza datos incompletos/inválidos con mensajes claros
- [ ] `SECTION_TYPES` contiene metadata: `{ id, name, icon, description, schema, defaultValues }`
- [ ] Tipos TypeScript exportados: `FaqSection`, `BannerSection`, `CarouselSection`, etc.

---

### PR-3: Selector de Cliente real + Fetch de datos multi-tenant

**Rama:** `feature/devportal-client-selector`  
**Estimación:** 2 días  
**Riesgo:** Medio (depende de APIs disponibles)  
**Dependencias:** PR-1

#### Qué se hace

1. **Nuevo componente** `src/__dev/components/ClientSelector.jsx`:
   - Dropdown con búsqueda que lista clientes reales
   - Fetch a la API: `GET /clients` (o cualquier endpoint equivalente que devuelva nombre + slug + id)
   - Fallback a 3 clientes demo si la API no está disponible
   - Persiste selección en context (`selectedClientId`)
   - Indicador de conexión (online/offline/demo mode)
2. **Nuevo hook** `src/__dev/hooks/useTenantData.ts`:
   - `useTenantData(clientId)` → retorna `{ products, categories, banners, faqs, settings, loading, error }`
   - Llama a las APIs existentes con header `x-client-id`
   - Cache con `useRef` para evitar re-fetch innecesario
   - Fallback a datos demo si API no disponible
3. **Integrar ClientSelector** en el Step 1 del SectionBuilderPage
4. **Actualizar TemplatesPage** para usar `ClientSelector` en lugar de los 3 clientes hardcoded

#### Archivos a tocar/crear

| Archivo | Cambio |
|---|---|
| `src/__dev/components/ClientSelector.jsx` | **Nuevo** |
| `src/__dev/hooks/useTenantData.ts` | **Nuevo** |
| `src/__dev/hooks/index.ts` | **Nuevo** — barrel export |
| `src/__dev/pages/SectionBuilderPage/index.jsx` | Integrar Step 1 con ClientSelector |
| `src/__dev/pages/TemplatesPage/index.jsx` | Reemplazar clientes hardcoded |
| `src/__dev/context/DevPortalContext.tsx` | Usar `selectedClientId` (uuid) además de slug |

#### Criterios de aceptación

- [ ] Dropdown muestra clientes reales si API está corriendo
- [ ] Muestra clientes demo si API está offline (graceful degradation)
- [ ] Al seleccionar un cliente, `useTenantData` trae productos/categorías/banners reales
- [ ] Header `x-client-id` se envía en cada request
- [ ] Selección persiste entre navegaciones

---

### PR-4: Editor Visual de Sección (formularios dinámicos + validación)

**Rama:** `feature/devportal-section-editor`  
**Estimación:** 3-4 días  
**Riesgo:** Medio  
**Dependencias:** PR-1, PR-2, PR-3

#### Qué se hace

1. **Wizard de 3 pasos** en `SectionBuilderPage`:
   - **Step 1:** Seleccionar Cliente (ClientSelector de PR-3)
   - **Step 2:** Elegir tipo de sección (grid de cards desde `SECTION_TYPES` registry de PR-2)
   - **Step 3:** Editor de campos + preview
2. **Componente `SectionFormRenderer`** — renderiza formulario dinámico según el schema:
   - Para `z.string()` → Input text
   - Para `z.string().url()` → Input text con preview de imagen si es imageUrl
   - Para `z.number()` → Input number con stepper
   - Para `z.array()` → Lista repetible con botón "Agregar" / "Quitar"
   - Para selects derivados de data real (ej. `categoryId`) → Dropdown con categorías del tenant
   - Validación inline en real-time usando `.safeParse()`
   - Mensajes de error Zod traducidos a español
3. **Componentes de campo** reutilizables:
   - `FieldText`, `FieldUrl`, `FieldNumber`, `FieldSelect`, `FieldImageUpload`, `FieldRepeatableGroup`
4. **Barra lateral** con metadatos de la sección (tipo, schema, campos requeridos/opcionales)
5. **Botón "Guardar en Staging"** — serializa config validada y la envía al staging area

#### Archivos a crear

| Archivo | Descripción |
|---|---|
| `src/__dev/pages/SectionBuilderPage/index.jsx` | Wizard completo de 3 pasos |
| `src/__dev/pages/SectionBuilderPage/StepSelectClient.jsx` | Step 1 |
| `src/__dev/pages/SectionBuilderPage/StepSelectSection.jsx` | Step 2 — grid de tipos |
| `src/__dev/pages/SectionBuilderPage/StepEditor.jsx` | Step 3 — editor + preview |
| `src/__dev/components/SectionFormRenderer.jsx` | Renderiza form según schema |
| `src/__dev/components/fields/FieldText.jsx` | Campo texto |
| `src/__dev/components/fields/FieldUrl.jsx` | Campo URL con preview |
| `src/__dev/components/fields/FieldNumber.jsx` | Campo numérico |
| `src/__dev/components/fields/FieldSelect.jsx` | Select (datos reales o estáticos) |
| `src/__dev/components/fields/FieldRepeatableGroup.jsx` | Grupo repetible (para FAQ items, testimonios) |
| `src/__dev/components/fields/FieldImageUpload.jsx` | Upload/URL de imagen con preview |
| `src/__dev/components/fields/index.js` | Barrel export |

#### Criterios de aceptación

- [ ] Wizard navega entre 3 pasos con animación (framer-motion)
- [ ] Step 2 muestra todos los tipos de sección con icono, nombre y descripción
- [ ] Step 3 renderiza formulario correcto según tipo elegido
- [ ] FAQ muestra lista de Q/A repetible
- [ ] Carousel muestra dropdown de categorías reales del tenant seleccionado
- [ ] Banner muestra campos de imagen/texto con preview de imagen
- [ ] Validación en real-time: campos inválidos se marcan en rojo con mensaje
- [ ] Solo se puede guardar si `.safeParse()` retorna `success: true`
- [ ] Al guardar, la sección aparece en staging area con su JSON config

---

### PR-5: Integración IA — Autocompletar campos con sugerencias

**Rama:** `feature/devportal-ai-autocomplete`  
**Estimación:** 2 días  
**Riesgo:** Medio-Alto (depende de acceso a API de IA)  
**Dependencias:** PR-4

#### Qué se hace

1. **Nuevo hook** `src/__dev/hooks/useAISuggestions.ts`:
   - Recibe: `sectionType`, `context` (nombre del negocio, rubro, datos del tenant)
   - Llama a API de IA (OpenAI / Anthropic / endpoint propio) con un prompt estructurado
   - Retorna JSON que matchea el schema Zod de la sección
   - Manejo de errores, timeout, rate limiting
   - Modo offline: si no hay API key configurada, devuelve sugerencias hardcoded de ejemplo
2. **Botón "✨ Sugerir con IA"** en cada formulario de sección (StepEditor):
   - Estado: idle → loading → success / error
   - Al recibir respuesta, rellena los campos del formulario
   - El usuario puede editar lo sugerido antes de guardar
3. **Prompt templates** por tipo de sección:
   - FAQ: "Generá 5 preguntas frecuentes para una tienda de {rubro} llamada {nombre}"
   - Banner: "Generá un título y subtítulo promocional para {nombre}, rubro {rubro}"
   - Testimonios: "Generá 3 testimonios realistas de clientes de {nombre}"
4. **Configuración de API key** en settings del Dev Portal (almacenado en localStorage, nunca commitear)

#### Archivos a crear/tocar

| Archivo | Cambio |
|---|---|
| `src/__dev/hooks/useAISuggestions.ts` | **Nuevo** — hook de IA |
| `src/__dev/config/aiPromptTemplates.ts` | **Nuevo** — templates de prompts por tipo |
| `src/__dev/config/aiConfig.ts` | **Nuevo** — config de API (key, model, endpoint) |
| `src/__dev/pages/SectionBuilderPage/StepEditor.jsx` | Agregar botón "Sugerir con IA" |
| `src/__dev/components/AISettingsModal.jsx` | **Nuevo** — modal para configurar API key |

#### Criterios de aceptación

- [ ] Botón "Sugerir con IA" visible en el editor de cada sección
- [ ] Al hacer clic, muestra loading state y luego rellena campos
- [ ] Respuesta de IA se valida contra el schema Zod antes de aplicar
- [ ] Si falla la IA o no hay key, muestra sugerencias demo con notificación
- [ ] Campos rellenados por IA son editables
- [ ] API key se guarda en localStorage (nunca en env ni en código)

---

### PR-6: Preview en Tiempo Real

**Rama:** `feature/devportal-live-preview`  
**Estimación:** 2-3 días  
**Riesgo:** Medio  
**Dependencias:** PR-4

#### Qué se hace

1. **Panel de preview** en el Step 3 del editor (split view: form izq / preview der)
2. **Renderizado real de componentes del storefront:**
   - Importar dinámicamente los componentes reales del site (`FaqAccordion`, `HeroBanner`, `ProductCarousel`, etc.)
   - Wrappearlos en un sandbox aislado con theme del cliente
   - Pasar las props del formulario en real-time
3. **Fallback: CSS mockup** si el componente real no está disponible
4. **Controles de viewport** en el preview (mobile/tablet/desktop) reutilizando `ResponsiveFrame`
5. **Toggle light/dark** mode en preview
6. **Zoom control** (50%, 75%, 100%)

#### Archivos a crear/tocar

| Archivo | Cambio |
|---|---|
| `src/__dev/components/SectionPreview.jsx` | **Nuevo** — wrapper de preview con viewport/zoom |
| `src/__dev/components/SectionPreviewRenderer.jsx` | **Nuevo** — mapea sectionType → componente real |
| `src/__dev/pages/SectionBuilderPage/StepEditor.jsx` | Integrar panel de preview |
| `src/__dev/components/ResponsiveFrame.jsx` | Reutilizar/extender para secciones |

#### Criterios de aceptación

- [ ] Al editar un campo del formulario, el preview se actualiza en <200ms
- [ ] Preview de FAQ muestra acordeón real con las preguntas del form
- [ ] Preview de Banner muestra imagen/texto al estilo del storefront
- [ ] Preview de Carousel muestra productos reales del tenant (o placeholders)
- [ ] Viewport responsive funciona (375/768/1280)
- [ ] Theme toggle aplica colores light/dark

---

### PR-7: Canvas de Layout — Organización de secciones de página

**Rama:** `feature/devportal-layout-canvas`  
**Estimación:** 2-3 días  
**Riesgo:** Medio  
**Dependencias:** PR-4, PR-6

#### Qué se hace

1. **Nueva vista "Layout Editor"** en SectionBuilderPage (tab adicional o paso extra)
2. **Lista vertical sorteable** de secciones (drag & drop) usando `@dnd-kit/sortable` o similar
3. **Cada item** muestra: tipo de sección (icono + label), mini-preview colapsable, botones (editar, duplicar, eliminar)
4. **Botón "Agregar sección"** que abre el wizard (Steps 2-3) y agrega la nueva sección al layout
5. **Persistencia** del layout en context (array de secciones con orden)
6. **Preview full-page** que renderiza todas las secciones en orden como se vería la página real
7. **Exportar layout** como JSON config descargable

#### Archivos a crear/tocar

| Archivo | Cambio |
|---|---|
| `src/__dev/pages/SectionBuilderPage/LayoutCanvas.jsx` | **Nuevo** — canvas de layout |
| `src/__dev/pages/SectionBuilderPage/SortableSection.jsx` | **Nuevo** — item drag & drop |
| `src/__dev/pages/SectionBuilderPage/FullPagePreview.jsx` | **Nuevo** — preview de todas las secciones |
| `src/__dev/pages/SectionBuilderPage/index.jsx` | Agregar tab/vista de layout |
| `src/__dev/context/DevPortalContext.tsx` | Acciones REORDER_SECTIONS |

#### Criterios de aceptación

- [ ] Se pueden agregar múltiples secciones al layout
- [ ] Drag & drop reordena las secciones
- [ ] Duplicar/eliminar sección funciona
- [ ] Preview full-page muestra todas las secciones en orden
- [ ] Layout persiste en localStorage
- [ ] JSON exportable contiene toda la config del layout

---

### PR-8: Polish, documentación y tests

**Rama:** `feature/devportal-section-builder-polish`  
**Estimación:** 1-2 días  
**Riesgo:** Bajo  
**Dependencias:** PR-1 a PR-7

#### Qué se hace

1. **Actualizar Design System** si se agregaron tokens/componentes nuevos
2. **Actualizar `src/__dev/README.md`** con documentación de la nueva funcionalidad
3. **Actualizar `devportal_user_guide.md`** en novavision-docs con sección "Constructor de Secciones"
4. **Actualizar `devportal-design-system.md`** con nuevos componentes de campo
5. **Atajos de teclado**: verificar que `⌘7` funciona, actualizar tabla en docs
6. **Responsive**: verificar que el editor funciona en viewports chicos
7. **Accesibilidad**: labels, aria-labels, focus management en el wizard
8. **Tests de integración** manuales: documentar checklist de prueba
9. **Performance**: verificar que lazy loading funciona, no hay memory leaks

#### Archivos a tocar

| Archivo | Cambio |
|---|---|
| `src/__dev/README.md` | Documentar nueva feature |
| `novavision-docs/runbooks/devportal_user_guide.md` | Sección nueva |
| `novavision-docs/architecture/devportal-design-system.md` | Nuevos componentes |
| `src/__dev/design-system/tokens.js` | Nuevos tokens si aplica |
| `src/__dev/design-system/components.jsx` | Nuevos componentes atómicos si aplica |

---

## 📅 Timeline Estimado

```
Semana 1
├── Lunes-Martes:    PR-1 (Infraestructura) + PR-2 (Schemas Zod) ← en paralelo
├── Miércoles-Jueves: PR-3 (Client Selector + Fetch)
└── Viernes:          Review + merge PR-1, PR-2, PR-3

Semana 2
├── Lunes-Jueves:    PR-4 (Editor Visual) ← PR más grande
└── Viernes:          Review + merge PR-4

Semana 3
├── Lunes-Martes:    PR-5 (IA Autocompletar) + PR-6 (Preview) ← en paralelo
├── Miércoles-Jueves: PR-7 (Canvas de Layout)
└── Viernes:          PR-8 (Polish) + Review final

Total: ~3 semanas (15 días hábiles)
```

---

## ⚠️ Riesgos y Mitigación

| Riesgo | Impacto | Mitigación |
|---|---|---|
| API backend no disponible en dev | Medio | Fallback a datos demo en todos los hooks |
| No hay acceso a API de IA (OpenAI) | Bajo | Sugerencias hardcoded de ejemplo. PR-5 es opcional |
| Componentes del storefront difíciles de importar en sandbox | Alto | Fallback a CSS mockups (como hoy). Mejora progresiva |
| Drag & drop complejo de implementar | Medio | Usar librería madura (`@dnd-kit`). Si bloquea, PR-7 se hace manual |
| Performance con muchas secciones en preview | Bajo | Virtualizar lista, lazy render de previews |

---

## 🔀 Convención de Ramas y Commits

```bash
# Ramas
feature/devportal-section-builder-infra      # PR-1
feature/devportal-section-schemas            # PR-2
feature/devportal-client-selector            # PR-3
feature/devportal-section-editor             # PR-4
feature/devportal-ai-autocomplete            # PR-5
feature/devportal-live-preview               # PR-6
feature/devportal-layout-canvas              # PR-7
feature/devportal-section-builder-polish     # PR-8

# Commits (formato)
[FEAT] devportal: agregar SectionBuilderPage + routing
[FEAT] devportal: schemas Zod para secciones (FAQ, Banner, Carousel, Hero, Testimonials)
[FEAT] devportal: ClientSelector con fetch real + fallback demo
[FEAT] devportal: editor visual de sección con formularios dinámicos
[FEAT] devportal: integración IA autocompletar campos
[FEAT] devportal: preview en tiempo real con componentes del storefront
[FEAT] devportal: canvas de layout con drag & drop
[CHORE] devportal: documentación, polish y tests

# Merge
Todas las ramas → develop (vía PR)
develop → feature/multitenant-storefront (cherry-pick)
develop → feature/onboarding-preview-stable (cherry-pick)
```

---

## 📦 Dependencias npm a evaluar

| Paquete | PR | Propósito | Alternativa |
|---|---|---|---|
| `zod` | PR-2 | Ya instalado en el proyecto | — |
| `@dnd-kit/core` + `@dnd-kit/sortable` | PR-7 | Drag & drop | `react-beautiful-dnd` (deprecated) |
| `openai` (SDK) | PR-5 | Llamadas a API de IA | Fetch directo al endpoint |
| — | — | El resto usa dependencias existentes (framer-motion, react-router, tailwind) | — |

---

## ✅ Checklist Global de Merge

Antes de mergear cada PR:

- [ ] `npm run lint` pasa sin errores
- [ ] `npm run typecheck` pasa sin errores  
- [ ] `npm run build` compila correctamente
- [ ] No se rompen rutas existentes del Dev Portal
- [ ] No se exponen claves/tokens en el código
- [ ] Persistencia en localStorage funciona (reload preserva estado)
- [ ] Funciona en modo offline (graceful degradation)
- [ ] Design system tokens consistentes (dark mode first)

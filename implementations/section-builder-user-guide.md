# Dev Portal — Constructor de Secciones (Section Builder)

> Guía de usuario para la herramienta de construcción de secciones del Dev Portal.

## Acceso

Ruta: `/__dev/sections` (solo disponible en modo desarrollo).  
Shortcut: `⌘7` o `⌥8` desde cualquier página del Dev Portal.

## Tabs

### 🧱 Constructor (wizard de 3 pasos)

| Paso | Nombre | Descripción |
|------|--------|-------------|
| 1 | **Cliente** | Conectarse a un tenant por slug. Se obtienen categorías reales via API. |
| 2 | **Sección** | Elegir el tipo de sección a crear (FAQ, Banner, Carousel, Hero, Testimonios). |
| 3 | **Editor** | Formulario dinámico con validación Zod + live preview CSS a la derecha. |

### 📐 Layout

Vista de todas las secciones creadas. Permite:
- **Drag & drop** para reordenar (HTML5 nativo)
- **Expandir** cada sección para ver mini preview + JSON
- **Duplicar** / **Eliminar** secciones
- **Full-page preview** que renderiza todas las secciones en orden
- **Exportar JSON** descargable con la config completa del layout

## Tipos de sección soportados

| Tipo | Icono | Schema Zod | Campos principales |
|------|-------|------------|-------------------|
| `faq` | ❓ | `faqSchema` | title, items[{question, answer}] |
| `banner` | 🖼️ | `bannerSchema` | title, subtitle, imageUrl, ctaText, ctaLink |
| `carousel` | 🎠 | `carouselSchema` | title, categoryId, limit |
| `hero` | 🦸 | `heroSchema` | headline, subheadline, backgroundImage, ctaText, ctaLink |
| `testimonials` | 💬 | `testimonialsSchema` | title, items[{name, role, text, avatarUrl}] |

## Validación

**Contrato Zod-first:** Nunca se aplican datos que no pasen `safeParse()`.

- Validación en tiempo real conforme se editan los campos
- Badge "✓ Válido" / "Campos incompletos" en el header del formulario
- Errores inline por campo (rojo + mensaje)
- Botón "Guardar en Staging" deshabilitado si hay errores

## AI Autocomplete

Cada campo de texto muestra opcionalmente sugerencias inteligentes:
- Click en "✨ Sugerencias" para toggle
- Pills con textos sugeridos por tipo de sección
- Click en una pill para aplicar el valor al campo
- Estrella (★) para sugerencias de alta confianza (≥ 0.85)

Las sugerencias son locales (sin API externa): basadas en templates por tipo de sección.

## Live Preview

Panel derecho en el Step 3 que muestra cómo se verá la sección:
- **Viewport:** Mobile (375px) / Tablet (768px) / Desktop (1280px)
- **Theme:** Dark 🌙 / Light ☀️ toggle
- **Zoom:** 75% / 100%
- Actualización en <200ms conforme se editan campos

Los previews son mockups CSS (Tailwind) independientes del storefront.

## Persistencia

Todo el estado se persiste automáticamente en `localStorage` (key: `novavision-devportal-state`):
- Secciones creadas (`sectionsList`)
- Cliente seleccionado
- Historial de slugs recientes

## Export JSON

El formato exportado es:

```json
{
  "version": 1,
  "exportedAt": "2025-01-15T10:30:00.000Z",
  "sections": [
    {
      "id": "section-123",
      "sectionType": "faq",
      "version": 1,
      "order": 0,
      "data": { "title": "FAQ", "items": [...] }
    }
  ]
}
```

`SectionConfig` es siempre **JSON-serializable** con `version: 1`.

## Arquitectura de archivos

```
src/__dev/
├── pages/SectionBuilderPage/
│   ├── index.jsx                # Wizard principal + tabs
│   └── LayoutCanvas.jsx         # Canvas de layout con D&D
├── components/
│   ├── ClientSelector.jsx       # Selector de tenant por slug
│   ├── SectionFormRenderer.jsx  # Formulario dinámico por tipo
│   ├── SectionPreview.jsx       # Preview CSS con controles viewport
│   └── SuggestionChips.jsx      # Pills de sugerencias AI
├── hooks/
│   ├── useTenantData.ts         # Fetch categorías + cache + offline
│   └── useAiSuggestions.ts      # Sugerencias locales por tipo/campo
├── schemas/
│   ├── faqSchema.ts
│   ├── bannerSchema.ts
│   ├── carouselSchema.ts
│   ├── heroSchema.ts
│   ├── testimonialsSchema.ts
│   ├── index.ts                 # Registry SECTION_TYPES + helpers
│   └── __tests__/schemas.test.ts
└── context/DevPortalContext.tsx  # State management (SectionBuilder slice)
```

## API

El Section Builder usa el header `x-tenant-slug` (no `x-client-id`):
- `GET /categories` — obtiene categorías del tenant conectado
- Base URL: `VITE_BACKEND_API_URL` > `VITE_BACKEND_URL` > `http://localhost:3000`
- Offline: fallback a localStorage cache (5 min TTL en memoria)

## PRs del feature

| PR | Rama | Descripción |
|----|------|-------------|
| PR-1 | `feature/devportal-section-builder-infra` | Wizard shell, routing, context |
| PR-2 | `feature/devportal-section-schemas` | Schemas Zod + registry + 28 tests |
| PR-3 | `feature/devportal-client-selector` | ClientSelector + useTenantData |
| PR-4 | `feature/devportal-section-form-renderer` | Formularios dinámicos + Zod validation |
| PR-5 | `feature/devportal-ai-autocomplete` | AI suggestions hook + SuggestionChips |
| PR-6 | `feature/devportal-live-preview` | Preview CSS con viewport/theme/zoom |
| PR-7 | `feature/devportal-layout-canvas` | Drag & drop + full-page preview + export |
| PR-8 | `feature/devportal-section-builder-polish` | Documentación + polish |

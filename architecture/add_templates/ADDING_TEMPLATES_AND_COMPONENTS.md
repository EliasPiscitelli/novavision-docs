# 📚 Guía: Cómo Agregar un Nuevo Template y Componentes en NovaVision

> **Última actualización:** 2026-02-21  
> **Basado en código real** (validado contra codebase, no docs anteriores)  
> **Autor:** Revisión completa vs código actual  
> **Versión:** 2.0 — Incluye TODOS los archivos de configuración necesarios (8 pasos)

---

## ⚠️ Estado de la documentación previa

| Documento                             | Estado                   | Problema                                                                                                                                                            |
| ------------------------------------- | ------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `store_render_flow.md`                | ⚠️ Parcialmente obsoleto | Dice que HomeRouter tiene su propio ThemeProvider — **ya no existe** desde `NOVAVISION-THEME-FIX-2026-02-07`. El tema ahora se resuelve completamente en `App.jsx`. |
| `TAILWIND_TEMPLATE_COMPATIBILITY.md`  | ✅ Vigente               | El contrato de 28 variables CSS `--nv-*` sigue siendo correcto.                                                                                                     |
| `TEMPLATE_GENERATION_PROMPT_GUIDE.md` | ✅ Vigente               | Las reglas de CSS vars y prompts de IA son correctas.                                                                                                               |

---

## 1. Arquitectura actual del sistema de templates

```
App.jsx
├── useEffectiveTheme()              ← Resuelve el tema (templateKey + paletteKey)
├── useThemeVars(theme)              ← Aplica CSS vars al :root
├── paletteVars override (useEffect) ← API vars sobreescriben todo (fuente de verdad)
├── ThemeProvider (styled-components)
│   ├── GlobalStyle
│   ├── AnnouncementBar
│   ├── DynamicHeader  ←──────────── GLOBAL, fuera del template
│   └── AppRoutes
│       └── HomeRouter
│           └── SelectedHome   ←─── template elegido (NO tiene su propio ThemeProvider)
```

> [!IMPORTANT]
> **No hay un segundo ThemeProvider en HomeRouter** (fue eliminado en Feb 2026 por flickering). El theme se inyecta UNA SOLA VEZ en `App.jsx` vía `useThemeVars` + el override de `paletteVars` desde la API.

---

## 2. Flujo de datos: de la API al template

```
GET /home/data
    └── normalizeHomeData()
            └── homeData {
                  products[], services[], banners{},
                  faqs[], logo, contactInfo[], socialLinks,
                  config: {
                    templateKey: "template_1",   ← elige qué template renderizar
                    paletteKey: "starter_default",
                    paletteVars: { --nv-primary: "#2563EB", ... },  ← 27 CSS vars
                    sections: [],               ← si hay secciones → modo dinámico
                    identity_config: { banners: { popup, top } }
                  }
                }
            └── HomeRouter recibe homeData
                    └── TEMPLATES[templateKey] → componente Home del template
```

---

## 3. Sistema de Templates: estructura de archivos

```
src/templates/
├── manifest.js               ← Catálogo de templates (metadatos, features, status)
├── first/
│   ├── components/           ← Componentes PRIVADOS del template
│   │   ├── Header/           ← ⚠️ NO se usa (Header global en App.jsx)
│   │   ├── Footer/
│   │   ├── ProductCard/
│   │   ├── ProductCarousel/
│   │   ├── Services/
│   │   ├── CollectionsSection/
│   │   ├── ContactSection/
│   │   ├── FAQSection/
│   │   └── ToTopButton/
│   └── pages/
│       └── HomePageFirst/
│           └── index.jsx     ← Entry point del template
├── second/   (estructura similar)
├── third/    (estructura similar)
├── fourth/   (estructura similar)
└── fifth/    (estructura similar)

src/registry/
└── templatesMap.ts           ← Mapeo ID → componente (importado por HomeRouter)
```

---

## 4. Cómo agregar un nuevo template (paso a paso)

### Paso 1: Crear la carpeta del template

```bash
mkdir -p apps/web/src/templates/sixth/pages/HomePageSixth
mkdir -p apps/web/src/templates/sixth/components
```

### Paso 2: Crear el componente Home del template

`apps/web/src/templates/sixth/pages/HomePageSixth/index.jsx`:

```jsx
import { SectionRenderer } from "../../../../components/SectionRenderer";
import { DEMO_HOME_DATA } from "../../../../sections/demoData";
// ✅ NO importar Header — se renderiza en App.jsx globalmente
// ✅ NO crear ThemeProvider aquí — el tema ya está inyectado en :root

function HomePageSixth({ homeData: rawHomeData }) {
  // Siempre usar DEMO_HOME_DATA como fallback
  const homeData = rawHomeData || DEMO_HOME_DATA;

  const { products, services, faqs, contactInfo, logo, banners } = homeData;

  const sections = homeData?.config?.sections || [];

  // MODO DINÁMICO: si hay secciones configuradas en Admin
  if (sections.length > 0) {
    return (
      <>
        {sections.map((section) => (
          <SectionRenderer
            key={section.id}
            section={section}
            data={{ products, services, faqs, contactInfo }}
          />
        ))}
      </>
    );
  }

  // MODO ESTÁTICO: layout fijo del template
  return (
    <>
      {/* Tus secciones hardcodeadas aquí */}
      {/* Usar SOLO variables --nv-* para colores — ver sección 7 */}
    </>
  );
}

export default HomePageSixth;
```

### Paso 3: Registrar en `templatesMap.ts`

`apps/web/src/registry/templatesMap.ts`:

```typescript
import HomeTemplate1 from "../templates/first/pages/HomePageFirst";
import HomeTemplate2 from "../templates/second/pages/HomePage";
import HomeTemplate3 from "../templates/third/pages/HomePageThird";
import HomeTemplate4 from "../templates/fourth/pages/Home";
import HomeTemplate5 from "../templates/fifth/pages/Home";
import HomeTemplate6 from "../templates/sixth/pages/HomePageSixth"; // ← AGREGAR

export const TEMPLATES = {
  // Canonical keys (matches DB)
  template_1: HomeTemplate1,
  template_2: HomeTemplate2,
  template_3: HomeTemplate3,
  template_4: HomeTemplate4,
  template_5: HomeTemplate5,
  template_6: HomeTemplate6, // ← AGREGAR

  // Legacy/Folder keys
  first: HomeTemplate1,
  second: HomeTemplate2,
  third: HomeTemplate3,
  fourth: HomeTemplate4,
  fifth: HomeTemplate5,
  sixth: HomeTemplate6, // ← AGREGAR
};
```

> [!IMPORTANT]
> Los **canonical keys** (`template_1`, `template_2`, etc.) son los que se guardan en la base de datos. Los **folder keys** (`first`, `second`, etc.) son aliases de retrocompatibilidad. Siempre agregar AMBOS.

### Paso 4: Registrar en `manifest.js`

`apps/web/src/templates/manifest.js`:

```javascript
export const TEMPLATES = {
  // ... templates existentes ...

  sixth: {
    id: "sixth",
    name: "Mi Nuevo Template",
    description: "Descripción corta del estilo del template",
    status: "beta", // 'stable' | 'beta' | 'deprecated'
    preview: "/demo/templates/sixth-preview.png",
    features: [
      "banner-carousel",
      "product-grid",
      "dynamic-sections",
      // otros features que soporta
    ],
    entryPage: "HomePageSixth",
    supportsSections: true, // true si implementa SectionRenderer
  },
};
```

### Paso 5: Registrar en `resolveEffectiveTheme.ts` (**OBLIGATORIO**)

`apps/web/src/theme/resolveEffectiveTheme.ts` — en la función `normalizeTemplateKey`, agregar al `templateMap`:

```typescript
const templateMap: Record<string, string> = {
  // ...existing...
  template_8: 'eighth',   // ← AGREGAR canonical key
  // ...existing aliases...
  eighth: 'eighth',        // ← AGREGAR folder key
};
```

> [!IMPORTANT]
> Sin esto, el theme system NO reconoce el template y usa el fallback `'first'`. La paleta se aplica incorrectamente.

### Paso 6: Registrar en `DynamicHeader.jsx` (**OBLIGATORIO**)

`apps/web/src/components/DynamicHeader.jsx` — dos cambios:

**a) En `TEMPLATE_HEADER_MAP`:**
```javascript
const TEMPLATE_HEADER_MAP = {
  // ...existing...
  template_8: HeaderFifth,  // ← AGREGAR (usar HeaderFifth como fallback hasta crear uno propio)
  eighth: HeaderFifth,      // ← AGREGAR
};
```

**b) En `normalizeTemplateKey`:**
```javascript
const valid = [
  "template_1", "template_2", ..., "template_8",  // ← AGREGAR
  "first", "second", ..., "eighth",                // ← AGREGAR
];
```

> [!IMPORTANT]
> Sin esto, el header NO se renderiza para el template nuevo. Se usa el fallback (Fifth) pero el templateKey no se reconoce como válido.

### Paso 7: Registrar en `TemplatePreviewer.jsx` (**OBLIGATORIO para dev portal**)

`apps/web/src/__dev/pages/TemplatePreviewer.jsx` — en `CANONICAL_TO_ALIAS`:

```javascript
const CANONICAL_TO_ALIAS = {
  // ...existing...
  template_8: 'eighth',  // ← AGREGAR
};
```

> Sin esto, el Dev Portal no muestra el template en el selector, ni resuelve la paleta por defecto.

### Paso 8: (Opcional) Paleta personalizada en `palettes.ts`

Si el template necesita colores propios, crear una paleta en `apps/web/src/theme/palettes.ts`:

```typescript
export const eighth_glow: PaletteTokens = {
  bg: '#FAFBFF',
  surface: '#FFFFFF',
  navbar_bg: '#FFFFFF',
  footer_bg: '#0F172A',
  text: '#1E293B',
  text_muted: '#64748B',
  primary: '#6366F1',
  primary_hover: '#4F46E5',
  primary_fg: '#FFFFFF',
  accent: '#F59E0B',
  accent_fg: '#FFFFFF',
  border: '#E2E8F0',
  // ...etc
};
```

Y registrarla en `PALETTES`:
```typescript
export const PALETTES = {
  // ...existing...
  eighth_glow,
};
```

Luego en `manifest.js` agregar:
```javascript
recommendedPalettes: ['eighth_glow'],
```

### Paso 9: (Opcional) Base de datos

Verificar si hay un enum o constraint en la tabla `accounts` que limite `template_id`. Si existe:
```sql
ALTER TYPE template_id_enum ADD VALUE 'template_8';
```

### Paso 10: Datos demo y preview image

- **Demo data:** verificar que `DEMO_HOME_DATA` en `src/sections/demoData.ts` tenga suficientes datos para todas las secciones del template.
- **Preview:** agregar `apps/web/public/demo/templates/eighth-preview.png` para el selector en Admin.

### ⚠️ Checklist de registro completo

Antes de hacer PR con un template nuevo, verificar que está registrado en **TODOS** estos archivos:

| # | Archivo | Cambio | ¿Obligatorio? |
|---|---------|--------|:-:|
| 1 | `src/templates/{nombre}/pages/` | Crear carpeta + entry point | ✅ |
| 2 | `src/registry/templatesMap.ts` | Import + canonical key + folder key | ✅ |
| 3 | `src/templates/manifest.js` | Config completa (id, name, status, features, entryPage) | ✅ |
| 4 | `src/theme/resolveEffectiveTheme.ts` | `template_N` + `{nombre}` en `templateMap` | ✅ |
| 5 | `src/components/DynamicHeader.jsx` | TEMPLATE_HEADER_MAP + normalizeTemplateKey | ✅ |
| 6 | `src/__dev/pages/TemplatePreviewer.jsx` | CANONICAL_TO_ALIAS | ✅ |
| 7 | `src/theme/palettes.ts` | Paleta personalizada (si aplica) | Opcional |
| 8 | Base de datos | Enum constraint (si existe) | Condicional |
| 9 | `public/demo/templates/` | Preview image | Recomendado |

---

## 5. Cómo agregar un nuevo componente para tiendas

### Estructura de un componente de template

Cada componente vive en su propia carpeta dentro de `templates/<nombre>/components/`:

```
templates/sixth/components/
└── MiNuevoComponente/
    ├── index.jsx       ← componente principal
    ├── style.jsx       ← styled-components (solo para layout estructural)
    └── MiNuevoComponente.test.jsx  ← tests (opcional)
```

### Reglas de desarrollo de componentes

#### ✅ Obligatorio — CSS Variables

```jsx
// ✅ CORRECTO — colores siempre via CSS vars
<div className="bg-nv-surface border border-nv-border rounded-[var(--nv-radius)]">
  <h2 className="text-nv-text">Título</h2>
  <p className="text-[var(--nv-text-muted)]">Subtítulo</p>
  <button className="bg-nv-primary text-[var(--nv-primary-fg)]
                     hover:bg-[var(--nv-primary-hover)]
                     focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none
                     rounded-[var(--nv-radius)] px-4 py-2 transition-colors">
    Acción
  </button>
</div>

// ❌ PROHIBIDO — colores hardcodeados
<div className="bg-white text-gray-900">
<button className="bg-blue-500 text-white">
<div style={{ color: '#333' }}>
```

#### ✅ Obligatorio — Dark mode automático

```jsx
// ✅ Correcto — no usar dark: prefix de Tailwind
<div className="bg-nv-background text-nv-text">  {/* funciona en light Y dark */}

// ❌ Incorrecto — el dark mode es automático via CSS vars
<div className="bg-white dark:bg-gray-900">
```

#### ✅ Obligatorio — Props contract

Todos los componentes deben recibir datos via props desde el Home del template (no hacer fetch propio):

```jsx
// ProductCard.jsx — ejemplo de props contract
export function ProductCard({ product }) {
  // product = { id, name, originalPrice, discountedPrice, imageUrl[], categories[] }
  // Ver demoData.ts para el schema completo de product
}

// En HomePageSixth
<ProductCard product={product} />;
```

#### ✅ Obligatorio — Fallback con demo data

Si el componente recibe datos que pueden ser `null` o `undefined`:

```jsx
// ✅ Siempre manejar el caso vacío
function Services({ servicesList = [] }) {
  if (!servicesList.length) return null;
  // render...
}
```

---

## 6. Schema de datos: qué viene de la API

### Producto completo

```typescript
interface Product {
  id: string;
  name: string;
  description: string;
  sku: string | null;
  originalPrice: number; // precio sin descuento
  discountedPrice: number; // 0 si no tiene descuento
  discountPercentage: number;
  available: boolean;
  quantity: number;
  sizes: string; // "L, XL, S" (string separado por comas)
  colors: string; // "Rojo, Azul" (string separado por comas)
  material: string;
  featured: boolean;
  bestSell: boolean;
  tags: string | null;
  categories: Array<{ id: string; name: string }>;
  imageUrl: Array<{ url: string; order: number }>; // array de objetos con url
  filters: string | null;
  client_id: string;
}
```

> [!WARNING]
> Los precios vienen en formato numérico (pesos ARS). El campo `imageUrl` es un **array de objetos** `{ url, order }`, no un array de strings.

### Servicio (benefit cards)

```typescript
interface Service {
  id: string;
  title: string;
  description: string;
  number: number; // orden de display
  image_url: string;
  file_path: string;
  client_id: string;
}
```

### Banner

```typescript
interface Banner {
  id: string;
  url: string; // URL de la imagen
  file_path: string;
  type: "desktop" | "mobile";
  link: string | null; // URL de destino al hacer click
  order: number;
  client_id: string;
}

interface BannersData {
  desktop: Banner[];
  mobile: Banner[];
}
```

### Logo

```typescript
interface Logo {
  id: string;
  url: string;
  show_logo: boolean; // ← siempre verificar antes de renderizar
  file_path: string;
  client_id: string;
}
```

### FAQ

```typescript
interface FAQ {
  id: string;
  question: string;
  answer: string;
  number: number; // orden de display
  client_id: string;
}
```

### ContactInfo

```typescript
interface ContactInfo {
  id: string;
  titleinfo: string; // ← typo intencional en el modelo de DB
  description: string;
  number: number; // orden de display
  phone?: string;
  email?: string;
  client_id: string;
}
```

### SocialLinks

```typescript
interface SocialLinks {
  id: string;
  whatsApp: string; // número sin + ni espacios (ej: "5491123456789")
  wspText: string; // mensaje predeterminado
  instagram: string; // URL completa
  facebook: string; // URL completa
  client_id: string;
}
```

---

## 7. Sistema de temas: variables CSS disponibles

### Contrato canónico (28 tokens — producidos por API)

| Variable             | Uso correcto                  | Tailwind utility                     |
| -------------------- | ----------------------------- | ------------------------------------ |
| `--nv-bg`            | Fondo de página               | `bg-nv-background`                   |
| `--nv-surface`       | Fondo de cards/panels         | `bg-nv-surface`                      |
| `--nv-card-bg`       | Alias de surface para cards   | `bg-nv-surface`                      |
| `--nv-navbar-bg`     | Fondo del header              | `bg-[var(--nv-navbar-bg)]`           |
| `--nv-footer-bg`     | Fondo del footer              | `bg-[var(--nv-footer-bg)]`           |
| `--nv-text`          | Texto principal               | `text-nv-text`                       |
| `--nv-text-muted`    | Texto secundario / subtítulos | `text-[var(--nv-text-muted)]`        |
| `--nv-primary`       | Color de marca principal      | `bg-nv-primary`, `text-nv-primary`   |
| `--nv-primary-hover` | Primary en hover              | `hover:bg-[var(--nv-primary-hover)]` |
| `--nv-primary-fg`    | Texto sobre botones primary   | `text-[var(--nv-primary-fg)]`        |
| `--nv-accent`        | Color de acento               | `bg-nv-accent`                       |
| `--nv-accent-fg`     | Texto sobre accent            | `text-[var(--nv-accent-fg)]`         |
| `--nv-border`        | Borde estándar                | `border-nv-border`                   |
| `--nv-shadow`        | Sombra de cards               | `shadow-[var(--nv-shadow)]`          |
| `--nv-ring`          | Anillo de focus               | `focus:ring-[var(--nv-ring)]`        |
| `--nv-link`          | Color de links                | `text-[var(--nv-link)]`              |
| `--nv-link-hover`    | Link en hover                 | `hover:text-[var(--nv-link-hover)]`  |
| `--nv-input-bg`      | Fondo de inputs               | `bg-[var(--nv-input-bg)]`            |
| `--nv-input-text`    | Texto de inputs               | `text-[var(--nv-input-text)]`        |
| `--nv-input-border`  | Borde de inputs               | `border-[var(--nv-input-border)]`    |
| `--nv-success`       | Estado éxito                  | `text-nv-success`, `bg-nv-success`   |
| `--nv-warning`       | Estado advertencia            |                                      |
| `--nv-error`         | Estado error                  |                                      |
| `--nv-info`          | Estado informativo            |                                      |
| `--nv-muted`         | Hover de íconos (rgba fondo)  | `hover:bg-[var(--nv-muted)]`         |
| `--nv-hover`         | Alias de primary              |                                      |
| `--nv-radius`        | Border radius base            | `rounded-[var(--nv-radius)]`         |
| `--nv-font`          | Font family                   | (inyectado en body)                  |

### Variables PROHIBIDAS (no existen en producción)

```css
/* ❌ No usar — generan render roto */
--nv-secondary      → usar --nv-accent
--nv-secondary-fg   → usar --nv-accent-fg
--nv-surface-hover  → usar hover:opacity-90
--nv-border-focus   → usar --nv-ring
--nv-foreground     → usar --nv-text

/* ⚠️ Trampa semántica: --nv-muted es rgba de FONDO, NO color de texto */
text-[var(--nv-muted)]  /* ❌ texto invisible */
text-[var(--nv-text-muted)]  /* ✅ correcto para texto secundario */
```

### Cómo se resuelve el tema (flujo actual)

```
homeData.config.paletteKey  →  useEffectiveTheme()  →  useThemeVars()  →  :root CSS vars
                                                      ↑
homeData.config.paletteVars  →  override directo en :root  (API es la fuente de verdad)
```

El Admin puede configurar `paletteKey` (paleta predefinida) O `themeConfig` (override manual de colores). La API resuelve cuál aplicar y lo envía como `paletteVars` (objeto `--nv-*: value`).

---

## 8. Compatibilidad con el onboarding

Los templates también se muestran durante el onboarding (preview del template que el cliente está eligiendo). Para que funcione correctamente:

### El template debe:

1. **Funcionar con `DEMO_HOME_DATA`** — el onboarding no tiene datos reales todavía
2. **No depender de datos del tenant** — el preview es anónimo
3. **Ser responsive desde 375px** — el preview se muestra en modal chico
4. **No hacer fetch por su cuenta** — recibe todo via props

### Verificación

```jsx
// En HomePageSixth/index.jsx
const homeData = rawHomeData || DEMO_HOME_DATA; // ← Este fallback es obligatorio
```

### Preview en onboarding

El onboarding usa el mismo `HomeRouter` con un `homeData` mínimo que tiene solo `config.templateKey`. El template debe verse bien incluso con datos mínimos.

---

## 9. Componentes compartidos entre templates

Algunos componentes están en `src/components/` (global) y pueden usarse desde cualquier template:

| Componente        | Ruta                              | Propósito                             |
| ----------------- | --------------------------------- | ------------------------------------- |
| `SectionRenderer` | `src/components/SectionRenderer/` | Modo dinámico de secciones            |
| `NVImage`         | `src/components/NVImage/`         | Imágenes con fallback a `/broken.png` |
| `PopupBanner`     | `src/components/Banners/`         | Popup configurado en Admin            |
| `AnnouncementBar` | `src/components/AnnouncementBar/` | Barra superior de anuncios            |
| `DynamicHeader`   | `src/components/DynamicHeader/`   | Header global (App.jsx)               |
| `SocialIcons`     | `src/components/SocialIcons/`     | Íconos flotantes de redes             |
| `ThemeDebugPanel` | `src/components/ThemeDebugPanel/` | Solo dev — panel de debug de tema     |

> [!NOTE]
> Si un componente es reutilizable entre templates, colocarlo en `src/components/`. Si es específico de un template, en `src/templates/<nombre>/components/`.

---

## 10. Checklist de validación antes de hacer PR

### Template (registro en el sistema)

- [ ] Carpeta creada en `src/templates/{nombre}/`
- [ ] Entry point en `pages/HomePage{Nombre}/index.jsx`
- [ ] Registrado en `src/registry/templatesMap.ts` (canonical + folder key)
- [ ] Registrado en `src/templates/manifest.js` con status y features
- [ ] Registrado en `src/theme/resolveEffectiveTheme.ts` (template_N + {nombre} en templateMap)
- [ ] Registrado en `src/components/DynamicHeader.jsx` (TEMPLATE_HEADER_MAP + normalizeTemplateKey)
- [ ] Registrado en `src/__dev/pages/TemplatePreviewer.jsx` (CANONICAL_TO_ALIAS)
- [ ] Fallback a `DEMO_HOME_DATA` implementado
- [ ] Modo dinámico (`SectionRenderer`) implementado si `supportsSections: true`
- [ ] Header NO importado (está en App.jsx via DynamicHeader)
- [ ] No crea su propio ThemeProvider
- [ ] No importa react-router-dom (ni Link, ni useNavigate, ni useLocation)
- [ ] Evaluado en DB si hay enum de `template_id`

### Componentes

- [ ] Todos los colores usan `var(--nv-*)` o clases Tailwind `nv-*`
- [ ] Cero colores hardcodeados (`#hex`, `rgb()`, `bg-blue-500`)
- [ ] No usa `dark:` prefix de Tailwind
- [ ] No usa `--nv-secondary`, `--nv-surface-hover`, `--nv-border-focus`
- [ ] Texto secundario usa `--nv-text-muted` (NO `--nv-muted`)
- [ ] Botones primarios: `bg-nv-primary text-[var(--nv-primary-fg)] hover:bg-[var(--nv-primary-hover)]`
- [ ] Focus rings: `focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none`
- [ ] Inputs: `bg-[var(--nv-input-bg)] text-[var(--nv-input-text)] border-[var(--nv-input-border)]`
- [ ] Responsive: funciona en 375px, 768px, 1024px, 1440px
- [ ] Props con fallback para datos vacíos o nulos
- [ ] No hace fetch directo a la API

### Compatibilidad con onboarding

- [ ] Se ve correctamente con `DEMO_HOME_DATA`
- [ ] Se ve correctamente con homeData mínimo `{ config: { templateKey: 'sixth' } }`

---

## 11. Archivos de referencia clave

| Archivo                                                                                                                                                                   | Propósito                               |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------- |
| [`src/templates/manifest.js`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/templates/manifest.js)                                       | Catálogo de templates                   |
| [`src/registry/templatesMap.ts`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/registry/templatesMap.ts)                                 | Mapeo ID → componente                   |
| [`src/theme/resolveEffectiveTheme.ts`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/theme/resolveEffectiveTheme.ts)                     | Normalización de template key + theme   |
| [`src/theme/palettes.ts`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/theme/palettes.ts)                                               | Paletas de colores + CSS vars generator |
| [`src/components/DynamicHeader.jsx`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/components/DynamicHeader.jsx)                         | Header global por template              |
| [`src/components/SectionRenderer.tsx`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/components/SectionRenderer.tsx)                     | Modo dinámico de secciones              |
| [`src/__dev/pages/TemplatePreviewer.jsx`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/__dev/pages/TemplatePreviewer.jsx)               | Dev portal para preview de templates    |
| [`src/routes/HomeRouter.jsx`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/routes/HomeRouter.jsx)                                       | Selección y render del template         |
| [`src/App.jsx`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/App.jsx)                                                                   | ThemeProvider global, useEffectiveTheme |
| [`src/sections/demoData.ts`](file:///Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web/src/sections/demoData.ts)                                         | Datos demo (fixture completo)           |
| [`architecture/TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md`](file:///Users/eliaspiscitelli/Documents/NovaVision/novavision-docs/architecture/TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md) | Prompt para generar templates con IA |
| [`architecture/TAILWIND_TEMPLATE_COMPATIBILITY.md`](file:///Users/eliaspiscitelli/Documents/NovaVision/novavision-docs/architecture/TAILWIND_TEMPLATE_COMPATIBILITY.md)   | Contrato de 28 CSS vars                 |

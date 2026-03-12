# Guia: Como Agregar un Nuevo Template y Componentes en NovaVision

> **Ultima actualizacion:** 2026-03-06  
> **Basado en codigo real** (validado contra `apps/admin`, `apps/api` y `apps/web`)  
> **Autor:** Revision y actualizacion de arquitectura lazy + preview  
> **Version:** 3.0

---

## Estado de la documentacion previa

| Documento | Estado | Nota |
| --- | --- | --- |
| `store_render_flow.md` | Parcialmente obsoleto | Sigue mencionando un `ThemeProvider` en `HomeRouter` que ya no existe. |
| `ADDING_TEMPLATES_AND_COMPONENTS.md` | Obsoleto | Describia `templatesMap.ts` sin lazy loading y no contemplaba `sectionComponentTemplates/*`. |
| `TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md` | Parcial | La parte creativa sigue sirviendo, pero el registro tecnico post-generacion quedo viejo. |

---

## 1. Arquitectura actual del sistema de templates

```text
App.jsx
|- useFetchHomeDataWithOptions()
|- useEffectiveTheme()
|- useThemeVars(theme)
|- ThemeProvider (styled-components)
|  |- GlobalStyle
|  |- AnnouncementBar
|  |- DynamicHeader        <- global, fuera del template
|  \- AppRoutes
|     \- HomeRouter
|        \- Suspense
|           \- TEMPLATES[templateKey]
```

Puntos clave:

- No hay un segundo `ThemeProvider` en `HomeRouter`.
- El template publicado se elige con `homeData.config.templateKey`.
- `templatesMap.ts` ahora usa `lazy(() => import(...))` para cada Home.
- El render dinamico de secciones pasa por `SectionRenderer` -> `sectionComponents.tsx` -> `sectionComponentTemplates/*`.

---

## 2. Flujo real: onboarding -> preview -> publicacion -> render

### 2.1 Onboarding / builder

```text
Step4TemplateSelector.tsx
|- getTemplates()        -> GET /templates
|- getPalettes()         -> GET /onboarding/palettes
|- updatePreferences()   -> PATCH /onboarding/preferences
|- PreviewFrame          -> /preview + postMessage(payload)
```

El builder trabaja con estas piezas:

- `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
- `apps/admin/src/services/builder/api.ts`
- `apps/admin/src/services/builder/designSystem.ts`

El payload que maneja el builder incluye:

- `templateKey`
- `paletteKey`
- `paletteVars`
- `themeOverride`
- `designConfig.sections[]`
- `seed` de preview

### 2.2 Persistencia y sync en API

```text
PATCH /onboarding/preferences
    -> OnboardingService.updatePreferences()
    -> nv_onboarding.selected_template_key
    -> nv_onboarding.selected_palette_key
    -> nv_onboarding.selected_theme_override
    -> sync a backend client_home_settings si el cliente ya esta provisionado
```

Archivos involucrados:

- `apps/api/src/onboarding/onboarding.controller.ts`
- `apps/api/src/onboarding/onboarding.service.ts`
- `apps/api/src/home/home-settings.service.ts`
- `apps/api/src/home/home.service.ts`

### 2.3 Preview del builder

```text
Admin Builder
    -> PreviewFrame
    -> /preview
    -> PreviewHost
    -> SectionRenderer
    -> sectionComponents.tsx
```

Importante:

- El preview **no** usa `GET /home/data` para renderizar la estructura que el usuario esta armando.
- `apps/web/src/pages/PreviewHost/index.tsx` recibe todo por `postMessage`.
- El preview usa seed demo o seed del builder para productos, banners, FAQ y contacto.

### 2.4 Tienda publicada

```text
App.jsx
    -> GET /home/data
    -> normalizeHomeData()
    -> HomeRouter
    -> TEMPLATES[config.templateKey]
    -> Home del template
       -> sections.map(SectionRenderer) o layout estatico
```

La tienda publicada si depende de:

- `apps/api/src/home/home.controller.ts`
- `apps/api/src/home/home.service.ts`
- `apps/api/src/home/home-settings.service.ts`

Y el fallback real server-side hoy es:

1. `client_home_settings.template_key`
2. `clients.template_id`
3. `template_1`

---

## 3. Contrato de datos para el template publicado

```text
GET /home/data
    -> response.data
       -> products
       -> services
       -> banners
       -> faqs
       -> logo
       -> contactInfo
       -> socialLinks
       -> storeName
       -> merchantLegal
       -> config
          -> templateKey
          -> paletteKey
          -> paletteVars
          -> identity_config
          -> themeConfig
          -> sections
```

Para el Home del template, lo mas importante es:

- `homeData.config.templateKey`
- `homeData.config.sections`
- `homeData.config.paletteVars`
- `homeData.products`
- `homeData.services`
- `homeData.faqs`
- `homeData.contactInfo`
- `homeData.banners`
- `homeData.logo`

---

## 4. Estructura actual de archivos

```text
apps/web/src/templates/
|- first/
|- second/
|- third/
|- fourth/
|- fifth/
|- sixth/
|- seventh/
\- eighth/

apps/web/src/registry/
|- templatesMap.ts
|- sectionComponents.tsx
\- sectionComponentTemplates/
   |- first.tsx
   |- second.tsx
   |- third.tsx
   |- fourth.tsx
   |- fifth.tsx
   |- sixth.tsx
   |- seventh.tsx
   \- eighth.tsx
```

---

## 5. Como agregar un nuevo template Home

### Paso 1: crear la carpeta del template

```bash
mkdir -p apps/web/src/templates/ninth/pages/HomePageNinth
mkdir -p apps/web/src/templates/ninth/components
```

### Paso 2: crear el componente Home

Ejemplo base:

```jsx
import { SectionRenderer } from '../../../../components/SectionRenderer';
import { DEMO_HOME_DATA } from '../../../../sections/demoData';

function HomePageNinth({ homeData: rawHomeData }) {
  const homeData = rawHomeData || DEMO_HOME_DATA;

  const {
    products,
    services,
    faqs,
    contactInfo,
    logo,
    banners,
    socialLinks,
  } = homeData;

  const sections = homeData?.config?.sections || [];

  if (sections.length > 0) {
    return (
      <>
        {sections.map((section) => (
          <SectionRenderer
            key={section.id}
            section={section}
            data={{
              products,
              services,
              faqs,
              contactInfo,
              logo,
              banners,
              socialLinks,
            }}
          />
        ))}
      </>
    );
  }

  return (
    <>
      {/* Layout estatico del template */}
    </>
  );
}

export default HomePageNinth;
```

Reglas:

- No importar el header publico aca.
- No crear un `ThemeProvider` propio.
- Soportar ambos modos: dinamico y estatico.

### Paso 3: registrar en `templatesMap.ts` con lazy loading

Ejemplo:

```ts
import { lazy } from 'react';

const HomeTemplate9 = lazy(() => import('../templates/ninth/pages/HomePageNinth'));

export const TEMPLATES = {
  ...,
  template_9: HomeTemplate9,
};
```

Importante:

- Hoy `HomeRouter.jsx` consume claves canonicas `template_1` ... `template_8`.
- Si agregas un `template_9`, asegurate de mantener la convencion canonica desde API y theme.

### Paso 4: registrar en la normalizacion de theme

Actualizar `apps/web/src/theme/resolveEffectiveTheme.ts` para que el template nuevo no caiga en fallback incorrecto.

Ejemplo:

```ts
const templateMap = {
  ...,
  template_9: 'ninth',
  ninth: 'ninth',
};
```

### Paso 5: registrar header si el template necesita variante propia

Si el template requiere header visual propio, actualizar `apps/web/src/components/DynamicHeader.jsx`.

Si no, podes dejarlo usando el fallback global existente.

### Paso 6: registrar el template en tooling auxiliar

Revisar, segun aplique:

- `apps/web/src/templates/manifest.js`
- `apps/web/src/__dev/pages/TemplatePreviewer.jsx`
- assets preview en `apps/web/public/demo/templates/`

---

## 6. Como agregar componentes para secciones dinamicas

Si el builder va a emitir `componentKey` nuevos, hay que registrar toda la cadena runtime.

### Paso 1: exponer el componente en `sectionComponentTemplates/*`

Ejemplo:

```tsx
// apps/web/src/registry/sectionComponentTemplates/ninth.tsx
export { default as HeroNinth } from '../../templates/ninth/components/Hero';
export { default as FooterNinth } from '../../templates/ninth/components/Footer';
```

### Paso 2: registrar loader y exports en `sectionComponents.tsx`

Ejemplo:

```tsx
const ninthTemplateLoader = () => import('./sectionComponentTemplates/ninth');
const HeroNinth = lazyTemplateExport(ninthTemplateLoader, 'HeroNinth');

export const SECTION_COMPONENTS = {
  ...,
  'hero.ninth': HeroNinth,
};
```

### Paso 3: asegurar consistencia con el builder

Los `componentKey` que el builder genera tienen que existir en:

- `apps/admin/src/services/builder/designSystem.ts`
- o en el `SECTION_CATALOG` compartido que consume el admin
- y en el runtime registry del web (`sectionComponents.tsx`)

Si falta alguno de esos pasos, el preview o la tienda publicada van a renderizar `null` o caer en fallback.

### Paso 4: registrar en el VARIANT_REGISTRY del API

Desde Fase 5 del plan de Store Design, el backend valida `component_key` contra un **VARIANT_REGISTRY** server-side. Si un nuevo `componentKey` no está en ese registro, el API lo rechazará.

Archivo: `apps/api/src/home/registry/sections.ts`

El registro tiene esta estructura:

```ts
export const VARIANT_REGISTRY: Record<string, VariantDef> = {
  'hero.first':     { type: 'hero', displayName: 'Hero – First',     planMin: 'starter' },
  'hero.ninth':     { type: 'hero', displayName: 'Hero – Ninth',     planMin: 'enterprise' },
  // ... 68 entradas total
};
```

Cada entrada define:
- **`type`**: a qué tipo de sección pertenece (debe coincidir con el `type` que se envía en el DTO)
- **`displayName`**: nombre legible para UI
- **`planMin`**: plan mínimo requerido (`starter`, `growth`, `enterprise`)

Para agregar una variante nueva:

```ts
// En VARIANT_REGISTRY dentro de sections.ts
'hero.ninth':     { type: 'hero', displayName: 'Hero – Ninth',     planMin: 'starter' },
```

**Helpers disponibles:**
- `getVariantsForType(type)` — devuelve todas las variantes de un tipo (ej: `getVariantsForType('hero')` → array de variants)
- `getVariantDef(componentKey)` — busca una variante por key (ej: `getVariantDef('hero.ninth')` → `VariantDef | undefined`)

### Paso 5: entender la validación server-side

Cuando se llama a `POST /home/sections` (addSection) o `PUT /home/sections/:id/replace` (replaceSection) con `component_key`, el servicio valida:

1. **Existencia**: `component_key` debe existir en `VARIANT_REGISTRY` → error `INVALID_COMPONENT_KEY` (400)
2. **Coincidencia de tipo**: `variant.type` debe coincidir con el `type` del DTO → error `COMPONENT_KEY_TYPE_MISMATCH` (400)
3. **Plan gating**: el plan del cliente debe ser >= `variant.planMin` → error `VARIANT_GATED` (403)

Si `component_key` no se envía (null/undefined), la validación se omite — compatibilidad hacia atrás.

### Paso 6: verificar persistencia en BD

La tabla `home_sections` tiene una columna `component_key TEXT` (nullable). Cuando el API persiste una sección, guarda `component_key` si fue provisto. Esto permite que `GET /home/data` devuelva el variant key correcto para el rendering en web.

El endpoint `GET /home/sections/registry` devuelve para cada tipo un array `variants[]` con las variantes disponibles y su `planMin`.

---

## 7. Diferencia entre preview y tienda publicada

| Flujo | Fuente de datos | Selector de template | Render de secciones |
| --- | --- | --- | --- |
| Preview builder | `postMessage(payload)` | `payload.templateKey` | `PreviewHost -> SectionRenderer` |
| Store publicada | `GET /home/data` | `homeData.config.templateKey` | `Home template -> SectionRenderer` |

Esto es clave para debug:

- Si falla el preview, mirar `Step4TemplateSelector`, `PreviewFrame` y `PreviewHost`.
- Si falla la tienda publicada, mirar `GET /home/data`, `HomeSettingsService`, `HomeRouter` y el Home del template.

---

## 8. Checklist de integracion

Antes de considerar terminado un template nuevo, verificar:

| # | Archivo / area | Que revisar |
| --- | --- | --- |
| 1 | `apps/web/src/templates/{nombre}/pages/` | Entry point creado |
| 2 | `apps/web/src/registry/templatesMap.ts` | Registro lazy con clave canonica |
| 3 | `apps/web/src/theme/resolveEffectiveTheme.ts` | Normalizacion del template |
| 4 | `apps/web/src/components/DynamicHeader.jsx` | Header propio o fallback correcto |
| 5 | `apps/web/src/registry/sectionComponents.tsx` | Nuevos `componentKey` registrados |
| 6 | `apps/web/src/registry/sectionComponentTemplates/*` | Re-exports del template |
| 7 | `apps/admin/src/services/builder/designSystem.ts` | Presets / catalogo consistentes |
| 8 | `apps/api/src/home/home-settings.service.ts` | Clave canonica valida y fallback correcto |
| 9 | `apps/api/src/home/registry/sections.ts` | Nuevos `componentKey` agregados al `VARIANT_REGISTRY` con `type` y `planMin` correctos |
| 10 | BD `home_sections` | Columna `component_key` existe (migración `BACKEND_051`) |
| 11 | `GET /home/sections/registry` | Endpoint devuelve `variants[]` incluyendo las nuevas keys |
| 12 | Validación server en `addSection()`/`replaceSection()` | Probar con keys inválidas, type mismatch y plan insuficiente |
| 13 | Preview builder | Renderiza via `/preview` |
| 14 | Store publicada | Renderiza via `/home/data` |

---

## 9. Errores comunes

### El preview funciona pero la tienda publicada no

Posibles causas:

- `templateKey` no llega a `client_home_settings`
- falta normalizacion en `resolveEffectiveTheme.ts`
- `HomeRouter` no encuentra la clave canonica

### La tienda publicada funciona pero una seccion dinamica no aparece

Posibles causas:

- falta el `componentKey` en `sectionComponents.tsx`
- falta el re-export en `sectionComponentTemplates/*`
- el builder esta emitiendo una key distinta a la que el web soporta

### El template carga pero con estilo equivocado

Posibles causas:

- falta mapear el template en `resolveEffectiveTheme.ts`
- `paletteVars` o `paletteKey` estan cayendo en fallback

### El API rechaza el component_key al agregar/reemplazar sección

Posibles causas y errores:

- **`INVALID_COMPONENT_KEY` (400)**: el `component_key` no existe en `VARIANT_REGISTRY`. Verificar que el key esté registrado en `apps/api/src/home/registry/sections.ts`.
- **`COMPONENT_KEY_TYPE_MISMATCH` (400)**: el `component_key` pertenece a un tipo diferente al que se está enviando. Ej: enviaste `type: 'features'` con `component_key: 'hero.first'` (que es tipo `hero`).
- **`VARIANT_GATED` (403)**: la variante requiere un plan superior al del cliente. Ej: variante requiere `enterprise` pero el cliente tiene plan `starter`.

Verificar:
- Que el `componentKey` esté en `VARIANT_REGISTRY` en `sections.ts`
- Que `variant.type` coincida con el `type` del DTO
- Que el plan del cliente sea >= `variant.planMin`
- Consultar variantes disponibles via `GET /home/sections/registry`

---

## 10. Resumen operativo rapido

- Preview del builder: `Step4TemplateSelector` -> `PreviewFrame` -> `PreviewHost` -> `SectionRenderer`
- Store publicada: `App.jsx` -> `GET /home/data` -> `HomeRouter` -> template Home -> `SectionRenderer`
- Fuente de verdad del template publicado: `client_home_settings`
- Fallback server-side: `clients.template_id` -> `template_1`
- Fuente de verdad de estructura en preview: `designConfig.sections[]`
- Fuente de verdad de estructura publicada: `homeData.config.sections`
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

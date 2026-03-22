# 🏗️ Prompt Estructural para Generar Homepages de E-Commerce — NovaVision

> **Versión:** 4.0
> **Fecha:** 2026-03-19
> **Propósito:** Generar templates de homepage con diseño UX/UI original, usando componentes unificados + un HeroSection único.
> **Stack:** React JS + Tailwind CSS + CSS variables `var(--nv-*)`
> **Cambios v4.0:** Post-unificación (T1-T6). Ya NO se generan componentes para FAQ, Contact, Footer, Services ni ProductCarousel. Solo se genera el HeroSection y un config.js con selección de variantes. Se usa `scripts/new-template.mjs` para scaffold.

---

## PROMPT (copiar completo)

---

Necesito que generes una homepage completa para una tienda e-commerce como un template de React JS con **Tailwind CSS** y **CSS variables** (`var(--nv-*)`). Tenés **libertad total de diseño, layout, UX, animaciones y estilo visual** — inventá algo original, no copies diseños existentes. Lo único que debés respetar son las **reglas de arquitectura de software** que te detallo abajo.

### ⛔ RESTRICCIONES CRÍTICAS (leer PRIMERO)

1. **CERO `<Link>` / `<NavLink>` / `useNavigate` de react-router-dom** — No importar NADA de `react-router-dom`. Para links usar `<a href="...">`. El template puede renderizarse SIN Router context y si usás `<Link>` se rompe con: `Cannot destructure property 'basename' of useContext(...) as it is null`.
2. **CERO fetch/API calls** — Todo llega por prop `homeData`. El template es puramente presentacional.
3. **CERO colores hardcodeados** — Todo color via `var(--nv-*)` (en clases Tailwind o en `style={{}}`). Nunca `#333`, `white`, `rgb(...)`, `bg-blue-500`, `text-gray-600`, etc.
4. **CERO styled-components** — No importar `styled` ni `useTheme()`.
5. **Tailwind + CSS vars** — Usar clases de Tailwind (`className="flex p-4 ..."`) combinadas con CSS variables `var(--nv-*)` para todos los colores. Responsive con breakpoints de Tailwind (`sm:`, `md:`, `lg:`, `xl:`).
6. **SIEMPRE importar React** — En **TODO** archivo `.jsx` agregar `import React from 'react'` en la primera línea (o al menos importar los hooks que uses: `import { useState, useEffect, useRef } from 'react'`). El proyecto **NO tiene** habilitado el nuevo JSX transform automático de React 17+, por lo que JSX sin el import explícito produce `Uncaught ReferenceError: React is not defined` en runtime. **Ejemplo correcto:**
   ```jsx
   import React, { useState, useRef } from 'react';
   // ...resto del componente
   ```

### ⚠️ ADVERTENCIA SOBRE ENTORNOS DE PREVIEW/SANDBOX

En entornos de sandbox o preview (CodeSandbox, StackBlitz, AI playgrounds), **Tailwind puede no generar las clases** si no está configurado el `content` path correctamente. Esto NO es un error del template — en el proyecto real de NovaVision, Tailwind está configurado y escanea `src/**/*.{js,ts,jsx,tsx}`. Si estás previsualizando en un sandbox, el diseño puede verse sin estilos; eso se resuelve al integrar en el repo real.

---

## 1. ESTRUCTURA DE ARCHIVOS (OBLIGATORIA — v4.0 post-unificación)

> **IMPORTANTE:** Desde marzo 2026, 5 tipos de secciones están unificadas en componentes con variantes.
> Ya **NO se generan** componentes para FAQ, Contact, Footer, Services ni ProductCarousel.
> Solo el **HeroSection** es único por template.

### Paso 0: Scaffold automático

```bash
node scripts/new-template.mjs <nombre> <número> "<Display Name>"
# Ejemplo: node scripts/new-template.mjs aurora 9 "Aurora"
```

Esto genera la estructura base. Solo necesitás **implementar el HeroSection** y **elegir variantes** en `config.js`.

### Estructura generada

```
src/templates/{nombre}/
├── config.js                         ← selección de variantes + metadata
├── components/
│   ├── HeroSection/
│   │   └── index.jsx                 ← ÚNICO componente original (diseño libre)
│   └── [componentes extra opcionales]/
│       └── index.jsx                 ← (marquee, testimonials, etc. — solo si son únicos)
└── pages/
    └── HomePage{Nombre}/
        └── index.jsx                 ← entry point genérico (ya viene pre-generado)
```

### Componentes unificados disponibles (NO crear por-template)

| Sección | Variantes | Se elige en |
|---|---|---|
| `FAQSection` | `accordion`, `cards`, `masonry` | `config.js` + `variantMap.ts` |
| `ContactSection` | `cards`, `two-column`, `minimal` | `config.js` + `variantMap.ts` |
| `Footer` | `columns`, `stacked`, `branded` | `config.js` + `variantMap.ts` |
| `ServicesSection` | `grid`, `list`, `cards` | `config.js` + `variantMap.ts` |
| `ProductCarousel` | `basic`, `featured`, `hero` | `config.js` + `variantMap.ts` |

**Reglas de carpetas:**
- Solo crear componentes que NO existen como variante unificada
- El HeroSection es donde va toda la identidad visual del template (layout de banners, animaciones, tipografía hero)
- El **entry point** es SIEMPRE `pages/HomePage{Nombre}/index.jsx`
- Componentes extra opcionales: testimonials, brand marquee, countdown, parallax, etc. (solo si el template necesita algo realmente único)

---

## 2. COMPONENTE HOME — ENTRY POINT (OBLIGATORIO)

El componente Home recibe **UNA SOLA prop**: `homeData`. Este es el contrato exacto:

```jsx
import PropTypes from 'prop-types';
import { DEMO_HOME_DATA } from '../../../../sections/demoData';
// Importá tus componentes locales desde ../../components/

function HomePage{Nombre}({ homeData: rawHomeData }) {
  // SIEMPRE fallback a demo data si no hay datos reales
  const homeData = rawHomeData || DEMO_HOME_DATA;

  // Desestructurar TODO lo que necesités
  const {
    products = [],
    services = [],
    faqs = [],
    contactInfo = [],
    banners = { desktop: [], mobile: [] },
    logo,
    socialLinks,
    storeName,
  } = homeData;

  // RENDERIZAR tus secciones pasando datos por PROPS
  return (
    <div style={{
      minHeight: '100vh',
      background: 'var(--nv-bg)',
      fontFamily: 'var(--nv-font)',
      color: 'var(--nv-text)',
    }}>
      {/* Tus secciones acá — diseño completamente libre */}
    </div>
  );
}

HomePage{Nombre}.propTypes = {
  homeData: PropTypes.object,
};

export default HomePage{Nombre};
```

### ⛔ REGLA INVIOLABLE: NO hacer fetch de datos

- **NUNCA** hacer `fetch()`, `axios()`, `useEffect` para traer datos, ni `useSWR`, `useQuery`, ni ninguna solicitud HTTP dentro del template
- **NUNCA** importar ni usar `supabase`, `api`, ni ningún service/client de datos
- **TODO** llega por `homeData` prop desde arriba — el template es **puramente presentacional**
- Si un dato puede ser `null`/`undefined`/`[]`, simplemente no renderizás esa sección

---

## 3. SCHEMA DE DATOS — QUÉ RECIBÍS EN `homeData`

Estos son los datos que te llegan. Usá los que quieras, ignorá los que no necesités:

### 3.1 `products` — Array de productos

```typescript
{
  id: string,                    // UUID
  name: string,                  // "Remera Oversize"
  description: string,           // HTML o texto plano
  sku: string | null,
  originalPrice: number,         // 25990 (en centavos o pesos, según config)
  discountedPrice: number | null, // null = sin descuento
  currency: string,              // "ARS"
  available: boolean,
  quantity: number,              // stock
  sizes: string[],               // ["S", "M", "L", "XL"]
  colors: string[],              // ["Negro", "Blanco"]
  material: string | null,
  promotionTitle: string | null, // "2x1 en remeras"
  discountPercentage: number | null,
  featured: boolean,             // producto destacado
  bestSell: boolean,             // más vendido
  tags: string[],
  categories: [{ id: string, name: string }],
  imageUrl: [
    { url: string, order: number }  // ⚠️ Es un ARRAY de objetos, NO un string
  ],
  client_id: string
}
```

**Tips de uso:**
- Para la imagen principal: `product.imageUrl?.[0]?.url`
- Para filtrar destacados: `products.filter(p => p.featured)`
- Para más vendidos: `products.filter(p => p.bestSell)`
- `discountedPrice !== null` indica que tiene descuento

### 3.2 `services` — Array de beneficios/servicios de la tienda

```typescript
{
  id: string,
  title: string,         // "Envío gratis"
  description: string,   // "En compras mayores a $20.000"
  number: number,        // orden de aparición
  image_url: string | null,
  file_path: string | null,
  client_id: string
}
```

### 3.3 `banners` — Objeto con arrays desktop y mobile

```typescript
{
  desktop: [
    { id: string, url: string, file_path: string, type: "desktop", link: string | null, order: number, client_id: string }
  ],
  mobile: [
    { id: string, url: string, file_path: string, type: "mobile", link: string | null, order: number, client_id: string }
  ]
}
```

**Tip:** Mostrá banners desktop en `md:` para arriba, mobile en pantallas chicas. Respetá el `order` para el carousel.

### 3.4 `faqs` — Array de preguntas frecuentes

```typescript
{
  id: string,
  question: string,     // "¿Cuál es el plazo de entrega?"
  answer: string,       // "Entre 3 y 5 días hábiles"
  number: number,       // orden
  client_id: string
}
```

### 3.5 `logo` — Objeto del logo de la tienda

```typescript
{
  id: string,
  url: string,           // URL pública de la imagen
  show_logo: boolean,    // si false, mostrar storeName en texto
  file_path: string,
  client_id: string
}
```

**Regla:** Si `logo.show_logo === true && logo.url` → mostrar imagen. Si no → mostrar `storeName` como texto.

### 3.6 `contactInfo` — Array de cards de información de contacto

```typescript
{
  id: string,
  titleinfo: string,     // "Dirección", "Teléfono", "Email"
  description: string,   // "Av. Corrientes 1234, CABA"
  number: number,        // orden
  client_id: string
}
```

### 3.7 `socialLinks` — Objeto con redes sociales

```typescript
{
  id: string,
  whatsApp: string | null,    // número completo con código de país
  wspText: string | null,     // mensaje predeterminado para WA
  instagram: string | null,   // URL completa del perfil
  facebook: string | null,    // URL completa de la página
  client_id: string
}
```

### 3.8 `storeName` — string

El nombre de la tienda. Usalo como fallback del logo y en el footer.

---

## 4. SECCIONES MÍNIMAS REQUERIDAS

Tu template DEBE incluir al menos las siguientes secciones (el diseño/layout/ubicación es libre):

| Sección | Datos que recibe | Cuándo renderizar |
|---------|-----------------|-------------------|
| **Hero/Banner** | `banners`, `logo`, `storeName` | Siempre (con fallback visual si no hay banners) |
| **Productos** | `products` | Si `products.length > 0` |
| **Servicios/Beneficios** | `services` | Si `services.length > 0` |
| **FAQ** | `faqs` | Si `faqs.length > 0` |
| **Contacto** | `contactInfo`, `socialLinks` | Si `contactInfo.length > 0 \|\| socialLinks` |
| **Footer** | `logo`, `socialLinks`, `storeName` | Siempre |

**Podés agregar secciones extra** que NO usen datos del API (testimonials estáticos, social proof, brand values, parallax dividers, formulario de contacto, etc.) — son totalmente libres y estáticos.

> ⚠️ **NO generar secciones de Newsletter / Suscripción por email.** El sistema no tiene backend de email marketing ni funcionalidad de suscripción. En su lugar, si querés agregar una sección de contacto extra, usá un **formulario de contacto** que redirija a WhatsApp (usando `social.whatsApp`) o sea puramente visual. Nunca generar secciones con input de "Suscribite" o "Newsletter".

---

## 5. SISTEMA DE COLORES — CSS VARIABLES (OBLIGATORIO)

Todos los colores del template se toman de CSS variables `--nv-*` que se inyectan globalmente. **NUNCA hardcodear colores.**

### 5.1 Variables disponibles (28 tokens de producción)

```
┌──────────────┬──────────────────────────────────────────────────────┐
│ FONDOS       │ --nv-bg          → fondo de la página               │
│              │ --nv-surface     → fondo de cards/panels/modals      │
│              │ --nv-card-bg     → alias de surface para cards       │
│              │ --nv-navbar-bg   → fondo del header/navbar           │
│              │ --nv-footer-bg   → fondo del footer                  │
├──────────────┼──────────────────────────────────────────────────────┤
│ TEXTO        │ --nv-text        → texto principal                   │
│              │ --nv-text-muted  → texto secundario/subtítulos       │
├──────────────┼──────────────────────────────────────────────────────┤
│ MARCA        │ --nv-primary       → color principal de marca        │
│              │ --nv-primary-hover → primary al hover                │
│              │ --nv-primary-fg    → texto sobre primary (contraste) │
│              │ --nv-accent        → color de acento                 │
│              │ --nv-accent-fg     → texto sobre accent (contraste)  │
├──────────────┼──────────────────────────────────────────────────────┤
│ INTERACCIÓN  │ --nv-link        → color de links                   │
│              │ --nv-link-hover  → link hover                       │
│              │ --nv-ring        → anillo de foco (focus)            │
│              │ --nv-hover       → color de hover genérico           │
├──────────────┼──────────────────────────────────────────────────────┤
│ BORDES       │ --nv-border      → borde estándar                   │
│              │ --nv-shadow      → color base de sombra              │
├──────────────┼──────────────────────────────────────────────────────┤
│ INPUTS       │ --nv-input-bg     → fondo de inputs                 │
│              │ --nv-input-text   → texto de inputs                  │
│              │ --nv-input-border → borde de inputs                  │
├──────────────┼──────────────────────────────────────────────────────┤
│ ESTADOS      │ --nv-success  → verde éxito                         │
│              │ --nv-warning  → amarillo advertencia                 │
│              │ --nv-error    → rojo error                           │
│              │ --nv-info     → azul informativo                     │
├──────────────┼──────────────────────────────────────────────────────┤
│ LAYOUT       │ --nv-radius   → border radius base (ej: 0.5rem)    │
│              │ --nv-font     → font family                         │
├──────────────┼──────────────────────────────────────────────────────┤
│ COMPAT       │ --nv-muted    → ⚠️ capa fondo semitransparente      │
│              │                  (rgba, NO texto — para hover bg)    │
└──────────────┴──────────────────────────────────────────────────────┘
```

### 5.2 Clases Tailwind mapeadas (usar cuando existan)

```jsx
// Estas clases de Tailwind ya mapean a las CSS vars:
bg-nv-background    // → var(--nv-background) — alias de --nv-bg
bg-nv-surface       // → var(--nv-surface)
bg-nv-primary       // → var(--nv-primary)
bg-nv-accent        // → var(--nv-accent)
text-nv-text        // → var(--nv-text)
text-nv-muted       // → var(--nv-muted) — ⚠️ ver nota abajo
text-nv-primary     // → var(--nv-primary)
border-nv-border    // → var(--nv-border)
```

### 5.3 Para tokens SIN clase Tailwind, usar `var()` directo:

```jsx
// Fondos específicos
bg-[var(--nv-navbar-bg)]
bg-[var(--nv-footer-bg)]
bg-[var(--nv-card-bg)]
bg-[var(--nv-input-bg)]

// Texto
text-[var(--nv-text-muted)]     // ✅ CORRECTO para subtítulos
text-[var(--nv-primary-fg)]     // texto sobre botón primary
text-[var(--nv-accent-fg)]      // texto sobre accent
text-[var(--nv-input-text)]

// Hover
hover:bg-[var(--nv-primary-hover)]
hover:text-[var(--nv-link-hover)]

// Focus
focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none

// Bordes
border-[var(--nv-input-border)]
border-[var(--nv-border)]

// Layout
rounded-[var(--nv-radius)]
shadow-[0_2px_8px_var(--nv-shadow)]  // o usar shadow-nv-md
```

### 5.4 ⛔ PROHIBIDO

```jsx
// ❌ NUNCA colores hardcodeados
bg-blue-500  bg-white  text-gray-600  bg-black
style={{ color: '#333' }}
style={{ background: 'white' }}

// ❌ NUNCA estas variables (NO EXISTEN en producción)
--nv-secondary
--nv-secondary-fg
--nv-surface-hover
--nv-border-focus
--nv-foreground

// ❌ NUNCA usar --nv-muted como color de TEXTO
text-nv-muted           // ⚠️ Es rgba semitransparente, NO un color de texto
text-[var(--nv-muted)]  // ⚠️ INCORRECTO para texto

// ✅ Para texto secundario SIEMPRE usar:
text-[var(--nv-text-muted)]

// ❌ NUNCA dark: prefix de Tailwind
dark:bg-gray-900  dark:text-white  // El dark mode es AUTOMÁTICO via CSS vars

// ❌ NUNCA styled-components
import styled from 'styled-components'  // PROHIBIDO en templates nuevos
useTheme()                               // PROHIBIDO
theme.colors.*                            // PROHIBIDO
```

---

## 6. PATRONES DE CÓDIGO OBLIGATORIOS

### 6.1 Botón primario (patrón base)

```jsx
<button
  className="bg-nv-primary text-[var(--nv-primary-fg)]
             hover:bg-[var(--nv-primary-hover)]
             focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none
             rounded-[var(--nv-radius)]
             px-6 py-3 font-medium transition-colors"
>
  Ver productos
</button>
```

### 6.2 Card de producto

```jsx
<div className="bg-nv-surface border border-nv-border rounded-[var(--nv-radius)]
                shadow-[0_2px_8px_var(--nv-shadow)] overflow-hidden
                hover:shadow-[0_4px_16px_var(--nv-shadow)] transition-shadow">
  <img src={product.imageUrl?.[0]?.url} alt={product.name}
       className="w-full aspect-[3/4] object-cover" />
  <div className="p-4">
    <h3 className="text-[var(--nv-text)] font-semibold">{product.name}</h3>
    {product.discountedPrice != null ? (
      <div className="flex items-center gap-2 mt-1">
        <span className="text-nv-primary font-bold">${product.discountedPrice}</span>
        <span className="line-through text-[var(--nv-text-muted)] text-sm">
          ${product.originalPrice}
        </span>
      </div>
    ) : (
      <span className="text-[var(--nv-text)] font-bold mt-1">${product.originalPrice}</span>
    )}
  </div>
</div>
```

### 6.3 Input/formulario

```jsx
<input
  type="email"
  placeholder="tu@email.com"
  className="w-full bg-[var(--nv-input-bg)] text-[var(--nv-input-text)]
             border border-[var(--nv-input-border)]
             rounded-[var(--nv-radius)] px-4 py-3
             focus:ring-2 focus:ring-[var(--nv-ring)] focus:outline-none
             transition-colors"
/>
```

### 6.4 Logo con fallback a storeName

```jsx
{logo?.show_logo && logo?.url ? (
  <img src={logo.url} alt={storeName || 'Logo'} className="h-10 object-contain" />
) : (
  <span className="text-[var(--nv-text)] text-xl font-bold tracking-tight">
    {storeName || 'Mi Tienda'}
  </span>
)}
```

### 6.5 Social links

```jsx
{socialLinks?.whatsApp && (
  <a href={`https://wa.me/${socialLinks.whatsApp}${socialLinks.wspText ? `?text=${encodeURIComponent(socialLinks.wspText)}` : ''}`}
     target="_blank" rel="noopener noreferrer" aria-label="WhatsApp">
    {/* ícono */}
  </a>
)}
{socialLinks?.instagram && (
  <a href={socialLinks.instagram} target="_blank" rel="noopener noreferrer" aria-label="Instagram">
    {/* ícono */}
  </a>
)}
{socialLinks?.facebook && (
  <a href={socialLinks.facebook} target="_blank" rel="noopener noreferrer" aria-label="Facebook">
    {/* ícono */}
  </a>
)}
```

### 6.6 Renderizado condicional de secciones

```jsx
// ✅ CORRECTO — no renderizar si no hay datos
{products.length > 0 && <ProductShowcase products={products} />}
{services.length > 0 && <ServicesSection services={services} />}
{faqs.length > 0 && <FAQSection faqs={faqs} />}
{(contactInfo.length > 0 || socialLinks) && (
  <ContactSection info={contactInfo} social={socialLinks} />
)}

// ❌ INCORRECTO — renderizar sección vacía
<ProductShowcase products={products} />  // si products=[] mostraría contenedor vacío
```

---

## 7. NAVEGACIÓN Y LINKS (OBLIGATORIO)

### 7.1 Links a páginas de producto

Los productos deben linkearse a su página de detalle con `<a href>` (NUNCA `<Link>` de react-router-dom):

```jsx
// ✅ CORRECTO — <a href> funciona sin Router context
<a href={`/product/${product.id}`} className="block">
  {/* contenido de la card */}
</a>

// ❌ INCORRECTO — <Link> requiere Router context y crashea en preview
import { Link } from 'react-router-dom'; // PROHIBIDO
<Link to={`/product/${product.id}`}>     // CRASHEA
```

### 7.2 Links de navegación scroll-to-section

En el header o nav, los links internos deben scrollear a secciones de la página:

```jsx
<a href="#products" className="...">Productos</a>
<a href="#services" className="...">Servicios</a>
<a href="#faq" className="...">FAQ</a>
<a href="#contact" className="...">Contacto</a>
```

Y cada sección correspondiente debe tener el `id`:

```jsx
<section id="products">...</section>
<section id="services">...</section>
<section id="faq">...</section>
<section id="contact">...</section>
```

### 7.3 Link a página de productos (catálogo completo)

```jsx
// ✅ CORRECTO
<a href="/products" className="...">Ver todo el catálogo</a>

// ❌ INCORRECTO
import { Link } from 'react-router-dom'; // PROHIBIDO
<Link to="/products">...</Link>           // CRASHEA
```

---

## 8. RESPONSIVIDAD (OBLIGATORIO)

- **Mobile-first**: escribí las clases base para mobile, luego usá `sm:`, `md:`, `lg:`, `xl:` para pantallas más grandes
- **Breakpoints disponibles** en Tailwind:
  - `sm`: 640px
  - `md`: 768px
  - `lg`: 1024px
  - `xl`: 1280px
  - `2xl`: 1536px
- **Banners**: mostrá `banners.mobile` en mobile y `banners.desktop` en desktop:

```jsx
{/* Desktop banners */}
<div className="hidden md:block">
  {banners.desktop?.map(b => <img key={b.id} src={b.url} ... />)}
</div>
{/* Mobile banners */}
<div className="md:hidden">
  {banners.mobile?.map(b => <img key={b.id} src={b.url} ... />)}
</div>
```

---

## 9. DEPENDENCIAS PERMITIDAS

Podés usar estas dependencias que ya están instaladas en el proyecto:

```
react                    // ya disponible
prop-types               // validación de props
framer-motion            // animaciones (motion.div, AnimatePresence, etc.)
react-icons              // íconos (FiShoppingCart, FiMenu, FiX, etc. — cualquier set)
```

**⛔ NO importar:**
- `react-router-dom` — ni `Link`, ni `NavLink`, ni `useNavigate`, ni `useLocation`. Usar `<a href>` para todos los links.
- Ninguna otra dependencia (no swiper, no slick, no embla, no react-spring). Si necesitás un carousel, construilo con scroll nativo + CSS (`overflow-x-auto`, `scroll-snap`) o con `framer-motion`.

---

## 10. NO INCLUIR (LO MANEJA EL SISTEMA)

Estos elementos ya se renderizan FUERA del template por el sistema global. **NO los incluyas:**

- ❌ **`<Header>` / `<Navbar>` principal** — ya se renderiza en `App.jsx` via `DynamicHeader` (ver sección 10.1)
- ❌ **`<AnnouncementBar>`** — ya se renderiza en `App.jsx`
- ❌ **`<ThemeProvider>`** — ya envuelve todo desde `App.jsx`
- ❌ **`<Router>`** / `<BrowserRouter>` — ya existe en `App.jsx`
- ❌ **SEO tags** / `<Helmet>` — ya se manejan en `App.jsx`
- ❌ **Social icons flotantes** — ya se renderizan en `App.jsx`
- ❌ **Cart drawer/modal** — ya se maneja globalmente
- ❌ **Auth modals** — ya se manejan globalmente

**SÍ incluí** tu propio `Footer` dentro del template (el footer es propio de cada template).

### 10.1 ⛔ HEADER — NUNCA CREARLO, ES GLOBAL

El sistema tiene un componente `DynamicHeader` en `src/components/DynamicHeader.jsx` que se renderiza **globalmente en `App.jsx`**, FUERA de tu template. Este header:

- Se elige automáticamente según el `templateKey` del cliente (hay un `TEMPLATE_HEADER_MAP` interno)
- Recibe `homeData`, `logo`, `socialLinks`, `storeName`, `toggleTheme`, `isDarkTheme` como props
- Incluye los íconos de carrito (`FiShoppingCart`), usuario (`FiUser`), menú hamburguesa (`FiMenu`/`FiX`), y dark mode toggle
- Los headers existentes están en `src/templates/{first,second,third,fourth,fifth}/components/Header/`

**¿Qué hacer en tu template?** NADA. No crear header, no importar header. Tu template empieza DEBAJO del header. El header ya va a estar arriba cuando se renderice en producción.

**Si estás probando en aislamiento** (sin App.jsx), el header no se ve — eso es normal. En producción, App.jsx renderiza `DynamicHeader` + tu template juntos.

### 10.2 ✅ FOOTER — OBLIGATORIO, ES TUYO

A diferencia del header, **cada template incluye su propio footer**. El footer es la única pieza de "navegación" que le pertenece al template.

**Requisitos del footer:**

1. **Fondo**: SIEMPRE usar `var(--nv-footer-bg)` — NUNCA `var(--nv-surface)` ni `var(--nv-bg)`
   ```jsx
   <footer style={{ background: 'var(--nv-footer-bg)' }}>
   ```

2. **Contenido mínimo obligatorio:**
   - Logo (con fallback a `storeName`)
   - Links de navegación: Inicio (`/`), Productos (`/products`), Ofertas (`/products?filter=sale`)
   - Links legales: Términos y condiciones (`/terms`), Política de privacidad (`/privacy`), Política de devoluciones (`/returns`)
   - Social links (WhatsApp, Instagram, Facebook) — renderizar condicionalmente
   - Copyright con año dinámico: `© ${new Date().getFullYear()} ${storeName}`
   
3. **Social links en footer — íconos correctos:**
   ```jsx
   import { FiInstagram, FiFacebook, FiMessageCircle } from 'react-icons/fi';
   
   // WhatsApp
   {socialLinks?.whatsApp && (
     <a href={`https://wa.me/${socialLinks.whatsApp}${socialLinks.wspText ? `?text=${encodeURIComponent(socialLinks.wspText)}` : ''}`}
        target="_blank" rel="noopener noreferrer" aria-label="WhatsApp">
       <FiMessageCircle />
     </a>
   )}
   // Instagram
   {socialLinks?.instagram && (
     <a href={socialLinks.instagram} target="_blank" rel="noopener noreferrer" aria-label="Instagram">
       <FiInstagram />
     </a>
   )}
   // Facebook  
   {socialLinks?.facebook && (
     <a href={socialLinks.facebook} target="_blank" rel="noopener noreferrer" aria-label="Facebook">
       <FiFacebook />
     </a>
   )}
   ```

4. **Props que recibe el footer:**
   ```jsx
   function Footer{Nombre}({ logo, socialLinks, storeName }) {
     // logo: { url, show_logo } — para el logo
     // socialLinks: { whatsApp, wspText, instagram, facebook } — para redes
     // storeName: string — para copyright y fallback de logo
   }
   ```

5. **Todos los links con `<a href>`, NUNCA `<Link>`** (aplica la restricción global)

6. **Colores del footer:**
   ```jsx
   // Fondo:           var(--nv-footer-bg)
   // Texto principal:  var(--nv-text)
   // Texto secundario: var(--nv-text-muted)
   // Links:           var(--nv-link) con hover var(--nv-link-hover)
   // Bordes:          var(--nv-border)
   // Social icons:    var(--nv-text-muted) con hover var(--nv-primary)
   ```

---

## 10.3 ⛔ CONTEXTOS PROHIBIDOS DENTRO DEL TEMPLATE

El template se renderiza dentro de un árbol que ya tiene providers globales. Los templates **NUNCA** deben crear ni importar:

```jsx
// ❌ PROHIBIDO — ya existe en App.jsx
import { ThemeProvider } from 'styled-components';
import { BrowserRouter, Routes, Route } from 'react-router-dom';
import { CartProvider } from '../../context/CartProvider';

// ❌ PROHIBIDO — hooks que dependen de contextos globales
import { useTheme } from 'styled-components';  // usar var(--nv-*) en su lugar
import { useNavigate, useLocation, Link } from 'react-router-dom';  // usar <a href>
import { useCart } from '../../hooks/useCart';  // el carrito es global, no del template

// ✅ CORRECTO — lo que SÍ podés importar en un template
import React, { useState, useEffect, useRef, useMemo } from 'react';
import PropTypes from 'prop-types';
import { motion, AnimatePresence, useInView } from 'framer-motion';
import { FiShoppingCart, FiHeart, FiArrowRight, ... } from 'react-icons/fi';
import { DEMO_HOME_DATA } from '../../../../sections/demoData';
```

**¿Por qué?** Si usás `<Link>` sin un Router context padre, el template crashea con:
> `Cannot destructure property 'basename' of useContext(...) as it is null`

Si usás `useTheme()` de styled-components sin un ThemeProvider, crashea con:
> `Cannot read properties of undefined`

---

## 11. CHECKLIST FINAL

Antes de entregar, verificá:

### Arquitectura (si falta alguno, el template NO funciona)
- [ ] **Entry point** en `pages/HomePage{Nombre}/index.jsx` con `export default`
- [ ] **TODOS los archivos .jsx** tienen `import React from 'react'` (o al menos `import { useState, ... } from 'react'`) — sin esto se rompe con `React is not defined`
- [ ] Recibe `homeData` como ÚNICA prop y desestructura con fallback a `DEMO_HOME_DATA`
- [ ] **CERO** llamadas fetch/API/supabase dentro del template
- [ ] **CERO** imports de `react-router-dom` — ni `Link`, ni `NavLink`, ni `useNavigate`
- [ ] **CERO** `styled-components` — no `styled`, no `useTheme()`, no `ThemeProvider`
- [ ] **CERO** imports de contextos globales del sistema (`useCart`, `useAuth`, `CartProvider`, etc.)
- [ ] NO incluye Header/Navbar principal (lo maneja `DynamicHeader` en `App.jsx`)
- [ ] NO incluye ThemeProvider, Router, Helmet, ni AnnouncementBar

### Colores (si falta alguno, se rompe el theme system)
- [ ] **CERO** colores hardcodeados — TODO via `var(--nv-*)` o clases `nv-*`
- [ ] **CERO** uso de `dark:` prefix — dark mode es automático via CSS vars
- [ ] Texto secundario usa `text-[var(--nv-text-muted)]` (NUNCA `--nv-muted` que es rgba)
- [ ] Botones primarios usan `bg-nv-primary text-[var(--nv-primary-fg)] hover:bg-[var(--nv-primary-hover)]`
- [ ] Focus accesible con `focus:ring-2 focus:ring-[var(--nv-ring)]` en todo interactivo
- [ ] **Footer usa `background: var(--nv-footer-bg)`** — NUNCA `var(--nv-surface)` ni `var(--nv-bg)`
- [ ] No usa variables inexistentes: `--nv-secondary`, `--nv-surface-hover`, `--nv-border-focus`, `--nv-foreground`

### Footer (obligatorio en cada template)
- [ ] Footer incluido como componente propio del template (`Footer{Nombre}`)
- [ ] Recibe `{ logo, socialLinks, storeName }` como props
- [ ] Fondo: `var(--nv-footer-bg)`
- [ ] Incluye logo con fallback a `storeName`
- [ ] Incluye links de navegación: Inicio, Productos, Ofertas
- [ ] Incluye links legales: Términos, Privacidad, Devoluciones (`/terms`, `/privacy`, `/returns`)
- [ ] Incluye social links condicionados (`whatsApp`, `instagram`, `facebook`)
- [ ] Incluye copyright con año dinámico
- [ ] Todos los links son `<a href>`, no `<Link>`

### Navegación y datos
- [ ] Links de producto usan `<a href={\`/product/${product.id}\`}>` (NUNCA `<Link>`)
- [ ] Secciones con `id` para scroll-to-section (`#products`, `#faq`, etc.)
- [ ] Cada sección se renderiza condicionalmente (si no hay datos, no renderizar)
- [ ] Mobile-first responsive (`sm:`, `md:`, `lg:`, `xl:`)
- [ ] Imágenes de producto: `product.imageUrl?.[0]?.url` (es array de objetos)
- [ ] Logo con fallback: `logo?.show_logo && logo?.url` → imagen, sino → `storeName` como texto
- [ ] `PropTypes` definidos en el componente Home
- [ ] Componentes usan solo `framer-motion` o scroll nativo para animaciones/carousels

---

## 12. EJEMPLO DE PROPIEDADES DEL COMPONENTE HOME (REFERENCIA)

```jsx
HomePage{Nombre}.propTypes = {
  homeData: PropTypes.shape({
    products: PropTypes.array,
    services: PropTypes.array,
    faqs: PropTypes.array,
    contactInfo: PropTypes.array,
    banners: PropTypes.shape({
      desktop: PropTypes.array,
      mobile: PropTypes.array,
    }),
    logo: PropTypes.shape({
      url: PropTypes.string,
      show_logo: PropTypes.bool,
    }),
    socialLinks: PropTypes.shape({
      whatsApp: PropTypes.string,
      wspText: PropTypes.string,
      instagram: PropTypes.string,
      facebook: PropTypes.string,
    }),
    storeName: PropTypes.string,
    config: PropTypes.object,
  }),
};
```

---

## 13. DISEÑOS EXISTENTES — NO REPETIR (OBLIGATORIO)

Ya existen 8 templates en el sistema. Tu diseño **DEBE ser visualmente diferente** a todos. Acá va un resumen del estilo de cada uno para que **no lo repitas:**

### Templates 1–5 (styled-components, stack anterior)

| # | Estilo | Características clave a evitar |
|---|--------|-------------------------------|
| 1 | **Clásico minimalista** | Cards con sombra suave, layout grid estándar, botones pill redondeados, hero centrado con gradiente |
| 2 | **Moderno limpio** | Grid 3 columnas, cards con hover scale, header sticky transparente, hero split (texto + imagen) |
| 3 | **Elegante premium** | Tipografía serif, imágenes full-bleed, espaciado amplio, tonos neutros, hero con overlay de texto |
| 4 | **Compacto funcional** | Cards compactas en grid denso, badges de descuento circulares, sidebar de filtros, hero carousel básico |
| 5 | **Editorial visual** | Layout asimétrico, tipografía bold, imágenes grandes con overlay gradiente, hero full-screen |

### Template 6 — "Drift" (Tailwind + CSS vars)

**Estilo:** Contemporáneo, aireado, con microinteracciones suaves. Combina elegancia con energía sutil.

**❌ No repetir estas decisiones de diseño:**

- **Hero:** Carousel full-viewport (80vh) con `AnimatePresence` fade+scale, fallback con gradiente radial `primary→transparent` + `accent→transparent` en esquinas opuestas. Sin texto overlay sobre los banners.
- **Brand Marquee:** Barra horizontal infinita (`framer-motion` animate x: 0%→-50%) con textos estáticos ("Envío a todo el país", "Calidad garantizada"...) separados por dots circulares `--nv-primary`, sobre fondo `--nv-surface` con border-y.
- **Productos:** Grid con `row-span-2` para items 0 y 3 (layout bento asimétrico). Cards con imagen + badges superpuestos (Destacado/Más vendido/descuento). Hover overlay oscuro con botón blanco "Ver producto". Categoría en uppercase tracking wide arriba del nombre. Precios con tachado y badge de descuento.
- **Servicios:** Cards en grid con ícono `--nv-primary` (cuadrado redondeado), número grande semitransparente (opacity-5) en esquina superior derecha como decoración. Stagger animation al entrar en viewport.
- **FAQ:** Acordeón con cards individuales redondeadas (rounded-xl) con fondo `--nv-surface`, borde `--nv-border`, sombra suave. Botón toggle es un círculo que cambia fondo a `--nv-primary` cuando está abierto (FiPlus→FiMinus). Header centrado con label "Preguntas frecuentes" en tracking-[0.3em] uppercase + título "¿Tenés dudas?" con palabra resaltada en `--nv-primary`.
- **Contacto:** Cards compactas con ícono en cuadrado `--nv-primary` a la izquierda, info a la derecha. Sección social con íconos circulares que hacen hover cambiando a `--nv-primary`. Layout en grid.
- **Footer:** 4 columnas (marca+descripción+social, navegación, legal, contacto CTA). Social icons circulares con border y hover hacia primary. Links con separadores por sección.
- **Animaciones:** `useInView` con stagger delays, `whileInView` con fade+slide-up, transiciones easeOut suaves (0.4–0.6s).
- **Tipografía:** clamp() para títulos responsivos, tracking negativo en headings, font-semibold/font-black.
- **Espaciado:** py-20 md:py-28, px-6 md:px-16 lg:px-24, max-w-7xl centrado.

### Template 7 — "Vanguard" (Tailwind + CSS vars)

**Estilo:** Neo-brutalista / editorial de alta moda. Bordes gruesos, sombras hard-offset, tipografía masiva uppercase, estética de revista/catálogo de diseño.

**❌ No repetir estas decisiones de diseño:**

- **Hero:** Banner carousel en la parte superior (55vh–70vh) con fade simple, seguido de una sección de texto DEBAJO del banner (no superpuesta) con grid decorativo de fondo (líneas con `backgroundImage: linear-gradient`). Título h1 gigante (text-5xl md:text-8xl) font-black uppercase con palabras alternando color sólido y gradiente `primary→accent` via `bg-clip-text`. Badge "Nueva Colección" rectangular sin redondeo.
- **Servicios:** Franja de fondo invertido (`background: --nv-text, color: --nv-bg`) con grid dividido por `divide-x`. Números grandes "01"/"02"/"03" en font-mono como decoración. Todo uppercase, tracking-wider.
- **Productos:** Heading con punto de color ("Catálogo.") en tamaño 5xl–7xl, border-bottom-4 grueso debajo del título. Cards con **border-2** y **shadow hard-offset** (`shadow-[8px_8px_0px_var(--nv-text)]`). Imágenes en grayscale que pasan a color en hover (`grayscale group-hover:grayscale-0`). Overlay de hover con botón rectangular con border-2. Precio con label "Precio" en font-mono uppercase y SKU visible.
- **FAQ:** Acordeón con borde grueso exterior (border-2) + shadow hard-offset. Items separados por border-b-2. Números "01"/"02" en `--nv-primary` font-mono. Toggle es un "+" que rota 45° para hacer "×". Respuestas con border-left-2 en `--nv-primary`, indentadas, en font-mono uppercase.
- **Contacto:** Cards con border-2 y **shadow hard-offset en `--nv-primary`** (`shadow-[6px_6px_0px_var(--nv-primary)]`). Heading gigante "Contacto." con punto de color. Social links como texto uppercase con underline en hover (no íconos).
- **Footer:** Nombre de tienda en tamaño **12vw** (masivo, casi full-width), font-black uppercase. Grid 4 columnas. Social links como texto mono uppercase con hover underline. Copyright con fecha dinámica. Botón "Scroll to Top" rectangular con border-2.
- **Firma general:** Todo uppercase, font-mono para labels y texto secundario, tracking-widest, bordes de 2–4px, sombras hard-offset, cero border-radius (todo rectangular), estética raw/industrial.
- **Sin framer-motion en la mayoría de componentes** (solo en Hero y FAQ transitions), el movimiento viene de CSS transitions (hover:-translate-y-1, hover:scale-110, hover:shadow).

### Template 8 — "Lumina" (Tailwind + CSS vars)

**Estilo:** Luminoso, fluido y emocional. Gradientes suaves, transiciones cálidas, secciones con personalidad (testimonials, newsletter). Diseño limpio con toques de profundidad.

**❌ No repetir estas decisiones de diseño:**

- **Hero:** Carousel de banners con `AnimatePresence` y transición fade+slide. Fallback sin banners: gradiente radial de `--nv-primary` → transparente centrado. Logo o storeName centrados sobre el hero. Indicadores de dots abajo, autoplay.
- **Productos:** `ProductShowcase` con grid de cards en hover scale+shadow. Imagen con `aspect-[3/4]`. Badge de descuento redondeado en esquina con `--nv-accent`. Precio tachado + precio nuevo en `--nv-primary`. Botón "Ver más" centrado al final.
- **Servicios:** Cards con ícono circular `--nv-primary` (fondo semitransparente), título y descripción. Grid responsive 1→2→3 columnas. Animación stagger con `useInView`.
- **Testimonials:** Sección estática con citas ficticias. Cards con avatar circular, nombre, texto entre comillas. Fondo `--nv-surface`. Layout en grid.
- **FAQ:** Acordeón con `AnimatePresence` para abrir/cerrar. Items con borde inferior `--nv-border`. Toggle con `FiChevronDown` que rota. Fondo `--nv-surface` en todo el bloque.
- **Newsletter:** ~~Sección CTA con input de email~~ **Reemplazada por formulario de contacto** con nombre/email/mensaje que redirige a WhatsApp. NO generar secciones de newsletter/suscripción.
- **Contacto:** Cards de info + social links con íconos circulares. Layout grid. Íconos `FiMessageCircle`, `FiInstagram`, `FiFacebook`.
- **Footer:** 4 columnas (marca, nav, legal, contacto). Línea decorativa superior con gradiente `transparent→primary→transparent`. Social icons circulares con borde. Botón scroll-to-top. Copyright con año dinámico.
- **Animaciones:** `useInView` con `motion.div` fade+slide-up en todas las secciones. Stagger delays. Transiciones `easeOut 0.5s`.
- **Colores:** Todo via CSS vars. Root div con `background: var(--nv-bg)`, `fontFamily: var(--nv-font)`, `color: var(--nv-text)`.

---

### Resumen rápido de lo que NO hacer

| Patrón | Template que ya lo usa |
|--------|----------------------|
| Carousel full-screen con fade+scale suave | Template 6 |
| Brand marquee horizontal infinito | Template 6 |
| Grid bento (row-span-2 asimétrico) para productos | Template 6 |
| Acordeón con cards redondeadas + círculo toggle ±  | Template 6 |
| Neo-brutalismo (bordes gruesos + shadow hard-offset) | Template 7 |
| Todo uppercase + font-mono + tracking-widest | Template 7 |
| Imágenes grayscale→color en hover | Template 7 |
| Nombre de tienda gigante (>8vw) como decoración | Template 7 |
| Franja invertida (fondo=texto, texto=fondo) para servicios | Template 7 |
| Números decorativos "01/02/03" prominentes | Template 6 y 7 |
| Hero con texto debajo del banner (no superpuesto) | Template 7 |
| Cards con sombra suave y hover scale | Templates 1–5, 8 |
| Layout grid simétrico 3 columnas | Templates 1–5 |
| Sección testimonials estática con avatares circulares | Template 8 |
| Sección formulario de contacto con redirección a WhatsApp | Template 8 |
| Hero con dots indicadores + autoplay | Template 8 |
| Línea gradiente decorativa transparent→primary→transparent | Template 8 |

💡 **Ideas de estilos aún NO explorados** (sugerencias, no obligatorias):

- Glassmorphism / frosted glass (backdrop-blur, bordes sutiles, fondos semitransparentes)
- Scroll horizontal / carruseles nativos con scroll-snap
- Layout asimétrico fluido con overlapping elements
- Estética retro/vintage (texturas, tipografía display, colores terrosos)
- Minimalismo extremo suizo (tipografía grande, mucho espacio negativo, sin decoración)
- Diseño editorial vertical (secciones a pantalla completa con scroll)
- Estética neomorphism (sombras internas/externas, sensación 3D suave)
- Dark-first con acentos de color vibrante (neon-on-dark)
- Orgánico/blob shapes con border-radius irregulares
- Magazine grid con overlapping de texto sobre imágenes
- Parallax (secciones que se mueven a velocidades distintas al scrollear)
- Neumorphism cards (sombras interior+exterior en fondo neutro)

---

## 14. REGISTRO POST-GENERACION — ARCHIVOS QUE DEBES CONFIGURAR (para el desarrollador)

> **Esta seccion es para el DESARROLLADOR que integra el template generado al repo.** No es parte del prompt creativo, sino un recordatorio de todo lo que hay que tocar para que el template funcione en preview y en produccion.

Despues de generar y colocar el template en `src/templates/{nombre}/`, hay que registrarlo al menos en estos puntos:

### 14.1 `src/registry/templatesMap.ts`
```typescript
import { lazy } from 'react';

const HomeTemplate8 = lazy(() => import('../templates/eighth/pages/HomePageLumina'));

export const TEMPLATES = {
  // ...existing...
  template_8: HomeTemplate8,
};
```

Nota: el flujo publicado hoy consume principalmente claves canonicas `template_N` desde `HomeRouter`.

### 14.2 `src/templates/manifest.js`
```javascript
eighth: {
  id: 'eighth',
  name: 'Lumina',
  description: 'Template luminoso...',
  status: 'beta',
  preview: '/demo/templates/eighth-preview.png',
  features: ['hero-animated', 'product-showcase', ...],
  entryPage: 'HomePageLumina',
  supportsSections: false,  // true si implementa SectionRenderer
},
```

### 14.3 `src/theme/resolveEffectiveTheme.ts`
En la función `normalizeTemplateKey`, agregar al `templateMap`:
```typescript
template_8: 'eighth',
eighth: 'eighth',
```

### 14.4 `src/components/DynamicHeader.jsx`
Si el template necesita header propio, agregarlo en `TEMPLATE_HEADER_MAP`:
```javascript
template_8: HeaderFifth, // TODO: crear HeaderEighth propio
eighth: HeaderFifth,
```
Y en `normalizeTemplateKey`, agregar `"template_8"` y `"eighth"` al array `valid`.

### 14.5 `src/registry/sectionComponents.tsx`
Si el template va a soportar secciones dinamicas nuevas, registrar sus `componentKey` runtime:

```tsx
const eighthTemplateLoader = () => import('./sectionComponentTemplates/eighth');
const HeroEighth = lazyTemplateExport(eighthTemplateLoader, 'HeroEighth');

export const SECTION_COMPONENTS = {
  ...,
  'hero.eighth': HeroEighth,
};
```

### 14.6 `src/registry/sectionComponentTemplates/*.tsx`
Re-exportar los componentes reales del template:

```tsx
export { default as HeroEighth } from '../../templates/eighth/components/Hero';
export { default as FooterEighth } from '../../templates/eighth/components/Footer';
```

### 14.7 `src/__dev/pages/TemplatePreviewer.jsx`
En `CANONICAL_TO_ALIAS`, agregar:
```javascript
template_8: 'eighth',
```

### 14.8 (Opcional) `src/theme/palettes.ts`
Si el template necesita paletas propias:
```typescript
export const eighth_glow: PaletteTokens = { ... };
```
Y agregar en `PALETTES` y en el manifest como `recommendedPalettes`.

### 14.9 Preview del builder
Recorda que el builder no usa `GET /home/data` para previsualizar. El flujo actual es:

```text
Step4TemplateSelector -> PreviewFrame -> /preview -> PreviewHost -> SectionRenderer
```

Si el template o una seccion solo funciona en store publicada pero no en preview, revisar `PreviewHost` y los props inyectados por `SectionRenderer`.

### 14.10 (Opcional) Base de datos
Verificar si hay un enum o constraint en la tabla de accounts que limite `template_id`. Si existe, agregar `template_8`.

---

## 15. LECCIONES APRENDIDAS — ERRORES REALES DE TEMPLATES 6, 7 Y 8

Estos son bugs reales que aparecieron al integrar templates generados por IA. **Cada uno rompió producción** y requirió debugging manual. El prompt ya cubre las soluciones, pero acá va el detalle para contexto:

### 15.1 `React is not defined` (Template 8 — Lumina)
**Síntoma:** `Uncaught ReferenceError: React is not defined` al abrir la tienda.
**Causa:** Archivos `.jsx` sin `import React from 'react'`. El proyecto NO tiene habilitado el JSX transform automático de React 17+.
**Fix:** Agregar `import React from 'react'` (o `import React, { useState, useRef } from 'react'`) en **TODO** archivo `.jsx`.
**Regla:** Restricción #6 del prompt.

### 15.2 FAQ con fondo negro ilegible (Template 6 — Drift)
**Síntoma:** Los botones de FAQ se veían con fondo `#1a1a1a` (negro) incluso en modo claro, haciendo el texto ilegible.
**Causa:** El boilerplate de Vite (`src/index.css`) incluía:
```css
button { background-color: #1a1a1a; }
```
Esto pisaba los estilos del template porque CSS specificity del tag selector `button` ganaba sobre las clases de Tailwind.
**Fix:** Se limpió `src/index.css` dejando solo `@import 'tailwindcss'`. Los templates nuevos NO tienen este problema, pero si alguien toca `index.css` hay que verificar que no haya estilos globales de tag.
**Regla:** No meter estilos globales de tag en `index.css`.

### 15.3 Contraste pobre en cards (Templates 4, 6, 7)
**Síntoma:** Texto casi invisible en certain paletas porque se usaban colores hardcodeados o variables incorrectas.
**Causa:** Usar `--nv-muted` (que es `rgba(...)` semitransparente para fondos de hover) como color de TEXTO. O usar colores Tailwind directos (`text-gray-600`).
**Fix:** Usar siempre `var(--nv-text-muted)` para texto secundario, nunca `var(--nv-muted)`.
**Regla:** Sección 5.4 del prompt.

### 15.4 Template crashea en preview de onboarding (varios)
**Síntoma:** El preview del template durante el onboarding mostraba error en lugar del template.
**Causa:** El template usaba `<Link>` de react-router-dom. En el preview del onboarding, no hay Router context → crash.
**Fix:** Usar siempre `<a href>` en lugar de `<Link>`.
**Regla:** Restricción #1 del prompt.

### 15.5 Footer con fondo igual al body (Templates 6, 7)
**Síntoma:** El footer se confundía con el body porque usaba `var(--nv-bg)` o `var(--nv-surface)` en lugar de `var(--nv-footer-bg)`.
**Causa:** La IA generó el footer con `bg-nv-surface` (fondo de cards) en vez de `var(--nv-footer-bg)` (fondo específico de footer, que en muchas paletas es más oscuro).
**Fix:** Footer SIEMPRE usa `style={{ background: 'var(--nv-footer-bg)' }}`.
**Regla:** Checklist del footer, sección 10.2.

### 15.6 Variables CSS inexistentes usadas (varios)
**Síntoma:** Colores que aparecen como `transparent` o valor por defecto del browser porque la variable no existe.
**Causa:** La IA inventó variables como `--nv-secondary`, `--nv-surface-hover`, `--nv-border-focus`, `--nv-foreground` que NO existen en el sistema.
**Fix:** Usar SOLO las 28 variables listadas en la sección 5.1.
**Regla:** Sección 5.4 — variables prohibidas.

---

## FIN DEL PROMPT

**Ahora creá una homepage de e-commerce completamente original.** No copies layouts existentes de Shopify, Wix, ni de los templates 1-8 de este sistema. Inventá algo visualmente único, moderno, y que se destaque. Tenés libertad total de diseño — solo respetá la arquitectura de arriba y evitá los patrones de diseño listados en la sección 13.

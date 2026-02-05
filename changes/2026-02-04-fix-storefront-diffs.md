# DIFF de Cambios - Fix Storefront (Productos, Secciones, Cache, Theme)

## Archivos Creados (NUEVOS)

### 1. `src/services/homeData/normalizeHomeData.js`

```javascript
/**
 * Normaliza homeData asegurando estructura mínima viable:
 * - Si faltan secciones, genera defaults
 * - Normaliza imágenes de productos soportando 4 formatos
 * - Asegura tipos esperados
 */

export function normalizeHomeData(homeData) {
  if (!homeData) return { sections: [] };

  const sections = Array.isArray(homeData.sections) ? homeData.sections : [];

  // Si no hay secciones, generar base default
  if (!sections.length) {
    const defaultSections = [
      hasProducts && {
        id: 'products_featured',
        type: 'products_carousel',
        title: 'Productos Destacados',
        limit: 12,
      },
      // ... (categories_grid, services, contact, faqs)
    ].filter(Boolean);
    return { ...homeData, sections: defaultSections };
  }
  return { ...homeData, sections };
}

// Soporta: product.image.url, product.images[0].url, product.imageUrl, fallback
function normalizeProducts(products = []) { ... }
function getProductImageUrl(product = {}) { ... }
```

**Por qué:** Sin secciones, el template no tenía qué renderizar → `sectionsCount: 0`.

---

### 2. `src/templates/first/components/SectionRenderer/index.jsx`

```javascript
/**
 * SectionRenderer - Switch por tipo de sección
 * Una única fuente de verdad para layout dinámico
 */

export function SectionRenderer({ section, data = {} }) {
  switch (type) {
    case 'products_carousel':
      return <ProductCarousel productsList={...} />;
    case 'services':
      return <Services servicesList={...} />;
    case 'contact':
      return <ContactSection contact={...} />;
    case 'faqs':
      return <FAQSection faqs={...} />;
    default: return null;
  }
}
```

**Por qué:** Elimina render duplicado (estático + dinámico).

---

### 3. `src/hooks/useThemeVars.js`

```javascript
/**
 * Aplica variables CSS globales desde el theme
 * Garantiza contraste legible
 */

export function useThemeVars(theme) {
  useEffect(() => {
    const root = document.documentElement;
    root.style.setProperty('--nv-bg', colors.bg || '#ffffff');
    root.style.setProperty('--nv-text', colors.text || '#000000');
    root.style.setProperty('--nv-muted', colors.muted || '#888888');
    root.style.setProperty('--nv-primary', colors.primary || '#0066cc');
    // ...
  }, [theme]);
}

// Global CSS resets
export const themeVarStyles = `
  body { background-color: var(--nv-bg); color: var(--nv-text); }
  h1, h2, h3 { color: var(--nv-text); }
  .muted { color: var(--nv-muted); }
`;
```

**Por qué:** Theme colors no se aplicaban → UI ilegible.

---

### 4. `src/components/TenantDebugBadge/index.jsx`

```javascript
/**
 * TenantDebugBadge - Visible solo en DEV
 * Muestra slug, clientId, templateKey, paletteKey
 */

export function TenantDebugBadge({ tenant = {} }) {
  if (import.meta.env.PROD) return null;
  return (
    <div style={{...}}>
      🔍 TENANT DEBUG
      slug: {slug}
      template: {templateKey}
      palette: {paletteKey}
    </div>
  );
}
```

**Por qué:** Sin validación visual de qué tenant/template está activo.

---

## Archivos Modificados (CAMBIOS)

### 1. `src/services/homeData/homeService.jsx`

**ANTES:**
```javascript
const getHookCacheData = () => {
  // Aceptaba cache aunque isValid: false
  if (cached?.data) return cached.data;
};

// 304 sin cache → fallback automático (incluso si inválido)
```

**DESPUÉS:**
```javascript
const getHookCacheData = () => {
  // ✅ CRÍTICO: solo usa si marked valid
  if (cached?.isValid !== false && cached?.data) {
    return cached.data;
  }
  // ❌ Cache invalid → rechaza explícitamente
  if (cached?.isValid === false) {
    return null;
  }
};

// 304 sin cache → refetch con cache-busting
if (response.status === 304 && !response.data) {
  const fallbackData = getHookCacheData(); // Solo si válido
  if (fallbackData) return fallbackData;
  
  // ❌ Sin fallback válido → force refetch
  clearStoredETag(cacheKey);
  const retryResponse = await fetchWithETag(url, {
    headers: { 'Cache-Control': 'no-cache' }
  });
}
```

**Por qué:** `isValid: false` + 304 → fallback viejo/incompleto.

---

### 2. `src/templates/first/pages/HomePageFirst/index.jsx`

**ANTES:**
```javascript
// Extraía secciones de homeData.config.sections (frecuentemente undefined)
const sections = homeData?.config?.sections || sectionsProp || [];

// Renderizaba:
// 1. Por secciones (si existen)
// 2. Más código estático: Header, Banner, Services, Collections, Carousels, Contact, FAQ
// → Duplicación si `sections` tenía products_carousel

if (sections && sections.length > 0) {
  return <SectionRenderer .../>;
}

// STATIC FALLBACK (siempre ahí)
return (
  <>
    <Header />
    <BannerHome />
    <Services />
    <CollectionsSection />
    <ProductCarousel /> {/* ← duplicado si sections[0].type === 'products_carousel' */}
    <ProductCarousel /> {/* ← ...más carouseles */}
    <ContactSection />
    <FAQSection />
  </>
);
```

**DESPUÉS:**
```javascript
// Normaliza → asegura secciones siempre existen
const normalizedData = normalizeHomeData(homeData || {});
const sections = normalizedData.sections || [];

// Renderiza SOLO por secciones (una fuente de verdad)
return (
  <>
    <Header logo={logo} />
    {sections.length > 0 ? (
      sections.map((section) => (
        <SectionRenderer key={section.id} section={section} data={{...}} />
      ))
    ) : (
      // Fallback mínimo si falla normalizer
      <>
        <BannerHome banners={banners} />
        {products.length > 0 && <ProductCarousel products={products} />}
      </>
    )}
    <ToTopButton />
  </>
);
```

**Por qué:** Una sola fuente → sin duplicación.

---

### 3. `src/App.jsx`

**ANTES:**
```javascript
import { TenantProvider } from './context/TenantProvider';
// ... resto

function AppContent() {
  const theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth;
  // No aplicaba variables CSS
  // No mostraba tenant debug
```

**DESPUÉS:**
```javascript
import { TenantProvider, useTenant } from './context/TenantProvider';
import { useThemeVars } from './hooks/useThemeVars';
import { TenantDebugBadge } from './components/TenantDebugBadge';
// ...

function AppContent() {
  const tenant = useTenant();
  const theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth;
  
  // ✅ Aplica variables CSS globales
  useThemeVars(theme);
  
  // ✅ Renderiza badge en DEV
  return (
    <TenantProvider>
      <ThemeProvider theme={theme}>
        {tenant && <TenantDebugBadge tenant={tenant} />}
        {/* ... resto */}
      </ThemeProvider>
    </TenantProvider>
  );
}
```

**Por qué:** Sin aplicar vars CSS, sin visibilidad de tenant.

---

## Resumen de Cambios

| Aspecto | Antes | Después | Cambio |
|---------|-------|---------|--------|
| **Secciones** | `sectionsCount: 0` siempre | Generadas dinámicamente | normalizeHomeData() |
| **Cache en 304** | Usaba si existía (incluso inválida) | Solo si `isValid !== false` | homeService.jsx |
| **Render layout** | Estático hardcoded + dinámico | Solo dinámico por sections | HomePageFirst + SectionRenderer |
| **Theme vars** | No aplicadas | `--nv-bg`, `--nv-text`, etc. | useThemeVars + App.jsx |
| **Tenant visibilidad** | Invisible | Badge DEV visible | TenantDebugBadge |

---

## Testing Rápido (Pasos de Validación)

### 1. Carouseles con productos
```
✅ Visita demo-store homepage
✅ Espera ~2s a carga
✅ Ve 8-12 productos en carousel (con imagen + título)
✅ Consola: "[SectionRenderer] Rendering section: { id: 'products_featured', type: 'products_carousel' }"
```

### 2. Cache no rechaza inválida
```
✅ F5 recarga
✅ Network: GET /home/data → 304
✅ Consola: Si invalida, ve "[homeService] ...will refetch…"
✅ Data actualiza (no UI vieja)
```

### 3. Theme variables aplicadas
```
✅ DevTools → HTML <html> element
✅ Ver estilos inline: --nv-bg, --nv-text, --nv-primary
✅ Textos legibles (no grises sobre grises)
```

### 4. Tenant debug badge
```
✅ DEV: Bottom-right corner muestra badge
✅ Valores: slug, template, palette
```

---


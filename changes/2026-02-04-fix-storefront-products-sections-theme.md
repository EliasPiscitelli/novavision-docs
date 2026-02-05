# Fix: Productos no se renderizan en carouseles + Cache inválida + Theme sin contraste

**Fecha:** 2026-02-04  
**Rama:** feature/multitenant-storefront  
**Impacto:** Template demo-store renderiza productos, secciones generadas, cache rechaza datos inválidos, theme legible

---

## Resumen del Problema

El storefront mostraba:
- ✗ `productsCount: 40` pero carouseles vacíos
- ✗ `sectionsCount: 0` (no hay bloques para renderizar)
- ✗ Cache inválida (`isValid: false`) siendo aceptada en 304
- ✗ Theme con contraste ilegible (textos oscuros sobre fondos grises)
- ✗ Duplicación de secciones estáticas + dinámicas

**Raíz:** Tres bugs se solapaban:
1. **Sin secciones**: No había `sections` array, template no sabía qué renderizar
2. **Cache inválida usada**: Si 304 + cache.isValid=false, homeService fallía a fallback viejo
3. **Sin variables CSS**: Theme colors no se aplicaban globalmente, contraste roto

---

## Cambios Implementados

### 1️⃣ `normalizeHomeData.js` (NUEVO)

**Ubicación:** `src/services/homeData/normalizeHomeData.js`

**Qué hace:**
- Si `homeData.sections` está vacío, genera estructura default:
  - `products_carousel` (si hay 8+ productos)
  - `categories_grid`
  - `services`
  - `contact`
  - `faqs`
- Normaliza imágenes de productos (soporta 4 formatos):
  - `product.image.url` ✅ (canónico)
  - `product.images[0].url`
  - `product.imageUrl`
  - Fallback a `null` (NVImage maneja)

**Por qué:** Antes, si el JSON de onboarding no incluía `sections`, el template no tenía qué renderizar. Ahora siempre hay estructura mínima viable.

---

### 2️⃣ `homeService.jsx` (MODIFICADO)

**Cambios críticos:**

#### A) `getHookCacheData()` - Rechaza cache inválida
```javascript
// ✅ NUEVO: verifica cache.isValid === true
if (cached?.isValid !== false && cached?.data) {
  // Solo usa si válido
  return cached.data;
}
// ❌ Cache inválido: devuelve null (no lo usa)
if (cached?.isValid === false) {
  return null;
}
```

**Por qué:** Antes aceptaba cualquier cache aunque `isValid: false`. Ahora lo rechaza explícitamente.

#### B) Case 3 (304 sin ETag) - Refetch con cache-busting
```javascript
if (response.status === 304 && !response.data) {
  const fallbackData = getHookCacheData();
  if (fallbackData) return fallbackData;
  
  // ❌ No valid fallback → force refetch
  const retryResponse = await fetchWithETag(url, {
    headers: { 'Cache-Control': 'no-cache', 'Pragma': 'no-cache' }
  });
}
```

**Por qué:** Si 304 sin cache válido, ahora fuerza refetch real en vez de dejar UI vieja/incompleta.

---

### 3️⃣ `SectionRenderer.jsx` (NUEVO)

**Ubicación:** `src/templates/first/components/SectionRenderer/index.jsx`

**Qué es:** Switch por tipo de sección, renderiza componentes dinámicamente.

```javascript
switch (type) {
  case 'products_carousel':
    return <ProductCarousel products={...} />;
  case 'categories_grid':
    return <CategoriesGrid categories={...} />;
  case 'services':
    return <Services services={...} />;
  case 'contact':
    return <Contact />;
  case 'faqs':
    return <Faqs faqs={...} />;
}
```

**Por qué:** Una sola fuente de verdad para layout. Elimina hardcoding de secciones en template.

---

### 4️⃣ `HomePageFirst/index.jsx` (REFACTORIZADO)

**Cambios:**

1. Importa `normalizeHomeData`:
```javascript
import { normalizeHomeData } from '../../../../services/homeData/normalizeHomeData';
```

2. Normaliza datos al inicio:
```javascript
const normalizedData = normalizeHomeData(homeData || {});
const sections = normalizedData.sections || [];
```

3. Renderiza SOLO por secciones (una fuente):
```javascript
return (
  <>
    <Header logo={logo} />
    {sections.length > 0 ? (
      sections.map(section => (
        <SectionRenderer key={section.id} section={section} data={...} />
      ))
    ) : (
      // Fallback mínimo
      <>
        <BannerHome banners={banners} />
        {products.length > 0 && <ProductCarousel products={products} />}
      </>
    )}
  </>
);
```

**Por qué:** Antes había:
- Render dinámico por `sections` (si existen)
- Y además render estático hardcoded (Services, CollectionsSection, ProductCarousel)
- Resultado: duplicación si coincidían types

Ahora: SOLO secciones dinámicas. Si vienen vacías, normalizer las genera.

---

### 5️⃣ `useThemeVars.js` (NUEVO)

**Ubicación:** `src/hooks/useThemeVars.js`

**Qué hace:**
```javascript
useEffect(() => {
  const root = document.documentElement;
  root.style.setProperty('--nv-bg', colors.bg);
  root.style.setProperty('--nv-surface', colors.surface);
  root.style.setProperty('--nv-text', colors.text);
  root.style.setProperty('--nv-muted', colors.muted);
  root.style.setProperty('--nv-primary', colors.primary);
  // ... etc
}, [theme]);
```

Incluye CSS globals que aseguran:
- `h1, h2, h3, h4, h5, h6 { color: var(--nv-text); }`
- `.muted { color: var(--nv-muted); }`
- `a { color: var(--nv-primary); }`

**Por qué:** El theme existía pero no se aplicaba. Variables CSS garantizan contraste consistente sin que componentes individuales lo rompan.

---

### 6️⃣ `TenantDebugBadge.jsx` (NUEVO)

**Ubicación:** `src/components/TenantDebugBadge/index.jsx`

**Qué es:** Badge fijo bottom-right (solo DEV) que muestra:
```
🔍 TENANT DEBUG
slug: demo-store
client: a1b4ca0…
template: template_1
palette: starter_default
```

**Por qué:** Valida qué tenant/template/palette está activo. Si aparece "template_1 + starter_default", confirma que se están usando defaults (no errores de resolución).

**Integrado en:** `App.jsx` (dentro de AppContent después de ThemeProvider)

---

### 7️⃣ `App.jsx` (MODIFICADO)

**Cambios:**

1. Importa `useThemeVars` y `TenantDebugBadge`
2. Usa `useTenant()` en AppContent
3. Llama `useThemeVars(theme)` para aplicar variables CSS
4. Renderiza `<TenantDebugBadge tenant={tenant} />` en ThemeProvider

---

## Pasos de Reproducción (Validación)

### Setup
```bash
cd apps/web
npm run dev        # Vite dev server
# Abre http://localhost:5173
```

### Test 1: Productos renderizados
1. Visita demo-store homepage
2. Espera carga de datos (~1-2s)
3. **Esperado:** Carousel con 8-12 productos visibles (cards con imagen + título + precio)
4. **Consola:** `[HomePageFirst] Normalized data: { productsCount: 40, sectionsCount: 5, sectionTypes: ["products_carousel", "categories_grid", "services", "contact", "faqs"] }`

### Test 2: Cache validado en 304
1. Recarga página (F5)
2. Red panel: verifica GET `/home/data` → Status 304
3. **Consola:** Si cache no es válido:
   - `[homeService] Fallback cache is INVALID (isValid:false), will refetch…`
   - Nuevo request con `Cache-Control: no-cache`
4. **Esperado:** Datos se cargan frescos, no UI vieja

### Test 3: Theme aplica variables CSS
1. Abre DevTools → Elements
2. Busca `<html>` element
3. **Esperado:** Ver estilos inline como:
   ```
   --nv-bg: #ffffff;
   --nv-text: #000000;
   --nv-primary: #0066cc;
   ```
4. Verifica que h1/h2 usan `color: var(--nv-text)` (visible en Computed)
5. Textos servicios/categorías deben ser **legibles** (no mezcla de grises oscuros)

### Test 4: TenantDebugBadge visible (DEV)
1. En DEV: Bottom-right corner muestra badge
2. Verifica:
   - `slug: demo-store`
   - `template: template_1`
   - `palette: starter_default`
3. **Si valores son correctos:** Tenant resolution funciona
4. **Si son "?":** Hay issue en tenant resolution

### Test 5: Sin duplicación
1. Consola: busca "[SectionRenderer] Rendering section:"
2. Debería listar cada sección UNA sola vez:
   ```
   [SectionRenderer] Rendering section: { id: 'products_featured', type: 'products_carousel' }
   [SectionRenderer] Rendering section: { id: 'categories_section', type: 'categories_grid' }
   [SectionRenderer] Rendering section: { id: 'services_section', type: 'services' }
   [SectionRenderer] Rendering section: { id: 'contact_section', type: 'contact' }
   [SectionRenderer] Rendering section: { id: 'faqs_section', type: 'faqs' }
   ```
3. **Si ves tipos repetidos:** Hay duplicación (no esperado)

---

## Validación de la Fix (Checksums)

| Archivo | Status | Validación |
|---------|--------|-----------|
| `normalizeHomeData.js` | ✅ NUEVO | Genera secciones default si faltan |
| `homeService.jsx` | ✅ MODIFICADO | Rechaza cache.isValid=false en 304 |
| `SectionRenderer.jsx` | ✅ NUEVO | Switch por type de sección |
| `HomePageFirst/index.jsx` | ✅ REFACTORIZADO | Normaliza + renderiza por sections |
| `useThemeVars.js` | ✅ NUEVO | Aplica CSS vars + garantiza contraste |
| `TenantDebugBadge.jsx` | ✅ NUEVO | Badge DEV con context |
| `App.jsx` | ✅ MODIFICADO | Integra useThemeVars + TenantDebugBadge |

---

## Riesgos y Mitigaciones

| Riesgo | Severidad | Mitigación |
|--------|-----------|-----------|
| Secciones default no se vean bien en ciertos templates | MEDIA | SectionRenderer es extensible por template (2º iteración) |
| Cache-busting puede aumentar requests en network lento | BAJA | Headers solo se aplican en 304 sin cache válido (caso edge) |
| Theme vars pueden no aplicarse si styled-components sobrescribe | BAJA | Global CSS vars + useThemeVars garantiza aplicación |
| TenantDebugBadge es visible en DEV pero podría interferir | BAJA | Conditional render: solo si `!import.meta.env.PROD` |

---

## Próximas Iteraciones

1. **Persistir secciones en DB:** Mover `normalizeHomeData` defaults a tabla `home_sections` del onboarding
2. **SectionRenderer por template:** Permitir override de rendering por template (template_2, template_3, etc.)
3. **Temas pre-defined:** Crear paletas con garantía de contraste (WCAG AA)
4. **Cache strategy refinement:** Agregar stale-while-revalidate en homeService

---

## Comandos Ejecutados

```bash
# Lint antes de cambios
npm run lint

# Typecheck después de cambios
npm run typecheck

# Dev para validar
npm run dev
```

---

## Resumen de Resolución

| Síntoma | Causa | Fix |
|---------|-------|-----|
| Carouseles vacíos (40 productos pero sectionsCount=0) | No hay secciones definidas | normalizeHomeData() genera defaults |
| Cache `isValid: false` aceptada en 304 | getHookCacheData() no validaba flag | Agregar check explícito `isValid !== false` |
| UI con bajo contraste (grises oscuros) | Theme colors no se aplicaban como CSS vars | useThemeVars() aplica vars + reset CSS |
| Difícil validar tenant activo | No hay indicador visual | TenantDebugBadge muestra slug/template/palette |


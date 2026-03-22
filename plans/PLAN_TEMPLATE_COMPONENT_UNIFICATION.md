# Plan: Unificacion de Componentes de Templates

> Fecha: 2026-03-18
> Prioridad: Alta — Deuda tecnica critica
> Repos afectados: `@nv/web`
> Relacion: Complementa `PLAN_COMPONENT_CATALOG_TOKEN_PRICING.md` (fluffy-jingling-peach)

---

## 1. Problema

### Estado actual

La arquitectura de templates tiene **130+ archivos** distribuidos en 8 templates con **6,000+ lineas de codigo duplicado**. Cada template reimplementa los mismos componentes con variaciones minimas.

```
templates/
├── first/    (9 componentes, 19 archivos)
├── second/   (15 componentes, 37 archivos) ← MAS COMPLEJO
├── third/    (8 componentes, 17 archivos)
├── fourth/   (11 componentes, 15 archivos)
├── fifth/    (10 componentes, 19 archivos)
├── sixth/    (8 componentes, 8 archivos)
├── seventh/  (7 componentes, 7 archivos)
└── eighth/   (8 componentes, 8 archivos)
```

### Impacto medido

**Caso real: Agregar badge "Agotado" a ProductCard**

| Metrica | Sin unificar | Con unificacion |
|---------|-------------|-----------------|
| Archivos a modificar | 8-10 | 1-2 |
| Lineas a revisar | ~800 | ~150 |
| Riesgo inconsistencia | Alto | Bajo |
| Tiempo | 30-45 min | 5 min |
| Templates omitidos por error | Frecuente | Imposible |

### Factor de duplicacion por componente

| Componente | Copias | Lineas min-max | Duplicacion |
|-----------|--------|----------------|-------------|
| ProductCard | 5 | 76-338 | 3.2x |
| Header | 5 | 168-731 | 3.4x |
| ContactSection | 6 | 147-421 | 2.9x |
| FAQSection | 6 | 101-192 | 1.9x |
| Footer | 6 | 251-681 | 2.7x |
| ProductCarousel | 3 | 143-229 | 1.6x |
| ServicesSection | 7 | 74-250 | 3.4x |

---

## 2. Solucion: Componentes base con variantes

### Arquitectura propuesta

```
src/
├── components/
│   ├── storefront/                    ← NUEVO: componentes unificados
│   │   ├── ProductCard/
│   │   │   ├── index.tsx              ← Logica unica
│   │   │   ├── variants/
│   │   │   │   ├── simple.tsx         ← Visual: first, third
│   │   │   │   ├── interactive.tsx    ← Visual: second (hover cart)
│   │   │   │   ├── full.tsx           ← Visual: fourth, fifth (badges, filtros)
│   │   │   │   └── showcase.tsx       ← Visual: sixth, seventh, eighth
│   │   │   ├── parts/
│   │   │   │   ├── PriceBadge.tsx
│   │   │   │   ├── StockBadge.tsx
│   │   │   │   ├── FavoriteButton.tsx
│   │   │   │   └── CartButton.tsx
│   │   │   └── styles.ts
│   │   ├── FAQSection/
│   │   │   ├── index.tsx
│   │   │   └── variants/
│   │   │       ├── accordion.tsx
│   │   │       ├── cards.tsx
│   │   │       └── tabs.tsx
│   │   ├── ContactSection/
│   │   ├── ServicesSection/
│   │   ├── ProductCarousel/
│   │   └── Footer/
│   └── ... (existentes)
├── templates/
│   ├── first/
│   │   └── config.ts                  ← Solo mapeo de variantes
│   └── ...
```

### API del componente unificado

```tsx
// Ejemplo: ProductCard unificado
interface ProductCardProps {
  product: NormalizedProduct;
  variant: 'simple' | 'interactive' | 'full' | 'showcase';
  features?: {
    showFavorites?: boolean;
    showQuickCart?: boolean;
    showStockBadge?: boolean;
    showRating?: boolean;
    showCategories?: boolean;
  };
  onAddToCart?: (product: NormalizedProduct) => void;
  onToggleFavorite?: (product: NormalizedProduct) => void;
}

// Uso en template config
const FIRST_TEMPLATE_CONFIG = {
  productCard: {
    variant: 'simple',
    features: { showRating: true, showStockBadge: true },
  },
  faq: { variant: 'accordion' },
  contact: { variant: 'cards', enableForm: true },
};
```

---

## 3. Fases de ejecucion

### Fase 1: ProductCard unificado (Prioridad maxima)

**Por que primero:** Es el componente mas duplicado (5 copias) y el que mas bugs cross-template genera (ej: badge Agotado requirio editar 8 archivos).

#### Paso 1.1: Normalizar datos de producto

Crear un `normalizeProduct()` util que unifique los distintos formatos de precio, stock e imagen que usa cada template.

**Archivo:** `src/utils/normalizeProduct.ts`

```typescript
interface NormalizedProduct {
  id: string;
  name: string;
  description?: string;
  slug?: string;
  imageUrl: string;            // imagen principal resuelta
  images: ImageVariant[];      // todas las imagenes
  originalPrice: number;
  discountedPrice: number;
  hasDiscount: boolean;
  discountPercent: number;
  stock: number;
  isOutOfStock: boolean;
  isAvailable: boolean;
  categories: string[];
  avgRating?: number;
  reviewCount?: number;
}

function normalizeProduct(raw: any): NormalizedProduct {
  const stock = Number(raw.quantity ?? raw.stock ?? 0);
  const isAvailable = raw.available !== false && stock > 0;
  const orig = Number(raw.originalPrice ?? raw.price ?? raw.original_price ?? 0);
  const disc = Number(raw.discountedPrice ?? raw.priceWithDiscount ?? 0);

  return {
    id: raw.id,
    name: raw.name || raw.title || '',
    description: raw.description || '',
    slug: raw.slug || '',
    imageUrl: getMainImage(raw) || '/broken.png',
    images: normalizeImages(raw.imageUrl ?? raw.image_variants ?? []),
    originalPrice: orig,
    discountedPrice: disc > 0 && disc < orig ? disc : 0,
    hasDiscount: disc > 0 && disc < orig,
    discountPercent: disc > 0 && orig > 0 ? Math.round((1 - disc / orig) * 100) : 0,
    stock,
    isOutOfStock: stock <= 0,
    isAvailable,
    categories: normalizeCategories(raw),
    avgRating: raw.avg_rating,
    reviewCount: raw.review_count,
  };
}
```

**Contexto:** Hoy cada template hace su propia normalizacion de precios/stock. El fourth template tiene 30+ lineas solo para esto. El fifth tiene 50+. Con un util compartido, todos convergen.

#### Paso 1.2: Extraer partes reutilizables

Componentes atomicos que todas las variantes comparten:

| Part | Responsabilidad | Lineas estimadas |
|------|----------------|-----------------|
| `StockBadge` | "Agotado" badge + opacity | 25 |
| `PriceBadge` | Precio con/sin descuento | 40 |
| `FavoriteButton` | Toggle favorito | 30 |
| `CartButton` | Agregar al carrito + toast | 50 |
| `DiscountBadge` | Badge -X% | 20 |

#### Paso 1.3: Crear variantes visuales

| Variante | Templates que la usan | Diferencia clave |
|----------|----------------------|-----------------|
| `simple` | first, third | Solo imagen + nombre + precio |
| `interactive` | second | Hover muestra cart, desktop/mobile split |
| `full` | fourth, fifth | Badges multiples, filtros, motion |
| `showcase` | sixth, seventh, eighth | Galeria, layout horizontal |

#### Paso 1.4: Migrar templates uno a uno

Orden de migracion (de menor a mayor complejidad):

1. **third** (76 lineas) — mas simple, ideal para validar
2. **first** (81 lineas) — similar a third
3. **generic** (`/components/ProductCard`) — ya parcialmente unificado
4. **second** (169 lineas) — agrega logica desktop/mobile
5. **fifth** (338 lineas) — mas complejo, validar que no se pierda nada
6. **fourth** (277 lineas) — usa theme system propio

**Cada migracion:**
1. Reemplazar import por el componente unificado
2. Pasar props de configuracion
3. Verificar visual con `vite build` + manual
4. Eliminar archivos viejos

#### Paso 1.5: Limpiar archivos obsoletos

Archivos a eliminar post-migracion:
- `templates/first/components/ProductCard/` (2 archivos)
- `templates/second/components/ProductCard/` (3 archivos)
- `templates/third/components/ProductCard/` (2 archivos)
- `templates/fourth/components/ProductCard.jsx` (1 archivo)
- `templates/fifth/components/ProductCard/` (2 archivos)
- `components/ProductCard/` (2 archivos)

**Total: ~12 archivos eliminados, ~950 lineas removidas**

---

### Fase 2: FAQSection unificado

**Justificacion:** 85% de similitud entre 6 implementaciones. Cambio simple de extraer.

#### Variantes

```tsx
<FAQSection
  items={faqs}
  variant="accordion"     // first, third, fourth, fifth
  variant="cards"          // sixth, seventh
  variant="masonry"        // eighth
  animation={true}
/>
```

#### Archivos a eliminar: 6 archivos, ~750 lineas

---

### Fase 3: ContactSection unificado

**Justificacion:** 80% similitud. Todas consumen los mismos datos de `contact_info` + `social_links`.

#### Variantes

```tsx
<ContactSection
  contactInfo={data}
  socialLinks={social}
  variant="cards"          // first, third
  variant="two-column"     // fourth, sixth, eighth
  variant="minimal"        // fifth, seventh
  enableForm={true}
  enableWhatsApp={true}
/>
```

#### Archivos a eliminar: 6 archivos, ~1,100 lineas

---

### Fase 4: Footer unificado *(movido desde Fase 6 — ver §9.4)*

**Justificacion:** 75% similitud, 6 copias, alta frecuencia de cambios (links legales, social links, contacto). Templates 6/7/8 ya comparten estructura en `sections/footer/`.

#### Variantes

```tsx
<Footer
  contactInfo={data}
  socialLinks={social}
  variant="columns"        // first, third (multi-columna clasico)
  variant="stacked"        // fourth, fifth (apilado, minimalista)
  variant="branded"        // sixth (Drift), seventh (Vanguard), eighth (Lumina)
  showNewsletter={true}
  showLegalLinks={true}
/>
```

#### Archivos a eliminar: 6 archivos, ~1,000 lineas

---

### Fase 5: ServicesSection unificado *(antes Fase 4)*

**Justificacion:** 70% similitud. Patron comun: grid de cards con icono/imagen + titulo + descripcion.

#### Variantes

```tsx
<ServicesSection
  services={data}
  variant="grid"           // first, third, fifth
  variant="cards-hover"    // fourth, sixth, eighth
  variant="minimal"        // seventh
  columns={3}
/>
```

#### Archivos a eliminar: 7 archivos, ~800 lineas

---

### Fase 6: ProductCarousel unificado *(antes Fase 5)*

**Justificacion:** 90% de codigo identico entre first, third, fifth.

#### Archivos a eliminar: 3 archivos, ~400 lineas

---

### Fase 7 (futura): Header unificado

**NO incluir en este sprint.** Razon:
- Variacion de 168 a 731 lineas (3.4x)
- Headers de templates nuevos usan `sections/header/ClassicHeader`
- Templates viejos (first-fifth) tienen headers totalmente custom
- Riesgo de regresion muy alto

**Recomendacion:** Migrar gradualmente templates viejos a `ClassicHeader` cuando se refactorize cada template.

---

## 4. Relacion con Component Catalog (fluffy-jingling-peach)

El plan de `component_catalog` en BD define **que componentes existen y cuanto cuestan en tokens**. Este plan define **como se implementan esos componentes en codigo**.

### Sinergia

```
component_catalog (BD)           Template Config (codigo)
┌─────────────────────┐         ┌────────────────────────┐
│ key: 'faq.accordion' │ ──────> │ variant: 'accordion'   │
│ min_plan: 'starter'  │         │ component: FAQSection  │
│ token_cost: 1        │         └────────────────────────┘
└─────────────────────┘

┌─────────────────────┐         ┌────────────────────────┐
│ key: 'faq.cards'     │ ──────> │ variant: 'cards'       │
│ min_plan: 'growth'   │         │ component: FAQSection  │
│ token_cost: 2        │         └────────────────────────┘
└─────────────────────┘
```

Con componentes unificados, el `component_catalog` puede referenciar variantes directamente, haciendo que el DesignStudio solo necesite cambiar un prop `variant` en vez de reemplazar componentes enteros.

### Orden de dependencia

1. **Primero:** Este plan (unificar componentes) — reduce superficie de codigo
2. **Despues:** Component Catalog en BD — gestiona variantes desde admin
3. **Resultado:** Cambiar un componente en DesignStudio = cambiar 1 prop

---

## 5. Estimacion de esfuerzo

| Fase | Componente | Dias estimados | Lineas eliminadas |
|------|-----------|---------------|-------------------|
| 0 | Setup (baselines + theme contract + skeletons) | 2-3 | 0 |
| 1 | ProductCard | 4-5 | ~950 |
| 2 | FAQSection | 1-2 | ~750 |
| 3 | ContactSection | 2-3 | ~1,100 |
| 4 | Footer *(movido)* | 3-4 | ~1,000 |
| 5 | ServicesSection | 2 | ~800 |
| 6 | ProductCarousel | 1 | ~400 |
| **Total** | | **15-20 dias** | **~5,000 lineas** |

> **Nota:** La estimacion ajustada (+3-4 dias vs. original) contempla setup de baselines
> de screenshots, creacion del theme contract, skeletons por variante, y debugging
> de edge cases cross-template. Ver §9.6 para el desglose del delta.

### ROI esperado

- **Inmediato:** Fix cross-template pasa de 8-10 archivos a 1-2
- **Corto plazo:** Nuevos features (ej: image navigation en cards) se implementan 1 vez
- **Largo plazo:** Onboarding de nuevos devs es significativamente mas rapido
- **Testing:** 1 suite de tests por componente en vez de 5 duplicadas

---

## 6. Criterios de exito

### Por fase
- [ ] Build pasa sin errores
- [ ] Visual identico al estado actual (screenshot comparison)
- [ ] Todos los templates renderean correctamente
- [ ] Archivos duplicados eliminados
- [ ] 0 regresiones en E2E tests

### General
- [ ] Reduccion de 5,000+ lineas de codigo
- [ ] ProductCard: 1 componente base + 4 variantes (reemplaza 5 implementaciones)
- [ ] Un fix de UI se aplica una sola vez y funciona en todos los templates
- [ ] `component_catalog` puede referenciar variantes por key

---

## 7. Riesgos y mitigaciones

| Riesgo | Probabilidad | Mitigacion |
|--------|-------------|------------|
| Regresion visual en template especifico | Alta | Screenshot testing + build por template |
| Performance por componente mas grande | Baja | Tree-shaking + lazy variants |
| Resistencia a eliminar codigo "que funciona" | Media | Demostrar con metricas de bugs (badge Agotado) |
| Props explosion (demasiadas opciones) | Media | Limitar a 4 variantes max por componente |
| Template nuevo no encaja en variantes | Baja | Siempre permitir variante custom |
| Componentes no consumen theme pipeline | Alta | Contrato obligatorio con `resolveEffectiveTheme` (ver §9.1) |
| Feature-gating desconectado de variantes | Media | Conectar `useEffectivePlanConfig` con variant resolution (ver §9.2) |

---

## 8. Verificacion

### Build
```bash
npx vite build          # 0 errores
```

### Visual — Estrategia de regresion (ver §9.3)

**Herramienta:** Playwright visual regression (ya existe `novavision-e2e` con Playwright)

**Matriz de screenshots:**

| Template | Viewports | Componentes verificados |
|----------|-----------|------------------------|
| first-eighth (8) | 1440px, 768px, 375px | ProductCard, FAQ, Contact, Services, Footer |

**Total: 8 × 3 × 5 = 120 screenshots base**

**Proceso por fase:**
1. **Antes de migrar:** Capturar baseline screenshots de cada template × viewport × componente
2. **Despues de migrar:** Capturar nuevos screenshots
3. **Diff automatico:** Playwright `toHaveScreenshot()` con threshold < 1%
4. **CI gate:** Si el diff supera el threshold, el pipeline falla

```bash
# Capturar baselines (una vez, antes de iniciar)
npx playwright test --update-snapshots --project=visual-regression

# Validar despues de cada fase
npx playwright test --project=visual-regression
```

**Script de smoke visual por template:**
```bash
# Levantar cada template y verificar render
for t in first second third fourth fifth sixth seventh eighth; do
  TEMPLATE_KEY=$t npm run dev &
  npx playwright test visual/$t.spec.ts
  kill %1
done
```

### E2E
```bash
npm run test:e2e        # Checkout, carrito, navegacion
```

### Metricas
- Contar archivos en `templates/*/components/` antes y despues
- Contar lineas de codigo duplicadas con `jscpd` o similar

---

## 9. Gaps identificados y correcciones

> Analisis post-redaccion — gaps detectados en la version original del plan
> que deben resolverse ANTES de iniciar la implementacion.

### 9.1 Gap: Sin contrato con el theme system

**Problema:** El plan propone componentes unificados pero no define como consumen el theme pipeline existente (`resolveEffectiveTheme` → 400+ propiedades → `ThemeProvider`). Si los componentes nuevos no respetan este contrato, rompen la cadena de personalizacion.

**Arquitectura real del theme pipeline:**
```
Backend DB (clients.theme_config, clients.template_id)
    ↓
API /home/data → { templateKey, paletteKey, themeConfig, paletteVars }
    ↓
resolveEffectiveTheme() — 5 pasos:
  1. Normalize: template_1 → first (key mapping)
  2. Resolve: paletteKey → PALETTES[key] (6 tokens)
  3. Create: createTheme(template, overrides) (400+ props)
  4. Merge: base + palette + paletteVars + themeConfig
  5. Freeze: deepFreeze() → inmutable
    ↓
<ThemeProvider theme={theme}> → styled-components context
    ↓
useThemeVars() → CSS custom properties en <html>
  --nv-primary, --nv-bg, --nv-surface, --nv-text, --nv-border (27 tokens)
```

**Correccion:** Todo componente unificado DEBE:

1. **Consumir theme via `styled-components` context** — nunca hardcodear colores
2. **Usar CSS custom properties (`--nv-*`)** como primera opcion, con fallback a `theme.*`
3. **Respetar `legacyAdapter`** para componentes que aun usan `theme.header`, `theme.button`

**Contrato de variante:**
```tsx
// CORRECTO: la variante solo define layout/estructura
const SimpleVariant = styled.div`
  display: grid;
  grid-template-rows: auto 1fr auto;
  border-radius: var(--nv-radius, 8px);

  /* Colores SIEMPRE del theme, nunca hardcodeados */
  background: var(--nv-surface);
  color: var(--nv-text);
  border: 1px solid var(--nv-border);
`;

// INCORRECTO: variante define colores propios
const SimpleVariant = styled.div`
  background: #ffffff;   // ← ROMPE personalizacion
  color: #333;           // ← ROMPE dark mode
`;
```

**Archivo a crear:** `src/components/storefront/theme-contract.ts`
```typescript
// Tokens CSS que todo componente storefront DEBE usar
export const STOREFRONT_TOKENS = {
  bg: 'var(--nv-bg)',
  surface: 'var(--nv-surface)',
  primary: 'var(--nv-primary)',
  text: 'var(--nv-text)',
  border: 'var(--nv-border)',
  accent: 'var(--nv-accent, var(--nv-primary))',
} as const;

// Validacion en dev: warn si un componente usa colores hardcodeados
// (implementar como ESLint rule o runtime check)
```

### 9.2 Gap: config.ts demasiado simple para feature-gating

**Problema:** El plan propone `config.ts` por template con solo mapeo de variantes:
```tsx
const FIRST_CONFIG = {
  productCard: { variant: 'simple' },
  faq: { variant: 'accordion' },
};
```

Pero esto no conecta con:
- **Entitlements del plan** (`useEffectivePlanConfig` → `maxProducts`, `maxFaqs`, etc.)
- **Component catalog en BD** (`component_catalog.min_plan`)
- **Feature flags** (que variantes estan disponibles segun el plan)

**Arquitectura real de gating:**
```
useEffectivePlanConfig() → {
  planKey: 'professional',
  maxProducts: 2000,
  maxFaqs: 20,
  maxServices: 15,
  customDomain: true,
  // ... 15+ campos
}
```

**Correccion:** El config debe ser un **resolutor**, no un objeto estatico:

```typescript
// src/components/storefront/resolveVariant.ts
import type { PlanLimits } from 'hooks/useEffectivePlanConfig';

interface VariantConfig {
  variant: string;
  features: Record<string, boolean>;
}

/**
 * Resuelve la variante efectiva de un componente considerando:
 * 1. Template default (que variante usa este template por defecto)
 * 2. Plan entitlements (que variantes permite el plan del cliente)
 * 3. Component catalog (si la variante requiere un plan minimo)
 * 4. Override del cliente (si el admin eligio una variante especifica)
 */
export function resolveVariant(
  componentKey: string,
  templateKey: string,
  planLimits: PlanLimits,
  clientOverride?: string,
): VariantConfig {
  const templateDefault = TEMPLATE_DEFAULTS[templateKey]?.[componentKey];
  const requested = clientOverride || templateDefault?.variant || 'simple';

  // Verificar si el plan permite esta variante
  const catalogEntry = componentCatalog[`${componentKey}.${requested}`];
  if (catalogEntry?.min_plan && !planMeetsMinimum(planLimits.planKey, catalogEntry.min_plan)) {
    // Downgrade a la variante mas cercana permitida
    return { variant: templateDefault?.variant || 'simple', features: {} };
  }

  return { variant: requested, features: templateDefault?.features || {} };
}
```

### 9.3 Gap: Sin estrategia de testing visual

**Problema:** La seccion 8 original solo decia "comparar screenshots" sin definir herramienta, proceso ni CI gate. Para un cambio que toca 8 templates × 7 componentes, la validacion visual es critica.

**Correccion:** Ver seccion 8 actualizada arriba — estrategia completa con Playwright visual regression, matriz de 120 screenshots, y CI gate con threshold.

### 9.4 Gap: Footer deberia ir antes en el orden de fases

**Problema:** El plan pone Footer en Fase 6 (penultimo) porque tiene "variaciones visuales significativas" y templates 6/7/8 tienen footers con nombres propios (Drift, Vanguard, Lumina). Pero el Footer es un componente de alta frecuencia de cambios (links legales, social links, info de contacto cambian seguido) y tiene un factor de duplicacion de 2.7x con 6 copias.

**Correccion:** Mover Footer a **Fase 4** (despues de ContactSection). Razon: los footers de T6/T7/T8 ya comparten estructura con `sections/footer/` y pueden convertirse en variantes facilmente. La complejidad visual se maneja con variantes `columns`, `stacked`, `branded`.

**Nuevo orden de fases:**

| Fase | Componente | Justificacion del orden |
|------|-----------|------------------------|
| 1 | ProductCard | Mas duplicado, mas bugs cross-template |
| 2 | FAQSection | 85% similitud, cambio simple |
| 3 | ContactSection | 80% similitud, consume mismos datos |
| 4 | Footer | Alta frecuencia de cambios, 6 copias (antes era Fase 6) |
| 5 | ServicesSection | 70% similitud, patron grid uniforme |
| 6 | ProductCarousel | 90% identico, solo 3 copias (antes era Fase 5) |
| 7 | Header | Sin cambios — sigue fuera de este sprint |

### 9.5 Gap: Sin estado de loading por variante

**Problema:** El plan no contempla skeletons/loading states por variante. Hoy cada template tiene (o no tiene) su propio skeleton. Con componentes unificados, el skeleton debe ser parte del componente.

**Correccion:** Cada componente unificado debe exportar un `Skeleton` companion:

```tsx
// src/components/storefront/ProductCard/index.tsx
export { default as ProductCard } from './ProductCard';
export { default as ProductCardSkeleton } from './ProductCardSkeleton';

// ProductCardSkeleton.tsx
export default function ProductCardSkeleton({ variant }: { variant: VariantKey }) {
  const Layout = SKELETON_VARIANTS[variant] || SimpleCardSkeleton;
  return <Layout />;
}
```

**Regla:** Si un componente tiene variante `X`, debe tener skeleton `X`. El skeleton respeta la misma estructura visual que la variante real.

### 9.6 Gap: Estimacion de tiempo optimista

**Problema:** El plan estima 12-16 dias para 7 fases. Esto no contempla:
- Creacion de baselines de screenshots (1-2 dias)
- Debugging de edge cases cross-template (alto riesgo con ProductCard)
- Ajustes de theme contract (variantes que usan colores hardcodeados hoy)
- Testing de regresion en N templates × M viewports

**Correccion:** Estimacion ajustada:

| Fase | Original | Ajustada | Delta |
|------|----------|----------|-------|
| Setup (baselines + contrato) | 0 | 2-3 | +2-3 |
| 1. ProductCard | 3-4 | 4-5 | +1 |
| 2. FAQSection | 1-2 | 1-2 | 0 |
| 3. ContactSection | 2-3 | 2-3 | 0 |
| 4. Footer (movido) | 3-4 | 3-4 | 0 |
| 5. ServicesSection | 2 | 2 | 0 |
| 6. ProductCarousel | 1 | 1 | 0 |
| **Total** | **12-16** | **15-20** | **+3-4** |

El delta viene principalmente del setup (baselines + theme contract) y de la complejidad real de ProductCard (5 variantes × theme integration × skeletons).

---

## 10. Proyeccion de evolucion arquitectonica

> Tres capas de evolucion que este plan habilita a futuro.
> No son parte del sprint actual, pero las decisiones de ahora
> deben ser compatibles con estas capas.

### Capa 1: Variantes como entidades en BD

**Estado actual:** Las variantes son codigo estatico (`variant: 'simple'`).
**Evolucion:** El `component_catalog` en BD ya tiene la estructura para mapear `key: 'faq.accordion'` → `min_plan: 'starter'`. Con componentes unificados, el DesignStudio puede:

```
component_catalog (BD)                    Frontend
┌──────────────────────────┐             ┌─────────────────────┐
│ key: 'productCard.full'  │ ──resolve──>│ variant: 'full'     │
│ min_plan: 'growth'       │             │ features: {...}     │
│ token_cost: 3            │             │ component: <Card/>  │
└──────────────────────────┘             └─────────────────────┘
```

**Compatibilidad requerida:** Los componentes unificados deben aceptar `variant` como string resuelto externamente, no como enum hardcodeado.

### Capa 2: CSS Custom Properties API

**Estado actual:** 27 tokens CSS (`--nv-primary`, `--nv-bg`, etc.) inyectados por `useThemeVars`.
**Evolucion:** Expandir a tokens por componente:

```css
/* Tokens globales (ya existen) */
--nv-primary: #1D4ED8;
--nv-surface: #ffffff;

/* Tokens por componente (futuros) */
--nv-card-radius: 12px;
--nv-card-shadow: 0 2px 8px rgba(0,0,0,0.08);
--nv-faq-gap: 1rem;
--nv-footer-bg: var(--nv-surface);
```

**Compatibilidad requerida:** Los componentes unificados deben usar CSS custom properties (no `theme.*` directo) para que este override funcione sin rebuild.

### Capa 3: Edicion IA de componentes

**Estado actual:** La IA genera imagenes y descripciones.
**Evolucion:** Con componentes unificados + catalog en BD + CSS tokens, la IA podria:

1. Sugerir variantes segun el rubro del negocio
2. Ajustar tokens de color/spacing basado en la identidad de marca
3. Generar combinaciones template + palette + variantes optimizadas

**Compatibilidad requerida:** Las variantes deben ser deterministas (mismo input → mismo output) para que la IA pueda predecir el resultado visual.

---

## 11. Auditoria de colores hardcodeados (pre-migracion)

> Grep ejecutado 2026-03-18 sobre los componentes target.
> Esta auditoria debe repetirse ANTES de cada fase para verificar que la migracion
> no arrastra colores hardcodeados al componente unificado.

### Resumen por componente target

| Componente | T1 | T2 | T3 | T6 | T7 | T8 | Shared | Total |
|-----------|----|----|----|----|----|----|--------|-------|
| ProductCard | 2 | 2 | 2 | — | — | — | 3 | **9** |
| FAQSection | 4 | — | — | 6* | — | — | — | **10** |
| ContactSection | 0 | — | — | 0 | — | — | — | **0** |
| Footer | 1 | — | — | 0 | — | — | — | **1** |
| ServicesSection | — | — | — | 0 | 1 | — | — | **1** |
| ProductCarousel | — | — | — | — | — | — | — | **0** |
| **Subtotal targets** | | | | | | | | **~21** |

*T6 FAQSection: los 6 son fallbacks dentro de `var()` — patron correcto.

### Componentes NO target (deuda futura)

| Componente | T6 | T8 | Total |
|-----------|----|----|-------|
| HeroSection | 7 | 3 | **10** |
| ProductShowcase | 3 | 2 | **5** |

**Total general: ~34 colores hardcodeados** (21 en targets + 13 fuera de scope)

### Patrones criticos a corregir durante migracion

| Patron | Donde aparece | Fix requerido |
|--------|-------------|---------------|
| `color: #fff` (bare) | OutOfStockBadge en ProductCard T1/T2/T3/Shared | `color: var(--nv-primary-fg, #fff)` |
| `#333` fallback en border | FAQSection T1 (lines 85, 96) | `var(--nv-text, #1a1a2e)` |
| `rgba(0,0,0,0.08)` shadow | FAQSection T1 (line 133) | `var(--nv-shadow, rgba(0,0,0,0.08))` |
| `#e0e0e0` border | Footer T1 (line 64) | `var(--nv-border, #e5e7eb)` |
| `rgba(255,255,255,0.18)` | ServicesSection T7 (line 31) | `rgba(var(--nv-surface-rgb, 255,255,255), 0.18)` |

### Modelo a seguir

Template 6 ContactSection, FooterDrift y ServicesSection: **0% hardcodeado**.
Patron: todos los colores via `style={{ color: 'var(--nv-text, #111827)' }}` con fallback semantico.

### Regla para el componente unificado

Ningun componente unificado puede contener colores hardcodeados sin `var()` wrapper.
Checklist pre-merge por PR:

```bash
# Grep de colores hardcodeados sin var() en componentes storefront
grep -rn '#[0-9a-fA-F]\{3,8\}' src/components/storefront/ \
  | grep -v 'var(' | grep -v '\.md' | grep -v 'node_modules'
# Resultado esperado: 0 lineas
```

---

## 12. Contradicciones con el sistema real

> Verificado 2026-03-18 contra codigo fuente y schema de BD.
> Cada contradiccion tiene una clasificacion de impacto y una resolucion propuesta.

### 12.1 CORREGIDO: `client_home_settings` tiene datos reales

**Hallazgo original (incorrecto):** Se afirmo que la tabla estaba vacia.

**Correccion (2026-03-18):** Verificacion directa contra BD muestra 3 registros:

| client_id | template_key | palette_key |
|---|---|---|
| `738705a7...` | `first` | `ocean_breeze` |
| `86e59bed...` | `fifth` | `midnight_pro` |
| `1fad8213...` | `template_8` | `standard_blue` |

El tercer registro ademas tiene `design_config` con 9 secciones completas
(header, hero, catalog, features, testimonials, faq, newsletter, contact, footer)
— es un layout T8 (Lumina) completo.

**Impacto revisado:** **No es bloqueante.** Las baselines del Paso 0 capturarian
el estado real de cada tienda. El Ticket D1 queda eliminado.

**Nota:** `theme_config` esta vacio (`{}`) en los 3 registros. Esto es correcto:
las personalizaciones de color se aplican via `paletteVars` del API, no via
`theme_config` directo.

### 12.2 CORREGIDO: `nv_templates` tiene 8 registros completos

**Hallazgo original (incorrecto):** Se afirmo que solo habia 5 registros.

**Correccion (2026-03-18):** Verificacion directa contra Admin DB muestra **8 registros activos**:

| key | label | min_plan | sort_order | is_active |
|---|---|---|---|---|
| `first` | Minimal Store | starter | 1 | true |
| `second` | Modern Dark | starter | 2 | true |
| `third` | Boutique Elegant | starter | 3 | true |
| `fourth` | Tech Startup | growth | 4 | true |
| `fifth` | Industrial Pro | starter | 5 | true |
| `sixth` | Drift Premium | starter | 6 | true |
| `seventh` | Vanguard | growth | 7 | true |
| `eighth` | Lumina | growth | 8 | true |

**Impacto revisado:** **Ninguno.** El catalogo de templates esta completo.
Templates `starter`: first, second, third, fifth, sixth (5).
Templates `growth`: fourth, seventh, eighth (3).
El Ticket D2 (seed T6-T8) queda **ELIMINADO** — los datos ya existen.

### 12.3 CRITICO: Paradigma sections vs variants — conflicto no reconciliado

**Hallazgo:** El sistema existente opera con un paradigma de **sections**:

```
SectionRenderer.tsx (linea 76-77):
  rawKey = section.componentKey || section.componentId || section.type

sectionCatalog.ts (linea 79-770):
  Keys: "header.first", "hero.second", "catalog.carousel.fifth.featured"
  Metadata: { name, type, planTier, thumbnail, defaultProps }

sectionComponents.tsx (linea 141-241):
  SECTION_COMPONENTS[componentKey] → React.lazy(() => import(...))
```

El plan propone un paradigma de **variants**:

```
<ProductCard variant="simple" features={...} />
resolveVariant(componentKey, templateKey, planLimits) → VariantConfig
```

**Estos son modelos ortogonales que no tienen nexo definido.**

- Sections: `type` = semantica ("catalog"), `componentKey` = implementacion
  ("catalog.carousel.fifth.featured"). Gating via `planTier` en metadata.
- Variants: `variant` = visual ("simple"). Gating via `resolveVariant()`.

**Impacto sobre el plan:**

El `resolveVariant()` de §9.2 **reinventa el mecanismo de gating que
`sectionCatalog.ts` ya provee**. El catalogo de secciones ya tiene:
- Variantes por tipo (header.first, header.second, etc.)
- Plan gating (`planTier`)
- Props por defecto (`defaultProps`)
- Thumbnails para el Design Studio

**Resolucion: los dos paradigmas operan en capas distintas.**

```
Capa de Seleccion (existente, no tocar):
  SectionRenderer → sectionCatalog → componentKey → React.lazy()
  Decide QUE componente renderizar y con QUE props.
  El Design Studio opera aqui.

Capa de Implementacion (este plan):
  Componente unificado → variante → styled-components + theme
  Decide COMO renderizar la estructura visual.
  El usuario no ve esto directamente.
```

**Reconciliacion practica:**

```tsx
// sectionComponents.tsx — ANTES
'catalog.grid.first': lazy(() => import('./first/ProductCard')),
'catalog.grid.second': lazy(() => import('./second/ProductCard')),

// sectionComponents.tsx — DESPUES
// Todos apuntan al mismo componente, la variante se resuelve por props
'catalog.grid.first': lazy(() => import('components/storefront/ProductCard')),
'catalog.grid.second': lazy(() => import('components/storefront/ProductCard')),

// SectionRenderer.tsx inyecta la variante como prop basado en componentKey:
const variantFromKey = extractVariant(componentKey); // "first" → "simple"
<Component variant={variantFromKey} {...mergedProps} />
```

**`resolveVariant()` de §9.2 se simplifica:** en vez de consultar `component_catalog`
(que no existe), consume el `planTier` del `sectionCatalog` existente.

**Archivos a modificar:** `sectionComponents.tsx`, `SectionRenderer.tsx`,
`sectionCatalog.ts` (actualizar componentKey → componente unificado).

### 12.4 CORREGIDO: `component_catalog` SI existe en BD

**Hallazgo original (incorrecto):** Se afirmo que `component_catalog` no existia.

**Correccion (2026-03-18):** El endpoint `GET /components/catalog` **existe y es
consumido activamente** por el DesignStudio (linea 358):

```js
apiClient.get('/components/catalog')
// → { items: [{ component_key, token_cost, ... }] }
```

`DesignStudio.jsx` lo usa para calcular `token_cost` por seccion en
`structureCatalog` (linea 522-523):
```js
const catalogEntry = componentCatalogMap[componentKey];
const tokenCost = catalogEntry?.token_cost ?? 1;
```

El plan `fluffy-jingling-peach` **fue ejecutado**. La tabla existe en el backend.

**Impacto revisado:** `resolveVariant()` de §9.2 **sigue siendo innecesario**,
pero por otra razon: el DesignStudio ya consume `component_catalog` + `sectionCatalog`
para plan gating + token costing. No necesita un tercer resolutor.

### 12.5 IMPORTANTE: `account_entitlements` vacia

**Hallazgo:** La tabla `account_entitlements` tiene 0 filas. `useEffectivePlanConfig`
hace fallback a `getPlanLimits()` (frontend legacy) cuando no hay entitlements del API.

**Impacto:** El gating por plan funciona via fallback legacy, no via entitlements reales.
`resolveVariant()` puede usar `planLimits.planKey` del fallback, pero los limites
seran los hardcodeados en `basicPlanLimits.jsx` / `professionalPlanLimits.jsx`.

**Resolucion:** No es bloqueante. El gating funciona con el fallback.
Cuando `account_entitlements` se pueble, `useEffectivePlanConfig` lo consumira
automaticamente sin cambios en componentes unificados.

### 12.6 BAJO: `theme_config` semantica hibrida

**Hallazgo:** `createTheme()` (theme/index.ts linea 244-446) mapea paleta a
200+ propiedades de componentes: `header.background`, `productCard.titleColor`,
`faqs.questionColor`, etc. El campo `themeConfig` ya almacena overrides de
componentes, no solo tokens CSS.

**Impacto:** Agregar configuracion de variantes a `themeConfig` es **compatible**
con el formato existente, pero necesita namespace para evitar colision.

**Resolucion:**

```jsonc
// themeConfig actual (overrides de tokens/componentes)
{
  "colors": { "primary": "#FF00AA" },
  "header": { "background": "#000" }
}

// Extension propuesta (namespaced bajo "variants")
{
  "colors": { "primary": "#FF00AA" },
  "header": { "background": "#000" },
  "variants": {                          // ← namespace nuevo, no colisiona
    "productCard": "interactive",
    "faq": "cards",
    "footer": "branded"
  }
}
```

`resolveEffectiveTheme` ignora keys que no conoce (no hay validacion estricta),
asi que agregar `variants` no rompe nada existente. El consumo se haria en
`SectionRenderer` o en el componente unificado, no en el theme pipeline.

### 12.7 CONFIRMADO: Dark mode existe y es riesgo real

**Hallazgo:** El §9.1 mencionaba dark mode como riesgo. Se confirma que el sistema
tiene dark mode completo:

- `App.jsx` (linea 50-64): Deteccion por `prefers-color-scheme` + localStorage
- `resolveEffectiveTheme.ts` (linea 162): isDarkMode → template `second` (Modern Dark)
- `palettes.ts`: `dark_default` y `starter_dark` palettes
- `theme/index.ts` (linea 13-58): `darkTemplate` con 400+ propiedades dark

**Impacto:** Los colores hardcodeados (`#fff`, `#333`) en componentes target
**rompen dark mode activamente**. La auditoría de §11 muestra 21 instancias.

**Resolucion:** La correccion de colores hardcodeados durante la migracion
(ya planificada en cada ticket) es **obligatoria**, no opcional.
El dark mode valida el §9.1 como critico.

### 12.8 CONFIRMADO: Code splitting ya resuelto

**Hallazgo:** El sistema ya usa code splitting efectivo:
- `templatesMap.ts`: `React.lazy()` por template
- `sectionComponents.tsx`: `lazyTemplateExport()` por seccion
- `vite.config.js` (linea 31-79): chunks manuales para admin, section-renderer, vendors

**Impacto sobre el plan:** **Ninguno negativo.** Los componentes unificados
deben mantener este patron:

```tsx
// CORRECTO: lazy import de variante
const SimpleVariant = lazy(() => import('./variants/simple'));

// INCORRECTO: import estatico de todas las variantes
import { SimpleVariant } from './variants/simple';
import { InteractiveVariant } from './variants/interactive';
import { FullVariant } from './variants/full';
```

**Resolucion:** Agregar al theme-contract: variantes se importan con `lazy()`.
El router de variante en el `index.tsx` del componente unificado debe ser lazy.

---

## 13. Dependencias externas — estado actualizado con auditoria BD

> Revision final 2026-03-18, verificada contra ambas BDs.

### Dependencias ELIMINADAS (verificadas que no aplican)

| # | Dependencia | Razon de eliminacion |
|---|-------------|---------------------|
| ~~D1~~ | Fix `client_home_settings` | Tabla tiene 3 registros reales (§12.1) |
| ~~D2~~ | Seed T6/T7/T8 en `nv_templates` | Tabla tiene 8 registros completos (§12.2) |
| ~~D4 old~~ | Crear `component_catalog` | Tabla tiene 70 registros activos (§12.4) |

### Dependencias NUEVAS descubiertas (auditoria §19)

| # | Dependencia | Donde vive | Tipo | Estado | Prioridad |
|---|-------------|-----------|------|--------|-----------|
| D3 | Fix template_key naming cross-BD | API + BD migration | Data fix | Pendiente | **Critica** |
| D4 | Fix plan `pro` en palette_catalog | Admin DB | Data fix | Pendiente | Alta |
| D5 | Fix locale/template_id vacios e2e | Backend DB | Data fix | Pendiente | Media |
| D6 | Implementar custom palette API | API + Web | Bug fix | Pendiente | Alta |
| D7 | Limpiar cuentas preview draft | Admin DB | Maintenance | Pendiente | Baja |

### Dependencias opcionales (no bloqueantes)

| # | Dependencia | Estado |
|---|-------------|--------|
| `account_entitlements` | Tabla vacia — gating funciona via fallback `useEffectivePlanConfig` |

### Grafo de dependencias actualizado

```
URGENTES (hacer primero):
  D3 (fix template_key) ── CRITICO ──┐
  D4 (fix plan pro) ── Alta ─────────┤
  D5 (fix locale vacios) ────────────┤
  D6 (custom palette API) ── Alta    │  (independiente)
  D7 (limpiar previews) ── Baja      │  (independiente)
                                     ▼
                         Ticket 0 (Setup + reconciliacion)
                                     │
                                     ├──> Tickets 1-6 (unificacion)
                                     └──> Ticket 11 (Template change UX)

PARALELOS (independientes):
  Ticket 7 (Labels) ──> Ticket 8 (Locale)
  Ticket 9 (CSS custom) ──> Ticket 10 (CSS IA)
  Ticket 12 (Branding Manager)
  Ticket 13 (Docs fix)
```

### Datos verificados contra BD (referencia rapida)

**Backend DB (3 clientes):**

| slug | template_id | plan_key | locale | home_sections | design_overrides |
|---|---|---|---|---|---|
| e2e-alpha | *(vacio)* | starter | *(vacio)* | 9 secciones | 0 |
| e2e-beta | *(vacio)* | growth | *(vacio)* | 8 secciones | 0 |
| farma | template_8 | growth | es-AR | 9 secciones | 0 |

**Admin DB:**
- `nv_templates`: 8 filas (first-eighth, todas activas)
- `component_catalog`: 70 filas (17 catalog, 8 contact, 8 faq, 8 features, 9 hero, 8 footer, 5 header, etc.)
- `plans`: 6 filas (starter, growth, enterprise + anuales)
- `addon_catalog`: 33 addons activos (10 ai, 15 capacity, 2 content, 2 media, 3 services)
- `palette_catalog`: 20 paletas (15 starter, 3 growth, 1 pro ← **bug: `pro` no existe como plan**)
- `provisioning_jobs`: 1 completado (farma)
- `account_entitlements`: 0 filas

**Entitlements por plan (verificados):**

| Entitlement | starter | growth | enterprise |
|---|---|---|---|
| products_limit | 300 | 2,000 | 50,000 |
| max_monthly_orders | 200 | 1,000 | 20,000 |
| images_per_product | 1 | 4 | 8 |
| banners_active_limit | 3 | 8 | 100 |
| max_faqs | 6 | 20 | 999,999 |
| max_services | 3 | 12 | 999,999 |
| coupons_active_limit | 0 | 10 | 0 |
| storage_gb_quota | 2 | 10 | 100 |
| egress_gb_quota | 50 | 200 | 1,024 |
| custom_domain | false | true | true |
| is_dedicated | false | false | true |

---

## 14. Inconsistencias detectadas en versiones anteriores del plan

> Revision cruzada contra el codigo real (2026-03-18).

### 14.1 `resolveVariant()` (§9.2) es redundante

**Inconsistencia:** §9.2 propone `resolveVariant()` que consulta `component_catalog`
y `useEffectivePlanConfig` para resolver variantes con gating.

**Realidad:** El DesignStudio ya resuelve todo esto en `structureCatalog` (linea 509-527):
```js
const lockedByPlan = !canAccessByPlan(planKey, normalizeMinPlan(meta.planTier));
const catalogEntry = componentCatalogMap[componentKey]; // ← component_catalog en BD
const tokenCost = catalogEntry?.token_cost ?? 1;
return { selectable: !lockedByPlan && !limitReached, tokenCost };
```

**Resolucion:** Eliminar `resolveVariant()` del scope. El gating se resuelve
en `DesignStudio` (admin side) y en `sectionCatalog.planTier` (storefront side).
Los componentes unificados no necesitan saber de planes — reciben `variant` como prop.

### 14.2 Contact ya esta unificado — patron existente no referenciado

**Inconsistencia:** El plan propone `ContactSection/variants/` como si fuera nuevo.

**Realidad:** `content.contact.first` a `.fifth` ya apuntan al mismo componente
`DynamicContactSection` en `sectionComponents.tsx`. La variacion visual se maneja
con `layoutVariant` como prop (valor: `"split"`).

**Resolucion:** Usar DynamicContactSection como **caso de estudio** para la
unificacion. El patron probado es:
- 1 componente con prop `layoutVariant` (no archivos de variante separados)
- Multiples `componentKey` en `sectionCatalog` apuntando al mismo componente
- `defaultProps` distintos por key

### 14.3 Footer ya tiene fallbacks — 3 de 8 unificados

**Inconsistencia:** El plan asume 6 footers independientes.

**Realidad:** `footer.second` y `footer.third` ya apuntan a `FooterFirst`.
Solo hay 6 componentes reales: FooterFirst (×3), FooterFourth, FooterFifth,
FooterSixth, FooterSeventh, FooterEighth.

### 14.4 Variantes en `themeConfig` (§12.6) contradice patron de `section.props`

**Inconsistencia:** §12.6 propone `themeConfig.variants.productCard = "interactive"`.

**Realidad:** Las variaciones visuales ya viven en `section.props`:
- `layoutVariant: "split"` en Contact
- `themeVariant: "dark"` en Hero Video
- `overlayStyle: "gradient"` en Hero Video

**Resolucion:** Las variantes deben ir como props de seccion (patron existente),
no en `themeConfig`. La seleccion de variante es una decision por-seccion,
no una configuracion global del tema.

### 14.5 ProductCard es hijo de Catalog Section — dos niveles de unificacion

**Inconsistencia:** El plan trata ProductCard como si fuera una seccion.

**Realidad:** El sistema de sections tiene:
- `catalog.carousel.*` (17 entries) — secciones que CONTIENEN cards
- ProductCard — componente interno de esas secciones

La unificacion del card no elimina la duplicacion de la seccion contenedora.
Hay 2 niveles de trabajo:
1. **Catalog Section unificada** → carousel, grid, showcase como variantes
2. **ProductCard unificado** → simple, interactive, full, showcase como variantes

El plan solo cubre el nivel 2. El nivel 1 es mas impactante (17 entries vs 5 cards).

---

## 15. Definiciones faltantes

### 15.1 Mapping `componentKey` → `variant` (70 entries)

Tabla completa de mappings necesarios para `extractVariant()`:

**Catalog sections → ProductCard variant:**

| componentKey | Tipo | Card variant |
|---|---|---|
| `catalog.carousel.first.featured` | carousel | `simple` |
| `catalog.carousel.first.bestsellers` | carousel | `simple` |
| `catalog.carousel.second.featured` | carousel | `interactive` |
| `catalog.carousel.second.bestsellers` | carousel | `interactive` |
| `catalog.carousel.third.featured` | carousel | `simple` |
| `catalog.carousel.third.bestsellers` | carousel | `simple` |
| `catalog.carousel.fourth` | carousel | `full` |
| `catalog.carousel.fifth.featured` | carousel | `full` |
| `catalog.carousel.fifth.bestsellers` | carousel | `full` |
| `catalog.grid.first` | grid | `simple` |
| `catalog.grid.third` | grid | `simple` |
| `catalog.grid.fourth` | grid | `full` |
| `catalog.grid.fifth` | grid | `full` |
| `catalog.showcase.sixth` | showcase | `showcase` |
| `catalog.showcase.seventh` | showcase | `showcase` |
| `catalog.showcase.eighth` | showcase | `showcase` |
| `categories.carousel.third` | categories | N/A |

**FAQ sections → FAQ variant:**

| componentKey | variant |
|---|---|
| `content.faq.first` | `accordion` |
| `content.faq.second` | `accordion` |
| `content.faq.third` | `accordion` |
| `content.faq.fourth` | `accordion` |
| `content.faq.fifth` | `accordion` |
| `content.faq.sixth` | `cards` |
| `content.faq.seventh` | `cards` |
| `content.faq.eighth` | `masonry` |

**Footer sections → Footer variant:**

| componentKey | variant | Componente actual |
|---|---|---|
| `footer.first` | `columns` | FooterFirst |
| `footer.second` | `columns` | FooterFirst (fallback) |
| `footer.third` | `columns` | FooterFirst (fallback) |
| `footer.fourth` | `stacked` | FooterFourth |
| `footer.fifth` | `stacked` | FooterFifth |
| `footer.sixth` | `branded` | FooterSixth (Drift) |
| `footer.seventh` | `branded` | FooterSeventh (Vanguard) |
| `footer.eighth` | `branded` | FooterEighth (Lumina) |

**Features sections → Services variant:**

| componentKey | variant |
|---|---|
| `features.grid.first` | `grid` |
| `features.list.second` | `grid` |
| `features.grid.third` | `grid` |
| `features.content.fourth` | `cards-hover` |
| `features.content.fifth` | `cards-hover` |
| `features.sixth` | `cards-hover` |
| `features.seventh` | `minimal` |
| `features.eighth` | `cards-hover` |

### 15.2 Impacto sobre `defaultProps` al unificar

Al unificar, cada entry en `sectionCatalog` debe agregar `variant` a sus
`defaultProps`. Ejemplo:

```typescript
// ANTES
'content.faq.sixth': {
  name: 'FAQ Drift',
  type: 'faq',
  planTier: 'enterprise',
  defaultProps: { title: 'Preguntas frecuentes' }
}

// DESPUES
'content.faq.sixth': {
  name: 'FAQ Drift',
  type: 'faq',
  planTier: 'enterprise',
  defaultProps: { title: 'Preguntas frecuentes', variant: 'cards' }  // ← nuevo
}
```

### 15.3 Impacto sobre `LEGACY_KEY_MAP`

30+ legacy keys deben seguir funcionando post-migracion:
```typescript
'content.faq' → 'content.faq.first'  // debe seguir resolviendo
'content.contact' → 'content.contact.first'
'catalog.carousel' → 'catalog.carousel.first.featured'
```

No eliminar ningun mapping legacy. Solo agregar nuevos si es necesario.

### 15.4 Skeleton vs `SectionLoadingFallback`

`SectionRenderer` ya tiene `SectionLoadingFallback` (div con min-height).
Los skeletons de §9.5 **complementan**, no reemplazan:

```
SectionRenderer carga componente → SectionLoadingFallback (generico)
    ↓ componente cargado
Componente carga datos → ComponentSkeleton (especifico por variante)
```

Dos fases de loading: la primera es del lazy import (Suspense),
la segunda es del fetch de datos (estado interno del componente).

---

## 16. Implementacion con IA — Tres capas independientes

### Infraestructura IA existente

| Capacidad | Estado | Donde vive |
|---|---|---|
| Store DNA (contexto por tienda) | Activo | `StoreContextService` |
| Vision API (analisis de imagenes) | Activo | `ai-from-photo` endpoint |
| 11 endpoints IA (texto + imagen) | Activo | API backend |
| Sistema de creditos (normal/pro) | Activo | `ai_feature_pricing` |
| 6 action codes | Activo | `useAiCredits` hook |
| component_catalog con token_cost | Activo | `GET /components/catalog` |
| sectionCatalog con planTier | Activo | `sectionCatalog.ts` (70 entries) |
| IA para decisiones de diseño | No existe | — |

### Capa A: AI Template + Palette Recommendation (corto plazo)

**No requiere unificacion de componentes.**

```
Endpoint: POST /ai/suggest-design
Input:  { logo_url?, business_category, business_description }
Output: { templateKey, paletteKey, customTokens?, reasoning }

Flujo:
1. Store DNA provee contexto del negocio
2. Vision API analiza logo → extrae colores dominantes (ya existe)
3. GPT recibe: DNA + colores + PALETTES registry (50 opciones)
4. Responde template + palette recomendados con justificacion
5. DesignStudio aplica como "sugerencia" (usuario confirma)
```

**Prerequisitos:** Store DNA (existe), Vision API (existe), palettes registry (existe).
**Nuevo:** 1 endpoint API + UI en DesignStudio ("Sugerir diseño con IA").
**Creditos:** 1 action code nuevo: `ai_design_suggestion`.

### Capa B: AI Section Layout Suggestion (mediano plazo)

**No requiere unificacion de componentes.**

```
Endpoint: POST /ai/suggest-layout
Input:  { store_dna, current_sections, product_count, plan_key }
Output: { sections: [{ componentKey, type, props }], reasoning }

Flujo:
1. GPT recibe Store DNA + sectionCatalog metadata (70 entries)
2. Filtra por planTier del tenant (solo sugiere lo accesible)
3. Genera layout optimizado: que secciones, en que orden, con que props
4. DesignStudio lo muestra como "Layout sugerido" → usuario acepta/modifica
```

**Ejemplo de output:**
```json
{
  "sections": [
    { "componentKey": "hero.fifth", "type": "hero",
      "props": { "banners": [{ "title": "Ropa artesanal con alma" }] } },
    { "componentKey": "catalog.carousel.fifth.featured", "type": "catalog",
      "props": { "title": "Destacados", "objectToShow": "featured" } },
    { "componentKey": "features.content.fifth", "type": "features",
      "props": {} },
    { "componentKey": "content.faq.fifth", "type": "faq",
      "props": { "title": "Preguntas frecuentes" } },
    { "componentKey": "content.contact.fifth", "type": "contact",
      "props": { "layoutVariant": "split" } }
  ],
  "reasoning": "Para una tienda de ropa artesanal, recomiendo..."
}
```

**Prerequisitos:** sectionCatalog (existe), Store DNA (existe), planTier gating (existe).
**Nuevo:** 1 endpoint API + UI en DesignStudio.

### Capa C: AI Variant + Token Tuning (largo plazo)

**REQUIERE unificacion de componentes.**

```
Endpoint: POST /ai/tune-design
Input:  { store_dna, active_sections, logo_colors, current_tokens }
Output: { variant_overrides, token_overrides }

Flujo:
1. Con componentes unificados, la IA puede "pensar" en variantes
2. Sugiere: "Tu ProductCard deberia usar variante 'full' para mostrar
   badges de descuento que tu rubro necesita"
3. Sugiere CSS tokens personalizados:
   { "--nv-card-radius": "16px", "--nv-card-shadow": "0 4px 12px ..." }
4. Frontend aplica via section.props.variant + CSS custom properties
```

**Prerequisitos:** Unificacion completa + CSS tokens por componente (§10.2).

### Secuencia de implementacion IA

```
AHORA (sin dependencias)     PRONTO (datos existentes)     POST-UNIFICACION
┌──────────────────────┐     ┌──────────────────────┐     ┌──────────────────┐
│ Capa A               │     │ Capa B               │     │ Capa C           │
│ Template + Palette    │     │ Layout Suggestion    │     │ Variant Tuning   │
│ desde logo + DNA     │     │ desde sectionCatalog │     │ desde variants   │
│                      │     │                      │     │ unificadas       │
│ Prerequisitos:       │     │ Prerequisitos:       │     │ Prerequisitos:   │
│ ✅ Store DNA         │     │ ✅ sectionCatalog    │     │ ❌ Unificacion   │
│ ✅ Vision API        │     │ ✅ planTier gating   │     │ ❌ CSS tokens    │
│ ✅ Palettes          │     │ ✅ defaultProps      │     │ ✅ comp. catalog │
└──────────────────────┘     └──────────────────────┘     └──────────────────┘
```

**Conclusion:** Las Capas A y B son independientes del plan de unificacion
y pueden implementarse en paralelo o incluso antes.
Solo la Capa C justifica esperar a la unificacion.

---

## 17. CSS custom por cliente + generacion IA

### Estado actual verificado contra BD

**Tabla `client_design_overrides` (Backend DB) — existe pero vacia (0 filas):**

```sql
-- Schema real verificado 2026-03-18
id                 uuid          PK
client_id          uuid          FK → clients
override_type      text          NOT NULL  -- ej: 'custom_css', 'theme_tokens', 'section_props'
target_slot        text          NULL      -- ej: 'header', 'productCard', 'global'
target_section_id  uuid          NULL      -- FK → home_sections.id (override por seccion)
original_value     jsonb         NULL      -- estado antes del override (para rollback)
applied_value      jsonb         NOT NULL  -- el override activo
source_addon_key   text          NOT NULL  -- addon que habilito el override
source_purchase_id uuid          NULL      -- compra del addon
is_visual_only     boolean       NOT NULL  -- true = solo CSS/visual, no funcional
status             text          NOT NULL  -- 'active' | 'suspended' | 'revoked'
applied_at         timestamptz
suspended_at       timestamptz   NULL
revoked_at         timestamptz   NULL
applied_by         uuid          NULL
metadata           jsonb         NULL
```

**La infraestructura de BD es perfecta para CSS custom.** Solo falta:
1. Un frontend que consuma los overrides
2. Un editor de CSS en el admin
3. Un endpoint IA que genere CSS

**No existe ningun mecanismo de CSS custom hoy:**
- No hay `customCss`, `custom_css`, `userStyles` en el frontend
- No hay inyeccion de `<style>` tags
- No hay consumo de `client_design_overrides` en ningun componente
- Todo el theming es via CSS variables (`--nv-*`) y styled-components

### Arquitectura propuesta

#### Nivel 1: CSS custom manual (addon premium)

```
Flujo:
1. Admin compra addon "CSS Personalizado" (addon_catalog.key = 'custom_css')
2. Admin abre editor CSS en DesignStudio (nuevo panel)
3. Escribe CSS scoped → preview en tiempo real
4. Guarda → POST /design-overrides con:
   {
     override_type: 'custom_css',
     target_slot: 'global',       // o un section_id especifico
     applied_value: { css: ".nv-hero { border-radius: 24px; }" },
     source_addon_key: 'custom_css',
     is_visual_only: true
   }
5. Frontend carga overrides activos → inyecta <style> scoped

Scoping (seguridad):
- CSS se sanitiza server-side (no permitir @import, url() externo, position:fixed)
- Cada override se wrappea en scope: .nv-store-{client_id} { ... }
- No se permite CSS que afecte elementos fuera del storefront
```

**Frontend — consumo de overrides:**

```tsx
// Hook nuevo: useDesignOverrides()
function useDesignOverrides(clientId: string) {
  const [overrides, setOverrides] = useState<DesignOverride[]>([]);

  useEffect(() => {
    // Cargar overrides activos del API
    apiClient.get(`/design-overrides?status=active`)
      .then(res => setOverrides(res.data));
  }, [clientId]);

  // Inyectar CSS overrides en <head>
  useEffect(() => {
    const cssOverrides = overrides.filter(o => o.override_type === 'custom_css');
    const style = document.createElement('style');
    style.id = 'nv-custom-css';
    style.textContent = cssOverrides.map(o => o.applied_value.css).join('\n');
    document.head.appendChild(style);
    return () => style.remove();
  }, [overrides]);

  return overrides;
}
```

**Donde se integra:** `App.jsx` despues de `useThemeVars()`.

#### Nivel 2: CSS generado por IA

```
Endpoint: POST /design-overrides/ai-generate
Action code: ai_css_generation (nuevo)

Input: {
  target: 'global' | section_id,
  description: "Quiero bordes mas redondeados y sombras suaves",
  current_tokens: { "--nv-primary": "#1D4ED8", ... },
  template_key: "fifth",
  store_dna: "..." (auto-inyectado)
}

Output: {
  css: ".nv-section-hero { border-radius: 24px; box-shadow: ... }",
  explanation: "Apliqué border-radius de 24px para...",
  credits_consumed: 2,
  tier: "normal"
}

Flujo:
1. GPT recibe: Store DNA + tokens actuales + template + descripcion del usuario
2. Genera CSS scoped que respeta los --nv-* tokens
3. Admin ve preview en tiempo real
4. Si acepta → guarda como design_override
5. Si rechaza → regenera o descarta
```

**Prompt del endpoint:**
```
Eres un diseñador CSS experto. El usuario tiene una tienda con estos tokens:
{tokens}

Template: {template_key}
Contexto: {store_dna}

Genera CSS scoped para: "{user_description}"

Reglas:
- Usa variables CSS existentes (var(--nv-primary), etc.) cuando sea posible
- No uses @import, url() externo, position:fixed, z-index > 100
- Scoping: todos los selectores deben empezar con .nv-store o .nv-section-*
- Mantene coherencia con la paleta existente
- Solo propiedades visuales (no funcionales)
```

#### Nivel 3: Override por seccion con IA

```
Flujo:
1. Admin selecciona una seccion en DesignStudio
2. Click "Personalizar con IA"
3. Describe que quiere: "Quiero que el hero tenga mas padding y un degradado"
4. IA genera CSS scoped a esa section_id
5. Se guarda en client_design_overrides con target_section_id = section.id
6. SectionRenderer inyecta el override como style prop
```

### Relacion con component_catalog

```
addon_catalog                    client_design_overrides
┌────────────────────────┐      ┌───────────────────────────┐
│ key: 'custom_css'      │      │ source_addon_key: 'custom_css' │
│ family: 'design'       │ ───> │ override_type: 'custom_css'     │
│ min_plan: 'growth'     │      │ applied_value: { css: "..." }   │
│ commercial_model:      │      │ status: 'active'                │
│   'one_time'           │      │ is_visual_only: true            │
└────────────────────────┘      └───────────────────────────┘
```

**Gating:** Solo clientes con addon `custom_css` comprado pueden crear overrides.
Si el addon se revoca → `status` pasa a `'suspended'` → CSS deja de aplicarse.

---

## 18. Labels configurables e internacionalizacion

### Estado actual verificado contra codigo y BD

**Props editables en secciones — YA FUNCIONA parcialmente:**

`home_sections.props` almacena textos configurables por seccion:
```json
// hero.first — client 738705a7
{ "title": "Bienvenido a tu tienda", "cta_text": "Ver productos",
  "subtitle": "Descubre nuestros productos", "cta_link": "/products" }

// features.grid.first — client 738705a7
{ "title": "Nuestros Servicios" }

// content.faq.first — client 738705a7
{ "title": "Preguntas Frecuentes" }

// content.contact.first — client 738705a7
{ "title": "Contáctanos" }
```

**SectionPropsEditor en DesignStudio — YA EXISTE:**
- Editor visual con campos tipo text, number, boolean, textarea, select, list
- Organizado en grupos: content, layout, style, actions, data
- Guarda en `section.props` via API `PATCH /home-sections/:id/props`

**PERO hay 18+ strings hardcodeados en componentes que ignoran props:**

| String | Componente | Archivo | Tipo |
|--------|-----------|---------|------|
| "Agotado" | ProductCard | `ProductCard.jsx:110` | Badge |
| "Nuestros Servicios" | ServicesGrid | `ServicesGrid/index.jsx:99` | Titulo |
| "Preguntas Frecuentes" | FaqAccordion | `FaqAccordion/index.jsx:57` | Titulo |
| "Productos" | Headers (Elegant, Bold) | `ElegantHeader.jsx:349` | Nav link |
| "Servicios" | Headers | varios | Nav link |
| "FAQs" | Headers | varios | Nav link |
| "Contacto" | Headers, Footers | varios | Nav link / titulo |
| "Inicio" | Footers | varios | Nav link |
| "Catálogo" | Footers | varios | Nav link |
| "Hola, quiero más información" | ContactInfo, Headers | varios | WhatsApp msg |
| "Sin información de contacto" | Footers | varios | Fallback |
| "Producto agregado/eliminado de favoritos" | ProductCard | varios | Toast |
| "Debes iniciar sesión..." | ProductCard | varios | Toast |
| "Envío gratis" | ProductCard (algunos) | varios | Badge |
| "$" | Precios | varios | Moneda |

**No existe infraestructura i18n:**
- No hay react-intl, i18next, ni archivos de traduccion
- No hay deteccion de `navigator.language`
- No hay campo `locale` en `clients`
- 100% del sistema esta en español

### Estrategia propuesta: Labels por seccion + locale del tenant

**POR QUE NO i18n clasico (react-intl/i18next):**
- NovaVision no es una app multi-idioma — es una plataforma SaaS donde cada
  tenant tiene UN idioma (el de su mercado local)
- Cuando NovaVision venda como SaaS en Brasil, los nuevos tenants brasileños
  necesitan UI en portugues desde el primer dia, no un switcher de idioma
- i18next agrega complejidad de bundle, archivos `.json`, context providers
- El sistema de `section.props` ya resuelve el 80% del problema

**Solucion: 3 capas complementarias**

#### Capa 1: Migrar strings hardcodeados a props (corto plazo)

Cada componente que tiene strings hardcodeados debe consumirlos como props
con fallback al valor actual:

```tsx
// ANTES (hardcodeado)
<Badge>Agotado</Badge>

// DESPUES (prop con fallback)
<Badge>{labels?.outOfStock || 'Agotado'}</Badge>
```

**Tabla de migracion:**

| String actual | Prop name | Default (es-AR) | Default (pt-BR) |
|---|---|---|---|
| "Agotado" | `labels.outOfStock` | "Agotado" | "Esgotado" |
| "Agregar al carrito" | `labels.addToCart` | "Agregar al carrito" | "Adicionar ao carrinho" |
| "Ver más" | `labels.viewMore` | "Ver más" | "Ver mais" |
| "Productos" | `labels.navProducts` | "Productos" | "Produtos" |
| "Servicios" | `labels.navServices` | "Servicios" | "Serviços" |
| "Contacto" | `labels.navContact` | "Contacto" | "Contato" |
| "Preguntas Frecuentes" | `labels.faqTitle` | "Preguntas Frecuentes" | "Perguntas Frequentes" |
| "Envío gratis" | `labels.freeShipping` | "Envío gratis" | "Frete grátis" |
| "$" | `currency.symbol` | "$" | "R$" |

**Donde se inyectan:** `SectionRenderer.tsx` ya inyecta props por tipo de seccion.
Agregar `labels` como prop inyectado desde la configuracion del tenant.

#### Capa 2: Locale del tenant en BD (mediano plazo)

```sql
-- Migracion en clients (Backend DB)
ALTER TABLE clients ADD COLUMN locale text NOT NULL DEFAULT 'es-AR';
-- Valores posibles: 'es-AR', 'pt-BR', 'es-MX', 'en-US'
```

**Mapa de defaults por locale:**

```typescript
// src/config/localeDefaults.ts
export const LOCALE_DEFAULTS: Record<string, Labels> = {
  'es-AR': {
    outOfStock: 'Agotado',
    addToCart: 'Agregar al carrito',
    viewMore: 'Ver más',
    navProducts: 'Productos',
    navServices: 'Servicios',
    navContact: 'Contacto',
    faqTitle: 'Preguntas Frecuentes',
    freeShipping: 'Envío gratis',
    currency: { symbol: '$', code: 'ARS', position: 'before' },
  },
  'pt-BR': {
    outOfStock: 'Esgotado',
    addToCart: 'Adicionar ao carrinho',
    viewMore: 'Ver mais',
    navProducts: 'Produtos',
    navServices: 'Serviços',
    navContact: 'Contato',
    faqTitle: 'Perguntas Frequentes',
    freeShipping: 'Frete grátis',
    currency: { symbol: 'R$', code: 'BRL', position: 'before' },
  },
};
```

**Resolucion de labels (cascada):**
```
1. section.props.labels.outOfStock  (override manual del admin)
2. client.locale → LOCALE_DEFAULTS   (default por idioma)
3. 'Agotado'                         (fallback hardcodeado, retrocompat)
```

#### Capa 3: IA para traduccion/adaptacion de labels (largo plazo)

```
Endpoint: POST /ai/translate-labels
Action code: ai_label_translation (nuevo)

Input: {
  source_locale: 'es-AR',
  target_locale: 'pt-BR',
  current_labels: { title: "Bienvenido a tu tienda", ... },
  store_dna: "..." (auto-inyectado),
  context: "hero section for clothing store"
}

Output: {
  translated_labels: {
    title: "Bem-vindo à sua loja",
    cta_text: "Ver produtos",
    subtitle: "Descubra nossos produtos"
  },
  credits_consumed: 1
}
```

**No es solo traduccion literal** — con Store DNA la IA adapta el tono y estilo
al mercado brasileño. "Ver productos" no se traduce como "Ver produtos" literal
sino como "Confira nossos produtos" si el Store DNA indica tono casual.

### Relacion con la unificacion de componentes

**La Capa 1 (migrar hardcodeados a props) se beneficia enormemente de la unificacion:**
- Sin unificacion: hay que migrar "Agotado" en 5 ProductCards distintos
- Con unificacion: se migra 1 vez en el ProductCard unificado

**La Capa 2 (locale del tenant) es independiente** — solo necesita:
- 1 migracion de BD (agregar `locale` a `clients`)
- 1 archivo `localeDefaults.ts`
- Modificar `SectionRenderer` para inyectar labels por locale

**La Capa 3 (IA) depende de Capa 2** pero no de la unificacion.

### Compatibilidad con client_design_overrides

Los labels custom del admin se pueden almacenar como design_override:

```sql
INSERT INTO client_design_overrides (
  client_id, override_type, target_slot,
  applied_value, source_addon_key, is_visual_only, status
) VALUES (
  '738705a7...', 'labels', 'global',
  '{"navProducts": "Nossos Produtos", "outOfStock": "Indisponível"}',
  'i18n_pack', true, 'active'
);
```

Esto permite que un addon de "Paquete de idioma" habilite la personalizacion
de labels, y si el addon se revoca, los labels vuelven a los defaults del locale.

---

## 19. Inconsistencias de BD descubiertas (auditoria 2026-03-18)

Auditoria directa contra las 2 BDs con datos reales. **10 inconsistencias criticas.**

### 19.1 CRITICA — `template_key` nomenclatura inconsistente entre BDs

```
Backend DB:
  clients.template_id         = 'template_8'  (farma)
  client_home_settings.template_key = 'template_8'

Admin DB:
  nv_templates.key            = 'eighth'
  component_catalog           = 'header.first', 'hero.eighth', etc.
```

**Impacto:** El frontend usa `normalizeTemplateKey()` para mapear `template_8` → `eighth`,
pero cualquier query que cruce BDs sin normalizacion va a fallar.
El provisionamiento escribio `template_8` en Backend DB pero el catalogo usa `eighth`.

**Fix requerido:** Decidir canon (`eighth` o `template_8`) y migrar. La normalizacion
en `resolveEffectiveTheme.ts:32-50` ya resuelve esto pero es un parche, no una solucion.

### 19.2 CRITICA — Plan `pro` referenciado en `palette_catalog` pero no existe

```sql
-- Admin DB
palette_catalog WHERE min_plan_key = 'pro':
  luxury_gold    →  min_plan_key = 'pro'

-- Pero plans solo tiene: starter, growth, enterprise (y anuales)
```

**Impacto:** La paleta `luxury_gold` nunca va a ser seleccionable si el gating
usa `canAccessPlanTier()` con `PLAN_ORDER` que no tiene `pro`.
En el API `normalizePlanKey()` mapea `pro` → `enterprise`, pero en el frontend
`planGating.js` podria no hacer lo mismo.

**Fix requerido:** `UPDATE palette_catalog SET min_plan_key = 'enterprise' WHERE palette_key = 'luxury_gold'`

### 19.3 MEDIA — `locale` vacio (string vacio) en clientes e2e

```
e2e-alpha: locale = ''   (string vacio, no NULL)
e2e-beta:  locale = ''   (string vacio, no NULL)
farma:     locale = 'es-AR'  ← unico con valor real
```

**Impacto:** Si el Ticket 8 (locale del tenant) usa `client.locale || 'es-AR'`,
el string vacio `''` es falsy en JS → cae al fallback. Pero en SQL `'' != NULL`,
asi que un `WHERE locale IS NOT NULL` no los filtraria.

**Fix requerido:** Migrar `'' → 'es-AR'` para clientes existentes.
La migracion del Ticket 8 debe usar `COALESCE(NULLIF(locale, ''), 'es-AR')`.

### 19.4 MEDIA — `template_id` vacio en clientes e2e

```
e2e-alpha: template_id = ''   (pero client_home_settings.template_key = 'first')
e2e-beta:  template_id = ''   (pero client_home_settings.template_key = 'fifth')
farma:     template_id = 'template_8'
```

**Impacto:** Si un componente lee `clients.template_id` directamente en vez de
`client_home_settings.template_key`, no va a encontrar template.
El frontend usa `homeData.config.templateKey` (viene de `/home/data` que lee
`client_home_settings`), asi que funciona. Pero es fuente de confusion.

**Fix requerido:** Sincronizar `clients.template_id` con `client_home_settings.template_key`.

### 19.5 BAJA — `account_entitlements` vacia (Admin DB)

**0 filas.** El snapshot de entitlements nunca se calculo para ninguna cuenta.
Esto significa que `SYNC_ENTITLEMENTS` nunca se ejecuto o la tabla no se usa.

**Impacto en la unificacion:** Si el plan propone usar `account_entitlements`
para gating de variantes, no va a funcionar. El gating actual depende de
`clients.plan_key` + `useEffectivePlanConfig()` que calcula en runtime.

**Decision:** Mantener gating via `useEffectivePlanConfig()`. No depender de
`account_entitlements` para esta fase.

### 19.6 INFO — Headers solo cubren 5 templates, no 8

```sql
-- component_catalog: header.{first..fifth} — solo 5 variantes
-- Templates sixth, seventh, eighth NO tienen header propio
-- farma (template eighth) usa header.first como fallback
```

**Impacto en la unificacion:** El Header unificado (fuera de scope del plan actual)
debe considerar que T6/T7/T8 ya reusan headers existentes. El sistema de fallback
`.first` de `SectionRenderer` lo resuelve, pero la unificacion no debe crear
`header.sixth/seventh/eighth` innecesariamente.

### 19.7 INFO — 20 cuentas preview draft sin limpiar

```sql
-- Admin DB: 20 nv_accounts con status='draft', email='preview+*@example.com'
-- Generadas por sistema de preview, no limpiadas
```

**Impacto:** Contaminan metricas de cuentas. No bloquean nada, pero deben limpiarse.

### 19.8 INFO — Documentacion desactualizada (database-first.md)

| Documentado | Real | Tabla |
|---|---|---|
| `plan_definitions` | `plans` | Admin DB |
| `backend_clusters.cluster_key` | `backend_clusters.cluster_id` | Admin DB |
| `addon_catalog.key` | `addon_catalog.addon_key` | Admin DB |

**Impacto:** Las reglas `.claude/rules/database-first.md` referencian nombres incorrectos.
Cualquier agente que siga las reglas al pie de la letra va a buscar columnas que no existen.

### 19.9 INFO — Solo 1 provisioning job completado

Solo `farma` paso por el flujo automatico `PROVISION_CLIENT → SEED_TEMPLATE`.
Los clientes e2e fueron creados manualmente, lo que explica inconsistencias
(template_id vacio, locale vacio).

### 19.10 INFO — Farma mezcla componentes de templates

```
farma: template_key = 'template_8' (eighth)
  header → header.first  (del template first, no eighth)
  resto  → *.eighth      (hero, catalog, features, etc.)
```

Esto es **intencional** — no hay `header.eighth` en el catalogo (§19.6).
Pero demuestra que el sistema de compatibilidad ya permite mezcla de templates,
lo cual es bueno para la unificacion.

---

## 20. Validacion del flujo de template change

### Flujo actual verificado

```
1. DesignStudio.jsx:299 → selectedTemplate state
2. DesignStudio.jsx:453 → evaluateTemplateCompatibility(sections, selectedTemplate)
3. compatibility.js:40 → mapea componentKeys al nuevo template (regex suffix swap)
4. Si incompatible → bloquea guardado con toast error
5. Si compatible → identity.js:24 → PUT /settings/home { templateKey, paletteKey }
6. Respuesta incluye consumedCredits → se actualiza balance local
7. PreviewFrame actualiza preview en tiempo real via postMessage
```

### Edge cases identificados

| # | Edge case | Estado | Riesgo |
|---|-----------|--------|--------|
| 1 | Cambiar de T5 a T2 con secciones incompatibles | **Cubierto** — compatibility.js bloquea | Bajo |
| 2 | Cambiar template sin creditos `ws_action_template_change` | **Cubierto** — creditValidation antes de guardar | Bajo |
| 3 | Cambiar template + palette atomicamente | **Cubierto** — PUT /settings/home acepta ambos | Bajo |
| 4 | Cambiar template con draft no guardado | **Parcial** — draft en localStorage puede quedar stale | Medio |
| 5 | Cambiar template y luego hacer undo | **NO cubierto** — no hay undo/redo | Alto |
| 6 | Downgrade de plan con template growth activo | **NO cubierto** — template sigue activo post-downgrade | Alto |
| 7 | Template change durante sesion de otro admin | **NO cubierto** — no hay lock optimista ni merge | Medio |
| 8 | Template change con custom CSS overrides activos | **NO cubierto** — CSS puede romper con nuevo template | Alto |
| 9 | Cambiar a template que requiere plan superior | **Cubierto** — planGating en structureCatalog | Bajo |
| 10 | Template T6/T7/T8 con header fallback | **Cubierto** — SectionRenderer fallback .first | Bajo |

### Edge cases criticos para la unificacion

**EC-6: Plan downgrade con template premium activo**
```
Escenario: Tenant tiene plan Growth con template "fourth" (min_plan: growth).
           Downgradea a Starter.

Actual: El template sigue activo. No se valida retroactivamente.
Esperado: Opciones:
  a) Forzar template change a uno Starter (destructivo)
  b) Marcar template como "congelado" (read-only, no se puede editar)
  c) Ignorar (el usuario ya pago, mantiene lo que tiene)

Recomendacion: Opcion (c) — "grandfathering". El template se mantiene pero
no puede cambiar a otro Growth. Esto ya es el comportamiento actual.
```

**EC-8: CSS custom + template change**
```
Escenario: Tenant tiene CSS custom targeting .nv-section-hero con estilos
           especificos del template fifth. Cambia a template second.

Actual: CSS sigue aplicandose pero puede romper visualmente (selectores
        no matchean o los tokens CSS cambian).

Solucion: Al cambiar template, mostrar warning si hay design_overrides activos:
  "Tenes CSS personalizado que podria no ser compatible con el nuevo template.
   ¿Querés mantenerlo, desactivarlo temporalmente, o regenerar con IA?"
```

### Custom palettes — metodos no implementados detectados

```javascript
// identity.js — LLAMADOS pero NO IMPLEMENTADOS:
identityService.createCustomPalette(data)   // Necesita: POST /palettes/custom
identityService.updateCustomPalette(id, data) // Necesita: PATCH /palettes/custom/:id
identityService.deleteCustomPalette(id)      // Necesita: DELETE /palettes/custom/:id
```

**Esto es un bug activo** — el CustomPaletteEditor en DesignStudio llama estos
metodos pero van a fallar silenciosamente.

---

## 21. Impacto en onboarding

### Flujo actual de onboarding verificado

```
Admin app:
1. not_started → /builder (wizard de creacion)
2. Usuario selecciona template + palette
3. in_progress → /builder (continua editando)
4. submitted_for_review → /onboarding/status (espera aprobacion)
5. Admin aprueba → provisioning_jobs: PROVISION_CLIENT + SEED_TEMPLATE
6. completed → /hub (listo para operar)
```

### ¿Que se seedea al provisionar?

```typescript
// API: default-template-sections.ts
// Cada template tiene un preset de secciones:
//   first:   9 secciones (header, hero, features, 3 catalog, contact, faq, footer)
//   second:  8 secciones
//   ...
//   eighth:  9 secciones (header, hero, catalog, features, testimonials, faq, newsletter, contact, footer)
```

### Impacto de la unificacion en el onboarding

| Aspecto | Antes | Despues |
|---------|-------|---------|
| Template selection | 8 templates, cada uno con componentKeys propios | 8 templates, componentKeys unificados + variant prop |
| Seed sections | `catalog.carousel.first.featured` | `catalog.carousel` + `variant: 'first'` |
| Palette selection | Funciona igual | Sin cambio |
| Provisioning job | SEED_TEMPLATE crea secciones con componentKeys legacy | Debe crear secciones con componentKeys unificados |
| Preview builder | Renderiza con componentes legacy | Renderiza con componentes unificados |

**Cambio requerido en API:**
`default-template-sections.ts` debe actualizarse para usar componentKeys unificados.
Ejemplo: `catalog.carousel.first.featured` → `catalog.carousel.featured` + `props: { variant: 'first' }`.

**Alternativa sin cambio en API:** Mantener LEGACY_KEY_MAP en sectionComponents.tsx
para que los componentKeys legacy sigan funcionando. El API sigue seedeando
con keys legacy y el frontend los normaliza. Esto es lo recomendado inicialmente
porque no requiere cambio cross-repo.

### Onboarding data verificada

```
nv_onboarding (Admin DB):
- 21 registros (20 draft_builder, 1 submitted_for_review)
- Solo 2 con datos significativos:
  1. testuser: template=sixth, palette=dark_default (no provisionado)
  2. farma: template=eighth, palette=standard_blue (unico provisionado)
- Los 20 drafts son preview+*@example.com (auto-generados)
```

**Riesgo:** Si la unificacion cambia componentKeys Y se limpian los legacy maps,
los onboardings en estado `draft_builder` con `design_config` que referencian
componentKeys legacy se van a romper al provisionar.

**Mitigacion:** NO limpiar LEGACY_KEY_MAP hasta confirmar que no hay onboardings
pendientes con componentKeys legacy.

---

## 22. Addon Store — impacto y nuevos addons monetizables

### Estado actual del Addon Store (33 addons activos)

| Family | Addons | Tipo | Ejemplo |
|--------|--------|------|---------|
| **ai** | 10 | consumable_action | ai_desc_pack_10/50, ai_photo_pack_10/50, ai_faq_pack_10/50, etc. |
| **capacity** | 15 | permanent_entitlement / permanent | slot extras (banner, catalog, features, contact), SEO packs, uplifts |
| **content** | 2 | consumable_action | structure_edit, component_change |
| **media** | 2 | consumable_action | theme_change, custom_theme_surcharge |
| **services** | 3 | consumable_action | template_change, tier_surcharge_growth/enterprise |

### Addons consumidos durante Design Studio

```
ws_action_template_change    → 1 credito al cambiar template
ws_action_theme_change       → 1 credito al cambiar palette
ws_action_structure_edit     → 1 credito por cada add/replace/update/delete/reorder de seccion
ws_action_component_change   → 1 credito al cambiar componentKey de seccion
ws_extra_custom_theme        → surcharge al crear palette custom
ws_extra_growth_visual_asset → surcharge al usar assets Growth en plan Starter
ws_extra_enterprise_visual_asset → surcharge al usar assets Enterprise
```

### Impacto de la unificacion en addons existentes

| Addon | Impacto | Accion |
|-------|---------|--------|
| `ws_action_component_change` | Cambiar variante de un componente unificado consume credito? | **Decidir:** Si cambiar variant es un component_change o no |
| `ws_action_structure_edit` | Sin cambio — agregar/borrar secciones sigue igual | Ninguna |
| `ws_action_template_change` | Sin cambio — cambiar template sigue requiriendo credito | Ninguna |
| `ws_extra_growth_visual_asset` | Si una variante premium requiere plan Growth, el surcharge aplica | Verificar logica |
| Slot extras (banner, catalog) | Sin cambio — limits se verifican igual | Ninguna |

### Nuevos addons propuestos post-unificacion

#### Categoria: Design (family: 'design')

| Addon key | Label | Tipo | Precio sugerido | Plan min |
|---|---|---|---|---|
| `custom_css` | CSS Personalizado | permanent | $15/mo | growth |
| `ai_css_generation_pack_10` | IA — 10 Estilos CSS | consumable_action | $9 | growth |
| `ai_css_generation_pack_50` | IA — 50 Estilos CSS | consumable_action | $29 | growth |
| `premium_variant_unlock` | Variantes Premium | permanent | $19 one-time | starter |

#### Categoria: Branding (family: 'branding')

| Addon key | Label | Tipo | Precio sugerido | Plan min |
|---|---|---|---|---|
| `branding_kit` | Kit de Marca Completo | service | $49 | starter |
| `ai_branding_pack_5` | IA — 5 Sugerencias de Marca | consumable_action | $12 | starter |

#### Categoria: i18n (family: 'i18n')

| Addon key | Label | Tipo | Precio sugerido | Plan min |
|---|---|---|---|---|
| `i18n_pack` | Paquete Multi-Idioma | permanent | $12/mo | growth |
| `ai_translation_pack_20` | IA — 20 Traducciones | consumable_action | $9 | growth |

### Impacto en el flujo de compra

El flujo de compra existente (MercadoPago) es robusto y no requiere cambios:
```
POST /addons/purchase → crea preference MP → webhook confirma pago → fulfillment
```

Solo se necesita insertar las filas nuevas en `addon_catalog` (Admin DB).

---

## 23. Marketing & Branding Manager — feature nueva

### Concepto

Un panel en el admin dashboard donde el tenant gestiona su **identidad de marca**
de forma centralizada. Hoy la marca esta dispersa en multiples secciones:

```
Actual:
  Logo           → LogoSection
  Paleta         → DesignStudio (PaletteSelector)
  Social links   → SocialLinksSection
  Contact info   → ContactInfoSection
  SEO metadata   → SeoAutopilotDashboard
  Banners        → BannerSection
  Nombre tienda  → identity.js (backend)
  Footer links   → IdentityConfigSection (tab 1)
  Anuncios       → IdentityConfigSection (tab 3)
  Dominio        → IdentityConfigSection (tab 4)
```

### Propuesta: Panel "Mi Marca"

Un single-page que unifique los aspectos de branding:

```
┌─────────────────────────────────────────────────────┐
│  MI MARCA                                    [IA ✨] │
├─────────────────────────────────────────────────────┤
│                                                     │
│  [Logo]  NombreTienda    @instagram  @whatsapp      │
│          Slogan           @facebook                 │
│                                                     │
│  ──── Identidad Visual ────────────────────────     │
│  Paleta: ████ ████ ████ ████  [Cambiar]             │
│  Template: Industrial Pro     [Cambiar]             │
│  CSS custom: 3 overrides      [Editar]              │
│                                                     │
│  ──── Presencia Digital ───────────────────────     │
│  Dominio: farma.novavision.lat  [Config]            │
│  SEO Score: 72/100              [Mejorar]           │
│  Analytics: 145 visitas/sem     [Ver]               │
│                                                     │
│  ──── Comunicacion ────────────────────────────     │
│  Banners activos: 3/8          [Gestionar]          │
│  Anuncio top: "Envio gratis..." [Editar]            │
│  WhatsApp: +54 11 ...          [Editar]             │
│                                                     │
│  ──── Kit de Marca IA ✨ ───────────────────────    │
│  [Generar paleta desde logo]                        │
│  [Sugerir slogan]                                   │
│  [Crear banner desde marca]                         │
│  [Audit de consistencia visual]                     │
│                                                     │
└─────────────────────────────────────────────────────┘
```

### Funcionalidades IA del Branding Manager

**1. Paleta desde logo:**
- Upload logo → IA extrae colores dominantes → sugiere paleta `--nv-*`
- Usa Store DNA para contexto (rubro, tono)
- Action code: `ai_branding_palette` (nuevo)

**2. Slogan/tagline:**
- Input: nombre tienda, rubro, Store DNA
- Output: 3-5 opciones de slogan
- Action code: `ai_branding_slogan` (nuevo)

**3. Audit de consistencia visual:**
- Analiza: paleta actual vs colores en banners vs logo
- Detecta: contrastes pobres, colores que no matchean, tokens no usados
- No consume creditos (utility gratuita)

**4. Banner desde marca:**
- Ya existe (`ai_banner_generation`) — se linka desde este panel

### Relacion con la unificacion

El Branding Manager es **independiente** de la unificacion de componentes.
Puede construirse antes, durante o despues. Pero se beneficia de:
- Componentes unificados que respetan tokens CSS → el audit funciona mejor
- Labels configurables (§18) → el Branding Manager puede editar labels globales
- CSS custom (§17) → se integra como seccion del panel

### Impacto en BD

No requiere tablas nuevas. Usa las existentes:
- `clients` → nombre, slug
- `client_home_settings` → template_key, palette_key
- `client_design_overrides` → CSS custom
- `logos` → logo actual
- `social_links` → redes
- `contact_info` → contacto
- `banners` → banners activos

Es un **panel de lectura + links a editores existentes**, no una duplicacion de funcionalidad.

---

## 24. Test matrix y edge cases

### Tests unitarios requeridos por componente unificado

#### ProductCard (Ticket 1)

| Test | Tipo | Edge case |
|---|---|---|
| Renderiza variante `simple` con datos minimos | Unit | producto sin imagen, sin precio, sin stock |
| Renderiza variante `interactive` con hover cart | Unit | desktop vs mobile (no hover en mobile) |
| Renderiza variante `full` con badges (Agotado, Descuento, Envio gratis) | Unit | badges combinados (agotado + descuento) |
| Renderiza variante `showcase` con motion | Unit | `prefers-reduced-motion: reduce` |
| Badge "Agotado" usa label configurable | Unit | `labels.outOfStock = 'Esgotado'` |
| Precio con currency symbol configurable | Unit | `currency.symbol = 'R$'` vs `$` |
| Click en favorito requiere login | Integration | usuario no logueado → toast |
| Click en agregar al carrito actualiza carrito | Integration | carrito lleno vs vacio |
| Skeleton renderiza por variante | Unit | 4 variantes de skeleton |
| Dark mode aplica colores correctos | Visual | todas las variantes en dark mode |
| **Edge:** producto con 0 imagenes | Unit | placeholder visible, no crash |
| **Edge:** precio = 0 (gratis) | Unit | mostrar "Gratis" no "$0" |
| **Edge:** nombre muy largo (100+ chars) | Unit | truncate con ellipsis |
| **Edge:** descuento > 50% | Unit | badge rojo mas prominente |

#### FAQSection (Ticket 2)

| Test | Edge case |
|---|---|
| Accordion toggle abre/cierra | click rapido multiple |
| Solo 1 FAQ abierta a la vez (accordion mode) | multiples clicks |
| Variante `cards` renderiza grid | 0 FAQs, 1 FAQ, 20+ FAQs |
| Variante `masonry` layout correcto | ancho variable, responsive |
| **Edge:** FAQ sin respuesta | mostrar pregunta sin collapse |
| **Edge:** HTML en respuesta FAQ | sanitizar XSS |

#### ContactSection (Ticket 3)

| Test | Edge case |
|---|---|
| WhatsApp link genera URL correcta | `+54 11...` vs `5411...` |
| Formulario de contacto valida campos | email invalido, campos vacios |
| **Edge:** sin contactInfo configurado | mostrar seccion vacia gracefully |
| **Edge:** `whatsappMessage` con caracteres especiales | URL encoding |

#### Footer (Ticket 4)

| Test | Edge case |
|---|---|
| Variante `branded` preserva identidad T6/T7/T8 | screenshot diff |
| Social links correctos | 0 links, 4+ links, link invalido |
| **Edge:** newsletter submit sin email | validacion |
| **Edge:** links legales vacios | no crashear, ocultar seccion |

#### ServicesSection (Ticket 5)

| Test | Edge case |
|---|---|
| Grid responsive (1-4 columnas) | 1 servicio vs 12 servicios |
| Hover effects en `cards-hover` | no hover en mobile |
| **Edge:** servicio sin icono | placeholder icon |
| **Edge:** descripcion muy larga | truncate o wrap |

### Tests de integracion cross-component

| Test | Componentes | Edge case |
|---|---|---|
| Template change preserva secciones | DesignStudio + SectionRenderer | T5 → T2 con secciones custom |
| Template change con CSS custom activo | DesignStudio + useDesignOverrides | CSS apunta a selectores del template anterior |
| Plan downgrade no rompe template activo | Subscription + DesignStudio | Growth → Starter con template fourth |
| Palette change actualiza todos los componentes | PaletteSelector + useThemeVars | cambiar palette con dark mode activo |
| Section add/delete actualiza preview | DesignStudio + PreviewFrame | agregar 10 secciones rapidamente |
| Labels se inyectan en cascada | SectionRenderer + localeDefaults | override manual > locale default > fallback |

### Tests E2E criticos

| Test | Flujo |
|---|---|
| Onboarding completo → tienda publicada | wizard → template → palette → preview → submit → provision |
| Compra de addon → efecto inmediato | addon store → MP checkout → webhook → credito visible |
| Checkout completo | browse → add to cart → checkout → payment → success |
| Design Studio round-trip | cambiar template → agregar seccion → editar props → guardar → verificar en storefront |
| AI banner generation → banner visible | prompt → generate → accept → banner en storefront |

### Visual regression matrix actualizada

```
8 templates × 3 viewports × 7 componentes × 2 modes (light/dark) = 336 screenshots

Viewports: 375px (mobile), 768px (tablet), 1440px (desktop)
Componentes: ProductCard, FAQ, Contact, Footer, Services, Carousel, Header
Modes: light, dark (prefers-color-scheme)

Reducido a 168 screenshots si solo se testean los templates que
efectivamente usan cada componente (no todos los templates usan todos).
```

---

## 25. Impacto en render pipeline

### Pipeline actual verificado

```
DB → API /home/data → App.jsx → resolveEffectiveTheme() → useThemeVars() → CSS vars
                              → HomeRouter → TEMPLATES[templateKey] (lazy) → template page
                              → SectionRenderer → sectionComponents (lazy) → section component
```

### Impacto del cambio

| Capa | Antes | Despues | Riesgo |
|---|---|---|---|
| `/home/data` response | `componentKey: 'catalog.carousel.first.featured'` | Sin cambio (LEGACY_KEY_MAP normaliza) | Ninguno |
| `SectionRenderer` | Busca en `sectionComponents` por key exacto o fallback .first | Busca componente unificado + inyecta `variant` prop | Bajo |
| `sectionComponents.tsx` | 70+ entries con lazy imports a templates/* | Menos entries apuntando a storefront/* | Medio (transicion) |
| `templatesMap.ts` | 8 lazy imports (1 por template page) | Sin cambio | Ninguno |
| `resolveEffectiveTheme` | Sin cambio | Sin cambio | Ninguno |
| `useThemeVars` | Sin cambio | Sin cambio | Ninguno |
| `useDesignOverrides` (nuevo) | No existe | Inyecta CSS custom en `<head>` despues de theme vars | Bajo |

### Code splitting — impacto en bundle size

**Antes (estado actual):**
```
templates/first/components/ProductCard.jsx     → chunk por template
templates/second/components/ProductCard.jsx    → chunk por template
...
templates/fifth/components/ProductCard.jsx     → chunk por template
```

Cada template page importa sus propios componentes → chunks separados por template.
Un usuario que visita template first nunca carga codigo de template second.

**Despues (unificado):**
```
storefront/ProductCard/index.tsx               → chunk compartido
storefront/ProductCard/variants/simple.tsx      → lazy sub-chunk
storefront/ProductCard/variants/interactive.tsx → lazy sub-chunk
```

**Riesgo:** Si las variantes no se cargan con `React.lazy()`, el bundle del
componente unificado incluye TODAS las variantes, aumentando el tamaño del chunk
compartido. El plan ya establece la regla de lazy variants (§9.1), pero debe
verificarse con `npx vite-bundle-analyzer`.

**Target:**
- Chunk compartido (logica comun): < 15KB gzipped
- Cada variante: < 5KB gzipped
- Total por template visitado: no debe exceder el chunk actual del template

### Performance — renders adicionales

**Antes:** `<ProductCardFirst {...props} />`
**Despues:** `<ProductCard variant="simple" {...props} />`

El layer adicional de `variant` prop + conditional render agrega ~0.1ms por componente.
Con 20 ProductCards en una pagina, esto es ~2ms adicional. Imperceptible.

**El unico riesgo real** es si el componente unificado importa estilos de todas
las variantes sin tree-shaking. Styled-components con interpolacion condicional
(`${props.variant === 'interactive' && css``}`) NO permite tree-shaking.

**Solucion:** Cada variante en archivo separado. El `index.tsx` solo importa
la variante necesaria via dynamic import o switch/map.

### CSS custom override — orden de cascada

```
1. Browser defaults
2. Reset/normalize
3. styled-components (template-specific styles)
4. CSS variables (--nv-* tokens via useThemeVars)
5. Dark mode overrides (prefers-color-scheme media query)
6. Custom CSS overrides (useDesignOverrides → <style> tag)
```

**La posicion 6 garantiza que el CSS custom siempre gana sobre los estilos del template.**
Esto es correcto porque el CSS custom es la personalizacion mas especifica.

**Riesgo:** Si el CSS custom usa `!important`, puede ser imposible de overridear
desde el template. La sanitizacion server-side debe **bloquear `!important`**
para evitar side effects.

---

## 26. Resumen de decisiones pendientes actualizadas

Ademas de las decisiones originales (§ Tickets), la auditoria agrega:

| # | Decision | Opciones | Recomendacion |
|---|----------|----------|---------------|
| 1 | Canon de template_key entre BDs | `eighth` vs `template_8` | `eighth` (el canon del catalogo) |
| 2 | Cambiar variant cuenta como component_change? | Si → consume credito / No → gratis | No — es ajuste visual, no cambio estructural |
| 3 | Plan downgrade con template premium | Forzar change / Congelar / Ignorar | Ignorar (grandfathering) |
| 4 | CSS custom permite `!important`? | Si / No | No — bloquear en sanitizacion |
| 5 | Branding Manager como seccion del admin | Nueva seccion / Vista overview | Nueva seccion con links a editores existentes |
| 6 | LEGACY_KEY_MAP: limpiar o mantener? | Limpiar post-migracion / Mantener forever | Mantener 6 meses, luego evaluar |
| 7 | Custom palette API methods | Implementar en identity.js / Postergar | Implementar (bug activo) |

---

## Anexo A: Flujo completo del DesignStudio (verificado)

### Template change flow

```
1. UI: DesignStudio.jsx:299 → setSelectedTemplate(newKey)
2. Validation: evaluateTemplateCompatibility(sections, selectedTemplate)
   - compatibility.js:40 → mapea componentKeys al nuevo template (regex suffix swap)
   - Si incompatible → bloquea con toast error, save impedido
3. Credit check: structureCatalog calcula tokens necesarios
   - Si faltan creditos → toast + redirige a AddonStore
4. Save: identity.js:24 → PUT /settings/home { templateKey, paletteKey }
5. Response: consumedCredits[] → applyConsumedCredits()
6. Preview: PreviewFrame actualiza via postMessage({ type: 'nv:preview:render' })
```

### Section CRUD flow

```
ADD section:
  1. handleAddSection() → crea seccion con id temporal (TEMP_SECTION_ + timestamp)
  2. Token cost calculado desde componentCatalogMap[componentKey]
  3. Plan gating: canAccessByPlan(planKey, minPlan) + limitReached check
  4. Section insertada localmente en draft

PERSIST (apply draft):
  1. buildStructureActionPlan() → calcula acciones: ADD, REPLACE, UPDATE, DELETE, REORDER
  2. Cada accion cuesta 1 token (consumable: ws_action_structure_edit)
  3. Secuencia API:
     a. POST /home/sections (add)         → temp_id → real_id
     b. PATCH /home/sections/:id/replace  → cambia componentKey
     c. PATCH /home/sections/:id/props    → actualiza props
     d. DELETE /home/sections/:id         → elimina
     e. PATCH /home/sections/order        → reordena

DRAFT (localStorage):
  Key: nv-store-design-structure-draft:{slug}
  Se hidrata al montar, se descarta al guardar exitosamente
```

### Preview system

```
Communication protocol:
  Admin → iframe: postMessage({ type: 'nv:preview:render', requestId, payload })
  iframe → Admin: postMessage({ type: 'nv:preview:height', requestId, height })

Payload:
  {
    requestId: string (unique per change),
    config: { sections: SectionInstance[] },
    templateKey: string,
    paletteKey: string,
    paletteVars: Record<string, string>,
    themeOverride: Record<string, any>,
    seed: HomeData,
    mode: 'editor' | 'production',
    clientSlug: string
  }

Triggers:
  - Template change → new requestId
  - Palette change → new requestId
  - Section add/delete/reorder → via previewSections dependency
  - Props edit → via previewSections dependency
```

---

## Anexo B: Onboarding flow completo (verificado)

### Estados del wizard

```
not_started     → /builder          (nuevo usuario)
in_progress     → /builder          (editando activamente)
submitted       → /onboarding/status (bajo revision — NUNCA /builder)
completed       → /hub              (aprobado, operativo)
live            → /hub              (fully operational)

Overrides por account status:
  incomplete         → /complete
  changes_requested  → /complete
  pending_approval   → /onboarding/status
  provisioning       → /onboarding/status
  suspended/rejected → /onboarding/status
  approved/live      → /hub
```

### Template seed por provision

```typescript
// API: default-template-sections.ts
// Cada template define un preset de secciones iniciales:

Template first (9 secciones):
  header.first → hero.first → features.grid.first →
  catalog.grid.first → catalog.carousel.first.featured →
  content.contact.first → catalog.carousel.first.bestsellers →
  content.faq.first → footer.first

Template eighth (9 secciones):
  header.first → hero.eighth → catalog.showcase.eighth →
  features.eighth → content.testimonials.eighth →
  content.faq.eighth → content.newsletter.eighth →
  content.contact.eighth → footer.eighth
```

### Provisioning job sequence

```
1. PROVISION_CLIENT — Crea client en Backend DB desde nv_onboarding data
   - Inserta en clients: slug, name, template_id, plan_key
   - Inserta en client_home_settings: template_key, palette_key
   - Ejecuta cada 30s con FOR UPDATE SKIP LOCKED (concurrencia safe)

2. SEED_TEMPLATE — Seedea home_sections iniciales
   - Lee default-template-sections.ts[templateKey]
   - Inserta N secciones en home_sections con sort_index secuencial

3. SYNC_ENTITLEMENTS — Sincroniza entitlements (si aplica)
   - Calcula entitlements base + addon overrides
   - Guarda en account_entitlements (actualmente no ejecutado)
```

---

## Anexo C: Addon catalog completo (verificado contra Admin DB)

### 33 addons activos agrupados por familia

**Family: ai (10 addons — consumable_action)**

| addon_key | display_name | credits | action_code |
|---|---|---|---|
| ai_desc_pack_10 | 10 Descripciones | 10 | ai_product_description |
| ai_desc_pack_50 | 50 Descripciones | 50 | ai_product_description |
| ai_photo_pack_10 | 10 Fichas desde Foto | 10 | ai_photo_product |
| ai_photo_pack_50 | 50 Fichas desde Foto | 50 | ai_photo_product |
| ai_faq_pack_10 | FAQs para 10 Productos | 10 | ai_faq_generation |
| ai_faq_pack_50 | FAQs para 50 Productos | 50 | ai_faq_generation |
| ai_qa_pack_20 | 20 Respuestas Q&A | 20 | ai_qa_answer |
| ai_qa_pack_100 | 100 Respuestas Q&A | 100 | ai_qa_answer |
| ai_mapping_pack_5 | 5 Analisis de Archivo | 5 | ai_column_mapping |
| ai_mapping_pack_15 | 15 Analisis de Archivo | 15 | ai_column_mapping |

**Family: capacity (15 addons)**

| addon_key | tipo | grants |
|---|---|---|
| ws_slot_extra_banner | permanent_entitlement | +1 banner slot |
| ws_slot_extra_catalog | permanent_entitlement | +1 catalog slot |
| ws_slot_extra_features | permanent_entitlement | +1 features slot |
| ws_slot_extra_contact | permanent_entitlement | +1 contact slot |
| seo_ai_pack_site | permanent | SEO site completo |
| seo_ai_pack_500 | permanent | 500 SEO metadata |
| seo_ai_pack_2000 | permanent | 2000 SEO metadata |
| + 8 uplifts mensuales | permanent | products, services, faq, banners, images boosts |

**Family: content (2), media (2), services (3)**

| addon_key | action_code | uso |
|---|---|---|
| ws_action_structure_edit | structure_edit | Cambios de estructura en DesignStudio |
| ws_action_component_change | component_change | Cambio de componentKey |
| ws_action_theme_change | theme_change | Cambio de palette/theme |
| ws_extra_custom_theme | custom_theme_surcharge | Surcharge por palette custom |
| ws_action_template_change | template_change | Cambio de template |
| ws_extra_growth_visual_asset | tier_surcharge_growth | Surcharge por asset Growth |
| ws_extra_enterprise_visual_asset | tier_surcharge_enterprise | Surcharge por asset Enterprise |

### Addons NUEVOS propuestos (no en BD aun)

| addon_key | family | tipo | precio sugerido | descripcion |
|---|---|---|---|---|
| custom_css | design | permanent | $15/mo | Editor CSS custom |
| ai_css_generation_pack_10 | design | consumable_action | $9 | 10 generaciones CSS IA |
| ai_css_generation_pack_50 | design | consumable_action | $29 | 50 generaciones CSS IA |
| premium_variant_unlock | design | permanent | $19 one-time | Variantes premium |
| branding_kit | branding | service | $49 | Kit de marca completo |
| ai_branding_pack_5 | branding | consumable_action | $12 | 5 sugerencias de marca IA |
| i18n_pack | i18n | permanent | $12/mo | Multi-idioma |
| ai_translation_pack_20 | i18n | consumable_action | $9 | 20 traducciones IA |

---

## Anexo D: Component catalog completo (70 entries verificadas)

### Distribucion por categoria

| Categoria | Tipo | Cantidad | Component keys |
|---|---|---|---|
| catalog | catalog | 17 | carousel.first.featured/bestsellers, carousel.second.*, carousel.third.*, carousel.fourth, carousel.fifth.*, grid.first/third/fourth/fifth, showcase.sixth/seventh/eighth, categories.carousel.third |
| communication | contact | 8 | content.contact.{first..eighth} |
| content | faq | 8 | content.faq.{first..eighth} |
| content | features | 8 | features.grid.first/third, features.list.second, features.content.fourth/fifth, features.sixth/seventh/eighth |
| layout | banner | 2 | banner.video.spotlight, banner.simple |
| layout | footer | 8 | footer.{first..eighth} |
| layout | header | 5 | header.{first..fifth} — **T6/T7/T8 reusan headers existentes** |
| layout | hero | 9 | hero.{first..eighth} + hero.video.background |
| marketing | contact | 1 | content.newsletter.eighth |
| marketing | features | 1 | content.marquee.sixth |
| social-proof | testimonials | 3 | content.testimonials.{sixth,seventh,eighth} |

### Implicaciones para la unificacion

- **Headers (5):** NO entran en el sprint actual (§Fase 7)
- **Heroes (9):** NO entran en el sprint actual
- **Catalog (17):** El ProductCard unificado (Ticket 1) se usa dentro de estas secciones
- **Contact (8):** Ya parcialmente unificado via DynamicContactSection (§14.2)
- **FAQ (8):** Ticket 2
- **Footer (8):** Ticket 4
- **Features (8):** Ticket 5
- **Testimonials (3):** NO entran — solo T6/T7/T8 los usan
- **Banner/Newsletter/Marquee:** NO entran — componentes especializados

---

## Anexo E: Admin Dashboard — mapa completo de funcionalidades

### 5 categorias, 27 secciones

**Tienda y Ventas:**
Products | Import Wizard (8 pasos, AI column mapping) | Orders | Payments |
Shipping | Coupons (CRUD completo, 3 tipos, 3 scopes, plan-gated) |
Option Sets | Size Guides | Q&A Manager (AI suggest) | Reviews Manager (AI suggest)

**Marca y Contenido:**
Logo | Banners (AI generation, 5 estilos) | Store Design (DesignStudio) |
Identity Config (4 tabs: footer, contacto/mapa, anuncios, dominio) |
Services | FAQs | SEO AI Autopilot (4 tabs) | Media Library (batch upload, 50 files)

**Contacto y Redes:**
Contact Info (CRUD) | Social Links (WhatsApp, Instagram, Facebook)

**Cuenta y Plan:**
Usage Dashboard | Analytics (KPIs, graficos, date range) | Addon Store |
Billing | Subscription | Support Tickets

**Usuarios:**
User Management

### Marketing features existentes vs faltantes

**Existentes:**
- Coupons (descuento %, monto fijo, envio gratis)
- SEO AI Autopilot (audit, edit, jobs)
- Analytics (ordenes, revenue, payments, productos top)
- Banners (desktop/mobile, AI generation)
- Social links (WhatsApp, Instagram, Facebook)

**Faltantes (oportunidades futuras):**
- Email marketing / newsletter campaigns
- Abandoned cart recovery
- Customer segmentation
- Loyalty/referral programs
- Flash sale / limited time offers
- A/B testing visual
- Conversion funnel analysis
- Push notifications

---

## Anexo F: Impacto y valor agregado al producto

### Vision general

En una oracion: **convertimos una plataforma que escala con dolor en una que
escala con ventaja competitiva.**

Sin estos cambios, cada feature nueva, cada fix, cada expansion de mercado
requiere tocar 8 templates × N archivos. Con estos cambios, todo se hace 1 vez.

### Impacto en velocidad de desarrollo

| Metrica | Antes | Despues | Mejora |
|---------|-------|---------|--------|
| Archivos para fix de UI | 8-10 | 1-2 | **5x** |
| Lineas a revisar por fix | ~800 | ~150 | **5x** |
| Tiempo por fix cross-template | 30-45 min | 5 min | **6-9x** |
| Templates olvidados por error | Frecuente | Imposible | **Eliminado** |
| Implementar feature nueva | 8 veces | 1 vez | **8x** |
| Onboarding de nuevo dev | Semanas (130 archivos) | Dias (1 patron) | **Significativo** |

**Resultado cuantificable:** ~5,000 lineas eliminadas, ~40 archivos menos.

### Features de producto habilitadas

| Feature | Que habilita | Impacto de negocio |
|---|---|---|
| **CSS custom por cliente** | Cada tienda tiene su estilo unico | Diferenciador vs Tiendanube/Shopify: "tu tienda no se ve como las demas" |
| **CSS generado por IA** | El cliente describe y la IA diseña | Wow factor. Vendible como addon premium |
| **Labels configurables** | Textos de UI editables por tienda | **Habilita que NovaVision venda en Brasil** — tenants brasileños con UI en portugues, sin reescribir codigo |
| **Locale por tenant** | Cada tienda en su idioma nativo | NovaVision puede operar como SaaS en pt-BR, es-MX, en-US — cada tenant nuevo ya sale en su idioma |
| **Branding Manager** | Panel centralizado de identidad de marca | El dueño siente que controla su marca, no que usa un template generico |
| **Variantes por plan** | Starter se ve bien, Growth se ve mejor | Incentivo real de upgrade — el usuario VE la diferencia |
| **Template change mejorado** | Warning de CSS custom, draft stale, grandfathering | Reduce soporte, evita tickets de "se me rompio la tienda" |

### Revenue directo — addons nuevos monetizables

| Addon | Precio sugerido | Modelo | Plan min |
|---|---|---|---|
| CSS Personalizado | $15/mes | Recurrente | growth |
| AI CSS Generation (10 creditos) | $9 | Consumible | growth |
| AI CSS Generation (50 creditos) | $29 | Consumible | growth |
| Kit de Marca IA | $49 | One-time | starter |
| AI Sugerencias de Marca (5 creditos) | $12 | Consumible | starter |
| Paquete Multi-Idioma | $12/mes | Recurrente | growth |
| AI Traducciones (20 creditos) | $9 | Consumible | growth |
| Variantes Premium | $19 | One-time | starter |

**Proyeccion MRR:**
Si el 20% de clientes Growth compra CSS custom ($15) + i18n ($12) = **+$5.40/cliente/mes**.
Con 100 clientes Growth = **+$540/mes** solo en estos 2 addons recurrentes.

Los consumibles (AI CSS, traducciones, branding) son revenue incremental
sin costo de infraestructura adicional (usan el sistema de creditos existente).

### Deuda tecnica eliminada

| Problema preexistente | Ticket | Estado post-implementacion |
|---|---|---|
| template_key `template_8` vs `eighth` entre BDs | D3 | Corregido — canon unico |
| Plan `pro` fantasma en palette_catalog | D4 | Corregido — luxury_gold accesible |
| Custom palette editor roto silenciosamente | D6 | Corregido — API implementada |
| Locale vacio en clientes e2e | D5 | Corregido — default es-AR |
| 20 cuentas preview sin limpiar | D7 | Corregido — TTL automatico |
| Documentacion BD incorrecta | T13 | Corregido — nombres reales |
| 18+ strings hardcodeados en español | T7 | Corregido — props configurables |
| 34 colores hardcodeados sin var() | T1-T6 | Corregido — tokens CSS |
| Dark mode con colores rotos | T1-T6 | Corregido — todo via --nv-* |

### Escalabilidad tecnica

```
ANTES:
  Nuevo template   = copiar 9+ archivos + personalizar cada uno
  Nuevo mercado    = buscar y reemplazar strings en 130 archivos
  Feature visual   = rezar que funcione en los 8 templates
  Fix de dark mode = editar N archivos con colores hardcodeados

DESPUES:
  Nuevo template   = 1 archivo config con variantes
  Nuevo mercado    = 1 archivo localeDefaults + 1 ALTER TABLE
  Feature visual   = 1 componente, funciona en todos
  Fix de dark mode = ya funciona (tokens CSS obligatorios)
```

### Experiencia del usuario final

| Sin estos cambios | Con estos cambios |
|---|---|
| "Mi tienda se ve igual que todas las de NovaVision" | "Mi tienda tiene MI estilo" (CSS custom) |
| NovaVision solo puede captar clientes hispanohablantes | NovaVision puede vender a emprendedores brasileños — UI nativa en pt-BR |
| "No se como mejorar el diseño" | "La IA me sugiere mejoras" (Branding IA) |
| "Cambie de template y se rompio" | Warning inteligente + compatibilidad |
| Dark mode con colores inconsistentes | Dark mode perfecto en todos los componentes |
| "Quiero eso pero es del plan Growth" | Ve la variante premium → incentivo de upgrade |

### Transformacion estrategica del producto

```
NovaVision HOY:
  "Hacete tu tienda online"
  → Commodity. Cualquier plataforma lo ofrece.
  → El usuario elige por precio, no por valor.

NovaVision DESPUES:
  "Hacete tu tienda online con TU identidad,
   y deja que la IA diseñe por vos"
  → Diferenciador real.
  → CSS custom + IA + branding = trilogia que ninguna
    plataforma argentina ofrece hoy.
  → El usuario elige por valor, no por precio.
  → NovaVision puede vender como SaaS en Brasil (pt-BR nativo)
    sin reescribir una sola linea de frontend.
```

### Cadena de valor

```
Unificacion de componentes (T0-T6)
  └── Es invisible para el usuario
  └── PERO habilita TODO lo demas:

  ├── CSS custom confiable (T9)
  │     Sin unificacion: cada template se comporta diferente,
  │     el CSS custom rompe en algunos templates si.
  │     Con unificacion: tokens CSS consistentes, CSS predecible.
  │
  ├── Labels configurables (T7)
  │     Sin unificacion: hay que editar "Agotado" en 5 ProductCards.
  │     Con unificacion: se edita 1 vez.
  │
  ├── IA de diseño (T10, T12)
  │     Sin unificacion: la IA no puede "pensar" en variantes
  │     porque no existen como concepto.
  │     Con unificacion: la IA sugiere variantes, genera CSS,
  │     y sabe que el resultado va a ser consistente.
  │
  └── Velocidad de desarrollo (permanente)
        Cada feature futura se construye 1 vez en vez de 8.
        El ROI se acumula con cada sprint.
```

**Conclusion:** La unificacion por si sola elimina 5,000 lineas. Pero su valor
real es que transforma la plataforma de "template generico" a "plataforma de
identidad de marca" — y eso es lo que se vende.

---

## §27: Generacion de templates — antes vs. despues de la unificacion

### 27.1 Estado actual: archivos por template (real)

```
Template      Archivos JSX/TSX   Componentes re-exportados
───────────   ────────────────   ─────────────────────────
first              20            HeroFirst, ProductFirst, ServicesFirst, FaqFirst, ContactFirst, FooterFirst...
second             42            HeroSecond, ProductSecond... (mas variantes y paginas extra)
third              18            HeroThird, ProductThird, ServicesThird, FaqThird, ContactThird, FooterThird...
fourth             16            HeroFourth, ProductFourth, ...
fifth              21            HeroFifth, ProductFifth, ...
sixth               9            HeroSixth, ProductShowcaseSixth, ServicesSixth, FaqSixth, ContactSixth, FooterSixth, TestimonialsSixth, MarqueeSixth
seventh             8            HeroSeventh, ProductSeventh, ServicesSeventh, FaqSeventh, ContactSeventh, FooterSeventh, TestimonialsSeventh, NewsletterSeventh
eighth             10            HeroEighth, ProductShowcaseEighth, ServicesEighth, FaqEighth, ContactEighth, FooterEighth, TestimonialsEighth, NewsletterEighth
───────────   ────────────────
TOTAL             144 archivos
```

**Observacion:** Los templates mas nuevos (sixth-eighth) siguen la guia de arquitectura y tienen 8-10 archivos. Los legacy (first-fifth) tienen 16-42 archivos por patrones antiguos.

### 27.2 Proceso actual de agregar un template

Segun `ADDING_TEMPLATES_AND_COMPONENTS.md` (14-point checklist):

1. Crear carpeta `templates/{nombre}/pages/HomePage/index.jsx` (~120 lineas)
2. Crear 6-8 carpetas de componentes: Hero, ProductShowcase, Services, FAQ, Contact, Footer, Testimonials, etc. (~2,000 lineas)
3. Crear `registry/sectionComponentTemplates/{nombre}.tsx` (re-exports, ~20 lineas)
4. Agregar lazy imports en `registry/sectionComponents.tsx` (~30 lineas)
5. Agregar entry en `registry/templatesMap.ts` (2 lineas)
6. Agregar normalizacion en `theme/resolveEffectiveTheme.ts` (1 linea)
7. Agregar metadata en `templates/manifest.js` (~15 lineas)
8. Agregar header variant en `DynamicHeader.jsx` (2-5 lineas)
9. Backend: agregar entries en `VARIANT_REGISTRY` (8-12 entradas por componente)
10. DB: insertar row en `nv_templates` + crear `palette_catalog` entries
11. Prompt IA genera todo el codigo desde cero (via TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md)

**Total por template nuevo:** ~13-15 archivos, ~2,300 lineas, 4-6 horas de trabajo

### 27.3 Proceso DESPUES de la unificacion

Con componentes unificados, un template nuevo solo necesita:

**Paso 1: Archivo de config del template** (NUEVO concepto)

```
templates/{nombre}/
├── config.js          ← 40-60 lineas: que variantes usar de cada componente
└── pages/HomePage.jsx ← 50-70 lineas: generico, solo renderiza SectionRenderer
```

Ejemplo de `config.js`:
```js
export default {
  templateKey: 'template_9',
  name: 'Neon Pulse',
  defaultSections: [
    { type: 'hero', variant: 'editorial', props: { height: 'xl', textAlign: 'center' } },
    { type: 'catalog', variant: 'masonry', props: { columns: 4, showFilters: true } },
    { type: 'features', variant: 'minimal', props: { iconPosition: 'top' } },
    { type: 'faq', variant: 'accordion', props: { style: 'bordered' } },
    { type: 'contact', variant: 'split', props: {} },
    { type: 'footer', variant: 'columns', props: { socialPosition: 'right' } },
  ],
  defaultTokens: {
    '--nv-primary': '#7C3AED',
    '--nv-bg': '#0A0A0F',
    '--nv-spacing-section': '5rem',
    '--nv-font': "'Space Grotesk', sans-serif",
  },
};
```

**Paso 2: Home generico** (reutilizable o minimo)

```jsx
import templateConfig from '../config';

function HomePage({ homeData }) {
  const data = homeData || DEMO_HOME_DATA;
  const sections = data?.config?.sections?.length > 0
    ? data.config.sections
    : templateConfig.defaultSections;

  return (
    <div style={{ fontFamily: 'var(--nv-font)' }}>
      {sections.map(section => (
        <SectionRenderer key={section.id} section={section} data={data} />
      ))}
    </div>
  );
}
```

**Paso 3: Registro minimo**

- `templatesMap.ts`: agregar 2 lineas (lazy import)
- `resolveEffectiveTheme.ts`: agregar 1 linea (normalizacion)
- DB: insertar en `nv_templates` + `palette_catalog`
- Backend VARIANT_REGISTRY: **0 cambios** (usa variantes genericas ya registradas)
- `sectionComponentTemplates/`: **0 archivos** (no hay componentes propios)

### 27.4 Comparacion cuantitativa

| Metrica | ANTES | DESPUES | Reduccion |
|---------|-------|---------|-----------|
| Archivos nuevos | 13-15 | 3-4 | **75%** |
| Lineas de codigo | ~2,300 | ~150 | **93%** |
| Carpetas de componentes | 6-8 | 0 | **100%** |
| Entries en VARIANT_REGISTRY | 8-12 | 0 | **100%** |
| sectionComponentTemplates | 1 archivo (20 lineas) | 0 | **100%** |
| Entries en sectionComponents.tsx | ~30 lineas | 0 | **100%** |
| Tiempo estimado | 4-6 horas | 30-45 minutos | **85%** |
| Testing requerido | Suite nueva completa | Solo config + visual | **Significativo** |

### 27.5 Impacto en el prompt de generacion IA

El archivo `TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md` debe actualizarse:

**ELIMINAR del prompt:**
- Instrucciones de crear carpetas de componentes
- Ejemplos de HeroSixth, ProductShowcaseSixth, etc.
- La guia de crear sectionComponentTemplates

**AGREGAR al prompt:**
- Estructura de `config.js` con variantes disponibles
- Lista de variantes registradas por tipo de seccion
- Guia de tokens de spacing y font
- Restriccion: NO crear componentes nuevos, solo seleccionar variantes
- Ejemplo de Home generico con SectionRenderer

**Resultado:** La IA pasa de "generar 2,000 lineas de JSX" a "seleccionar variantes + definir tokens" — es un prompt mas simple, mas rapido, y con menos riesgo de errores.

### 27.6 Transicion gradual

Los 8 templates existentes siguen funcionando con sus componentes propios (backward compatible). El nuevo flujo aplica solo a templates nuevos (9+). Si se quiere, los templates legacy se pueden migrar gradualmente reemplazando componentes propios por variantes genericas.

---

## §28: Generalizacion de spacing — tokens CSS

### 28.1 Estado actual

**El spacing esta 100% hardcodeado** en clases Tailwind dentro de cada componente:

```jsx
// HeroSection/sixth — hardcodeado
className="py-20 md:py-28 px-6 md:px-16 lg:px-24"

// FAQSection/sixth — diferente, tambien hardcodeado
className="py-20 md:py-28 px-6 md:px-16 lg:px-24"

// ContactSection/sixth — mismo patron pero inconsistente con otros templates
className="py-20 md:py-28 px-6 md:px-16 lg:px-24"
```

**Problema:** Cada template tiene sus propios valores de padding/gap. No hay forma de que un cliente ajuste la "densidad visual" de su tienda sin CSS custom.

### 28.2 Tokens propuestos

Agregar al contrato de `paletteToCssVars` en `palettes.ts` (actualmente 27 tokens → pasaria a 35):

```
// ── Spacing ───────────────────────────────────
'--nv-spacing-xs':      '0.5rem',   // 8px  — gaps internos pequeños
'--nv-spacing-sm':      '0.75rem',  // 12px — padding de badges/chips
'--nv-spacing-md':      '1rem',     // 16px — padding de cards
'--nv-spacing-lg':      '1.5rem',   // 24px — gap entre items
'--nv-spacing-xl':      '2rem',     // 32px — padding de secciones mobile
'--nv-spacing-section': '5rem',     // 80px — padding vertical entre secciones
'--nv-spacing-page':    '1.5rem',   // 24px — padding horizontal de pagina (mobile)
'--nv-spacing-page-lg': '6rem',     // 96px — padding horizontal de pagina (desktop)
```

### 28.3 Uso en componentes unificados

```jsx
// ANTES (hardcodeado):
className="py-20 md:py-28 px-6 md:px-16 lg:px-24"

// DESPUES (tokenizado):
className="py-[var(--nv-spacing-section)] px-[var(--nv-spacing-page)] lg:px-[var(--nv-spacing-page-lg)]"
```

**Beneficios:**
- El DesignStudio puede ofrecer un control de "Densidad": compacta / normal / relajada
- Cada template puede definir su spacing preferido en `config.js`
- CSS custom puede modificar spacing sin romper el layout
- La IA puede generar spacing personalizado

### 28.4 Presets de densidad

```js
export const DENSITY_PRESETS = {
  compact: {
    '--nv-spacing-section': '3rem',
    '--nv-spacing-page': '1rem',
    '--nv-spacing-page-lg': '4rem',
    '--nv-spacing-lg': '1rem',
  },
  normal: {
    '--nv-spacing-section': '5rem',
    '--nv-spacing-page': '1.5rem',
    '--nv-spacing-page-lg': '6rem',
    '--nv-spacing-lg': '1.5rem',
  },
  relaxed: {
    '--nv-spacing-section': '7rem',
    '--nv-spacing-page': '2rem',
    '--nv-spacing-page-lg': '8rem',
    '--nv-spacing-lg': '2rem',
  },
};
```

### 28.5 UI en DesignStudio

Agregar un control simple de 3 opciones en el panel de tema:

```
┌─────────────────────────────────────────┐
│  Densidad visual                         │
│  ○ Compacta   ● Normal   ○ Relajada     │
│                                          │
│  Preview: los espacios entre secciones   │
│  se ajustan en tiempo real               │
└─────────────────────────────────────────┘
```

### 28.6 Almacenamiento

Se guarda en `client_home_settings.theme_config` (Backend DB) junto con la paleta:

```json
{
  "palette_key": "dark_default",
  "custom_vars": {
    "--nv-spacing-section": "7rem",
    "--nv-spacing-page": "2rem"
  }
}
```

El `resolveEffectiveTheme()` ya soporta `custom_vars` override — no requiere cambios en el pipeline de tema.

---

## §29: Seleccion de fonts como feature

### 29.1 Estado actual

- **Token `--nv-font` existe** en `palettes.ts:464` con default `Inter, system-ui, sans-serif`
- **Se usa** en 3 de 8 templates (sixth, seventh, eighth) via `fontFamily: 'var(--nv-font, inherit)'`
- Los templates first-fifth **no lo referencian** — heredan el font del body/browser
- **No hay UI** para que el admin elija tipografia
- El token se inyecta en `paletteToCssVars()` como valor fijo, no configurable

### 29.2 Catalogo de fonts propuesto

```js
export const FONT_CATALOG = [
  // Sans-serif (modernas)
  { key: 'inter',        label: 'Inter',           family: "'Inter', system-ui, sans-serif",         category: 'sans' },
  { key: 'poppins',      label: 'Poppins',         family: "'Poppins', system-ui, sans-serif",       category: 'sans' },
  { key: 'dm_sans',      label: 'DM Sans',         family: "'DM Sans', system-ui, sans-serif",       category: 'sans' },
  { key: 'space_grotesk', label: 'Space Grotesk',  family: "'Space Grotesk', system-ui, sans-serif", category: 'sans' },
  { key: 'outfit',       label: 'Outfit',          family: "'Outfit', system-ui, sans-serif",        category: 'sans' },

  // Serif (editoriales)
  { key: 'playfair',     label: 'Playfair Display', family: "'Playfair Display', Georgia, serif",    category: 'serif' },
  { key: 'lora',         label: 'Lora',            family: "'Lora', Georgia, serif",                 category: 'serif' },
  { key: 'merriweather', label: 'Merriweather',    family: "'Merriweather', Georgia, serif",         category: 'serif' },

  // Monospace (tech/industrial)
  { key: 'jetbrains',    label: 'JetBrains Mono',  family: "'JetBrains Mono', monospace",            category: 'mono' },
  { key: 'fira_code',    label: 'Fira Code',       family: "'Fira Code', monospace",                 category: 'mono' },
];
```

Todas son Google Fonts gratuitas — se cargan via `<link>` en el `<head>`.

### 29.3 Carga dinamica de Google Fonts

```jsx
// En el componente root del storefront:
function FontLoader({ fontKey }) {
  useEffect(() => {
    if (!fontKey || fontKey === 'inter') return; // Inter ya esta cargada por defecto
    const font = FONT_CATALOG.find(f => f.key === fontKey);
    if (!font) return;

    const linkId = `nv-gfont-${fontKey}`;
    if (document.getElementById(linkId)) return;

    const link = document.createElement('link');
    link.id = linkId;
    link.rel = 'stylesheet';
    link.href = `https://fonts.googleapis.com/css2?family=${font.label.replace(/ /g, '+')}:wght@300;400;500;600;700&display=swap`;
    document.head.appendChild(link);
  }, [fontKey]);

  return null;
}
```

### 29.4 UI en DesignStudio

```
┌─────────────────────────────────────────────────┐
│  Tipografia                                      │
│                                                   │
│  ┌────────────────────────────────────────┐      │
│  │ ▼  Inter (Moderna)                     │      │
│  └────────────────────────────────────────┘      │
│                                                   │
│  Preview:                                         │
│  ┌────────────────────────────────────────┐      │
│  │ Aa Bb Cc Dd 1234                       │      │
│  │ El zorro marron rapido salta sobre...  │      │
│  └────────────────────────────────────────┘      │
│                                                   │
│  Categorias: [Sans] [Serif] [Mono]               │
└─────────────────────────────────────────────────┘
```

### 29.5 Almacenamiento

Se guarda `font_key` en `client_home_settings.theme_config`:

```json
{
  "palette_key": "dark_default",
  "font_key": "space_grotesk",
  "custom_vars": {}
}
```

El `resolveEffectiveTheme()` resuelve `font_key` → `FONT_CATALOG[key].family` → `--nv-font`.

### 29.6 Plan gating

| Plan | Fonts disponibles |
|------|-------------------|
| starter | 3 fonts basicas (Inter, Poppins, Lora) |
| growth | Todas las fonts del catalogo (10) |
| enterprise | Todas + capacidad de subir font custom (futuro) |

**Monetizacion:** No se cobra como addon separado — es un diferenciador de plan que incentiva upgrade de starter → growth.

### 29.7 Compatibilidad con templates legacy (first-fifth)

Los templates first-fifth no usan `var(--nv-font)` explicitamente. Para que la seleccion de font aplique a todos los templates:

**Opcion A (recomendada):** Agregar `font-family: var(--nv-font, inherit)` al `body` o al contenedor root del storefront en `App.jsx` o `StoreLayout`.

**Opcion B:** Actualizar cada HomePage de templates legacy para incluir el style inline (mas invasivo, menos recomendado).

La Opcion A es un cambio de 1 linea que cubre todos los templates sin tocar codigo legacy.

---

## Anexo G: Checklist de generacion de templates — nuevo proceso

### Para agregar template_9 (ejemplo)

```
□ 1. Crear /templates/ninth/config.js
     - Definir defaultSections con variantes existentes
     - Definir defaultTokens (paleta, spacing, font)

□ 2. Crear /templates/ninth/pages/HomePage.jsx
     - Importar SectionRenderer + config
     - Render generico (sin componentes propios)

□ 3. Registrar en templatesMap.ts
     - Agregar lazy import + entry en TEMPLATES

□ 4. Registrar en resolveEffectiveTheme.ts
     - Agregar template_9: 'ninth'

□ 5. DB: nv_templates
     - INSERT INTO nv_templates (key, name, thumbnail_url, is_active)

□ 6. DB: palette_catalog
     - INSERT paletas recomendadas para este template

□ 7. Actualizar manifest.js
     - Agregar metadata del template

□ 8. Testing
     - Visual regression: 3 viewports x 2 modes = 6 screenshots
     - Config validation: verificar que todas las variantes existen
     - Preview en DesignStudio

□ 9. Documentar en ADDING_TEMPLATES_AND_COMPONENTS.md
     - Actualizar seccion "Quick Start" con nuevo proceso
```

**Checklist anterior (14 pasos, 2,300 lineas) → Checklist nuevo (9 pasos, 150 lineas)**

---

## Anexo H: Resumen de tokens CSS — contrato actual vs. propuesto

### Contrato actual (27 tokens en paletteToCssVars)

```
Layout:        --nv-bg, --nv-surface, --nv-card-bg
Typography:    --nv-text, --nv-text-muted
Borders:       --nv-border, --nv-shadow
Primary:       --nv-primary, --nv-primary-hover, --nv-primary-fg
Accent:        --nv-accent, --nv-accent-fg
Links:         --nv-link, --nv-link-hover
Status:        --nv-info, --nv-success, --nv-warning, --nv-error
Focus:         --nv-ring
Inputs:        --nv-input-bg, --nv-input-text, --nv-input-border
Navigation:    --nv-navbar-bg, --nv-footer-bg
Compat:        --nv-muted, --nv-hover, --nv-surface-fg, --nv-bg-fg, --nv-input
Non-color:     --nv-radius, --nv-font
```

### Tokens NUEVOS propuestos (+8)

```
Spacing:       --nv-spacing-xs, --nv-spacing-sm, --nv-spacing-md,
               --nv-spacing-lg, --nv-spacing-xl,
               --nv-spacing-section, --nv-spacing-page, --nv-spacing-page-lg
```

### Contrato propuesto total: 35 tokens

Los 8 tokens nuevos de spacing se agregan en `paletteToCssVars()` con valores por defecto. No rompen ningun template existente porque los templates legacy usan clases Tailwind hardcodeadas que no referencian estos tokens. Solo los componentes unificados nuevos los usarian.

**Migracion gradual:** A medida que se unifican componentes (Tickets T1-T6), se reemplazan clases hardcodeadas por tokens. Los templates legacy mantienen sus clases hasta ser migrados.

---

## §30: Auditoria QA — hallazgos consolidados (2026-03-19)

Resultado de 3 auditorias paralelas: arquitectura del plan, tickets, y seguridad/performance.

### 30.1 Hallazgos CRITICOS (bloquean inicio)

| # | Hallazgo | Ubicacion | Accion requerida |
|---|----------|-----------|------------------|
| C1 | **CSS injection sin sanitizacion whitelist** — Ticket 9 dice "bloquear @import, url() externo" pero no define whitelist de properties permitidas. Vectores: `expression()`, `behavior:`, `@keyframes` CPU bombing, data exfiltration via `background: url()` | §17, T9 | Crear `CSS_SANITIZER.ts` en API con allowlist de properties + blocklist de patterns. Agregar como Ticket 0.5 |
| C2 | **XSS via labels configurables** — Ticket 7 pasa labels a componentes sin validacion de entrada. Si el backend no sanitiza, un admin malicioso podria guardar XSS en `clients.config.labels` | §7, T7 | Validador `isSimpleString()` en API: solo alfanumericos, espacios, puntuacion basica, max 200 chars |
| C3 | **Palette hex sin validacion** — `paletteFromVars()` acepta cualquier string como color. Inyeccion: `--nv-primary: ";background:url(https://attacker.com)"` | palettes.ts:28, T0 | Validador `isValidHexColor()` en palettes.ts + API |
| C4 | **Visual baseline incorrecto** — Ticket 0 dice "120 screenshots" pero la matriz real es 336 (8×7×3×2). No define herramienta ni threshold | §9.3, T0 | Corregir a 336 baselines. Herramienta: Playwright. Threshold: 1% pixeles. CI gate obligatorio |
| C5 | **No hay rollback plan** — Si T1 sale mal, no hay procedimiento documentado para revertir el componente unificado y restaurar legacy | T1-T6 | Definir runbook por ticket: restaurar imports legacy + revert sectionComponents + revert sectionCatalog |
| C6 | **Dark mode + variante hardcodeada** — Si una variante tiene `background: #FFF` hardcodeado y el usuario elige dark mode, el resultado es ilegible. Los componentes deben usar SOLO tokens CSS | T1-T6 | Regla obligatoria: prohibir colores literales en componentes unificados. Solo `var(--nv-*)` |
| C7 | **ProductCard sin manejo de 0 o 1000+ productos** — SectionRenderer no limita cantidad. 1000 items en carousel sin virtualizacion = memory leak | T1, T6 | Array vacio → EmptyState. >50 items → virtualizar (react-window o similar) |

### 30.2 Hallazgos ALTOS (resolver pre-implementacion)

| # | Hallazgo | Ubicacion | Accion requerida |
|---|----------|-----------|------------------|
| A1 | **Bundle size sin targets** — Plan menciona code splitting pero sin metricas: ¿cual es el max bundle? ¿LCP target? ¿FCP target? | §25 | Targets: main <150KB gzip, template chunk <80KB, variant <25KB. LCP <2500ms, FCP <1800ms, CLS <0.1. Lighthouse CI |
| A2 | **Font loading → CLS** — Cambiar font dinamicamente (Inter→Poppins) causa layout shift. Sin `font-display: swap` hay FOIT | T15 | `font-display: swap` obligatorio. Precargar font antes de aplicar. `font-size-adjust: 0.5` |
| A3 | **Plan downgrade sin fallback de font/palette** — Cliente enterprise con "Space Grotesk" downgradea a starter → font no disponible. ¿Se reemplaza? ¿Error? | §29, T15 | `resolveEffectiveTheme()` debe validar font_key contra plan. Fallback a Inter si no disponible |
| A4 | **Google Fonts timeout sin fallback** — Si Google Fonts no responde (5s+), la pagina "se cuelga". Sin error handling | T15 | `AbortController` con timeout 5s + fallback a system fonts |
| A5 | **Template change sin accion para incompatibles** — `evaluateTemplateCompatibility()` retorna issues pero no define que hacer. ¿Cancelar? ¿Reemplazar? ¿Dejar elegir? | §20 | Definir: dialog de confirmacion con opciones de reemplazo por seccion |
| A6 | **Contrast ratio sin validacion en backend** — Admin puede elegir palette custom que no cumple WCAG AA. Solo hay warning en console, no bloqueador | T0, T15 | Validacion WCAG AA en API (endpoint de save palette). Si contrast <4.5:1 → warn + sugerir fallback |
| A7 | **Footer branded subespecificado** — Drift/Vanguard/Lumina tienen identidad visual unica. ¿Como se "preserva" en variante unificada? ¿Sub-variantes? ¿Props de marca? | T4 | Definir pre-start: ¿branded es sub-variante o usa theme tokens? Investigar que es unico de cada footer |
| A8 | **T1 ProductCard subestimado** — 5 copias, theme fourth/fifth con sistema propio, 4 variantes × features × viewports = combinatoria grande. 4-5d → 5-7d reales | T1 | Ajustar estimacion. Dividir en sub-tickets: variantes + parts + migration + testing |
| A9 | **SectionRenderer no pasa variant prop** — T1-T6 dependen de que SectionRenderer inyecte `variant` al componente. Actualmente no lo hace | T0 | Agregar al scope de T0: SectionRenderer extrae `finalProps.variant` y lo pasa |
| A10 | **Dependencias backend no ticketeadas** — D3/D4/D5 requieren scripts SQL en API. D6 requiere endpoints. T9 requiere sanitizacion server-side. No hay tickets en @nv/api | D3-D6, T9 | Crear tickets espejo en @nv/api para cada dependencia backend |

### 30.3 Hallazgos MEDIOS (resolver durante implementacion)

| # | Hallazgo | Accion |
|---|----------|--------|
| M1 | **postMessage iframe sin origin validation** — DesignStudio preview usa postMessage. Validar `event.origin` contra whitelist | Agregar validacion en preview listeners |
| M2 | **localStorage sin scope por tenant** — `theme` key es global. Tenant A ve preferencias de tenant B en misma maquina | Scopear: `nv_${slug}_theme` |
| M3 | **Sin Content-Security-Policy** — No hay CSP headers. Permite inline scripts y eval | Agregar CSP en config de deploy |
| M4 | **prefers-reduced-motion no contemplado** — Componentes con animaciones (hover, transitions) sin media query | Agregar `@media (prefers-reduced-motion: reduce)` que desactiva transitions |
| M5 | **Token count confuso** — Anexo H dice 27 actual + 8 nuevos = 35. Pero los 8 nuevos estan en §28, no listados en Anexo H explicitamente | Corregido: Anexo H ya lista los 8 tokens de spacing |
| M6 | **DynamicContactSection como patron existente** — ContactInfo/index.jsx YA es un componente unificado con `layoutVariant` prop. Plan no lo reconoce como REFERENCIA para las otras fases | Documentar como patron canonico en T0 |
| M7 | **SectionRenderer NO filtra por plan** — El codigo tiene comentario: "Plan-tier gating removed from SectionRenderer entirely". Es correcto (gating en DesignStudio upstream), pero plan lo contradice | Actualizar §6 criterios de exito |
| M8 | **Touch targets con spacing compact** — Si density=compact, botones pueden ser <44px (WCAG 2.5.5) | Agregar `--nv-min-touch-target: 2.75rem` con override para pointer:fine |
| M9 | **Concurrencia dos admins** — Si dos admins editan tema al mismo tiempo, last-write-wins sin warning | Bajo riesgo en practica (single admin por tienda). Documentar como limitacion conocida |
| M10 | **Onboarding preview sin auto-save** — Si admin cambia template en wizard y hace reload, ¿se pierden cambios? | Verificar en onboarding flow. Probablemente ya se guarda en nv_onboarding |

### 30.4 Patron existente validado: DynamicContactSection

```
HALLAZGO POSITIVO: Ya existe un componente unificado funcionando en produccion.

Archivo: src/sections/content/ContactInfo/index.jsx (~286 lineas)
Import: sectionComponents.tsx linea 14 como DynamicContactSection
Mappings: 'content.contact.first' a 'content.contact.fifth' (5 templates)
Variantes: layoutVariant prop ("split", "split-reverse", "stacked", "map-only", "contact-only")

Este componente ES el patron que los Tickets 1-6 deben seguir:
- Un solo archivo de componente
- Props para variantes (no archivos separados)
- Import multiple en sectionComponents.tsx (N keys → mismo componente)
- Lógica de variante interna (switch/if basado en prop)
```

**Recomendacion:** Ticket 0 debe documentar DynamicContactSection como "reference implementation" y T1-T6 deben seguir el mismo patron.

### 30.5 Estimacion ajustada post-auditoria

| Grupo | Estimacion original | Estimacion ajustada | Delta |
|-------|--------------------|--------------------|-------|
| **Nuevo: T0.5 Security hardening** | — | 2-3 dias | +2-3 |
| Fixes BD (D3-D7, T13) | 2.7d | 3.2d | +0.5 |
| Setup (T0) | 3-4d | 4-5d | +1 |
| Unificacion (T1-T6) | 17-24d | 21-29d | +4-5 |
| Features (T7-T12) | 14.5-18.5d | 16-21d | +1.5-2.5 |
| Tokens/Fonts/Docs (T14-T16) | 4-6d | 4-6d | 0 |
| **Total** | **38-51d** | **50-67d** | **+12-16** |

**Razones del ajuste:**
- T0.5 (security) es nuevo ticket bloqueante (+2-3d)
- T0 baselines: 336 screenshots requieren mas tiempo que 120 (+1d)
- T1 ProductCard: combinatoria de variantes mayor a lo estimado (+1-2d)
- T4 Footer: branded variante subespecificada (+1d)
- T9 CSS custom: sanitizacion server-side no especificada (+1d)
- Testing y visual regression: subestimado en todos los tickets (+2-3d total)

### 30.6 Nuevo ticket propuesto: T0.5 Security & Performance Hardening

**Tipo:** Infraestructura (BLOQUEANTE)
**Prioridad:** Critica
**Estimacion:** 2-3 dias
**Bloqueado por:** Ninguno
**Bloquea:** T0, T7, T9, T15

**Scope:**
- CSS_SANITIZER.ts en API con allowlist de properties + blocklist de patterns
- Validador `isSimpleString()` para labels en API + frontend
- Validador `isValidHexColor()` para palette colors en palettes.ts + API
- Lighthouse CI budgets: main <150KB, template <80KB, variant <25KB
- Contrast ratio WCAG AA validation en backend con fallback
- Content-Security-Policy headers
- Penetration test para CSS injection

### 30.7 Tests faltantes propuestos (por componente)

**ProductCard — 14 tests:**
- Variante fallback para templates ausentes
- 0 productos → EmptyState
- 1000+ productos → virtualizacion
- Dark mode respeta CSS vars
- Skeleton para cada variante
- Precio con descuento
- Sin imagen → placeholder
- a11y: aria-labels en botones
- Mobile 375px sin overflow
- Integracion con ProductCarousel

**FAQSection — 6 tests:**
- Accordion toggle open/close
- Solo 1 FAQ abierto a la vez
- Variante accordion vs cards vs masonry
- Fallback si faqs=[]
- a11y: role="button" y tabindex

**Footer — 4 tests:**
- Branded detecta template
- Newsletter subscribe optimistic
- Social links no 404
- Legal links responsive mobile

**ServicesSection — 4 tests:**
- Grid 3 columns desktop
- Card sin icono
- >12 servicios paginacion
- Hover solo desktop

**ContactSection — 5 tests:**
- WhatsApp link correcto
- Form validacion email
- Form submit API call
- Variantes layout diferentes
- Sin telefono → WhatsApp oculto

**Cross-cutting — 8 tests:**
- CSS sanitization (6 payloads maliciosos)
- Palette fuzzing (hex, rgb, injection, XSS)
- Contrast ratio en todas las paletas
- CLS en cambio de font
- Bundle size regression
- Lighthouse budgets
- prefers-reduced-motion
- Template change 8×8 compatibility matrix

**Total tests propuestos: ~55 tests nuevos**

### 30.8 Checklist pre-implementacion actualizado

```
BLOQUEANTES (resolver ANTES de cualquier ticket):
□ T0.5: CSS sanitizer implementado en API
□ T0.5: Label validator implementado
□ T0.5: Palette color validator implementado
□ T0.5: Lighthouse CI budgets configurados
□ T0.5: Contrast ratio validation en backend
□ D3: Fix template_key naming (script SQL real, no pseudocode)
□ D4: Fix plan pro en palette_catalog
□ D5: Fix locale vacios
□ D6: Custom palette API methods (endpoints existen?)

PRE-FASE 1 (resolver durante T0):
□ DynamicContactSection documentado como reference implementation
□ 336 screenshots baselines capturados
□ SectionRenderer modificado para pasar variant prop
□ Rollback plan documentado por ticket
□ ProductCard props schema definido (variantes, tipos, backward compat)
□ Theme contract final (27 + 8 spacing = 35 tokens)

DURANTE IMPLEMENTACION:
□ postMessage origin validation en preview
□ localStorage scoped por tenant
□ prefers-reduced-motion en CSS variables
□ font-display: swap en Google Fonts
□ CSP headers en deploy
□ Touch targets ≥ 44px en mobile
```

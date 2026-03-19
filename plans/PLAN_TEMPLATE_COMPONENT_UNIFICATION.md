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

### 12.1 BLOQUEANTE: `client_home_settings` vacia en produccion

**Hallazgo:** Las dos tiendas activas (`urbanprint`, `Tienda Test`) no tienen registro
en `client_home_settings`. Cuando no hay row, `resolveEffectiveTheme` (linea 162-172)
hace fallback silencioso:
- Sin dark mode: `templateKey: 'first'`, `paletteKey: 'starter_default'`
- Con dark mode: `templateKey: 'second'` (Modern Dark)

**App.jsx** (linea 149-152) tiene un default adicional a `'fifth'` — es decir, hay
**dos fallbacks distintos** dependiendo de donde se resuelva primero.

**Impacto sobre el plan:**
- **Paso 0 (baselines):** Los screenshots capturarian el estado con defaults,
  no con la configuracion que el usuario eligio. Si el bug se corrige despues,
  las baselines quedan invalidas.
- **Riesgo real:** Las tiendas en produccion pueden estar mostrando template `first`
  cuando el usuario eligio otro template en el Design Studio.

**Resolucion:**
- **Opcion A (recomendada):** Arreglar el bug en el backend ANTES de capturar baselines.
  `HomeSettingsService.save()` debe persistir la seleccion del Design Studio.
  Ticket externo bloqueante.
- **Opcion B:** Capturar baselines del estado actual (defaults) y aceptar que
  representan lo que el usuario realmente ve hoy. Re-capturar post-fix.
- **Decision requerida:** Producto/backend.

### 12.2 IMPORTANTE: `nv_templates` solo tiene 5 registros vs 8 en codigo

**Hallazgo:** Templates `sixth`, `seventh`, `eighth` existen en codigo
(`templatesMap.ts`, `theme/index.ts`, `sectionComponents.tsx`) pero no estan
registrados en la tabla `nv_templates` de BD.

**Verificacion:** El frontend NUNCA consulta `nv_templates` directamente.
Los templates se resuelven en memoria via:
- `TEMPLATES` registry en `theme/index.ts` (linea 188-200)
- `templatesMap` con `React.lazy()` para code splitting
- `normalizeTemplateKey()` en `resolveEffectiveTheme.ts` (linea 32-50)

**Impacto sobre el plan:** **Bajo.** Los componentes unificados consumen el
template key ya resuelto. No importa si viene de BD o de codigo. T6/T7/T8
funcionan correctamente como ciudadanos de primera clase en el frontend.

**Resolucion:** Documentar que `nv_templates` es una tabla de metadata
para el admin/Design Studio, no una fuente de verdad para el rendering.
Si el Design Studio necesita listar T6/T7/T8 como opciones, esos registros
deben insertarse en `nv_templates`. Ticket separado, no bloqueante.

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

## 13. Dependencias externas actualizadas

> Revision del grafo de dependencias considerando §12.

### Pre-requisitos bloqueantes

| # | Dependencia | Donde vive | Tipo | Estado |
|---|-------------|-----------|------|--------|
| D1 | Fix `client_home_settings` persistencia | API backend | Bug fix | Pendiente |
| D2 | Insertar T6/T7/T8 en `nv_templates` | API/Admin | Data seed | Pendiente |

### Pre-requisitos recomendados (no bloqueantes)

| # | Dependencia | Donde vive | Tipo | Estado |
|---|-------------|-----------|------|--------|
| D3 | Poblar `account_entitlements` | API backend | Feature | Pendiente |
| D4 | Crear tabla `component_catalog` | API backend | Plan fluffy-jingling-peach | Pendiente |

### Grafo de dependencias actualizado

```
D1 (fix client_home_settings) ──┐
                                 ├──> Ticket 0 (Setup + baselines)
D2 (seed nv_templates T6-T8)  ──┘        │
                                          ├──> Tickets 1-6 (migraciones)
                                          │
D3 (account_entitlements) ─── opcional ───┤
D4 (component_catalog BD) ─── futuro ────┘
```

### Reconciliacion sections/variants en tickets

El Ticket 0 debe incluir:
- [ ] Definir mapping `componentKey` → `variant` (ej: "catalog.grid.first" → "simple")
- [ ] Actualizar `SectionRenderer.tsx` para inyectar `variant` prop
- [ ] Verificar que `sectionCatalog.ts` tiene `planTier` para todas las variantes
- [ ] Documentar que `sectionCatalog` + `component_catalog` son el gating real

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

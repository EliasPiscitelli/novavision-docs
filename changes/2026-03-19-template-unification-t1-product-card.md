# 2026-03-19 — Template Unification: T1 ProductCard Unificado

## Repo: `@nv/web` (branch: `develop`)

## Resumen

Implementación del ticket T1: ProductCard unificado que reemplaza 8 implementaciones separadas (una por template) con un único componente que usa lazy-loaded variants y shared parts.

## Arquitectura

```
src/components/storefront/ProductCard/
├── index.tsx              ← Entry point: normaliza datos + variant router
├── ProductCardSkeleton.tsx ← Suspense fallback
├── parts/
│   ├── index.ts           ← Barrel export
│   ├── StockBadge.tsx     ← Badge "Agotado"
│   ├── PriceBadge.tsx     ← Display de precios con formatCurrency
│   ├── DiscountBadge.tsx  ← Badge de descuento %
│   ├── FavoriteButton.tsx ← Toggle favorito (usa FavoritesProvider)
│   └── CartButton.tsx     ← Agregar al carrito (usa CartProvider)
└── variants/
    ├── Simple.tsx         ← T1, T3: imagen + nombre + precio
    ├── Interactive.tsx    ← T2: + botón carrito
    ├── Full.tsx           ← T4, T5: + favoritos + descuento + carrito
    └── Showcase.tsx       ← T6-T8: editorial, browse-only
```

## Decisiones de diseño

### Variant Router con React.lazy
Cada variante se carga bajo demanda via `React.lazy()`. Un store con template T1 nunca carga el código de T6-T8. El `ProductCardSkeleton` actúa como fallback de Suspense.

### Shared Parts como composición
Cada variante selecciona qué parts usar — como piezas de LEGO:
- Simple: StockBadge + PriceBadge
- Interactive: StockBadge + PriceBadge + CartButton
- Full: StockBadge + PriceBadge + DiscountBadge + FavoriteButton + CartButton
- Showcase: PriceBadge + DiscountBadge

### normalizeProduct como capa de abstracción
Todos los productos pasan por `normalizeProduct()` antes de llegar a variantes, resolviendo las inconsistencias de campo entre templates.

### Inline SVGs vs react-icons
Las shared parts usan SVGs inline mínimos para íconos (corazón, carrito, spinner). Esto evita agregar `react-icons` como dependencia, manteniendo los chunks de variantes ligeros.

### CSS tokens exclusivamente
Cero colores hardcodeados. Todo usa `var(--nv-*)` del theme-contract. Los estilos son inline `CSSProperties` — no styled-components ni Tailwind — para máxima portabilidad y tree-shaking.

## Cambios

### ProductCard Entry Point
- Nuevo: `src/components/storefront/ProductCard/index.tsx` — recibe `product` + `variant`, normaliza datos, despacha a variante lazy-loaded
- Exports: `ProductCard`, `ProductCardProps`, `ProductCardVariantProps`, `NormalizedProduct`

### Shared Parts (5 componentes)
- `StockBadge` — badge absoluto top-left, `--nv-error` bg, label configurable
- `PriceBadge` — precio actual + strikethrough original, usa `formatCurrency()` canónico
- `DiscountBadge` — badge absoluto top-right, porcentaje redondeado, `colorVar` configurable
- `FavoriteButton` — consume `useFavorites()` internamente, optimistic updates, SVG heart
- `CartButton` — consume `useCart()` internamente, estado `isAdding`, labels dinámicos

### 4 Variantes
- `Simple` (T1/T3): tarjeta limpia con Link, imagen, nombre, descripción, precio
- `Interactive` (T2): agrega CartButton debajo de la info
- `Full` (T4/T5): FavoriteButton overlay + DiscountBadge + CartButton + multi-line text clamp
- `Showcase` (T6-T8): aspecto 3:4, tipografía editorial, sin cart ni favoritos

### Skeleton
- `ProductCardSkeleton` — shimmer placeholder con aspect ratio adaptado por variante

### Tests
- `src/__tests__/product-card-parts.test.ts` — 26 tests cubriendo pipeline de datos, derivación de stock/precio/descuento/imagen, escenarios compuestos por formato de template

## Validación

- `typecheck`: 0 errores
- `build`: exitoso (6.38s)
- `test:unit`: 208/208 tests pasan (26 nuevos)
- `ensure-no-mocks`: OK
- `check:bundle`: todos los chunks dentro del budget (ProductCard aún no wired → no afecta chunks)

## Archivos nuevos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/components/storefront/ProductCard/index.tsx` | 97 | Entry point + variant router |
| `src/components/storefront/ProductCard/ProductCardSkeleton.tsx` | 66 | Skeleton de carga |
| `src/components/storefront/ProductCard/parts/StockBadge.tsx` | 40 | Badge de stock |
| `src/components/storefront/ProductCard/parts/PriceBadge.tsx` | 57 | Display de precios |
| `src/components/storefront/ProductCard/parts/DiscountBadge.tsx` | 44 | Badge de descuento |
| `src/components/storefront/ProductCard/parts/FavoriteButton.tsx` | 95 | Botón favorito |
| `src/components/storefront/ProductCard/parts/CartButton.tsx` | 115 | Botón carrito |
| `src/components/storefront/ProductCard/parts/index.ts` | 5 | Barrel export |
| `src/components/storefront/ProductCard/variants/Simple.tsx` | 84 | Variante simple |
| `src/components/storefront/ProductCard/variants/Interactive.tsx` | 72 | Variante interactive |
| `src/components/storefront/ProductCard/variants/Full.tsx` | 103 | Variante full |
| `src/components/storefront/ProductCard/variants/Showcase.tsx` | 73 | Variante showcase |
| `src/__tests__/product-card-parts.test.ts` | 196 | Tests unitarios |

## Próximos pasos

- Wiring: conectar ProductCard unificado al `sectionCatalog` + `sectionComponents` para reemplazar las importaciones legacy
- T2: FAQSection unificado
- Visual regression: capturar baselines post-wiring

# T6: ProductCarousel unificado — 3 variantes lazy-loaded

**Fecha:** 2026-03-19
**Componente:** `src/components/storefront/ProductCarousel/`
**Tipo:** Template Unification (T6)

## Resumen

Reemplaza 6 carouseles de productos (T1, T3, T5 + ServicesGrid) y 3 showcases (T6, T7, T8) con
un componente unificado que usa 3 variantes lazy-loaded (`basic`, `featured`, `hero`) y compone
el ProductCard unificado (T1) para renderizar cada producto.

## Archivos creados

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `CarouselArrows.tsx` | ~45 | Botones prev/next compartidos con SVG inline |
| `ProductCarouselSkeleton.tsx` | ~50 | Skeleton de carga para Suspense fallback |
| `index.tsx` | ~85 | Entry point: filterValidProducts, variant router |
| `variants/Basic.tsx` | ~90 | T1-T5 bestsellers: scroll horizontal + snap |
| `variants/Featured.tsx` | ~95 | T1-T5 featured: scroll con cards más grandes |
| `variants/Hero.tsx` | ~80 | T6-T8 showcase: grid CSS con máx 8 productos |
| `__tests__/product-carousel.test.ts` | ~200 | 19 tests unitarios |

## Arquitectura

Primer componente unificado que compone otro: ProductCarousel importa y renderiza
ProductCard (T1). Lazy-loading anidado funciona correctamente con Vite.

**Flujo de carga:**
```
SectionRenderer → ProductCarousel (lazy) → Variant (lazy) → ProductCard (import directo)
                                                            → ProductCard variant (lazy)
```

## Navegación

Cada producto se envuelve en `<Link to="/product/{slug}">` de react-router-dom.
Prioriza `slug` sobre `id` para URLs amigables.

## Eliminación de dependencias

| Antes | Después |
|-------|---------|
| `react-slick` + `slick-carousel` (T1, T3) | CSS scroll-snap nativo |
| `react-icons` (IoIosArrow*, FaChevron*) | Inline SVG chevrons |
| `framer-motion` (T5, T6, T7, T8) | CSS transitions |

## Variantes ← Templates

| Variante | Templates/Secciones | Layout |
|----------|---------------------|--------|
| `basic` | T1-T5 bestsellers, T4 grid | Scroll horizontal con snap, cards simples |
| `featured` | T1-T5 featured | Scroll horizontal, cards interactivas |
| `hero` | T6, T7, T8 showcase | Grid CSS responsivo, máx 8 + CTA "Ver todo" |

## Validación

- typecheck: 0 errores (primera pasada)
- tests: 344/344 (19 nuevos)
- build: 6.62s
- ensure-no-mocks: OK
- bundle: todos los chunks dentro del budget

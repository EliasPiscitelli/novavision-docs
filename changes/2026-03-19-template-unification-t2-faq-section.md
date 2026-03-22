# 2026-03-19 — Template Unification: T2 FAQSection Unificado

## Repo: `@nv/web` (branch: `develop`)

## Resumen

Implementación del ticket T2: FAQSection unificado que reemplaza 8 implementaciones separadas (+ 1 legacy FaqAccordion) con un único componente que usa lazy-loaded variants.

## Arquitectura

```
src/components/storefront/FAQSection/
├── index.tsx              ← Entry point: normaliza datos + variant router + accordion state
├── FAQItem.tsx            ← Item accordion compartido (a11y: button + aria-expanded/controls)
├── EmptyState.tsx         ← Fallback cuando faqs=[]
├── FAQSectionSkeleton.tsx ← Skeleton de carga
└── variants/
    ├── Accordion.tsx      ← T1-T5: classic vertical accordion
    ├── Cards.tsx          ← T6-T7: items como tarjetas individuales
    └── Masonry.tsx        ← T8: two-column editorial + sidebar
```

## Decisiones de diseño

### Prop name unification
Los 8 templates usan 3 nombres distintos para los datos: `faqs` (T1/T3/T4/T6/T7/T8), `faqsList` (T2), `items` (T5). El componente acepta los 3 y resuelve con fallback: `faqs || faqsList || items`.

### Sorting robusto
Multi-criteria: `number` → `position` → `order` → Infinity. Cubre T7 Vanguard que usa `position/order` en vez de `number`.

### Accordion state centralizado
El toggle y `openId` viven en `index.tsx`, no en cada variante. Las variantes son puramente visuales — reciben `items`, `openId`, `onToggle` como props.

### A11y como estándar
`FAQItem` sigue el patrón de T4 (único template con ARIA completo): `<button>` nativo + `aria-expanded` + `aria-controls` + `role="region"` + `aria-labelledby`. Los 7 templates restantes tenían gaps de accesibilidad.

### Animación CSS pura
En vez de `framer-motion` (que varía entre templates), se usa CSS `transition: height 300ms` con medición de `scrollHeight`. Esto elimina la dependencia de `vendor-motion` (47KB gzip) para las variantes FAQ.

## Problemas encontrados (del análisis)

| Issue | Descripción | Resolución |
|-------|------------|------------|
| Prop fragmentation | `faqs` vs `faqsList` vs `items` | Acepta los 3 |
| No a11y en T1-T3 | `<div>` como trigger, sin ARIA | `<button>` + full ARIA |
| Crash en T8 | `[...faqs].sort()` sin guard para `undefined` | Guard con filter + fallback |
| Crash en T3 | `theme.faqs.background` sin optional chaining | Solo CSS tokens |
| Empty state inconsistente | 4 patterns distintos (demo/null/empty/crash) | EmptyState component |
| 15+ colores hardcodeados | `rgba()`, `#hex`, gradients | Solo `var(--nv-*)` |

## Archivos nuevos

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `src/components/storefront/FAQSection/index.tsx` | 135 | Entry point + variant router |
| `src/components/storefront/FAQSection/FAQItem.tsx` | 120 | Shared accordion item |
| `src/components/storefront/FAQSection/EmptyState.tsx` | 42 | Empty state fallback |
| `src/components/storefront/FAQSection/FAQSectionSkeleton.tsx` | 55 | Skeleton de carga |
| `src/components/storefront/FAQSection/variants/Accordion.tsx` | 70 | Variante accordion |
| `src/components/storefront/FAQSection/variants/Cards.tsx` | 85 | Variante cards |
| `src/components/storefront/FAQSection/variants/Masonry.tsx` | 110 | Variante masonry |
| `src/__tests__/faq-section.test.ts` | 195 | 21 tests unitarios |

## Validación

- `typecheck`: 0 errores
- `build`: exitoso (6.65s)
- `test:unit`: 119/119 tests de unificación pasan (21 nuevos)
- `ensure-no-mocks`: OK
- `check:bundle`: todos los chunks dentro del budget

## Próximos pasos

- T3: ContactSection unificado
- T4: Footer unificado

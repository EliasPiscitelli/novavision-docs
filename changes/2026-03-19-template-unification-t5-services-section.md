# T5: ServicesSection unificado — 3 variantes lazy-loaded

**Fecha:** 2026-03-19
**Componente:** `src/components/storefront/ServicesSection/`
**Tipo:** Template Unification (T5)

## Resumen

Reemplaza 8 implementaciones de servicios (T1-T8 + ServicesGrid) con un componente unificado
que usa 3 variantes lazy-loaded (`grid`, `cards`, `list`), shared parts con 12 íconos SVG inline,
y resolución de imágenes compatible con todos los formatos de datos existentes.

## Archivos creados

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `ServiceCard.tsx` | ~200 | Shared parts: ServiceIcon, ServiceImage, resolveIconKey, resolveServiceImage, normalizeServices, 12 inline SVGs |
| `ServicesSectionSkeleton.tsx` | ~55 | Skeleton de carga para Suspense fallback |
| `index.tsx` | ~75 | Entry point: normalización de props, variant router |
| `variants/Grid.tsx` | ~75 | T1, T3, T8: Grid CSS responsivo, cards limpias |
| `variants/Cards.tsx` | ~85 | T4, T5, T6, T7: Cards con surface bg, border, shadow |
| `variants/List.tsx` | ~85 | T2: Layout horizontal compacto con dividers |
| `__tests__/services-section.test.ts` | ~250 | 35 tests unitarios |

## Resolución de imágenes

Replica la lógica de `serviceCardMedia.utils.js` con soporte para:
- String directo: `image: "photo.jpg"`
- Alias: `imageUrl`, `image_url`
- Objeto anidado: `image: { url: "...", src: "..." }`
- Array de candidatos: `image: ["first.jpg", "second.jpg"]`
- Recursivo: `image: [{ url: "variant.jpg", width: 200 }]`

## Sistema de íconos

12 íconos Feather-style inline (SVG 24×24, stroke-based):
`truck`, `shield`, `refresh`, `headphones`, `creditcard`, `package`,
`star`, `zap`, `check`, `heart`, `message`, `tag`

Con fallback cycling: cuando no hay imagen ni ícono explícito,
los íconos rotan por índice en un ciclo de 8 predeterminados.

## Eliminación de dependencias

| Antes | Después |
|-------|---------|
| `react-icons/fi` (FiTruck, FiShield, etc.) | Inline SVGs |
| `ServiceCardMedia` render-props pattern | Componente ServiceImage directo |
| `framer-motion` (T1, T3, T4, T5) | CSS transitions |
| `styled-components` (T1-T5) | CSS-in-JS con tokens |

## Variantes ← Templates

| Variante | Templates | Layout |
|----------|-----------|--------|
| `grid` | T1, T3, T8 | Grid CSS responsivo, cards centradas |
| `cards` | T4, T5, T6, T7 | Cards con surface, border, hover |
| `list` | T2 | Filas horizontales con dividers |

## Validación

- typecheck: 0 errores (primera pasada)
- tests: 325/325 (35 nuevos)
- build: 6.54s
- ensure-no-mocks: OK
- bundle: todos los chunks dentro del budget

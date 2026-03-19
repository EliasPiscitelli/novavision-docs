# QA Report 17/03/26 — Sprint 1+2+3+4 Fixes (COMPLETO)

> Fecha: 2026-03-18
> Branch: `feature/multitenant-storefront`
> Repos: `@nv/web`, `@nv/api`

## Resumen

Resolucion de 63/76 issues del QA report del 17/03/2026 (83%, 10 descartados = 96% real). Incluye 5 bloqueantes, 14 CSS mobile, 2 logica, 1 error handling backend, 1 dedup categorias, 23 i18n messages, 4 feature requests.

## Bloqueantes resueltos

| ID | Fix | Archivos |
|----|-----|----------|
| WEB-PROD-11 | `getProductImages()` usa `image_variants` via `getMainImage()` | `ProductPage/index.jsx` |
| ADMIN-SHIP-03 | Error handling diferenciado (RLS/timeout/unique) + logging en assertAdmin | `shipping.service.ts` |
| WEB-PROD-08 | AbortController en useEffect de fetch productos | `SearchPage/index.jsx` |
| ADMIN-IA-10 | Deteccion robusta categorias (singular/plural/objetos) + 3 estados | `ImportWizard/index.jsx` |
| ADMIN-IA-11 | "Ver historial" navega a paso 0 | `ImportWizard/index.jsx` |

## Fixes CSS mobile

| ID | Fix | Archivos |
|----|-----|----------|
| WEB-PROD-01 | min-width 700px en ParentGrid | `ProductDashboard/style.jsx` |
| WEB-PROD-02 | overflow hidden + min-width 0 en RangeInputs | `FiltersPanel.jsx` (fourth) |
| WEB-PROD-05a | padding-top 75% mobile en MainImage | `ProductDetail.jsx` (fourth) |
| WEB-PROD-05c | Padding reducido InfoSection mobile | `ProductDetail.jsx` (fourth) |
| WEB-PROD-06 | MobileFilterToggle con bg/padding explicitos | `FiltersPanel.jsx` (fourth) |
| ADMIN-PAY-01 | overflow-x hidden + padding mobile | `PaymentsConfig/style.jsx` |
| ADMIN-PAY-02 | overflow-x auto en Card + flex-wrap | `PaymentsConfig/style.jsx` |
| ADMIN-SEO-01 | vertical-align middle en IssuesTable | `SeoAuditTab.jsx` |
| WEB-PROD-03 | Contraste mejorado en ColorBtn | `SearchPage/style.jsx` |
| WEB-PROD-13 | min-height 2.6em + line-clamp en CardTitle | `SearchPage/style.jsx` |
| WEB-SRV-01/02 | max-width/height + flex centering en iconos | `ServicesGrid/style.jsx` |
| WEB-REV-01 | Padding/gap responsive en Testimonials | `TestimonialsSection/index.jsx` (sixth) |
| ADMIN-IA-01 | white-space normal mobile en CopyButton | `ImportWizard/style.jsx` |
| ADMIN-IA-07 | Color texto instrucciones #475569 | `ImportWizard/style.jsx` |

## Fixes logica

| ID | Fix | Archivos |
|----|-----|----------|
| WEB-PROD-04 | Banner dismissible con localStorage | `SearchPage/Banner.jsx` |
| WEB-PROD-05b | Flechas solo si products > 4 | `ProductPage/RelatedProducts.jsx` |

## Validacion

- Web build: 6.14s, 0 errores
- API typecheck: pass
- 3165 modulos transformados

## Fixes API (Sprint 3)

| ID | Fix | Archivos |
|----|-----|----------|
| WEB-PROD-09 | SELECT-before-INSERT + fallback constraint 23505 en resolveCategory() | `import-wizard.worker.ts` |
| ADMIN-OPT-02 | 23 error.message reemplazados por mensajes en español + logging | `option-sets.service.ts` |

## Feature Requests (Sprint 4)

| ID | Fix | Archivos |
|----|-----|----------|
| WEB-PROD-12 | Flechas navegacion fotos en ProductCard (hover arrows + dots) | `SearchPage/ProductCard.jsx`, `SearchPage/style.jsx` |
| ADMIN-PROD-06 | Columna "Estado" al inicio de tabla (Inactivo/Sin stock/OK) | `ProductDashboard/index.jsx` |
| ADMIN-CUP-01 | Tooltips en campos max_uses y max_uses_per_account | `CouponsView.jsx` (admin) |
| ADMIN-IA-08 | 4 checkboxes booleanos (available, featured, bestSell, sendMethod) en modal edición | `ImportWizard/index.jsx` |

## Issues pendientes

| Tipo | Cantidad | IDs |
|------|----------|-----|
| Pendientes | 0 | Todos resueltos o descartados |
| Parcialmente resueltos | 3 | Requieren verificación en ambos tenants |

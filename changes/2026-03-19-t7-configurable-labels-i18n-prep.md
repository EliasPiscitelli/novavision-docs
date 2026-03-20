# T7 — Configurable Labels / i18n Prep

**Fecha:** 2026-03-19
**Tipo:** Refactor / i18n prep
**Impacto:** Web — storefront components (13 archivos)
**Commits:** `7b7d07d` (develop), `d44cff0` (multitenant-storefront), `5ef9b93` (onboarding-preview-stable)

## Resumen

Elimina ~30 strings españoles hardcodeados de los componentes unificados del storefront. Introduce un sistema de labels configurable con cascade de resolución preparado para i18n (T8: pt-BR).

## Archivo nuevo

| Archivo | Propósito |
|---------|-----------|
| `src/config/localeDefaults.ts` | `StorefrontLabels` interface (32 keys) + defaults es-AR + `getLabels()` / `mergeLabels()` |

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `SectionRenderer.tsx` | Inyecta labels via `mergeLabels(tenant?.locale, rawSectionProps.labels)` |
| `Footer/FooterParts.tsx` | `getDefaultNavLinks(labels)`, `getLegalLinks(labels)`, FooterLogo/Copyright/LegalLinks aceptan labels |
| `Footer/index.tsx` | `labels` en FooterProps + FooterVariantProps, storeName desde labels |
| `Footer/variants/Stacked.tsx` | Headings "Explorar", "Información", "Contacto" configurables |
| `Footer/variants/Columns.tsx` | Headings "Navegación", "Contacto", "Seguinos" configurables |
| `Footer/variants/Branded.tsx` | "Navegación", "Catálogo", "Ver todo" configurables |
| `ProductCarousel/index.tsx` | `labels` en props, pasado a variants |
| `ProductCarousel/variants/Hero.tsx` | "Ver todo" → `labels?.viewAll` |
| `ProductCard/parts/CartButton.tsx` | labels cascade para addToCart, outOfStock, adding |
| `ProductCard/parts/FavoriteButton.tsx` | labels cascade para aria-labels favoritos |
| `ProductCard/parts/StockBadge.tsx` | labels cascade para badge "Agotado" |
| `FAQSection/EmptyState.tsx` | labels cascade para título/descripción vacía |

## Patrón de cascade

```
section.props.labels (override por tenant) → locale defaults (es-AR) → fallback hardcodeado
```

SectionRenderer resuelve labels una sola vez y las propaga a todos los componentes hijos.

## Labels definidas (32 keys)

- **Product Card:** addToCart, outOfStock, outOfStockBadge, adding, addToFavorites, removeFromFavorites
- **Navigation:** navHome, navProducts, navServices, navFaq, navContact
- **Footer:** footerExplore, footerNavigation, footerInformation, footerContact, footerFollowUs, footerCatalog, footerCatalogDescription, termsAndConditions, privacyPolicy, withdrawal, allRightsReserved, defaultStoreName
- **Sections:** viewAll
- **FAQ:** faqEmptyTitle, faqEmptyDescription
- **Contact:** contactAddress, contactPhone, contactEmail, contactWhatsApp, whatsAppMessage
- **Skeleton:** loadingProduct, loadingContact, loadingFooter

## Notas

- Los skeleton components mantienen aria-labels hardcodeados (son estados de carga efímeros fuera del flujo de props)
- `DEFAULT_NAV_LINKS` y `LEGAL_LINKS` constantes marcadas `@deprecated` — usar `getDefaultNavLinks(labels)` y `getLegalLinks(labels)`
- T8 agregará `pt-BR` como segundo locale en el registry

## Validación

- TypeScript: 0 errores
- Build: exitoso (6.61s)
- Tests: 341/341 pass
- Pre-push: pasó en las 3 ramas

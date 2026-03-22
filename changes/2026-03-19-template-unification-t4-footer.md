# T4: Footer unificado — 3 variantes lazy-loaded

**Fecha:** 2026-03-19
**Componente:** `src/components/storefront/Footer/`
**Tipo:** Template Unification (T4)

## Resumen

Reemplaza 8 implementaciones de footer (T1-T8 + ClassicFooter + ElegantFooter) con un componente unificado
que usa 3 variantes lazy-loaded (`columns`, `stacked`, `branded`), shared parts reutilizables y cero
dependencias externas de íconos.

## Archivos creados

| Archivo | Líneas | Propósito |
|---------|--------|-----------|
| `Footer/FooterParts.tsx` | ~200 | Sub-componentes compartidos: Logo, NavList, SocialIcons, LegalLinks, Copyright, PoweredBy + normalizeFooterContact + buildWhatsAppUrl |
| `Footer/FooterSkeleton.tsx` | ~45 | Skeleton de carga para Suspense fallback |
| `Footer/index.tsx` | ~115 | Entry point: normalización de props (logo, links, contact, social), variant router |
| `Footer/variants/Columns.tsx` | ~155 | T1-T3: 4 columnas (Brand, Nav, Contact/Banner, Social) |
| `Footer/variants/Stacked.tsx` | ~120 | T4-T5: 4 columnas con links divididos en 2 columnas |
| `Footer/variants/Branded.tsx` | ~145 | T6-T8: gradiente accent, CTA "Ver todo", descripción de marca |
| `__tests__/footer.test.ts` | ~250 | 27 tests unitarios |

## Normalización de datos

- **Logo:** `showLogo` (T1-T5) vs `show_logo` (T6-T8) → `visible` booleano
- **Contact:** Array `{titleinfo, description}` + Object `{address, phone, email}` → `ContactItem[]`
- **Links:** `{label, url}` → `{label, to}` (internal) / `{label, href}` (external)
- **Social:** `social` vs `socialLinks` → unificado en entry point
- **WhatsApp:** Siempre sanitiza con `replace(/\D/g, '')` (T6/T8 no lo hacían)

## Eliminación de dependencias

| Antes | Después |
|-------|---------|
| `react-icons/fa` (T1, ClassicFooter) | Inline SVGs |
| `react-icons/fi` (T6 FooterDrift) | Inline SVGs |
| `lucide-react` (T4, T5) | Inline SVGs |
| `framer-motion` (T8 FooterLumina) | CSS transitions |

## Variantes ← Templates

| Variante | Templates | Layout |
|----------|-----------|--------|
| `columns` | T1, T2, T3 | Grid 4-col + banner promo opcional |
| `stacked` | T4, T5 | Grid 4-col + links split en 2 columnas |
| `branded` | T6, T7, T8 | Grid auto-fit + CTA catálogo + gradiente accent |

## Validación

- typecheck: 0 errores
- tests: 290/290 (27 nuevos)
- build: 6.74s
- ensure-no-mocks: OK
- bundle: todos los chunks dentro del budget

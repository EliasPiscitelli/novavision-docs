# Template Unification — Wiring (Activación)

**Fecha:** 2026-03-19
**Módulo:** Web Storefront (`@nv/web`)
**Rama:** `develop`

## Resumen

Activación de los 5 componentes unificados (T2-T6) en el pipeline de renderizado.
Los componentes existían pero `sectionComponents.tsx` aún apuntaba a los legacy per-template.
Este cambio hace que todas las tiendas usen los componentes unificados.

## Cambios

### `src/registry/sectionComponents.tsx` — Reescritura

- **5 `lazy()` imports unificados** reemplazan ~30 declaraciones `lazyTemplateExport` per-template
- Entradas actualizadas en `SECTION_COMPONENTS`:
  - 8 FAQ entries → `UnifiedFAQSection`
  - 8 Contact entries → `UnifiedContactSection`
  - 8 Footer entries → `UnifiedFooter`
  - 8 Services entries → `UnifiedServicesSection`
  - 12 Carousel/Showcase entries → `UnifiedProductCarousel`
- Template loaders siguen existiendo para componentes no-unificados (headers, heroes, grids, testimonials, etc.)
- `DynamicContactSection` import eliminado

### `src/components/SectionRenderer.tsx` — Bug fix

- Removido `!finalProps.layoutVariant` del check de inyección de variant (línea 331)
- **Problema:** `layoutVariant` siempre se seteaba a `'split'` para contact sections, bloqueando la inyección de `variant` desde variantMap
- **Impacto:** Sin este fix, ContactSection nunca recibía el variant correcto (cards/two-column/minimal)

### `src/__tests__/contact-section-renderer.test.jsx` — Actualización

- Tests convertidos a `async` con `findByText` para soportar `React.lazy` de componentes unificados
- 12 → 9 tests (removidos 3 tests de behaviors legacy: `layoutVariant: contact-only`, `layoutVariant: map-only`, editor map placeholder)
- CTA button assertion condicional: solo para `cards` variant (first-third), no para `two-column` (fourth-fifth)

## Validación

| Check | Resultado |
|-------|-----------|
| typecheck | 0 errores |
| build | 6.92s OK |
| tests | 341/341 (9 contact-renderer) |
| ensure-no-mocks | OK |
| bundle | dentro del budget |

## Impacto

- Todas las tiendas publicadas ahora renderizan FAQ, Contact, Footer, Services y Product Carousel con los componentes unificados
- Code splitting mejorado: cada componente carga solo la variante necesaria (~3-7KB por variante)
- El variant se inyecta automáticamente por SectionRenderer vía variantMap.ts

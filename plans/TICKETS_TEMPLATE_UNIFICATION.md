# Tickets: Unificacion de Componentes de Templates

> Generado desde `PLAN_TEMPLATE_COMPONENT_UNIFICATION.md` (2026-03-18)
> Actualizado con contradicciones arquitectonicas verificadas (§12).
> Cada ticket mapea 1:1 a una fase del plan.
> Dependencias son estrictas — no iniciar un ticket si su bloqueante no esta DONE.

---

## Dependencias externas (pre-requisitos)

Estos tickets viven fuera de `@nv/web` y bloquean el inicio.

### Ticket D1: Fix persistencia de `client_home_settings` (BLOQUEANTE)
**Repo:** `@nv/api`
**Tipo:** Bug fix
**Prioridad:** Critica

**Problema:** Las tiendas activas no tienen registro en `client_home_settings`.
El Design Studio permite elegir template/palette pero no se persiste.
`resolveEffectiveTheme` hace fallback a `first`/`starter_default`.

**Criterio:** Despues de guardar en Design Studio, `client_home_settings` tiene
row con `template_key`, `palette_key` y `theme_config` correctos.

### Ticket D2: Seed T6/T7/T8 en `nv_templates` (RECOMENDADO)
**Repo:** `@nv/api`
**Tipo:** Data seed
**Prioridad:** Media

**Problema:** `nv_templates` solo tiene 5 registros. T6/T7/T8 funcionan en
frontend pero no aparecen como opciones en el Design Studio.

**Criterio:** `nv_templates` tiene 8 registros con metadata completa.

---

## Ticket 0: Setup — Baselines, theme contract, reconciliacion sections/variants
**Tipo:** Infraestructura
**Prioridad:** Critica (bloqueante de TODOS los demas)
**Estimacion:** 3-4 dias (ajustado por reconciliacion de paradigmas)
**Bloqueado por:** Ticket D1
**Bloquea:** Tickets 1, 2, 3, 4, 5, 6

### Scope

**Theme contract y tokens (§9.1):**
- [ ] Crear `src/components/storefront/theme-contract.ts` con tokens CSS obligatorios
- [ ] Incluir regla: variantes se importan con `React.lazy()`, no estaticamente (§12.8)

**Reconciliacion sections/variants (§12.3 — CRITICO):**
- [ ] Definir mapping completo `componentKey` → `variant` (ver §15.1 — 70 entries)
- [ ] Estudiar patron existente de `DynamicContactSection` como modelo (§14.2)
- [ ] Decidir: variantes como archivos separados vs prop `layoutVariant` (como Contact)
- [ ] Agregar `variant` a `defaultProps` de cada entry en `sectionCatalog` (§15.2)
- [ ] Verificar que `LEGACY_KEY_MAP` (30+ mappings) no se rompe (§15.3)
- [ ] **NO crear `resolveVariant.ts`** — el gating ya esta resuelto por
  `structureCatalog` en DesignStudio + `sectionCatalog.planTier` + `component_catalog` (§14.1)
- [ ] Documentar relacion entre capas:
  - Seleccion: `SectionRenderer` → `sectionCatalog` → `componentKey`
  - Gating: `structureCatalog` (DesignStudio) + `component_catalog` (BD)
  - Implementacion: Componente unificado → `variant` prop → styled-components

**Variantes en section.props (NO en themeConfig — §14.4):**
- [ ] Las variantes van como prop de seccion (`variant: 'cards'`), no en `themeConfig`
- [ ] Seguir patron existente: `layoutVariant` en Contact, `themeVariant` en Hero Video

**Visual regression (§9.3):**
- [ ] Configurar proyecto `visual-regression` en Playwright (`novavision-e2e`)
- [ ] Capturar **120 screenshots baseline** (8 templates × 3 viewports × 5 componentes)
  - **NOTA:** Solo despues de que D1 este resuelto (baselines deben capturar config real)

**Utilidades compartidas:**
- [ ] Crear `src/utils/normalizeProduct.ts` (Paso 1.1)
- [ ] Documentar patron de skeleton companion por variante (§9.5)
- [ ] Crear grep CI hook: colores hardcodeados sin `var()` → fail (§11)

### Criterios de aceptacion

- `theme-contract.ts` exporta `STOREFRONT_TOKENS` + regla de lazy import
- `extractVariant()` mapea todos los `componentKey` existentes a variantes
- `sectionCatalog` tiene `planTier` para cada variante target
- 120 screenshots baseline capturados post-fix de D1
- `normalizeProduct()` pasa tests unitarios con datos de los 8 templates
- CI grep hook integrado
- Documento de reconciliacion sections/variants aprobado

### Notas

Este ticket absorbio la complejidad de §12.3 (sections vs variants).
La decision clave: los componentes unificados son la **capa de implementacion**,
no reemplazan el sistema de sections. `SectionRenderer` sigue siendo el router.
Los `componentKey` en `sectionCatalog` apuntan al componente unificado
y le pasan `variant` como prop.

---

## Ticket 1: ProductCard unificado
**Tipo:** Refactor
**Prioridad:** Alta
**Estimacion:** 4-5 dias
**Bloqueado por:** Ticket 0
**Bloquea:** Ninguno (las fases son independientes post-Ticket 0)

### Scope

- [ ] Crear `src/components/storefront/ProductCard/` con estructura:
  - `index.tsx` — logica unica + router de variantes
  - `variants/simple.tsx` — visual para T1, T3
  - `variants/interactive.tsx` — visual para T2 (hover cart, desktop/mobile)
  - `variants/full.tsx` — visual para T4, T5 (badges, filtros, motion)
  - `variants/showcase.tsx` — visual para T6, T7, T8
  - `parts/` — StockBadge, PriceBadge, FavoriteButton, CartButton, DiscountBadge
  - `ProductCardSkeleton.tsx` — skeleton companion con variantes
- [ ] Corregir colores hardcodeados (9 instancias — ver §11):
  - `#fff` bare en OutOfStockBadge → `var(--nv-primary-fg, #fff)`
  - `#666` bare → `var(--nv-text-muted)`
  - `#e53e3e` ya tiene `var()` wrapper → OK
- [ ] Migrar templates en orden: third → first → generic → second → fifth → fourth
- [ ] Por cada migracion: reemplazar import → pasar props → screenshot diff → eliminar archivos
- [ ] Eliminar ~12 archivos obsoletos (~950 lineas)

### Criterios de aceptacion

- Build pasa (`npx vite build`)
- Screenshots diff < 1% en todos los templates migrados
- 0 colores hardcodeados sin `var()` en `storefront/ProductCard/`
- Skeleton funcional para las 4 variantes
- E2E tests pasan (carrito, checkout, navegacion)

### Riesgo principal

Template fourth usa theme system propio. Verificar que `theme.productCard.*` mapea correctamente a CSS vars via `legacyAdapter`.

---

## Ticket 2: FAQSection unificado
**Tipo:** Refactor
**Prioridad:** Media-Alta
**Estimacion:** 1-2 dias
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/FAQSection/` con estructura:
  - `index.tsx` — logica unica (toggle accordion, animacion)
  - `variants/accordion.tsx` — T1, T3, T4, T5
  - `variants/cards.tsx` — T6, T7
  - `variants/masonry.tsx` — T8
  - `FAQSectionSkeleton.tsx`
- [ ] Corregir colores hardcodeados (4 instancias en T1 — ver §11):
  - `#333` fallback → `var(--nv-text, #1a1a2e)`
  - `rgba(0,0,0,0.08)` shadow → `var(--nv-shadow)`
- [ ] Migrar 6 implementaciones existentes
- [ ] Eliminar 6 archivos obsoletos (~750 lineas)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- 0 colores hardcodeados sin `var()`
- Accordion toggle funcional en todos los templates
- Skeleton companion funcional

---

## Ticket 3: ContactSection unificado
**Tipo:** Refactor
**Prioridad:** Media
**Estimacion:** 2-3 dias
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/ContactSection/` con estructura:
  - `index.tsx` — logica unica (consume `contact_info` + `social_links`)
  - `variants/cards.tsx` — T1, T3
  - `variants/two-column.tsx` — T4, T6, T8
  - `variants/minimal.tsx` — T5, T7
  - `ContactSectionSkeleton.tsx`
- [ ] Auditar colores: T1 y T6 ya estan a 0% hardcodeado — mantener
- [ ] Migrar 6 implementaciones existentes
- [ ] Eliminar 6 archivos (~1,100 lineas)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- WhatsApp link y formulario de contacto funcionales en variantes que los usan
- Skeleton companion funcional

---

## Ticket 4: Footer unificado
**Tipo:** Refactor
**Prioridad:** Media
**Estimacion:** 3-4 dias
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/Footer/` con estructura:
  - `index.tsx` — logica unica (social links, contacto, legales)
  - `variants/columns.tsx` — T1, T3 (multi-columna clasico)
  - `variants/stacked.tsx` — T4, T5 (apilado minimalista)
  - `variants/branded.tsx` — T6 (Drift), T7 (Vanguard), T8 (Lumina)
  - `FooterSkeleton.tsx`
- [ ] Corregir 1 color hardcodeado en T1: `#e0e0e0` → `var(--nv-border, #e5e7eb)`
- [ ] Variante `branded` debe preservar identidad visual de Drift/Vanguard/Lumina
  - Usar sub-variantes o props de marca, no hardcodear estilos por template
- [ ] Migrar 6 implementaciones existentes
- [ ] Eliminar 6 archivos (~1,000 lineas)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Social links, newsletter y links legales funcionales
- Variante `branded` visualmente identica a Drift/Vanguard/Lumina actuales
- Skeleton companion funcional

### Riesgo principal

La variante `branded` concentra la mayor complejidad. Los footers de T6/T7/T8 ya estan en `sections/footer/` — verificar si se puede reusar esa estructura como base.

---

## Ticket 5: ServicesSection unificado
**Tipo:** Refactor
**Prioridad:** Media
**Estimacion:** 2 dias
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/ServicesSection/` con estructura:
  - `index.tsx` — logica unica (grid de cards con icono + titulo + descripcion)
  - `variants/grid.tsx` — T1, T3, T5
  - `variants/cards-hover.tsx` — T4, T6, T8
  - `variants/minimal.tsx` — T7
  - `ServicesSectionSkeleton.tsx`
- [ ] Corregir 1 color hardcodeado en T7: `rgba(255,255,255,0.18)` → `rgba(var(--nv-surface-rgb, 255,255,255), 0.18)`
- [ ] Migrar 7 implementaciones existentes
- [ ] Eliminar 7 archivos (~800 lineas)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Hover effects funcionales en variante `cards-hover`
- Skeleton companion funcional

---

## Ticket 6: ProductCarousel unificado
**Tipo:** Refactor
**Prioridad:** Baja
**Estimacion:** 1 dia
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/ProductCarousel/` con estructura:
  - `index.tsx` — logica unica (scroll horizontal, autoplay, navigation)
  - Sin variantes (90% identico entre T1, T3, T5)
  - `ProductCarouselSkeleton.tsx`
- [ ] 0 colores hardcodeados detectados — mantener limpio
- [ ] Migrar 3 implementaciones existentes
- [ ] Eliminar 3 archivos (~400 lineas)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Autoplay y navegacion por flechas/dots funcionales
- Skeleton companion funcional
- Respeta `ProductCard` unificado (consume variante del template)

### Dependencia blanda

Si Ticket 1 (ProductCard) no esta completo, el carousel puede usar el ProductCard legacy. Pero idealmente se hace despues de Ticket 1.

---

## Resumen ejecutivo

| Ticket | Componente | Dias | Lineas eliminadas | Archivos eliminados |
|--------|-----------|------|-------------------|-------------------|
| D1 | Fix client_home_settings (API) | 1-2 | 0 | 0 |
| D2 | Seed nv_templates T6-T8 (API) | 0.5 | 0 | 0 |
| 0 | Setup (baselines + infra + reconciliacion) | 3-4 | 0 | 0 |
| 1 | ProductCard | 4-5 | ~950 | ~12 |
| 2 | FAQSection | 1-2 | ~750 | ~6 |
| 3 | ContactSection | 2-3 | ~1,100 | ~6 |
| 4 | Footer | 3-4 | ~1,000 | ~6 |
| 5 | ServicesSection | 2 | ~800 | ~7 |
| 6 | ProductCarousel | 1 | ~400 | ~3 |
| **Total** | | **17-24** | **~5,000** | **~40** |

### Grafo de dependencias

```
D1 (fix client_home_settings) ──┐
                                 ├──> Ticket 0 (Setup + reconciliacion)
D2 (seed nv_templates) ─────────┘         │
                                          ├──> Ticket 1 (ProductCard)
                                          ├──> Ticket 2 (FAQSection)
                                          ├──> Ticket 3 (ContactSection)
                                          ├──> Ticket 4 (Footer)
                                          ├──> Ticket 5 (ServicesSection)
                                          └──> Ticket 6 (ProductCarousel)
                                                    └── dep. blanda → Ticket 1

D3 (account_entitlements) ─── opcional, mejora gating cuando se pueble
D4 (component_catalog BD) ─── YA EXISTE y se consume en DesignStudio (corregido §12.4)
```

Tickets 1-6 son paralelizables entre si (post-Ticket 0), pero la recomendacion
es ejecutarlos en orden numerico para acumular confianza progresiva en el patron.

### Decisiones de producto pendientes

Antes de ejecutar, el equipo debe resolver:

1. **¿El Design Studio expone variantes al usuario?**
   - Si → necesita mockup UX + las variantes se definen por valor al usuario,
     no por reduccion de duplicacion. Puede cambiar que variantes existen.
   - No → la unificacion es refactor interno, el usuario sigue viendo
     sections como hoy. El plan se ejecuta tal cual.

2. **¿Se arregla D1 antes o se capturan baselines del estado actual?**
   - Opcion A (recomendada): Fix D1, luego baselines con config real.
   - Opcion B: Baselines ahora, re-capturar post-fix. Mas rapido, mas riesgo.

### Definition of Done (global)

- [ ] 0 archivos duplicados en `templates/*/components/` para componentes migrados
- [ ] Build pasa sin errores ni warnings
- [ ] Screenshot diff < 1% en 120 baselines
- [ ] E2E tests pasan (checkout, carrito, navegacion)
- [ ] `jscpd` muestra reduccion de duplicacion > 40%
- [ ] Grep de colores hardcodeados sin `var()` en `storefront/` = 0
- [ ] `sectionComponents.tsx` apunta a componentes unificados (no a legacy)
- [ ] `SectionRenderer.tsx` inyecta `variant` prop correctamente
- [ ] Dark mode funcional con todos los componentes unificados
- [ ] Changelog actualizado en `novavision-docs/changes/`

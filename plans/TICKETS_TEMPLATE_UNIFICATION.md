# Tickets: Unificacion de Componentes de Templates

> Generado desde `PLAN_TEMPLATE_COMPONENT_UNIFICATION.md` (2026-03-18)
> Actualizado con contradicciones arquitectonicas verificadas (§12).
> Cada ticket mapea 1:1 a una fase del plan.
> Dependencias son estrictas — no iniciar un ticket si su bloqueante no esta DONE.

---

## Dependencias externas (pre-requisitos)

Estos tickets viven fuera de `@nv/web` y bloquean el inicio.

### ~~Ticket D1: Fix persistencia de `client_home_settings`~~ ELIMINADO
**Estado:** Verificado contra BD — la tabla tiene 3 registros con datos reales.
El hallazgo original era incorrecto (§12.1 corregido).

### ~~Ticket D2: Seed T6/T7/T8 en `nv_templates`~~ ELIMINADO
**Estado:** Verificado contra Admin DB — la tabla tiene 8 registros completos
(first-eighth, todas activas con label, min_plan y sort_order).
El hallazgo original era incorrecto (§12.2 corregido).

---

## Ticket 0.5: Security & Performance Hardening (NUEVO — QA audit)
**Tipo:** Infraestructura (BLOQUEANTE)
**Prioridad:** Critica
**Estimacion:** 2-3 dias
**Bloqueado por:** Ninguno
**Bloquea:** T0, T7, T9, T15
**Plan:** §30.6

### Scope

**CSS sanitization (API):**
- [ ] Crear `CSS_SANITIZER.ts` en `@nv/api`
- [ ] Allowlist de properties CSS seguras:
  - Permitidas: `color`, `background-color`, `border-color`, `font-family`, `font-size`, `padding`, `margin`, `text-align`, `text-decoration`, `font-weight`, `letter-spacing`, `line-height`, `border-radius`, `opacity`, `box-shadow`
  - Prohibidas: `@import`, `@keyframes`, `url()` externo, `expression()`, `behavior:`, `position: fixed/absolute`, `z-index`, `display: none`, `calc()` en contextos peligrosos
- [ ] Scopear CSS custom en `.nv-store-{client_id} { ... }`
- [ ] Bloquear selectores globales: `body`, `html`, `*`

**Label validation (API + Frontend):**
- [ ] Validador `isSimpleString()`: solo alfanumericos, espacios, puntuacion basica, max 200 chars
- [ ] Aplicar en endpoint de save de labels/config
- [ ] Frontend: renderizar labels con `textContent`, NUNCA `dangerouslySetInnerHTML`

**Palette color validation:**
- [ ] Validador `isValidHexColor()` en `palettes.ts`
- [ ] Acepta: `#RRGGBB`, `#RGB`, `rgb()`, `hsl()`
- [ ] Rechaza: cualquier otra cosa (injection via color values)
- [ ] Validacion WCAG AA en backend: contrast ratio ≥ 4.5:1 para text vs bg

**Performance budgets:**
- [ ] Crear `lighthouse-budgets.json`: main <150KB gzip, template chunk <80KB, variant <25KB
- [ ] Metricas target: LCP <2500ms, FCP <1800ms, CLS <0.1
- [ ] CI gate: bundle size check en build

**Extras:**
- [ ] Content-Security-Policy headers en config de deploy
- [ ] `font-display: swap` como default en toda carga de fonts

### Criterios de aceptacion

- CSS custom rechaza 100% de payloads maliciosos (test suite de 6+ payloads)
- Labels solo aceptan strings simples
- Palette colors validadas como hex/rgb/hsl
- Lighthouse CI budgets configurados y pasando
- WCAG AA contrast validado en backend con fallback a palette segura
- CSP headers activos
- Build pasa

---

## Ticket 0: Setup — Baselines, theme contract, reconciliacion sections/variants
**Tipo:** Infraestructura
**Prioridad:** Critica (bloqueante de TODOS los demas)
**Estimacion:** 4-5 dias (ajustado post-QA audit: 336 baselines + variant prop en SectionRenderer)
**Bloqueado por:** D3 (fix template_key naming — §19.1), T0.5 (security hardening)
**Bloquea:** Tickets 1, 2, 3, 4, 5, 6, 11, 14, 15

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
- [ ] Capturar **336 screenshots baseline** (8 templates × 3 viewports × 7 componentes × 2 modes light/dark)
  - **NOTA:** Solo despues de que D3 este resuelto (template_key consistente entre BDs)

**Utilidades compartidas:**
- [ ] Crear `src/utils/normalizeProduct.ts` (Paso 1.1)
- [ ] Documentar patron de skeleton companion por variante (§9.5)
- [ ] Crear grep CI hook: colores hardcodeados sin `var()` → fail (§11)

**Hallazgos QA agregados (§30):**
- [ ] **SectionRenderer: inyectar variant prop** — actualmente no pasa `variant` al componente. Agregar extraccion de `finalProps.variant` y pasarlo al componente resuelto
- [ ] **DynamicContactSection como reference implementation** — documentar `ContactInfo/index.jsx` como patron canonico que T1-T6 deben seguir (layoutVariant prop, import multiple, logica de variante interna)
- [ ] **Rollback plan por ticket** — documentar procedimiento: restaurar imports legacy + revert sectionComponents + revert sectionCatalog
- [ ] **Regla: prohibir colores literales** — componentes unificados solo usan `var(--nv-*)`, nunca hex/rgb directos
- [ ] **ProductCard 0/1000+ items** — definir: array vacio → EmptyState, >50 items → virtualizacion

### Criterios de aceptacion

- `theme-contract.ts` exporta `STOREFRONT_TOKENS` + regla de lazy import
- `extractVariant()` mapea todos los `componentKey` existentes a variantes
- `sectionCatalog` tiene `planTier` para cada variante target
- **336** screenshots baseline capturados (no 120) — 8 templates × 3 viewports × 7 componentes × 2 modes
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
**Estimacion:** 5-7 dias (ajustado post-QA: combinatoria de variantes + theme fourth/fifth)
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
- [ ] **Regla QA: 0 colores literales** — solo `var(--nv-*)` en componentes unificados (§30 C6)
- [ ] Migrar templates en orden: third → first → generic → second → fifth → fourth
- [ ] Por cada migracion: reemplazar import → pasar props → screenshot diff → eliminar archivos
- [ ] Eliminar ~12 archivos obsoletos (~950 lineas)

**Manejo de edge cases (§30 C7):**
- [ ] `products = []` → renderizar `EmptyState` con mensaje configurable
- [ ] `products = null/undefined` → fallback a array vacio + warning en console
- [ ] `products.length > 50` → activar virtualizacion (react-window o similar) en contexto de carousel/grid
- [ ] `product.imageUrl = null` → fallback a `/placeholder.png`

**Dark mode safety (§30 C6):**
- [ ] Todas las variantes usan SOLO tokens CSS (`var(--nv-surface)`, `var(--nv-text)`, etc.)
- [ ] Test especifico: renderizar cada variante en dark mode → verificar legibilidad
- [ ] `prefers-reduced-motion: reduce` → desactivar hover animations

**Rollback plan:**
- Si el componente unificado falla en produccion:
  1. Revertir imports en `sectionComponents.tsx` a templates legacy
  2. Revertir entries en `sectionCatalog.ts`
  3. Los archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa (`npx vite build`)
- Screenshots diff < 1% en todos los templates migrados
- 0 colores hardcodeados sin `var()` en `storefront/ProductCard/`
- Skeleton funcional para las 4 variantes
- E2E tests pasan (carrito, checkout, navegacion)
- **Nuevo:** products=[] muestra EmptyState (no crash)
- **Nuevo:** Dark mode legible en las 4 variantes (visual regression)
- **Nuevo:** a11y: aria-labels en botones (agregar carrito, favorito)
- **Nuevo:** Mobile 375px sin overflow horizontal

### Tests requeridos (§30.7)

| Test | Tipo |
|------|------|
| Renderiza variante simple sin crash | unit |
| Aplica variant CSS correctamente | visual |
| Agotado badge renderiza si stock=0 | unit |
| Descuento renderiza % correcto | unit |
| Favorito toggle optimistic | integration |
| Agregar carrito desactiva button | integration |
| Dark mode respeta CSS vars | visual |
| a11y: aria-label en botones | a11y |
| Mobile 375px sin overflow | visual |
| Skeleton renderiza todas variantes | unit |
| Integracion con ProductCarousel | integration |
| Sin imagen: fallback placeholder | unit |
| Migracion: pixel diff < 1% | visual |
| products=[] → EmptyState | unit |

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

**Reglas QA transversales (§30):**
- [ ] 0 colores literales — solo `var(--nv-*)` en componentes unificados
- [ ] `faqs = []` → renderizar estado vacio (no crash)
- [ ] Dark mode legible en todas las variantes
- [ ] a11y: `role="button"` y `tabindex="0"` en items FAQ
- [ ] Rollback: archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- 0 colores hardcodeados sin `var()`
- Accordion toggle funcional en todos los templates
- Skeleton companion funcional
- **Nuevo:** faqs=[] muestra estado vacio
- **Nuevo:** Dark mode legible en las 3 variantes

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

**Reglas QA transversales (§30):**
- [ ] 0 colores literales — solo `var(--nv-*)` en componentes unificados
- [ ] Seguir patron de `DynamicContactSection` (ContactInfo/index.jsx) — reference implementation
- [ ] `contact_info = null` → renderizar sin crash (ocultar seccion o mostrar placeholder)
- [ ] Dark mode legible en todas las variantes
- [ ] Rollback: archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- WhatsApp link y formulario de contacto funcionales en variantes que los usan
- Skeleton companion funcional
- **Nuevo:** Sin telefono → WhatsApp link oculto (no broken link)
- **Nuevo:** Form validacion email client-side antes de submit

---

## Ticket 4: Footer unificado
**Tipo:** Refactor
**Prioridad:** Media
**Estimacion:** 4-5 dias (ajustado post-QA: branded variante subespecificada)
**Bloqueado por:** Ticket 0

### Scope

- [ ] Crear `src/components/storefront/Footer/` con estructura:
  - `index.tsx` — logica unica (social links, contacto, legales)
  - `variants/columns.tsx` — T1, T3 (multi-columna clasico)
  - `variants/stacked.tsx` — T4, T5 (apilado minimalista)
  - `variants/branded.tsx` — T6 (Drift), T7 (Vanguard), T8 (Lumina)
  - `FooterSkeleton.tsx`
- [ ] Corregir 1 color hardcodeado en T1: `#e0e0e0` → `var(--nv-border, #e5e7eb)`
- [ ] **Regla QA: 0 colores literales** — solo `var(--nv-*)` en variantes
- [ ] Variante `branded` debe preservar identidad visual de Drift/Vanguard/Lumina
  - Usar sub-variantes o props de marca, no hardcodear estilos por template
- [ ] Migrar 6 implementaciones existentes
- [ ] Eliminar 6 archivos (~1,000 lineas)

**Definicion de variante `branded` (§30 A7 — resolver ANTES de empezar):**
- [ ] Investigar que es unico en cada footer: FooterDrift, FooterVanguard, FooterLumina
  - ¿Son colores propios? → Deben usar tokens CSS (no hardcodear)
  - ¿Son layouts unicos? → Sub-variantes: `branded-drift`, `branded-vanguard`, `branded-lumina`
  - ¿Son assets unicos (logos, iconos)? → Props configurables
- [ ] Decidir: ¿`branded` es 1 variante con `brandStyle` prop o 3 sub-variantes separadas?
- [ ] Documentar la decision ANTES de implementar

**Rollback plan:**
- Archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Social links, newsletter y links legales funcionales
- Variante `branded` visualmente identica a Drift/Vanguard/Lumina actuales
- Skeleton companion funcional
- **Nuevo:** Dark mode legible en todas las variantes
- **Nuevo:** Links legales responsive en mobile (no overflow)
- **Nuevo:** Newsletter subscribe con feedback optimistic

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

**Reglas QA transversales (§30):**
- [ ] 0 colores literales — solo `var(--nv-*)` en componentes unificados
- [ ] `services = []` → renderizar estado vacio
- [ ] Dark mode legible en todas las variantes
- [ ] `prefers-reduced-motion: reduce` → desactivar hover animations
- [ ] Rollback: archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Hover effects funcionales en variante `cards-hover` (solo desktop, no mobile)
- Skeleton companion funcional
- **Nuevo:** >12 servicios → paginacion o scroll (no layout roto)

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

**Reglas QA transversales (§30):**
- [ ] 0 colores literales — solo `var(--nv-*)` en componentes unificados
- [ ] `products.length === 1` → ocultar flechas/dots de navegacion
- [ ] `products.length > 50` → considerar virtualizacion
- [ ] Touch swipe pausa autoplay (no competir con gestos del usuario)
- [ ] Rollback: archivos legacy NO se eliminan hasta validacion en staging (7 dias)

### Criterios de aceptacion

- Build pasa
- Screenshots diff < 1%
- Autoplay y navegacion por flechas/dots funcionales
- Skeleton companion funcional
- Respeta `ProductCard` unificado (consume variante del template)
- **Nuevo:** 1 producto → sin arrows/dots
- **Nuevo:** Touch swipe funcional en mobile

### Dependencia blanda

Si Ticket 1 (ProductCard) no esta completo, el carousel puede usar el ProductCard legacy. Pero idealmente se hace despues de Ticket 1.

---

## Resumen ejecutivo

### Tickets de infraestructura / fixes

| Ticket | Descripcion | Dias | Prioridad | Bloqueado por |
|--------|-------------|------|-----------|---------------|
| **T0.5** | **Security & Performance Hardening** | **2-3** | **Critica** | Ninguno |
| ~~D1~~ | ~~Fix client_home_settings~~ | — | ELIMINADO | — |
| ~~D2~~ | ~~Seed nv_templates T6-T8~~ | — | ELIMINADO (8 filas existen) | — |
| **D3** | **Fix template_key naming cross-BD** | **1** | **Critica** | Ninguno |
| D4 | Fix plan `pro` en palette_catalog | 0.1 | Alta | Ninguno |
| D5 | Fix locale/template_id vacios e2e | 0.1 | Media | Ninguno |
| **D6** | **Implementar custom palette API (bug activo)** | **1.5** | **Alta** | Ninguno |
| D7 | Limpiar cuentas preview draft | 0.5 | Baja | Ninguno |
| 13 | Actualizar docs database-first.md | 0.5 | Media | Ninguno |

### Tickets de unificacion

| Ticket | Componente | Dias | Lineas eliminadas | Archivos eliminados |
|--------|-----------|------|-------------------|-------------------|
| 0 | Setup (baselines + infra + reconciliacion) | 4-5 | 0 | 0 |
| 1 | ProductCard | 5-7 | ~950 | ~12 |
| 2 | FAQSection | 1-2 | ~750 | ~6 |
| 3 | ContactSection | 2-3 | ~1,100 | ~6 |
| 4 | Footer | 4-5 | ~1,000 | ~6 |
| 5 | ServicesSection | 2 | ~800 | ~7 |
| 6 | ProductCarousel | 1 | ~400 | ~3 |
| **Total unificacion** | | **19-25** | **~5,000** | **~40** |

### Tickets de features nuevas

| Ticket | Feature | Dias | Bloqueado por |
|--------|---------|------|---------------|
| 7 | Labels configurables (i18n prep) | 2-3 | T0.5 |
| 8 | Locale del tenant + defaults | 2 | Ticket 7 |
| 9 | CSS custom manual | 4-5 | T0.5 |
| 10 | CSS generado por IA | 2-3 | Ticket 9 |
| 11 | Template change UX improvements | 2 | Ticket 0 |
| 12 | Marketing & Branding Manager | 3-4 | Ninguno |
| 14 | Tokens de spacing (densidad visual) | 1-2 | Ticket 0 |
| 15 | Seleccion de fonts (catalogo + UI) | 2-3 | T0.5 + Ticket 0 |
| 16 | Actualizar proceso generacion templates | 1 | Tickets 1-6 |

### Totales (ajustados post-QA audit §30)

| Grupo | Estimacion original | Estimacion ajustada | Razon |
|-------|--------------------|--------------------|-------|
| **Nuevo: T0.5 Security** | — | 2-3 | Nuevo ticket bloqueante |
| Fixes BD (D3-D7, T13) | 2.7 | 3.2 | D3 necesita script SQL real, no pseudocode |
| Setup (T0) | 3-4 | 4-5 | 336 baselines + variant prop + rollback plans |
| Unificacion (T1-T6) | 17-24 | 21-29 | T1 subestimado (+1-2d), T4 footer branded (+1d) |
| Features (T7-T12) | 14.5-18.5 | 16-21 | T9 CSS sanitizacion (+1d) |
| Tokens/Fonts/Docs (T14-T16) | 4-6 | 4-6 | Sin cambios |
| **Total** | **38-51** | **50-67** | **+12-16 dias** |

### Grafo de dependencias

```
URGENTES (hacer primero, en paralelo):
  T0.5 (Security & Performance Hardening) ── NUEVO, bloquea T0/T7/T9/T15
  D3 (fix template_key naming) ─── CRITICO, bloquea consistencia
  D4 (fix plan pro) ─── 10 min
  D5 (fix locale/template vacios) ─── 10 min
  D6 (custom palette API bug) ─── bug activo en produccion

POST-FIXES:
  T0.5 (Security) + D3 (template_key) ──┐
                                          ▼
                              Ticket 0 (Setup + reconciliacion)
                                          │
                                          ├──> Ticket 1 (ProductCard)
                                          ├──> Ticket 2 (FAQSection)
                                          ├──> Ticket 3 (ContactSection)
                                          ├──> Ticket 4 (Footer)
                                          ├──> Ticket 5 (ServicesSection)
                                          ├──> Ticket 6 (ProductCarousel)
                                          │         └── dep. blanda → Ticket 1
                                          └──> Ticket 11 (Template change UX)

PARALELOS (independientes de unificacion):
  Ticket 7 (Labels) ──> Ticket 8 (Locale)
  Ticket 9 (CSS custom) ──> Ticket 10 (CSS IA)
  Ticket 12 (Branding Manager) ── independiente
  Ticket 13 (Docs fix) ── independiente
  D7 (Limpiar previews) ── independiente

POST-SETUP (dependen de T0, paralelos entre si):
  Ticket 0 ──> Ticket 14 (Spacing tokens)
  Ticket 0 ──> Ticket 15 (Font selection)

POST-UNIFICACION (depende de T1-T6):
  Tickets 1-6 ──> Ticket 16 (Actualizar generacion de templates + prompt IA)
```

### Orden de ejecucion recomendado

```
Semana 1: T0.5 + D3 + D4 + D5 + D6 + D7 + T13 (security + fixes rapidos, en paralelo)
Semana 1-2: T0 (Setup — depende de D3 + T0.5)
Semana 2-3: T7 + T9 (Labels + CSS custom — paralelos, dependen de T0.5 para sanitizacion)
Semana 3-6: T1 → T2 → T3 → T4 → T5 → T6 (unificacion secuencial)
Semana 4+: T8 (Locale — depende de T7)
Semana 3+: T14 + T15 (Spacing + Fonts — paralelos, dependen de T0)
Semana 5+: T10 + T11 (CSS IA + Template UX — dependen de T9 y T0)
Semana 6+: T12 (Branding Manager — cuando haya espacio)
Semana 7+: T16 (Actualizar generacion — depende de T1-T6 completos)
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

2. **Canon de template_key: `eighth` vs `template_8`** (§19.1)
   - Opcion A (recomendada): Canon = `eighth`. Migrar Backend DB.
   - Opcion B: Canon = `template_8`. Migrar Admin DB catalogo.

3. **Cambiar variante consume credito de component_change?** (§22)
   - Si → monetizable pero puede frustrar al usuario
   - No (recomendado) → cambiar variant es ajuste visual, no cambio estructural

4. **Plan downgrade con template premium activo** (§20 EC-6)
   - Grandfathering (recomendado) → template se mantiene pero no puede cambiar

5. **CSS custom permite `!important`?** (§25)
   - No (recomendado) → bloquear en sanitizacion para evitar side effects

6. **Custom palette API: implementar o postergar?** (§20)
   - Implementar (recomendado) → es un bug activo en DesignStudio

7. **LEGACY_KEY_MAP: limpiar o mantener?** (§21)
   - Mantener 6 meses post-unificacion, luego evaluar

### Definition of Done (global)

**Build & CI:**
- [ ] Build pasa sin errores ni warnings (`npm run build`)
- [ ] Lint pasa (`npm run lint`)
- [ ] Typecheck pasa (`npm run typecheck`)
- [ ] `node scripts/ensure-no-mocks.mjs` — 0 mocks en produccion

**Codigo:**
- [ ] 0 archivos duplicados en `templates/*/components/` para componentes migrados
- [ ] `jscpd` muestra reduccion de duplicacion > 40%
- [ ] Grep de colores hardcodeados sin `var()` en `storefront/` = 0
- [ ] `sectionComponents.tsx` apunta a componentes unificados (no a legacy)
- [ ] `SectionRenderer.tsx` inyecta `variant` prop correctamente
- [ ] LEGACY_KEY_MAP mantiene retrocompat con componentKeys existentes
- [ ] Cada variante usa `React.lazy()` (no import estatico)
- [ ] Bundle size por variante < 5KB gzipped

**Visual & UX:**
- [ ] Screenshot diff < 1% en 336 baselines (8 templates × 3 viewports × 7 componentes × 2 modes)
- [ ] Dark mode funcional con todos los componentes unificados
- [ ] `prefers-reduced-motion: reduce` respetado en variantes con animacion
- [ ] Skeleton companion funcional para cada componente unificado

**Tests unitarios (§24):**
- [ ] ProductCard: 14 tests (4 variantes + 5 badges + 5 edge cases)
- [ ] FAQSection: 6 tests (accordion + grid + edge cases)
- [ ] ContactSection: 4 tests (WhatsApp + form + edge cases)
- [ ] Footer: 4 tests (branded + links + edge cases)
- [ ] ServicesSection: 4 tests (grid + hover + edge cases)

**Tests de integracion (§24):**
- [ ] Template change preserva secciones compatibles
- [ ] Template change con CSS custom activo muestra warning
- [ ] Plan downgrade no rompe template activo (grandfathering)
- [ ] Palette change actualiza todos los componentes
- [ ] Labels se inyectan en cascada (override > locale > fallback)

**Tests E2E:**
- [ ] Checkout completo (browse → cart → checkout → payment → success)
- [ ] Design Studio round-trip (cambiar template → guardar → verificar)
- [ ] Onboarding → tienda publicada → storefront renderiza

**BD:**
- [ ] 0 inconsistencias template_key entre Backend y Admin DB
- [ ] 0 valores vacios en `clients.locale` o `clients.template_id`
- [ ] `normalizeTemplateKey()` es idempotente (input canonico = output)

**Documentacion:**
- [ ] Changelog actualizado en `novavision-docs/changes/`
- [ ] `database-first.md` actualizado con nombres reales de tablas/columnas

---

## Tickets adicionales: Labels + CSS custom + IA

Estos tickets son **independientes** de la unificacion de componentes (Tickets 0-6).
Pueden ejecutarse en paralelo o antes.

---

## Ticket 7: Migrar strings hardcodeados a props configurables
**Tipo:** Refactor / i18n prep
**Prioridad:** Alta (prerequisito para vender NovaVision como SaaS en Brasil)
**Estimacion:** 2-3 dias
**Bloqueado por:** T0.5 (necesita label validator implementado)
**Bloquea:** Ticket 8

### Scope

- [ ] Definir interfaz `Labels` con todas las keys configurables (~15 strings)
- [ ] Migrar strings hardcodeados en componentes de seccion:
  - [ ] ProductCard: "Agotado" → `labels.outOfStock || 'Agotado'`
  - [ ] ServicesGrid: "Nuestros Servicios" → `props.title || labels.servicesTitle`
  - [ ] FaqAccordion: "Preguntas Frecuentes" → `props.title || labels.faqTitle`
  - [ ] Headers (Elegant, Bold, Classic): nav links → `labels.navProducts`, etc.
  - [ ] Footers: links y fallbacks → `labels.navHome`, `labels.noContactInfo`
  - [ ] ContactInfo: "Hola, quiero más información" → `labels.whatsappMessage`
  - [ ] Toasts de favoritos → `labels.addedToFavorites`, `labels.loginRequired`
  - [ ] Currency: "$" → `currency.symbol`
- [ ] Crear `src/config/localeDefaults.ts` con defaults para `es-AR`
- [ ] Modificar `SectionRenderer.tsx` para inyectar `labels` en props de todas las secciones
- [ ] Verificar que SectionPropsEditor permite editar labels custom

**Seguridad — XSS prevention (§30 C2):**
- [ ] Renderizar labels con `{label}` (texto plano), NUNCA con `dangerouslySetInnerHTML`
- [ ] Usar validador `isSimpleString()` de T0.5 al guardar labels custom en API
- [ ] Regex de validacion: `/^[a-zA-Z0-9\s\.,!¿?áéíóúñçãõêâîôûàèìòùÀ-ÿ\-:(){}$%#&]{0,200}$/`
  - Acepta: caracteres latinos, puntuacion, simbolos de moneda
  - Rechaza: `<`, `>`, comillas, backticks, scripts

### Criterios de aceptacion

- 0 strings en español hardcodeados en componentes de seccion (grep clean)
- Todos los strings usan cascada: `props.label || labels[key] || fallback`
- Build pasa
- Visual identico (los defaults son los mismos strings actuales)
- **Nuevo:** Labels se renderizan como texto plano (no HTML) — test de XSS payload
- **Nuevo:** API rechaza labels con caracteres HTML/JS

---

## Ticket 8: Locale del tenant + defaults por idioma
**Tipo:** Feature
**Prioridad:** Alta (habilitador de NovaVision SaaS en Brasil)
**Estimacion:** 2 dias
**Bloqueado por:** Ticket 7
**Repos:** `@nv/api` + `@nv/web`

### Scope

**Backend:**
- [ ] Migracion: `ALTER TABLE clients ADD COLUMN locale text NOT NULL DEFAULT 'es-AR'`
- [ ] Endpoint: `PATCH /clients/:id/locale` (admin only)
- [ ] Incluir `locale` en response de `/home/data`

**Frontend:**
- [ ] Agregar defaults `pt-BR` a `localeDefaults.ts`:
  - "Esgotado", "Adicionar ao carrinho", "Ver mais", "Produtos", etc.
  - Currency: `{ symbol: 'R$', code: 'BRL', position: 'before' }`
- [ ] `SectionRenderer` resuelve labels en cascada:
  1. `section.props.labels.*` (override manual)
  2. `LOCALE_DEFAULTS[client.locale].*` (default por idioma)
  3. Fallback hardcodeado (retrocompat)
- [ ] Selector de locale en admin settings

### Criterios de aceptacion

- Tienda con `locale: 'pt-BR'` muestra todos los labels en portugues
- Admin puede override manual de cualquier label via SectionPropsEditor
- Build pasa en ambos repos

---

## Ticket 9: CSS custom manual via `client_design_overrides`
**Tipo:** Feature (addon premium)
**Prioridad:** Media
**Estimacion:** 4-5 dias (ajustado post-QA: sanitizacion completa requiere mas trabajo)
**Bloqueado por:** T0.5 (necesita CSS_SANITIZER implementado)
**Repos:** `@nv/api` + `@nv/web`

### Scope

**Backend:**
- [ ] CRUD endpoints para `client_design_overrides`:
  - `POST /design-overrides` — crear override
  - `GET /design-overrides` — listar activos
  - `PATCH /design-overrides/:id` — actualizar
  - `DELETE /design-overrides/:id` — revocar
- [ ] Guard: solo clientes con addon `custom_css` comprado
- [ ] Insertar addon en `addon_catalog`:
  - `key: 'custom_css'`, `family: 'design'`, `min_plan: 'growth'`

**Sanitizacion CSS server-side (§30 C1 — usar CSS_SANITIZER de T0.5):**
- [ ] Usar `CSS_SANITIZER.ts` creado en T0.5 con:
  - **Allowlist de properties:** `color`, `background-color`, `border-color`, `font-family`, `font-size`, `font-weight`, `padding`, `margin`, `text-align`, `text-decoration`, `letter-spacing`, `line-height`, `border-radius`, `opacity`, `box-shadow`, `border`, `border-width`, `border-style`, `text-transform`, `background`
  - **Blocklist de patterns:** `@import`, `@keyframes`, `@media`, `@supports`, `url()` externo, `expression()`, `behavior:`, `calc()` con nesting, `var()` con injection, `!important`
  - **Blocklist de properties:** `display: none`, `position: fixed/absolute`, `z-index`, `visibility: hidden`, `content` (pseudo-elements), `cursor: url()`
  - **Blocklist de selectores:** `body`, `html`, `*`, `#root`, selectores fuera del scope
- [ ] Scope obligatorio: wrappear en `.nv-store-{client_id} { ... }`
- [ ] Parsear con postcss (no regex) para mayor robustez
- [ ] Responder con `{ valid: boolean, sanitized: string, warnings: string[] }`

**Frontend:**
- [ ] Hook `useDesignOverrides()` — carga overrides activos, inyecta CSS en `<head>`
- [ ] Panel "CSS Personalizado" en DesignStudio:
  - Editor de texto con syntax highlighting (Monaco o CodeMirror lite)
  - Preview en tiempo real (aplica CSS al iframe de preview)
  - Selector: global vs por seccion (`target_section_id`)
  - **Nuevo:** Warning visual si se detectan properties bloqueadas (feedback inmediato)
- [ ] Integrar en `App.jsx` despues de `useThemeVars()`
- [ ] **postMessage validation:** preview iframe valida `event.origin` contra whitelist de dominios permitidos

### Criterios de aceptacion

- Admin puede escribir CSS custom y verlo aplicado en preview
- CSS se sanitiza server-side (no se puede inyectar JS ni cargar recursos externos)
- Override se desactiva si el addon se revoca
- Build pasa
- **Nuevo (seguridad):** Test suite de payloads maliciosos: `@import`, `url(attacker.com)`, `expression()`, `behavior:`, `display:none`, selector `body` — todos rechazados
- **Nuevo (seguridad):** CSS fuera del scope `.nv-store-{id}` es eliminado
- **Nuevo (UX):** Warning inmediato si admin escribe property bloqueada
- **Nuevo (aislamiento):** CSS de tenant A NO afecta a tenant B

---

## Tickets de infraestructura: Fixes de BD y UX

Estos tickets resuelven inconsistencias descubiertas en la auditoria (§19-§20).
Algunos son prerequisitos de la unificacion, otros son independientes.

---

## Ticket D3: Fix nomenclatura template_key entre BDs (CRITICO)
**Repo:** `@nv/api`
**Tipo:** Data migration + code fix
**Prioridad:** Critica (bloquea consistencia cross-BD)
**Estimacion:** 0.5 dias
**Bloqueado por:** Ninguno

### Problema (§19.1)

Backend DB usa `template_8`, Admin DB usa `eighth`. El frontend normaliza
con `normalizeTemplateKey()` pero es un parche.

### Scope

- [ ] Decidir canon: `eighth` (recomendado — es lo que usa component_catalog)
- [ ] Migracion Backend DB:
  ```sql
  UPDATE clients SET template_id = 'eighth' WHERE template_id = 'template_8';
  UPDATE clients SET template_id = 'first' WHERE template_id = 'template_1';
  -- etc. para todos los template_N → word equivalente
  UPDATE client_home_settings SET template_key = 'eighth' WHERE template_key = 'template_8';
  UPDATE client_home_settings SET template_key = 'first' WHERE template_key = 'template_1';
  -- etc.
  ```
- [ ] Actualizar `default-template-sections.ts` si usa format `template_N`
- [ ] Verificar que `normalizeTemplateKey()` sigue funcionando (retrocompat)
- [ ] Actualizar onboarding payloads en `nv_onboarding.design_config` si referencian `template_N`

### Criterios de aceptacion

- `SELECT DISTINCT template_id FROM clients` solo devuelve words (`first`..`eighth`)
- `SELECT DISTINCT template_key FROM client_home_settings` idem
- Build pasa
- Storefront renderiza correctamente post-migracion

---

## Ticket D4: Fix plan `pro` en palette_catalog
**Repo:** `@nv/api`
**Tipo:** Data fix
**Prioridad:** Alta
**Estimacion:** 10 min
**Bloqueado por:** Ninguno

### Problema (§19.2)

`palette_catalog` tiene `luxury_gold` con `min_plan_key = 'pro'` pero el plan
`pro` no existe. Solo existen `starter`, `growth`, `enterprise`.

### Scope

- [ ] `UPDATE palette_catalog SET min_plan_key = 'enterprise' WHERE palette_key = 'luxury_gold'`
- [ ] Verificar que no hay otros registros con `min_plan_key = 'pro'` en ninguna tabla

### Criterios de aceptacion

- `SELECT * FROM palette_catalog WHERE min_plan_key NOT IN ('starter','growth','enterprise')` → 0 filas
- Paleta luxury_gold accesible para plan enterprise

---

## Ticket D5: Fix locale y template_id vacios en clientes e2e
**Repo:** `@nv/api`
**Tipo:** Data fix
**Prioridad:** Media
**Estimacion:** 10 min
**Bloqueado por:** Ninguno

### Problema (§19.3, §19.4)

Clientes e2e-alpha y e2e-beta tienen `locale = ''` y `template_id = ''`.

### Scope

- [ ] Fix datos:
  ```sql
  UPDATE clients SET locale = 'es-AR' WHERE locale = '' OR locale IS NULL;
  UPDATE clients SET template_id = 'first' WHERE slug = 'e2e-alpha' AND template_id = '';
  UPDATE clients SET template_id = 'fifth' WHERE slug = 'e2e-beta' AND template_id = '';
  ```
- [ ] Agregar constraint para prevenir vacios futuros:
  ```sql
  ALTER TABLE clients ALTER COLUMN locale SET DEFAULT 'es-AR';
  ALTER TABLE clients ADD CONSTRAINT locale_not_empty CHECK (locale <> '');
  ```

### Criterios de aceptacion

- `SELECT * FROM clients WHERE locale = '' OR template_id = ''` → 0 filas
- Constraint activo para prevenir vacios futuros

---

## Ticket D6: Implementar custom palette API methods (BUG ACTIVO)
**Repo:** `@nv/api` + `@nv/web`
**Tipo:** Bug fix
**Prioridad:** Alta
**Estimacion:** 1 dia
**Bloqueado por:** Ninguno

### Problema (§20)

DesignStudio llama `identityService.createCustomPalette()`,
`updateCustomPalette()`, `deleteCustomPalette()` pero estos metodos
NO estan implementados en `identity.js`. El usuario puede intentar
crear una paleta custom y la operacion falla silenciosamente.

### Scope

**Backend (verificar si existen):**
- [ ] `POST /palettes/custom` — crear paleta custom
- [ ] `PATCH /palettes/custom/:id` — actualizar
- [ ] `DELETE /palettes/custom/:id` — eliminar

**Frontend:**
- [ ] Implementar metodos en `services/identity.js`:
  ```javascript
  createCustomPalette: async (data) => axiosInstance.post('/palettes/custom', data),
  updateCustomPalette: async (id, data) => axiosInstance.patch(`/palettes/custom/${id}`, data),
  deleteCustomPalette: async (id) => axiosInstance.delete(`/palettes/custom/${id}`),
  ```
- [ ] Verificar error handling en CustomPaletteEditor

### Criterios de aceptacion

- Admin puede crear, editar y eliminar paletas custom desde DesignStudio
- Paleta custom persiste en BD y se usa en storefront
- Build pasa

---

## Ticket D7: Limpiar cuentas preview draft
**Repo:** `@nv/api`
**Tipo:** Maintenance
**Prioridad:** Baja
**Estimacion:** 0.5 dias
**Bloqueado por:** Ninguno

### Problema (§19.7)

20 cuentas `nv_accounts` con status `draft` y email `preview+*@example.com`
contaminan metricas.

### Scope

- [ ] Crear endpoint o script de limpieza:
  ```sql
  DELETE FROM nv_onboarding WHERE account_id IN (
    SELECT id FROM nv_accounts WHERE email LIKE 'preview+%@example.com' AND status = 'draft'
  );
  DELETE FROM nv_accounts WHERE email LIKE 'preview+%@example.com' AND status = 'draft';
  ```
- [ ] Implementar TTL automatico: cron job que limpia drafts > 24h con email preview+*

### Criterios de aceptacion

- 0 cuentas preview draft > 24h en BD
- Cron job programado para limpieza periodica

---

## Ticket 11: Template change UX improvements
**Tipo:** Enhancement
**Prioridad:** Media
**Estimacion:** 2 dias
**Bloqueado por:** Ticket 0
**Repos:** `@nv/web`

### Problema (§20, edge cases 5, 6, 8)

El flujo de template change tiene 3 edge cases no cubiertos:
1. No hay undo/redo para cambios de template
2. Plan downgrade no valida template activo
3. CSS custom puede romper al cambiar template

### Scope

- [ ] **Warning de CSS custom al cambiar template:**
  - Si `client_design_overrides` tiene overrides activos al cambiar template
  - Mostrar modal: "Tenes CSS personalizado. ¿Mantener / Desactivar / Regenerar con IA?"
  - Si "Desactivar": `PATCH /design-overrides/:id { status: 'suspended' }`

- [ ] **Draft stale detection:**
  - Al cargar DesignStudio, comparar `localStorage` draft timestamp con `client_home_settings.updated_at`
  - Si draft es mas viejo → toast "Hay cambios mas recientes. ¿Cargar o descartar draft?"

- [ ] **Grandfathering on plan downgrade:**
  - No forzar template change en downgrade
  - Pero deshabilitar boton "Cambiar template" si template actual > plan actual
  - Tooltip: "Tu template actual se mantiene pero no podes cambiar a otros templates de este plan"

### Criterios de aceptacion

- Warning visible al cambiar template con CSS custom activo
- Draft stale detectado y mostrado al usuario
- Template premium no se pierde en downgrade pero tampoco se puede cambiar
- Build pasa

---

## Ticket 12: Marketing & Branding Manager
**Tipo:** Feature (nuevo panel admin)
**Prioridad:** Media-Baja
**Estimacion:** 3-4 dias
**Bloqueado por:** Ninguno (independiente)
**Repos:** `@nv/web`

### Concepto (§23)

Panel centralizado "Mi Marca" en admin dashboard que agrega vistas
existentes de branding en una unica experiencia.

### Scope

- [ ] Crear seccion `BrandingManager` en admin:
  - Vista overview con logo, nombre, paleta, template, redes sociales
  - Links rapidos a cada editor existente (no duplicar funcionalidad)
  - Indicadores de completitud (logo subido? redes configuradas? SEO?)
  - Score de "brand completeness" (0-100%)

- [ ] Agregar a `AdminDashboard/index.jsx`:
  - Nueva seccion en categoria "Marca y Contenido"
  - Icon, titulo, descripcion

- [ ] **Kit de Marca IA (premium):**
  - [ ] Boton "Generar paleta desde logo" (extrae colores dominantes)
  - [ ] Boton "Sugerir slogan" (usa Store DNA)
  - [ ] Boton "Audit de consistencia visual" (gratis, no consume creditos)

- [ ] Nuevos action codes en backend:
  - `ai_branding_palette` — paleta desde logo
  - `ai_branding_slogan` — slogan suggestions

### Criterios de aceptacion

- Panel "Mi Marca" visible en admin dashboard
- Links a editores existentes funcionales
- Brand completeness score calculado correctamente
- AI palette extraction funcional (si se implementa la capa IA)
- Build pasa

---

## Ticket 13: Actualizar documentacion database-first.md
**Tipo:** Documentation
**Prioridad:** Media
**Estimacion:** 0.5 dias
**Bloqueado por:** Ninguno

### Problema (§19.8)

Las reglas `.claude/rules/database-first.md` tienen nombres de tablas/columnas
incorrectos que confunden a agentes IA.

### Scope

- [ ] Fix nombres:
  - `plan_definitions` → `plans`
  - `backend_clusters.cluster_key` → `backend_clusters.cluster_id`
  - `addon_catalog.key` → `addon_catalog.addon_key`
- [ ] Agregar columnas faltantes en el schema documentado
- [ ] Verificar que todos los schemas match con BD real

### Criterios de aceptacion

- Todos los nombres de tablas y columnas en database-first.md coinciden con BD real
- Agentes IA pueden generar queries correctos siguiendo las reglas

---
## Ticket 10: CSS generado por IA
**Tipo:** Feature (AI)
**Prioridad:** Media-Baja
**Estimacion:** 2-3 dias
**Bloqueado por:** Ticket 9
**Repos:** `@nv/api` + `@nv/web`

### Scope

**Backend:**
- [ ] Nuevo action code: `ai_css_generation`
- [ ] Registrar pricing en `ai_feature_pricing` (2 cr normal, 5 cr pro)
- [ ] Endpoint: `POST /design-overrides/ai-generate`
  - Input: `{ target, description, current_tokens, template_key }`
  - Store DNA se inyecta automaticamente
  - Output: `{ css, explanation, credits_consumed }`
- [ ] Prompt optimizado para CSS scoped con variables --nv-*

**Frontend:**
- [ ] Boton "Generar con IA" en el panel CSS del DesignStudio
  - AiButton con action code `ai_css_generation`
  - Textarea para descripcion del usuario
  - AiTierToggle (normal/pro)
- [ ] AiImagePreviewModal adaptado para CSS:
  - Muestra preview del CSS aplicado
  - Diff visual (antes/despues)
  - Botones: "Aplicar" / "Regenerar" / "Descartar"

### Criterios de aceptacion

- Admin describe en lenguaje natural → IA genera CSS
- CSS generado respeta tokens --nv-* y scoping
- Preview en tiempo real antes de aplicar
- Credits se consumen correctamente
- Build pasa

---
## Ticket 14: Tokens de spacing — generalizacion de medidas
**Tipo:** Infraestructura + UX
**Prioridad:** Media
**Estimacion:** 1-2 dias
**Bloqueado por:** Ticket 0
**Repos:** `@nv/web`
**Plan:** §28

### Scope

**Tokens CSS (palettes.ts):**
- [ ] Agregar 8 tokens de spacing a `paletteToCssVars()`:
  - `--nv-spacing-xs` (8px), `--nv-spacing-sm` (12px), `--nv-spacing-md` (16px)
  - `--nv-spacing-lg` (24px), `--nv-spacing-xl` (32px)
  - `--nv-spacing-section` (80px / 5rem)
  - `--nv-spacing-page` (24px mobile), `--nv-spacing-page-lg` (96px desktop)
- [ ] Crear `DENSITY_PRESETS` (compact, normal, relaxed) como export

**Componentes unificados:**
- [ ] Reemplazar clases Tailwind hardcodeadas por tokens en componentes nuevos:
  - `py-20 md:py-28` → `py-[var(--nv-spacing-section)]`
  - `px-6 md:px-16 lg:px-24` → `px-[var(--nv-spacing-page)] lg:px-[var(--nv-spacing-page-lg)]`
- [ ] Solo aplicar a componentes unificados (Tickets 1-6), NO tocar templates legacy

**UI en DesignStudio:**
- [ ] Agregar control de "Densidad visual" con 3 opciones: Compacta / Normal / Relajada
- [ ] Preview en tiempo real via postMessage al iframe
- [ ] Guardar en `client_home_settings.theme_config.custom_vars`

**Almacenamiento:**
- [ ] `resolveEffectiveTheme()` ya soporta `custom_vars` override — verificar que funcione con spacing

**Accesibilidad — touch targets (§30 M8):**
- [ ] Agregar token `--nv-min-touch-target: 2.75rem` (44px) para mobile
- [ ] Media query `@media (pointer: fine)` reduce a `1.5rem` (24px) para desktop
- [ ] Density=compact NO puede reducir botones/links por debajo de `--nv-min-touch-target`
- [ ] `prefers-reduced-motion: reduce` → tokens de transition a `0ms`:
  ```css
  @media (prefers-reduced-motion: reduce) {
    :root { --nv-transition-fast: 0ms; --nv-transition: 0ms; }
  }
  ```

### Criterios de aceptacion

- Los 8 tokens de spacing se inyectan con valores por defecto en todos los templates
- Templates legacy NO se ven afectados (siguen usando clases hardcodeadas)
- Componentes unificados usan los tokens
- Cambiar densidad en DesignStudio actualiza el preview en tiempo real
- Persistencia correcta en theme_config
- Build pasa
- **Nuevo (a11y):** Touch targets ≥ 44px en mobile, incluso con density=compact
- **Nuevo (a11y):** prefers-reduced-motion desactiva transiciones

---
## Ticket 15: Seleccion de fonts — catalogo y UI
**Tipo:** Feature
**Prioridad:** Media
**Estimacion:** 2-3 dias
**Bloqueado por:** Ticket 0
**Repos:** `@nv/web`
**Plan:** §29

### Scope

**Catalogo de fonts:**
- [ ] Crear `src/theme/fontCatalog.ts` con 10 Google Fonts:
  - Sans: Inter, Poppins, DM Sans, Space Grotesk, Outfit
  - Serif: Playfair Display, Lora, Merriweather
  - Mono: JetBrains Mono, Fira Code
- [ ] Cada entry: `{ key, label, family, category, planMin }`
- [ ] Plan gating: starter = 3 fonts, growth = 10, enterprise = 10 + custom (futuro)

**Carga dinamica (con protecciones §30 A2, A4):**
- [ ] Crear componente `FontLoader` que inyecta `<link>` de Google Fonts al `<head>`
- [ ] Lazy: solo carga la font seleccionada (no todas)
- [ ] Cache: no re-insertar si ya existe el `<link>` tag
- [ ] **Timeout 5s:** Usar `AbortController` — si Google Fonts no responde en 5s, usar system fonts como fallback
- [ ] **font-display: swap** obligatorio en todas las cargas (evita FOIT — Flash of Invisible Text)
- [ ] **Preconnect:** Agregar `<link rel="preconnect" href="https://fonts.googleapis.com">` y `<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>` en `index.html`
- [ ] **font-size-adjust: 0.5** en el root para minimizar CLS al cambiar entre fonts

**UI en DesignStudio:**
- [ ] Agregar selector de tipografia con dropdown
- [ ] Preview de la font: "Aa Bb Cc Dd 1234" + texto de ejemplo
- [ ] Filtro por categoria: Sans / Serif / Mono
- [ ] Plan badge en fonts gated (lock icon + "Growth")
- [ ] **Precargar font ANTES de aplicar:** Al seleccionar font, cargarla en background y aplicar solo cuando este lista (evita CLS)

**Aplicacion global:**
- [ ] Agregar `font-family: var(--nv-font, inherit)` al contenedor root del storefront
  - Esto hace que TODOS los templates (incluidos legacy) hereden la font seleccionada
  - Cambio de 1 linea en `App.jsx` o `StoreLayout`

**Plan downgrade fallback (§30 A3):**
- [ ] En `resolveEffectiveTheme()`: validar `font_key` contra fonts disponibles del plan actual
- [ ] Si font no disponible en plan (ej: "Space Grotesk" en starter) → fallback a "Inter" + log warning
- [ ] NO mostrar error al usuario — degradar gracefully

**Almacenamiento:**
- [ ] Guardar `font_key` en `client_home_settings.theme_config`
- [ ] `resolveEffectiveTheme()` resuelve `font_key` → `FONT_CATALOG[key].family` → `--nv-font`

### Criterios de aceptacion

- Admin puede seleccionar tipografia desde el DesignStudio
- La font se carga dinamicamente desde Google Fonts
- Preview en tiempo real
- Fonts gated muestran indicador de plan
- Persistencia correcta en theme_config
- Todos los templates (incluidos legacy 1-5) heredan la font seleccionada
- Build pasa, sin flicker al cargar la font (display=swap)
- **Nuevo (performance):** CLS < 0.05 al cambiar font (font-size-adjust + preload)
- **Nuevo (resilience):** Si Google Fonts timeout 5s → system fonts sin crash
- **Nuevo (plan):** Downgrade de plan → font fallback automatico a Inter
- **Nuevo (security):** Font family string viene de whitelist (FONT_CATALOG), nunca de user input libre

---
## Ticket 16: Actualizar proceso de generacion de templates
**Tipo:** Documentacion + Infraestructura
**Prioridad:** Baja
**Estimacion:** 1 dia
**Bloqueado por:** Tickets 1-6 (depende de que existan componentes unificados)
**Repos:** `novavision-docs`
**Plan:** §27

### Scope

**Actualizar ADDING_TEMPLATES_AND_COMPONENTS.md:**
- [ ] Agregar seccion "Nuevo proceso (post-unificacion)"
- [ ] Documentar estructura de `config.js` con variantes
- [ ] Documentar Home generico con SectionRenderer
- [ ] Reducir 14-point checklist a 9 pasos
- [ ] Mantener seccion legacy "Proceso anterior" como referencia

**Actualizar TEMPLATE_HOMEPAGE_GENERATION_PROMPT.md:**
- [ ] Cambiar instrucciones: de "generar componentes completos" a "seleccionar variantes"
- [ ] Agregar lista de variantes disponibles por tipo de seccion
- [ ] Agregar guia de tokens de spacing y font
- [ ] Agregar restriccion: NO crear carpetas de componentes
- [ ] Agregar ejemplo de config.js

**Crear template scaffold:**
- [ ] Script `scripts/new-template.mjs` que genera:
  - `templates/{nombre}/config.js` con boilerplate
  - `templates/{nombre}/pages/HomePage.jsx` generico
  - Entry en `templatesMap.ts`
  - Entry en `resolveEffectiveTheme.ts`
  - SQL de seed para `nv_templates` y `palette_catalog`

### Criterios de aceptacion

- Documentacion refleja el proceso nuevo
- Prompt de IA genera configs validos (no codigo de componentes)
- Script scaffold genera estructura correcta
- El proceso nuevo esta validado con al menos 1 template de prueba

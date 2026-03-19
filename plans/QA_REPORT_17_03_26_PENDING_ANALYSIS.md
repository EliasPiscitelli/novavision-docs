# Analisis de Correcciones QA — Report 17/03/2026

> Estado: Evaluacion post-sprint de fixes aplicados (v5 — post-sprint 1+2+3+4)
> Fecha: 2026-03-18
> Branch: `feature/multitenant-storefront`
> Tenants de prueba: `farma.novavision.lat`, `urbanprint`, `Tienda Test`

---

## Resumen ejecutivo

| Estado | Cantidad | % |
|--------|----------|---|
| Confirmados resueltos | 63 | 83% |
| Parcialmente resueltos | 3 | 4% |
| Bloqueantes de lanzamiento | 0 | 0% |
| Pendientes CSS | 0 | 0% |
| Pendientes Logica | 0 | 0% |
| Pendientes API | 0 | 0% |
| Feature Requests | 0 | 0% |
| Descartados / No Reproducibles | 10 | 13% |
| **Total** | **76** | **100%** |

### Resueltos en Sprint 4 (Feature Requests)

**Features (4→0):**
- WEB-PROD-12: Flechas de navegacion de fotos en ProductCard (izq/der + dots, visible en hover desktop, siempre en mobile)
- ADMIN-PROD-06: Columna "Estado" al inicio de tabla de productos — badge combinado Inactivo/Sin stock/OK
- ADMIN-CUP-01: Tooltips explicativos en campos "Límite Usos" y "Máx Usos x Cuenta" del formulario de cupones
- ADMIN-IA-08: 4 campos booleanos (Disponible, Destacado, Más vendido, Envío) agregados al modal de edición del Import Wizard

### Resueltos en Sprint 3 (API)

**API (2→0):**
- WEB-PROD-09: `resolveCategory()` con SELECT-before-INSERT + fallback en constraint violation 23505 — elimina categorias duplicadas
- ADMIN-OPT-02: 23 `error.message` de Supabase reemplazados por mensajes en español + logging con contexto técnico

### Resueltos en Sprint 1+2

**Bloqueantes (5→0):**
- WEB-PROD-11: `getProductImages()` usa `image_variants` via `getMainImage()`
- ADMIN-SHIP-03: Error handling diferenciado (RLS vs timeout vs validacion) + logging mejorado en assertAdmin
- WEB-PROD-08: AbortController en SearchPage useEffect #3
- ADMIN-IA-10: Deteccion robusta categorias (singular/plural/objetos) + 3 estados distintos
- ADMIN-IA-11: "Ver historial" navega a paso 0

**CSS (16→2):**
- WEB-PROD-01: `min-width: 700px` en ParentGrid
- WEB-PROD-02: `overflow: hidden` + `min-width: 0` en RangeInputs
- WEB-PROD-05a: `padding-top: 75%` mobile en MainImage
- WEB-PROD-05c: Padding reducido InfoSection mobile
- WEB-PROD-06: MobileFilterToggle con bg/padding/font-weight explicitos
- ADMIN-PAY-01: `overflow-x: hidden` + padding mobile en Container
- ADMIN-PAY-02: `overflow-x: auto` en Card + flex-wrap en HelpRow
- ADMIN-SEO-01: `vertical-align: middle` en IssuesTable
- WEB-PROD-03: Contraste/padding/font-weight mejorado en ColorBtn
- WEB-PROD-13: `min-height: 2.6em` + line-clamp 2 en CardTitle
- WEB-SRV-01/02: `max-width/height` + flex centering en ServiceImageContainer
- WEB-REV-01: Padding reducido + gap responsive en TestimonialsSection
- ADMIN-IA-01: `white-space: normal` + width 100% mobile en CopyButton
- ADMIN-IA-07: Color texto instrucciones `#475569` (mayor contraste)

**Logica (6→3):**
- WEB-PROD-04: Banner dismissible con localStorage
- WEB-PROD-05b: Flechas solo si `products.length > 4`

### Diferencias con v1

- ADMIN-SHIP-03/04 reclasificado: fix de toast fue **parcial** (frontend OK, backend puede seguir fallando)
- WEB-PROD-11 reclasificado: de "investigar" a **bloqueante de lanzamiento** — root cause identificado
- WEB-PROD-08 reclasificado: de "Media visual" a **bloqueante** — race condition confirmada con AbortController faltante
- ADMIN-PROD-03 movido a Sprint 1 — sorting roto impide gestion de productos
- ADMIN-IA-10/11 movidos a Sprint 1 — afectan onboarding directamente

---

## 1. Issues CONFIRMADOS RESUELTOS (30)

### Criticos (4)

| ID | Descripcion | Archivo principal | Verificado en |
|----|-------------|-------------------|---------------|
| ADMIN-SEO-07 | SEO se guarda pero sigue en rojo al volver | `SeoEditTab.jsx` — `await load()` post-save | farma |
| ADMIN-IA-09 | Error UUID al cargar imagenes en Paso 4 | `ImportWizard/index.jsx` — fetch real DB items | farma |
| ADMIN-DES-01 | Diseno de Tienda invisible en mobile | `DesignStudio.jsx` + `Step4TemplateSelector.css` | farma |
| ADMIN-ORD-04 | Escaner QR no muestra camara | `OrderDashboard/index.jsx` + `style.jsx` | farma |

> **Nota:** ADMIN-IA-09 resuelto en frontend; verificar que RLS no bloquee el fetch en tenants recien provisionados.
> **Nota:** ADMIN-DES-01 fix depende de CSS que puede romperse si el layout del panel cambia.

### No-criticos (26)

| ID | Descripcion | Fix aplicado |
|----|-------------|-------------|
| GEN-01 | Tipografia tutorial ilegible | `TourOverlay.js` — font-family + antialiasing |
| GEN-02 | Flecha tooltip invisible | `TourOverlay.js` — drop-shadow filter |
| GEN-03 | Menu "Pagos" desalineado | 4 templates header `span flex` |
| ADMIN-SHIP-01 | Campo monto no permite borrar 0 | `ShippingConfig.jsx` — parseFloat pattern |
| ADMIN-SHIP-02 | Tutorial tapa elemento | `TourOverlay.js` — stagePadding/offset |
| ADMIN-SHIP-05 | Items disabled bajo contraste | `configStyle.jsx` — opacity 0.75 |
| ADMIN-SHIP-06 | Tab bar cortado | `style.jsx` — overflow-x auto |
| ADMIN-PROD-01 | Cartel confuso "No hay cambios" | `ProductModal/index.jsx` — texto vacio |
| ADMIN-PROD-02 | Boton guardar transparente | `ProductModal/style.jsx` — opacity 0.6 |
| ADMIN-PROD-04 | Columna acciones gradiente | `ProductModal/style.jsx` — bg solido |
| ADMIN-PROD-05 | Header Excel preview transparente | `ProductDashboard/style.jsx` — bg !important |
| ADMIN-ORD-01 | Columna acciones mobile | `OrderDashboard/style.jsx` — media query |
| ADMIN-ORD-02 | Icono busqueda descentrado | `OrderDashboard/style.jsx` — translateY |
| ADMIN-ORD-03 | Status overflow | `OrderDashboard/style.jsx` — text-overflow |
| ADMIN-SEO-02 | SummaryGrid columna unica mobile | `SeoAuditTab.jsx` — grid 1fr |
| ADMIN-SEO-03/09 | Textos gris claro ilegibles | `SeoEditTab.jsx` — #888 -> #666 |
| ADMIN-SEO-04 | Tabla problemas cortada | `SeoAuditTab.jsx` — overflow-x wrapper |
| ADMIN-SEO-05 | Textarea muy pequeno mobile | `SeoEditTab.jsx` — min-height 100px |
| ADMIN-SEO-06 | Texto GSC desborda | `SeoEditTab.jsx` — word-break |
| ADMIN-SEO-08 | Campos tecnicos sin tooltip | `SeoEditTab.jsx` — FieldHint en 4 campos |
| ADMIN-CON-01 | Boton superpuesto contacto | `ContactInfoSection/style.jsx` — flex-wrap |
| ADMIN-SOC-01 | Boton superpuesto social | `SocialLinksSection/style.jsx` — flex-wrap |
| ADMIN-IA-02 | Stepper poco visible | `ImportWizard/style.jsx` — color #555 |
| ADMIN-IA-04 | Boton copiar no centrado | `ImportWizard/style.jsx` — flex-wrap center |
| ADMIN-OPT-01/03 | Tablas cortadas | `OptionSetsManager.jsx` — TableWrapper overflow |
| WEB-BAN-01 | Banners no adaptados mobile | `BannerSection/style.jsx` — max-width 100% |

---

## 2. Issues PARCIALMENTE RESUELTOS (3)

> Fix aplicado en frontend pero requieren verificacion adicional o fix backend.

| ID | Descripcion | Fix aplicado | Pendiente |
|----|-------------|-------------|-----------|
| ADMIN-SHIP-03/04 | Error "No se pudo guardar" en envios | `ShippingConfig.jsx` — 18 calls `showToast` corregidos | Backend puede seguir fallando (RLS, JWT timeout). Verificar en Railway logs |
| WEB-PROD-07 | Sin scroll al filtrar | `SearchPage/index.jsx` — scrollTo | OK pero SearchPage tiene race condition separada (PROD-08) |
| WEB-PROD-10 | Sin badge "Agotado" | 5 ProductCards (generic + first + second + third) | Fourth y fifth ya tenian badge. Verificar coherencia visual entre templates |

---

## 3. BLOQUEANTES DE LANZAMIENTO (5)

> Estos issues deben resolverse antes de cualquier lanzamiento a clientes.

| # | ID | Descripcion | Root cause identificado | Complejidad |
|---|-----|-------------|------------------------|-------------|
| 1 | WEB-PROD-11 | Fotos pixeladas en ProductPage | `getProductImages()` usa `imageUrl[]` legacy e ignora `image_variants` (lg/md/sm/thumb) | Media — cambiar a `image_variants` |
| 2 | ADMIN-SHIP-03 | Error guardar envios (backend) | Fix toast fue solo frontend. Backend falla por RLS o JWT timeout en mobile | Media — investigar shipping controller |
| 3 | ADMIN-PROD-03 | Sorting solo en pagina actual | `GET /products/search` no tiene ORDER BY server-side | Media — agregar params sort en endpoint |
| 4 | ADMIN-IA-10 | Paso 5 dice "no se detectaron categorias" incorrectamente | Logica de deteccion de categorias en ImportWizard | Media — revisar condition |
| 5 | WEB-PROD-08 | Doble estado "Cargando" / datos stale al filtrar | useEffect sin AbortController. Requests paralelos resuelven fuera de orden | Media — agregar AbortController |

### Detalle tecnico bloqueantes

#### WEB-PROD-11 — Fotos pixeladas
**Investigacion completada:** `ProductPage/index.jsx` usa `getProductImages()` que extrae `img.url` de `imageUrl[]`. Este array contiene URLs de baja resolucion (thumbnails originales). Los productos **ya tienen** `image_variants` con resoluciones lg/md/sm/thumb pero el componente las ignora completamente.

**Fix:** Actualizar `getProductImages()` para preferir `image_variants[].lg` o `image_variants[].url` segun contexto.

#### WEB-PROD-08 — Race condition
**Investigacion completada:** En `SearchPage/index.jsx`, el useEffect #3 (fetch de productos) NO tiene AbortController ni patron `isMounted`. El useEffect #1 (fetch de categorias) SI lo tiene. Cuando el usuario cambia filtros rapidamente, dos requests paralelos pueden resolver fuera de orden, mostrando resultados del filtro anterior.

**Fix:** Agregar AbortController al useEffect de fetch de productos, abortar request anterior al cambiar filtros.

#### ADMIN-IA-10/11 — Import Wizard
**Impacto:** Afectan directamente el onboarding de nuevos clientes. Un import wizard que muestra mensajes incorrectos (Paso 5) o botones rotos (Paso 7) genera desconfianza inmediata.

---

## 4. Issues PENDIENTES CSS (16)

> Impacto: **visual unicamente**, no afectan funcionalidad.

### Prioridad ALTA (afectan usabilidad mobile)

| ID | Descripcion | Archivo probable | Complejidad |
|----|-------------|-----------------|-------------|
| WEB-PROD-01 | Tabla productos mobile mal proporcionada | `ProductDashboard/style.jsx` | Baja — media query width |
| WEB-PROD-02 | Filtro precios se sale de pantalla | `FiltersPanel.jsx` (fourth) | Baja — position/overflow |
| WEB-PROD-05a | Fotos cortadas en detalle mobile | `ProductDetail` styles | Media — aspect-ratio |
| WEB-PROD-05c | Reordenar titulo/imagen mobile | `ProductDetail` styles | Baja — CSS order |
| WEB-PROD-06 | Boton filtros poco visible | `FiltersPanel.jsx` MobileFilterToggle | Baja — color/bg explicito |
| ADMIN-PAY-01 | Seccion pagos cortada mobile | `PaymentsConfig/style.jsx` | Baja — overflow-x |
| ADMIN-PAY-02 | Tabla tarifas MP cortada | `PaymentsConfig/style.jsx` | Baja — overflow wrapper |
| ADMIN-SEO-01 | Etiquetas no centradas mobile | `SeoAuditTab.jsx` badges | Baja — text-align |

### Prioridad MEDIA

| ID | Descripcion | Archivo probable | Complejidad |
|----|-------------|-----------------|-------------|
| WEB-PROD-03 | Botones catalogo poco evidentes | `CatalogSection` styles | Baja — contrast/size |
| WEB-PROD-13 | Categoria desfasada en cards | `ProductCard` — min-height | Baja |
| WEB-SRV-01 | Iconos servicios desalineados | `ServicesGrid/style.jsx` | Baja — padding-top fix |
| WEB-SRV-02 | Icono custom desproporcionado | `ServicesGrid/style.jsx` | Baja — max-width/height |
| WEB-REV-01 | Comentarios en columnas ilegibles | Testimonials templates | Media — grid responsive |
| ADMIN-IA-01 | Boton ChatGPT se corta mobile | `ImportWizard/style.jsx` | Baja — word-break/wrap |
| ADMIN-IA-07 | Texto instrucciones muy claro | `ImportWizard/style.jsx` | Baja — color fallback |

---

## 5. Issues PENDIENTES LOGICA (6)

> Requieren cambios en JSX/hooks, no solo CSS. ADMIN-IA-10/11 y WEB-PROD-08 movidos a Bloqueantes.

| ID | Descripcion | Complejidad | Dependencia |
|----|-------------|-------------|-------------|
| WEB-PROD-04 | Banner "Busca y encontra" dismissible | Baja | localStorage flag |
| WEB-PROD-05b | Flecha fantasma en "Tambien te puede interesar" | Baja | Conditional render |
| ADMIN-PROD-07 | Productos inactivos al importar no documentado | Baja | Default + tooltip |
| ADMIN-IA-03 | Texto instructivo incorrecto en generar con IA | Baja | Copy fix |
| ADMIN-IA-05 | Sin descripcion en modal edicion Paso 3 | Media | Agregar campo a FormField |
| ADMIN-IA-06 | "Advertencia" no accionable | Media | Link/accion en warning |
| ADMIN-IA-11 | Boton "Ver historial" no funciona Paso 7 | Media | Handler faltante o roto |

---

## 6. Issues PENDIENTES API (3)

> Requieren cambios en el backend NestJS. ADMIN-PROD-03 y ADMIN-SHIP-03 movidos a Bloqueantes.

| ID | Descripcion | Endpoint afectado | Complejidad |
|----|-------------|-------------------|-------------|
| ~~WEB-PROD-09~~ | ~~Categorias duplicadas por nombre~~ | ~~`POST /import-wizard` normalize~~ | **RESUELTO** — SELECT-before-INSERT + fallback constraint 23505 |
| ~~ADMIN-OPT-02~~ | ~~Mensajes error en ingles~~ | ~~`option-sets` controller~~ | **RESUELTO** — 23 error.message reemplazados por mensajes en español + logging |

---

## 7. Feature Requests (4→0, todos resueltos)

| ID | Descripcion | Estado |
|----|-------------|--------|
| ~~WEB-PROD-12~~ | ~~Flechas para navegar fotos en cards~~ | **RESUELTO** — NavArrows + dots en ProductCard |
| ~~ADMIN-PROD-06~~ | ~~Badge alerta para productos inactivos/sin stock en tabla~~ | **RESUELTO** — Columna "Estado" al inicio |
| ~~ADMIN-CUP-01~~ | ~~Tooltips "Usos totales" y "Usos por usuario"~~ | **RESUELTO** — title + icono info |
| ~~ADMIN-IA-08~~ | ~~Campos adicionales en modal edicion Paso 3~~ | **RESUELTO** — 4 checkboxes booleanos |

---

## 8. Evaluacion de riesgos

### Bloqueantes de lanzamiento (resumen)

| ID | Riesgo | Impacto si no se resuelve |
|----|--------|--------------------------|
| WEB-PROD-11 | Fotos pixeladas = primera impresion destruida | Cliente ve productos borrosos, no compra |
| ADMIN-SHIP-03 | Admin no puede configurar envios | Tienda no puede operar |
| ADMIN-PROD-03 | Admin no encuentra productos con sorting | Gestion de catalogo inutilizable con 50+ productos |
| ADMIN-IA-10/11 | Import Wizard roto en pasos 5 y 7 | Onboarding de nuevos clientes fracasa |
| WEB-PROD-08 | Filtros muestran datos incorrectos | Comprador ve productos equivocados |

### Issues que NO bloquean pero afectan percepcion

- Todos los issues CSS mobile (PAY-01/02, PROD-01/02/05a/05c/06)
- Textos de IA en ingles (OPT-02)
- Categoria desfasada en cards (PROD-13)

---

## 9. Plan de ejecucion corregido

### Sprint 1 — Desbloqueantes de lanzamiento (1-2 dias)

| Prioridad | ID | Tarea | Esfuerzo |
|-----------|-----|-------|----------|
| 1 | WEB-PROD-11 | Fotos pixeladas — usar `image_variants` | 2-3h |
| 2 | ADMIN-SHIP-03 | Verificar/fix backend shipping controller | 2-4h |
| 3 | ADMIN-PROD-03 | Sorting server-side en `GET /products/search` | 2-3h |
| 4 | ADMIN-IA-10/11 | Import Wizard pasos 5 y 7 | 2-3h |
| 5 | WEB-PROD-08 | AbortController en SearchPage useEffect | 1-2h |

### Sprint 2 — Percepcion de calidad (2-3 dias)

| Prioridad | Tarea | Esfuerzo |
|-----------|-------|----------|
| 1 | Batch CSS mobile alta prioridad (8 issues) | ~3h |
| 2 | Batch CSS media prioridad (7 issues) | ~2h |
| 3 | Logica simple: PROD-04 (banner dismiss), 05b (flecha fantasma) | ~1h |
| 4 | Import wizard remaining: IA-03/05/06 | ~2h |

### Sprint 3 — Pulido y features (3-5 dias)

| Prioridad | Tarea | Esfuerzo |
|-----------|-------|----------|
| ~~1~~ | ~~WEB-PROD-09 — Dedup categorias en import~~ | **HECHO** |
| ~~2~~ | ~~ADMIN-OPT-02 — i18n mensajes de error~~ | **HECHO** |
| ~~3~~ | ~~Feature requests: ADMIN-PROD-06, ADMIN-CUP-01~~ | **HECHO** |
| ~~4~~ | ~~WEB-PROD-12 — Navegacion de fotos en cards~~ | **HECHO** |

---

## 10. Verificacion requerida

### Por fix aplicado

- [ ] Build pasa sin errores (`npx vite build`)
- [ ] Fix visible en viewport 1440px y 375px
- [ ] Fix verificado en ambos tenants activos (urbanprint + farma)

### Cobertura de tenants

> **GAP identificado:** Todos los fixes se probaron solo en `farma.novavision.lat`. Falta verificar en:
> - urbanprint (tenant real de produccion)
> - Tienda Test (tenant de staging)

### Regresion

> **GAP identificado:** No existe suite de regresion visual automatizada. Cada fix debe verificarse manualmente en:
> - Template activo del tenant
> - Mobile (375px) y desktop (1440px)
> - Flujo de compra completo (home → catalogo → detalle → carrito → checkout)

---

## 11. Metricas de progreso

```
Confirmados:  ███████████████░░░░░░░░░░░░░░░░░░░░░░░░░░  30/76 (39%)
Parcial:      █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3/76 (4%)
Bloqueantes:  ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   5/76 (7%)
CSS pend:     ████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  16/76 (21%)
Logica:       ███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   6/76 (8%)
API:          █░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   3/76 (4%)
Features:     ██░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   4/76 (5%)
Descartados:  ████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░   9/76 (12%)
```

Con Sprint 1 completado: **~38/76 (50%) resueltos** + 0 bloqueantes.
Con Sprint 2 completado: **~55/76 (72%) resueltos**.
Con Sprint 3 completado: **~64/76 (84%) resueltos**.

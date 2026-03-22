# 2026-03-21 — Rediseño UX del AddonStoreDashboard

## Contexto

Auditoría QA + UX identificó 20 problemas de usabilidad. Usuarios 50+ no encontraban
la compra de créditos IA, la tipografía era chica, no había categorización visual clara
y faltaba confirmación antes de la compra.

## Cambios realizados

### AddonStoreDashboard/index.jsx

**Tabs renombrados:**
- "Catálogo" → "Mejorar mi tienda"
- "Mis consumibles" → "Mi saldo y usos"
- "Historial" → "Compras realizadas"

**Filtro unificado ai + seo_ai:**
- Nueva categoría virtual `ai_all` que agrupa ambas familias bajo "Inteligencia Artificial"
- El filtro interno sigue diferenciando la data, pero el usuario ve una sola categoría

**Agrupación por categoría:**
- Grid plano reemplazado por secciones con header de categoría (icono + nombre + cantidad)
- Orden: Inteligencia Artificial → Capacidad → Servicios → Contenido → Media

**Botón Comprar en cards:**
- Nuevo botón primario "Comprar" directo en cada card (antes solo había "Ver detalle")
- Respeta bloqueos por plan y policy

**Hero IA con saldo:**
- AiBanner muestra saldo actual de usos IA y SEO AI desde `usePlanLimits()`
- Botón "Comprar más usos" que filtra a categoría IA

**Diálogo de confirmación pre-compra:**
- Nuevo `ConfirmModal` antes de redirigir a Mercado Pago
- Muestra: nombre de la mejora, precio, tipo de compra, beneficio principal

**Tipografía mínima:**
- 12 styled components ajustados: mínimo 0.74rem en badges, 0.78rem en labels, 0.82rem en texto

**Accesibilidad:**
- `role="tablist"`, `role="tab"`, `aria-selected` en tabs
- `role="group"`, `aria-label` en secciones de categoría
- `role="dialog"`, `role="alertdialog"`, `role="banner"` donde corresponde
- `aria-live="polite"` en banner de éxito
- `aria-label` descriptivos en búsqueda y botones

### addonLabels.js
- Agregado `ai_store_dna: 'Contexto de Tienda IA'`

### MyConsumables.jsx
- Error handling: catch con mensaje visible + botón Reintentar (antes silencioso)
- Título renombrado a "Mi saldo y usos"
- StatusBadge tipografía: 0.72rem → 0.78rem

### PurchaseHistory.jsx
- Error handling: catch con mensaje visible + botón Reintentar (antes silencioso)
- Título renombrado a "Compras realizadas"
- StatusPill tipografía: 0.72rem → 0.78rem
- Th tipografía: 0.78rem → 0.82rem

## Plan de referencia

`novavision-docs/plans/PLAN_ADDON_STORE_UX_REDESIGN.md`

## Validación

- `npm run build` → OK (6.78s)

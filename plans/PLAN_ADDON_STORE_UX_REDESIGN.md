# Plan: Rediseño UX del AddonStoreDashboard

## Contexto

El AddonStoreDashboard actual presenta 20 problemas UX identificados por auditoría QA + UX.
El problema principal: **usuarios de 50+ años no encuentran la compra de créditos IA**, la información
está desorganizada, la tipografía es chica y no hay categorización visual clara.

## Diagnóstico

| Severidad | Cantidad | Ejemplos |
|-----------|:--------:|---------|
| Crítico | 1 | Créditos IA no descubribles |
| Alto | 5 | Sin botón comprar en cards, tipografía <0.82rem, sin agrupación, impacto oculto, errores silenciosos |
| Medio | 9 | Tabs confusos, sin confirmación pre-compra, saldo no visible, contraste bajo |
| Bajo | 3 | Falta ARIA labels, navegación por teclado incompleta |

---

## Fase 1 — Tabs, Labels y Tipografía

### 1A. Renombrar tabs

```
Antes:    "Catálogo"          | "Mis consumibles"    | "Historial"
Después:  "Mejorar mi tienda" | "Mi saldo y usos"   | "Compras realizadas"
```

**Por qué:** "Catálogo" y "Mis consumibles" son términos técnicos. Los nuevos nombres comunican
beneficio ("mejorar") y estado ("mi saldo") en lenguaje que un no-técnico entiende.

**Archivo:** `web/src/components/admin/AddonStoreDashboard/index.jsx` (L1099-L1107)

### 1B. Agregar ai_store_dna a addonLabels

**Archivo:** `web/src/components/admin/AddonStoreDashboard/addonLabels.js`

```javascript
ai_store_dna: 'Contexto de Tienda IA',
```

### 1C. Fix tipografía mínima 0.82rem

Componentes afectados:
- `IntroEyebrow`: 0.75rem → 0.82rem
- `FilterLabel`: 0.72rem → 0.82rem
- `FilterCount`: 0.68rem → 0.74rem
- `Badge`: 0.68rem → 0.74rem
- `MetaPill`: 0.72rem → 0.78rem
- `CompactSummaryTitle`: 0.72rem → 0.78rem
- `ImpactTitle`: 0.73rem → 0.78rem
- `PurchasePolicyTitle`: 0.73rem → 0.78rem
- `CouponLabel`: 0.7rem → 0.78rem
- `StatusBadge` (MyConsumables): 0.72rem → 0.78rem
- `StatusPill` (PurchaseHistory): 0.72rem → 0.78rem
- `Th` (PurchaseHistory): 0.78rem → 0.82rem
- `PlanPill`: 0.7rem → 0.76rem

### 1D. Fusionar ai + seo_ai en filtro "Inteligencia Artificial"

En los filter pills, mostrar ambas familias como una sola categoría visual.
Internamente siguen siendo familias distintas en la data, pero el filtro
`filterFamily === 'ai_all'` filtra `family === 'ai' || family === 'seo_ai'`.

**Cambio:** Agregar lógica de filtro combinado `ai_all` que agrupa ambas familias.

---

## Fase 2 — Cards con botón Comprar y agrupación por sección

### 2A. Botón "Comprar" directo en la card

Agregar `AdminButton $variant="primary"` al `Actions` div de cada card:
- Si está bloqueado por plan → disabled, texto "Requiere {plan}"
- Si está bloqueado por policy → disabled, texto "Límite alcanzado"
- Si `buying === addon_key` → loading, texto "Comprando..."
- Normal → "Comprar"

### 2B. Agrupación por categoría con headers de sección

En lugar de un grid plano, renderizar los addons agrupados por familia con un header
de sección antes de cada grupo:

```
┌─────────────────────────────────────────────┐
│ 🤖 Inteligencia Artificial (5 mejoras)      │
│ ┌──────┐ ┌──────┐ ┌──────┐ ┌──────┐ ┌────┐ │
│ │ Card │ │ Card │ │ Card │ │ Card │ │Card│ │
│ └──────┘ └──────┘ └──────┘ └──────┘ └────┘ │
├─────────────────────────────────────────────┤
│ 📈 Capacidad (3 mejoras)                    │
│ ┌──────┐ ┌──────┐ ┌──────┐                 │
│ │ Card │ │ Card │ │ Card │                  │
│ └──────┘ └──────┘ └──────┘                  │
├─────────────────────────────────────────────┤
│ 🖼️ Media (2 mejoras)                        │
│ ┌──────┐ ┌──────┐                           │
│ │ Card │ │ Card │                            │
│ └──────┘ └──────┘                            │
└─────────────────────────────────────────────┘
```

**Lógica:** `groupedAddons = Object.groupBy(filteredAddons, a => mergedFamily(a.family))`

Familias `ai` y `seo_ai` se agrupan juntas bajo "Inteligencia Artificial".

### 2C. Impacto visible en card

Mover el `CompactSummary` ("Qué incluye") antes de las `Actions` para que se vea
sin abrir el modal. Ya existe, solo reordenar para mayor visibilidad.

---

## Fase 3 — Hero IA con saldo, Confirmación y Accesibilidad

### 3A. Hero de IA con saldo actual

Transformar el `AiBanner` existente para mostrar el saldo de créditos IA actual:

```
┌──────────────────────────────────────────────────┐
│ 🤖  Potenciá tu tienda con IA                    │
│     Descripciones, fotos, FAQs y más automáticos │
│                                                  │
│     Tu saldo: 45 usos IA disponibles             │
│                                                  │
│     [Comprar más usos]                           │
└──────────────────────────────────────────────────┘
```

**Datos:** Usar `usePlanLimits()` que ya retorna `ai_credits` y `seo_ai_credits`.

### 3B. Diálogo de confirmación pre-compra

Antes de redirigir a MP, mostrar un `ConfirmDialog` con resumen:

```
┌──────────────────────────────────────┐
│ Confirmar compra                     │
│                                      │
│ Vas a comprar:                       │
│ "Pack 100 usos IA - Descripciones"   │
│                                      │
│ Precio: $14.900                      │
│ Tipo: Compra única                   │
│                                      │
│ Se te redirigirá a Mercado Pago.     │
│                                      │
│  [Cancelar]  [Confirmar y pagar]     │
└──────────────────────────────────────┘
```

**Implementación:** Estado `confirmAddon` que almacena el addon seleccionado para
confirmar. `handleBuy` pasa a ser el paso post-confirmación.

### 3C. Errores visibles

Cambiar `catch {}` (silent fail) en `MyConsumables` y `PurchaseHistory` por
`setError(msg)` con render de `AdminErrorState`.

### 3D. ARIA labels y accesibilidad

- `role="tablist"` en `TabBar`, `role="tab"` en cada `Tab`, `aria-selected`
- `role="group"` y `aria-label` en cada sección de categoría
- `aria-label` descriptivos en `FilterPill`, `SearchField`
- `aria-live="polite"` en el banner de éxito y errores

---

## Archivos a modificar

| Archivo | Cambios |
|---------|---------|
| `web/src/components/admin/AddonStoreDashboard/index.jsx` | Tabs, filtros, cards, hero, confirmación, ARIA |
| `web/src/components/admin/AddonStoreDashboard/MyConsumables.jsx` | Error handling, tipografía |
| `web/src/components/admin/AddonStoreDashboard/PurchaseHistory.jsx` | Error handling, tipografía |
| `web/src/components/admin/AddonStoreDashboard/addonLabels.js` | Agregar ai_store_dna |

## Verificación

1. `npm run build` en web → OK
2. Tabs muestran nombres claros
3. Cards tienen botón "Comprar" directo
4. Addons agrupados por categoría con headers
5. Hero IA muestra saldo actual
6. Confirmación aparece antes de redirigir a MP
7. Errores se muestran al usuario
8. Tipografía mínima >= 0.74rem en badges, >= 0.78rem en labels, >= 0.82rem en texto

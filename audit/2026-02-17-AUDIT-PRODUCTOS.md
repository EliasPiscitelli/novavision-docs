# 🔍 Auditoría QA — Módulo "Productos" NovaVision

**Fecha:** 2026-02-17  
**Auditor:** QA Lead Agent  
**Rama API:** `feature/automatic-multiclient-onboarding`  
**Rama Web:** `feature/multitenant-storefront`  
**Alcance:** CRUD manual, Excel export/import, sistema de opciones (sizes), envíos, PDP, checkout/orden  

---

## 1. Resumen Ejecutivo

Se auditó de punta a punta el módulo de productos del dashboard admin de NovaVision, abarcando creación/edición manual, tabla de gestión, descarga/carga masiva vía Excel, el nuevo sistema de opciones (option_sets para talles/colores), envíos, promociones, PDP (Product Detail Page) y persistencia en carrito/orden.

**Hallazgos críticos (P0):** 2  
**Hallazgos importantes (P1):** 8  
**Hallazgos menores (P2):** 7  

Los dos P0 son:
1. **Crash en PDP** para productos sin `option_mode = 'option_set'`: referencia a variables no declaradas (`sortedSizes`, `selectedSize`) que generan `ReferenceError` en runtime.
2. **Excel import sin validación de datos negativos ni requeridos**: precios negativos, stock negativo y productos sin nombre se importan silenciosamente, corrompiendo datos.

Además, existe una **deuda técnica significativa** en la coexistencia del sistema legacy (campos `sizes`/`colors` como strings CSV) y el nuevo sistema (`option_sets`). La tabla admin sigue mostrando columnas legacy vacías, el formulario tiene campos muertos, y el Excel no contempla el nuevo sistema de opciones.

---

## 2. FASE 0 — Mapa de la Verdad

### 2.1 Mapa de campos: DB → API → UI → Excel

| # | Campo DB | Tipo DB | Requerido | API (payload) | UI Form | UI Tabla | Excel Export | Excel Import | PDP | Notas |
|---|---|---|---|---|---|---|---|---|---|---|
| 1 | `id` | UUID PK | Sí (auto) | id | — (oculto) | ✅ | ✅ | ✅ (upsert key) | — | Si no es UUID válido en import → genera nuevo |
| 2 | `client_id` | UUID FK | Sí | — (middleware) | — | — | — | — | — | Inyectado por TenantContext |
| 3 | `name` | text | Sí | name | ✅ req | ✅ | ✅ | ✅ | ✅ | **Import NO valida required** |
| 4 | `description` | text | Sí | description | ✅ req | ✅ | ✅ | ✅ | ✅ (tab) | |
| 5 | `sku` | text | No | sku | ✅ req (UI) | ✅ | ✅ | ✅ | — | UI lo marca required, DB no |
| 6 | `filters` | text | No | filters | ✅ req (UI) | ✅ | ✅ | ✅ | — | Palabras clave para búsqueda |
| 7 | `originalPrice` | numeric | Sí | originalPrice | ✅ req, min 0.01 | ✅ | ✅ | ✅ | ✅ | **camelCase en DB** |
| 8 | `discountedPrice` | numeric | No | discountedPrice | ✅ | ✅ | ✅ | ✅ | ✅ | Si > 0 y < original → "en oferta" |
| 9 | `currency` | text | No | currency | ✅ (default ARS) | ✅ | ✅ | ✅ | — | **Import NO valida valores** |
| 10 | `available` | boolean | Sí | available | ✅ checkbox | ✅ | ✅ (Sí/No) | ✅ | — | Visibilidad pública |
| 11 | `quantity` | integer | Sí | quantity | ✅ req | ✅ | ✅ | ✅ | ✅ (stock) | **Import NO valida negativo** |
| 12 | `material` | text | No | material | ✅ req (UI) | ✅ | ✅ | ✅ | ✅ (tab) | UI lo marca required |
| 13 | `promotionTitle` | text | No | promotionTitle | ✅ | ✅ | ✅ | ✅ | ✅ (banner) | |
| 14 | `promotionDescription` | text | No | promotionDescription | ✅ | ✅ | ✅ | ✅ | ✅ (tab) | |
| 15 | `discountPercentage` | numeric | No | discountPercentage | ✅, 0–100 | ✅ | ✅ ("X%") | ✅ (strip %) | ✅ (badge) | |
| 16 | `validFrom` | date | No | validFrom | ✅ datepicker | ✅ | ✅ | ✅ | ✅ (tab) | **Sin validación server de rango** |
| 17 | `validTo` | date | No | validTo | ✅ datepicker | ✅ | ✅ | ✅ | ✅ (tab) | **Sin validación server de rango** |
| 18 | `featured` | boolean | No | featured | ✅ checkbox | ✅ | ✅ (Sí/No) | ✅ | — | Destacado |
| 19 | `bestSell` | boolean | No | bestSell | ✅ checkbox | ✅ | ✅ (Sí/No) | ✅ | — | Más vendido |
| 20 | `sendMethod` | boolean | No | sendMethod | ✅ checkbox | ✅ | ✅ (Sí/No) | ✅ | — | Flag "envío disponible" per-product |
| 21 | `tags` | text | No | tags | ✅ CSV | ✅ | ✅ | ✅ | ✅ (badges) | Comma-separated |
| 22 | `imageUrl` | jsonb | No | files (multipart) | ✅ upload | — | ❌ | ❌ | ✅ | Array de {url, order} |
| 23 | `image_variants` | jsonb | No | — (server gen) | — | — | ❌ | ❌ | ✅ | Variantes optimizadas |
| 24 | `weight_grams` | integer | No | weightGrams | ✅ (opcional) | ❌ | ❌ | ❌ | — | **Falta en Excel y tabla** |
| 25 | `slug` | text | No | — (auto) | — | — | ❌ | ❌ | ✅ (URL) | |
| 26 | `option_mode` | text | No | option_mode | ✅ select | ❌ | ❌ | ❌ | ✅ | `'none'` o `'option_set'` |
| 27 | `option_set_id` | UUID FK | No | option_set_id | ✅ (condicional) | ❌ | ❌ | ❌ | ✅ | FK a option_sets |
| 28 | `option_config` | jsonb | No | option_config | ❌ | ❌ | ❌ | ❌ | — | Override inline (sin UI) |
| 29 | `sizes` | — | — | — | ✅ (MUERTO) | ✅ (vacío) | ❌ | ❌ | — | **LEGACY, no se persiste** |
| 30 | `colors` | — | — | — | ✅ (MUERTO) | ✅ (vacío) | ❌ | ❌ | — | **LEGACY, no se persiste** |
| 31 | `created_at` | timestamptz | Sí (auto) | — | — | — | ❌ | — | — | |
| 32 | `updated_at` | timestamptz | Sí (auto) | — | — | — | ❌ | — | — | Trigger auto-update |
| 33 | `original_price` | numeric | — | — | — | — | — | — | — | Alias snake_case (migración) |
| 34 | `discounted_price` | numeric | — | — | — | — | — | — | — | Alias snake_case (migración) |
| 35 | *categorías* | M:N | No | categoryIds[] | ✅ multi-select | ✅ | ✅ (CSV nombres) | ✅ (CSV nombres) | ✅ | Via `product_categories` |

### 2.2 Diagrama de flujo de datos

```
┌─────────────────────────────────────────────────────────────────┐
│                     FLUJO DE DATOS — PRODUCTOS                   │
├─────────────────────────────────────────────────────────────────┤
│                                                                   │
│  ┌──────────────┐     FormData (JSON + files)     ┌──────────┐  │
│  │  UI Form     │ ──────────────────────────────▶ │ API      │  │
│  │  (Admin)     │                                  │ Controller│  │
│  └──────────────┘                                  └────┬─────┘  │
│                                                         │         │
│  ┌──────────────┐     Supabase JS SDK               ┌──┴──────┐ │
│  │  UI Tabla    │ ◀─── GET /products ────────────── │ Service  │ │
│  │  (Admin)     │                                    │ (CRUD)   │ │
│  └──────────────┘                                    └────┬─────┘ │
│                                                           │       │
│  ┌──────────────┐     xlsx npm                        ┌──┴─────┐ │
│  │  Excel       │ ◀─── GET /products/download ──── │ DB      │ │
│  │  (Descarga)  │                                    │ Supabase│ │
│  └──────┬───────┘                                    └──┬──────┘ │
│         │                                                ▲       │
│         ▼ (editar)                                       │       │
│  ┌──────────────┐     POST /products/upload/excel        │       │
│  │  Excel       │ ──────────────────────────────────────────┘    │
│  │  (Subida)    │  upsert batch 50 + categorías auto-create     │
│  └──────────────┘                                                │
│                                                                   │
│  ┌──────────────┐     GET /products/:id (+ resolved_options)     │
│  │  PDP         │ ◀─── con option_set resuelto ─────────────────│
│  │  (Comprador) │                                                │
│  └──────┬───────┘                                                │
│         │ addToCart(productId, qty, selectedOptions)              │
│         ▼                                                        │
│  ┌──────────────┐     selected_options + options_hash            │
│  │  Cart        │ ──── POST /api/cart ──────────────────────────│
│  │  (cart_items) │                                               │
│  └──────┬───────┘                                                │
│         │ checkout                                               │
│         ▼                                                        │
│  ┌──────────────┐     order_items JSON (snapshot) con            │
│  │  Orden       │ ──── selected_options preservadas ────────────│
│  │  (orders)    │                                                │
│  └──────────────┘                                                │
└─────────────────────────────────────────────────────────────────┘
```

### 2.3 Sistema de Opciones (Sizes) — Arquitectura actual

```
┌────────────────────────────────────────────────────────────────┐
│                     OPTION SETS SYSTEM                          │
├────────────────────────────────────────────────────────────────┤
│                                                                  │
│  option_sets (tabla)                                             │
│  ├─ id, client_id (NULL = preset global), code, name            │
│  ├─ type: 'apparel' | 'footwear' | 'accessory' | 'generic'     │
│  ├─ system: 'EU' | 'US' | 'UK' | 'cm' | null                   │
│  └─ is_preset: true (global) | false (custom del tenant)        │
│                                                                  │
│  option_set_items (tabla)                                        │
│  ├─ option_set_id FK, value, label, position                    │
│  └─ metadata: { hex?: string, equivalent?: {} }                 │
│                                                                  │
│  size_guides (tabla)                                             │
│  ├─ client_id, option_set_id?, product_id?                      │
│  ├─ columns: ["Talle", "Pecho (cm)", "Cintura (cm)"]            │
│  └─ rows: [{ label: "S", values: ["88-92", "72-76"] }]          │
│                                                                  │
│  products.option_mode = 'none' | 'option_set'                   │
│  products.option_set_id FK → option_sets                         │
│                                                                  │
│  En GET /products/:id → resolved_options =                       │
│    { source: 'option_set', option_set: {...}, items: [...] }     │
│                                                                  │
│  LEGACY (MUERTO):                                                │
│  products.sizes → NO existe en ALLOWED_FIELDS ni en DB           │
│  products.colors → NO existe en ALLOWED_FIELDS ni en DB          │
│  UI Form: campos registrados pero NO enviados en submit          │
│  UI Tabla: columnas "Tamaños" y "Colores" → siempre vacías      │
└────────────────────────────────────────────────────────────────┘
```

### 2.4 Envíos — Arquitectura actual

| Aspecto | Valor |
|---|---|
| **Nivel de config** | Per-tenant (global por tienda), NO per-product |
| **Campo `sendMethod` en producto** | Boolean. Solo flag de "envío disponible" (badge decorativo) |
| **Métodos disponibles** | `delivery` (a domicilio), `pickup` (retiro en local), `arrange` (coordinar WhatsApp) |
| **Pricing modes** | `flat` (costo fijo), `zone` (por CP/provincia), `provider_api` (Andreani/OCA/Correo Argentino) |
| **`weight_grams` en producto** | Se usa para cotización con provider_api. Default 500g si null |
| **Tabla admin** | Columna "Método de Envío" muestra Sí/No (confuso — no es el método, es un flag) |
| **Excel** | Columna "Método_Envío" exporta Sí/No (confuso) |
| **PDP** | `<ShippingEstimator>` que cotiza via `POST /shipping/quote` (no usa `sendMethod` del producto) |

### 2.5 Promociones — Arquitectura actual

| Aspecto | Valor |
|---|---|
| **Modelo** | Inline en producto (no hay entidad separada de promos) |
| **Precio final** | Si `discountedPrice > 0 && < originalPrice` → se muestra como precio final |
| **Display** | Precio original tachado + precio promo + badge "XX% OFF" |
| **Vigencia (`validFrom`/`validTo`)** | Almacenada pero **NO validada server-side**. El filtro `onSale` solo verifica `discountedPrice > 0` |
| **Impacto** | Promo "vencida" sigue mostrándose como activa → **riesgo de negocio** |

---

## 3. Matriz de Pruebas

### 3.1 CRUD Manual

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| C01 | Crear producto mínimo | Form: name, sku, filters, material, description, originalPrice, quantity, 1 imagen → Guardar | Se crea, aparece en tabla con todos los valores | ⚠️ Verificar | — |
| C02 | Crear producto con option_set | Seleccionar option_mode="option_set", elegir preset "Ropa XS-XL" → Guardar | Se persiste option_set_id, PDP muestra selector de talles | ⚠️ Verificar | — |
| C03 | Crear producto con promo | Completar promotionTitle, discountedPrice < originalPrice, validFrom < validTo → Guardar | PDP muestra banner promo + precio tachado | ⚠️ Verificar | — |
| C04 | Crear producto stock=0 | quantity=0 → Guardar | PDP muestra "Sin stock", botón agregar deshabilitado | ⚠️ Verificar | — |
| C05 | Editar solo precio | Cambiar originalPrice → Guardar | Solo cambia precio, demás campos intactos | ⚠️ Verificar | — |
| C06 | Editar toggles | Cambiar featured/bestSell/available → Guardar | Cambia solo los toggles, sin side effects | ⚠️ Verificar | — |
| C07 | Editar option_set | Cambiar de preset A a preset B → Guardar | Cambia vinculación, PDP muestra nuevos items | ⚠️ Verificar | — |
| C08 | Editar sin tocar imágenes | Cambiar nombre → Guardar | Imágenes se preservan (no se borran) | ⚠️ Verificar | — |

### 3.2 Tabla y Búsqueda

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| T01 | Columnas "Tamaños" y "Colores" | Abrir tabla, revisar columnas | Vacías para todos los productos (legacy muerto) | **HALLAZGO P1** | P1 |
| T02 | Columna "Método de Envío" | Ver valor en tabla | Muestra "Sí/No" (confuso, debería decir algo como "Envío habilitado") | **HALLAZGO P2** | P2 |
| T03 | Buscar por nombre | Escribir nombre parcial en buscador | Filtra correctamente con ILIKE | ⚠️ Verificar | — |
| T04 | Buscar por SKU | Escribir SKU en buscador | Filtra correctamente | ⚠️ Verificar | — |
| T05 | Paginación | Navegar páginas con >10 productos | No duplica ni omite filas | ⚠️ Verificar | — |
| T06 | Formato de precios | Ver columnas de precio | Muestra con formato moneda correcto | ⚠️ Verificar | — |
| T07 | Formato de fechas | Ver columnas Desde/Hasta | Formato legible (no ISO crudo) | ⚠️ Verificar | — |
| T08 | Overflow en descripción larga | Producto con descripción >500 chars | No rompe layout de celda | ⚠️ Verificar | — |

### 3.3 Excel Export

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| E01 | Descarga completa | Click "Descargar Productos" | Se descarga `productos.xlsx` con todas las filas | ⚠️ Verificar | — |
| E02 | Columnas presentes | Abrir Excel, revisar headers | 22 columnas (ID a Categorías) | ⚠️ Verificar | — |
| E03 | weight_grams ausente | Buscar columna de peso | **NO existe en Excel** | **HALLAZGO P1** | P1 |
| E04 | option_mode/option_set_id ausente | Buscar columnas de opciones | **NO existen en Excel** | **HALLAZGO P1** | P1 |
| E05 | Booleanos consistentes | Revisar columnas Disponible/Destacado/Más_Vendido/Método_Envío | Todos usan "Sí"/"No" | ⚠️ Verificar | — |
| E06 | Porcentaje con % | Revisar Porcentaje_Descuento | Formato "X%" (string) | ⚠️ Verificar | — |
| E07 | Fechas | Revisar Válido_Desde/Hasta | Formato consistente | ⚠️ Verificar | — |
| E08 | Categorías como CSV | Revisar columna Categorías | Nombres separados por coma | ⚠️ Verificar | — |

### 3.4 Excel Import

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| I01 | Roundtrip sin cambios | Descargar → Subir mismo archivo | 0 cambios efectivos, timestamps NO se modifican innecesariamente | ⚠️ Verificar (probable que sí se modifiquen por upsert) | P2 |
| I02 | Update precio | Cambiar Precio_Original de 3 productos → Subir | Solo cambia el precio de esos 3 | ⚠️ Verificar | — |
| I03 | Update stock | Cambiar Cantidad → Subir | Stock actualizado en DB, PDP refleja cambio | ⚠️ Verificar | — |
| I04 | Crear nuevo (sin ID) | Fila sin ID, con nombre/sku/precio → Subir | Se genera UUID nuevo, se crea producto | ⚠️ Verificar | — |
| I05 | Precio negativo | Fila con Precio_Original = -100 → Subir | **Se importa sin error** | **HALLAZGO P0** | P0 |
| I06 | Stock negativo | Fila con Cantidad = -5 → Subir | **Se importa sin error** | **HALLAZGO P0** | P0 |
| I07 | Moneda inválida | Fila con Moneda = "XYZ" → Subir | **Se importa sin error** | **HALLAZGO P1** | P1 |
| I08 | Fecha Desde > Hasta | validFrom > validTo → Subir | **Se importa sin error** | **HALLAZGO P1** | P1 |
| I09 | Nombre vacío | Fila sin Nombre → Subir | **Se importa sin error (campo required en UI pero no en import)** | **HALLAZGO P1** | P1 |
| I10 | Categoría inexistente | Categorías = "CategoríaInventada" → Subir | Se crea automáticamente la categoría | ⚠️ Diseño intencional, pero **riesgo de typos** | P2 |
| I11 | Reporte de errores | Provocar fallo en 1 fila de 10 → Subir | Reporte indica fila fallida + filas exitosas | ⚠️ Verificar | — |
| I12 | Estrategia de match | ¿Por ID? ¿Por SKU? | **Solo por ID (UUID)**, no por SKU | **HALLAZGO P1** — un SKU duplicado con ID diferente crea un duplicado | P1 |

### 3.5 PDP

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| P01 | PDP con option_set (ropa) | Abrir PDP de producto con option_mode='option_set' tipo apparel | Selector de talles como botones, guía de talles link | ⚠️ Verificar | — |
| P02 | PDP con option_set (color) | Producto con option_set tipo color | Selector con círculos coloreados (hex) | ⚠️ Verificar | — |
| P03 | PDP sin option_set (legacy) | Producto con option_mode='none' | **CRASH: ReferenceError sortedSizes** | **HALLAZGO P0** | P0 |
| P04 | PDP stock=0 | Producto con quantity=0 | Dot rojo "Sin stock", botón deshabilitado | ⚠️ Verificar | — |
| P05 | PDP promo activa | Producto con discountedPrice < originalPrice | Precio original tachado + precio promo + badge "% OFF" | ⚠️ Verificar | — |
| P06 | PDP promo vencida | Producto con validTo < hoy pero discountedPrice activo | **Promo sigue mostrándose como activa** | **HALLAZGO P1** | P1 |
| P07 | Add to cart con opción seleccionada | Seleccionar talle M → Agregar | Cart item tiene selected_options: [{type:'size', value:'M'}] | ⚠️ Verificar | — |
| P08 | Add to cart sin opción cuando se requiere | option_mode='option_set', no seleccionar nada → Agregar | Botón deshabilitado ("Selecciona una opción") | ⚠️ Verificar | — |
| P09 | Shipping estimator | Ingresar CP → Calcular | Muestra costo y tiempo estimado | ⚠️ Verificar | — |
| P10 | Rating hardcodeado | Ver sección de rating | Muestra 4.8 estrellas sin reviews reales | **HALLAZGO P2** | P2 |

### 3.6 Checkout/Orden

| # | Caso | Pasos | Esperado | Resultado | Sev |
|---|---|---|---|---|---|
| K01 | Opciones en cart_items | Agregar producto con talle M → Ver carrito | Muestra "Talle: M" debajo del producto | ⚠️ Verificar | — |
| K02 | Opciones en orden | Completar checkout → Ver orden en admin | order_items incluye selected_options del cart snapshot | ⚠️ Verificar | — |
| K03 | Modificar producto post-orden | Cambiar precio/talle después de una venta → Ver orden histórica | Orden preserva snapshot original (precios/opciones no cambian) | ⚠️ Verificar | — |
| K04 | Método de envío mixto | 2 productos: uno con sendMethod=true, otro false → Checkout | No debería generar inconsistencia (sendMethod es decorativo) | ⚠️ Verificar | — |

---

## 4. Hallazgos Detallados (P0 / P1 / P2)

### 🔴 P0-001: Crash en PDP para productos sin option_set

**Severidad:** P0 — Bloqueante  
**Componente:** Web Storefront → ProductPage/index.jsx (~línea 735)

**Pasos para reproducir:**
1. Crear (o tener) un producto con `option_mode = 'none'` (o sin el campo seteado).
2. Navegar a la PDP de ese producto en la tienda.
3. Observar la consola del navegador.

**Comportamiento actual:**  
El botón "Agregar al carrito" evalúa:
```jsx
disabled={
  (product.option_mode === 'option_set'
    ? resolvedOptionGroups.length > 0 && selectedOptions.length === 0
    : sortedSizes.length > 0 && !selectedSize  // ← ReferenceError
  ) || stock <= 0 || adding
}
```
`sortedSizes` y `selectedSize` **no están declaradas** en el componente. Si `option_mode !== 'option_set'`, se ejecuta la rama del ternario que las referencia → `ReferenceError: sortedSizes is not defined` → **la PDP entera crashea** (React Error Boundary o pantalla blanca).

**Comportamiento esperado:**  
Para productos sin opciones, el botón debería estar habilitado (si hay stock) sin requerir selección de talle.

**Impacto:** Cualquier producto legacy o producto nuevo sin option_set vinculado genera una PDP rota. El comprador no puede ver ni comprar el producto.

**Recomendación:**
```jsx
// Reemplazar la línea del ternario con:
disabled={
  (product.option_mode === 'option_set'
    ? resolvedOptionGroups.length > 0 && selectedOptions.length === 0
    : false  // Sin opciones = no requiere selección
  ) || stock <= 0 || adding
}
```

---

### 🔴 P0-002: Excel import acepta datos inválidos sin validación

**Severidad:** P0 — Integridad de datos  
**Componente:** API → products.service.ts → `uploadProducts()`

**Pasos para reproducir:**
1. Descargar Excel de productos.
2. Modificar fila: `Precio_Original = -500`, `Cantidad = -10`, borrar `Nombre`.
3. Subir el archivo modificado.
4. Verificar en DB / tabla admin.

**Comportamiento actual:**  
La importación procesa la fila sin error. Se persiste:
- Precio negativo en DB → PDP muestra precio negativo.
- Stock negativo → lógica de "Sin stock" puede fallar (comparación `<= 0` podría interpetarse diferente a un stock válido).
- Producto sin nombre → fila en DB con `name = null` o vacío → tabla admin muestra celda vacía.

**Comportamiento esperado:**  
Validación por fila con rechazo y reporte:
- `originalPrice` debe ser > 0
- `quantity` debe ser >= 0
- `name` es requerido (no puede ser vacío/null)
- `currency` debe estar en la lista permitida (ARS, USD, etc.)
- `validFrom <= validTo` si ambos están presentes

**Impacto:** Un usuario de admin con un Excel mal formado (error de tipeo, fórmula rota, etc.) puede corromper datos de producción silenciosamente.

**Recomendación:**  
Agregar una función `validateProductRow(row, index)` que retorne errores por fila antes del upsert. Las filas inválidas se rechazan y se reportan; las válidas se importan.

---

### 🟡 P1-001: Columnas "Tamaños" y "Colores" en tabla admin son legacy muerto

**Severidad:** P1 — UX confusa  
**Componente:** Web → ProductDashboard  

**Detalle:** La tabla de gestión muestra columnas "Tamaños" y "Colores" que leen `product.sizes` y `product.colors`. Estos campos **no existen en DB, no se persisten, y no se envían desde el formulario**. Las columnas están siempre vacías.

**Impacto:** Confusión para el admin ("¿Por qué no se guardan mis talles?"). Espacio visual desperdiciado.

**Recomendación:**  
- Eliminar columnas "Tamaños" y "Colores" de la tabla.
- Reemplazar con una columna "Opciones" que muestre el nombre del `option_set` vinculado (si existe) o "Sin opciones".

---

### 🟡 P1-002: Excel no incluye campos del nuevo sistema de opciones

**Severidad:** P1 — Roundtrip roto  
**Componente:** API → Excel export/import  

**Detalle:** El Excel no exporta ni importa:  
- `option_mode` (none/option_set)  
- `option_set_id` (referencia al set)  
- `weight_grams` (peso para cotización de envío)  

Esto significa que un **roundtrip export→edit→import** pierde la vinculación del producto con sus opciones y su peso.

**Impacto:** Si un admin descarga, edita precios y re-sube, pierde la config de talles/opciones de todos los productos.

**Recomendación:**  
- Agregar columnas `Modo_Opciones`, `ID_Set_Opciones`, `Peso_Gramos` al Excel.
- En import: si `option_set_id` viene como UUID válido, validar que exista en DB.
- Si `option_mode` no viene, preservar el valor existente en DB (no pisar con 'none').

---

### 🟡 P1-003: Promos no respetan fecha de vigencia (validFrom/validTo)

**Severidad:** P1 — Riesgo de negocio  
**Componente:** API → Lógica de "en oferta"  

**Detalle:** El filtro `onSale` en `searchProducts()` solo verifica `discountedPrice > 0`. No compara contra `validFrom`/`validTo`. Un producto cuya promo venció el mes pasado sigue mostrándose como "en oferta".

**Impacto:** Productos vendidos a precio de promoción cuando la promo ya expiró → pérdida de margen para el cliente.

**Recomendación:**  
Agregar condición temporal:
```sql
AND (validFrom IS NULL OR validFrom <= NOW())
AND (validTo IS NULL OR validTo >= NOW())
```

---

### 🟡 P1-004: Match de import solo por ID, no por SKU

**Severidad:** P1 — Riesgo de duplicados  
**Componente:** API → `uploadProducts()`  

**Detalle:** La lógica de upsert solo usa `id` (UUID) como key de match. Si un usuario importa un Excel con un producto que tiene el mismo SKU pero un ID diferente (o sin ID), se crea un duplicado.

**Impacto:** Duplicados accidentales de productos con el mismo SKU pero IDs diferentes.

**Recomendación:**  
Implementar match en cascada: `id` (si es UUID válido y existe en DB) → `sku` (si coincide con existente del mismo tenant) → crear nuevo.

---

### 🟡 P1-005: "Método de Envío" es confuso (boolean vs nombre de método)

**Severidad:** P1 — UX confusa  
**Componente:** UI tabla, Excel, formulario  

**Detalle:** El campo `sendMethod` es un **boolean** que indica "envío disponible", pero:
- La columna en tabla se llama "Método de Envío" (sugiere un valor como "A domicilio").
- El Excel exporta "Método_Envío: Sí/No".
- El formulario muestra un checkbox sin tooltip claro.
- El modelo real de envío es **global por tenant** (delivery/pickup/arrange), no per-product.

**Impacto:** Los admins creen que están configurando el "método" de envío del producto cuando solo están poniendo un flag genérico.

**Recomendación:**
- Renombrar a "Envío Habilitado" / "Envío Disponible" en tabla, Excel y form.
- Agregar tooltip: "Indica si este producto es elegible para envío. La configuración de métodos de envío se gestiona en la sección Envíos."

---

### 🟡 P1-006: Campos legacy (sizes/colors) en formulario no hacen nada

**Severidad:** P1 — UX confusa  
**Componente:** Web → ProductModal  

**Detalle:** El formulario de producto tiene campos `sizes` y `colors` (inputs de texto CSV) que:
- Se registran en react-hook-form con `register('sizes')` / `register('colors')`.
- No se incluyen en el objeto `updatedProduct` del `onSubmit`.
- No están en `ALLOWED_FIELDS` del backend.
- Se inicializan desde `product?.sizes` / `product?.colors` (que vienen como `undefined` o `null` de la DB).

**Impacto:** Un admin podría escribir talles "S, M, L" en el campo, guardar, y luego ver que no se persistió. Frustración y confusión.

**Recomendación:**
- Eliminar los campos legacy `sizes` y `colors` del formulario.
- Asegurar que el bloque de `option_mode` + `option_set_id` sea prominente y claro como reemplazo.

---

### 🟡 P1-007: import no valida fechas (from > to)

**Severidad:** P1 — Integridad de datos  
**Componente:** API → `uploadProducts()`  

**Detalle:** Si en Excel se pone `Válido_Desde = 2026-03-01` y `Válido_Hasta = 2026-01-01` (from > to), se importa sin error. Tampoco se valida el formato de fecha.

**Recomendación:** Validar que si ambas fechas están presentes, `validFrom <= validTo`. Rechazar fila con error descriptivo.

---

### 🟡 P1-008: Categorías auto-creadas por typo en import

**Severidad:** P1 — Riesgo de datos basura  
**Componente:** API → `uploadProducts()` → `resolveCategory()`  

**Detalle:** Si en el Excel se escribe `Categorías = "Remras"` (typo de "Remeras"), el import crea una categoría nueva "Remras" y vincula el producto a ella. No hay confirmación, warning ni sugerencia de "similares existentes".

**Recomendación:**
- En el reporte de import, indicar categorías que fueron **creadas** (no solo vinculadas).
- Opcionalmente: fuzzy match contra existentes y warning si la similitud es > 80%.

---

### 🟢 P2-001: Roundtrip export→import actualiza timestamps innecesariamente

**Severidad:** P2  
**Detalle:** El upsert por batch siempre ejecuta un update (incluso si los datos son idénticos), lo que dispara el trigger `updated_at = NOW()` en todas las filas tratadas.

**Recomendación:** Considerar comparar hash de datos antes de upsert para evitar writes innecesarios (optimización futura).

---

### 🟢 P2-002: Columnas camelCase en DB (originalPrice, discountedPrice, etc.)

**Severidad:** P2  
**Detalle:** Contra la convención PostgreSQL, varios campos usan camelCase. Ya hay aliases snake_case (`original_price`, `discounted_price`) pero no se migraron los datos.

**Recomendación:** En un refactor futuro, migrar a snake_case completo y usar transformadores en el service.

---

### 🟢 P2-003: Entity TypeORM desactualizada

**Severidad:** P2  
**Detalle:** `product.entity.ts` solo declara 5 campos (id, name, price, description, quantity). No se usa pero genera confusión para desarrolladores.

**Recomendación:** Eliminar o actualizar para reflejar el schema real.

---

### 🟢 P2-004: Rating hardcodeado en PDP (4.8 estrellas)

**Severidad:** P2  
**Detalle:** El PDP muestra `rating = 4.8` fijo sin sistema de reviews. Puede generar desconfianza en compradores.

**Recomendación:** Ocultar rating hasta implementar reviews, o mostrar "Nuevo" en vez de estrellas.

---

### 🟢 P2-005: Favoritos inconsistentes (PDP vs Card)

**Severidad:** P2  
**Detalle:** En ProductCard se usa `useFavorites` (context con persistencia en DB). En ProductPage se usa `useState` local (se pierde al recargar).

**Recomendación:** Unificar usando `useFavorites` en ambos.

---

### 🟢 P2-006: Preview de Excel no muestra diff vs DB

**Severidad:** P2  
**Detalle:** La previsualización muestra las primeras 20 filas del archivo como tabla plana. No indica qué productos son nuevos vs existentes, ni qué campos cambiaron.

**Recomendación:** Preview con columna "Acción" (Crear/Actualizar/Sin cambios) y resaltado de campos modificados.

---

### 🟢 P2-007: Endpoint remove-image sin guard explícito

**Severidad:** P2  
**Detalle:** `POST /products/remove-image` no tiene `@UseGuards(RolesGuard)` explícito. Si el guard global no cubre este endpoint, cualquier usuario autenticado podría borrar imágenes de productos.

**Recomendación:** Agregar `@Roles('admin', 'super_admin')` + `@UseGuards(RolesGuard)` explícito.

---

## 5. Recomendaciones Priorizadas

### ⚡ Quick Wins (1-2 días cada uno)

| # | Cambio | Impacto | Esfuerzo |
|---|---|---|---|
| QW-1 | **Fix P0-001:** Reemplazar `sortedSizes.length > 0 && !selectedSize` por `false` en PDP | Desbloquea productos sin option_set | 5 min |
| QW-2 | **Fix P1-001:** Eliminar columnas "Tamaños" y "Colores" de tabla admin; agregar "Opciones" | Limpia UX | 30 min |
| QW-3 | **Fix P1-005:** Renombrar "Método de Envío" → "Envío Habilitado" en tabla, Excel y form | Claridad | 30 min |
| QW-4 | **Fix P1-006:** Eliminar campos legacy `sizes` y `colors` del ProductModal | Limpia form | 15 min |
| QW-5 | **Fix P2-007:** Agregar guard a `remove-image` endpoint | Seguridad | 5 min |

### 🔧 Cambios Medianos (3-5 días)

| # | Cambio | Impacto | Esfuerzo |
|---|---|---|---|
| CM-1 | **Fix P0-002:** Agregar validación por fila en Excel import (precios, stock, required, currency, fechas) | Integridad de datos | 2 días |
| CM-2 | **Fix P1-002:** Agregar columnas option_mode, option_set_id, weight_grams a Excel | Roundtrip completo | 1 día |
| CM-3 | **Fix P1-003:** Implementar validación temporal de promos (validFrom/validTo) en API | Previene pérdida de margen | 1 día |
| CM-4 | **Fix P1-004:** Implementar match por SKU como fallback en Excel import | Previene duplicados | 1 día |
| CM-5 | **Fix P1-008:** Reporte de categorías creadas en import + warning de similares | Previene datos basura | 1 día |

### 🏗️ Cambios Estructurales (1+ semanas)

| # | Cambio | Impacto | Esfuerzo |
|---|---|---|---|
| CE-1 | Implementar DTOs con class-validator para create/update product (reemplazar `any`) | Type safety + validación automática | 3-5 días |
| CE-2 | Preview de Excel con diff vs DB (crear/actualizar/sin cambios) | UX de import profesional | 3-5 días |
| CE-3 | Plantilla Excel con dropdowns de validación (moneda, categorías existentes) | Previene errores de usuario | 2-3 días |
| CE-4 | Sistema de reviews real (reemplazar rating hardcodeado) | UX de comprador | 1-2 semanas |
| CE-5 | Migrar DB a snake_case completo + eliminar camelCase | Consistencia técnica | 1 semana |

---

## 6. Checklist DoD — "Módulo Productos Validado"

### Crítico (DEBE pasar para dar por validado)

- [ ] **P0-001 resuelto:** PDP no crashea para productos sin option_set
- [ ] **P0-002 resuelto:** Excel import rechaza precios negativos, stock negativo, nombre vacío
- [ ] Crear producto manual con todos los campos → se persiste y se ve en tabla + PDP
- [ ] Editar producto → campos no editados se preservan (especialmente imágenes y option_set)
- [ ] Excel roundtrip (export → import sin cambios) → no corrompe datos
- [ ] PDP muestra opciones (botones talle / círculos color) correctamente
- [ ] Add to cart con opción seleccionada → cart muestra selected_options
- [ ] Checkout → orden preserva snapshot con selected_options
- [ ] Stock=0 → PDP bloquea compra
- [ ] Envío: ShippingEstimator funciona en PDP

### Importante (DEBERÍA pasar)

- [ ] **P1-001:** Columnas legacy eliminadas de tabla
- [ ] **P1-002:** Excel exporta/importa option_mode, option_set_id, weight_grams
- [ ] **P1-003:** Promos expiradas (validTo < hoy) no se muestran como activas
- [ ] **P1-004:** Import por SKU como fallback (no solo por ID)
- [ ] **P1-005:** "Método de Envío" renombrado a "Envío Habilitado"
- [ ] **P1-006:** Campos legacy sizes/colors eliminados del formulario
- [ ] Excel import reporta errores por fila (no silencioso)
- [ ] Preview de Excel muestra resumen de filas válidas/inválidas

### Deseable (NICE-TO-HAVE)

- [ ] **P2-001:** Roundtrip no actualiza timestamps innecesariamente
- [ ] **P2-004:** Rating ocultado o reemplazado por "Nuevo"
- [ ] **P2-005:** Favoritos unificados (context en PDP y Card)
- [ ] **P2-006:** Preview con diff visual (crear/actualizar/sin cambios)
- [ ] Plantilla Excel con dropdowns de validación

---

## Anexo A — Dataset de Prueba Controlado (10 productos)

| # | Nombre | SKU | Precio | DescPrecio | Stock | option_mode | option_set | Promo | Featured | BestSell | sendMethod | Tags | Categorías | weight_grams |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| A | "Remera Básica" | REM-001 | 5000 | 3500 | 50 | option_set | Ropa XS-XL (apparel) | Sí (titulo+fechas válidas) | false | false | true | "algodón,básico" | "Remeras" | 200 |
| B | "Zapatillas Runner" | ZAP-001 | 45000 | — | 20 | option_set | Calzado EU 36-46 (footwear) | No | true | false | true | "running,deporte" | "Calzado" | 800 |
| C | "Cinturón Cuero" | CIN-001 | 8000 | — | 30 | none | — | No | false | false | false | "cuero" | "Accesorios" | 150 |
| D | "Vestido Fiesta" | VES-001 | 25000 | 20000 | 10 | option_set | Ropa XS-XL (apparel) | Sí (titulo+descripción+%descuento) | false | true | true | "fiesta,elegante" | "Vestidos,Ofertas" | 350 |
| E | "Gorra Branded" | GOR-001 | 3500 | — | 100 | none | — | No | true | false | false | "casual" | "Accesorios,Gorras" | 100 |
| F | "Pantalón Jogger" | PAN-001 | 15000 | 12000 | 0 | option_set | Ropa XS-XL (apparel) | Sí (con validTo = ayer → promo vencida) | false | false | true | "jogger,sport" | "Pantalones" | 400 |
| G | "Cartera Premium" | CAR-001 | 35000 | — | 5 | option_set | Colores (generic) | No | false | true | true | "premium,cuero" | "Carteras" | 600 |
| H | "Bufanda Invierno" | BUF-001 | 6000 | 4500 | 40 | none | — | Sí (sin fechas → siempre activa) | false | false | false | "invierno,lana,abrigo" | "Accesorios,Invierno,Bufandas" | 100 |
| I | "Botas Trekking" | BOT-001 | 55000 | — | 15 | option_set | Calzado EU 36-46 (footwear) | No | false | false | true | "trekking,outdoor" | "Calzado,Outdoor" | 1200 |
| J | "Set Accesorios" | SET-001 | 12000 | 9000 | 2 | none | — | Sí (validFrom=futuro → promo no vigente aún) | true | true | false | "set,regalo" | "Accesorios,Regalos" | 300 |

**Cobertura del dataset:**
- ✅ Con option_set tipo apparel (A, D, F)
- ✅ Con option_set tipo footwear (B, I)
- ✅ Con option_set tipo generic/color (G)
- ✅ Sin option_set (C, E, H, J) → **estos activan P0-001**
- ✅ Con promo activa y fechas válidas (A)
- ✅ Con promo vencida (F) → **activa P1-003**
- ✅ Con promo futura/no vigente aún (J)
- ✅ Con promo sin fechas (H)
- ✅ Stock=0 (F)
- ✅ Featured (B, E, J)
- ✅ BestSell (D, G, J)
- ✅ sendMethod true y false (mezcla)
- ✅ Tags múltiples (H: 3 tags)
- ✅ Categorías múltiples (D, H, I, J: 2-3 categorías)
- ✅ weight_grams variado (100-1200)

---

## Anexo B — Riesgos de Producto / Decisiones Pendientes

| # | Tema | Estado | Decisión necesaria | Impacto si no se resuelve |
|---|---|---|---|---|
| R1 | `sendMethod` → ¿eliminar o reconvertir? | Ambiguo | ¿Sigue siendo un flag útil dado que el envío es global por tenant? ¿Se usa solo como badge decorativo? | Confusión de admins |
| R2 | Vigencia de promos → ¿validar server-side o solo informar? | Sin validación | ¿Debe el backend filtrar promos vencidas automáticamente, o solo mostrar warning al admin? | Venta a precio descontado erróneo |
| R3 | Excel + opciones → ¿cómo representar option sets complejos? | Sin soporte | ¿Agregar columnas simples (mode + ID) o JSON? ¿Debe el import poder cambiar el option_set de un producto? | Pierde opciones en roundtrip |
| R4 | Variantes por opción (stock por talle) → `option_config.variants` | Parcialmente implementado (cart valida) | ¿Se gestiona desde admin? ¿Se importa desde Excel? | Stock global, no por variante |
| R5 | `sizes`/`colors` legacy → ¿migración o eliminación? | Muertos pero visibles | ¿Hay datos legacy en algún tenant que use estos campos? | Campos fantasma en UI |

---

*Fin del informe de auditoría. No se aplicaron cambios al código.*

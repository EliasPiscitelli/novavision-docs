# Sistema Completo de Talles y Medidas (Option Sets)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-16
- **Ramas:** 
  - API: `feature/automatic-multiclient-onboarding`
  - Web: `feature/multitenant-storefront` → cherry-pick a `develop` + `feature/onboarding-preview-stable`
  - Admin: `feature/automatic-multiclient-onboarding`

---

## Resumen

Implementación completa del sistema de **Talles y Medidas** para NovaVision, abarcando backend (API NestJS), storefront (Web React) y panel de administración NovaVision (Admin React). El sistema permite a cada tenant definir sets de opciones (talles, colores, etc.), asignarlos a productos, y que los compradores seleccionen variantes con control de stock por variante.

---

## Arquitectura de Datos

### Tablas nuevas (Multicliente DB)

| Tabla | Propósito |
|-------|-----------|
| `option_sets` | Define grupos de opciones (ej: "Talles Remeras", "Colores Básicos") |
| `option_set_items` | Items dentro de un set (ej: "S", "M", "L", "XL") |
| `size_guides` | Tablas de medidas con columnas/filas dinámicas |

### Columnas agregadas a `products`

| Columna | Tipo | Propósito |
|---------|------|-----------|
| `option_mode` | `text` | `'none'` \| `'option_set'` — modo de opciones del producto |
| `option_set_id` | `uuid` (FK → option_sets) | Set de opciones asignado |
| `option_config` | `jsonb` | Config de variantes: `{ variants: [{ options: [...], stock, sku }] }` |
| `size_guide_id` | `uuid` (FK → size_guides) | Guía de talles asignada |

### Columnas agregadas a `cart_items`

| Columna | Tipo | Propósito |
|---------|------|-----------|
| `selected_options` | `jsonb` | Opciones elegidas: `[{ key, value, label }]` |
| `options_hash` | `text` | Hash MD5 para deduplicar variantes en carrito |

### Columnas eliminadas (legacy)

- `products.sizes` (text[]) — reemplazado por option_sets
- `products.colors` (text[]) — reemplazado por option_sets

---

## Archivos Modificados/Creados

### Backend (API - templatetwobe)

**Módulo nuevo: `src/option-sets/`**
- `option-sets.module.ts` — Módulo NestJS
- `option-sets.controller.ts` — Endpoints REST
- `option-sets.service.ts` — Lógica de negocio (CRUD + filtros + size guides)
- `dto/create-option-set.dto.ts` — DTO de creación
- `dto/update-option-set.dto.ts` — DTO de actualización
- `dto/create-size-guide.dto.ts` — DTO de guía de talles

**Modificados:**
- `src/cart/cart.service.ts` — Validación de stock por variante via `option_config.variants`
- `src/app.module.ts` — Importa OptionSetsModule
- `src/products/products.service.ts` — Soporte option_mode/option_set_id/option_config en CRUD

**Migraciones ejecutadas:**
- `migrations/backend/20260216_option_sets_tables.sql` — Tablas + RLS + índices
- `migrations/backend/20260216_products_option_columns.sql` — Columnas en products
- `migrations/backend/20260216_cart_items_selected_options.sql` — Columnas en cart_items
- `migrations/backend/20260216_size_guides_table.sql` — Tabla size_guides
- `migrations/backend/20260216_drop_legacy_sizes_colors.sql` — Drop sizes/colors

### Frontend (Web - templatetwo)

**Componentes nuevos:**
- `src/components/OptionSetSelector.jsx` — Selector de opciones en PDP (botones tipo talle)
- `src/components/SizeGuideModal.jsx` — Modal con tabla de medidas en PDP
- `src/components/admin/OptionSetsManager.jsx` — CRUD de sets de opciones (admin tenant)
- `src/components/admin/SizeGuidesManager.jsx` — CRUD de guías de talles (admin tenant)
- `src/components/selects/OptionSetSelect.jsx` — Select de option_set para ProductModal
- `src/components/selects/SizeGuideSelect.jsx` — Select de size_guide para ProductModal

**Modificados:**
- `src/pages/ProductPage/index.jsx` — Integra OptionSetSelector + SizeGuideModal
- `src/pages/SearchPage/index.jsx` — Filtros por opciones en PLP
- `src/pages/SearchPage/FilterSidebar.jsx` — Sidebar con filtros de option_sets
- `src/pages/AdminDashboard/index.jsx` — Secciones optionSets + sizeGuides
- `src/components/ProductModal/index.jsx` — Campos option_mode, option_set_id, option_config, size_guide_id
- `src/context/CartProvider.jsx` — Pasa selectedOptions al addItem
- `src/hooks/cart/useCartItems.js` — Envía selectedOptions y expectedPrice al backend

### Admin (novavision)
_(Sin cambios en esta iteración — la gestión de option_sets del tenant se hace desde el admin del storefront)_

---

## Endpoints API

### Option Sets CRUD

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/option-sets` | Listar sets del tenant |
| `GET` | `/option-sets/:id` | Detalle de un set |
| `POST` | `/option-sets` | Crear set con items |
| `PUT` | `/option-sets/:id` | Actualizar set |
| `DELETE` | `/option-sets/:id` | Eliminar set |
| `GET` | `/option-sets/filters/available?categoryId=` | Filtros disponibles para PLP |
| `GET` | `/option-sets/product/:productId/options` | Opciones de un producto |

### Size Guides CRUD

| Método | Ruta | Descripción |
|--------|------|-------------|
| `GET` | `/option-sets/size-guides/list` | Listar guías del tenant |
| `GET` | `/option-sets/size-guides/by-context?optionSetId=&productId=` | Guía por contexto (producto > set > null) |
| `GET` | `/option-sets/size-guides/:id` | Detalle de una guía |
| `POST` | `/option-sets/size-guides` | Crear guía |
| `PUT` | `/option-sets/size-guides/:id` | Actualizar guía |
| `DELETE` | `/option-sets/size-guides/:id` | Eliminar guía |

---

## Flujo de Stock por Variante

1. Producto con `option_mode = 'option_set'` tiene `option_config.variants[]`
2. Cada variante: `{ options: ["S", "Rojo"], stock: 5, sku: "REM-S-R" }`
3. Al agregar al carrito, el frontend envía `selectedOptions` → backend genera `options_hash`
4. `cart.service.ts` busca la variante coincidente por `options_hash` y usa su `stock` individual
5. Si no hay variantes definidas, usa `product.quantity` como fallback (stock global)

---

## Seguridad (RLS)

Todas las tablas nuevas tienen:
- `server_bypass` para service_role
- `*_select_tenant` con `client_id = current_client_id()`  
- `*_write_admin` con `is_admin()` para escritura
- Índices por `client_id` y foreign keys

---

## Cómo Probar

### Crear un set de opciones (admin tenant)
1. Login como admin del tenant
2. Panel Admin → 🏷️ Opciones de Producto
3. Crear set "Talles" con items S, M, L, XL
4. Crear set "Colores" con items Rojo, Azul, Negro

### Asignar a producto
1. Panel Admin → Productos → Editar producto
2. Cambiar "Modo de opciones" a "Set de opciones"
3. Seleccionar el set creado
4. Configurar variantes con stock individual

### Guía de talles
1. Panel Admin → 📏 Guías de Talles
2. Crear guía con columnas (Talle, Pecho, Cintura) y filas (S: 90, 70, etc.)
3. Asignar guía al producto desde editor de producto

### Verificar en storefront
1. Abrir producto → ver selector de opciones (botones tipo talle)
2. Click "📐 Ver guía de talles" → modal con tabla de medidas
3. Seleccionar opciones → agregar al carrito
4. Verificar que el carrito muestra opciones seleccionadas
5. Verificar validación de stock por variante

---

## Riesgos / Notas

- **Migración irreversible**: Las columnas `sizes` y `colors` fueron eliminadas de `products`. Datos legacy no recuperables.
- **Stock por variante es opt-in**: Si no se definen variantes en `option_config`, usa stock global.
- **Hash de opciones**: Usa MD5 sobre las opciones ordenadas como string canónico. Cambiar el algoritmo requeriría re-hashear cart_items existentes.
- **Performance**: Filtros de PLP hacen JOINs a option_sets/option_set_items. Con catálogos muy grandes (>10k productos), considerar materializar filtros.

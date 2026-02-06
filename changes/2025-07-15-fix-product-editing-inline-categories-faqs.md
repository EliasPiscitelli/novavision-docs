# Fix: Edición de productos + Categorías/FAQs inline en panel Super Admin

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos modificados

### Backend (apps/api)
- `src/admin/admin.service.ts`
- `src/admin/admin.controller.ts`

### Frontend (apps/admin)
- `src/services/adminApi.js`
- `src/pages/AdminDashboard/ClientApprovalDetail.jsx`

---

## Resumen de cambios

### 1. Fix crítico: Productos sin ID (alias collision en Supabase)

**Problema:** La query de catálogo usaba `catalog_data:products(*, categories:categories(name))` como alias en un `select` sobre la tabla `clients`. Si `clients` tiene una columna `catalog_data` (JSONB), Supabase retorna esa columna en vez de la relación, causando que los productos lleguen sin `id`.

**Consecuencia:** `p.id` era `undefined` para TODOS los productos → `expandedProducts[undefined]` y `editingProducts[undefined]` afectaban todos simultáneamente → "Ver detalle" abría TODOS, editar mostraba los MISMOS datos, guardar fallaba con PATCH a `/products/undefined`.

**Solución:** Separé la query en:
1. `SELECT *` directo a `products WHERE client_id = X`
2. Query separada a `product_categories` + `categories` para armar el mapa de categorías
3. Productos llegan con `id` UUID correcto

### 2. Fix: updateAccountProduct siempre usa snake_case

La lógica anterior intentaba camelCase primero y después retry con snake_case si fallaba. Ahora siempre convierte a snake_case directamente → más confiable.

### 3. Nuevo: Eliminar producto desde panel admin

- `DELETE /admin/accounts/:accountId/products/:productId`
- Botón de eliminación (ícono trash) en cada producto

### 4. Nuevo: Categorías inline (CRUD)

- `GET /admin/accounts/:id/categories` → lista categorías de `completion_categories`
- `POST /admin/accounts/:id/categories` → crea categoría
- `DELETE /admin/accounts/:accountId/categories/:categoryId` → elimina
- Auto-refresca checklist (`client_completion_checklist.categories_count`)

### 5. Nuevo: FAQs inline (CRUD)

- `GET /admin/accounts/:id/faqs` → lista FAQs de `completion_faqs`
- `POST /admin/accounts/:id/faqs` → crea FAQ
- `DELETE /admin/accounts/:accountId/faqs/:faqId` → elimina
- Auto-refresca checklist (`client_completion_checklist.faqs_count`)

### 6. Frontend: Reemplazo de sección checklist

- **Eliminado:** Botón "Ir a completar" (navegaba a `/complete` que no funciona para super admin)
- **Mantenido:** Indicadores de completitud (qué falta para 100%)
- **Agregado:** Card inline de categorías con lista/crear/eliminar
- **Agregado:** Card inline de FAQs con lista/crear/eliminar

### 7. Frontend: Fix de renderizado de productos

- Variable `pid = p.id || \`idx-${i}\`` para key estable
- Botones "Ver", "Editar", "Eliminar" en header de cada producto
- Todas las referencias de estado (`editingProducts`, `expandedProducts`, `productSaving`, `productDeleting`) usan `pid`
- `saveProductChanges(realId, stateKey)` recibe ID real (API) + key de estado
- `startEditProduct(product, key)` acepta key override

---

## Por qué

1. Los 4 bugs de productos tenían una **causa raíz única**: alias collision en la query de Supabase que causaba `p.id === undefined`
2. El botón "Ir a completar" navegaba a la vista del CLIENTE, no del admin → no funcionaba
3. El super admin necesita poder agregar categorías/FAQs faltantes sin salir del panel

## Cómo probar

### Backend
```bash
cd apps/api && npm run start:dev
```

### Frontend
```bash
cd apps/admin && npm run dev
```

### Pasos
1. Ir a panel Super Admin → Aprobaciones pendientes → seleccionar un cliente
2. **Productos:**
   - Verificar que "Ver" expande UN solo producto (no todos)
   - Verificar que "Editar" muestra datos del producto correcto
   - Cambiar precio → "Guardar" → verificar que persiste
   - Click en trash → confirmar → verificar eliminación
3. **Categorías:**
   - En sección checklist, expandir "Categorías (0/4)" o similar
   - Escribir nombre → "Agregar" → verificar que aparece
   - Click en X → verificar eliminación
   - Verificar que el checklist se actualiza
4. **FAQs:**
   - Mismo flujo: expandir, agregar pregunta+respuesta, verificar

## Notas de seguridad

- Todos los endpoints nuevos están protegidos con `@UseGuards(SuperAdminGuard)`
- Las operaciones sobre la DB multi-tenant usan `DbRouterService` con `service_role`
- Delete de productos valida que el producto existe antes de eliminar
- No se exponen SERVICE_ROLE_KEY en frontend

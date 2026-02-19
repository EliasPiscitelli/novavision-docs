# Fix Crítico: RLS — Reemplazo de SUPABASE_CLIENT (anon) por SUPABASE_ADMIN_CLIENT (service_role)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-19
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Commits:** `cbb66b7` (RLS fix 4 services), `2f4c5cd` (UUID regex + service auto-number)

---

## Resumen

Se descubrió y corrigió un **bug crítico sistémico**: 4 servicios del backend usaban `SUPABASE_CLIENT` (anon key, `role: "anon"`) para operaciones de lectura y escritura contra PostgREST. Las políticas RLS de la base de datos requieren `service_role` o un usuario autenticado con `current_client_id()` — la anon key no cumple ninguna de las dos condiciones.

**Resultado**: PostgREST devolvía arrays vacíos (`[]`) sin error, la API respondía 200 OK, el frontend mostraba toast de éxito, pero **nada se persistía en la base de datos**.

---

## Causa Raíz

| Token | Role | Acceso RLS |
|-------|------|-----------|
| `SUPABASE_CLIENT` (anon key) | `anon` | ❌ Bloqueado por RLS — `auth.uid()` y `current_client_id()` son null |
| `SUPABASE_ADMIN_CLIENT` (service_role) | `service_role` | ✅ Bypass completo de RLS |

El backend NestJS usa su propio middleware para autenticación y validación de tenant (JWT + `x-client-id`). Las operaciones a Supabase son server-to-server con service_role key, por lo que RLS debería bypassearse siempre. El error fue que 4 servicios inyectaban el token equivocado.

---

## Servicios Afectados (100% rotos)

### 1. `ProductsService` (`src/products/products.service.ts`)
- **Impacto:** Crear, editar, eliminar productos no persistía. Cargar imágenes, option sets, categorías — todo fallaba silenciosamente.
- **Cambio:** Se eliminó `@Inject('SUPABASE_CLIENT')` completo. Todos los ~20 métodos migrados a `this.adminClient`.
- **Métodos afectados:** `createProduct`, `updateProduct`, `deleteProduct`, `removeImage`, `updateImageVariants`, `findOne`, `getAllProducts`, `getProductsStamp`, `uploadProducts`, `preloadCategoryMap`, `findOrCreateCategory`, `downloadProducts`, `searchProducts`, `searchProductsRpc`, `hydrateProductsByIds`, `searchProductsWithRelevance`

### 2. `CartService` (`src/cart/cart.service.ts`)
- **Impacto:** Agregar/ver/modificar/eliminar items del carrito no funcionaba.
- **Cambio:** `@Inject('SUPABASE_CLIENT')` → `@Inject('SUPABASE_ADMIN_CLIENT')`
- **Métodos afectados:** `getCart`, `addItem`, `updateItem`, `removeItem`, `clearCart`

### 3. `FavoritesService` (`src/favorites/favorites.service.ts`)
- **Impacto:** Agregar/eliminar/listar favoritos no funcionaba.
- **Cambio:** `@Inject('SUPABASE_CLIENT')` → `@Inject('SUPABASE_ADMIN_CLIENT')`
- **Métodos afectados:** `getFavorites`, `addFavorite`, `removeFavorite`, `mergeFavorites`

### 4. `AnalyticsService` (`src/analytics/analytics.service.ts`)
- **Impacto:** Dashboard de admin mostraba todos los valores en 0 (0 órdenes, $0 revenue, 0 pagos).
- **Cambio:** `@Inject('SUPABASE_CLIENT')` → `@Inject('SUPABASE_ADMIN_CLIENT')`
- **Métodos afectados:** `getOrdersSummary`, `getPaymentsSummary`, `getRecentOrders`

---

## Servicios Verificados (correctos, no necesitaban cambio)

| Servicio | Razón |
|----------|-------|
| `AuthService` | Usa anon key solo para Supabase Auth API (signUp, signIn, OAuth) — correcto. Operaciones de datos ya usan `adminClient`. |
| `SeoService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `ReviewsService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `QuestionsService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `BannerService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `OrdersService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `UsersService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `LogoService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `OptionSetsService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `ShippingService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `FaqService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `ContactInfoService` | Ya usa `SUPABASE_ADMIN_CLIENT` |
| `ServiceService` | Ya usa `SUPABASE_ADMIN_CLIENT` |

---

## Cómo se descubrió

1. Bug reportado: option sets no aparecían en storefront pese a configurarse en admin.
2. Se verificó que el producto en DB tenía `option_mode: "none"`, `option_set_id: null`.
3. Se trazó el flujo: Admin → API PUT → `products.service.updateProduct` → Supabase update.
4. Se decodificó JWT de `SUPABASE_KEY` → `"role":"anon"`.
5. **Prueba directa**: PATCH con service_role → funciona. PATCH con anon → retorna `[]` (0 rows).
6. **Conclusión**: RLS bloqueaba silenciosamente TODAS las operaciones.

---

## Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| `src/products/products.service.ts` | Removido `SUPABASE_CLIENT`. Todos los métodos migrados a `adminClient`. |
| `src/cart/cart.service.ts` | `SUPABASE_CLIENT` → `SUPABASE_ADMIN_CLIENT` |
| `src/favorites/favorites.service.ts` | `SUPABASE_CLIENT` → `SUPABASE_ADMIN_CLIENT` |
| `src/analytics/analytics.service.ts` | `SUPABASE_CLIENT` → `SUPABASE_ADMIN_CLIENT` |

---

## Validación

```bash
npm run lint       # 0 errores
npm run typecheck  # 0 errores  
npm run build      # OK (dist/main.js generado)
```

---

## Cómo Probar

1. Crear/editar un producto en admin dashboard → verificar que persista en DB.
2. Configurar option sets (tallas/colores) → verificar que `option_mode` y `option_set_id` se guarden.
3. Agregar items al carrito desde storefront → verificar en DB que `cart_items` se crean.
4. Agregar/eliminar favoritos → verificar en DB tabla `favorites`.
5. Abrir dashboard de analytics → verificar que muestra datos reales (no ceros).

---

## Notas de Seguridad

- El service_role key bypassa RLS completamente → la seguridad multi-tenant depende 100% del middleware de la API (AuthMiddleware + TenantContextGuard).
- Esto es correcto por diseño: el backend valida JWT + tenant antes de ejecutar queries.
- La anon key SOLO debe usarse para llamadas al Auth API de Supabase (signUp, signIn, etc.) que no tocan tablas de negocio.

---

## Riesgo Residual

`auth.service.ts` usa `this.supabase.auth.updateUser()` para `resetPassword`/`changePassword`, lo cual depende del estado de sesión del cliente singleton — posible problema de concurrencia bajo carga. No se abordó en esta sesión (es un issue separado del fix de RLS).

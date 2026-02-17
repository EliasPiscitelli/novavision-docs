# Cambio: Módulo Option Sets + Selección de opciones en carrito

- **Autor:** agente-copilot
- **Fecha:** 2026-02-16
- **Rama:** feature/automatic-multiclient-onboarding
- **Contexto:** PR1-PR4 del plan "Rediseño Sistema Talles y Medidas Polirrubro"

## Archivos creados

### Migraciones SQL
- `migrations/20260216_option_sets_tables.sql` — Tablas `option_sets`, `option_set_items`, `size_guides`
- `migrations/20260216_option_sets_product_columns.sql` — ALTER en `products` (option_mode, option_set_id, option_config) y `cart_items` (selected_options, options_hash)
- `migrations/20260216_option_sets_rls.sql` — Políticas RLS para las 3 tablas nuevas
- `migrations/20260216_option_sets_seed_presets.sql` — 37 presets globales (ropa, calzado, accesorios, genéricos)

### Módulo NestJS option-sets
- `src/option-sets/option-sets.module.ts`
- `src/option-sets/option-sets.service.ts` — CRUD completo + size guides + resolveProductOptions (dual-read) + validateSelectedOptions
- `src/option-sets/option-sets.controller.ts` — Endpoints REST con guards por rol
- `src/option-sets/dto/create-option-set.dto.ts`
- `src/option-sets/dto/update-option-set.dto.ts`
- `src/option-sets/dto/size-guide.dto.ts`
- `src/option-sets/dto/index.ts`

## Archivos modificados

- `src/app.module.ts` — Importa y registra `OptionSetsModule`
- `src/cart/dto/add-cart-item.dto.ts` — Agrega `SelectedOptionDto` + campo `selectedOptions` opcional
- `src/cart/cart.service.ts` — Soporta `selected_options` en: signature de `addItemToCart`, búsqueda por hash (mismo producto con distintas opciones = ítems separados), INSERT incluye `selected_options`, método privado `hashSelectedOptions()`
- `src/cart/cart.controller.ts` — Pasa `dto.selectedOptions` al service

## Resumen

Implementación del backend para el sistema de opciones polirrubro (talles, medidas, colores, etc.) con:

1. **Tablas normalizadas**: `option_sets` → `option_set_items` (1:N), con soporte para presets globales (`client_id IS NULL`) y custom por tenant.
2. **Size guides**: tabla aparte con versionado y soporte por producto u option_set.
3. **37 presets**: ropa (letras XS→5XL, numéricas 34→52), jeans, calzado (AR/US/EU niño/adulto), accesorios, genéricos.
4. **Dual-read**: `resolveProductOptions()` lee el nuevo sistema (option_set) y si no existe hace fallback al CSV legacy (`sizes`/`colors` en products).
5. **Carrito con opciones**: el mismo producto con distintas opciones se almacena como ítems separados, usando hash SHA-256 para matching.

## Por qué

- El sistema anterior guardaba talles/colores como texto CSV en la tabla `products`, sin normalización ni validación.
- La selección del usuario se perdía entre frontend y backend (el POST del carrito no incluía talle/color).
- No existía forma de reutilizar conjuntos de opciones entre productos.
- Este cambio es backward-compatible: productos sin option_set siguen funcionando con el fallback CSV.

## Cómo probar

```bash
# En terminal back:
cd apps/api

# 1. Lint (0 errores)
npm run lint

# 2. TypeScript (compila limpio)
npm run typecheck

# 3. Build producción
npm run build

# 4. Levantar servidor
npm run start:dev

# 5. Probar endpoints (requiere JWT admin + x-client-id):
# GET  /option-sets              → lista presets + custom
# POST /option-sets              → crear option set
# POST /option-sets/:id/duplicate → clonar preset a custom
# GET  /option-sets/size-guides/list
# POST /api/cart                  → ahora acepta selectedOptions[]
```

**Migraciones pendientes de ejecutar en Supabase:**
```
20260216_option_sets_tables.sql
20260216_option_sets_product_columns.sql
20260216_option_sets_rls.sql
20260216_option_sets_seed_presets.sql
```

## Notas de seguridad

- RLS con `server_bypass` para service_role
- Presets globales (`client_id IS NULL`) son solo lectura para todos los tenants; escritura solo por admin del tenant sobre sus propios sets
- Los endpoints de escritura están protegidos con `@UseGuards(RolesGuard) @Roles('admin', 'super_admin')`
- `validateSelectedOptions()` valida que los valores seleccionados existan en el option_set del producto

## Riesgos / Rollback

- **Bajo riesgo**: las migraciones son aditivas (ALTER ADD COLUMN, CREATE TABLE) — no modifican estructura existente
- **Rollback**: `DROP TABLE size_guides, option_set_items, option_sets CASCADE;` + `ALTER TABLE products DROP COLUMN option_mode, option_set_id, option_config;` + `ALTER TABLE cart_items DROP COLUMN selected_options, options_hash;`
- El carrito sigue funcionando sin opciones (selectedOptions es opcional, fallback a comportamiento actual)

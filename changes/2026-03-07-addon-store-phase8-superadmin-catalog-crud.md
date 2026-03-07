# Cambio: Addon Store Phase 8 - CRUD de catálogo global en super admin

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront

## Archivos modificados

- apps/api/src/addons/addons.admin.controller.ts
- apps/api/src/addons/addons.service.ts
- apps/api/src/addons/addons.service.spec.ts
- apps/admin/src/services/adminApi.js
- apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx

## Resumen

Se habilitó el CRUD del catálogo global del Addon Store para super admin, diferenciándolo explícitamente del catálogo de productos de cada tienda. La UI del panel de operaciones ahora muestra métricas visuales, un formulario de alta/edición y acciones para editar, desactivar/reactivar o borrar sólo los ítems administrables de `addon_catalog`.

## Por qué

El panel mostraba el catálogo del Addon Store, pero no permitía operar los ítems persistidos en `addon_catalog`. Además, el catálogo mezcla tres fuentes distintas: packs SEO AI, templates de servicios y filas gestionables del catálogo admin. Hacía falta exponer CRUD únicamente sobre la fuente administrable, sin dar la falsa impresión de que los packs o servicios derivados podían editarse desde el dashboard.

## Qué se implementó

- La API de super admin ahora expone:
  - `GET /admin/addons/catalog` con vista admin completa
  - `POST /admin/addons/catalog`
  - `PATCH /admin/addons/catalog/:addonKey`
  - `DELETE /admin/addons/catalog/:addonKey`
- `AddonsService` ahora distingue `catalog_source` y `can_manage` para separar ítems de solo lectura de ítems CRUD.
- El borrado de `addon_catalog` quedó protegido: si el item ya tiene historial en `account_addons` o `account_addon_purchases`, la API rechaza el delete y fuerza la estrategia de desactivación.
- `AddonPurchasesView` reemplaza la tabla estática por:
  - cards de métricas del módulo
  - formulario de alta/edición
  - cards del catálogo con acciones contextuales
  - badges para diferenciar “gestionable” vs “solo lectura”
- Se agregaron tests de servicio para cubrir catálogo admin y borrado protegido.

## Cómo probar

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/api
npm test -- src/addons/addons.service.spec.ts
npm run typecheck
npm run build

cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npm run lint
npm run typecheck -- --pretty false
npm run build
```

Prueba manual sugerida:

- Abrir el módulo Addon Store Ops en super admin.
- Crear un item nuevo con `addon_key`, nombre, precio y delta de productos.
- Editarlo y verificar persistencia en el listado.
- Desactivarlo y reactivarlo desde la card.
- Intentar borrar un item sin historial y verificar eliminación.
- Intentar borrar un item con historial y verificar mensaje de bloqueo para desactivar en su lugar.

## Notas de seguridad

- El CRUD nuevo sigue protegido por `SuperAdminGuard`.
- No se modificó el flujo de compra tenant ni el catálogo de productos de cada cliente.
- El delete evita remover addons con activaciones o purchases históricas para no romper trazabilidad de billing.

## Riesgos y próximos pasos

- El formulario actual modela sólo el subset administrable real de `addon_catalog` (`display_name`, `price_cents`, `products_limit_delta`, `is_active`). Si en el futuro el catálogo requiere más capacidad, habrá que extender la tabla y el contrato explícitamente.
- La UI del admin sigue cargando un bundle grande; el build advierte chunks altos, aunque no bloquea esta entrega.
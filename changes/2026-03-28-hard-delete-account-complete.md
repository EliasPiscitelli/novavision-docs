# Hard Delete de cuenta completo — API + Admin

**Fecha:** 2026-03-28
**Apps afectadas:** API, Admin
**Tipo:** feature + fix

## Resumen

Reescritura completa del endpoint `DELETE /admin/clients/:clientId` para hacer un borrado exhaustivo de todas las bases de datos, Storage y Auth. El endpoint anterior solo borraba `clients` (Backend DB) y `nv_accounts` (Admin DB) confiando en CASCADE, lo cual dejaba datos huérfanos.

## Cambios

### API (`apps/api/`)

- **`src/admin/admin-client.controller.ts`** — Reescrito `deleteClient()`:
  - Backend DB: borra ~47 tablas en orden de FK (desde hojas como `cart_items`, `favorites` hasta `clients`)
  - Admin DB: borra ~38 tablas FK-dependientes de `nv_accounts` (incluye tablas con `account_id`, `tenant_id`, `subscription_id`, `nv_account_id`)
  - Storage: purga archivos de 3 buckets (`product-images`, `tenant-media`, `logos`) en lotes de 100
  - Auth: elimina usuario de Supabase Auth
  - Retorna reporte detallado con conteo por recurso eliminado
  - Inyectado `StorageService` + `clientPrefix` path builder
  - Nuevo método privado `purgeClientStorage()`
- **`src/admin/admin.module.ts`** — Importado `StorageModule`

### Admin (`apps/admin/`)

- **`src/services/adminApi.js`** — Nuevo helper `hardDeleteAccount(clientId)`
- **`src/pages/AdminDashboard/SubscriptionDetailView.jsx`**:
  - Botón "Eliminar cuenta" (rojo) en la barra de acciones del header
  - Modal con type-to-confirm (`eliminar-cuenta`) para prevenir clicks accidentales
  - Lista detallada de qué se eliminará (productos, órdenes, imágenes, suscripción, etc.)
  - Navega atrás después de eliminación exitosa
- **`src/utils/deleteClientEverywhere.jsx`** — Toast mejorado con conteo de recursos limpiados

## Validación

- API: lint ✓, typecheck ✓, build ✓
- Admin: lint ✓, typecheck ✓, build ✓

## Contexto

Surgió de la limpieza manual del tenant "farma" donde se mapearon todas las tablas FK de ambas BDs (60+ en Backend, 38 en Admin) y el orden correcto de eliminación. Ahora esa lógica está productivizada en el endpoint para uso del super admin.

# 2026-03-27 — AI Discoverability (Empty States) + Media Migration Script

## Resumen

Dos cambios independientes: CTAs de IA en estados vacíos del dashboard tenant y script de migración de imágenes a tenant_media.

## Cambios

### Task 1: AI Discoverability — Empty State CTAs (Web)

Archivos modificados:
- `apps/web/src/components/admin/ProductDashboard/index.jsx`
- `apps/web/src/components/admin/FaqSection/index.jsx`
- `apps/web/src/components/admin/ServiceSection/index.jsx`
- `apps/web/src/components/admin/QADashboard/index.jsx`

Detalle:
- **ProductDashboard**: Agregado empty state cuando el catálogo no tiene productos. Muestra CTAs para "Generar catálogo con IA", "Crear producto desde foto" y "Crear Producto manual".
- **FaqSection**: Agregado `AdminEmptyState` cuando la lista de FAQs está vacía. Sugiere "Generar FAQs con IA" y "Crear FAQ manual". Se corrigió import faltante de `AdminEmptyState`.
- **ServiceSection**: El empty state existente se mejoró reemplazando el botón simple por un doble CTA: "Crear servicio con IA" (AiButton) + "Crear manualmente".
- **QADashboard**: Se corrigió prop `description` (inexistente) por `message` (correcto) y se agregó texto mencionando la sugerencia de respuestas con IA.
- **AI Credits Badge**: Ya existía en el header del AdminDashboard (`AiCreditsWidget`) junto al `NotificationBell`. No requirió cambios.

### Task 2: Script de migración de imágenes (API)

Archivo creado:
- `apps/api/scripts/migrate-product-images-to-tenant-media.ts`

Detalle:
- Conecta a Backend DB vía Supabase client (SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY).
- Recorre todos los productos con `imageUrl` no nulo.
- Para cada imagen de Supabase storage, extrae el `storage_key` de la URL.
- Verifica idempotencia: si ya existe en `tenant_media` con ese `storage_key` + `client_id`, no duplica.
- Crea registros en `tenant_media` y los vincula en `product_media` (upsert).
- Soporta `--dry-run` (default) y `--execute`.
- Registra progreso y errores detallados.
- Patrón basado en `migrateExistingProductImages()` de `media-library.service.ts` y `migrate-storage.ts`.

## Validación

- Script API: typecheck limpio con `tsc --noEmit --skipLibCheck`.
- Web: cambios son JSX inline, consistentes con patrones existentes (AiButton, AdminEmptyState).

## Impacto

- No rompe contratos ni APIs existentes.
- No toca base de datos (el script solo se ejecuta manualmente).
- No afecta ramas de producción (solo develop).

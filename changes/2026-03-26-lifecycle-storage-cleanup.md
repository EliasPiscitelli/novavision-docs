# Lifecycle Storage Cleanup

**Fecha:** 2026-03-26
**Plan:** `PLAN_CHURN_LIFECYCLE.md` Fase 2 — retención de datos y purga
**Estado:** Implementado + testeado

---

## Problema

Cuando se eliminaba un tenant (hard-delete), los registros de BD se limpiaban pero los archivos en Supabase Storage (`product-images` bucket) quedaban huérfanos, consumiendo espacio indefinidamente.

Además, las tablas nuevas (`tenant_media`, `product_media`, `media_upload_jobs`, `media_upload_batches`, `footer_config`) no estaban en la lista de tablas a limpiar durante el cascade delete.

## Solución

### Storage purge

- Nuevo método `purgeClientStorage(clientIds)` en `lifecycle-cleanup.cron.ts`
- Lista todos los objetos bajo `clients/{clientId}/` en el bucket `product-images`
- Borra en lotes de 100 (límite de Supabase Storage API)
- Cap de 10,000 archivos por tenant (protección contra loops infinitos)
- Se ejecuta **después** de la limpieza de tablas DB (para que los registros ya no existan)

### Tablas agregadas al cascade

- `product_media` (antes de `products` por FK)
- `tenant_media` (antes de `products`)
- `media_upload_jobs` (antes de `media_upload_batches`)
- `media_upload_batches`
- `footer_config`

### Archivos modificados

- `api/src/lifecycle/lifecycle-cleanup.cron.ts` — import `StorageService`, inyección en constructor, `purgeClientStorage()`, tablas nuevas en `tablesToClean`
- `api/src/lifecycle/lifecycle.module.ts` — import `StorageModule`

### Tests creados

- `api/src/lifecycle/__tests__/lifecycle-cleanup.cron.spec.ts` — 12 tests:
  - `suspendExpiredTrials`: suspensión + notificación, sin expirados, error de query
  - `scheduleExpiredSuspensions`: soft-delete, sin expiradas
  - `saveTombstonesBeforeHardDelete`: tombstones + cleanup + storage purge, sin archivos, tabla faltante
  - `detectAndNotifyZombies`: notificación, columna faltante
  - `releaseDeletedSlugs`: limpieza, sin huérfanos

## Validación

- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 108/108 suites, 1057/1059 tests OK (2 skipped preexistentes)

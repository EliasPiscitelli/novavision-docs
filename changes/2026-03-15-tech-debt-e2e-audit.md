# 2026-03-15 — Resolución de deuda técnica (Auditoría E2E)

## Resumen
4 items de deuda técnica identificados en la auditoría E2E del 15/03/2026.

## Cambios

### Item 1: progress mega-JSONB → columnas tipadas
- **Migración SQL:** `migrations/admin/20260315_typed_onboarding_columns.sql`
  - Nuevas columnas: `checkout_status`, `checkout_paid_at`, `wizard_catalog`, `wizard_assets`, `personal_info`, `google_linked`, `current_step`
  - Backfill automático desde `progress` existente
- **Dual-write en `onboarding.service.ts`:** `updateProgress()` ahora escribe tanto en `progress` JSONB como en las columnas tipadas correspondientes
- **Lectura con fallback en `provisioning-worker.service.ts`:** Lee columnas tipadas primero, fallback a `progress->>'key'`
- Fase incremental: `progress` se mantiene como archive/fallback

### Item 2: Extender runStep a más pasos del provisioning
- **Archivo:** `provisioning-worker.service.ts`
- Steps wrapeados con saga pattern (`runStep()`):
  - `create_auth_user` (ALTO riesgo — Supabase Auth)
  - `sync_mp_credentials` (ALTO riesgo — MP tokens)
  - `update_account_status` (MEDIO)
  - `update_onboarding` (MEDIO)
  - `clean_slug_reservation` (Bajo)
  - `sync_home_settings` (MEDIO)
  - `create_custom_palettes` (Bajo)
  - `seed_shipping` (Bajo)
  - `migrate_assets` (MEDIO)
  - `seed_pages` (Bajo)
- Total: 10 steps nuevos + 4 existentes (`upsert_client`, `upsert_user`, `migrate_logo`, `migrate_catalog`) = 14 de 23 steps con tracking

### Item 3: Consolidar schemas conflictivos
- **`backend_clusters`:** `migrations/admin/20260315_canonical_backend_clusters.sql`
  - Alinea con schema real de producción (columnas faltantes como `db_url_encrypted`, `status`, `maintenance_mode`)
  - Documenta que ADMIN_010 está superseded
- **`subscriptions`:** `migrations/admin/20260315_canonical_subscriptions.sql`
  - Agrega `mp_preapproval_id` como nombre canónico
  - Backfill desde `provider_id` si existe

### Item 4: has_demo_data y suspension_reason
- **`has_demo_data` eliminado:**
  - `migrations/backend/20260315_drop_has_demo_data.sql` — Drop columna + recrea trigger sin referencia
  - `demo.service.ts` — Eliminado write de `has_demo_data`
- **`suspension_reason` mantenido:** Documentado como write-only audit trail (no se elimina)

## Riesgo
- Item 1: MEDIO (incremental, retrocompatible)
- Item 2: BAJO (no cambia lógica, solo agrega tracking)
- Item 3: MEDIO (verificar contra producción antes de ejecutar)
- Item 4: BAJO

## Verificación pendiente
- [ ] `npm run build` en API
- [ ] Verificar Farma: `curl -H "x-tenant-slug: farma" https://api.novavision.lat/home/data`
- [ ] Ejecutar migraciones en staging antes de producción

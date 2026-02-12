# Cambios: Fix suscripción bloqueada + Backlog BUG-004/BUG-005

- **Autor**: agente-copilot
- **Fecha**: 2026-02-11
- **Rama API**: feature/automatic-multiclient-onboarding

## Archivos modificados

### API (apps/api)
- `src/plans/featureCatalog.ts` — Agregada feature `dashboard.subscription`
- `src/worker/provisioning-worker.service.ts` — BUG-004: limpieza inmediata de base64 logo
- `migrations/admin/ADMIN_060_slug_immutability_trigger.sql` — BUG-005: trigger de inmutabilidad de slug

## Resumen de cambios

### 1. Fix "Suscripción y Tienda" bloqueada para plan starter
**Problema**: La sección "Suscripción y Tienda" en el admin dashboard de las tiendas
aparecía bloqueada (con candado) para TODOS los planes, incluyendo starter.

**Causa raíz**: El frontend referenciaba `dashboard.subscription` en el mapa
`SECTION_FEATURES` de `AdminDashboard/index.jsx`, pero esa feature ID no existía
en el catálogo del backend (`featureCatalog.ts`). La función `isSectionLocked()`
retornaba `true` porque el feature ID no estaba en el `allowedFeatures` Set.

**Fix**: Se agregó la feature `dashboard.subscription` al `FEATURE_CATALOG` con
`plans: { starter: true, growth: true, enterprise: true }` — disponible para todos
los planes ya que todo cliente necesita gestionar su suscripción.

### 2. BUG-004: Limpieza inmediata de base64 logo en provisioning
**Problema**: Tras `migrateLogoToBackend`, el base64 del logo (~5MB) permanecía en
`nv_onboarding.progress.wizard_assets.logo_url` hasta que el cron semanal
(`cleanBase64FromProgress`) lo limpiara. Durante 0-7 días, ese blob pesado
persistía en el JSONB de la Admin DB.

**Fix**: Después de subir exitosamente el logo a Storage y actualizar `clients.logo_url`,
ahora se reemplaza inmediatamente `wizard_assets.logo_url` con `[migrated_to_storage]`
en `nv_onboarding.progress`. Es non-blocking: si falla, el cron semanal lo captura.

### 3. BUG-005: Trigger de inmutabilidad de slug en nv_accounts
**Problema**: No existía protección a nivel DB para evitar modificar el slug de una
cuenta ya provisionada. Un UPDATE accidental o malicioso podía romper DNS, rutas de
storage y URLs externas.

**Fix**: Migración ADMIN_060 con trigger `trg_prevent_slug_change` que:
- Permite cambiar slug si `status IN ('draft', 'awaiting_payment')`
- Bloquea cambios para cualquier otro estado (paid, provisioning, provisioned, live, etc.)
- Usa `RAISE EXCEPTION` con ERRCODE P0001

### BUG-003: purgeExpiredDrafts (ya resuelto)
El backlog estaba desactualizado. El cron ya fue migrado a `TtlCleanupService`
con `@Cron('0 2 * * *')` activo. No requiere acción adicional.

## Cómo probar

### Fix Suscripción
1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Web: `npm run dev` (terminal front)
3. Loguearse como admin de una tienda con plan starter
4. Ir a `/admin-dashboard` → verificar que "Suscripción y Tienda" NO tiene candado
5. Verificar que se puede acceder a la sección

### BUG-004: Logo cleanup
1. Provisionar una cuenta nueva con logo base64 en el wizard
2. Verificar en logs: `✅ Base64 logo cleared from nv_onboarding for {accountId}`
3. Consultar `nv_onboarding.progress` → `wizard_assets.logo_url` debe ser `[migrated_to_storage]`

### BUG-005: Slug trigger (requiere ejecutar migración)
```bash
psql "$ADMIN_DB_URL" -f migrations/admin/ADMIN_060_slug_immutability_trigger.sql
```
Verificación:
```sql
-- Debe funcionar (status = draft):
UPDATE nv_accounts SET slug = 'test-slug' WHERE status = 'draft' LIMIT 1;
-- Debe fallar (status = provisioned):
UPDATE nv_accounts SET slug = 'hacked' WHERE status = 'provisioned' LIMIT 1;
-- ERROR: Cannot change slug after payment (current status: provisioned)
```

## Notas de seguridad
- BUG-005 protege contra escalation via slug tampering
- BUG-004 reduce superficie de datos sensibles en Admin DB (base64 blobs)
- La migración ADMIN_060 es idempotente (DROP TRIGGER IF EXISTS + CREATE OR REPLACE)

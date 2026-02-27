# Cambio: Single Cluster + Metering/Quotas/Enforcement — Fix & Activation

- **Autor:** agente-copilot
- **Fecha:** 2025-02-27
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Docs:** `main`

---

## Archivos modificados

### API (`templatetwobe`)

| Archivo | Tipo | Detalle |
|---------|------|---------|
| `src/db/db-router.service.ts` | Simplificación | `chooseBackendCluster()` ahora retorna `'cluster_shared_01'` directamente (era: weighted random + query DB + status filter) |
| `migrations/admin/ADMIN_071_backfill_cluster_id.sql` | Migración nueva | Backfill `backend_cluster_id` para cuentas activas. Ejecutada: UPDATE 0 (todos ya tenían valor) |
| `src/billing/usage-consolidation.cron.ts` | **Rewrite completo** | 3 bugs críticos corregidos (ver abajo) |
| `src/tenant-payments/mercadopago.service.ts` | Emisión de métrica | Agregada métrica `order` (qty=1) en `confirmPayment()` junto al `gmv` existente |
| `railway.env.template` | Config | Agregado `ENABLE_QUOTA_ENFORCEMENT=false` con documentación |

### Docs (`novavision-docs`)

| Archivo | Tipo |
|---------|------|
| `plans/PLAN_SINGLE_CLUSTER_METERING_ENFORCEMENT.md` | Plan de implementación (3 bloques, evidencia, DoD) |
| `plans/MULTI_CLUSTER_FUTURE.md` | Documentación de items F2.1–F2.4 como pendientes (multi-cluster) |
| `changes/2025-02-27-single-cluster-metering-enforcement.md` | Este archivo |

---

## Resumen de cambios

### Bloque 1 — Single Cluster Hardening

**Problema:** `chooseBackendCluster()` ejecutaba lógica de weighted random y queries a `backend_clusters` innecesarias en entorno de un solo cluster.

**Solución:** Simplificado a `return 'cluster_shared_01'`. Lógica multi-cluster documentada en `MULTI_CLUSTER_FUTURE.md` para restauración futura.

### Bloque 2 — Pipeline de Metering (3 bugs críticos)

**Bug 1 — DB incorrecta:** `UsageConsolidationCron` leía de Backend DB pero `usage_daily` vive en Admin DB. Corregido a `SUPABASE_METERING_CLIENT` (Admin DB).

**Bug 2 — ID mismatch:** `usage_ledger.client_id` = Backend `clients.id` ≠ `nv_accounts.id` (Admin). Los rollups se indexan por `nv_accounts.id` (tenant_id). Corregido construyendo mapa `backendId → accountId` vía `clients.nv_account_id` FK.

**Bug 3 — Métrica `order` nunca emitida:** Solo `request`, `egress_bytes` y `gmv` se emitían. Sin `order`, la columna `orders_confirmed` en `usage_rollups_monthly` siempre era 0 → enforcement de órdenes nunca se activaba. Corregido agregando emisión en `mercadopago.service.ts`.

**Diseño storage:** En lugar de agregar storage al ledger (complejidad, no es evento), se lee el gauge `client_usage.storage_bytes_used` (mantenido por triggers en Backend DB) durante la consolidación. Más preciso.

### Bloque 3 — Enforcement

**Verificado (sin cambios de código necesarios):**
- `QuotaEnforcementService`: estado máquina monotónica ACTIVE→WARN→SOFT_LIMIT→GRACE→HARD_LIMIT ✅
- `QuotaCheckGuard`: registrado como APP_GUARD, resuelve via `clients.nv_account_id`, bloquea POST/PUT/PATCH/DELETE en HARD_LIMIT ✅
- `PlansService.validateAction()`: `create_order` es soft cap intencional (nunca bloquea checkout) ✅
- Tablas de overage rates están pobladas en `plans` (starter/growth/enterprise) ✅
- `metering_prices` vacía → sin conflicto (reservada Fase 4) ✅

**Activación:** `ENABLE_QUOTA_ENFORCEMENT=false` agregado a template. Setear `true` en Railway para activar.

---

## Por qué se hizo

El pipeline de metering estaba completamente roto: la consolidación cron leía de la DB equivocada, usaba el formato de columnas equivocado, mapeaba IDs incompatibles, y le faltaba una métrica clave (`order`). Sin estos fixes, QuotaEnforcementService recibía rollups vacíos o con 0s, haciendo que el enforcement nunca se disparara.

El hardening de single-cluster elimina complejidad innecesaria para el primer lanzamiento manteniendo la posibilidad de restaurar multi-cluster en el futuro.

---

## Cómo probar

### Build Verification
```bash
cd apps/api
npm run lint      # 0 errores (1272 warnings preexistentes)
npm run typecheck # OK
npm run build     # OK, dist/main.js generado
```

### Pipeline de Metering (post-deploy)
1. Confirmar un pago via MP sandbox → verificar que `usage_ledger` registra métricas `gmv` y `order`
2. Esperar ejecución del `MetricsCron` (03:15 ART) → verificar `usage_daily` tiene rows dimensionales
3. Esperar ejecución del `UsageConsolidationCron` (02:30 UTC) → verificar `usage_rollups_monthly` tiene valores no-0 para `orders_confirmed` y `api_calls`
4. Activar `ENABLE_QUOTA_ENFORCEMENT=true` → verificar que `QuotaEnforcementService` (03:00 UTC) evalúa y transiciona estados

### Single Cluster
1. Verificar que `chooseBackendCluster()` retorna `'cluster_shared_01'`
2. Confirmar que el onboarding de nuevos clientes sigue funcionando (cluster se asigna correctamente)

---

## Notas de seguridad

- No se exponen credenciales ni claves nuevas
- `ENABLE_QUOTA_ENFORCEMENT` es toggle seguro: `false` = dry-run (código existente)
- El cron de consolidación usa service_role keys que ya existían
- RLS no se modifica; las queries usan `SERVICE_ROLE_KEY` (server-side)

---

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| UsageConsolidationCron falla en prod con datos reales | Feature flag `ENABLE_QUOTA_ENFORCEMENT=false` (dry-run). Cron loguea errores sin bloquear. Revisar logs post-deploy. |
| ID mapping incorrecto para algún tenant | Validado con datos reales: slug "farma" → `nv_account_id` correcto. Query tiene fallback warning si no encuentra FK. |
| Overhead de storage query a Backend DB | Una sola query por ejecución diaria. Insignificante. |

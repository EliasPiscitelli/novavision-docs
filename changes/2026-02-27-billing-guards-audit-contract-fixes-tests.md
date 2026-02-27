# Cambio: Auditoría de guards/permisos, contract fixes front y tests billing

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama API:** `feature/automatic-multiclient-onboarding` (commit `fdc0632`)
- **Rama Admin:** `feature/automatic-multiclient-onboarding` (commit `5084162`)
- **Rama Web:** `develop` (commit `4b4c21d`) → cherry-pick `feature/multitenant-storefront` (`f63c4b7`)
- **Rama Docs:** `main` (commit `3c6e4dc`)

---

## Resumen

Auditoría completa de guards, permisos, contratos FE↔BE y tests del sistema de billing/overages/debt management implementado en sesiones anteriores. Se encontraron y corrigieron **4 bugs críticos de contrato** en el frontend y se crearon **30 tests nuevos** para el backend.

---

## Archivos modificados

### API (templatetwobe) — 21 archivos (+2953/-97 líneas)

#### Nuevos
| Archivo | Propósito |
|---------|-----------|
| `src/billing/__tests__/billing.controller.spec.ts` | 19 unit tests del BillingController |
| `src/billing/__tests__/billing-debt-management.service.spec.ts` | 11 unit tests de getCancellationDebts + waiveCancellationDebt |
| `src/billing/__tests__/billing-overage.service.spec.ts` | Tests de OverageService (sesión anterior) |
| `src/billing/__tests__/overage-accumulation.cron.spec.ts` | Tests de OverageAccumulationCron (sesión anterior) |
| `src/billing/overage-accumulation.cron.ts` | Cron: infla monto MP con overages pendientes |
| `migrations/admin/ADMIN_071_backfill_cluster_id.sql` | Backfill cluster para cuentas activas |
| `migrations/admin/ADMIN_091_plans_overage_storage_column.sql` | Columna overage_per_gb_storage en plans |
| `migrations/admin/ADMIN_092_overage_accumulation_and_debt.sql` | cancellation_debt_log + columnas overage en subscriptions |
| `migrations/backend/BACKEND_050_fix_duplicate_product_triggers.sql` | Fix triggers duplicados en products |

#### Modificados
| Archivo | Cambio |
|---------|--------|
| `src/billing/billing.controller.ts` | 3 nuevos endpoints: getCancellationDebts, waiveCancellationDebt, getAccountDebtStatus |
| `src/billing/billing.module.ts` | Registro OverageAccumulationCron |
| `src/billing/billing.service.ts` | getCancellationDebts, waiveCancellationDebt, getAccountDebtStatus |
| `src/billing/auto-charge.cron.ts` | Deduce overages acumulados del monto fallback |
| `src/billing/gmv-pipeline.cron.ts` | Skip meses ya consolidados |
| `src/billing/overage.service.ts` | Soporte storage overage + overage_rate_storage_cents |
| `src/billing/usage-consolidation.cron.ts` | Guard skip-if-exists |
| `src/db/db-router.service.ts` | Helper resolveAdminClient |
| `src/plans/plans-admin.controller.ts` | UpdatePlanDto: overage_rate_storage_cents |
| `src/subscriptions/subscriptions.service.ts` | Debt tracking en cancelación |
| `src/tenant-payments/mercadopago.service.ts` | inflateSubscriptionAmount, getSubscriptionAmount |
| `railway.env.template` | ENABLE_QUOTA_ENFORCEMENT=false |

### Admin (novavision) — 7 archivos (+258/-28 líneas)

| Archivo | Cambio |
|---------|--------|
| `src/components/PlanEditorModal.jsx` | Campos overage rate (GMV + storage cents) |
| `src/pages/AdminDashboard/CancellationsView.jsx` | Columna "Deuda" con badge + acción "Condonar" |
| `src/pages/AdminDashboard/GmvCommissionsView.jsx` | Badge "accruing" + filtros por mes |
| `src/pages/AdminDashboard/SubscriptionDetailView.jsx` | **FIX:** Reemplazado dead code `cancel_pending_payment` con pre-check de deuda vía `getAccountDebtStatus()` |
| `src/pages/ClientDetails/index.jsx` | Badge "accruing" + acciones cancel/charge |
| `src/pages/Settings/BillingPage.tsx` | **FIX:** `result.debt_usd` → `result.debt?.amount_usd`, `result.init_point` → `result.payment_link` |
| `src/services/adminApi.js` | 3 nuevos endpoints: getCancellationDebts, waiveCancellationDebt, getAccountDebtStatus |

### Web (templatetwo) — 2 archivos (+13 líneas)

| Archivo | Cambio |
|---------|--------|
| `src/components/UserDashboard/BillingHub.jsx` | 3 nuevos labels de tipo de evento billing |
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | **FIX:** `result.debt_usd` → `result.debt?.amount_usd`, `result.init_point` → `result.payment_link` |

### Docs (novavision-docs) — 6 archivos (+1306 líneas)

| Archivo | Propósito |
|---------|-----------|
| `changes/2025-02-27-single-cluster-metering-enforcement.md` | Plan single cluster + metering |
| `changes/2026-02-27-metering-audit-fixes.md` | 3 bugs metering corregidos |
| `changes/2026-02-27-overage-accumulation-debt-management.md` | Implementación overage acumulación + deuda |
| `changes/2026-02-27-overage-debt-ui-gaps-resolved.md` | 7 gaps UI + 1 riesgo web resueltos |
| `plans/MULTI_CLUSTER_FUTURE.md` | Plan futuro multi-cluster |
| `plans/PLAN_SINGLE_CLUSTER_METERING_ENFORCEMENT.md` | Plan single cluster enforcement |

---

## Bugs de contrato encontrados y corregidos

### BUG-C01: BillingPage.tsx — shape de respuesta incorrecta
- **Archivo:** `src/pages/Settings/BillingPage.tsx`
- **Problema:** Usaba `result.debt_usd` pero la API devuelve `result.debt.amount_usd`. Usaba `result.init_point` pero la API devuelve `result.payment_link`.
- **Fix:** `result.debt?.amount_usd` y `result.payment_link || result.sandbox_payment_link`

### BUG-C02: SubscriptionManagement.jsx — misma shape incorrecta
- **Archivo:** `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx`
- **Problema:** Idéntico a BUG-C01.
- **Fix:** Idéntico.

### BUG-C03: SubscriptionDetailView.jsx — dead code
- **Archivo:** `src/pages/AdminDashboard/SubscriptionDetailView.jsx`
- **Problema:** Chequeaba `result?.status === 'cancel_pending_payment'` pero el endpoint admin de cancelación **siempre** devuelve `status: 'canceled'` (force cancel). Ese branch nunca se ejecutaría.
- **Fix:** Reemplazado con pre-check de deuda antes de cancelar. Llama a `adminApi.getAccountDebtStatus(accountId)` y muestra `window.confirm()` si hay deuda pendiente, advirtiendo al super admin antes de forzar la cancelación.

### BUG-C04: BillingHub.jsx — labels faltantes
- **Archivo:** `src/components/UserDashboard/BillingHub.jsx`
- **Problema:** 3 tipos de evento billing se mostraban como tipo genérico sin label descriptivo.
- **Fix:** Agregados labels para `overage_charge`, `overage_accumulated`, `cancellation_debt`.

---

## Auditoría de Guards y Permisos

### PlatformAuthGuard
- **Implementación:** Valida JWT contra Admin DB Supabase Auth.
- **Detección de role:** `app_metadata.is_super_admin` / `user_metadata.is_super_admin` / `user_metadata.role === 'superadmin'`
- **Output:** `req.user = { id, email, role, client_id, realm, project }`

### Endpoints nuevos — Validación de acceso

| Endpoint | Guard | Chequeo imperativo | Status |
|----------|-------|-------------------|--------|
| `GET /billing/cancellation-debts` | PlatformAuthGuard | `req.user?.role !== 'superadmin'` → 403 | ✅ Correcto |
| `POST /billing/cancellation-debts/:id/waive` | PlatformAuthGuard | `req.user?.role !== 'superadmin'` → 403 | ✅ Correcto |
| `GET /billing/accounts/:id/debt-status` | PlatformAuthGuard | `req.user?.role !== 'superadmin'` → 403 | ✅ Correcto |

**Consistencia:** Los 3 endpoints siguen el mismo patrón que los endpoints existentes del BillingController (`getAllEvents`, `markAsPaidManual`, `syncWithMp`).

---

## Tests creados

### billing.controller.spec.ts (19 tests)
- `getCancellationDebts`: 4 tests (superadmin OK, admin 403, user 403, undefined 403)
- `waiveCancellationDebt`: 4 tests (superadmin con nota, admin 403, user 403, undefined 403)
- `getAccountDebtStatus`: 4 tests (superadmin OK, admin 403, user 403, undefined 403)
- `getAllEvents`: 2 tests (superadmin OK, non-super 403)
- `markAsPaidManual`: 1 test
- `syncWithMp`: 1 test
- `getMyEvents`: 3 tests (user OK, admin 403, sin account_id error)

### billing-debt-management.service.spec.ts (11 tests)
- `getCancellationDebts`: 4 tests (happy, empty, null, error)
- `waiveCancellationDebt`: 7 tests (happy, sin nota, sin billing event, sin adjustments, not found, already paid, already waived)

### Total: 56 tests billing pasando (26 previos + 30 nuevos)

---

## Migraciones — Estado de aplicación

| Migración | Target DB | Estado | Verificación |
|-----------|-----------|--------|-------------|
| ADMIN_071 | Admin | ✅ Aplicada | 0 cuentas activas sin cluster |
| ADMIN_091 | Admin | ✅ Aplicada | Columna `overage_per_gb_storage` existe en plans |
| ADMIN_092 | Admin | ✅ Aplicada | Tabla `cancellation_debt_log` existe + 3 columnas en subscriptions |
| BACKEND_050 | Backend | ✅ Aplicada | Triggers duplicados eliminados, funciones orphanadas borradas |

---

## Validación Farma

| Check | Resultado |
|-------|-----------|
| Account status | `approved`, plan `growth`, cluster `cluster_shared_01` |
| Subscription | `active`, MP preapproval `fbb536...`, $85,500 ARS |
| Overage inflation | `false` (ningún overage pendiente) |
| Pending debt | $0 USD |
| Cancellation debts | 0 registros |
| Billing adjustments | 0 registros |
| Products count gauge | 11 (correcto, coincide con 11 productos reales) |
| Triggers productos | Duplicados eliminados (BACKEND_050) |
| Plan growth config | $60 USD, 1000 orders, 10 GB storage, overage $0.06/order, $0.021/GB storage |

**Farma NO necesita ninguna migración adicional.** Todas las 4 migraciones ya fueron aplicadas y sus datos están consistentes.

---

## Validación build (todos clean)

| App | Lint | Typecheck | Build |
|-----|------|-----------|-------|
| API | ✅ 0 errores | ✅ Clean | ✅ dist/main.js |
| Admin | ✅ Clean | ✅ Clean | ✅ Build OK |
| Web | ✅ 0 errores | ✅ Clean | ✅ Build OK |

---

## Cómo probar

### Debt management (Admin panel)
1. Login como super admin en admin panel
2. Ir a Cancellations view → verificar columna "Deuda"
3. Ir a detalle de suscripción → botón cancelar muestra pre-check de deuda

### Cancel flow (Web storefront / BillingPage)
1. Login como admin de tienda
2. Ir a Settings > Billing > Cancelar → si hay deuda, muestra monto y link de pago correcto

### Tests
```bash
cd apps/api
npm test -- --testPathPattern="billing" --verbose
# Resultado esperado: 56 tests passing
```

---

## Notas de seguridad
- Todos los endpoints de debt management son solo `superadmin` (guard + chequeo imperativo)
- Waive debt registra `notes`, `resolved_by` (user id) y crea billing_event de auditoría
- No se exponen SERVICE_ROLE_KEY ni credenciales en frontend
- RLS activo en `cancellation_debt_log` con `server_bypass`

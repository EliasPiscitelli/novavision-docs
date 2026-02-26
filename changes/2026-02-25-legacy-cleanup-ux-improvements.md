# Cambio: Limpieza legacy + mejoras UX admin dashboard

- **Autor:** agente-copilot
- **Fecha:** 2026-02-25
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Repos:** templatetwobe (API), novavision (Admin)

## Archivos modificados

### Backend (API)
- `src/onboarding/onboarding.controller.ts` — Eliminado endpoint legacy `POST /onboarding/approve/:accountId` e import `SuperAdminGuard` huérfano
- `src/onboarding/onboarding.service.ts` — Eliminado método legacy `approveOnboarding()` (~100 líneas)

### Admin Frontend
- `src/pages/AdminDashboard/CouponsView.jsx` — Agregados presets de duración (1-6 meses) con auto-cálculo de `expires_at`, campo numérico de meses + componentes styled `PresetGrid`/`PresetButton`
- `src/pages/BuilderWizard/steps/Step12Success.css` — Agregado fallback `#92400e` a `.status-text` color (era `var(--nv-alert-warning-text)` sin fallback → texto invisible)
- `src/pages/BuilderWizard/steps/Step8ClientData.tsx` — Reemplazados `<select>` nativos por `SearchableSelect` en: país, categoría fiscal, subdivisión/provincia
- `src/components/SearchableSelect/SearchableSelect.tsx` — **NUEVO** componente reutilizable para dropdowns con buscador
- `src/components/SearchableSelect/SearchableSelect.css` — **NUEVO** estilos del componente
- `src/components/SearchableSelect/index.ts` — **NUEVO** barrel export

## Resumen de cambios

### 1. Eliminación de endpoint legacy `approveOnboarding`
El endpoint `POST /onboarding/approve/:accountId` era un flujo de aprobación incompleto que:
- Solo seteaba `state: 'approved'` en `nv_onboarding` y `status: 'approved'` en `nv_accounts`
- Ejecutaba `OnboardingMigrationHelper.migrateToBackendDB()` + `cleanupAdminData()` (migration parcial)
- **NO publicaba la tienda** (no seteaba `is_published = true` en `clients`)
- **NO enviaba welcome email**
- **NO ejecutaba el provisioning completo** (RLS, storage, etc.)

El flujo de producción correcto es `POST /admin/clients/:id/approve` → `AdminService.approveClient()`, que sí hace el saga completo: provisioning, self-healing, cross-DB publish, welcome email.

**Validación:** zero frontend consumers encontrados para el endpoint legacy.

### 2. Presets de cupones en super admin dashboard
- Botones preset para 1-6 meses que auto-setean `free_months` y calculan `expires_at` desde la fecha actual
- Campo numérico de meses que también auto-calcula la expiración
- Se mantienen los campos de fecha manual (`starts_at`/`expires_at`) para períodos custom

### 3. Fix de visibilidad en Step12Success (review step)
- `.status-text` tenía `color: var(--nv-alert-warning-text)` sin fallback
- Las variables CSS `--nv-*` no están definidas en el admin app → texto invisible (color heredaba transparent/default sobre fondo `#fef3c7`)
- Agregado fallback `#92400e` (dark amber) legible sobre el fondo warning

### 4. Selectores con buscador (país, provincia, categoría fiscal)
- Creado componente `SearchableSelect` reutilizable con: dropdown filtrable, click-outside para cerrar, keyboard escape, native `<select>` oculto para form validation
- Aplicado en Step8ClientData.tsx reemplazando los 3 `<select>` nativos

## Por qué

- **Legacy:** El endpoint redundante era un vector de aprobación incompleta que dejaba tiendas en estado "approved" pero no publicadas ni provisionadas. Eliminarlo evita confusión y posibles bugs.
- **Cupones:** El super admin necesitaba una forma rápida de configurar duración sin calcular fechas manualmente.
- **Step12:** Bug visual reportado — texto "24-48 horas" no se leía sobre fondo claro.
- **Selectors:** Con 24 provincias (AR) y futuros países (MX, CO, etc.), el `<select>` nativo es incómodo. El buscador mejora la UX significativamente.

## Cómo probar

### Legacy removal
```bash
# El endpoint ya no responde (debería dar 404):
curl -X POST https://api.novavision.lat/onboarding/approve/test-id -H "Authorization: Bearer ..."
```

### Cupones
1. Super Admin Dashboard → Cupones → + Nuevo Cupón
2. Verificar que los botones de preset (1 mes, 2 meses, etc.) setean `free_months` y calculan `expires_at`
3. Verificar que el campo numérico de meses funciona igual
4. Verificar que editar `expires_at` manualmente sigue funcionando

### Step12
1. Completar wizard hasta el paso 12 (revisión)
2. Verificar que el texto "24-48 horas" es legible (dark amber sobre fondo warning)

### SearchableSelect
1. Ir al paso 8 del wizard (datos del negocio)
2. Verificar que país, categoría fiscal y provincia tienen buscador integrado
3. Escribir parcial para filtrar opciones
4. Click outside cierra el dropdown
5. Escape cierra el dropdown

## Validación técnica

```bash
# API
npm run lint      # 0 errors
npm run typecheck # ✅ clean
npm run build     # ✅ clean

# Admin
npm run lint      # 0 errors, 0 warnings
npm run typecheck # ✅ clean
```

## Notas de seguridad
- El endpoint legacy eliminado era protegido por `SuperAdminGuard`, no era accesible sin auth
- El endpoint de producción `POST /admin/clients/:id/approve` sigue intacto y funcional
- `OnboardingMigrationHelper` queda como código muerto (solo era llamado desde `approveOnboarding`). Se puede remover en un futuro cleanup.

---

## Fixes de flujo de aprobación y suscripciones (misma fecha)

### Archivos adicionales modificados

#### Backend (API)
- `src/admin/admin.service.ts` — Wrapped post-saga steps (nv_onboarding update, welcome email, checklist, events) en try/catch no-bloqueante
- `src/admin/admin.controller.ts` — `pauseClient` ahora sincroniza `store_paused` a `nv_accounts` (Admin DB)
- `src/subscriptions/subscriptions.service.ts` — Agregado check D5 `plan_key` mismatch en `reconcileCrossDb`; cambiado lookup de `slug` a `nv_account_id` en `syncEntitlementsAfterUpgrade` y `syncEntitlementsAfterCancel`
- `src/outbox/outbox-worker.service.ts` — `handlePlanChanged` ahora prefiere `nv_account_id` como lookup key, fallback a `slug`

### Bugs corregidos

| # | Severidad | Fix |
|---|-----------|-----|
| 1 | **ALTO** | `reconcileCrossDb` D5: sincroniza `plan_key` cuando difiere entre Admin DB y Backend DB — antes era un desync permanente |
| 2 | **MEDIO** | `syncEntitlementsAfterUpgrade/Cancel` + outbox `plan.changed`: lookup por `nv_account_id` en vez de `slug` — evita fallo silencioso si el slug está desincronizado |
| 3 | **MEDIO** | `approveClient` post-saga: `nv_onboarding.state='live'`, welcome email, checklist/events ahora están en try/catch — aprobación no falla si alguno de estos pasos secundarios falla |
| 4 | **BAJO** | `pauseClient` (admin controller): ahora sincroniza `nv_accounts.store_paused=true` — antes solo pausaba en Backend DB, causando desync restaurable solo por cron |

### Gap funcional reportado (NO implementado — requiere definición de producto)
- **No existe endpoint de super admin para cambiar plan**: Si se necesita forzar un cambio de plan (upgrade gratuito, downgrade de emergencia), no hay forma desde el admin dashboard. Solo el owner puede vía su storefront. Requiere diseño de endpoint + UI.

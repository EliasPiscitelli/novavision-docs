# Plan: Billing Automation — Completar el pipeline de facturación

**Fecha:** 2026-02-24  
**Autor:** agente-copilot  
**Rama:** `feature/automatic-multiclient-onboarding`  
**Repos afectados:** API (templatetwobe), Admin (novavision), Web (templatetwo), Docs

---

## 1. Resumen ejecutivo

El sistema de billing/quotas está **estructuralmente armado** (tablas, crons, guards, services) pero **operativamente inactivo**. Este plan documenta e implementa las 8 correcciones necesarias para que el pipeline funcione end-to-end.

### Estado actual

| Componente | Estado | Detalles |
|------------|--------|----------|
| Tablas DB | ✅ Completas | `billing_adjustments`, `usage_rollups_monthly`, `quota_state`, `subscription_notification_outbox`, `plans`, `subscriptions` |
| UsageConsolidationCron | ⚠️ Parcial | Funciona, pero `orders_gmv_usd` siempre = 0 |
| QuotaEnforcementService | ⚠️ Desactivado | `ENABLE_QUOTA_ENFORCEMENT=false` por defecto |
| GmvCommissionCron | ❌ Roto | Lee `orders_gmv_usd` que siempre es 0 → comisiones nunca se cobran |
| OverageService | ⚠️ Parcial | Solo orders + egress; falta requests + storage |
| CostRollupCron | ⚠️ Hardcoded | Coeficientes fijos, no lee fee_schedules |
| Notification Consumer | ❌ No existe | Outbox se llena, nadie la procesa → emails nunca se envían |
| Auto-charge cron | ❌ No existe | Solo manual vía admin endpoint |
| Quota reset automático | ❌ No existe | Solo manual vía admin endpoint |
| FX Rates | ❌ 4/6 rotos | frankfurter.app no soporta CLP, COP, UYU, PEN |
| T&C / Billing disclosure | ❌ Ausente | No se informa al cliente sobre comisiones, overages, límites |

---

## 2. Gaps y correcciones (8 items)

### Gap 1: FX Rates — 4 monedas LATAM sin cotización automática

**Problema:** frankfurter.app usa datos del ECB (Banco Central Europeo) que solo publica ~33 monedas. **CLP, COP, UYU, PEN no están incluidas.** Solo MXN (sí está en ECB) y AR (usa dolarapi.com) funcionan.

**Solución:** Migrar las 4 monedas a **exchangerate-api.com** (free tier: 1500 req/mo, soporta TODAS las LATAM).

| País | API actual | API nueva | Endpoint |
|------|-----------|-----------|----------|
| AR | dolarapi.com ✅ | Sin cambio | `https://dolarapi.com/v1/dolares/oficial` |
| MX | frankfurter.app ✅ | Sin cambio | `https://frankfurter.app/latest?from=USD&to=MXN` |
| CL | frankfurter.app ❌ | exchangerate-api.com | `https://open.er-api.com/v6/latest/USD` → `.rates.CLP` |
| CO | frankfurter.app ❌ | exchangerate-api.com | `https://open.er-api.com/v6/latest/USD` → `.rates.COP` |
| UY | frankfurter.app ❌ | exchangerate-api.com | `https://open.er-api.com/v6/latest/USD` → `.rates.UYU` |
| PE | frankfurter.app ❌ | exchangerate-api.com | `https://open.er-api.com/v6/latest/USD` → `.rates.PEN` |

**Archivos a tocar:**
- `migrations/admin/ADMIN_088_fix_fx_rates_endpoints.sql` — actualizar `fx_rates_config` con nuevos endpoints
- Sin cambios en `fx.service.ts` (ya soporta `auto_field_path` genérico como `rates.CLP`)

**Migración SQL:**
```sql
-- ADMIN_088: Fix FX rates for CL, CO, UY, PE
-- exchangerate-api.com free tier supports all LATAM currencies
UPDATE fx_rates_config SET
  auto_endpoint = 'https://open.er-api.com/v6/latest/USD',
  auto_field_path = 'rates.CLP',
  last_error = NULL
WHERE country_id = 'CL';

UPDATE fx_rates_config SET
  auto_endpoint = 'https://open.er-api.com/v6/latest/USD',
  auto_field_path = 'rates.COP',
  last_error = NULL
WHERE country_id = 'CO';

UPDATE fx_rates_config SET
  auto_endpoint = 'https://open.er-api.com/v6/latest/USD',
  auto_field_path = 'rates.UYU',
  last_error = NULL
WHERE country_id = 'UY';

UPDATE fx_rates_config SET
  auto_endpoint = 'https://open.er-api.com/v6/latest/USD',
  auto_field_path = 'rates.PEN',
  last_error = NULL
WHERE country_id = 'PE';
```

**Test:**
```bash
# Verificar que la API soporta las monedas
curl -s 'https://open.er-api.com/v6/latest/USD' | jq '.rates | {CLP, COP, UYU, PEN}'
# Esperado: {"CLP": ~950, "COP": ~4200, "UYU": ~42, "PEN": ~3.75}

# Después de aplicar la migración, forzar refresh desde admin:
curl -X POST "$API_URL/admin/fx/rates/CL/refresh" -H "Authorization: Bearer $TOKEN" -H "x-internal-key: $KEY"
curl -X POST "$API_URL/admin/fx/rates/CO/refresh" -H "Authorization: Bearer $TOKEN" -H "x-internal-key: $KEY"
curl -X POST "$API_URL/admin/fx/rates/UY/refresh" -H "Authorization: Bearer $TOKEN" -H "x-internal-key: $KEY"
curl -X POST "$API_URL/admin/fx/rates/PE/refresh" -H "Authorization: Bearer $TOKEN" -H "x-internal-key: $KEY"
```

---

### Gap 2: GMV Pipeline — `orders_gmv_usd` nunca se popula

**Problema:** `UsageConsolidationCron` escritura `orders_gmv_usd: 0` con el comentario `"Populated by Fase 4 GmvCommissionCron"`. Pero `GmvCommissionCron` solo LEE este campo, no lo escribe. El pipeline está roto.

**Solución:** Después de consolidar usage diario, hacer una segunda pasada que sume orders `paid/approved` del mes × FX rate → USD y actualice `orders_gmv_usd`.

**Archivo a tocar:** `src/billing/usage-consolidation.cron.ts`

**Lógica:**
```
Para cada tenant:
  1. Obtener orders del Backend DB con status 'paid'|'approved' del mes
  2. Agrupar por currency → sumar totales
  3. Convertir cada total a USD usando FxService
  4. Sumar todo → orders_gmv_usd
  5. Actualizar usage_rollups_monthly
```

**Dependencia:** Requiere inyectar `FxService` en `UsageConsolidationCron` (o crear un `GmvPipelineCron` separado).

**Decisión:** Crear cron separado `GmvPipelineCron` que se ejecute a las 02:45 UTC (después de consolidation a las 02:30 y antes de quota enforcement a las 03:00).

**Test:**
```bash
# Manualmente ejecutar el pipeline para un período
curl -X POST "$API_URL/admin/billing/gmv-pipeline" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-internal-key: $KEY" \
  -d '{"periodStart":"2026-02-01"}'

# Verificar que orders_gmv_usd ya no es 0
PGPASSWORD="..." psql -h db.erbfzlsznqsmwmjugspo.supabase.co -U postgres -d postgres \
  -c "SELECT tenant_id, orders_gmv_usd FROM usage_rollups_monthly WHERE period_start='2026-02-01' AND orders_gmv_usd > 0;"
```

---

### Gap 3: Notification Consumer — outbox sin procesador

**Problema:** `QuotaEnforcementService.enqueueNotification()` escribe a `subscription_notification_outbox` con `status='pending'`, pero no existe ningún servicio que lea, procese y envíe estas notificaciones.

**Solución:** Crear `NotificationDrainCron` que:
1. Lea outbox con `status='pending'`
2. Genere el contenido del email según `notif_type`
3. Inserte en `email_jobs` (admin DB) para que el `EmailJobsWorker` existente la envíe
4. Marque como `sent` en la outbox

**Archivo nuevo:** `src/billing/notification-drain.cron.ts`

**Schedule:** Cada 5 minutos (`*/5 * * * *`)

**Tipos de notificación y contenido:**

| notif_type | Asunto | Contenido |
|------------|--------|-----------|
| `quota_warn_50` | Tu tienda alcanzó el 50% de uso | "Estás usando {X}% de tus recursos del plan {Plan}. Podés ver los detalles..." |
| `quota_warn_75` | Tu tienda alcanzó el 75% de uso | "Estás usando {X}% de tus recursos. Considerá actualizar tu plan..." |
| `quota_warn_90` | ⚠️ Tu tienda está al 90% de capacidad | "Estás cercano al límite. Actualizá tu plan para evitar restricciones..." |
| `quota_soft_limit` | Tu tienda superó el límite de uso | "Superaste los límites de tu plan. Tenés {grace_days} días de gracia..." |
| `quota_grace` | Periodo de gracia activo | "Tu periodo de gracia finaliza el {grace_until}. Actualizá o contactanos..." |
| `quota_hard_limit` | 🚫 Tienda restringida por límite de uso | "Tu tienda fue restringida. Las operaciones de escritura están bloqueadas..." |

**Email doble:** Cada notificación genera 2 emails:
1. Al **cliente** (merchant) — notificación informativa
2. Al **admin** (NovaVision) — alerta interna para seguimiento

**Test:**
```sql
-- Insertar notificación de prueba en outbox
INSERT INTO subscription_notification_outbox (account_id, notif_type, channel, payload, status, scheduled_for)
VALUES ('TEST_TENANT', 'quota_warn_75', 'email', '{"email":"test@test.com","name":"Test","state":"WARN_75","usage_percent":78}', 'pending', NOW());

-- Esperar 5 minutos y verificar que se procesó
SELECT status, sent_at FROM subscription_notification_outbox WHERE account_id='TEST_TENANT';
-- Verificar email_job creado
SELECT * FROM email_jobs WHERE type = 'quota_notification' ORDER BY created_at DESC LIMIT 2;
```

---

### Gap 4: Auto-charge Cron

**Problema:** `BillingService.chargeAllPendingAutoCharge()` existe y funciona, pero solo se invoca manualmente desde `POST /admin/adjustments/bulk-charge`.

**Solución:** Crear cron que lo invoque automáticamente el día 5 de cada mes.

**Archivo nuevo:** `src/billing/auto-charge.cron.ts`  
**Schedule:** `0 8 5 * *` (día 5, 08:00 UTC)

**Test:**
```bash
# Invocar manualmente para verificar
curl -X POST "$API_URL/admin/adjustments/bulk-charge" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-internal-key: $KEY"
```

---

### Gap 5: Quota Reset Automático

**Problema:** `quota_state` nunca se resetea a `ACTIVE` al inicio del período. Solo manual vía `POST /admin/quotas/:tenantId/reset`.

**Solución:** Agregar lógica de reset al inicio del `UsageConsolidationCron` o crear un mini-cron dedicado.

**Decisión:** Agregar al cron de consolidation (día 1 del mes): si es el primer día del mes, antes de consolidar, resetear todos los `quota_state` a `ACTIVE`.

**Archivo:** `src/billing/usage-consolidation.cron.ts` (modificar)

**Lógica:**
```typescript
// Al inicio de consolidate(), si es día 1:
if (now.getDate() === 1) {
  await this.resetQuotaStates(adminClient);
}
```

**Test:**
```sql
-- Verificar quota_state después de día 1
SELECT tenant_id, state, last_evaluated_at FROM quota_state;
-- Todos deben estar en 'ACTIVE' después de ejecutar el cron el día 1
```

---

### Gap 6: Overage Requests + Storage

**Problema:** `OverageService` solo calcula `overage_orders` y `overage_egress`. Los tipos `overage_requests` y `overage_storage` existen como válidos en la DB (CHECK constraint) pero nunca se calculan.

**Solución:** Extender `calculateTenantOverage()` para incluir las 4 dimensiones.

**Archivo:** `src/billing/overage.service.ts`

**Rates a agregar:**
```typescript
const OVERAGE_RATES: Record<string, OverageRates> = {
  growth: {
    orderRate: 0.015,      // USD per extra order
    egressRate: 0.08,      // USD per extra GB egress
    requestRate: 0.0002,   // USD per 1K extra API requests ($0.20/1M)
    storageRate: 0.021,    // USD per extra GB storage/month
  },
};
```

**Archivo DB:** `usage_rollups_monthly` ya tiene `api_calls` y `storage_gb_avg` → ya hay datos.

**Test:**
```bash
# Recalcular overages para un período
curl -X POST "$API_URL/admin/adjustments/recalculate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "x-internal-key: $KEY" \
  -d '{"periodStart":"2026-02-01"}'
```

---

### Gap 7: T&C — Disclosure de comisiones y límites

**Problema:** Los Términos y Condiciones (tanto onboarding como admin dashboard) no mencionan:
- Comisión sobre GMV (2% Growth, excedente sobre $40K)
- Cargos por exceso de recursos (overages)
- Límites por plan
- Política de suspensión por cuota excedida

**Solución:** Agregar sección "6b. Límites de Uso, Comisiones y Cargos Adicionales" a los T&C en:
1. `apps/admin/src/pages/BuilderWizard/steps/Step9Terms.tsx` (onboarding corto)
2. `apps/admin/src/pages/BuilderWizard/steps/Step11Terms.tsx` (onboarding largo)
3. `apps/admin/src/components/TermsConditions/index.jsx` (admin dashboard)
4. `apps/web/src/components/TermsConditions/index.jsx` (web storefront — sección relevante para compradores)

**Contenido nuevo (sección 6b):**
```
6b. Límites de Uso, Comisiones y Cargos Adicionales

Cada plan incluye una asignación mensual de recursos (órdenes, almacenamiento,
ancho de banda y solicitudes API). Al superar estos límites:

• Plan Starter: las operaciones de escritura se restringen hasta el inicio
  del siguiente período de facturación. No se aplican cargos adicionales.

• Plan Growth: se aplican cargos por exceso según las tarifas vigentes
  publicadas en novavision.lat/pricing. Se otorga un período de gracia
  de 14 días antes de aplicar restricciones.

• Plan Enterprise: tarifas de excedente negociables según tu contrato.
  Período de gracia de 30 días.

Comisión sobre volumen de ventas (GMV):
Los planes Growth aplican una comisión del 2% sobre el volumen de ventas
(GMV) mensual que supere el umbral establecido en tu plan (actualmente
USD $40.000). Esta comisión se calcula mensualmente y se factura como
cargo adicional.

NovaVision te notificará por email cuando tu uso alcance el 50%, 75% y
90% de los límites incluidos en tu plan, y al superar el 100%.

Para más detalles sobre límites y tarifas vigentes, consultá
novavision.lat/pricing o contactanos a novavision.contact@gmail.com.
```

**Bump versión T&C:** `2.0` → `2.1`

---

### Gap 8: Enable QUOTA_ENFORCEMENT (preparación)

**Problema:** `ENABLE_QUOTA_ENFORCEMENT=false` por defecto. El sistema está apagado.

**Solución (staging first):**
1. Activar en env de Railway con `ENABLE_QUOTA_ENFORCEMENT=true`
2. Monitorear logs por 1 semana
3. Verificar que no hay false positives
4. Activar en producción

**Esto NO requiere cambios de código**, solo configuración de env var. Se documenta pero se deja para el TL.

---

## 3. Orden de implementación

```
Fase A — Fixes inmediatos (hoy)
├── A.1  ADMIN_088: Fix FX rates endpoints (SQL migration)
├── A.2  GMV Pipeline cron (nuevo archivo)
├── A.3  Notification drain cron (nuevo archivo)
├── A.4  Auto-charge cron (nuevo archivo)
├── A.5  Quota reset automático (modificar consolidation cron)
├── A.6  Overage requests + storage (modificar overage.service.ts)
├── A.7  Registrar nuevos providers en billing.module.ts
└── A.8  T&C update (3 archivos admin + 1 web)

Fase B — Validación
├── B.1  lint + typecheck + build (API)
├── B.2  lint + typecheck (Admin)
└── B.3  Tests manuales (curl, SQL)

Fase C — Deploy (con confirmación TL)
├── C.1  Commit + push
├── C.2  Aplicar ADMIN_088 en DB
├── C.3  Verificar FX rates en dashboard
└── C.4  Monitorear crons en logs Railway
```

---

## 4. Plan de pruebas

### Test 1: FX Rates
```bash
# Pre-migración: verificar que frankfurter falla
curl -s 'https://frankfurter.app/latest?from=USD&to=CLP' | head -5
# Post-migración: verificar que exchangerate-api funciona
curl -s 'https://open.er-api.com/v6/latest/USD' | jq '.rates.CLP'
```

### Test 2: GMV Pipeline
```bash
# Invocar manualmente y verificar
curl -X POST "$API_URL/admin/billing/gmv-pipeline" \
  -H "x-internal-key: $INTERNAL_KEY"
# Verificar en DB
PGPASSWORD="..." psql -h db.erbfzlsznqsmwmjugspo.supabase.co -U postgres \
  -c "SELECT tenant_id, orders_gmv_usd FROM usage_rollups_monthly WHERE orders_gmv_usd > 0;"
```

### Test 3: Notification Drain
```sql
-- Insertar notif de test
INSERT INTO subscription_notification_outbox (account_id, notif_type, channel, payload, status, scheduled_for)
VALUES ('00000000-0000-0000-0000-000000000001', 'quota_warn_50', 'email',
  '{"email":"test@example.com","name":"Test Tenant","state":"WARN_50","usage_percent":52}',
  'pending', NOW());
-- Esperar procesamiento y verificar
SELECT status FROM subscription_notification_outbox WHERE account_id='00000000-0000-0000-0000-000000000001';
```

### Test 4: Auto-charge
```bash
# Verificar que el endpoint funciona
curl -X POST "$API_URL/admin/adjustments/bulk-charge" \
  -H "x-internal-key: $INTERNAL_KEY"
# Respuesta esperada: {"charged":0,"errors":0,"results":[]}
```

### Test 5: Overage completo
```bash
# Recalcular para período actual
curl -X POST "$API_URL/admin/adjustments/recalculate" \
  -H "x-internal-key: $INTERNAL_KEY" \
  -d '{"periodStart":"2026-02-01"}'
```

### Test 6: T&C
- Abrir onboarding wizard → verificar sección 6b en Step9Terms
- Abrir admin dashboard → verificar sección 6b en TermsConditions
- Verificar versión = 2.1

---

## 5. Archivos nuevos

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `migrations/admin/ADMIN_088_fix_fx_rates_endpoints.sql` | Migration | Fix FX rates endpoints para CL/CO/UY/PE |
| `src/billing/gmv-pipeline.cron.ts` | Cron | Pipeline GMV: orders → FX → USD → usage_rollups_monthly |
| `src/billing/auto-charge.cron.ts` | Cron | Auto-charge adjustments el día 5 |

**Nota:** `notification-drain.cron.ts` NO fue necesario. El consumidor ya existía en `subscriptions.service.ts` (`dispatchLifecycleNotifications()` cada 10 min). Solo se enriquecieron los payloads y se agregaron 6 templates de quota.

## 6. Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/billing/billing.module.ts` | Registrar 2 nuevos providers (GmvPipelineCron, AutoChargeCron) |
| `src/billing/overage.service.ts` | Agregar overage_requests + overage_storage (4 dimensiones completas) |
| `src/billing/usage-consolidation.cron.ts` | Agregar quota reset automático el día 1 |
| `src/billing/quota-enforcement.service.ts` | Enriquecer payload notificaciones con slug/storeName/accountId |
| `src/onboarding/onboarding-notification.service.ts` | Agregar 6 templates de email para quotas (warn_50/75/90, soft/grace/hard_limit) |
| `apps/admin/src/pages/BuilderWizard/steps/Step9Terms.tsx` | Agregar sección 6b + bump v2.1 |
| `apps/admin/src/pages/BuilderWizard/steps/Step11Terms.tsx` | Agregar sección 6b + bump v2.1 |
| `apps/admin/src/components/TermsConditions/index.jsx` | Agregar sección VII billing disclosure (es + en) |
| `apps/web/src/components/TermsConditions/index.jsx` | Agregar sección XI plataforma y servicios tecnológicos |

---

## 7. Riesgos y mitigaciones

| Riesgo | Probabilidad | Impacto | Mitigación |
|--------|-------------|---------|------------|
| exchangerate-api.com rate limit (1500 req/mo free) | Baja | Medio | Cache TTL 60min reduce a ~720 req/mo para 6 countries. Fallback a last_auto_rate |
| GMV Pipeline FX rate stale | Baja | Bajo | Ya hay 5 niveles de fallback en FxService |
| Auto-charge cobra doble | Baja | Alto | `chargeAllPendingAutoCharge` ya es idempotente (solo cobra status='pending') |
| Quota reset pierde estado | Media | Medio | Solo resetea si es día 1; el enforcement re-evalúa inmediatamente después |
| Notification spam | Baja | Medio | Outbox usa upsert con `ignoreDuplicates` — max 1 notif por tipo por período |

---

## 8. Timeline estimado

| Fase | Duración | Estado |
|------|----------|--------|
| A.1 FX Rates migration | 15 min | ✅ Aplicada a DB |
| A.2 GMV Pipeline cron | 45 min | ✅ `gmv-pipeline.cron.ts` |
| A.3 Notification consumer | — | ✅ Ya existía; se enriquecieron payloads + 6 templates |
| A.4 Auto-charge cron | 15 min | ✅ `auto-charge.cron.ts` |
| A.5 Quota reset | 15 min | ✅ En `usage-consolidation.cron.ts` |
| A.6 Overage completo (4 dim) | 30 min | ✅ En `overage.service.ts` |
| A.7 Module registration | 5 min | ✅ En `billing.module.ts` |
| A.8 T&C update | 30 min | ✅ 4 archivos (Step9, Step11, Admin T&C, Web T&C) |
| B Validación | 30 min | ✅ lint + typecheck + build OK (API, Admin, Web) |
| **Total real** | **~3.5 horas** | **✅ COMPLETADO 2026-02-24** |

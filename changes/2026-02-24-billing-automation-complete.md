# Cambio: Billing Automation Pipeline — Implementación completa

- **Autor:** agente-copilot
- **Fecha:** 2026-02-24
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Repos:** API (templatetwobe), Admin (novavision), Web (templatetwo), Docs (novavision-docs)

## Archivos nuevos

| Repo | Archivo | Propósito |
|------|---------|-----------|
| API | `src/billing/gmv-pipeline.cron.ts` | Cron diario 02:45 UTC — calcula GMV en USD por tenant |
| API | `src/billing/auto-charge.cron.ts` | Cron día 5 08:00 UTC — cobra billing_adjustments pendientes |
| API | `migrations/admin/ADMIN_088_fix_fx_rates_endpoints.sql` | Fix endpoints FX (CL/CO/UY/PE → exchangerate-api.com) |

## Archivos modificados

| Repo | Archivo | Cambio |
|------|---------|--------|
| API | `src/billing/billing.module.ts` | +2 providers: GmvPipelineCron, AutoChargeCron |
| API | `src/billing/overage.service.ts` | +4 dimensiones: orders, egress, requests, storage |
| API | `src/billing/usage-consolidation.cron.ts` | +quota reset automático día 1 de cada mes |
| API | `src/billing/quota-enforcement.service.ts` | +enriquecimiento payload notificaciones quota |
| API | `src/onboarding/onboarding-notification.service.ts` | +6 templates email quota (warn_50/75/90, soft/grace/hard_limit) |
| Admin | `src/pages/BuilderWizard/steps/Step9Terms.tsx` | v2.0→2.1, +sección 6b límites y comisiones |
| Admin | `src/pages/BuilderWizard/steps/Step11Terms.tsx` | v2.0→2.1, +sección 6b límites y comisiones |
| Admin | `src/components/TermsConditions/index.jsx` | +sección VII billing disclosure (es + en) |
| Web | `src/components/TermsConditions/index.jsx` | +sección XI plataforma y servicios tecnológicos |
| Docs | `plans/PLAN_BILLING_AUTOMATION_COMPLETE.md` | Plan completo con estado final ✅ |

## Resumen de cambios

Se corrigieron los **8 gaps identificados** en la auditoría del sistema de billing:

1. **FX Rates (CL/CO/UY/PE)**: Migrados de frankfurter.app (que no los soporta) a open.er-api.com
2. **GMV Pipeline**: Nuevo cron que lee órdenes pagadas/aprobadas, convierte a USD via FxService, actualiza usage_rollups
3. **Notification consumer**: Ya existía en `subscriptions.service.ts` — se enriquecieron payloads y se agregaron 6 templates
4. **Auto-charge**: Nuevo cron que cobra adjustments pendientes de forma automática
5. **Quota reset**: Resetea quota_state a 'ACTIVE' el día 1 de cada mes
6. **Overage 4 dimensiones**: Extendido de 2 (orders+egress) a 4 (+requests+storage)
7. **T&C billing disclosure**: Informamos al usuario final sobre límites, comisiones y cargos
8. **T&C plataforma (web)**: Disclosure de que NovaVision provee infraestructura

## Por qué se hizo

El pipeline de billing estaba **estructuralmente completo** (tablas, services, guards) pero **operativamente inactivo**. Sin estos cambios:
- GMV siempre era $0 → comisiones nunca se cobraban
- 4 monedas LATAM no tenían tipo de cambio → billing no calculaba USD
- Los emails de quota nunca se enviaban (payload incompatible)
- No había auto-charge → requería intervención manual cada mes
- No había quota reset → estados quedaban stale
- Overages solo cubrían 2 de 4 dimensiones
- No había disclosure legal sobre comisiones en T&C

## Cómo probar

### FX Rates
```bash
curl -s -H "x-internal-key: $INTERNAL_ACCESS_KEY" \
  https://templatetwobe-production.up.railway.app/admin/fx-rates/CL | jq .
# Debe devolver rate ~865 (CLP/USD)
```

### GMV Pipeline (manual trigger via NestJS REPL o esperar 02:45 UTC)
- Verificar en `usage_rollups_monthly` que `orders_gmv_usd` > 0 para tenants con órdenes

### Quota Templates
- En `onboarding-notification.service.ts`, las 6 templates están registradas como `quota_warn_50`, `quota_warn_75`, `quota_warn_90`, `quota_soft_limit`, `quota_grace`, `quota_hard_limit`
- Verificar que `dispatchLifecycleNotifications()` las procesa cuando hay entries en `subscription_notification_outbox`

### T&C
- Onboarding wizard: Step 9 y 11 deben mostrar sección "6b. Límites de Uso..."
- Admin dashboard: T&C debe mostrar sección VII (español e inglés)
- Web storefront: T&C debe mostrar sección XI

## Validación ejecutada

```
API:   lint ✅ (0 errors)  |  typecheck ✅  |  build ✅
Admin: lint ✅ (0 errors)  |  typecheck ✅  |  build ✅ (chunks warning preexistente)
Web:   lint ✅ (0 errors)  |  typecheck ✅  |  build ✅ (chunks warning preexistente)
```

## Notas de seguridad

- `ENABLE_QUOTA_ENFORCEMENT` sigue en `false` por defecto — no se activa enforcement hasta habilitación manual
- Migración ADMIN_088 ya fue aplicada a la DB de producción
- No se exponen SERVICE_ROLE_KEY en ningún archivo frontend
- Auto-charge es idempotente (solo procesa status='pending')

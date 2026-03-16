# Custom Domain System — Fase 3-4

**Fecha:** 2026-03-16
**Autor:** Equipo NovaVision

## Resumen

Implementación de audit trail, Domain Center para tenants, herramientas de administración avanzadas, sistema de notificaciones por email, fix del flujo de pago, observabilidad de crons, y T&C/disclaimers.

## WS1: Audit Trail para operaciones de dominio

- **admin.service.ts**: Agregados `lifecycleEvents.emit()` en `setCustomDomain()`, `removeCustomDomain()`, `verifyCustomDomain()`
- **managed-domain.service.ts**: Inyectado `LifecycleEventsService`. Emisión en `provisionDomain()`, `quoteRenewal()`, `createRenewalPreference()`, `handleRenewalWebhook()`
- **Test**: `domain-audit-trail.spec.ts` — ~15 casos cubriendo happy paths y edge cases

### Event Types nuevos:
| Event Type | Source | Método |
|------------|--------|--------|
| `custom_domain.set` | admin | setCustomDomain |
| `custom_domain.removed` | admin | removeCustomDomain |
| `custom_domain.verified` | cron | verifyCustomDomain |
| `custom_domain.config_reset` | admin | resetDomainDnsStatus |
| `custom_domain.config_unlocked` | admin | unlockDomainConfig |
| `managed_domain.provisioned` | admin | provisionDomain |
| `managed_domain.quoted` | system | quoteRenewal |
| `managed_domain.invoice_created` | admin | createRenewalPreference |
| `managed_domain.paid` | webhook | handleRenewalWebhook |

## WS2: Domain Center en Tenant Admin Dashboard

- **IdentityConfigSection**: Tab "Dominio" transformado de read-only a condicional con 3 estados:
  1. Formulario de configuración (plan Growth+, config disponible)
  2. Mensaje "contactar soporte" (config ya usada o plan Starter)
  3. Read-only con badge de estado y instrucciones DNS
- **identityService**: Nuevo método `configureDomain()`
- **client-dashboard.controller.ts**: Nuevo endpoint `POST /client-dashboard/domain/configure`
- **client-dashboard.service.ts**: Método `configureDomain()` con validación de `custom_domain_self_config` y delegación a AdminService

## WS3: Super Admin — Reset DNS + Unlock Config

- **admin.service.ts**: Nuevos métodos `resetDomainDnsStatus()` y `unlockDomainConfig()`
- **admin.controller.ts**: Nuevos endpoints:
  - `POST /admin/accounts/:id/custom-domain/reset-status`
  - `POST /admin/accounts/:id/custom-domain/unlock-config`
- **ClientApprovalDetail.jsx**: Botones "Resetear DNS" y "Habilitar re-configuración" en la pestaña Dominio
- **adminApi.js**: Métodos `resetDomainDnsStatus()` y `unlockDomainConfig()`

## WS4: T&C y Disclaimers

- **domain-terms.js** (Web): Constantes de texto para disclaimers concierge/self-service/shared
- **domain-terms.ts** (Admin): Mismas constantes en TypeScript
- **IdentityConfigSection**: Disclaimer dinámico según modo + checkbox de aceptación obligatorio
- **Step9Summary.tsx**: Disclaimer agregado en el formulario de dominio del onboarding

## WS5: Observabilidad de Crons

- **managed-domain.service.ts**: `checkExpirations()` retorna `{ processed, quoted, errors[] }`, `checkPendingDns()` retorna `{ processed, verified, stillPending, errors[] }`
- **managed-domain.cron.ts**: Logging JSON estructurado con `{ cron, processed, quoted/verified, errors, durationMs }`
- **custom-domain-verifier.cron.ts**: Mismo patrón de logging JSON

## WS6: DomainNotificationService + Email Templates

- **domain-notification.service.ts** (nuevo): 6 templates + 1 confirmación de pago
- **admin-renewals.controller.ts**: TODO reemplazado — ahora usa `DomainNotificationService.sendByTemplate()`
- **admin.module.ts**: Registrado `DomainNotificationService` como provider

### Templates de email:
| Template | Asunto |
|----------|--------|
| `90_days` | Tu dominio {domain} vence en ~90 días |
| `30_days` | Tu dominio {domain} vence pronto |
| `7_days` | URGENTE: {domain} vence en 7 días |
| `invoice_created` | Renovación lista: {domain} |
| `renewal_failed` | No pudimos renovar {domain} |
| `manual_required` | Renovación requiere intervención: {domain} |

## WS7: Fix Payment Flow (BillingService gap)

- **managed-domain.service.ts**: `handleRenewalWebhook()` ahora cierra el BillingEvent asociado y crea uno retroactivo si no existe
- **billing.service.ts**: Nuevos métodos `findByMetadata()` y `markAsPaid()`
- Email de confirmación de pago enviado automáticamente

## WS8: Documentación

- **ENV_INVENTORY.md**: Inventario de variables de entorno por servicio
- **ROUTING_RULES.md**: Flujo de resolución de tenants, CNAME setup, diagrama de estados

## Migración DB requerida

```sql
ALTER TABLE nv_accounts ADD COLUMN IF NOT EXISTS custom_domain_self_config boolean DEFAULT true;
```

## Archivos nuevos (~12)

| Archivo | WS |
|---------|-----|
| `apps/api/src/admin/domain-notification.service.ts` | WS6 |
| `apps/api/src/admin/__tests__/domain-audit-trail.spec.ts` | WS1 |
| `apps/web/src/config/domain-terms.js` | WS4 |
| `apps/admin/src/config/domain-terms.ts` | WS4 |
| `novavision-docs/architecture/ENV_INVENTORY.md` | WS8 |
| `novavision-docs/architecture/ROUTING_RULES.md` | WS8 |

## Archivos modificados (~14)

| Archivo | WS |
|---------|-----|
| `apps/api/src/admin/admin.service.ts` | WS1, WS3 |
| `apps/api/src/admin/admin.controller.ts` | WS3 |
| `apps/api/src/admin/managed-domain.service.ts` | WS1, WS5, WS7 |
| `apps/api/src/admin/managed-domain.cron.ts` | WS5 |
| `apps/api/src/admin/admin-renewals.controller.ts` | WS6 |
| `apps/api/src/admin/admin.module.ts` | WS6 |
| `apps/api/src/billing/billing.service.ts` | WS7 |
| `apps/api/src/cron/custom-domain-verifier.cron.ts` | WS5 |
| `apps/api/src/client-dashboard/client-dashboard.controller.ts` | WS2 |
| `apps/api/src/client-dashboard/client-dashboard.service.ts` | WS2 |
| `apps/web/src/components/admin/IdentityConfigSection/index.jsx` | WS2, WS4 |
| `apps/web/src/services/identity.js` | WS2 |
| `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx` | WS3 |
| `apps/admin/src/pages/BuilderWizard/steps/Step9Summary.tsx` | WS4 |
| `apps/admin/src/services/adminApi.js` | WS3 |

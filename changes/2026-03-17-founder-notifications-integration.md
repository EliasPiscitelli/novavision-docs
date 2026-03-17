# Integración FounderNotifications en flujos de negocio

**Fecha:** 2026-03-17
**Branch:** feature/multitenant-storefront
**Fase:** Marketing OS — Fase 2 (Notificaciones)
**Impacto:** API (NestJS)

---

## Resumen

Se integró `FounderNotificationsService` (WhatsApp Cloud API) en 4 flujos de negocio críticos para que el founder reciba alertas en tiempo real sin depender del dashboard.

## Cambios

### Módulos actualizados

| Archivo | Cambio |
|---------|--------|
| `src/onboarding/onboarding.module.ts` | Import `FounderNotificationsModule` |
| `src/subscriptions/subscriptions.module.ts` | Import `FounderNotificationsModule` |

### Servicios modificados

| Archivo | Cambio |
|---------|--------|
| `src/onboarding/onboarding.service.ts` | Inyección de `FounderNotificationsService` + 2 notificaciones |
| `src/subscriptions/subscriptions.service.ts` | Inyección de `FounderNotificationsService` + 2 notificaciones |

### 4 Notificaciones WA al Founder

| Evento | Método | Ubicación | Datos enviados |
|--------|--------|-----------|----------------|
| Cuenta nueva registrada | `sendAlert()` | `startDraftBuilder()` ~L771 | email, slug deseado, account_id |
| Onboarding completado | `sendReport()` | `submitForReview()` ~L2784 | email, slug, template, plan |
| Pago suscripción recibido | `sendReport()` | `handlePaymentSuccess()` ~L2964 | email, plan, monto, sub_id |
| Pago suscripción fallido | `sendAlert()` | `handlePaymentFailed()` ~L3051 | email, motivo, intentos, estado |

### Tests

| Archivo | Cobertura |
|---------|-----------|
| `src/founder-notifications/founder-notifications.service.spec.ts` | Nuevo — 10 tests: servicio base + 4 contratos de integración |

## Patrón utilizado

**Fire-and-forget dual**: Las llamadas a WA no bloquean el flujo de negocio. El servicio maneja errores internamente (devuelve `false`), y un `try/catch` exterior protege contra cualquier excepción inesperada.

## Validación

- [x] `npm run typecheck` — sin errores
- [x] `npm run build` — exitoso
- [ ] `npm run test` — pendiente ejecución
- [ ] Test manual: triggear cada flujo y verificar mensaje WA

## Dependencias

- `FounderNotificationsModule` ya existía y estaba registrado en `AppModule`
- Variables de entorno ya configuradas: `WHATSAPP_PHONE_NUMBER_ID`, `WHATSAPP_TOKEN`, `FOUNDER_WHATSAPP_NUMBER`

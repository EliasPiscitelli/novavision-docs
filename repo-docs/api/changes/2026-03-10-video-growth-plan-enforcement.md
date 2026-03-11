# Cambio: enforcement server-side para video Growth-only

- Autor: agente-copilot
- Fecha: 2026-03-10
- Rama: feature/automatic-multiclient-onboarding

## Archivos

- src/onboarding/onboarding.service.ts
- src/onboarding/onboarding.controller.ts
- src/onboarding/onboarding.service.video-plan-guard.spec.ts

## Resumen

Se agregó validación server-side para impedir que cuentas Starter persistan `design_config` con secciones de video Growth-only, tanto por `PATCH /onboarding/preferences` como por `POST /onboarding/session/save` y por el flujo de `POST /onboarding/submit` que reutiliza esos métodos.

También se agregó un endpoint de tracking de intención de upgrade que registra eventos en `lifecycle_events` cuando el builder detecta interacción con componentes de video bloqueados.

## Por qué

El gating visual del frontend no alcanza para proteger persistencia si el payload se manipula manualmente. El backend ahora rechaza explícitamente esos casos antes de grabar en `nv_onboarding`, `progress` o `client_home_settings`.

## Cómo probar

- `npm test -- --runInBand src/onboarding/onboarding.service.video-plan-guard.spec.ts`
- `npm run lint`
- `npm run typecheck`
- `npm run build`

## Notas

- Regla de negocio documentada: una tienda Growth no baja a Starter; si el cliente deja Growth, el flujo válido es baja de la tienda y alta de una nueva.
- No se agregaron migraciones ni tablas nuevas; se reutilizó `lifecycle_events`.

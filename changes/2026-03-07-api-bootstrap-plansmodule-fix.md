# API bootstrap fix for PlansModule wiring

- Fecha: 2026-03-07
- Autor: GitHub Copilot
- Repo: apps/api
- Rama: feature/automatic-multiclient-onboarding

## Resumen

Se corrigió un fallo de arranque en producción de la API. El build en Railway terminaba bien, pero la aplicación quedaba fuera de servicio durante el healthcheck porque Nest no resolvía `PlansService` en algunos módulos que instanciaban servicios endurecidos por límites de plan.

## Archivos modificados

- `apps/api/src/faq/faq.module.ts`
- `apps/api/src/service/service.module.ts`
- `apps/api/src/logo/logo.module.ts`
- `apps/api/src/home/home.module.ts`
- `apps/api/src/app.module.ts`

## Causa raíz

Durante el endurecimiento de addons y cuotas se agregaron dependencias a `PlansService` en `FaqService`, `ServiceService` y `LogoService`. Parte del wiring de módulos quedó incompleto y en producción el bootstrap fallaba con errores de DI antes de que la API pudiera responder `/` o `/healthz`.

## Validación realizada

- `npm run build` en `apps/api`
- arranque productivo local con `.env` cargado
- verificación manual de `GET /` y `GET /healthz` con `200 OK`

## Impacto

- Se recupera el bootstrap productivo.
- No hay cambios de contrato HTTP ni de esquema.
- El problema estaba en el runtime de Nest, no en la etapa de build.
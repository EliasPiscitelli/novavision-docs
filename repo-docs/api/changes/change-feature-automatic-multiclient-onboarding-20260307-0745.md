# Cambio: fix de bootstrap productivo por wiring de PlansModule

- Autor: GitHub Copilot
- Fecha: 2026-03-07 07:45
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/faq/faq.module.ts, src/service/service.module.ts, src/logo/logo.module.ts, src/home/home.module.ts, src/app.module.ts

Resumen:
Se agregó `PlansModule` en los módulos que instancian servicios endurecidos recientemente con `PlansService`. El deploy fallaba después del build porque Nest no podía resolver `PlansService` al bootstrapear `FaqService` y otros servicios relacionados.

Por qué:
El build de Railway/Nixpacks completaba correctamente, pero la app quedaba unhealthy en el healthcheck porque el proceso se caía durante el arranque por DI incompleta. El endurecimiento de límites agregó dependencias a `PlansService` en FAQ, Services y Logo, pero no se actualizó el wiring en todos los contextos de módulo donde esos servicios se proveen.

Cómo probar:
1. En `apps/api`, correr `npm run build`.
2. Cargar variables desde `.env` y arrancar en modo productivo: `set -a && source .env && set +a && PORT=3001 NODE_ENV=production npm run start:prod`.
3. Verificar `GET /` y `GET /healthz` con respuesta `200 OK`.

Notas de seguridad:
- No cambia contratos ni validaciones funcionales.
- Corrige exclusivamente el wiring de módulos para que el enforcement backend ya implementado pueda inicializarse en producción.
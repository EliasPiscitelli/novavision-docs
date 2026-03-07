# Cambio: eliminación definitiva de endpoints legacy SEO AI

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/automatic-multiclient-onboarding
- Archivos:
  - apps/api/src/seo-ai-billing/seo-ai-purchase.controller.ts
  - apps/api/src/seo-ai-billing/seo-ai-purchase.service.ts
  - apps/api/src/app.module.ts
  - apps/api/src/auth/auth.middleware.ts
  - novavision-docs/seo/SEO_AI_GUIDE.md
  - novavision-docs/audit/endpoint-inventory.md
  - novavision-docs/audit/audit-auth-tenant-isolation.md
  - novavision-docs/changes/2026-03-07-addon-store-phase9-seo-checkout-centralization-and-banner-boosts.md

## Resumen

Se eliminaron los endpoints legacy `POST /seo-ai/purchase` y `POST /seo-ai/webhook`. A partir de este cambio, la única vía válida para checkout y webhook de packs SEO AI es la superficie de Addon Store: `POST /addons/purchase` y `POST /addons/webhook`.

## Por qué

La compatibilidad temporal ya no era necesaria y mantener alias legacy seguía dejando deuda operativa y de seguridad: doble inventario de endpoints, bypasses de auth extra y documentación ambigua sobre cuál era el flujo activo.

## Cómo probar

1. En apps/api correr `npm run typecheck`.
2. En apps/api correr `npm run build`.
3. Verificar que `POST /seo-ai/purchase` responda 404.
4. Verificar que `POST /seo-ai/webhook` responda 404.
5. Verificar que la compra desde la tab SEO AI siga saliendo por `POST /addons/purchase`.
6. Verificar que Mercado Pago notifique a `POST /addons/webhook`.

## Notas de seguridad

- Se eliminó un bypass público residual en `AuthMiddleware` para `/seo-ai/webhook`.
- Se eliminó la exclusión del `AppModule` para `/seo-ai/webhook`.
- El default técnico de `SeoAiPurchaseService` ahora apunta a `/addons/webhook`, evitando regresiones silenciosas.
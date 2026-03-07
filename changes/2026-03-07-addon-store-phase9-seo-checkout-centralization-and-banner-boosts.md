# Cambio: centralización del checkout SEO AI y banner boosts en Addon Store

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/automatic-multiclient-onboarding
- Archivos:
  - apps/api/src/addons/addons.admin.controller.ts
  - apps/api/src/addons/addons.service.ts
  - apps/api/src/addons/addons.service.spec.ts
  - apps/api/src/seo-ai-billing/seo-ai-purchase.service.ts
  - apps/api/src/subscriptions/platform-mercadopago.service.ts
  - apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx
  - apps/web/src/components/admin/AddonStoreDashboard/index.jsx
  - apps/web/src/components/admin/SeoAutopilotDashboard/index.jsx

## Resumen

Se unificó el checkout de packs SEO AI bajo el flujo de Addon Store sin retirar la tab operativa de SEO AI. Además, se eliminó del catálogo base la venta de servicios manuales innecesarios, se habilitó soporte administrable para boosts de banners y se restringió el checkout de addons/SEO AI a débito en una cuota.

También se dejó preparada la desactivación controlada de `/seo-ai/purchase` con headers de deprecación y se consolidó el flujo activo de webhook de packs SEO AI comprados desde Addon Store hacia `/addons/webhook`.

## Por qué

Había dos entrypoints de compra para el mismo vertical SEO AI: uno desde SEO AI y otro desde Addon Store. Eso fragmentaba historial, copy operativo y futuras automatizaciones. También seguían publicados addons manuales que ya no se querían vender y faltaba un uplift liviano válido para Starter con enforcement real. El límite de banners sí existe hoy en entitlements; límites equivalentes para FAQs/services no.

## Cómo probar

### API

1. En apps/api correr `npm run lint`.
2. En apps/api correr `npm run typecheck`.
3. En apps/api correr `npm run build`.
4. Opcionalmente correr el spec focalizado: `npm test -- addons.service.spec.ts`.
5. Para bootstrap real del primer uplift starter, correr `npm run seed:addon:starter-banner-boost` con `SUPABASE_ADMIN_URL` y `SUPABASE_ADMIN_SERVICE_ROLE_KEY` válidos en `apps/api/.env`.

### Web tenant

1. En apps/web correr `npm run lint`.
2. En apps/web correr `npm run typecheck`.
3. En apps/web correr `npm run build`.
4. Entrar a la tab SEO AI y comprar un pack.
5. Verificar que el POST salga a `/addons/purchase` con `return_section=seoAutopilot`.
6. Confirmar que al volver desde Mercado Pago la URL limpia quede en `?seoAutopilot`.
7. Confirmar que el Addon Store muestre copy de checkout centralizado y pago por débito en una cuota.

### Admin

1. En apps/admin correr `npm run lint`.
2. En apps/admin correr `npm run typecheck`.
3. Crear o editar un item gestionable con `banners_active_limit_delta=3`.
4. Confirmar que la card muestre el delta compuesto correctamente y que la estadística de banners extra aumente.

## Notas funcionales

- `+3 banners` queda validado como addon real para Starter porque impacta `banners_active_limit`.
- `+services` y `+faqs` no se publican como uplift de plan porque hoy no existe enforcement duro equivalente en entitlements.
- La compra sigue impactando en `account_addon_purchases` y, para uplifts activos, en `clients.entitlement_overrides` mediante la sincronización ya existente.
- Matriz visible en super admin:
  - Pago único: packs SEO AI/consumibles derivados.
  - Upgrade mensual: uplifts con entitlements reales como `products_limit` y `banners_active_limit`.
  - Preset sugerido cargable en formulario: `starter_banner_boost_3` por USD 19 mensuales.
- En la fase siguiente se eliminó por completo el alias `/seo-ai/webhook`; el único webhook válido para estos pagos es `/addons/webhook`.

## Notas de seguridad

- El checkout de addons y SEO AI queda restringido a débito en una cuota vía `payment_methods` de Mercado Pago.
- No se agregaron secretos ni variables nuevas.

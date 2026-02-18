# Email Template Consistency — Centralización de branding

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama:** feature/automatic-multiclient-onboarding (API)

## Resumen

Centralización completa del sistema de emails de NovaVision. Se creó `EmailTemplateService` como servicio @Injectable() global que unifica el layout HTML y branding de todos los emails de la plataforma.

### Problema
- 8+ servicios con HTML inline diferente
- Email de contacto inconsistente (`contact.novavision@gmail.com` vs `novavision.contact@gmail.com`)
- Logos duplicados y footers distintos
- Sin separación clara entre emails buyer-facing y merchant-facing

### Solución
- **2 modos**: `store` (buyer → logo tienda + "Powered by NV") y `platform` (merchant → logo NV directo)
- **1 servicio**: `EmailTemplateService.wrapInLayout()` genera HTML completo con header + contenido + footer
- **1 archivo de constantes**: `email-branding.constants.ts` como fuente única de verdad

## Archivos creados
- `src/common/email/email-template.service.ts` — Servicio principal (198 líneas)
- `src/common/email/email-branding.constants.ts` — Constantes centralizadas (55 líneas)
- `src/common/email/index.ts` — Barrel exports

## Archivos modificados
- `src/common/common.module.ts` — EmailTemplateService como provider global
- `src/legal/legal-notification.service.ts` — Migrado a wrapInLayout (2 templates)
- `src/support/support-notification.service.ts` — Migrado a wrapInLayout (5 templates incluyendo reapertura)
- `src/shipping/shipping-notification.service.ts` — Migrado a wrapInLayout (6 templates por estado)
- `src/onboarding/onboarding-notification.service.ts` — Migrado footers a renderPlatformFooterHtml (8 templates)
- `src/tenant-payments/mercadopago.service.ts` — Constantes unificadas desde email-branding.constants

## Constantes centralizadas

| Constante | Valor |
|-----------|-------|
| PLATFORM_NAME | NovaVision |
| PLATFORM_CONTACT_EMAIL | novavision.contact@gmail.com |
| PLATFORM_LOGO_URL | https://novavision.lat/assets/logo-titulo-Y-ZOfWz4.png |
| PLATFORM_LOGO_PNG | https://novavision.lat/logo/logo.png |
| PLATFORM_WEBSITE | https://novavision.lat |
| PLATFORM_INSTAGRAM | https://instagram.com/novavision.lat |
| EMAIL_COLORS | brandDark, textLight, linkLight, muted, cardBg, text, subtle, border |

## Tests validados (45/45 ✅)
- 31 tests: EmailTemplateService + branding constants
- 14 tests: notification services integration (legal, support, shipping, onboarding, orders)
- XSS prevention: storeName, storeLogo, preheader escapados
- Regresión: email viejo `contact.novavision@gmail.com` no aparece en ningún output

## Seguridad
- Escape de HTML en storeName, storeLogo, storeUrl y preheader (prevención XSS)
- Constantes overrideables por variables de entorno para staging/dev
- Contact email unificado a `novavision.contact@gmail.com` (canonical)

## Cómo probar
1. Trigger cualquier email (orden pagada, soporte, shipping) y verificar layout consistente
2. Verificar footer "Powered by NovaVision" con logo en emails de tienda
3. Verificar header NovaVision en emails de plataforma
4. Email de contacto: siempre `novavision.contact@gmail.com`

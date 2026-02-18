# Legal Compliance — Implementación completa (Ley 24.240 Argentina)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront
- **Rama Admin:** feature/automatic-multiclient-onboarding

## Resumen

Implementación integral de cumplimiento legal argentino (Ley 24.240 de Defensa del Consumidor) abarcando:

1. **Documentos legales** — 8 documentos Markdown en `novavision-docs/legal/` (T&C, Privacidad, DPA, AUP, SLA, Suscripción, Template Tienda, Disclaimer)
2. **Módulo Legal en backend** — `src/legal/` con controller, service, notification service
3. **Buyer consent** — Aceptación de T&C en checkout + registro en DB
4. **Formulario de arrepentimiento** — Botón "Solicitar Devolución" en detalle de orden (10 días corridos)
5. **Notificaciones legales** — Emails a comprador y vendedor ante solicitudes de devolución
6. **Protección al vendedor** — Máquina de estados, validaciones, endpoints admin
7. **Migraciones** — Admin DB (consent_log, legal_docs) + Backend DB (buyer_consent, withdrawal_requests)
8. **Campos legales** — `terms_accepted_at`, `privacy_accepted_at` en nv_accounts y clients

## Archivos modificados/creados

### Backend (API)
- `src/legal/legal.module.ts` — Módulo NestJS con LegalController + LegalService
- `src/legal/legal.controller.ts` — Endpoints: POST consent, POST withdrawal, GET docs
- `src/legal/legal.service.ts` — Lógica de negocio legal
- `src/legal/legal-notification.service.ts` — Emails legales (buyer=store mode, merchant=platform mode)
- `src/app.module.ts` — Importa LegalModule
- `src/orders/orders.service.ts` — Nuevos estados return_requested, refunded
- `src/tenant-payments/helpers/status.ts` — OrderStatus enum actualizado
- `migrations/admin/20260217_consent_log_and_legal_docs.sql`
- `migrations/admin/ADMIN_042_add_legal_compliance_fields.sql`
- `migrations/backend/20260217_buyer_consent_and_withdrawal.sql`
- `migrations/backend/20260218_add_legal_fields_to_clients.sql`

### Web (Storefront)
- `src/components/TermsConditions/index.jsx` — Modal T&C con contenido actualizado
- `src/components/OrderDetail/index.jsx` — Botón "Solicitar Devolución" con formulario
- `src/components/checkout/CheckoutStepper/steps/ConfirmationStep.jsx` — Checkbox T&C
- `src/pages/LegalPage/` — Página legal dedicada (nueva)
- `src/sections/footer/ClassicFooter/index.jsx` — Links a legales en footer
- `src/sections/footer/ElegantFooter/index.jsx` — Links a legales en footer
- `src/templates/fourth/components/Footer.jsx` — Links a legales
- `src/routes/AppRoutes.jsx` — Ruta /legal
- `src/utils/statusTokens.js` — Tokens para return_requested, refunded

### Admin
- `src/pages/BuilderWizard/steps/Step9Terms.tsx` — T&C en wizard de onboarding
- `src/pages/BuilderWizard/steps/Step11Terms.tsx` — Términos de servicio
- `src/pages/Settings/BillingPage.tsx` — Sección legal en billing
- `src/context/WizardContext.tsx` — Estado legal en wizard

## Migraciones SQL

### Admin DB (erbfzlsznqsmwmjugspo)
- Tabla `consent_log`: registro de aceptaciones (user_id, document_type, version, accepted_at, ip_address)
- Tabla `legal_docs`: documentos legales con versionado
- 7 documentos legales insertados como seed
- Campos `terms_accepted_at`, `privacy_accepted_at` en `nv_accounts`
- RLS: service_role bypass + policies por tenant

### Backend DB (ulndkhijxtxvpmbbfrgp)
- Tabla `buyer_consent`: consentimiento del comprador (user_id, client_id, document_type, version)
- Tabla `withdrawal_requests`: solicitudes de arrepentimiento (order_id, user_id, reason, status)
- Campos `terms_accepted_at`, `privacy_accepted_at` en `clients`
- 9 políticas RLS (select/insert/update por owner + admin + service_role)

## Seguridad
- RLS en todas las tablas nuevas con policies estrictas
- Consent registra IP del usuario
- Withdrawal tiene máquina de estados (pending → approved/rejected)
- 10 días corridos para arrepentimiento (Ley 24.240 Art. 34)
- Emails automáticos a comprador y vendedor

## Cómo probar
1. Checkout: verificar checkbox de T&C obligatorio antes de pagar
2. Post-compra: verificar botón "Solicitar Devolución" visible dentro de 10 días
3. Footer: verificar links a T&C y Política de Privacidad
4. Admin: verificar campos legales en wizard y billing
5. API: `POST /legal/consent`, `POST /legal/withdrawal`, `GET /legal/docs`

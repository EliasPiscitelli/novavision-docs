# Admin — Legal en Wizard y Billing

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama:** feature/automatic-multiclient-onboarding (Admin)

## Resumen

Integración de aceptación de términos legales en el flujo de onboarding del admin y en la página de facturación para cumplimiento normativo argentino.

## Archivos modificados

- `src/pages/BuilderWizard/steps/Step9Terms.tsx` — Paso de aceptación de T&C en wizard de creación de tienda
- `src/pages/BuilderWizard/steps/Step11Terms.tsx` — Aceptación de términos de servicio NovaVision
- `src/pages/BuilderWizard/steps/Step8ClientData.tsx` — Datos del cliente con campos legales
- `src/context/WizardContext.tsx` — Estado de aceptación legal en contexto del wizard
- `src/pages/Settings/BillingPage.tsx` — Sección de información legal y cumplimiento en billing
- `src/pages/AdminDashboard/ClientApprovalDetail.jsx` — Vista de aprobación con datos legales

## Flujo
1. Merchant crea tienda → Step8 pide datos fiscales
2. Step9: acepta T&C de tienda (template con datos del merchant)
3. Step11: acepta términos de servicio de NovaVision
4. Se registra `terms_accepted_at` y `privacy_accepted_at` en nv_accounts
5. BillingPage muestra estado de aceptación legal

## Cómo probar
1. Iniciar wizard de nueva tienda en Admin
2. Completar hasta Step9 → verificar checkbox de T&C
3. Completar Step11 → verificar aceptación de servicio
4. Ir a Settings > Billing → verificar sección legal
5. Super admin: ver datos legales en ClientApprovalDetail

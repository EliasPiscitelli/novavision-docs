# Cambio: Centralización legal en NovaVision Admin

- Fecha: 2026-03-09
- Autor: GitHub Copilot
- Rama: feature/automatic-multiclient-onboarding
- Repositorio afectado: apps/admin

## Resumen

Se consolidó el contenido legal de NovaVision Admin en una única fuente de verdad reutilizable y se separó en documentos públicos independientes:

- Términos y condiciones del servicio
- Política de privacidad
- Política comercial, bajas y soporte
- Instrucciones para eliminación de datos

También se reemplazó la duplicación legal que existía en el modal inicial y en el paso 11 del Builder Wizard por resúmenes con enlaces a documentos públicos versionados.

## Motivo

Había divergencias entre:

- el modal de aceptación global
- las páginas públicas de términos y privacidad
- el paso de onboarding que pedía aceptación legal

Eso generaba riesgo de contradicción contractual y dejaba huecos para cumplimiento/App Review, especialmente en políticas comerciales y data deletion.

## Archivos principales

- `apps/admin/src/legal/legalDocuments.tsx`
- `apps/admin/src/components/legal/LegalDocumentPage.tsx`
- `apps/admin/src/components/TermsConditions/index.jsx`
- `apps/admin/src/pages/BuilderWizard/steps/Step11Terms.tsx`
- `apps/admin/src/App.jsx`

## Decisiones

- Se explicitó que NovaVision actúa como proveedor SaaS y no como responsable de la operatoria comercial/fiscal/tributaria de cada tienda cliente.
- Se mantuvieron rutas públicas en español y se agregaron aliases en inglés/legacy (`/terms`, `/privacy`, `/data-deletion`).
- Se añadió una página pública específica para eliminación de datos, útil para cumplimiento y configuración de Meta.

## Cómo validar

1. Abrir `/terminos`, `/privacidad`, `/politica-comercial` y `/eliminacion-de-datos`.
2. Verificar aliases `/terms`, `/privacy`, `/devoluciones` y `/data-deletion`.
3. Entrar al Builder Wizard paso 11 y confirmar que el consentimiento sigue guardándose antes del submit for review.
4. Confirmar que el modal inicial ya no contiene un contrato duplicado sino enlaces a los documentos vigentes.

## Riesgos

- Si existieran enlaces hardcodeados adicionales fuera de Admin, pueden seguir apuntando a rutas legacy no relevadas en esta pasada.
- El backend sigue registrando una única versión de términos; la aceptación agrupa ahora más de un documento bajo la misma versión legal publicada.

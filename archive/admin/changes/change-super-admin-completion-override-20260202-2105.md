# Cambio: Override de requisitos en review Super Admin

- Autor: agente-copilot
- Fecha: 2026-02-02
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx

## Resumen
Se agregó en el review de super admin la visualización de mínimos efectivos y un editor de override por cliente para requisitos de completitud.

## Por qué
Se necesitaba poder ajustar requisitos por cliente directamente desde el review y explicar por qué se marcaban faltantes (ej. productos mínimos globales).

## Cómo probar
1. Abrir un cliente en el review de super admin.
2. Verificar que se muestre “Mínimos efectivos” en el checklist.
3. Editar override y guardar; confirmar que se actualiza la completitud.
4. Restablecer global y confirmar que vuelve a los valores globales.

## Notas de seguridad
No aplica.

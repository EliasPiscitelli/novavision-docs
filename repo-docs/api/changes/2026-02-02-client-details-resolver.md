# Cambio: Resolver determinístico de Client Details

- Autor: agente-copilot
- Fecha: 2026-02-02
- Rama: feature/automatic-multiclient-onboarding
- Archivos:
  - apps/api/src/admin/admin.service.ts
  - apps/api/src/admin/admin.controller.ts
  - apps/api/src/client-dashboard/client-dashboard.service.ts
  - apps/api/migrations/20260202_add_requirements_override.sql
  - apps/admin/src/services/adminApi.js
  - apps/admin/src/pages/ClientDetails/index.jsx
  - apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx

## Resumen
- Se separa claramente `account_status` (onboarding) de `subscription_status` (billing) y se resuelve la suscripción por `account_id`.
- Se elimina cualquier escritura en endpoints GET y se agrega acción explícita para reparar el link de suscripción.
- Se muestra evidencia X/mínimo en checklist (incluye productos con imagen cuando aplica).
- Se usa `nv_accounts.requirements_override` como fuente principal de overrides (fallback de lectura a `nv_account_settings`).

## Motivo
Eliminar la inconsistencia en Client Details/Approval Detail y evitar falsos “Suscripción: incomplete” cuando hay suscripción activa.

## Cómo probar
1. Caso con `nv_accounts.status=incomplete` y `subscriptions.status=active`:
   - UI debe mostrar “Estado cuenta = incomplete” y “Suscripción = active”.
2. Caso `subscription_id` null con suscripción activa:
   - Resolver muestra suscripción correcta y el endpoint de reparación vincula el id bajo demanda.
3. Caso productos 6 y mínimo 10:
   - Evidencia “Productos 6/10”.
4. Override `products_min=5`:
   - Checklist deja de marcar faltante.

## Notas de seguridad
- No se ejecutaron scripts ni migraciones en este cambio.
- No se expusieron credenciales.

# Cambio: Auditoría y refactor del Dashboard Detalle de Cliente

- **Autor**: agente-copilot
- **Fecha**: 2026-02-07
- **Rama**: `feature/automatic-multiclient-onboarding` (admin + api)
- **Archivos modificados**: 17 archivos (ver inventario abajo)
- **Documentación**: [audit/client-dashboard-audit.md](../audit/client-dashboard-audit.md) | [audit/client-dashboard-plan.md](../audit/client-dashboard-plan.md)

---

## Resumen

Auditoría completa y refactor incremental del componente `ClientDetails/index.jsx` del panel Admin de NovaVision. Se ejecutaron **7 PRs** secuenciales que resolvieron **15 hallazgos** técnicos clasificados en 7 categorías.

El componente pasó de ~1478 líneas monolíticas con queries directas a Supabase, estados planos y un pattern de `createRoot` imperativo, a ~1022 líneas con 4 hooks extraídos, 4 componentes reutilizables, estados normalizados con badges semánticos, y confirmación fuerte para operaciones destructivas.

---

## Por qué se hizo

1. **Imports rotos**: 4 componentes usados sin importar — potencial crash en runtime.
2. **Componente monolítico**: 1478 líneas imposibles de testear.
3. **Bypass de API**: 2 hooks importaban Supabase directamente, rompiendo el patrón multi-tenant.
4. **Bug BE**: `onboarding_state` siempre null por nombre de columna incorrecto.
5. **UX inconsistente**: loading/empty/error como texto plano; acciones sin agrupar.
6. **Operación destructiva sin guardia**: borrar cliente sin type-to-confirm, con doble modal redundante y `createRoot` anti-patrón.

---

## PRs ejecutados

### Admin repo

| # | Hash | Descripción |
|---|------|-------------|
| PR1+2 | `23f2fa2` | Fix imports/tooltip/dead code + extract 4 custom hooks |
| PR3 | `8d254fc` | normalizeAccountHealth + HealthBadge + AccountHealthRow |
| PR4 | `655f5ba` | Eliminate Supabase direct queries, use adminApi methods |
| PR5 | `0017b99` | Group actions into 3 columns, remove duplicate analytics section |
| PR6 | `73c99ba` | SectionSkeleton, EmptyState, ErrorState components |
| PR7 | `334fd98` | type-to-confirm delete, remove createRoot imperative |

### API repo

| # | Hash | Descripción |
|---|------|-------------|
| PR3 | `be7eb57` | Fix onboarding_state always null (column `state` not `status`) |
| PR4 | `268534c` | 3 new GET endpoints (payments, invoices, usage-months) |

---

## Archivos modificados

### Creados (9)

| Archivo | PR |
|---------|-----|
| `admin/src/pages/ClientDetails/hooks/useClientData.js` | 2 |
| `admin/src/pages/ClientDetails/hooks/useClientPayments.js` | 2 |
| `admin/src/pages/ClientDetails/hooks/useCompletionRequirements.js` | 2 |
| `admin/src/pages/ClientDetails/hooks/useClientMetrics.js` | 2 |
| `admin/src/utils/normalizeAccountHealth.js` | 3 |
| `admin/src/components/HealthBadge/index.jsx` | 3 |
| `admin/src/components/SectionSkeleton/index.jsx` | 6 |
| `admin/src/components/EmptyState/index.jsx` | 6 |
| `admin/src/components/ErrorState/index.jsx` | 6 |

### Modificados (8)

| Archivo | PRs |
|---------|-----|
| `admin/src/pages/ClientDetails/index.jsx` | 1-7 |
| `admin/src/pages/ClientDetails/style.jsx` | 1, 5 |
| `admin/src/components/ConfirmDialog/index.jsx` | 7 |
| `admin/src/components/ConfirmDialog/style.jsx` | 7 |
| `admin/src/utils/deleteClientEverywhere.jsx` | 7 |
| `admin/src/services/adminApi.js` | 4 |
| `api/src/admin/admin.service.ts` | 3 |
| `api/src/admin/admin-client.controller.ts` | 4 |

---

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Admin: `npm run dev` (terminal front, puerto 5174)
3. Ir a la lista de clientes → click en cualquier cliente
4. Verificar:
   - Badges de colores en account_status, subscription_status, onboarding_state
   - Skeletons animados mientras cargan secciones
   - Empty states con ícono cuando no hay datos
   - Error states con botón "Reintentar" (desconectar API para probar)
   - Acciones agrupadas en 3 columnas (Operativas / Billing / Diagnóstico)
   - Botón "Eliminar cliente" requiere tipear el nombre exacto del cliente
5. Lint: `npm run lint` → 0 errors en ambos repos

---

## Notas de seguridad

- Se eliminaron 2 imports directos de Supabase client en hooks del frontend, reemplazados por llamadas vía `adminApi` (endpoints protegidos por JWT + role).
- Se removió `createRoot` imperativo que podía causar memory leaks, reemplazado por flujo declarativo con `ConfirmDialog`.
- 3 nuevos endpoints GET en API ya están protegidos por `AuthMiddleware` + `TenantContextGuard` existentes.
- No se tocaron migraciones ni RLS.

---

## Riesgos / Rollback

- **Riesgo bajo**: cambios incrementales, cada PR fue validado con lint.
- **Rollback**: revertir commits individuales por PR si fuese necesario.
- **No hay cambios de DB**: sin migraciones, sin cambios de schema.

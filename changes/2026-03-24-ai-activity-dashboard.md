# 2026-03-24 — Página Actividad IA + UX background + Cancel/Retry/Fairness

## Resumen

Implementación completa del plan "Actividad IA" en 4 fases + extras de robustez:

1. **Página Actividad IA**: Nueva sección en admin dashboard con listado de todos los jobs IA (filtros por status/tipo, paginación, vista detalle con input/result/error data).
2. **Registro de operaciones sync**: Todos los endpoints sync (fill, improve, photo, description, logo, banner, service) ahora logean en `ai_generation_jobs` via fire-and-forget.
3. **Deep links desde notificaciones**: Click en notificación con `job_id` navega directo al detalle del job en Actividad IA.
4. **Messaging UX**: Mensajes "seguí trabajando" durante loading en ProductModal, ServiceSection, LogoSection, BannerSection y AiCatalogWizard.
5. **Fairness multi-tenant**: Máximo 5 jobs activos (queued+processing) por tenant. HTTP 429 si se excede.
6. **Cancel/Retry**: Endpoints `PATCH /ai-jobs/:id/cancel` (solo queued, con refund) y `POST /ai-jobs/:id/retry` (solo failed, con re-reserva de créditos).
7. **Migración BACKEND_053**: Status `cancelled` en constraint + índice parcial para fairness.
8. **Tests E2E**: 15 tests nuevos para listado/cancel/retry/fairness + fixes a tests existentes (26/26 passing).

## Archivos modificados

### API (`apps/api/`)
- `src/ai-generation/ai-generation.controller.ts` — Filtros en `GET /ai-jobs`, endpoints `PATCH /ai-jobs/:id/cancel` y `POST /ai-jobs/:id/retry`, fairness check en `generateCatalog`, calls a `logSyncOperation` en 9 endpoints sync
- `src/ai-generation/ai-generation.service.ts` — Nuevo método `logSyncOperation()` (fire-and-forget insert en `ai_generation_jobs`)
- `migrations/backend/BACKEND_053_ai_jobs_cancelled_status.sql` — Nuevo: constraint con `cancelled` + índice `idx_ai_gen_jobs_client_active`
- `test/ai-jobs.e2e.spec.ts` — Nuevo: 15 tests E2E para jobs (list, cancel, retry, fairness)
- `test/ai-generation.e2e.spec.ts` — Fix: agregado `logSyncOperation` al mock, pricing `ai_product_full`, corrección action code en test 20

### Web (`apps/web/`)
- `src/hooks/useAiJobs.js` — Nuevo: hook con auto-polling 10s, filtros, paginación
- `src/components/admin/AiActivityDashboard/index.jsx` — Nuevo: componente principal con lista + detalle + cancel/retry buttons
- `src/components/admin/AiActivityDashboard/style.jsx` — Nuevo: styled-components con CSS custom properties
- `src/pages/AdminDashboard/index.jsx` — Registrada sección `aiActivity` (lazy, icon, feature flag)
- `src/components/admin/NotificationBell/index.jsx` — Deep link: click notificación → navega a detalle job
- `src/components/ProductModal/index.jsx` — Mensaje "seguí trabajando" durante AI loading
- `src/components/admin/ServiceSection/index.jsx` — Mensaje durante AI loading
- `src/components/admin/LogoSection/index.jsx` — Mensaje durante AI loading
- `src/components/admin/BannerSection/index.jsx` — Mensaje durante AI loading
- `src/components/admin/AiCatalogWizard/index.jsx` — Mensaje post-submit + toast actualizado

## Migración ejecutada

- `BACKEND_053_ai_jobs_cancelled_status.sql` ejecutada en `nv-backend-db` el 2026-03-24

## Quality gate

- API: lint (0 errors), typecheck, build, tests (1028/1035 passed, 5 fallos pre-existentes en `home/`)

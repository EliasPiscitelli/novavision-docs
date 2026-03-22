# AI Generation Async + Notificaciones + Key Pool

**Fecha:** 2026-03-19
**Repos afectados:** API, Web
**Rama:** feature/multitenant-storefront

## Resumen

Implementación del sistema de generación IA asíncrona con pool de API keys, cola de jobs, y notificaciones al usuario.

## Cambios

### API — Archivos nuevos

| Archivo | Propósito |
|---------|-----------|
| `api/src/ai-generation/openai-key-pool.ts` | Pool de API keys OpenAI con rotación least-loaded + cooldown 30s tras 429 |
| `api/src/ai-generation/ai-generation.worker.ts` | Worker cron (cada 5s) que procesa jobs de `ai_generation_jobs` |
| `api/src/ai-generation/ai-notification.service.ts` | Crea notificaciones en `client_notifications` al completar/fallar jobs |
| `api/src/notifications/notifications.controller.ts` | `GET /notifications`, `GET /notifications/unread-count`, `PATCH /:id/read`, `PATCH /read-all` |
| `api/src/notifications/notifications.module.ts` | Módulo NestJS para notificaciones |
| `api/migrations/backend/BACKEND_052_ai_generation_jobs_and_notifications.sql` | Tablas `ai_generation_jobs` y `client_notifications` con índices parciales y RLS |

### API — Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `ai-generation.service.ts` | `callOpenAI`, `callOpenAIImageGeneration`, `callOpenAIVision` ahora usan `OpenAiKeyPool` en vez de un solo `OpenAI` client |
| `ai-generation.module.ts` | Registrados `OpenAiKeyPool`, `AiNotificationService`, `AiGenerationWorker` |
| `ai-generation.controller.ts` | `POST /products/ai-catalog` → async (crea job, retorna `job_id`). Nuevos: `GET /ai-jobs`, `GET /ai-jobs/:id` |
| `ai-credits.service.ts` | Nuevos métodos `reserveCredits()` y `refundReservedCredits()` |
| `app.module.ts` | Registrado `NotificationsModule` |
| `ai-generation.service.spec.ts` | Adaptado al pool (mock `OpenAiKeyPool` en vez de `ConfigService`) |
| `ai-credits.service.spec.ts` | Corregido count de `AI_ACTION_CODES` (5→6, pre-existente) |

### Web — Archivos nuevos

| Archivo | Propósito |
|---------|-----------|
| `web/src/hooks/useNotifications.js` | Polling cada 15s a `/notifications/unread-count`, toast automático en nuevas notificaciones |
| `web/src/components/admin/NotificationBell/index.jsx` | Campana con badge de unread count + dropdown de notificaciones |
| `web/src/components/admin/NotificationBell/style.jsx` | Estilos styled-components |

### Web — Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `pages/AdminDashboard/index.jsx` | Agregado `<NotificationBell />` en header antes de `AiCreditsWidget` |
| `components/admin/AiCatalogWizard/index.jsx` | Simplificado: solo Step 1 (config), click genera job async → toast → cierra wizard |

## Base de datos

**Backend DB:** Ejecutada migración `BACKEND_052`
- `ai_generation_jobs`: cola de jobs con status (queued/processing/completed/failed), retry, prioridad
- `client_notifications`: notificaciones por tenant con read/unread tracking
- RLS: `server_bypass` + `tenant_select` (+ `tenant_update` para notifications)

## Env vars nuevas (opcionales)

| Variable | Default | Descripción |
|----------|---------|-------------|
| `OPENAI_API_KEYS` | — | Múltiples keys separadas por coma (fallback a `OPENAI_API_KEY`) |
| `AI_MAX_CONCURRENT` | `8` | Máximo de llamadas concurrentes a OpenAI |
| `AI_WORKER_BATCH_SIZE` | `3` | Jobs por tick del worker |

## Validación

- `tsc --noEmit` OK
- `npm run build` OK (API)
- `npx vite build` OK (Web)
- Tests: 977 pass, 5 fail pre-existentes

# Fase 3: Outbox Cross-DB — Sincronización eventual Admin → Backend

- **Autor:** agente-copilot
- **Fecha:** 2026-02-10
- **Rama:** feature/multitenant-storefront
- **Fase:** 3 (del action-plan de auditoría dual-DB)

## Archivos creados

- `migrations/admin/20260210_account_sync_outbox.sql` — DDL tabla outbox + índices + RLS + función TTL
- `src/outbox/outbox-event.types.ts` — Tipos de eventos, payloads tipados, OutboxRow
- `src/outbox/outbox.service.ts` — Servicio core: emit(), claimPending(), markCompleted/Failed, getHealthStats(), purgeCompleted()
- `src/outbox/outbox-worker.service.ts` — Worker cron (cada 30s) con handlers por event_type y backoff exponencial
- `src/outbox/outbox.module.ts` — Módulo NestJS
- `src/outbox/index.ts` — Barrel export

## Archivos modificados

- `src/app.module.ts` — Importa OutboxModule
- `src/worker/worker.module.ts` — Importa OutboxModule para inyección en ProvisioningWorkerService
- `src/worker/provisioning-worker.service.ts` — Emite outbox events en provisionClient (account.created) y syncEntitlements (entitlements.synced)
- `src/subscriptions/subscriptions.module.ts` — Importa OutboxModule
- `src/subscriptions/subscriptions.service.ts` — Emite outbox events en:
  - `requestCancel()` → account.suspended (cierra el gap: tienda no se pausaba en Backend al cancelar)
  - `pauseStore()` → account.suspended (cierra el gap: pausa manual no se sincronizaba a Backend)
  - `resumeStore()` → account.updated (cierra el gap: reanudación manual no se sincronizaba a Backend)
  - `requestUpgrade()` → plan.changed (cierra el gap: plan_key textual no se sincronizaba a Backend, solo entitlements)

## Resumen

### Problema
Los dual-writes entre Admin DB y Backend DB eran fire-and-forget: si la segunda escritura fallaba, los datos quedaban inconsistentes sin reintento. Además, varias operaciones (cancelar suscripción, pausar/reanudar tienda, upgrade de plan) solo escribían a Admin DB sin propagar los cambios a Backend DB.

### Solución
Patrón **Outbox** con tabla `account_sync_outbox` en Admin DB:
1. Cada operación en Admin DB emite un evento outbox (idempotente via `event_key` UNIQUE).
2. Un worker cron (cada 30s) reclama eventos pendientes, los aplica a Backend DB, y los marca completados.
3. Si falla: backoff exponencial (30s → 2m → 8m → 32m) y DLQ tras 5 intentos.
4. TTL de 30 días para eventos completados (purge diario a las 3am).

### Tipos de eventos

| event_type | Acción en Backend DB |
|------------|---------------------|
| `account.created` | Upsert `clients` |
| `account.updated` | Update parcial `clients` (mapeo de campos) |
| `plan.changed` | Update `clients.plan`, `billing_period`, `entitlements` |
| `account.suspended` | `clients.is_active = false` |
| `account.deleted` | Soft-delete `clients.deleted_at` |
| `entitlements.synced` | Update `clients.entitlements` |
| `settings.synced` | Upsert `client_home_settings` |
| `mp_credentials.synced` | Verificación de sync (read-only check) |

### Gaps cerrados

1. **`requestCancel()`** — Ahora emite `account.suspended` → tienda se desactiva en Backend
2. **`pauseStore()`** — Ahora emite `account.suspended` → Backend refleja la pausa
3. **`resumeStore()`** — Ahora emite `account.updated` → Backend reactiva la tienda
4. **`requestUpgrade()`** — Ahora emite `plan.changed` → `clients.plan` se actualiza en Backend (antes solo se sincronizaban entitlements)

### Diseño no-intrusivo

- Los eventos outbox se emiten con try/catch no-bloqueante: si la emisión falla, la operación principal continúa.
- El worker de outbox es independiente del worker de provisioning existente.
- No se refactorizaron los flujos complejos de provisioning (ya tienen su propio sistema de saga/jobs).

## Cómo probar

1. Aplicar migración SQL en Admin DB:
   ```sql
   -- Ejecutar: migrations/admin/20260210_account_sync_outbox.sql
   ```
2. Build y arrancar:
   ```bash
   npm run build && node dist/main.js
   ```
3. La app arranca con "Nest application successfully started".
4. Con un cliente provisionado, ejecutar una pausa de tienda → verificar que aparece un evento en `account_sync_outbox` con status `pending` → esperar 30s → verificar que el worker lo procesa y lo marca `completed`.

## Notas de seguridad

- RLS estricto: solo `service_role` puede operar sobre `account_sync_outbox`.
- Los payloads no contienen credenciales ni tokens.
- El worker usa `DbRouterService` que resuelve clusters con PGP decryption.

## Riesgos / Rollback

- **Riesgo bajo:** los outbox events son no-bloqueantes (try/catch). Si la tabla no existe o hay un error, la funcionalidad preexistente sigue operando normalmente.
- **Rollback:** eliminar `OutboxModule` de `app.module.ts` y revertir los imports en `worker.module.ts` y `subscriptions.module.ts`.

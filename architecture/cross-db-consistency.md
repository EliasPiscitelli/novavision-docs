# Cross-DB Consistency Strategy

> Última actualización: 2026-02-07  
> Autor: Copilot Agent  
> Estado: Implementado parcial (Fase 3.4 del Lifecycle Fix Plan)

---

## 1. Problema

NovaVision usa **dos bases de datos Supabase independientes**:

| DB | Alias | Contenido principal |
|----|-------|---------------------|
| Admin | `erbfzlsznqsmwmjugspo` | `nv_accounts`, `subscriptions`, `provisioning_jobs`, `lifecycle_events`, `subscription_locks` |
| Multicliente (Backend) | `ulndkhijxtxvpmbbfrgp` | `clients`, `products`, `orders`, `users`, `categories`, etc. |

**No hay transacciones ACID cross-DB.** Cuando una operación escribe en ambas bases (ej: `approveClient`, pause/unpause), si un write falla después de que otro ya commitó, queda **estado inconsistente**.

---

## 2. Principios

1. **Admin DB es source of truth** para account state (`nv_accounts.status`, `subscription_status`, `slug`).
2. **Backend DB refleja** — debe converger hacia el estado de Admin DB.
3. **Eventual consistency** con compensación inmediata + reconciliación periódica.
4. **Detección proactiva** de desync con queries automáticas.
5. **Logs de auditoría** en `lifecycle_events` para trazabilidad.

---

## 3. Mecanismos implementados

### 3.1 Compensación en approveClient (Fase 3.1)

```
┌─────────────────────────────────────────────┐
│ approveClient(accountId)                     │
│                                              │
│ 1. Validate (idempotency, draft expiry)     │
│ 2. Write Backend DB: publish store          │ ← Step A
│ 3. Write Admin DB: status = 'approved'      │ ← Step B
│                                              │
│ Si Step B falla:                            │
│   Compensar Step A → revert to draft        │
│   Emit lifecycle_event('approval_failed')   │
│   Throw error                               │
└─────────────────────────────────────────────┘
```

**Archivo:** `src/admin/admin.service.ts` → `approveClient()`

### 3.2 Atomic WHERE en unpause (Fase 4.2)

El unpause solo actúa si la condición sigue siendo cierta al momento del write:
```sql
UPDATE clients
SET publication_status = 'published', paused_reason = NULL
WHERE id = :id
  AND publication_status = 'paused'          -- todavía paused
  AND paused_reason LIKE 'subscription_%'    -- por motivo de suscripción
```

Si un admin pausó manualmente entre el read y el write, el UPDATE no hace nada (safe no-op).

### 3.3 Lifecycle Events (Fase 3.2)

Cada operación cross-DB emite un evento a `lifecycle_events` con `old_value` y `new_value`. Esto permite:
- Reconstruir la secuencia de eventos
- Detectar gaps o inconsistencias post-hoc
- Alimentar dashboards de CRM

### 3.4 Distributed Locks (Fase 3.3)

Previenen mutaciones concurrentes sobre el mismo account (ej: webhook + upgrade simultáneo):
- `try_lock_subscription(account_id, ttl)` → lock o fail
- `release_subscription_lock(account_id)` → liberar
- TTL de 30s con cleanup automático

---

## 4. Condiciones de desync a detectar

| # | Condición | Severidad | Auto-fix posible |
|---|-----------|-----------|------------------|
| D1 | `nv_accounts.status = 'approved'` AND `clients.publication_status != 'published'` | P0 | Sí → publicar clients |
| D2 | `nv_accounts.status = 'suspended'` AND `clients.publication_status = 'published'` | P0 | Sí → pausar clients |
| D3 | `nv_accounts.slug != clients.slug` | P1 | Sí → copiar slug de nv_accounts a clients |
| D4 | `subscriptions.status = 'active'` AND `clients.publication_status = 'paused'` AND `paused_reason LIKE 'subscription_%'` | P1 | Sí → unpause clients |
| D5 | `nv_accounts.store_paused = true` AND `clients.publication_status = 'published'` | P1 | Parcial → investigar causa |
| D6 | `nv_accounts` sin `clients` correspondiente (backend_client_id missing) | P2 | No → provisioning manual |

---

## 5. Cron de reconciliación

### Implementación: `reconcileCrossDb()` en `SubscriptionsService`

**Frecuencia:** Diaria (6:00 AM, junto con reconciliación MP existente)

**Algoritmo:**

```
1. Cargar nv_accounts con status IN ('approved', 'live', 'suspended')
   → para cada account con backend_cluster_id:

2. Cargar clients correspondiente del Backend DB
   → si no existe: log WARNING (D6), skip

3. Comparar:
   a. status vs publication_status (D1, D2)
   b. slug vs slug (D3)
   c. subscription_status + paused_reason (D4)
   d. store_paused vs publication_status (D5)

4. Para cada desync encontrado:
   a. Log [DESYNC] con detalles
   b. Emit lifecycle_event('desync_detected', ...)
   c. Si auto-fix posible: aplicar corrección + emit lifecycle_event('desync_fixed', ...)
   d. Si no: solo alertar
```

### Query de detección (pseudo-SQL)

```sql
-- Ejecutar desde el backend (lee ambas DBs en memoria)

-- Admin side
SELECT id, status, subscription_status, slug, store_paused, backend_cluster_id
FROM nv_accounts
WHERE status IN ('approved', 'live', 'suspended')
  AND backend_cluster_id IS NOT NULL;

-- Para cada account, en Backend DB:
SELECT id, publication_status, paused_reason, slug
FROM clients
WHERE nv_account_id = :account_id;

-- Desync conditions:
-- D1: account.status IN ('approved','live') AND client.publication_status != 'published'
-- D2: account.status = 'suspended' AND client.publication_status = 'published'
-- D3: account.slug != client.slug
-- D4: account.subscription_status = 'active' AND client.publication_status = 'paused'
--     AND client.paused_reason LIKE 'subscription_%'
```

---

## 6. Flujos cross-DB y sus protecciones

| Flujo | Archivos | Protección |
|-------|----------|------------|
| approveClient | `admin.service.ts` | Compensación + lifecycle event |
| pauseStoreIfNeeded | `subscriptions.service.ts` | Health-check logs + lifecycle event |
| unpauseStoreIfReactivated | `subscriptions.service.ts` | Atomic WHERE + lifecycle event |
| provisionClient | `provisioning-worker.service.ts` | Idempotency via provisioning_jobs |
| reconcileCrossDb (cron) | `subscriptions.service.ts` | Auto-fix + alertas |

---

## 7. Escalamiento futuro

- **Outbox pattern:** Si la carga crece, migrar a un patrón de outbox table donde cada write genera un evento en una cola local, y un worker aplica los cambios al otro DB.
- **Change Data Capture:** Si Supabase implementa CDC nativo, usar webhooks de tabla para sincronizar en tiempo real.
- **Multi-store:** Si un account tiene múltiples stores, el desync check debe iterar por cada store.

---

## 8. Monitoreo

### Métricas clave (para dashboard futuro)
- `desync_detected_total` — contador por tipo (D1-D6)
- `desync_fixed_total` — contador de auto-fixes
- `lifecycle_events_count` — volumen de eventos por tipo
- `cross_db_reconcile_duration_ms` — duración del cron

### Alertas
- **P0:** Cualquier D1 o D2 detectado → alerta inmediata
- **P1:** D3 (slug) o D4 (unpause fallido) → alerta diaria
- **P2:** D6 (account sin client) → revisar en próximo sprint

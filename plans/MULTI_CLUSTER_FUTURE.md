# Multi-Cluster: Diseño Pendiente para Escalamiento Futuro

> **Estado:** PENDIENTE — no implementar hasta tener >50 tenants activos o requerimientos de latencia geográfica.  
> **Prioridad:** P3 (post-lanzamiento)  
> **Referencia anterior:** La lógica de multi-cluster fue simplificada intencionalmente en el sprint Single-Cluster Hardening (2025-07).

---

## Contexto

NovaVision actualmente opera con un único cluster de Backend (`cluster_shared_01`) que aloja a todos los tenants en una sola instancia de Supabase. Esto es suficiente para la escala actual (<10 tenants) y simplifica operación, monitoreo y debugging.

La arquitectura ya tiene los **cimientos** para multi-cluster en código y DB:

### Infraestructura existente (reutilizar, no recrear)

| Artefacto | Ubicación | Estado |
|-----------|-----------|--------|
| Tabla `backend_clusters` | Admin DB | ✅ Existe, con `cluster_shared_01` |
| Columna `nv_accounts.backend_cluster_id` | Admin DB | ✅ Poblada para todos los accounts |
| `DbRouterService.chooseBackendCluster()` | `src/db/db-router.service.ts` | ⏸️ Simplificado a return `'cluster_shared_01'` |
| `DbRouterService.getBackendClient(clusterId)` | `src/db/db-router.service.ts` | ✅ Funcional, soporta clusterId dinámico |
| `DbRouterService.getClientBackendCluster()` | `src/db/db-router.service.ts` | ✅ Funcional, lookup por nv_account_id |

### Qué se simplificó (y cómo restaurar)

**`chooseBackendCluster()`** — Antes: selección aleatoria ponderada entre clusters activos. Ahora: retorna `'cluster_shared_01'` directamente.

Para restaurar:
1. Descomentar/reimplementar la lógica de weighted random en `db-router.service.ts`
2. Agregar nuevos clusters a la tabla `backend_clusters`
3. Asignar `backend_cluster_id` a nuevos tenants (manual o por lógica de routing)

---

## Items pendientes para multi-cluster (F2.x)

### F2.1 — Routing inteligente por carga/región
- **Qué:** `chooseBackendCluster()` selecciona cluster basado en:
  - Carga actual (cantidad de tenants, storage, orders/mes)
  - Región geográfica del tenant (si aplica latencia)
  - Estado del cluster (active/draining/maintenance)
- **Cómo:** Restaurar la lógica comentada + agregar métricas de carga desde `usage_rollups_monthly`
- **Prerequisito:** Tener ≥2 clusters activos

### F2.2 — Migración de tenants entre clusters
- **Qué:** Mover un tenant de un cluster a otro sin downtime
- **Cómo:**
  1. Crear tenant en cluster destino (clone de datos)
  2. Switchear `backend_cluster_id` en nv_accounts
  3. Poner cluster origen en modo drain para ese tenant
  4. Verificar y cleanup
- **Riesgo:** Consistencia de datos durante la ventana de migración

### F2.3 — Health monitoring por cluster
- **Qué:** Dashboard de salud por cluster (latencia, error rate, storage)
- **Cómo:** Agregar endpoint `/health/clusters` que consulte cada cluster y reporte métricas
- **Prerequisito:** Tener ≥2 clusters activos

### F2.4 — Auto-scaling de clusters
- **Qué:** Crear/escalar clusters automáticamente ante picos de carga
- **Cómo:** Integración con API de Supabase para provisioning programático
- **Riesgo:** Costo elevado — solo justificable con volumen significativo

---

## Criterios para activar multi-cluster

- [ ] >50 tenants activos con >1000 órdenes/mes agregadas
- [ ] Requerimiento de latencia geográfica (tenants en otras regiones)
- [ ] Supabase Free/Pro tier insuficiente para backend compartido
- [ ] Requerimiento contractual de aislamiento dedicado (plan enterprise_dedicated)

---

## Notas de implementación

- La tabla `metering_prices` (Admin DB, vacía) está reservada para tracking de costos de infra por cluster (Fase 4).
- El `UsageConsolidationCron` ya soporta multi-cluster (lee `backend_cluster_id` de cada account y busca backend clients con el mismo mapping).
- El `QuotaCheckGuard` resuelve el tenant via `clients.nv_account_id` en Backend DB — funciona con cualquier cluster.

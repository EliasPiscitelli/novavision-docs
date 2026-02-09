# Plan de Remediación por Fases — Admin DB vs Multitenant DB (v2)

**Fecha:** 2026-02-09  
**Autor:** Agente Copilot (Principal Data Architect + Security Auditor)  
**Referencia:** [2026-02-08-db-audit-admin-vs-multitenant.md](2026-02-08-db-audit-admin-vs-multitenant.md)  
**Supersede:** [2026-02-08-db-audit-plan.md](2026-02-08-db-audit-plan.md) (v1)  
**Baseline Evidence:** [2026-02-09-baseline-evidence.md](2026-02-09-baseline-evidence.md)

---

## Cambios respecto a v1

| Problema en v1 | Corrección en v2 |
|---|---|
| Ejecutaba remediaciones sobre nombres supuestos (tablas/columnas/funciones del reporte del agente) | **Fase -1 obligatoria**: reconcilio de evidencia real antes de tocar nada |
| CORS como mitigación de seguridad | Eliminado; DoD depende de JWT/rol/secret interno |
| Sin auditoría de `service_role` leak al frontend | **Fase 0.5** dedicada a secrets hardening |
| Sin storage isolation | Incluido en Fase -1 (inventario) y Fase 1 (remediación) |
| Outbox sin idempotency key definida | `event_key` UNIQUE obligatorio + contrato de eventos |

---

## 0) Objetivo y métricas (DoD global)

* **0** superficies críticas sin auth real (JWT + rol o secreto interno rotado).
* **0** paths donde un tenant puede leer/escribir datos de otro tenant (API + RLS + Storage).
* **1** set canónico de `plan_key` y `billing_period` (mismo contrato lógico en ambos lados).
* **0** divergencias persistentes cross-DB sin un "sync job" pendiente visible y reintentable.
* **0** keys sensibles expuestas al cliente (service_role / secrets).

---

## Fase -1 (Gate obligatorio) — Reconcilio de Evidencia (sin cambios)

**Objetivo:** convertir supuestos en hechos y parametrizar el plan con nombres reales.

### Tareas

* **DB** (Admin + Multi):
  * Inventario real: tablas, columnas, constraints, índices, policies RLS, functions.
  * Detectar **columna scope real**: `client_id|tenant_id|store_id` (y en qué tablas aplica).
  * Storage: listar buckets + policies + patrón de paths (prefijo por tenant o no).
* **API**:
  * Mapear endpoints sensibles (onboarding, subscriptions, billing, payments, provisioning) → servicios → tablas.
  * Listar rutas `@AllowNoTenant()` y justificar cada una.
  * Confirmar cómo se resuelve tenant (slug/host/header) y dónde se valida.
* **Admin (Edge Functions)**:
  * Listar funciones, y para cada una: método de auth real (JWT/rol/secret interno/ninguno).
  * Confirmar con qué key inicializa supabase dentro de cada function (anon vs service_role).

### DoD

* Documento "Baseline Evidence" con snippets SQL y rutas de archivo por cada hallazgo.
* Tabla "Nombre real → alias del plan" (ej: `tenant_id` en vez de `client_id` si aplica).

**Sin esto no se habilita Fase 0.**

---

## Fase 0 — Hotfix Seguridad (P0) + cierre de superficies "internal-only"

**Objetivo:** eliminar escrituras peligrosas sin auth.

### Tareas

* Edge Functions críticas:
  * Requerir **JWT válido** (`verify_jwt`) + **rol** (`admin/super_admin`) para funciones "UI-facing".
  * Para funciones "job/cron/internal": requerir **`x-internal-key` rotado** + opcional JWT de service (si existe).
* Rechazar explícitamente cualquier patrón "Authorization: Bearer <anon-key>" como auth.
* Logging estructurado mínimo (sin PII): `request_id`, `actor_id`, `actor_role`, `tenant/account id`, `action`, `result`.

### DoD

* Sin Authorization → 401
* Con JWT sin rol → 403
* Con JWT admin → 200
* Con internal key inválida → 401/403
* **Prueba negativa**: no se puede crear/borrar tenant desde un cliente externo.

### Rollback

* Revert del cambio de auth en functions (solo código/config).

---

## Fase 0.5 (P0) — "Service role leakage" + Secrets hardening

**Objetivo:** asegurar que ninguna key privilegiada está expuesta al cliente.

### Tareas

* Auditoría de envs (Netlify/Railway/Vite build):
  * Buscar `service_role`, `SUPABASE_SERVICE_ROLE_KEY`, tokens MP platform, HMAC secrets.
  * Confirmar que el frontend **solo** usa anon key.
* Rotación de secretos si hubo exposición (procedimiento documentado, no improvisado).
* Verificar que los endpoints que requieren service_role solo corren server-side.

### DoD

* Evidencia de "no service key en cliente" (búsqueda en builds + configs).
* Rotación hecha si aplica (con checklist).

---

## Fase 1 — Integridad tenant-scoped + índices mínimos (P1/P2)

**Objetivo:** eliminar huérfanos y asegurar performance por scope.

### Tareas (parametrizadas por Fase -1)

* Backfill de scope en tablas que **deben** ser tenant-scoped y hoy permiten NULL.
* Luego aplicar `NOT NULL` en scope donde corresponda.
* Índices hot-path:
  * `(<scope>, created_at desc)`
  * `(<scope>, status, created_at desc)` en órdenes/facturas
  * `(<scope>, user_id)` en carritos/órdenes por usuario
* Validar FKs críticas (o mitigación si legacy impide):
  * cart_items → products
  * order_items → orders/products
  * pagos → órdenes

### DoD

* `COUNT(*) WHERE <scope> IS NULL = 0` en tablas target.
* Índices creados y verificados con `EXPLAIN` básico (sin scans evidentes en listados).
* Reporte de FKs faltantes con decisión: "agregar" o "aceptar + cleanup job".

### Rollback

* Drop índices, revert constraints NOT NULL (datos se mantienen).

---

## Fase 2 — Normalización de planes (P1)

**Objetivo:** contrato único de plan/billing para evitar gating roto y estados inválidos.

### Decisión canónica

* `plan_key`: `starter|growth|scale|enterprise`
* `billing_period`: `monthly|annual`

### Tareas

* Definir fuente de verdad (recomiendo: **Admin DB** como catálogo canónico).
* Migración additive:
  * nueva columna canónica (`plan_key_v2`, `billing_period_v2`)
  * backfill desde legacy
  * switch de lectura
  * switch de escritura
  * eliminación de legacy (post-estabilidad)

### DoD

* No existen valores legacy sin mapping.
* Onboarding/suscripción crean estados válidos en ambos lados.
* Validación: queries de auditoría devuelven 0 inconsistencias.

### Rollback

* Volver a leer legacy, mantener v2 como shadow.

---

## Fase 3 — Confiabilidad cross-DB (P1): Outbox + idempotencia + convergencia

**Objetivo:** eliminar divergencias permanentes por dual-write.

### Patrón

* Admin DB emite eventos en `account_sync_outbox`.
* Worker procesa y aplica cambios idempotentes en Multi DB.

### Reglas clave (no negociables)

* `event_key` UNIQUE (idempotencia): `account_id + event_type + version` o hash determinístico del payload.
* `attempts`, `next_retry_at`, `last_error`, DLQ lógico.
* Métrica de backlog: si `pending > X` o `oldest_pending > Y` → alerta.

### DoD

* Si falla Multi DB, el evento queda pendiente y reintenta hasta converger.
* Reprocesar el mismo evento N veces no duplica efectos.
* No existe divergencia sin outbox pendiente asociado.

### Rollback

* Feature flag: volver a write directo (manteniendo outbox en shadow para visibilidad).

---

## Fase 4 — Observabilidad, auditoría, y crecimiento (P2/P3)

**Objetivo:** poder investigar incidentes y evitar degradación por tablas crecientes.

### Tareas

* TTL/archiving en logs/eventos/idempotency.
* Índices por `(scope/account, created_at desc)` en eventos.
* `admin_actions_audit` para acciones sensibles (cambios de catálogo/config pago).
* Estado de jobs (cron/worker) visible en dashboard.

### DoD

* Jobs corriendo con logs.
* Consultas de auditoría no escanean tablas enormes.
* Acciones admin críticas quedan auditadas.

---

## Orden recomendado (quick wins)

1. **Fase -1** (evidencia) — gate obligatorio
2. **Fase 0** (auth functions/endpoints)
3. **Fase 0.5** (service key + secrets)
4. **Fase 1** (scope + índices)
5. **Fase 2** (planes)
6. **Fase 3** (outbox)
7. **Fase 4** (observabilidad/TTL)

---

## Plan de pruebas mínimo (smoke/regresión)

* **Security:** 401/403/200 según JWT/rol/internal-key.
* **No tenant leakage:** tenant A no lee/escribe tenant B (API + RLS + Storage).
* **Webhooks:** replay del mismo evento 3 veces → 1 efecto.
* **Outbox:** caída Multi DB → se acumula pending y luego converge.
* **Preview:** fail-closed (si token falta en prod, preview no habilita compras ni mutaciones).

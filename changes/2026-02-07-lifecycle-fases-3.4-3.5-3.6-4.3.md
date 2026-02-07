# Cambio: Lifecycle Fases 3.4, 3.5, 3.6, 4.3

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos modificados

### Nuevos
- `novavision-docs/architecture/cross-db-consistency.md` — Documento completo de estrategia cross-DB
- `novavision-docs/changes/2026-02-07-lifecycle-fases-3.4-3.5-3.6-4.3.md` — Este changelog

### Modificados
- `src/subscriptions/subscriptions.service.ts` — reconcileCrossDb cron + pending >24h en reconcileWithMercadoPago
- `src/admin/admin.service.ts` — getAccount360 method
- `src/admin/admin.controller.ts` — GET /admin/accounts/:id/360 route
- `novavision-docs/LIFECYCLE_FIX_PLAN.md` — Tracker actualizado (puntos 3, 6, 14 → ✅; Fases 3 y 4 → APLICADO)

## Resumen de cambios

### Fase 3.4 — Cross-DB Consistency Strategy (punto #3)
- Creado documento `cross-db-consistency.md` con principios, condiciones de desync (D1-D6), algoritmo de reconciliación y métricas de monitoreo
- Implementado `reconcileCrossDb()` cron (6:15 AM) en SubscriptionsService que detecta y auto-resuelve desyncs D1-D4 entre Admin DB y Backend DB
- Emite lifecycle events para cada desync encontrado
- Genera reporte con total/desyncs/fixed/errors/details

### Fase 3.5 — Customer 360 Endpoint (punto #3 + criterio de aceptación)
- Nuevo método `getAccount360(accountId)` en AdminService que consolida:
  - nv_accounts (datos completos)
  - subscriptions (últimas 10)
  - lifecycle_events (últimos 20)
  - provisioning_jobs (últimos 5)
  - backend client state (publication_status, paused_reason, slug, etc.)
  - desync checks en tiempo real (D1-D4 + D6)
- Nueva ruta `GET /admin/accounts/:id/360` con SuperAdminGuard
- Respuesta incluye `has_desyncs: boolean` y `desync_checks[]` con type/description/severity

### Fase 3.6 — Reconciliación MP Mejorada (punto #6)
- Expandido `reconcileWithMercadoPago()` para incluir subs con `status=pending` que tengan >24h de antigüedad
- Estas subs se consultan contra MP API para detectar cambios de estado perdidos (webhook no recibido)
- Merge seguro con set existente para evitar duplicados

### Fase 4.3 — Slug Desync Monitoring (punto #14)
- Implementado como D3 check dentro de `reconcileCrossDb()`: compara `nv_accounts.slug` vs `clients.slug`, auto-fix copiando admin → backend

## Validación

```bash
npx tsc --noEmit          # 0 errores
npx jest test/subscriptions-lifecycle.spec.ts test/admin-approve-idempotency.spec.ts
                          # 12/12 PASS (3.4s)
```

## Notas de seguridad
- El endpoint 360 está protegido por SuperAdminGuard (solo super_admin)
- reconcileCrossDb() usa try/catch por account para aislar fallos individuales
- Los auto-fixes emiten lifecycle_events para auditoría
- Queries a backend DB usan backend_cluster_id resuelto por account

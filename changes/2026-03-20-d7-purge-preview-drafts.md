# D7 — Purge preview draft accounts

**Fecha:** 2026-03-20
**Módulo:** API (TtlCleanupService)
**Commit:** `d904116` en `feature/automatic-multiclient-onboarding`

## Problema

20 cuentas sintéticas `preview+*@example.com` con `status='draft'` en Admin DB, generadas durante testing del flujo de onboarding. Contaminan métricas de conversión del funnel.

## Cambios

### TtlCleanupService (API)
- Nuevo cron `purgePreviewDraftAccounts` (2:30 AM diario)
- Hard-delete de cuentas `preview+*@example.com` con `status='draft'` > 24h
- Borra `nv_onboarding` primero (FK), luego `nv_accounts`

### Migración SQL
- `migrations/admin/20260320_d7_purge_preview_drafts.sql`
- One-shot cleanup de los 20 registros existentes
- **Pendiente de ejecución manual** en Admin DB

## Impacto

- Métricas del funnel de onboarding reflejan solo cuentas reales
- Prevención automática de acumulación futura

## Validación

- TypeScript: 0 errores
- Build: OK
- Pre-push: 7/7 checks pasados
- Migración SQL pendiente de ejecución manual

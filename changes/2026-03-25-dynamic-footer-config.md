# Dynamic Footer Config — Fase 1 Backend

**Fecha:** 2026-03-25
**Plan:** `PLAN_DYNAMIC_FOOTER_GENERATION.md` Fase 1
**Estado:** Fase 1 (Backend) implementada. Fase 2 (Admin) y Fase 3 (Storefront) pendientes.

---

## Implementación

### Tabla `footer_config` (Backend DB)

Nueva tabla con:
- `footer_links` (JSONB) — array de links custom con label, url, position
- `show_social`, `show_contact`, `show_legal`, `show_powered_by` — toggles de secciones
- `custom_copyright` — texto personalizado de copyright
- `cta_text` + `cta_url` — call-to-action opcional
- RLS: service_role bypass + select por tenant
- Trigger `updated_at` automático
- Constraint UNIQUE en `client_id` (1 config por tenant)

### Módulo NestJS `footer-config`

| Endpoint | Método | Guard | Descripción |
|----------|--------|-------|-------------|
| `/settings/footer` | GET | Público (scopeado por client_id) | Obtener config del footer |
| `/settings/footer` | PUT | RolesGuard (admin, super_admin) | Upsert config del footer |

Patrón upsert con `onConflict: 'client_id'` — si no existe, crea; si existe, actualiza.

### Feature Catalog

Agregada `content.footer_config` con `plans: { starter: true, growth: true, enterprise: true }`.

### Archivos creados/modificados

- `api/migrations/20260325_footer_config.sql` — migración (ejecutada)
- `api/src/footer-config/footer-config.module.ts` — módulo NestJS
- `api/src/footer-config/footer-config.service.ts` — servicio con get + upsert
- `api/src/footer-config/footer-config.controller.ts` — controller con GET + PUT
- `api/src/app.module.ts` — registro del módulo
- `api/src/plans/featureCatalog.ts` — nueva feature `content.footer_config`

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 106/106 suites, 1033/1035 tests OK (2 skipped)

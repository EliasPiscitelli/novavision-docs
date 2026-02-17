# Cambio: Remediación de Seguridad — Phase 5

- **Autor:** agente-copilot
- **Fecha:** 2025-07-17
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding
- **Rama Docs:** main

## Archivos Modificados

### API (templatetwobe)
- `src/guards/rate-limiter.guard.ts` — **ELIMINADO** (código muerto)
- `src/app.module.ts` — Removido `ThrottlerModule` import y registro (código muerto)
- `migrations/backend/20250717_cleanup_opb_policies_and_indexes.sql` — Migración H-28 + H-32
- `migrations/admin/20250717_missing_client_id_indexes.sql` — Migración H-32 Admin

### Admin (novavision)
- `src/components/IdentitySettingsTab.tsx` — **ELIMINADO** (código muerto, nunca importado)
- `src/context/AuthContext.jsx` — Limpieza de `builder_token`, `novavision_builder_token` y `wizard_state` al logout
- `src/pages/BuilderWizard/steps/Step1Slug.tsx` — Limpieza de builder tokens al logout del wizard

### Docs (novavision-docs)
- `audit/SECURITY_AUDIT_2025-07-14.md` — Actualización checklist Phase 5

## Resumen de Cambios

### H-24 · Webhook backoff — ✅ YA IMPLEMENTADO (re-evaluado)

El análisis reveló que `getPaymentDetails()` YA implementa backoff exponencial (`delay = baseDelay * 2^attempt`) para errores 429/5xx y errores transitorios de red. La deduplicación es doble capa:
1. Tabla `tenant_payment_events` con `event_key` SHA256 unique
2. Lock in-memory (Map con TTL 120s) por `clientId:paymentId`

No se requirió ninguna acción adicional.

### H-28 · Double policy en order_payment_breakdown — ✅ RESUELTO

**Antes:** 5 policies (2 SELECT, 2 server_bypass, 1 Super Admin)
**Después:** 3 policies

Eliminadas:
- `opb_select_admin` — redundante (subsumida por `opb_select_tenant` que cubre todo user del tenant)
- `server_bypass` — duplicada de `opb_server_bypass`

### H-32 · Índices client_id faltantes — ✅ RESUELTO

**Backend DB:** 1 tabla sin índice
- `product_categories` → `idx_product_categories_client_id` creado

**Admin DB:** 3 tablas sin índice
- `nv_onboarding` → `idx_nv_onboarding_client_id` creado
- `system_events` → `idx_system_events_client_id` creado
- `users` → `idx_users_client_id` creado

Verificación post-creación: 0 tablas con `client_id` sin índice en ambas DBs.

### Dead Code Cleanup

1. **`rate-limiter.guard.ts`** (108 líneas) — `RateLimiterGuard extends ThrottlerGuard` nunca fue registrado como `APP_GUARD` ni usado con `@UseGuards`. El rate limiting real es via Express middleware (`rate-limit.middleware.ts`). Eliminado junto con `ThrottlerModule.forRoot()` de `app.module.ts`.

2. **`IdentitySettingsTab.tsx`** (369 líneas) — Componente que nunca fue importado en ningún archivo del proyecto. Contenía `localStorage.getItem("token")` vulnerable. Eliminado.

### H-16 · builder_token cleanup — ⚠️ MITIGADO

Se agregó limpieza de `builder_token` y `novavision_builder_token` de localStorage en:
- `AuthContext.jsx` → función `logout()` (punto centralizado, usado por Header y Hub)
- `Step1Slug.tsx` → `handleLogout()` (logout del wizard, independiente de AuthContext)

También se limpia `wizard_state` en logout centralizado para reducir datos persistentes.

## Migraciones Ejecutadas

| DB | Archivo | Estado |
|----|---------|--------|
| Backend | `20250717_cleanup_opb_policies_and_indexes.sql` | ✅ Ejecutado |
| Admin | `20250717_missing_client_id_indexes.sql` | ✅ Ejecutado |

## Cómo Probar

### DB Policies (H-28)
```sql
-- Backend DB: debe retornar 3 rows (opb_select_tenant, opb_server_bypass, Super Admin Bulk Access)
SELECT policyname, cmd FROM pg_policies WHERE tablename='order_payment_breakdown';
```

### Indexes (H-32)
```sql
-- Debe retornar 0 rows en ambas DBs
SELECT c.relname FROM pg_attribute a
JOIN pg_class c ON c.oid = a.attrelid
JOIN pg_namespace n ON n.oid = c.relnamespace
WHERE a.attname = 'client_id' AND c.relkind = 'r' AND n.nspname = 'public'
  AND NOT EXISTS (SELECT 1 FROM pg_index i JOIN pg_attribute ia ON ia.attrelid = i.indexrelid
    WHERE i.indrelid = c.oid AND ia.attname = 'client_id');
```

### Dead Code (API)
```bash
# Debe retornar 0 resultados
grep -rn "RateLimiterGuard\|rate-limiter.guard" apps/api/src/ --include="*.ts"
```

### Builder Token Cleanup (Admin)
1. Iniciar sesión como admin → navegar al Builder → verificar que `builder_token` existe en localStorage
2. Hacer logout → verificar que `builder_token` y `novavision_builder_token` ya no están en localStorage

## Notas de Seguridad

- `ThrottlerModule` removido sin impacto: el rate limiting real lo provee `rate-limit.middleware.ts` (Express middleware, registrado globalmente en `main.ts`)
- Los 4 índices creados con `CONCURRENTLY` para evitar locks en producción
- La eliminación de `IdentitySettingsTab.tsx` cierra definitivamente el vector H-18 en ese archivo

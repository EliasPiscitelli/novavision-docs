# Cambio: Fase 0 – Remediación de seguridad (Plan de Acción v2)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-10
- **Rama:** feature/automatic-multiclient-onboarding (API + Admin)

---

## Resumen

Implementación completa de la **Fase 0** del plan de acción de seguridad derivado de la auditoría dual-database de NovaVision. Se corrigieron 8 hallazgos de prioridad P0-P2.

## Archivos modificados

### API (templatetwobe)

| Archivo | Cambio |
|---------|--------|
| `.gitignore` | Expandido a `.env.*` con excepciones explícitas para templates |
| `.github/copilot-instructions.md` | Regla #0: nunca usar [CELULA-3] |
| `src/app.module.ts` | DevModule condicional (solo non-production) |
| `src/dev/dev-seeding.controller.ts` | Agregado `@UseGuards(SuperAdminGuard)` |
| `src/onboarding/onboarding.controller.ts` | `GET /resume`: agregado `@UseGuards(BuilderOrSupabaseGuard)` |
| `src/coupons/coupons.controller.ts` | Agregado `@UseGuards(BuilderOrSupabaseGuard)` a nivel clase |
| `migrations/backend/BACKEND_004_rls_client_secrets.sql` | **NUEVO** - RLS para `client_secrets` (solo service_role) |
| `migrations/admin/ADMIN_055_reenable_super_admins_rls.sql` | **NUEVO** - Re-habilitar RLS en `super_admins` + revocar SELECT a authenticated |

### Admin (novavision)

| Archivo | Cambio |
|---------|--------|
| `.github/copilot-instructions.md` | Regla #0: nunca usar [CELULA-3] |
| `supabase/functions/_shared/requireAuth.ts` | **NUEVO** - Helper compartido de auth para Edge Functions |
| `supabase/functions/admin-create-client/index.ts` | Agregada autenticación con `requireAuth()` |
| `supabase/functions/admin-delete-client/index.ts` | Agregada autenticación con `requireAuth()` |
| `supabase/functions/admin-sync-usage/index.ts` | Agregada autenticación con `requireAuth()` |
| `supabase/functions/admin-sync-usage-batch/index.ts` | Agregada autenticación con `requireAuth()` |

### Web (templatetwo) – ya pusheado

| Archivo | Cambio |
|---------|--------|
| `.gitignore` | Limpieza de duplicados, patrón `.env.*` |
| `.github/copilot-instructions.md` | Regla #0: nunca usar [CELULA-3] |

---

## Detalle por item del plan

### 0.1 – Secretos en Git (P0) ✅ PUSHEADO
- `git rm --cached .env.production .env.subscription_config` (API)
- `git rm --cached .env` (Web)
- Archivos siguen existiendo localmente
- `.gitignore` actualizado para prevenir re-tracking

### 0.2 – Edge Functions sin auth (P0) ✅
- 4 funciones críticas protegidas: `admin-create-client`, `admin-delete-client`, `admin-sync-usage`, `admin-sync-usage-batch`
- Helper compartido `_shared/requireAuth.ts` valida JWT Bearer Token, verifica rol en app_metadata → profiles → users
- Retorna 401 si no hay token, 403 si el usuario no es admin/super_admin

### 0.3 – RLS en client_secrets (P1) ✅
- Migración `BACKEND_004_rls_client_secrets.sql` creada
- Solo permite acceso a `service_role` (tabla contiene MP access tokens encriptados)
- **PENDIENTE: ejecutar migración contra la DB multicliente**

### 0.4 – DevModule condicional (P1) ✅
- `DevModule` solo se carga cuando `NODE_ENV !== 'production'`
- Adicionalmente, `DevSeedingController` tiene `@UseGuards(SuperAdminGuard)` como defensa en profundidad

### 0.5.1 – Resume sin auth (P2) ✅
- `GET /onboarding/resume` ahora requiere `BuilderOrSupabaseGuard`
- Acepta builder session token O Supabase JWT

### 0.5.2 – Coupons sin auth (P2) ✅
- `POST /coupons/validate` ahora requiere `BuilderOrSupabaseGuard` a nivel clase
- Eliminado comentario de guard deshabilitado

### 0.5.3 – Webhook MP firma (P1) ✅ YA IMPLEMENTADO
- El código en `mp-router.service.ts` ya implementa fail-closed:
  - Rechaza si firma inválida + secret configurado
  - Rechaza en producción si no hay secret configurado
  - Solo permite sin firma en desarrollo

### 0.5.5 – super_admins sin RLS (P2) ✅
- Migración `ADMIN_055_reenable_super_admins_rls.sql` creada
- Re-habilita RLS (estaba deshabilitado por `20260201_fix_super_admin_rls.sql`)
- Agrega policy `server_bypass` (solo service_role)
- Revoca `GRANT SELECT` a authenticated (innecesario, `is_super_admin()` es SECURITY DEFINER)
- **PENDIENTE: ejecutar migración contra la DB admin**

---

## Items pendientes (post-Fase 0)

1. **Ejecutar migraciones** contra las DBs reales:
   - `BACKEND_004_rls_client_secrets.sql` → Multicliente DB
   - `ADMIN_055_reenable_super_admins_rls.sql` → Admin DB
2. **Rotación de secretos** (diferido por decisión del TL)
3. **Fase 1+** del plan de acción

## Cómo probar

### API
```bash
cd apps/api
npm run typecheck   # 0 errores (779 warnings pre-existentes de @typescript-eslint/no-explicit-any)
npm run lint        # verificar que no hay errores nuevos
npm run start:dev   # levantar y verificar endpoints
```

### Tests manuales
- `GET /onboarding/resume?user_id=xxx` sin token → debería devolver 401
- `POST /coupons/validate` sin token → debería devolver 401
- `POST /dev/seed-tenant` sin auth de super_admin → debería devolver 403
- Edge Functions: llamar sin Bearer token → debería devolver 401

## Notas de seguridad

- Las migraciones SQL deben ejecutarse en una ventana de mantenimiento controlada
- La migración de `super_admins` revoca un GRANT; verificar que ningún otro servicio depende de lectura directa
- La función `is_super_admin()` seguirá funcionando porque es `SECURITY DEFINER`

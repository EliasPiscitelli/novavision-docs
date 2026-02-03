# Commit Message Template

## Título (max 72 caracteres)

```
fix: sincronizar terms_accepted entre DB, Auth y localStorage
```

## Descripción Completa

```
Fix: Sincronización de terms_accepted y metadata entre nv_accounts, Supabase Auth y localStorage

PROBLEMA:
- Usuario completaba onboarding y aceptaba términos pero era redirigido al wizard en login posterior
- Root cause: Triple fallo arquitectónico
  1. Backend: acceptTerms() solo actualizaba nv_accounts, no auth.users.raw_user_meta_data
  2. Frontend: useTermsAccepted() solo leía localStorage, ignoraba JWT
  3. Auth Callback: no sincronizaba terms_accepted del JWT a localStorage
  4. Signup: ensureMembership() creaba usuarios sin inicializar metadata en Auth

SOLUCIÓN:
Implementados 4 fixes para garantizar sincronización completa:

1. Backend - OnboardingService.acceptTerms()
   - Archivo: apps/api/src/onboarding/onboarding.service.ts
   - Cambio: Después de actualizar nv_accounts, también actualiza auth.users via 
     adminClient.auth.admin.updateUserById() con terms_accepted, client_id, role
   - Impacto: JWT de usuarios que aceptan términos ahora contiene metadata correcto

2. Backend - AuthService.ensureMembership()
   - Archivo: apps/api/src/auth/auth.service.ts
   - Cambio: Al crear nuevo usuario (signup con Google), inmediatamente inicializa 
     user_metadata con client_id, role, terms_accepted=false
   - Impacto: Usuarios nuevos tienen metadata completo desde primer JWT

3. Frontend - useTermsAccepted()
   - Archivo: apps/admin/src/hooks/useTermsAccepted.jsx
   - Cambio: Reescritura completa. Lee de localStorage Y JWT (useEffect sincroniza).
     acceptTerms() actualiza ambos: localStorage + supabase.auth.updateUser()
   - Impacto: Estado de términos consistente entre localStorage y JWT

4. Frontend - ClientAuthCallback
   - Archivo: apps/admin/src/pages/ClientAuthCallback.tsx
   - Cambio: Después de OAuth redirect, sincroniza terms_accepted del JWT a localStorage
   - Impacto: Usuario no bloqueado por modal de términos tras re-login

MIGRACIÓN:
- Ejecutada para usuario afectado kaddocpendragon@gmail.com
- Script: apps/admin/docs/sql/fix-terms-accepted-user-metadata.sql
- Fecha: 2026-01-28 23:17:01
- Resultado: terms_accepted=true, client_id=platform, role=client en auth.users

TESTING:
- Usuario debe hacer logout/login para obtener nuevo JWT
- Usuarios nuevos verificados con metadata correcto en primer signup
- Script de validación: apps/admin/scripts/validate-user-metadata.sh

DOCUMENTACIÓN:
- Análisis técnico: apps/admin/docs/changes/bug-analysis-terms-accepted-20260128.md
- Resumen completo: apps/admin/docs/changes/COMPLETE_FIX_SUMMARY_20260128.md
- Checklist: apps/admin/docs/CHECKLIST_IMPLEMENTATION.md

Fixes #<ISSUE_NUMBER>
```

## Archivos Modificados

```
apps/api/src/onboarding/onboarding.service.ts
apps/api/src/auth/auth.service.ts
apps/admin/src/hooks/useTermsAccepted.jsx
apps/admin/src/pages/ClientAuthCallback.tsx
```

## Archivos Nuevos (Documentación)

```
apps/admin/docs/sql/fix-terms-accepted-user-metadata.sql
apps/admin/docs/MIGRATION_GUIDE_TERMS_ACCEPTED.md
apps/admin/docs/EXECUTIVE_SUMMARY_TERMS_BUG.md
apps/admin/docs/CHECKLIST_IMPLEMENTATION.md
apps/admin/docs/changes/bug-analysis-terms-accepted-20260128.md
apps/admin/docs/changes/fix-terms-accepted-redirect-20260128.md
apps/admin/docs/changes/fix-signup-metadata-init-20260128.md
apps/admin/docs/changes/COMPLETE_FIX_SUMMARY_20260128.md
apps/admin/scripts/fix-terms-accepted.sh
apps/admin/scripts/run-terms-migration.sh
apps/admin/scripts/validate-user-metadata.sh
```

---

## Comandos Git Sugeridos

```bash
# Asegúrate de estar en la branch correcta
git checkout feature/automatic-multiclient-onboarding

# Stage todos los archivos modificados
git add apps/api/src/onboarding/onboarding.service.ts
git add apps/api/src/auth/auth.service.ts
git add apps/admin/src/hooks/useTermsAccepted.jsx
git add apps/admin/src/pages/ClientAuthCallback.tsx

# Stage documentación
git add apps/admin/docs/
git add apps/admin/scripts/

# Commit con mensaje detallado
git commit -F commit-message.txt

# O alternativamente (commit interactivo)
git commit

# Push a remote
git push origin feature/automatic-multiclient-onboarding
```

---

## Checklist Pre-Commit

- [x] Código compila sin errores TypeScript
- [x] Linter ejecutado y aprobado
- [x] Documentación completa creada
- [x] Scripts de migración y validación creados
- [ ] Tests E2E ejecutados y pasando
- [ ] Usuario afectado notificado para testing

---

## Notas para PR

**Labels sugeridos:**
- `bug`
- `security`
- `critical`
- `auth`
- `onboarding`

**Reviewers sugeridos:**
- @eliaspiscitelli (owner)

**Merge strategy:**
- Squash and merge (consolidar en 1 commit limpio)

**Deployment:**
- Railway auto-deploy para backend
- Netlify auto-deploy para frontend
- Requiere smoke test post-deploy

---

**Fecha:** 2026-01-28  
**Autor:** GitHub Copilot Agent + @eliaspiscitelli

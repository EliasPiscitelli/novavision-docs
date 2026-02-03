# Resumen Completo: Solución Bug Terms Accepted

## 📋 Problema Original

Usuario **kaddocpendragon@gmail.com** (ID: `951fe334-9bc7-4651-8bb9-a2b6d877aa8e`) completó el wizard de onboarding al 71% y aceptó términos dos veces (homepage + Step 9/11 del wizard), pero al volver a hacer login era redirigido al wizard en lugar de la página `/complete`.

### Root Cause

**Triple fallo arquitectónico:**

1. **Backend:** `OnboardingService.acceptTerms()` solo actualizaba tabla `nv_accounts`, NUNCA actualizaba `auth.users.raw_user_meta_data`
2. **Frontend Hook:** `useTermsAccepted()` solo leía de `localStorage`, NUNCA consultaba el JWT
3. **Auth Callback:** `ClientAuthCallback` no sincronizaba `terms_accepted` del JWT a `localStorage` al hacer login
4. **Signup OAuth:** `ensureMembership()` creaba usuarios sin inicializar `client_id`, `role`, `terms_accepted` en metadata

**Resultado:** El JWT contenía `terms_accepted: false` aunque el usuario había aceptado términos, y el frontend bloqueaba toda la aplicación.

---

## ✅ Soluciones Implementadas

### Fix 1: Backend - OnboardingService.acceptTerms()

**Archivo:** `apps/api/src/onboarding/onboarding.service.ts`  
**Líneas:** 2554-2634

**Qué hace:**
- Además de actualizar `nv_accounts`, ahora también actualiza `auth.users.raw_user_meta_data`
- Usa `adminClient.auth.admin.updateUserById()` para persistir `terms_accepted: true` en Supabase Auth
- Mantiene sincronización con `client_id` y `role` del usuario

**Código:**
```typescript
// Después de actualizar nv_accounts
const adminClient = this.dbRouter.getAdminClient();
const { data: authUsers, error: listError } = await adminClient.auth.admin.listUsers();

if (listError || !authUsers?.users) {
  this.logger.warn('[acceptTerms] No se pudo listar usuarios de Auth:', listError);
} else {
  const authUser = authUsers.users.find((u) => u.email === account.email);
  
  if (authUser) {
    await adminClient.auth.admin.updateUserById(authUser.id, {
      user_metadata: {
        ...authUser.user_metadata,
        terms_accepted: true,
        terms_version: version,
        client_id: authUser.user_metadata?.client_id || 'platform',
        role: authUser.user_metadata?.role || 'client',
      }
    });
  }
}
```

---

### Fix 2: Frontend Hook - useTermsAccepted()

**Archivo:** `apps/admin/src/hooks/useTermsAccepted.jsx`  
**Reescritura completa**

**Qué hace:**
- Lee `terms_accepted` de **localStorage Y JWT** (fuente dual)
- Sincroniza JWT → localStorage en cada render (useEffect)
- Actualiza **ambos** localStorage y JWT cuando se aceptan términos
- Usa `supabase.auth.updateUser()` para actualizar metadata en Auth

**Código:**
```typescript
useEffect(() => {
  const syncFromJWT = async () => {
    const { data: { session } } = await supabase.auth.getSession();
    const termsFromJWT = session?.user?.user_metadata?.terms_accepted;
    
    if (termsFromJWT === true) {
      localStorage.setItem("terms_accepted", "true");
      setTermsAccepted(true);
    }
  };
  syncFromJWT();
}, []);

const acceptTerms = async () => {
  localStorage.setItem("terms_accepted", "true");
  setTermsAccepted(true);
  
  // Actualizar metadata en Supabase Auth
  await supabase.auth.updateUser({
    data: { terms_accepted: true }
  });
};
```

---

### Fix 3: Frontend Auth Callback - ClientAuthCallback

**Archivo:** `apps/admin/src/pages/ClientAuthCallback.tsx`  
**Líneas:** 40-56 (insertadas)

**Qué hace:**
- Después de OAuth redirect, sincroniza `terms_accepted` del JWT a localStorage
- Previene que el usuario sea bloqueado por el modal de términos tras re-login

**Código:**
```typescript
const { data: { user }, error: userError } = await supabase.auth.getUser();

if (user?.user_metadata?.terms_accepted === true) {
  localStorage.setItem("terms_accepted", "true");
  console.log("[ClientAuthCallback] Synced terms_accepted from JWT to localStorage");
}
```

---

### Fix 4: Backend Signup - ensureMembership()

**Archivo:** `apps/api/src/auth/auth.service.ts`  
**Líneas:** ~1200-1290 (dos bloques modificados)

**Qué hace:**
- Cuando se crea un usuario nuevo (signup con Google OAuth), inicializa INMEDIATAMENTE su metadata en Supabase Auth
- Asegura que el JWT contenga `client_id`, `role`, `terms_accepted` desde el primer login
- Ejecuta dos veces: una para usuarios platform (sin clientId), otra para usuarios tenant (con clientId)

**Código:**
```typescript
// Después de insertar en tabla users
const metadataToSync: Record<string, any> = {
  client_id: this.isPlatformClientId(clientId) ? 'platform' : normalizedClientId,
  role: defaultRole,
  terms_accepted: false,
};

if (!this.isPlatformClientId(clientId)) {
  metadataToSync.personal_info = personal_info;
}

await this.adminClient.auth.admin.updateUserById(userId, {
  user_metadata: metadataToSync,
});
```

---

## 🛠️ Migración SQL Ejecutada

**Archivo:** `apps/admin/docs/sql/fix-terms-accepted-user-metadata.sql`

**Usuario afectado:** kaddocpendragon@gmail.com

**Query ejecutada:**
```sql
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || 
  '{"terms_accepted": true, "client_id": "platform", "role": "client"}'::jsonb
WHERE email = 'kaddocpendragon@gmail.com';
```

**Resultado:**
- `terms_accepted`: `true` ✅
- `client_id`: `"platform"` ✅
- `role`: `"client"` ✅
- `updated_at`: `2026-01-28 23:17:01.666118+00` ✅

---

## 📚 Documentación Creada

1. **`fix-terms-accepted-user-metadata.sql`** - Queries SQL para migración
2. **`MIGRATION_GUIDE_TERMS_ACCEPTED.md`** - Guía paso a paso para ejecutar migración
3. **`bug-analysis-terms-accepted-20260128.md`** - Análisis técnico con diagramas Mermaid
4. **`fix-terms-accepted-redirect-20260128.md`** - Registro de cambios completo
5. **`EXECUTIVE_SUMMARY_TERMS_BUG.md`** - Resumen ejecutivo no técnico
6. **`fix-signup-metadata-init-20260128.md`** - Documentación del Fix 4
7. **`fix-terms-accepted.sh`** - Script bash para ejecución manual
8. **`run-terms-migration.sh`** - Script automatizado con psql

---

## 🔍 Testing

### Test 1: Usuario Existente (kaddocpendragon@gmail.com)

**Pasos:**
1. Usuario hace logout
2. Usuario hace login con Google
3. Verificar que NO se muestre modal de términos
4. Verificar que NO se redirija a `/wizard`
5. Verificar que se muestre dashboard de completitud `/complete`

**Estado:** ⏳ Pendiente de ejecución por usuario

---

### Test 2: Usuario Nuevo

**Pasos:**
1. Crear usuario nuevo desde wizard con Google OAuth
2. Verificar JWT contiene:
   ```json
   {
     "client_id": "platform",
     "role": "client", 
     "terms_accepted": false
   }
   ```
3. Aceptar términos en Step 9/11
4. Logout y re-login
5. Verificar que no se bloquee con modal ni redirija a wizard

**Estado:** ⏳ Pendiente de implementación en QA

---

### Test 3: Usuario Existente Sin Metadata

**Escenario:** Usuario creado antes de estos fixes

**Query de diagnóstico:**
```sql
SELECT 
  id,
  email,
  raw_user_meta_data->>'terms_accepted' as terms_accepted,
  raw_user_meta_data->>'client_id' as client_id,
  raw_user_meta_data->>'role' as role
FROM auth.users
WHERE raw_user_meta_data->>'terms_accepted' IS NULL
  OR raw_user_meta_data->>'client_id' IS NULL;
```

**Fix:** Ejecutar migración SQL para cada usuario afectado

---

## 🚀 Deployment

### Archivos Modificados

**Backend:**
- `apps/api/src/onboarding/onboarding.service.ts`
- `apps/api/src/auth/auth.service.ts`

**Frontend:**
- `apps/admin/src/hooks/useTermsAccepted.jsx`
- `apps/admin/src/pages/ClientAuthCallback.tsx`

### Comandos

```bash
# Backend (Railway)
cd apps/api
npm run build
git push origin feature/automatic-multiclient-onboarding

# Frontend (Netlify)
cd apps/admin
npm run build
git push origin feature/automatic-multiclient-onboarding
```

### Verificación Post-Deploy

```bash
# Verificar logs en Railway
railway logs

# Verificar build en Netlify
netlify deploy --prod

# Test E2E
npm run test:e2e
```

---

## 📊 Impacto

### Usuarios Afectados

- **Actual:** 1 usuario confirmado (kaddocpendragon@gmail.com)
- **Potencial:** Todos los usuarios que aceptaron términos desde el lanzamiento del wizard

### Query de Auditoría

```sql
-- Contar usuarios sin metadata crítico
SELECT COUNT(*) as affected_users
FROM auth.users
WHERE raw_user_meta_data->>'terms_accepted' IS NULL
  OR raw_user_meta_data->>'client_id' IS NULL;

-- Listar emails afectados
SELECT email, created_at
FROM auth.users
WHERE raw_user_meta_data->>'terms_accepted' IS NULL
  OR raw_user_meta_data->>'client_id' IS NULL
ORDER BY created_at DESC;
```

---

## 🔐 Seguridad

### Cambios en RLS

**Ninguno.** Los fixes no modifican políticas RLS.

### Cambios en Auth

- ✅ Metadata `terms_accepted` ahora es fuente de verdad
- ✅ Frontend valida contra JWT (no solo localStorage)
- ✅ Backend sincroniza automáticamente en signup y term acceptance

---

## 📝 Rollback Plan

### Si hay problemas críticos:

1. **Revertir commits:**
   ```bash
   git revert <commit-hash-fix-4>
   git revert <commit-hash-fix-3>
   git revert <commit-hash-fix-2>
   git revert <commit-hash-fix-1>
   git push
   ```

2. **Restaurar metadata de usuario (si fue modificado incorrectamente):**
   ```sql
   -- Backup antes de migración
   SELECT raw_user_meta_data 
   FROM auth.users 
   WHERE email = 'usuario@example.com';
   
   -- Restaurar
   UPDATE auth.users
   SET raw_user_meta_data = '<BACKUP_JSONB>'::jsonb
   WHERE email = 'usuario@example.com';
   ```

3. **Limpiar localStorage de usuarios:**
   ```javascript
   localStorage.removeItem("terms_accepted");
   ```

---

## ✨ Mejoras Futuras

1. **Webhook de Supabase Auth:** Escuchar evento `user.created` y sincronizar metadata automáticamente
2. **Admin Panel:** Herramienta para corregir masivamente metadata de usuarios afectados
3. **Monitoring:** Dashboard en Grafana con métrica "users_with_missing_metadata"
4. **E2E Tests:** Agregar tests automatizados para flujo completo signup → terms → login

---

## 👥 Responsables

- **Autor:** GitHub Copilot Agent
- **Revisor:** @eliaspiscitelli
- **QA:** Pendiente
- **Deploy:** Pendiente

---

**Fecha:** 2026-01-28  
**Branch:** feature/automatic-multiclient-onboarding  
**Status:** ✅ Implementado - ⏳ Testing Pendiente

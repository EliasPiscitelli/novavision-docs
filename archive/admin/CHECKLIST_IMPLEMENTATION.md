# Checklist: Implementación Completa - Bug Terms Accepted

## ✅ Implementado

### Backend

- [x] **OnboardingService.acceptTerms()** - Actualiza `auth.users.raw_user_meta_data` además de `nv_accounts`
  - Archivo: `apps/api/src/onboarding/onboarding.service.ts`
  - Líneas: 2554-2634
  - Commit: Pendiente

- [x] **AuthService.ensureMembership()** - Inicializa metadata en signup con Google OAuth
  - Archivo: `apps/api/src/auth/auth.service.ts`
  - Líneas: ~1200-1290 (dos bloques)
  - Commit: Pendiente

### Frontend

- [x] **useTermsAccepted()** - Sincronización bidireccional localStorage ↔ JWT
  - Archivo: `apps/admin/src/hooks/useTermsAccepted.jsx`
  - Reescritura completa
  - Commit: Pendiente

- [x] **ClientAuthCallback** - Sincroniza JWT → localStorage en OAuth redirect
  - Archivo: `apps/admin/src/pages/ClientAuthCallback.tsx`
  - Líneas: 40-56
  - Commit: Pendiente

### Migración

- [x] **SQL Migration** - Usuario kaddocpendragon@gmail.com actualizado
  - Ejecutado: 2026-01-28 23:17:01
  - Estado: ✅ Completado

### Documentación

- [x] `fix-terms-accepted-user-metadata.sql` - Queries SQL
- [x] `MIGRATION_GUIDE_TERMS_ACCEPTED.md` - Guía de migración
- [x] `bug-analysis-terms-accepted-20260128.md` - Análisis técnico
- [x] `fix-terms-accepted-redirect-20260128.md` - Registro de cambios
- [x] `EXECUTIVE_SUMMARY_TERMS_BUG.md` - Resumen ejecutivo
- [x] `fix-signup-metadata-init-20260128.md` - Documentación Fix 4
- [x] `COMPLETE_FIX_SUMMARY_20260128.md` - Resumen completo
- [x] `fix-terms-accepted.sh` - Script bash manual
- [x] `run-terms-migration.sh` - Script automatizado
- [x] `validate-user-metadata.sh` - Script de validación

---

## ⏳ Pendiente de Ejecución

### 1. Testing del Usuario Afectado

**Usuario:** kaddocpendragon@gmail.com

**Pasos:**
1. [ ] Usuario hace logout en `/admin`
2. [ ] Usuario hace login con Google
3. [ ] Verificar que **NO** se muestre modal de términos
4. [ ] Verificar que **NO** se redirija a `/wizard`
5. [ ] Verificar que se muestre dashboard `/complete`

**Resultado esperado:** ✅ Usuario accede directamente a `/complete` sin bloqueos

---

### 2. Validación de Metadata (Todos los Usuarios)

**Script:** `apps/admin/scripts/validate-user-metadata.sh`

**Ejecutar:**
```bash
cd apps/admin
./scripts/validate-user-metadata.sh
```

**Revisar output para:**
- [ ] Usuarios sin `client_id`
- [ ] Usuarios sin `role`
- [ ] Usuarios sin `terms_accepted`

**Acción:** Si hay usuarios afectados, ejecutar migración SQL para cada uno

---

### 3. Build & Verificación de Errores

**Backend:**
```bash
cd apps/api
npm run build
```

**Resultado esperado:** ✅ Build exitoso sin errores TypeScript

**Frontend:**
```bash
cd apps/admin
npm run build
```

**Resultado esperado:** ✅ Build exitoso sin errores

---

### 4. Testing E2E - Usuario Nuevo

**Escenario:** Signup completo desde wizard

**Pasos:**
1. [ ] Abrir `/wizard` en modo incógnito
2. [ ] Completar Steps 1-4 (slug, plan, diseño, catálogo)
3. [ ] En Step 5/6 (Auth), hacer "Login with Google" con usuario nuevo
4. [ ] Verificar en consola del navegador: JWT contiene `client_id: "platform"`, `role: "client"`, `terms_accepted: false`
5. [ ] Continuar hasta Step 9/11 (Términos)
6. [ ] Aceptar términos
7. [ ] Verificar en consola: `localStorage.getItem("terms_accepted")` = `"true"`
8. [ ] Verificar en consola: JWT actualizado con `terms_accepted: true`
9. [ ] Completar wizard y submit
10. [ ] Hacer logout
11. [ ] Hacer login con Google nuevamente
12. [ ] **Verificar:** NO aparece modal de términos, redirige a `/complete`

**Resultado esperado:** ✅ Flujo completo sin bloqueos

---

### 5. Auditoría Base de Datos

**Query 1: Contar usuarios afectados**
```sql
-- Ejecutar en Admin DB
SELECT COUNT(*) as affected_users
FROM auth.users
WHERE raw_user_meta_data->>'terms_accepted' IS NULL
  OR raw_user_meta_data->>'client_id' IS NULL;
```

**Query 2: Listar emails afectados**
```sql
SELECT 
  email, 
  created_at,
  raw_user_meta_data->>'client_id' as client_id,
  raw_user_meta_data->>'role' as role,
  raw_user_meta_data->>'terms_accepted' as terms_accepted
FROM auth.users
WHERE raw_user_meta_data->>'terms_accepted' IS NULL
  OR raw_user_meta_data->>'client_id' IS NULL
ORDER BY created_at DESC;
```

**Acción:** Documentar usuarios que necesitan migración manual

---

### 6. Deploy a Staging/Production

**Pre-Deploy:**
- [ ] Commits locales pusheados a branch
- [ ] Build exitoso (backend + frontend)
- [ ] Tests E2E ejecutados

**Deploy Backend (Railway):**
```bash
cd apps/api
git push origin feature/automatic-multiclient-onboarding
# Railway auto-deploys
```

**Deploy Frontend (Netlify):**
```bash
cd apps/admin
git push origin feature/automatic-multiclient-onboarding
# Netlify auto-deploys
```

**Post-Deploy:**
- [ ] Verificar logs en Railway (no errores críticos)
- [ ] Verificar build en Netlify (status 200)
- [ ] Smoke test: Login con Google en producción

---

### 7. Migración Masiva (Si hay usuarios afectados)

**Si la auditoría (paso 5) encontró usuarios sin metadata:**

**Script SQL:**
```sql
-- Template para cada usuario afectado
UPDATE auth.users
SET raw_user_meta_data = raw_user_meta_data || 
  '{"terms_accepted": false, "client_id": "platform", "role": "client"}'::jsonb
WHERE email = 'usuario@example.com'
  AND (raw_user_meta_data->>'client_id' IS NULL 
       OR raw_user_meta_data->>'terms_accepted' IS NULL);
```

**Nota:** Usar `terms_accepted: false` para usuarios que no han aceptado explícitamente. El sistema les mostrará el modal de términos en su próximo login.

---

### 8. Monitoring Post-Deploy

**Métricas a monitorear:**

1. **Errores 500 en `/auth/google/callback`**
   - Dashboard: Railway logs
   - Buscar: `[handleGoogleCallback]` + `error`

2. **Usuarios bloqueados por modal de términos**
   - Frontend: Console errors
   - Buscar: `terms_accepted: false` en logs

3. **Metadata faltante en JWT**
   - Backend: Logs de `syncUserMetadataWithInternal`
   - Buscar: `[ensureMembership] Metadata inicializado`

**Alertas críticas:**
- ❌ Más de 5 errores en `handleGoogleCallback` en 1 hora
- ❌ Usuarios reportando "no puedo entrar" después de login

---

### 9. Comunicación a Usuarios Afectados

**Si se identifican usuarios bloqueados:**

**Template de email:**
```
Hola [Nombre],

Detectamos y resolvimos un problema técnico que podría haberte impedido 
acceder a tu cuenta después de iniciar sesión.

Hemos aplicado una corrección y tu cuenta ahora debería funcionar 
correctamente. Por favor, intenta iniciar sesión nuevamente:

https://admin.novavision.com.ar

Si sigues teniendo problemas, responde a este email con detalles del error.

Disculpas por las molestias,
Equipo NovaVision
```

---

### 10. Rollback Plan (Si hay problemas críticos)

**Síntomas que requieren rollback:**
- Ningún usuario puede hacer login con Google
- Errores 500 masivos en `/auth/google/callback`
- Metadata corrupto (usuarios pierden acceso a sus tiendas)

**Pasos de rollback:**

1. **Revertir código:**
```bash
git revert HEAD~4  # Revierte los 4 commits de los fixes
git push origin feature/automatic-multiclient-onboarding --force
```

2. **Restaurar metadata de usuarios afectados:**
```sql
-- Ejecutar backup previo (debe haberse guardado antes de migración)
UPDATE auth.users
SET raw_user_meta_data = <BACKUP_JSONB>
WHERE id = '<USER_ID>';
```

3. **Limpiar caché frontend:**
```javascript
// Ejecutar en consola del navegador de usuarios afectados
localStorage.clear();
location.reload();
```

---

## 📊 Métricas de Éxito

**Criterios de aceptación:**

1. ✅ Usuario kaddocpendragon@gmail.com puede hacer login sin bloqueos
2. ✅ Usuarios nuevos tienen metadata correcto en primer JWT
3. ✅ Aceptar términos persiste correctamente en Auth
4. ✅ Frontend sincroniza localStorage ↔ JWT sin errores
5. ✅ Cero errores 500 relacionados con metadata en 24h post-deploy

---

## 🎯 Próximos Pasos Recomendados

1. **Tests E2E automatizados** (Playwright/Cypress)
   - Flujo completo signup → terms → login → redirect
   - Validar JWT en cada paso

2. **Webhook de Supabase Auth**
   - Escuchar evento `user.created`
   - Sincronizar metadata automáticamente sin depender de backend

3. **Admin Panel para metadata**
   - UI para corregir metadata de usuarios
   - Herramienta de diagnóstico masivo

4. **Monitoring Dashboard**
   - Grafana: métrica `users_with_missing_metadata`
   - Alerta si supera threshold

---

**Última actualización:** 2026-01-28  
**Responsable:** @eliaspiscitelli  
**Status:** ⏳ Implementación completa - Testing pendiente

# Fix: Wizard Auth Architecture - Admin DB vs Backend DB

**Date:** 2026-01-28  
**Issue:** Users completing wizard were authenticating in Backend DB instead of Admin DB  
**Status:** ✅ Fixed (code) + 🔄 Migration required (user data)

---

## Problem

### Incorrect Architecture Implementation

The code was configured **incorrectly**:

```javascript
// ❌ WRONG: Was using Backend DB for wizard auth
export const supabase = backendSupabaseInstance || adminSupabaseInstance;
```

This caused:
- ✅ User `kaddocpendragon@gmail.com` exists in **Backend DB** (ulndkhijxtxvpmbbfrgp)
- ❌ User does NOT exist in **Admin DB** (erbfzlsznqsmwmjugspo) ← **Where it should be**

### Correct Architecture

**Admin DB (erbfzlsznqsmwmjugspo):**
- Platform users (NovaVision admin panel)
- Wizard signups (clients completing onboarding)
- Pre-approval client accounts
- Super admins

**Backend DB (ulndkhijxtxvpmbbfrgp):**
- Multicliente stores (approved clients)
- Tenant data (products, orders, customers)
- Post-approval operations

---

## Solution

### 1. Code Fix ✅

**File:** `apps/admin/src/services/supabase/index.js`

```javascript
// ✅ CORRECT: Use Admin DB for wizard auth
export const supabase = adminSupabaseInstance || backendSupabaseInstance;
```

**Impact:**
- Future signups will correctly authenticate in Admin DB
- Wizard users will have their data in the right database
- No more confusion between platform vs tenant auth

**Changed:**
- Line 88-90: Inverted client priority
- Updated comments to reflect correct architecture
- Added explanation of DB separation

---

### 2. User Migration 🔄

**Current user affected:** `kaddocpendragon@gmail.com` (ID: `935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0`)

**Migration files created:**
1. `apps/admin/docs/sql/migrate-user-backend-to-admin.sql` - SQL migration script
2. `apps/admin/scripts/migrate-user-to-admin.sh` - Bash automation helper

**Migration steps:**

```bash
# 1. Run migration helper (exports data)
./apps/admin/scripts/migrate-user-to-admin.sh

# 2. Follow manual steps in SQL file
# apps/admin/docs/sql/migrate-user-backend-to-admin.sql
```

**What gets migrated:**
- ✅ `auth.users` record (with `terms_accepted: true`)
- ✅ `nv_users` record (completion 71%, review_status)
- ✅ All metadata and timestamps
- ✅ OAuth credentials (Google)

**Post-migration verification:**

```sql
-- Admin DB: Should return 1 row with terms_accepted=true
SELECT id, email, raw_user_meta_data->>'terms_accepted' 
FROM auth.users 
WHERE email = 'kaddocpendragon@gmail.com';

-- Backend DB: Should return 0 rows (after cleanup)
SELECT COUNT(*) FROM auth.users 
WHERE email = 'kaddocpendragon@gmail.com';
```

---

## Testing

### Before Fix
- ❌ User signup → Backend DB
- ❌ JWT issued by ulndkhijxtxvpmbbfrgp.supabase.co
- ❌ `terms_accepted: false` in token (stale)
- ❌ Wizard redirect loop

### After Fix + Migration
- ✅ User signup → Admin DB
- ✅ JWT issued by erbfzlsznqsmwmjugspo.supabase.co
- ✅ `terms_accepted: true` in metadata
- ✅ Wizard completion loads correctly

---

## Rollback Plan

If migration fails or causes issues:

```sql
-- Rollback: Delete from Admin DB
psql "postgresql://...@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres" << 'EOF'
BEGIN;
DELETE FROM public.nv_users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';
DELETE FROM auth.users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';
COMMIT;
EOF

-- Restore: Backend DB data already exists (don't delete until verified)
```

**Code rollback:**
```javascript
// Revert to old (wrong) behavior if needed
export const supabase = backendSupabaseInstance || adminSupabaseInstance;
```

---

## Future Prevention

### ✅ Done
1. Fixed Supabase client initialization order
2. Updated documentation with correct architecture
3. Created migration tools for future cases

### 🔄 Recommended
1. Add database router logic to detect wizard vs store context
2. Implement client creation webhook to auto-migrate on approval
3. Add RLS policies to prevent cross-database contamination
4. Create E2E test for signup → wizard → approval flow

---

## Related Files

- ✅ `apps/admin/src/services/supabase/index.js` - Main fix
- 📝 `apps/admin/docs/sql/migrate-user-backend-to-admin.sql` - Migration SQL
- 🛠️ `apps/admin/scripts/migrate-user-to-admin.sh` - Migration helper
- 📄 `apps/admin/docs/AUTH_FLOW.md` - Architecture documentation
- 📄 Previous fix: `COMPLETE_FIX_SUMMARY_20260128.md` (terms_accepted backend)

---

## Deployment Checklist

- [x] Code changes committed
- [x] Migration scripts created
- [ ] Migration executed and verified
- [ ] User logout/login to refresh JWT
- [ ] Test wizard completion flow
- [ ] Delete user from Backend DB (cleanup)
- [ ] Update environment variables if needed
- [ ] Deploy to production

---

**Next Steps for User:**
1. Cierra sesión completamente
2. Espera a que ejecutemos la migración SQL
3. Vuelve a iniciar sesión (recibirás JWT del Admin DB correcto)
4. El wizard debería cargar tu progreso 71% correctamente
5. Continúa con los pasos restantes

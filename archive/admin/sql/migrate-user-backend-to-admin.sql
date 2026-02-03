-- Migration: Move wizard user from Backend DB to Admin DB
-- User: kaddocpendragon@gmail.com (935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0)
-- Reason: User created in wrong database during wizard signup
-- Target: Admin DB (erbfzlsznqsmwmjugspo)
-- Date: 2026-01-28

-- STEP 1: Extract user data from Backend DB (ulndkhijxtxvpmbbfrgp)
-- Run this first to get the data:
/*
psql "postgresql://postgres:Novavision_39628997_2025@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres" -c "
SELECT 
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  invited_at,
  confirmation_token,
  confirmation_sent_at,
  recovery_token,
  recovery_sent_at,
  email_change_token_new,
  email_change,
  email_change_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  created_at,
  updated_at,
  phone,
  phone_confirmed_at,
  phone_change,
  phone_change_token,
  phone_change_sent_at,
  confirmed_at,
  email_change_token_current,
  email_change_confirm_status,
  banned_until,
  reauthentication_token,
  reauthentication_sent_at,
  is_sso_user,
  deleted_at
FROM auth.users 
WHERE email = 'kaddocpendragon@gmail.com';
" -o /tmp/user_backup_backend.txt
*/

-- STEP 2: Get nv_users data from Backend DB
/*
psql "postgresql://postgres:Novavision_39628997_2025@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres" -c "
SELECT 
  id,
  email,
  first_name,
  last_name,
  role,
  client_id,
  completion_percentage,
  review_status,
  rejection_reason,
  approved_at,
  rejected_at,
  created_at,
  updated_at
FROM public.nv_users 
WHERE email = 'kaddocpendragon@gmail.com';
" -o /tmp/nv_users_backup_backend.txt
*/

-- STEP 3: Insert into Admin DB (erbfzlsznqsmwmjugspo) auth.users
-- Replace values with data from STEP 1
-- NOTE: You'll need to run this with service_role permissions

/*
psql "postgresql://postgres:Novavision_39628997_2025@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres" << 'EOF'
BEGIN;

-- Insert user into auth.users
INSERT INTO auth.users (
  id,
  instance_id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  invited_at,
  confirmation_token,
  confirmation_sent_at,
  recovery_token,
  recovery_sent_at,
  email_change_token_new,
  email_change,
  email_change_sent_at,
  last_sign_in_at,
  raw_app_meta_data,
  raw_user_meta_data,
  is_super_admin,
  created_at,
  updated_at,
  phone,
  phone_confirmed_at,
  phone_change,
  phone_change_token,
  phone_change_sent_at,
  confirmed_at,
  email_change_token_current,
  email_change_confirm_status,
  banned_until,
  reauthentication_token,
  reauthentication_sent_at,
  is_sso_user,
  deleted_at
)
VALUES (
  '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0',  -- id from Backend DB
  '00000000-0000-0000-0000-000000000000',  -- instance_id (default)
  'authenticated',  -- aud
  'authenticated',  -- role
  'kaddocpendragon@gmail.com',  -- email
  '<encrypted_password_from_step1>',  -- COPY from Backend DB
  '<email_confirmed_at_from_step1>',  -- COPY from Backend DB
  NULL,  -- invited_at
  '',  -- confirmation_token
  NULL,  -- confirmation_sent_at
  '',  -- recovery_token
  NULL,  -- recovery_sent_at
  '',  -- email_change_token_new
  '',  -- email_change
  NULL,  -- email_change_sent_at
  '<last_sign_in_at_from_step1>',  -- COPY from Backend DB
  '<raw_app_meta_data_from_step1>',  -- COPY from Backend DB
  '{"terms_accepted": true, "client_id": "platform", "role": "client", "provider": "google", "providers": ["google"]}'::jsonb,  -- IMPORTANT: terms_accepted=true
  false,  -- is_super_admin
  '<created_at_from_step1>',  -- COPY from Backend DB
  now(),  -- updated_at (now)
  NULL,  -- phone
  NULL,  -- phone_confirmed_at
  '',  -- phone_change
  '',  -- phone_change_token
  NULL,  -- phone_change_sent_at
  '<confirmed_at_from_step1>',  -- COPY from Backend DB
  '',  -- email_change_token_current
  0,  -- email_change_confirm_status
  NULL,  -- banned_until
  '',  -- reauthentication_token
  NULL,  -- reauthentication_sent_at
  false,  -- is_sso_user
  NULL  -- deleted_at
)
ON CONFLICT (id) DO UPDATE SET
  raw_user_meta_data = EXCLUDED.raw_user_meta_data,
  updated_at = now();

-- Insert or update in nv_users
INSERT INTO public.nv_users (
  id,
  email,
  first_name,
  last_name,
  role,
  client_id,
  completion_percentage,
  review_status,
  rejection_reason,
  approved_at,
  rejected_at,
  created_at,
  updated_at
)
VALUES (
  '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0',
  'kaddocpendragon@gmail.com',
  '<first_name_from_step2>',  -- COPY from Backend DB
  '<last_name_from_step2>',  -- COPY from Backend DB
  'client',
  'platform',
  71,  -- Current completion
  'changes_requested',  -- Current status
  NULL,
  NULL,
  NULL,
  '<created_at_from_step2>',  -- COPY from Backend DB
  now()
)
ON CONFLICT (id) DO UPDATE SET
  email = EXCLUDED.email,
  first_name = EXCLUDED.first_name,
  last_name = EXCLUDED.last_name,
  role = EXCLUDED.role,
  client_id = EXCLUDED.client_id,
  completion_percentage = EXCLUDED.completion_percentage,
  review_status = EXCLUDED.review_status,
  updated_at = now();

COMMIT;

-- Verify migration
SELECT 
  u.id, 
  u.email, 
  u.raw_user_meta_data->>'terms_accepted' as terms_accepted,
  u.raw_user_meta_data->>'client_id' as client_id,
  u.raw_user_meta_data->>'role' as role,
  nu.completion_percentage,
  nu.review_status,
  u.updated_at
FROM auth.users u
LEFT JOIN public.nv_users nu ON nu.id = u.id
WHERE u.email = 'kaddocpendragon@gmail.com';

EOF
*/

-- STEP 4: (OPTIONAL) Delete from Backend DB after confirming Admin DB works
-- DO NOT RUN THIS until you've verified the user can login to Admin DB successfully
/*
psql "postgresql://postgres:Novavision_39628997_2025@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres" << 'EOF'
BEGIN;

-- Delete from nv_users first (foreign key)
DELETE FROM public.nv_users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';

-- Delete from auth.users
DELETE FROM auth.users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';

COMMIT;

-- Verify deletion
SELECT COUNT(*) FROM auth.users WHERE email = 'kaddocpendragon@gmail.com';
-- Should return 0

EOF
*/

-- ROLLBACK (if something goes wrong)
-- Run this ONLY if you need to undo the Admin DB insertion:
/*
psql "postgresql://postgres:Novavision_39628997_2025@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres" << 'EOF'
BEGIN;
DELETE FROM public.nv_users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';
DELETE FROM auth.users WHERE id = '935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0';
COMMIT;
EOF
*/

# Cambio: Security Remediation Phase 3

- **Autor:** GitHub Copilot (agente)
- **Fecha:** 2025-07-15
- **Rama API:** `feature/automatic-multiclient-onboarding`
- **Rama Web:** `feature/multitenant-storefront` (→ cherry-pick a develop primero)

## Archivos modificados

### Migraciones aplicadas en live DB
- `apps/api/migrations/backend/20250715_order_items_rls_tenant.sql` — 4 políticas tenant-scoped para order_items
- `apps/api/migrations/backend/20250715_secdefiner_search_path.sql` — SET search_path en 10 funciones Backend
- `apps/api/migrations/admin/20250715_secdefiner_search_path.sql` — SET search_path en 15 funciones Admin

### Web Storefront
- `apps/web/netlify.toml` — CSP hardening + security headers

### Docs
- `novavision-docs/audit/SECURITY_AUDIT_2025-07-14.md` — Checklist actualizado con Phase 3

## Resumen de cambios

### 1. order_items RLS tenant-scoped (Backend DB) — P0
**Problema:** `order_items` tenía RLS habilitado pero solo con políticas de super_admin (email hardcodeado) y service_role. Usuarios normales y admins de tenant no podían acceder a items de sus órdenes vía RLS directo.

**Solución:** 4 políticas que scop a través de JOIN a `orders.client_id`:
- `order_items_select_tenant` — owner del order O admin del tenant
- `order_items_insert_admin` — solo admin del tenant
- `order_items_update_admin` — solo admin del tenant
- `order_items_delete_admin` — solo admin del tenant

**Patrón usado:**
```sql
EXISTS (
  SELECT 1 FROM public.orders o
  WHERE o.id = order_items.order_id
    AND o.client_id = current_client_id()
    AND (o.user_id = auth.uid() OR is_admin())
)
```

### 2. SECURITY DEFINER + SET search_path (ambas DBs) — P1
**Problema:** 25 funciones `SECURITY DEFINER` (10 Backend + 15 Admin) ejecutaban con privilegios elevados sin fijar `search_path`, exponiendo a ataques de search_path hijacking.

**Solución:** `ALTER FUNCTION ... SET search_path = 'public', 'pg_temp'` en las 25 funciones.

**Funciones corregidas (Backend DB):**
- `dashboard_client_detail_v1`, `dashboard_client_detail_v2`
- `dashboard_metrics_v1`, `dashboard_metrics_v2`
- `dashboard_tops_v1`, `dashboard_tops_v2`
- `decrypt_mp_token`, `encrypt_mp_token`
- `export_usage_snapshot`, `fn_update_coupons_usage`

**Funciones corregidas (Admin DB):**
- `claim_slug_final`, `cleanup_stale_subscription_locks`
- `generate_last_month_invoices`, `generate_monthly_invoices` (×2 overloads)
- `get_app_secret`, `is_super_admin`
- `purge_completed_outbox_events`, `purge_old_lifecycle_events`
- `purge_old_notification_outbox`, `purge_old_provisioning_jobs`
- `purge_old_webhook_events`, `release_subscription_lock`
- `seo_ai_balance`, `try_lock_subscription`

### 3. Web CSP hardening — P2
**Cambios en `apps/web/netlify.toml`:**
- ❌ **Removido:** `Access-Control-Allow-Origin: *` (innecesario en CDN estático, los CORS se manejan en la API)
- ❌ **Removido:** `Access-Control-Allow-Methods` y `Access-Control-Allow-Headers` (son headers de API, no de sitio estático)
- ❌ **Removido:** `http://localhost:3000` de connect-src (no debe estar en producción)
- ❌ **Removido:** `https://templatetwobe-production.up.railway.app` de connect-src (ya migrado a novavision-production)
- ✅ **Añadido:** `X-Content-Type-Options: nosniff`
- ✅ **Añadido:** `X-Frame-Options: DENY`
- ✅ **Añadido:** `Referrer-Policy: strict-origin-when-cross-origin`
- ✅ **Añadido:** `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- ⚠️ **Mantenido:** `'unsafe-eval'` en script-src — **requerido por MercadoPago SDK** (checkout bricks usan eval internamente)

## Verificación post-migración

```sql
-- Backend DB: 0 funciones sin search_path
SELECT COUNT(*) FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public' AND p.prosecdef = true
  AND pg_get_functiondef(p.oid) NOT LIKE '%search_path%';
-- Resultado: 0 ✅

-- Admin DB: 0 funciones sin search_path
-- Resultado: 0 ✅

-- order_items: 6 políticas (4 nuevas + 2 existentes)
SELECT policyname FROM pg_policies WHERE tablename = 'order_items';
-- Resultado: 6 rows ✅
```

## Cómo probar

1. **order_items RLS:** Hacer login como usuario de Tenant A → cargar orden con items → verificar que los items se muestran. Intentar acceder a items de Tenant B → debe dar 0 resultados.
2. **SECURITY DEFINER:** Las funciones de dashboard y métricas deben seguir funcionando. Verificar en admin panel que las métricas se cargan correctamente.
3. **Web CSP:** Abrir una tienda publicada → verificar que no hay errores en consola. El checkout con MercadoPago debe funcionar. Verificar headers con `curl -I https://{slug}.novavision.lat` → debe mostrar los nuevos security headers.

## Notas de seguridad

- `unsafe-eval` no se pudo remover del Web storefront porque MercadoPago SDK lo requiere. Esto es una limitación del vendor. Documentado con comentario en el TOML.
- `internal_key` → httpOnly cookie se mantiene DIFERIDO (cross-origin entre novavision.lat y *.railway.app requiere SameSite=None + Safari ITP consideration).
- Los 2 hallazgos P0 restantes pendientes son: H-01 (email hardcodeado en 78 tablas — cambio masivo, requiere planificación aparte) y builder_token en localStorage.

## Riesgos

- **Bajo:** Las políticas de order_items usan JOIN que puede impactar performance en tablas grandes. Mitigado por el índice existente en `orders(client_id)`.
- **Bajo:** Remover CORS wildcard del storefront podría afectar si hay integraciones externas consumiendo assets. En la práctica, los assets se cargan directamente (no vía XHR), así que no debería impactar.

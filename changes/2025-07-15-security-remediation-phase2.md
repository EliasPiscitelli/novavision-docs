# Security Remediation Phase 2

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding

## Archivos Modificados

### API (templatetwobe)
- `src/accounts/accounts.service.ts` — DNI storage: almacenar paths en vez de public URLs, usar signed URLs para retornar datos
- `src/main.ts` — Restringir ngrok CORS a entornos no-producción
- `migrations/admin/20250714_rls_auth_bridge_provisioning_steps.sql` — RLS para auth_bridge_codes y provisioning_job_steps

### Admin (novavision)
- `netlify.toml` — Agregar CSP + security headers (X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy)

## Resumen de Cambios

### 1. DNI PII Protection — `accounts.service.ts`
**Problema:** `getPublicUrl()` genera URLs permanentes y predecibles para documentos DNI (PII sensible). Se almacenaba la public URL directamente en la base de datos.

**Solución:**
- `uploadDni()` ahora almacena el **path** del storage (ej: `clientId/uploads/file.jpg`) en vez de la public URL
- `verifyIdentityWithDniUpload()` almacena `frontPath` y `backPath` en vez de public URLs
- `resolveSignedUrl()` actualizado para manejar tanto paths raw (nuevos) como legacy public URLs (backwards compatible)
- Si falla la generación del signed URL, retorna `null` en vez de caer back a la public URL (defense-in-depth para PII)

### 2. Ngrok CORS restricted — `main.ts`
**Problema:** El wildcard `*.ngrok-free.app` en CORS permitía tunneling desde cualquier ngrok URL, incluso en producción.

**Solución:** Envuelto en `!isProd` check — ngrok solo permitido en development/staging.

### 3. Admin CSP Headers — `netlify.toml`
**Problema:** El admin panel no tenía headers de seguridad (CSP, X-Frame-Options, etc.), permitiendo potencialmente ataques XSS, clickjacking, y MIME sniffing.

**Solución:** Headers agregados:
- `Content-Security-Policy`: `default-src 'self'`, script-src sin `unsafe-eval`, connect-src con Supabase + Railway, img-src con Supabase storage
- `X-Content-Type-Options: nosniff`
- `X-Frame-Options: DENY`
- `Referrer-Policy: strict-origin-when-cross-origin`
- `Permissions-Policy: camera=(), microphone=(), geolocation=()`
- Cache headers para assets estáticos (1 año, immutable)

### 4. RLS Migration — `20250714_rls_auth_bridge_provisioning_steps.sql`
**Problema:** Las tablas `auth_bridge_codes` y `provisioning_job_steps` en Admin DB no tenían RLS habilitado. Cualquier usuario autenticado podría leer/modificar códigos SSO bridge o datos de provisioning.

**Solución:** Migración SQL que:
- Habilita RLS en ambas tablas
- Fuerza RLS incluso para table owner (`FORCE ROW LEVEL SECURITY`)
- Crea política bypass para `service_role` (solo el backend accede estas tablas)
- **NOTA:** Esta migración debe ejecutarse manualmente en la Admin DB (Supabase project `erbfzlsznqsmwmjugspo`)

### 5. internal_key → httpOnly Cookie (DIFERIDO a Phase 3)
**Razón del diferimiento:**
- El admin frontend (`novavision.lat`) y backend (`novavision-production.up.railway.app`) están en dominios diferentes
- Cookies cross-origin requieren `SameSite=None; Secure` y `withCredentials: true` en axios
- Safari ITP puede bloquear third-party cookies
- **Riesgo alto** de romper toda la comunicación admin↔API
- **Mitigado parcialmente** por: CSP nuevo (reduce XSS), sessionStorage per-tab, key enviada solo en rutas super admin
- Se documentará un plan detallado para Phase 3

## Cómo Probar

### DNI Signed URLs
1. Subir un DNI vía endpoint de verificación de identidad
2. Verificar en DB que `dni_front_url` almacena un **path** (ej: `abc123/uploads/file.jpg`) y no una URL completa
3. Llamar `GET /accounts/:id/info` y verificar que las URLs retornadas son **signed** (contienen `token=...` y expiran en 1 hora)

### Ngrok CORS
1. En producción: verificar que requests desde `*.ngrok-free.app` son bloqueados por CORS
2. En desarrollo (`NODE_ENV=development`): verificar que ngrok sigue funcionando

### Admin CSP
1. Deployar admin a Netlify
2. Verificar en DevTools → Network → Response Headers que `Content-Security-Policy` está presente
3. Verificar que `X-Frame-Options: DENY` está presente
4. Verificar que no hay errores de CSP en la consola (todos los orígenes necesarios deberían estar permitidos)

### RLS Migration
```sql
-- Ejecutar en Admin DB (Supabase SQL Editor)
-- Verificar RLS habilitado:
SELECT tablename, rowsecurity FROM pg_tables 
WHERE tablename IN ('auth_bridge_codes', 'provisioning_job_steps');
-- Debe retornar: rowsecurity = true para ambas
```

## Notas de Seguridad
- La migración RLS debe ejecutarse manualmente en la Admin DB antes de que la protección esté activa
- El CSP del admin no incluye `'unsafe-eval'` (a diferencia del web storefront), lo cual es intencionalmente más restrictivo
- Los signed URLs de DNI expiran en 1 hora (3600 segundos)
- La backwards compatibility con legacy public URLs en DB se mantiene para registros existentes

## Hallazgos Pendientes (Phase 3)
- internal_key → httpOnly cookie (requiere investigación de cross-origin cookies)
- Web storefront CSP: remover `'unsafe-eval'` y `Access-Control-Allow-Origin: *`
- `SECURITY DEFINER` functions sin `SET search_path`
- `order_items` sin RLS

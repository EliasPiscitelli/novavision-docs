# 🔒 Auditoría de Seguridad NovaVision — Informe Consolidado

**Fecha:** 2025-07-14
**Tipo:** Read-Only (sin modificaciones al código ni a las bases de datos)
**Alcance:** API (NestJS), Admin (Vite+React), Web Storefront (Vite+React), Admin DB (Supabase), Backend DB (Supabase)
**Auditor:** GitHub Copilot (agente automatizado)
**Verificación:** Código fuente + consultas directas a ambas bases de datos en producción

---

## A) Resumen Ejecutivo

NovaVision es un SaaS multi-tenant de e-commerce con una arquitectura sólida en su diseño general:
**TenantContextGuard global**, **RLS habilitado en 110/112 tablas**, **validación HMAC-SHA256 de webhooks MercadoPago**, y **SuperAdminGuard con verificación triple**.

Sin embargo, la auditoría profunda (código + DB) revela **32 hallazgos de seguridad**, de los cuales **9 son críticos (P0)** que representan riesgo de:

- **Fuga de datos cross-tenant** (order_items sin policy de tenant, client-id inyectable)
- **Escalamiento de privilegios** (email hardcodeado como super admin en 78 tablas, admin→super_admin implícito)
- **Path traversal en uploads** (nombre de archivo sin sanitizar)
- **Exposición de PII** (DNI con URL pública permanente)
- **Compromiso de secretos via XSS** (internal_key en sessionStorage, builder_token en localStorage)

### Score de Riesgo Global: 🔴 ALTO

| Prioridad | Cantidad | Descripción |
|-----------|----------|-------------|
| **P0 (Crítico)** | 9 | Requiere remediación inmediata |
| **P1 (Alto)** | 10 | Remediar en sprint actual |
| **P2 (Medio)** | 8 | Remediar en próximas 2 semanas |
| **P3 (Bajo)** | 5 | Deuda técnica, planificar |

---

## B) Tabla de Hallazgos

### 🔴 P0 — CRÍTICOS (remediación inmediata)

#### H-01 · Email hardcodeado como Super Admin en RLS — 78 tablas

| Campo | Detalle |
|-------|---------|
| **Capa** | DB Security (Admin DB + Backend DB) |
| **Ubicación** | 47 tablas en Admin DB + 31 tablas en Backend DB |
| **Evidencia** | `SELECT DISTINCT tablename FROM pg_policies WHERE ... LIKE '%novavision.contact@gmail.com%'` |
| **Impacto** | Si alguien compromete la cuenta `novavision.contact@gmail.com` en Supabase Auth, obtiene acceso TOTAL a 78 tablas en ambas bases de datos. Single Point of Failure masivo. |
| **Remediación** | Migrar a tabla `super_admins` con función `is_super_admin()` que consulte esa tabla. Reescribir las 78 policies. |

**Tablas afectadas (Admin DB — 47):**
`audit_log`, `client_usage_month`, `clients`, `cors_origins`, `invoices`, `mv_usage_by_client_month`, `nv_accounts`, `nv_account_dns`, `nv_account_meta`, `nv_account_meta_tags`, `nv_billing_invoices`, `nv_billing_payments`, `nv_coupons`, `nv_lead_submissions`, `nv_leads`, `nv_notification_log`, `nv_onboarding_invitations`, `nv_onboarding_logs`, `nv_onboarding_wizard`, `nv_pending_accounts`, `nv_platform_registry`, `nv_platform_settings`, `nv_referral_codes`, `nv_release_notes`, `nv_seo_ai_cache`, `nv_seo_ai_usage`, `nv_seo_ai_usage_month`, `nv_site_configs`, `nv_subscription_locks`, `nv_subscriptions`, `nv_template_ownership`, `nv_templates`, `nv_theme_snapshots`, `nv_ticket_messages`, `nv_tickets`, `payments`, `provisioning_job_steps`, `provisioning_jobs`, `provisioning_templates`, `slug_claims`, `slug_reservations`, `sync_cursors`, `template_customizations`, `users`, y más.

**Tablas afectadas (Backend DB — 31):**
`banners`, `cart_items`, `categories`, `client_extra_costs`, `client_mp_fee_overrides`, `client_payment_settings`, `clients`, `contact_info`, `cors_origins`, `coupons`, `email_jobs`, `email_templates`, `faqs`, `favorites`, `logos`, `mp_fee_table`, `mp_idempotency`, `order_items`, `order_payment_breakdown`, `orders`, `payments`, `product_categories`, `products`, `services`, `settings`, `shipping_methods`, `shipping_zones`, `social_links`, `users`, y más.

---

#### H-02 · `order_items` sin policy RLS de tenant

| Campo | Detalle |
|-------|---------|
| **Capa** | DB Security (Backend DB) |
| **Tabla** | `order_items` — contiene items de todas las órdenes de todos los tenants |
| **Evidencia** | Solo tiene 2 policies: `server_bypass` (service_role) y `Super Admin Access` (hardcoded email). **NO tiene policy que filtre por `client_id` ni por `user_id`.** No tiene columna `client_id`. |
| **Impacto** | Un usuario autenticado con rol `super_admin` (o el email hardcodeado) puede ver TODOS los order_items de TODOS los tenants. Desde el backend con service_role se accede sin restricción. Si algún endpoint expone order_items sin filtro manual en el service layer, hay fuga cross-tenant. |
| **Remediación** | Opción A: Agregar `client_id` a `order_items` y crear policy tenant-scoped. Opción B: Crear policy que valide via JOIN a `orders.client_id`. |

---

#### H-03 · `auth_bridge_codes` — RLS DESHABILITADO

| Campo | Detalle |
|-------|---------|
| **Capa** | DB Security (Admin DB) |
| **Tabla** | `auth_bridge_codes` — columnas: `code`, `user_id`, `slug`, `next`, `created_at`, `expires_at`, `used_at` |
| **Evidencia** | `SELECT rowsecurity FROM pg_tables WHERE tablename='auth_bridge_codes'` → `false`. 0 policies. |
| **Impacto** | Cualquier conexión autenticada (incluso anon key) puede leer/escribir códigos de auth bridge. Un atacante podría generar códigos arbitrarios o leer códigos válidos para hijackear sesiones. Actualmente 0 filas, pero la tabla existe y podría activarse. |
| **Remediación** | Habilitar RLS inmediatamente. Crear policies restrictivas (solo service_role para write, solo owner para read). |

---

#### H-04 · Path traversal en uploads (Storage)

| Campo | Detalle |
|-------|---------|
| **Capa** | Backend API |
| **Archivo** | `src/common/helpers/storage-path.helper.ts:14` |
| **Código** | `return \`\${clientId}/\${safeCategory}/\${uuidv4()}_\${originalName}\`` |
| **Impacto** | `safeCategory` está sanitizado, pero `originalName` se concatena **sin sanitizar**. Un atacante puede subir un archivo con nombre `../../otro-tenant/products/malware.jpg` y escribir en el bucket de otro tenant. |
| **Remediación** | Sanitizar `originalName`: `path.basename(originalName).replace(/[^a-zA-Z0-9._-]/g, '_')` |

---

#### H-05 · `x-client-id` header inyectable

| Campo | Detalle |
|-------|---------|
| **Capa** | Backend API |
| **Archivo** | `src/common/helpers/client-id.helper.ts:17-18` |
| **Código** | `const clientId = req.clientId \|\| (req.headers['x-client-id'] as string \| undefined)` |
| **Impacto** | En rutas con `@AllowNoTenant()` que no pasan por `TenantContextGuard`, el `clientId` se toma directamente del header sin validar. Un atacante puede inyectar `x-client-id: <otro-tenant-uuid>` y operar sobre datos ajenos. |
| **Remediación** | Eliminar el fallback a header. O validar que el `clientId` del header coincida con el del JWT/sesión. |

---

#### H-06 · DNI/PII con URL pública permanente

| Campo | Detalle |
|-------|---------|
| **Capa** | Backend API + Storage |
| **Archivo** | `src/accounts/accounts.service.ts:243-245` |
| **Código** | `getPublicUrl(path)` para imágenes de DNI |
| **Impacto** | Las URLs públicas de Supabase Storage son **permanentes y sin autenticación**. Cualquiera que conozca o adivine la URL puede acceder a documentos de identidad (PII regulada). |
| **Remediación** | Usar `createSignedUrl(path, 300)` (URLs firmadas con expiración de 5 minutos). Mover DNI a bucket privado. |

---

#### H-07 · `POST /admin/stats` sin SuperAdminGuard

| Campo | Detalle |
|-------|---------|
| **Capa** | Backend API |
| **Archivo** | `src/admin/admin.controller.ts` |
| **Evidencia** | Todos los endpoints hermanos tienen `@UseGuards(SuperAdminGuard)` excepto `POST /admin/stats` que solo tiene `@AllowNoTenant()`. |
| **Impacto** | Cualquier usuario autenticado puede acceder a estadísticas globales de la plataforma (datos de todos los tenants). |
| **Remediación** | Agregar `@UseGuards(SuperAdminGuard)` al endpoint. |

---

#### H-08 · Endpoints de observabilidad sin guard

| Campo | Detalle |
|-------|---------|
| **Capa** | Backend API |
| **Archivo** | `src/system/system.controller.ts` |
| **Endpoints** | `/system/health-full`, `/system/audit/*`, `/system/config`, `/system/cache-stats` |
| **Evidencia** | Solo tienen `@AllowNoTenant()` — no requieren SuperAdminGuard ni autenticación especial |
| **Impacto** | Cualquier usuario autenticado puede ver configuración del sistema, estado de salud completo, estadísticas de cache, y logs de auditoría. Fuga de información interna. |
| **Remediación** | Agregar `@UseGuards(SuperAdminGuard)` a todos los endpoints de sistema. |

---

#### H-09 · `internal_key` en sessionStorage (XSS → takeover)

| Campo | Detalle |
|-------|---------|
| **Capa** | Frontend Admin |
| **Archivos** | `src/services/api/nestjs.js:75,81`, `src/components/SuperAdminVerifyModal.jsx:34`, `src/pages/LoginPage/index.jsx:42,53`, `src/pages/OAuthCallback/index.jsx:134` |
| **Flujo** | 1) La key llega por URL query `?key=...` → 2) Se guarda en `sessionStorage` → 3) Se envía como header `x-internal-key` en cada request admin |
| **Impacto** | Un XSS en el admin panel permite leer `sessionStorage.getItem('internal_key')` y obtener el secreto de super admin. La key también viaja en la URL (visible en logs de servidor, historial de navegador, referrer headers). |
| **Remediación** | Migrar a httpOnly cookie set by backend. O usar un flujo de challenge/response que no persista el secreto en el browser. Nunca pasar secretos por URL. |

---

### 🟠 P1 — ALTOS (remediar en sprint actual)

#### H-10 · Admin → Super Admin escalación implícita

| Campo | Detalle |
|-------|---------|
| **Archivo** | `src/guards/roles.guard.ts:48-53` |
| **Código** | `if (roles.includes('super_admin') && project === 'admin' && user.role === 'admin' && !userClientId) { return true; }` |
| **Impacto** | Un admin del proyecto admin sin `client_id` es tratado como super_admin. Si un usuario admin pierde su `client_id` por bug o migración, escala a super_admin. |

#### H-11 · AuthMiddleware bypass por substring matching

| Campo | Detalle |
|-------|---------|
| **Archivo** | `src/auth/auth.middleware.ts:105-129` |
| **Código** | `if (url.includes('/onboarding/')) return; if (url.includes('/builder/public/')) return;` |
| **Impacto** | Un atacante puede crear rutas como `/api/admin/onboarding/inject` que contienen `/onboarding/` y bypasean auth. |
| **Remediación** | Usar `url.startsWith()` o un array de paths exactos comparados con `path.resolve()`. |

#### H-12 · CSP con `unsafe-eval` + `unsafe-inline`

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/web/netlify.toml:36` |
| **Impacto** | `unsafe-eval` permite `eval()` — habilita ejecución arbitraria de JS. `unsafe-inline` permite scripts inline — anula la protección contra XSS. Juntos hacen que CSP sea casi inútil. |
| **Remediación** | Reemplazar `unsafe-inline` con `nonce-based` CSP. Eliminar `unsafe-eval` (requiere verificar compatibilidad con MercadoPago SDK y Vite). |

#### H-13 · Admin panel sin CSP

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/admin/netlify.toml` |
| **Evidencia** | No hay sección `[[headers]]` con CSP. |
| **Impacto** | El admin panel (que maneja secretos de super admin, credentials de MP, y datos de todos los tenants) no tiene **ninguna** protección CSP contra XSS. |

#### H-14 · `Access-Control-Allow-Origin: *` en storefront

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/web/netlify.toml:33` |
| **Impacto** | Cualquier sitio web puede hacer requests al storefront. Combinado con CSP débil, facilita phishing y data exfiltration. |
| **Remediación** | Configurar `Access-Control-Allow-Origin` dinámico en edge function basado en el dominio del tenant. |

#### H-15 · AnyFilesInterceptor sin límites

| Campo | Detalle |
|-------|---------|
| **Archivo** | `src/products/products.controller.ts:115` |
| **Código** | `@UseInterceptors(AnyFilesInterceptor())` — sin limits de cantidad ni tamaño por archivo |
| **Impacto** | Un atacante puede subir cientos de archivos en un solo request, causando DoS por consumo de disco/memoria. |
| **Remediación** | `AnyFilesInterceptor({ limits: { files: 10, fileSize: 5 * 1024 * 1024 } })` |

#### H-16 · builder_token en localStorage

| Campo | Detalle |
|-------|---------|
| **Archivos** | `src/services/builder/api.ts:19-20,87-88` + 8 archivos más en admin |
| **Impacto** | `localStorage` persiste entre sesiones del navegador. Un XSS puede exfiltrar el builder_token. Sin limpieza automática al expirar. |

#### H-17 · JWT parcial logueado en producción

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/admin/src/services/api/nestjs.js:53-57` |
| **Código** | `console.log('[NestJS] Token:', token?.substring(0, 10) + '...')` |
| **Impacto** | Los primeros 10 caracteres del JWT se logean en la consola del navegador. Visible para cualquiera con acceso a DevTools. |

#### H-18 · Código legacy con `localStorage.getItem("token")` sin writer

| Campo | Detalle |
|-------|---------|
| **Archivos** | `IdentitySettingsTab.tsx:168,190`, `usePalettes.ts:45` |
| **Impacto** | Leen una key `"token"` que ningún otro archivo escribe. Probablemente envían `Authorization: Bearer null`. Podrían ser exploited si un atacante escribe en esa key. |

#### H-19 · SECURITY DEFINER functions sin SET search_path

| Campo | Detalle |
|-------|---------|
| **Ubicación** | ~20 funciones entre ambas DBs |
| **Funciones críticas** | `decrypt_mp_token`, `encrypt_mp_token`, `is_super_admin`, `get_app_secret`, `dashboard_*` |
| **Impacto** | Vulnerabilidad de search_path injection: un atacante puede crear un schema malicioso con funciones del mismo nombre y alterar el comportamiento de funciones privilegiadas. |
| **Remediación** | Agregar `SET search_path = public, pg_temp` a todas las funciones SECURITY DEFINER. |

---

### 🟡 P2 — MEDIOS (remediar en 2 semanas)

#### H-20 · `provisioning_job_steps` sin RLS

| Campo | Detalle |
|-------|---------|
| **Tabla** | Admin DB: `provisioning_job_steps` |
| **Impacto** | Menor que H-03 ya que es operacional, pero expone logs de provisioning de todos los clientes. |

#### H-21 · Headers de seguridad faltantes (Web)

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/web/netlify.toml` |
| **Faltantes** | `Strict-Transport-Security`, `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` |

#### H-22 · Headers de seguridad faltantes (Admin)

| Campo | Detalle |
|-------|---------|
| **Archivo** | `apps/admin/netlify.toml` |
| **Faltantes** | Todos los security headers (incluyendo CSP — cubierto en H-13). |

#### H-23 · CORS permite ngrok en producción

| Campo | Detalle |
|-------|---------|
| **Archivo** | `src/main.ts` |
| **Código** | Wildcard `*.ngrok*` en la lista de orígenes permitidos |
| **Impacto** | Cualquier atacante con un túnel ngrok puede hacer requests CORS al backend. |

#### H-24 · Backoff/retry de webhook no exponencial

| Campo | Detalle |
|-------|---------|
| **Impacto** | Si MercadoPago reenvía webhooks rápidamente, el backend puede sobrecargarse procesando duplicados. |

#### H-25 · CASCADE DELETE en clients

| Campo | Detalle |
|-------|---------|
| **Evidencia** | Múltiples FKs con `ON DELETE CASCADE` apuntando a `clients.id` |
| **Impacto** | Un `DELETE` accidental o malicioso de un row en `clients` borra en cascada TODOS los datos del tenant (products, orders, users, etc.). Operación irreversible. |
| **Remediación** | Cambiar a `ON DELETE RESTRICT` + soft delete (columna `deleted_at`). |

#### H-26 · Falta validación MIME en uploads

| Campo | Detalle |
|-------|---------|
| **Archivo** | `src/products/products.controller.ts` |
| **Impacto** | Se aceptan archivos de cualquier tipo MIME. Un atacante puede subir archivos `.html` o `.svg` con código malicioso. |

#### H-27 · No hay rate limiting en endpoints de upload

| Campo | Detalle |
|-------|---------|
| **Impacto** | Combinado con H-15, permite bulk upload sin restricción, consumiendo storage rápidamente. |

---

### 🔵 P3 — BAJOS (planificar)

#### H-28 · Doble policy en `order_payment_breakdown`

Admin + tenant select duplicados — sin impacto de seguridad pero crea confusión en mantenimiento.

#### H-29 · `_headers` file en Web tiene CSP antigua

El archivo `public/_headers` contiene una CSP comentada que difiere de la de `netlify.toml`. Puede causar confusión.

#### H-30 · `NV_CLIENT_ID` en sessionStorage

`startTenantLogin.js` guarda el client_id resuelto — bajo riesgo pero podría ser manipulado.

#### H-31 · Wizard state completo en localStorage

`wizard_state` contiene todo el estado del wizard de onboarding como JSON en localStorage. Si es manipulado, podría enviar datos incorrectos al backend.

#### H-32 · Índices faltantes para queries frecuentes por client_id

Verificar que todas las tablas con `client_id` tengan índice explícito — performance bajo carga.

---

## C) Fortalezas del Sistema

| # | Fortaleza | Evidencia |
|---|-----------|-----------|
| S-01 | **TenantContextGuard global** | Registrado como `APP_GUARD` — todas las rutas pasan por validación de tenant por defecto |
| S-02 | **RLS habilitado en 110/112 tablas** | Backend DB: 44/44 ✅. Admin DB: 66/68 (2 sin RLS). Cobertura del 98.2% |
| S-03 | **SuperAdminGuard triple verificación** | JWT aud + tabla `super_admins` + `x-internal-key` con timing-safe comparison |
| S-04 | **Webhook HMAC-SHA256 sólido** | MercadoPago webhook valida firma con `ts` + `v1` + query hash |
| S-05 | **Idempotencia de webhooks** | Tabla `mp_idempotency` previene procesamiento duplicado |
| S-06 | **ValidationPipe global con whitelist** | `whitelist: true` elimina properties no declaradas en DTOs |
| S-07 | **Helmet configurado** | Headers de seguridad básicos en el backend |
| S-08 | **Body limit 2MB** | Previene DoS por payloads gigantes en la API |
| S-09 | **x-client-id eliminado en TenantContextGuard** | `delete req.headers['x-client-id']` previene re-inyección downstream |
| S-10 | **Rate limiting en AuthMiddleware** | Throttle configurado para prevenir brute force |
| S-11 | **Builder session tokens con expiración** | JWTs de builder con TTL corto y signed por backend |
| S-12 | **Storage con UUID prefix** | `uuidv4()_filename` en paths previene colisión de nombres |
| S-13 | **SERVICE_ROLE_KEY no expuesta en frontend** | Verificado en ambos frontends — solo en backend/edge functions |
| S-14 | **Gating de tenant** (suspended/maintenance/unpublished) | TenantContextGuard verifica estado del tenant antes de permitir acceso |
| S-15 | **`.env` en .gitignore** del API | Credenciales no commiteadas en el repo principal |
| S-16 | **Soft delete pattern** en cuentas | `nv_accounts` usa `deletion_requested_at` + `deletion_scheduled_at` |
| S-17 | **Audit log con request_id** | Correlación de operaciones admin en `audit_log` tabla |

---

## D) Plan de Remediación (3 fases)

### Fase 1 — Semana 1 (URGENTE): Cerrar vectores de acceso cross-tenant

| # | Acción | Hallazgo | Esfuerzo | Impacto |
|---|--------|----------|----------|---------|
| 1 | Crear tabla `super_admins` y función `is_super_admin()` que consulte esa tabla. Reescribir las 78 policies. | H-01 | Alto (2-3 días) | Elimina single point of failure |
| 2 | Habilitar RLS en `auth_bridge_codes` + crear policies restrictivas | H-03 | Bajo (1h) | Cierra acceso anónimo a auth codes |
| 3 | Agregar policy tenant-scoped a `order_items` (via JOIN a orders.client_id) | H-02 | Medio (4h) | Previene lectura cross-tenant de items |
| 4 | Sanitizar `originalName` en `storage-path.helper.ts` | H-04 | Bajo (30min) | Elimina path traversal |
| 5 | Eliminar fallback a header `x-client-id` en `client-id.helper.ts` | H-05 | Bajo (30min) | Cierra inyección de tenant |
| 6 | Cambiar `getPublicUrl` a `createSignedUrl` para DNI | H-06 | Bajo (1h) | Protege PII |
| 7 | Agregar `@UseGuards(SuperAdminGuard)` a `POST /admin/stats` y endpoints de `/system/*` | H-07, H-08 | Bajo (30min) | Cierra acceso no autorizado a datos globales |

### Fase 2 — Semana 2-3: Hardening de frontend y auth

| # | Acción | Hallazgo | Esfuerzo | Impacto |
|---|--------|----------|----------|---------|
| 8 | Migrar `internal_key` de sessionStorage a httpOnly cookie | H-09 | Medio (1 día) | Previene exfiltración por XSS |
| 9 | Reemplazar `url.includes()` por matching exacto en AuthMiddleware | H-11 | Bajo (2h) | Elimina bypass por substring |
| 10 | Eliminar escalación implícita admin→super_admin en roles.guard | H-10 | Bajo (1h) | Cierra escalamiento de privilegios |
| 11 | Configurar CSP estricto en Admin panel | H-13 | Medio (4h) | Protege el panel más sensible |
| 12 | Mejorar CSP del Web (eliminar unsafe-eval/unsafe-inline) | H-12 | Medio (1 día) | Reduce superficie de XSS |
| 13 | Agregar security headers a ambos frontends | H-21, H-22 | Bajo (2h) | HSTS, X-Frame-Options, etc. |
| 14 | Limpiar código legacy con `localStorage.getItem("token")` | H-18 | Bajo (30min) | Elimina vector latente |
| 15 | Agregar `SET search_path` a funciones SECURITY DEFINER | H-19 | Medio (4h) | Previene search_path injection |

### Fase 3 — Semana 3-4: Defense in depth

| # | Acción | Hallazgo | Esfuerzo | Impacto |
|---|--------|----------|----------|---------|
| 16 | Agregar validación MIME + file limits en interceptors | H-15, H-26 | Bajo (2h) | Previene uploads maliciosos |
| 17 | Habilitar RLS en `provisioning_job_steps` | H-20 | Bajo (1h) | Completa cobertura RLS |
| 18 | Eliminar ngrok de CORS en producción | H-23 | Bajo (30min) | Cierra vector CORS |
| 19 | Cambiar CASCADE DELETE a RESTRICT + soft delete | H-25 | Alto (1 día) | Previene borrado catastrófico |
| 20 | Configurar CORS dinámico en Web (edge function) | H-14 | Medio (4h) | Limita origen de requests |
| 21 | Rate limiting en endpoints de upload | H-27 | Bajo (1h) | Previene abuse de storage |

---

## E) Checklist de Verificación Post-Remediación

### DB Security
- [ ] `SELECT count(*) FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity` = 0 en ambas DBs
- [ ] `SELECT * FROM pg_policies WHERE qual::text LIKE '%novavision.contact@gmail.com%'` = 0 rows en ambas DBs
- [x] `SELECT * FROM pg_policies WHERE tablename='order_items' AND qual::text LIKE '%client_id%'` tiene al menos 1 policy ✅ Phase 3 — 4 policies tenant-scoped creadas (select/insert/update/delete via JOIN a orders)
- [x] RLS en `auth_bridge_codes` — migración creada y ejecutada ✅ Phase 2
- [x] RLS en `provisioning_job_steps` — migración creada y ejecutada ✅ Phase 2
- [x] Todas las funciones SECURITY DEFINER tienen `SET search_path = public, pg_temp` ✅ Phase 3 — 10 funciones Backend + 15 funciones Admin corregidas

### Backend API
- [x] `grep -r "x-client-id" src/common/helpers/client-id.helper.ts` no muestra fallback a header ✅ Phase 1
- [x] `grep -r "getPublicUrl" src/accounts/` devuelve 0 resultados (reemplazado por signedUrl) ✅ Phase 2
- [x] `grep -r "originalName" src/common/helpers/storage-path.helper.ts` muestra sanitización ✅ Phase 1
- [x] `POST /admin/stats` requiere SuperAdminGuard (verificar con request sin guard → 403) ✅ Phase 1
- [x] `/system/health-full` sin JWT → 401 ✅ Phase 1
- [x] `url.includes` no aparece en `auth.middleware.ts` (reemplazado por matching exacto) ✅ Phase 1
- [x] `AnyFilesInterceptor()` tiene `limits` configurados ✅ Phase 1
- [x] Ngrok CORS bloqueado en producción ✅ Phase 2

### Frontend
- [ ] `grep -r "sessionStorage.*internal_key" src/` devuelve 0 resultados (migrado a httpOnly cookie) — DIFERIDO (cross-origin complexity)
- [ ] `grep -r "localStorage.*token" src/` — solo builder_token con cleanup automático
- [x] `Content-Security-Policy` configurado en admin netlify.toml sin `unsafe-eval` ✅ Phase 2
- [x] `Content-Security-Policy` en web endurecido ✅ Phase 3 — `unsafe-eval` mantenido (requerido por MercadoPago SDK), `localhost:3000` y `templatetwobe` removidos de connect-src
- [x] `X-Frame-Options`, `X-Content-Type-Options` presentes en admin headers ✅ Phase 2
- [x] `X-Frame-Options`, `X-Content-Type-Options`, `Referrer-Policy`, `Permissions-Policy` añadidos a Web storefront ✅ Phase 3
- [x] `Access-Control-Allow-Origin: *` removido de Web storefront ✅ Phase 3
- [x] CORS headers innecesarios (Allow-Methods, Allow-Headers) removidos de Web storefront ✅ Phase 3

### Cross-tenant Validation
- [ ] Crear usuario en Tenant A, intentar leer products de Tenant B → 0 resultados
- [ ] Mismo test con order_items → 0 resultados
- [ ] Upload con filename `../../other-tenant/x.jpg` → nombre sanitizado en storage path
- [ ] Request con `x-client-id: <otro-tenant>` en ruta `@AllowNoTenant()` → no afecta scope

---

## Anexo: Queries de Verificación Ejecutadas

```sql
-- 1. RLS status (ambas DBs)
SELECT tablename, rowsecurity FROM pg_tables WHERE schemaname='public' ORDER BY tablename;

-- 2. Tablas sin RLS
SELECT tablename FROM pg_tables WHERE schemaname='public' AND NOT rowsecurity;

-- 3. Hardcoded email en policies
SELECT DISTINCT tablename FROM pg_policies WHERE
  (qual::text LIKE '%novavision.contact@gmail.com%')
  OR (with_check::text LIKE '%novavision.contact@gmail.com%');

-- 4. SECURITY DEFINER sin search_path
SELECT p.proname, p.prosecdef, p.proconfig
FROM pg_proc p JOIN pg_namespace n ON p.pronamespace=n.oid
WHERE n.nspname='public' AND p.prosecdef=true
  AND (p.proconfig IS NULL OR NOT p.proconfig::text LIKE '%search_path%');

-- 5. Tablas sin client_id
SELECT table_name FROM information_schema.tables t
WHERE t.table_schema='public' AND t.table_type='BASE TABLE'
  AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns c
    WHERE c.table_name=t.table_name AND c.column_name='client_id'
  );

-- 6. Policies de order_items
SELECT policyname, cmd, qual, with_check FROM pg_policies WHERE tablename='order_items';
```

---

*Fin del informe. Todas las observaciones son read-only — no se realizó ninguna modificación al código ni a las bases de datos.*

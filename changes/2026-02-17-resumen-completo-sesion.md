# Resumen completo de sesión — 2026-02-17

- **Autor:** agente-copilot
- **Fecha:** 2026-02-17
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding`
  - Admin: `feature/automatic-multiclient-onboarding`
  - Web: `feature/multitenant-storefront` (+ cherry-pick a `develop`)

---

## Trabajo realizado en esta sesión

### 1. Migración de dominio: `api.novavision.lat`

**Objetivo:** Reemplazar la URL interna de Railway (`novavision-production.up.railway.app`) por un subdominio propio `api.novavision.lat`.

**Archivos modificados:**

| Repo | Archivo | Cambio |
|------|---------|--------|
| API | `src/main.ts` | CSP `connectSrc` fallback → `api.novavision.lat` |
| API | `src/auth/auth.controller.ts` | Nuevos endpoints verify/revoke cookie + lectura cookie en Google OAuth |
| API | `src/guards/super-admin.guard.ts` | Lectura de cookie `nv_ik` (fallback a header) |
| Admin | `src/services/api/nestjs.js` | `PROD_URL` → `api.novavision.lat`, `withCredentials: true` |
| Admin | `src/pages/LoginPage/index.jsx` | httpOnly cookie reemplaza sessionStorage |
| Admin | `src/components/SuperAdminVerifyModal.jsx` | Validación via API + cookie |
| Admin | `src/pages/BuilderWizard/steps/Step7MercadoPago.tsx` | URL fallback actualizada |
| Admin | `src/pages/OAuthCallback/index.jsx` | `credentials: 'include'`, removido internal_key del body |
| Admin | `netlify.toml` | CSP `connect-src` actualizada |
| Web | `src/api/client.ts` | URL fallback actualizada |
| Web | `netlify.toml` | CSP `connect-src` actualizada |

**Commits:**
- API: `32968c8` — `feat(api): migrate to api.novavision.lat + httpOnly cookie for internal_key`
- Admin: `d6394f9` — `feat(admin): migrate to api.novavision.lat + httpOnly cookie for internal_key`
- Web: `831321a` (multitenant) + `45c93bd` (develop cherry-pick) — `feat(web): migrate API URL to api.novavision.lat`

---

### 2. httpOnly Cookie para `internal_key` (H-09 completado)

**Objetivo:** Mover el `internal_key` de super admin de sessionStorage (accesible por XSS) a una cookie httpOnly.

**Implementación:**
- **Cookie:** `nv_ik` con `httpOnly: true`, `secure: true` (prod), `sameSite: 'none'` (prod), `domain: .novavision.lat`, `maxAge: 24h`
- **Nuevos endpoints API:**
  - `POST /auth/internal-key/verify` — valida key, setea cookie
  - `POST /auth/internal-key/revoke` — limpia cookie
- **Guard actualizado:** `SuperAdminGuard` lee `request.cookies['nv_ik']` primero, fallback a header `x-internal-key`
- **Frontend:** Ya no almacena el secreto; guarda flag `internal_key_set` en sessionStorage

---

### 3. Sistema de Tickets de Soporte (nuevo módulo)

**Objetivo:** Implementar un sistema completo de tickets de soporte para clientes Growth/Enterprise.

#### API (Backend) — Archivos nuevos

| Archivo | Propósito |
|---------|-----------|
| `src/support/support.module.ts` | Módulo NestJS principal |
| `src/support/support.controller.ts` | CRUD tickets (tenant admin) |
| `src/support/support-admin.controller.ts` | Gestión tickets (super admin) |
| `src/support/support.service.ts` | Lógica de negocio: CRUD, mensajes, estado |
| `src/support/support-sla.service.ts` | SLA automático según plan (Growth: 48h, Enterprise: 24h) |
| `src/support/support-notification.service.ts` | Notificaciones por email (Postmark) |
| `src/support/types/ticket.types.ts` | Tipos TypeScript (estados, prioridades, SLA) |
| `src/support/types/index.ts` | Barrel export |
| `src/support/dto/*.ts` | 5 DTOs (create, update, close, message, filters) |
| `src/cron/support-sla.cron.ts` | Cron job para escalamiento SLA (cada 15 min) |
| `src/cron/__tests__/support-sla.cron.spec.ts` | Test del cron |
| `src/support/__tests__/support.service.spec.ts` | Test del servicio principal |
| `src/support/__tests__/support-sla.service.spec.ts` | Test del servicio SLA |
| `src/support/__tests__/support-notification.service.spec.ts` | Test de notificaciones |
| `migrations/admin/20260216_support_tickets.sql` | Migración SQL (tablas + RLS + índices) |

#### API — Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `src/cron/cron.module.ts` | Agregado `SupportModule` + `SupportSlaCron` |
| `src/plans/featureCatalog.ts` | Categoría `support` + feature `support.tickets` |

#### Admin — Archivos nuevos/modificados

| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/SupportConsoleView.jsx` | **Nuevo** (1066 líneas): Consola super admin para gestionar todos los tickets |
| `src/App.jsx` | Ruta `/admin/soporte` → `SupportConsoleView` |
| `src/pages/AdminDashboard/index.jsx` | Sidebar link a soporte |

#### Web (Storefront) — Archivos nuevos/modificados

| Archivo | Cambio |
|---------|--------|
| `src/components/admin/SupportTickets/index.jsx` | **Nuevo**: Dashboard de tickets para tenant admin |
| `src/components/admin/SupportTickets/style.jsx` | **Nuevo**: Estilos styled-components |
| `src/pages/AdminDashboard/index.jsx` | Sección `supportTickets` en dashboard del tenant |

#### Tablas SQL creadas (Admin DB)

- `support_tickets` — Ticket principal (client_id, subject, status, priority, sla_*, assigned_to)
- `support_messages` — Mensajes del hilo (sender_type: client/admin/system)
- `support_attachments` — Adjuntos por mensaje (file_url, file_name, file_size)

**Características:**
- SLA automático según plan: Growth (48h respuesta, 72h resolución), Enterprise (24h/48h)
- Escalamiento por cron cada 15 min cuando se incumple SLA
- Estados: `open → in_progress → waiting_client → resolved → closed`
- Prioridades: `low, medium, high, urgent`
- Categorías: `billing, technical, feature_request, account, other`
- RLS por client_id
- Feature-gated: solo Growth y Enterprise

---

### 4. Auditoría de variables de entorno Netlify

**Análisis realizado:**

#### Multicliente (storefront)
- **Borrar:** `VITE_AUTH_HUB_URL` (muerta), `VITE_USE_HOME_MOCK` (muerta)
- **Actualizar:** `VITE_BACKEND_URL` → `https://api.novavision.lat`

#### Onboarding
- **Borrar:** `VITE_ALLOWED_PREVIEW_ORIGINS` (muerta), `VITE_PREVIEW_TOKEN` (solo Admin la usa)
- **Actualizar:** `VITE_API_URL` → `https://api.novavision.lat`

#### Admin (novavision.lat)
- **Borrar:** `VITE_ACCESS_KEY` (muerta)
- **Actualizar:** `VITE_BACKEND_API_URL` → `https://api.novavision.lat`

---

## Pasos manuales pendientes (usuario)

### Railway
1. **Corregir puerto:** `api.novavision.lat` target port de 8070 → 3000
2. **Env vars:**
   - `BACKEND_URL=https://api.novavision.lat`
   - `PUBLIC_BASE_URL=https://api.novavision.lat`
   - `MP_REDIRECT_URI=https://api.novavision.lat/mp/oauth/callback`

### Netlify
3. **Actualizar env vars:**
   - Multicliente: `VITE_BACKEND_URL=https://api.novavision.lat`
   - Onboarding: `VITE_API_URL=https://api.novavision.lat`
   - Admin: `VITE_BACKEND_API_URL=https://api.novavision.lat`
4. **Limpiar env vars muertas** (ver sección 4 arriba)

### Supabase (Admin DB)
5. **Ejecutar migración:** `migrations/admin/20260216_support_tickets.sql`

---

## Validaciones ejecutadas

| Repo | Lint | Typecheck | Build |
|------|------|-----------|-------|
| API | ✅ 0 errors (1112 warnings) | ✅ Clean | ✅ OK |
| Admin | ✅ 0 errors, 0 warnings | ✅ Clean | ✅ 4.22s |
| Web | ✅ 0 errors (28 warnings) | ✅ Clean | ✅ 6.88s |

---

## Commits de esta sesión (cronológico)

| Repo | Hash | Mensaje | Ramas |
|------|------|---------|-------|
| API | `32968c8` | feat(api): migrate to api.novavision.lat + httpOnly cookie | `feature/automatic-multiclient-onboarding` |
| Admin | `d6394f9` | feat(admin): migrate to api.novavision.lat + httpOnly cookie | `feature/automatic-multiclient-onboarding` |
| Web | `831321a` | feat(web): migrate API URL to api.novavision.lat | `feature/multitenant-storefront` |
| Web | `45c93bd` | feat(web): migrate API URL to api.novavision.lat | `develop` (cherry-pick) |
| Docs | `aa08020` | docs: changelog migración api.novavision.lat + httpOnly cookie | `main` |
| API | pendiente | feat(api): add support ticket system | `feature/automatic-multiclient-onboarding` |
| Admin | pendiente | feat(admin): add support console view | `feature/automatic-multiclient-onboarding` |
| Web | pendiente | feat(web): add support tickets dashboard | `feature/multitenant-storefront` + `develop` |

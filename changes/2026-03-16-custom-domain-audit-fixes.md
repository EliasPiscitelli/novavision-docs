# Custom Domain System — Audit Fixes (Fase 0 + Fase 1 + Fase 2)

**Fecha:** 2026-03-16
**Rama:** develop
**Alcance:** Web (storefront), API, Admin
**Auditoría completa:** `audits/2026-03-16-custom-domain-system-audit.md`

---

## Resumen

Implementación de fixes identificados en la auditoría completa del sistema de custom domain. Cubre los 3 P0 de Fase 0, los items de Fase 1 (removeCustomDomain, sync bidireccional, Netlify alias management) y los 4 items P2 de Fase 2.

---

## Cambios implementados — Fase 0 (P0)

### P0-1: Fix bug `www.mitienda.com` no resuelve (Web)

**Archivo:** `apps/web/src/utils/tenantResolver.js`

- Movido `isLikelyCustomDomain()` check **antes** del subdomain parsing
- Antes: `www.mitienda.com` → extraía `'www'` como slug → STORE_NOT_FOUND
- Después: `www.mitienda.com` → detecta custom domain → retorna `null` → resolución async via TenantProvider

**Test:** `apps/web/src/__tests__/tenant-resolver.test.js` (nuevo, 15 tests)
- Valida platform subdomains, custom domains (root y www), dev overrides, edge cases

### P0-3 (parcial): Fix inversión www/root en Netlify (API)

**Archivo:** `apps/api/src/admin/admin.service.ts` (método `setCustomDomain`)

- Antes: `customDomain: www.domain`, `domainAliases: [domain]`
- Después: `customDomain: domain`, `domainAliases: [www.domain]`
- Netlify espera el apex como `custom_domain` canónico

---

## Cambios implementados — Fase 1

### `removeCustomDomain()` — endpoint completo (API + Admin)

**Archivos:**
- `apps/api/src/admin/admin.service.ts` — nuevo método `removeCustomDomain(accountId)`
- `apps/api/src/admin/admin.controller.ts` — nuevo endpoint `DELETE /admin/accounts/:id/custom-domain`
- `apps/admin/src/services/adminApi.js` — nuevo método `removeCustomDomain(accountId)`
- `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx` — handler + botón "Remover dominio"

### `removeSiteDomain()` y `getDomainAliasCount()` (API — Netlify)

**Archivo:** `apps/api/src/admin/netlify.service.ts`

### Check de capacidad antes de agregar alias (API)

**Archivo:** `apps/api/src/admin/admin.service.ts` (método `setCustomDomain`)
- Verifica `getDomainAliasCount() < 90` antes de agregar

### Sync bidireccional de `clients.custom_domain` (API)

**Archivo:** `apps/api/src/admin/admin.service.ts` (método `setCustomDomain`)
- Limpia dominio viejo en Backend DB + CORS origins al cambiar

### Color coding para domain status (Admin)

**Archivo:** `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx`
- Status chip con colores por estado (active → verde, pending_dns → amarillo, error → rojo)

---

## Cambios implementados — Fase 2 (P2)

### P2-1: Validación regex en Step9Summary (Admin — Onboarding)

**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step9Summary.tsx`

- Normalización en `onChange`: lowercase, strip protocol/path/port
- Validación regex antes de submit: `/^[a-z0-9.-]+\.[a-z]{2,}$/`
- Rechazo de dominios de plataforma (`*.novavision.lat`)
- Se envía el valor normalizado (sin `www.`) al backend

### P2-2: `PLATFORM_DOMAIN` constante (Web + API + Admin)

**Archivos nuevos:**
- `apps/web/src/config/platform.js` — `PLATFORM_DOMAIN` vía `VITE_PLATFORM_DOMAIN`
- `apps/admin/src/config/platform.ts` — `PLATFORM_DOMAIN` vía `VITE_PLATFORM_DOMAIN`

**Archivos API migrados (5):**
- `apps/api/src/common/email/email-branding.constants.ts` — nueva constante `PLATFORM_DOMAIN` + derivados
- `apps/api/src/admin/admin.service.ts` — importa y usa en `ensureCustomDomainFormat`, `approveClient`
- `apps/api/src/onboarding/onboarding.service.ts` — importa y usa en `ensureCustomDomainFormat`
- `apps/api/src/guards/tenant-context.guard.ts` — importa y usa en custom domain detection
- `apps/api/src/auth/auth.controller.ts` — importa y usa en cookie domain

**Archivos Web migrados (3):**
- `apps/web/src/utils/tenantResolver.js` — importa `PLATFORM_DOMAIN` para `isLikelyCustomDomain`
- `apps/web/src/api/client.ts` — reemplaza `BASE_DOMAIN` local y API fallback
- `apps/web/src/__tests__/tenant-resolver.test.js` — importa constante

**Archivos Admin migrados (2):**
- `apps/admin/src/pages/BuilderWizard/steps/Step9Summary.tsx` — usa `PLATFORM_DOMAIN` en slug preview + validación
- `apps/admin/src/pages/BuilderWizard/steps/Step10Summary.tsx` — usa `PLATFORM_DOMAIN` en slug preview

### P2-3: Domain request visible en PendingApprovalsView (API + Admin)

**API:** `apps/api/src/admin/admin.service.ts`
- `getPendingApprovals()`: agregado `custom_domain, custom_domain_mode` al SELECT

**Admin:** `apps/admin/src/pages/AdminDashboard/PendingApprovalsView.tsx`
- Interfaz `Store`: campos `custom_domain?`, `custom_domain_mode?`
- Grid actualizado a 7 columnas: `2fr 1.5fr 1fr 1fr 1fr 1fr auto`
- Nueva columna "Dominio" con texto del dominio o "—"
- Filtro de búsqueda incluye `custom_domain`

### P2-4: CNAME target dinámico en instrucciones DNS (API + Admin)

**API:** `apps/api/src/admin/admin.service.ts`
- `getAccountDetails()`: nuevo campo `netlify_default_domain` en response (vía env var `NETLIFY_DEFAULT_DOMAIN`)

**Admin:** `apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx`
- Reemplazado `tu-sitio.netlify.app` por `data?.netlify_default_domain` con fallback `(tu-sitio).netlify.app`
- 3 ocurrencias actualizadas (concierge, self-service, paso a paso Namecheap)

---

## Validación

- 15 tests para `tenantResolver.js` (Vitest): passing
- Tests unitarios del repo web: passing
- Build Admin: passing
- Build Web: passing

---

## Pendientes (Fase 3-4)

- [ ] Audit trail para cambios de dominio
- [ ] Centro de Dominio para tenant admin (Fase 3)
- [ ] Observabilidad: métricas del cron de verificación (Fase 4)
- [ ] Documentos de portabilidad: ENV_INVENTORY.md, ROUTING_RULES.md, CUSTOM_DOMAIN_CHECKLIST.md

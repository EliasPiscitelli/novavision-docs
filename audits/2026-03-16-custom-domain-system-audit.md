# Auditoría Completa: Sistema de Custom Domain / URL Personalizada

**Fecha:** 2026-03-16
**Auditor:** Principal Architect + Multi-tenant Platform Auditor + Staff QA
**Alcance:** End-to-end — Onboarding → Admin Dashboard → API → DB → Web Storefront → Edge Functions → Infra
**Repos auditados:** API, Admin, Web, Docs, E2E

---

## 1. Resumen Ejecutivo

### Estado general: FUNCIONAL con bugs críticos y deuda técnica significativa

El sistema de custom domain de NovaVision es **operacionalmente funcional** para el flujo principal (subdomain `*.novavision.lat`), con soporte parcial para dominios personalizados. La arquitectura dual-DB (Admin DB + Backend DB) con sincronización eventual es sólida conceptualmente pero tiene **gaps de consistencia** que pueden causar estados huérfanos.

### Hallazgos por severidad

| Severidad | Cantidad | Descripción |
|-----------|----------|-------------|
| **P0 — Crítico** | 5 | Bug `www.*` custom domain, hardcoding `novavision.lat`, sin remoción de dominio, www/root invertidos en Netlify, límite ~100 aliases sin enforcement |
| **P1 — Importante** | 7 | Sin panel tenant, `base_url` stale, sin audit trail, CORS stale, status sin labels, DNS instructions con CNAME genérico, `handleSaveCustomDomain` sin refresh |
| **P2 — Mejora** | 6 | Cookie domain, PendingApprovals sin dominio, concierge expiry sin acción, race conditions, UX labels, JsonLd baseUrl |

### Fortalezas detectadas

- Resolución de tenant **stateless** (header-based) — escalable y cacheable
- Doble verificación DNS (root + www) vía Netlify API
- Slug **inmutable** post-publicación (trigger DB `ADMIN_060`)
- Reserva de slug con TTL de 30 min contra race conditions
- Cross-tenant blocking en axios interceptor (seguridad sólida)
- Custom domain solo para Growth+ (plan gating correcto)
- Normalización robusta de dominios (strip protocol, www, port, trailing dots)
- Edge functions pasan `x-forwarded-host` correctamente

---

## 2. Mapa de Flujo End-to-End

### 2.1 Flujo de creación de slug (Onboarding)

```
[Usuario en Admin]
       │
       ▼
Step1Slug.tsx ──────────────────────────────────────────────────────────
│ Input: slug (regex /^[a-z0-9-]+$/)                                  │
│ Sanitización on-change: .toLowerCase().replace(/[^a-z0-9-]/g, '')   │
│ Sufijo visual: .novavision.lat (hardcoded)                          │
│ POST /onboarding/builder/start { email, slug }                      │
└─────────────────────────┬─────────────────────────────────────────────
                          ▼
              API: OnboardingService.startBuilder()
                          │
                          ├─ Valida formato slug
                          ├─ Verifica unicidad en nv_accounts.slug
                          ├─ Verifica unicidad en slug_reservations
                          ├─ INSERT slug_reservations (TTL 30 min)
                          ├─ INSERT/UPDATE nv_accounts (slug, email, status='draft')
                          └─ Retorna { account_id, builder_token }
                          │
                          ▼
              WizardContext.tsx almacena:
              { slug, email, accountId, builderToken }
              Persiste en localStorage('wizard_state')
```

### 2.2 Flujo de custom domain (Onboarding Step 9 — solo Growth)

```
[Step9Summary.tsx — Solo si plan === 'growth']
       │
       ├─ Checkbox: "Ya tengo dominio propio"
       ├─ Input: dominio (placeholder: tu-marca.com)
       ├─ Select: mode (self_service | concierge)
       ├─ Si self_service: registrar, dnsProvider, dnsContactEmail, nameservers, usesCdn, notes
       │
       ▼
PATCH /onboarding/custom-domain
Headers: { X-Builder-Token }
Body: { domain, mode, details }
       │
       ▼
API: Almacena en nv_onboarding.builder_payload.custom_domain_request
(NO ejecuta setCustomDomain() aquí — solo registra la intención)
```

### 2.3 Flujo de publicación (Provisioning)

```
[Super Admin aprueba tienda]
       │
       ▼
AdminService.approveClient(accountId)
       │
       ├─ Cross-DB Saga:
       │   ├─ Backend DB: INSERT clients {
       │   │     slug: finalSlug,
       │   │     base_url: "https://{slug}.novavision.lat",  ← HARDCODED
       │   │     custom_domain: NULL,  ← NO se copia del onboarding
       │   │     publication_status: 'draft' → 'published'
       │   │   }
       │   └─ Admin DB: UPDATE nv_accounts SET status='approved'
       │       (con compensación si falla)
       │
       └─ Slug consumido de slug_reservations (claim_slug_final RPC)
```

### 2.4 Flujo de asignación de custom domain (Post-publicación)

```
[Super Admin en ClientApprovalDetail.jsx → Tab "Dominio"]
       │
       ├─ Input: dominio
       ├─ Select: mode (self_service | concierge)
       │
       ▼
POST /admin/accounts/:id/custom-domain { domain, mode }
       │
       ▼
AdminService.setCustomDomain(accountId, domain, mode)
       │
       ├─ 1. Normaliza: lowercase, strip protocol/www/port/trailing dots
       ├─ 2. Valida formato: /^[a-z0-9.-]+\.[a-z]{2,}$/
       ├─ 3. Rechaza *.novavision.lat
       ├─ 4. Verifica plan elegible: growth|enterprise|scale|pro
       ├─ 5. Colisión Admin DB: nv_accounts WHERE custom_domain ILIKE domain
       ├─ 6. Colisión Backend DB: clients WHERE custom_domain = domain
       ├─ 7. Netlify: PATCH /sites/{id} { custom_domain: www.domain, aliases: [domain], force_ssl: true }
       ├─ 8. UPDATE nv_accounts SET custom_domain=domain, status='pending_dns', mode, timestamps
       └─ Retorna: { domain, status: 'pending_dns'|'error', mode }
       │
       │  ⚠️ NO actualiza clients.custom_domain aquí
       │  ⚠️ NO actualiza clients.base_url aquí
       │
       ▼
[DNS Propagation — Usuario configura CNAME/A records]
       │
       ▼
Verificación DNS (3 triggers):
  ├─ Manual: POST /admin/accounts/:id/custom-domain/verify
  ├─ Cron cada 10 min: CustomDomainVerifierCron (hasta 100 cuentas pending_dns|error)
  └─ Cron cada 6h: ManagedDomainCron.handlePendingDnsCheck()
       │
       ▼
AdminService.verifyCustomDomain(accountId)
       │
       ├─ Netlify API: resolveDomainStatus(siteId, domain) × 2 (root + www)
       ├─ Si rootActive || wwwActive → status = 'active'
       ├─ UPDATE nv_accounts SET custom_domain_status, verified_at, last_checked_at
       │
       └─ SI status === 'active':
           ├─ UPDATE clients SET custom_domain = domain  ← SINCRONIZACIÓN A BACKEND DB
           ├─ UPSERT cors_origins: https://domain + https://www.domain
           └─ A partir de aquí: SEO, sitemap, OG usan custom domain como canónico
```

### 2.5 Flujo de resolución en runtime (Web Storefront)

```
[Browser navega a slug.novavision.lat o mitienda.com]
       │
       ▼
tenantResolver.js → getStoreSlugFromHost(hostname)
       │
       ├─ Prioridad 1: ?tenant= o ?slug= (query param, dev)
       ├─ Prioridad 2: VITE_DEV_SLUG (localhost/127.0.0.1/ngrok)
       ├─ Prioridad 3: hostname.split('.')[0] si parts >= 3  ← SUBDOMAIN
       ├─ Prioridad 4: return null  ← CUSTOM DOMAIN (2 partes)
       │
       ▼
tenantScope.js → getTenantSlug()
       │  Cachea en window.__NV_TENANT_SLUG__
       │  Fallback: 'unknown'
       │
       ▼
TenantProvider.jsx
       │
       ├─ Si slug válido (no 'unknown'/'server'):
       │   ├─ Set header x-tenant-slug
       │   └─ GET /tenant/bootstrap → tenant data
       │
       ├─ Si slug inválido + isLikelyCustomDomain(hostname):
       │   ├─ GET /tenant/resolve-host?domain=hostname (sin x-tenant-slug)
       │   ├─ API: TenantService.resolveHostToSlug(domain)
       │   │   └─ nv_accounts WHERE custom_domain IN [domain, www.domain]
       │   │     AND custom_domain_status = 'active'
       │   ├─ Si resuelve: slug = response.slug, cachea en window.__NV_TENANT_SLUG__
       │   └─ GET /tenant/bootstrap con slug resuelto
       │
       └─ Si falla todo: error "Tienda No Encontrada"
       │
       ▼
API: TenantContextGuard (para /tenant/bootstrap y todas las requests)
       │
       ├─ Prioridad 1: x-tenant-slug header → nv_accounts.slug lookup
       ├─ Prioridad 2: Host no-novavision.lat → nv_accounts.custom_domain lookup (status='active')
       ├─ Prioridad 3: Subdominio de Host → extract slug (reserved: admin,api,app,www,build,novavision,localhost)
       ├─ Prioridad 4: @AllowNoTenant() → continúa sin tenant
       │
       └─ gateStorefront(): deleted_at? → suspended? → maintenance? → published?
```

---

## 3. Matriz Maestra de Dominio/URL

| Concepto | Pantalla/Componente | Campo UI | Endpoint API | Servicio | Tabla.Columna | Validación | Consumidor |
|----------|-------------------|----------|--------------|----------|---------------|------------|------------|
| **Slug** | Step1Slug.tsx | Input + sufijo `.novavision.lat` | POST /onboarding/builder/start | OnboardingService | `nv_accounts.slug` (UNIQUE) | `/^[a-z0-9-]+$/`, sanitize on-change | TenantContextGuard, provisioning, URLs |
| **Slug reserva** | Step1Slug.tsx (interno) | — | POST /onboarding/builder/start | OnboardingService | `slug_reservations.slug` (PK) | TTL 30 min, unicidad | Anti-colisión race condition |
| **Slug inmutable** | — | — | Trigger DB | — | `nv_accounts.slug` | `trg_prevent_slug_change` (status ∈ approved,live,suspended) | Protección DNS, URLs, storage |
| **Base URL** | — (no editable) | — | PROVISION_CLIENT | ProvisioningWorker | `clients.base_url` | Hardcoded `https://{slug}.novavision.lat` | SEO fallback, OG tags |
| **Custom domain (request)** | Step9Summary.tsx | Input + mode select | PATCH /onboarding/custom-domain | OnboardingService | `nv_onboarding.builder_payload.custom_domain_request` | Non-empty (sin regex!) | Referencia para super admin |
| **Custom domain (set)** | ClientApprovalDetail.jsx (Domain tab) | Input + mode select | POST /admin/accounts/:id/custom-domain | AdminService.setCustomDomain | `nv_accounts.custom_domain` (UNIQUE citext) | `/^[a-z0-9.-]+\.[a-z]{2,}$/`, no `*.novavision.lat`, plan Growth+ | Netlify, DNS crons |
| **Custom domain (verified)** | ClientApprovalDetail.jsx (Domain tab) | Status badge | POST /admin/accounts/:id/custom-domain/verify | AdminService.verifyCustomDomain | `nv_accounts.custom_domain_status` | Netlify API root+www check | Sincroniza a `clients.custom_domain` |
| **Custom domain (runtime)** | — | — | GET /tenant/resolve-host | TenantService.resolveHostToSlug | `nv_accounts.custom_domain` WHERE status='active' | Max 253 chars, strip www | TenantProvider async resolution |
| **Custom domain (backend)** | — | — | — | verifyCustomDomain (sync) | `clients.custom_domain` (UNIQUE) | Solo se escribe cuando status='active' | SEO service, sitemap, OG, canonical |
| **Netlify site** | — | — | Netlify PATCH/GET | NetlifyService | `nv_accounts.netlify_site_id` | Fallback a env var | DNS verification, SSL |
| **CORS origins** | — | — | — | verifyCustomDomain (upsert) | `cors_origins.origin` | `https://domain` + `https://www.domain` | Seguridad cross-origin |
| **Managed domain** | ClientDomains component | Domain + expiry + renewal | POST /admin/domains/provision | ManagedDomainService | `managed_domains.domain` (UNIQUE citext) | Namecheap/manual | Renovación, billing |
| **SEO canonical** | SEOHead/index.jsx | `<link rel="canonical">` | — (client-side) | — | `window.location.origin` | Auto-resuelve según dominio accedido | Google, social sharing |
| **SEO sitemap** | — (edge/API) | — | GET /seo/sitemap | SeoService.generateSitemapXml | `clients.custom_domain` > `clients.base_url` > slug | Prioridad custom_domain | Motores de búsqueda |
| **SEO OG tags** | SEOHead, og-inject edge fn | `og:url` | GET /seo/og | SeoService.getOgData | `clients.custom_domain` > `clients.base_url` > slug | Prioridad custom_domain | Social sharing, bots |

---

## 4. Matriz de Impacto de Configuración de Tenant

| Configuración | Source of Truth | Tabla | ¿Usa dominio? | ¿Qué pasa si cambia el dominio? |
|--------------|-----------------|-------|---------------|--------------------------------|
| **Slug** | Onboarding Step 1 | `nv_accounts.slug` | Sí — construye `*.novavision.lat` | INMUTABLE post-publicación (trigger) |
| **Base URL** | Provisioning worker | `clients.base_url` | Sí — `https://{slug}.novavision.lat` | ⚠️ NUNCA se actualiza — queda stale |
| **Custom domain** | Super admin sets | `nv_accounts.custom_domain` | Sí — es el dominio | Se sobreescribe, viejo NO se limpia de `clients` hasta verify del nuevo |
| **Custom domain (backend)** | Sync on verify | `clients.custom_domain` | Sí — prioridad para SEO | Se sobreescribe cuando nuevo dominio verifica. ⚠️ Sin flujo de remoción |
| **CORS origins** | Sync on verify | `cors_origins` | Sí — `https://domain` | ⚠️ Viejas entradas NO se eliminan — acumulación |
| **Netlify domains** | setCustomDomain | Netlify API | Sí — aliases + custom_domain | Se agregan al sitio. ⚠️ Viejos NO se eliminan |
| **Cookie domain** | Hardcoded | `.novavision.lat` | No | ⚠️ Cookies no funcionan en custom domains — auth issues potenciales |
| **GA4/GTM/Pixel** | Admin config | `seo_settings` | No — IDs independientes | Sin impacto |
| **MP credentials** | Onboarding OAuth | `nv_accounts.mp_*` | No | Sin impacto |
| **SEO redirects** | Admin SEO panel | `seo_redirects` | Indirecto — `from_path` relativo | Sin impacto directo |
| **Template/Theme** | Admin config | `clients.template_id`, `theme_config` | No | Sin impacto |
| **Logo/Banners** | Admin config | `logos`, `banners` | No — URLs de storage | Sin impacto |
| **Social links** | Admin config | `social_links` | No | Sin impacto |

---

## 5. Matriz de Resolución en Runtime

### 5.1 Resolución en Web Storefront (client-side)

| Paso | Archivo | Input | Lookup | Fallback | Error |
|------|---------|-------|--------|----------|-------|
| 1. Query param | `tenantResolver.js:7-9` | `?tenant=` o `?slug=` | URL search params | Paso 2 | — |
| 2. Dev override | `tenantResolver.js:12-18` | `VITE_DEV_SLUG` | env var (solo localhost/127/ngrok) | Paso 3 | `null` |
| 3. Subdomain | `tenantResolver.js:24-29` | `hostname.split('.')` | Si parts ≥ 3 → `parts[0]` | Paso 4 | — |
| 4. Custom domain | `tenantResolver.js:32` | — | Retorna `null` (async) | — | `null` |
| 5. Cache global | `tenantScope.js` | `window.__NV_TENANT_SLUG__` | Memory cache | `'unknown'` | — |
| 6. Async resolve | `TenantProvider.jsx:81-110` | Si slug inválido + `isLikelyCustomDomain()` | `GET /tenant/resolve-host?domain=` | Error NO_SLUG | NO_SLUG |
| 7. Bootstrap | `TenantProvider.jsx:130-142` | `x-tenant-slug` header | `GET /tenant/bootstrap` | Error STORE_NOT_FOUND | STORE_NOT_FOUND / SUSPENDED / PENDING |

### 5.2 Resolución en API (TenantContextGuard)

| Paso | Archivo | Input | Lookup (tabla → campo) | Fallback | Error |
|------|---------|-------|----------------------|----------|-------|
| 1. Header slug | `tenant-context.guard.ts:143-190` | `x-tenant-slug` / `x-store-slug` | `nv_accounts.slug` → `clients.nv_account_id` | Paso 2 | `STORE_NOT_FOUND` si slug no existe |
| 2. ~~x-client-id~~ | `tenant-context.guard.ts:192-197` | ELIMINADO (P0 audit) | — | Paso 3 | — |
| 3. Custom domain | `tenant-context.guard.ts:203-257` | `x-forwarded-host` > `host` > `x-tenant-host` | `nv_accounts.custom_domain` IN [host, www.host] WHERE status='active' | Paso 4 | — |
| 4. Subdominio | `tenant-context.guard.ts:260-312` | `request.headers.host` | Extrae subdomain, verifica no-reservado (admin,api,app,www,build,...), lookup `nv_accounts.slug` | Paso 5 | `STORE_NOT_FOUND` |
| 5. ~~resolvedClientId~~ | `tenant-context.guard.ts:314-327` | ELIMINADO (P0 audit) | — | Paso 6 | — |
| 6. Sin tenant | `tenant-context.guard.ts:329-345` | — | `@AllowNoTenant()` decorator | — | `Se requiere client_id` |

### 5.3 Resolución en Edge Functions (Netlify)

| Edge Function | Path | Input | Lookup | Notas |
|--------------|------|-------|--------|-------|
| `og-inject.ts` | `/*` | `request.headers.get('host')` → `x-forwarded-host` | Backend: `GET /seo/og?path=` | Social bot detection (facebook, twitter, linkedin, etc.) |
| `seo-redirects.ts` | `/*` | `request.headers.get('host')` → `x-forwarded-host` | Backend: `GET /seo/redirects/resolve?path=` | 301/302 redirect |
| `seo-robots.ts` | `/robots.txt` | `request.headers.get('host')` → `x-forwarded-host` | Backend: `GET /seo/settings` | Custom robots.txt |
| `maintenance.ts` | `/*` | — | `BACKEND_HEALTH_URL` | 503 si backend caído |

### 5.4 Resolución SEO (API-side)

| Método | Prioridad 1 | Prioridad 2 | Prioridad 3 |
|--------|------------|------------|------------|
| `generateSitemapXml()` | `clients.custom_domain` → `https://{cd}` | `clients.base_url` (sin trailing /) | `clients.slug` → `https://{slug}.novavision.lat` |
| `getOgData()` | `clients.custom_domain` → `https://{cd}` | `clients.base_url` (sin trailing /) | `clients.slug` → `https://{slug}.novavision.lat` |
| SEOHead (frontend) | `window.location.origin` | — | — |

---

## 6. Inconsistencias y Bugs Detectados

### P0 — Críticos (bloquean funcionalidad o causan estados corruptos)

#### P0-1: Bug `www.custom-domain.com` no resuelve en Web Storefront

**Archivos:** `apps/web/src/utils/tenantResolver.js:24-29`, `apps/web/src/context/TenantProvider.jsx:81`

**Descripción:** Cuando un usuario accede a `www.mitienda.com`:
1. `getStoreSlugFromHost('www.mitienda.com')` → `hostname.split('.') = ['www','mitienda','com']` → `parts.length >= 3` → retorna `'www'`
2. `getTenantSlug()` → `'www'`
3. TenantProvider: `slug = 'www'`, no es `'unknown'`/`'server'`, **no entra en custom domain resolution**
4. Sets `x-tenant-slug: www`, llama `/tenant/bootstrap` → API retorna `STORE_NOT_FOUND`
5. Usuario ve **"Tienda No Encontrada"**

**Impacto:** Cualquier custom domain accedido con `www.` prefix no funciona. Esto es ~50% del tráfico típico.

**Root cause:** `getStoreSlugFromHost()` extrae subdomain sin verificar primero si el dominio es de la plataforma (`novavision.lat`/`netlify.app`) o un custom domain.

**Fix propuesto:**
```javascript
// En getStoreSlugFromHost(), ANTES del subdomain parsing:
if (isLikelyCustomDomain(hostname)) {
  return null; // Forzar resolución async via TenantProvider
}
```

**Severidad:** P0 — custom domains con `www` son inaccesibles.

---

#### P0-2: `novavision.lat` hardcoded en ~20 ubicaciones sin constante

**Archivos afectados (Admin):**
| Archivo | Líneas | Contexto |
|---------|--------|----------|
| `Step1Slug.tsx` | 276, 280 | Sufijo visual + hint |
| `Step9Summary.tsx` | 460 | Preview dominio |
| `Step10Summary.tsx` | 303 | Preview dominio |
| `Step11Success.tsx` | 90, 100, 125 | Next steps + soporte email |
| `Step12Success.tsx` | 90, 100, 125 | Next steps + soporte email |
| `OnboardingStatus.tsx` | 154, 166 | Timeline + info box |
| `ClientApprovalDetail.jsx` | 1510, 1568, 2963 | Approval dialog + header + hint |
| `ClientCompletionDashboard/index.tsx` | 434 | Bridge URL |
| `TermsConditions/index.jsx` | 103, 107, 144, 265, 269, 306 | Links legales |

**Archivos afectados (API):**
| Archivo | Contexto |
|---------|----------|
| `provisioning-worker.service.ts` | `base_url = https://{slug}.novavision.lat` |
| `admin.service.ts` | `ensureCustomDomainFormat()`: rechaza `*.novavision.lat` |
| `tenant-context.guard.ts` | Check `host.endsWith('novavision.lat')` |

**Archivos afectados (Web):**
| Archivo | Contexto |
|---------|----------|
| `tenantResolver.js` | `endsWith('novavision.lat')` |

**Impacto:** Si el dominio de la plataforma cambia (ej: migración a `novavision.com`, white-label), requiere cambios en ~20 archivos en 3 repos.

**Fix propuesto:** Constante `PLATFORM_DOMAIN` en env/config compartida, consumida por todos.

---

#### P0-3: Sin flujo de remoción de custom domain

**Archivos:** `admin.service.ts`

**Descripción:** No existe un método `removeCustomDomain()`. Si un tenant quiere quitar su custom domain:
- `nv_accounts.custom_domain` puede setearse a NULL manualmente
- Pero `clients.custom_domain` en Backend DB **no se limpia** (no hay trigger ni método)
- `cors_origins` mantiene entradas stale
- Netlify mantiene el dominio como alias
- Si el dominio se reasigna a otro tenant, la collision check en Backend DB **falla** porque `clients.custom_domain` del viejo tenant aún tiene el valor

**Impacto:** Imposible reasignar un dominio que fue verificado para otro tenant.

**Fix propuesto:** Crear `AdminService.removeCustomDomain(accountId)` que:
1. NULL en `nv_accounts.custom_domain, custom_domain_status, etc.`
2. NULL en `clients.custom_domain` (Backend DB)
3. DELETE de `cors_origins` correspondientes
4. Netlify: remove domain alias

---

### P1 — Importantes (degradan experiencia o mantenibilidad)

#### P1-1: Tenant admin no puede gestionar su dominio post-onboarding

**Archivos:** Solo `ClientApprovalDetail.jsx` (super admin) tiene el Domain tab.

**Descripción:** Después del onboarding, el tenant admin no tiene ninguna pantalla para:
- Ver el estado de verificación DNS de su dominio
- Ver instrucciones de configuración DNS
- Solicitar cambio de dominio
- Ver cuándo fue la última verificación

Solo el super admin puede hacer esto desde ClientApprovalDetail.

**Impacto:** Todo cambio de dominio post-onboarding requiere contacto con soporte.

---

#### P1-2: `clients.base_url` nunca se actualiza cuando custom domain se activa

**Archivos:** `provisioning-worker.service.ts`, `admin.service.ts`

**Descripción:** `base_url` se setea una vez en provisioning como `https://{slug}.novavision.lat` y nunca cambia. El SEO service prioriza `custom_domain` sobre `base_url`, por lo que el sitemap/OG funcionan correctamente. Pero cualquier lógica que use `base_url` directamente (sin verificar `custom_domain` primero) mostraría el dominio incorrecto.

**Impacto:** Medio — los flujos de SEO ya manejan el fallback correctamente. Pero `base_url` como campo es engañoso (no refleja la URL real si hay custom domain).

---

#### P1-3: Sin audit trail para cambios de dominio

**Descripción:** No existe logging estructurado de:
- Quién cambió el dominio (super admin ID)
- Cuál era el dominio anterior
- Cuándo se cambió
- Estado anterior → nuevo

Solo se actualizan timestamps (`custom_domain_requested_at`, `custom_domain_verified_at`).

---

#### P1-4: CORS origins se acumulan sin limpieza

**Archivos:** `admin.service.ts:1276-1300`

**Descripción:** `verifyCustomDomain()` hace upsert de `cors_origins` cuando un dominio pasa a `active`. Si el dominio se cambia después, las entradas CORS del dominio anterior permanecen. No hay cleanup.

**Impacto:** Acumulación de entradas stale. No es un riesgo de seguridad inmediato (CORS origins extra no abren acceso a datos), pero genera ruido y puede alcanzar límites.

---

#### P1-5: Domain status se muestra como valor raw sin labels/colores

**Archivos:** `ClientApprovalDetail.jsx:2918`

**Descripción:** El status se muestra como: `{account.custom_domain_status || 'Sin configurar'}`. Los valores `pending_dns`, `active`, `error` se muestran tal cual, sin:
- Labels amigables en español
- Color coding (verde/amarillo/rojo)
- Iconos indicativos

---

### P2 — Mejoras (deuda técnica, UX polish)

#### P2-1: Cookie domain `.novavision.lat` no aplica a custom domains

**Descripción:** Las cookies de autenticación se setean con domain `.novavision.lat`. Si un comprador inicia sesión en `tienda.novavision.lat` y luego accede a `www.mitienda.com`, la sesión no se mantiene.

**Impacto:** Los compradores que acceden vía custom domain no verán su sesión de `*.novavision.lat`. Cada dominio tiene su propia sesión de Supabase (por diseño), pero no hay documentación sobre este comportamiento esperado.

---

#### P2-2: PendingApprovalsView no muestra info de dominio

**Archivos:** `PendingApprovalsView.tsx:362-373`

**Descripción:** La lista de aprobaciones pendientes muestra slug, email, plan, fecha. No muestra si el tenant solicitó custom domain en onboarding, lo que obliga al super admin a abrir el detalle de cada uno para verificar.

---

#### P2-3: `custom_domain_concierge_until` sin cron de expiración

**Descripción:** `setCustomDomain()` setea `concierge_until = now + 1 year` en modo concierge. Pero no existe ningún cron ni lógica que actúe cuando esta fecha expira. El campo existe pero no tiene efecto práctico.

---

#### P2-4: Race condition potencial en `setCustomDomain()`

**Descripción:** La verificación de colisión (pasos 5-6) y el UPDATE (paso 9) no están en una transacción. Si dos requests concurrentes intentan setear el mismo dominio para cuentas diferentes, ambas podrían pasar la validación antes de que la primera complete el UPDATE. El UNIQUE index de DB protege contra insert duplicado, pero el error sería un 500 genérico en vez de un 409 Conflict amigable.

---

#### P2-5: Step9Summary valida custom domain solo como non-empty

**Archivos:** `Step9Summary.tsx:242-244`

**Descripción:** La validación del dominio en Step9 es solo `if (!customDomainInput)`. No aplica el regex `/^[a-z0-9.-]+\.[a-z]{2,}$/` que sí aplica la API. El usuario puede escribir cualquier cosa y solo recibe error al enviar al backend.

---

#### P2-6: JsonLd usa `baseUrl` del tenant sin priorizar custom domain

**Descripción:** Si el `TenantProvider` pasa `base_url` (que es siempre `*.novavision.lat`) como prop, y `JsonLd.jsx` lo usa sin verificar `custom_domain`, los datos estructurados tendrían la URL incorrecta cuando se accede vía custom domain. Sin embargo, el SEOHead principal usa `window.location.origin`, que sí resuelve correctamente.

---

## 7. Casos de Test E2E (20 escenarios)

### Grupo A: Slug y Onboarding (5 tests)

| # | Escenario | Precondición | Pasos | Resultado Esperado | Gap Actual |
|---|-----------|-------------|-------|-------------------|-----------|
| 1 | Crear slug válido | Sin cuenta previa | 1. Input `mi-tienda-123` 2. Submit | Slug reservado, account creado, redirect a Step 2 | ✅ Funciona |
| 2 | Slug duplicado | `mi-tienda` ya existe en nv_accounts | 1. Input `mi-tienda` 2. Submit | Error "dominio ya en uso" visible | ✅ Funciona |
| 3 | Slug con caracteres inválidos | — | 1. Input `Mi_Tienda!` | Sanitize on-change a `mitienda`, solo a-z0-9- | ✅ Funciona |
| 4 | Slug reserva expira | Reserva creada hace >30 min | 1. Otro usuario intenta mismo slug | Slug disponible (TTL expirado) | ✅ Funciona (claim_slug_final RPC) |
| 5 | Slug inmutable post-publish | nv_accounts.status = 'approved' | 1. UPDATE slug vía DB | Trigger previene cambio, RAISE EXCEPTION | ✅ Funciona (trigger ADMIN_060) |

### Grupo B: Custom Domain — Set y Verify (5 tests)

| # | Escenario | Precondición | Pasos | Resultado Esperado | Gap Actual |
|---|-----------|-------------|-------|-------------------|-----------|
| 6 | Set custom domain Growth | Cuenta aprobada, plan Growth | 1. POST /admin/accounts/:id/custom-domain `{domain: 'mitienda.com'}` | Status 200, nv_accounts.custom_domain = 'mitienda.com', status = 'pending_dns' | ✅ Funciona |
| 7 | Set custom domain Starter (rejected) | Cuenta aprobada, plan Starter | 1. POST /admin/accounts/:id/custom-domain `{domain: 'mitienda.com'}` | Error 400 "Disponible a partir del plan Growth" | ✅ Funciona |
| 8 | Set dominio duplicado | `mitienda.com` ya asignado a otra cuenta | 1. POST set domain | Error 409 "Dominio ya en uso" | ✅ Funciona |
| 9 | Set dominio `*.novavision.lat` | — | 1. POST set domain `test.novavision.lat` | Error 400 "Dominio reservado" | ✅ Funciona |
| 10 | Verify DNS — active | DNS configurado, Netlify reporta SSL active | 1. POST verify | Status 200, nv_accounts.status='active', clients.custom_domain synced, CORS upserted | ✅ Funciona |

### Grupo C: Custom Domain — Runtime Resolution (5 tests)

| # | Escenario | Precondición | Pasos | Resultado Esperado | Gap Actual |
|---|-----------|-------------|-------|-------------------|-----------|
| 11 | Acceso `slug.novavision.lat` | Tienda publicada con slug `tienda-1` | 1. Navegar a `tienda-1.novavision.lat` | Tienda carga correctamente | ✅ Funciona |
| 12 | Acceso `mitienda.com` (root) | Custom domain active, DNS ok | 1. Navegar a `mitienda.com` | isLikelyCustomDomain → async resolve → tienda carga | ✅ Funciona |
| 13 | Acceso `www.mitienda.com` | Custom domain active, DNS ok | 1. Navegar a `www.mitienda.com` | Tienda carga correctamente | ❌ **BUG P0-1**: Extrae 'www' como slug, STORE_NOT_FOUND |
| 14 | Acceso dominio no registrado | `random.com` sin custom_domain en DB | 1. Navegar a `random.com` | Error "Tienda No Encontrada" con código NO_SLUG o STORE_NOT_FOUND | ✅ Funciona |
| 15 | Custom domain pending_dns | nv_accounts.status='pending_dns' | 1. Navegar a `mitienda.com` | resolveHostToSlug retorna null → STORE_NOT_FOUND | ✅ Funciona (by design) |

### Grupo D: SEO y URL Canónica (3 tests)

| # | Escenario | Precondición | Pasos | Resultado Esperado | Gap Actual |
|---|-----------|-------------|-------|-------------------|-----------|
| 16 | Canonical URL con subdomain | Sin custom domain | 1. Ver `<link rel="canonical">` | `https://slug.novavision.lat/path` | ✅ Funciona (window.location.origin) |
| 17 | Canonical URL con custom domain | custom_domain='mitienda.com' active | 1. Acceder via `mitienda.com` 2. Ver canonical | `https://mitienda.com/path` | ✅ Funciona (window.location.origin) |
| 18 | Sitemap con custom domain | custom_domain active en clients | 1. GET /seo/sitemap | URLs usan `https://mitienda.com/...` | ✅ Funciona (SeoService prioriza custom_domain) |

### Grupo E: Edge Cases y Seguridad (2 tests)

| # | Escenario | Precondición | Pasos | Resultado Esperado | Gap Actual |
|---|-----------|-------------|-------|-------------------|-----------|
| 19 | Cross-tenant request blocked | Slug `tienda-1` resuelto | 1. Inyectar header `x-tenant-slug: tienda-2` en request | Request bloqueada con "Security Error: Cross-Tenant Request Blocked" | ✅ Funciona (axios interceptor) |
| 20 | Remoción de custom domain | Dominio `mitienda.com` active | 1. Intentar quitar dominio | ❌ **No existe flujo**: No hay endpoint ni UI para remover dominio. `clients.custom_domain` queda stale |

---

## 8. Auditoría UX / Producto

### 8.1 Estado actual — UX Journey del dominio

| Etapa | Actor | Pantalla | Calidad UX | Problemas |
|-------|-------|----------|-----------|-----------|
| Elegir slug | Tenant | Step1Slug | ✅ Buena | Feedback inmediato, sanitize, error claro |
| Solicitar custom domain | Tenant (Growth) | Step9Summary | ⚠️ Media | Sin validación de formato, solo non-empty. No muestra preview del resultado final |
| Ver URL final | Tenant | Step11/12Success | ✅ Buena | Muestra `slug.novavision.lat` claramente. No menciona custom domain si fue solicitado |
| Configurar dominio | Super Admin | ClientApprovalDetail (Domain tab) | ⚠️ Media | Status raw sin labels, instrucciones DNS completas pero densas |
| Verificar DNS | Super Admin | ClientApprovalDetail (Domain tab) | ⚠️ Media | Botón funcional, pero resultado es texto plano sin indicador visual |
| Gestionar dominio post-launch | Tenant Admin | **NO EXISTE** | ❌ Mala | El tenant no tiene acceso a ninguna información de su dominio |
| Ver estado en lista | Super Admin | PendingApprovalsView | ⚠️ Media | No muestra si hay custom domain solicitado |

### 8.2 Propuesta: "Centro de Dominio y Publicación" para Tenant Admin

**Ubicación sugerida:** Nueva sección en el dashboard del tenant (`/hub/domain` o tab en settings).

**Componentes propuestos:**

```
┌─────────────────────────────────────────────────────────┐
│  🌐 Tu Dominio                                          │
│                                                         │
│  ┌──────────────────────────┐  ┌──────────────────────┐ │
│  │ Dominio Actual           │  │ Custom Domain        │ │
│  │                          │  │                      │ │
│  │ tienda.novavision.lat    │  │ mitienda.com         │ │
│  │ ✅ Activo                │  │ 🟡 Pendiente DNS     │ │
│  │                          │  │                      │ │
│  │ [Copiar URL]             │  │ Última verificación: │ │
│  └──────────────────────────┘  │ hace 2 horas         │ │
│                                │                      │ │
│                                │ [Ver instrucciones]  │ │
│                                │ [Solicitar ayuda]    │ │
│                                └──────────────────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ 📋 Instrucciones DNS                                │ │
│  │                                                     │ │
│  │ Configurá estos registros en tu proveedor de DNS:   │ │
│  │                                                     │ │
│  │ Tipo    Nombre    Valor               TTL           │ │
│  │ ─────   ─────     ─────               ───           │ │
│  │ CNAME   www       tu-sitio.netlify.app 3600         │ │
│  │ A       @         75.2.60.5            3600         │ │
│  │ A       @         99.83.190.102        3600         │ │
│  │                                                     │ │
│  │ ⏱️ La verificación automática corre cada 10 min.    │ │
│  │ Te notificaremos cuando esté listo.                 │ │
│  └─────────────────────────────────────────────────────┘ │
│                                                         │
│  ┌─────────────────────────────────────────────────────┐ │
│  │ 🔒 SSL                                              │ │
│  │ ✅ Certificado activo (Let's Encrypt via Netlify)    │ │
│  │ Próxima renovación: automática                      │ │
│  └─────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────┘
```

**Funcionalidades:**
1. **Vista read-only** del dominio actual y su estado
2. **Instrucciones DNS** contextuales (según modo concierge/self-service)
3. **Indicador de estado** con colores: verde (active), amarillo (pending_dns), rojo (error)
4. **Última verificación** con timestamp humanizado
5. **Botón "Solicitar ayuda"** que abre ticket/contacto
6. **Notificación** cuando el dominio cambia de estado

---

## 9. Propuesta de Mejora Técnica

### 9.1 Máquina de estados para custom domain

**Estado actual:** 3 estados como strings sin validación (`pending_dns`, `active`, `error`)

**Propuesta:** State machine formal con transiciones definidas

```
                    setCustomDomain()
                          │
                          ▼
                   ┌──────────────┐
     ┌────────────▶│  pending_dns  │◀──────────────┐
     │             └──────┬───────┘               │
     │                    │                        │
     │            verifyCustomDomain()             │
     │                    │                        │
     │         ┌──────────┴──────────┐             │
     │         ▼                     ▼             │
     │  ┌──────────┐         ┌──────────┐          │
     │  │  active   │         │  error   │──────────┘
     │  └──────┬───┘         └──────────┘    retry verify
     │         │
     │   removeCustomDomain()
     │         │
     │         ▼
     │  ┌──────────┐
     └──│ removed  │
        └──────────┘
              │
              ▼
          (NULL all fields)
```

**Transiciones válidas:**
- `NULL → pending_dns` (setCustomDomain)
- `pending_dns → active` (verifyCustomDomain con DNS OK)
- `pending_dns → error` (verifyCustomDomain con DNS fail)
- `error → pending_dns` (retry verify)
- `active → removed` (removeCustomDomain — NUEVO)
- `active → pending_dns` (setCustomDomain con dominio diferente — NUEVO)
- `removed → pending_dns` (setCustomDomain nuevo dominio)

### 9.2 Normalización de `novavision.lat` hardcoded

**Propuesta:** Crear constante compartida

```
// Shared config (API)
export const PLATFORM_DOMAIN = process.env.PLATFORM_DOMAIN || 'novavision.lat';

// Admin (env)
VITE_PLATFORM_DOMAIN=novavision.lat

// Web (env)
VITE_PLATFORM_DOMAIN=novavision.lat
```

Impacto: ~20 archivos, cambio mecánico.

### 9.3 Health check de dominio con observabilidad

**Propuesta:** Agregar métricas y alertas al cron de verificación:

```typescript
// Métricas a trackear
domain_verification_total       // Counter: verificaciones ejecutadas
domain_verification_success     // Counter: transiciones a 'active'
domain_verification_failure     // Counter: DNS no resuelve
domain_verification_duration_ms // Histogram: duración de verificación
domain_stale_pending_count      // Gauge: dominios en pending_dns > 48h
```

### 9.4 Endpoint `removeCustomDomain()`

```typescript
async removeCustomDomain(accountId: string) {
  // 1. Leer dominio actual de nv_accounts
  // 2. NULL en nv_accounts: custom_domain, status, mode, timestamps, error
  // 3. NULL en clients (Backend DB): custom_domain
  // 4. DELETE cors_origins WHERE origin LIKE '%domain%' AND client_id
  // 5. Netlify: remove domain alias (optional - puede dejarse)
  // 6. Log audit event
  return { removed: true, domain: oldDomain };
}
```

### 9.5 Sync bidireccional de `clients.custom_domain`

**Problema:** `clients.custom_domain` solo se escribe en `verifyCustomDomain()` cuando status='active'. Si se cambia el dominio sin verificar, el viejo valor persiste en Backend DB.

**Propuesta:** Agregar sync en `setCustomDomain()`:

```typescript
// En setCustomDomain(), después de actualizar nv_accounts:
// Si el dominio ANTERIOR era 'active', limpiar de clients
if (oldDomain && oldDomain !== normalized) {
  await backendSupabase
    .from('clients')
    .update({ custom_domain: null })
    .eq('nv_account_id', accountId);
  // También limpiar cors_origins del viejo dominio
}
```

---

## 10. Plan de Implementación por Fases

### Fase 0 — Hotfix P0 (1-2 días) ← ANTES DE LANZAMIENTO

| Tarea | Archivos | Migración | Riesgo | Esfuerzo |
|-------|----------|-----------|--------|----------|
| Fix bug `www.*` custom domain | `apps/web/src/utils/tenantResolver.js` | No | Bajo | 30 min |
| Test del fix | `apps/web/src/utils/__tests__/tenantResolver.test.js` (crear) | No | Bajo | 1h |

**Cambio exacto en `tenantResolver.js`:**

```javascript
// ANTES del bloque "if (parts.length >= 3)"
// 3. Custom domain → force async resolution
if (isLikelyCustomDomain(hostname)) {
  return null;
}

// 4. Platform Subdomain Parsing (only *.novavision.lat, *.netlify.app)
const parts = hostname.split('.');
if (parts.length >= 3) {
  return parts[0];
}
```

---

### Fase 1 — Consistencia de datos (3-5 días)

| Tarea | Archivos | Migración | Riesgo | Esfuerzo |
|-------|----------|-----------|--------|----------|
| Crear `removeCustomDomain()` | `admin.service.ts`, `admin.controller.ts` | No | Medio | 4h |
| Sync bidireccional `clients.custom_domain` | `admin.service.ts` | No | Medio | 2h |
| Cleanup CORS on domain change | `admin.service.ts` | No | Bajo | 1h |
| Extraer constante `PLATFORM_DOMAIN` (API) | `admin.service.ts`, `tenant-context.guard.ts`, `provisioning-worker.service.ts` | No | Bajo | 2h |
| Actualizar `base_url` cuando domain verifica | `admin.service.ts` | No | Bajo | 1h |
| CHECK constraint para `custom_domain_status` | Migration file | Sí: `ALTER TABLE nv_accounts ADD CONSTRAINT ...` | Bajo | 30 min |

---

### Fase 2 — UX Admin (5-7 días)

| Tarea | Archivos | Migración | Riesgo | Esfuerzo |
|-------|----------|-----------|--------|----------|
| Labels y colores para domain status | `ClientApprovalDetail.jsx` | No | Bajo | 2h |
| Mostrar domain request en PendingApprovals | `PendingApprovalsView.tsx` | No | Bajo | 2h |
| Validación regex en Step9Summary | `Step9Summary.tsx` | No | Bajo | 1h |
| Extraer constante `PLATFORM_DOMAIN` (Admin) | ~10 archivos | No | Bajo | 3h |
| Audit trail para cambios de dominio | `admin.service.ts`, nueva tabla o columna | Sí: tabla `domain_audit_log` | Bajo | 4h |

---

### Fase 3 — Centro de Dominio Tenant (7-10 días)

| Tarea | Archivos | Migración | Riesgo | Esfuerzo |
|-------|----------|-----------|--------|----------|
| API: endpoint read-only domain status para tenant | `client-dashboard.controller.ts` | No | Bajo | 2h |
| UI: componente DomainStatusCard | Nuevo componente Admin | No | Bajo | 4h |
| UI: instrucciones DNS contextuales | Nuevo componente Admin | No | Bajo | 3h |
| UI: integrar en Hub/Settings del tenant | `TenantSettingsPage` o similar | No | Bajo | 2h |
| Notificación por email al cambiar estado | `admin.service.ts`, template de email | No | Medio | 4h |

---

### Fase 4 — Observabilidad y hardening (5-7 días)

| Tarea | Archivos | Migración | Riesgo | Esfuerzo |
|-------|----------|-----------|--------|----------|
| Métricas de domain verification | `custom-domain-verifier.cron.ts` | No | Bajo | 3h |
| Alerta: dominio en pending_dns > 48h | Cron o monitor | No | Bajo | 2h |
| Transaccionalidad en setCustomDomain | `admin.service.ts` | No | Medio | 3h |
| Cron para `concierge_until` expirado | Nuevo cron | No | Bajo | 2h |
| Cleanup de Netlify aliases stale | `netlify.service.ts` | No | Medio | 3h |
| Web: constante `PLATFORM_DOMAIN` | `tenantResolver.js` | No | Bajo | 1h |

---

## Apéndice A: Tablas de Base de Datos Involucradas

### Admin DB (`nv_accounts`)

| Columna | Tipo | Nullable | Default | Constraint |
|---------|------|----------|---------|------------|
| `slug` | text | NO | — | UNIQUE |
| `custom_domain` | text | Sí | NULL | UNIQUE (citext, WHERE NOT NULL) |
| `custom_domain_status` | text | Sí | NULL | Sin CHECK (debería ser: pending_dns, active, error) |
| `custom_domain_mode` | text | Sí | NULL | Sin CHECK (debería ser: self_service, concierge) |
| `custom_domain_requested_at` | timestamptz | Sí | NULL | — |
| `custom_domain_verified_at` | timestamptz | Sí | NULL | — |
| `custom_domain_last_checked_at` | timestamptz | Sí | NULL | — |
| `custom_domain_error` | text | Sí | NULL | — |
| `custom_domain_concierge_until` | timestamptz | Sí | NULL | — |
| `netlify_site_id` | text | Sí | NULL | — |

### Admin DB (`managed_domains`)

| Columna | Tipo | Nullable | Constraint |
|---------|------|----------|------------|
| `domain` | citext | NO | UNIQUE |
| `account_id` | uuid | Sí | FK → nv_accounts |
| `expires_at` | timestamptz | NO | — |
| `auto_renew` | boolean | — | DEFAULT true |
| `renewal_state` | enum | — | none, due_soon, invoice_created, paid, overdue, renewal_failed |
| `provider` | text | — | DEFAULT 'manual' |

### Admin DB (`slug_reservations`)

| Columna | Tipo | Constraint |
|---------|------|------------|
| `slug` | text | PK |
| `account_id` | uuid | FK → nv_accounts |
| `reserved_at` | timestamptz | DEFAULT now() |
| `expires_at` | timestamptz | DEFAULT now() + 30 min |

### Backend DB (`clients`)

| Columna | Tipo | Constraint |
|---------|------|------------|
| `slug` | text | — |
| `custom_domain` | text | UNIQUE (WHERE NOT NULL) |
| `base_url` | text | — |
| `publication_status` | text | draft, pending_approval, published |
| `nv_account_id` | uuid | UNIQUE |

### Backend DB (`seo_settings`)

| Columna | Tipo | Constraint |
|---------|------|------------|
| `client_id` | uuid | UNIQUE, FK → clients |
| `ga4_measurement_id` | text | — |
| `gtm_container_id` | text | — |
| `search_console_token` | text | — |

---

## Apéndice B: Endpoints API Relevantes

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| POST | `/onboarding/builder/start` | Público | Crea cuenta + reserva slug |
| PATCH | `/onboarding/custom-domain` | X-Builder-Token | Registra intención de custom domain |
| POST | `/admin/accounts/:id/custom-domain` | SuperAdminGuard | Setea custom domain |
| POST | `/admin/accounts/:id/custom-domain/verify` | SuperAdminGuard | Verifica DNS |
| GET | `/tenant/resolve-host?domain=` | Público (AllowNoTenant) | Resuelve custom domain → slug |
| GET | `/tenant/bootstrap` | x-tenant-slug header | Datos completos del tenant |
| POST | `/admin/domains/provision` | SuperAdminGuard | Provisiona managed domain (Namecheap) |
| POST | `/admin/domains/:id/manual-renewal` | SuperAdminGuard | Renueva managed domain |
| GET | `/admin/domains/account/:id` | SuperAdminGuard | Info de managed domain |
| GET | `/client/managed-domains` | TenantGuard | Status de managed domain (read-only) |

---

## Apéndice C: Variables de Entorno Relevantes

| Variable | Repo | Descripción |
|----------|------|-------------|
| `NETLIFY_API_TOKEN` | API | Token de acceso a Netlify API |
| `NETLIFY_STOREFRONT_SITE_ID` | API | Site ID del storefront en Netlify |
| `NETLIFY_SITE_ID` | API | Fallback de site ID |
| `VITE_BACKEND_API_URL` | Web | URL del backend API |
| `VITE_DEV_SLUG` | Web | Override de slug para dev local |
| `VITE_PLATFORM_DOMAIN` | Web/Admin | **NO EXISTE** — debería crearse |
| `PLATFORM_DOMAIN` | API | **NO EXISTE** — debería crearse |

---

## Apéndice D: Auditoría Detallada del Super Admin Domain Tab

**Actualización:** 2026-03-16 (segunda pasada)

### D.1 Flujo completo del Domain Tab en `ClientApprovalDetail.jsx`

**Componentes del tab (L2873-3206):**

| Sección | Líneas | Contenido |
|---------|--------|-----------|
| Estado actual (card izq) | L2893-2931 | Dominio, modo, status DNS (texto plano), último check, error |
| Configuración rápida (card der) | L2933-3024 | Input dominio, select modo, botones Guardar/Verificar |
| Instrucciones DNS | L3027-3108 | Pasos concierge/self-service, paso a paso Namecheap |
| Checklist rápido | L3136-3154 | Lista estática (no interactiva) |
| Datos del onboarding | L3156-3205 | 8 campos del custom_domain_request |

### D.2 Bugs encontrados en el Domain Tab

#### BUG: `handleSaveCustomDomain` no ejecuta `refreshDetail()`

**Archivo:** `ClientApprovalDetail.jsx:936-955`

Después del toast de éxito (L948), no recarga los datos. El super admin ve "Dominio configurado" pero el bloque "Estado actual" sigue mostrando el valor viejo. Tiene que refrescar la página manualmente.

En contraste, `handleVerifyCustomDomain` (L957-968) SÍ ejecuta `refreshDetail()` en L962.

**Fix:** Agregar `await refreshDetail();` después del toast en L948.

#### BUG: Instrucciones DNS con CNAME genérico

**Archivo:** `ClientApprovalDetail.jsx:3045,3068`

Las instrucciones dicen literalmente `tu-sitio.netlify.app` como target del CNAME. No sustituyen por el site name real de Netlify. El super admin tiene que adivinar o buscar en el dashboard de Netlify.

**Fix:** Obtener `netlify_site_id` del account, hacer `GET /sites/{id}` para obtener el `default_domain` (ej: `novavision-storefront.netlify.app`), y mostrarlo dinámico.

#### BUG: Status sin color coding

**Archivo:** `ClientApprovalDetail.jsx:2917-2918`

```jsx
{account.custom_domain_status || 'Sin configurar'}
```

Texto plano sin badge ni color. Comparar con `ClientDomains` que SÍ tiene `StatusChip` con verde/amarillo/rojo.

### D.3 IPs de Netlify documentadas en las instrucciones

| Registro | Valor | Fuente |
|----------|-------|--------|
| A Record (apex) | `75.2.60.5` | Hardcoded en L3092 |
| A Record (apex) | `99.83.190.102` | Hardcoded en L3094 |
| CNAME (www) | `tu-sitio.netlify.app` | Genérico en L3088 |

Las IPs `75.2.60.5` y `99.83.190.102` son las IPs públicas del load balancer de Netlify. Son correctas a la fecha pero pueden cambiar. Netlify recomienda ALIAS/ANAME cuando el registrar lo soporta.

---

## Apéndice E: Límites de Netlify y Riesgo de Escalabilidad

### E.1 Arquitectura actual: single-site

Todos los custom domains de todos los tenants se agregan como `domain_aliases` a **un único Netlify site** (el storefront). El `netlify_site_id` se toma de:
1. `nv_accounts.netlify_site_id` (per-account, usualmente NULL)
2. `NETLIFY_STOREFRONT_SITE_ID` (env var)
3. `NETLIFY_SITE_ID` (env var legacy)

En la práctica, todos comparten el mismo site ID.

### E.2 Límite real de Netlify

| Fuente | Límite |
|--------|--------|
| Netlify Staff (foro, 2023) | ~90-100 apex domains por site |
| Let's Encrypt | 100 SANs (Subject Alternative Names) por certificado SSL |
| Netlify docs (recomendación) | ≤50 domain aliases por site |
| Subdominios wildcard | Sin límite (requiere Netlify DNS en plan Pro+) |

**Fuentes:**
- [Maximum number of Custom domains — Netlify Forums](https://answers.netlify.com/t/maximum-number-of-custom-domains/29099)
- [Limits on domain aliases — Netlify Forums](https://answers.netlify.com/t/limits-on-domain-aliases/23319)

### E.3 Comportamiento de `updateSiteDomains()` — aliases se ACUMULAN

**Archivo:** `netlify.service.ts:33-75`

```
1. GET /sites/{id} → lee domain_aliases existentes
2. Crea Set(existentes) + Set(nuevos) → MERGE
3. PATCH /sites/{id} con el Set completo
```

Los aliases **nunca se eliminan**. No existe `removeSiteAlias()`. Dominios de ex-clientes, dominios cambiados, dominios de prueba — todos quedan acumulados contra el límite de ~100.

### E.4 Proyección de capacidad

| Escenario | Custom domains necesarios | ¿Cabe en 1 site? |
|-----------|--------------------------|-------------------|
| Lanzamiento (primeros 50 tenants Growth) | ~10-15 | ✅ Sí |
| 100 tenants Growth activos | ~30-40 | ✅ Sí (pero sin cleanup) |
| 200 tenants Growth + churn | ~60-80 + stale | ⚠️ Límite |
| 500+ tenants | ~150+ | ❌ No — requiere multi-site o Cloudflare |

### E.5 Bug: inversión www/root en Netlify

**Archivo:** `admin.service.ts:1157-1162`

```typescript
customDomain: `www.${normalized}`,   // ← www como primary
domainAliases: [normalized],         // ← root como alias
```

Netlify espera que `custom_domain` sea el dominio canónico (usualmente root/apex). Poner `www` como primary puede causar que Netlify redirija `mitienda.com → www.mitienda.com` automáticamente, lo cual contradice la práctica moderna de preferir el apex.

### E.6 Estrategia de escalabilidad recomendada

**Corto plazo (0-100 custom domains):**
1. Implementar `removeNetlifyAlias()` para cleanup
2. Agregar check de cantidad antes de agregar
3. Corregir inversión www/root

**Mediano plazo (100-500 custom domains):**
- Evaluar **Cloudflare for SaaS** (custom hostnames ilimitados, SSL automático, diseñado para multi-tenant)
- O implementar multi-site Netlify con routing por grupo de tenants

**Largo plazo (500+ custom domains):**
- Cloudflare for SaaS es la opción clara para SaaS multi-tenant a escala

---

## Apéndice F: Inventario de Acoplamiento con Netlify

### F.1 Servicios de Netlify usados vs no usados

| Servicio Netlify | ¿Lo usa NovaVision? | Impacto en migración |
|-----------------|---------------------|---------------------|
| **Static hosting (CDN)** | ✅ Sí | Bajo — cualquier CDN sirve archivos estáticos |
| **Edge Functions (Deno)** | ✅ Sí — 4 funciones | **Medio** — requiere rewrite a middleware del destino |
| **Domain aliases (API)** | ✅ Sí — `netlify.service.ts` | **Alto** — toda la gestión de custom domains pasa por la API de Netlify |
| **Wildcard SSL (Let's Encrypt)** | ✅ Sí — plan Pro | Medio — alternativas lo ofrecen también |
| **Security headers** | ✅ Sí — `netlify.toml` | Bajo — portable a cualquier plataforma |
| **Build config** | ✅ Sí — `netlify.toml` | Bajo — es un `npm run build` estándar |
| **Deploy previews** | ✅ Sí — branch/PR deploys | Bajo — feature estándar en Vercel/Cloudflare Pages |
| **Netlify DNS** | ❌ No — usa Namecheap | ✅ **Punto a favor**: DNS externo = portabilidad |
| **Netlify Forms** | ❌ No | — |
| **Netlify Identity** | ❌ No — usa Supabase Auth | — |
| **Netlify Functions (serverless)** | ❌ No — usa Railway (NestJS) | — |
| **Netlify Blobs / DB** | ❌ No — usa Supabase | — |

### F.2 Las 4 Edge Functions — Detalle de acoplamiento

| Edge Function | LOC | APIs de Netlify usadas | Equivalente portable |
|--------------|-----|----------------------|---------------------|
| `maintenance.ts` | 84 | `context.next()`, `context.rewrite()`, `Deno.env.get()` | Vercel: `middleware.ts` con `NextResponse.rewrite()`. Cloudflare: Worker con `fetch()` |
| `og-inject.ts` | 215 | `context.next()`, `Deno.env.get()` | Vercel: middleware o API route. Cloudflare: Worker con `HTMLRewriter` |
| `seo-redirects.ts` | 115 | `context.next()`, `Deno.env.get()` | Vercel: `middleware.ts` con `NextResponse.redirect()`. Cloudflare: Worker |
| `seo-robots.ts` | 100 | `Deno.env.get()` | Vercel: API route `/api/robots`. Cloudflare: Worker |
| **Total** | **~514** | | |

**Patrón común:** Todas las edge functions hacen `fetch()` al backend (Railway) con `x-forwarded-host` y devuelven la respuesta o `context.next()`. La lógica de negocio vive en el API, no en las edge functions. Esto hace que la migración sea **rewrite del wrapper**, no reimplementación de lógica.

### F.3 `netlify.service.ts` — El servicio más acoplado

**Archivo:** `apps/api/src/admin/netlify.service.ts` (3 métodos, ~110 LOC)

Este servicio **sí es específico de Netlify** y sería el componente más difícil de migrar:

| Método | Llamada Netlify API | Qué hace |
|--------|-------------------|----------|
| `getSite(siteId)` | `GET /api/v1/sites/{id}` | Lee estado actual del site |
| `updateSiteDomains(siteId, params)` | `PATCH /api/v1/sites/{id}` | Agrega domain aliases + custom_domain + SSL |
| `resolveDomainStatus(siteId, domain)` | `GET /api/v1/sites/{id}` | Verifica si dominio existe y SSL está activo |

**Patrón de abstracción sugerido:** Crear interfaz `DomainProviderService` que `NetlifyService` implemente hoy y que mañana pueda implementar `CloudflareSaasService` o `VercelDomainService`.

```typescript
interface DomainProviderService {
  addDomain(domain: string): Promise<{ status: 'pending' | 'active' | 'error' }>;
  removeDomain(domain: string): Promise<void>;
  verifyDomain(domain: string): Promise<{ status: 'pending' | 'active' | 'error', ssl: boolean }>;
  listDomains(): Promise<string[]>;
}
```

---

## Apéndice G: Plan de Portabilidad — Migración Futura Fácil

### G.1 Principio rector

> **Tratar a Netlify como un proveedor de hosting reemplazable, no como el lugar donde vive la lógica del negocio.**

### G.2 Lo que ya está bien (puntos a favor de portabilidad)

| Aspecto | Estado | Por qué es bueno |
|---------|--------|-------------------|
| DNS en Namecheap (externo) | ✅ | Cambiar CNAME targets es trivial — no hay lock-in de DNS |
| Backend en Railway (separado) | ✅ | El API no depende de Netlify en absoluto |
| Auth en Supabase (separada) | ✅ | No depende de Netlify Identity |
| DB en Supabase (separada) | ✅ | No depende de Netlify DB/Blobs |
| Lógica de negocio en API | ✅ | Edge functions son wrappers livianos, no lógica core |
| Tenant → dominio modelado en DB | ✅ | `nv_accounts.custom_domain` es la source of truth, no Netlify |
| Build estándar (Vite SPA) | ✅ | `npm run build` → `dist/` — funciona en cualquier host |

### G.3 Lo que hay que asegurar AHORA para migrar fácil después

#### 1. Config de build y deploy — en el repo (ya cumplido parcialmente)

| Item | Estado | Archivo |
|------|--------|---------|
| Comando de build | ✅ `netlify.toml` + `package.json` | `npm run build` |
| Carpeta de salida | ✅ `dist/` | Standard Vite output |
| Versión de Node | ✅ `netlify.toml:17` | `NODE_VERSION = "20.11.1"` |
| Lock file | ✅ | `package-lock.json` |
| Headers custom | ✅ | `netlify.toml` (CSP, security headers) |
| Redirects SPA | ⚠️ **NO versionado** | Falta `_redirects` con `/* /index.html 200` — probablemente está solo en panel de Netlify |
| Edge Functions | ✅ | En el repo: `netlify/edge-functions/` |

**Acción:** Crear archivo `_redirects` en `public/` con el SPA fallback, no depender de config en el panel.

#### 2. Variables de entorno — inventario completo

**Acción:** Crear documento `ENV_INVENTORY.md` con:

| Variable | Entorno | Dónde se usa | Valor (referencia) |
|----------|---------|--------------|-------------------|
| `VITE_BACKEND_URL` | Build + Edge | Todas las edge functions | URL de Railway API |
| `VITE_BACKEND_API_URL` | Build | `axiosConfig.jsx` | URL de Railway API |
| `VITE_DEV_SLUG` | Dev only | `tenantResolver.js` | Slug de test local |
| `BACKEND_HEALTH_URL` | Edge | `maintenance.ts` | URL de health endpoint |
| `BACKEND_FALLBACK_URL` | Edge | `maintenance.ts` | URL fallback |
| `MAINTENANCE` | Edge | `maintenance.ts` | Kill-switch manual |
| `ROBOTS_NOINDEX` | Deploy preview | `netlify.toml` | Flag para previews |
| `NETLIFY_API_TOKEN` | Railway (API) | `netlify.service.ts` | Token de Netlify API |
| `NETLIFY_STOREFRONT_SITE_ID` | Railway (API) | `admin.service.ts` | Site ID del storefront |
| `NETLIFY_SITE_ID` | Railway (API) | `admin.service.ts` (legacy) | Site ID fallback |

#### 3. Mapa de dominios y DNS — en la DB (ya cumplido)

La source of truth de tenant → dominio ya vive en la DB:

| Campo | Tabla | DB | ¿Suficiente? |
|-------|-------|----|-------------|
| `slug` | `nv_accounts` | Admin | ✅ |
| `custom_domain` | `nv_accounts` | Admin | ✅ |
| `custom_domain_status` | `nv_accounts` | Admin | ✅ |
| `custom_domain_mode` | `nv_accounts` | Admin | ✅ |
| `base_url` | `clients` | Backend | ⚠️ Nunca se actualiza con custom domain |
| `custom_domain` | `clients` | Backend | ✅ (sync cuando active) |

**Acción necesaria:** Agregar campo `redirect_to_primary` (boolean) para controlar si `slug.novavision.lat` redirige a `mitienda.com` cuando hay custom domain activo. Hoy no existe este concepto.

#### 4. Reglas de routing — documentar

**Acción:** Crear `ROUTING_RULES.md` con:

```markdown
## Resolución de dominios

| Dominio | Destino | Cómo resuelve |
|---------|---------|---------------|
| `novavision.lat` | Admin (Site 1) | DNS: A record → Netlify Admin |
| `www.novavision.lat` | Admin (Site 1) | DNS: CNAME → Netlify Admin |
| `api.novavision.lat` | Railway API | DNS: CNAME → Railway |
| `*.novavision.lat` | Storefront (Site 2) | DNS: CNAME wildcard → Netlify Storefront |
| `mitienda.com` | Storefront (Site 2) | DNS del cliente: CNAME/A → Netlify Storefront |

## SPA fallback
Todas las rutas que no matcheen un archivo estático → /index.html (200)

## Redirects SEO
Manejados por edge function seo-redirects.ts → consulta backend

## Canonicalización www
Actualmente NO hay redirect www → root ni root → www para custom domains.
El sistema acepta ambos (si el bug P0-1 se corrige).
```

#### 5. Checklist de alta de custom domain — documentar

**Acción:** Crear `CUSTOM_DOMAIN_CHECKLIST.md`:

```markdown
## Alta de custom domain para un tenant

### Pre-requisitos
- [ ] Tenant con plan Growth o superior
- [ ] Tenant con tienda publicada (publication_status = 'published')

### Pasos (Super Admin)
1. [ ] Ir a Admin → Clientes → Detalle → Tab "Dominio"
2. [ ] Ingresar dominio (sin www, sin protocolo)
3. [ ] Seleccionar modo: self_service o concierge
4. [ ] Click "Guardar dominio"
5. [ ] Verificar que Netlify registró el alias (check logs)

### Pasos (Cliente — Self Service)
6. [ ] Configurar DNS:
   - CNAME: www → [storefront-site].netlify.app
   - A: @ → 75.2.60.5
   - A: @ → 99.83.190.102
7. [ ] Esperar propagación DNS (hasta 48h)

### Verificación (Super Admin)
8. [ ] Click "Verificar DNS" en el tab de dominio
9. [ ] Confirmar status = 'active'
10. [ ] Verificar que clients.custom_domain se sincronizó
11. [ ] Test: abrir https://mitienda.com en browser
12. [ ] Test: abrir https://www.mitienda.com en browser
13. [ ] Test: verificar OG tags (compartir en WhatsApp/Facebook)
14. [ ] Test: verificar sitemap tiene URLs con custom domain
```

#### 6. Proceso de SSL — documentar (no portarlo)

Los certificados se regeneran en el host nuevo. Lo que hay que documentar:

| Aspecto | Valor actual |
|---------|-------------|
| Emisor | Let's Encrypt (via Netlify) |
| Tipo | Wildcard para `*.novavision.lat` + individual por custom domain |
| Renovación | Automática por Netlify |
| Verificación | DNS (CNAME/A records) |
| Tiempo de emisión | 5-15 minutos típico, hasta 1 hora |
| Errores comunes | DNS no propagado, CNAME apunta a site incorrecto |

### G.4 Evaluación de alternativas a Netlify

| Plataforma | Custom domains multi-tenant | Edge compute | Wildcard SSL | Esfuerzo migración | Costo |
|-----------|---------------------------|-------------|-------------|-------------------|-------|
| **Netlify (actual)** | ~100 aliases/site, API | Edge Functions (Deno) | Pro ($19/mes) | — | $19/mes |
| **Cloudflare Pages + for SaaS** | **Ilimitados** (diseñado para SaaS) | Workers (V8) | Automático, incluido | Medio (4 workers + API adapter) | $5/mes (Pro) + $0.50/100k hostnames |
| **Vercel** | ~50 dominios/proyecto, API | Middleware (Node) | Automático | Medio (1 middleware + API adapter) | $20/mes (Pro) |
| **AWS CloudFront + ACM** | Ilimitados (manual) | Lambda@Edge / CloudFront Functions | ACM gratuito | Alto (infra compleja) | Variable |
| **Railway (unified)** | Manual (Caddy/nginx) | No nativo | Manual (certbot) | Alto | Ya pagando |

**Recomendación para NovaVision:**
- **Hoy:** Quedarse en Netlify. El acoplamiento es bajo y el límite de 100 custom domains alcanza para la fase de lanzamiento.
- **Cuando escale (>50 custom domains):** Evaluar **Cloudflare for SaaS** — diseñado exactamente para este caso de uso, con custom hostnames ilimitados y Workers para reemplazar las edge functions.
- **Para prepararse ahora:** Implementar la interfaz `DomainProviderService` y los documentos de este apéndice.

### G.5 Lo que tenés que poder reconstruir en 1 hora

Si mañana cerraras Netlify, deberías poder:

| Tarea | ¿Podés hoy? | ¿Qué falta? |
|-------|-------------|-------------|
| Levantar el frontend con el repo | ✅ `npm run build` → `dist/` | — |
| Cargar variables de entorno | ⚠️ | Crear `ENV_INVENTORY.md` |
| Apuntar DNS de `novavision.lat` | ✅ DNS en Namecheap | — |
| Servir `*.novavision.lat` (wildcard) | ⚠️ | Depende de que el nuevo host soporte wildcard |
| Servir custom domains de clientes | ❌ | Necesitás reescribir `netlify.service.ts` para el nuevo proveedor |
| OG tags para social bots | ❌ | Necesitás migrar `og-inject.ts` a middleware del nuevo host |
| Redirects SEO per-tenant | ❌ | Necesitás migrar `seo-redirects.ts` |
| Robots.txt dinámico | ❌ | Necesitás migrar `seo-robots.ts` |
| Maintenance page automática | ❌ | Necesitás migrar `maintenance.ts` |
| Security headers (CSP) | ⚠️ | Traducir `netlify.toml` headers a formato del nuevo host |

### G.6 Acciones inmediatas para portabilidad (hacer ahora)

| # | Acción | Esfuerzo | Prioridad |
|---|--------|----------|-----------|
| 1 | Crear `ENV_INVENTORY.md` con todas las env vars | 1h | Alta |
| 2 | Crear `ROUTING_RULES.md` con mapa de DNS y routing | 1h | Alta |
| 3 | Crear `CUSTOM_DOMAIN_CHECKLIST.md` operativo | 1h | Alta |
| 4 | Crear interfaz `DomainProviderService` abstracta | 2h | Media |
| 5 | Agregar `_redirects` al repo (`/* /index.html 200`) | 5 min | Alta |
| 6 | Documentar proceso de SSL en `SSL_PROCESS.md` | 30 min | Media |
| 7 | Agregar campo `redirect_to_primary` a `nv_accounts` | 1h | Baja (futuro) |

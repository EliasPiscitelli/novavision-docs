# Reglas de Routing y Resolucion de Tenant — NovaVision Platform

> Ultima actualizacion: 2026-03-16

Este documento describe como se resuelve el tenant (tienda) tanto en el storefront (Web) como en el backend (API), el setup de dominios custom via CNAME en Netlify, los estados de dominio y los crons de verificacion.

---

## 1. Web — Flujo de Resolucion de Tenant

El storefront resuelve el tenant en dos capas: primero en el cliente (`tenantResolver.js`) y luego confirmando contra la API.

### 1.1 Resolucion Client-Side (`tenantResolver.js`)

**Archivo**: `/apps/web/src/utils/tenantResolver.js`

La funcion `getStoreSlugFromHost(hostname)` sigue esta cascada de prioridad:

```
1. Query Param Override  (mayor prioridad)
   └─ ?tenant=store-a  o  ?slug=store-a
   └─ Solo para testing local

2. Env Override (desarrollo local)
   └─ Si hostname es localhost / 127.0.0.1 / ngrok
   └─ Usa import.meta.env.VITE_DEV_SLUG
   └─ Retorna null si no esta definida

3. Deteccion de Custom Domain
   └─ isLikelyCustomDomain(hostname) retorna true si:
      - NO es localhost / 127.0.0.1 / ngrok
      - NO termina en PLATFORM_DOMAIN (novavision.lat)
      - NO termina en netlify.app
      - Tiene al menos 2 partes (ej: mitienda.com)
   └─ Si es custom domain → retorna null
   └─ TenantProvider se encarga de resolver via API

4. Subdominio de Plataforma
   └─ Si hostname tiene >= 3 partes (ej: store-a.novavision.lat)
   └─ Extrae parts[0] como slug → "store-a"

5. Hostname no reconocido → retorna null
   └─ TenantProvider maneja el caso
```

### 1.2 Resolucion de Custom Domain via API

Cuando `getStoreSlugFromHost()` retorna `null` y `isLikelyCustomDomain()` retorna `true`, el `TenantProvider` hace una llamada al backend:

```
GET /tenant/resolve-host?domain=mitienda.com
```

Este endpoint es publico (no requiere auth ni tenant context). Retorna el slug de la tienda asociada al dominio custom, o un 404 si no existe.

### 1.3 API Client — Headers de Tenant

**Archivo**: `/apps/web/src/api/client.ts`

El `apiClient` (axios) agrega automaticamente headers segun el metodo de resolucion:

| Metodo de resolucion | Header enviado | Valor |
|---------------------|----------------|-------|
| Subdominio de plataforma | `X-Tenant-Slug` | El slug extraido (ej: `store-a`) |
| Custom domain | `X-Tenant-Host` | El hostname completo (ej: `mitienda.com`) |
| Query param (dev) | `X-Tenant-Slug` | El slug del query param |

La URL del API se resuelve asi:
- **Local**: `VITE_API_URL_LOCAL` o `http://localhost:3000`
- **Produccion**: `VITE_BACKEND_API_URL` → `VITE_BACKEND_URL` → `VITE_API_URL` → `https://api.{PLATFORM_DOMAIN}`

### 1.4 Constante de Plataforma

**Archivo**: `/apps/web/src/config/platform.js`

```js
export const PLATFORM_DOMAIN = import.meta.env.VITE_PLATFORM_DOMAIN || 'novavision.lat';
```

Esta constante es la fuente de verdad para separar subdominios de plataforma vs custom domains.

---

## 2. API — Flujo de Resolucion de Tenant (`TenantContextGuard`)

**Archivo**: `/apps/api/src/guards/tenant-context.guard.ts`

El guard se ejecuta en cada request protegido y resuelve `request.clientId` siguiendo esta cascada:

```
1. Header Slug (prioridad maxima)
   └─ x-tenant-slug  o  x-store-slug (compat)
   └─ Busca en nv_accounts por slug
   └─ Luego busca en clients por nv_account_id
   └─ Valida gateStorefront (activa, publicada, no mantenimiento, no eliminada)

2. [REMOVIDO por audit P0] Header x-client-id
   └─ Eliminado por riesgo de Identifier Leakage

3. Custom Domain (Host)
   └─ Lee x-forwarded-host → host → x-tenant-host (solo dev)
   └─ Normaliza hostname (split por coma, quita puerto, lowercase)
   └─ Si NO termina en PLATFORM_DOMAIN:
      └─ Genera candidatos: [hostname, sin-www] o [hostname, con-www]
      └─ Busca en nv_accounts.custom_domain con IN (candidatos)
      └─ Resuelve clients por nv_account_id

4. Subdominio del Host
   └─ Extrae slug del host (ej: tienda1.novavision.lat → tienda1)
   └─ Filtra subdominios reservados: admin, api, app, www, novavision,
      localhost, build, novavision-production
   └─ Valida formato: solo [a-z0-9-]
   └─ Busca en nv_accounts y luego en clients

5. [REMOVIDO por audit P0] Extraer de request.user

6. Sin tenant resuelto
   └─ Si la ruta tiene @AllowNoTenant() → permite
   └─ Si no → 401 "Se requiere client_id"
```

### 2.1 Cadena de Resolucion Account → Client

Cada resolucion sigue el mismo patron de dos pasos:

```
nv_accounts (Admin DB)          clients (Backend DB)
┌──────────────────┐           ┌──────────────────────┐
│ id               │──────────>│ nv_account_id        │
│ slug             │           │ id (= clientId)      │
│ backend_cluster_id│           │ is_active            │
│ custom_domain    │           │ publication_status   │
│ custom_domain_status│        │ maintenance_mode     │
└──────────────────┘           │ deleted_at           │
                               └──────────────────────┘
```

### 2.2 Gate Storefront — Validaciones

Antes de inyectar el `clientId`, el guard valida:

| Condicion | Codigo HTTP | Codigo de Error |
|-----------|-------------|----------------|
| `deleted_at` presente | 401 | `STORE_NOT_FOUND` |
| `is_active === false` | 403 | `STORE_SUSPENDED` |
| `maintenance_mode === true` | 403 | `STORE_MAINTENANCE` |
| `publication_status !== 'published'` | 403 | `STORE_NOT_PUBLISHED` |

### 2.3 Inyeccion en el Request

Una vez resuelto, el guard inyecta:

```typescript
request.clientId = clientId;
request.tenant = { clientId, slug };
request.requestId = 'req-...' // generado o del header x-request-id
```

### 2.4 Endpoint de Resolucion de Host

**`GET /tenant/resolve-host?domain=mitienda.com`**

- Decorado con `@AllowNoTenant()` — no requiere context
- Solo retorna el slug publico, sin datos sensibles
- Retorna 404 con codigo `DOMAIN_NOT_FOUND` si no existe match

---

## 3. Setup de CNAME — Dominios Custom en Netlify

### 3.1 Arquitectura

El storefront se deploya en **Netlify** como un sitio unico. Todos los tenants comparten el mismo deploy. La resolucion del tenant se hace en runtime via el hostname.

### 3.2 Configuracion DNS Requerida

Para que un dominio custom (ej: `mitienda.com`) apunte al storefront:

| Tipo | Nombre | Valor | Proposito |
|------|--------|-------|-----------|
| `CNAME` | `@` (apex) | `novavision-test.netlify.app` | Dominio raiz |
| `CNAME` | `www` | `novavision-test.netlify.app` | Alias www |

> **Nota**: Algunos registrars no soportan CNAME en apex. En esos casos se usa ALIAS o ANAME record, o el registrar implementa CNAME flattening.

### 3.3 Configuracion en Netlify (via API)

El `NetlifyService` (`/apps/api/src/admin/netlify.service.ts`) gestiona los dominios via la API de Netlify:

1. **Agregar dominio**: `PATCH /sites/{siteId}` con `custom_domain` y/o `domain_aliases`
2. **Remover dominio**: `PATCH /sites/{siteId}` filtrando el dominio de aliases
3. **Verificar estado**: `GET /sites/{siteId}` y checar `ssl.status`
4. **Force SSL**: Siempre habilitado (`force_ssl: true`)

El `siteId` se resuelve desde `NETLIFY_STOREFRONT_SITE_ID` (o fallback `NETLIFY_SITE_ID`).

### 3.4 Flujo de Alta de Custom Domain

```
1. Admin/Super Admin configura custom_domain para una cuenta
2. AdminService.setCustomDomain() actualiza nv_accounts:
   - custom_domain = 'mitienda.com'
   - custom_domain_status = 'pending_dns'
3. NetlifyService.updateSiteDomains() agrega el dominio + www como aliases
4. Netlify intenta aprovisionar SSL automaticamente
5. Cron custom-domain-verifier (cada 10 min) verifica el DNS
6. Cuando SSL esta activo → custom_domain_status = 'active'
```

---

## 4. Diagrama de Estados de Dominio

Los estados se almacenan en `nv_accounts.custom_domain_status`:

```
                    ┌──────────────────┐
                    │                  │
                    │     none         │  (sin dominio custom)
                    │                  │
                    └────────┬─────────┘
                             │
                     Admin setCustomDomain()
                             │
                             v
                    ┌──────────────────┐
                    │                  │
                    │  pending_dns     │  (esperando propagacion DNS + SSL)
                    │                  │
                    └────────┬─────────┘
                             │
                    Cron verifica DNS/SSL
                             │
                     ┌───────┴────────┐
                     │                │
                     v                v
            ┌──────────────┐  ┌──────────────┐
            │              │  │              │
            │   active     │  │    error     │
            │              │  │              │
            └──────┬───────┘  └──────┬───────┘
                   │                 │
                   │   Admin resetea │
                   │   o corrige DNS │
                   │                 │
                   │                 v
                   │        ┌──────────────────┐
                   │        │  pending_dns     │ (reintento)
                   │        └──────────────────┘
                   │
                   │  Admin remueve dominio
                   v
            ┌──────────────┐
            │    none      │
            └──────────────┘
```

### Transiciones validas:

| Desde | Hacia | Trigger |
|-------|-------|---------|
| `none` | `pending_dns` | Admin configura custom domain |
| `pending_dns` | `active` | Cron verifica DNS + SSL exitoso |
| `pending_dns` | `error` | Cron detecta fallo de DNS/SSL |
| `error` | `pending_dns` | Admin resetea DNS |
| `active` | `none` | Admin remueve dominio custom |
| `error` | `none` | Admin remueve dominio custom |

---

## 5. Crons de Verificacion de Dominios

### 5.1 `custom-domain-verifier` — Cada 10 minutos

**Archivo**: `/apps/api/src/cron/custom-domain-verifier.cron.ts`

| Propiedad | Valor |
|-----------|-------|
| Schedule | `CronExpression.EVERY_10_MINUTES` |
| Servicio | `AdminService.verifyPendingCustomDomains(100)` |
| Batch size | Hasta 100 dominios por ejecucion |

**Que hace**:
- Busca cuentas con `custom_domain_status = 'pending_dns'` en la Admin DB
- Para cada dominio, consulta la API de Netlify para verificar si el SSL esta activo
- Si SSL esta `active` / `issued` / `ready` → cambia estado a `active`
- Si falla → cambia estado a `error`
- Loguea un resumen JSON con `processed`, `verified`, `errors` y `durationMs`

**Output de ejemplo**:
```json
{
  "cron": "custom_domain_verifier",
  "processed": 5,
  "verified": 3,
  "errors": 2,
  "durationMs": 4521
}
```

### 5.2 `check_domain_expirations` — Diario a las 00:00 ART

**Archivo**: `/apps/api/src/admin/managed-domain.cron.ts`

| Propiedad | Valor |
|-----------|-------|
| Schedule | `0 0 0 * * *` (medianoche) |
| Timezone | `America/Argentina/Buenos_Aires` |
| Servicio | `ManagedDomainService.checkExpirations()` |

**Que hace**:
- Busca dominios gestionados (`managed_domains`) que expiran en los proximos 30 dias
- Filtra solo los que tienen `renewal_state = 'none'` (aun no cotizados)
- Para cada dominio, genera un quote de renovacion (`quoteRenewal()`):
  - Consulta precio de renovacion via Namecheap API
  - Calcula fee de gestion (10% del costo, min $3 USD, max $10 USD)
  - Obtiene tasa de cambio blue dollar actual
  - Congela todo en un snapshot (`managed_domain_renewals`)
- Actualiza `renewal_state` a `due_soon` (o `manual_required` si Namecheap falla)
- Loguea resumen con `processed`, `quoted`, `errors` y `durationMs`

**Output de ejemplo**:
```json
{
  "cron": "check_domain_expirations",
  "processed": 2,
  "quoted": 2,
  "errors": 0,
  "durationMs": 8932
}
```

### 5.3 `check_pending_dns` — Cada 6 horas

**Archivo**: `/apps/api/src/admin/managed-domain.cron.ts`

| Propiedad | Valor |
|-----------|-------|
| Schedule | `0 0 */6 * * *` (cada 6h) |
| Timezone | `America/Argentina/Buenos_Aires` |
| Servicio | `ManagedDomainService.checkPendingDns()` |

**Que hace**:
- Busca cuentas en `nv_accounts` con `custom_domain_status = 'pending_dns'` y `custom_domain IS NOT NULL`
- Para cada cuenta, ejecuta `AdminService.verifyCustomDomain(accountId)`
- Clasifica resultados en `verified` (paso a active) y `stillPending`
- Complementa al cron de 10 minutos como safety net con ventana mas amplia

**Output de ejemplo**:
```json
{
  "cron": "check_pending_dns",
  "processed": 3,
  "verified": 1,
  "stillPending": 2,
  "errors": 0,
  "durationMs": 6210
}
```

### 5.4 Resumen de Crons

| Cron | Frecuencia | Modulo | Responsabilidad |
|------|-----------|--------|----------------|
| `custom-domain-verifier` | Cada 10 min | CronModule | Verificar DNS/SSL pendientes via Netlify API |
| `check_domain_expirations` | Diario 00:00 ART | ManagedDomainCron | Generar quotes de renovacion para dominios proximos a expirar |
| `check_pending_dns` | Cada 6h | ManagedDomainCron | Safety net para DNS pendientes (complementa al de 10 min) |

---

## 6. Diagrama de Flujo Completo — Request de un Comprador

```
Comprador visita store-a.novavision.lat
           │
           v
┌─────────────────────────────────┐
│   Browser (Web Storefront)      │
│                                 │
│  tenantResolver.js              │
│  getStoreSlugFromHost()         │
│  → hostname = store-a.novavision.lat
│  → parts.length >= 3            │
│  → slug = "store-a"             │
└──────────────┬──────────────────┘
               │
    apiClient interceptor
    agrega: X-Tenant-Slug: store-a
               │
               v
┌─────────────────────────────────┐
│   API NestJS                    │
│                                 │
│  TenantContextGuard             │
│  1. Lee x-tenant-slug = store-a │
│  2. nv_accounts.slug = store-a  │
│     → account.id, cluster_id   │
│  3. clients.nv_account_id =    │
│     account.id → client.id     │
│  4. gateStorefront() ✓          │
│  5. request.clientId = client.id│
└──────────────┬──────────────────┘
               │
               v
         Controller usa
         request.clientId
         para queries
         scopeados por tenant
```

```
Comprador visita mitienda.com (custom domain)
           │
           v
┌─────────────────────────────────┐
│   Browser (Web Storefront)      │
│                                 │
│  tenantResolver.js              │
│  getStoreSlugFromHost()         │
│  → isLikelyCustomDomain() = true
│  → retorna null                 │
│                                 │
│  TenantProvider                 │
│  GET /tenant/resolve-host       │
│      ?domain=mitienda.com       │
│  → slug = "store-a"             │
└──────────────┬──────────────────┘
               │
    apiClient interceptor
    agrega: X-Tenant-Slug: store-a
    (o X-Tenant-Host: mitienda.com)
               │
               v
┌─────────────────────────────────┐
│   API NestJS                    │
│                                 │
│  TenantContextGuard             │
│  → Resuelve por slug o host    │
│  → Mismo flujo account→client  │
└─────────────────────────────────┘
```

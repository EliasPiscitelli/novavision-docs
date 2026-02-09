# Guía: Configurar `{slug}.novavision.lat` — Wildcard Subdomains

**Fecha:** 2026-02-09  
**Estado:** Lista para ejecutar  
**Requisito:** Netlify Pro ($19/mes por miembro)

---

## Resumen

Esta guía cubre el paso a paso para habilitar que cada tienda se acceda como `https://{slug}.novavision.lat`, manteniendo `https://novavision.lat` para el admin/home/onboarding.

**Arquitectura final:**

```
Site 1 (Admin/Home) → novavision.lat
                       www.novavision.lat

Site 2 (Storefront) → *.novavision.lat  (wildcard)
                       + domain aliases para dominios custom de clientes
```

**¿Qué ya está listo en el código?**

| Componente | Estado |
|---|---|
| Frontend: `tenantResolver.js` extrae slug del subdomain | ✅ Listo |
| Axios: inyecta `x-tenant-slug` por request | ✅ Listo |
| Backend: `TenantContextGuard.extractSlugFromHost()` | ✅ Listo |
| Backend: `NetlifyService` (API Netlify para custom domains) | ✅ Listo |
| Backend: CORS acepta `*.novavision.lat` | ✅ Listo |
| Admin: Muestra URL `{slug}.novavision.lat` al owner | ✅ Listo |

**No se necesitan cambios de código.** Solo configuración de DNS + Netlify.

---

## Pre-requisitos

- [ ] Acceso al panel de Namecheap (DNS de `novavision.lat`)
- [ ] Acceso al dashboard de Netlify (ambos sites)
- [ ] Cuenta Netlify Pro activa (o activar en el proceso)
- [ ] API key de Netlify configurada en Railway como `NETLIFY_API_TOKEN`
- [ ] Site ID del storefront configurado como `NETLIFY_STOREFRONT_SITE_ID`

---

## Paso 1: Identificar tus sites de Netlify

Antes de empezar, confirmá los nombres de tus sites:

| Propósito | Site Netlify (probable) | Dominio actual |
|---|---|---|
| Admin / Home / Onboarding | `novavision` (repo: novavision) | `novavision.lat` |
| Storefront Multi-tenant | `novavision-test` o `visiontemplate` (repo: templatetwo) | Sin dominio custom aún |

**Cómo obtener el Site ID del storefront:**

1. Entrá a [app.netlify.com](https://app.netlify.com)
2. Seleccioná el site del storefront
3. Andá a **Site configuration** → **General** → **Site ID**
4. Copiá el ID (formato: `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx`)

Este ID es el que va en `NETLIFY_STOREFRONT_SITE_ID` en Railway.

---

## Paso 2: Upgrade a Netlify Pro

1. En [app.netlify.com](https://app.netlify.com), andá a **Team settings** → **Billing**
2. Cambiá a **Pro** ($19/mes por miembro)
3. Confirmá el pago

> **Nota:** El wildcard SSL solo se habilita en Pro+. Sin esto, los subdominios no van a tener HTTPS.

---

## Paso 3: Configurar el dominio en el site del Storefront

### 3.1 Agregar dominio custom al site del storefront

1. En Netlify, entrá al **site del storefront** (templatetwo)
2. Andá a **Domain management** → **Add a domain**
3. Agregá: `novavision.lat` como dominio (Netlify te va a pedir verificar ownership)

> **Espera:** ¿Pero `novavision.lat` no está en el site del Admin?
> 
> **Sí, y es clave entender esto:**
> - El **apex** (`novavision.lat`) queda en el site del Admin
> - Solo necesitás que el **wildcard** (`*.novavision.lat`) apunte al site del Storefront
> - **NO agregues `novavision.lat`** al storefront — solo los subdominios

### 3.2 Habilitar wildcard subdomain

1. En el site del storefront, andá a **Domain management**
2. Buscá la opción de **Wildcard domain** o contactá soporte Netlify:
   - En Pro, **a veces hay que pedirlo por soporte** (chat o form)
   - Escribí: *"I need wildcard subdomain support for `*.novavision.lat` on site [tu-site-id]"*
3. Una vez habilitado, Netlify mostrará `*.novavision.lat` como dominio del site

> **Importante:** Netlify no siempre habilita wildcard automáticamente en Pro. Si no aparece la opción, contactá soporte desde el dashboard. Suelen responder en menos de 24hs.

---

## Paso 4: Configurar DNS en Namecheap

Entrá a [namecheap.com](https://www.namecheap.com) → **Domain List** → `novavision.lat` → **Advanced DNS**

### 4.1 Registros que ya deberías tener (Admin/Home)

| Type | Host | Value | TTL |
|---|---|---|---|
| A / ALIAS | `@` | IP de Netlify del site Admin (o `apex-loadbalancer.netlify.com`) | Auto |
| CNAME | `www` | `[site-admin].netlify.app` | Auto |

### 4.2 Agregar registro wildcard para el Storefront

| Type | Host | Value | TTL |
|---|---|---|---|
| **CNAME** | `*` | `[site-storefront].netlify.app` | Auto |

**Ejemplo concreto:**

```
Type:   CNAME
Host:   *
Value:  novavision-test.netlify.app    ← reemplazá con tu site name real
TTL:    Automatic
```

> **Nota sobre el apex (`@`):** No borres el registro A/ALIAS del apex. El wildcard (`*`) captura todos los subdominios que no tengan un registro explícito. El apex (`novavision.lat`) sigue apuntando a tu site del Admin.

### 4.3 Registros que **NO** debés tocar

- `@` (apex) → sigue apuntando al site del Admin
- `www` → sigue apuntando al site del Admin
- `api` → si tenés un CNAME para la API en Railway, dejalo

### 4.4 Resultado esperado de DNS

```
novavision.lat          →  Site Admin (home/onboarding)
www.novavision.lat      →  Site Admin
api.novavision.lat      →  Railway (API NestJS)
*.novavision.lat        →  Site Storefront (wildcard)
  └─ mi-tienda.novavision.lat   → Storefront resuelve tenant "mi-tienda"
  └─ otra-tienda.novavision.lat → Storefront resuelve tenant "otra-tienda"
```

---

## Paso 5: Verificar SSL wildcard en Netlify

1. Esperá ~5-15 minutos después de configurar DNS
2. En Netlify → site del storefront → **Domain management** → **HTTPS**
3. Verificá que diga **"Certificate: Active"** o **"Let's Encrypt Wildcard"**
4. Si no se provisiona automáticamente:
   - Click en **"Verify DNS configuration"**
   - Si falla, verificá que el CNAME `*` apunte correctamente
   - Click en **"Provision certificate"**

---

## Paso 6: Configurar variables de entorno en Railway (API)

En el dashboard de Railway → servicio de la API → **Variables**:

```env
# Site ID del storefront en Netlify (para custom domains via API)
NETLIFY_STOREFRONT_SITE_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx

# Token de API de Netlify (para gestionar domain aliases)
NETLIFY_API_TOKEN=nfp_xxxxxxxxxxxxxxxxxxxxxxxxxxxx

# URLs base (actualizar si no están)
ADMIN_URL=https://novavision.lat
STORES_URL=https://novavision.lat
```

### Cómo obtener el `NETLIFY_API_TOKEN`:

1. En Netlify → **User settings** (ícono de usuario arriba a la derecha)
2. **Applications** → **Personal access tokens**
3. **New access token** → nombre: `novavision-api` → copiar token
4. Pegarlo en Railway como `NETLIFY_API_TOKEN`

---

## Paso 7: Verificación completa

### 7.1 Test DNS (desde terminal)

```bash
# Verificar que el wildcard resuelve
dig mi-tienda.novavision.lat CNAME +short
# Debería devolver: novavision-test.netlify.app (o tu site name)

# Verificar que el apex sigue en el admin
dig novavision.lat A +short
# Debería devolver la IP del site admin
```

### 7.2 Test HTTP (storefront)

```bash
# Probar con un slug que exista en tu sistema
curl -sI https://mi-tienda.novavision.lat | head -20

# Debería devolver 200 OK (si la tienda existe y está publicada)
# o un 401/403 del TenantContextGuard (si no existe o no está publicada)
```

### 7.3 Test desde browser

1. Abrí `https://{slug-real}.novavision.lat` (usá un slug de una tienda provisionada)
2. Verificá que:
   - Carga el storefront
   - Muestra los productos correctos del tenant
   - El logo y theme son los del cliente
3. Abrí `https://novavision.lat`
4. Verificá que:
   - Sigue cargando el Admin/Home
   - No se rompe el onboarding

### 7.4 Test de aislamiento

```bash
# Slug que NO existe → debe dar error/404
curl -s https://slug-inexistente.novavision.lat | head -5

# Subdominios reservados → deben ser ignorados
curl -sI https://admin.novavision.lat | head -5
curl -sI https://api.novavision.lat | head -5
```

---

## Paso 8: Dominios custom de clientes (ya implementado)

Una vez que el wildcard funciona, los dominios custom de clientes (`mitienda.com`) **ya están cubiertos** por tu código existente:

1. Admin llama `setCustomDomain(accountId, 'mitienda.com')`
2. `NetlifyService.updateSiteDomains()` agrega `mitienda.com` como domain alias en Netlify
3. `nv_accounts.custom_domain_status` queda en `pending_dns`
4. El CRON de DNS verifica cada 6h → pasa a `active` cuando el SSL está OK
5. `TenantContextGuard` resuelve por `x-forwarded-host` → busca en `nv_accounts.custom_domain`

**Límite:** Netlify permite hasta ~100 domain aliases por site. Si llegás a escalar más allá de eso, se puede splitear en múltiples sites.

---

## Troubleshooting

### "El subdomain carga pero da CORS error"

Tu API ya acepta `*.novavision.lat` en [main.ts](apps/api/src/main.ts#L80):

```typescript
if (/^https:\/\/.*\.novavision\.lat$/.test(normalized)) return true;
```

Si da CORS, verificá:
- Que la URL en el browser sea `https` (no `http`)
- Que la API esté corriendo correctamente
- Que no haya un proxy/CDN intermedio agregando headers

### "El SSL wildcard no se provisiona"

1. Verificá que el plan sea Pro o superior
2. Asegurate que el CNAME `*` en Namecheap apunte exactamente al site de Netlify
3. Esperá hasta 1 hora (Let's Encrypt a veces tarda)
4. En Netlify → HTTPS → "Renew certificate"

### "El subdomain carga el Admin en vez del Storefront"

Esto pasa si el CNAME wildcard apunta al site equivocado. Verificá:
```bash
dig mi-tienda.novavision.lat CNAME +short
# Debe apuntar al site del STOREFRONT, no al del Admin
```

### "Las tiendas cargan pero sin datos"

Verificá que la API esté recibiendo el header `x-tenant-slug`:
1. Abrí DevTools → Network
2. Buscá cualquier request a la API
3. Verificá que tenga `x-tenant-slug: {slug}` en los headers

---

## Checklist final

- [ ] Netlify Pro activado
- [ ] Wildcard habilitado en el site del storefront (puede requerir contactar soporte)
- [ ] CNAME `*` configurado en Namecheap → `[storefront-site].netlify.app`
- [ ] SSL wildcard activo en Netlify
- [ ] `NETLIFY_STOREFRONT_SITE_ID` configurado en Railway
- [ ] `NETLIFY_API_TOKEN` configurado en Railway
- [ ] Test: `https://{slug-real}.novavision.lat` carga la tienda correcta
- [ ] Test: `https://novavision.lat` sigue cargando el Admin/Home
- [ ] Test: `https://api.novavision.lat` (si aplica) sigue funcionando
- [ ] Test: slug inexistente devuelve error apropiado
- [ ] Test: custom domain de cliente sigue funcionando (si ya había alguno)

---

## Costos

| Concepto | Costo | Frecuencia |
|---|---|---|
| Netlify Pro | $19 USD/mes por miembro | Mensual |
| SSL Wildcard | Incluido en Pro (Let's Encrypt) | Automático |
| DNS en Namecheap | Incluido en el dominio | Anual (renovación dominio) |
| Domain aliases (custom domains de clientes) | Incluido en Pro | Sin costo extra |

---

## Diagrama final

```
                         ┌─────────────────────┐
                         │     Namecheap DNS    │
                         │   novavision.lat     │
                         └──────┬──────────────┘
                                │
                ┌───────────────┼───────────────┐
                │               │               │
                ▼               ▼               ▼
          @ (apex)         * (wildcard)    api (CNAME)
          www (CNAME)                           │
                │               │               │
                ▼               ▼               ▼
        ┌──────────────┐ ┌──────────────┐ ┌──────────────┐
        │  Netlify      │ │  Netlify      │ │  Railway     │
        │  Site: Admin  │ │  Site: Store  │ │  NestJS API  │
        │               │ │               │ │              │
        │ novavision.lat│ │*.novavision.lat│ │api.novavision│
        │               │ │               │ │   .lat       │
        │ Home          │ │ Multi-tenant  │ │              │
        │ Onboarding    │ │ Storefront    │ │ Auth         │
        │ Super Admin   │ │               │ │ Products     │
        │               │ │ + aliases:    │ │ Orders       │
        │               │ │ mitienda.com  │ │ Payments     │
        └──────────────┘ │ otratienda.com│ │ Webhooks     │
                         └──────────────┘ └──────────────┘
```

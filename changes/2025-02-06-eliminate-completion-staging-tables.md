# Eliminación de tablas `completion_*` — Migración a `nv_onboarding.progress` JSON

- **Autor:** agente-copilot
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `apps/api/src/admin/admin.service.ts`
  - `apps/api/src/client-dashboard/client-dashboard.service.ts`

---

## Contexto: ¿Por qué existían las tablas `completion_*`?

Originalmente se crearon 5 tablas "staging" en la **admin DB** para almacenar datos del onboarding del cliente antes de publicar:

| Tabla (ELIMINADA) | Propósito original |
|---|---|
| `completion_products` | Productos cargados durante onboarding |
| `completion_categories` | Categorías cargadas durante onboarding |
| `completion_faqs` | FAQs cargadas durante onboarding |
| `completion_contact_info` | Info de contacto del onboarding |
| `completion_social_links` | Redes sociales del onboarding |

Estas tablas fueron **dropeadas** por la migración:
```
migrations/admin/20260205_drop_completion_staging_tables.sql
```

## ¿Por qué se eliminaron?

Porque **duplicaban información** que ya vivía en `nv_onboarding.progress` (columna JSONB).
El campo `progress` del onboarding ya contiene toda la data del wizard, incluyendo:

```jsonc
{
  "catalog_data": {
    "products": [...],      // ← antes en completion_products
    "categories": [...],    // ← antes en completion_categories
    "faqs": [...],          // ← antes en completion_faqs
    "services": [...],      // ← no tenía tabla, siempre vivió acá
    "socialLinks": {...}    // ← antes en completion_social_links
  },
  "contact_info": {...},    // ← antes en completion_contact_info
  "wizard_assets": {
    "logo_url": "..."
  },
  // ... más campos del wizard
}
```

Mantener dos fuentes de verdad generaba inconsistencias y errores de sincronización.

---

## Regla fundamental del ciclo de vida de datos

```
┌─────────────────────────────────────────────────────────────────┐
│ ANTES de publicar (client_id = null, provisioned_at = null):    │
│                                                                  │
│   TODO vive en: nv_onboarding.progress (admin DB, JSONB)        │
│   - Productos, categorías, FAQs, servicios, contacto, social   │
│   - Se lee y escribe con getOnboardingProgress / update JSON    │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ AL publicar (provisioning):                                      │
│                                                                  │
│   onboarding-migration.helper.ts copia datos del JSON a las    │
│   tablas reales de la multicliente DB:                          │
│   - products, categories, faqs, services, social_links, etc.   │
│   - Se asigna client_id en nv_onboarding                        │
│                                                                  │
├─────────────────────────────────────────────────────────────────┤
│ DESPUÉS de publicar (client_id != null):                         │
│                                                                  │
│   Datos viven en: multicliente DB (backendSupabase)             │
│   - products → backendSupabase.from('products').eq('client_id') │
│   - faqs → backendSupabase.from('faqs').eq('client_id')         │
│   - categories → backendSupabase.from('categories').eq(...)     │
│   - services → backendSupabase.from('services').eq(...)         │
│                                                                  │
│   El progress JSON sigue existiendo pero ya NO es fuente de     │
│   verdad para datos migrados.                                   │
└─────────────────────────────────────────────────────────────────┘
```

---

## Cómo determinar si una cuenta está provisionada

```typescript
const { adminSupabase, backendSupabase, clientId } =
  await this.resolveBackendClientForAccount(accountId);

if (clientId) {
  // PROVISIONADA → usar backendSupabase (multicliente DB)
} else {
  // NO PROVISIONADA → usar progress JSON (admin DB)
}
```

`resolveBackendClientForAccount` busca en `clients.nv_account_id` en la multicliente DB.
Si encuentra un `client`, devuelve su `id` como `clientId`. Si no, devuelve `null`.

---

## Cambios aplicados

### 1. `admin.service.ts` — CRUD de FAQs del super admin

#### `getAccountFaqs(accountId)`
- **Antes:** Provisionado → `adminSupabase.from('completion_faqs')` ❌ (tabla no existe)
- **Ahora:** Provisionado → `backendSupabase.from('faqs').eq('client_id', clientId)` ✅
- **No provisionado:** Sin cambios → lee de `progress.catalog_data.faqs`

#### `createAccountFaq(accountId, question, answer)`
- **Antes:** Provisionado → insert en `completion_faqs` ❌
- **Ahora:** Provisionado → insert en `backendSupabase.from('faqs')` con `number` calculado ✅

#### `deleteAccountFaq(accountId, faqId)`
- **Antes:** Provisionado → delete de `completion_faqs` ❌
- **Ahora:** Provisionado → delete de `backendSupabase.from('faqs').eq('client_id', clientId)` ✅

#### `getApprovalDetail(accountId)` — conteos del checklist
- **Antes:** Leía counts de `completion_products`, `completion_contact_info`, `completion_social_links` ❌
- **Ahora:**
  - Products: provisionado → `backendSupabase.from('products')`, fallback → `progress.catalog_data.products`
  - Categories: siempre → `progress.catalog_data.categories` (son strings, no tabla dedicada)
  - FAQs: provisionado → `backendSupabase.from('faqs')`, fallback → `progress.catalog_data.faqs`
  - Contact: → `progress.contact_info`
  - Social: → `progress.catalog_data.socialLinks`

#### `refreshCompletionChecklist()` — FAQs count
- **Antes:** Provisionado → contaba de `adminSupabase.from('completion_faqs')` ❌
- **Ahora:** Provisionado → `backendSupabase.from('faqs').eq('client_id', clientId)` ✅

### 2. `client-dashboard.service.ts` — Dashboard del dueño de tienda

Este servicio es usado por el **cliente** (dueño de tienda) durante el onboarding,
cuando la tienda aún NO está provisionada. Por lo tanto, TODO lee/escribe del progress JSON.

#### `getChecklist(accountId)` — conteos dinámicos
- **Antes:** 6 queries paralelas a tablas `completion_*` ❌
- **Ahora:** Lee `nv_onboarding.progress` una vez y extrae conteos del JSON ✅

#### `saveProducts/saveCategories/saveFAQs`
- **Antes:** Delete + insert en tablas `completion_*` ❌
- **Ahora:** Actualiza `progress.catalog_data.*` en `nv_onboarding` ✅

#### `getCatalogProducts/getCatalogCategories/getCatalogFaqs`
- **Antes:** Select de tablas `completion_*` ❌
- **Ahora:** Lee de `progress.catalog_data.*` ✅

#### `getContactInfo/getSocialLinks`
- **Antes:** Select de `completion_contact_info` / `completion_social_links` ❌
- **Ahora:** Lee de `progress.contact_info` / `progress.catalog_data.socialLinks` ✅

#### `saveContactInfo/saveSocialLinks`
- **Antes:** Delete + upsert en tablas `completion_*` ❌
- **Ahora:** Actualiza progress JSON ✅

#### `importJson(accountId, payload)`
- **Antes:** Leía existentes de tablas `completion_*` ❌
- **Ahora:** Lee existentes del progress JSON ✅

---

## Errores que otro agente NO debe cometer

### ❌ Nunca crear/referenciar tablas `completion_*`
```
completion_products     ← ELIMINADA, NO EXISTE
completion_categories   ← ELIMINADA, NO EXISTE
completion_faqs         ← ELIMINADA, NO EXISTE
completion_contact_info ← ELIMINADA, NO EXISTE
completion_social_links ← ELIMINADA, NO EXISTE
```
La migración `20260205_drop_completion_staging_tables.sql` las eliminó permanentemente.

### ❌ Nunca usar `adminSupabase` para leer FAQs/products de tiendas provisionadas
Las tablas `faqs`, `products`, `categories`, `services` están en la **multicliente DB** (`backendSupabase`), no en admin.

### ❌ Nunca asumir que los datos del onboarding están en tablas separadas
Todo el onboarding pre-publicación vive en una sola columna JSONB: `nv_onboarding.progress`.

### ✅ Patrón correcto para CRUD híbrido (admin panel)
```typescript
async getAccountXxx(accountId: string) {
  const { adminSupabase, backendSupabase, clientId } =
    await this.resolveBackendClientForAccount(accountId);

  if (clientId) {
    // PROVISIONADA → leer de multicliente
    return backendSupabase.from('xxx').select('*').eq('client_id', clientId);
  }

  // NO PROVISIONADA → leer de progress JSON
  const result = await this.getOnboardingProgress(adminSupabase, accountId);
  return result?.progress?.catalog_data?.xxx || [];
}
```

### ✅ Patrón correcto para client-dashboard (dueño de tienda, pre-publicación)
```typescript
// Siempre lee/escribe de progress JSON — la tienda NO está provisionada aún
const progress = await this.getOnboardingProgress(accountId);
const products = progress.catalog_data?.products || [];
```

---

## Estructura de `progress.catalog_data` esperada

```jsonc
{
  "catalog_data": {
    "products": [
      {
        "name": "string",
        "price": 1234,
        "description": "string",
        "category": "string | null",
        "image_url": "string | null",
        "stock": 0,
        "is_active": true
      }
    ],
    "categories": ["General", "Combos"],  // Array de strings
    "faqs": [
      {
        "question": "string",
        "answer": "string",
        "number": 1
      }
    ],
    "services": [
      {
        "title": "string",
        "description": "string",
        "number": 1
      }
    ],
    "socialLinks": {
      "whatsApp": "1122334455",
      "wspText": "Hola!",
      "instagram": null,
      "facebook": null
    }
  },
  "contact_info": {
    "email": "string | null",
    "phone": "string | null",
    "whatsapp": "string | null",
    "address": "string | null"
  }
}
```

## Tablas multicliente (post-publicación)

| Tabla | Columnas clave | Filtro |
|---|---|---|
| `faqs` | `id`, `question`, `answer`, `number`, `client_id` | `.eq('client_id', clientId)` |
| `products` | `id`, `name`, `price`, `description`, `stock`, `client_id` | `.eq('client_id', clientId)` |
| `categories` | `id`, `name`, `description`, `client_id` | `.eq('client_id', clientId)` |
| `services` | `id`, `title`, `description`, `client_id` | `.eq('client_id', clientId)` |

---

## Cómo validar

1. Build: `npm run build` en `apps/api/` — debe pasar con 0 errores
2. Verificar que no queden refs: `grep -r "completion_faqs\|completion_products\|completion_categories\|completion_contact_info\|completion_social_links" src/`
3. Probar endpoint: `GET /admin/accounts/{id}/faqs` — debe devolver FAQs del progress JSON para cuentas no provisionadas

# SEO AI – Guía Completa

> Última actualización: 2025-07-15 · Aplica a API v1.x + Web storefront

## Índice

1. [Visión general](#1-visión-general)
2. [Arquitectura](#2-arquitectura)
3. [Endpoints](#3-endpoints)
4. [Modelo de datos](#4-modelo-de-datos)
5. [Worker de generación](#5-worker-de-generación)
6. [Billing (créditos)](#6-billing-créditos)
7. [Auditoría gratuita](#7-auditoría-gratuita)
8. [Prompt copiable](#8-prompt-copiable)
9. [SERP Preview](#9-serp-preview)
10. [Seguridad](#10-seguridad)
11. [Configuración](#11-configuración)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Visión general

El módulo SEO AI permite a los clientes de NovaVision:

- **Auditar** el estado SEO de sus productos y categorías (gratuito)
- **Generar** automáticamente meta titles y descriptions con IA (consume créditos)
- **Copiar un prompt** optimizado para usar en ChatGPT/Claude (gratuito)
- **Previsualizar** cómo se verán sus páginas en Google (SERP preview)

### Planes y acceso

| Feature | Free audit | Prompt copiable | AI generation |
|---------|-----------|-----------------|---------------|
| Todos los planes | ✅ | ✅ | Requiere créditos |

Los créditos se compran como add-ons vía Mercado Pago.

---

## 2. Arquitectura

```
┌─────────────────┐     ┌──────────────────────┐
│  Web Storefront  │────▶│   API (NestJS)        │
│  (React + Vite)  │     │                        │
│                  │     │  SeoAiController       │
│  - Audit tab     │     │  SeoAiService (OpenAI) │
│  - Prompt tab    │     │  SeoAiJobService       │
│  - Credits tab   │     │  SeoAiWorkerService    │
│  - Jobs tab      │     │  SeoAiBillingService   │
└─────────────────┘     └───────┬──────────────┘
                                │
                    ┌───────────┼───────────┐
                    ▼           ▼           ▼
              ┌──────────┐ ┌────────┐ ┌──────────┐
              │ Supabase │ │ OpenAI │ │ Mercado  │
              │ (Multi)  │ │ API    │ │ Pago     │
              │          │ │ gpt-4o │ │          │
              │ products │ │ -mini  │ │ checkout │
              │ categor. │ └────────┘ └──────────┘
              │ seo_ai_* │
              └──────────┘
```

### Módulos NestJS

- **SeoAiModule**: Controller + Service + JobService + WorkerService
- **SeoAiBillingModule**: BillingService + PurchaseController + AdminController

---

## 3. Endpoints

### 3.1. Jobs

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `POST` | `/seo-ai/jobs` | ClientDashboard | Crear job de generación AI |
| `GET` | `/seo-ai/jobs` | ClientDashboard | Listar jobs del tenant |
| `GET` | `/seo-ai/jobs/:id` | ClientDashboard | Detalle de un job |
| `GET` | `/seo-ai/jobs/:id/log` | ClientDashboard | Log de cambios del job |

**POST /seo-ai/jobs** body:
```json
{
  "job_type": "products" | "categories" | "site" | "audit",
  "mode": "update_missing" | "refresh" | "create",
  "scope": {}
}
```

### 3.2. Auditoría

| Método | Ruta | Auth | Créditos | Descripción |
|--------|------|------|----------|-------------|
| `GET` | `/seo-ai/audit` | ClientDashboard | Gratis | Escaneo SEO completo |

**Response:**
```json
{
  "summary": {
    "products": {
      "total": 50,
      "missing_title": 12,
      "missing_description": 8,
      "too_long_title": 3,
      "too_long_description": 1,
      "locked": 5,
      "ai_generated": 20
    },
    "categories": { ... }
  },
  "issues": [
    {
      "entity_type": "product",
      "entity_id": "uuid",
      "entity_name": "Zapatillas Pro",
      "issue": "Falta meta title",
      "severity": "error",
      "field": "meta_title"
    }
  ]
}
```

### 3.3. Prompt copiable

| Método | Ruta | Auth | Créditos | Descripción |
|--------|------|------|----------|-------------|
| `GET` | `/seo-ai/prompt` | ClientDashboard | Gratis | Prompt ChatGPT-ready |

### 3.4. Estado

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `GET` | `/seo-ai/status` | ClientDashboard | Balance + jobs activos |

### 3.5. Billing

| Método | Ruta | Auth | Descripción |
|--------|------|------|-------------|
| `GET` | `/seo-ai/packs` | ClientDashboard | Catálogo de packs |
| `GET` | `/seo-ai/my-credits` | ClientDashboard | Balance + historial |
| `POST` | `/seo-ai/purchase` | ClientDashboard | Comprar pack (→ MP) |
| `POST` | `/seo-ai/purchase/webhook` | Público | Webhook de MP |

---

## 4. Modelo de datos

### Columnas SEO en `products` y `categories`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `meta_title` | text | Meta title para `<title>` y OG |
| `meta_description` | text | Meta description |
| `slug` | text | URL amigable |
| `noindex` | bool | Excluir de indexación |
| `seo_source` | text | `'manual'` / `'ai'` / `'template'` |
| `seo_locked` | bool | Impide overwrite por AI |
| `seo_needs_refresh` | bool | Marca para re-generar |
| `seo_last_generated_at` | timestamptz | Última generación AI |

### Tabla `seo_ai_jobs`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | uuid PK | |
| client_id | uuid FK | Tenant |
| requested_by | text | account_id o email |
| job_type | text | products/categories/site/audit |
| mode | text | create/update_missing/refresh |
| scope | jsonb | Filtros opcionales |
| status | text | pending/processing/completed/failed/cancelled |
| progress | jsonb | `{total, done, errors}` |
| cost_estimated | int | Entidades estimadas |
| cost_actual | int | Entidades procesadas |
| tokens_input | int | Tokens consumidos (input) |
| tokens_output | int | Tokens consumidos (output) |
| error | text | Mensaje de error |
| result | jsonb | Resultado final |

### Tabla `seo_ai_log`

| Columna | Tipo | Descripción |
|---------|------|-------------|
| id | uuid PK | |
| client_id | uuid | Tenant |
| job_id | uuid FK | Job que generó el cambio |
| entity_type | text | product/category/site |
| entity_id | uuid | ID de la entidad |
| field_name | text | seo_title/seo_description |
| old_value | text | Valor anterior |
| new_value | text | Nuevo valor |
| tokens_used | int | Tokens usados |

### Tabla `seo_ai_credits`

Ledger de créditos con `account_id`, `delta`, `balance_after`, `reason`, `metadata`.

---

## 5. Worker de generación

El `SeoAiWorkerService` usa `@Interval(10000)` (polling cada 10s):

1. **Claim**: toma el job `pending` más antiguo con CAS (compare-and-swap)
2. **Dispatch**: según `job_type` → products, categories, o site (ambos)
3. **Chunk**: procesa de a 25 entidades
4. **Pre-check créditos**: antes de cada chunk, verifica balance ≥ chunk.length
5. **Genera**: llama a OpenAI gpt-4o-mini para cada entidad
6. **Escribe**: actualiza `meta_title`, `meta_description`, `seo_source='ai'`
7. **Debita**: resta créditos del ledger
8. **Log**: registra old/new values en `seo_ai_log`

### Guardrails

| Regla | Valor |
|-------|-------|
| Max concurrent jobs/tenant | 1 |
| Max daily jobs/tenant | 5 |
| Chunk size | 25 |
| Model | gpt-4o-mini |
| Temperature | 0.3 |
| Max tokens/call | 500 |
| Retries por entidad | 2 |
| Backoff | exponential (2s, 4s) |

### Entities con `seo_locked = true` se skipean automáticamente.

---

## 6. Billing (créditos)

### Flujo de compra

```
1. Cliente → GET /seo-ai/packs → ve catálogo
2. Cliente → POST /seo-ai/purchase {addon_key} → crea preferencia MP
3. MP → redirect a checkout
4. MP → POST /seo-ai/purchase/webhook → verifica firma HMAC
5. API → addCredits(account, +delta, reason)
6. Cliente → ve créditos actualizados
```

### Pack catalog (hardcodeado en `SeoAiBillingService`)

Los packs se definen con `addon_key`, `display_name`, `price_cents`, y `delta_entitlements.seo_ai_credits`.

---

## 7. Auditoría gratuita

El endpoint `GET /seo-ai/audit`:

1. Consulta **todos** los productos y categorías del tenant
2. Analiza cada entidad buscando:
   - Meta title faltante → severity `error`
   - Meta description faltante → severity `error`
   - Title > 65 chars → severity `warning`
   - Description > 160 chars → severity `warning`
   - Slug faltante → severity `error`
   - Titles duplicados → severity `warning`
3. Calcula score: `(campos completados / total campos) × 100%`
4. No consume créditos ni llama a OpenAI

---

## 8. Prompt copiable

El endpoint `GET /seo-ai/prompt`:

1. Obtiene nombre de tienda desde `nv_accounts`
2. Lista todas las categorías del tenant
3. Lista productos sin meta SEO (hasta 50)
4. Construye un prompt ChatGPT-ready con instrucciones + contexto
5. El cliente lo copia y pega en su AI preferida

---

## 9. SERP Preview

Componente frontend `SerpPreview` que renderiza un snippet tipo Google:

- **Title** (azul): hasta 65 chars, link clickeable
- **URL** (verde): dominio de la tienda
- **Description** (gris): hasta 160 chars
- **Indicadores de longitud**: verde (OK), amarillo (cerca del límite), rojo (excedido)

---

## 10. Seguridad

### API Key OpenAI
- Solo se lee de `OPENAI_API_KEY` env var en el constructor
- Nunca se expone en responses, logs, ni frontend
- Si no está configurada: `isConfigured() = false` → rechaza requests

### Multi-tenant
- Todos los endpoints usan `ClientDashboardGuard`
- Cada query filtra por `client_id`
- Jobs solo visibles por el tenant que los creó
- Créditos aislados por `account_id`

### Webhooks MP
- Verificación de firma HMAC
- Idempotencia por `provider_payment_id`
- Validación de monto

### Rate limiting
- 1 job concurrente por tenant
- 5 jobs diarios por tenant
- Chunks de 25 para controlar costo

---

## 11. Configuración

### Variables de entorno requeridas

```env
# OpenAI
OPENAI_API_KEY=sk-...

# Supabase (backend)
SUPABASE_URL=https://...
SUPABASE_SERVICE_ROLE_KEY=...

# Supabase (admin)
SUPABASE_ADMIN_URL=https://...
SUPABASE_ADMIN_SERVICE_ROLE_KEY=...

# Mercado Pago
MP_ACCESS_TOKEN=...
```

### Feature flag

En `featureCatalog.ts`, la feature `seo.ai_autopilot` está en `status: 'planned'`.
Se habilita por tenant vía purchase de addon (no por plan).

---

## 12. Troubleshooting

### "El servicio de IA no está configurado"
→ Falta `OPENAI_API_KEY` en env vars. Verificar en Railway/local.

### "Ya hay un job activo para este tenant"
→ Hay un job pending/processing. Esperar o cancelar. Max concurrent = 1.

### "Límite diario alcanzado"
→ Se lanzaron 5 jobs en el día. Esperar al día siguiente.

### "Créditos insuficientes"
→ El balance es menor al chunk a procesar. Comprar más créditos.

### Job se queda en "processing" eternamente
→ El worker crasheó. Ver logs del worker. El job no tiene auto-timeout (feature futura).
Workaround: actualizar manualmente en DB a `status = 'failed'`.

### Audit muestra 0 productos
→ Verificar que el tenant tiene productos cargados en la DB del backend.
→ Verificar que `resolveContext()` está obteniendo el `client_id` correcto.

### Prompt está vacío
→ No hay productos sin SEO meta. Todos ya tienen `meta_title` y `meta_description`.

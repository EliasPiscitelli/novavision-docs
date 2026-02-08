# Plan de Implementación E2E — NovaVision

> **Versión:** 1.0  
> **Fecha:** 2025-07-17  
> **Autor:** QA Architect Agent  
> **Estado:** Plan completo — sin código implementado aún  
> **Alcance:** Repo `novavision-e2e` standalone con Playwright + TypeScript

---

## Tabla de Contenidos

1. [Decisiones Arquitectónicas](#1-decisiones-arquitectónicas)
2. [Estructura del Repo](#2-estructura-del-repo)
3. [Mock Data Master](#3-mock-data-master)
4. [Fixtures y Helpers](#4-fixtures-y-helpers)
5. [Suites de Test (10 fases)](#5-suites-de-test-10-fases)
6. [Orden de Ejecución](#6-orden-de-ejecución)
7. [CI / Ejecución Local](#7-ci--ejecución-local)
8. [Riesgos y Mitigaciones](#8-riesgos-y-mitigaciones)
9. [Checklist Pre-implementación](#9-checklist-pre-implementación)

---

## 1. Decisiones Arquitectónicas

### 1.1 Entorno de ejecución

| Aspecto | Decisión | Justificación |
|---------|----------|---------------|
| Entorno | **100% local** | Sin CI por ahora. `localhost:3000` (API), `localhost:5173` (Web), `localhost:5174` (Admin) |
| DB | **Supabase remota** (Admin `erbfzlsz` + Backend `ulndkhij`) | No hay Supabase local. Todos los tests operan en las DBs reales de dev |
| MP | **Sandbox mode** (`MP_SANDBOX_MODE=true` en `.env` API) | Pagos con tarjetas de test MP, nunca dinero real |
| Browsers | **Chromium only** | Consistente con la config Playwright existente |
| Auth | **Supabase Auth remota** | Login real via `signInWithPassword`. storageState persistido para reusar sesiones |

### 1.2 Estrategia de datos

| Aspecto | Decisión |
|---------|----------|
| Creación de tenants | Los tests de onboarding crean **2 tenants nuevos** (`e2e-tienda-a`, `e2e-tienda-b`). Se reusan en suites posteriores |
| Cleanup | **Soft cleanup**: los tenants quedan vivos para inspección. Solo se limpian orders/cart_items de test |
| Identificación E2E | Todos los slugs empiezan con `e2e-`. Todos los emails usan dominio `+e2e-` en el sufijo. External references llevan suffix `_E2E` |
| Idempotencia | Cada test verifica estado previo antes de actuar. Si el tenant ya existe, lo reutiliza |

### 1.3 Sandbox Guard

El sandbox guard es un **fixture de Playwright** que:
1. Antes de cada test, verifica que `MP_SANDBOX_MODE=true` leyendo el `.env` del API
2. Si no está en sandbox, **aborta toda la suite** con `test.fail()`
3. NO necesita health endpoint — lee el archivo directamente (ejecución local)

### 1.4 Checkout E2E

```
[Test] → POST /mercadopago/create-preference-for-plan
     → Recibe { redirect_url, preference_id, external_reference }
     → Guarda preference_id y external_reference
     → NO redirige a MP (no se puede automatizar UI de MP)
     → Simula webhook: POST /mercadopago/webhook con body fake
     → (webhook pasa sin firma en dev si MP_WEBHOOK_SECRET_TENANT no está)
     → Verifica: POST /mercadopago/confirm-by-reference → { confirmed: true }
```

---

## 2. Estructura del Repo

```
novavision-e2e/
├── package.json
├── tsconfig.json
├── playwright.config.ts
├── .env.e2e                          # Variables para E2E (NO commitear valores reales)
├── .env.e2e.example                  # Template con placeholders
├── .gitignore
├── README.md
│
├── fixtures/
│   ├── sandbox-guard.ts              # Fixture que aborta si no es sandbox
│   ├── auth.fixture.ts               # Fixture de login/storageState
│   ├── api-client.fixture.ts         # Axios helper con headers tenant
│   ├── builder-session.fixture.ts    # Helper para generar builder_token JWT
│   ├── test-base.ts                  # `test` extendido con todos los fixtures
│   └── teardown.ts                   # Global teardown
│
├── data/
│   ├── accounts.json                 # Mock data: cuentas de onboarding
│   ├── products.json                 # Mock data: productos de test
│   ├── users.json                    # Mock data: compradores de test
│   ├── plans.json                    # Snapshot de planes activos
│   ├── mp-cards.json                 # Tarjetas de test de MP sandbox
│   └── tenants.json                  # Config de tenants E2E
│
├── helpers/
│   ├── supabase-admin.ts             # Cliente Supabase Admin DB (service_role)
│   ├── supabase-backend.ts           # Cliente Supabase Backend DB (service_role)
│   ├── mp-webhook-simulator.ts       # Simula webhook de MP sin firma
│   ├── external-reference.ts         # Builder/parser de external_reference
│   ├── wait-for.ts                   # Polling helper (assertivo)
│   └── cleanup.ts                    # Funciones de limpieza
│
├── auth-states/                      # storageState files (gitignored)
│   ├── .gitkeep
│   ├── buyer-a.json
│   ├── buyer-b.json
│   ├── admin-a.json
│   └── super-admin.json
│
├── tests/
│   ├── 01-health/
│   │   └── api-health.spec.ts
│   ├── 02-onboarding/
│   │   ├── onboarding-tienda-a.spec.ts
│   │   └── onboarding-tienda-b.spec.ts
│   ├── 03-admin-approve/
│   │   └── approve-tenants.spec.ts
│   ├── 04-storefront-public/
│   │   └── storefront-navigation.spec.ts
│   ├── 05-auth/
│   │   ├── signup-buyer.spec.ts
│   │   └── login-buyer.spec.ts
│   ├── 06-catalog/
│   │   └── product-listing.spec.ts
│   ├── 07-cart/
│   │   └── cart-operations.spec.ts
│   ├── 08-checkout/
│   │   └── checkout-payment.spec.ts
│   ├── 09-admin-dashboard/
│   │   └── admin-order-management.spec.ts
│   └── 10-multitenant/
│       └── tenant-isolation.spec.ts
│
├── reports/                          # HTML reports (gitignored)
│   └── .gitkeep
│
└── scripts/
    ├── setup-e2e.sh                  # Verifica pre-requisitos
    ├── run-all.sh                    # Ejecuta todas las suites en orden
    └── cleanup-e2e-data.sh           # Limpia datos E2E de las DBs
```

---

## 3. Mock Data Master

### 3.1 `data/plans.json` — Planes activos (snapshot real)

```json
{
  "_source": "SELECT * FROM plans WHERE active = true — Admin DB erbfzlsz",
  "_snapshot_date": "2025-07-17",
  "plans": [
    {
      "plan_key": "starter",
      "display_name": "Starter Store",
      "monthly_fee": 20.00,
      "setup_fee": 0,
      "currency": "USD",
      "recommended": false
    },
    {
      "plan_key": "growth",
      "display_name": "Growth Store",
      "monthly_fee": 60.00,
      "setup_fee": 0,
      "currency": "USD",
      "recommended": true
    },
    {
      "plan_key": "enterprise",
      "display_name": "Enterprise Store",
      "monthly_fee": 250.00,
      "setup_fee": 0,
      "currency": "USD",
      "recommended": false
    }
  ]
}
```

### 3.2 `data/accounts.json` — Cuentas de onboarding E2E

```json
{
  "_description": "Cuentas que los tests de onboarding crearán via POST /onboarding/builder/start",
  "accounts": {
    "tienda_a": {
      "email": "kaddocpendragon+e2e-tienda-a@gmail.com",
      "slug": "e2e-tienda-a",
      "plan_key": "starter",
      "cycle": "month",
      "owner": {
        "firstName": "Test",
        "lastName": "TiendaA",
        "password": "E2E_Test_2025!",
        "phone": "+5491100000001"
      },
      "business_info": {
        "business_name": "E2E Tienda A SRL",
        "cuit_cuil": "20345678901",
        "fiscal_address": "Av. Test 1234, CABA",
        "phone": "+5491100000001",
        "billing_email": "kaddocpendragon+e2e-tienda-a@gmail.com"
      },
      "design": {
        "template_key": "first",
        "palette_key": "ocean_breeze"
      }
    },
    "tienda_b": {
      "email": "kaddocpendragon+e2e-tienda-b@gmail.com",
      "slug": "e2e-tienda-b",
      "plan_key": "growth",
      "cycle": "month",
      "owner": {
        "firstName": "Test",
        "lastName": "TiendaB",
        "password": "E2E_Test_2025!",
        "phone": "+5491100000002"
      },
      "business_info": {
        "business_name": "E2E Tienda B SA",
        "cuit_cuil": "30456789012",
        "fiscal_address": "Calle Test 5678, CABA",
        "phone": "+5491100000002",
        "billing_email": "kaddocpendragon+e2e-tienda-b@gmail.com"
      },
      "design": {
        "template_key": "fifth",
        "palette_key": "midnight_pro"
      }
    }
  }
}
```

### 3.3 `data/users.json` — Compradores E2E

```json
{
  "_description": "Usuarios buyer creados via Supabase Auth signUp en tests de auth",
  "buyers": {
    "buyer_a": {
      "email": "kaddocpendragon+e2e-buyer-a@gmail.com",
      "password": "E2E_Buyer_2025!",
      "firstName": "Comprador",
      "lastName": "Alpha",
      "phoneNumber": "+5491100000010",
      "tenant_slug": "e2e-tienda-a",
      "_description": "Comprador principal de tienda A. Creado en 05-auth, reutilizado en 07/08/09"
    },
    "buyer_b": {
      "email": "kaddocpendragon+e2e-buyer-b@gmail.com",
      "password": "E2E_Buyer_2025!",
      "firstName": "Comprador",
      "lastName": "Beta",
      "phoneNumber": "+5491100000011",
      "tenant_slug": "e2e-tienda-b",
      "_description": "Comprador de tienda B. Usado en 10-multitenant para verificar aislamiento"
    }
  }
}
```

### 3.4 `data/products.json` — Productos de test

```json
{
  "_description": "Productos insertados directamente en Backend DB para los tenants E2E",
  "products": {
    "tienda_a": [
      {
        "name": "E2E Remera Básica",
        "description": "Producto de test E2E - no tocar",
        "price": 15000,
        "discount_price": null,
        "stock": 100,
        "sku": "E2E-REM-001",
        "active": true,
        "imageUrl": "https://placehold.co/400x400/png?text=E2E-A1"
      },
      {
        "name": "E2E Pantalón Clásico",
        "description": "Producto de test E2E - no tocar",
        "price": 25000,
        "discount_price": 22000,
        "stock": 50,
        "sku": "E2E-PAN-001",
        "active": true,
        "imageUrl": "https://placehold.co/400x400/png?text=E2E-A2"
      },
      {
        "name": "E2E Zapatillas Running (sin stock)",
        "description": "Producto de test E2E sin stock",
        "price": 45000,
        "discount_price": null,
        "stock": 0,
        "sku": "E2E-ZAP-001",
        "active": true,
        "imageUrl": "https://placehold.co/400x400/png?text=E2E-A3"
      }
    ],
    "tienda_b": [
      {
        "name": "E2E Notebook Pro",
        "description": "Producto de test E2E para tienda B",
        "price": 350000,
        "discount_price": 320000,
        "stock": 20,
        "sku": "E2E-NOT-001",
        "active": true,
        "imageUrl": "https://placehold.co/400x400/png?text=E2E-B1"
      },
      {
        "name": "E2E Mouse Inalámbrico",
        "description": "Producto de test E2E para tienda B",
        "price": 8000,
        "discount_price": null,
        "stock": 200,
        "sku": "E2E-MOU-001",
        "active": true,
        "imageUrl": "https://placehold.co/400x400/png?text=E2E-B2"
      }
    ]
  },
  "categories": {
    "tienda_a": [
      { "name": "E2E Ropa", "slug": "e2e-ropa" },
      { "name": "E2E Calzado", "slug": "e2e-calzado" }
    ],
    "tienda_b": [
      { "name": "E2E Electrónica", "slug": "e2e-electronica" },
      { "name": "E2E Accesorios", "slug": "e2e-accesorios" }
    ]
  }
}
```

### 3.5 `data/mp-cards.json` — Tarjetas de test Mercado Pago sandbox

```json
{
  "_source": "https://www.mercadopago.com.ar/developers/es/docs/your-integrations/test/cards",
  "_description": "Tarjetas de test para sandbox MP Argentina (MLA)",
  "cards": {
    "visa_approved": {
      "number": "4509953566233704",
      "expiration_month": 11,
      "expiration_year": 2025,
      "security_code": "123",
      "holder_name": "APRO",
      "dni": "12345678",
      "result": "approved"
    },
    "mastercard_approved": {
      "number": "5031755734530604",
      "expiration_month": 11,
      "expiration_year": 2025,
      "security_code": "123",
      "holder_name": "APRO",
      "dni": "12345678",
      "result": "approved"
    },
    "visa_rejected": {
      "number": "4509953566233704",
      "expiration_month": 11,
      "expiration_year": 2025,
      "security_code": "123",
      "holder_name": "OTHE",
      "dni": "12345678",
      "result": "rejected"
    },
    "visa_pending": {
      "number": "4509953566233704",
      "expiration_month": 11,
      "expiration_year": 2025,
      "security_code": "123",
      "holder_name": "CONT",
      "dni": "12345678",
      "result": "pending"
    }
  },
  "mp_test_vendors": {
    "tienda_a": {
      "_description": "Cuenta vendedor test MP para tienda A. CREAR en MP sandbox dashboard.",
      "access_token": "APP_USR-XXXXXXXX-TIENDA-A-PLACEHOLDER",
      "public_key": "APP_USR-XXXXXXXX-TIENDA-A-PK-PLACEHOLDER",
      "_note": "Reemplazar con credenciales reales de vendor test creado en sandbox"
    },
    "tienda_b": {
      "_description": "Cuenta vendedor test MP para tienda B. CREAR en MP sandbox dashboard.",
      "access_token": "APP_USR-XXXXXXXX-TIENDA-B-PLACEHOLDER",
      "public_key": "APP_USR-XXXXXXXX-TIENDA-B-PK-PLACEHOLDER",
      "_note": "Reemplazar con credenciales reales de vendor test creado en sandbox"
    }
  }
}
```

### 3.6 `data/tenants.json` — Configuración de tenants para reutilizar

```json
{
  "_description": "IDs y configs resueltos en runtime. Este archivo se GENERA por los tests de onboarding y se lee en suites posteriores. NO commitear con datos reales.",
  "_generated_by": "02-onboarding suite",
  "tenants": {
    "tienda_a": {
      "account_id": null,
      "client_id": null,
      "builder_token": null,
      "slug": "e2e-tienda-a",
      "owner_user_id": null,
      "storefront_url": "http://localhost:5173?tenant=e2e-tienda-a",
      "api_url": "http://localhost:3000"
    },
    "tienda_b": {
      "account_id": null,
      "client_id": null,
      "builder_token": null,
      "slug": "e2e-tienda-b",
      "owner_user_id": null,
      "storefront_url": "http://localhost:5173?tenant=e2e-tienda-b",
      "api_url": "http://localhost:3000"
    }
  }
}
```

> **NOTA**: Los valores `null` se completan en runtime por la suite `02-onboarding` y se persisten en `auth-states/tenants-runtime.json`.

---

## 4. Fixtures y Helpers

### 4.1 `fixtures/sandbox-guard.ts`

```
Propósito: Leer el .env del API y verificar MP_SANDBOX_MODE=true
Input:     path al .env de la API (configurable via E2E_API_ENV_PATH)
Output:    boolean
Acción:    Si false → test.fail('SANDBOX MODE NOT ACTIVE — aborting')
Ejecución: beforeAll global (playwright.config.ts globalSetup)
```

**Lógica:**
1. Leer `E2E_API_ENV_PATH` del `.env.e2e` (default: `../apps/api/.env`)
2. Parsear el archivo con `dotenv`
3. Verificar `MP_SANDBOX_MODE === 'true'`
4. Si no existe o es `false` → throw Error

### 4.2 `fixtures/auth.fixture.ts`

```
Propósito: Manejar autenticación Supabase y storageState de Playwright
Exports:
  - loginBuyer(email, password, tenantSlug) → storageState JSON path
  - loginAdmin(email, password) → storageState JSON path
  - getSupabaseSession(email, password) → { access_token, refresh_token, user }
```

**Lógica:**
1. Usa `@supabase/supabase-js` directamente (NO browser)
2. Llama `supabase.auth.signInWithPassword({ email, password })`
3. Construye el `storageState` de Playwright con:
   - `localStorage`: `[{ name: "sb-{REF}-auth-token", value: JSON.stringify(session) }]`
4. Escribe el archivo en `auth-states/{name}.json`
5. Devuelve el path para usar en `test.use({ storageState: path })`

**Claves de storage**:
- Backend DB (storefront): `sb-ulndkhij-auth-token`
- Admin DB: `nv_auth_platform`

### 4.3 `fixtures/api-client.fixture.ts`

```
Propósito: Cliente axios pre-configurado con headers de tenant
Exports:
  - createApiClient(tenantSlug, authToken?) → AxiosInstance
  - createOnboardingClient(builderToken) → AxiosInstance
```

**Headers por default:**
```typescript
{
  'x-tenant-slug': slug,
  'x-store-slug': slug,      // compat
  'x-client-id': clientId,   // resuelto dinámicamente
  'Authorization': `Bearer ${authToken}`,
  'Content-Type': 'application/json'
}
```

### 4.4 `fixtures/builder-session.fixture.ts`

```
Propósito: NO generar JWT manualmente. Usar POST /onboarding/builder/start
           que devuelve un builder_token válido.
Exports:
  - startBuilderSession(email, slug) → { account_id, builder_token }
  - resumeBuilderSession(accountId) → builder_token (si existe)
```

### 4.5 `helpers/mp-webhook-simulator.ts`

```
Propósito: Simular un webhook de MP para completar un pago en E2E
           Funciona SOLO si MP_WEBHOOK_SECRET_TENANT no está definido (dev mode)
```

**Lógica:**
1. Recibe `{ preferenceId, externalReference, paymentAmount }`
2. Crea un `paymentId` fake: `e2e_payment_${Date.now()}`
3. POST a `http://localhost:3000/mercadopago/webhook` con body:
```json
{
  "action": "payment.created",
  "api_version": "v1",
  "data": { "id": "{paymentId}" },
  "date_created": "2025-07-17T00:00:00Z",
  "type": "payment"
}
```
4. **PROBLEMA**: El webhook consulta la API de MP con `data.id` para obtener detalles.
   Con un ID fake, la API de MP retornará error.

**ALTERNATIVA (preferida):**
- En vez de simular webhook, insertar directamente en la DB:
  1. Crear orden en tabla `orders` con `payment_status: 'approved'`
  2. O usar `confirm-payment` con un `paymentId` real de sandbox

**DECISIÓN FINAL para checkout E2E:**
```
Opción A (RECOMENDADA): 
  1. Test genera preference → captura external_reference + preference_id
  2. Test verifica que preference se creó (assertion sobre response)
  3. Test BYPASSA el pago real: inserta orden directamente en DB via helper
  4. Test navega a SuccessPage con el external_reference correcto
  5. Verifica que la UI muestra "Pago confirmado"

Opción B (Si se quieren pagos MP sandbox reales):
  1. Crear preference
  2. Navegar al redirect_url de sandbox MP
  3. Completar formulario de pago en sandbox con tarjeta test
  4. Esperar redirect de vuelta
  5. Verificar confirm-by-reference
  → PROBLEMA: La UI de sandbox MP cambia frecuentemente, tests frágiles
```

### 4.6 `helpers/external-reference.ts`

```
Propósito: Replicar la lógica de buildExternalReference del backend
Exports:
  - buildExternalReference(clientId, userId, orderToken) → string
  - parseExternalReference(ref) → { clientId, userId, orderToken }
```

**Formato:** `client_{clientId}_user_{userId}_order_{orderToken}`

### 4.7 `helpers/supabase-admin.ts` / `supabase-backend.ts`

```
Propósito: Acceso directo a las DBs para setup/teardown/assertions
Usa:       SERVICE_ROLE_KEY (bypassa RLS)
```

**Admin DB** (`erbfzlsz`) — para:
- Verificar/modificar `nv_accounts`
- Verificar/modificar `nv_onboarding`
- Insertar en `super_admins` si hace falta
- Leer `plans`

**Backend DB** (`ulndkhij`) — para:
- Insertar productos y categorías para tenants E2E
- Verificar que el provisioning creó el `client` en tabla `clients`
- Leer/crear usuarios en tabla `users`
- Insertar/limpiar `orders`, `order_items`, `cart_items`
- Verificar aislamiento multi-tenant

### 4.8 `helpers/cleanup.ts`

```
Propósito: Limpiar datos de E2E de las DBs
Reglas:
  - NUNCA borrar tenants/accounts (quedan para inspección)
  - Sí borrar: orders donde external_reference contiene 'e2e',
    cart_items de users E2E, payments E2E
  - Identificar datos E2E por: slug starts with 'e2e-', sku starts with 'E2E-'
```

### 4.9 `fixtures/test-base.ts`

```
Propósito: Extender `test` de Playwright con fixtures custom
```

```typescript
// Pseudocódigo
import { test as base } from '@playwright/test';
import { createApiClient } from './api-client.fixture';

type E2EFixtures = {
  apiClient: AxiosInstance;
  tenantSlug: string;
  // etc.
};

export const test = base.extend<E2EFixtures>({
  apiClient: async ({ tenantSlug }, use) => {
    const client = createApiClient(tenantSlug);
    await use(client);
  },
  tenantSlug: ['e2e-tienda-a', { option: true }],
});

export { expect } from '@playwright/test';
```

---

## 5. Suites de Test (10 fases)

### Fase 01 — Health Check (`tests/01-health/api-health.spec.ts`)

**Pre-requisito:** API corriendo en `localhost:3000`

| # | Test | Endpoint | Assertion |
|---|------|----------|-----------|
| 1.1 | API responde OK | `GET /health` | `status: 'ok'` |
| 1.2 | DB Admin conectada | `GET /health/ready` | `admin_db: 'ok'` |
| 1.3 | DB Backend conectada | `GET /health/ready` | `backend_db: 'ok'` |
| 1.4 | Sandbox mode activo | Leer `.env` API local | `MP_SANDBOX_MODE=true` |

**Duración estimada:** 5 segundos

---

### Fase 02 — Onboarding (`tests/02-onboarding/`)

#### `onboarding-tienda-a.spec.ts`

**Pre-requisito:** Fase 01 pasó. Credenciales MP sandbox vendor en `.env.e2e`

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 2.1 | Builder start | `POST /onboarding/builder/start` `{ email, slug: 'e2e-tienda-a' }` | `account_id` y `builder_token` recibidos |
| 2.2 | Accept terms | `POST /onboarding/session/accept-terms` `{ version: "1.0" }` | `{ ok: true }` |
| 2.3 | Complete owner | `POST /onboarding/complete-owner` `{ token, password, firstName, lastName }` | 200 OK |
| 2.4 | Select plan | `POST /onboarding/checkout/start` `{ planId: 'starter', cycle: 'month' }` | `redirect_url` recibido |
| 2.5 | Business info | `POST /onboarding/business-info` con datos de `accounts.json` | 200 OK |
| 2.6 | MP credentials | `POST /onboarding/mp-credentials` `{ access_token: 'APP_USR-...', public_key: 'APP_USR-...' }` | `{ message: 'MercadoPago credentials validated...' }` |
| 2.7 | Design preferences | `PATCH /onboarding/preferences` `{ templateKey: 'first', paletteKey: 'ocean_breeze' }` | 200 OK |
| 2.8 | Submit for review | `POST /onboarding/submit-for-review` | `{ message: 'Onboarding submitted...' }` |
| 2.9 | Verify state | `GET /onboarding/status` | `state: 'submitted_for_review'` |

**Post-test:** Guardar `{ account_id, builder_token, slug }` en `auth-states/tenants-runtime.json`

**Body de `builder/start`:**
```json
{
  "email": "kaddocpendragon+e2e-tienda-a@gmail.com",
  "slug": "e2e-tienda-a"
}
```

**Body de `complete-owner`:**
```json
{
  "token": "{{builder_token}}",
  "password": "E2E_Test_2025!",
  "firstName": "Test",
  "lastName": "TiendaA",
  "phone": "+5491100000001"
}
```

**Body de `business-info`:**
```json
{
  "business_name": "E2E Tienda A SRL",
  "cuit_cuil": "20345678901",
  "fiscal_address": "Av. Test 1234, CABA",
  "phone": "+5491100000001",
  "billing_email": "kaddocpendragon+e2e-tienda-a@gmail.com"
}
```

**Body de `checkout/start`:**
```json
{
  "planId": "starter",
  "cycle": "month"
}
```

**Body de `mp-credentials`:**
```json
{
  "access_token": "APP_USR-XXXXXXXX-TIENDA-A",
  "public_key": "APP_USR-XXXXXXXX-TIENDA-A-PK"
}
```

**Nota:** Los `APP_USR-...` se reemplazan con credenciales reales de MP sandbox vendor en `.env.e2e`.

#### `onboarding-tienda-b.spec.ts`

Idéntico a tienda-a pero con datos de `accounts.json.tienda_b`:
- slug: `e2e-tienda-b`
- plan: `growth`
- template: `fifth`
- palette: `midnight_pro`

---

### Fase 03 — Admin Approve (`tests/03-admin-approve/approve-tenants.spec.ts`)

**Pre-requisito:** Fase 02 completada. Ambas cuentas en `submitted_for_review`.

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 3.1 | Approve tienda A | `POST /onboarding/approve/{accountId_A}` con headers SuperAdmin | `{ ok: true }` |
| 3.2 | Verify tienda A live | Verificar en Admin DB: `nv_accounts.status = 'active'` | status correcto |
| 3.3 | Verify tienda A provisioned | Verificar en Backend DB: existe fila en `clients` con slug `e2e-tienda-a` | `client_id` capturado |
| 3.4 | Approve tienda B | `POST /onboarding/approve/{accountId_B}` con headers SuperAdmin | `{ ok: true }` |
| 3.5 | Verify tienda B provisioned | Backend DB: `clients` con slug `e2e-tienda-b` | `client_id` capturado |

**Headers SuperAdmin:**
```
Authorization: Bearer {super_admin_jwt}
X-Internal-Key: {INTERNAL_ACCESS_KEY del .env}
```

**¿Cómo obtener `super_admin_jwt`?**
1. Leer `SUPER_ADMIN_EMAIL` del `.env.e2e`
2. Login en Supabase Admin DB con `signInWithPassword`
3. Usar el `access_token` del session

**Post-test:**
- Guardar `client_id` de ambos tenants en `auth-states/tenants-runtime.json`
- Insertar productos E2E en Backend DB para ambos tenants (via `supabase-backend.ts`)
- Insertar categorías E2E y vincular con `product_categories`

**Productos a insertar (datos de `products.json`):**

Para `e2e-tienda-a` (client_id resuelto):
```sql
INSERT INTO products (id, client_id, name, description, price, discount_price, stock, sku, active, "imageUrl")
VALUES 
  (gen_random_uuid(), '{client_id_a}', 'E2E Remera Básica', '...', 15000, NULL, 100, 'E2E-REM-001', true, '...'),
  (gen_random_uuid(), '{client_id_a}', 'E2E Pantalón Clásico', '...', 25000, 22000, 50, 'E2E-PAN-001', true, '...'),
  (gen_random_uuid(), '{client_id_a}', 'E2E Zapatillas Running (sin stock)', '...', 45000, NULL, 0, 'E2E-ZAP-001', true, '...');
```

Para `e2e-tienda-b` (client_id_b):
```sql
INSERT INTO products (id, client_id, name, description, price, discount_price, stock, sku, active, "imageUrl")
VALUES 
  (gen_random_uuid(), '{client_id_b}', 'E2E Notebook Pro', '...', 350000, 320000, 20, 'E2E-NOT-001', true, '...'),
  (gen_random_uuid(), '{client_id_b}', 'E2E Mouse Inalámbrico', '...', 8000, NULL, 200, 'E2E-MOU-001', true, '...');
```

---

### Fase 04 — Storefront Público (`tests/04-storefront-public/storefront-navigation.spec.ts`)

**Pre-requisito:** Fase 03 completada. Tenants provisioned, productos insertados.

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 4.1 | Bootstrap tienda A | `GET /tenant/bootstrap` con `x-tenant-slug: e2e-tienda-a` | `tenant.status: 'active'` |
| 4.2 | Home data carga | Navegar browser a `localhost:5173?tenant=e2e-tienda-a` | Página carga sin errores JS |
| 4.3 | Productos visibles | Verificar que los productos E2E aparecen en el home | Al menos 1 producto con texto "E2E" |
| 4.4 | Búsqueda funciona | Navegar a `/search?q=E2E` | Resultados contienen productos E2E |
| 4.5 | PDP accesible | Click en un producto | Página de producto carga con precio correcto |
| 4.6 | Bootstrap tienda B | `GET /tenant/bootstrap` con `x-tenant-slug: e2e-tienda-b` | `tenant.status: 'active'` |
| 4.7 | Home tienda B | Navegar a `localhost:5173?tenant=e2e-tienda-b` | Productos de tienda B visibles, NO los de tienda A |

**URLs:**
- Tienda A: `http://localhost:5173?tenant=e2e-tienda-a`
- Tienda B: `http://localhost:5173?tenant=e2e-tienda-b`

---

### Fase 05 — Autenticación (`tests/05-auth/`)

#### `signup-buyer.spec.ts`

**Pre-requisito:** Fase 04 pasó. Storefront accessible.

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 5.1 | Signup buyer A | Navegar a `localhost:5173?tenant=e2e-tienda-a`, ir a `/login`, completar formulario de registro | Email de confirmación enviado (o auto-confirm si está configurado) |
| 5.2 | Confirm buyer A | Usar Supabase Admin API para confirmar email directamente | `supabase.auth.admin.updateUserById(userId, { email_confirm: true })` |
| 5.3 | Signup buyer B | Mismo flow para `e2e-tienda-b` con `buyer_b` data | Buyer creado y confirmado |

**Formulario de registro** (campos del LoginPage):
```json
{
  "firstName": "Comprador",
  "lastName": "Alpha",
  "phoneNumber": "+5491100000010",
  "email": "kaddocpendragon+e2e-buyer-a@gmail.com",
  "emailConfirm": "kaddocpendragon+e2e-buyer-a@gmail.com",
  "password": "E2E_Buyer_2025!",
  "passwordConfirm": "E2E_Buyer_2025!",
  "termsAccepted": true
}
```

**PROBLEMA:** El formulario de signup requiere `data-testid` o selectores estables para llenar los campos. **Si no hay data-testid**, usar `label`, `name` o `placeholder` como fallback.

**Post-test:** Guardar buyer user_ids y persist storageState.

#### `login-buyer.spec.ts`

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 5.4 | Login buyer A | Navegar a `/login`, llenar email/password, submit | Redirige a Home o cart. Session activa |
| 5.5 | Persist session | Guardar `storageState` en `auth-states/buyer-a.json` | Archivo generado |
| 5.6 | Login buyer B | Mismo flow con buyer_b en tienda-b | `auth-states/buyer-b.json` generado |

---

### Fase 06 — Catálogo (`tests/06-catalog/product-listing.spec.ts`)

**Pre-requisito:** Fase 04 pasó (no necesita auth).

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 6.1 | Listado carga | `GET /products` | Retorna productos E2E de tienda A |
| 6.2 | Búsqueda con filtros | `GET /products/search?q=E2E&page=1&pageSize=12` | `totalItems >= 3` |
| 6.3 | Filtro por categoría | `GET /products/search?categoryIds={id}` | Solo productos de esa categoría |
| 6.4 | Producto sin stock visible | Buscar "E2E Zapatillas" en resultados | `stock: 0` presente |
| 6.5 | PDP muestra descuento | `GET /p/{id}` del "E2E Pantalón" | Muestra precio tachado 25000, precio final 22000 |

---

### Fase 07 — Carrito (`tests/07-cart/cart-operations.spec.ts`)

**Pre-requisito:** Fase 05 completada. storageState de buyer_a disponible.

**Usa:** `storageState: 'auth-states/buyer-a.json'`

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 7.1 | Agregar al carrito | `POST /api/cart` `{ productId: remera_id, quantity: 2 }` | `201` o `200` con item agregado |
| 7.2 | Ver carrito | `GET /api/cart` | `cartItems.length >= 1`, cantidad correcta |
| 7.3 | Modificar cantidad | `PUT /api/cart/{itemId}` `{ productId, quantity: 3 }` | Cantidad actualizada |
| 7.4 | Agregar segundo producto | `POST /api/cart` `{ productId: pantalon_id, quantity: 1 }` | 2 items en carrito |
| 7.5 | Totales correctos | `GET /api/cart` | `totals.priceWithDiscount` = (15000*3 + 22000*1) = 67000 |
| 7.6 | Eliminar item | `DELETE /api/cart/{itemId2}` | Solo queda 1 item |
| 7.7 | No agregar sin stock | `POST /api/cart` `{ productId: zapatillas_id, quantity: 1 }` | Error 400 o stock warning |
| 7.8 | UI: carrito visible | Navegar a `/cart` en browser | Ver items con precios |

---

### Fase 08 — Checkout (`tests/08-checkout/checkout-payment.spec.ts`)

**Pre-requisito:** Fase 07 completada. Carrito con items.

**Usa:** `storageState: 'auth-states/buyer-a.json'`

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 8.1 | Validate cart | `POST /mercadopago/validate-cart` | `{ valid: true }` |
| 8.2 | Create preference | `POST /mercadopago/create-preference-for-plan` con payload completo | Recibe `redirect_url`, `preference_id`, `external_reference` |
| 8.3 | Preference contiene datos | Verificar que `external_reference` tiene formato `client_{id}_user_{id}_order_{token}` | Regex match |
| 8.4 | Redirect URL válida | `redirect_url` empieza con `https://www.mercadopago.com` (sandbox) | URL válida |
| 8.5 | Simular pago via DB | Insertar orden con `payment_status: 'approved'` en Backend DB usando `external_reference` | Orden creada |
| 8.6 | Confirm by reference | `POST /mercadopago/confirm-by-reference` `{ external_reference }` | `{ confirmed: true }` o verifica orden |
| 8.7 | UI: Success page | Navegar a `/payment-result?status=approved&external_reference={ref}` | Muestra "Pago confirmado" o similar |

**Payload de `create-preference-for-plan`:**
```json
{
  "baseAmount": 45000,
  "selection": {
    "method": "debit_card",
    "installmentsSeed": 1,
    "settlementDays": 0,
    "planKey": "debit_1"
  },
  "cartItems": [
    {
      "id": "{product_id_remera}",
      "title": "E2E Remera Básica",
      "quantity": 3,
      "unit_price": 15000,
      "picture_url": "https://placehold.co/400x400/png?text=E2E-A1"
    }
  ]
}
```

**Headers:**
```
Authorization: Bearer {buyer_a_jwt}
x-tenant-slug: e2e-tienda-a
x-store-slug: e2e-tienda-a
x-client-id: {client_id_a}
Idempotency-Key: {crypto.randomUUID()}
Content-Type: application/json
```

**Inserción directa de orden (test 8.5):**
```sql
INSERT INTO orders (
  id, user_id, client_id, payment_status, status,
  total_amount, external_reference, order_items,
  payment_mode, first_name, last_name, email,
  method, plan_key, subtotal, preference_id, created_at
) VALUES (
  gen_random_uuid(),
  '{buyer_a_user_id}',
  '{client_id_a}',
  'approved',
  'paid',
  45000,
  '{external_reference_from_8.2}',
  '[{"product_id":"{id}","name":"E2E Remera Básica","quantity":3,"unit_price":15000}]'::jsonb,
  'total',
  'Comprador',
  'Alpha',
  'kaddocpendragon+e2e-buyer-a@gmail.com',
  'debit_card',
  'debit_1',
  45000,
  '{preference_id_from_8.2}',
  NOW()
);
```

---

### Fase 09 — Admin Dashboard (`tests/09-admin-dashboard/admin-order-management.spec.ts`)

**Pre-requisito:** Fase 08 completada. Orden existente.

**Nota:** El "admin" acá es el dueño de la tienda (admin de tenant), NO el super admin. Usa las credenciales del owner de tienda A.

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 9.1 | Login admin tienda A | Login en storefront como owner (email de tienda A, password de complete-owner) | Session activa con role admin |
| 9.2 | Ver pedidos | Navegar a `/admin-dashboard` | Lista de pedidos visible |
| 9.3 | Orden E2E presente | Buscar orden con external_reference del test 8.2 | Orden con status "paid" visible |
| 9.4 | Detalle de orden | Click en la orden | Muestra items, monto, buyer info |
| 9.5 | Cambiar estado | Marcar como "delivered" | Status cambia a "delivered" |

**Problema potencial:** El admin del storefront puede no tener una ruta `/admin-dashboard` funcional si el provisioning no creó el user como admin en la tabla `users` del backend. Verificar con query directa.

---

### Fase 10 — Multi-tenant Isolation (`tests/10-multitenant/tenant-isolation.spec.ts`)

**Pre-requisito:** Fases 03-08 completadas. Ambos tenants con datos.

| # | Test | Acción | Assertion |
|---|------|--------|-----------|
| 10.1 | Buyer A no ve productos de B | Login como buyer_a, `GET /products` con `x-tenant-slug: e2e-tienda-a` | Solo productos con SKU `E2E-*-001` (no `E2E-NOT-001` ni `E2E-MOU-001`) |
| 10.2 | Buyer B no ve productos de A | Login como buyer_b, `GET /products` con `x-tenant-slug: e2e-tienda-b` | Solo `E2E-NOT-001`, `E2E-MOU-001` |
| 10.3 | Buyer A no ve órdenes de B | `GET /orders` como buyer_a en tienda A | Solo sus órdenes |
| 10.4 | API rechaza cross-tenant | `GET /products` con JWT de tenant A pero `x-tenant-slug: e2e-tienda-b` | Error 403 o 0 resultados |
| 10.5 | Bootstrap cross-tenant aislado | `GET /home/data` con `x-client-id: {client_id_a}` | NO contiene productos de tienda B |
| 10.6 | Carrito aislado | Buyer A tiene items en carrito de tienda A. `GET /api/cart` en contexto tienda B | Carrito vacío, no muestra items de tienda A |

---

## 6. Orden de Ejecución

```
┌──────────────────────────────────────────────────────────┐
│ GLOBAL SETUP                                              │
│ 1. sandbox-guard → verificar MP_SANDBOX_MODE=true         │
│ 2. Verificar servicios levantados (API, Web, Admin)       │
│ 3. Leer tenants-runtime.json (puede estar vacío)          │
└────────────────────────┬─────────────────────────────────┘
                         │
         ┌───────────────▼───────────────┐
         │ 01-health (5s)                │
         │ API alive + DBs + sandbox     │
         └───────────────┬───────────────┘
                         │
         ┌───────────────▼───────────────┐
         │ 02-onboarding (60s)           │
         │ Crea tienda A + tienda B      │
         │ → Persiste account_ids        │
         └───────────────┬───────────────┘
                         │
         ┌───────────────▼───────────────┐
         │ 03-admin-approve (30s)        │
         │ Approves ambos tenants        │
         │ → Persiste client_ids         │
         │ → Inserta productos E2E       │
         └───────────────┬───────────────┘
                         │
         ┌───────────────▼───────────────┐
         │ 04-storefront-public (20s)    │
         │ Bootstrap + navegación        │
         └───────────────┬───────────────┘
                         │
         ┌───────────────▼───────────────┐
         │ 05-auth (30s)                 │
         │ Signup + login buyers         │
         │ → Persiste storageState       │
         └───────────────┬───────────────┘
                         │
    ┌────────────────────┼────────────────────┐
    │                    │                    │
    ▼                    ▼                    ▼
 06-catalog (15s)   07-cart (20s)        (paralelo)
                         │
                         ▼
                  08-checkout (30s)
                         │
                         ▼
                  09-admin-dashboard (20s)
                         │
                         ▼
                  10-multitenant (20s)
                         │
         ┌───────────────▼───────────────┐
         │ GLOBAL TEARDOWN               │
         │ 1. Cleanup orders E2E         │
         │ 2. Cleanup cart_items E2E     │
         │ 3. NO borrar tenants          │
         │ 4. Guardar report             │
         └───────────────────────────────┘

Tiempo estimado total: ~4 minutos
```

### `playwright.config.ts` — Proyectos ordenados

```typescript
projects: [
  { name: '01-health',           testDir: './tests/01-health' },
  { name: '02-onboarding',       testDir: './tests/02-onboarding',       dependencies: ['01-health'] },
  { name: '03-admin-approve',    testDir: './tests/03-admin-approve',    dependencies: ['02-onboarding'] },
  { name: '04-storefront',       testDir: './tests/04-storefront-public', dependencies: ['03-admin-approve'] },
  { name: '05-auth',             testDir: './tests/05-auth',             dependencies: ['04-storefront'] },
  { name: '06-catalog',          testDir: './tests/06-catalog',          dependencies: ['04-storefront'] },
  { name: '07-cart',             testDir: './tests/07-cart',             dependencies: ['05-auth'] },
  { name: '08-checkout',         testDir: './tests/08-checkout',         dependencies: ['07-cart'] },
  { name: '09-admin-dashboard',  testDir: './tests/09-admin-dashboard',  dependencies: ['08-checkout'] },
  { name: '10-multitenant',      testDir: './tests/10-multitenant',      dependencies: ['03-admin-approve', '05-auth'] },
]
```

---

## 7. CI / Ejecución Local

### 7.1 `.env.e2e.example`

```env
# ── URLs de servicios locales ──
API_URL=http://localhost:3000
WEB_URL=http://localhost:5173
ADMIN_URL=http://localhost:5174

# ── Path al .env del API (para sandbox guard) ──
E2E_API_ENV_PATH=../apps/api/.env

# ── Supabase Admin DB (erbfzlsz) ──
ADMIN_SUPABASE_URL=https://erbfzlsznqsmwmjugspo.supabase.co
ADMIN_SUPABASE_SERVICE_ROLE_KEY=eyJ...

# ── Supabase Backend DB (ulndkhij) ──
BACKEND_SUPABASE_URL=https://ulndkhij....supabase.co
BACKEND_SUPABASE_SERVICE_ROLE_KEY=eyJ...

# ── Super Admin (para approve) ──
SUPER_ADMIN_EMAIL=kaddocpendragon@gmail.com
SUPER_ADMIN_PASSWORD=...
INTERNAL_ACCESS_KEY=...

# ── MP Sandbox Vendor Test: Tienda A ──
MP_VENDOR_A_ACCESS_TOKEN=APP_USR-...
MP_VENDOR_A_PUBLIC_KEY=APP_USR-...

# ── MP Sandbox Vendor Test: Tienda B ──
MP_VENDOR_B_ACCESS_TOKEN=APP_USR-...
MP_VENDOR_B_PUBLIC_KEY=APP_USR-...

# ── JWT Secret (mismo que el API para builder sessions) ──
JWT_SECRET=...
```

### 7.2 Scripts

#### `scripts/setup-e2e.sh`
```bash
#!/bin/bash
set -e
echo "🔍 Verificando pre-requisitos E2E..."

# 1. API corriendo
curl -sf http://localhost:3000/health > /dev/null || { echo "❌ API no responde en :3000"; exit 1; }
echo "✅ API OK"

# 2. Web corriendo
curl -sf http://localhost:5173 > /dev/null || { echo "❌ Web no responde en :5173"; exit 1; }
echo "✅ Web OK"

# 3. .env.e2e existe
[ -f .env.e2e ] || { echo "❌ Falta .env.e2e — copiar de .env.e2e.example"; exit 1; }
echo "✅ .env.e2e OK"

# 4. Sandbox mode
grep -q "MP_SANDBOX_MODE=true" ../apps/api/.env || { echo "❌ MP_SANDBOX_MODE no es true"; exit 1; }
echo "✅ Sandbox mode OK"

echo "🚀 Todo listo para E2E"
```

#### `scripts/run-all.sh`
```bash
#!/bin/bash
set -e
./scripts/setup-e2e.sh
npx playwright test --reporter=html
echo "📊 Report en reports/index.html"
```

#### `scripts/cleanup-e2e-data.sh`
```bash
#!/bin/bash
echo "🧹 Limpiando datos E2E..."
# Este script invoca un helper de Node que:
# 1. Borra orders donde external_reference LIKE '%e2e%'
# 2. Borra cart_items de users con email LIKE '%e2e%'
# 3. Borra payments E2E
# 4. NO borra tenants ni accounts
npx ts-node helpers/cleanup.ts
echo "✅ Limpieza completada"
```

### 7.3 `package.json`

```json
{
  "name": "novavision-e2e",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "test": "playwright test",
    "test:ui": "playwright test --ui",
    "test:headed": "playwright test --headed",
    "test:debug": "playwright test --debug",
    "test:health": "playwright test --project=01-health",
    "test:onboarding": "playwright test --project=02-onboarding",
    "test:checkout": "playwright test --project=08-checkout",
    "test:isolation": "playwright test --project=10-multitenant",
    "setup": "./scripts/setup-e2e.sh",
    "cleanup": "./scripts/cleanup-e2e-data.sh",
    "report": "playwright show-report reports"
  },
  "devDependencies": {
    "@playwright/test": "^1.47.0",
    "@supabase/supabase-js": "^2.45.0",
    "axios": "^1.7.0",
    "dotenv": "^16.4.0",
    "jsonwebtoken": "^9.0.0",
    "typescript": "^5.5.0"
  },
  "devDependenciesComments": {
    "@playwright/test": "Framework de E2E testing",
    "@supabase/supabase-js": "Acceso directo a Admin y Backend DB para setup/teardown/assertions",
    "axios": "HTTP client para API calls directas (no-browser)",
    "dotenv": "Parsear .env para sandbox guard",
    "jsonwebtoken": "Solo para debugging de tokens, NO para generar builder sessions",
    "typescript": "Lenguaje del proyecto"
  }
}
```

---

## 8. Riesgos y Mitigaciones

| # | Riesgo | Probabilidad | Impacto | Mitigación |
|---|--------|-------------|---------|------------|
| R1 | Onboarding crea cuenta duplicada (slug ya existe) | Alta (re-runs) | Medio | Test verifica si slug existe antes de crear. Si existe, reutiliza `account_id` |
| R2 | Approve falla porque onboarding state != expected | Media | Alto | Query directa a DB para verificar state antes de approve. Si ya approved, skip |
| R3 | Productos no aparecen en storefront tras provisioning | Media | Alto | Wait con polling (hasta 10s) post-insert. Verificar cache headers |
| R4 | MP sandbox credentials inválidas o expiradas | Media | Bloqueante | Documentar proceso de crear vendor test en MP. Mantener en `.env.e2e` |
| R5 | Supabase Auth signup requiere email confirmation | Alta | Medio | Usar `supabase.auth.admin.updateUserById()` para confirm directo |
| R6 | storageState expira entre suites | Baja | Medio | Regenerar al inicio de cada suite dependiente |
| R7 | Orden no se confirma por confirm-by-reference (busca en MP API real) | Alta | Alto | Usar inserción directa en DB en vez de confirm-by-reference para E2E |
| R8 | Sin data-testid en formularios web | Alta | Medio | Usar selectores por `label`, `placeholder`, `name`. Documentar PR pendiente |
| R9 | Webhook sin firma falla en dev | Baja | Alto | Verificar que `MP_WEBHOOK_SECRET_TENANT` NO está definido en .env del API |
| R10 | Race condition en insert de productos post-approve | Media | Medio | Approve y seed son secuenciales. Verify query post-insert |

---

## 9. Checklist Pre-implementación

### Datos que se necesitan ANTES de codear

- [ ] **Crear 2 cuentas vendedor test MP sandbox** en https://www.mercadopago.com.ar/developers/panel/test-users  
  - Vendor A → `APP_USR-` access_token + public_key
  - Vendor B → `APP_USR-` access_token + public_key
  - Guardar en `.env.e2e`

- [ ] **Obtener `INTERNAL_ACCESS_KEY`** del `.env` del API (necesario para SuperAdminGuard)

- [ ] **Verificar `super_admins` table** en Admin DB tiene el email `kaddocpendragon@gmail.com`

- [ ] **Obtener `BACKEND_SUPABASE_URL`** y `BACKEND_SUPABASE_SERVICE_ROLE_KEY` del `.env` del API

- [ ] **Verificar que `MP_WEBHOOK_SECRET_TENANT` NO está** definido en `.env` del API (para que webhook pase sin firma)

- [ ] **Levantar servicios locales:**
  - `cd apps/api && npm run start:dev` → `localhost:3000`
  - `cd apps/web && npm run dev` → `localhost:5173`
  - `cd apps/admin && npm run dev` → `localhost:5174` (opcional para fase 09)

- [ ] **Supabase Auth: email confirmation**
  - Verificar si auto-confirm está habilitado en el proyecto Supabase
  - Si no, el test 5.2 usa `auth.admin.updateUserById()` para confirmar manualmente

### Selectores web pendientes (PR futuro)

Formularios que necesitan `data-testid` para estabilidad:

| Componente | Selector actual probable | data-testid sugerido |
|------------|------------------------|---------------------|
| Login email input | `input[name="email"]` | `login-email` |
| Login password input | `input[name="password"]` | `login-password` |
| Login submit button | `button[type="submit"]` | `login-submit` |
| Signup first name | `input[name="firstName"]` | `signup-firstname` |
| Signup last name | `input[name="lastName"]` | `signup-lastname` |
| Signup email | `input[name="email"]` | `signup-email` |
| Signup email confirm | `input[name="emailConfirm"]` | `signup-email-confirm` |
| Signup password | `input[name="password"]` | `signup-password` |
| Signup password confirm | `input[name="passwordConfirm"]` | `signup-password-confirm` |
| Signup phone | `input[name="phoneNumber"]` | `signup-phone` |
| Signup terms checkbox | `input[name="termsAccepted"]` | `signup-terms` |
| Signup submit | `button[type="submit"]` | `signup-submit` |
| Add to cart button | `.add-to-cart` o `button:has-text("Agregar")` | `add-to-cart` |
| Cart item quantity | `input[type="number"]` | `cart-item-qty-{id}` |
| Checkout button | `button:has-text("Pagar")` | `checkout-pay` |
| Product card | `.product-card` | `product-card-{id}` |
| Search input | `input[type="search"]` | `search-input` |

---

## Apéndice A — Flujo de Datos entre Suites

```
Suite 02 (onboarding) GENERA:
  ├── account_id_a, builder_token_a
  └── account_id_b, builder_token_b
       │
       ▼ [persiste en auth-states/tenants-runtime.json]
       │
Suite 03 (approve) LEE account_ids, GENERA:
  ├── client_id_a (de Backend DB)
  ├── client_id_b (de Backend DB)
  ├── product_ids para cada tenant
  └── category_ids para cada tenant
       │
       ▼ [persiste en auth-states/tenants-runtime.json]
       │
Suite 05 (auth) GENERA:
  ├── buyer_a_user_id + auth-states/buyer-a.json
  └── buyer_b_user_id + auth-states/buyer-b.json
       │
       ▼ [persiste en auth-states/]
       │
Suite 07 (cart) LEE product_ids + buyer storageState
       │
       ▼
Suite 08 (checkout) LEE cart state, GENERA:
  ├── preference_id
  ├── external_reference
  └── order_id (insertado en DB)
       │
       ▼
Suite 09 (admin) LEE order data
Suite 10 (isolation) LEE TODOS los datos anteriores
```

### Formato de `auth-states/tenants-runtime.json`

```json
{
  "_generated_at": "2025-07-17T10:30:00Z",
  "_generated_by": "novavision-e2e suites 02+03+05",
  "tienda_a": {
    "account_id": "uuid-generado-por-onboarding",
    "client_id": "uuid-generado-por-provisioning",
    "builder_token": "jwt-string",
    "slug": "e2e-tienda-a",
    "owner_user_id": "uuid-de-supabase-auth",
    "owner_email": "kaddocpendragon+e2e-tienda-a@gmail.com",
    "products": [
      { "id": "uuid", "sku": "E2E-REM-001", "name": "E2E Remera Básica", "price": 15000 },
      { "id": "uuid", "sku": "E2E-PAN-001", "name": "E2E Pantalón Clásico", "price": 25000, "discount_price": 22000 },
      { "id": "uuid", "sku": "E2E-ZAP-001", "name": "E2E Zapatillas Running (sin stock)", "price": 45000, "stock": 0 }
    ],
    "categories": [
      { "id": "uuid", "name": "E2E Ropa", "slug": "e2e-ropa" },
      { "id": "uuid", "name": "E2E Calzado", "slug": "e2e-calzado" }
    ]
  },
  "tienda_b": {
    "account_id": "uuid",
    "client_id": "uuid",
    "builder_token": "jwt-string",
    "slug": "e2e-tienda-b",
    "owner_user_id": "uuid",
    "owner_email": "kaddocpendragon+e2e-tienda-b@gmail.com",
    "products": [
      { "id": "uuid", "sku": "E2E-NOT-001", "name": "E2E Notebook Pro", "price": 350000, "discount_price": 320000 },
      { "id": "uuid", "sku": "E2E-MOU-001", "name": "E2E Mouse Inalámbrico", "price": 8000 }
    ],
    "categories": [
      { "id": "uuid", "name": "E2E Electrónica", "slug": "e2e-electronica" },
      { "id": "uuid", "name": "E2E Accesorios", "slug": "e2e-accesorios" }
    ]
  },
  "buyers": {
    "buyer_a": {
      "user_id": "uuid",
      "email": "kaddocpendragon+e2e-buyer-a@gmail.com",
      "tenant_slug": "e2e-tienda-a",
      "storage_state_path": "auth-states/buyer-a.json"
    },
    "buyer_b": {
      "user_id": "uuid",
      "email": "kaddocpendragon+e2e-buyer-b@gmail.com",
      "tenant_slug": "e2e-tienda-b",
      "storage_state_path": "auth-states/buyer-b.json"
    }
  },
  "checkout": {
    "preference_id": null,
    "external_reference": null,
    "order_id": null
  }
}
```

---

## Apéndice B — Referencia de Endpoints Usados

| Suite | Método | Endpoint | Auth |
|-------|--------|----------|------|
| 01 | GET | `/health` | Ninguna |
| 01 | GET | `/health/ready` | Ninguna |
| 02 | POST | `/onboarding/builder/start` | Ninguna (público) |
| 02 | POST | `/onboarding/session/accept-terms` | BuilderSession |
| 02 | POST | `/onboarding/complete-owner` | BuilderSession |
| 02 | POST | `/onboarding/checkout/start` | BuilderSession |
| 02 | POST | `/onboarding/business-info` | BuilderSession |
| 02 | POST | `/onboarding/mp-credentials` | BuilderSession |
| 02 | PATCH | `/onboarding/preferences` | BuilderSession |
| 02 | POST | `/onboarding/submit-for-review` | BuilderSession |
| 02 | GET | `/onboarding/status` | BuilderSession |
| 03 | POST | `/onboarding/approve/:accountId` | SuperAdmin + X-Internal-Key |
| 04 | GET | `/tenant/bootstrap` | x-tenant-slug |
| 04 | GET | `/home/data` | x-client-id |
| 06 | GET | `/products` | x-tenant-slug |
| 06 | GET | `/products/search` | x-tenant-slug |
| 07 | GET | `/api/cart` | Bearer JWT + x-tenant-slug |
| 07 | POST | `/api/cart` | Bearer JWT + x-tenant-slug |
| 07 | PUT | `/api/cart/:itemId` | Bearer JWT + x-tenant-slug |
| 07 | DELETE | `/api/cart/:itemId` | Bearer JWT + x-tenant-slug |
| 08 | POST | `/mercadopago/validate-cart` | Bearer JWT + x-tenant-slug |
| 08 | POST | `/mercadopago/create-preference-for-plan` | Bearer JWT + x-tenant-slug + Idempotency-Key |
| 08 | POST | `/mercadopago/confirm-by-reference` | Bearer JWT + x-client-id |
| 10 | GET | `/products` | Bearer JWT cross-tenant |
| 10 | GET | `/api/cart` | Bearer JWT cross-tenant |

---

## Apéndice C — Matriz de Cobertura vs Flows Reales

| Flow del Sistema | Suite | Cobertura |
|-----------------|-------|-----------|
| Onboarding completo (10 pasos) | 02 + 03 | **100% API** (no UI de wizard) |
| Storefront público (home, search, PDP) | 04 | **80%** (falta filtros avanzados) |
| Registro de usuario | 05 | **100%** |
| Login usuario | 05 | **100%** |
| Catálogo con filtros | 06 | **70%** (faltan filtros de precio/color) |
| Carrito CRUD | 07 | **100%** |
| Checkout + pago MP | 08 | **80%** (no pasa por UI de MP, simula via DB) |
| Admin gestión órdenes | 09 | **60%** (verificación básica) |
| Aislamiento multi-tenant | 10 | **90%** (6 checks de aislamiento) |
| Suscripciones/billing | — | **0%** (fuera de scope v1) |

---

**FIN DEL PLAN — Listo para implementar paso a paso tras confirmación del TL.**

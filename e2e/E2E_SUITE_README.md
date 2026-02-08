# NovaVision E2E Test Suite — Resumen Completo

**Fecha:** 2025-07-15  
**Autor:** agente-copilot  
**Repo:** `/Users/eliaspiscitelli/Documents/NovaVision/novavision-e2e/`

---

## Estructura del Repo

```
novavision-e2e/
├── package.json              # Deps: @playwright/test, @supabase/supabase-js, axios
├── tsconfig.json             # ES2022, bundler resolution, resolveJsonModule
├── playwright.config.ts      # 10 projects, 1 worker, secuencial, dependency DAG
├── global-setup.ts           # Carga env, sandbox guard, cleanup, reset runtime
├── global-teardown.ts        # Hook post-run
├── .env.e2e.example          # Template de variables de entorno
├── .gitignore                # Ignora auth-states/*.json, .env.e2e, reports
│
├── data/                     # Datos de prueba (JSON)
│   ├── accounts.json         # 2 tenants: tienda_a, tienda_b
│   ├── users.json            # 2 compradores: buyer_a, buyer_b
│   ├── plans.json            # 3 planes: starter, growth, enterprise
│   ├── products.json         # Productos y categorías por tenant
│   └── mp-cards.json         # Tarjetas de prueba Mercado Pago sandbox
│
├── helpers/                  # Utilidades compartidas
│   ├── config.ts             # Config tipada desde .env.e2e
│   ├── supabase-admin.ts     # Client Admin DB (nv_accounts, plans, super_admins)
│   ├── supabase-backend.ts   # Client Backend DB (products, orders, users, etc.)
│   ├── external-reference.ts # Build/parse external references (MP)
│   ├── wait-for.ts           # Polling helper + sleep
│   ├── cleanup.ts            # Limpieza de datos E2E en ambas DBs
│   ├── tenants-runtime.ts    # Estado compartido via JSON entre suites
│   └── hmac.ts               # Firma HMAC para webhooks de MP
│
├── fixtures/                 # Fixtures de Playwright
│   ├── test-base.ts          # Extended test con apiPublic y runtime fixtures
│   ├── api-client.fixture.ts # 5 client factories + API_ROUTES (40+ rutas)
│   ├── auth.fixture.ts       # Registro/login de compradores via Supabase Auth
│   ├── builder-session.fixture.ts # 8 métodos para onboarding builder
│   └── sandbox-guard.ts      # Pre-flight: valida sandbox mode
│
├── tests/                    # 10 suites secuenciales (85+ tests)
│   ├── 01-health/            # 7 tests — smoke
│   ├── 02-onboarding/        # 14 tests — flujo completo de onboarding
│   ├── 03-admin-approve/     # 10 tests — aprobación super admin
│   ├── 04-storefront-public/ # 6 tests — bootstrap y acceso público
│   ├── 05-auth/              # 6 tests — registro y login de compradores
│   ├── 06-catalog/           # 5 tests — siembra y lectura de catálogo
│   ├── 07-cart/              # 10 tests — CRUD completo de carrito
│   ├── 08-checkout/          # 12 tests — flujo de pago storefront
│   ├── 09-onboarding-checkout/ # 6 tests — verificación de suscripción
│   └── 10-multitenant/       # 10 tests — aislamiento cross-tenant
│
├── auth-states/              # Storage states generados (gitignored)
└── reports/                  # HTML reports (gitignored)
```

## Cadena de Dependencias (Playwright Projects)

```
01-health
    ↓
02-onboarding
    ↓
03-admin-approve ──────────┐
    ↓                      ↓
04-storefront  ──→  09-onboarding-checkout
    ↓
05-auth
    ↓
06-catalog
    ↓
07-cart
    ↓
08-checkout
    ↓
10-multitenant
```

## Cobertura por flujo

| Flujo | Suite | Tests | Tipo |
|-------|-------|-------|------|
| Smoke / Salud | 01-health | 7 | API + DB |
| Onboarding completo | 02-onboarding | 14 | API |
| Aprobación admin | 03-admin-approve | 10 | API + DB |
| Storefront público | 04-storefront-public | 6 | API + Browser |
| Auth compradores | 05-auth | 6 | Supabase Auth |
| Catálogo | 06-catalog | 5 | API + DB |
| Carrito CRUD | 07-cart | 10 | API |
| Checkout + pago | 08-checkout | 12 | API + DB + MP |
| Suscripción | 09-onboarding-checkout | 6 | DB verification |
| Multitenant | 10-multitenant | 10 | API + DB |
| **TOTAL** | | **~86** | |

## Hallazgos Críticos Durante la Implementación

### 1. State Mismatch Bug (onboarding)
`submitForReview` setea `state: 'submitted_for_review'` pero `approveOnboarding` espera `state === 'review_pending'`.
**Workaround en tests:** Se parchea el state a `review_pending` via Admin DB después de `submitForReview`.

### 2. `x-client-id` fue removido del TenantContextGuard
Solo se usa `x-tenant-slug` y `x-store-slug` (alias). **Pero** `ClientContextGuard` en `/api/cart` sí lee `x-client-id` como UUID.
Los API clients envían ambos headers.

### 3. INTERNAL_ACCESS_KEY
No estaba definido en la API .env. Es requerido por `SuperAdminGuard` junto con el email en la tabla `super_admins`.
**Acción requerida:** Generar un valor y agregarlo a la API .env y a `.env.e2e`.

### 4. Pago simulado (no real)
Mercado Pago sandbox no permite pagos automáticos via API sin interacción humana.
El checkout se simula insertando un payment y actualizando la orden directamente en DB.

## Variables de Entorno Requeridas (.env.e2e)

```env
API_URL=https://novavision-production.up.railway.app
WEB_URL=https://novavision-storefront.netlify.app
ADMIN_URL=https://novavision-admin.netlify.app

SUPABASE_ADMIN_URL=https://erbfzlsznqsmwmjugspo.supabase.co
SUPABASE_ADMIN_SERVICE_ROLE_KEY=<key>
SUPABASE_BACKEND_URL=https://ulndkhijxtxvpmbbfrgp.supabase.co
SUPABASE_BACKEND_SERVICE_ROLE_KEY=<key>

SUPER_ADMIN_EMAIL=novavision.contact@gmail.com
SUPER_ADMIN_PASSWORD=<password>
INTERNAL_ACCESS_KEY=<generar>

MP_VENDOR_ACCESS_TOKEN=<sandbox token>
MP_WEBHOOK_SECRET=86fc408419dc...
JWT_SECRET=5c3742b71bdf...
```

## Cómo Ejecutar

```bash
cd novavision-e2e
npm install
npx playwright install chromium

# Crear .env.e2e con los valores reales
cp .env.e2e.example .env.e2e
# Editar .env.e2e con credenciales

# Ejecutar todas las suites
npx playwright test

# Ejecutar una suite específica
npx playwright test --project=01-health

# Ver report
npx playwright show-report reports
```

## Pendientes para Primera Ejecución

1. **Crear `.env.e2e`** con credenciales reales
2. **Generar `INTERNAL_ACCESS_KEY`** y agregar a la API .env en Railway
3. **Verificar email super admin** en tabla `super_admins` de Admin DB
4. **Revisar que la API esté corriendo** en producción/staging
5. **Confirmar que MP sandbox mode** está activo

## Decisiones de Diseño

- **Secuencial obligatorio:** 1 worker, suites dependen entre sí via `tenants-runtime.json`
- **Sin retries:** Para detectar flakes rápido (retries = 0)
- **Pago simulado:** Se inserta payment en DB en vez de pagar en MP sandbox
- **State mismatch workaround:** Se parchea estado en Admin DB
- **Dual DB access:** service_role para Admin y Backend Supabase
- **API_ROUTES centralizado:** Todas las rutas verificadas contra los controllers reales

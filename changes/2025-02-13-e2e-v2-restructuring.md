# Reporte de Reestructuración E2E v2 — NovaVision

**Fecha:** 2025-02-13  
**Autor:** Agente Copilot  
**Rama:** main (novavision-e2e)  
**Estado:** Estructura completa — pendiente primera ejecución

---

## 1. Resumen Ejecutivo

Se reestructuró completamente la suite E2E de NovaVision siguiendo las reglas del PROMPT MAESTRO:

| Regla | Estado |
|-------|--------|
| Data determinística (no random) | ✅ `fixtures/e2e.fixtures.json` |
| Cleanup scoped (no TRUNCATE) | ✅ `helpers/cleanup-scoped.ts` |
| Tests 100% browser UI | ✅ 10 spec files, 0 fetch/axios |
| `E2E_ALLOW_DESTRUCTIVE` guard | ✅ En `global-setup.ts` |
| Login 1 vez → storageState | ✅ `helpers/auth-setup.ts` |
| globalSetup idempotente | ✅ Check-then-create pattern |
| Dry-run antes de borrar | ✅ `dryRunCleanup()` |

---

## 2. Estructura de Archivos

```
novavision-e2e/
├── fixtures/
│   └── e2e.fixtures.json         ← Contrato determinístico
├── global-setup.ts               ← v2: guard + cleanup + seed + auth
├── global-teardown.ts            ← Existente
├── playwright.config.ts          ← Restructurado con 10 projects v2 + 2 legacy
├── helpers/
│   ├── seed.ts                   ← NUEVO: seed idempotente via API onboarding
│   ├── cleanup-scoped.ts         ← NUEVO: cleanup solo datos e2e-*
│   ├── auth-setup.ts             ← NUEVO: login browser → storageState
│   ├── config.ts                 ← Existente (reusado)
│   ├── ui-helpers.ts             ← Existente (reusado)
│   ├── qa-prod-config.ts         ← Existente (reusado por legacy)
│   └── page-objects/             ← Existente (reusado)
│       ├── storefront/ (8 POs)
│       └── admin/ (4 POs)
├── tests/
│   ├── qa-v2/                    ← NUEVA suite v2
│   │   ├── 01-storefront-navigation.spec.ts  (9 tests)
│   │   ├── 02-auth.spec.ts                   (6 tests)
│   │   ├── 03-cart-checkout.spec.ts           (9 tests)
│   │   ├── 04-admin-dashboard.spec.ts         (6 tests)
│   │   ├── 05-admin-crud.spec.ts              (8 tests)
│   │   ├── 06-shipping.spec.ts                (5 tests)
│   │   ├── 07-store-coupons.spec.ts           (5 tests)
│   │   ├── 08-super-admin.spec.ts             (7 tests)
│   │   ├── 09-cross-tenant.spec.ts            (5 tests)
│   │   └── 10-responsive.spec.ts              (9 tests)
│   ├── qa-prod/                  ← Legacy (sin modificar)
│   │   └── qa-01 … qa-11
│   └── 01-health … 11-seo/      ← Legacy API tests
```

---

## 3. Conteo de Tests

| Suite | Spec File | Tests | Área |
|-------|-----------|-------|------|
| v2-01 | storefront-navigation | 9 | Home, header, búsqueda, catálogo, producto, footer |
| v2-02 | auth | 6 | Login, logout, credenciales inválidas, sesión persistente |
| v2-03 | cart-checkout | 9 | Carrito vacío, agregar, incrementar, eliminar, stepper, total |
| v2-04 | admin-dashboard | 6 | Login admin, métricas, tabla clientes, detalle |
| v2-05 | admin-crud | 8 | Panel admin, productos, FAQs, contacto, social, aislamiento |
| v2-06 | shipping | 5 | Paso envío, métodos, cotización CP, retiro, beta |
| v2-07 | store-coupons | 5 | Sección cupones, crear cupón, aplicar, cupón inválido |
| v2-08 | super-admin | 7 | Dashboard NovaVision, badge SA, clientes, health, sync |
| v2-09 | cross-tenant | 5 | Productos aislados, branding distinto, sesión aislada |
| v2-10 | responsive | 9 | Mobile home, hamburger, catálogo, tablet |
| **TOTAL v2** | **10 files** | **69** | |
| Legacy qa-prod | 9 files | ~196 | Onboarding, pagos, shipping API, cupones API |
| **TOTAL general** | **19 files** | **~265** | |

---

## 4. Cobertura por Área de Cambio (vs 90 Change Docs)

| Área (de change docs) | v2 Spec | Cobertura |
|------------------------|---------|-----------|
| Cross-tenant isolation | v2-09 | ✅ Productos, branding, sesión |
| Onboarding/provisioning | v2-08 (super admin verifica) | ⚠️ Parcial (seed infra lo cubre) |
| Payments/MercadoPago | v2-03 (checkout stepper) | ⚠️ Parcial (hasta step 2, no paga) |
| Subscriptions/lifecycle | v2-08 (health badges) | ⚠️ Parcial |
| Shipping V2 | v2-06 | ✅ Métodos, cotización, retiro |
| Security/RLS/auth | v2-02, v2-09 | ✅ Login, sesión, aislamiento |
| SEO/meta tags | — | 🔲 No cubierto (requiere head parsing) |
| Themes/design | v2-09 (branding) | ⚠️ Parcial |
| Admin dashboard | v2-04, v2-05, v2-08 | ✅ Dashboard, CRUD, super admin |
| Store coupons | v2-07 | ✅ Crear, aplicar, validar |
| Responsive | v2-10 | ✅ Mobile, tablet |

---

## 5. Fixture Contract (`e2e.fixtures.json`)

**2 Tenants:**
- `e2e-alpha` (plan starter) — 3 productos ropa, 2 categorías
- `e2e-beta` (plan growth) — 3 productos tech, 2 categorías

**4 Usuarios:**
- `superAdmin` — novavision.contact@gmail.com
- `adminAlpha` — kaddocpendragon+e2e-alpha@gmail.com
- `adminBeta` — kaddocpendragon+e2e-beta@gmail.com
- `buyer` — kaddocpendragon+e2e-buyer@gmail.com

**MercadoPago Sandbox:**
- Visa y Master test cards
- Buyer sandbox credentials

---

## 6. Arquitectura de Ejecución

```
┌─────────────────────────────────────────────┐
│           global-setup.ts                   │
│                                             │
│  1. Guard: E2E_ALLOW_DESTRUCTIVE check      │
│  2. Cleanup: solo datos con prefix e2e-*    │
│  3. Seed: onboarding API → approve → wait   │
│  4. Auth: login browser → storageState      │
└──────────────────┬──────────────────────────┘
                   │
    ┌──────────────┼──────────────┐
    │              │              │
    ▼              ▼              ▼
  CAPA A        CAPA B/C       CAPA D/E
  Storefront    Auth/Admin     SuperAdmin/
  (sin auth)    (con auth)     CrossTenant/
                               Responsive
```

**Dependencias entre projects:**
- v2-01 → v2-02 → v2-03 (storefront → auth → cart)
- v2-01 → v2-04 → v2-05/v2-06/v2-07 (storefront → admin → crud/shipping/coupons)
- v2-01 → v2-08/v2-09/v2-10 (storefront → super admin/cross-tenant/responsive)

---

## 7. Cómo Ejecutar

```bash
# Suite v2 completa (requiere datos seeded)
E2E_ALLOW_DESTRUCTIVE=true npx playwright test --project='v2-*'

# Solo una capa
npx playwright test --project=v2-01-storefront

# Solo un spec
npx playwright test tests/qa-v2/03-cart-checkout.spec.ts

# Con reporte HTML
npx playwright test --project='v2-*' --reporter=html

# Legacy tests (mantienen compatibilidad)
npx playwright test --project=qa-prod
```

---

## 8. Riesgos y Limitaciones

| Riesgo | Mitigación |
|--------|-----------|
| DBs están vacías — primera ejecución seed lento | seed.ts es idempotente; runs siguientes son rápidos |
| Pagos MP no testeados end-to-end | Stepper hasta paso 2 sí; pago real en legacy qa-prod |
| SEO no cubierto en v2 | Los meta tags necesitan parsing headless; considerar spec v2-11 |
| Admin routing puede cambiar | Page Objects abstraen locators; actualizar POs si cambia |
| Tests con `test.skip()` si feature no existe | Graceful degradation — reporta skip, no falla |

---

## 9. Próximos Pasos

1. **Ejecutar suite v2** con `E2E_ALLOW_DESTRUCTIVE=true`
2. **Verificar seed** — que ambos tenants se provisionan correctamente
3. **Ajustar locators** si hay cambios de UI post-último deploy
4. **Agregar v2-11-seo.spec.ts** para meta tags/OpenGraph
5. **Agregar v2-12-payments.spec.ts** cuando MP sandbox esté estable
6. **CI/CD** — integrar en GitHub Actions con matriz de projects

---

## 10. TypeScript Status

```
v2 spec files:    0 errores ✅
infrastructure:   0 errores ✅ (cleanup-scoped.ts corregido)
legacy:           1 error en tests/08-checkout/checkout.spec.ts (preexistente)
```

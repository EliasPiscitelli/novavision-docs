# Suite E2E v2 — Arquitectura, Diagramas y Cobertura

> Generado: 2025-02-13  
> Repo: `novavision-e2e` | Branch: `main`  
> Total: **82 tests** en **10 specs**

---

## 1. Diagrama de Flujo — Ejecución Completa

```mermaid
flowchart TB
    subgraph SETUP["🔧 Global Setup"]
        G1[E2E_ALLOW_DESTRUCTIVE guard]
        G2[Scoped Cleanup — solo datos e2e-*]
        G3[Seed idempotente]
        G4[Auth storageState x4 roles]
        G1 --> G2 --> G3 --> G4
    end

    subgraph LAYER_A["🅰️ Capa A — Storefront Público"]
        V01["01-storefront-navigation<br/>13 tests<br/>• Home carga<br/>• Header elementos ≥2/3<br/>• Búsqueda<br/>• Catálogo productos<br/>• Producto detalle<br/>• Footer<br/>─ EDGE ─<br/>• Búsqueda vacía<br/>• Sin stock<br/>• Con descuento<br/>• Tenant inexistente"]
    end

    subgraph LAYER_B["🅱️ Capa B — Auth + Carrito"]
        V02["02-auth<br/>8 tests<br/>• Login válido<br/>• Login inválido<br/>• Logout<br/>• Sesión persistente<br/>─ EDGE ─<br/>• Buyer intenta /admin<br/>• Email vacío"]
        V03["03-cart-checkout<br/>13 tests<br/>• Cart vacío<br/>• Agregar/Incrementar/Eliminar<br/>• Stepper / Envío / Total<br/>─ EDGE ─<br/>• Doble agregar<br/>• Qty > stock<br/>• Logout+carrito<br/>• Favoritos"]
    end

    subgraph LAYER_C["🅲️ Capa C — Admin + Features"]
        V04["04-admin-dashboard<br/>6 tests"]
        V05["05-admin-crud<br/>8 tests"]
        V06["06-shipping<br/>7 tests<br/>─ EDGE ─<br/>• CP inválido<br/>• Guardar dirección"]
        V07["07-store-coupons<br/>6 tests<br/>─ EDGE ─<br/>• Cupón vacío"]
    end

    subgraph LAYER_D["🅳️ Capa D — Super Admin"]
        V08["08-super-admin<br/>7 tests"]
    end

    subgraph LAYER_E["🅴️ Capa E — Cross-tenant + Responsive"]
        V09["09-cross-tenant<br/>5 tests"]
        V10["10-responsive<br/>9 tests"]
    end

    SETUP --> LAYER_A
    LAYER_A --> LAYER_B
    LAYER_B --> LAYER_C
    LAYER_C --> LAYER_D
    LAYER_D --> LAYER_E
```

---

## 2. Distribución de Tests por Spec

```mermaid
pie title Distribución de 82 Tests
    "01 Storefront Navigation" : 13
    "02 Auth" : 8
    "03 Cart & Checkout" : 13
    "04 Admin Dashboard" : 6
    "05 Admin CRUD" : 8
    "06 Shipping" : 7
    "07 Cupones" : 6
    "08 Super Admin" : 7
    "09 Cross-Tenant" : 5
    "10 Responsive" : 9
```

---

## 3. Dataset E2E — Tenants, Usuarios y Productos

```mermaid
erDiagram
    FIXTURE_JSON ||--o{ TENANT_ALPHA : contiene
    FIXTURE_JSON ||--o{ TENANT_BETA : contiene
    FIXTURE_JSON ||--o{ USERS : contiene

    TENANT_ALPHA {
        string slug "e2e-alpha"
        string plan "starter"
        string owner "kaddocpendragon@gmail.com"
    }

    TENANT_BETA {
        string slug "e2e-beta"
        string plan "growth"
        string owner "elias.piscitelli@gmail.com"
    }

    TENANT_ALPHA ||--o{ PRODUCTS_ALPHA : tiene
    TENANT_BETA ||--o{ PRODUCTS_BETA : tiene

    PRODUCTS_ALPHA {
        string sku1 "E2E-ALPHA-001 Remera 15k"
        string sku2 "E2E-ALPHA-002 Pantalón 25k"
        string sku3 "E2E-ALPHA-003 Zapatillas SIN STOCK"
    }

    PRODUCTS_BETA {
        string sku1 "E2E-BETA-001 Notebook 350k"
        string sku2 "E2E-BETA-002 Mouse 8k"
        string sku3 "E2E-BETA-003 Monitor SIN STOCK"
    }

    USERS {
        string super_admin "novavision.contact@gmail.com"
        string admin_alpha "kaddocpendragon@gmail.com"
        string admin_beta "elias.piscitelli@gmail.com"
        string buyer "buyer TBD"
    }
```

---

## 4. Análisis de Cobertura: Happy Paths vs Edge Cases

```mermaid
quadrantChart
    title Cobertura E2E — Happy Paths vs Edge Cases
    x-axis "Happy Path" --> "Edge Case"
    y-axis "UI Básica" --> "Lógica de Negocio"
    "Home carga": [0.1, 0.2]
    "Header elementos": [0.15, 0.3]
    "Catálogo productos": [0.2, 0.4]
    "Login válido": [0.1, 0.5]
    "Cart agregar": [0.15, 0.6]
    "Checkout stepper": [0.2, 0.7]
    "Admin dashboard": [0.15, 0.8]
    "Super admin": [0.1, 0.9]
    "Login inválido": [0.6, 0.5]
    "Cart vacío": [0.5, 0.4]
    "Búsqueda vacía": [0.7, 0.35]
    "Sin stock": [0.8, 0.65]
    "Con descuento": [0.65, 0.6]
    "Tenant inexistente": [0.9, 0.45]
    "Buyer intenta admin": [0.85, 0.75]
    "Doble agregar": [0.75, 0.7]
    "Qty mayor stock": [0.9, 0.8]
    "Logout carrito": [0.7, 0.55]
    "CP inválido": [0.8, 0.55]
    "Cupón vacío": [0.7, 0.65]
```

---

## 5. Flujo de Onboarding (Setup de Tenants)

```mermaid
flowchart LR
    subgraph WIZARD["🧙 Builder Wizard (12 pasos)"]
        S1[1 Email + Slug]
        S2[2 Logo]
        S3[3 Catálogo]
        S4[4 Diseño / Template]
        S5[5 Auth / Login]
        S6[6 Plan + Pago MP]
        S7[7 Conectar MP OAuth]
        S8[8 Datos Cliente]
        S9[9 Credenciales MP]
        S10[10 Resumen]
        S11[11 Términos]
        S12[12 Éxito]

        S1 --> S2 --> S3 --> S4 --> S5 --> S6
        S6 --> S7 --> S8 --> S9 --> S10 --> S11 --> S12
    end

    S12 --"POST submit-for-review"--> REVIEW["📋 En Revisión<br/>(pending_review)"]
    REVIEW --"Super Admin aprueba"--> APPROVED["✅ Aprobado"]
    APPROVED --"Provisioning auto"--> LIVE["🚀 Tienda LIVE<br/>(client en multicliente DB)"]

    style WIZARD fill:#1a2a3a,stroke:#2196f3,color:#fff
    style REVIEW fill:#ff9800,stroke:#e65100,color:#fff
    style APPROVED fill:#4caf50,stroke:#2e7d32,color:#fff
    style LIVE fill:#2196f3,stroke:#1565c0,color:#fff
```

### División de responsabilidades

| Paso | Quién lo hace | Método |
|------|--------------|--------|
| Steps 1-11 (Wizard completo) | **Agente (Playwright)** | Automatización UI browser |
| Step 12 (Submit) | **Agente** | Automático al completar step 11 |
| Aprobación | **TL (Manual)** | Desde admin panel |
| Pago MP en tiendas | **TL (Manual)** | Sandbox Mercado Pago |
| Seed productos | **Agente** | service_role post-provisioning |
| Seed buyer | **Agente** | Supabase auth admin |

---

## 6. Estructura de Archivos

```
novavision-e2e/
├── .env.e2e                    # Variables de entorno
├── global-setup.ts             # Guard + cleanup + seed + auth
├── playwright.config.ts        # 10 v2 projects + 2 legacy
│
├── fixtures/
│   └── e2e.fixtures.json       # Dataset determinístico (2 tenants, 4 users, 6 products)
│
├── helpers/
│   ├── seed.ts                 # Seed idempotente (productos + buyer)
│   ├── cleanup-scoped.ts       # Cleanup solo datos e2e-*
│   ├── auth-setup.ts           # Browser login → storageState
│   ├── config.ts               # URLs y credenciales desde env
│   ├── ui-helpers.ts           # 30+ funciones de ayuda UI
│   └── page-objects/
│       ├── storefront/         # HomePage, LoginPage, CartPage, SearchPage, etc.
│       └── admin/              # AdminDashboardPage, ClientsPage, etc.
│
├── scripts/
│   └── onboard-wizard.spec.ts  # Onboarding via UI (Playwright)
│
└── tests/
    └── qa-v2/
        ├── 01-storefront-navigation.spec.ts  (13 tests)
        ├── 02-auth.spec.ts                   (8 tests)
        ├── 03-cart-checkout.spec.ts          (13 tests)
        ├── 04-admin-dashboard.spec.ts        (6 tests)
        ├── 05-admin-crud.spec.ts             (8 tests)
        ├── 06-shipping.spec.ts               (7 tests)
        ├── 07-store-coupons.spec.ts          (6 tests)
        ├── 08-super-admin.spec.ts            (7 tests)
        ├── 09-cross-tenant.spec.ts           (5 tests)
        └── 10-responsive.spec.ts             (9 tests)
```

---

## 7. Tests Detallados por Spec

### 01 — Storefront Navigation (13 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Home carga correctamente (alpha) | Happy Path |
| 2 | Header tiene ≥ 2 de 3 elementos | Happy Path |
| 3 | Navegar a búsqueda | Happy Path |
| 4 | Catálogo muestra productos | Happy Path |
| 5 | Detalle de producto carga | Happy Path |
| 6 | Footer presente | Happy Path |
| 7 | Beta home carga | Happy Path |
| 8 | Beta muestra productos distintos | Happy Path |
| 9 | Beta tiene ≥ 3 productos | Happy Path |
| 10 | EDGE: Búsqueda sin resultados | Edge Case |
| 11 | EDGE: Producto sin stock | Edge Case |
| 12 | EDGE: Producto con descuento | Edge Case |
| 13 | EDGE: Tenant slug inexistente | Edge Case |

### 02 — Auth (8 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Login page carga | Happy Path |
| 2 | Login credenciales válidas | Happy Path |
| 3 | Login credenciales inválidas | Edge Case |
| 4 | Logout funciona | Happy Path |
| 5 | Login en tenant beta | Happy Path |
| 6 | Sesión persiste tras recargar | Happy Path |
| 7 | EDGE: Buyer no accede a panel admin | Edge Case |
| 8 | EDGE: Email vacío no navega | Edge Case |

### 03 — Cart & Checkout (13 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Carrito vacío muestra mensaje | Happy Path |
| 2 | Agregar producto desde catálogo | Happy Path |
| 3 | Incrementar cantidad | Happy Path |
| 4 | Eliminar producto | Happy Path |
| 5 | Buyer agrega y ve carrito | Happy Path |
| 6 | Stepper paso 0 = Carrito | Happy Path |
| 7 | Navegar a paso Envío | Happy Path |
| 8 | Total visible | Happy Path |
| 9 | Beta productos y agregar | Happy Path |
| 10 | EDGE: Doble agregar = +qty | Edge Case |
| 11 | EDGE: Qty > stock | Edge Case |
| 12 | EDGE: Logout + carrito | Edge Case |
| 13 | EDGE: Favoritos toggle | Edge Case |

### 04 — Admin Dashboard (6 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Admin login carga | Happy Path |
| 2 | Login super admin | Happy Path |
| 3 | Metrics cards visibles | Happy Path |
| 4 | Lista de clientes | Happy Path |
| 5 | Buscar e2e-alpha | Happy Path |
| 6 | Ver detalle de cliente | Happy Path |

### 05 — Admin CRUD (8 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Acceder panel admin tenant | Happy Path |
| 2 | Lista de productos | Happy Path |
| 3 | Sección FAQs | Happy Path |
| 4 | Crear FAQ | Happy Path |
| 5 | Info de contacto | Happy Path |
| 6 | Redes sociales | Happy Path |
| 7 | Beta admin accesible | Happy Path |
| 8 | Beta productos ≠ alpha | Happy Path |

### 06 — Shipping (7 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Paso envío accesible | Happy Path |
| 2 | Métodos disponibles | Happy Path |
| 3 | Cotizar con CP 1425 | Happy Path |
| 4 | Retiro en local | Happy Path |
| 5 | Beta envío accesible | Happy Path |
| 6 | EDGE: CP inválido | Edge Case |
| 7 | EDGE: Guardar dirección | Edge Case |

### 07 — Store Coupons (6 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Sección cupones accesible | Happy Path |
| 2 | Crear cupón porcentual | Happy Path |
| 3 | Lista muestra cupones | Happy Path |
| 4 | Campo cupón visible | Happy Path |
| 5 | Cupón inválido = error | Edge Case |
| 6 | EDGE: Cupón vacío | Edge Case |

### 08 — Super Admin (7 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Dashboard con métricas | Happy Path |
| 2 | Badge Super Admin | Happy Path |
| 3 | Navegar a clientes | Happy Path |
| 4 | Buscar alpha/beta | Happy Path |
| 5 | Health badges | Happy Path |
| 6 | Acciones de sync | Happy Path |
| 7 | Filtrar clientes | Happy Path |

### 09 — Cross-Tenant (5 tests)

| # | Test | Tipo |
|---|------|------|
| 1 | Alpha ≠ Beta productos | Happy Path |
| 2 | Fixtures predicen productos | Happy Path |
| 3 | Store name diferente | Happy Path |
| 4 | URLs independientes | Happy Path |
| 5 | Login alpha no filtra a beta | Happy Path |

### 10 — Responsive (9 tests)

| # | Test | Tipo |
|---|------|------|
| 1-5 | Mobile alpha (home, header, hamburger, productos, catálogo) | Happy Path |
| 6-7 | Mobile beta (home, productos) | Happy Path |
| 8-9 | Tablet alpha (layout, productos) | Happy Path |

---

## 8. Ejecución

```bash
# Suite completa v2 (requiere tenants provisioned)
E2E_ALLOW_DESTRUCTIVE=true npx playwright test --project='v2-*'

# Solo una capa
npx playwright test --project='v2-01-storefront'

# Con UI de Playwright
npx playwright test --ui --project='v2-*'

# Solo onboarding (setup inicial)
npx playwright test scripts/onboard-wizard.spec.ts
```

---

## 9. Riesgos y Limitaciones

| Riesgo | Mitigación |
|--------|-----------|
| Tenants no provisioned | globalSetup verifica y alerta; tests hacen skip |
| MP sandbox caído | Tests de pago se skipean; flujo core no depende |
| Selectores CSS cambian | Page Objects centralizan; fácil de actualizar |
| Rate limits de Supabase | Waits entre operaciones; retry implícito |
| DB sucia con datos huérfanos | Cleanup scoped solo borra `e2e-*`; no trunca |

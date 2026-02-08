# Plan de Implementación — E2E UI Tests (Browser)

**Fecha:** 2026-02-08  
**Autor:** agente-copilot  
**Repo:** `novavision-e2e` (se extiende la suite existente)  
**Herramienta:** Playwright (browser mode — Chromium + Mobile Safari viewport)

---

## Contexto

Actualmente tenemos **86 tests E2E de API** que validan contratos HTTP. Este plan agrega una **segunda capa de tests de UI** que abren un navegador real, navegan páginas, interactúan con formularios/botones y verifican lo que ve el usuario final — equivalente a un **QA manual automatizado**.

### Frontends a cubrir

| App | URL local | Puerto | Descripción |
|-----|-----------|--------|-------------|
| Web Storefront | `http://localhost:5173` | 5173 | Tienda para compradores |
| Admin Dashboard | `http://localhost:5174` | 5174 | Panel super admin + onboarding |

### Cobertura actual vs objetivo

| Capa | Estado actual | Objetivo |
|------|--------------|----------|
| API E2E (HTTP) | ✅ 86 tests, 10 suites | Mantenimiento |
| UI E2E Storefront | ❌ 2 tests con mocks | ~60 tests reales |
| UI E2E Admin | ❌ 0 tests | ~45 tests reales |
| **Total UI E2E** | **2** | **~105 tests** |

---

## Arquitectura Propuesta

```
novavision-e2e/
├── playwright.config.ts          # Agregar proyectos UI (browser)
├── tests/
│   ├── 01-health/ ... 10-multitenant/   # API tests (existentes, intactos)
│   │
│   └── ui/                              # ← NUEVO: tests de browser
│       ├── storefront/
│       │   ├── sf-01-navigation.spec.ts
│       │   ├── sf-02-catalog.spec.ts
│       │   ├── sf-03-product-detail.spec.ts
│       │   ├── sf-04-auth.spec.ts
│       │   ├── sf-05-cart-checkout.spec.ts
│       │   ├── sf-06-user-dashboard.spec.ts
│       │   ├── sf-07-favorites.spec.ts
│       │   ├── sf-08-admin-panel.spec.ts
│       │   └── sf-09-responsive.spec.ts
│       │
│       └── admin/
│           ├── ad-01-landing.spec.ts
│           ├── ad-02-onboarding-wizard.spec.ts
│           ├── ad-03-auth-flows.spec.ts
│           ├── ad-04-super-admin-dashboard.spec.ts
│           ├── ad-05-client-management.spec.ts
│           ├── ad-06-approvals.spec.ts
│           ├── ad-07-billing.spec.ts
│           └── ad-08-lead-enterprise.spec.ts
│
├── helpers/
│   ├── page-objects/                    # ← NUEVO: Page Object Model
│   │   ├── storefront/
│   │   │   ├── home.page.ts
│   │   │   ├── search.page.ts
│   │   │   ├── product.page.ts
│   │   │   ├── cart.page.ts
│   │   │   ├── login.page.ts
│   │   │   ├── profile.page.ts
│   │   │   └── admin-panel.page.ts
│   │   └── admin/
│   │       ├── landing.page.ts
│   │       ├── builder-wizard.page.ts
│   │       ├── dashboard.page.ts
│   │       ├── client-details.page.ts
│   │       └── approval.page.ts
│   └── ui-helpers.ts                    # Login via storageState, screenshots, waiters
│
└── screenshots/                         # Capturas de referencia (visual regression opcional)
```

### Playwright Config — proyectos UI

```typescript
// Se agregan a playwright.config.ts
{
  name: 'ui-storefront',
  testDir: './tests/ui/storefront',
  use: {
    baseURL: 'http://localhost:5173',
    browserName: 'chromium',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  dependencies: ['08-checkout'], // requiere tenants provisionados
},
{
  name: 'ui-storefront-mobile',
  testDir: './tests/ui/storefront',
  use: {
    baseURL: 'http://localhost:5173',
    ...devices['iPhone 14'],
    screenshot: 'only-on-failure',
  },
  dependencies: ['ui-storefront'],
},
{
  name: 'ui-admin',
  testDir: './tests/ui/admin',
  use: {
    baseURL: 'http://localhost:5174',
    browserName: 'chromium',
    screenshot: 'only-on-failure',
    trace: 'retain-on-failure',
  },
  dependencies: ['ui-storefront'],
},
```

---

## Fases de Implementación

### FASE 1 — Infraestructura + Navegación Storefront (Semana 1)

**Objetivo:** Montar el scaffolding de Page Objects, auth por storageState y los primeros tests de navegación.

#### 1.1 Infraestructura base
- [ ] Agregar proyectos `ui-storefront`, `ui-storefront-mobile`, `ui-admin` a `playwright.config.ts`
- [ ] Crear `helpers/ui-helpers.ts` con:
  - `loginAsUser(page, email, password)` → completa el formulario de login
  - `loginAsAdmin(page, email, password)` → login de admin de tienda
  - `loginAsSuperAdmin(page)` → login interno
  - `saveStorageState(page, path)` → persistir sesión para reusar
  - `expectToastMessage(page, text)` → verificar notificaciones
  - `waitForPageReady(page)` → esperar skeleton/loader
- [ ] Crear Page Objects base: `home.page.ts`, `search.page.ts`, `login.page.ts`

#### 1.2 Suite sf-01-navigation (~8 tests)
```
sf-01.0 — Home carga correctamente (logo, banners, productos destacados)
sf-01.1 — Navbar muestra links correctos (Inicio, Catálogo, Carrito, Login)
sf-01.2 — Click en "Catálogo" navega a /search
sf-01.3 — Click en producto desde home navega a /p/:id
sf-01.4 — Footer visible con links de redes sociales
sf-01.5 — 404 page para ruta inexistente
sf-01.6 — Favicon y título del tab reflejan la tienda
sf-01.7 — Logo en navbar es clickeable y vuelve a Home
```

#### 1.3 Suite sf-02-catalog (~8 tests)
```
sf-02.0 — /search muestra grid de productos
sf-02.1 — Filtro por categoría funciona (click en chip → se filtra)
sf-02.2 — Buscador por texto filtra en tiempo real
sf-02.3 — Paginación visible y funcional (next/prev)
sf-02.4 — Producto sin stock muestra badge "Agotado"
sf-02.5 — Ordenar por precio funciona (menor/mayor)
sf-02.6 — Sin resultados muestra mensaje vacío
sf-02.7 — Producto con descuento muestra precio tachado + precio final
```

**Entregable Fase 1:** ~16 tests, Page Objects base, login helpers, storageState configurado.

---

### FASE 2 — Producto, Auth y Carrito Storefront (Semana 2)

#### 2.1 Suite sf-03-product-detail (~7 tests)
```
sf-03.0 — PDP carga imagen, nombre, precio, descripción
sf-03.1 — Selector de talle / color (si aplica) cambia selección
sf-03.2 — Botón "Agregar al carrito" agrega y muestra toast
sf-03.3 — Badge del carrito en navbar se incrementa
sf-03.4 — Producto sin stock → botón deshabilitado con mensaje
sf-03.5 — Botón de favorito (corazón) togglea estado
sf-03.6 — Breadcrumb muestra Home > Categoría > Producto
```

#### 2.2 Suite sf-04-auth (~8 tests)
```
sf-04.0 — /login muestra formulario de login (email + password)
sf-04.1 — Switch a registro muestra campos adicionales (nombre, teléfono, etc.)
sf-04.2 — Login con credenciales válidas → redirect a home
sf-04.3 — Login con credenciales inválidas → mensaje de error visible
sf-04.4 — Registro con datos válidos → mensaje de confirmación de email
sf-04.5 — Registro con email duplicado → error
sf-04.6 — Validaciones de formulario (campos requeridos, password mismatch)
sf-04.7 — Logout desde navbar → redirect a home, menú cambia a "Login"
```

#### 2.3 Suite sf-05-cart-checkout (~8 tests)
```
sf-05.0 — /cart muestra items agregados (imagen, nombre, precio, cantidad)
sf-05.1 — Cambiar cantidad actualiza subtotal
sf-05.2 — Eliminar item del carrito funciona
sf-05.3 — Carrito vacío muestra mensaje + CTA "Seguir comprando"
sf-05.4 — Botón "Pagar" redirige a checkout (MP o pantalla intermedia)
sf-05.5 — Resumen de pedido muestra subtotal + recargos + total
sf-05.6 — /payment-result?status=approved muestra éxito con número de orden
sf-05.7 — /payment-result?status=rejected muestra error con opción de reintentar
```

**Entregable Fase 2:** ~23 tests adicionales. Total acumulado: ~39 tests UI storefront.

---

### FASE 3 — Dashboard de Usuario y Responsive (Semana 3)

#### 3.1 Suite sf-06-user-dashboard (~7 tests)
```
sf-06.0 — /profile carga con tabs visibles (Info, Órdenes, Dominio, Facturación)
sf-06.1 — Tab "Información Personal" muestra nombre, email, teléfono
sf-06.2 — Editar info personal → guardar → toast éxito
sf-06.3 — Tab "Órdenes" lista las compras con estado y fecha
sf-06.4 — Click en orden despliega detalle (productos, total, estado pago)
sf-06.5 — Botón "Cambiar Contraseña" abre modal funcional
sf-06.6 — Sin órdenes → mensaje vacío
```

#### 3.2 Suite sf-07-favorites (~4 tests)
```
sf-07.0 — /favorites muestra productos marcados
sf-07.1 — Quitar favorito desde la lista lo remueve en tiempo real
sf-07.2 — Click en producto navega al PDP
sf-07.3 — Sin favoritos → mensaje vacío
```

#### 3.3 Suite sf-09-responsive (~6 tests, viewport mobile)
```
sf-09.0 — Navbar colapsa en hamburger menu
sf-09.1 — Hamburger menu se abre y muestra todos los links
sf-09.2 — Grid de productos cambia a 1-2 columnas
sf-09.3 — PDP layout se adapta (imagen arriba, info abajo)
sf-09.4 — Carrito legible en mobile
sf-09.5 — Footer apilado verticalmente
```

**Entregable Fase 3:** ~17 tests adicionales. Total acumulado: ~56 tests UI storefront.

---

### FASE 4 — Admin Panel del Storefront (Semana 4)

#### 4.1 Suite sf-08-admin-panel (~10 tests)
```
sf-08.0 — /admin-dashboard carga grid de secciones (cards con íconos)
sf-08.1 — Sección Productos: lista productos, botón Agregar, formulario funcional
sf-08.2 — Sección Productos: editar producto existente → guardar → toast
sf-08.3 — Sección Productos: eliminar producto → confirmación → desaparece
sf-08.4 — Sección Banners: subir imagen, reordenar, eliminar
sf-08.5 — Sección Logo: subir logo → preview actualizada
sf-08.6 — Sección FAQs: agregar pregunta/respuesta → visible en lista
sf-08.7 — Sección Pagos: ver config MP, plan actual, cuotas
sf-08.8 — Sección Usuarios: lista de usuarios registrados
sf-08.9 — Sección bloqueada por plan → mensaje "Upgrade tu plan"
```

**Entregable Fase 4:** ~10 tests. Total storefront acumulado: ~66 tests.

---

### FASE 5 — Admin Dashboard: Landing + Onboarding Wizard (Semana 5)

#### 5.1 Suite ad-01-landing (~5 tests)
```
ad-01.0 — Landing page carga (hero, pricing cards, servicios, testimonios)
ad-01.1 — Scroll a sección pricing muestra 3 planes con precios
ad-01.2 — CTA "Crear mi tienda" navega a /builder
ad-01.3 — Link "Blog" navega a /blog
ad-01.4 — Footer con links legales y contacto
```

#### 5.2 Suite ad-02-onboarding-wizard (~12 tests)
```
ad-02.0  — /builder carga Step 1 (elegir slug)
ad-02.1  — Slug válido → avanza; slug tomado → error inline
ad-02.2  — Step 2: upload de logo funciona (drag & drop o click)
ad-02.3  — Step 4: selección de template y paleta de colores
ad-02.4  — Step 5: auth con Google (verifica redirect y retorno)
ad-02.5  — Step 7: configuración de Mercado Pago
ad-02.6  — Step 8: formulario de datos del negocio (nombre, CUIT, dirección)
ad-02.7  — Step 9: validación de credenciales MP
ad-02.8  — Step 10: pantalla de resumen muestra todo lo ingresado
ad-02.9  — Step 11: checkbox de términos habilitado y funcional
ad-02.10 — Step 12: submit exitoso → redirect a /onboarding/status
ad-02.11 — /onboarding/status muestra estado "En revisión" con info
```

**Entregable Fase 5:** ~17 tests admin. Total acumulado: ~83 tests UI.

---

### FASE 6 — Admin Dashboard: Auth + Super Admin (Semana 6)

#### 6.1 Suite ad-03-auth-flows (~6 tests)
```
ad-03.0 — /login muestra botón Google + campo visual
ad-03.1 — /internal/login muestra formulario email/pass
ad-03.2 — Login super admin exitoso → redirect a /dashboard
ad-03.3 — Login con credenciales inválidas → error
ad-03.4 — /unauthorized se muestra correctamente
ad-03.5 — Logout cierra sesión y redirige a /
```

#### 6.2 Suite ad-04-super-admin-dashboard (~10 tests)
```
ad-04.0  — /dashboard carga con sidebar y KPIs en home
ad-04.1  — Sidebar muestra todos los módulos (clientes, métricas, leads, etc.)
ad-04.2  — /dashboard/metrics carga gráficos y totales
ad-04.3  — /dashboard/finance muestra tablas de conciliación
ad-04.4  — /dashboard/usage lista uso por cliente
ad-04.5  — /dashboard/plans muestra planes con límites
ad-04.6  — /dashboard/leads muestra funnel
ad-04.7  — /dashboard/coupons permite crear/editar cupón
ad-04.8  — /dashboard/emails muestra jobs y estado
ad-04.9  — /dashboard/backend-clusters lista proyectos Supabase
```

**Entregable Fase 6:** ~16 tests. Total acumulado: ~99 tests UI.

---

### FASE 7 — Admin Dashboard: Gestión de Clientes y Aprobaciones (Semana 7)

#### 7.1 Suite ad-05-client-management (~6 tests)
```
ad-05.0 — /dashboard/clients lista clientes con nombre, plan, estado
ad-05.1 — Búsqueda por nombre filtra la lista
ad-05.2 — Click en cliente navega a /client/:id
ad-05.3 — Ficha del cliente muestra tabs (overview, pagos, requirements, sync)
ad-05.4 — /dashboard/clients/new permite alta manual
ad-05.5 — Editar datos de cliente → guardar → toast
```

#### 7.2 Suite ad-06-approvals (~5 tests)
```
ad-06.0 — /dashboard/pending-approvals lista cuentas pendientes
ad-06.1 — Click en cuenta abre detalle de revisión
ad-06.2 — Botón "Aprobar" → confirmación → estado cambia a "approved"
ad-06.3 — Botón "Rechazar" → modal con motivo → estado cambia
ad-06.4 — Cuenta aprobada desaparece de la lista de pendientes
```

#### 7.3 Suite ad-07-billing (~4 tests)
```
ad-07.0 — /settings/billing muestra plan actual y estado de suscripción
ad-07.1 — Botón "Cambiar plan" muestra opciones disponibles
ad-07.2 — /dashboard/renewal-center lista renovaciones pendientes
ad-07.3 — Click en renovación abre detalle con acciones
```

**Entregable Fase 7:** ~15 tests. **Total final: ~114 tests UI.**

---

## Resumen por Fase

| Fase | Semana | Scope | Tests | Acumulado |
|------|--------|-------|:-----:|:---------:|
| 1 | S1 | Infra + Navegación Storefront | ~16 | 16 |
| 2 | S2 | Producto + Auth + Carrito | ~23 | 39 |
| 3 | S3 | User Dashboard + Responsive | ~17 | 56 |
| 4 | S4 | Admin Panel Storefront | ~10 | 66 |
| 5 | S5 | Landing + Wizard Admin | ~17 | 83 |
| 6 | S6 | Auth Admin + Super Dashboard | ~16 | 99 |
| 7 | S7 | Clientes + Aprobaciones + Billing | ~15 | 114 |

---

## Requisitos Previos (para cada ejecución)

1. **API** corriendo en `localhost:3000` (`npm run start:dev`)
2. **Web Storefront** corriendo en `localhost:5173` (`npm run dev`)
3. **Admin** corriendo en `localhost:5174` (`npm run dev`)
4. **Tenants provisionados** (los API E2E tests los crean en las suites 01-08)
5. **`.env.e2e`** con credenciales de Supabase y tenant slugs

## Patrones Técnicos

### Page Object Model (POM)
Cada página encapsula selectores y acciones:
```typescript
export class SearchPage {
  constructor(private page: Page) {}

  async goto() {
    await this.page.goto('/search');
    await this.page.waitForSelector('[data-testid="product-grid"]');
  }

  async searchFor(text: string) {
    await this.page.fill('[data-testid="search-input"]', text);
    await this.page.waitForResponse('**/products*');
  }

  async getProductCount() {
    return this.page.locator('[data-testid="product-card"]').count();
  }

  async clickProduct(index: number) {
    await this.page.locator('[data-testid="product-card"]').nth(index).click();
  }
}
```

### Auth via storageState
Login una vez, reutilizar la sesión:
```typescript
// En global-setup o beforeAll
const context = await browser.newContext();
const page = await context.newPage();
await loginAsUser(page, email, password);
await context.storageState({ path: 'auth-states/buyer-ui.json' });

// En el test
test.use({ storageState: 'auth-states/buyer-ui.json' });
```

### Selectores resilientes
Prioridad: `data-testid` > `role` > `text` > CSS selector.
Si los componentes no tienen `data-testid`, se agregan al frontend como parte de cada fase.

### Screenshots y Visual Regression (opcional, Fase 8+)
```typescript
await expect(page).toHaveScreenshot('home-loaded.png', { maxDiffPixelRatio: 0.01 });
```

---

## Riesgos y Mitigaciones

| Riesgo | Impacto | Mitigación |
|--------|---------|-----------|
| Componentes sin `data-testid` | Tests frágiles por selectores CSS | Agregar `data-testid` al frontend en cada fase |
| OAuth Google no testeable | No se puede automatizar popup Google | Mock de OAuth o bypass con token directo |
| Mercado Pago redirect externo | No se puede completar pago real | Mockear redirect MP o usar simulación como en API tests |
| Cambios de UI frecuentes | Tests se rompen | POM + selectores `data-testid` minimizan impacto |
| 3 servicios necesarios (API+WEB+Admin) | Setup complejo | Script `start-all.sh` que levanta los 3 |
| Rate limiting de Supabase Auth | 429 en tests rápidos | Reusar sesiones via storageState |

---

## Extensiones Futuras (post Fase 7)

- **Fase 8:** Visual Regression con screenshots de referencia
- **Fase 9:** Accessibility testing (axe-core + Playwright)
- **Fase 10:** Performance testing (Lighthouse CI dentro de Playwright)
- **Fase 11:** CI/CD Pipeline (GitHub Actions ejecutando la suite completa)
- **Fase 12:** Cross-browser (Firefox, WebKit además de Chromium)

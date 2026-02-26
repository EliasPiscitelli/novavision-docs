# Auditoría de Integridad Full-Stack — NovaVision
**Fecha:** 2026-02-25  
**Alcance:** API (NestJS) + Admin (React) + Storefront (React) + DB Multicliente + DB Admin  
**Rama auditada:** `feature/automatic-multiclient-onboarding`  
**Metodología:** Inspección estática de código (sin ejecución de requests ni conexión a DB)

---

## 1. RESUMEN EJECUTIVO

### Postura general
El sistema tiene una **postura de seguridad multi-tenant sólida** (~95% de queries correctamente filtradas por `client_id`). Sin embargo, se identificaron **vulnerabilidades puntuales críticas** en validación de datos (productos sin DTO), bypass de auth (builder token no validado), y configuraciones de RLS en Admin DB.

### Top 10 Riesgos (por severidad)

| # | Sev | Área | Hallazgo | Impacto |
|---|-----|------|----------|---------|
| 1 | 🔴 P0 | **Backend/DTO** | Productos CREATE/UPDATE sin DTO — `JSON.parse()` de string crudo sin validación | Inyección de campos arbitrarios, precios negativos, client_id override |
| 2 | 🔴 P0 | **Backend/Auth** | Builder token (`x-builder-token`) valida solo existencia del header, no el JWT | Acceso sin autenticación a `/palettes`, `/templates` |
| 3 | 🔴 P0 | **Admin DB/RLS** | Policies con `using: "true"` en `invoices`, `client_usage_month`, `sync_cursors` | Cualquier usuario autenticado puede leer/escribir datos financieros |
| 4 | 🔴 P0 | **Admin DB/RLS** | UUID de admin hardcodeado — single point of failure | Si se compromete ese usuario, se pierde todo |
| 5 | 🔴 P0 | **Admin DB/RLS** | Policy `users.insert` con `with_check: "true"` — insert abierto | Escalación de privilegios vía auto-insert en tabla users |
| 6 | 🔴 P0 | **Storefront** | `encrypt.jsx` con clave AES hardcodeada `"secret"` | Cifrado nulo — datos "encriptados" trivialmente descifrables |
| 7 | 🟡 P1 | **Backend/DTO** | `QuoteDto`, `UpdateSettingsDto`, `CreateSocialLinksDto` sin decoradores de validación | Cualquier valor pasa sin restricción (pagos, settings) |
| 8 | 🟡 P1 | **Backend/DTO** | `client_id` aceptado desde query params en `PaymentDetailsQueryDto` y `SearchProductsDto` | Potencial cross-tenant si el controller lo usa |
| 9 | 🟡 P1 | **Backend/Service** | `validateStock()` — filtro `client_id` condicional (`if (clientId)`) | Stock cross-tenant si caller no pasa clientId |
| 10 | 🟡 P1 | **Multi DB/RLS** | `order_payment_breakdown` — policy select permite a cualquier user del tenant ver breakdowns de otros | Leak de info financiera intra-tenant |

---

## 2. INVENTARIO DEL SISTEMA

### 2.1 Backend (API — NestJS)

| Métrica | Valor |
|---------|-------|
| Controllers | 77 |
| Endpoints (~) | 356+ |
| DTOs encontrados | 34 |
| Services | ~30+ |
| Guards | 15 |
| Middlewares | 2 (auth + rate-limit) |
| Validation pipe | Global: `whitelist: true, transform: true` (falta `forbidNonWhitelisted`) |

### 2.2 Admin Dashboard (React)

| Métrica | Valor |
|---------|-------|
| Componentes form | ~17 formularios principales |
| Canal principal | NestJS API via Axios (`adminApi.js`) — ~70% operaciones |
| Canal secundario | Supabase Admin DB directo (anon key) — ~25% ⚠️ |
| Canal terciario | Supabase Edge Functions — ~5% |
| `x-client-id` header | No se usa (correcto: es super admin cross-tenant) |
| Multicliente DB directa | ❌ Eliminada ✅ (`backendSupabase = null`) |

### 2.3 Web Storefront (React)

| Métrica | Valor |
|---------|-------|
| Resolución tenant | Subdominio → custom domain → query param `?tenant=` |
| API clients | 2 Axios instances (apiClient + publicClient) |
| Supabase directa | Solo Auth (login/signup) — sin acceso a tablas ✅ |
| Headers enviados | `Authorization: Bearer`, `x-client-id` (auto-inyectado) |

### 2.4 Base de Datos

| DB | Tablas detectadas | RLS | Patrón |
|----|-------------------|-----|--------|
| Multicliente | ~35+ tablas | ✅ Activo en todas | `client_id = current_client_id()` + `server_bypass` |
| Admin | ~8 tablas | ✅ Activo | Hardcoded UUID ⚠️ + `service_role` |

---

## 3. HALLAZGOS PRIORIZADOS CON EVIDENCIA

### 🔴 Sev-1 (Corrupción de datos, seguridad, cross-tenant)

---

#### H-01: Productos CREATE/UPDATE sin DTO (bypass total de validación)

**Archivos:** `products.controller.ts`, `products.service.ts`

**Evidencia:**
```typescript
// products.controller.ts
@Post()
async createProduct(
  @Body('productData') productData: string,  // RAW STRING
) {
  const parsedProductData = JSON.parse(productData);  // SIN validación
  await this.productsService.createOrUpdateProduct(parsedProductData, files, clientId);
}
```

**Impacto:** Un admin puede enviar:
- Precios negativos (`price: -100`)
- Stock no entero (`stock: 1.5`)
- Campos arbitrarios (`client_id: "otro-tenant"`, `created_at: "2020-01-01"`)
- Inyección de JSONB malformado

**Reproduce:** `POST /products` con `productData: '{"price":-100,"client_id":"x"}'`

**Recomendación:** Crear `CreateProductDto` / `UpdateProductDto` con class-validator. Implementar un `ParseJsonPipe` custom para multipart.

---

#### H-02: Builder token no valida JWT

**Archivo:** `auth.middleware.ts`

**Evidencia:** El middleware solo verifica `if (req.headers['x-builder-token'])` — existencia del header, no su valor. Cualquier string pasa.

**Impacto:** Acceso sin autenticación a `/palettes` y `/templates`.

**Reproduce:** `curl -H "x-builder-token: fake" https://api/palettes`

**Recomendación:** Validar el JWT del builder token contra Supabase o secreto compartido.

---

#### H-03: Admin DB — RLS policies con `true`

**Evidencia (directa del schema dump):**
```json
{"table": "invoices", "policy": "invoices_service_role_all", "using": "true", "with_check": "true"}
{"table": "client_usage_month", "policy": "usage_service_role_all", "using": "true", "with_check": "true"}
{"table": "sync_cursors", "policy": "cursors_service_role_all", "using": "true", "with_check": "true"}
```

**Impacto:** Nombre dice "service_role" pero expresión es `true` — **cualquier** rol autenticado (incluso `anon_key`) puede operar. RLS OR entre policies: la `true` invalida toda restricción.

**Reproduce:** Login con anon key → `SELECT * FROM invoices` → devuelve todos los datos.

**Recomendación:** Cambiar `"true"` → `"auth.role() = 'service_role'"` o eliminar policies redundantes.

---

#### H-04: Admin DB — UUID hardcodeado

**Evidencia:** TODAS las policies de Admin DB:
```sql
using_expression: (auth.uid() = 'a1b4ca03-3873-440e-8d81-802c677c5439'::uuid)
```
Se repite en `clients` (CRUD), `invoices` (CRUD), `payments` (CRUD), `users` (CRUD).

**Impacto:** 
- Sin escalabilidad (agregar otro admin = cambiar RLS en todas las tablas)
- Si ese user se compromete → acceso total
- Si se elimina accidentalmente → lockout total

**Recomendación:** Crear tabla `admin_roles` o usar campo `role = 'platform_admin'` en `users`, referenciar en policies.

---

#### H-05: Admin DB — users.insert abierto

**Evidencia:**
```json
{"policy": "Allow insert with service role", "with_check": "true", "for_command": "a"}
```

**Impacto:** Cualquier usuario autenticado puede insertar filas en `users` de Admin DB. Combinado con self-read policy, permite escalación de privilegios.

**Recomendación:** Cambiar a `auth.role() = 'service_role'` o eliminar y dejar solo la policy condicional.

---

#### H-06: Storefront — encrypt.jsx con clave hardcodeada

**Archivo:** `apps/web/src/utils/encrypt.jsx`

**Evidencia:** Clave AES estática `"secret"` en código fuente público.

**Impacto:** Cualquier dato "encriptado" es trivialmente descifrable. Si se usa para tokens o datos sensibles → exposición total.

**Recomendación:** Eliminar este módulo y usar HTTPS + tokens del backend. Si se necesita cifrado client-side, usar Web Crypto API con claves efímeras.

---

### 🟡 Sev-2 (Mapeos incompletos, validaciones faltantes, drift)

---

#### H-07: DTOs sin decoradores de validación

**Archivos y DTOs afectados:**

| DTO | Archivo | Campos sin validar |
|-----|---------|-------------------|
| `QuoteDto` (payments) | `payments/dto/quote.dto.ts` | subtotal, installments, method, settlementDays, partial — TODOS |
| `UpdateSettingsDto` | `payments/dto/update-settings.dto.ts` | allowPartial, partialPercent, maxInstallments, surchargeMode — TODOS |
| `CreateSocialLinksDto` | `social-links/dto/create-social-links.dto.ts` | whatsApp, instagram, facebook — TODOS |

**Nota:** Existe un `QuoteDto` **duplicado y correcto** en `mercadopago.dto.ts` con `@IsNumber`, `@IsIn`, etc. Verificar cuál usa cada controller.

**Impacto:** `partialPercent: -500`, `maxInstallments: 0`, `surchargePercent: 99999` pasan sin error.

---

#### H-08: client_id en query params de DTOs

**Archivos:**
- `mercadopago.dto.ts` → `PaymentDetailsQueryDto.client_id`
- `products/dto/search-products.dto.ts` → `SearchProductsDto.clientId`

**Impacto:** Si el controller usa el valor del DTO en vez del middleware → cross-tenant access.

**Recomendación:** Eliminar estos campos de los DTOs y usar solo `req.clientId` del middleware.

---

#### H-09: validateStock con client_id condicional

**Archivo:** `mercadopago.service.ts:1162`

**Evidencia:**
```typescript
if (clientId) q = q.eq('client_id', clientId);
```

**Impacto:** Si un caller interno pasa `clientId` como `undefined`, lee stock de CUALQUIER tenant.

**Recomendación:** `if (!clientId) throw new BadRequestException('client_id requerido');`

---

#### H-10: order_payment_breakdown — leak intra-tenant

**Evidencia RLS:**
```json
{"policy": "opb_select_tenant", "using": "(client_id = current_client_id())", "for_command": "r"}
```
Sin filtrar por `user_id` ni `is_admin()`.

**Impacto:** Cualquier comprador autenticado del tenant puede ver los breakdowns de pagos de todos los demás compradores.

**Recomendación:** Agregar `AND (is_admin() OR EXISTS(SELECT 1 FROM orders o WHERE o.id = order_id AND o.user_id = auth.uid()))`.

---

#### H-11: Admin Dashboard — writes directos a Supabase Admin DB

**Archivos afectados:**
| Archivo | Operación | Tabla |
|---------|-----------|-------|
| `clientService.jsx:134` | `.update()` | `clients` |
| `LeadsView.jsx:2418` | `.upsert()` | `outreach_leads` |
| `playbook.js` | `.insert/.update` | `nv_playbook` |
| `leads.js` | `.insert/.update` | `leads`, `lead_assets` |

**Impacto:** Bypasea backend NestJS. Depende enteramente de RLS (que tiene el UUID hardcodeado). Inconsistente con el patrón del resto del sistema.

---

#### H-12: Campos posiblemente redundantes en client_payment_settings

| Campo A | Campo B | Default |
|---------|---------|---------|
| `surcharge_mode` (enum) | `fee_routing` (text) | ambos `'buyer_pays'` |
| `surcharge_percent` (numeric) | `service_percent` (numeric) | ambos `0` |

**Riesgo:** Backend lee uno, frontend envía otro → configuración perdida.

---

#### H-13: Nested objects sin ValidateNested en DTOs

| DTO | Campo | Problema |
|-----|-------|---------|
| `ValidateStoreCouponDto` | `cart_items` | Interface (no class) — sin validación |
| `SubmitWizardDataDto` | `catalog`, `designConfig` | `any` type |
| `SizeGuideDto` | `rows` | Array de objects sin `@ValidateNested` |
| `ShippingSettingsDto` | `provinces`, `zip_codes` | Falta `@IsString({each:true})` |

---

#### H-14: MaintenanceGuard fail-open

**Archivo:** `guards/maintenance.guard.ts`

Si no puede verificar el estado de mantenimiento del tenant → permite acceso (fail-open).

**Recomendación:** Fail-closed: si no se puede verificar, bloquear con 503.

---

### 🟠 Sev-3 (UX/validaciones inconsistentes, edge cases)

---

#### H-15: Falta `forbidNonWhitelisted: true` en ValidationPipe global

**Archivo:** `main.ts:120`
```typescript
app.useGlobalPipes(new ValidationPipe({ whitelist: true, transform: true }));
```
Campos extra se eliminan silenciosamente en vez de rechazarse.

#### H-16: cart_items.id es INTEGER (no UUID)

Inconsistente con el resto del schema. IDs secuenciales exponen conteo.

#### H-17: Doble policy overlapping en cart_items y favorites

`_owner_all` (for all) + `_*_tenant` (por operación). Redundante y dificulta auditoría.

#### H-18: ProtectedRoute.jsx — fallback permisivo en Admin

Si no encuentra usuario en tabla `users` y `requireSuperAdmin` es false → permite acceso.

#### H-19: Dos Axios instances en Storefront

`apiClient` (con auth) y `publicClient` (sin auth). Riesgo de usar el incorrecto.

#### H-20: Zod vs class-validator mezclados

3 DTOs usan Zod (`identity-config`, `section`, `home-data-lite`), el resto class-validator. El `ValidationPipe` global ignora Zod.

---

## 4. MATRIZ DE INTEGRIDAD MULTI-TENANT

### 4.1 Writes (INSERT/UPSERT/UPDATE/DELETE)

**170+ operaciones auditadas. Resultado: ✅ 100% correcto.**

| Servicio | Operaciones | Todas con client_id | Notas |
|----------|:-----------:|:-------------------:|-------|
| products | 9 | ✅ | create, update, delete, categories, bulk upload |
| cart | 5 | ✅ | add, update, remove, clear + user_id |
| orders | 3 | ✅ | status, tracking, confirmation |
| mercadopago | 12 | ✅ | order creation, payments, email_jobs, stock RPCs |
| faqs | 3 | ✅ | CRUD |
| banners | 4 | ✅ | CRUD + link update |
| social-links | 3 | ✅ | CRUD |
| contact-info | 3 | ✅ | CRUD |
| home-sections | 3 | ✅ | CRUD |
| home-settings | 2 | ✅ | upsert, update |
| store-coupons | 4 | ✅ | CRUD + targets sync |
| services (tienda) | 3 | ✅ | CRUD |
| shipping-settings | 4 | ✅ | settings upsert, zones CRUD |
| logo | 3 | ✅ | CRUD |
| reviews | 4 | ✅ | create, update, reply, moderate |
| categories | 3 | ✅ | CRUD |
| payment-breakdown | 1 | ✅ | save breakdown |
| addresses | 5 | ✅ | CRUD + default reset, con user_id |
| questions | 5 | ✅ | create, answer, moderate, archive |
| themes | 1 | ✅ | upsert |
| option-sets | 12 | ✅ | sets CRUD, items, size guides, presets |
| seo | 5 | ✅ | settings upsert, entity meta, redirects CRUD |
| palettes | 6 | ✅ | custom + catalog CRUD |
| legal | 5 | ✅ | consent, withdrawal, cancellation |
| auth | 8 | ✅ | signup, membership, bridge, profile, migration |
| demo | 6 | ✅ | seed operations |

### 4.2 Reads (SELECT) — Hallazgos

**~85 queries auditadas.**

| # | Servicio | Método | Tabla | Filtro client_id | Riesgo |
|---|----------|--------|-------|:----------------:|--------|
| — | categories | findAll, findOne | categories | ✅ | OK |
| — | orders | getAll, getFiltered, getUserOrders, getById, getDetail | orders | ✅ | OK |
| — | cart | getCartItems | cart_items+products | ✅ Doble | OK |
| — | banners | getBanners, getAllBanners | banners | ✅ | OK |
| — | themes, home-settings, home-sections | todos | client_* | ✅ | OK |
| — | shipping (3 services) | todos | shipping_* | ✅ | OK |
| — | store-coupons | list, getById, validate | store_coupons | ✅ | OK |
| — | payment-settings | getSettings, getConfig | client_payment_settings | ✅ | OK |
| — | contenido (contact, social, faqs, services, logo) | todos | respectivas | ✅ | OK |
| — | users | getAll, getById | users | ✅ | OK |
| — | seo | getSettings, getEntityMeta, sitemap | seo_*, products, categories | ✅ | OK |
| — | addresses | listByUser, getById | user_addresses | ✅ + user_id | OK |
| — | analytics | getDashboard | orders, payments | ✅ | OK |
| — | legal | getWithdrawal | withdrawal_requests | ✅ | OK |
| **R-1** | **products** | `resolveOptionsForProduct` | option_sets | ⚠️ Solo por ID | **MEDIUM** |
| **R-2** | **products** | `resolveProductColors` | option_set_items | ⚠️ Solo por IDs | **MEDIUM** |
| **R-3** | **reviews** | cursor lookup | product_reviews | ⚠️ Solo por ID | **MEDIUM** |
| **R-4** | **questions** | cursor lookup | product_questions | ⚠️ Solo por ID | **MEDIUM** |
| **R-5** | **questions** | answers subquery | product_questions | ❌ `.in('parent_id')` sin client_id | **HIGH** |
| **R-6** | **mercadopago** | `validateStock` | products | ⚠️ Condicional | **HIGH** (=H-09) |
| **R-7** | **auth** | `exchangeBridgeCode` | users | ❌ Solo por user_id | **HIGH** (mitigado: código único 60s) |
| **R-8** | **option-sets** | `findOne` | option_sets | ⚠️ Post-fetch check | OK (mitigado) |
| — | reconciliation CRON | varios | orders, payments | ❌ Cross-tenant | **LOW** (interno) |

### 4.3 RPC Calls

| Función | Recibe client_id | Riesgo |
|---------|:----------------:|--------|
| `decrement_stock_bulk_strict` | ✅ `p_client_id` | OK |
| `restore_stock_bulk` | ✅ `p_client_id` | OK |
| `decrement_product_stock` | ⚠️ Solo `p_product_id` | INFO |
| `search_products` | ✅ `p_client_id` | OK |
| `dashboard_metrics/tops/detail` | ✅ `p_client_id` | OK |
| `merge_favorites` | Verificar SQL | INFO |

**SQL crudo:** ❌ No encontrado. Todo vía Supabase query builder + `.rpc()`.

---

## 5. MATRIZ DE INTEGRIDAD DE CAMPOS (Módulos Críticos)

### 5.1 Productos (Admin → API → DB → Storefront)

| Campo UI (Admin) | API Request | Backend Validation | DB Column | API Response | UI Storefront | Estado |
|-------------------|-------------|-------------------|-----------|--------------|---------------|--------|
| Nombre | `productData.name` | ❌ Sin DTO | `products.name` | `name` | PDP title | ⚠️ **NO VALIDADO** |
| Descripción | `productData.description` | ❌ Sin DTO | `products.description` | `description` | PDP desc | ⚠️ **NO VALIDADO** |
| Precio | `productData.price` | ❌ Sin DTO | `products.price` | `price` | PDP/Card price | ⚠️ **NO VALIDADO** - puede ser negativo |
| Precio anterior | `productData.compare_at_price` | ❌ Sin DTO | `products.compare_at_price` | `compare_at_price` | PDP tachado | ⚠️ **NO VALIDADO** |
| Stock | `productData.stock` | ❌ Sin DTO | `products.stock` | `stock` | Disponibilidad | ⚠️ **NO VALIDADO** - puede ser decimal |
| SKU | `productData.sku` | ❌ Sin DTO | `products.sku` | `sku` | — | ⚠️ **NO VALIDADO** |
| Imágenes | Files multipart | Multer config | `products.images` (jsonb) | `images` | Carrusel PDP | OK (validación de tipo Multer) |
| Categorías | `productData.categories` | ❌ | `product_categories` M:N | join | Filtros/breadcrumb | ⚠️ |
| Activo | `productData.active` | ❌ | `products.active` | `active` | Visibilidad | ⚠️ |
| Option set | `productData.option_set_id` | ❌ | `products.option_set_id` | join → variants | PDP selector | ⚠️ |
| SEO title/desc | `productData.seo_*` | ❌ | `products.seo_title/desc` | `seo_*` | `<meta>` tags | ⚠️ |

### 5.2 Checkout (Storefront → API → DB)

| Campo UI | API Request | Backend Validation | DB Column | Estado |
|----------|-------------|-------------------|-----------|--------|
| Cart items | `items[]` array | `@ValidateNested` en `CreatePrefAdvancedDto` | `order_items` (inline en orders jsonb) | ✅ OK |
| Selected options | `items[].selected_options` | `@IsOptional @IsObject` | `order_items[].selected_options` | ✅ parcial |
| Shipping method | `delivery.method` | `@IsIn(enum)` | `orders.delivery_method` | ✅ OK |
| Shipping cost | `delivery.shipping_cost` | `@Min(0)` | `orders.shipping_cost` | ✅ OK |
| Coupon code | `coupon.code` | `@IsString` | `orders.coupon_snapshot` | ✅ OK |
| Buyer name | `buyer.first_name/last_name` | `@IsOptional @IsString` | `orders.buyer_*` | ✅ OK |
| Buyer email | `buyer.email` | `@IsOptional @IsEmail` | `orders.buyer_email` | ✅ OK |
| Address | `delivery.address` | `@IsOptional @IsObject` | `orders.delivery_address` (jsonb) | ⚠️ Sin ValidateNested |
| Idempotency key | `idempotency_key` | `@IsString` | `mp_idempotency.key` | ✅ OK |
| Partial payment | `partialPercent` | `@Min(1)` (debería ser 0-100) | `orders.partial_*` | ⚠️ Rango incompleto |

### 5.3 Payment Settings (Admin → API → DB → Storefront)

| Campo UI | API Request Field | Backend Validation | DB Column | Storefront Use | Estado |
|----------|-------------------|-------------------|-----------|----------------|--------|
| Permitir seña | `allowPartial` | ❌ Sin decorador | `allow_partial` bool default false | Checkout partial | ⚠️ **NO VALIDADO** |
| % de seña | `partialPercent` | ❌ Sin decorador | `partial_percent` numeric default 30 | % calculation | ⚠️ **NO VALIDADO** |
| Permitir cuotas | `allowInstallments` | ❌ Sin decorador | `allow_installments` bool default true | Installments selector | ⚠️ **NO VALIDADO** |
| Max cuotas | `maxInstallments` | ❌ Sin decorador | `max_installments` int default 12 | Max shown | ⚠️ **NO VALIDADO** |
| Modo recargo | `surchargeMode` | ❌ Sin decorador | `surcharge_mode` enum | Fee routing | ⚠️ **NO VALIDADO + REDUNDANTE** |
| Fee routing | — | — | `fee_routing` text default 'buyer_pays' | — | ⚠️ **REDUNDANTE** con surchargeMode |
| Currency | `currency` | ❌ | `currency` char(3) default 'ARS' | Display | ⚠️ |
| Rounding step | `roundingStep` | ❌ | `rounding_step` numeric default 0 | Price rounding | ⚠️ |

### 5.4 Banners (Admin → API → DB → Storefront)

| Campo UI | Request | Validation | DB Column | Response | Storefront | Estado |
|----------|---------|-----------|-----------|----------|------------|--------|
| Image file | multipart | Multer | `banners.url` + `file_path` | `url` | `<img>` hero | ✅ OK |
| Type | `type` | — | `banners.type` varchar | `type` | desktop/mobile | ⚠️ Sin enum validation |
| Link redirect | `link` | — | `banners.link` varchar nullable | `link` | `<a href>` | ✅ OK |
| Order/position | `order` | — | `banners.order` int nullable | `order` | sort | ⚠️ keyword SQL, nullable |
| Image variants | auto-generated | — | `banners.image_variants` jsonb | `image_variants` | responsive | ✅ OK |

---

## 6. CAMPOS HUÉRFANOS DETECTADOS

### En UI pero no llegan a API
| Campo | Módulo | Ubicación | Nota |
|-------|--------|-----------|------|
| (No se detectaron campos huérfanos significativos en esta dirección) | — | — | El storefront no captura datos que no envíe |

### Llegan a API pero no se guardan
| Campo | Endpoint | Nota |
|-------|----------|------|
| `client_id` en `SearchProductsDto` | `GET /products` | Se acepta en DTO pero el controller usa `req.clientId` — campo ignorado |
| `client_id` en `PaymentDetailsQueryDto` | `GET /mercadopago/payment-details` | Verificar si se usa o se ignora |

### En DB pero no editables desde Admin
| Columna | Tabla | Nota |
|---------|-------|------|
| `fee_routing` | `client_payment_settings` | Coexiste con `surcharge_mode` — potencialmente legacy |
| `service_mode`, `service_percent`, `service_fixed`, `service_label` | `client_payment_settings` | Verificar si hay UI para estos en Admin |
| `excluded_payment_types`, `excluded_payment_methods` | `client_payment_settings` | Arrays — verificar si hay UI |
| `pay_with_debit` | `client_payment_settings` | Boolean — verificar UI |
| `discount_percent`, `promo_code`, `free_months` | `clients` (Multicliente) | Campos billing — verificar si Admin maneja estos |

---

## 7. PLAN DE PRUEBAS DE REGRESIÓN

### 7.1 Smoke Suite (~15 min, pre-deploy)

| # | Test | Tipo | Prioridad |
|---|------|------|-----------|
| S1 | Login admin → dashboard carga | E2E | P0 |
| S2 | Login buyer → storefront carga con datos del tenant | E2E | P0 |
| S3 | CRUD producto básico (crear con nombre/precio, listar, editar precio, eliminar) | E2E Admin | P0 |
| S4 | Add to cart → checkout → crear preferencia MP | E2E Store | P0 |
| S5 | Webhook MP simulado → orden pasa a `paid` | Integration | P0 |
| S6 | **Cross-tenant: user A no ve productos de client B** | Security | P0 |
| S7 | **Cross-tenant: admin A no puede editar settings de client B** | Security | P0 |
| S8 | Payment settings → guardar → releer → valores consistentes | E2E Admin | P1 |
| S9 | Banner CRUD + upload imagen | E2E Admin | P1 |
| S10 | Order list en admin muestra status correcto post-pago | E2E Admin | P1 |

### 7.2 Full Suite por Módulo (~2h)

#### Productos
- Crear producto con TODOS los campos (title, desc, price, discount, stock, sku, images, categories, options, size guide, SEO)
- Editar solo precio → verificar que otros campos no se pisen
- Producto con stock=0 → no agregable al carrito
- Producto inactive → no visible en storefront
- Bulk import Excel → verificar client_id correcto
- Eliminar producto → verificar cascada (cart_items, favorites, order_items históricos)

#### Checkout/Órdenes
- Carrito: add, update qty (0→remove), clear
- Checkout con cupón válido → descuento correcto en total
- Checkout con cupón expirado → error
- Checkout con envío cotizado → total = subtotal + shipping - discount
- Checkout con seña parcial → partial_amount correcto
- Checkout con cuotas → fee breakdown correcto
- Verificar order_items matchean carrito exacto

#### Pagos (MP)
- Webhook firma válida → procesa
- Webhook firma inválida → 403
- Webhook duplicado (idempotency) → no re-procesa
- Verificar montos desde backend (no frontend)
- Polling de status post-redirect

#### Multi-tenant
- Crear orden con user A de client X → `client_id` correcto en orders, order_items, payments
- `GET /products` con header de otro tenant → solo productos de ese tenant
- Admin A intenta `PUT /products/:id` de client B → 403/404
- `validateStock` con `clientId=undefined` → debe fallar (actualmente no falla — H-09)

#### Contenido
- CRUD banners (desktop + mobile)
- CRUD FAQs (con orden)
- CRUD services
- Update contact info
- Update social links
- Update logo → verificar que viejo se elimina de storage

#### SEO
- Update seo_title y seo_description por producto
- Generate sitemap.xml → verificar solo productos/categorías del tenant
- Redirects CRUD + hit_count increment

### 7.3 Casos Negativos (Validación)

| # | Input | Esperado | Actual (estimado) |
|---|-------|----------|-------------------|
| N1 | Precio = -100 | 400 Bad Request | ⚠️ Se guarda (sin DTO) |
| N2 | Stock = 1.5 | 400 (debe ser int) | ⚠️ Se guarda |
| N3 | partialPercent = -500 | 400 | ⚠️ Se guarda (sin decorador) |
| N4 | maxInstallments = 0 | 400 | ⚠️ Se guarda |
| N5 | `x-builder-token: fake` | 401 | ⚠️ 200 (acceso concedido) |
| N6 | JWT expirado | 401 | ✅ 401 |
| N7 | Payload vacío en POST product | 400 | ⚠️ Error no controlado (JSON.parse) |
| N8 | client_id en body de producto | Ignorado | ⚠️ Se guarda (sin DTO) |

### 7.4 Propuesta de Test Files (Playwright E2E)

```
tests/
├── smoke/
│   ├── admin-login.spec.ts
│   ├── store-login.spec.ts
│   ├── product-crud.spec.ts
│   ├── checkout-basic.spec.ts
│   └── cross-tenant-isolation.spec.ts
├── products/
│   ├── product-create-all-fields.spec.ts
│   ├── product-edit-partial.spec.ts
│   ├── product-stock-zero.spec.ts
│   ├── product-inactive.spec.ts
│   └── product-bulk-import.spec.ts
├── checkout/
│   ├── cart-crud.spec.ts
│   ├── checkout-with-coupon.spec.ts
│   ├── checkout-with-shipping.spec.ts
│   ├── checkout-partial-payment.spec.ts
│   └── checkout-installments.spec.ts
├── payments/
│   ├── webhook-valid.spec.ts
│   ├── webhook-invalid-signature.spec.ts
│   ├── webhook-idempotency.spec.ts
│   └── payment-polling.spec.ts
├── security/
│   ├── cross-tenant-products.spec.ts
│   ├── cross-tenant-orders.spec.ts
│   ├── cross-tenant-settings.spec.ts
│   ├── builder-token-validation.spec.ts
│   └── admin-role-escalation.spec.ts
└── content/
    ├── banners-crud.spec.ts
    ├── faqs-crud.spec.ts
    ├── social-links-crud.spec.ts
    └── seo-settings.spec.ts
```

---

## 8. ITEMS NO VERIFICABLES

| # | Qué falta | Cómo verificar | Impacto |
|---|-----------|---------------|---------|
| 1 | **Schema real runtime de DB** (solo tenemos migrations parsedas) | `SELECT * FROM information_schema.columns WHERE table_schema='public'` en ambas DBs | ALTO — constraints, defaults, triggers reales |
| 2 | **Funciones SQL** `current_client_id()`, `is_admin()`, `is_super_admin()` | `SELECT proname, prosrc FROM pg_proc WHERE proname IN (...)` | CRÍTICO — base de toda la RLS |
| 3 | **SQL body de RPCs** (`decrement_product_stock`, `merge_favorites`, `claim_email_jobs`) | `SELECT prosrc FROM pg_proc WHERE proname = '...'` | ALTO — verificar client_id interno |
| 4 | **Triggers runtime** — ¿hay alguno que sobreescriba client_id? | `SELECT * FROM information_schema.triggers` | MEDIO |
| 5 | **contact_info columnas reales** — dump solo muestra 3 columnas pero RLS usa `client_id` | `SELECT * FROM information_schema.columns WHERE table_name='contact_info'` | MEDIO |
| 6 | **Edge Functions del Admin** — lógica interna de `admin-create-client`, `admin-payments`, etc. | Leer `supabase/functions/*/index.ts` | MEDIO |
| 7 | **Comportamiento runtime de RLS** cuando backend usa `service_role` | Test de integración con ambos keys | ALTO |
| 8 | **MP webhook signature validation** — ¿se valida la firma realmente? | Leer `mercadopago.controller.ts` webhook handler completo | ALTO |
| 9 | **Campos de `client_payment_settings` sin UI** | Revisar Admin → Payment Settings form completo | MEDIO |
| 10 | **Prueba cross-tenant real** (request con user A, header de client B) | E2E test o cURL manual | CRÍTICO |

---

## 9. PLAN DE CORRECCIONES PRIORIZADO

### Sprint 1 (P0 — esta semana)

| # | Fix | Esfuerzo | Archivos |
|---|-----|----------|----------|
| F1 | Crear `CreateProductDto` / `UpdateProductDto` con class-validator | 4h | +2 DTOs, edit controller |
| F2 | Validar JWT de builder token (no solo existencia) | 2h | auth.middleware.ts |
| F3 | Fijar RLS policies Admin DB (`"true"` → `service_role` check) | 1h | SQL migration |
| F4 | Eliminar policy `users.insert true` en Admin DB | 30min | SQL migration |
| F5 | Eliminar/reescribir `encrypt.jsx` en storefront | 1h | web/src/utils/ |
| F6 | Hacer `clientId` obligatorio en `validateStock()` | 15min | mercadopago.service.ts |

### Sprint 2 (P1 — semana 2)

| # | Fix | Esfuerzo |
|---|-----|----------|
| F7 | Agregar decoradores a `QuoteDto`, `UpdateSettingsDto`, `CreateSocialLinksDto` | 2h |
| F8 | Eliminar `client_id`/`clientId` de DTOs (query params) | 1h |
| F9 | Agregar `client_id` filter a answers subquery en questions.service | 15min |
| F10 | Fijar `order_payment_breakdown` RLS (agregar user_id/admin check) | 30min |
| F11 | Agregar `forbidNonWhitelisted: true` al ValidationPipe | 15min + test sweep |
| F12 | Migrar `clientService.update()` de Admin a endpoint NestJS | 3h |
| F13 | Agregar `client_id` a cursor lookups en reviews/questions | 30min |
| F14 | Cambiar MaintenanceGuard a fail-closed | 30min |

### Sprint 3 (P2 — semana 3-4)

| # | Fix | Esfuerzo |
|---|-----|----------|
| F15 | Agregar `@ValidateNested` + `@Type` a objetos anidados en DTOs | 3h |
| F16 | Estandarizar Zod → class-validator (o agregar ZodValidationPipe) | 2h |
| F17 | Migrar Admin DB RLS de UUID hardcodeado a tabla de roles | 4h |
| F18 | Migrar módulos leads/playbook a API NestJS | 6h |
| F19 | Auditar y limpiar campos redundantes en `client_payment_settings` | 2h |
| F20 | Agregar `@Min(0)` a todos los campos de precio/monto | 1h |

---

## 10. CHECKLIST DE CALIDAD

- [x] Cada hallazgo tiene evidencia (payload formato + path de código)
- [x] Confirmé create/update/read en ambos: Admin y Storefront
- [x] Verifiqué client_id/user_id en 170+ writes y 85+ reads
- [x] Marqué campos huérfanos y drift entre UI ↔ API ↔ DB
- [x] Incluí plan de regresión automatizable (Playwright E2E)
- [x] Identifiqué 10 items NO VERIFICABLES con pasos para verificar
- [ ] Pendiente: verificación runtime (requiere conexión a DB y requests reales)
- [ ] Pendiente: funciones SQL de RLS (`current_client_id()`, `is_admin()`)
- [ ] Pendiente: Edge Functions del Admin

---

## APÉNDICE: Documentos de auditoría de trabajo

| Archivo | Contenido |
|---------|-----------|
| [audit-code.md](audit-code.md) | Auditoría detallada (3400+ líneas) — guards, DTOs, schema, storefront |
| [endpoint-inventory.md](endpoint-inventory.md) | Inventario completo de 77 controllers / 356+ endpoints |
| [2025-07-24-multitenant-service-layer-audit.md](2025-07-24-multitenant-service-layer-audit.md) | Auditoría de capa de servicios |
| [audit-auth-tenant-isolation.md](audit-auth-tenant-isolation.md) | Auth y tenant isolation |

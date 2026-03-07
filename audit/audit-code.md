

# Auditoría de Integridad Full-Stack — NovaVision

## ⚠️ Nota preliminar de seguridad

**Detecto que el archivo .env con credenciales reales (DB URLs, API keys, tokens de Supabase, Mercado Pago, OpenAI, Postmark, Netlify, JWT secrets) está incluido en el contexto de esta conversación.** Esto es un **Sev-1 de seguridad**. Recomiendo rotar todas estas credenciales tras esta sesión de auditoría. No voy a utilizar estas credenciales para conectarme ni ejecutar nada — la auditoría será por inspección de código.

---

## Fase A — Inventario Real

> **Inventario de endpoints completo:** Ver [endpoint-inventory.md](endpoint-inventory.md) — 76 controllers, ~450+ endpoints, 34+ DTOs mapeados con guards, DTOs y hallazgos de validación.

---

## RESUMEN EJECUTIVO (Hallazgos Preliminares — Top 10 Riesgos)

Basándome en la inspección del código disponible y las instrucciones/schema documentados:

1. **🔴 Sev-1 — Credenciales reales en .env expuestas en contexto de chat** — Passwords de DB, service role keys, MP tokens, OpenAI key, Postmark key, JWT secret están en texto plano.

2. **🔴 Sev-1 — Políticas RLS en Admin DB con `using_expression: "true"` y `with_check_expression: "true"`** — Las tablas `client_usage_month`, `invoices`, `sync_cursors` tienen políticas que permiten acceso irrestricto (`true`) para `service_role` o incluso sin condición, lo que podría ser explotable si la key se filtra.

3. **🔴 Sev-1 — RLS en Admin hardcodea un UUID específico para admin** — Todas las policies de `clients`, `invoices`, `payments`, `users` en Admin DB usan `auth.uid() = 'a1b4ca03-3873-440e-8d81-802c677c5439'::uuid`. Si ese usuario se compromete, se pierde todo. No hay ni roles ni tabla de admins, es un single point of failure.

4. **🟡 Sev-2 — Tabla `contact_info` en Multicliente no muestra `client_id` en el schema dump proporcionado** — Solo se ven columnas `id`, `titleinfo`, `description`. Sin embargo, las RLS policies sí referencian `client_id`. Necesito verificar si la columna existe y no se incluyó en el dump, o si hay un mismatch real.

5. **🟡 Sev-2 — `cart_items` usa `id` integer (serial) en vez de UUID** — Inconsistente con el resto del schema que usa UUID para PKs. Podría generar conflictos en escenarios de migración o replicación.

6. **🟡 Sev-2 — Tablas de diagnóstico (`cart_items_products_mismatch`, `cart_items_products_mismatch_secure`) sin RLS visible** — No aparecen en el dump de policies. Si tienen data sensible y RLS activo pero sin policies → bloqueo total o leak.

7. **🟡 Sev-2 — `client_payment_settings` tiene campos posiblemente redundantes** — `surcharge_mode` (USER-DEFINED) vs `fee_routing` (text), `surcharge_percent` vs `service_percent`. Riesgo de que el backend lea uno y el front envíe otro.

8. **🟡 Sev-2 — Doble policy overlapping en `cart_items` y `favorites`** — Tienen tanto policies `*_tenant` (por operación) como `*_owner_all` (for all). Las policies OR entre sí en Postgres, lo que podría ampliar permisos inesperadamente.

9. **🟡 Sev-2 — `order_payment_breakdown` tiene dos policies de select** — `opb_select_admin` y `opb_select_tenant`, ambas para `r`. La de tenant no exige ser admin ni owner, solo `client_id = current_client_id()`. Cualquier usuario autenticado del tenant puede ver breakdowns de pagos de otros usuarios.

10. **🟠 Sev-3 — Políticas de `users` en Admin DB permiten insert con `true`** — Policy "Allow insert with service role" tiene `with_check_expression: "true"` sin restricción, y coexiste con "Insertar usuario si tiene rol válido". Redundancia + riesgo.

---

## FASE A1 — Mapa de Entidades y Campos (desde Schema Proporcionado)

### Base de Datos Multicliente

| Tabla | Columnas Clave | PK Type | `client_id` | RLS Activo | Notas |
|-------|---------------|---------|-------------|------------|-------|
| `banners` | id, url, file_path, type, link, order, client_id, image_variants (jsonb) | UUID | ✅ | ✅ | image_variants es JSONB para variantes responsive |
| `cart_items` | id, user_id, product_id, quantity, created_at, client_id | **INTEGER** (serial) | ✅ | ✅ | ⚠️ PK no es UUID |
| `cart_items_products_mismatch` | cart_item_id, item_client_id, product_id, product_client_id | N/A | parcial | ❓ Sin policies visibles | Tabla de diagnóstico |
| `cart_items_products_mismatch_secure` | client_id, user_id, product_id, quantity | N/A | ✅ | ❓ Sin policies visibles | Tabla de diagnóstico |
| `categories` | id, name (varchar 255), description, created_at, client_id | UUID | ✅ | ✅ | |
| `client_extra_costs` | id, client_id, name, type (enum), amount, apply_to (enum), active, position, created_at | UUID | ✅ | ✅ | Costos adicionales configurables |
| `client_mp_fee_overrides` | id, client_id, method (enum), installments_from/to, settlement_days, percent_fee, fixed_fee, active | UUID | ✅ | ✅ | Override de fees MP por cliente |
| `client_payment_settings` | id, client_id, allow_partial, partial_percent, allow_installments, max_installments, surcharge_mode (enum), surcharge_percent, allow_custom_extras, ... +14 campos más | UUID | ✅ | ✅ | ⚠️ Campos posiblemente redundantes (fee_routing vs surcharge_mode, service_percent vs surcharge_percent) |
| `clients` | id, name, logo_url, mp_public_key, mp_access_token, email_admin, plan, monthly_fee, connection_type, base_url, is_active, +14 campos billing/promo | UUID | es la PK | ✅ | Tabla central de tenants |
| `contact_info` | id, titleinfo, description, **[client_id?]** | UUID | ⚠️ No en dump pero sí en RLS | ✅ | **VERIFICAR** |
| `orders` | (no detallada en dump) | — | ✅ (per RLS) | ✅ | Referenciada en policies |
| `payments` | (no detallada en dump) | — | ✅ (per RLS) | ✅ | |
| `products` | (no detallada en dump) | — | ✅ (per RLS) | ✅ | |
| `product_categories` | (no detallada en dump) | — | ✅ (per RLS) | ✅ | M:N |
| `favorites` | (inferida de RLS) | — | ✅ | ✅ | user_id + client_id |
| `logos` | (inferida de RLS) | — | ✅ | ✅ | |
| `social_links` | (inferida de RLS) | — | ✅ | ✅ | |
| `services` | (inferida de RLS) | — | ✅ | ✅ | |
| `faqs` | (inferida de RLS) | — | ✅ | ✅ | |
| `email_jobs` | (inferida de RLS) | — | ✅ | ✅ | Compleja: order_id join |
| `mp_idempotency` | (inferida de RLS) | — | ✅ | ✅ | Solo select admin |
| `order_payment_breakdown` | (inferida de RLS) | — | ✅ | ✅ | ⚠️ Doble policy select |
| `cors_origins` | (inferida de RLS) | — | ❌ | ✅ | Solo super_admin |
| `mp_fee_table` | (inferida de RLS) | — | ❌ | ✅ | Solo super_admin |
| `users` | (inferida de RLS) | — | ✅ | ✅ | |

### Base de Datos Admin

| Tabla | Columnas Clave | `client_id` | RLS | Notas |
|-------|---------------|-------------|-----|-------|
| `clients` | id, name, email_admin, plan, monthly_fee, base_url, connection_type, +billing fields, commission_percent | es la PK | ✅ (hardcoded UUID) | ⚠️ Single admin UUID |
| `users` | id, email, role, created_at, client_id | ✅ | ✅ | Role default 'client' |
| `invoices` | id, client_id, month, total_sales, commission, fixed_fee, total_due, paid, paid_at, sent_reminder | ✅ | ✅ | ⚠️ `true` policy |
| `payments` | id, client_id, type, amount, paid_at, method, note | ✅ | ✅ | |
| `client_usage_month` | client_id+period (composite PK?), orders_count, revenue, storage_mb, imported_at | ✅ | ✅ | ⚠️ `true` policy |
| `mv_usage_by_client_month` | Materialized view — mismas cols | ✅ | ❌ (es MV) | |
| `sync_cursors` | client_id (PK), last_synced_at, last_etag | ✅ | ✅ | ⚠️ `true` + `service_role` policies |

---

## FASE A2/A3 — Para completar la auditoría necesito inspeccionar código

Para construir la **Matriz de Integridad de Campos completa**, necesito examinar archivos específicos. Voy a listar lo que necesito inspeccionar y lo que puedo verificar con la información disponible:

### NO VERIFICABLE (sin inspección de código fuente)

| Ítem | Qué falta | Cómo verificarlo |
|------|-----------|-------------------|
| **Endpoints reales del backend** | Listar controllers/routes en src del API | `find apps/api/src -name "*.controller.ts" -o -name "*.module.ts"` |
| **DTOs y validaciones** | Class-validator decorators | `find apps/api/src -name "*.dto.ts"` |
| **Schema completo de products, orders, order_items** | No están en el dump proporcionado | `SELECT * FROM information_schema.columns WHERE table_name IN ('products','orders','order_items','shipping_settings','coupons','addresses','size_guides','option_sets','option_items')` |
| **Formularios del Admin** | Componentes React con inputs | `find apps/admin/src -name "*.jsx" -o -name "*.tsx" | grep -i form` |
| **Formularios del Storefront** | Checkout, cart, account | `find apps/web/src -name "*.jsx" -o -name "*.tsx" | grep -iE "checkout|cart|address"` |
| **Services del backend** | Lógica de negocio y queries | `find apps/api/src -name "*.service.ts"` |
| **Migrations** | DDL real | `find apps/api -name "*.sql" -path "*/migration*"` |
| **Supabase functions del Admin** | Edge functions | `ls apps/admin/supabase/functions/` |

---

## HALLAZGOS CONFIRMADOS (con evidencia del schema/policies proporcionados)

### 🔴 Hallazgo #1 — Sev-1: RLS Policies con `true` en Admin DB

**Evidencia:**
```json
{
  "table_name": "client_usage_month",
  "policy_name": "usage_service_role_all",
  "using_expression": "true",
  "with_check_expression": "true",
  "for_command": "*"
}
```
Y también:
```json
{
  "table_name": "invoices",
  "policy_name": "invoices_service_role_all",
  "using_expression": "true",
  "with_check_expression": "true",
  "for_command": "*"
}
```
```json
{
  "table_name": "sync_cursors",
  "policy_name": "cursors_service_role_all",
  "using_expression": "true",
  "with_check_expression": "true",
  "for_command": "*"
}
```

**Riesgo:** Estas policies permiten acceso a **cualquier rol autenticado** (no solo `service_role`). La policy se llama `*_service_role_all` pero la expresión es `true`, no `auth.role() = 'service_role'`. Esto significa que un usuario con `anon_key` podría leer/escribir invoices y usage data.

**Nota:** Coexisten con policies que sí verifican `service_role` (`client_usage_month_service_role_all` y `sync_cursors_service_role_all`), pero dado que Postgres RLS usa **OR entre policies**, la policy `true` invalida cualquier restricción.

**Recomendación:** Cambiar `using_expression` y `with_check_expression` de `true` a `auth.role() = 'service_role'` o eliminar las policies redundantes.

---

### 🔴 Hallazgo #2 — Sev-1: Admin DB hardcodea UUID de admin

**Evidencia:**
```json
{
  "table_name": "clients",
  "policy_name": "Admin can select clients",
  "using_expression": "(auth.uid() = 'a1b4ca03-3873-440e-8d81-802c677c5439'::uuid)"
}
```
Este patrón se repite en **todas** las tablas del Admin DB (clients, invoices, payments, users) para todas las operaciones (select, insert, update, delete).

**Riesgo:**
- Single point of failure: si ese usuario se compromete, se pierde todo.
- No escalable: agregar otro admin requiere cambiar RLS en todas las tablas.
- Si ese user ID se elimina accidentalmente de Supabase Auth, se pierde acceso admin.

**Recomendación:** Crear una tabla `admin_users` o usar un campo `role = 'super_admin'` en la tabla `users` de Admin DB, y referenciar eso en las policies.

---

### 🔴 Hallazgo #3 — Sev-1: `users` en Admin DB permite insert `true`

**Evidencia:**
```json
{
  "table_name": "users",
  "policy_name": "Allow insert with service role",
  "with_check_expression": "true",
  "for_command": "a"
}
```

**Riesgo:** Cualquier usuario autenticado (incluso con `anon_key`) puede insertar filas en la tabla `users` del Admin DB. Combinado con la policy de self-read (`id = auth.uid()`), un atacante podría:
1. Registrarse en Supabase Auth del proyecto Admin
2. Insertar una fila en `users` con su `auth.uid()` y `role = 'admin'`
3. Si alguna lógica de la app lee el role de esta tabla, escalar privilegios

**Recomendación:** Cambiar a `auth.role() = 'service_role'` o eliminar esta policy y dejar solo la de "Insertar usuario si tiene rol válido".

---

### 🟡 Hallazgo #4 — Sev-2: `order_payment_breakdown` leak a usuarios del tenant

**Evidencia:**
```json
{
  "table_name": "order_payment_breakdown",
  "policy_name": "opb_select_tenant",
  "using_expression": "(client_id = current_client_id())",
  "for_command": "r"
}
```

**Riesgo:** Cualquier usuario autenticado del tenant puede leer **todos** los breakdowns de pagos de **todas** las órdenes del tenant (no solo las suyas). Información financiera sensible (montos, fees, cuotas) de otros compradores queda expuesta.

**Recomendación:** Agregar condición de ownership:
```sql
(client_id = current_client_id() AND (
  is_admin() OR 
  EXISTS (SELECT 1 FROM orders o WHERE o.id = order_payment_breakdown.order_id AND o.user_id = auth.uid())
))
```

---

### 🟡 Hallazgo #5 — Sev-2: Overlapping policies en `cart_items` y `favorites`

**Evidencia (cart_items):**
- `cart_items_owner_all` — `for_command: "*"` con `user_id = auth.uid() AND client_id = ...`
- `cart_items_select_tenant` — `for_command: "r"` con `is_admin() OR user_id = auth.uid()`
- `cart_items_insert_tenant` — `for_command: "a"` con `is_admin() OR user_id = auth.uid()`
- `cart_items_update_tenant` — `for_command: "w"` con `is_admin() OR user_id = auth.uid()`
- `cart_items_delete_tenant` — `for_command: "d"` con `is_admin() OR user_id = auth.uid()`

**Riesgo:** La policy `cart_items_owner_all` (`for all`) se superpone con las individuales. Dado que Postgres usa OR entre policies del mismo comando, la `owner_all` es redundante para el owner pero las `*_tenant` amplían el acceso al admin. No es un bug funcional, pero sí complejidad innecesaria que dificulta auditoría y podría causar confusión al modificar policies.

El mismo patrón ocurre en `favorites`.

**Recomendación:** Simplificar: dejar solo las policies por operación (`select/insert/update/delete`) que ya incluyen `is_admin() OR user_id = auth.uid()`, y eliminar la `_owner_all`.

---

### 🟡 Hallazgo #6 — Sev-2: `client_payment_settings` campos potencialmente redundantes

**Evidencia del schema:**
```
surcharge_mode  → USER-DEFINED (enum) — default 'buyer_pays'
surcharge_percent → numeric — default 0
fee_routing     → text — default 'buyer_pays'
service_mode    → text — default 'mp_fee'
service_percent → numeric — default 0
service_fixed   → numeric — default 0
service_label   → text — default 'Costo del Servicio'
```

**Riesgo:** `surcharge_mode` (enum) y `fee_routing` (text) parecen representar conceptos similares con defaults iguales (`buyer_pays`). Si el backend lee uno y el front envía otro, se pierden configuraciones. Lo mismo para `surcharge_percent` vs `service_percent`.

**Verificación necesaria:** Inspeccionar el código del backend (`PaymentSettingsService` o similar) y del admin para confirmar qué campo se usa en cada flujo.

---

### 🟡 Hallazgo #7 — Sev-2: `contact_info` posible falta de `client_id` en schema

**Evidencia del dump proporcionado:**
```json
[
  {"table_name": "contact_info", "column_name": "id", ...},
  {"table_name": "contact_info", "column_name": "titleinfo", ...},
  {"table_name": "contact_info", "column_name": "description", ...}
]
```
Solo 3 columnas. Pero las policies RLS referencian `client_id`:
```json
{
  "policy_name": "contact_info_select_tenant",
  "using_expression": "(client_id = current_client_id())"
}
```

**Riesgo:** O bien el dump está incompleto (falta `client_id` y posiblemente más columnas como email, phone, address, hours), o la columna fue agregada después del dump, o hay un mismatch real que haría que las RLS policies fallen con error.

**Verificación necesaria:** `SELECT column_name, data_type FROM information_schema.columns WHERE table_name = 'contact_info' ORDER BY ordinal_position;`

---

### 🟠 Hallazgo #8 — Sev-3: `cart_items.id` es INTEGER, no UUID

**Evidencia:**
```json
{
  "table_name": "cart_items",
  "column_name": "id",
  "data_type": "integer",
  "column_default": "nextval('cart_items_id_seq'::regclass)"
}
```

**Riesgo:** Inconsistente con el patrón UUID del resto de tablas. Si el frontend o API asume UUID en algún lugar, habrá type mismatch. IDs secuenciales también exponen conteo de operaciones (information disclosure menor).

---

## MATRIZ DE INTEGRIDAD DE CAMPOS (Parcial — basada en info disponible)

> **Nota:** Esta matriz está limitada a lo que puedo inferir del schema dump y policies. Para completarla necesito inspeccionar controllers, services, DTOs del backend y componentes del frontend.

### Tabla: `banners` (Multicliente)

| Campo UI | API Request | DB Column | DB Type | Default | Nullable | RLS | Estado |
|----------|------------|-----------|---------|---------|----------|-----|--------|
| Image URL | `url` | `url` | varchar | — | NOT NULL | ✅ tenant | **NO VERIFICABLE** — falta ver form admin |
| File Path | `file_path` | `file_path` | varchar | — | NOT NULL | ✅ | **NO VERIFICABLE** |
| Type (desktop/mobile) | `type` | `type` | varchar | — | NOT NULL | ✅ | **NO VERIFICABLE** |
| Link/redirect | `link` | `link` | varchar | — | YES | ✅ | **NO VERIFICABLE** |
| Order/position | `order` | `order` | integer | — | YES | ✅ | ⚠️ field name `order` es keyword SQL |
| Image variants | `image_variants` | `image_variants` | jsonb | — | YES | ✅ | **NO VERIFICABLE** — falta ver si front envía |

### Tabla: `client_payment_settings` (Multicliente)

| Campo UI | API Request | DB Column | DB Type | Default | Estado |
|----------|------------|-----------|---------|---------|--------|
| Permitir seña | ? | `allow_partial` | boolean | false | **NO VERIFICABLE** |
| % de seña | ? | `partial_percent` | numeric | 30 | **NO VERIFICABLE** |
| Permitir cuotas | ? | `allow_installments` | boolean | true | **NO VERIFICABLE** |
| Max cuotas | ? | `max_installments` | integer | 12 | **NO VERIFICABLE** |
| Surcharge mode | ? | `surcharge_mode` | enum | 'buyer_pays' | ⚠️ Posible redundancia con `fee_routing` |
| Surcharge % | ? | `surcharge_percent` | numeric | 0 | ⚠️ Posible redundancia con `service_percent` |
| Fee routing | ? | `fee_routing` | text | 'buyer_pays' | ⚠️ Posible redundancia |
| Service mode | ? | `service_mode` | text | 'mp_fee' | **NO VERIFICABLE** |
| Service % | ? | `service_percent` | numeric | 0 | **NO VERIFICABLE** |
| Service fixed | ? | `service_fixed` | numeric | 0 | **NO VERIFICABLE** |
| Service label | ? | `service_label` | text | 'Costo del Servicio' | **NO VERIFICABLE** |
| Pay with debit | ? | `pay_with_debit` | boolean | false | **NO VERIFICABLE** |
| Excluded payment types | ? | `excluded_payment_types` | text[] | null | **NO VERIFICABLE** |
| Excluded payment methods | ? | `excluded_payment_methods` | text[] | null | **NO VERIFICABLE** |
| Currency | ? | `currency` | char(3) | 'ARS' | **NO VERIFICABLE** |
| Rounding step | ? | `rounding_step` | numeric | 0 | **NO VERIFICABLE** |
| Settlement days | ? | `default_settlement_days` | integer | 10 | **NO VERIFICABLE** |
| Allowed settlement days | ? | `allowed_settlement_days` | int[] | {0,10,35} | **NO VERIFICABLE** |

---

## PLAN DE PRUEBAS DE REGRESIÓN (Propuesta)

### Smoke Suite (rápida, ~15 min)

| # | Test | Tipo | Prioridad |
|---|------|------|-----------|
| 1 | Login admin → dashboard carga | E2E | P0 |
| 2 | Login user → storefront carga con datos del tenant | E2E | P0 |
| 3 | CRUD producto básico (crear, editar nombre/precio, listar) | E2E Admin | P0 |
| 4 | Add to cart → checkout → crear preferencia MP | E2E Storefront | P0 |
| 5 | Webhook MP → orden pasa a `paid` | Integration | P0 |
| 6 | **Cross-tenant: user A no ve productos de client B** | Security | P0 |
| 7 | **Cross-tenant: admin A no puede editar settings de client B** | Security | P0 |
| 8 | Payment settings → guardar → releer → valores consistentes | E2E Admin | P1 |
| 9 | Banners CRUD + upload imagen | E2E Admin | P1 |
| 10 | Order list en admin muestra status correcto post-pago | E2E Admin | P1 |

### Full Suite (completa, ~2h)

#### Módulo Productos
- Crear producto con todos los campos (title, desc, price, discount, stock, sku, images, categories, option sets, size guide)
- Editar producto parcialmente (solo precio) → verificar que otros campos no se pisen
- Eliminar producto → verificar que desaparece de storefront y cart_items asociados
- Producto con stock 0 → no se puede agregar al carrito
- Producto inactive → no se muestra en storefront

#### Módulo Checkout/Órdenes
- Carrito: add, update qty, remove, clear
- Checkout con cupón válido → descuento correcto
- Checkout con cupón expirado → rechazo
- Checkout con envío cotizado → total correcto
- Crear orden → verificar order_items matches carrito
- Payment con seña parcial → flujo correcto
- Payment con cuotas → fee breakdown correcto

#### Módulo Pagos (MP)
- Webhook con firma válida → procesa
- Webhook con firma inválida → rechaza (403)
- Webhook duplicado (idempotency) → no re-procesa
- Verificar que montos vienen del backend (no del front)

#### Módulo Multi-tenant
- Crear orden con user de client A → `client_id` correcto en `orders`, `order_items`, `payments`
- Intentar `GET /products` con `x-client-id` de otro tenant → solo ve productos de su tenant
- Admin de client A intenta `PUT /products/:id` de client B → 403/404
- Super admin puede operar cross-tenant (si implementado)

#### Módulo Contenido
- CRUD banners (desktop + mobile + variantes)
- CRUD FAQs
- CRUD services
- Update contact info
- Update social links
- Update logo

### Casos Negativos Prioritarios
- Enviar precio como string al crear producto
- Enviar stock negativo
- Enviar `client_id` vacío/null en header
- JWT expirado → 401
- Payload vacío en POST/PUT → errores de validación claros
- Campos `required` en DB sin valor → error 400, no 500

---

## LISTA DE "NO VERIFICABLE" — Qué falta para completar

| # | Qué falta | Cómo obtenerlo | Impacto en auditoría |
|---|-----------|---------------|---------------------|
| 1 | **Schema completo** de products, orders, order_items, shipping_*, coupons, addresses, option_sets, option_items, size_guides, reviews | `SELECT table_name, column_name, data_type, is_nullable, column_default FROM information_schema.columns WHERE table_schema='public' ORDER BY table_name, ordinal_position;` en ambas DBs | Alto — sin esto no puedo completar la matriz |
| 2 | **Controllers del backend** — lista de endpoints reales | `find apps/api/src -name "*.controller.ts" -exec head -50 {} \;` | Alto — no puedo mapear UI→API |
| 3 | **DTOs del backend** — validaciones | `find apps/api/src -name "*.dto.ts"` | Alto — no puedo verificar validación |
| 4 | **Services del backend** — queries reales | `find apps/api/src -name "*.service.ts"` | Alto — no puedo verificar client_id filtering |
| 5 | **Componentes form del Admin** | `find apps/admin/src -name "*Form*" -o -name "*Editor*" -o -name "*Modal*"` | Alto — no puedo mapear campos UI |
| 6 | **Componentes del Storefront** (cart, checkout, PDP) | `find apps/web/src -path "*/pages/*" -name "*.jsx" -o -name "*.tsx"` | Alto |
| 7 | **API client / hooks del frontend** | `find apps/web/src -path "*/api/*" -o -path "*/hooks/*"` | Medio |
| 8 | **Supabase functions** del admin | `ls -la apps/admin/supabase/functions/*/` | Medio — Edge Functions bypassean RLS |
| 9 | **Guards y middleware** del backend | `find apps/api/src -name "*.guard.ts" -o -name "*.middleware.ts"` | Alto — tenant isolation |
| 10 | **Migrations SQL** | `find apps/api -name "*.sql" -path "*migrat*"` | Medio — schema evolution |
| 11 | **Funciones SQL custom** (`current_client_id()`, `is_admin()`, `is_super_admin()`) | `SELECT proname, prosrc FROM pg_proc WHERE proname IN ('current_client_id','is_admin','is_super_admin');` | **Crítico** — todas las RLS dependen de estas |

---

## PRÓXIMOS PASOS

Para completar esta auditoría necesito que me des acceso a inspeccionar los archivos de código fuente. Puedo hacerlo en fases:

**Fase inmediata (prioridad máxima):**
1. Inspeccionar las funciones SQL `current_client_id()`, `is_admin()`, `is_super_admin()` — son la base de TODA la seguridad RLS.
2. Inspeccionar `auth.middleware.ts` y `tenant-context.guard.ts` del backend.
3. Obtener schema completo de tablas faltantes (products, orders, etc.).

**Fase siguiente:**
4. Mapear controllers → services → queries para los flujos críticos (productos, checkout, pagos).
5. Mapear formularios del admin → API calls → campos enviados.
6. Verificar los campos redundantes de `client_payment_settings`.

---

# Fase B — Auditoría Completa: Products CRUD Flow (End-to-End)

> Fecha: 2026-02-25
> Archivos inspeccionados:
> - `src/products/products.controller.ts` (693 líneas)
> - `src/products/products.service.ts` (2037 líneas)
> - `src/products/dto/search-products.dto.ts` (55 líneas)
> - `src/products/products.module.ts` (14 líneas)
> - `src/option-sets/option-sets.controller.ts` (173 líneas)
> - `src/option-sets/option-sets.service.ts` (814 líneas)
> - `src/option-sets/dto/create-option-set.dto.ts`
> - `src/option-sets/dto/update-option-set.dto.ts`
> - `src/option-sets/dto/size-guide.dto.ts`
> - `src/categories/categories.controller.ts` (108 líneas)
> - `src/categories/categories.service.ts` (90 líneas)
> - `src/common/utils/client-id.helper.ts`
> - `src/common/utils/storage-path.helper.ts`
> - `src/guards/roles.guard.ts`

**Nota:** No existen DTOs de create/update para productos — los datos llegan como `JSON.parse(body.productData)` string en un form-data multipart. No hay DTO para categorías tampoco (`@Body() dto: any`).

---

## B.1 — PRODUCTS CONTROLLER: Inventario de Endpoints

### B.1.1 — `GET /products` (Listado paginado)

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /products` |
| **Guards/Decoradores** | Ninguno (público) |
| **Query params** | `page` (default 1), `limit` (default 10) |
| **client_id** | `getClientId(req)` → `req.clientId` (resuelto por TenantContextGuard) |
| **DB client** | `adminClient` (service_role, bypasea RLS) |
| **Tablas tocadas** | `products`, `product_categories`, `categories` |
| **Queries** | 1) `products` WHERE `client_id = X` + paginación, order by `created_at` desc. 2) `product_categories` WHERE `client_id = X`. 3) `categories` WHERE id IN (category_ids) AND `client_id = X` |
| **Response** | `{ products: [...], totalItems: number }` — cada producto con campo `categories` (array de `{id, name}`) y `weightGrams` (aliased de `weight_grams`) |
| **Cache** | ETag basado en `getTableStamp()` (MAX updated_at + count). `Cache-Control: public, max-age=30` para anónimos, `private, max-age=20` para admins. Soporte 304. |
| **Admin view** | Si el JWT tiene `role = admin|super_admin`, o query param `includeUnavailable=true`, se incluyen productos con `available=false` |

**🟡 Hallazgo B.1.1-a:** El `limit` no tiene cap máximo en el controller (solo en el service con `Math.min(100, ...)`). Un usuario podría pasar `limit=100` y obtener una página grande, pero está cappeado a 100 en el service.

**🟡 Hallazgo B.1.1-b:** La query de `product_categories` trae TODAS las relaciones del tenant, no solo las de los productos de la página actual. Para un tenant con muchos productos, esto es ineficiente — carga todas las relaciones product-category en memoria y luego filtra en JS.

**🟢 Bien:** `client_id` se aplica en las 3 queries.

---

### B.1.2 — `POST /products` (Crear producto)

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /products` |
| **Guards/Decoradores** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')`, `@UseGuards(PlanLimitsGuard)`, `@PlanAction('create_product')` |
| **Body** | `multipart/form-data` con field `productData` (JSON string) + files (imágenes) |
| **Interceptor** | `AnyFilesInterceptor` — max 10 files, 5MB cada uno, solo `image/*` |
| **client_id** | `getClientId(req)` |
| **Validación DTO** | **❌ NO HAY DTO** — `JSON.parse(productData)` sin validación class-validator |
| **Tablas tocadas** | `products` (INSERT), `product-images` (Storage upload), `product_categories` (DELETE + INSERT) |
| **Response** | `{ message: 'Producto creado correctamente', productId: string }` |
| **Campos aceptados** | Se filtran por `ALLOWED_FIELDS`: name, description, sku, filters, originalPrice, discountedPrice, currency, available, quantity, material, promotionTitle, promotionDescription, discountPercentage, validFrom, validTo, featured, bestSell, sendMethod, tags, imageUrl, weight_grams, option_mode, option_set_id, option_config |

**🔴 Hallazgo B.1.2-a (Sev-2): NO HAY VALIDACIÓN DE INPUT.** Los datos del producto llegan como JSON string en un campo form-data y se parsean con `JSON.parse()`. No hay DTO con class-validator. Cualquier valor es aceptado para cualquier campo. Campos numéricos se parsean con `parseFloat()` / `parseInt()` con fallback a 0, pero no hay validación de rangos, tipos de campo, ni sanitización de strings.

**🔴 Hallazgo B.1.2-b (Sev-2): Whitelist (ALLOWED_FIELDS) no incluye todos los campos posibles.** Si un atacante envía un campo como `slug`, `client_id`, `id`, `created_at`, etc., el filtro `ALLOWED_FIELDS` los descartaría — excepto que `client_id` se fuerza en el insert directamente. Sin embargo, `productData.id` se usa para decidir si es update. Un usuario podría forzar un update de otro producto si envía un `id` válido.

**🟡 Hallazgo B.1.2-c:** El `ALLOWED_FIELDS` incluye `imageUrl` lo cual permite que se persista un `imageUrl` arbitrario desde el body (sin ser un archivo subido). Esto podría permitir inyectar URLs externas en el campo imageUrl.

**🟡 Hallazgo B.1.2-d:** Si `files` está vacío, retorna 400 "No files uploaded. At least one image is required." — esto fuerza al menos una imagen en la creación, lo cual es correcto.

**🟢 Bien:** `client_id` se fuerza desde `getClientId(req)`, no desde el body. Guards de roles y plan limits están presentes.

---

### B.1.3 — `PUT /products/:id` (Actualizar producto)

| Atributo | Valor |
|---|---|
| **Ruta** | `PUT /products/:id` |
| **Guards/Decoradores** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **Body** | `multipart/form-data` con field `productData` (JSON string) + files opcionales |
| **Interceptor** | `AnyFilesInterceptor` — max 10 files, 5MB |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (UPDATE), `product-images` (Storage upload), `product_categories` (DELETE + INSERT) |
| **Response** | `{ message: 'Producto actualizado correctamente', productId: string }` |

**🟡 Hallazgo B.1.3-a:** Falta `@UseGuards(PlanLimitsGuard)` y `@PlanAction(...)` — no se validan límites del plan en update, solo en create. Esto es probablemente intencional, pero debería documentarse.

**🟡 Hallazgo B.1.3-b:** Si no hay files ni imageUrl en el body, retorna 400. Pero si hay imageUrl (string/array) en el body sin archivos, se pasa a `createOrUpdateProduct` que los procesa — podría mantener URLs existentes válidas.

**🟢 Bien:** El `id` se toma del `:id` param y se fuerza en `parsedProductData.id = id`. El service aplica `.eq('client_id', clientId)` en el update.

---

### B.1.4 — `DELETE /products/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `DELETE /products/:id` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (SELECT imageUrl, DELETE), `product-images` (Storage remove) |
| **Response** | `{ message: 'Product deleted successfully' }` |

**🟡 Hallazgo B.1.4-a:** El delete NO elimina las filas de `product_categories` asociadas. Si hay FK constraint con ON DELETE CASCADE, no es problema. Pero si no, quedan filas huérfanas en `product_categories`.

**🟢 Bien:** Elimina las imágenes del Storage antes de borrar el registro. `client_id` se filtra correctamente.

---

### B.1.5 — `POST /products/upload/excel` (Bulk upload)

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /products/upload/excel` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **Interceptor** | `FileInterceptor('file')` — memoryStorage, 5MB, `spreadsheetFileFilter` |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (UPSERT en batches de 50), `product_categories` (batch DELETE + INSERT), `categories` (SELECT + INSERT si auto-create) |
| **Response** | `{ message, total, success, failed, errors[], createdCategories[] }` |

**Lógica notable:**
- Mapeo de columnas español → inglés (e.g. `Nombre` → `name`, `Precio_Original` → `originalPrice`)
- Validación por fila: name obligatorio, price >= 0, quantity >= 0, moneda en {ARS, USD}, fecha from <= to, descuento 0-100
- Match por SKU para updates (si no tiene UUID válido, busca por SKU)
- Auto-creación de categorías si no existen
- Preserva imágenes existentes en updates (busca imageUrl del producto existente)
- Batch de 50 filas por upsert

**🟢 Bien:** `ALLOWED_FIELDS` se aplica vía COLUMN_MAPPING. `client_id` se fuerza en cada fila. Validación de filas es clara.

**🟡 Hallazgo B.1.5-a:** El upsert usa `onConflict: 'id'` + `.eq('client_id', clientId)`. Sin embargo, si un atacante en el Excel pone un UUID de un producto de otro tenant, el upsert con `client_id=X` no coincidirá con el ID existente (que tiene otro client_id) y creará un nuevo producto. Esto no es un leak de datos, pero podría crear filas duplicadas.

---

### B.1.6 — `GET /products/download` (Exportar Excel)

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /products/download` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (SELECT sin imageUrl) |
| **Response** | archivo `.xlsx` |

**🟡 Hallazgo B.1.6-a:** La query de download hace `select('id, name, ..., "weightGrams", ..., categories')` — el campo `categories` en la tabla products (si existe como columna) no es lo mismo que las categorías de la junction table. Las categorías se exportan como lo que esté en la columna `categories` del producto, NO como los nombres de las categorías asociadas via `product_categories`. **Esto puede exportar datos inconsistentes.**

---

### B.1.7 — `POST /products/remove-image`

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /products/remove-image` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **Body** | `{ productId: string, imageUrl: string }` |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (SELECT + UPDATE imageUrl), `product-images` (Storage remove) |
| **Response** | `{ message: 'Image removed successfully' }` |

**🟢 Bien:** Valida `client_id` en findOne y en el UPDATE.

---

### B.1.8 — `GET /products/search`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /products/search` |
| **Guards** | Ninguno (público) |
| **Query params (DTO `SearchProductsDto`)** | `clientId?` (UUID), `q?` (string libre), `sort?` (relevance/price_asc/price_desc/best_selling), `priceMin?`, `priceMax?`, `page` (default 1), `pageSize` (default 24), `optionValues?` (comma-separated), `optionSetId?` (UUID), `onSale?` (boolean string) |
| **Validación** | class-validator decoradores en SearchProductsDto |
| **client_id** | `req.clientId ?? q.clientId ?? header['x-client-id'] ?? user.client_id` |
| **Tablas tocadas** | `products`, `product_categories`, `categories`, `option_set_items` (para filtros), `product_review_aggregates` (para avg_rating), RPC `search_products` |
| **Response** | `{ products: [...], totalItems: number }` — productos con categories, weightGrams, avg_rating, review_count |
| **Cache** | ETag + 304 support. Public: `max-age=20`. Admin: `private, max-age=15`. |

**Flujo de búsqueda:**
1. Si el `q` es un UUID → bypass RPC, busca directo por ID
2. Si hay `categoryIds` → usa `searchProducts()` (query directa con JOIN a product_categories)
3. Si no → usa RPC `search_products()` (función SQL con ranking), luego `hydrateProductsByIds()`
4. Para `sort=relevance` → reordena local: featured > bestSell > onSale > orden RPC

**🔴 Hallazgo B.1.8-a (Sev-2): SQL injection potencial en `searchProducts()`.** La query usa interpolación directa: `.or('name.ilike.%${query}%,description.ilike.%${query}%,tags.ilike.%${query}%')`. Si el `query` contiene caracteres especiales de PostgREST filter syntax (como `,`, `.`, `(`), podría manipular la query. Supabase-js escapa algunos caracteres pero la interpolación directa en `.or()` es riesgosa.

**🟡 Hallazgo B.1.8-b:** El fallback de `clientId` en search incluye `q.clientId` y `req.headers['x-client-id']` — esto es inconsistente con el resto del sistema donde solo se acepta `req.clientId` de TenantContextGuard. Un atacante podría intentar pasar un `clientId` diferente en el query param para escanear productos de otro tenant.

**🟡 Hallazgo B.1.8-c:** Los filtros `optionValues` y `optionSetId` para la vía RPC se aplican **post-fetch** (filtrando los resultados de la RPC). Esto puede causar que se devuelvan menos resultados que `limit` y que `totalItems` no refleje el filtro real.

**🟡 Hallazgo B.1.8-d:** La query también acepta aliases de parámetros (`rawQuery.query`, `rawQuery.min`, `rawQuery.minPrice`, etc.) fuera del DTO — esto bypasea las validaciones de class-validator.

---

### B.1.9 — `GET /products/search/filters`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /products/search/filters` |
| **Guards** | Ninguno (público) |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (option_set_id, option_config), `option_sets`, `option_set_items`, `categories` |
| **Response** | `{ optionSets: [...], categories: [{id, name}] }` |

**🟢 Bien:** Filtra por `client_id`. Incluye pseudo-set `__colors__` para paleta predefinida.

---

### B.1.10 — `GET /products/:id` (Detalle)

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /products/:id` |
| **Guards** | Ninguno (público) |
| **Param** | `:id` — acepta UUID o slug |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (SELECT by id/slug + client_id), `option_sets`, `option_set_items`, `size_guides` |
| **Response** | Producto completo con `resolved_options` (source, option_set info, items, has_size_guide, colors) |
| **Cache** | ETag basado en updated_at + campos de precio/stock. max-age=30, s-maxage=60. |

**🟢 Bien:** `client_id` filtrado en findOne. Resolución de opciones es robusta con soporte legacy (color_ids) y nuevo (colors).

**🟡 Hallazgo B.1.10-a:** El `findOne` en el service no verifica `client_id` al buscar el `option_set` asociado. La query es `.eq('id', product.option_set_id).maybeSingle()` sin filtro de tenant. Esto permite que un producto apunte a un option_set de otro tenant o global (preset), lo cual es probablemente intencional para presets.

---

### B.1.11 — `POST /products/:id/image` (Upload optimizada)

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /products/:id/image` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')`, `@UseGuards(PlanLimitsGuard)`, `@PlanAction('upload_image')` |
| **Body** | `multipart/form-data` con field `file` (single image) |
| **Interceptor** | `FileInterceptor` — memoryStorage, 2MB, `imageFileFilter` |
| **client_id** | `getClientId(req)` |
| **Tablas tocadas** | `products` (UPDATE imageUrl + image_variants), `product-images` (Storage upload via ImageService) |
| **Response** | `{ main: string, variants: object }` |

**🟢 Bien:** Guards completos. ImageService genera variantes optimizadas (avif/webp). `client_id` usado en storage path y update query.

---

## B.2 — PRODUCTS SERVICE: Detalles Internos

### B.2.1 — `ALLOWED_FIELDS` (whitelist de campos persistibles)

```typescript
static readonly ALLOWED_FIELDS = [
  'name', 'description', 'sku', 'filters', 'originalPrice', 'discountedPrice',
  'currency', 'available', 'quantity', 'material', 'promotionTitle',
  'promotionDescription', 'discountPercentage', 'validFrom', 'validTo',
  'featured', 'bestSell', 'sendMethod', 'tags', 'imageUrl', 'weight_grams',
  'option_mode', 'option_set_id', 'option_config',
];
```

**Campos notables ausentes de ALLOWED_FIELDS (no se persisten desde el body):**
- `id` — se genera internamente o se toma del param `:id`
- `client_id` — se fuerza desde req
- `categoryIds` — se maneja por separado en `assignCategoriesToProduct`
- `slug` — NO está en ALLOWED_FIELDS. ¿Se genera automáticamente en DB (trigger)? ¿O no se persiste nunca desde la API?
- `created_at`, `updated_at` — gestionados por DB
- `image_variants` — solo se escribe via `updateImageVariants()`

### B.2.2 — Transformaciones en `createOrUpdateProduct`

```
originalPrice = parseFloat() || 0
discountedPrice = parseFloat() || 0
discountPercentage = parseFloat() || 0
quantity = parseInt() || 0
weightGrams → weight_grams (camelCase → snake_case)
available = === true || === 'true'
categoryIds = JSON.parse() si es string
imageUrl = se asegura que sea array
```

**🟡 Hallazgo B.2.2-a:** `available` solo acepta `true` literal o `'true'` string. Valores como `'1'`, `'yes'`, `'sí'` NO se convierten a true (a diferencia del bulk upload que usa `coerceBoolean`). Inconsistencia entre create individual y bulk upload.

### B.2.3 — Mapa de tablas tocadas por operación

| Operación | products | product_categories | categories | product-images (Storage) | option_sets | option_set_items | size_guides | product_review_aggregates |
|---|:---:|:---:|:---:|:---:|:---:|:---:|:---:|:---:|
| GET /products | R | R | R | - | - | - | - | - |
| POST /products | W | D+W | - | W | - | - | - | - |
| PUT /products/:id | W | D+W | - | W | - | - | - | - |
| DELETE /products/:id | R+D | - | - | D | - | - | - | - |
| POST upload/excel | W (upsert) | D+W | R+W | - | - | - | - | - |
| GET /download | R | - | - | - | - | - | - | - |
| POST remove-image | R+W | - | - | D | - | - | - | - |
| GET /search | R | R | R | - | - | R | - | R |
| GET /search/filters | R | - | R | - | R | R | - | - |
| GET /:id | R | - | - | - | R | R | R | - |
| POST /:id/image | W | - | - | W | - | - | - | - |

---

## B.3 — OPTION SETS CONTROLLER: Inventario de Endpoints

### B.3.1 — `GET /option-sets`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /option-sets` |
| **Guards** | `@UseGuards(PlanAccessGuard)` (class-level) |
| **client_id** | `getClientId(req)` |
| **Tablas** | `option_sets` + `option_set_items` (eager load) |
| **Query** | WHERE `client_id = X` OR (`client_id IS NULL` AND `is_preset = true`) |
| **Response** | Array de option_sets con items incluidos |

**🟢 Bien:** Incluye presets globales (nullables) + los del tenant.

### B.3.2 — `GET /option-sets/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /option-sets/:id` |
| **Guards** | PlanAccessGuard |
| **Validación** | Verifica `data.client_id === clientId` O (`client_id = null` AND `is_preset`) |
| **Response** | Option set con items |

**🟢 Bien:** Valida acceso por tenant o preset global.

### B.3.3 — `POST /option-sets`

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /option-sets` |
| **Guards** | PlanAccessGuard + RolesGuard(`admin`, `super_admin`) + `@PlanFeature('commerce.option_sets')` |
| **Body DTO** | `CreateOptionSetDto` — `code` (required string), `name` (required string), `type?` (apparel/footwear/accessory/generic), `system?`, `metadata?`, `items?` (array de `OptionSetItemDto`: value, label, position?, metadata?, is_active?) |
| **Tablas** | `option_sets` (INSERT) + `option_set_items` (INSERT) |
| **Validaciones** | Unicidad de `code` por tenant. Si insert de items falla → rollback (delete set) |
| **Response** | El set completo con items (via findOne) |

**🟢 Bien:** DTO con validación class-validator. Unicidad verificada. Rollback manual de items.

**🟡 Hallazgo B.3.3-a:** No hay validación de `metadata` (es `Record<string, any>`). Se podría inyectar cualquier JSON.

### B.3.4 — `PUT /option-sets/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `PUT /option-sets/:id` |
| **Guards** | PlanAccessGuard + RolesGuard + PlanFeature |
| **Body DTO** | `UpdateOptionSetDto` — name?, type?, system?, metadata?, items? |
| **Lógica** | Replace items (delete all + insert new). No permite editar presets globales. |
| **Tablas** | `option_sets` (UPDATE) + `option_set_items` (DELETE + INSERT) |

**🟡 Hallazgo B.3.4-a:** El delete de `option_set_items` NO filtra por `client_id` — solo por `option_set_id`. Esto es correcto porque ya se validó que el set pertenece al tenant, pero si hay un bug en la validación, podría borrar items de otros tenants.

**🟡 Hallazgo B.3.4-b:** No se puede cambiar el `code` de un option_set existente (no está en UpdateOptionSetDto). Esto es probablemente intencional.

### B.3.5 — `DELETE /option-sets/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `DELETE /option-sets/:id` |
| **Guards** | PlanAccessGuard + RolesGuard + PlanFeature |
| **Validación** | No permite borrar presets globales. Verifica que `count(products WHERE option_set_id = X) == 0` |
| **Tablas** | `products` (count), `option_sets` (DELETE) |
| **Response** | `{ deleted: true, id }` |

**🟢 Bien:** Impide borrar si hay productos asociados. Filtra por `client_id`.

### B.3.6 — `POST /option-sets/:id/duplicate`

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /option-sets/:id/duplicate` |
| **Guards** | PlanAccessGuard + RolesGuard + PlanFeature |
| **Body** | `{ code?: string, name?: string }` (sin DTO formal) |
| **Lógica** | Copia set + items. Verifica unicidad de nuevo code. Rollback si falla items. |
| **Response** | El nuevo set completo |

**🟡 Hallazgo B.3.6-a:** El body `{ code?, name? }` no tiene validación DTO. Se podría enviar cualquier valor.

---

## B.4 — SIZE GUIDES (Sub-endpoints de Option Sets)

### B.4.1 — `GET /option-sets/size-guides/list`
- **Guards:** PlanAccessGuard
- **Query:** `size_guides WHERE client_id = X OR client_id IS NULL`
- **Response:** Array de guías

### B.4.2 — `GET /option-sets/size-guides/by-context?optionSetId=&productId=`
- **Guards:** PlanAccessGuard
- **Lógica:** Prioridad: guía por product_id > guía por option_set_id
- **Query:** Filtra `client_id = X OR client_id IS NULL`, order by version DESC, limit 1
- **Response:** Guía única o 404

### B.4.3 — `GET /option-sets/size-guides/:id`
- **Guards:** PlanAccessGuard
- **Validación:** `data.client_id === clientId OR client_id === null`

### B.4.4 — `POST /option-sets/size-guides`
- **Guards:** PlanAccessGuard + RolesGuard + `@PlanFeature('commerce.size_guides')`
- **DTO:** `CreateSizeGuideDto` — option_set_id?, product_id?, name?, columns (string[]), rows ({label, values}[]), notes?
- **Inserta:** `version: 1`
- **🟢** DTO validado con class-validator

### B.4.5 — `PUT /option-sets/size-guides/:id`
- **Guards:** PlanAccessGuard + RolesGuard + PlanFeature
- **DTO:** `UpdateSizeGuideDto` — name?, columns?, rows?, notes?, version?
- **Lógica:** Auto-incrementa `version`. No permite editar guías globales.
- **🟡:** El DTO acepta `version` pero el service lo ignora (auto-incrementa). Campo fantasma.

### B.4.6 — `DELETE /option-sets/size-guides/:id`
- **Guards:** PlanAccessGuard + RolesGuard + PlanFeature
- **Validación:** No permite borrar guías globales
- **🟢** Filtra por `client_id`

---

## B.5 — CATEGORIES CONTROLLER: Inventario de Endpoints

### B.5.1 — `POST /categories`

| Atributo | Valor |
|---|---|
| **Ruta** | `POST /categories` |
| **Guards** | `@UseGuards(RolesGuard)`, `@Roles('admin', 'super_admin')` |
| **Body** | `@Body() dto: any` — **❌ SIN DTO, sin validación** |
| **Tablas** | `categories` (INSERT: name, description, client_id) |
| **Response** | data (resultado del insert — Nota: Supabase `.insert([...])` sin `.select()` retorna null en data por defecto) |

**🔴 Hallazgo B.5.1-a (Sev-2): NO HAY DTO NI VALIDACIÓN.** Se acepta cualquier body. No se valida que `name` exista o sea string. El `description` se persiste sin sanitización.

**🟡 Hallazgo B.5.1-b:** El insert no usa `.select()`, por lo que `data` devuelto es probablemente `null`. El caller no recibe confirmación del registro creado.

### B.5.2 — `GET /categories`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /categories` |
| **Guards** | Ninguno (público) |
| **client_id** | `getClientId(req)` |
| **Tablas** | `categories` WHERE `client_id = X` |
| **Cache** | ETag + 304. `max-age=300, s-maxage=600` |
| **Response** | Array de categorías |

**🟢 Bien:** `client_id` filtrado. Cache agresivo (5 min client, 10 min CDN).

### B.5.3 — `GET /categories/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `GET /categories/:id` |
| **Guards** | Ninguno (público) |
| **Tablas** | `categories` WHERE `id = X AND client_id = Y` |
| **Cache** | ETag + 304 |

**🟢 Bien**

### B.5.4 — `PUT /categories/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `PUT /categories/:id` |
| **Guards** | RolesGuard (`admin`, `super_admin`) |
| **Body** | `body.name` — sin DTO, sin validación |
| **Tablas** | `categories` UPDATE name WHERE id AND client_id |

**🔴 Hallazgo B.5.4-a (Sev-3):** Solo actualiza `name`. Si el body no tiene `name`, se setea `undefined`. No valida que sea string no vacío.

**🟡 Hallazgo B.5.4-b:** No se puede actualizar `description` via update — el endpoint solo acepta `body.name`.

### B.5.5 — `DELETE /categories/:id`

| Atributo | Valor |
|---|---|
| **Ruta** | `DELETE /categories/:id` |
| **Guards** | RolesGuard (`admin`, `super_admin`) |
| **Tablas** | `categories` DELETE WHERE id AND client_id |
| **Response** | `{ message: 'Categoría eliminada con éxito' }` |

**🟡 Hallazgo B.5.5-a:** No verifica si hay productos asociados antes de borrar. Si `product_categories` tiene FK sin CASCADE, podría fallar con error de constraint. Si tiene CASCADE, se borran las asociaciones silenciosamente.

---

## B.6 — HALLAZGOS CONSOLIDADOS Y SEVERIDAD

### 🔴 Críticos (Sev-1/Sev-2) — Requieren acción inmediata

| # | Hallazgo | Archivo | Impacto |
|---|---|---|---|
| 1 | **Sin DTO de validación para crear/editar productos** | products.controller.ts L113-159 | Cualquier campo/tipo se acepta. Sin validación de rangos, tipos, strings. XSS potencial en `name`, `description`, `tags`. |
| 2 | **SQL injection potencial en search (interpolación ilike)** | products.service.ts L1406 | `.or('name.ilike.%${query}%,...')` — query no sanitizado en PostgREST filter |
| 3 | **Sin DTO en categories (create/update)** | categories.controller.ts L31, L82 | `@Body() dto: any` sin validación |
| 4 | **Fallback de clientId en search bypasea TenantContextGuard** | products.controller.ts L361-365 | `q.clientId` del query param podría usarse para escanear otro tenant |

### 🟡 Moderados (Sev-3) — Mejorar a corto plazo

| # | Hallazgo | Archivo | Impacto |
|---|---|---|---|
| 5 | product_categories no se borra en DELETE product | products.service.ts L795 | Filas huérfanas si no hay CASCADE |
| 6 | Carga de TODAS las product_categories en GET /products | products.service.ts L132 | Performance: carga todas las relaciones del tenant, no solo la página |
| 7 | `available` parsing inconsistente (create vs bulk) | products.service.ts L400 vs L935 | `'1'`/`'yes'` no funcionan en create individual |
| 8 | Download Excel exporta `categories` de la columna, no de junction table | products.service.ts L1254 | Datos inconsistentes en export |
| 9 | `imageUrl` permitido en ALLOWED_FIELDS | products.service.ts L53 | Permite inyectar URLs externas arbitrarias |
| 10 | Categories insert sin `.select()` retorna null | categories.service.ts L10 | No hay feedback del registro creado |
| 11 | UpdateSizeGuideDto acepta `version` pero se ignora | size-guide.dto.ts L35 | Campo fantasma |
| 12 | POST option-sets/:id/duplicate sin DTO formal | option-sets.controller.ts L96 | Body sin validación |
| 13 | `metadata` en DTOs de option-sets sin validación de estructura | create-option-set.dto.ts, update-option-set.dto.ts | JSON arbitrario aceptado |

### 🟢 Bien implementado

| # | Aspecto | Detalle |
|---|---|---|
| 1 | `client_id` forzado desde TenantContextGuard | `getClientId(req)` nunca usa el body para client_id |
| 2 | ALLOWED_FIELDS whitelist en products | Previene escritura de campos no autorizados |
| 3 | Storage path con clientId + UUID | `buildStorageObjectPath()` previene path traversal |
| 4 | Guards de roles consistentes en escrituras | Todos los POST/PUT/DELETE requieren admin/super_admin |
| 5 | Plan limits en creación de productos | PlanLimitsGuard + PlanAction en POST |
| 6 | Cache con ETag + 304 | Implementación correcta en reads públicos |
| 7 | Option sets: unicidad de code por tenant | ConflictException si ya existe |
| 8 | Option sets: previene borrado si hay productos asociados | count > 0 → ConflictException |
| 9 | Rollback manual en option_set create si items fallan | Borra el set recién creado |
| 10 | Resolución de opciones con soporte legacy + nuevo | `colors` (paleta) > `color_ids` (UUIDs) |

---

## B.7 — RECOMENDACIONES PRIORITARIAS

### Inmediatas (Sprint actual)

1. **Crear `CreateProductDto` y `UpdateProductDto`** con class-validator — validar name (required, maxLength), originalPrice (min 0), quantity (int, min 0), currency (in ARS/USD), etc. Cambiar el controller para parsear el JSON y validarlo contra el DTO.

2. **Sanitizar query de búsqueda** — escapar caracteres especiales de PostgREST (`.`, `,`, `(`, `)`) en el search term antes de interpolar en `.or()`.

3. **Crear `CreateCategoryDto`** con `@IsString() @IsNotEmpty() name: string` y `@IsOptional() @IsString() description?: string`.

4. **Eliminar fallback de `q.clientId` y `req.headers['x-client-id']`** en GET /products/search — usar solo `req.clientId` de TenantContextGuard.

### A corto plazo

5. Optimizar GET /products para traer solo `product_categories` de los productos de la página (filtrar por `product_id IN [ids de la página]`).

6. Agregar DELETE de `product_categories` en `deleteProduct()` antes de borrar el producto (o verificar que hay CASCADE en DB).

7. Unificar parsing de `available` — usar `coerceBoolean()` tanto en create individual como en bulk.

8. Fixear download Excel para obtener categorías de la junction table en vez de la columna `categories` del producto.

9. Remover `imageUrl` de `ALLOWED_FIELDS` y manejar imágenes solo via archivos subidos o el endpoint dedicado `/products/:id/image`.

---

# FASE B — Auditoría de Guards y Middleware de Seguridad (Capas Críticas)

**Fecha:** 2025-02-25
**Auditor:** Copilot Agent
**Alcance:** Inspección completa de `AuthMiddleware`, `TenantContextGuard`, y todos los guards/middleware descubiertos en `/src`.

---

## B1 — Inventario Completo de Guards y Middleware

### Archivos encontrados (17 total)

| # | Archivo | Tipo | Propósito |
|---|---------|------|-----------|
| 1 | `src/auth/auth.middleware.ts` | Middleware | **JWT validation + client_id resolution** (capa principal de autenticación) |
| 2 | `src/guards/tenant-context.guard.ts` | Guard | **Resolución de tenant desde slug/dominio** + gating de storefront |
| 3 | `src/guards/super-admin.guard.ts` | Guard | Validación de super admin (DB lookup + internal key) |
| 4 | `src/guards/roles.guard.ts` | Guard | Verificación de roles por metadata |
| 5 | `src/guards/builder-or-supabase.guard.ts` | Guard | Autenticación dual (builder JWT o Supabase JWT) |
| 6 | `src/guards/builder-session.guard.ts` | Guard | Validación de sesiones builder (onboarding) |
| 7 | `src/guards/client-dashboard.guard.ts` | Guard | Autenticación unificada para panel de cliente |
| 8 | `src/guards/maintenance.guard.ts` | Guard | Bloqueo por maintenance_mode o soft-delete |
| 9 | `src/guards/quota-check.guard.ts` | Guard | Enforcement de quotas por plan |
| 10 | `src/guards/subscription.guard.ts` | Guard | Bloqueo por estado de suscripción |
| 11 | `src/guards/tenant-rate-limit.guard.ts` | Guard | Rate limiting por tenant basado en plan RPS |
| 12 | `src/auth/guards/platform-auth.guard.ts` | Guard | JWT validation SOLO contra Admin DB |
| 13 | `src/auth/guards/tenant-auth.guard.ts` | Guard | JWT validation SOLO contra Multicliente DB + client_id match |
| 14 | `src/common/guards/client-context.guard.ts` | Guard | Inyección de clientId desde `getClientId()` helper |
| 15 | `src/plans/guards/plan-access.guard.ts` | Guard | Feature gating por plan (catálogo de features) |
| 16 | `src/plans/guards/plan-limits.guard.ts` | Guard | Límites de acciones por plan (upload, etc.) |
| 17 | `src/common/middleware/rate-limit.middleware.ts` | Middleware | Rate limiting por IP (auth, admin, generic) |

### Decorador de bypass principal

| Decorador | Ubicación | Key Metadata |
|-----------|-----------|--------------|
| `@AllowNoTenant()` | `src/common/decorators/allow-no-tenant.decorator.ts` | `'allow_no_tenant'` |

**Implementación:**
```typescript
import { SetMetadata } from '@nestjs/common';
export const ALLOW_NO_TENANT_KEY = 'allow_no_tenant';
export const AllowNoTenant = () => SetMetadata(ALLOW_NO_TENANT_KEY, true);
```

No se encontraron decoradores `@Public`, `@AllowAnonymous`, ni `IS_PUBLIC`. El bypass de autenticación se maneja por **prefijos de path en el middleware**, no por metadata de NestJS.

---

## B2 — AuthMiddleware (Capa de Autenticación Principal)

**Archivo:** `src/auth/auth.middleware.ts` (382 líneas)

### Flujo de ejecución

```
Request
  │
  ├─ Extrae: Authorization Bearer token, x-client-id header, x-builder-token header
  │
  ├─ ¿Es ruta pública (PUBLIC_PATH_PREFIXES)?
  │    └─ SÍ → next() sin autenticación
  │
  ├─ ¿Es ruta de builder (/client-dashboard/) con builder token?
  │    └─ SÍ → tryAttachBuilderUser() → next()
  │
  ├─ ¿Falta token?
  │    ├─ ¿Es ruta builder de cuentas con builder token? → tryAttachBuilderUser()
  │    └─ NO → 401 "Token requerido"
  │
  ├─ Validar JWT en Supabase (multiclient primero, luego admin)
  │    └─ Falla ambos → 401 "Token inválido o expirado"
  │
  ├─ Extraer role de user_metadata / app_metadata
  │    └─ Sin rol → 403 "Rol no autorizado"
  │
  ├─ RESOLVER client_id:
  │    ├─ Admin project → header ó metadata
  │    ├─ Super admin → header ó metadata (cross-tenant permitido)
  │    └─ User/Admin → validar contra allowedClientIds (membership check en DB)
  │         └─ Sin membership → 403 "sin client_id asignado"
  │
  ├─ Inyectar en req: user object, x-client-id header, supabase per-request client
  │
  └─ next()
```

### Rutas públicas (sin autenticación)

```typescript
const PUBLIC_PATH_PREFIXES = [
  '/mercadopago/webhook',
  '/mercadopago/notification',
  '/webhooks/mp/tenant-payments',
  '/webhooks/mp/platform-subscriptions',
  '/subscriptions/webhook',
  '/subscriptions/manage',
  '/health',
  '/auth/google/start',
  '/auth/google/callback',
  '/auth/confirm-email',
  '/auth/email-callback',
  '/auth/forgot-password',
  '/auth/reset-password',
  '/auth/signup',
  '/auth/login',
  '/auth/internal-key/verify',
  '/auth/internal-key/revoke',
  '/auth/bridge/',
  '/oauth/callback',
  '/mp/oauth/start?',
  '/mp/oauth/callback',
  '/onboarding/',
  '/coupons/',
];
```

Además, dos prefijos extra con builder token:
```typescript
if (builderToken && url.startsWith('/palettes')) → next()
if (builderToken && url.startsWith('/templates')) → next()
```

### Cómo se valida el JWT

```typescript
private async resolveUserFromToken(token: string): Promise<TokenValidationResult | null> {
  // Intenta validar contra Supabase multicliente primero, luego admin
  for (const candidate of [multiProjectClient, adminProjectClient]) {
    const { data, error } = await candidate.client.auth.getUser(token);
    if (data?.user) return { user: data.user, project: candidate.project };
  }
  return null;
}
```

**Observación:** Usa `supabase.auth.getUser(token)` que hace un round-trip al servidor Supabase para validar el JWT (no verificación local). Esto es **seguro** (no confía en claims sin verificar) pero **costoso** en latencia.

### Cómo se resuelve y propaga el client_id

**Para admin project:**
```typescript
resolvedClientId = effectiveHeaderClientId || userClientId || null;
```

**Para super_admin:**
```typescript
resolvedClientId = effectiveHeaderClientId || userClientId || null;
// Cross-tenant permitido con log de debug
```

**Para usuarios normales (admin/user):**
```typescript
// 1. Obtener IDs permitidos desde user_metadata + DB lookup
const allowedClientIds = new Set<string>();
allowedClientIds.add(userClientId); // desde metadata
const linkedClients = await this.fetchUserClientIds(user.id); // desde tabla users

// 2. Verificar que el header coincida con un tenant permitido
if (effectiveHeaderClientId && allowedClientIds.has(effectiveHeaderClientId)) {
  resolvedClientId = effectiveHeaderClientId;
} else {
  resolvedClientId = defaultClientId; // primero del set
}
```

**Propagación:**
```typescript
req.headers['x-client-id'] = resolvedClientId;  // overwrite del header
req.user = { ..., resolvedClientId, role, project };
req.supabase = makeRequestSupabaseClient(req);   // Supabase client scoped
```

---

## B3 — TenantContextGuard (Resolución de Tenant)

**Archivo:** `src/guards/tenant-context.guard.ts` (447 líneas)

### Flujo de resolución del tenant (en orden de prioridad)

```
1. Header x-tenant-slug / x-store-slug
   └─ resolveAccountBySlug() → resolveClientByAccount() → gateStorefront()

2. [REMOVED] x-client-id header (eliminado por auditoría P0 — Identifier Leakage)

3. Custom domain (x-forwarded-host / host)
   └─ resolveAccountByCustomDomain([host, www.host]) → resolveClientByAccount()

4. Subdominio del host (tienda1.novavision.lat)
   └─ extractSlugFromHost() → resolveAccountBySlug()

5. [REMOVED] req.user.resolvedClientId (eliminado por auditoría P0)

6. Si no hay clientId → verificar @AllowNoTenant
   └─ No tiene decorador → 401 "Se requiere client_id"
```

### Gating de storefront

```typescript
private gateStorefront(client) {
  if (client.deleted_at) → 401 STORE_NOT_FOUND
  if (client.is_active === false) → 403 STORE_SUSPENDED
  if (client.maintenance_mode === true) → 403 STORE_MAINTENANCE
  if (client.publication_status !== 'published') → 403 STORE_NOT_PUBLISHED
}
```

### Subdominios reservados (no resuelven como tiendas)

```typescript
const reserved = ['admin', 'api', 'app', 'www', 'novavision', 'localhost', 'build', 'novavision-production'];
```

### Inyección en request

```typescript
request.clientId = clientId;
request.tenant = { clientId, slug: resolvedSlug };
request.requestId = `req-${Date.now()}-${Math.random()...}`;
```

---

## B4 — SuperAdminGuard

**Archivo:** `src/guards/super-admin.guard.ts` (85 líneas)

### Doble verificación

1. **DB lookup:** Verifica que el email del usuario existe en tabla `super_admins` de Admin DB.
2. **Internal key:** Verifica cookie `nv_ik` o header `x-internal-key` contra `INTERNAL_ACCESS_KEY` env var usando `timingSafeEquals()`.

```typescript
// Fail-closed si falta INTERNAL_ACCESS_KEY
if (!expected) {
  throw new ForbiddenException('Super admin security misconfigured');
}
const provided = request.cookies?.['nv_ik'] || request.headers['x-internal-key'] || '';
if (!provided || !timingSafeEquals(provided, expected)) {
  throw new UnauthorizedException('Invalid internal access key');
}
```

**Buena práctica:** Usa timing-safe comparison para prevenir timing attacks.

---

## B5 — RolesGuard

**Archivo:** `src/guards/roles.guard.ts` (60 líneas)

### Comportamiento

- Si no se definen roles con `@Roles(...)` → permite todo (return true).
- Verifica `user.role` contra los roles requeridos.
- **Bloquea escalación** admin → super_admin explícitamente:

```typescript
if (roles.includes('super_admin') && project === 'admin' && user.role === 'admin' && !userClientId) {
  throw new ForbiddenException('Acceso denegado: escalación de admin a super_admin no permitida.');
}
```

---

## B6 — Otros Guards (Resumen)

### BuilderSessionGuard
- Valida JWT con `JWT_SECRET` y verifica `type === 'builder_session'`.
- Pobla `req.account_id` y `req.email` desde el token.
- **Seguridad:** "NO confiar en account_id del body, solo del JWT" (documentado).

### BuilderOrSupabaseGuard
- Acepta builder token (X-Builder-Token) O Supabase JWT.
- Intenta validar contra Admin DB primero, luego Multicliente.
- Busca `account_id` por `user_id` o email en `nv_accounts`.

### ClientDashboardGuard
- Acepta builder token, Supabase JWT (roles: admin/super_admin/builder/client), o Authorization Bearer como fallback.
- Resuelve `account_id` desde `nv_accounts` si no está en metadata.

### MaintenanceGuard
- Verifica `maintenance_mode` y `deleted_at` en tabla `clients`.
- **⚠️ Fail-open** en caso de error de DB (catch genérico → return true).

### TenantRateLimitGuard
- Rate limiting per-tenant basado en plan (Starter: 5 RPS, Growth: 15, Enterprise: 60).
- Cache in-memory de 60s para límites de plan.
- **Fail-open** en caso de error de Redis o DB.

### QuotaCheckGuard
- Bloquea writes (POST/PUT/PATCH/DELETE) en `HARD_LIMIT`.
- Permite reads (GET/HEAD/OPTIONS) siempre.
- Feature flag: `ENABLE_QUOTA_ENFORCEMENT`.
- **Fail-open** en caso de error.

### SubscriptionGuard
- Bloquea si suscripción no está activa o en periodo de gracia.
- Skipeable con `@SkipSubscriptionCheck()`.

### PlatformAuthGuard
- Valida JWT **solo contra Admin DB**.
- Detecta super admin por `app_metadata.is_super_admin` o `user_metadata.role === 'superadmin'`.

### TenantAuthGuard
- Valida JWT **solo contra Multicliente DB**.
- **Verifica que `user_metadata.client_id === headerClientId`** — aislamiento estricto.
- Rechaza mismatch de client_id.

### ClientContextGuard
- Usa `getClientId(req)` helper que extrae **solo desde `req.clientId`** (no headers).
- Seguridad: "NO se acepta x-client-id desde headers para evitar inyección de tenant".

---

## B7 — Helper de Client ID

**Archivo:** `src/common/utils/client-id.helper.ts`

```typescript
export function getClientId(req: Request): string {
  const clientId = req.clientId;
  if (!clientId) {
    throw new BadRequestException('Tenant context is required.');
  }
  return clientId;
}
```

**Solo acepta `req.clientId`** (inyectado por TenantContextGuard), no el header crudo. Esto es correcto.

---

## B8 — Controladores con @AllowNoTenant() (Bypass de Tenant)

| Controlador | Cantidad de endpoints sin tenant | Justificación probable |
|-------------|----------------------------------|----------------------|
| `client-dashboard.controller.ts` | **17 endpoints** | Panel builder opera por account_id, no por tenant |
| `auth.controller.ts` | **13 endpoints** | Login/signup/oauth no requieren tenant |
| `oauth-relay.controller.ts` | 3 endpoints | OAuth callbacks |
| `health.controller.ts` | Clase completa | Health checks |
| `metrics.controller.ts` | Clase completa | Métricas internas |
| `plans.controller.ts` | 2 endpoints | Consulta de planes públicos |
| `plans-admin.controller.ts` | Clase completa | Admin de planes (protegido por SuperAdminGuard) |
| `admin.controller.ts` | Clase completa | Admin NovaVision (protegido por SuperAdminGuard) |
| `admin-accounts.controller.ts` | Clase completa | Gestión de cuentas platform |
| `admin-renewals.controller.ts` | Clase completa | Renovaciones |
| `admin-fx-rates.controller.ts` | Clase completa | Tipos de cambio |
| `admin-adjustments.controller.ts` | Clase completa | Ajustes |
| `admin-country-configs.controller.ts` | Clase completa | Configs por país |
| `admin-option-sets.controller.ts` | Clase completa | Option sets |
| `admin-shipping.controller.ts` | Clase completa | Shipping config |
| `admin-managed-domain.controller.ts` | Clase completa | Dominios |
| `admin-client.controller.ts` | Clase completa | Gestión de clientes |
| `admin-quotas.controller.ts` | Clase completa | Quotas |
| `super-admin-email-jobs.controller.ts` | Clase completa | Email jobs |
| `tenant.controller.ts` | 2 endpoints | Resolución de tenant público |
| `mercadopago.controller.ts` | 2 endpoints | Webhooks MP |

---

## B9 — Hallazgos de Seguridad

### 🔴 Sev-1 — Críticos

**B9.1 — `/coupons/` está en PUBLIC_PATH_PREFIXES sin protección de middleware**

```typescript
'/coupons/',  // auth handled by BuilderOrSupabaseGuard at controller level
```

El comentario dice que la autenticación se maneja a nivel controller con `BuilderOrSupabaseGuard`, pero **cualquier ruta que empiece con `/coupons/` bypasea completamente AuthMiddleware**. Si algún endpoint de coupons NO tiene ese guard, queda expuesto sin autenticación. Esto es un patrón frágil — depende de que TODOS los endpoints del controller tengan guard.

**Recomendación:** Mover la protección al middleware o usar un guard global para el módulo de coupons.

---

**B9.2 — `/onboarding/` está completamente abierto en el middleware**

```typescript
'/onboarding/',
```

Todas las rutas bajo `/onboarding/` bypasean AuthMiddleware. Si algún endpoint de onboarding tiene operaciones sensibles (crear cuentas, configurar tiendas) y no tiene su propio guard, es una brecha.

**Recomendación:** Verificar que TODOS los endpoints de onboarding estén protegidos por `BuilderSessionGuard` o equivalente.

---

**B9.3 — webhook legacy SEO AI abierto sin validación de firma**

Estado actual: resuelto por eliminación del endpoint legacy; el webhook vigente para este flujo es `/addons/webhook`.

```typescript
// endpoint legacy removido
```

A diferencia de los webhooks de Mercado Pago (que validan firma), este webhook no tiene indicación de validación de origen/firma.

**Recomendación:** Implementar validación de firma o shared secret para este webhook.

---

### 🟡 Sev-2 — Importantes

**B9.4 — AuthMiddleware: resolvedClientId silenciosamente fallback al default**

Cuando un usuario normal envía un `x-client-id` que no le pertenece:

```typescript
if (effectiveHeaderClientId) {
  this.logger.warn(`Usuario intentó operar con tenant no asociado. Se usará el tenant por defecto`);
}
const defaultClientId = allowedClientIds.values().next().value;
resolvedClientId = defaultClientId ?? null;
```

En lugar de rechazar la request (403), **silenciosamente cambia al primer tenant del set**. Un atacante podría explotar esto para descubrir si su request fue redirigida (timing differences) o podría causar que operaciones se ejecuten en el tenant equivocado sin que el usuario lo note.

**Recomendación:** Considerar retornar 403 cuando `x-client-id` no coincide con los tenants del usuario, en lugar de hacer fallback silencioso.

---

**B9.5 — Super admin cross-tenant: solo log de debug, sin audit trail persistente**

```typescript
if (effectiveHeaderClientId && userClientId && effectiveHeaderClientId !== userClientId) {
  this.logger.debug(`super_admin operando como tenant ${effectiveHeaderClientId}`);
}
```

El cross-tenant de super admin **solo se logguea en debug** (no en producción por defecto). Falta un audit trail persistente en DB para estas operaciones.

**Recomendación:** Registrar cada operación cross-tenant de super_admin en una tabla `audit_log`.

---

**B9.6 — MaintenanceGuard fail-open por defecto**

```typescript
} catch (err) {
  // Fail open or closed? Closed is safer for maintenance.
  // But if DB is down, maybe open?
  // Let's safe-fail to open for now unless critical.
}
return true;
```

El propio comentario del código reconoce la duda. Si la DB está caída y un tenant está en maintenance, el guard **permite acceso**.

**Recomendación:** Fail-closed es más seguro para un guard de mantenimiento. Si no se puede verificar el estado, rechazar con 503.

---

**B9.7 — TenantContextGuard: consulta doble a DB por cada request (N+1)**

Cada request resuelve:
1. `nv_accounts` por slug → obtiene `account_id` + `backend_cluster_id`
2. `clients` por `nv_account_id` → obtiene `client_id` + estado

Son 2 queries a Supabase REST por request, sin caching. En alta concurrencia esto puede ser un cuello de botella.

**Recomendación:** Implementar cache in-memory (similar a `TenantRateLimitGuard.planCache`) para mapeo slug→clientId con TTL de 30-60s.

---

**B9.8 — `tryAttachBuilderUser` no verifica expiración del JWT builder**

```typescript
const tryAttachBuilderUser = (builderJwt?: string) => {
  const decoded = jwt.verify(builderJwt, secret); // verify() sí chequea exp
  if (decoded?.type !== 'builder_session') return false;
  if (!decoded?.account_id) return false;
  // No chequea exp explícitamente, pero jwt.verify() lo hace por defecto
  req.user = { id: decoded.account_id, ... };
  return true;
};
```

`jwt.verify()` verifica expiración por defecto, así que esto está **correcto** técnicamente. Pero a diferencia de `BuilderSessionGuard` que tiene un check explícito de expiración, aquí se confía enteramente en la librería.

**Recomendación:** Agregar check explícito de expiración para claridad defensiva.

---

### 🟠 Sev-3 — Menores

**B9.9 — Logs excesivos con console.log en TenantContextGuard**

El guard usa `console.log` extensivamente en lugar de `Logger` de NestJS. Esto dificulta el control de nivel de log en producción y puede exponer información sensible (clientId, slug, paths) en output estándar.

---

**B9.10 — `extractSlugFromHost` regex simple para validar slugs**

```typescript
if (!/^[a-z0-9-]+$/.test(subdomain)) {
  console.warn(`Subdominio inválido: ${subdomain}`);
  return null;
}
```

No hay límite de longitud. Un subdomain de miles de caracteres pasaría la validación y se enviaría como slug a la DB.

**Recomendación:** Agregar límite de longitud (ej: max 63 chars, estándar DNS).

---

**B9.11 — RolesGuard: múltiples fuentes para resolvedClientId**

```typescript
const userClientId =
  user.resolvedClientId ||
  user.user_metadata?.client_id ||
  (typeof user === 'object' && (user as any).clientId) ||
  null;
```

4 fuentes distintas para el mismo dato. Si alguna fuente tiene un valor corrupto o desactualizado, podría causar escalación de privilegios.

---

**B9.12 — `/palettes` y `/templates` aceptan cualquier builder token sin tenant**

```typescript
if (builderToken && url.startsWith('/palettes')) return next();
if (builderToken && url.startsWith('/templates')) return next();
```

Basta con enviar **cualquier string** en `x-builder-token` — no se valida el JWT, simplemente se hace `next()`.

**Recomendación Sev-1 UPGRADE:** Esto es un bypass total. Cualquier request con un header `x-builder-token` (cualquier valor, incluso "fake") a `/palettes/*` o `/templates/*` pasa sin autenticación. **Corregir para validar el JWT antes de hacer bypass.**

---

## B10 — Resumen de Flujo Completo de Seguridad

```
                    ┌───────────────────────────┐
                    │     Rate Limit Middleware   │ ← Por IP (20-200 req/min)
                    └─────────┬─────────────────┘
                              │
                    ┌─────────▼─────────────────┐
                    │      AuthMiddleware         │ ← JWT validation + client_id resolution
                    │                             │
                    │  PUBLIC_PATH_PREFIXES?       │──→ next() (sin auth)
                    │  Builder token + /palettes? │──→ next() (⚠️ SIN validar JWT)
                    │  Token → Supabase getUser() │──→ user + role + resolvedClientId
                    └─────────┬─────────────────┘
                              │
                    ┌─────────▼─────────────────┐
                    │    TenantContextGuard       │ ← Slug/domain → clientId (global guard)
                    │                             │
                    │  @AllowNoTenant? → bypass   │
                    │  Slug → nv_accounts → client │
                    │  Host → custom domain        │
                    │  gateStorefront() checks     │
                    └─────────┬─────────────────┘
                              │
                    ┌─────────▼─────────────────┐
                    │   TenantRateLimitGuard      │ ← Per-tenant RPS (plan-based)
                    └─────────┬─────────────────┘
                              │
                    ┌─────────▼─────────────────┐
                    │   Endpoint-specific Guards   │
                    │                             │
                    │  RolesGuard                  │ ← @Roles('admin')
                    │  SuperAdminGuard             │ ← DB + internal key
                    │  BuilderSessionGuard         │ ← Builder JWT
                    │  ClientDashboardGuard        │ ← Dual auth
                    │  PlanAccessGuard             │ ← Feature gating
                    │  PlanLimitsGuard             │ ← Action limits
                    │  QuotaCheckGuard             │ ← Write quotas
                    │  SubscriptionGuard           │ ← Subscription status
                    │  MaintenanceGuard            │ ← Maintenance mode
                    └─────────┬─────────────────┘
                              │
                    ┌─────────▼─────────────────┐
                    │       Controller            │
                    │  getClientId(req) → req.clientId │
                    └─────────────────────────────┘
```

---

## B11 — Matriz de Aislamiento de Tenant

| Capa | Mecanismo | ¿Enforce client_id? | Notas |
|------|-----------|---------------------|-------|
| AuthMiddleware | Valida JWT, resuelve client_id desde metadata/DB | ✅ Sí | Users normales: membership check. Super admin: cross-tenant permitido |
| TenantContextGuard | Resuelve client_id desde slug/domain | ✅ Sí | **Fuente de verdad**. Ignora header x-client-id (removido por audit P0) |
| TenantAuthGuard | Verifica `userClientId === headerClientId` | ✅ Estricto | Solo usado en rutas de tenant puro |
| ClientContextGuard | `getClientId()` solo desde `req.clientId` | ✅ Sí | No acepta headers crudos |
| `getClientId()` helper | Solo `req.clientId` | ✅ Sí | Documentado como anti-inyección |
| Services (downstream) | `.eq('client_id', clientId)` | ⚠️ Depende del service | No hay enforcement automático — cada service debe filtrar |

---

## B12 — Recomendaciones Prioritarias

### P0 (Corregir inmediatamente)

1. **B9.12 — `/palettes` y `/templates` bypass con cualquier `x-builder-token`:** El header no se valida como JWT, se verifica solo su existencia. Cualquier atacante puede enviar `x-builder-token: anything` y acceder sin auth.

### P1 (Corregir esta semana)

2. **B9.1 — `/coupons/` sin auth en middleware:** Verificar que todos los endpoints del controller tengan guard. Considerar mover a guard global del módulo.
3. **B9.2 — `/onboarding/` público:** Verificar que todos los endpoints tengan BuilderSessionGuard.
4. **B9.3 — Endpoint legacy SEO AI eliminado:** cerrar el hallazgo en el seguimiento y mantener la validación de firma sobre `/addons/webhook`.
5. **B9.4 — Fallback silencioso de tenant:** Cambiar a 403 en lugar de fallback al primer tenant.
6. **B9.6 — MaintenanceGuard fail-open:** Cambiar a fail-closed (503).

### P2 (Planificar)

7. **B9.5 — Audit trail para super admin cross-tenant:** Crear tabla `super_admin_audit_log`.
8. **B9.7 — Cache de resolución slug→clientId:** Implementar cache in-memory con TTL.
9. **B9.9 — Reemplazar `console.log` por Logger en TenantContextGuard.**
10. **B9.10 — Limitar longitud de slug en `extractSlugFromHost()`.**
11. **B9.11 — Unificar fuente de `resolvedClientId` en RolesGuard.**

---

## Fase B10 — Inventario Completo de Controllers y Endpoints

> Generado el 2025-02-25 por inspección directa del código fuente.
> **77 archivos controller** encontrados en `src/`. Total: **~350+ endpoints**.

### Leyenda de Guards/Decorators

| Abreviatura | Significado |
|---|---|
| **SA** | `@UseGuards(SuperAdminGuard)` — solo super_admin |
| **NT** | `@AllowNoTenant()` — no requiere contexto tenant |
| **CC** | `@UseGuards(ClientContextGuard)` — requiere tenant resuelto |
| **TC** | `@UseGuards(TenantContextGuard)` — requiere tenant |
| **RG** | `@UseGuards(RolesGuard)` + `@Roles(...)` — role check |
| **PA** | `@UseGuards(PlanAccessGuard)` — feature gating por plan |
| **PL** | `@UseGuards(PlanLimitsGuard)` — limit check (quota) |
| **BS** | `@UseGuards(BuilderSessionGuard)` — onboarding builder |
| **CD** | `@UseGuards(ClientDashboardGuard)` — client dashboard auth |
| **BO** | `@UseGuards(BuilderOrSupabaseGuard)` — builder or supabase |
| **SG** | `@UseGuards(SubscriptionGuard)` — subscription status |
| **PA+PL** | Combined plan access + plan limits |

---

### 1. AUTH & IDENTITY

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| auth.controller.ts | `/auth` | POST | `/internal-key/verify` | NT | Internal key verification |
| | | POST | `/internal-key/revoke` | NT | Internal key revocation |
| | | POST | `/bridge/generate` | — | Generate bridge token |
| | | POST | `/bridge/exchange` | NT | Exchange bridge token |
| | | POST | `/signup` | — | User signup |
| | | POST | `/login` | — | User login |
| | | POST | `/google/start` | NT | Google OAuth start |
| | | POST | `/tenant/google/callback` | NT | Google OAuth callback |
| | | GET | `/validate-token` | — | Validate JWT |
| | | GET | `/confirm-email` | NT | Confirm email |
| | | POST | `/resend-confirmation` | NT | Resend confirmation email |
| | | GET | `/email-callback` | NT | Email callback handler |
| | | POST | `/forgot-password` | NT | Forgot password |
| | | POST | `/reset-password` | NT | Reset password |
| | | POST | `/change-password` | NT | Change password |
| | | GET | `/session` | NT | Get session |
| | | POST | `/switch-client` | NT | Switch tenant context |
| | | GET | `/hub-context` | NT | Hub context data |
| | | POST | `/session/sync` | — | Sync session |
| oauth-relay.controller.ts | `/oauth` | GET | `/callback` | NT | OAuth callback relay |
| | | GET | `/callback.js` | NT | JS callback for OAuth |
| | | POST | `/diagnose` | NT | Diagnose OAuth issues |
| accounts.controller.ts | `/accounts` | GET | `/me` | NT | Get current account |
| | | POST | `/identity` | NT | Submit identity |
| | | POST | `/verify-identity` | NT | Verify identity |
| | | POST | `/dni/upload` | NT | Upload DNI document |
| users.controller.ts | `/users` | GET | `/` | CC, PA | List users |
| | | GET | `/:id` | CC, PA | Get user |
| | | PATCH | `/:id` | CC, PA | Update user |
| | | PUT | `/:id/block` | CC, PA | Block user |
| | | POST | `/:id/accept-terms` | CC, PA | Accept terms |
| | | DELETE | `/:id` | CC, PA | Delete user |

### 2. CATALOG (Products, Categories, Option Sets)

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| products.controller.ts | `/products` | GET | `/` | — | List products (public) |
| | | POST | `/` | RG(admin,super_admin), PL | Create product |
| | | PUT | `/:id` | RG(admin,super_admin) | Update product |
| | | DELETE | `/:id` | RG(admin,super_admin) | Delete product |
| | | POST | `/upload/excel` | RG(admin,super_admin) | Bulk import Excel |
| | | GET | `/download` | RG(admin,super_admin) | Export catalog |
| | | POST | `/remove-image` | RG(admin,super_admin) | Remove product image |
| | | GET | `/search` | — | Search products (public) |
| | | GET | `/search/filters` | — | Get filter options |
| | | GET | `/:id` | — | Get single product |
| | | POST | `/:id/image` | RG(admin,super_admin), PL | Upload product image |
| categories.controller.ts | `/categories` | POST | `/` | RG(admin,super_admin) | Create category |
| | | GET | `/` | — | List categories |
| | | GET | `/:id` | — | Get category |
| | | PUT | `/:id` | RG(admin,super_admin) | Update category |
| | | DELETE | `/:id` | RG(admin,super_admin) | Delete category |
| option-sets.controller.ts | `/option-sets` | GET | `/` | PA | List option sets |
| | | GET | `/:id` | PA | Get option set |
| | | POST | `/` | PA, RG(admin,super_admin) | Create option set |
| | | PUT | `/:id` | PA, RG(admin,super_admin) | Update option set |
| | | DELETE | `/:id` | PA, RG(admin,super_admin) | Delete option set |
| | | POST | `/:id/duplicate` | PA, RG(admin,super_admin) | Duplicate option set |
| | | GET | `/size-guides/list` | PA | List size guides |
| | | GET | `/size-guides/by-context` | PA | Size guides by context |
| | | GET | `/size-guides/:id` | PA | Get size guide |
| | | POST | `/size-guides` | PA, RG(admin,super_admin) | Create size guide |
| | | PUT | `/size-guides/:id` | PA, RG(admin,super_admin) | Update size guide |
| | | DELETE | `/size-guides/:id` | PA, RG(admin,super_admin) | Delete size guide |

### 3. CART

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| cart.controller.ts | `/api/cart` | POST | `/` | CC | Add to cart |
| | | GET | `/` | CC | Get cart |
| | | PUT | `/:id` | CC | Update item |
| | | DELETE | `/:id` | CC | Remove item |

### 4. ORDERS

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| orders.controller.ts | `/orders` | GET | `/` | CC | List orders |
| | | GET | `/search` | CC | Search orders |
| | | GET | `/track/:publicCode` | CC | Track by public code |
| | | GET | `/external/ref/:externalReference` | CC | Get by external ref |
| | | GET | `/user/:userId` | CC | User's orders |
| | | GET | `/status/:externalReference` | CC | Order status by ref |
| | | GET | `/:orderId` | CC | Get single order |
| | | PATCH | `/:orderId/status` | CC, RG(admin,super_admin) | Update order status |
| | | PATCH | `/:orderId/tracking` | CC, RG(admin,super_admin) | Update tracking |
| | | POST | `/:orderId/send-confirmation` | CC | Send confirmation email |

### 5. PAYMENTS (Tenant / Mercado Pago)

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| mercadopago.controller.ts | `/mercadopago` | POST | `/quote` | — | Quote payment |
| | | PUT | `/preferences/:id/payment-methods` | — | Update payment methods |
| | | POST | `/create-preference-for-plan` | — | Create preference for plan |
| | | POST | `/create-preference-advanced` | — | Advanced preference creation |
| | | POST | `/validate-cart` | — | Validate cart before payment |
| | | POST | `/create-preference` | — | Create MP preference |
| | | POST | `/confirm-payment` | — | Confirm payment |
| | | POST | `/notification` | **NT** | MP IPN notification |
| | | POST | `/webhook` | **NT** | MP webhook |
| | | GET | `/payment-details` | — | Get payment details |
| | | GET | `/payment-details/:paymentId` | — | Get specific payment |
| | | POST | `/confirm-by-reference` | — | Confirm by reference |
| | | POST | `/confirm-by-preference` | — | Confirm by preference |
| | | POST | `/subscriptions/reconcile` | — | Reconcile subscriptions |
| | | GET | `/debug/email` | — | Debug email |
| payments.controller.ts | `/api/payments` | GET | `/config` | CC | Get payment config |
| | | POST | `/quote` | CC | Quote payment |
| | | POST | `/quote-matrix` | CC | Quote matrix |
| | | POST | `/preference` | CC | Create preference |
| admin-payments.controller.ts | `/api/admin/payments` | GET | `/mp-fees` | TC, RG(admin,super_admin), PA | Get MP fees |
| | | PUT | `/config` | TC, RG(admin,super_admin), PA | Update payment config |
| | | GET | `/config` | TC, RG(admin,super_admin), PA | Get payment config |
| mp-router.controller.ts | `/webhooks/mp` | POST | `/tenant-payments` | **NT** | Route tenant payment webhooks |
| | | POST | `/platform-subscriptions` | **NT** | Route platform subscription webhooks |

### 6. SHIPPING

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| shipping.controller.ts | `/shipping` | GET | `/integrations/available-providers` | CC, PA | Available providers |
| | | GET | `/integrations` | CC, PA | List integrations |
| | | GET | `/integrations/:id` | CC, PA | Get integration |
| | | POST | `/integrations` | CC, PA | Create integration |
| | | PUT | `/integrations/:id` | CC, PA | Update integration |
| | | DELETE | `/integrations/:id` | CC, PA | Delete integration |
| | | POST | `/integrations/:id/test` | CC, PA | Test integration |
| | | GET | `/orders/:orderId` | CC, PA | Get shipping order |
| | | POST | `/orders/:orderId` | CC, PA | Create shipment |
| | | PATCH | `/orders/:orderId` | CC, PA | Update shipment |
| | | POST | `/orders/:orderId/sync-tracking` | CC, PA | Sync tracking |
| | | GET | `/settings` | CC, PA | Get shipping settings |
| | | PUT | `/settings` | CC, PA | Update shipping settings |
| | | GET | `/zones` | CC, PA | List shipping zones |
| | | GET | `/zones/:id` | CC, PA | Get zone |
| | | POST | `/zones` | CC, PA | Create zone |
| | | PUT | `/zones/:id` | CC, PA | Update zone |
| | | DELETE | `/zones/:id` | CC, PA | Delete zone |
| | | POST | `/quote` | CC, PA | Quote shipping |
| | | POST | `/quote/revalidate` | CC, PA | Revalidate quote |
| | | GET | `/quote/:quoteId` | CC, PA | Get quote |
| | | POST | `/webhooks/:provider` | **NT** | Provider webhooks |
| | | GET | `/webhook-failures` | CC, PA | List failures |
| | | POST | `/webhook-failures/:failureId/retry` | CC, PA | Retry failure |
| | | GET | `/health` | **NT** | Shipping health |

### 7. STORE APPEARANCE (Banners, Logo, Themes, Palettes, Home, SEO, Social, Contact, FAQ, Services, Legal, Templates)

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| banner.controller.ts | `/settings/banner` | GET | `/` | — | List banners |
| | | GET | `/all` | — | List all banners |
| | | POST | `/` | RG(admin,super_admin), PL | Create banner |
| | | PATCH | `/` | RG(admin,super_admin) | Update banner |
| | | DELETE | `/` | RG(admin,super_admin) | Delete banner |
| logo.controller.ts | `/settings/logo` | GET | `/` | — | Get logo |
| | | POST | `/` | RG(admin,super_admin) | Upload logo |
| | | DELETE | `/` | RG(admin,super_admin) | Delete logo |
| faq.controller.ts | `/settings/faqs` | GET | `/` | — | List FAQs |
| | | POST | `/` | RG(admin,super_admin) | Create FAQ |
| | | PUT | `/` | RG(admin,super_admin) | Update FAQ |
| | | DELETE | `/` | RG(admin,super_admin) | Delete FAQ |
| service.controller.ts | `/settings/services` | GET | `/` | — | List services |
| | | POST | `/` | RG(admin,super_admin) | Create service |
| | | PUT | `/:id` | RG(admin,super_admin) | Update service |
| | | DELETE | `/` | RG(admin,super_admin) | Delete service |
| home-settings.controller.ts | `/settings/home` | GET | `/` | — | Get home settings |
| | | PUT | `/` | RG(admin,super_admin) | Update home settings |
| | | PATCH | `/identity` | RG(admin,super_admin) | Update identity |
| | | POST | `/popup-image` | RG(admin,super_admin) | Upload popup image |
| | | DELETE | `/popup-image` | RG(admin,super_admin) | Delete popup image |
| settings.controller.ts | `/settings` | GET | `/identity` | TC | Get identity settings |
| | | PATCH | `/identity` | TC, RG(admin,super_admin) | Update identity |
| home.controller.ts | `/home` | GET | `/data` | — | Get home data (public) |
| | | GET | `/navigation` | — | Get navigation (public) |
| | | GET | `/sections` | TC | Get sections |
| | | POST | `/sections` | TC | Create section |
| | | PATCH | `/sections/order` | TC | Reorder sections |
| | | PATCH | `/sections/:id/replace` | TC | Replace section |
| | | DELETE | `/sections/:id` | TC | Delete section |
| social-links.controller.ts | `/social-links` | GET | `/` | — | List social links |
| | | POST | `/` | RG(admin,super_admin) | Create link |
| | | PUT | `/:id` | RG(admin,super_admin) | Update link |
| | | DELETE | `/:id` | RG(admin,super_admin) | Delete link |
| contact-info.controller.ts | `/contact-info` | GET | `/` | — | Get contact info |
| | | POST | `/` | RG(admin,super_admin) | Create contact info |
| | | PUT | `/:id` | RG(admin,super_admin) | Update contact info |
| | | DELETE | `/:id` | RG(admin,super_admin) | Delete contact info |
| themes.controller.ts | `/themes` | GET | `/:clientId` | BS | Get theme |
| | | PATCH | `/:clientId` | BS | Update theme |
| palettes.controller.ts | `/palettes` | GET | `/catalog` | NT | Get palette catalog |
| | | GET | `/admin/catalog` | NT+SA | Admin palette catalog |
| | | GET | `/` | BS | Builder palettes |
| | | POST | `/custom` | BS | Create custom palette |
| | | PUT | `/custom/:id` | BS | Update custom palette |
| | | DELETE | `/custom/:id` | BS | Delete custom palette |
| | | POST | `/admin` | NT+SA | Create admin palette |
| | | PUT | `/admin/:key` | NT+SA | Update admin palette |
| | | DELETE | `/admin/:key` | NT+SA | Delete admin palette |
| templates.controller.ts | `/templates` | GET | `/` | NT | List templates (public) |
| | | GET | `/admin/all` | NT+SA | Admin list all |
| | | POST | `/admin` | NT+SA | Create template |
| | | PUT | `/admin/:key` | NT+SA | Update template |
| | | DELETE | `/admin/:key` | NT+SA | Delete template |

### 8. SEO & SEO AI

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| seo.controller.ts | `/seo` | GET | `/settings` | — | Get SEO settings |
| | | PUT | `/settings` | RG(admin,super_admin) | Update SEO settings |
| | | GET | `/meta/:entity/:id` | PA | Get entity meta |
| | | PUT | `/meta/:entity/:id` | RG(admin,super_admin) | Update entity meta |
| | | GET | `/sitemap.xml` | — | Generate sitemap |
| | | GET | `/og` | — | OpenGraph data |
| | | GET | `/redirects` | RG(admin,super_admin), PA | List redirects |
| | | POST | `/redirects` | RG(admin,super_admin), PA | Create redirect |
| | | PUT | `/redirects/:id` | RG(admin,super_admin), PA | Update redirect |
| | | DELETE | `/redirects/:id` | RG(admin,super_admin), PA | Delete redirect |
| | | GET | `/redirects/resolve` | — | Resolve redirect |
| seo-ai.controller.ts | `/seo-ai` | POST | `/jobs` | NT+CD | Create SEO AI job |
| | | GET | `/jobs` | NT+CD | List SEO AI jobs |
| | | GET | `/jobs/:id` | NT+CD | Get job |
| | | GET | `/jobs/:id/log` | NT+CD | Get job log |
| | | GET | `/estimate` | NT+CD | Estimate cost |
| | | GET | `/entities-preview` | NT+CD | Preview entities |
| | | GET | `/status` | NT+CD | AI status |
| | | GET | `/audit` | NT+CD | SEO audit |
| | | GET | `/prompt` | NT+CD | Get prompt |
| seo-ai-purchase.controller.ts | `/seo-ai` | GET | `/packs` | NT | List AI credit packs |
| | | POST | `/purchase` | NT+CD | Purchase credits |
| | | GET | `/my-credits` | NT+CD | Get credit balance |
| | | POST | `/webhook` | NT | SEO AI purchase webhook |
| seo-ai-billing-admin.controller.ts | `/admin/seo-ai-billing` | GET | `/packs` | NT+SA | List packs |
| | | PATCH | `/packs/:addonKey` | NT+SA | Update pack |
| | | GET | `/credits/:accountId/balance` | NT+SA | Credit balance |
| | | GET | `/credits/:accountId` | NT+SA | Credit history |
| | | PATCH | `/credits/:accountId` | NT+SA | Adjust credits |
| | | GET | `/pricing` | NT+SA | Get pricing |
| | | PATCH | `/pricing/:entityType` | NT+SA | Update pricing |

### 9. FAVORITES, REVIEWS, QUESTIONS

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| favorites.controller.ts | `/favorites` | GET | `/` | — | List favorites |
| | | POST | `/merge` | — | Merge favorites |
| | | POST | `/:productId` | — | Add favorite |
| | | DELETE | `/:productId` | — | Remove favorite |
| reviews.controller.ts | *(no base)* | GET | `/products/:productId/reviews` | PA | List reviews |
| | | POST | `/products/:productId/reviews` | PA | Create review |
| | | PATCH | `/reviews/:reviewId` | PA | Update review |
| | | POST | `/reviews/:reviewId/reply` | PA, RG(admin,super_admin) | Reply to review |
| | | PATCH | `/reviews/:reviewId/moderate` | PA, RG(admin,super_admin) | Moderate review |
| | | GET | `/products/:productId/social-proof` | PA | Social proof |
| | | GET | `/admin/reviews` | PA, RG(admin,super_admin) | Admin list reviews |
| questions.controller.ts | *(no base)* | GET | `/products/:productId/questions` | PA | List questions |
| | | POST | `/products/:productId/questions` | PA | Ask question |
| | | POST | `/questions/:questionId/answers` | PA, RG(admin,super_admin) | Answer question |
| | | PATCH | `/questions/:questionId/moderate` | PA, RG(admin,super_admin) | Moderate question |
| | | DELETE | `/questions/:questionId` | PA | Delete question |
| | | GET | `/admin/questions` | PA, RG(admin,super_admin) | Admin list questions |

### 10. ADDRESSES

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| addresses.controller.ts | `/addresses` | GET | `/` | CC | List addresses |
| | | GET | `/:id` | CC | Get address |
| | | POST | `/` | CC | Create address |
| | | PUT | `/:id` | CC | Update address |
| | | DELETE | `/:id` | CC | Delete address |

### 11. STORE COUPONS (Tenant)

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| store-coupons.controller.ts | `/store-coupons` | GET | `/` | PA, RG(admin,super_admin) | List coupons |
| | | GET | `/:id` | PA, RG(admin,super_admin) | Get coupon |
| | | POST | `/` | PA, RG(admin,super_admin), PL | Create coupon |
| | | PUT | `/:id` | PA, RG(admin,super_admin) | Update coupon |
| | | DELETE | `/:id` | PA, RG(admin,super_admin) | Delete coupon |
| | | GET | `/:id/redemptions` | PA, RG(admin,super_admin) | Coupon redemptions |
| | | POST | `/validate` | PA | Validate coupon (buyer) |
| | | POST | `/:id/reverse-redemption` | PA, RG(admin,super_admin) | Reverse redemption |

### 12. SUBSCRIPTIONS

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| subscriptions.controller.ts | `/subscriptions` | GET | `/me` | BS | Get my subscription |
| | | POST | `/webhook` | NT | MP subscription webhook |
| | | POST | `/reconcile` | NT+SA | Reconcile |
| | | GET | `/:accountId/status` | NT+SA | Account sub status |
| | | GET | `/manage/status` | NT+BS | Manage: status |
| | | POST | `/manage/cancel` | NT+BS | Manage: cancel |
| | | POST | `/manage/revert-cancel` | NT+BS | Manage: revert cancel |
| | | POST | `/manage/pause-store` | NT+BS | Manage: pause store |
| | | POST | `/manage/resume-store` | NT+BS | Manage: resume |
| | | GET | `/manage/plans` | NT+BS | Manage: list plans |
| | | POST | `/manage/upgrade` | NT+BS+SG | Manage: upgrade plan |
| | | GET | `/client/manage/status` | NT+CD | Client manage: status |
| | | POST | `/client/manage/cancel` | NT+CD | Client manage: cancel |
| | | POST | `/client/manage/revert-cancel` | NT+CD | Client manage: revert |
| | | POST | `/client/manage/pause-store` | NT+CD | Client manage: pause |
| | | POST | `/client/manage/resume-store` | NT+CD | Client manage: resume |
| | | GET | `/client/manage/plans` | NT+CD | Client manage: plans |
| | | POST | `/client/manage/upgrade` | NT+CD+SG | Client manage: upgrade |
| | | POST | `/client/manage/validate-coupon` | NT+CD | Client validate coupon |

### 13. BILLING & FINANCE

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| billing.controller.ts | `/billing` | GET | `/admin/all` | NT, PlatformAuth | All billing records |
| | | POST | `/admin/:id/mark-paid` | NT, PlatformAuth | Mark invoice paid |
| | | POST | `/admin/:id/sync` | NT, PlatformAuth | Sync billing |
| | | GET | `/me` | NT, AuthMiddleware | My billing |
| quota.controller.ts | *(no base)* | GET | `/quotas/me` | — | My quotas |
| | | GET | `/v1/tenants/:id/quotas` | NT+SA | Tenant quotas |
| | | POST | `/v1/quota/check` | — | Check quota |
| finance.controller.ts | `/admin/finance` | GET | `/summary` | NT+SA | Finance summary |

### 14. PLANS

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| plans.controller.ts | `/plans` | GET | `/catalog` | NT | Plan catalog (public) |
| | | GET | `/pricing` | NT | Pricing (public) |
| | | GET | `/my-limits` | — | My plan limits |
| plans-admin.controller.ts | `/admin/plans` | GET | `/` | NT+SA | List plans |
| | | GET | `/:planKey` | NT+SA | Get plan |
| | | PATCH | `/:planKey` | NT+SA | Update plan |
| | | GET | `/clients/usage` | NT+SA | Clients usage overview |
| | | GET | `/clients/:clientId/usage` | NT+SA | Client usage |
| | | GET | `/clients/:clientId/features` | NT+SA | Client features |
| | | PATCH | `/clients/:clientId/features` | NT+SA | Update features |
| | | GET | `/clients/:clientId/entitlements` | NT+SA | Client entitlements |
| | | PATCH | `/clients/:clientId/entitlements` | NT+SA | Update entitlements |

### 15. ONBOARDING

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| onboarding.controller.ts | `/onboarding` | GET | `/active-countries` | NT | Active countries |
| | | GET | `/country-config/:countryId` | NT | Country config |
| | | POST | `/builder/start` | NT | Start builder |
| | | POST | `/resolve-link` | NT | Resolve link |
| | | POST | `/complete-owner` | NT+BS | Complete owner |
| | | POST | `/import-home-bundle` | NT+BS | Import home bundle |
| | | GET | `/status` | NT+BS | Builder status |
| | | GET | `/public/status` | NT | Public status |
| | | PATCH | `/progress` | NT+BS | Update progress |
| | | PATCH | `/preferences` | NT+BS | Update preferences |
| | | PATCH | `/custom-domain` | NT+BS | Update custom domain |
| | | GET | `/plans` | NT | Available plans |
| | | GET | `/palettes` | NT | Palette options |
| | | POST | `/preview-token` | NT+BS | Generate preview token |
| | | POST | `/checkout/start` | NT+BS | Start checkout |
| | | GET | `/checkout/status` | NT+BS | Checkout status |
| | | POST | `/checkout/confirm` | NT+BS | Confirm checkout |
| | | POST | `/link-google` | NT+BS | Link Google account |
| | | POST | `/checkout/webhook` | NT | Checkout webhook |
| | | POST | `/business-info` | NT+BS | Submit business info |
| | | POST | `/mp-credentials` | NT+BS | Submit MP credentials |
| | | POST | `/submit-for-review` | NT+BS | Submit for review |
| | | POST | `/submit` | NT+BS | Submit onboarding |
| | | POST | `/publish` | NT+BS | Publish store |
| | | POST | `/logo/upload-url` | NT+BS | Upload logo URL |
| | | POST | `/clients/:clientId/mp-secrets` | NT+BS | MP secrets |
| | | POST | `/session/save` | NT+BS | Save session |
| | | POST | `/session/upload` | NT+BS | Upload to session |
| | | POST | `/session/link-user` | NT+BS | Link user to session |
| | | GET | `/mp-status` | NT+BS | MP status |
| | | POST | `/session/accept-terms` | NT+BS | Accept terms |
| | | GET | `/resume` | NT+BO | Resume builder |
| | | POST | `/approve/:accountId` | NT+SA | Admin approve |

### 16. TENANT RESOLUTION & CLIENT

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| tenant.controller.ts | `/tenant` | GET | `/bootstrap` | TC | Bootstrap tenant data |
| | | GET | `/status` | TC | Tenant status |
| | | GET | `/resolve-host` | NT | Resolve host to tenant |
| | | GET | `/countries` | NT | List countries |
| clients.controller.ts | `/clients` | GET | `/me/requirements` | — | My requirements |
| | | POST | `/me/request-publish` | — | Request publish |
| client-dashboard.controller.ts | `/client-dashboard` | GET | `/completion-checklist` | NT+CD | Completion checklist |
| | | POST | `/completion-checklist/update` | NT+CD | Update checklist |
| | | POST | `/completion-checklist/resubmit` | NT+CD | Resubmit checklist |
| | | POST | `/products` | NT+CD | Add products |
| | | POST | `/categories` | NT+CD | Add categories |
| | | POST | `/faqs` | NT+CD | Add FAQs |
| | | POST | `/contact-info` | NT+CD | Add contact info |
| | | POST | `/social-links` | NT+CD | Add social links |
| | | POST | `/import-json` | NT+CD | Import JSON |
| | | GET | `/products/list` | NT+CD | List products |
| | | GET | `/categories/list` | NT+CD | List categories |
| | | GET | `/faqs/list` | NT+CD | List FAQs |
| | | GET | `/contact-info` | NT+CD | Get contact info |
| | | GET | `/social-links` | NT+CD | Get social links |
| | | GET | `/domain` | NT+CD | Get domain |
| | | POST | `/domain/renew` | NT+CD | Renew domain |
| client-managed-domain.controller.ts | `/client/managed-domains` | GET | `/` | TC | List managed domains |
| analytics.controller.ts | `/api/analytics` | GET | `/summary` | CC, PA | Analytics summary |

### 17. LEGAL

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| legal.controller.ts | `/legal` | GET | `/documents` | NT | List legal documents |
| | | GET | `/documents/:type` | NT | Get legal doc by type |
| | | POST | `/buyer-consent` | — | Record buyer consent |
| | | POST | `/withdrawal` | — | Create withdrawal |
| | | GET | `/withdrawal/:trackingCode` | — | Track withdrawal |
| | | GET | `/withdrawals` | — | List withdrawals |
| | | PATCH | `/withdrawal/:id` | — | Update withdrawal |
| | | GET | `/withdrawal/order/:orderId` | — | Withdrawal by order |
| | | POST | `/cancellation` | NT+SA | Create cancellation |
| | | GET | `/cancellation/:trackingCode` | NT | Track cancellation |

### 18. PLATFORM COUPONS (NovaVision platform level)

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| admin-coupons.controller.ts | `/admin/coupons` | POST | `/` | NT+SA | Create platform coupon |
| | | GET | `/` | NT+SA | List platform coupons |
| | | PATCH | `/:id/toggle` | NT+SA | Toggle coupon |
| | | DELETE | `/:id` | NT+SA | Delete coupon |
| coupons.controller.ts | `/coupons` | POST | `/validate` | NT+BO | Validate platform coupon |

### 19. SUPER ADMIN — Platform Management

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| admin.controller.ts | `/admin` | GET | `/dashboard-meta` | NT+SA | Dashboard metadata |
| | | GET | `/pending-approvals` | NT+SA | Pending approvals |
| | | GET | `/backend-clusters` | NT+SA | DB clusters |
| | | POST | `/backend-clusters` | NT+SA | Create cluster |
| | | POST | `/backend-clusters/:clusterId/db-url` | NT+SA | Set cluster DB URL |
| | | POST | `/backend-clusters/:targetClusterId/clone-schema` | NT+SA | Clone schema |
| | | GET | `/pending-approvals/:id` | NT+SA | Get approval detail |
| | | GET | `/accounts/:id/details` | NT+SA | Account details |
| | | GET | `/accounts/:id/subscription-status` | NT+SA | Sub status |
| | | GET | `/accounts/:id/360` | NT+SA | Account 360 view |
| | | GET | `/accounts/:id/completion-checklist` | NT+SA | Completion checklist |
| | | GET | `/completion-requirements/defaults` | NT+SA | Default requirements |
| | | PATCH | `/completion-requirements/defaults` | NT+SA | Update defaults |
| | | GET | `/accounts/:id/completion-requirements` | NT+SA | Account requirements |
| | | PATCH | `/accounts/:id/completion-requirements` | NT+SA | Update requirements |
| | | DELETE | `/accounts/:id/completion-requirements` | NT+SA | Reset requirements |
| | | POST | `/clients/:id/backfill-catalog` | NT+SA | Backfill catalog |
| | | POST | `/clients/:id/sync-mp` | NT+SA | Sync MP |
| | | POST | `/clients/:id/approve` | NT+SA | Approve client |
| | | POST | `/clients/:id/backfill-nv-account-id` | NT+SA | Backfill NV ID |
| | | POST | `/clients/:id/validate-and-cleanup` | NT+SA | Validate & cleanup |
| | | POST | `/accounts/:id/custom-domain` | NT+SA | Set custom domain |
| | | POST | `/accounts/:id/custom-domain/verify` | NT+SA | Verify domain |
| | | PATCH | `/accounts/:accountId/products/:productId` | NT+SA | Update product |
| | | POST | `/clients/:id/request-changes` | NT+SA | Request changes |
| | | POST | `/clients/:id/reject-final` | NT+SA | Final reject |
| | | POST | `/clients/:id/review-email/preview` | NT+SA | Preview review email |
| | | POST | `/clients/:id/pause` | NT+SA | Pause client |
| | | POST | `/stats` | NT+SA | Generate stats |
| | | GET | `/pending-completions` | NT+SA | Pending completions |
| | | GET | `/clients` | NT+SA | List all clients |
| | | GET | `/finance/clients` | NT+SA | Finance clients |
| | | GET | `/clients/:id` | NT+SA | Get client |
| | | GET | `/metrics/summary` | NT+SA | Metrics summary |
| | | GET | `/metrics/tops` | NT+SA | Top metrics |
| | | GET | `/clients/:id/metrics` | NT+SA | Client metrics |
| | | GET | `/subscriptions/health` | NT+SA | Subscription health |
| | | GET | `/subscription-events` | NT+SA | Subscription events |
| | | GET | `/check-invariants` | NT+SA | Check invariants |
| | | DELETE | `/accounts/:accountId/products/:productId` | NT+SA | Delete product |
| | | GET | `/accounts/:id/categories` | NT+SA | Account categories |
| | | POST | `/accounts/:id/categories` | NT+SA | Add category |
| | | DELETE | `/accounts/:accountId/categories/:categoryId` | NT+SA | Delete category |
| | | GET | `/accounts/:id/faqs` | NT+SA | Account FAQs |
| | | POST | `/accounts/:id/faqs` | NT+SA | Add FAQ |
| | | DELETE | `/accounts/:accountId/faqs/:faqId` | NT+SA | Delete FAQ |
| | | GET | `/accounts/:id/services` | NT+SA | Account services |
| | | POST | `/accounts/:id/services` | NT+SA | Add service |
| | | DELETE | `/accounts/:accountId/services/:serviceId` | NT+SA | Delete service |
| | | PATCH | `/accounts/:accountId/categories/:categoryId` | NT+SA | Update category |
| | | PATCH | `/accounts/:accountId/faqs/:faqId` | NT+SA | Update FAQ |
| | | PATCH | `/accounts/:accountId/services/:serviceId` | NT+SA | Update service |
| | | GET | `/accounts/:id/contact-social` | NT+SA | Contact & social |
| | | PATCH | `/accounts/:id/contact-social` | NT+SA | Update contact & social |
| admin-accounts.controller.ts | `/admin/accounts` | POST | `/draft` | NT+SA | Create draft account |
| | | POST | `/:accountId/onboarding-link` | NT+SA | Generate onboarding link |
| admin-client.controller.ts | `/admin/clients` | DELETE | `/:clientId` | NT+SA | Delete client |
| | | POST | `/:clientId/payment-reminder` | NT+SA | Send payment reminder |
| | | POST | `/:clientId/payments` | NT+SA | Register payment |
| | | PATCH | `/:clientId/status` | NT+SA | Update client status |
| | | GET | `/:clientId/payments` | NT+SA | List payments |
| | | GET | `/:clientId/invoices` | NT+SA | List invoices |
| | | POST | `/:clientId/sync-invoices` | NT+SA | Sync invoices |
| | | POST | `/:clientId/sync-to-backend` | NT+SA | Sync to backend |
| | | GET | `/:clientId/usage-months` | NT+SA | Usage months |
| | | GET | `/:clientId/diff` | NT+SA | Client diff |
| admin-adjustments.controller.ts | `/admin/adjustments` | GET | `/` | NT+SA | List adjustments |
| | | GET | `/:id` | NT+SA | Get adjustment |
| | | POST | `/:id/charge` | NT+SA | Charge adjustment |
| | | POST | `/:id/waive` | NT+SA | Waive adjustment |
| | | POST | `/bulk-charge` | NT+SA | Bulk charge |
| | | POST | `/recalculate` | NT+SA | Recalculate |
| admin-country-configs.controller.ts | `/admin/country-configs` | GET | `/` | NT+SA | List country configs |
| | | PATCH | `/:siteId` | NT+SA | Update config |
| | | POST | `/` | NT+SA | Create config |
| admin-fee-schedules.controller.ts | `/admin/fee-schedules` | GET | `/` | NT+SA | List fee schedules |
| | | POST | `/` | NT+SA | Create schedule |
| | | PATCH | `/:id` | NT+SA | Update schedule |
| | | DELETE | `/:id` | NT+SA | Delete schedule |
| | | POST | `/:id/lines` | NT+SA | Add line |
| | | PATCH | `/:id/lines/:lineId` | NT+SA | Update line |
| | | DELETE | `/:id/lines/:lineId` | NT+SA | Delete line |
| admin-fx-rates.controller.ts | `/admin/fx` | GET | `/rates` | NT+SA | Get FX rates |
| | | PATCH | `/rates/:countryId` | NT+SA | Update FX rate |
| | | POST | `/rates/:countryId/refresh` | NT+SA | Refresh rate |
| admin-managed-domain.controller.ts | `/admin/managed-domains` | GET | `/` | NT+SA | List domains |
| | | POST | `/provision` | NT+SA | Provision domain |
| | | POST | `/trigger-expirations` | NT+SA | Trigger expirations |
| | | GET | `/account/:accountId` | NT+SA | Account domains |
| | | GET | `/:id` | NT+SA | Get domain |
| | | POST | `/:id/quote` | NT+SA | Quote domain |
| | | POST | `/:id/mark-renewed` | NT+SA | Mark renewed |
| | | POST | `/:id/manual-renewal` | NT+SA | Manual renewal |
| | | POST | `/:id/mark-failed` | NT+SA | Mark failed |
| | | POST | `/:id/verify-dns` | NT+SA | Verify DNS |
| | | POST | `/account/:accountId/verify-dns` | NT+SA | Verify DNS by account |
| admin-option-sets.controller.ts | `/admin/option-sets` | GET | `/` | NT+SA | List option sets |
| | | GET | `/stats` | NT+SA | Stats |
| | | GET | `/:id` | NT+SA | Get option set |
| | | POST | `/` | NT+SA | Create |
| | | PUT | `/:id` | NT+SA | Update |
| | | DELETE | `/:id` | NT+SA | Delete |
| | | POST | `/:id/duplicate` | NT+SA | Duplicate |
| admin-quotas.controller.ts | `/admin/quotas` | GET | `/` | NT+SA | List quotas |
| | | GET | `/:tenantId` | NT+SA | Tenant quota |
| | | PATCH | `/:tenantId` | NT+SA | Update quota |
| | | POST | `/:tenantId/reset` | NT+SA | Reset quota |
| admin-renewals.controller.ts | `/admin/renewals` | POST | `/:id/checkout` | NT+SA | Renewal checkout |
| | | POST | `/:id/send-email` | NT+SA | Send renewal email |
| admin-shipping.controller.ts | `/admin/shipping` | GET | `/overview` | NT+SA | Shipping overview |
| | | GET | `/shipments` | NT+SA | List shipments |
| | | GET | `/integrations` | NT+SA | List integrations |
| | | GET | `/webhook-failures` | NT+SA | Webhook failures |
| | | POST | `/webhook-failures/:failureId/retry` | NT+SA | Retry failure |
| | | GET | `/providers` | NT+SA | List providers |
| | | PUT | `/providers/:provider` | NT+SA | Update provider |
| admin-store-coupons.controller.ts | `/admin/store-coupons` | GET | `/` | NT+SA | List all store coupons |
| | | GET | `/stats` | NT+SA | Stats |
| | | GET | `/access` | NT+SA | Access configs |
| | | PATCH | `/plan-defaults` | NT+SA | Update plan defaults |
| | | PATCH | `/access/:clientId` | NT+SA | Update client access |
| media-admin.controller.ts | `/admin/media` | DELETE | `/clients/:clientId` | NT+SA | Delete client media |
| | | DELETE | `/clients/:clientId/stats` | NT+SA | Delete media stats |
| super-admin-email-jobs.controller.ts | `/admin/super-emails` | GET | `/` | NT+SA | List email jobs |
| | | POST | `/:id/retry` | NT+SA | Retry email |
| | | POST | `/:id/resend` | NT+SA | Resend email |
| system.controller.ts | `/admin/system` | GET | `/health` | NT+SA | System health |
| | | GET | `/audit/recent` | NT+SA | Recent audit entries |
| metrics.controller.ts | `/admin/metering` | POST | `/sync` | NT+SA | Sync metering |
| | | GET | `/summary` | NT+SA | Metering summary |

### 20. MERCADO PAGO OAUTH

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| mp-oauth.controller.ts | `/mp/oauth` | GET | `/start` | NT | Start MP OAuth |
| | | GET | `/callback` | NT | MP OAuth callback |
| | | GET | `/start-url` | RG(admin,super_admin) | Get start URL |
| | | GET | `/status/:clientId` | RG(admin,super_admin) | MP connection status |
| | | POST | `/disconnect/:clientId` | RG(admin,super_admin) | Disconnect MP |
| | | POST | `/refresh/:accountId` | RG(super_admin) | Refresh MP tokens |

### 21. SUPPORT TICKETS

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| support.controller.ts | `/client-dashboard/support` | GET | `/tickets` | NT+CD | List my tickets |
| | | POST | `/tickets` | NT+CD | Create ticket |
| | | GET | `/tickets/:ticketId` | NT+CD | Get ticket |
| | | GET | `/tickets/:ticketId/messages` | NT+CD | Get messages |
| | | POST | `/tickets/:ticketId/messages` | NT+CD | Send message |
| | | PATCH | `/tickets/:ticketId/close` | NT+CD | Close ticket |
| | | PATCH | `/tickets/:ticketId/reopen` | NT+CD | Reopen ticket |
| support-admin.controller.ts | `/admin/support` | GET | `/metrics` | NT+SA | Support metrics |
| | | GET | `/tickets` | NT+SA | All tickets |
| | | GET | `/tickets/:ticketId` | NT+SA | Get ticket |
| | | GET | `/tickets/:ticketId/messages` | NT+SA | Messages |
| | | GET | `/tickets/:ticketId/events` | NT+SA | Events |
| | | PATCH | `/tickets/:ticketId` | NT+SA | Update ticket |
| | | POST | `/tickets/:ticketId/messages` | NT+SA | Reply |
| | | PATCH | `/tickets/:ticketId/assign` | NT+SA | Assign ticket |
| | | GET | `/accounts/:accountId/ticket-limit` | NT+SA | Ticket limit |
| | | PATCH | `/accounts/:accountId/ticket-limit` | NT+SA | Update limit |

### 22. CORS, HEALTH & DEBUG

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| cors-origins.controller.ts | `/cors-origins` | GET | `/` | NT+SA | List CORS origins |
| | | POST | `/` | NT+SA | Add origin |
| | | PATCH | `/:id` | NT+SA | Update origin |
| | | DELETE | `/:id` | NT+SA | Delete origin |
| health.controller.ts | `/health` | GET | `/` | NT | Health check |
| | | GET | `/live` | NT | Liveness probe |
| | | GET | `/ready` | NT | Readiness probe |
| debug.controller.ts | `/debug` | GET | `/whoami` | NT+SA | Debug current user |

### 23. DEV & DEMO

| Controller | Base Path | Method | Route | Guards/Decorators | Notes |
|---|---|---|---|---|---|
| demo.controller.ts | `/demo` | POST | `/seed` | BS | Seed demo data |
| dev-portal.controller.ts | `/dev/portal` | GET | `/verify-access` | NT+BO | Verify portal access |
| | | GET | `/health` | NT | Portal health |
| | | GET | `/whitelist` | NT+SA | Get whitelist |
| | | POST | `/whitelist` | NT+SA | Add to whitelist |
| | | PATCH | `/whitelist/:email` | NT+SA | Update whitelist |
| | | DELETE | `/whitelist/:email` | NT+SA | Remove from whitelist |
| dev-seeding.controller.ts | `/dev` | POST | `/seed-tenant` | NT+SA | Seed tenant |
| | | GET | `/tenants` | NT+SA | List dev tenants |
| | | DELETE | `/tenants/:slug` | NT+SA | Delete dev tenant |

---

### Resumen cuantitativo

| Dominio | Controllers | Endpoints aprox. |
|---|---|---|
| Auth & Identity | 4 | 26 |
| Catalog | 3 | 22 |
| Cart | 1 | 4 |
| Orders | 1 | 10 |
| Payments (Tenant/MP) | 4 | 21 |
| Shipping | 1 | 25 |
| Store Appearance | 11 | 42 |
| SEO & SEO AI | 4 | 23 |
| Favorites/Reviews/Questions | 3 | 15 |
| Addresses | 1 | 5 |
| Store Coupons | 1 | 8 |
| Subscriptions | 1 | 19 |
| Billing & Finance | 3 | 7 |
| Plans | 2 | 11 |
| Onboarding | 1 | 32 |
| Tenant & Client Dashboard | 4 | 22 |
| Legal | 1 | 10 |
| Platform Coupons | 2 | 5 |
| Super Admin (all admin/*) | 16 | ~110 |
| MP OAuth | 1 | 6 |
| Support Tickets | 2 | 17 |
| CORS/Health/Debug | 3 | 8 |
| Dev & Demo | 3 | 8 |
| **TOTAL** | **77** | **~356** |

### Observaciones de seguridad identificadas

1. **`/mercadopago` controller** — la mayoría de endpoints NO tienen guards explícitos (ni CC ni RG). Dependen del middleware global, pero debería verificarse.
2. **Webhook endpoints sin firma** — `/shipping/webhooks/:provider`, `/subscriptions/webhook`, `/onboarding/checkout/webhook` — deben validar HMAC/firma. El legado `/seo-ai/webhook` ya fue eliminado.
3. **`/demo/seed`** usa solo `BuilderSessionGuard` — potencialmente peligroso si un builder puede inyectar datos.
4. **`/mercadopago/debug/email`** — endpoint de debug expuesto sin guards visibles.
5. **Duplicación de rutas** — `/seo-ai` base path compartido entre `seo-ai.controller.ts` y `seo-ai-purchase.controller.ts`.
6. **Withdrawal routes** en `/legal` no tienen RG explícito — dependen del middleware global para auth.

---

# Fase W — Auditoría del Web Storefront (React)

**Fecha:** 2026-02-25  
**Ruta:** `apps/web/src/`  
**Stack:** Vite + React 18 + Styled Components + axios + Supabase JS (solo Auth)

---

## W.1 — Estructura de Directorios del Source

```
src/
├── __dev/pages/          # Dev Portal (solo DEV mode)
├── ai/                   # Auditors & generators (dev tooling)
│   ├── auditors/         # SecurityAuditor, MultiTenantAuditor, StyleAuditor
│   ├── generators/
│   └── prompts/
├── api/                  # API client mejorado (ETag, polling, enhanced services)
│   ├── index.js          # Re-exports: orders, payments, mercadopago enhanced
│   ├── client.ts         # apiClient con axios + X-Tenant-Slug interceptor
│   ├── payments.ts       # Typed payment API
│   ├── paymentsEnhanced.js
│   ├── ordersEnhanced.js
│   └── mercadopagoEnhanced.js
├── components/
│   ├── admin/            # Admin panel components (17 secciones)
│   ├── checkout/         # CheckoutStepper (4 steps), CouponInput, ShippingSection
│   ├── product/          # ShippingEstimator, ProductReviews, ProductQA, StarRating
│   ├── ProductCard/      # Tarjeta de producto (PLP)
│   ├── ProductModal/     # Modal de creación/edición de producto (admin)
│   ├── ProductSearch/    # Buscador con paginación
│   ├── SEOHead/          # ProductSEO, JsonLd
│   ├── StoreBootLoader/  # Loading screen while tenant resolves
│   └── ... (Header, Footer, Toast, etc.)
├── config/
├── constants/
├── context/
│   ├── AuthProvider.jsx
│   ├── CartProvider.jsx      # Orquestador: delega a 8 hooks especializados
│   ├── FavoritesProvider.jsx # Strategy pattern: Local vs Remote store
│   ├── LoadingProvider.jsx
│   └── TenantProvider.jsx    # Resolución de tenant + bootstrap + gating
├── core/                 # Constantes, schemas, validators compartidos
├── favorites/
│   ├── LocalFavoritesStore.js    # Guest: localStorage scoped
│   ├── RemoteFavoritesStore.js   # Logged in: API calls con retry
│   └── storeFactory.js           # Strategy factory
├── hooks/
│   ├── cart/
│   │   ├── useCartItems.js       # CRUD carrito vía /api/cart
│   │   ├── useCartQuotes.js      # Cotizaciones con cache
│   │   ├── useCartValidation.js  # Validación pre-checkout
│   │   ├── useCheckout.js        # Genera preferencia MP con idempotencia
│   │   ├── usePaymentPolling.js  # Polling estado del pago
│   │   ├── usePaymentSettings.js # Config de planes/cuotas del tenant
│   │   ├── useShipping.js        # Settings + quote de envío
│   │   └── useAddresses.js       # CRUD direcciones del comprador
│   └── useCheckoutStepper.js     # Máquina de estados del stepper
├── lib/
├── pages/
│   ├── AdminDashboard/
│   ├── CartPage/                 # Página de carrito (wrapper del stepper)
│   ├── ProductPage/              # PDP con gallery, reviews, Q&A, shipping estimator
│   ├── FavoritesPage/
│   ├── PaymentResultPage/        # Callbacks de MP (?status=approved|pending|rejected)
│   ├── SearchPage/
│   ├── PreviewHost/              # Preview de tienda para onboarding
│   ├── LoginPage/
│   └── ... (Maintenance, NotFound, Legal, etc.)
├── preview/
├── registry/
├── routes/
├── sections/             # Secciones reutilizables (header, footer, hero, product)
├── services/
│   ├── supabase.js       # createClient con ANON_KEY + PKCE auth
│   ├── axiosConfig.jsx   # Interceptores: X-Tenant-Slug + Bearer + tenant mismatch guard
│   └── homeData/
├── styles/
├── templates/            # 8 templates de tienda (first..eighth)
├── theme/
├── tour/                 # Guided tours (admin)
├── types/
├── utils/
│   ├── cart/             # paymentPlanHelpers, quoteHelpers, validationHelpers
│   ├── tenantScope.js    # getTenantSlug(), getScopedKey()
│   ├── tenantResolver.js # getStoreSlugFromHost(), isLikelyCustomDomain()
│   ├── storage.ts        # Scoped storage (session/persist per tenant)
│   ├── formatCurrency.js
│   └── encrypt.jsx       # ⚠️ AES con clave hardcodeada "secret"
└── validators/
```

---

## W.2 — Resolución de Tenant (Multi-Tenant)

### Mecanismo de resolución (3 fuentes, prioridad descendente):

| # | Fuente | Ejemplo | Implementación |
|---|--------|---------|----------------|
| 1 | **Query param** `?tenant=slug` | `localhost:5173?tenant=mitienda` | `tenantResolver.js` → solo en DEV o localhost |
| 2 | **Subdominio** de `novavision.lat` | `mitienda.novavision.lat` | `tenantResolver.js` → extrae primer segmento del hostname |
| 3 | **Custom domain** (async) | `www.mitienda.com` | `TenantProvider.jsx` → `GET /tenant/resolve-host?domain=xxx` |

### Flujo completo:
1. `tenantScope.js` → `getTenantSlug()` resuelve el slug sincrónicamente (query param / subdominio / cache `window.__NV_TENANT_SLUG__`)
2. `TenantProvider.jsx` → si el slug sync falla y el hostname parece custom domain, llama a `GET /tenant/resolve-host` async
3. Una vez resuelto, setea `axios.defaults.headers.common['x-tenant-slug']` y `['x-store-slug']` **globalmente**
4. Llama a `GET /tenant/bootstrap` para obtener config completa del tenant
5. Valida estado (`suspended`, `pending_approval`, `is_active`)
6. Cachea en `tenantFetchState` (module-level) para evitar doble-fetch en StrictMode

### Headers enviados en CADA request:
- `X-Tenant-Slug: <slug>` — identificación del tenant
- `X-Store-Slug: <slug>` — alias de compatibilidad
- `Authorization: Bearer <jwt>` — cuando hay sesión (Supabase Auth token)

### ✅ Buenas prácticas detectadas:
- **No se envía `x-client-id` hardcodeado** — el backend resuelve el client_id desde el slug
- **Cross-tenant guard en el interceptor**: si el slug del header difiere del slug actual, el request se bloquea (`Cross-Tenant Request Blocked`)
- **Subdominios reservados**: `build`, `www`, `novavision` son excluidos
- **Validación de formato**: solo `[a-z0-9-]` para slugs
- **Module-level dedup**: evita race conditions en StrictMode

### ⚠️ Hallazgos:
1. **`VITE_CLIENT_ID` presente como fallback** en `CartProvider` (`resolvedClientId` memo) y `ProductPage` — es un env var legacy. Si se setea incorrectamente, podría enviar un `client_id` incorrecto al backend. **Riesgo bajo** porque el backend resuelve por slug, no por client_id del front.
2. **`VITE_DEV_SLUG`** permite override en dev — correcto, pero asegurar que no llega a producción.

---

## W.3 — API Client y Cómo se Hacen los Requests

### Dos clientes coexisten:

| Cliente | Archivo | Uso |
|---------|---------|-----|
| **axiosConfig** (principal) | `services/axiosConfig.jsx` | Carrito, productos, checkout, shipping, favoritos, órdenes — **todo pasa por acá** |
| **apiClient** (secundario) | `api/client.ts` | Módulo `api/` con ETag, polling — usado por `ordersEnhanced`, `paymentsEnhanced`, `mercadopagoEnhanced` |

### Interceptor en axiosConfig (principal):
```
Request flow:
  1. getTenantSlug() → setea X-Tenant-Slug global al bootstrap
  2. Per-request: supabase.auth.getSession() → Bearer token
  3. Strictness check: compara slug del header vs slug actual → bloquea si mismatch
  4. Emite event 'loading-start'

Response flow:
  1. Emite event 'loading-stop'
  2. Si 401 → dispara 'session-expired' event
```

### Interceptor en apiClient (secundario):
```
Request flow:
  1. extractTenantSlug() → X-Tenant-Slug header
  2. getTenantHost() → X-Tenant-Host header (custom domains)
  3. supabase.auth.getSession() → Bearer token

Response flow:
  1. Log errors en DEV
  2. Si 401 → dispara 'session-expired' event
```

### ⚠️ Hallazgo: **Dos clientes axios** con interceptores ligeramente distintos. El `apiClient` (client.ts) agrega `X-Tenant-Host` para custom domains, pero el `axiosConfig` principal NO lo agrega. Esto puede causar que las llamadas del módulo principal (cart, products, etc.) **no funcionen con custom domains** si el backend depende de ese header.

---

## W.4 — Carrito (Cart)

### Arquitectura:
`CartProvider` (orquestador) delega a 8 hooks especializados:
- `useCartItems` — CRUD de items
- `useCartQuotes` — Cotizaciones con cache
- `useCartValidation` — Validación pre-checkout
- `useCheckout` — Generación de preferencia MP
- `usePaymentPolling` — Polling estado del pago
- `usePaymentSettings` — Config de planes/cuotas
- `useShipping` — Envío (settings + quote)
- `useAddresses` — CRUD de direcciones

### Add to Cart — Payload enviado:
```json
POST /api/cart
{
  "productId": "uuid",
  "quantity": 1,
  "expectedPrice": 1500.00,           // Precio que ve el usuario → detección de cambio
  "selectedOptions": [                  // Solo si hay option sets
    { "key": "talle", "label": "Talle", "value": "M" },
    { "key": "color", "label": "Colores", "value": "Rojo" }
  ]
}
```

### Update Quantity — Payload:
```json
PUT /api/cart/:itemId
{
  "productId": "uuid",
  "quantity": 3
}
```

### Delete Item:
```
DELETE /api/cart/:itemId
```

### Fetch Cart:
```
GET /api/cart?includeQuote=true&method=debit&installments=1&settlementDays=0
```
Respuesta incluye `cartItems`, `totals`, y opcionalmente `quote`.

### ✅ Buenas prácticas:
- **Detección de cambio de precio**: envía `expectedPrice` y notifica al usuario si el backend detecta discrepancia
- **Validación de stock**: verifica `product.quantity/stock` antes de incrementar
- **Optimistic delete**: actualiza UI inmediatamente y luego sincroniza
- **Dedupe de fetches**: usa `lastFetchRef` para evitar requests duplicados
- **Login required**: si el usuario no está logueado, redirige a `/login` con `redirectAfterLogin`

### ⚠️ Hallazgos:
1. **`clearCart` es solo local**: no llama DELETE al backend — si el usuario tiene items, el servidor los conserva. Esto es intencional post-pago, pero podría causar inconsistencia si se llama desde otro flujo.
2. **`quantity` vs `stock` ambigüedad**: en `increaseQuantity`, el stock máximo se busca como `item.product?.quantity ?? item.product?.stock ?? 999`. El fallback a `999` es permisivo.

---

## W.5 — Checkout

### Flujo:
```
generatePreference()
  → Validar: hasMpCredentials? Plan válido? Carrito no vacío? Cart validado?
  → Calcular plan forzado (si credit_card excluido → debit_1)
  → Calcular settlementDays final (validar contra allowedSettlementDays)
  → Construir payload
  → POST /mercadopago/create-preference-for-plan (con Idempotency-Key)
  → Guardar refs en storage (preference_id, external_reference)
  → window.location.replace(redirect_url)
```

### Payload de Checkout:
```json
POST /mercadopago/create-preference-for-plan
Headers: { "Idempotency-Key": "uuid" }
{
  "baseAmount": 15000.00,
  "selection": {
    "method": "debit",
    "installmentsSeed": 1,
    "settlementDays": 0,
    "planKey": "debit_1"
  },
  "cartItems": [...snapshot...],
  "delivery": {                          // Solo si hay envío
    "method": "delivery",
    "quote_id": "uuid | null",
    "shipping_cost": 500.00,
    "save_address": false,
    "address_id": "uuid"                 // O "address": { full_name, street, ... }
  },
  "couponCode": "DESCUENTO10"           // Solo si hay cupón aplicado
}
```

### ✅ Buenas prácticas:
- **Idempotency-Key**: genera UUID único por intento, se resetea al cambiar plan
- **Double-submit guard**: `generatingRef.current` previene clicks dobles
- **Precios del backend**: `baseAmount` es `totals.priceWithDiscount` calculado por el backend
- **Error handling exhaustivo**: mapeo de códigos de error del backend a mensajes en español
- **Cart snapshot**: `createCartSnapshot()` congela items (producto/cantidad/precio)

### ⚠️ Hallazgos:
1. **`window.location.replace(redirect_url)`**: un atacante que controlara la respuesta del backend podría redirigir a un sitio malicioso. **Riesgo bajo** (requiere compromiso del backend), pero se podría validar que `redirect_url` pertenece a MP (`mercadopago.com`).

---

## W.6 — Product Detail Page (PDP)

### Datos mostrados:
- `name`, `brand`, `originalPrice`, `discountedPrice`, `discountPercentage`
- `promotionTitle`, `promotionDescription`
- `stock` (de `product.quantity`)
- `images` (array ordenado por `order`)
- `tags` (parsed de string CSV)
- `categories` (array de objetos)
- `material`, `sizes`, `colors`
- `resolved_options` (option sets con variantes)
- Social proof: `avg_rating`, `review_count` (de `/products/:id/social-proof`)

### Transformaciones client-side:
- Precios: `_disc > 0 ? _disc : _orig` con `formatCurrency()`
- Imágenes: sort por `.order` y mapeo a URLs
- Tags: split por coma
- Options: automáticamente se selecciona el primer item de cada grupo
- Productos relacionados: busca por categoría en cache local → fallback a `/products/search` API

### Campos del add-to-cart payload (PDP):
```js
{
  ...product,          // Objeto completo del producto
  quantity: N,         // Cantidad seleccionada por el usuario
  selectedOptions: [   // Opciones elegidas en el PDP
    { type: "talle", value: "M", label: "M" }
  ]
}
```
Luego `useCartItems.addItem()` lo transforma a: `{ productId, quantity, expectedPrice, selectedOptions }`

### ⚠️ Hallazgos:
1. **Se envía el objeto completo del producto** al addToCart: `{ ...product, quantity, selectedOptions }`. Dentro de `addItem`, se extrae solo `product.id`, `quantity`, y `expectedPrice`. Esto está bien pero es innecesario enviar tanto.
2. **`fetchProduct`** no valida el formato del `id` antes de enviarlo al backend. Si alguien navega a `/product/<script>...`, se envía como parte de la URL.

---

## W.7 — Favoritos

### Arquitectura (Strategy Pattern):
- **Guest (no logueado)**: `LocalFavoritesStore` — localStorage scoped por tenant
- **Logged in**: `RemoteFavoritesStore` — API calls (`/favorites`, `/favorites/:id`, `/favorites/merge`)
- **Factory**: `storeFactory.js` decide cuál usar

### Operaciones:
| Op | Guest | Logged In |
|----|-------|-----------|
| Add | localStorage | `POST /favorites/:productId` |
| Remove | localStorage | `DELETE /favorites/:productId` |
| List | localStorage | `GET /favorites` |
| Hydrate | N/A | `GET /favorites?full=1&page=X&pageSize=Y` |
| Merge | N/A | `POST /favorites/merge { productIds }` |

### ✅ Buenas prácticas:
- **Optimistic updates** con rollback en error
- **Merge post-login**: sincroniza favoritos guest con el servidor
- **Retry con backoff** en merge (hasta 4 intentos, 300ms * intentos)

---

## W.8 — Direcciones (Addresses)

### CRUD via backend:
```
GET    /addresses        → listado del usuario
POST   /addresses        → crear
PUT    /addresses/:id    → actualizar
DELETE /addresses/:id    → eliminar
```

### ✅ Buenas prácticas:
- Auto-selecciona dirección default al cargar
- Silencia errores 400 (tabla no migrada/shipping no configurado) sin mostrar error al usuario
- Se integra con el checkout (pasa `selectedAddress` al payload de preferencia)

---

## W.9 — Shipping (Envío)

### Flujo:
1. `GET /shipping/settings` → métodos habilitados (delivery, pickup, arrange)
2. Usuario selecciona método
3. Si `delivery` → ingresa CP → `POST /shipping/quote` → recibe quote_id + cost
4. Quote se envía al checkout para revalidación

### Datos del quote request:
```json
POST /shipping/quote
{
  "delivery_method": "delivery",
  "zip_code": "1234",
  "province": "Buenos Aires",
  "subtotal": 15000,
  "items": [{ "product_id": "uuid", "quantity": 2 }]  // Solo si pricing_mode = provider_api
}
```

### ✅ Buenas prácticas:
- Auto-select si hay un solo método habilitado
- Free shipping threshold tracking
- Quote se revalida server-side al crear preferencia

---

## W.10 — ¿Acceso Directo a Supabase desde el Storefront?

### Resultado: **NO hay accesos directos a base de datos**

El cliente Supabase (`services/supabase.js`) se usa **exclusivamente para Auth**:
- `supabase.auth.getSession()` — obtener token JWT
- `supabase.auth.signInWithPassword()` — login
- `supabase.auth.signInWithOAuth()` — OAuth
- `supabase.auth.signUp()` — registro
- `supabase.auth.signOut()` — logout

**No hay llamadas a**: `supabase.from()`, `supabase.rpc()`, `supabase.storage.*`

**Todos los datos se obtienen via el backend NestJS** (a través de axiosConfig). Esto es la arquitectura correcta para multi-tenant — el frontend nunca toca la DB directamente.

---

## W.11 — Hallazgos de Seguridad

### 🔴 SEV-1: Clave de cifrado hardcodeada

**Archivo**: `src/utils/encrypt.jsx`
```js
const encryptedMessage = CryptoJS.AES.encrypt(msj, "secret").toString();
```
- Usa la cadena literal `"secret"` como clave AES
- Se usa en `templates/second/components/Register/index.jsx` para cifrar el password antes de enviar
- **Esto no provee seguridad real** — cualquiera puede descifrarlo desde el código fuente
- **Recomendación**: Eliminar este módulo. Los passwords deben enviarse en HTTPS plano al backend, que los hashea con bcrypt/argon2. Si se necesita cifrado en tránsito, HTTPS ya lo provee.

### 🟡 SEV-2: Dos clientes axios con comportamiento divergente

| Aspecto | axiosConfig (principal) | apiClient (client.ts) |
|---------|------------------------|----------------------|
| Custom domain support | ❌ No envía `X-Tenant-Host` | ✅ Envía `X-Tenant-Host` |
| Cross-tenant guard | ✅ Bloquea mismatch | ❌ No tiene |
| Loading events | ✅ Emite loading-start/stop | ❌ No emite |

**Recomendación**: Unificar en un solo cliente o hacer que `apiClient` extienda el config de `axiosConfig`.

### 🟡 SEV-2: Fallback de stock a 999

En `useCartItems.js` L280:
```js
const maxStock = item.product?.quantity ?? item.product?.stock ?? 999;
```
Si el producto no tiene stock informado, permite agregar hasta 999 unidades. **Recomendación**: fallback a 1 o 0, y validar server-side (el backend debería ser la fuente de verdad del stock).

### 🟢 SEV-3: `VITE_CLIENT_ID` como fallback legacy

Presente en `CartProvider` y `ProductPage` como fallback de `resolvedClientId`. No se envía como header (el backend resuelve por slug), pero podría causar confusión si se usa para scoping de storage. **Bajo riesgo**, pero debería limpiarse.

### 🟢 SEV-3: Código legacy comentado masivo

`ProductPage/index.jsx` tiene ~250 líneas de código legacy comentado (la versión anterior completa). `axiosConfig.jsx` tiene ~100 líneas comentadas de versiones anteriores. **Recomendación**: limpiar código muerto.

---

## W.12 — Resumen de Seguridad Multi-Tenant

| Control | Estado | Detalle |
|---------|--------|---------|
| Tenant isolation (headers) | ✅ | X-Tenant-Slug en cada request |
| No acceso directo a DB | ✅ | Solo Supabase Auth, datos via backend |
| Cross-tenant guard | ✅ | axiosConfig bloquea slug mismatch |
| No SERVICE_ROLE_KEY en frontend | ✅ | Solo ANON_KEY |
| PKCE Auth Flow | ✅ | `flowType: 'pkce'` configurado |
| Precios del backend (no del front) | ✅ | expectedPrice es solo para detección, backend decide |
| Idempotency en checkout | ✅ | Idempotency-Key header |
| Double-submit prevention | ✅ | generatingRef flag |
| Login required para carrito | ✅ | Redirige a /login si no hay sesión |
| Estado de tenant validado | ✅ | Gating por suspended/pending/inactive |
| Storage scoped por tenant | ✅ | getScopedKey() con slug:clientId |
| Custom domain async resolution | ✅ | GET /tenant/resolve-host |
| Cipher hardcodeado | 🔴 | encrypt.jsx con clave "secret" |
| Dos clientes axios divergentes | 🟡 | apiClient vs axiosConfig |

---

## W.13 — Feature Map del Storefront

| Feature | Implementación | Via Backend? |
|---------|---------------|-------------|
| Catálogo/Búsqueda | ProductSearch + SearchPage | ✅ GET /products/search |
| PDP | ProductPage + gallery + options | ✅ GET /products/:id |
| Carrito CRUD | CartProvider + useCartItems | ✅ /api/cart |
| Cotización de pagos | useCartQuotes | ✅ /api/cart (includeQuote) |
| Checkout | useCheckout | ✅ /mercadopago/create-preference-for-plan |
| Payment Result | PaymentResultPage | ✅ Polling /orders/:ref/status |
| Favoritos (guest) | LocalFavoritesStore | ❌ localStorage |
| Favoritos (logged) | RemoteFavoritesStore | ✅ /favorites |
| Direcciones | useAddresses | ✅ /addresses |
| Shipping | useShipping | ✅ /shipping/settings + /shipping/quote |
| Cupones | CouponInput | ✅ /store-coupons/validate |
| Reviews/Q&A | ProductReviews, ProductQA | ✅ API calls |
| Social Proof | ProductPage | ✅ /products/:id/social-proof |
| Auth | Supabase JS (PKCE) | ✅ Supabase Auth |
| Admin Dashboard | components/admin/* | ✅ Multiple API endpoints |
| SEO | ProductSEO + JsonLd | Client-side rendering |
| Templates (8) | templates/{first..eighth} | Static + data from backend |

---

## Fase G — Auditoría de Schema de Base de Datos (Migraciones SQL)

> Fecha: 2026-02-25
> Método: Inspección estática de todos los archivos `.sql` en `migrations/`, `migrations/admin/`, `migrations/backend/`

### G.1 — Inventario Completo de Archivos de Migración

**Total: ~180+ archivos SQL** distribuidos en 3 carpetas:

#### Root (`migrations/`) — 33 archivos
Migraciones iniciales y cross-cutting (RLS base, payments, option sets, reviews, etc.)

| Archivo | Propósito |
|---------|-----------|
| `00_reporting_setup.sql` | Setup de reporting |
| `20250815_add_image_variants.sql` | Variantes de imagen en banners |
| `20250816_make_orders_payment_id_nullable.sql` | orders.payment_id nullable |
| `20250905_client_payment_settings.sql` | Config pagos por tenant |
| `20250912_add_users_blocked_column.sql` | users.blocked |
| `20251002_add_payment_settings_and_fees.sql` | Settings avanzados de pago |
| `20251003_add_mp_idempotency_table.sql` | Idempotencia MP |
| `20251003_add_service_fields.sql` | Campos service label/mode |
| `20251003_seed_mp_fee_table.sql` | Seed comisiones MP |
| `20251004_archive_unused_tables.sql` | Archivado de tablas obsoletas |
| `20251004_enable_rls_policies.sql` | RLS habilitado en tablas core |
| `20251004_idx_orders_status.sql` | Índice en orders(status) |
| `20251004_rls_complete_with_comments.sql` | RLS + funciones `current_client_id()`, `is_admin()`, `is_super_admin()` |
| `20251005_*` | Columnas de fees, exclusiones, overrides |
| `20251006_*` | Fees reales, pay_with_debit |
| `20251007_*` | Email flags, payment tables, payment mode, timestamps, RLS multiclient |
| `20251008_*` | Unique constraints, decrement_stock RPC, email_jobs |
| `20251009_*` | Image variants, RLS multiclient revisión 2 |
| `20251014_multiclient_storage.sql` | Storage policies multiclient |
| `20251026_create_oauth_state_nonces.sql` | OAuth nonces |
| `20251102_add_home_template_settings.sql` | Home template config |
| `20251103_adjust_storage_public_policy.sql` | Storage policy ajuste |
| `20251105_*` | QR hash, claim email jobs, fix RPC |
| `20251107_*` | Usage metering y ledger |
| `20260103_seed_palettes.sql` | Seed paletas |
| `20260111_*` | nv_accounts alter, onboarding, payment_failures, price_history, subscriptions |
| `20260116_consolidate_plan_fields.sql` | Consolidación planes |
| `20260124_add_subscription_columns.sql` | Columnas en subscriptions |
| `20260131_claim_slug_rpc.sql` | RPC claim slug |
| `20260201_auth_bridge_codes.sql` | Auth bridge |
| `20260202_add_requirements_override.sql` | Override de requirements |
| `20260211_*` | Public codes, shipping |
| `20260216_option_sets_*.sql` (4 archivos) | Option sets + items + RLS + seed + product columns |
| `20260217_qa_reviews_tables.sql` | Reviews + Q&A completo |
| `20260217_fix_cart_items_unique_with_options_hash.sql` | Unique cart items con opciones |
| `20260218_review_aggregates_count_all.sql` | Fix aggregados reviews |

#### Admin (`migrations/admin/`) — ~80 archivos
Todas las tablas del Admin DB (nv_accounts, subscriptions, billing, support, etc.)

| Grupo | Archivos claves |
|-------|----------------|
| Foundation (001–009) | Extensions, types, security lockdown, nv_accounts, nv_onboarding, addon_catalog, plan_definitions, provisioning_jobs, mp_events, backend_clusters |
| Themes (011–016) | Palettes, coupons, themes, custom palettes, soft delete audit |
| Plans (020–024) | Plan management, sync, onboarding extension, slug reservations, webhooks |
| Auth (028–036) | Terms acceptance, auth handoff, super admin, identity verification |
| Templates & Business (040–044) | nv_templates, business fields, legal compliance, billing events |
| Billing Hub (050–055) | Hardening, RLS fix, managed domains, payments/invoices RLS |
| Provisioning (057–058) | Dedupe, job steps |
| Shipping & Slug (059–060) | Platform shipping providers, slug immutability trigger |
| Tickets (061) | Ticket limits |
| Subscriptions (063–076) | Coupons, country configs, fx rates, plans enforcement, i18n, auto-charge, quota, usage rollups, billing adjustments, invoices, fee schedules, cost rollups, trial |
| Country (080–088) | Country configs, subdivisions, fiscal categories, multicurrency, legacy cleanup |
| Security (089) | RLS en billing tables |
| Hardening (20250101–20250717) | RLS comprehensiva, hardening, pro concierge, publication state machine, MP OAuth |
| Subscriptions Infra (20260102–20260207) | Subscriptions lifecycle, events, locks, outbox, backfill, check constraints |
| Billing/Reporting (20260201) | Dashboard metrics, RPCs, super admin RLS |
| Support (20260216) | Support tickets completo (SLA, messages, events, CSAT) |
| Legal (20260217) | Consent log, legal docs, cancellation requests, SEO AI pricing |

#### Backend (`migrations/backend/`) — ~60 archivos

| Grupo | Archivos claves |
|-------|----------------|
| Security (001–006) | client_secrets, secure views, backfill secrets, RLS bypass, super_admins |
| Indexes (007) | order_items indexes (order_id, product_id) |
| Plans (008) | clients plan_key, billing_period |
| Webhooks (009) | shipping_webhook_failures (DLQ) |
| Templates (010) | template_id, theme_config, page_layout en clients |
| Entitlements (011) | entitlements JSONB en clients |
| Usage (012) | client_usage + product count triggers |
| Home (013) | home_settings, home_sections, publication flow |
| Unique (015) | Unique constraints |
| Usage ext (027) | Extend client_usage (orders_month_count, etc.) |
| Assets (028) | client_assets table |
| Banners (029) | Banner usage triggers |
| Tracking (030) | Order tracking + monthly reset |
| Tenant events (031) | tenant_payment_events |
| Storage (041) | Storage bucket policies |
| **Coupons (042–044)** | **store_coupons + targets + redemptions + RPC + RLS** |
| Feature flags (043) | client_feature_overrides |
| i18n (045) | clients i18n (country_code, timezone, locale, currency) |
| Multicurrency (046) | Orders multicurrency |
| Fiscal (048) | clients generic fiscal fields |
| Publication (20260102) | publication_status enum, enhance, identity_config, home_sections |
| Custom domain (20260126) | custom_domain en clients |
| Lifecycle (20260207) | clients lifecycle columns, unique indexes, check constraints |
| **Shipping (20260211)** | **shipping_tables, shipping_settings_zones, user_addresses, shipping_phase4_provider** |
| **SEO (20260212–13)** | **seo_settings, seo_redirects, categories_slug, seo_ai_model, seo_robots_txt** |
| Legacy cleanup (20260216) | Drop legacy sizes/colors |
| **Legal (20260217)** | **buyer_consent_and_withdrawal** |
| **Stock (20260217)** | **stock_reservation_system** |
| **Products (20260217)** | **products.client_id SET NOT NULL** |
| Templates (20260220) | template sixth, seventh, eighth |
| RLS (20250715) | **order_items RLS tenant** |

### G.2 — DDL Crítico Descubierto (Tablas NO en el schema dump original)

#### Backend DB — Tablas Nuevas

**1. `store_coupons`** — Cupones de tienda
```sql
CREATE TABLE store_coupons (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  code text NOT NULL, code_normalized text GENERATED ALWAYS AS (upper(trim(code))) STORED,
  description text, discount_type text NOT NULL CHECK (percentage|fixed_amount|free_shipping),
  discount_value numeric DEFAULT 0, max_discount numeric, currency text DEFAULT 'ARS',
  min_subtotal numeric DEFAULT 0, target_type text DEFAULT 'all' CHECK (all|products|categories),
  starts_at timestamptz, ends_at timestamptz, is_active boolean DEFAULT true,
  archived_at timestamptz, max_redemptions int, max_per_user int DEFAULT 1,
  redemptions_count int DEFAULT 0, stackable boolean DEFAULT false,
  created_at timestamptz, updated_at timestamptz, created_by uuid
);
-- UNIQUE(client_id, code_normalized), CHECK constraints para porcentaje/fixed/fechas
-- RLS: server_bypass + admin CRUD
-- Trigger: updated_at
-- RPC: redeem_store_coupon (atomic CAS, idempotente)
-- RPC: reverse_store_coupon_redemption
```

**2. `store_coupon_targets`** — Targets de cupón (productos/categorías)
```sql
CREATE TABLE store_coupon_targets (
  id uuid PK, coupon_id uuid FK→store_coupons ON DELETE CASCADE,
  client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  target_type text CHECK (product|category), target_id uuid, created_at timestamptz
);
-- UNIQUE(coupon_id, target_type, target_id)
-- RLS: server_bypass + admin
```

**3. `store_coupon_redemptions`** — Canjes de cupón
```sql
CREATE TABLE store_coupon_redemptions (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  coupon_id uuid NOT NULL FK→store_coupons ON DELETE RESTRICT,
  order_id uuid NOT NULL FK→orders ON DELETE RESTRICT,
  user_id uuid NOT NULL, coupon_code text, discount_type text, discount_value numeric,
  discount_amount numeric, breakdown jsonb, status text CHECK (applied|reversed),
  reversed_at timestamptz, reversed_by uuid, created_at timestamptz
);
-- UNIQUE(order_id)
-- RLS: server_bypass + admin + owner read
```

**4. `shipping_integrations`** — Integraciones de envío por tenant
```sql
CREATE TABLE shipping_integrations (
  id uuid PK, client_id uuid NOT NULL, provider text NOT NULL, display_name text NOT NULL,
  mode text DEFAULT 'manual' CHECK (manual|api_key|oauth),
  credentials_enc text, config jsonb, is_active boolean, is_default boolean,
  test_status text CHECK (untested|ok|failed|expired), test_last_at timestamptz,
  created_at, updated_at, created_by uuid
);
-- UNIQUE(client_id, provider), partial idx active, trigger updated_at
-- RLS: server_bypass + admin
```

**5. `shipments`** — Envíos por orden
```sql
CREATE TABLE shipments (
  id uuid PK, client_id uuid NOT NULL, order_id uuid NOT NULL,
  integration_id uuid FK→shipping_integrations ON DELETE SET NULL,
  provider text DEFAULT 'manual', tracking_code text, tracking_url text, label_url text,
  provider_ref text, status text CHECK (12 estados), cost numeric(12,2), currency text,
  estimated_delivery_at timestamptz, events jsonb, metadata jsonb,
  created_at, updated_at, created_by uuid
);
-- IDX: (client_id, order_id), (client_id, tracking_code), (provider, provider_ref)
-- RLS: server_bypass + tenant select (via orders.user_id) + admin write
```

**6. `client_shipping_settings`** — Config de envío por tenant
```sql
CREATE TABLE client_shipping_settings (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  delivery_enabled bool, pickup_enabled bool, arrange_enabled bool,
  shipping_pricing_mode shipping_pricing_mode ENUM, flat_shipping_cost numeric,
  free_shipping_enabled bool, free_shipping_threshold numeric,
  pickup_address text, pickup_instructions text, arrange_whatsapp text,
  labels (shipping/pickup/arrange), estimated_delivery_text text,
  origin_address jsonb, created_at, updated_at
);
-- UNIQUE(client_id), trigger updated_at
-- RLS: server_bypass + tenant select + admin write
```

**7. `shipping_zones`** — Zonas de envío por tenant
```sql
CREATE TABLE shipping_zones (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  name text, provinces text[], zip_codes text[], cost numeric(12,2), currency char(3),
  estimated_delivery text, position int, is_active bool, created_at, updated_at
);
-- IDX: (client_id), (client_id, is_active), GIN(provinces)
-- RLS: server_bypass + tenant select + admin write
```

**8. `user_addresses`** — Direcciones de usuario
```sql
CREATE TABLE user_addresses (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  user_id uuid NOT NULL, label text, full_name text NOT NULL, phone text,
  street text NOT NULL, street_number text NOT NULL, floor_apt text,
  city text NOT NULL, province text NOT NULL, zip_code text NOT NULL,
  country text DEFAULT 'AR', notes text, is_default bool, created_at, updated_at
);
-- IDX: (user_id, client_id), (client_id)
-- RLS: owner CRUD + admin select + server bypass
```

**9. `option_sets`** — Conjuntos de opciones reutilizables
```sql
CREATE TABLE option_sets (
  id uuid PK, client_id uuid FK→clients ON DELETE CASCADE (NULL = preset global),
  code text NOT NULL, name text NOT NULL, type text CHECK (apparel|footwear|accessory|generic),
  system text, is_preset bool, metadata jsonb, created_at, updated_at
);
-- UNIQUE(client_id, code), IDX: client, preset, type
-- RLS: server_bypass + tenant select (incluye presets globales) + admin write
```

**10. `option_set_items`** — Valores de option_set
```sql
CREATE TABLE option_set_items (
  id uuid PK, option_set_id uuid NOT NULL FK→option_sets ON DELETE CASCADE,
  value text NOT NULL, label text NOT NULL, position int, metadata jsonb, is_active bool
);
-- UNIQUE(option_set_id, value)
-- RLS: server_bypass + tenant select (via parent) + admin write (via parent)
```

**11. `size_guides`** — Guías de talles
```sql
CREATE TABLE size_guides (
  id uuid PK, client_id uuid FK→clients ON DELETE CASCADE,
  option_set_id uuid FK→option_sets ON DELETE SET NULL,
  product_id uuid FK→products ON DELETE CASCADE,
  name text, columns jsonb, rows jsonb, notes text, version int, created_at, updated_at
);
-- IDX: client, option_set, product
-- RLS: server_bypass + tenant select + admin write
```

**12. `product_questions`** — Q&A de productos
```sql
CREATE TABLE product_questions (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  product_id uuid NOT NULL FK→products ON DELETE CASCADE,
  user_id uuid NOT NULL, parent_id uuid FK→self ON DELETE CASCADE,
  body text CHECK 10-2000 chars, display_name text, status text CHECK (open|answered|resolved),
  moderation_status text CHECK (published|hidden|archived),
  moderated_by uuid, moderated_at, moderation_reason text,
  created_at, updated_at, last_activity_at
);
-- FK compuesta (user_id, client_id) → users(id, client_id)
-- IDX: 5 índices parciales para PDP, answers, admin, user, FK
-- RLS: server_bypass + tenant select (moderation filters) + user insert + admin update + owner archive
```

**13. `product_reviews`** — Reviews de productos
```sql
CREATE TABLE product_reviews (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  product_id uuid NOT NULL FK→products ON DELETE CASCADE,
  user_id uuid NOT NULL, rating smallint CHECK 1-5, title text, body text,
  display_name text, verified_purchase bool, moderation_status text,
  admin_reply text, admin_reply_by uuid, admin_reply_at timestamptz,
  moderated_by uuid, moderated_at, moderation_reason text, created_at, updated_at
);
-- UNIQUE(client_id, product_id, user_id), FK compuesta (user_id, client_id)
-- RLS: server_bypass + tenant select + user insert + admin update + owner update
```

**14. `product_review_aggregates`** — Agregados pre-calculados
```sql
CREATE TABLE product_review_aggregates (
  client_id uuid NOT NULL, product_id uuid NOT NULL,  -- PK compuesta
  avg_rating numeric(3,2), review_count int, rating_1-5 int, question_count int, updated_at
);
-- Trigger: actualizado automáticamente al INSERT/UPDATE/DELETE en reviews y questions
-- RLS: tenant select + server_bypass
```

**15. `seo_settings`** — Configuración SEO por tenant
```sql
CREATE TABLE seo_settings (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE UNIQUE,
  site_title text, site_description text, brand_name text, og_image_default text,
  favicon_url text, ga4_measurement_id text, gtm_container_id text,
  search_console_token text, product_url_pattern text, robots_txt text,
  custom_meta jsonb, created_at, updated_at
);
-- RLS: server_bypass + tenant select + admin write
```

**16. `seo_redirects`** — Redirects 301/302 por tenant
```sql
CREATE TABLE seo_redirects (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  from_path text NOT NULL, to_url text NOT NULL, redirect_type int CHECK (301|302),
  active bool, hit_count int, created_at, updated_at
);
-- UNIQUE(client_id, from_path), IDX: lookup activo
-- RLS: server_bypass + tenant select + admin write
```

**17. `seo_ai_jobs`** + **`seo_ai_log`** — AI SEO job queue y audit trail
```sql
-- seo_ai_jobs: job queue for AI SEO generation
-- seo_ai_log: immutable audit trail of AI field changes
-- Ambas: client_id NOT NULL, RLS solo service_role
```

**18. `buyer_consent_log`** — Consentimiento de compradores
```sql
CREATE TABLE buyer_consent_log (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  user_id uuid, order_id uuid FK→orders, document_type text, document_version text,
  ip_address inet, user_agent text, accepted_at timestamptz
);
-- RLS: server_bypass + admin select + owner select + tenant insert
```

**19. `withdrawal_requests`** — Solicitudes de arrepentimiento (Art. 34 Ley 24.240)
```sql
CREATE TABLE withdrawal_requests (
  id uuid PK, client_id uuid NOT NULL FK→clients ON DELETE CASCADE,
  user_id uuid, order_id uuid FK→orders, tracking_code text NOT NULL,
  reason text, status text, requested_at, resolved_at, resolved_by uuid,
  ip_address inet, contact_email text, contact_phone text, metadata jsonb
);
-- RLS: server_bypass + admin select/update + owner select + tenant insert
```

**20. `shipping_webhook_failures`** — DLQ para webhooks de shipping
```sql
CREATE TABLE shipping_webhook_failures (
  id uuid PK, provider text NOT NULL, payload jsonb, headers jsonb,
  error_msg text, status text, attempts int, max_retries int,
  next_retry timestamptz, created_at, resolved_at
);
-- RLS: server_bypass only (no client_id — es una tabla cross-tenant)
```

#### Admin DB — Tablas Nuevas Destacadas

**21. `support_tickets`** + `support_messages` + `support_ticket_events` + `support_csat` + `support_sla_policies`
- Completo sistema de soporte: SLA, mensajes, eventos, CSAT
- Scoped por `account_id → nv_accounts` (no `client_id`)
- RLS: server_bypass + policies por account

**22. `nv_legal_documents`** + `nv_merchant_consent_log`** + `nv_cancellation_requests`
- Legal compliance (Ley 24.240, Disp. 954/2025)
- consent_log scoped por `account_id`
- cancellation_requests scoped por `account_id`

**23. `subscriptions`** + `subscription_events` + lifecycle tables
- subscription_status ENUM (active, past_due, grace, expired, canceled)
- provider_id (MP preapproval), account_id FK
- Events idempotentes por event_id

### G.3 — Columnas añadidas a tablas existentes (ALTER TABLE)

| Tabla | Columnas añadidas | Migración |
|-------|-------------------|-----------|
| `products` | `slug`, `meta_title`, `meta_description`, `noindex`, `seo_source`, `seo_locked`, `seo_needs_refresh`, `seo_last_generated_at`, `option_mode`, `option_set_id`, `option_config`, `weight_grams` | SEO, SEO AI, Option Sets, Shipping |
| `categories` | `slug`, `meta_title`, `meta_description`, `noindex`, `seo_source`, `seo_locked`, `seo_needs_refresh`, `seo_last_generated_at` | SEO, SEO AI, Categories Slug |
| `cart_items` | `selected_options` (jsonb), `options_hash` (text) | Option Sets |
| `orders` | `installments`, `settlement_days`, `coupon_id`, `coupon_code`, `coupon_discount`, `coupon_breakdown`, `delivery_method`, `shipping_cost`, `shipping_address` (jsonb), `delivery_address`, `pickup_info` (jsonb), `estimated_delivery_min`, `estimated_delivery_max`, `shipping_label`, `stock_reserved` (bool) | Payments, Coupons, Shipping, Stock Reservation |
| `clients` | `template_id`, `theme_config` (jsonb), `page_layout` (jsonb), `entitlements` (jsonb), `custom_domain`, `publication_status`, etc. | Multiple |

### G.4 — Triggers y Funciones Definidos

| Función/Trigger | Tabla afectada | Propósito |
|----------------|----------------|-----------|
| `current_client_id()` | — | Retorna `client_id` del user autenticado via `users.id = auth.uid()` |
| `is_admin()` | — | Verifica `role IN ('admin','super_admin')` en users |
| `is_super_admin()` | — | Verifica `role = 'super_admin'` en users |
| `trigger_set_timestamp()` | Varias | Actualiza `updated_at = now()` en UPDATE |
| `update_updated_at_column()` | shipping_integrations, shipments | Idem |
| `increment_product_count()` / `decrement_product_count()` | products INSERT/DELETE | Actualiza `client_usage.products_count` |
| `increment_order_count()` | orders INSERT | Actualiza `client_usage.orders_month_count` |
| `reset_monthly_usage()` | client_usage | Resetea contadores mensuales |
| `update_review_aggregates()` | product_reviews AFTER I/U/D | Recalcula `product_review_aggregates` |
| `update_question_count()` | product_questions AFTER I/U/D | Actualiza `question_count` en aggregates |
| `has_purchased_product(UUID,UUID,UUID)` | — | Verifica compra aprobada (para verified_purchase) |
| `redeem_store_coupon(...)` | store_coupons + redemptions | Atomic CAS: redime cupón idempotente |
| `reverse_store_coupon_redemption(...)` | store_coupons + redemptions | Reversa de redención |
| `decrement_product_stock_rpc()` | products | Decrementa stock atómicamente |
| `restore_stock_bulk(UUID, JSONB)` | products | Restaura stock (inversa de decrement) |

### G.5 — Análisis de Multi-Tenant: client_id en Todas las Tablas

#### ✅ Tablas con `client_id NOT NULL` + FK + Index

| Tabla | NOT NULL | FK→clients | Index | RLS |
|-------|:--------:|:----------:|:-----:|:---:|
| products | ✅ (SET NOT NULL en migración) | ✅ | ✅ | ✅ |
| categories | ⚠️ nullable | ✅ | ✅ (via slug) | ✅ |
| product_categories | ✅ | ✅ | ✅ | ✅ |
| cart_items | ✅ | — (columna existe) | — | ✅ |
| orders | ✅ | ✅ | ✅ | ✅ |
| users | ✅ | ✅ | ✅ | ✅ |
| banners | ⚠️ nullable | — | — | ✅ |
| faqs | ⚠️ nullable | — | — | ✅ |
| contact_info | — | — | — | ✅ |
| social_links | — | — | — | ✅ |
| services | — | — | — | ✅ |
| logos | — | — | — | ✅ |
| favorites | ✅ | — | — | ✅ |
| payments | — | ✅ | — | ✅ |
| email_jobs | ✅ | — | — | ✅ |
| store_coupons | ✅ | ✅ CASCADE | ✅ | ✅ |
| store_coupon_targets | ✅ | ✅ CASCADE | ✅ | ✅ |
| store_coupon_redemptions | ✅ | ✅ CASCADE | ✅ | ✅ |
| shipping_integrations | ✅ | — (no FK) | ✅ | ✅ |
| shipments | ✅ | — (no FK) | ✅ | ✅ |
| client_shipping_settings | ✅ | ✅ CASCADE | ✅ | ✅ |
| shipping_zones | ✅ | ✅ CASCADE | ✅ | ✅ |
| user_addresses | ✅ | ✅ CASCADE | ✅ | ✅ |
| option_sets | ⚠️ nullable (NULL=preset) | ✅ CASCADE | ✅ | ✅ |
| size_guides | ⚠️ nullable | ✅ CASCADE | ✅ | ✅ |
| product_questions | ✅ | ✅ CASCADE | ✅ | ✅ |
| product_reviews | ✅ | ✅ CASCADE | ✅ | ✅ |
| product_review_aggregates | ✅ (PK comp.) | — (no FK) | PK | ✅ |
| seo_settings | ✅ | ✅ CASCADE | ✅ | ✅ |
| seo_redirects | ✅ | ✅ CASCADE | ✅ | ✅ |
| seo_ai_jobs | ✅ | — (no FK) | ✅ | ✅ (service only) |
| seo_ai_log | ✅ | — (no FK) | ✅ | ✅ (service only) |
| buyer_consent_log | ✅ | ✅ CASCADE | ✅ | ✅ |
| withdrawal_requests | ✅ | ✅ CASCADE | ✅ | ✅ |

#### ⛔ Tablas SIN client_id (hallazgos críticos)

| Tabla | Tiene client_id | Impacto | Severidad |
|-------|:--------------:|---------|:---------:|
| **order_items** | ❌ NO | Depende de JOIN a orders.client_id para RLS. No tiene índice directo por client_id para queries aisladas. | **MEDIO** |
| **option_set_items** | ❌ NO | Depend de JOIN a option_sets para tenant isolation. RLS correctamente implementada via parent. | **BAJO** |
| **shipping_webhook_failures** | ❌ NO (es cross-tenant DLQ) | Solo service_role. Correcto por diseño. | **INFO** |
| **product_review_aggregates** | ✅ (en PK compuesta) | No tiene FK a clients. Solo escrita por trigger/service_role. | **BAJO** |

### G.6 — Hallazgos Críticos y Recomendaciones

#### 🔴 SEV-1: Tablas core sin original CREATE TABLE versionado

**Problema:** Las tablas fundamentales (`products`, `orders`, `order_items`, `users`, `clients`, `categories`, `cart_items`, `favorites`, `banners`, `faqs`, `contact_info`, `social_links`, `logos`, `services`, `payments`, `cors_origins`) **no tienen un CREATE TABLE en los archivos de migración**. Fueron creadas directamente en Supabase Dashboard sin migración rastreable.

**Impacto:** No hay forma de reconstruir la DB desde cero usando solo las migraciones. Si se pierde el proyecto Supabase, estas tablas no se pueden recrear.

**Recomendación:** Crear una migración `000_baseline_schema.sql` con el DDL actual de todas las tablas core (obtenido vía `pg_dump --schema-only`).

---

#### 🟡 SEV-2: `order_items` sin `client_id` directo

**Problema:** La tabla `order_items` no tiene columna `client_id`. La RLS usa un JOIN a `orders` para resolver el tenant. Esto es funcionalmente correcto pero:
- Queries directos a `order_items` sin JOIN son imposibles de scop-ear
- Performance de RLS degradada por el subquery en cada policy

**Recomendación:** Agregar `client_id` desnormalizado en `order_items` con FK y NOT NULL, y migrar datos existentes. Luego simplificar las policies RLS.

---

#### 🟡 SEV-2: `categories.client_id` y `banners.client_id` son nullable

**Problema:** Según el schema dump original, `categories.client_id` y `banners.client_id` permiten NULL. Un `client_id = NULL` en estas tablas **no matchea ninguna policy RLS** (porque `NULL = current_client_id()` es siempre false), lo que significa que esos registros serían **datos fantasma** invisibles via RLS pero presentes en la tabla.

**Nota:** Ya se corrigió esto para `products` en la migración `20260217_products_client_id_not_null.sql`, pero no se hizo lo mismo para categories ni banners.

**Recomendación:** Aplicar `ALTER TABLE categories ALTER COLUMN client_id SET NOT NULL` y lo mismo para `banners`, `faqs`, `contact_info`, `social_links`, `logos`, `services`, `payments`. Previamente auditar y eliminar registros con `client_id IS NULL`.

---

#### 🟡 SEV-2: `shipping_integrations` y `shipments` sin FK a clients

**Problema:** Ambas tablas tienen `client_id NOT NULL` pero **no tienen `REFERENCES clients(id)`**. Esto significa que no hay integridad referencial; se podrían insertar registros con un `client_id` que no exista en `clients`.

**Recomendación:** `ALTER TABLE shipping_integrations ADD CONSTRAINT fk_si_client FOREIGN KEY (client_id) REFERENCES clients(id) ON DELETE CASCADE;` y lo mismo para `shipments`.

---

#### 🟡 SEV-2: `seo_ai_jobs` y `seo_ai_log` sin FK a clients

**Problema:** Tienen `client_id NOT NULL` pero sin FK constraint. Mismo riesgo de datos huérfanos.

**Recomendación:** Agregar FK a clients.

---

#### 🟡 SEV-2: `product_review_aggregates` sin FK a clients ni products

**Problema:** PK compuesta `(client_id, product_id)` pero sin FKs. Podría tener aggregados de productos/clientes que ya no existen.

**Recomendación:** Agregar `REFERENCES clients(id)` y `REFERENCES products(id)` con ON DELETE CASCADE.

---

#### 🟢 SEV-3: Índices faltantes en tablas core

| Tabla | Índice faltante | Recomendación |
|-------|----------------|---------------|
| `banners` | `idx_banners_client_id` | Crear |
| `faqs` | `idx_faqs_client_id` | Crear |
| `contact_info` | `idx_contact_info_client_id` | Crear |
| `social_links` | `idx_social_links_client_id` | Crear |
| `logos` | `idx_logos_client_id` | Crear |
| `services` | `idx_services_client_id` | Crear |
| `favorites` | `idx_favorites_client_id` | Crear |
| `payments` | `idx_payments_client_id` | Crear |
| `cart_items` | `idx_cart_items_client_id` | Verificar si existe |
| `home_sections` | `idx_home_sections_client_id` | Crear |
| `home_settings` | `idx_home_settings_client_id` | Crear |

**Nota:** Como el schema original fue creado en Supabase Dashboard sin migración, estos índices podrían existir. Se necesita verificar contra la DB real con `\di`.

---

#### 🟢 SEV-3: Funciones SECURITY DEFINER sin SET search_path

Las funciones `current_client_id()`, `is_admin()`, `is_super_admin()` en la migración `20251004_rls_complete_with_comments.sql` **no tienen `SET search_path`**, pero la versión revisada en `20251007_rls_multiclient_security.sql` **sí lo tiene** (`SET search_path=public`).

**Si la versión más nueva se ejecutó correctamente**, esto no es un problema. Las funciones `has_purchased_product()`, `redeem_store_coupon()` y `restore_stock_bulk()` sí tienen `SET search_path` correctamente.

---

#### 🟢 SEV-3: Inconsistencia en PK de `client_mp_fee_overrides`

El schema dump original muestra `id uuid PK DEFAULT gen_random_uuid()`, pero la migración `20251007_add_payment_tables_and_order_cols.sql` la crea con `id bigserial PRIMARY KEY`. Esto indica que la tabla fue recreada o alterada.

---

### G.7 — Resumen de Triggers

| Trigger | Tabla | Evento | Función |
|---------|-------|--------|---------|
| `set_updated_at_shipping_integrations` | shipping_integrations | BEFORE UPDATE | `update_updated_at_column()` |
| `set_updated_at_shipments` | shipments | BEFORE UPDATE | `update_updated_at_column()` |
| `trg_css_updated_at` | client_shipping_settings | BEFORE UPDATE | `trg_update_css_updated_at()` |
| `trg_sz_updated_at` | shipping_zones | BEFORE UPDATE | `trg_update_sz_updated_at()` |
| `update_user_addresses_updated_at` | user_addresses | BEFORE UPDATE | `update_updated_at()` |
| `set_option_sets_updated_at` | option_sets | BEFORE UPDATE | `trigger_set_timestamp()` |
| `set_size_guides_updated_at` | size_guides | BEFORE UPDATE | `trigger_set_timestamp()` |
| `trg_review_aggregates` | product_reviews | AFTER I/U/D | `update_review_aggregates()` |
| `trg_question_count` | product_questions | AFTER I/U/D | `update_question_count()` |
| `trg_store_coupons_updated_at` | store_coupons | BEFORE UPDATE | `store_coupons_updated_at()` |
| `tr_product_insert_count` | products | AFTER INSERT | `increment_product_count()` |
| `tr_product_delete_count` | products | AFTER DELETE | `decrement_product_count()` |
| `trg_orders_usage` | orders | AFTER INSERT | `increment_order_count()` |
| `trg_subscriptions_updated` | subscriptions | BEFORE UPDATE | `update_subscriptions_updated_at()` |

### G.8 — RPCs (Remote Procedure Calls)

| Función | DB | Propósito |
|---------|:--:|-----------|
| `has_purchased_product(client_id, user_id, product_id)` | Backend | Verified purchase check |
| `redeem_store_coupon(...)` | Backend | Atomic coupon redemption |
| `reverse_store_coupon_redemption(...)` | Backend | Reverse redemption |
| `decrement_product_stock_rpc(...)` | Backend | Atomic stock decrement |
| `restore_stock_bulk(client_id, items_jsonb)` | Backend | Bulk stock restore |
| `reset_monthly_usage()` | Backend | Cron: reset monthly counters |
| `claim_slug(...)` | Admin | Slug reservation |

### G.9 — Consistencia vs. Instrucciones (NovaVisionBackend.instructions.md)

| Aspecto del Instructions | Estado Real | Consistente |
|--------------------------|-------------|:-----------:|
| "`client_id` en todas las tablas de negocio" | order_items no tiene client_id | ⚠️ |
| "todas las tablas con RLS habilitado" | Todas las nuevas ✅; tablas originales no verificable sin acceso a DB | ⚠️ |
| "Cada query debe filtrar por `.eq('client_id', clientId)`" | Verified en code (audit previa) | ✅ |
| "índices por `client_id` y FKs críticos creados" | Tablas nuevas ✅; originales sin verificar | ⚠️ |
| "RLS bypass service_role + políticas por tenant bien definidas" | ✅ en todas las nuevas | ✅ |
| "products.client_id FK, NOT NULL, index" | ✅ (migración explícita SET NOT NULL) | ✅ |
| "orders(user_id, client_id) index" | `idx_orders_client_user_paid` existe (parcial) | ⚠️ |

### G.10 — Plan de Acción Priorizado

| # | Severidad | Acción | Esfuerzo |
|:-:|:---------:|--------|:--------:|
| 1 | 🔴 SEV-1 | Crear `000_baseline_schema.sql` con pg_dump de tablas core | 2h |
| 2 | 🟡 SEV-2 | `ALTER TABLE order_items ADD COLUMN client_id UUID NOT NULL` + backfill + FK + index | 1h |
| 3 | 🟡 SEV-2 | SET NOT NULL en client_id de: categories, banners, faqs, contact_info, social_links, logos, services, payments | 1h |
| 4 | 🟡 SEV-2 | Agregar FK→clients a: shipping_integrations, shipments, seo_ai_jobs, seo_ai_log, product_review_aggregates | 30m |
| 5 | 🟢 SEV-3 | Crear índices `idx_{table}_client_id` en tablas core sin verificar | 30m |
| 6 | 🟢 SEV-3 | Verificar `SET search_path` en funciones `current_client_id()`, `is_admin()` contra la DB real | 15m |

# NovaVision — Spec para Agente IA (Onboarding + Templates + Deploy) v1.0
**Fecha:** 2025-12-29  
**Objetivo:** que un agente pueda implementar/validar onboarding automatizado + configuración de tiendas + navegación + deploy, manteniendo seguridad, multi-tenancy y escalabilidad (shared → dedicated).

---

## 0) Qué versión aplica (fuente de verdad)

Usar como base estos documentos:
- `plan-tecnico-onboarding-v1.3.6-SHIP.md` (técnico / seguridad / APIs)
- `plan-ejecucion-ux-v1.3.1-FINAL.md` (flujo UX y pantallas)
- `template-system-dynamic-v1.0.md` (sistema de templates dinámicos)

**Ajuste clave:** En tu schema real de *MULTICLIENTE* existe `public.clients` (no `tenants`). Por lo tanto, en data-plane la “tienda/tenant” se llama **client** y su key es `clients.id`.

---

## 1) Mapa de sistemas (qué interactúa con qué)

### Control Plane (ADMIN DB)
Guarda: clientes (negocio), billing, onboarding state, jobs y links a recursos (Netlify/GitHub/Supabase dedicated).
- Tablas ya existentes: `clients`, `invoices`, `plans`, `usage_logs`, etc.
- A agregar (si no existen): `client_onboarding` (estado + progress JSON), `provisioning_jobs`, `mp_events`, `audit_events` (o equivalentes).

**NO debe guardar:** catálogo de productos, categorías, órdenes, carrito.

### Data Plane (MULTICLIENTE DB)
Guarda: **datos operativos de la tienda** (productos, categorías, órdenes, contenido).
- Tablas existentes: `products`, `categories`, `orders`, `cart_items`, `banners`, `site_content`, etc.
- “Tenant” = `public.clients` (slug, is_active, config pública mínima).

**NO debe exponer secretos** por RLS a usuarios finales.

### Apps/Servicios
- **Portal (frontend)**: wizard onboarding del dueño.
- **Admin (frontend)**: panel interno NovaVision.
- **API (NestJS)**:
  - `Store API`: sólo lectura pública (config, products) + preview gating.
  - `Portal API`: endpoints autenticados del dueño (progress, upload logo, MP keys).
  - `Admin API`: aprobación go-live, soporte, auditoría.
- **Worker/Queue**: provisioning (crear registros, optional: recursos dedicated), reintentos, idempotencia.
- **Storage (Supabase Storage)**: logos/imágenes con signed URLs.
- **Netlify**: hosting storefront **único** (modo dinámico) + domains.
- **GitHub**: repo único del storefront (modo dinámico). Branch/site por cliente sólo en Enterprise.

---

## 2) Flujo real end-to-end (sin ramas por cliente en el caso estándar)

### 2.1 Alta (sign-up / pago / create client)
1) Usuario completa formulario + paga (o free trial).
2) Admin API crea/actualiza registro en **ADMIN DB** (`clients` + `client_onboarding.state='created'`).
3) Worker crea el registro espejo en **MULTICLIENTE DB**:
   - `public.clients.id` = **mismo UUID que admin.clients.id** (esto evita mapeos frágiles).
   - set `slug`, `is_active=false`, `plan`, y defaults.
4) Worker genera **preview token** (server-side) y lo guarda (Admin DB) o lo calcula on-demand.

### 2.2 Wizard (config + contenido)
En cada paso del wizard, Portal llama a Portal API:
- Guarda `progress` (ADMIN DB) para tracking.
- Guarda config operativa (MULTICLIENTE DB) en `clients.theme_config` / `site_content` / `banners` / `products`.

Ejemplos:
- Paso “Tema”: `clients.theme_config` (JSONB) + `template_id`.
- Paso “Home”: `site_content` (bloques) o `pages` (si ya existe).
- Paso “Productos”: carga masiva en `products` + `product_images`.
- Paso “Medios de pago”: `client_secrets` (ver sección 4).

### 2.3 Preview (antes de aprobar)
Storefront (Netlify) se abre con:
- `https://{slug}.tudominio.com/?preview=TOKEN`

Storefront:
- deriva `slug` desde hostname.
- llama `GET /store/config/:slug?preview=...`
- renderiza layout dinámico.

Store API valida:
- si `clients.is_active=true` → live
- si no → exige preview token válido

### 2.4 Aprobación (go-live)
Admin en panel → “Aprobar”.
Admin API:
- `UPDATE multicliente.clients SET is_active=true WHERE id = $client_id`
- `UPDATE admin.client_onboarding SET state='live' ...`
- (opcional) configurar domain en Netlify.

**No hay deploy por cliente** en el modo estándar: todas las tiendas ya están “deployadas” porque comparten el mismo storefront.

---

## 3) Navegación / client_id / “qué home es”

### Resolución de tienda
- Fuente de verdad: `slug` del hostname.
- `client_id` se resuelve **server-side**: `SELECT id FROM multicliente.clients WHERE slug=$1`.

### Qué home renderiza
- `template_id` define preset de layout.
- `theme_config` define tokens (colores, tipografías, etc).
- `site_content` / `pages` definen bloques y orden.

**Regla:** el storefront NUNCA decide `client_id` por query param ni por localStorage (sólo por hostname + Store API).

---

## 4) Seguridad de credenciales (Mercado Pago + dedicated secrets)

### Problema actual del schema
En MULTICLIENTE `clients` hoy tiene campos sensibles (ej: `mp_access_token`, `dedicated_db_service_key`).
Eso es **riesgo** si existe cualquier policy que permita SELECT del row.

### Solución requerida
Crear `public.client_secrets` en MULTICLIENTE y mover ahí:
- MP access token (cifrado)
- Dedicated DB url + service key (si aplica)
- cualquier secreto de infraestructura

Y dejar en `clients` sólo:
- `mp_public_key` (no secreto)
- config pública (template/theme) sin tokens

Implementar cifrado con `pgcrypto` + functions SECURITY DEFINER accesibles sólo por service role.

---

## 5) Templates dinámicos: ensamblar componentes “tipo page builder”

### Qué SÍ (sin redeploy)
- Catálogo de **bloques** (Hero, Features, Categories, ProductGrid, Testimonials, FAQ, Contact, Footer).
- Cada bloque tiene `props` + `dataBinding` (de dónde sale la info).
- La “página” es un JSON ordenado:
  ```json
  [
    { "block": "Hero", "variant": "split", "props": {...} },
    { "block": "ProductGrid", "props": { "source": "featured" } }
  ]
  ```
- El dueño reordena / activa / desactiva bloques en el wizard.
- El storefront interpreta ese JSON y renderiza.

### Cómo se guarda
- `clients.template_id` (preset)
- `clients.theme_config` (tokens)
- `site_content` o una tabla `client_pages` (recomendado si vas full page-builder):
  - `client_pages(client_id, page_key, blocks_jsonb, updated_at)`

### Qué NO (sin redeploy)
- Agregar un **bloque nuevo** que no existe en el catálogo: eso requiere release del storefront.
  - Se soluciona creando un catálogo suficientemente grande y variantes.

---

## 6) “Diseño personalizado” (Pro / Premium)

Hay 3 niveles (recomendado):

### Nivel 1 — Starter/Growth (100% dinámico)
- Sólo presets + bloques existentes + theme tokens.
- No hay código a medida.

### Nivel 2 — Pro (semi-personalizado, sin infraestructura dedicada)
- Se habilitan:
  - bloques premium (catálogo extendido)
  - variantes extra (animaciones, layouts)
  - CSS variables / overrides controlados (sin tocar código por cliente)
- Se implementa como: `feature_flags` por client en `clients.theme_config` o tabla `client_features`.

### Nivel 3 — Premium/Enterprise (código a medida + opcional dedicated)
Dos opciones:
1) **Custom blocks dentro del repo único** (feature-flagged): agregás bloques genéricos que no rompan a otros.
2) **Site/Repo dedicado**:
   - crear branch/repo por cliente
   - Netlify site propio
   - (opcional) DB dedicada

---

## 7) Escalamiento: shared → dedicated (upgrade en caliente)

**Sí, es posible con tu schema**, porque ya existen campos tipo `dedicated_db_url` y `needs_db_setup` en MULTICLIENTE `clients`.

### Estrategia recomendada
- Mantener un “stub” del cliente en MULTICLIENTE shared (para resolver slug → modo).
- Si `clients.dedicated_db_url` existe → Store API redirige queries a esa DB (pool dedicado).

### Proceso de migración (job)
1) Provisioning job crea Supabase project dedicado (DB+Storage+Auth) + Railway API (si aplica).
2) Ejecuta migraciones de schema en DB dedicada (misma versión).
3) Exporta data del cliente desde shared:
   - tablas filtradas por `client_id`
4) Importa a dedicated (bulk insert / COPY / scripts).
5) Verifica consistencia:
   - conteo de filas
   - sumas/ordenes
   - integrity (FKs)
6) “Cutover”:
   - set `clients.dedicated_db_url` + `clients.needs_db_setup=false`
   - store API empieza a usar dedicated
7) Post-cutover:
   - shared queda read-only para ese client (opcional) o se purga.

---

## 8) Deploy: estándar vs enterprise

### Estándar (lo recomendado)
- **1 solo sitio Netlify** (storefront).
- Wildcard DNS: `*.tudominio.com` → mismo sitio.
- El storefront resuelve slug por hostname y carga config.

### Enterprise (cuando sí hay branch + site)
- GitHub: crear branch `client/{slug}` (o repo fork) desde main.
- Netlify: crear site desde repo y fijar branch (o Deploy Preview).
- Variables env por sitio.
- Domain por sitio.

---

## 9) Validaciones obligatorias (acceptance criteria)

### Seguridad
- Ningún secreto en frontend bundle (grep de `service_role`, `PREVIEW_SECRET`).
- MP access token NO está en `clients` (sólo cifrado en `client_secrets`).
- Signed upload URLs usan token y expiran según spec.
- Preview token validación server-side + timing-safe compare.

### Multi-tenancy
- Todas las tablas operativas filtran por `client_id` y/o están aisladas.
- Store API nunca acepta `client_id` directo del usuario final.

### UX / Onboarding
- Wizard guarda progress y puede resumir “faltantes”.
- Preview funciona antes de aprobar.
- Aprobar cambia a live sin redeploy.

---

## 10) Entregables que debe producir el agente

1) **SQL migrations**:
   - MULTICLIENTE: `client_secrets`, cifrado, mover tokens, agregar template/theme si falta.
   - ADMIN: tablas/columns de onboarding si faltan.
2) **Cambios en API**:
   - endpoints de config/products con gating preview
   - endpoints de portal para theme/pages/products/mp
3) **Docs actualizados**:
   - actualizar `template-system-dynamic-v1.0.md` a naming real (`clients`)
   - actualizar plan técnico para eliminar “...” y dejar scripts completos
4) **Diagrama Mermaid** actualizado (para Miro) del flujo estándar + upgrade.

---

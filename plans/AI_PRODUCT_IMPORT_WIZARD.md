# AI Product Import Wizard — Plan de Implementación

> **Fecha:** 2026-02-27  
> **Autor:** agente-copilot  
> **Estado:** EN IMPLEMENTACIÓN (Fase 1)  
> **Alcance:** API (templatetwobe) + Web (templatetwo) + Admin DB (migración)  
> **Rama destino:** `feature/automatic-multiclient-onboarding` (API) / `develop` (Web)

---

## 0. Resumen Ejecutivo

Feature tipo "wizard onboarding" que permite al admin de tienda importar productos masivamente usando IA generativa como asistente. El flujo es:

```
Prompt Builder → IA externa genera JSON → Validación estricta →
Pre-carga editable → Staging de imágenes → Confirmación → Cola batch → Reporte
```

**Diferencia clave con el Excel upload actual:** el wizard guía paso a paso, permite edición/revisión individual antes de enviar, soporta carga de imágenes por producto, y procesa en background con reporte detallado.

---

## 1. Análisis del Sistema Actual

### 1.1 Flujo Excel existente (qué se reutiliza)

| Componente | Estado actual | Reutilizable |
|---|---|---|
| `COLUMN_MAPPING` + `resolveColumnKey()` | Fuzzy matching maduro (~40 labels) | ✅ Reutilizar para mapeo de campos JSON → DB |
| `validateProductRow()` | Valida name, price ≥ 0, qty ≥ 0, currency, dates, % | ✅ Extraer como servicio compartido |
| `findOrCreateCategory()` | Auto-crea categorías faltantes | ✅ Reutilizar tal cual |
| Upsert batches de 50 | `.upsert()` Supabase sincrónico | ⚠️ Migrar a cola asíncrona |
| `handleUploadExcel()` (FE) | FileDropZone + preview | ❌ Reemplazar con wizard |
| `parseExcelForPreview()` (FE) | Lee Excel client-side | ❌ No aplica (input es JSON) |
| `ProductModal` | Formulario completo con imágenes | ✅ Reutilizar como editor de pre-carga |

### 1.2 Modelo de producto real (campos DB)

```
Obligatorios: name, sku, originalPrice, quantity, client_id
Opcionales:   description, discountedPrice, currency (def ARS), available (def true),
              material, filters, promotionTitle, promotionDescription,
              discountPercentage, validFrom, validTo, featured, bestSell,
              sendMethod, tags[], weight_grams, option_mode, option_set_id,
              size_guide_id, slug, meta_title, meta_description
Calculados:   id (uuid), imageUrl (post-upload), image_variants (pipeline)
Relaciones:   categories (via product_categories M:N)
```

### 1.3 Restricciones de infraestructura

| Aspecto | Estado | Implicación |
|---|---|---|
| **Background jobs** | No hay Bull/Redis | Usar patrón DB-polling (como `email_jobs`) |
| **Storage** | `StorageService` + `ImageService` maduros | Reutilizar para staging de imágenes |
| **Plan gating** | `PlanLimitsGuard` + `@PlanAction` activos | Extender con `@PlanAction('ai_import')` |
| **Multi-tenant** | Estricto, `client_id` obligatorio | Toda tabla nueva lleva `client_id` |
| **Upload imágenes** | Endpoint separado `POST /products/:id/image` | Requiere producto creado antes de subir imagen |

### 1.4 Onboarding IA existente

Según `ONBOARDING_FIXPACK.md` (OB-02, OB-13), ya existe un flujo de "catálogo IA" en el onboarding. Este wizard es la **evolución independiente** para el dashboard admin (post-onboarding), con más control, edición y soporte de imágenes.

---

## 2. Arquitectura Propuesta

### 2.1 Diagrama de flujo completo

```
┌─────────────────────────────────────────────────────────────────────────┐
│                        FRONTEND (Web Storefront)                        │
│                                                                         │
│  ┌──────────┐   ┌──────────┐   ┌──────────────┐   ┌───────────────┐   │
│  │  Step 0   │──▶│  Step 1   │──▶│   Step 2      │──▶│   Step 3       │   │
│  │  Modo &   │   │  Prompt   │   │  Pegar JSON   │   │  Pre-carga    │   │
│  │  Límites  │   │  Builder  │   │  + Validar    │   │  Editable     │   │
│  └──────────┘   └──────────┘   └──────────────┘   └───────┬───────┘   │
│                                                             │           │
│  ┌───────────────┐   ┌──────────────┐   ┌──────────────────▼────────┐  │
│  │   Step 6       │◀──│   Step 5      │◀──│   Step 4                  │  │
│  │  Cola + Reporte│   │  Confirmación │   │  Staging de imágenes     │  │
│  └───────────────┘   └──────────────┘   └───────────────────────────┘  │
│                                                                         │
└─────────────────────────────────────────────────────────────────────────┘

                              ▼ API Calls ▼

┌─────────────────────────────────────────────────────────────────────────┐
│                         BACKEND (NestJS API)                            │
│                                                                         │
│  ┌──────────────────┐   ┌──────────────────┐   ┌────────────────────┐  │
│  │ ImportWizardModule│   │ ImportBatchWorker │   │ ProductsService     │  │
│  │                  │   │ (@Cron polling)   │   │ (reutilizado)      │  │
│  │ - validate JSON  │   │ - procesa items   │   │ - upsert           │  │
│  │ - create batch   │   │ - sube imágenes   │   │ - findOrCreate Cat │  │
│  │ - enqueue        │   │ - reporta         │   │ - validateRow      │  │
│  └──────────────────┘   └──────────────────┘   └────────────────────┘  │
│                                                                         │
│  DB: import_batches + import_batch_items (patrón email_jobs)            │
│  Storage: product-images bucket (existente)                             │
└─────────────────────────────────────────────────────────────────────────┘
```

### 2.2 Tablas nuevas (Backend DB — Multicliente)

#### `import_batches`

```sql
CREATE TABLE import_batches (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id   UUID NOT NULL REFERENCES clients(id),
  user_id     UUID NOT NULL,                          -- admin que creó el batch
  mode        TEXT NOT NULL CHECK (mode IN ('create', 'update', 'mixed')),
  status      TEXT NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft', 'validating', 'staging', 'queued', 'processing', 'completed', 'failed', 'cancelled')),
  
  -- Contadores (actualización incremental por el worker)
  total_items     INT NOT NULL DEFAULT 0,
  ok_count        INT NOT NULL DEFAULT 0,
  warning_count   INT NOT NULL DEFAULT 0,
  error_count     INT NOT NULL DEFAULT 0,
  processed_count INT NOT NULL DEFAULT 0,
  
  -- Metadatos
  source          TEXT DEFAULT 'ai_wizard',            -- 'ai_wizard' | 'excel' (futuro unificado)
  ai_prompt_used  TEXT,                                -- prompt original (para auditoría/debugging)
  original_json   JSONB,                               -- JSON pegado por el admin (pre-validación)
  
  started_at      TIMESTAMPTZ,
  completed_at    TIMESTAMPTZ,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_import_batches_client_id ON import_batches(client_id);
CREATE INDEX idx_import_batches_status ON import_batches(status);
```

#### `import_batch_items`

```sql
CREATE TABLE import_batch_items (
  id          UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id    UUID NOT NULL REFERENCES import_batches(id) ON DELETE CASCADE,
  client_id   UUID NOT NULL REFERENCES clients(id),
  
  -- Posición y matching
  position    INT NOT NULL,                            -- orden dentro del batch (0-based)
  action      TEXT NOT NULL CHECK (action IN ('create', 'update')),
  
  -- Matching para updates
  match_sku       TEXT,                                -- SKU para matching
  match_product_id UUID,                               -- ID resuelto (si existe)
  
  -- Payload
  payload_raw     JSONB NOT NULL,                      -- tal como vino del JSON del admin
  payload_normalized JSONB,                            -- normalizado con campos DB reales
  
  -- Imágenes staging
  staged_images   JSONB DEFAULT '[]',                  -- [{url, storage_path, order, status}]
  
  -- Resultado de validación (pre-queue)
  validation_status TEXT NOT NULL DEFAULT 'pending'
                    CHECK (validation_status IN ('pending', 'ok', 'warning', 'error')),
  validation_errors JSONB DEFAULT '[]',                -- [{field, code, message, suggested_fix}]
  
  -- Resultado de procesamiento (post-queue)
  process_status  TEXT DEFAULT 'pending'
                  CHECK (process_status IN ('pending', 'processing', 'success', 'failed', 'skipped')),
  process_error   JSONB,                               -- {code, message, field_path, suggested_fix}
  result_product_id UUID,                              -- ID del producto creado/actualizado
  
  created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX idx_ibi_batch_id ON import_batch_items(batch_id);
CREATE INDEX idx_ibi_client_id ON import_batch_items(client_id);
CREATE INDEX idx_ibi_process_status ON import_batch_items(process_status);
```

#### RLS

```sql
ALTER TABLE import_batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE import_batch_items ENABLE ROW LEVEL SECURITY;

-- Server bypass (backend con service_role)
CREATE POLICY "server_bypass" ON import_batches FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

CREATE POLICY "server_bypass" ON import_batch_items FOR ALL
  USING (auth.role() = 'service_role') WITH CHECK (auth.role() = 'service_role');

-- Tenant isolation (admin del tenant puede leer sus batches)
CREATE POLICY "ib_select_tenant" ON import_batches FOR SELECT
  USING (client_id = current_client_id() AND is_admin());

CREATE POLICY "ibi_select_tenant" ON import_batch_items FOR SELECT
  USING (client_id = current_client_id() AND is_admin());
```

### 2.3 Máquina de estados del batch

```
                ┌──────────┐
                │  draft    │ ← Batch creado, JSON validándose
                └────┬─────┘
                     │ validación OK
                     ▼
              ┌──────────────┐
              │  staging      │ ← Admin editando items + subiendo imágenes
              └────┬─────────┘
                   │ admin confirma (0 errors)
                   ▼
              ┌──────────┐
              │  queued   │ ← Listo para procesar
              └────┬─────┘
                   │ worker toma el batch
                   ▼
            ┌──────────────┐
            │  processing   │ ← Worker procesando item por item
            └────┬─────────┘
                 │ todos procesados
            ┌────┴────┐
            ▼         ▼
      ┌──────────┐ ┌────────┐
      │ completed │ │ failed  │ ← si >50% falló = failed
      └──────────┘ └────────┘

  En cualquier estado pre-processing:
      → cancelled (el admin cancela)
```

---

## 3. Contrato JSON — `ProductImportV1`

### 3.1 Schema del JSON que pega el admin

```typescript
interface ProductImportPayload {
  version: 'ProductImportV1';
  products: ProductImportItem[];
}

interface ProductImportItem {
  // --- Obligatorios ---
  action: 'create' | 'update';
  sku: string;                     // min 1 char, unique dentro del lote
  name: string;                    // min 3 chars, max 200
  originalPrice: number;           // > 0

  // --- Opcionales con defaults ---
  quantity?: number;               // >= 0, default 0
  currency?: 'ARS' | 'USD';       // default: currency de la tienda
  available?: boolean;             // default: true
  description?: string;            // max 5000 chars, texto plano (sanitizar HTML)

  // --- Opcionales libres ---
  discountedPrice?: number | null;        // < originalPrice si presente
  discountPercentage?: number | null;     // 0-100
  material?: string | null;
  filters?: string | null;                // texto libre (color, talle, etc.)
  categories?: string[];                  // nombres o IDs — resuelve contra catálogo
  tags?: string[];
  weight_grams?: number | null;           // >= 0
  featured?: boolean;
  bestSell?: boolean;
  sendMethod?: boolean;

  // --- SEO (opcionales) ---
  slug?: string | null;
  meta_title?: string | null;             // max 65 chars
  meta_description?: string | null;       // max 160 chars

  // --- Promoción (opcionales) ---
  promotionTitle?: string | null;
  promotionDescription?: string | null;
  validFrom?: string | null;              // ISO 8601
  validTo?: string | null;                // ISO 8601, >= validFrom

  // --- Imágenes (sugerencias de IA, no URLs finales) ---
  image_prompts?: string[];               // max 6, texto descriptivo para buscar imágenes
}
```

### 3.2 Reglas de validación (2 capas)

#### Capa 1 — Schema (estructura y tipos)

| Regla | Detalle |
|---|---|
| `version` = `'ProductImportV1'` | Obligatorio, exacto |
| `products` = array no vacío | Mínimo 1 item |
| `products.length` ≤ límite del plan | Starter: 10, Growth: 50, Enterprise: 200 |
| Cada item tiene `action`, `sku`, `name`, `originalPrice` | Campos obligatorios |
| Tipos correctos | `sku` string, `originalPrice` number, etc. |
| No hay campos desconocidos | Warn (no error) si hay campos extra |

#### Capa 2 — Business Rules (lógica de negocio)

| Regla | Severidad | Mensaje |
|---|---|---|
| `sku` único dentro del lote | ERROR | `SKU "{sku}" duplicado en posición {pos1} y {pos2}` |
| `sku` ya existe en DB (action=`create`) | WARNING | `SKU "{sku}" ya existe — se actualizará en lugar de crear` |
| `sku` NO existe en DB (action=`update`) | ERROR | `SKU "{sku}" no encontrado para actualizar` |
| `originalPrice` > 0 | ERROR | `Precio debe ser mayor a 0` |
| `quantity` >= 0 | ERROR | `Stock no puede ser negativo` |
| `quantity` === 0 | WARNING | `Stock en 0 — producto no disponible para compra` |
| `discountedPrice` >= `originalPrice` | WARNING | `Precio con descuento mayor o igual al original` |
| `discountPercentage` fuera de 0-100 | ERROR | `Porcentaje de descuento debe estar entre 0 y 100` |
| Categoría no existe en el tenant | WARNING | `Categoría "{name}" no existe — se creará automáticamente` |
| `name` < 3 chars | ERROR | `Nombre demasiado corto (mínimo 3 caracteres)` |
| `description` con HTML pesado | WARNING | `Se detectó HTML en la descripción — se sanitizará` |
| `meta_title` > 65 chars | WARNING | `Título SEO excede 65 caracteres (puede cortarse en buscadores)` |
| `meta_description` > 160 chars | WARNING | `Descripción SEO excede 160 caracteres` |
| `validFrom` > `validTo` | ERROR | `Fecha de inicio posterior a fecha de fin de promoción` |
| Total productos + existentes > `maxProducts` del plan | ERROR | `Excede el límite de {max} productos del plan {plan}` |
| `currency` no es ARS ni USD | ERROR | `Moneda no soportada: "{currency}"` |
| Imágenes > 6 por producto | WARNING | `Máximo 6 imágenes — se ignorarán las excedentes` |

### 3.3 Formato de errores de validación

```typescript
interface ValidationError {
  position: number;       // índice del producto en el array (0-based)
  sku: string;            // para identificar rápidamente
  field: string;          // campo afectado ("originalPrice", "categories[0]", etc.)
  code: string;           // "REQUIRED" | "INVALID_TYPE" | "DUPLICATE_SKU" | "SKU_NOT_FOUND" | etc.
  severity: 'error' | 'warning';
  message: string;        // mensaje humano en español
  suggested_fix: string;  // sugerencia accionable
}
```

---

## 4. Límites por Plan (AI Import)

Extender los plan limits existentes con propiedades de import:

```javascript
// basicPlanLimits.jsx (Starter)
aiImport: {
  enabled: false,                // No disponible — mostrar upgrade CTA
  maxProductsPerBatch: 0,
  maxBatchesPerDay: 0,
  maxImageSizeKB: 300,
  maxImagesPerProduct: 1,
}

// professionalPlanLimits.jsx (Growth)
aiImport: {
  enabled: true,
  maxProductsPerBatch: 50,
  maxBatchesPerDay: 5,
  maxImageSizeKB: 800,
  maxImagesPerProduct: 5,
}

// premiumPlanLimits.jsx (Enterprise)
aiImport: {
  enabled: true,
  maxProductsPerBatch: 200,
  maxBatchesPerDay: 20,
  maxImageSizeKB: 1024,
  maxImagesPerProduct: 10,
}
```

**Backend enforcement:** Nuevo `@PlanAction('ai_import')` que valida `aiImport.enabled` + conteo de batches del día.

---

## 5. Diseño Detallado por Paso del Wizard

### Step 0 — Modo de Importación

**UI:** Card selector con 2 opciones + panel de info del plan.

```
┌─────────────────────────────────────────────────────────┐
│  ¿Qué querés hacer?                                     │
│                                                         │
│  ┌──────────────────┐  ┌──────────────────┐            │
│  │  ➕ Crear nuevos   │  │  ✏️ Actualizar    │            │
│  │  productos        │  │  existentes      │            │
│  │                  │  │  (por SKU)       │            │
│  └──────────────────┘  └──────────────────┘            │
│                                                         │
│  📊 Tu plan: Growth                                     │
│  • Productos actuales: 47 de 200                       │
│  • Podés importar hasta 50 por lote                    │
│  • Imágenes: hasta 5 por producto (máx 800 KB)         │
│  • Lotes hoy: 1 de 5 usados                           │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Datos necesarios (API calls):**
- `GET /products/count` → total de productos actuales del tenant
- `GET /import-batches/today-count` → batches usados hoy
- Plan limits del contexto client

**Componente estimado:** `ImportWizardStep0.jsx` (~120 líneas)

---

### Step 1 — Prompt Builder

**UI:** Formulario que construye un prompt contextualizado con datos reales de la tienda.

```
┌─────────────────────────────────────────────────────────┐
│  Generador de Prompt para IA                            │
│                                                         │
│  Rubro / Categoría de tienda: [___________________]    │
│  Moneda:          [ARS ▼]     País: [Argentina ▼]      │
│  Estilo de texto: [Profesional ▼]                      │
│                                                         │
│  Categorías existentes:                                │
│  ☑ Remeras  ☑ Pantalones  ☑ Accesorios  ☐ Crear nuevas │
│                                                         │
│  Campos a incluir:                                     │
│  ☑ Descripción  ☑ SKU  ☑ Precio  ☑ Stock              │
│  ☐ Material  ☐ Peso  ☐ SEO  ☐ Promoción               │
│                                                         │
│  ¿Cuántos productos? [15   ]                           │
│                                                         │
│  📝 Contexto adicional (opcional):                     │
│  [Somos una tienda de ropa urbana para jóvenes...]     │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  PROMPT GENERADO (editable)                       │  │
│  │                                                    │  │
│  │  Actuá como un generador de datos ESTRICTO...     │  │
│  │  ...                                               │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  [📋 Copiar Prompt]  [▶ Usar con ChatGPT]              │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Lógica clave:**
- El prompt se genera dinámicamente según las selecciones del admin.
- Las categorías se obtienen de `GET /categories` del tenant.
- El prompt incluye la lista EXACTA de categorías permitidas.
- Los campos seleccionados se reflejan en el schema dentro del prompt.
- El número de productos se limita al máximo del plan.

**Template del prompt:** Se almacena como constante en el frontend (no depende del backend). Incluye:
1. Rol de la IA ("generador de datos ESTRICTO")
2. Regla principal (solo JSON, sin markdown)
3. Contexto de la tienda (interpolado)
4. Restricciones (interpoladas desde plan limits)
5. Schema exacto del JSON esperado (campos marcados/desmarcados)
6. Lista de categorías permitidas
7. Input placeholder para que el admin agregue productos base

**Componente estimado:** `ImportWizardStep1.jsx` + `buildPrompt.js` (~250 líneas total)

---

### Step 2 — Pegar JSON + Validar

**UI:** Textarea con syntax highlighting (opcional) + panel de resultados.

```
┌─────────────────────────────────────────────────────────┐
│  Pegá el JSON generado por la IA                       │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │ {                                                  │  │
│  │   "version": "ProductImportV1",                   │  │
│  │   "products": [                                    │  │
│  │     { "action": "create", "sku": "REM-001", ... } │  │
│  │   ]                                                │  │
│  │ }                                                  │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  [🔍 Validar JSON]                                     │
│                                                         │
│  ── Resultado ──────────────────────────────────────── │
│  ✅ 12 productos válidos                               │
│  ⚠️  3 warnings (stock=0, categoría nueva)             │
│  ❌ 0 errores                                          │
│                                                         │
│  ⚠️ Producto #4 (SKU: REM-004):                       │
│     Stock en 0 — producto no disponible para compra    │
│  ⚠️ Producto #7 (SKU: ACC-001):                       │
│     Categoría "Gorras" no existe → se creará           │
│                                                         │
│  [📋 Copiar prompt de corrección]  [▶ Siguiente]      │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Flujo de validación:**

```
JSON string → JSON.parse() → ¿parse OK?
  ├─ NO → mostrar error de sintaxis con línea/columna
  └─ SÍ → Capa 1 (schema) → ¿OK?
       ├─ NO → errores de estructura
       └─ SÍ → Capa 2 (business rules) → resultado mixto (errors + warnings)
            └─ API call: POST /import-wizard/validate
               Body: { mode, products[] }
               Response: { valid, errors[], warnings[], resolvedCategories[], skuMatches[] }
```

**¿Dónde se valida?**

| Capa | Dónde | Por qué |
|---|---|---|
| JSON.parse() | Frontend | Feedback instantáneo |
| Schema (estructura y tipos) | Frontend | No necesita DB, feedback rápido |
| Business rules (SKU duplicado, categorías, plan limits) | **Backend** | Necesita acceso a DB para verificar SKUs existentes, categorías, conteo de productos |

**Endpoint:** `POST /import-wizard/validate`

```typescript
// Request
{
  mode: 'create' | 'update' | 'mixed',
  products: ProductImportItem[]
}

// Response
{
  valid: boolean,                      // true si 0 errors (warnings permitidos)
  total: number,
  errors: ValidationError[],           // severity='error'
  warnings: ValidationError[],         // severity='warning'
  summary: {
    ok: number,
    warnings: number,
    errors: number
  },
  resolved: {
    categories: { input: string, exists: boolean, id?: string }[],
    skus: { sku: string, exists: boolean, productId?: string }[]
  }
}
```

**Prompt de corrección:** Si hay errores, se genera automáticamente un prompt que incluye el JSON actual + la lista de errores, para que el admin lo pegue de vuelta en la IA.

**Componente estimado:** `ImportWizardStep2.jsx` + `validateSchema.js` (~300 líneas FE, ~200 líneas BE)

---

### Step 3 — Pre-carga Editable

**UI:** Tabla con estado por producto + click para editar en el ProductModal existente.

```
┌─────────────────────────────────────────────────────────────┐
│  Pre-carga: revisá y editá antes de importar                │
│                                                              │
│  🔍 [Buscar...]  Filtrar: [Todos ▼] [Solo warnings ▼]      │
│                                                              │
│  ┌───┬─────────┬──────────────┬─────────┬────────┬───────┐ │
│  │ # │ Estado  │ Nombre       │ SKU     │ Precio │ Stock │ │
│  ├───┼─────────┼──────────────┼─────────┼────────┼───────┤ │
│  │ 1 │ ✅ OK   │ Remera Basic │ REM-001 │ $4.500 │  25   │ │
│  │ 2 │ ✅ OK   │ Pantalón Jog │ PAN-001 │ $8.900 │  15   │ │
│  │ 3 │ ⚠️ Warn │ Gorra Urban  │ ACC-001 │ $2.100 │   0   │ │
│  │ 4 │ ✅ OK   │ Buzo Oversize│ BUZ-001 │ $12.500│  10   │ │
│  └───┴─────────┴──────────────┴─────────┴────────┴───────┘ │
│                                                              │
│  📊 12 OK  |  3 Warnings  |  0 Errors                      │
│                                                              │
│  [◀ Volver]                          [▶ Siguiente]          │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

**Interacción:**
- Click en una fila → abre `ProductModal` en modo "draft" (no guarda en DB aún).
- El modal permite editar todos los campos + subir/previewear imágenes locales.
- Al guardar en el modal, se actualiza el item del batch (estado local o `PATCH /import-wizard/batches/:id/items/:itemId`).
- Los warnings se recalculan después de cada edición.

**Reutilización del ProductModal:**
- El `ProductModal` ya maneja todos los campos del producto, incluyendo:
  - `FileUploader` para imágenes (drag & drop, reordenamiento)
  - Selección de categorías (select múltiple)
  - Descuentos con cálculo automático
  - Variantes/option sets
- Se agrega una prop `mode: 'draft' | 'live'` para distinguir:
  - `draft`: no llama API de create/update, solo devuelve datos vía callback
  - `live`: comportamiento actual (create/update real en DB)

**Persistencia del draft:**
- **Opción recomendada:** guardar en `import_batch_items.payload_normalized` vía API.
- Cada edit llama `PATCH /import-wizard/batches/:batchId/items/:itemId` con el payload actualizado.
- Esto permite cerrar el browser y retomar más tarde.

**Componente estimado:** `ImportWizardStep3.jsx` + adaptación de `ProductModal` (~200 líneas nuevas + ~30 líneas de cambios en ProductModal)

---

### Step 4 — Staging de Imágenes

**UI:** Panel de progreso de subida de imágenes por producto.

```
┌─────────────────────────────────────────────────────────┐
│  Subida de imágenes (staging)                           │
│                                                         │
│  Las imágenes se suben ahora para agilizar la carga.   │
│                                                         │
│  Producto 1: Remera Basic (REM-001)                    │
│  ████████████████████░░░░ 80% — 2 de 3 imágenes       │
│                                                         │
│  Producto 2: Pantalón Jogger (PAN-001)                 │
│  ██████████████████████████ 100% ✅                     │
│                                                         │
│  Producto 3: Gorra Urban (ACC-001)                     │
│  Sin imágenes                                           │
│                                                         │
│  ── Progreso general ──                                │
│  ████████████████░░░░░░░░ 60% — 7 de 12 productos     │
│                                                         │
│  [◀ Volver]                          [▶ Siguiente]     │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Flujo técnico:**

```
1. Para cada producto que tiene imágenes locales (File objects):
   a. Para cada imagen:
      - Validar tipo + tamaño vs plan limits
      - Subir a Storage vía POST /import-wizard/batches/:batchId/items/:itemId/stage-image
        (el backend sube al bucket product-images con path temporal:
         {clientId}/staging/{batchId}/{itemId}/{uuid}_{filename})
      - Backend retorna {storage_path, public_url}
      - Actualizar import_batch_items.staged_images
   b. Progreso: 0% → 100% por producto
2. Cuando todos terminan → habilitar "Siguiente"
```

**¿Por qué staging y no subir después?**
- El worker batch NO puede recibir File blobs (es server-side).
- Las imágenes deben estar en Storage ANTES de encolar.
- Si falla la carga de imágenes, el admin puede reintentar antes de commitear.
- Después del procesamiento, el worker MUEVE las imágenes de `staging/` al path definitivo.

**Endpoint:** `POST /import-wizard/batches/:batchId/items/:itemId/stage-image`

```typescript
// Request: FormData con file
// Response:
{
  storage_path: string,    // path en el bucket
  public_url: string,      // URL pública
  order: number            // posición en el array de imágenes
}
```

**Componente estimado:** `ImportWizardStep4.jsx` (~180 líneas)

---

### Step 5 — Confirmación Final

**UI:** Resumen con contadores + botón de encolado.

```
┌─────────────────────────────────────────────────────────┐
│  Resumen de importación                                 │
│                                                         │
│  Modo: Crear nuevos productos                          │
│  Total: 15 productos                                   │
│                                                         │
│  ✅ OK:        12                                       │
│  ⚠️ Warnings:   3 (stock=0, categoría nueva)           │
│  ❌ Errors:     0                                       │
│                                                         │
│  📦 Imágenes:  28 subidas (de 30)                      │
│  📂 Categorías nuevas: Gorras, Cinturones              │
│                                                         │
│  ⚠️ Los 3 productos con warnings se importarán         │
│     con las condiciones indicadas.                      │
│                                                         │
│  ┌──────────────────────────────────────────────────┐  │
│  │  ☑ Entiendo que esta acción creará 15 productos   │  │
│  │    y 2 categorías nuevas en mi tienda.            │  │
│  └──────────────────────────────────────────────────┘  │
│                                                         │
│  [◀ Volver]              [🚀 Confirmar e importar]    │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Lógica:**
- Botón "Confirmar" deshabilitado si hay errors > 0 o falta el checkbox.
- Al confirmar → `POST /import-wizard/batches/:batchId/enqueue`
- El endpoint cambia `status: 'staging' → 'queued'`
- Navega automáticamente al Step 6.

**Componente estimado:** `ImportWizardStep5.jsx` (~120 líneas)

---

### Step 6 — Cola de Carga + Reporte

**UI:** Progreso live + reporte descargable al finalizar.

```
┌─────────────────────────────────────────────────────────┐
│  Importación en progreso...                             │
│                                                         │
│  ████████████████████░░░░ 80%                          │
│  12 de 15 procesados                                   │
│                                                         │
│  ✅ Creados:    10                                      │
│  ⚠️ Con aviso:   2                                     │
│  ❌ Fallidos:    0                                      │
│  ⏳ Pendientes:  3                                      │
│                                                         │
│  ── Log en vivo ──                                     │
│  12:03:45  ✅ REM-001 "Remera Basic" creado            │
│  12:03:46  ✅ PAN-001 "Pantalón Jogger" creado         │
│  12:03:47  ⚠️ ACC-001 "Gorra Urban" creado (stock=0)  │
│  ...                                                   │
│                                                         │
│  ── Al completar ──                                    │
│  [📥 Descargar reporte (JSON)]                         │
│  [📥 Descargar reporte (CSV)]                          │
│  [🔙 Volver al catálogo]                               │
│                                                         │
└─────────────────────────────────────────────────────────┘
```

**Polling de progreso:**
- `GET /import-wizard/batches/:batchId` cada 3 segundos.
- Response incluye contadores actualizados + últimos N items procesados.
- Cuando `status === 'completed' | 'failed'` → detener polling, mostrar reporte.

**Reporte descargable:**

```typescript
interface ImportReport {
  batch_id: string;
  created_at: string;
  completed_at: string;
  mode: string;
  summary: {
    total: number;
    success: number;
    failed: number;
    warnings: number;
    categories_created: string[];
  };
  items: ImportReportItem[];
}

interface ImportReportItem {
  position: number;
  sku: string;
  name: string;
  action: 'create' | 'update';
  status: 'success' | 'failed' | 'skipped';
  product_id?: string;           // ID del producto creado/actualizado
  warnings?: string[];
  error?: {
    code: string;
    message: string;
    field: string;
    suggested_fix: string;
  };
}
```

**Endpoint:** `GET /import-wizard/batches/:batchId/report?format=json|csv`

**Componente estimado:** `ImportWizardStep6.jsx` (~200 líneas)

---

## 6. Backend — Módulo `ImportWizardModule`

### 6.1 Estructura de archivos

```
src/import-wizard/
├── import-wizard.module.ts
├── import-wizard.controller.ts        # Endpoints REST
├── import-wizard.service.ts           # Lógica de negocio (validate, create batch, etc.)
├── import-wizard-worker.service.ts    # Worker @Cron que procesa batches
├── dto/
│   ├── validate-import.dto.ts         # DTO para POST /validate
│   ├── create-batch.dto.ts            # DTO para POST /batches
│   └── update-batch-item.dto.ts       # DTO para PATCH /batches/:id/items/:itemId
├── schemas/
│   └── product-import-v1.schema.ts    # Validación de schema
└── utils/
    ├── import-validators.ts           # Business rules (extraídas de products.service.ts)
    └── import-report.ts               # Generación de reporte JSON/CSV
```

### 6.2 Endpoints

| Método | Ruta | Auth | Descripción |
|---|---|---|---|
| `POST` | `/import-wizard/validate` | Admin | Valida JSON sin crear batch |
| `POST` | `/import-wizard/batches` | Admin | Crea batch en estado `draft` + items |
| `GET` | `/import-wizard/batches` | Admin | Lista batches del tenant (paginado) |
| `GET` | `/import-wizard/batches/:id` | Admin | Detalle de batch con contadores |
| `GET` | `/import-wizard/batches/:id/items` | Admin | Items del batch (paginado, filtrable por status) |
| `PATCH` | `/import-wizard/batches/:id/items/:itemId` | Admin | Actualiza payload de un item |
| `POST` | `/import-wizard/batches/:id/items/:itemId/stage-image` | Admin | Sube imagen al staging |
| `DELETE` | `/import-wizard/batches/:id/items/:itemId/staged-images/:order` | Admin | Elimina imagen staged |
| `POST` | `/import-wizard/batches/:id/enqueue` | Admin | Cambia status a `queued` |
| `POST` | `/import-wizard/batches/:id/cancel` | Admin | Cancela batch (si no está processing) |
| `GET` | `/import-wizard/batches/:id/report` | Admin | Descarga reporte (JSON/CSV) |
| `GET` | `/import-wizard/today-count` | Admin | Batches usados hoy (para límite diario) |

### 6.3 Worker (Cron — patrón DB-polling)

```typescript
@Injectable()
export class ImportWizardWorkerService {
  
  // Polling cada 10 segundos para batches en estado 'queued'
  @Cron('*/10 * * * * *')
  async processQueuedBatches() {
    // 1. SELECT batch WHERE status='queued' ORDER BY created_at LIMIT 1
    //    → UPDATE status='processing', started_at=now()
    //    (usar FOR UPDATE SKIP LOCKED si hay múltiples workers)
    
    // 2. SELECT items WHERE batch_id=? AND process_status='pending' ORDER BY position
    
    // 3. Para cada item:
    //    a. Normalizar payload → campos DB reales
    //    b. Resolver categorías (findOrCreateCategory)
    //    c. Resolver imágenes staged → mover de staging/ a path definitivo
    //    d. Upsert producto (reutilizar lógica de products.service.ts)
    //    e. Asignar categorías (product_categories)
    //    f. Actualizar item: process_status='success'|'failed', result_product_id
    //    g. Actualizar batch: processed_count++, ok/error_count
    
    // 4. Al terminar todos los items:
    //    UPDATE batch SET status='completed'|'failed', completed_at=now()
    
    // Concurrency: procesar 1 batch a la vez, items en serie (evitar overload DB)
  }
}
```

**Decisión: concurrency baja.** Procesar 1 batch y 1 item a la vez. Razones:
- No hay Redis/Bull para coordinar workers.
- Supabase tiene rate limits.
- El batch es background — no necesita ser instantáneo.
- Serie permite rollback simple si algo falla.

### 6.4 Validadores (extraer de products.service.ts)

Actualmente `validateProductRow()` está embebido en `products.service.ts`. Propuesta:

```
// ANTES: monolítico en products.service.ts
// DESPUÉS: extraer a módulo compartido

src/products/validators/
├── product-row.validator.ts      # validateProductRow() existente
├── product-row.validator.spec.ts # tests

src/import-wizard/utils/
├── import-validators.ts          # Orquesta schema + business rules
                                  # Importa product-row.validator
```

Esto permite que tanto el Excel upload como el AI Import usen las mismas validaciones.

---

## 7. Frontend — Componentes del Wizard

### 7.1 Estructura de archivos

```
src/components/admin/ImportWizard/
├── index.jsx                     # Componente principal con Stepper
├── ImportWizardStep0.jsx          # Modo + límites
├── ImportWizardStep1.jsx          # Prompt Builder
├── ImportWizardStep2.jsx          # Pegar JSON + validar
├── ImportWizardStep3.jsx          # Pre-carga editable
├── ImportWizardStep4.jsx          # Staging de imágenes
├── ImportWizardStep5.jsx          # Confirmación
├── ImportWizardStep6.jsx          # Cola + reporte
├── prompts/
│   ├── buildPrompt.js            # Genera prompt dinámico
│   ├── buildCorrectionPrompt.js  # Genera prompt de corrección
│   └── buildUpdatePrompt.js      # Genera prompt de actualización
├── validators/
│   └── schemaValidator.js        # Validación client-side (capa 1)
├── hooks/
│   ├── useImportWizard.js        # Estado global del wizard
│   └── useBatchPolling.js        # Polling de progreso
└── style.jsx                     # Styled components (reutilizar design system admin)
```

### 7.2 Acceso desde el Dashboard

Agregar botón/entrada en `ProductDashboard`:

```jsx
// En la barra de acciones del ProductDashboard
{planLimits.aiImport?.enabled && (
  <Button onClick={() => navigate('/admin/products/import-wizard')}>
    🤖 Importar con IA
  </Button>
)}
```

**Ruta:** `/admin/products/import-wizard` → componente `ImportWizard`

### 7.3 UX del Stepper

Reutilizar el patrón de stepper existente en el proyecto (similar al checkout stepper). Los steps son lineales (no se puede saltar adelante sin completar el anterior).

```jsx
const STEPS = [
  { label: 'Modo',          icon: '🎯' },
  { label: 'Prompt',        icon: '✨' },
  { label: 'JSON',          icon: '📋' },
  { label: 'Revisión',      icon: '👀' },
  { label: 'Imágenes',      icon: '🖼️' },
  { label: 'Confirmar',     icon: '✅' },
  { label: 'Progreso',      icon: '🚀' },
];
```

---

## 8. Prompts IA — Templates Adaptados al Sistema Real

### 8.1 Prompt de creación (template)

Se genera dinámicamente en `buildPrompt.js`. Variables interpoladas:

| Variable | Fuente |
|---|---|
| `{{MONEDA}}` | `clientConfig.currency` o selección del admin |
| `{{PAIS}}` | `clientConfig.country` o selección |
| `{{MAX_PRODUCTS}}` | `planLimits.aiImport.maxProductsPerBatch` |
| `{{LISTA_CATEGORIAS}}` | `GET /categories` del tenant |
| `{{CAMPOS_SELECCIONADOS}}` | Checkboxes del Step 1 |
| `{{CONTEXTO_ADMIN}}` | Textarea libre del Step 1 |

```javascript
export function buildPrompt({ currency, country, maxProducts, categories, fields, context }) {
  const categoryList = categories.length > 0
    ? categories.map(c => `"${c.name}"`).join(', ')
    : '(no hay categorías creadas — podés sugerir nombres)';

  const fieldsSchema = buildFieldsSchema(fields); // genera solo los campos seleccionados

  return `Actuá como un generador de datos ESTRICTO para importación de productos de e-commerce.

REGLA PRINCIPAL:
Respondé ÚNICAMENTE con JSON válido (sin markdown, sin comentarios, sin texto extra).
Si no estás seguro de un dato, usá null o un string vacío, pero NO inventes.

CONTEXTO DE LA TIENDA:
- País/mercado: ${country}
- Moneda: ${currency}
- Estilo de comunicación: claro, profesional, español neutro.

RESTRICCIONES DE IMPORTACIÓN (OBLIGATORIAS):
- Máximo ${maxProducts} productos.
- Cada producto DEBE tener: action, sku, name, originalPrice.
- quantity puede ser 0 (permitido, pero será warning).
- material y filters son opcionales — si no aplican, omitirlos.
- NO escribir "Sin categoría". Si no hay categoría, categories debe ser [].
- categories solo puede usar valores de esta lista EXACTA (si no corresponde, dejar []):
  [${categoryList}]
- No uses HTML en description. Texto plano.
- Imágenes: NO inventes URLs. Si querés sugerir búsquedas de imágenes, usá "image_prompts" (máximo 3 por producto).

FORMATO DE SALIDA:
{
  "version": "ProductImportV1",
  "products": [ ... ]
}

ESQUEMA DE CADA PRODUCTO:
${fieldsSchema}

INPUT DEL ADMIN:
${context || '(Generá productos de ejemplo representativos del rubro)'}`;
}
```

### 8.2 Prompt de corrección

```javascript
export function buildCorrectionPrompt({ json, errors }) {
  const errorList = errors.map(e =>
    `- Producto #${e.position + 1} (SKU: ${e.sku}), campo "${e.field}": ${e.message}`
  ).join('\n');

  return `Actuá como un reparador ESTRICTO de JSON para importación de productos.

REGLA PRINCIPAL:
Devolvé ÚNICAMENTE el JSON corregido válido. Sin markdown. Sin texto extra.
No cambies campos que no sean mencionados en los errores.

ERRORES A CORREGIR:
${errorList}

JSON A CORREGIR:
${JSON.stringify(json, null, 2)}`;
}
```

### 8.3 Prompt de actualización masiva

```javascript
export function buildUpdatePrompt({ currency, categories, context }) {
  return `Sos un generador de JSON para ACTUALIZAR productos existentes por SKU.

REGLA:
Solo devolvé JSON válido. Sin texto extra. action debe ser "update".

FORMATO:
{
  "version": "ProductImportV1",
  "products": [
    { "action": "update", "sku": "X", "originalPrice": 123, "quantity": 10, "name": "..." },
    ...
  ]
}

RESTRICCIONES:
- sku obligatorio (para matching)
- name opcional (solo si cambia)
- Incluí solo campos que cambian
- categories solo pueden ser: [${categories.map(c => `"${c.name}"`).join(', ')}]

INPUT:
${context}`;
}
```

---

## 9. Plan de Implementación por Fases

### Fase 1 — Foundation (Backend) ≈ 2-3 días

| # | Tarea | Entregable | Archivos |
|---|---|---|---|
| 1.1 | Migración: tablas `import_batches` + `import_batch_items` | SQL migration | `migrations/backend/YYYYMMDD_import_wizard_tables.sql` |
| 1.2 | RLS policies para las 2 tablas nuevas | SQL migration | mismo archivo |
| 1.3 | Crear `ImportWizardModule` (module + controller + service) | Scaffolding NestJS | `src/import-wizard/*.ts` |
| 1.4 | Extraer `validateProductRow()` a módulo compartido | Refactor sin cambio funcional | `src/products/validators/`, `src/products/products.service.ts` |
| 1.5 | Implementar `POST /import-wizard/validate` | Endpoint de validación | `import-wizard.service.ts` |
| 1.6 | Implementar CRUD de batches + items | Endpoints REST | `import-wizard.controller.ts` |
| 1.7 | Tests unitarios del validador | Cobertura | `*.spec.ts` |

**Riesgos Fase 1:**
- La extracción de `validateProductRow` podría romper el upload Excel existente → testing cuidadoso.
- Las migraciones necesitan ejecutarse en backend DB (no admin DB).

### Fase 2 — Worker + Staging (Backend) ≈ 2-3 días

| # | Tarea | Entregable | Archivos |
|---|---|---|---|
| 2.1 | Endpoint de staging de imágenes | `POST .../stage-image` | `import-wizard.controller.ts` |
| 2.2 | Worker cron para procesar batches | `ImportWizardWorkerService` | `import-wizard-worker.service.ts` |
| 2.3 | Lógica de mover imágenes de staging a path definitivo | Storage helper | `import-wizard.service.ts` |
| 2.4 | Generador de reporte (JSON + CSV) | `GET .../report` | `utils/import-report.ts` |
| 2.5 | Rate limiting por tenant (batches/día) | Guard/validator | `import-wizard.service.ts` |
| 2.6 | Tests de integración del worker | E2E del flujo completo | `*.spec.ts` |

**Riesgos Fase 2:**
- El worker @Cron comparte el event loop de NestJS → limitar procesamiento para no impactar requests normales.
- Imágenes en staging podrían quedar huérfanas si el batch se cancela → agregar cleanup cron.

### Fase 3 — Frontend Wizard (Web) ≈ 3-4 días

| # | Tarea | Entregable | Archivos |
|---|---|---|---|
| 3.1 | `ImportWizard` con stepper + routing | Componente base | `src/components/admin/ImportWizard/` |
| 3.2 | Step 0: Modo + límites | UI + API call | `ImportWizardStep0.jsx` |
| 3.3 | Step 1: Prompt Builder | UI + `buildPrompt.js` | `ImportWizardStep1.jsx`, `prompts/` |
| 3.4 | Step 2: Pegar JSON + validar | UI + schema validator + API call | `ImportWizardStep2.jsx`, `validators/` |
| 3.5 | Step 3: Pre-carga editable | Tabla + integración ProductModal | `ImportWizardStep3.jsx` |
| 3.6 | Step 4: Staging de imágenes | Upload + progreso | `ImportWizardStep4.jsx` |
| 3.7 | Step 5: Confirmación | Resumen + checkbox | `ImportWizardStep5.jsx` |
| 3.8 | Step 6: Polling + reporte | Progreso live + descarga | `ImportWizardStep6.jsx` |
| 3.9 | Agregar límites `aiImport` a plan configs | Config | `src/config/*PlanLimits.jsx` |
| 3.10 | Botón de acceso desde ProductDashboard | Integración | `ProductDashboard/index.jsx` |

**Riesgos Fase 3:**
- Adaptar `ProductModal` a modo "draft" requiere cuidado para no romper el modo "live".
- El stepper necesita persistir estado si el admin cierra el browser → los datos están en DB (batches/items).

### Fase 4 — Polish + Edge Cases ≈ 1-2 días

| # | Tarea | Entregable |
|---|---|---|
| 4.1 | Cleanup cron para batches abandonados (>24h en draft/staging) | Worker secundario |
| 4.2 | Cleanup de imágenes staged huérfanas | Storage cleanup |
| 4.3 | Historial de importaciones (lista de batches pasados) | UI en dashboard |
| 4.4 | Error boundaries y estados de carga/error en cada step | UX resiliente |
| 4.5 | Documentación de la feature | `novavision-docs/` |
| 4.6 | Actualizar docs de API (endpoints nuevos) | `api/docs/` |

---

## 10. Decisiones de Diseño y Alternativas Consideradas

### 10.1 ¿Por qué DB-polling y no Bull/Redis?

| Opción | Pros | Contras |
|---|---|---|
| **DB-polling (elegido)** | Sin infra nueva, patrón probado (email_jobs), simple | Latencia 10s entre polls, polling consume queries |
| Bull/Redis | Procesamiento instantáneo, reintentos built-in | Requiere Redis ($), más complejidad, Railway config |
| Edge Function (Supabase) | Serverless, auto-scale | Timeout 60s, no accede a NestJS services |

**Decisión:** DB-polling. Coherente con la arquitectura actual. El import no necesita ser instantáneo (el admin puede esperar minutos).

### 10.2 ¿Por qué staging de imágenes separado?

El worker batch corre server-side y no puede acceder a File objects del browser. Las opciones eran:

1. **Staging previo (elegido):** El frontend sube imágenes al Storage antes de encolar. El worker mueve de `staging/` a path definitivo.
2. **Base64 en JSON:** Imágenes como base64 en el payload — demasiado pesado, ineficiente.
3. **URLs externas:** La IA provee URLs — no confiable, problemas de CORS y disponibilidad.

### 10.3 ¿Por qué reutilizar ProductModal en vez de crear uno nuevo?

- Ya tiene TODOS los campos, validaciones, FileUploader, categorías, descuentos, variantes.
- Mantiene coherencia UX (el admin ya lo conoce).
- Solo necesita una prop `mode: 'draft'` para evitar el API call real.
- Reduce ~800 líneas de código duplicado.

### 10.4 ¿Validación client vs server?

| Validación | Dónde | Justificación |
|---|---|---|
| JSON syntax | Frontend | Feedback instantáneo, no necesita red |
| Schema (tipos, required) | Frontend | Feedback rápido, no necesita DB |
| Business rules (SKU, categorías, plan) | **Backend** | Necesita estado de DB |

Resultado: validación split en 2 capas. El frontend atrapa errores obvios inmediatamente; el backend valida contra la realidad del tenant.

### 10.5 ¿Qué pasa con el Excel upload existente?

**No se reemplaza.** El Excel upload sigue funcionando para admins que prefieren hojas de cálculo. A futuro, ambos flujos podrían converger a un único pipeline backend (ya que comparten validación y upsert), pero en esta fase se mantienen independientes.

Posible evolución futura:
```
Excel upload → parsea → ProductImportV1 JSON → misma cola → mismo reporte
```

---

## 11. Seguridad

| Aspecto | Mitigación |
|---|---|
| **JSON injection** | `JSON.parse()` estándar + validación de schema; nunca `eval()` |
| **HTML en description** | Sanitizar con DOMPurify o strip tags server-side |
| **Rate limiting** | Máx batches/día por plan + máx items/batch |
| **Storage abuse** | Imágenes validadas (tipo + tamaño) + cleanup de staging huérfano |
| **Multi-tenant leak** | Toda query filtra `client_id`; RLS como defensa en profundidad |
| **SKU collision** | Validación dentro del lote + contra DB del tenant |
| **Denegación de servicio** | Worker procesa 1 batch a la vez; no bloquea requests HTTP |

---

## 12. Métricas de Éxito

| Métrica | Objetivo |
|---|---|
| Tiempo de carga de 50 productos (con imágenes) | < 5 minutos |
| Tasa de error en primera validación | < 30% (el prompt bien armado reduce errores) |
| Adopción (admins que usan wizard vs Excel) | > 40% en 3 meses |
| Productos importados por wizard / mes | Tracking en `import_batches` |

---

## 13. Estimación Total

| Fase | Esfuerzo | Archivos nuevos | Archivos modificados |
|---|---|---|---|
| Fase 1: Foundation BE | 2-3 días | ~8 archivos | 2 (refactor validador) |
| Fase 2: Worker + Staging | 2-3 días | ~4 archivos | 1 (storage helper) |
| Fase 3: Frontend Wizard | 3-4 días | ~15 archivos | 4 (plan configs, dashboard, ProductModal, routes) |
| Fase 4: Polish | 1-2 días | ~3 archivos | 2 (docs) |
| **Total** | **8-12 días** | **~30 archivos** | **~9 archivos** |

---

## 14. Decisiones Confirmadas (por TL)

- [x] **Starter tiene acceso:** SÍ — muestra de **5 productos por batch**, 1 batch/día. Limits: `{ enabled: true, maxPerBatch: 5, maxBatchesPerDay: 1 }`
- [x] **Auto-creación de categorías:** MANTENER `findOrCreateCategory()` **pero** en Step 3 (pre-carga) avisar cuáles son categorías nuevas (badge "NUEVA") y permitir eliminarlas/remapearlas antes de confirmar.
- [x] **Imágenes obligatorias:** NO — solo **WARNING** si un producto no tiene imágenes. No bloquea la importación.
- [x] **Migración:** DIRECTO A PRODUCCIÓN — ejecutar SQL contra backend DB sin ambiente de staging previo. Actualizar datos existentes si es necesario.
- [x] **Plan limits (Growth/Enterprise):** Growth: 50/batch, 5 batches/día. Enterprise: 200/batch, ilimitado.
- [x] **Timeout batches abandonados:** 24h cleanup (sin cambios).
- [x] **Approval de otro admin:** NO requerido — el mismo admin crea y confirma.

---

## Apéndice A — Ejemplo de Flujo Completo (Happy Path)

```
1. Admin entra a /admin/products/import-wizard
2. Step 0: Selecciona "Crear nuevos", ve que tiene plan Growth (50/batch, 3 usados hoy de 5)
3. Step 1: Selecciona ARS, Argentina, categorías existentes [Remeras, Pantalones], marca campos extra [Material, SEO]
   → Copia prompt generado y lo pega en ChatGPT
4. ChatGPT genera JSON con 15 productos
5. Step 2: Pega JSON → "Validar" → 15 OK, 2 warnings (stock=0)
   → Confirma y avanza
6. Step 3: Ve tabla de 15 productos. Edita #3 (cambia precio). #7 no tenía categoría → la mapea a "Remeras"
7. Step 4: Para los 15 productos, sube imágenes locales (2-3 por producto)
   → Barra de progreso muestra 100% cuando todas están en staging
8. Step 5: Resumen: 15 productos, 2 warnings, 0 errors. Confirma checkbox y clickea "Importar"
9. Step 6: Progreso live: 15/15 procesados en ~45 segundos
   → Descarga reporte JSON con los 15 product_ids creados
10. Vuelve al catálogo → los 15 productos aparecen con imágenes y categorías
```

---

## Apéndice B — Mapeo de Campos JSON → DB

| Campo JSON (ProductImportV1) | Campo DB (products) | Transformación |
|---|---|---|
| `name` | `name` | Directo |
| `description` | `description` | Strip HTML |
| `sku` | `sku` | Directo, unique check |
| `originalPrice` | `originalPrice` | Number, > 0 |
| `discountedPrice` | `discountedPrice` | Number o null |
| `discountPercentage` | `discountPercentage` | 0-100 o null |
| `currency` | `currency` | Default tenant currency |
| `quantity` | `quantity` | Integer ≥ 0 |
| `available` | `available` | Boolean, default true |
| `material` | `material` | String o null |
| `filters` | `filters` | String o null |
| `categories` | N/A (→ product_categories) | Resolve por nombre/id |
| `tags` | `tags` | Array de strings |
| `weight_grams` | `weight_grams` | Number ≥ 0 o null |
| `featured` | `featured` | Boolean |
| `bestSell` | `bestSell` | Boolean |
| `sendMethod` | `sendMethod` | Boolean |
| `slug` | `slug` | Auto-generate si vacío |
| `meta_title` | `meta_title` | Max 65 chars |
| `meta_description` | `meta_description` | Max 160 chars |
| `promotionTitle` | `promotionTitle` | String o null |
| `promotionDescription` | `promotionDescription` | String o null |
| `validFrom` | `validFrom` | ISO 8601 → timestamp |
| `validTo` | `validTo` | ISO 8601 → timestamp, ≥ validFrom |
| `image_prompts` | N/A | Solo sugerencias para el admin |

---

## Apéndice C — Códigos de Error de Validación

| Code | Mensaje | Suggested Fix |
|---|---|---|
| `REQUIRED_FIELD` | Campo "{field}" es obligatorio | Agregá el campo con un valor válido |
| `INVALID_TYPE` | "{field}" debe ser {expected}, recibido {actual} | Cambiá el tipo del valor |
| `DUPLICATE_SKU_IN_BATCH` | SKU "{sku}" duplicado en posiciones {pos1} y {pos2} | Usá SKUs únicos para cada producto |
| `SKU_NOT_FOUND` | SKU "{sku}" no existe para actualizar | Verificá el SKU o cambiá action a "create" |
| `SKU_EXISTS` | SKU "{sku}" ya existe (action=create) | Cambiá action a "update" o usá otro SKU |
| `PRICE_INVALID` | Precio debe ser mayor a 0 | Corregí el precio |
| `STOCK_NEGATIVE` | Stock no puede ser negativo | Usá 0 o un valor positivo |
| `STOCK_ZERO` | Stock en 0 — producto no disponible | Considerá agregar stock (warning) |
| `DISCOUNT_EXCEEDS_PRICE` | Precio con descuento ≥ precio original | El descuento debe ser menor al precio |
| `CATEGORY_NOT_FOUND` | Categoría "{name}" no existe | Se creará automáticamente (warning) |
| `PLAN_LIMIT_EXCEEDED` | Excede {max} productos del plan | Reducí la cantidad o upgrade de plan |
| `BATCH_LIMIT_EXCEEDED` | Máximo {max} lotes por día alcanzado | Intentá mañana o upgrade de plan |
| `INVALID_CURRENCY` | Moneda "{val}" no soportada | Usá ARS o USD |
| `DATE_RANGE_INVALID` | Fecha inicio posterior a fecha fin | Corregí las fechas de promoción |
| `SEO_TITLE_TOO_LONG` | Título SEO excede 65 chars | Acortá a 65 caracteres |
| `SEO_DESC_TOO_LONG` | Descripción SEO excede 160 chars | Acortá a 160 caracteres |
| `NAME_TOO_SHORT` | Nombre menor a 3 caracteres | Usá un nombre más descriptivo |
| `HTML_IN_DESCRIPTION` | Se detectó HTML en la descripción | Usá texto plano (warning) |

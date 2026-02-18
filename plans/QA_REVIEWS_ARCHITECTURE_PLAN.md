# NovaVision — Plan Ejecutable: Q&A + Reviews por Producto

> **Autor:** Copilot Agent (Principal Engineer)  
> **Fecha:** 2026-02-17  
> **Estado:** PLAN — No implementar sin aprobación del TL  
> **Rama destino:** `feature/automatic-multiclient-onboarding` (API) | `develop` (Web)

---

## 1. Resumen Ejecutivo

Se propone implementar dos subsistemas nuevos sobre la plataforma multi-tenant existente:

| Feature | Descripción | Planes habilitados |
|---------|-------------|-------------------|
| **Q&A por producto** | Preguntas públicas por producto con respuestas del admin. Moderación con soft-delete y placeholders. | Growth, Enterprise |
| **Reviews/Calificación** | Reseñas (1–5 estrellas) con cuerpo de texto, badge "compra verificada", y respuesta del admin. Una review por producto por usuario por tenant. | Growth, Enterprise |

**Principios irrenunciables:**
- Multi-tenant: `client_id` obligatorio en cada tabla, RLS estricto, filtros en backend.
- Plan gating: Starter no ve ni puede usar nada (UI + API bloqueados).
- Performance PDP: Carga 100% lazy — render del producto no depende de Q&A/Reviews.
- Privacidad: Solo `display_name` snapshot; nunca email/teléfono/ID externo.
- Moderación: Soft-delete con placeholder público + contenido visible para admin/autor.
- Verified purchase: Validación eficiente contra el JSONB `orders.order_items`.

---

## 2. Auditoría del Estado Actual — Hallazgos

### 2.1 Schema relevante (Backend/Multicliente DB)

| Tabla/Columna | Hallazgo | Impacto |
|---------------|----------|---------|
| `orders.order_items` | **Columna JSONB**, no tabla relacional. Array de `{ product_id, name, quantity, unit_price }`. La tabla relacional `order_items` existe con RLS pero **no se usa en código**. | Verificar compra = query JSONB con operador `@>` o función |
| `orders.status` / `payment_status` | Status de orden/pago como text. `payment_status = 'approved'` indica pago confirmado. | Condición para "verified purchase" |
| `users` | Campos `first_name`, `last_name`, `personal_info` (JSONB con `firstName`, `lastName`). **No existe `display_name`** dedicado. | Snapshot de display_name al crear Q/review |
| `clients.plan_key` | CHECK constraint: `'starter'`, `'growth'`, `'enterprise'`. | Gating directo |
| `clients.feature_overrides` | JSONB para override por cliente individual. | Permite habilitar/deshabilitar Q&A/Reviews por tienda |
| `products.id` / `products.client_id` | UUID. **No hay `idx_products_client_id` explícito.** | Necesario como FK target. Crear índice. |

### 2.2 Plan Gating existente

- **Mecanismo:** `@PlanFeature('feature.id')` + `PlanAccessGuard` en controllers.
- **Feature Catalog:** `src/plans/featureCatalog.ts` — 34 features con status `live`/`beta`/`planned`.
- **Error response:** `ForbiddenException({ code: 'FEATURE_GATED', required_plan: 'growth', message })`.
- **Override por cliente:** `clients.feature_overrides[featureId]` (boolean) tiene prioridad sobre catálogo.

### 2.3 Riesgos identificados

| # | Riesgo | Mitigación |
|---|--------|-----------|
| R1 | `order_items` es JSONB — queries de verificación no indexables con btree estándar | GIN index + RPC helper |
| R2 | No hay `display_name` en users — riesgo de inconsistencia si el user cambia nombre | Snapshot inmutable al crear question/review |
| R3 | Falta `idx_products_client_id` e `idx_orders_client_id` | Crear en misma migración |
| R4 | La tabla `order_items` relacional existe pero no se usa — confusión futura | Documentar explícitamente, no depender de ella |
| R5 | Doble submit / spam en Q&A | Rate limit + idempotency key |

---

## 3. Decisiones de Diseño

### 3.1 Q&A: ¿Single-table o Thread+Messages?

| Opción | Pros | Contras |
|--------|------|---------|
| **A) Single table `product_questions`** con `parent_id` para respuestas | Simple, una sola tabla, queries directas | Limita a 1 nivel de profundidad (pregunta → respuesta). Para Q&A de producto es suficiente. |
| B) Dos tablas `question_threads` + `question_messages` | Soporta conversaciones multi-mensaje | Over-engineering para Q&A de producto. Complejidad innecesaria. |

**Decisión: Opción A — Single table con `parent_id`.**  
Justificación: En Q&A de e-commerce, el patrón es estrictamente pregunta → respuesta(s) del vendedor. No hay conversaciones. Un solo nivel de `parent_id` cubre el caso al 100%. Si en el futuro se necesitan threads, migrar a un `type` column es trivial.

### 3.2 Reviews: Modelo

**Decisión: Tabla `product_reviews` independiente.**  
- Una review por `(client_id, product_id, user_id)` — UNIQUE constraint.
- `rating` INT CHECK 1–5.
- `admin_reply` TEXT nullable + `admin_reply_at` para respuesta inline del admin.
- `verified_purchase` BOOLEAN computado al insertar (no editable).

### 3.3 Verified Purchase: ¿Cómo validar?

| Opción | Performance | Ruptura |
|--------|------------|---------|
| A) Query sobre `orders` con `order_items @> '[{"product_id":"..."}]'` + GIN index | Buena con GIN. ~50ms worst case | Cero ruptura. Solo agregar GIN index |
| B) Normalizar `order_items` a tabla relacional y popular retroactivamente | Excelente con btree FK | **Alta ruptura** — requiere migración de datos, cambiar mercadopago.service, doble write |
| C) Tabla helper `user_purchased_products` derivada al confirmar pago | Excelente query, O(1) lookup | Ruptura media — trigger/hook en flujo de pago |

**Decisión: Opción A (JSONB + GIN) como P0 + Opción C como P1.**

**Justificación:**
- Opción A es zero-breaking-change: solo agrega un GIN index. La query `orders.order_items @> '[{"product_id":"uuid"}]'::jsonb` es eficiente con GIN.
- P1 — cuando haya volumen — se agrega la tabla `user_purchased_products` con un trigger `AFTER UPDATE ON orders WHERE payment_status = 'approved'`. Se backfill con script una sola vez.
- Opción B es demasiado invasiva para el flujo de checkout existente.

### 3.4 Display Name — Snapshot

**Decisión:** Cada `product_questions` y `product_reviews` almacena `display_name` TEXT NOT NULL al momento de creación.  
- Se construye como: `COALESCE(users.first_name, (users.personal_info->>'firstName'), 'Usuario') || ' ' || LEFT(COALESCE(users.last_name, (users.personal_info->>'lastName'), ''), 1) || '.'`
- Ejemplo: "Juan P." — nunca revela apellido completo.
- Es inmutable después de creación. Si el usuario cambia nombre, las Q&A/reviews antiguas conservan el original.

### 3.5 Soft Delete y Moderación

**Decisión:** Campo `moderation_status` con estados:

```
published  → (default) visible para todos
hidden     → admin lo ocultó: visible solo para admin + autor; placeholder para el resto
archived   → autor lo archivó: invisible para público; visible para admin; autor puede restaurar
```

Campos de auditoría: `moderated_by` (UUID admin), `moderated_at` (timestamptz), `moderation_reason` (TEXT nullable).

**Placeholder público:** Cuando `moderation_status = 'hidden'`:
- Para público: `"Esta pregunta fue eliminada por el administrador"`
- Para admin: contenido original + badge "Oculta" + datos de moderación
- Para autor: contenido original + badge "Eliminada por el administrador" + motivo (si se proporcionó)

---

## 4. Propuesta de Schema (DDL — Pseudo-migraciones)

### 4.1 Tabla `product_questions`

```sql
-- Migration: BACKEND_XXX_create_product_questions.sql

CREATE TABLE public.product_questions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id       UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    parent_id       UUID REFERENCES public.product_questions(id) ON DELETE CASCADE,
    
    -- Contenido
    body            TEXT NOT NULL CHECK (char_length(body) BETWEEN 10 AND 2000),
    display_name    TEXT NOT NULL DEFAULT 'Usuario',
    
    -- Estado
    status          TEXT NOT NULL DEFAULT 'open'
                    CHECK (status IN ('open', 'answered', 'resolved')),
    moderation_status TEXT NOT NULL DEFAULT 'published'
                    CHECK (moderation_status IN ('published', 'hidden', 'archived')),
    
    -- Moderación
    moderated_by    UUID REFERENCES public.users(id),
    moderated_at    TIMESTAMPTZ,
    moderation_reason TEXT,
    
    -- Timestamps
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_activity_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Constraints
    CONSTRAINT fk_parent_same_product CHECK (
        parent_id IS NULL OR parent_id != id
    )
);

-- Comentarios
COMMENT ON TABLE public.product_questions IS 'Q&A por producto. parent_id=NULL → pregunta; parent_id set → respuesta';
COMMENT ON COLUMN public.product_questions.display_name IS 'Snapshot del nombre del autor al momento de crear. Inmutable.';
COMMENT ON COLUMN public.product_questions.moderation_status IS 'published=visible, hidden=admin borró (placeholder), archived=autor archivó';
```

### 4.2 Tabla `product_reviews`

```sql
-- Migration: BACKEND_XXX_create_product_reviews.sql

CREATE TABLE public.product_reviews (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    client_id       UUID NOT NULL REFERENCES public.clients(id) ON DELETE CASCADE,
    product_id      UUID NOT NULL REFERENCES public.products(id) ON DELETE CASCADE,
    user_id         UUID NOT NULL REFERENCES public.users(id) ON DELETE SET NULL,
    
    -- Review
    rating          SMALLINT NOT NULL CHECK (rating BETWEEN 1 AND 5),
    title           TEXT CHECK (title IS NULL OR char_length(title) BETWEEN 3 AND 200),
    body            TEXT CHECK (body IS NULL OR char_length(body) BETWEEN 10 AND 3000),
    display_name    TEXT NOT NULL DEFAULT 'Usuario',
    verified_purchase BOOLEAN NOT NULL DEFAULT FALSE,
    
    -- Estado
    moderation_status TEXT NOT NULL DEFAULT 'published'
                    CHECK (moderation_status IN ('published', 'hidden', 'pending')),
    
    -- Respuesta del admin
    admin_reply     TEXT CHECK (admin_reply IS NULL OR char_length(admin_reply) BETWEEN 5 AND 2000),
    admin_reply_by  UUID REFERENCES public.users(id),
    admin_reply_at  TIMESTAMPTZ,
    
    -- Moderación
    moderated_by    UUID REFERENCES public.users(id),
    moderated_at    TIMESTAMPTZ,
    moderation_reason TEXT,
    
    -- Timestamps
    created_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    -- Una review por producto por usuario por tenant
    CONSTRAINT uq_review_per_user_product UNIQUE (client_id, product_id, user_id)
);

COMMENT ON TABLE public.product_reviews IS 'Reviews/calificaciones de productos. Una por usuario por producto por tenant.';
COMMENT ON COLUMN public.product_reviews.verified_purchase IS 'TRUE si el usuario compró el producto (validado al crear via orders).';
```

### 4.3 Tabla `product_review_aggregates` (Materialización)

```sql
-- Migration: BACKEND_XXX_create_review_aggregates.sql

CREATE TABLE public.product_review_aggregates (
    client_id       UUID NOT NULL,
    product_id      UUID NOT NULL,
    avg_rating      NUMERIC(3,2) NOT NULL DEFAULT 0,
    review_count    INTEGER NOT NULL DEFAULT 0,
    rating_1        INTEGER NOT NULL DEFAULT 0,
    rating_2        INTEGER NOT NULL DEFAULT 0,
    rating_3        INTEGER NOT NULL DEFAULT 0,
    rating_4        INTEGER NOT NULL DEFAULT 0,
    rating_5        INTEGER NOT NULL DEFAULT 0,
    question_count  INTEGER NOT NULL DEFAULT 0,
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT now(),
    
    PRIMARY KEY (client_id, product_id)
);

COMMENT ON TABLE public.product_review_aggregates IS 
  'Agregados pre-calculados para PDP. Actualizado por trigger o servicio al publicar/ocultar review/question.';
```

### 4.4 GIN Index para Verified Purchase (sobre orders)

```sql
-- Migration: BACKEND_XXX_gin_order_items_product_id.sql

-- GIN index para buscar rápidamente si un product_id está en order_items JSONB
CREATE INDEX IF NOT EXISTS idx_orders_order_items_gin
    ON public.orders USING GIN (order_items jsonb_path_ops);

-- Índice compuesto para la query de verified purchase
-- Query típica: SELECT 1 FROM orders 
--   WHERE client_id=$1 AND user_id=$2 AND payment_status='approved' 
--   AND order_items @> '[{"product_id":"..."}]'
CREATE INDEX IF NOT EXISTS idx_orders_client_user_paid
    ON public.orders (client_id, user_id)
    WHERE payment_status = 'approved';
```

### 4.5 RPC helper para Verified Purchase

```sql
-- Migration: BACKEND_XXX_rpc_has_purchased_product.sql

CREATE OR REPLACE FUNCTION public.has_purchased_product(
    p_client_id UUID,
    p_user_id UUID,
    p_product_id UUID
) RETURNS BOOLEAN
LANGUAGE sql STABLE SECURITY DEFINER
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.orders
        WHERE client_id = p_client_id
          AND user_id = p_user_id
          AND payment_status = 'approved'
          AND order_items @> ('[{"product_id":"' || p_product_id::text || '"}]')::jsonb
    );
$$;

COMMENT ON FUNCTION public.has_purchased_product IS 
  'Verifica si un usuario tiene una compra aprobada que contenga el product_id dado.';
```

---

## 5. Índices

### 5.1 Índices para `product_questions`

```sql
-- Listado público de preguntas por producto (PDP)
CREATE INDEX idx_pq_product_public 
    ON product_questions (client_id, product_id, created_at DESC)
    WHERE parent_id IS NULL AND moderation_status = 'published';

-- Respuestas a una pregunta
CREATE INDEX idx_pq_answers 
    ON product_questions (parent_id, created_at ASC)
    WHERE parent_id IS NOT NULL;

-- Preguntas pendientes de responder (admin dashboard)
CREATE INDEX idx_pq_admin_pending 
    ON product_questions (client_id, status, last_activity_at DESC)
    WHERE parent_id IS NULL AND status = 'open';

-- Mis preguntas (perfil usuario)
CREATE INDEX idx_pq_user 
    ON product_questions (client_id, user_id, created_at DESC)
    WHERE parent_id IS NULL;

-- FK lookup
CREATE INDEX idx_pq_product_id ON product_questions (product_id);
```

### 5.2 Índices para `product_reviews`

```sql
-- Listado público de reviews por producto (PDP)
CREATE INDEX idx_pr_product_public 
    ON product_reviews (client_id, product_id, created_at DESC)
    WHERE moderation_status = 'published';

-- Mis reviews (perfil usuario)
CREATE INDEX idx_pr_user 
    ON product_reviews (client_id, user_id, created_at DESC);

-- Admin: reviews pendientes/reportadas
CREATE INDEX idx_pr_admin_moderation 
    ON product_reviews (client_id, moderation_status, created_at DESC)
    WHERE moderation_status != 'published';

-- FK lookup
CREATE INDEX idx_pr_product_id ON product_reviews (product_id);
```

### 5.3 Índices faltantes (pre-existentes que crear)

```sql
-- Estos NO existen y son necesarios para el sistema general:
CREATE INDEX IF NOT EXISTS idx_orders_client_id ON public.orders (client_id);
CREATE INDEX IF NOT EXISTS idx_products_client_id ON public.products (client_id);
```

---

## 6. RLS / Políticas

### 6.1 `product_questions`

```sql
-- Habilitar RLS
ALTER TABLE public.product_questions ENABLE ROW LEVEL SECURITY;

-- 1. Server bypass (service_role)
CREATE POLICY "pq_server_bypass" ON product_questions
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- 2. SELECT público del tenant (solo published + preguntas raíz con respuestas)
CREATE POLICY "pq_select_tenant" ON product_questions
    FOR SELECT
    USING (
        client_id = current_client_id()
        AND (
            moderation_status = 'published'                    -- publicadas: todos
            OR (moderation_status IN ('hidden', 'archived') AND user_id = auth.uid())  -- ocultas: solo autor
            OR is_admin()                                      -- admin: todo
        )
    );

-- 3. INSERT por usuarios autenticados del tenant
CREATE POLICY "pq_insert_user" ON product_questions
    FOR INSERT
    WITH CHECK (
        client_id = current_client_id()
        AND user_id = auth.uid()
    );

-- 4. UPDATE por admin del tenant (moderar, responder, cambiar status)
CREATE POLICY "pq_update_admin" ON product_questions
    FOR UPDATE
    USING (client_id = current_client_id() AND is_admin())
    WITH CHECK (client_id = current_client_id() AND is_admin());

-- 5. UPDATE por autor (solo archivar su propia pregunta)
CREATE POLICY "pq_update_owner_archive" ON product_questions
    FOR UPDATE
    USING (
        client_id = current_client_id()
        AND user_id = auth.uid()
        AND parent_id IS NULL  -- solo preguntas raíz
    )
    WITH CHECK (
        client_id = current_client_id()
        AND user_id = auth.uid()
        AND moderation_status = 'archived'  -- solo puede archivar
    );

-- 6. DELETE -> NO permitido (soft delete only)
-- No se crea policy de DELETE. Todo es soft-delete via moderation_status.
```

### 6.2 `product_reviews`

```sql
ALTER TABLE public.product_reviews ENABLE ROW LEVEL SECURITY;

-- 1. Server bypass
CREATE POLICY "pr_server_bypass" ON product_reviews
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');

-- 2. SELECT: published para todos del tenant; hidden para admin y autor
CREATE POLICY "pr_select_tenant" ON product_reviews
    FOR SELECT
    USING (
        client_id = current_client_id()
        AND (
            moderation_status = 'published'
            OR user_id = auth.uid()
            OR is_admin()
        )
    );

-- 3. INSERT: usuario autenticado del tenant (UNIQUE constraint previene duplicados)
CREATE POLICY "pr_insert_user" ON product_reviews
    FOR INSERT
    WITH CHECK (
        client_id = current_client_id()
        AND user_id = auth.uid()
    );

-- 4. UPDATE admin (moderar, responder)
CREATE POLICY "pr_update_admin" ON product_reviews
    FOR UPDATE
    USING (client_id = current_client_id() AND is_admin())
    WITH CHECK (client_id = current_client_id() AND is_admin());

-- 5. UPDATE owner (editar solo body/rating mientras moderation_status='published')
CREATE POLICY "pr_update_owner" ON product_reviews
    FOR UPDATE
    USING (
        client_id = current_client_id()
        AND user_id = auth.uid()
        AND moderation_status = 'published'
    )
    WITH CHECK (
        client_id = current_client_id()
        AND user_id = auth.uid()
    );

-- 6. No DELETE — soft delete only
```

### 6.3 `product_review_aggregates`

```sql
ALTER TABLE public.product_review_aggregates ENABLE ROW LEVEL SECURITY;

-- Solo lectura pública del tenant
CREATE POLICY "pra_select_tenant" ON product_review_aggregates
    FOR SELECT
    USING (client_id = current_client_id());

-- Escritura solo service_role (actualizaciones por trigger/service)
CREATE POLICY "pra_server_bypass" ON product_review_aggregates
    FOR ALL
    USING (auth.role() = 'service_role')
    WITH CHECK (auth.role() = 'service_role');
```

---

## 7. Feature Catalog — Nuevas Entries

```typescript
// Agregar a src/plans/featureCatalog.ts

{
  id: 'storefront.product_qa',
  title: 'Preguntas y Respuestas por producto',
  category: 'storefront',
  surfaces: ['storefront', 'client_dashboard', 'api_only'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'planned',
  evidence: [],
},
{
  id: 'storefront.product_reviews',
  title: 'Reviews y calificación por producto',
  category: 'storefront',
  surfaces: ['storefront', 'client_dashboard', 'api_only'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'planned',
  evidence: [],
},
```

---

## 8. API Contracts (NestJS)

### 8.1 Q&A Endpoints

#### `GET /products/:productId/questions`
Listado público de preguntas con respuestas.

```
Auth: Opcional (anónimo puede leer)
Plan gate: @PlanFeature('storefront.product_qa')
Headers: x-tenant-slug o resolución por host
Query params:
  - cursor: string (uuid, última question.id de página anterior)
  - limit: number (default 10, max 50)
  - search: string (opcional, busca en body con ILIKE)

Response 200:
{
  "data": [
    {
      "id": "uuid",
      "body": "¿Viene en color rojo?",
      "display_name": "Juan P.",
      "status": "answered",
      "created_at": "2026-02-17T...",
      "answers": [
        {
          "id": "uuid",
          "body": "Sí, disponible en rojo y azul.",
          "display_name": "TiendaX",  // nombre de la tienda para answers de admin
          "is_admin_answer": true,
          "created_at": "2026-02-17T..."
        }
      ],
      // Solo si moderation_status='hidden' y user es el autor:
      "is_hidden": true,
      "moderation_reason": "Contenido inapropiado"
    }
  ],
  "next_cursor": "uuid-or-null",
  "total_count": 42  // solo en primer request (cursor=null)
}

Response 200 (placeholder si pregunta hidden, no es autor ni admin):
{
  "id": "uuid",
  "body": null,
  "placeholder": "Esta pregunta fue eliminada por el administrador",
  "display_name": null,
  "status": "hidden",
  "created_at": "2026-02-17T...",
  "answers": []
}

Errores:
  403: { code: 'FEATURE_GATED', required_plan: 'growth' }
  404: Producto no encontrado
```

#### `POST /products/:productId/questions`
Crear una pregunta.

```
Auth: Requerido (Bearer JWT)
Plan gate: @PlanFeature('storefront.product_qa')
Rate limit: 5 preguntas por minuto por usuario

Request body:
{
  "body": "¿Viene en talle L?"   // 10-2000 chars, sanitizado (strip HTML)
}

Response 201:
{
  "id": "uuid",
  "body": "¿Viene en talle L?",
  "display_name": "Maria G.",
  "status": "open",
  "created_at": "..."
}

Errores:
  400: Body inválido (muy corto, muy largo, XSS detectado)
  401: No autenticado
  403: FEATURE_GATED
  404: Producto no existe
  429: Rate limit excedido
```

#### `POST /questions/:questionId/answers`
Responder a una pregunta (admin only).

```
Auth: Requerido (admin del tenant)
Plan gate: @PlanFeature('storefront.product_qa')

Request body:
{
  "body": "Sí, disponible en L y XL"   // 10-2000 chars
}

Response 201:
{
  "id": "uuid",
  "body": "Sí, disponible en L y XL",
  "display_name": "TiendaX",
  "is_admin_answer": true,
  "created_at": "..."
}

Side effects:
  - question.status → 'answered'
  - question.last_activity_at → now()

Errores:
  403: No es admin / FEATURE_GATED
  404: Pregunta no encontrada
```

#### `PATCH /questions/:questionId/moderate`
Moderar una pregunta (admin).

```
Auth: Requerido (admin)

Request body:
{
  "action": "hide" | "restore" | "resolve",
  "reason": "Contenido inapropiado"  // opcional, recomendado para 'hide'
}

Response 200:
{
  "id": "uuid",
  "moderation_status": "hidden",
  "moderated_at": "...",
  "moderation_reason": "Contenido inapropiado"
}

Side effects para 'hide':
  - moderation_status → 'hidden'
  - moderated_by → admin.id
  - moderated_at → now()
  - Todas las respuestas (children) también se ocultan

Side effects para 'restore':
  - moderation_status → 'published'
  - moderated_by/at/reason se conservan (auditoría)

Side effects para 'resolve':
  - status → 'resolved'
  - last_activity_at → now()
```

#### `DELETE /questions/:questionId` (Autor archiva su pregunta)
```
Auth: Requerido (autor de la pregunta)
Response 204
Side effects: moderation_status → 'archived'
Restricción: Solo si parent_id IS NULL (preguntas raíz)
Idempotente: Si ya está archived → 204 sin cambios
```

### 8.2 Reviews Endpoints

#### `GET /products/:productId/reviews`
```
Auth: Opcional
Plan gate: @PlanFeature('storefront.product_reviews')

Query params:
  - cursor: uuid
  - limit: number (default 10, max 50)
  - sort: 'recent' | 'top' | 'lowest' (default 'recent')
  - rating: 1|2|3|4|5 (filtro opcional)
  - verified_only: boolean (default false)

Response 200:
{
  "data": [
    {
      "id": "uuid",
      "rating": 5,
      "title": "Excelente producto",
      "body": "La calidad es muy buena...",
      "display_name": "Carlos M.",
      "verified_purchase": true,
      "created_at": "...",
      "admin_reply": "¡Gracias Carlos!",
      "admin_reply_at": "..."
    }
  ],
  "aggregates": {
    "avg_rating": 4.3,
    "review_count": 28,
    "rating_distribution": { "1": 2, "2": 1, "3": 3, "4": 8, "5": 14 }
  },
  "next_cursor": "uuid-or-null",
  "user_review": {   // solo si está autenticado
    "id": "uuid",     // review existente del usuario (null si no tiene)
    "can_review": true,  // true si tiene compra verificada y no tiene review
    "has_purchased": true
  }
}
```

#### `POST /products/:productId/reviews`
```
Auth: Requerido
Plan gate: @PlanFeature('storefront.product_reviews')
Rate limit: 3 reviews por hora por usuario

Request body:
{
  "rating": 5,          // 1-5, required
  "title": "Excelente", // 3-200 chars, opcional
  "body": "..."         // 10-3000 chars, opcional (pero recomendado)
}

Validaciones backend:
  1. verified_purchase = has_purchased_product(client_id, user_id, product_id)
     → Si FALSE: se permite crear pero verified_purchase=false
     → UI puede decidir si bloquear (policy: definir)
  2. UNIQUE constraint (client_id, product_id, user_id) → 409 si ya existe

Response 201:
{
  "id": "uuid",
  "rating": 5,
  "title": "Excelente",
  "body": "...",
  "display_name": "Carlos M.",
  "verified_purchase": true,
  "created_at": "..."
}

Errores:
  400: Datos inválidos
  401: No autenticado
  403: FEATURE_GATED
  404: Producto no existe
  409: Ya existe review del usuario para este producto
```

#### `PATCH /reviews/:reviewId`
Editar review propia (solo si published).
```
Auth: Requerido (autor)
Request body: { rating?, title?, body? }
Response 200: review actualizada
Restricción: Solo moderation_status='published'
```

#### `POST /reviews/:reviewId/reply`
Admin responde a review.
```
Auth: Admin required
Request body: { body: string }
Response 200: review con admin_reply actualizado
Side effects: admin_reply, admin_reply_by, admin_reply_at
```

#### `PATCH /reviews/:reviewId/moderate`
Admin modera review.
```
Auth: Admin required
Request body: { action: 'hide'|'restore', reason?: string }
Response 200: review con moderation_status actualizado
```

### 8.3 Aggregates Endpoint

#### `GET /products/:productId/social-proof`
Retorna SOLO los agregados (para lazy load mínimo en PDP).
```
Auth: Opcional
Plan gate: @PlanFeature('storefront.product_reviews')
Cache: 300s (5 min)

Response 200:
{
  "avg_rating": 4.3,
  "review_count": 28,
  "question_count": 15,
  "features_enabled": {
    "qa": true,
    "reviews": true
  }
}

Si plan no tiene acceso:
{
  "features_enabled": {
    "qa": false,
    "reviews": false
  }
}
```

### 8.4 User Dashboard (opcional — /me)

#### `GET /me/questions`
```
Auth: Requerido
Response: Lista de preguntas del usuario con status y respuestas
```

#### `GET /me/reviews`
```
Auth: Requerido
Response: Lista de reviews del usuario con status
```

---

## 9. UI/UX Flows

### 9.1 PDP — Estrategia de Carga Lazy

```
┌──────────────────────────────────────┐
│  PRODUCTO (render inmediato)          │
│  - Imagen, nombre, precio, desc      │
│  - CTA "Agregar al carrito"          │
│  - NO carga QA/Reviews               │
├──────────────────────────────────────┤
│  [★★★★☆ 4.3 (28 reviews)]           │  ← GET /social-proof (lazy, IntersectionObserver)
│  [💬 15 preguntas]                   │     Cache 5 min. Solo si plan tiene acceso.
├──────────────────────────────────────┤
│                                      │
│  ▼ Preguntas y Respuestas (collapsed)│  ← NO carga hasta click/expand
│                                      │
│  ▼ Reviews (collapsed)               │  ← NO carga hasta click/expand
│                                      │
└──────────────────────────────────────┘
```

**Trigger de carga:**
1. **IntersectionObserver** cuando la sección Q&A/Reviews entra en viewport → pre-fetch.
2. **Click en "Preguntas" o "Reviews"** → expand + fetch si no pre-fetched.
3. **Click en "Hacer una pregunta"** → abre modal; si no autenticado → redirect login.
4. **Input de búsqueda de preguntas (onFocus)** → fetch preguntas.

**Componentes React:**
```
<ProductPage>
  <ProductDetails />               // render inmediato
  <Suspense fallback={<Skeleton />}>
    <SocialProofBar />              // lazy, IntersectionObserver trigger
  </Suspense>
  <LazySection title="Preguntas y Respuestas" featureId="storefront.product_qa">
    <Suspense fallback={<QuestionsSkeleton />}>
      <QASection productId={id} />  // solo cuando se expande
    </Suspense>
  </LazySection>
  <LazySection title="Reviews" featureId="storefront.product_reviews">
    <Suspense fallback={<ReviewsSkeleton />}>
      <ReviewsSection productId={id} /> 
    </Suspense>
  </LazySection>
</ProductPage>
```

### 9.2 Q&A — Estados de UI

| Estado | Qué ve el público | Qué ve el admin | Qué ve el autor |
|--------|-------------------|-----------------|-----------------|
| `published` | Pregunta + respuestas | Pregunta + respuestas + badge "Publicada" + acciones | Pregunta + respuestas + "Eliminar" |
| `hidden` | Placeholder: "Eliminada por admin" | Contenido original + badge roja "Oculta" + motivo + "Restaurar" | Contenido original + badge "Eliminada por admin" + motivo |
| `archived` | No visible (filtrado) | Contenido + badge "Archivada por usuario" | Contenido + "Desarchivar" |

**UX "Preguntas similares":**
- Cuando el usuario escribe en "Hacer una pregunta" (>5 chars), se hace debounced search (300ms).
- Se muestran hasta 3 preguntas similares inline: "¿Esta es tu pregunta?"
- Si elige una existente → scroll a esa pregunta.
- Si no → "Enviar mi pregunta".

### 9.3 Reviews — Estados de UI

| Situación | UI |
|-----------|-----|
| Sin reviews, tiene compra | "Sé el primero en calificar" + form |
| Sin reviews, no compró | "Aún no hay reviews" (no muestra form) |
| Con reviews, tiene compra, no calificó | Form de review + listado |
| Con reviews, ya calificó | Badge "Tu review" + listado (puede editar) |
| Sin reviews, plan Starter | **Sección oculta completamente** |
| Admin logueado | Listado + botones moderar + responder |

**Form de review:**
1. Stars (1-5) — requerido
2. Título (opcional, placeholder "Resume tu experiencia")
3. Cuerpo (opcional, placeholder "¿Qué te pareció?")
4. Badge automático "✓ Compra verificada" si `verified_purchase`
5. Submit → optimistic UI → review aparece arriba con spinner

### 9.4 Admin Dashboard — Bandeja Q&A

```
┌──────────────────────────────────────────────────────┐
│  PREGUNTAS Y RESPUESTAS                               │
│                                                       │
│  Filtros: [Sin responder ▼] [Producto ▼] [Fecha ▼]  │
│                                                       │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 💬 ¿Viene en color rojo?                        │ │
│  │    Juan P. · hace 2h · Producto: Remera Basic   │ │
│  │    Estado: 🔴 Sin responder                      │ │
│  │    [Responder] [Resolver] [Ocultar]              │ │
│  └─────────────────────────────────────────────────┘ │
│  ┌─────────────────────────────────────────────────┐ │
│  │ 💬 ¿Cuánto tarda el envío?                      │ │
│  │    Maria G. · hace 1d · Producto: Campera Winter │ │
│  │    Estado: ✅ Respondida                          │ │
│  │    ↳ "Enviamos en 48hs hábiles" - TiendaX       │ │
│  │    [Resolver] [Ocultar]                          │ │
│  └─────────────────────────────────────────────────┘ │
│                                                       │
│  Métricas:                                            │
│  • Sin responder: 5                                   │
│  • Tiempo promedio de respuesta: 4.2h                 │
│  • Total preguntas este mes: 23                       │
└──────────────────────────────────────────────────────┘
```

**Admin Dashboard — Bandeja Reviews:**
Similar, con filtros por rating, estado de moderación, y acciones de moderar/responder.

### 9.5 Plan Gating en UI

```javascript
// Hook: useFeatureAccess('storefront.product_qa')
// Retorna: { enabled: boolean, requiredPlan: string | null }

// En PDP:
if (!qaEnabled) {
  // NO renderizar la sección de Q&A en absoluto
  return null;
}

// En Admin Dashboard:
if (!qaEnabled) {
  return <UpsellCard 
    title="Preguntas y Respuestas" 
    description="Disponible en planes Growth y Enterprise"
    cta="Mejorar plan"
  />;
}
```

---

## 10. Edge Cases + Checklist QA

### 10.1 Seguridad Multi-tenant

| # | Caso | Validación | Test |
|---|------|------------|------|
| E1 | Usuario de Cliente A intenta leer preguntas de Cliente B | RLS `client_id = current_client_id()` + filtro en service | E2E: login como user-A, request con tenant-B → 0 results |
| E2 | Admin de Cliente A intenta moderar pregunta de Cliente B | RLS + guard `client_id` match | Unit: mock clientId diferente → 404 |
| E3 | Usuario sin login intenta crear pregunta | Auth guard → 401 | Unit |
| E4 | Usuario de plan Starter intenta POST question | PlanAccessGuard → 403 FEATURE_GATED | Integration |

### 10.2 Privacidad

| # | Caso | Validación |
|---|------|-----------|
| E5 | display_name nunca muestra email | Snapshot se construye como "FirstName L." — sin email |
| E6 | display_name nunca muestra ID de usuario | ID no se expone en response DTO público |
| E7 | Usuario sin nombre → "Usuario" | `COALESCE(first_name, 'Usuario')` |
| E8 | Usuario cambia nombre después de preguntar | Snapshot inmutable — pregunta vieja conserva nombre viejo |

### 10.3 Moderación

| # | Caso | Validación |
|---|------|-----------|
| E9 | Admin oculta pregunta con respuestas | Respuestas (children) también se ocultan (CASCADE en moderation_status) |
| E10 | Admin restaura pregunta oculta | Pregunta + respuestas vuelven a published |
| E11 | Placeholder en listado público | Si hidden: body=null, placeholder="Eliminada por admin", display_name=null |
| E12 | Autor ve su pregunta oculta | body visible, badge "Eliminada por admin", motivo visible |
| E13 | Audit trail | moderated_by, moderated_at, moderation_reason persistidos |

### 10.4 Reviews

| # | Caso | Validación |
|---|------|-----------|
| E14 | Usuario intenta crear 2 reviews para mismo producto | UNIQUE constraint → 409 Conflict |
| E15 | Verified purchase con refund/cancel | `payment_status = 'approved'` — si se cambia a 'refunded', verified_purchase ya fue snapshotted. **Decisión: la review persiste, verified_purchase NO se revoca retroactivamente** |
| E16 | Producto eliminado | FK ON DELETE CASCADE → questions y reviews se eliminan. **Riesgo**: si se soft-delete el producto, Q&A queda huérfana. Mitigación: excluir productos deleted del listado de Q&A. |
| E17 | Rating promedio con 0 reviews | `avg_rating = 0, review_count = 0` — UI muestra "Sin calificaciones" |
| E18 | Doble submit (race condition) | Idempotency: UNIQUE constraint en reviews. Para questions: frontend envía `idempotency_key` (uuid v4), backend lo guarda y rechaza duplicados con 409. |

### 10.5 Performance

| # | Caso | Validación |
|---|------|-----------|
| E19 | PDP no debe degradarse con Q&A/Reviews | Carga lazy con Suspense. Endpoint PDP actual no cambia. |
| E20 | Producto con 1000+ preguntas | Cursor pagination, limit=10. GIN index para search. |
| E21 | Agregados (avg_rating, count) no deben ser N+1 | Tabla `product_review_aggregates` pre-computada. Cache 5min. |
| E22 | Search "preguntas similares" al escribir | Debounce 300ms + ILIKE truncado a 100 chars + limit 3 |

### 10.6 Migración/Deploy

| # | Caso | Validación |
|---|------|-----------|
| E23 | Deploy sin downtime | Tablas nuevas (additive). No modifica tablas existentes. Feature flag en off hasta deploy completo. |
| E24 | Rollback | DROP TABLE product_questions, product_reviews, product_review_aggregates — sin impacto en sistema existente |
| E25 | Feature catalog update | Agregar entries con `status: 'planned'` → cambiar a `'live'` cuando listo |

---

## 11. Trigger para Agregados (estrategia)

```sql
-- Opción recomendada: Trigger en lugar de materialización periódica
-- Se ejecuta AFTER INSERT/UPDATE/DELETE en product_reviews

CREATE OR REPLACE FUNCTION update_review_aggregates()
RETURNS TRIGGER AS $$
DECLARE
    v_client_id UUID;
    v_product_id UUID;
BEGIN
    -- Determinar client_id y product_id afectados
    v_client_id  := COALESCE(NEW.client_id, OLD.client_id);
    v_product_id := COALESCE(NEW.product_id, OLD.product_id);
    
    INSERT INTO product_review_aggregates (client_id, product_id, avg_rating, review_count,
        rating_1, rating_2, rating_3, rating_4, rating_5, updated_at)
    SELECT 
        v_client_id,
        v_product_id,
        COALESCE(AVG(rating), 0),
        COUNT(*),
        COUNT(*) FILTER (WHERE rating = 1),
        COUNT(*) FILTER (WHERE rating = 2),
        COUNT(*) FILTER (WHERE rating = 3),
        COUNT(*) FILTER (WHERE rating = 4),
        COUNT(*) FILTER (WHERE rating = 5),
        now()
    FROM product_reviews
    WHERE client_id = v_client_id
      AND product_id = v_product_id
      AND moderation_status = 'published'
    ON CONFLICT (client_id, product_id)
    DO UPDATE SET
        avg_rating   = EXCLUDED.avg_rating,
        review_count = EXCLUDED.review_count,
        rating_1     = EXCLUDED.rating_1,
        rating_2     = EXCLUDED.rating_2,
        rating_3     = EXCLUDED.rating_3,
        rating_4     = EXCLUDED.rating_4,
        rating_5     = EXCLUDED.rating_5,
        updated_at   = now();
    
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER trg_review_aggregates
    AFTER INSERT OR UPDATE OR DELETE ON product_reviews
    FOR EACH ROW EXECUTE FUNCTION update_review_aggregates();
```

**Para `question_count`:** trigger similar en `product_questions` solo incrementa/decrementa el contador en `product_review_aggregates`.

---

## 12. Plan de Implementación por Fases

### P0 — Fundamentos (Semana 1–2)

| Tarea | Entregable | Riesgo |
|-------|-----------|--------|
| Migración SQL: tablas, índices, RLS, trigger, RPC | 5 archivos SQL | Bajo — additive, sin romper nada |
| Feature catalog: agregar 2 entries | 1 archivo TS | Bajo |
| GIN index en orders.order_items | 1 SQL | Bajo — index CONCURRENTLY |
| Índices faltantes (orders.client_id, products.client_id) | 1 SQL | Bajo |
| Backend: módulos NestJS (controllers/services/DTOs) para Q&A + Reviews | ~8 archivos | Medio — integración con guards |
| Tests unitarios de services | ~4 archivos | Bajo |

**Rollback P0:** `DROP TABLE IF EXISTS product_questions, product_reviews, product_review_aggregates CASCADE;` + revert feature catalog entries.

### P1 — Frontend Storefront (Semana 2–3)

| Tarea | Entregable | Riesgo |
|-------|-----------|--------|
| `<LazySection>` genérico para PDP | 1 componente | Bajo |
| `<QASection>` + `<QuestionCard>` + `<AskQuestionModal>` | 3 componentes | Medio |
| `<ReviewsSection>` + `<ReviewCard>` + `<ReviewForm>` | 3 componentes | Medio |
| `<SocialProofBar>` (rating + counts) | 1 componente | Bajo |
| Hook `useFeatureAccess` (consulta plan del tenant) | 1 hook | Bajo |
| API client (hooks con SWR/react-query) | 2 hooks | Bajo |
| Gating UI para Starter (ocultar secciones) | N/A — conditional render | Bajo |

**Rollback P1:** Revert componentes — no impactan PDP existente (todo es additive/lazy).

### P2 — Admin Dashboard + Polish (Semana 3–4)

| Tarea | Entregable | Riesgo |
|-------|-----------|--------|
| Admin: Bandeja Q&A (filtros, acciones) | 2 componentes | Medio |
| Admin: Bandeja Reviews (filtros, moderar, responder) | 2 componentes | Medio |
| Admin: Métricas básicas (sin responder, avg response time) | 1 componente | Bajo |
| Tabla `user_purchased_products` (P1 de verified purchase optimization) | 1 SQL + trigger | Bajo |
| Tests E2E (multi-tenant isolation, plan gating) | ~5 specs | Medio |
| Documentación API | 1 doc | Bajo |
| UpsellCard para plan Starter en Admin | 1 componente | Bajo |

**Rollback P2:** Revert admin components — no impactan storefront.

---

## 13. Observabilidad

### Logs requeridos

| Evento | Level | Campos |
|--------|-------|--------|
| Pregunta creada | INFO | `clientId`, `productId`, `userId`, `questionId` |
| Pregunta moderada | WARN | `clientId`, `questionId`, `action`, `adminId`, `reason` |
| Review creada | INFO | `clientId`, `productId`, `userId`, `rating`, `verified` |
| Review moderada | WARN | `clientId`, `reviewId`, `action`, `adminId` |
| Verified purchase check | DEBUG | `clientId`, `userId`, `productId`, `result`, `queryTime` |
| Plan gate blocked | WARN | `clientId`, `planKey`, `featureId`, `endpoint` |
| Rate limit hit | WARN | `clientId`, `userId`, `endpoint`, `ip` |

### Métricas por tenant (dashboard admin)

- Preguntas totales / sin responder / este mes
- Reviews totales / promedio general / este mes
- Tiempo promedio de respuesta (first answer)
- % verified purchase en reviews

---

## 14. Diagrama de Arquitectura

```
                          ┌─────────────────────────────┐
                          │         PDP (Frontend)       │
                          │  ProductPage                 │
                          │    ├─ ProductDetails  ←──── GET /products/:id (existente, sin cambios)
                          │    ├─ SocialProofBar ←───── GET /products/:id/social-proof (lazy)
                          │    ├─ QASection      ←───── GET /products/:id/questions (lazy, on expand)
                          │    └─ ReviewsSection ←───── GET /products/:id/reviews (lazy, on expand)
                          └──────────────┬──────────────┘
                                         │
                          ┌──────────────▼──────────────┐
                          │      NestJS API              │
                          │                              │
                          │  ┌── AuthMiddleware          │
                          │  ├── TenantContextGuard      │
                          │  ├── PlanAccessGuard          │
                          │  │   └── @PlanFeature(...)    │
                          │  ├── QuestionsController      │
                          │  │   └── QuestionsService     │
                          │  ├── ReviewsController        │
                          │  │   └── ReviewsService       │
                          │  └── AggregatesController     │
                          └──────────────┬──────────────┘
                                         │
                          ┌──────────────▼──────────────┐
                          │   Supabase (Multicliente)    │
                          │                              │
                          │  ┌── product_questions       │
                          │  ├── product_reviews         │
                          │  ├── product_review_aggs     │
                          │  ├── orders (GIN on items)   │
                          │  └── RPC: has_purchased_*    │
                          └─────────────────────────────┘
```

---

## 15. Preguntas para Funcional/TL antes de implementar

1. **¿Permitir reviews sin compra verificada?** El plan actual las permite pero sin badge "Verificada". ¿O bloquear completamente si no compró?
2. **¿El autor puede borrar su review permanentemente** o solo archivarla?
3. **¿Notificación al admin cuando hay pregunta nueva?** (email/push/badge en dashboard)
4. **¿Notificación al usuario cuando su pregunta es respondida?** (email)
5. **¿Permitir imágenes/adjuntos en reviews?** (P2/P3, no incluido en este plan)
6. **¿Helpful/Not helpful votes en reviews?** (P2, no incluido)
7. **¿Report de abuso por usuarios?** (P2, no incluido)
8. **Custom domain stores: ¿algún cambio en el flujo de resolución de tenant?** No debería, el guard existente resuelve por host/slug.

---

*Fin del plan. Esperando aprobación del TL para iniciar P0.*

# Plan: AI Full Product Generation + AI Everywhere + Tour AI Integration

**Fecha:** 2026-03-18
**Estado:** Draft
**Repos afectados:** API, Web
**Ramas:** `feature/automatic-multiclient-onboarding` (API), `develop` (Web)

---

## Contexto y Problemas Actuales

### Problema 1: "Llenar con IA" genera solo descripción
El endpoint `POST /products/ai-fill` y su UI solo generan:
- `description` (texto)
- `photo` (opcional)

**Debería generar TODOS los campos del producto:** nombre comercial mejorado, descripción, precio sugerido, categoría sugerida, SKU sugerido, tags, filtros, material, etc. — exactamente como hace `ai-from-photo` pero sin imagen de input.

### Problema 2: UX incompleta del modal AI
- "Llenar con IA" está metido abajo en la sección de descripción, debería ser prominente arriba
- Falta la opción de "Mejorar producto con IA" en edición (que revise y mejore todos los labels)
- El botón "Llenar con IA" muestra "0 cr / Normal (1 cr) / Pro (3 cr)" de forma confusa

### Problema 3: Foto comercial desde contenido del producto
- En "Galería y assets" falta un botón para generar foto a partir del contenido del producto (nombre, descripción, categoría)
- Debería estar disponible tanto en creación como en edición
- Solo se activa si hay info suficiente del producto Y créditos disponibles

### Problema 4: Banco de imágenes vacío
- El MediaLibraryPicker no trae imágenes previas al cambio
- **Diagnóstico:** El componente y endpoint están correctos (`GET /media-library` filtra por `client_id`). Probable causa: las imágenes se subieron con un sistema anterior a `tenant_media` (estaban directamente en `products.image_url` como URLs de storage, no como registros en `tenant_media`). Las imágenes existentes no fueron migradas a la tabla `tenant_media`.

### Problema 5: Tours no incluyen IA
- Los tours existentes (banners, FAQs, logo, servicios, productos) no mencionan las features de IA
- QADashboard y ReviewsDashboard no tienen tour

### Problema 6: IA faltante en secciones
- **LogoSection**: sin IA (candidato: generar logo desde nombre/industria)
- **ServiceSection**: sin IA (candidato: mejorar títulos/descripciones)
- **Banners**: tiene IA pero el tour no lo menciona

---

## Bloque 1: API — Endpoint `ai-fill` Full Product Generation

### 1A: Nuevo prompt `PRODUCT_FILL_SYSTEM_PROMPT`

**Archivo:** `api/src/ai-generation/prompts/product-fill.ts` (nuevo)

El prompt debe instruir a la IA a generar un producto completo:

```
Sos un product manager de e-commerce. A partir del nombre y/o descripción básica,
generá una ficha de producto completa y optimizada para venta.

REGLAS:
- name: nombre comercial mejorado (max 80 chars), optimizado para SEO
- description: descripción de venta persuasiva (max 1500 chars)
- suggested_price: precio en ARS estimado (puede ser null si no es inferible)
- suggested_category: categoría del producto
- sku_suggestion: SKU sugerido basado en nombre/categoría (max 20 chars, alfanumérico)
- tags: hasta 5 tags relevantes para búsqueda
- material: material principal si es inferible (o null)
- filters: atributos key-value relevantes (color, tamaño, etc.)
- is_price_estimated: true si el precio es una estimación
- Español rioplatense natural
- NO inventar datos que no se puedan inferir razonablemente
- Respondé SOLO con JSON
```

**Respuesta esperada:**
```typescript
interface ProductFillResult {
  name: string;                          // Nombre comercial mejorado
  description: string;                   // Descripción persuasiva
  suggested_price: number | null;        // Precio ARS estimado
  suggested_category: string | null;     // Categoría sugerida
  sku_suggestion: string | null;         // SKU sugerido
  tags: string[];                        // Hasta 5 tags
  material: string | null;              // Material si inferible
  filters: Record<string, string>;      // Atributos (color, etc.)
  is_price_estimated: boolean;
}
```

### 1B: Modificar `aiProductFill` en service

**Archivo:** `api/src/ai-generation/ai-generation.service.ts`

Cambios:
1. Usar el nuevo `PRODUCT_FILL_SYSTEM_PROMPT` en vez del de descripción
2. Aceptar `description` como input adicional (descripción básica del usuario)
3. Retornar el `ProductFillResult` completo
4. Mantener generación de foto opcional (consumo de `ai_photo_product` adicional)

### 1C: Nuevo endpoint `POST /products/ai-improve`

**Archivo:** `api/src/ai-generation/ai-generation.controller.ts`

Nuevo endpoint para **modo edición** — "Mejorar producto con IA":
- Recibe `productId` como param
- Lee el producto existente de la BD
- Envía todos los campos actuales al prompt con instrucción de **mejorar** (no reescribir)
- Retorna `ProductFillResult` con las mejoras sugeridas
- Guard: `@RequireAiCredits('ai_product_description')`
- Consume 1 crédito `ai_product_description`

**Prompt:** Similar al de fill pero con instrucción de mejorar:
```
Tenés la ficha actual de un producto. Mejorá los labels para que sean más
comerciales y optimizados para conversión. Mantené los datos factuales pero
hacelos más atractivos para el comprador.
```

### 1D: Actualizar DTO `AiFillDto`

**Archivo:** `api/src/ai-generation/dto/ai-fill.dto.ts`

Agregar:
- `description?: string` — descripción básica del usuario (max 500 chars, opcional)

---

## Bloque 2: Web — Nuevo flujo "Llenar con IA" en ProductModal

### 2A: Reestructurar posición de AI Fill (Creación)

**Archivo:** `web/src/components/ProductModal/index.jsx`

**Estado actual:** Botón "Llenar con IA" está abajo en la sección de descripción (línea ~1008)

**Cambio:** Mover a un panel hero prominente arriba del formulario (después del header del modal, antes de "Información base"):

```jsx
{/* ── AI Fill Hero (solo creación) ── */}
{!isEditing && (
  <AiFillPanel>
    <AiFillHeader>
      <AiFillIcon>✨</AiFillIcon>
      <div>
        <h3>Crear producto con IA</h3>
        <p>Escribí el nombre o una descripción básica y la IA completa todo.</p>
      </div>
    </AiFillHeader>
    <AiFillInputs>
      <input placeholder="Nombre del producto *" ... />
      <textarea placeholder="Descripción básica (opcional)" ... />
      <label>
        <input type="checkbox" /> También generar foto comercial
        <small>Consume 1 crédito adicional de foto</small>
      </label>
    </AiFillInputs>
    <AiFillActions>
      <AiButton actionCode="ai_product_description" ... />
      <AiTierToggle actionCode="ai_product_description" ... />
    </AiFillActions>
  </AiFillPanel>
)}
```

**Resultado de AI Fill:** Abre un **preview panel** (no aplica directo) mostrando:
- Nombre sugerido vs input original
- Descripción generada
- Precio sugerido (si hay)
- Categoría sugerida
- SKU sugerido
- Tags
- Material
- Foto (si se pidió)
- Botón "Aplicar todo" / "Aplicar seleccionados" con checkboxes por campo

### 2B: "Mejorar producto con IA" (Edición)

**Archivo:** `web/src/components/ProductModal/index.jsx`

En modo edición (`isEditing`), en la misma posición hero pero con copy diferente:

```jsx
{isEditing && product?.id && (
  <AiImprovePanel>
    <h3>Mejorar producto con IA</h3>
    <p>La IA revisa tu producto y sugiere mejoras comerciales para vender más.</p>
    <AiButton
      actionCode="ai_product_description"
      label="Mejorar con IA"
      onClick={handleAiImprove}
      loading={aiImproveLoading}
      balance={getBalance('ai_product_description')}
    />
    <AiTierToggle ... />
  </AiImprovePanel>
)}
```

**Endpoint:** `POST /products/:id/ai-improve`

**Resultado:** Preview con diff (actual vs sugerido) por campo, con checkboxes para aceptar/rechazar cada mejora individualmente.

### 2C: Eliminar botones AI sueltos de la sección descripción

- **Creación:** Quitar "Llenar con IA" de la sección descripción (línea ~1008-1039) — ya está en el hero panel
- **Edición:** Quitar "Mejorar descripción con IA" de la sección descripción (línea ~990-1007) — reemplazado por "Mejorar producto con IA" en el hero
- Mantener "Crear desde foto" como está (es un flujo diferente, vision-based)

### 2D: Generar foto desde contenido del producto (Galería)

**Archivo:** `web/src/components/ProductModal/index.jsx`

En la sección "Galería y assets", agregar botón **tanto en creación como edición**:

```jsx
{/* Generar foto desde contenido (creación + edición) */}
{imageUrl.length < planLimits.maxImagesPerProduct && (
  <AiPhotoFromContent>
    <AiButton
      actionCode="ai_photo_product"
      label="Generar foto del producto"
      onClick={handleAiPhotoFromContent}
      loading={aiPhotoLoading}
      balance={getBalance('ai_photo_product')}
      disabled={!hasProductContent}  // Se activa solo si hay nombre+descripción
      size="sm"
    />
    <AiTierToggle actionCode="ai_photo_product" ... />
    <select>{PHOTO_STYLES}</select>
    {!hasProductContent && (
      <small>Completá al menos nombre y descripción para generar una foto.</small>
    )}
  </AiPhotoFromContent>
)}
```

**`hasProductContent`:** `!!watch('name')?.trim() && !!watch('description')?.trim()`

**En creación:** Usa los valores del formulario (nombre, descripción actuales)
**En edición:** Usa los valores del formulario + datos del producto existente

**Endpoint:** Reutiliza `POST /products/:id/ai-photo` (edición) o un nuevo endpoint `POST /products/ai-photo-from-content` (creación, sin product_id) que acepte `{ name, description, category_name, style, ai_tier }`.

### 2E: Costos de tokens clarificados

El panel AI debe mostrar claramente:
- **Solo texto:** Normal = 1 cr, Pro = 3 cr (de `ai_product_description`)
- **Con foto:** +1 cr Normal, +3 cr Pro (de `ai_photo_product`)
- **Total visible:** "Esta operación consumirá X créditos"

---

## Bloque 3: Migración de imágenes existentes a `tenant_media`

### 3A: Script de migración one-time

**Archivo:** `api/migrations/scripts/migrate_product_images_to_tenant_media.ts`

Script que:
1. Lee todos los `products` con `image_url` no vacío
2. Para cada imagen URL que no tenga registro en `tenant_media`:
   - Crea registro en `tenant_media` con `storage_key` extraído de la URL
   - Crea registro en `product_media` vinculando producto ↔ media
   - Genera variants si es posible (o marca como pending)
3. Logging detallado de migración
4. Idempotente (puede correrse múltiples veces sin duplicar)
5. Filtrado por `client_id` para multi-tenant safety

### 3B: Validación post-migración

- Verificar que `GET /media-library` retorna las imágenes migradas
- Verificar que MediaLibraryPicker las muestra correctamente
- Verificar que `excludeIds` funciona para no mostrar imágenes ya asignadas

---

## Bloque 4: IA en todas las secciones

### 4A: ServiceSection — Mejorar texto de servicios

**Archivos:**
- `api/src/ai-generation/ai-generation.controller.ts` — nuevo endpoint
- `api/src/ai-generation/ai-generation.service.ts` — nuevo método
- `web/src/components/admin/ServiceSection/index.jsx` — UI

**Endpoint:** `POST /services/:id/ai-improve`
- Guard: `@RequireAiCredits('ai_product_description')` (reutiliza action code)
- Recibe: servicio actual (title, description)
- Retorna: `{ title: string, description: string }` mejorados

**UI:**
- AiButton "Mejorar con IA" en el form de edición de cada servicio
- AiTierToggle para Normal/Pro
- Preview con diff antes de aplicar

### 4B: LogoSection — Generación de logo

**Archivos:**
- `api/src/ai-generation/ai-generation.controller.ts` — nuevo endpoint
- `api/src/ai-generation/ai-generation.service.ts` — nuevo método
- `web/src/components/admin/LogoSection/index.jsx` — UI

**Endpoint:** `POST /logos/ai-generate`
- Guard: `@RequireAiCredits('ai_photo_product')` (reutiliza action code de foto)
- Recibe: `{ store_name, industry?, style: 'modern'|'elegant'|'minimal'|'bold'|'playful' }`
- Retorna: `{ url: string, temp_key: string }`

**UI:**
- AiButton "Generar logo con IA" debajo del uploader actual
- Selector de estilo (5 opciones)
- AiTierToggle
- Preview con botón aceptar/rechazar

### 4C: Banners — Ya tiene IA, solo mejorar UX

**Archivo:** `web/src/components/admin/BannerSection/index.jsx`

Mejoras menores:
- Mostrar costo de tokens claramente en el botón
- Agregar sugerencia de prompt basada en Store DNA / productos destacados

### 4D: ContactSection, SocialLinks — Candidatos futuros (no este sprint)

Estos componentes son formularios simples (teléfono, email, redes sociales) donde la IA no aporta valor significativo. Se dejan fuera del scope.

---

## Bloque 5: Tours con IA

### 5A: Actualizar tour de productos

**Archivo:** `web/src/tour/definitions/products-crear-producto.js`

Agregar steps:
- "Crear producto con IA" — explicar el panel hero, input de nombre/descripción, checkbox foto
- "Mejorar producto con IA" — explicar que revisa y sugiere mejoras comerciales
- "Generar foto del producto" — explicar generación desde contenido en galería

Agregar `data-tour-target`:
- `product-ai-fill` en el panel hero de creación
- `product-ai-improve` en el panel hero de edición
- `product-ai-photo-gallery` en el botón de foto en galería

### 5B: Actualizar tour de banners

**Archivo:** `web/src/tour/definitions/banners-gestionar-banners.js`

Agregar step:
- "Generar banner con IA" — explicar prompt, estilos, preview

Agregar `data-tour-target`:
- `banners-ai-generate` en el botón/sección de generación AI

### 5C: Actualizar tour de FAQs

**Archivo:** `web/src/tour/definitions/faqs-preguntas-frecuentes.js`

Agregar steps:
- "Generar FAQs con IA" — explicar selección de productos, preview
- "Mejorar FAQ individual" — explicar botón de mejora en edición

Agregar `data-tour-target`:
- `faqs-ai-generate` en el botón de generación
- `faqs-ai-enhance` en el botón de mejora

### 5D: Crear tour para QADashboard

**Archivo nuevo:** `web/src/tour/definitions/qa-preguntas-clientes.js`

Steps:
1. Intro: "Acá vas a gestionar preguntas de tus clientes sobre productos"
2. Filtros de estado (pendiente, respondida, oculta)
3. Abrir thread / detalle de pregunta
4. "Sugerir respuesta con IA" — explicar AiButton + tier
5. Responder y enviar

Registrar en `tourRegistry.js`.

### 5E: Crear tour para ReviewsDashboard

**Archivo nuevo:** `web/src/tour/definitions/reviews-opiniones-clientes.js`

Steps:
1. Intro: "Acá gestionás las reseñas/opiniones de tus clientes"
2. Filtros (estado, rating)
3. Responder a una reseña
4. "Sugerir respuesta con IA" — explicar AiButton + tier
5. Moderación (aprobar, ocultar)

Registrar en `tourRegistry.js`.

### 5F: Actualizar tour de logo

**Archivo:** `web/src/tour/definitions/logo-configurar-logo.js`

Agregar step:
- "Generar logo con IA" — explicar estilos y preview

### 5G: Actualizar tour de servicios

**Archivo:** `web/src/tour/definitions/services-gestionar-servicios.js`

Agregar step:
- "Mejorar servicio con IA" — explicar mejora de texto

---

## Bloque 6: Pricing y Créditos

### Tabla de costos por operación

| Operación | Action Code | Normal | Pro |
|-----------|------------|--------|-----|
| Llenar producto (solo texto) | `ai_product_description` | 1 | 3 |
| Llenar producto (texto + foto) | `ai_product_description` + `ai_photo_product` | 1+1=2 | 3+3=6 |
| Mejorar producto | `ai_product_description` | 1 | 3 |
| Mejorar descripción | `ai_product_description` | 1 | 3 |
| Generar foto | `ai_photo_product` | 1 | 3 |
| Generar logo | `ai_photo_product` | 1 | 3 |
| Generar banner | `ai_banner_generation` | 1 | 3 |
| Generar FAQs | `ai_faq_generation` | 1 | 3 |
| Mejorar FAQ | `ai_faq_generation` | 1 | 3 |
| Sugerir respuesta Q&A | `ai_qa_answer` | 1 | 3 |
| Sugerir respuesta Review | `ai_qa_answer` | 1 | 3 |
| Mejorar servicio | `ai_product_description` | 1 | 3 |
| Crear desde foto (Vision) | `ai_photo_product` | 1 | 3 |

**Nota:** Los costos Normal/Pro se configuran en `ai_feature_pricing` en Admin DB. Los valores de arriba son los defaults actuales.

---

## Orden de Ejecución

| Prioridad | Bloque | Descripción | Esfuerzo |
|-----------|--------|-------------|----------|
| **P0** | 1A-1D | API: ai-fill full + ai-improve endpoint | Alto |
| **P0** | 2A-2E | Web: nuevo flujo ProductModal AI | Alto |
| **P1** | 3A-3B | Migración imágenes a tenant_media | Medio |
| **P1** | 4A | ServiceSection AI | Bajo |
| **P1** | 4B | LogoSection AI | Medio |
| **P2** | 5A-5G | Tours con IA (7 archivos) | Medio |
| **P2** | 4C | Banners UX improvements | Bajo |

---

## Archivos Clave (existentes a modificar)

| Archivo | Cambio |
|---------|--------|
| `api/src/ai-generation/ai-generation.service.ts` | Nuevo prompt full, método aiImprove |
| `api/src/ai-generation/ai-generation.controller.ts` | Endpoint ai-improve, update ai-fill |
| `api/src/ai-generation/dto/ai-fill.dto.ts` | Agregar campo description |
| `web/src/components/ProductModal/index.jsx` | Reestructurar AI panels |
| `web/src/components/admin/ServiceSection/index.jsx` | Agregar AI improve |
| `web/src/components/admin/LogoSection/index.jsx` | Agregar AI generate |
| `web/src/components/admin/BannerSection/index.jsx` | UX improvements |
| `web/src/tour/definitions/*.js` | 7 archivos de tour |
| `web/src/tour/tourRegistry.js` | Registrar 2 tours nuevos |

## Archivos Nuevos

| Archivo | Propósito |
|---------|-----------|
| `api/src/ai-generation/prompts/product-fill.ts` | Prompt full generation |
| `api/src/ai-generation/prompts/product-improve.ts` | Prompt improve product |
| `api/src/ai-generation/prompts/service-improve.ts` | Prompt improve service |
| `api/src/ai-generation/prompts/logo-generate.ts` | Prompt logo generation |
| `api/migrations/scripts/migrate_product_images_to_tenant_media.ts` | Migración one-time |
| `web/src/tour/definitions/qa-preguntas-clientes.js` | Tour Q&A |
| `web/src/tour/definitions/reviews-opiniones-clientes.js` | Tour Reviews |

---

## Validación

### API
- `npm run lint` — 0 errors
- `npm run typecheck` — pass
- `npm run build && ls -la dist/main.js`
- `POST /products/ai-fill` con `{ name, description }` retorna ficha completa
- `POST /products/:id/ai-improve` retorna mejoras
- `POST /services/:id/ai-improve` retorna mejoras
- `POST /logos/ai-generate` retorna imagen

### Web
- `npx vite build` — pass
- Creación de producto: panel hero AI Fill visible, genera todos los campos
- Edición de producto: panel hero "Mejorar con IA", muestra diff
- Galería: botón "Generar foto del producto" visible si hay contenido
- MediaLibraryPicker: muestra imágenes migradas
- Servicios: botón "Mejorar con IA" funciona
- Logo: botón "Generar logo con IA" funciona
- Tours: todos los pasos AI visibles y funcionales

### Pricing
- Tokens se descuentan correctamente según tabla de costos
- HTTP 402 se intercepta y muestra modal en todos los flujos
- Balance se actualiza post-operación

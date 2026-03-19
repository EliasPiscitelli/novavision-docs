# Plan: AI Image Features — 3 Flujos IA de Producto + Banners IA

## Fecha: 2026-03-18
## Estado: Pendiente de aprobación (v2 — post-review)
## Última revisión: 2026-03-18 — Resolución de 16 gaps identificados

---

## Contexto

La infraestructura de AI Credits ya soporta `ai_photo_product` (pricing, welcome credits, addon packs), pero **no existe implementación**. Este plan cubre **4 features de imágenes IA**:

| # | Feature | Trigger en UI | Qué hace | API OpenAI |
|---|---------|---------------|----------|------------|
| 1 | **Llenar con IA** | Modal creación de producto, botón "Llenar con IA" | Admin pone nombre/categoría → IA genera descripción + (opcional) foto | `chat.completions` + (opcional) `images.generate` |
| 2 | **Generar Imagen IA** | Sección de imágenes del producto | Producto ya tiene datos → IA genera foto comercial | `images.generate` |
| 3 | **Llenar desde Foto** | Header/toolbar del producto, "Llenar con Foto IA" | Admin sube foto real → Vision analiza → genera nombre, descripción, categoría, precio | `chat.completions` con Vision (imagen como input) |
| 4 | **Banner IA** | Sección Banners, "Generar Banner con IA" | Admin describe banner → IA genera imagen | `images.generate` |

**API Key:** Se usa la misma `OPENAI_API_KEY` existente. No hace falta key nueva. El mismo SDK `openai` cubre texto, Vision e imagen.

---

## Resolución de Gaps (Review 2026-03-18)

### Gaps descartados (verificados contra API real)

| # | Gap reportado | Resultado |
|---|---------------|-----------|
| 1 | Nombres de modelos no existen | **Descartado** — `gpt-image-1-mini` y `gpt-image-1.5` existen y están activos en la API de OpenAI |
| 2 | Tamaños no soportados | **Descartado** — `1536x1024` y `1024x1536` son válidos para modelos GPT Image (distinto de DALL-E 3 que usa 1792) |

### Gaps incorporados al plan

| # | Gap | Sección | Criticidad |
|---|-----|---------|------------|
| 3 | Race condition en créditos | → Protecciones de Concurrencia | 🔴 Crítico |
| 4 | Content policy vs error de servicio | → Protecciones de Resiliencia | 🔴 Crítico |
| 5 | Imágenes temporales huérfanas | → Gestión de Imágenes Temporales | 🟠 Alto |
| 6 | Storage falla post-generación | → Protecciones de Resiliencia | 🟠 Alto |
| 7 | AbortSignal timeout | → Protecciones de Resiliencia | 🟠 Alto |
| 8 | Vision JSON sin schema validation | → Feature 3 (actualizado) | 🟠 Alto |
| 9 | Idempotencia / doble generación | → Protecciones de Concurrencia | 🟠 Alto |
| 10 | HEIC/HEIF no contemplado | → Feature 3 Validación (actualizado) | 🟡 Medio |
| 11 | EXIF orientation | → Feature 3 Pre-procesamiento (nuevo) | 🟡 Medio |
| 12 | suggested_price disclaimer | → Feature 3 Output (actualizado) | 🟡 Medio |
| 13 | StoreDNA falla silenciosamente | → Protecciones de Resiliencia | 🟡 Medio |
| 14 | Límite de imágenes por producto | → Feature 2 Validación (actualizado) | 🟡 Medio |
| 15 | Storage quota no contabilizada | → Gestión de Storage Quota | 🟡 Medio |
| 16 | +16 edge case tests | → Tests (actualizado) | 🔵 Tests |

### Actualización adicional: Modelos Vision

Se actualizan los modelos de Vision de `gpt-4o` / `gpt-4o-mini` a `gpt-4.1` / `gpt-4.1-mini` (lanzados en 2026, mejores benchmarks multimodales, menor costo).

| Tier | Modelo anterior | Modelo nuevo | Ahorro |
|------|----------------|-------------|--------|
| Normal | gpt-4o-mini ($0.15/M in) | gpt-4.1-mini ($0.40/M in) | Mejor calidad Vision, costo comparable |
| Pro | gpt-4o ($2.50/M in) | gpt-4.1 ($2.00/M in) | -20% costo, mejor performance |

---

## Infraestructura existente

### `ai_photo_product` — Billing listo (pricing a actualizar)

| Componente | Estado |
|-----------|--------|
| `AI_ACTION_CODES` array | `'ai_photo_product'` registrado |
| Pricing seed SQL | Normal: 3 créd / Pro: 5 créd (modelo texto → **hay que actualizar**) |
| Welcome credits | starter:3, growth:10, enterprise:30 |
| Addon packs | `ai_photo_pack_10` ($69.90), `ai_photo_pack_50` ($249.90) |
| Labels frontend | `'Fichas desde Foto'` → **renombrar a 'Fotos IA Producto'** |
| Guard + decorator | Funcional |

### `ai_product_description` — Ya implementado

El endpoint `POST /products/:id/ai-description` que genera descripción de texto **ya existe** (implementado en este sprint). La Feature 1 lo reutiliza.

### Storage + Image Processing — Listo

- **StorageService:** Supabase Storage, bucket `product-images`
- **ImageService:** sharp → variantes webp/avif (thumb 320, md 800, lg 1600 para productos; md 1280, lg 1920, xl 2560 para banners)
- **MediaLibraryService:** CRUD `tenant_media` + `product_media`
- **BannerService:** CRUD banners con upload y variantes
- **PathBuilder:** `clients/{client_id}/{kind}/{entity_id}/{base}-{size}.{format}`

---

## Feature 1: Llenar con IA (modal de creación)

### Concepto

En el modal de creación de producto, el admin ingresa datos básicos (nombre, categoría) y hace clic en "Llenar con IA". La IA genera la descripción. Opcionalmente, un checkbox "También generar foto" activa la generación de imagen.

### Flujo

```
1. Admin abre modal "Crear Producto"
2. Escribe nombre del producto + selecciona categoría
3. Hace clic en "Llenar con IA"
   - Checkbox opcional: "También generar foto comercial"
4. Frontend envía POST /products/ai-fill
5. Backend:
   a. Guard valida créditos para ai_product_description
   b. Si include_photo=true, también valida créditos para ai_photo_product
   c. Genera descripción con GPT (chat.completions) — reutiliza lógica existente
   d. Si include_photo=true, genera foto con images.generate()
   e. Consume créditos solo de lo que fue exitoso
6. Retorna draft: { description, photo_url? }
7. Admin ve preview en el modal, edita lo que quiera, y confirma creación
```

### Endpoint

**`POST /products/ai-fill`**

- **Action code:** `ai_product_description` (+ `ai_photo_product` si `include_photo`)
- **Guards:** `ClientDashboardGuard`, `AiCreditsGuard`
- **Decorator:** `@RequireAiCredits('ai_product_description')`
- **Input:**
```json
{
  "name": "Remera Oversize Negra",
  "category_name": "Remeras",
  "include_photo": true,
  "photo_style": "studio",
  "ai_tier": "normal"
}
```
- **Output:**
```json
{
  "description": "Una remera oversize de algodón premium...",
  "photo": {
    "temp_url": "https://storage.../temp/ai-generated.webp",
    "temp_key": "temp/ai-photo-uuid.webp"
  },
  "credits_consumed": {
    "description": 1,
    "photo": 5
  },
  "tier": "normal"
}
```

**Nota sobre créditos:** La descripción consume de `ai_product_description` (1 crédito) y la foto de `ai_photo_product` (5 créditos). Son pools separados. Si el admin no tiene créditos para foto pero sí para descripción, se genera solo la descripción.

### System Prompt (descripción)

Reutiliza `PRODUCT_DESCRIPTION_SYSTEM_PROMPT` existente de `prompts/index.ts`. No necesita prompt nuevo.

### Prompt (foto — si include_photo=true)

```
Professional studio product photography with neutral background and soft lighting.
Product: {name}
Category: {category_name}
Requirements:
- Commercial e-commerce product photo
- High quality, sharp focus on the product
- Realistic, not illustrated or cartoon
- NO text, watermarks, logos, or labels in the image
- Professional color grading
Style: {photo_style}
```

---

## Feature 2: Generar Imagen IA (sección imágenes)

### Concepto

Para un producto que ya existe y tiene datos completos pero necesita una foto. El admin va a la sección de imágenes del producto y hace clic en "Generar con IA".

### Flujo

```
1. Admin está en la edición de un producto existente
2. Va a la sección "Imágenes"
3. Hace clic en "Generar con IA"
4. Selecciona estilo (studio, lifestyle, flat_lay, minimalist, creative)
5. Opcionalmente agrega instrucciones extra
6. Frontend envía POST /products/:id/ai-photo
7. Backend:
   a. Guard valida créditos ai_photo_product
   b. Lee producto completo de BD (nombre, descripción, categoría, precio)
   c. Obtiene Store DNA
   d. Construye prompt descriptivo en inglés
   e. Llama images.generate()
   f. Procesa imagen (sharp → variantes webp)
   g. Sube a Storage
   h. Crea tenant_media + product_media (asocia al producto)
   i. Consume crédito solo si exitoso
8. Retorna imagen con variantes
9. Admin ve preview — puede regenerar o aceptar
```

### Endpoint

**`POST /products/:id/ai-photo`**

- **Action code:** `ai_photo_product`
- **Guards:** `ClientDashboardGuard`, `AiCreditsGuard`
- **Decorator:** `@RequireAiCredits('ai_photo_product')`
- **Input:**
```json
{
  "ai_tier": "normal",
  "style": "studio",
  "instructions": "Fondo blanco, vista frontal"
}
```
- **Estilos:**
  - `studio` — fondo neutro, luz profesional (default)
  - `lifestyle` — producto en contexto de uso
  - `flat_lay` — vista cenital
  - `minimalist` — fondo blanco puro
  - `creative` — estilo editorial/artístico
- **Output:**
```json
{
  "image": {
    "media_id": "uuid",
    "url": "https://storage.../products/generated-lg.webp",
    "variants": {
      "thumb": "...-thumb.webp",
      "md": "...-md.webp",
      "lg": "...-lg.webp"
    }
  },
  "product_id": "uuid",
  "credits_consumed": 5,
  "tier": "normal"
}
```

### Prompt Builder

```typescript
function buildProductPhotoPrompt(input: {
  name: string;
  description?: string;
  categoryName?: string;
  attributes?: Record<string, string>;
  style: string;
  instructions?: string;
}): string {
  const styleMap = {
    studio: 'Professional studio product photography, neutral background, soft lighting',
    lifestyle: 'Lifestyle product photography, product in real-world usage context',
    flat_lay: 'Overhead flat lay product photography, clean surface, complementary props',
    minimalist: 'Minimalist product photo, pure white background, centered, no props',
    creative: 'Editorial product photography, creative composition and dramatic lighting',
  };

  const parts = [styleMap[input.style] || styleMap.studio];
  parts.push(`Product: ${input.name}`);
  if (input.categoryName) parts.push(`Category: ${input.categoryName}`);
  if (input.description) {
    parts.push(`Description: ${input.description.slice(0, 200)}`);
  }
  parts.push('Requirements:');
  parts.push('- Commercial e-commerce product photo, realistic');
  parts.push('- Sharp focus, professional color grading');
  parts.push('- NO text, watermarks, logos, labels, or numbers');
  if (input.instructions) parts.push(`Additional: ${input.instructions}`);

  return parts.join('\n');
}
```

---

## Feature 3: Llenar desde Foto (Vision)

### Concepto

El admin sube una foto real de su producto (foto de celular, catálogo, etc.) → GPT-4o Vision analiza la imagen → genera todos los datos: nombre, descripción, categoría sugerida, precio estimado, atributos detectados (color, material, etc.).

### Flujo

```
1. Admin hace clic en "Llenar desde Foto" (header/toolbar del producto)
2. Sube una foto real (drag & drop o file picker, max 5MB)
3. Frontend envía POST /products/ai-from-photo (multipart)
4. Backend:
   a. Guard valida créditos ai_photo_product
   b. Convierte imagen a base64
   c. Obtiene Store DNA
   d. Envía a GPT-4o Vision via chat.completions.create con image_url
   e. Parsea respuesta JSON (nombre, descripción, categoría, precio, atributos)
   f. Sube foto original a storage temporal
   g. Consume crédito solo si exitoso
5. Retorna draft completo + URL de la foto subida
6. Admin ve preview — edita lo que quiera — confirma
7. Se crea/actualiza el producto con los datos + la foto original adjunta
```

### Endpoint

**`POST /products/ai-from-photo`**

- **Action code:** `ai_photo_product`
- **Guards:** `ClientDashboardGuard`, `AiCreditsGuard`
- **Decorator:** `@RequireAiCredits('ai_photo_product')`
- **Input:** Multipart form
  - `image` — archivo de imagen (max 5MB, jpeg/png/webp)
  - `ai_tier` — `'normal'` | `'pro'`
- **Output:**
```json
{
  "draft": {
    "name": "Remera Oversize Negra",
    "description": "Remera oversize confeccionada en algodón premium...",
    "suggested_category": "Remeras",
    "suggested_price": 15000,
    "is_price_estimated": true,
    "attributes": {
      "material": "algodón",
      "color": "negro",
      "tipo": "oversize"
    }
  },
  "uploaded_image": {
    "temp_url": "https://storage.../temp/original-photo.webp",
    "temp_key": "temp/photo-uuid.webp"
  },
  "credits_consumed": 5,
  "tier": "normal"
}
```

### System Prompt (Vision)

```
{storeDNA}

Analizá esta foto de un producto de e-commerce y generá una ficha completa para venta online.

REGLAS:
- Nombre descriptivo y comercial (máx 80 caracteres)
- Descripción persuasiva para venta online (máx 300 palabras)
- Sugerí una categoría del catálogo si es identificable
- Estimá un precio razonable para el mercado argentino (puede ser null si no es estimable)
- Identificá atributos visibles: color, material, talle/tamaño, marca si es visible
- NO inventar especificaciones técnicas que no se vean en la foto
- Español rioplatense natural
- Respondé SOLO con JSON:
{
  "name": "...",
  "description": "...",
  "suggested_category": "...",
  "suggested_price": null,
  "attributes": {}
}
```

### Pre-procesamiento de imagen (Gap #10, #11)

Antes de enviar la imagen a Vision, se aplica un pipeline de pre-procesamiento con `sharp`:

```typescript
async preprocessImageForVision(buffer: Buffer): Promise<{ processed: Buffer; mimeType: string }> {
  let pipeline = sharp(buffer);

  // Gap #11: EXIF orientation — sharp().rotate() sin args usa EXIF para auto-rotar
  pipeline = pipeline.rotate();

  // Obtener metadata para validaciones
  const metadata = await pipeline.metadata();

  // Gap #10: HEIC/HEIF — convertir a JPEG si es necesario
  // sharp soporta HEIC si libvips fue compilado con libheif
  if (metadata.format === 'heif' || metadata.format === 'heic') {
    pipeline = pipeline.jpeg({ quality: 90 });
  }

  // Validar dimensiones mínimas (200x200px)
  if ((metadata.width ?? 0) < 200 || (metadata.height ?? 0) < 200) {
    throw new BadRequestException('Image too small. Minimum 200x200px.');
  }

  // Si excede 20MP, redimensionar manteniendo aspect ratio
  const pixels = (metadata.width ?? 0) * (metadata.height ?? 0);
  if (pixels > 20_000_000) {
    const scale = Math.sqrt(20_000_000 / pixels);
    pipeline = pipeline.resize(
      Math.round((metadata.width ?? 0) * scale),
      Math.round((metadata.height ?? 0) * scale),
    );
  }

  // Si >1MB, comprimir a webp para ahorrar tokens de Vision
  const processed = await pipeline.webp({ quality: 85 }).toBuffer();

  return { processed, mimeType: 'image/webp' };
}
```

**MIME types aceptados (actualizado):**
- `image/jpeg`, `image/png`, `image/webp` — directo
- `image/heic`, `image/heif` — **aceptado con conversión automática a JPEG** (requiere `libheif` en el servidor)
- Otros → 400 `"Unsupported image format. Use JPG, PNG, WebP or HEIC."`

### Implementación OpenAI Vision (actualizado con gpt-4.1, schema validation, AbortSignal)

```typescript
async generateProductFromPhoto(
  clientId: string,
  accountId: string,
  imageBuffer: Buffer,
  mimeType: string,
  tier: 'normal' | 'pro',
): Promise<ProductDraft> {
  // Gap #13: StoreDNA fallback — generar sin DNA si falla
  let storeDNA = '';
  try {
    storeDNA = await this.storeContext.getOrGenerateStoreDNA(clientId, accountId);
  } catch (err) {
    this.logger.warn(`StoreDNA failed for client=${clientId}, generating without DNA: ${err.message}`);
  }

  // Pre-procesar: EXIF rotation, HEIC conversion, resize si necesario
  const { processed, mimeType: finalMime } = await this.preprocessImageForVision(imageBuffer);

  // Modelos actualizados a gpt-4.1 family (mejores benchmarks multimodales)
  const visionModel = tier === 'pro' ? 'gpt-4.1' : 'gpt-4.1-mini';

  const base64 = processed.toString('base64');
  const dataUrl = `data:${finalMime};base64,${base64}`;

  const response = await this.client.chat.completions.create(
    {
      model: visionModel,
      temperature: 0.3,
      max_tokens: 1200,
      response_format: { type: 'json_object' },
      messages: [
        { role: 'system', content: storeDNA ? `${storeDNA}\n\n${VISION_SYSTEM_PROMPT}` : VISION_SYSTEM_PROMPT },
        {
          role: 'user',
          content: [
            { type: 'text', text: 'Analizá esta foto y generá la ficha de producto.' },
            {
              type: 'image_url',
              image_url: { url: dataUrl, detail: tier === 'pro' ? 'high' : 'low' },
            },
          ],
        },
      ],
    },
    { timeout: 55_000 }, // Gap #7: AbortSignal — 55s antes del timeout del cliente (60s)
  );

  const raw = response.choices?.[0]?.message?.content;
  if (!raw) throw new Error('Empty Vision response');

  // Gap #8: Schema validation post-parse
  return this.validateAndSanitizeVisionResponse(JSON.parse(raw));
}

// Gap #8: Validación y sanitización de respuesta Vision
private validateAndSanitizeVisionResponse(data: any): ProductDraft {
  const stripHtml = (s: string) => s.replace(/<[^>]*>/g, '').trim();

  const name = typeof data.name === 'string'
    ? stripHtml(data.name).slice(0, 80)
    : 'Producto sin nombre';

  const description = typeof data.description === 'string'
    ? stripHtml(data.description).slice(0, 1500)
    : '';

  const suggested_category = typeof data.suggested_category === 'string'
    ? data.suggested_category.slice(0, 100)
    : null;

  // Gap #12: suggested_price — validar numérico positivo, marcar como estimado
  let suggested_price: number | null = null;
  if (typeof data.suggested_price === 'number' && data.suggested_price > 0 && data.suggested_price < 100_000_000) {
    suggested_price = Math.round(data.suggested_price);
  }

  // Attributes: solo objeto plano, max 10 keys, valores string
  const attributes: Record<string, string> = {};
  if (data.attributes && typeof data.attributes === 'object' && !Array.isArray(data.attributes)) {
    const keys = Object.keys(data.attributes).slice(0, 10);
    for (const key of keys) {
      if (typeof data.attributes[key] === 'string') {
        attributes[key.slice(0, 50)] = String(data.attributes[key]).slice(0, 200);
      }
    }
  }

  return {
    name,
    description,
    suggested_category,
    suggested_price,
    is_price_estimated: suggested_price !== null, // Gap #12: Flag explícito
    attributes,
  };
}
```

**Costos Vision (NO image generation) — modelos actualizados:**

| Tier | Modelo | detail | Costo aprox |
|------|--------|--------|-------------|
| Normal | gpt-4.1-mini | low | ~$0.003-0.006 |
| Pro | gpt-4.1 | high | ~$0.01-0.03 |

Mucho más barato que generar imágenes. Se puede compartir pool de créditos con `ai_photo_product`.

---

## Feature 4: Banner IA (`ai_banner_generation`)

### Concepto

El admin describe qué banner quiere → la IA genera una imagen de banner con las dimensiones correctas → se integra al sistema de banners existente.

### Action Code: `ai_banner_generation` (nuevo)

### Flujo

```
1. Admin va a Configuración → Banners
2. Hace clic en "Generar Banner con IA"
3. Escribe descripción del banner deseado
4. Selecciona tipo (desktop/mobile), estilo, tier
5. Frontend envía POST /banners/ai-generate
6. Backend:
   a. Guard valida créditos
   b. Obtiene Store DNA
   c. Construye prompt
   d. Llama images.generate()
   e. Procesa con ImageService (variantes banner)
   f. Sube a Storage
   g. Crea entry en tabla banners
   h. Consume crédito solo si exitoso
7. Retorna banner creado
8. Admin ve preview — puede editar link/orden, regenerar o descartar
```

### Endpoint

**`POST /banners/ai-generate`**

- **Action code:** `ai_banner_generation` (nuevo)
- **Guards:** `ClientDashboardGuard`, `AiCreditsGuard`
- **Input:**
```json
{
  "prompt": "Banner de ofertas de verano con colores vibrantes",
  "type": "desktop",
  "style": "photorealistic",
  "ai_tier": "normal"
}
```
- **Estilos:** `photorealistic`, `illustrated`, `abstract`, `gradient`, `seasonal`
- **Output:**
```json
{
  "banner": {
    "id": "uuid",
    "url": "https://storage.../banners/generated-xl.webp",
    "type": "desktop",
    "image_variants": { "md": "...", "lg": "...", "xl": "..." }
  },
  "credits_consumed": 5,
  "tier": "normal"
}
```

### Tamaños

| Tipo | Tamaño OpenAI | Post-proceso |
|------|---------------|-------------|
| Desktop | `1536x1024` | 2560×850 (xl), 1920×640 (lg), 1280×427 (md) |
| Mobile | `1024x1536` | 1200×1800 (xl), 800×1200 (lg), 600×900 (md) |

### Prompt Builder

```typescript
function buildBannerPrompt(input: {
  userPrompt: string;
  type: 'desktop' | 'mobile';
  style: string;
  storeDNA: string;
}): string {
  const styleMap = {
    photorealistic: 'Photorealistic promotional banner',
    illustrated: 'Illustrated/vector art promotional banner',
    abstract: 'Abstract geometric shapes and bold colors',
    gradient: 'Modern gradient design, clean and minimal',
    seasonal: 'Seasonal themed with festive elements',
  };

  const orientation = input.type === 'desktop'
    ? 'Wide horizontal landscape (16:5 ratio)'
    : 'Tall vertical portrait (2:3 ratio)';

  return [
    `${styleMap[input.style]} for an Argentine e-commerce store.`,
    orientation,
    `Store: ${input.storeDNA}`,
    'NO text/words/letters/numbers in the image.',
    'Leave clear space for text overlay.',
    `Theme: ${input.userPrompt}`,
  ].join('\n');
}
```

---

## Método compartido: `callOpenAIImageGeneration` (Gap #4, #7)

Features 1 (foto opcional), 2 (foto de producto) y 4 (banner) usan el mismo método.

**Cambios vs v1:**
- Gap #4: Bifurcación de errores — content policy NO se reintenta
- Gap #7: AbortSignal timeout (55s) via segundo argumento del SDK
- Gap #6: Retorna null si falla → el controller NO consume créditos

```typescript
// Errores que NO deben reintentarse (siempre van a fallar)
private readonly NON_RETRYABLE_ERRORS = new Set([
  'content_policy_violation',
  'billing_hard_limit_exceeded',
  'invalid_api_key',
  'model_not_found',
]);

async callOpenAIImageGeneration(params: {
  prompt: string;
  size: '1024x1024' | '1024x1536' | '1536x1024';
  quality: 'low' | 'medium' | 'high';
  model: string;
  retries?: number;
}): Promise<{ buffer: Buffer; error?: never } | { buffer?: never; error: string; errorCode: string }> {
  if (!this.client) throw new Error('OpenAI API key not configured');
  const retries = params.retries ?? 2;

  for (let attempt = 0; attempt <= retries; attempt++) {
    try {
      const response = await this.client.images.generate(
        {
          model: params.model,
          prompt: params.prompt,
          n: 1,
          size: params.size as any,
          quality: params.quality as any,
          output_format: 'webp',
          response_format: 'b64_json',
        },
        {
          timeout: 55_000, // Gap #7: 55s antes del timeout del frontend (60s)
        },
      );

      const b64 = response.data?.[0]?.b64_json;
      if (!b64) {
        this.logger.warn(`Empty image response (attempt ${attempt + 1})`);
        continue;
      }
      return { buffer: Buffer.from(b64, 'base64') };

    } catch (err: any) {
      const errorCode = err?.error?.code || err?.code || '';

      // Gap #4: Content policy y otros errores permanentes → NO reintentar
      if (this.NON_RETRYABLE_ERRORS.has(errorCode)) {
        this.logger.warn(`Non-retryable OpenAI error: ${errorCode} — ${err.message}`);
        return {
          error: this.humanReadableError(errorCode),
          errorCode,
        };
      }

      // Errores retryable: 429 rate_limit, 500/503 server errors, timeout
      if (attempt < retries) {
        const backoff = (attempt + 1) * 3000; // 3s, 6s
        this.logger.warn(`Image gen error (attempt ${attempt + 1}, retry in ${backoff}ms): ${err.message}`);
        await this.sleep(backoff);
      } else {
        this.logger.error(`Image gen failed after ${retries + 1} attempts: ${err.message}`);
        return { error: 'Image generation failed after retries', errorCode: 'generation_failed' };
      }
    }
  }
  return { error: 'Image generation failed', errorCode: 'generation_failed' };
}

private humanReadableError(code: string): string {
  const map: Record<string, string> = {
    content_policy_violation: 'La imagen fue rechazada por las políticas de contenido de OpenAI. Intentá con un prompt diferente.',
    billing_hard_limit_exceeded: 'Límite de facturación de OpenAI alcanzado. Contactá soporte.',
  };
  return map[code] || 'Error en la generación de imagen.';
}
```

**Tipo de retorno discriminado:** El controller puede distinguir entre éxito (`buffer` presente) y error (`error` + `errorCode`). Si es `content_policy_violation`, retorna HTTP 422 con mensaje descriptivo. Si es `generation_failed`, retorna HTTP 502. En ningún caso se consume crédito.

---

## Protecciones de Concurrencia (Gap #3, #9)

### Advisory Lock para créditos (Gap #3)

Dos requests simultáneos del mismo tenant con saldo justo pueden pasar ambos el `AiCreditsGuard` y consumir más créditos de los disponibles. Se usa **advisory lock** por `(account_id, action_code)` para serializar el consumo.

```typescript
// En ai-credits.service.ts — método consumeCredit (actualizado)
async consumeCredit(params: ConsumeParams): Promise<void> {
  const lockKey = this.advisoryLockKey(params.accountId, params.actionCode);

  // pg_advisory_xact_lock se libera al final de la transacción
  await this.adminDb.rpc('exec_sql', {
    sql: `SELECT pg_advisory_xact_lock($1)`,
    args: [lockKey],
  });

  // Re-verificar balance dentro del lock (doble check)
  const balance = await this.getBalance(params.accountId, params.actionCode);
  const pricing = await this.getPricingForTier(params.actionCode, params.tier);
  if (balance < (pricing?.credit_cost ?? 1)) {
    throw new HttpException({
      error: 'insufficient_ai_credits',
      message: 'Credits consumed by concurrent request',
    }, HttpStatus.PAYMENT_REQUIRED);
  }

  // Consumir dentro de la misma transacción
  await this.insertLedgerEntry(params);
}

private advisoryLockKey(accountId: string, actionCode: string): number {
  // Hash estable a int32 para pg_advisory_lock
  const str = `${accountId}:${actionCode}`;
  let hash = 0;
  for (let i = 0; i < str.length; i++) {
    hash = ((hash << 5) - hash + str.charCodeAt(i)) | 0;
  }
  return hash;
}
```

**Alternativa más simple (si advisory locks no son viables via Supabase RPC):**
Usar `UPDATE ... SET balance = balance - cost WHERE balance >= cost RETURNING *` con condición atómica. Si no retorna rows → créditos insuficientes.

### Lock de generación en curso (Gap #9)

Para evitar que un retry del frontend dispare una segunda generación mientras la primera sigue en curso:

```typescript
// In-memory lock por (accountId + actionCode)
private readonly generatingLocks = new Map<string, number>(); // key → timestamp

private acquireGeneratingLock(accountId: string, actionCode: string): boolean {
  const key = `${accountId}:${actionCode}`;
  const existing = this.generatingLocks.get(key);

  // Si hay un lock activo de menos de 60s, rechazar
  if (existing && Date.now() - existing < 60_000) {
    return false;
  }

  this.generatingLocks.set(key, Date.now());
  return true;
}

private releaseGeneratingLock(accountId: string, actionCode: string): void {
  this.generatingLocks.delete(`${accountId}:${actionCode}`);
}
```

**Uso en controller:**
```typescript
if (!this.aiGeneration.acquireGeneratingLock(accountId, 'ai_photo_product')) {
  throw new HttpException('Generation already in progress', HttpStatus.TOO_MANY_REQUESTS); // 429
}
try {
  const result = await this.aiGeneration.generateProductPhoto(...);
  // ... consume credit, return
} finally {
  this.aiGeneration.releaseGeneratingLock(accountId, 'ai_photo_product');
}
```

**Nota:** Este lock es in-memory y no sobrevive un restart. Para multi-instancia (Railway con réplicas), se puede escalar a Redis o a una tabla `ai_generation_locks` con TTL. En la primera versión, in-memory es suficiente (Railway single instance).

---

## Protecciones de Resiliencia (Gap #4, #6, #7, #13)

### Flujo de consumo de créditos (Gap #6 — clarificado)

El crédito se consume **SOLO si el resultado completo llega al cliente**. El flujo es:

```
1. Guard valida créditos (pre-check, no consume)
2. Acquire generating lock
3. Generar imagen con OpenAI
   → Si falla OpenAI → NO consume → return error
   → Si content policy → NO consume → return 422
4. Procesar con sharp (variantes)
   → Si falla sharp → NO consume → return 500
5. Subir a Supabase Storage
   → Si falla upload → NO consume → return 502 + cleanup buffer
6. Crear product_media / banner en BD
   → Si falla BD → cleanup storage → NO consume → return 500
7. Consumir crédito (advisory lock + doble check)
   → Si falla consumo (race condition) → cleanup storage + BD → return 402
8. Retornar resultado al cliente
9. Release generating lock (finally)
```

```typescript
// Patrón en controller (pseudo-código)
async generateProductPhoto(...) {
  // Steps 1-2 (guards + lock)
  try {
    const imageResult = await this.aiGeneration.generateProductPhoto(...);
    if (imageResult.error) {
      // Step 3 failed — no credit consumed
      throw new HttpException(imageResult.error, imageResult.errorCode === 'content_policy_violation' ? 422 : 502);
    }

    const stored = await this.storage.uploadWithVariants(imageResult.buffer, ...);
    // If storage fails here, exception propagates — no credit consumed

    const media = await this.mediaLibrary.createProductMedia(stored, productId, ...);
    // If DB fails here, cleanup storage, exception propagates

    // Only NOW consume credit
    await this.aiCredits.consumeCredit({ ... });

    return { image: media, credits_consumed: pricing.credit_cost, tier };
  } catch (err) {
    // Cleanup on partial failure
    if (stored?.key) await this.storage.deleteQuietly(stored.key);
    throw err;
  } finally {
    this.aiGeneration.releaseGeneratingLock(accountId, actionCode);
  }
}
```

### AbortSignal timeout (Gap #7)

Todas las llamadas al SDK de OpenAI usan timeout de **55 segundos** (5s antes del timeout del frontend):

```typescript
// images.generate — segundo argumento
await this.client.images.generate({ ... }, { timeout: 55_000 });

// chat.completions.create (Vision) — segundo argumento
await this.client.chat.completions.create({ ... }, { timeout: 55_000 });
```

Si se excede el timeout, OpenAI SDK lanza `APIConnectionTimeoutError`. Este error NO se reintenta (ya consumió tiempo).

### StoreDNA fallback (Gap #13)

Si `getOrGenerateStoreDNA()` falla (timeout, tienda sin datos), se genera con prompt base:

```typescript
let storeDNA = '';
try {
  storeDNA = await this.storeContext.getOrGenerateStoreDNA(clientId, accountId);
} catch (err) {
  this.logger.warn(`StoreDNA failed for client=${clientId}: ${err.message}`);
  // Fallback: generar sin DNA — el prompt base es suficiente
}

const systemPrompt = storeDNA
  ? `${storeDNA}\n\n${BASE_SYSTEM_PROMPT}`
  : BASE_SYSTEM_PROMPT;
```

Este patrón se aplica a los 4 endpoints de imagen. No se lanza error — el resultado será menos personalizado pero funcional.

---

## Gestión de Imágenes Temporales (Gap #5)

### Problema

Los endpoints `ai-fill` (con foto) y `ai-from-photo` retornan `temp_url`/`temp_key` — imágenes en `temp/` que esperan confirmación del admin. Si el admin no confirma, quedan huérfanas.

### Solución: TTL + Cleanup + Endpoint de confirmación

#### 1. Ruta temporal

```
clients/{client_id}/temp/ai-{uuid}.webp
```

- TTL: **2 horas** desde creación
- No se crea `tenant_media` ni `product_media` hasta confirmar

#### 2. Endpoint de confirmación

```
POST /products/:id/confirm-ai-image
```

```json
// Request
{ "temp_key": "clients/abc/temp/ai-uuid.webp" }

// Response
{
  "media_id": "uuid",
  "url": "https://storage.../products/confirmed-lg.webp",
  "variants": { "thumb": "...", "md": "...", "lg": "..." }
}
```

Este endpoint:
1. Valida que `temp_key` pertenece al `client_id` del request
2. Mueve la imagen de `temp/` a `products/{product_id}/`
3. Genera variantes con `ImageService` (thumb, md, lg)
4. Crea `tenant_media` + `product_media`
5. Borra el archivo temporal
6. NO consume créditos (ya se consumieron en la generación)

#### 3. Cron de cleanup

```typescript
// Ejecutar cada 30 minutos via @Cron
@Cron('*/30 * * * *')
async cleanupOrphanedTempImages() {
  const backend = this.dbRouter.getBackendClient();

  // Listar archivos en temp/ con más de 2 horas
  const { data: files } = await backend.storage
    .from('product-images')
    .list('temp', {
      limit: 100,
      sortBy: { column: 'created_at', order: 'asc' },
    });

  const twoHoursAgo = new Date(Date.now() - 2 * 60 * 60 * 1000);

  for (const file of files ?? []) {
    if (new Date(file.created_at) < twoHoursAgo) {
      await backend.storage.from('product-images').remove([`temp/${file.name}`]);
      this.logger.log(`Cleaned up orphaned temp image: temp/${file.name}`);
    }
  }
}
```

**Nota:** El cron se limita a 100 archivos por ejecución para no sobrecargar. Si hay más, se procesan en la siguiente ejecución.

---

## Verificación de Límites por Producto (Gap #14)

Antes de crear `product_media` en Feature 2, verificar:

```typescript
async validateImageLimit(clientId: string, productId: string): Promise<void> {
  const backend = this.dbRouter.getBackendClient();

  // Contar imágenes actuales del producto
  const { count } = await backend
    .from('product_media')
    .select('*', { count: 'exact', head: true })
    .eq('product_id', productId)
    .eq('client_id', clientId);

  // Obtener límite del plan (entitlements del tenant)
  const { data: client } = await backend
    .from('clients')
    .select('entitlements')
    .eq('id', clientId)
    .single();

  const maxImages = client?.entitlements?.max_images_per_product ?? 10; // default 10

  if ((count ?? 0) >= maxImages) {
    throw new HttpException({
      error: 'image_limit_reached',
      message: `Product already has ${count} images (max ${maxImages} for your plan).`,
      max_images: maxImages,
      current_count: count,
    }, HttpStatus.UNPROCESSABLE_ENTITY); // 422
  }
}
```

La imagen generada se agrega como **última** en el orden (no reemplaza la principal).

---

## Contabilización de Storage (Gap #15)

Las imágenes generadas por IA cuentan contra la cuota de storage del tenant. Se registra un `usage_event` al subir:

```typescript
// Después de subir imagen + variantes a Storage
await this.usageService.trackEvent({
  clientId,
  eventType: 'storage_upload',
  bytes: totalBytes, // suma de todas las variantes
  metadata: {
    source: 'ai_generation',
    action_code: actionCode,
    entity_type: entityType, // 'product' | 'banner'
    entity_id: entityId,
  },
});
```

Esto se integra con el sistema de `usage_ledger` / `usage_daily` existente. Si el tenant excede su cuota de storage, se retorna 422 `"Storage quota exceeded"` antes de intentar la generación (se valida pre-check junto con los créditos).

---

## Migration SQL (Admin DB)

```sql
-- ─── 1. Actualizar pricing ai_photo_product (texto → imagen) ────────────

-- Pricing para GENERACIÓN de imagen (images.generate)
UPDATE ai_feature_pricing SET
  model_id = 'gpt-image-1-mini', credit_cost = 5,
  temperature = 0, max_tokens = 0,
  label = 'Foto Producto Normal',
  description = 'Genera foto comercial con modelo rápido'
WHERE action_code = 'ai_photo_product' AND tier = 'normal';

UPDATE ai_feature_pricing SET
  model_id = 'gpt-image-1.5', credit_cost = 8,
  temperature = 0, max_tokens = 0,
  label = 'Foto Producto Pro',
  description = 'Genera foto comercial premium de alta calidad'
WHERE action_code = 'ai_photo_product' AND tier = 'pro';

-- NOTA: Para Vision (ai-from-photo), se usa el MISMO action_code ai_photo_product
-- pero el modelo de Vision se elige en código (gpt-4.1-mini / gpt-4.1)
-- porque no pasa por images.generate sino por chat.completions.
-- El model_id en pricing se usa SOLO para image generation.
-- Vision siempre usa los modelos de chat, no los de imagen.

-- ─── 2. Nuevo pricing ai_banner_generation ───────────────────────────────

INSERT INTO ai_feature_pricing
  (action_code, tier, credit_cost, model_id, temperature, max_tokens, label, description, is_active)
VALUES
  ('ai_banner_generation', 'normal', 5, 'gpt-image-1-mini', 0, 0,
   'Banner Normal', 'Genera banner promocional con modelo rápido', true),
  ('ai_banner_generation', 'pro', 10, 'gpt-image-1.5', 0, 0,
   'Banner Pro', 'Genera banner premium de alta calidad', true);

-- ─── 3. Welcome credits ai_banner_generation ─────────────────────────────

INSERT INTO ai_welcome_credit_config (plan_key, action_code, credits, expires_days)
VALUES
  ('starter',    'ai_banner_generation', 2,  90),
  ('growth',     'ai_banner_generation', 5,  120),
  ('enterprise', 'ai_banner_generation', 15, 180);

-- ─── 4. Addon packs ai_banner_generation ─────────────────────────────────

INSERT INTO addon_catalog
  (addon_key, display_name, description, addon_type, billing_mode, family,
   price_cents, is_active, long_description, category_label, placement,
   commercial_model, action_code, grants_credits)
VALUES
  ('ai_banner_pack_5', 'AI — 5 Banners',
   '5 créditos para generar banners con IA.',
   'consumable', 'one_time', 'ai', 4990, true,
   'Generá banners promocionales con inteligencia artificial.',
   'IA', 'addonStore', 'consumable_action', 'ai_banner_generation', 5),
  ('ai_banner_pack_20', 'AI — 20 Banners',
   '20 créditos para generar banners con IA.',
   'consumable', 'one_time', 'ai', 14990, true,
   'Pack de banners IA. Ahorrá 25% vs individual.',
   'IA', 'addonStore', 'consumable_action', 'ai_banner_generation', 20);
```

---

## Resumen de endpoints

| # | Endpoint | Feature | Action code | OpenAI API |
|---|----------|---------|-------------|------------|
| 1 | `POST /products/ai-fill` | Llenar con IA | `ai_product_description` + `ai_photo_product` | chat + images |
| 2 | `POST /products/:id/ai-photo` | Generar Imagen IA | `ai_photo_product` | images.generate |
| 3 | `POST /products/ai-from-photo` | Llenar desde Foto | `ai_photo_product` | chat (Vision gpt-4.1) |
| 4 | `POST /banners/ai-generate` | Banner IA | `ai_banner_generation` | images.generate |
| 5 | `POST /products/:id/confirm-ai-image` | Confirmar temp → definitivo | — (no consume créditos) | — |

---

## Archivos a modificar

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `ai-generation/prompts/index.ts` | +3 prompts: product photo, banner, vision + ProductDraft type |
| 2 | `ai-generation/ai-generation.service.ts` | +4 métodos públicos + `callOpenAIImageGeneration` + `callOpenAIVision` + `preprocessImageForVision` + `validateAndSanitizeVisionResponse` + generating locks + NON_RETRYABLE_ERRORS |
| 3 | `ai-generation/ai-generation.controller.ts` | +4 endpoints + confirm-ai-image endpoint + lock acquire/release pattern |
| 4 | `ai-generation/ai-generation.module.ts` | +imports: ImageProcessingModule, StorageModule, MediaLibraryModule, ScheduleModule |
| 5 | `ai-credits/ai-credits.service.ts` | +`'ai_banner_generation'` en AI_ACTION_CODES + advisory lock en consumeCredit |
| 6 | `ai-generation/ai-generation.service.spec.ts` | +tests unitarios (16 base + 16 edge cases) |
| 7 | `test/ai-generation.e2e.spec.ts` | +tests E2E (10 base + 16 edge cases) |

## Archivos a crear

| # | Archivo | Propósito |
|---|---------|-----------|
| 1 | `migrations/admin/YYYYMMDD_ai_image_features.sql` | Pricing + packs + welcome |
| 2 | `ai-generation/ai-temp-cleanup.service.ts` | Cron job cleanup de imágenes temporales huérfanas (cada 30 min) |

---

## Tests

### Unitarios (+16)

| # | Test |
|---|------|
| 1 | aiProductFill genera descripción sin foto |
| 2 | aiProductFill genera descripción + foto cuando include_photo=true |
| 3 | aiProductFill sin créditos de foto → solo descripción |
| 4 | generateProductPhoto lee producto de BD y genera imagen |
| 5 | generateProductPhoto con producto inexistente → 404 |
| 6 | generateProductPhoto incluye Store DNA en prompt |
| 7 | generateProductPhoto mapea estilos correctamente |
| 8 | generateProductFromPhoto envía imagen como base64 data URL a Vision |
| 9 | generateProductFromPhoto parsea JSON de respuesta Vision |
| 10 | generateProductFromPhoto con imagen > 5MB → error |
| 11 | generateBanner retorna buffer de imagen |
| 12 | generateBanner con prompt vacío → error |
| 13 | callOpenAIImageGeneration usa modelo correcto por tier |
| 14 | callOpenAIImageGeneration reintenta con backoff 3s |
| 15 | callOpenAIImageGeneration retorna null tras agotar reintentos |
| 16 | callOpenAIImageGeneration sin API key → error |

### E2E (+10)

| # | Test |
|---|------|
| 1 | POST /products/ai-fill sin auth → 403 |
| 2 | POST /products/ai-fill → 200 (solo descripción) |
| 3 | POST /products/ai-fill con include_photo → 200 |
| 4 | POST /products/:id/ai-photo sin créditos → 402 |
| 5 | POST /products/:id/ai-photo → 200 |
| 6 | POST /products/ai-from-photo sin auth → 403 |
| 7 | POST /products/ai-from-photo → 200 |
| 8 | POST /banners/ai-generate sin créditos → 402 |
| 9 | POST /banners/ai-generate → 200 |
| 10 | Fallo OpenAI → NO consume créditos |

### Edge Cases (+16) — Gap #16

| # | Edge case | Feature | HTTP |
|---|-----------|---------|------|
| 1 | OpenAI rechaza por content_policy_violation → no retry, no consume crédito | Todas | 422 |
| 2 | Request concurrente mismo tenant, créditos insuficientes para ambos → solo uno pasa | Todas | 402 |
| 3 | Storage upload falla después de imagen generada → crédito NO consumido | F1, F2, F4 | 502 |
| 4 | Frontend hace retry mientras generación en curso → 429 TOO_MANY_REQUESTS | Todas | 429 |
| 5 | Imagen de 0 bytes enviada a ai-from-photo | F3 | 400 |
| 6 | Imagen válida MIME pero corrompida internamente (sharp lanza) | F3 | 400 |
| 7 | Imagen HEIC → se acepta y convierte a JPEG correctamente | F3 | 200 |
| 8 | Foto con EXIF rotation 90° → producto procesado orientado correctamente | F3 | 200 |
| 9 | Vision devuelve JSON con `suggested_price: "caro"` → sanitizado a null | F3 | 200 |
| 10 | Vision devuelve JSON con HTML en description → stripped | F3 | 200 |
| 11 | `getOrGenerateStoreDNA()` lanza → fallback sin DNA, generación exitosa | F2, F3, F4 | 200 |
| 12 | Admin no confirma imagen temp → cron la limpia después de 2h | F1 | — |
| 13 | Prompt banner con inyección (`"ignore previous instructions"`) → 400 | F4 | 400 |
| 14 | OpenAI tarda >55s → timeout cancela → no consume crédito | Todas | 504 |
| 15 | `callOpenAIImageGeneration` retorna `b64_json: null` con `data[0]` presente → retry | Todas | — |
| 16 | Producto con `name = null` llega a ai-photo → 422 descriptivo | F2 | 422 |

---

## Orden de implementación

1. Migration SQL (pricing updates + ai_banner_generation)
2. `AI_ACTION_CODES` + prompts + types (`ProductDraft`)
3. Service: `preprocessImageForVision()` + `validateAndSanitizeVisionResponse()`
4. Service: `callOpenAIImageGeneration()` (con error bifurcation + AbortSignal)
5. Service: `callOpenAIVision()` (con gpt-4.1 + schema validation)
6. Service: 4 métodos públicos + generating locks
7. `ai-credits.service.ts`: advisory lock en `consumeCredit()`
8. `ai-temp-cleanup.service.ts`: cron de cleanup
9. Module: agregar imports (ImageProcessing, Storage, MediaLibrary, Schedule)
10. Controller: 5 endpoints (4 features + confirm-ai-image)
11. Tests unitarios (16 base)
12. Tests edge cases (16 adicionales)
13. Tests E2E (10 base)
14. Validación: lint + typecheck + build + tests

---

## Costos OpenAI (verificados marzo 2026)

| Feature | Tier | Modelo | Quality | Size | Costo/uso | Créditos |
|---------|------|--------|---------|------|-----------|----------|
| Llenar con IA (texto) | Normal | gpt-4o-mini | — | — | ~$0.005 | 1 |
| Llenar con IA (foto) | Normal | gpt-image-1-mini | medium | 1024x1024 | ~$0.015 | 5 |
| Generar Imagen | Normal | gpt-image-1-mini | medium | 1024x1024 | ~$0.015 | 5 |
| Generar Imagen | Pro | gpt-image-1.5 | high | 1024x1024 | ~$0.140 | 8 |
| Llenar desde Foto (Vision) | Normal | gpt-4.1-mini | low detail | — | ~$0.003-0.006 | 5 |
| Llenar desde Foto (Vision) | Pro | gpt-4.1 | high detail | — | ~$0.01-0.03 | 8 |
| Banner | Normal | gpt-image-1-mini | medium | 1536x1024 | ~$0.022 | 5 |
| Banner | Pro | gpt-image-1.5 | high | 1536x1024 | ~$0.200 | 10 |

**Nota:** Los costos de Vision (chat.completions con imagen) dependen del tamaño de la imagen en tokens. Los costos de image generation son fijos por tamaño/quality.

---

## Riesgos y mitigaciones

| Riesgo | Mitigación |
|--------|-----------|
| Latencia alta generación imagen (15-45s) | Spinner "Generando imagen...", AbortSignal 55s (Gap #7) |
| Foto generada no representa el producto real | Preview + opción regenerar; prompt incluye descripción completa |
| Vision no reconoce bien producto desde foto amateur | Fallback genérico; schema validation sanitiza output (Gap #8) |
| Costos Pro altos | Margen mínimo 5x; monitoring; caps por cuenta |
| Rate limits OpenAI | Retry backoff 3s/6s, NO retry en content policy (Gap #4) |
| Race condition créditos concurrentes | Advisory lock por (account_id, action_code) (Gap #3) |
| Doble generación por retry frontend | Lock in-memory de generación en curso → 429 (Gap #9) |
| Imágenes temporales huérfanas | Cron cleanup cada 30min, TTL 2h (Gap #5) |
| Storage falla post-generación | Crédito se consume SOLO al final del pipeline completo (Gap #6) |
| OpenAI content policy rechaza prompt | Error 422 descriptivo sin retry ni consumo de crédito (Gap #4) |
| StoreDNA no disponible | Fallback sin DNA — generación funcional pero menos personalizada (Gap #13) |
| Fotos HEIC de iPhone | Conversión automática con sharp (Gap #10) |
| Fotos rotadas por EXIF | `sharp().rotate()` auto-corrige antes de enviar a Vision (Gap #11) |
| suggested_price desactualizado | Flag `is_price_estimated: true` + tooltip en frontend (Gap #12) |
| Producto supera límite de imágenes | Validación pre-generación con 422 descriptivo (Gap #14) |
| Storage quota excedida | Pre-check antes de generar + tracking en usage_event (Gap #15) |

---

## Validación de Inputs por Endpoint

### 1. `POST /products/ai-fill` — Llenar con IA

| Campo | Tipo | Requerido | Validación | Error si falla |
|-------|------|-----------|------------|----------------|
| `name` | string | **Sí** | Min 3 chars, max 200 chars, trim | 400 `"name must be between 3 and 200 characters"` |
| `category_name` | string | No | Max 100 chars | 400 |
| `include_photo` | boolean | No | Default `false` | — |
| `photo_style` | string | No | Enum: `studio`, `lifestyle`, `flat_lay`, `minimalist`, `creative`. Default `studio` | 400 `"Invalid photo_style"` |
| `instructions` | string | No | Max 300 chars | 400 |
| `ai_tier` | string | No | Enum: `normal`, `pro`. Default `normal` | 400 (validado por AiCreditsGuard) |

**Validación de negocio:**
- Si `include_photo=true`, se valida créditos de `ai_photo_product` además de `ai_product_description`
- Si no hay créditos de foto pero sí de texto → genera solo descripción (no falla, informa en response)
- `name` se sanitiza: trim, colapsar espacios múltiples

### 2. `POST /products/:id/ai-photo` — Generar Imagen IA

| Campo | Tipo | Requerido | Validación | Error si falla |
|-------|------|-----------|------------|----------------|
| `:id` (param) | UUID | **Sí** | UUID v4 válido | 400 `"Invalid product ID"` |
| `style` | string | No | Enum: `studio`, `lifestyle`, `flat_lay`, `minimalist`, `creative`. Default `studio` | 400 `"Invalid style"` |
| `instructions` | string | No | Max 300 chars, sin URLs ni HTML | 400 |
| `ai_tier` | string | No | `normal` \| `pro`. Default `normal` | 400 |

**Validación de negocio:**
- El producto debe existir Y pertenecer al `client_id` del request → 404 si no
- El producto debe tener al menos `name` (no nulo, no vacío) → 422 `"Product must have a name to generate a photo"`
- Se recomienda que tenga `description` y `categoryName` para mejor resultado, pero no son requeridos

**Datos leídos de BD (tabla `products`):**
- `name` — siempre presente, base del prompt
- `description` — truncada a 200 chars para el prompt
- `categoryName` — contexto de categoría
- `originalPrice` — contexto de precio (no se incluye en prompt de imagen)
- `material` — si existe, se agrega como atributo al prompt
- `tags` — si existen, se agregan como contexto

### 3. `POST /products/ai-from-photo` — Llenar desde Foto (Vision)

| Campo | Tipo | Requerido | Validación | Error si falla |
|-------|------|-----------|------------|----------------|
| `image` (file) | Multipart | **Sí** | MIME: `image/jpeg`, `image/png`, `image/webp`, `image/heic`, `image/heif`. Max 5MB. Min 10KB | 400 `"Image required"` / 413 `"Image too large (max 5MB)"` |
| `ai_tier` | string | No | `normal` \| `pro`. Default `normal` | 400 |

**Validación de imagen:**
- MIME type verificado por magic bytes (no confiar solo en Content-Type header)
- **HEIC/HEIF aceptado** (Gap #10): conversión automática a JPEG via `sharp` (requiere `libheif`)
- **EXIF orientation** (Gap #11): `sharp().rotate()` auto-corrige antes de procesar
- Dimensiones mínimas: 200x200px (imágenes más chicas no dan buen resultado en Vision)
- Dimensiones máximas: 20MP (20 megapixels) — se redimensiona antes de enviar si excede
- Si la imagen es > 1MB, se comprime a webp quality 85 antes de convertir a base64 (ahorra tokens de Vision)

**Datos generados por Vision (output — sanitizados, Gap #8):**
- `name` — string, max 80 chars, HTML stripped
- `description` — string, max 1500 chars, HTML stripped
- `suggested_category` — string (max 100 chars) o null
- `suggested_price` — number positivo o null (validado: no string, no negativo, <100M)
- `is_price_estimated` — boolean, siempre `true` cuando `suggested_price` no es null (Gap #12)
- `attributes` — object plano `{ color?, material?, tipo?, marca? }` — max 10 keys, valores string max 200 chars

### 4. `POST /banners/ai-generate` — Banner IA

| Campo | Tipo | Requerido | Validación | Error si falla |
|-------|------|-----------|------------|----------------|
| `prompt` | string | **Sí** | Min 10 chars, max 500 chars, trim | 400 `"prompt must be between 10 and 500 characters"` |
| `type` | string | **Sí** | Enum: `desktop`, `mobile` | 400 `"type must be 'desktop' or 'mobile'"` |
| `style` | string | No | Enum: `photorealistic`, `illustrated`, `abstract`, `gradient`, `seasonal`. Default `photorealistic` | 400 `"Invalid style"` |
| `ai_tier` | string | No | `normal` \| `pro`. Default `normal` | 400 |

**Validación de negocio:**
- `prompt` se sanitiza: trim, colapsar espacios, eliminar URLs y HTML tags
- El prompt no debe contener instrucciones de inyección tipo "ignore previous instructions" → 400 `"Invalid prompt content"`

---

## Guía de Ejemplos para Buenos Resultados

### Feature 1: Llenar con IA — Ejemplos

El nombre del producto es lo más importante. Cuanto más descriptivo, mejor resultado.

#### Buenos ejemplos

| Nombre | Categoría | Resultado esperado |
|--------|-----------|-------------------|
| `Remera Oversize Algodón Premium Negra` | Remeras | Descripción enfocada en comodidad, algodón, versatilidad |
| `Zapatillas Running Nike Air Max 90` | Calzado Deportivo | Descripción con beneficios de amortiguación, estilo retro |
| `Set de Skincare Facial 3 Pasos Vitamina C` | Belleza | Descripción con rutina de cuidado, beneficios de vitamina C |
| `Mesa Ratona Industrial Hierro y Madera` | Muebles | Descripción con estilo industrial, dimensiones, materiales |

#### Malos ejemplos (la IA no tiene suficiente contexto)

| Nombre | Problema | Cómo mejorar |
|--------|----------|-------------|
| `Remera` | Muy genérico, sin detalles | `Remera Cuello Redondo Algodón Blanca` |
| `Producto 1` | Sin información real | Usar nombre comercial descriptivo |
| `abc123` | SKU, no nombre | Usar nombre legible para humanos |

#### Tips para el admin

> **Tip:** Incluí material, color y característica diferenciadora en el nombre.
> - "Remera" → "Remera Oversize Algodón Peinado Negra"
> - "Pantalón" → "Pantalón Cargo Gabardina Stretch Verde Militar"
> - "Vela" → "Vela Aromática Soja Natural Lavanda 200g"

---

### Feature 2: Generar Imagen IA — Ejemplos por estilo

La IA lee los datos del producto de la base de datos. El campo `instructions` es opcional y permite ajustar el resultado.

#### Estilos y cuándo usarlos

| Estilo | Ideal para | Ejemplo visual |
|--------|-----------|----------------|
| `studio` | Cualquier producto, catálogo profesional | Fondo gris claro, producto centrado, sombra suave |
| `lifestyle` | Ropa, accesorios, decoración | Modelo usando la remera en un café |
| `flat_lay` | Cosmética, accesorios, kits, sets | Vista desde arriba sobre mesa de madera |
| `minimalist` | Electrónica, productos simples | Fondo blanco puro, sin distracciones |
| `creative` | Productos premium, joyería, arte | Iluminación dramática, composición artística |

#### Ejemplos de `instructions` opcionales

| Producto | Estilo | Instructions | Resultado |
|----------|--------|-------------|-----------|
| Remera Negra | `studio` | `"Fondo blanco, doblada prolijamente"` | Remera doblada sobre fondo blanco |
| Zapatillas | `lifestyle` | `"Persona caminando en la calle, vista lateral"` | Zapatillas en contexto urbano |
| Crema Facial | `flat_lay` | `"Con flores secas y toalla blanca"` | Flat lay spa/wellness |
| Notebook | `minimalist` | `"Vista en ángulo 45 grados, pantalla encendida"` | Producto tech limpio |
| Collar de Plata | `creative` | `"Sobre terciopelo negro, luz puntual"` | Joyería editorial |

#### Tips para el admin

> **Tip 1:** El estilo `studio` funciona bien para la mayoría de los productos. Usalo como default.
>
> **Tip 2:** Si el producto no tiene descripción detallada en la ficha, agregá instructions con detalles: color, material, tamaño.
>
> **Tip 3:** Evitá instructions contradictorias: "fondo blanco" + estilo `lifestyle` genera resultados confusos. Si querés fondo blanco, usá estilo `minimalist` o `studio`.
>
> **Tip 4:** Las fotos generadas son cuadradas (1024x1024). Son ideales para catálogo y grillas de productos.

---

### Feature 3: Llenar desde Foto — Ejemplos

La IA analiza la foto real que subís y extrae toda la información que pueda ver.

#### Buenas fotos (mejor resultado)

| Tipo de foto | Qué reconoce bien | Ejemplo |
|-------------|-------------------|---------|
| Producto aislado, fondo limpio | Nombre, categoría, color, material, forma | Foto de remera sobre fondo blanco |
| Producto con etiqueta visible | Marca, composición, talle | Foto donde se ve la etiqueta |
| Producto en packaging | Nombre comercial, marca, variante | Caja del producto con info impresa |
| Múltiples ángulos (1 foto) | Detalles del producto, textura | Collage de producto en distintos ángulos |

#### Malas fotos (resultado pobre)

| Tipo de foto | Problema | Cómo mejorar |
|-------------|----------|-------------|
| Foto borrosa/oscura | No puede identificar detalles | Foto nítida, buena iluminación |
| Muchos productos juntos | No sabe cuál analizar | 1 producto por foto |
| Screenshot de otra tienda | Puede copiar texto no deseado | Foto propia del producto |
| Foto muy lejos | Producto muy chico en la imagen | Encuadre cerrado del producto |

#### Tips para el admin

> **Tip 1:** La foto ideal es un producto solo, bien iluminado, que ocupe al menos el 50% del encuadre.
>
> **Tip 2:** Si el producto tiene etiqueta con marca o composición, incluila visible en la foto — la IA la puede leer.
>
> **Tip 3:** La IA NO inventa datos. Si no puede determinar el material o la marca, devuelve `null` en esos campos. Es mejor que inventar.
>
> **Tip 4:** Para mejores resultados, usá el tier **Pro** — usa GPT-4o con `detail: high` que analiza la imagen en mayor resolución.

---

### Feature 4: Banner IA — Ejemplos de prompts

El prompt es la descripción de lo que querés en el banner. Cuanto más específico, mejor.

#### Buenos prompts

| Prompt | Estilo | Tipo | Resultado esperado |
|--------|--------|------|-------------------|
| `"Ofertas de verano, colores tropicales, palmeras y playa"` | photorealistic | desktop | Banner con estética tropical, colores cálidos |
| `"Descuentos de invierno, tonos azules y blancos, copos de nieve"` | seasonal | desktop | Banner invernal, paleta fría |
| `"Colección nueva primavera, flores y colores pastel"` | illustrated | mobile | Banner ilustrado con flores, tono suave |
| `"Black Friday, fondo negro con destellos dorados y rojos"` | gradient | desktop | Banner dramático, elegante |
| `"Envío gratis, fondo celeste con nubes y paquetes"` | illustrated | desktop | Banner promocional friendly |

#### Malos prompts

| Prompt | Problema | Cómo mejorar |
|--------|----------|-------------|
| `"Banner"` | Sin descripción, demasiado vago | Describir temática, colores, ambiente |
| `"Oferta 30% OFF en remeras"` | Pide texto — la IA NO genera texto legible | Describir la estética, no el texto |
| `"Copiar el banner de Nike"` | Violación de marca, resultado impredecible | Describir el estilo deseado: "deportivo, dinámico, colores vibrantes" |
| `"foto de mi tienda"` | La IA no conoce tu tienda | Describir colores, ambiente, temática |

#### Tips para el admin

> **Tip 1:** Los banners se generan **sin texto**. El texto (ej: "30% OFF") se agrega después como overlay en el editor del storefront. Pedí la estética, no las palabras.
>
> **Tip 2:** Mencioná colores específicos si tenés identidad de marca: "tonos rosa y dorado" funciona mejor que "bonito".
>
> **Tip 3:** Para banners desktop, pedí composiciones horizontales con espacio libre en el centro o arriba (ahí va el texto overlay).
>
> **Tip 4:** El estilo `gradient` es ideal para banners simples y profesionales cuando no tenés una idea clara. Combinalo con colores de tu marca.
>
> **Tip 5:** Usá el tier **Pro** para banners hero (el principal de la home). Para banners secundarios, el tier Normal alcanza.

---

## Verificación

1. `npm run lint` — 0 errores
2. `npm run typecheck` — 0 errores
3. `npm run build && ls dist/main.js` — build exitoso
4. `npm run test -- --testPathPattern=ai-generation` — 32 unit tests pasan (16 base + 16 edge)
5. `npm run test:e2e -- --testPathPattern=ai-generation` — 26 E2E tests pasan (10 base + 16 edge)
6. Migration SQL sin errores
7. `sharp` soporta HEIC (verificar `sharp.format.heif.input.file` en runtime)

## Checklist de Gaps Resueltos

```
CRÍTICOS:
  ✅ #1 Modelos OpenAI verificados — gpt-image-1-mini y gpt-image-1.5 existen
  ✅ #2 Tamaños verificados — 1536x1024 y 1024x1536 soportados por GPT Image
  ✅ #3 Advisory lock para race condition de créditos
  ✅ #4 Bifurcar errores OpenAI (content policy ≠ servicio)

ALTOS:
  ✅ #5 TTL + cron cleanup para imágenes temporales (2h + cada 30min)
  ✅ #6 Endpoint "confirmar temp → definitivo" + flujo de consumo clarificado
  ✅ #7 AbortSignal timeout 55s en SDK calls
  ✅ #8 Schema validation post-parse de Vision response
  ✅ #9 Lock de generación en curso por tenant → 429

MEDIOS:
  ✅ #10 HEIC/HEIF aceptado con conversión automática
  ✅ #11 sharp().rotate() para EXIF orientation
  ✅ #12 Flag is_price_estimated en suggested_price
  ✅ #13 Fallback si StoreDNA falla (genera sin DNA)
  ✅ #14 Verificar límite imágenes/producto antes de crear
  ✅ #15 Contabilizar storage generado en usage_event

TESTS:
  ✅ #16 +16 edge cases adicionales documentados
```

# Casos de Prueba — Sistema AI Credits + Store DNA + Column Mapping + Admin Pricing
> NovaVision · Fecha: 2026-03-18 · Estado: Pre-implementación

---

## Convenciones

| Símbolo | Significado |
|---------|-------------|
| ✅ | Happy path — resultado esperado exitoso |
| ❌ | Resultado esperado de error/rechazo |
| ⚠️ | Edge case — comportamiento sutil o crítico |
| 🔒 | Aislamiento multi-tenant — no debe cruzar datos |
| 🔁 | Concurrencia / race condition |
| 💸 | Impacto económico / billing |

Todos los tests asumen que las migraciones SQL están aplicadas y los seeds de `ai_feature_pricing` y `ai_welcome_credit_config` ejecutados.

---

## SECCIÓN 1 — AiCreditsService: Balance y Ledger

### TC-01 · Balance inicial de cuenta nueva ✅
**Precondición:** Cuenta recién provisionada (plan `starter`), step `GRANT_WELCOME_AI_CREDITS` ejecutado.
**Acción:** `GET /ai-credits/balances`
**Esperado:**
```json
[
  { "action_code": "ai_product_description", "available": 5 },
  { "action_code": "ai_qa_answer",            "available": 10 },
  { "action_code": "ai_faq_generation",        "available": 3 },
  { "action_code": "ai_photo_product",         "available": 3 },
  { "action_code": "ai_column_mapping",        "available": 2 }
]
```
**Validar en DB:** `account_action_credit_ledger` tiene 5 rows con `credits_delta > 0`, `expires_at = NOW() + 90 days`.

---

### TC-02 · Balance inicial plan growth ✅
**Precondición:** Cuenta recién provisionada con plan `growth`.
**Acción:** `GET /ai-credits/balances`
**Esperado:** `ai_product_description.available = 20`, `ai_qa_answer.available = 50`, `expires_at = NOW() + 120 days`.

---

### TC-03 · `getBalance` retorna 0 cuando no hay ledger rows ✅
**Precondición:** Cuenta nueva sin paso de provisioning ejecutado.
**Acción:** `AiCreditsService.getBalance(accountId, 'ai_product_description')`
**Esperado:** `0` (no excepción, cero por defecto).

---

### TC-04 · Ledger filtra créditos expirados ⚠️
**Precondición:** Insertar manualmente en `account_action_credit_ledger` un row con `credits_delta = 10`, `expires_at = NOW() - 1 day`.
**Acción:** `GET /ai-credits/balances`
**Esperado:** `available = 0` para ese `action_code`. La vista `account_action_credit_balance_view` excluye expirados.
**Anti-patrón a verificar:** `getBalance()` NO debe sumar rows expirados.

---

### TC-05 · Suma correcta con múltiples grants parciales ✅
**Precondición:** Insertar 3 grants: +5, +10, -3 (consumo) para `ai_product_description`.
**Acción:** `AiCreditsService.getBalance(accountId, 'ai_product_description')`
**Esperado:** `12`.

---

### TC-06 · Balance negativo imposible ⚠️
**Precondición:** Balance actual = 1.
**Acción:** Intentar `consumeCredit(accountId, clientId, 'ai_product_description', 'pro')` (costo pro = 3).
**Esperado:** `assertAvailable()` lanza excepción antes de insertar la row negativa. Balance permanece en 1.

---

## SECCIÓN 2 — AiCreditsGuard: Interceptación y errores

### TC-07 · Guard pasa cuando hay créditos suficientes ✅
**Precondición:** Balance `ai_product_description` = 5, tier `normal` (costo = 1).
**Acción:** `POST /products/:id/ai-description` con `{ ai_tier: "normal" }`.
**Esperado:** HTTP 200, balance decrementado a 4.

---

### TC-08 · Guard retorna 402 con payload completo ❌
**Precondición:** Balance `ai_product_description` = 0.
**Acción:** `POST /products/:id/ai-description` con `{ ai_tier: "normal" }`.
**Esperado HTTP 402:**
```json
{
  "error": "insufficient_ai_credits",
  "action_code": "ai_product_description",
  "tier": "normal",
  "required": 1,
  "available": 0,
  "feature_label": "Descripcion de Producto",
  "addon_store_url": "/admin-dashboard?addonStore&family=ai"
}
```
**Validar:** Ningún row de consumo insertado en `account_action_credit_ledger`.

---

### TC-09 · Guard usa pricing de DB, no hardcoded ⚠️
**Precondición:** Cambiar `credit_cost` de `(ai_product_description, normal)` a `2` vía admin dashboard. Balance = 1.
**Acción:** `POST /products/:id/ai-description` con `{ ai_tier: "normal" }`.
**Esperado:** HTTP 402 (requiere 2, disponible 1). Confirma que el guard lee `ai_feature_pricing` en runtime.

---

### TC-10 · Tier por defecto es "normal" cuando no se especifica ✅
**Precondición:** Body sin campo `ai_tier`.
**Acción:** `POST /products/:id/ai-description` con `{}`.
**Esperado:** Guard evalúa costo de tier `normal`. No 400 por falta de campo.

---

### TC-11 · Tier inválido rechazado ❌
**Acción:** `POST /products/:id/ai-description` con `{ ai_tier: "ultra" }`.
**Esperado:** HTTP 400, error de validación. No se busca en `ai_feature_pricing`.

---

### TC-12 · Feature inactiva (`is_active = false`) bloquea la acción ❌
**Precondición:** Setear `is_active = false` para `(ai_qa_answer, normal)` en `ai_feature_pricing`.
**Acción:** `POST /questions/:id/ai-suggest` con `{ ai_tier: "normal" }`.
**Esperado:** HTTP 402 o HTTP 503 con mensaje "feature_disabled". Balance no alterado.

---

## SECCIÓN 3 — Consumo y débito de créditos

### TC-13 · Consumo Normal registra metadata correcta ✅
**Acción:** `POST /products/:id/ai-description` exitoso (tier normal).
**Validar en DB:**
```sql
SELECT * FROM account_action_credit_ledger
WHERE action_code = 'ai_product_description'
ORDER BY created_at DESC LIMIT 1;
```
Debe contener: `credits_delta = -1`, `addon_key = NULL`, `metadata->>'tier' = 'normal'`, `metadata->>'client_id' = :clientId`.

---

### TC-14 · Consumo Pro débita créditos correctos ✅
**Precondición:** Balance = 5, tier `pro` (costo = 3).
**Acción:** Invocación exitosa tier pro.
**Esperado:** Balance = 2. Row en ledger: `credits_delta = -3`, `metadata->>'tier' = 'pro'`.

---

### TC-15 · Consumo falla si OpenAI falla — no se cobra ⚠️
**Precondición:** Simular fallo de OpenAI (timeout o 500).
**Esperado:** Ningún row de consumo en ledger. Balance intacto. HTTP 502 al cliente.
**Regla:** El débito solo ocurre DESPUÉS de respuesta exitosa de OpenAI.

---

### TC-16 · Idempotencia — doble submit no dobla el débito 🔁
**Escenario:** Usuario hace doble click y el frontend envía 2 requests simultáneos.
**Esperado:** Solo 1 crédito debitado. El segundo request debe recibir 429 o el guard debe serializar.
**Mecanismo sugerido:** Redis lock por `(accountId, actionCode)` con TTL 5s.

---

## SECCIÓN 4 — Store DNA: Generación y Cache

### TC-17 · Store DNA se genera en provisioning ✅
**Precondición:** Correr provisioning completo para cuenta nueva.
**Esperado:** Row en `store_dna_cache` con `client_id`, `dna_instruction` no vacío, `expires_at = NOW() + 24h`, `invalidated_at = NULL`.

---

### TC-18 · `getOrGenerateStoreDNA` usa cache cuando es válido ✅
**Precondición:** Row válido en `store_dna_cache` (no expirado, no invalidado).
**Acción:** Llamar `getOrGenerateStoreDNA(clientId)` dos veces seguidas.
**Esperado:** Solo 1 llamada a OpenAI. Segunda llamada retorna el `dna_instruction` cacheado.
**Validar:** `generated_at` no cambia entre las dos llamadas.

---

### TC-19 · Cache expirado regenera automáticamente ⚠️
**Precondición:** Row en `store_dna_cache` con `expires_at = NOW() - 1 minute`.
**Acción:** `getOrGenerateStoreDNA(clientId)`.
**Esperado:** Llama a OpenAI, actualiza el row (nuevo `generated_at`, nuevo `expires_at`, nuevo `dna_instruction`).

---

### TC-20 · Invalidación manual fuerza regeneración ✅
**Acción:** `POST /ai-credits/store-dna/regenerate`.
**Esperado:** `invalidated_at` se setea a NOW(). Próxima llamada a `getOrGenerateStoreDNA` ignora el row y regenera.

---

### TC-21 · Store DNA con datos mínimos (tienda vacía) ⚠️
**Precondición:** Tienda sin productos, sin categorías, sin `seo_settings`.
**Acción:** `generateStoreDNA(clientId, 'normal')`.
**Esperado:** Se genera igualmente con datos disponibles (nombre, país). No lanza excepción. `dna_instruction` menciona que la tienda está siendo configurada.

---

### TC-22 · Store DNA NO consume créditos 💸
**Precondición:** Balance `ai_product_description` = 2.
**Acción:** `POST /ai-credits/store-dna/regenerate`.
**Esperado:** Balance permanece en 2. Ningún row negativo en `account_action_credit_ledger` para ningún `action_code`.

---

### TC-23 · Store DNA inyectado en features IA ⚠️
**Precondición:** `store_dna_cache` con `dna_instruction = "Sos el asistente de Luna Textil..."`.
**Acción:** `POST /products/:id/ai-description` (tier normal).
**Esperado:** El system prompt enviado a OpenAI comienza con el contenido del DNA (verificar via log/mock). El resultado final debe ser coherente con la identidad de la tienda.

---

### TC-24 · Tiendas distintas no comparten DNA 🔒
**Precondición:** Clients `f2d3f270` (urbanprint) e `19986d95` (tienda test) con DNAs distintos.
**Acción:** Feature IA para urbanprint.
**Esperado:** Usa DNA de urbanprint, NO el de tienda test. Validar que `store_dna_cache` se filtra por `client_id`.

---

### TC-25 · Campos nuevos de nv_accounts alimentan el DNA ✅
**Precondición:** Setear `industry = 'indumentaria'`, `brand_tone = 'casual'`, `target_audience = 'mujeres 25-40'` en `nv_accounts`.
**Acción:** `generateStoreDNA`.
**Esperado:** `store_context` en el row de cache incluye estos campos. `dna_instruction` los refleja.

---

### TC-26 · Cambio de categorías invalida DNA ⚠️
**Precondición:** DNA cacheado válido.
**Acción:** Crear/borrar una categoría.
**Esperado:** `invalidateStoreDNA(clientId)` es llamado. El próximo uso regenera.
**Validar:** Evento de invalidación logeado.

---

## SECCIÓN 5 — Welcome Credits y Provisioning

### TC-27 · Step GRANT_WELCOME_AI_CREDITS ejecutado después de PROVISION_CLIENT ✅
**Acción:** Correr provisioning job completo.
**Validar en `provisioning_job_steps`:**
```sql
SELECT step_name, status FROM provisioning_job_steps
WHERE job_id = :jobId ORDER BY created_at;
```
`GRANT_WELCOME_AI_CREDITS` debe aparecer con `status = 'completed'` y ejecutarse DESPUÉS de `PROVISION_CLIENT`.

---

### TC-28 · Welcome credits del plan correcto 💸
**Escenario A (starter):** `ai_product_description = 5`, `ai_qa_answer = 10`, etc.
**Escenario B (growth):** `ai_product_description = 20`, `ai_qa_answer = 50`, etc.
**Escenario C (enterprise):** `ai_product_description = 50`, `ai_qa_answer = 200`, etc.

---

### TC-29 · Welcome credits expiración según plan 💸
**Plan starter:** `expires_at = provisioning_timestamp + 90 days`.
**Plan growth:** `expires_at = provisioning_timestamp + 120 days`.
**Plan enterprise:** `expires_at = provisioning_timestamp + 180 days`.

---

### TC-30 · Welcome credits no se otorgan si config inactiva ⚠️
**Precondición:** Setear `is_active = false` en `ai_welcome_credit_config` para plan `starter`.
**Acción:** Provisionar cuenta nueva (plan starter).
**Esperado:** No se insertan rows de grant para ese `action_code`. Otros `action_code` activos sí se otorgan.

---

### TC-31 · Welcome credits no se duplican si provisioning re-ejecuta el step ⚠️
**Escenario:** Por algún fallo, el step `GRANT_WELCOME_AI_CREDITS` se ejecuta dos veces.
**Esperado:** Idempotencia garantizada (upsert o check previo). Balance final = welcome credits de 1 sola ejecución.

---

### TC-32 · Grant manual (super-admin) acumula sobre existing balance ✅
**Precondición:** Balance `ai_product_description` = 5.
**Acción:** `POST /admin/ai-credits/clients/:accountId/adjust` con `{ action_code: "ai_product_description", amount: 10, reason: "compensacion" }`.
**Esperado:** Balance = 15. Nuevo row en ledger con `credits_delta = +10`, `metadata->>'reason' = 'compensacion'`, `metadata->>'granted_by' = superAdminId`.

---

### TC-33 · Grant con expires_days = 0 → no expira ✅
**Acción:** Grant manual con `expires_days = 0` o `expires_days = null`.
**Esperado:** Row en ledger con `expires_at = NULL`. La vista los suma indefinidamente.

---

## SECCIÓN 6 — AI Column Mapping para Import

### TC-34 · Detección automática TiendaNube sin crédito 💸
**Input:** Archivo Excel con headers: `Identificador de URL`, `Nombre del Producto`, `Categoria`, `Precio`, `Variante1`.
**Acción:** `POST /import-wizard/analyze-file`
**Esperado:**
```json
{
  "platform_detected": "tiendanube",
  "credit_consumed": false,
  "mapping_suggestions": [...],
  "tier_used": null
}
```
Balance de `ai_column_mapping` intacto.

---

### TC-35 · Detección WooCommerce sin crédito 💸
**Input:** Headers: `post_title`, `regular_price`, `_sku`, `tax:product_cat`, `post_content`.
**Esperado:** `platform_detected = "woocommerce"`, `credit_consumed = false`.

---

### TC-36 · Detección MercadoLibre sin crédito 💸
**Input:** Headers: `Titulo de publicacion`, `Precio`, `SKU del vendedor`, `Categoria`.
**Esperado:** `platform_detected = "mercadolibre"`, `credit_consumed = false`.

---

### TC-37 · Archivo desconocido consume crédito ✅
**Precondición:** Balance `ai_column_mapping` = 2, tier normal (costo = 1).
**Input:** Headers sin firma conocida: `Articulo`, `Costo`, `Deposito`, `Proveedor`.
**Acción:** `POST /import-wizard/analyze-file` con `{ ai_tier: "normal" }`.
**Esperado:** `credit_consumed = true`, `tier_used = "normal"`. Balance = 1.

---

### TC-38 · Mapeo AI con confianza mínima por columna ✅
**Esperado en `mapping_suggestions`:** Cada item incluye `{ source, target, confidence, source_type }` donde `confidence` es entre 0 y 100 y `source_type` es `"ai"` o `"platform"`.

---

### TC-39 · Sin créditos para archivo desconocido → 402 ❌
**Precondición:** Balance `ai_column_mapping` = 0.
**Input:** Archivo de plataforma desconocida.
**Esperado:** HTTP 402 con `error: "insufficient_ai_credits"`, `action_code: "ai_column_mapping"`. Archivo no procesado.

---

### TC-40 · Archivo supera límite de tamaño → 413 ❌
**Input:** Archivo de 6MB (límite es 5MB).
**Esperado:** HTTP 413, mensaje claro. Sin débito de créditos.

---

### TC-41 · Archivo supera límite de filas → 422 ❌
**Input:** Archivo CSV de 501 filas (límite es 500).
**Esperado:** HTTP 422, mensaje indicando el límite. Sin débito de créditos.

---

### TC-42 · Archivo con encoding inválido → 422 ❌
**Input:** Archivo binario renombrado como .csv.
**Esperado:** HTTP 422. Sin débito.

---

### TC-43 · `apply-mapping` transforma correctamente ✅
**Precondición:** `file_key` obtenido de `analyze-file` exitoso.
**Acción:** `POST /import-wizard/apply-mapping` con `{ file_key, mapping: [{ source: "Articulo", target: "name" }, ...] }`.
**Esperado:** Retorna batch de `ProductImportV1[]` con campos mapeados. Sin nuevo débito de créditos (el crédito ya fue cobrado en `analyze-file`).

---

### TC-44 · `file_key` pertenece a otro tenant 🔒
**Precondición:** `file_key` generado por tenant A.
**Acción:** Tenant B llama `POST /import-wizard/apply-mapping` con ese `file_key`.
**Esperado:** HTTP 403 o 404. Tenant B no puede acceder a archivos de Tenant A.

---

### TC-45 · `file_key` expirado → 410 ❌
**Precondición:** `file_key` generado hace más de 30 minutos (TTL esperado).
**Esperado:** HTTP 410 Gone. Sin débito.

---

### TC-46 · Plataforma detectada por ≥ 3 headers coincidentes ⚠️
**Input:** 2 de 5 headers de TiendaNube + headers desconocidos.
**Esperado:** `platform_detected = null` (no alcanza el umbral de 3). Pasa por mapeo IA.

---

### TC-47 · Headers duplicados en archivo CSV ⚠️
**Input:** CSV con 2 columnas llamadas "Precio".
**Esperado:** El parser agrega sufijo `_2` o similar, no crashea. Ambas columnas aparecen en `mapping_suggestions`.

---

### TC-48 · Archivo con 0 columnas → 422 ❌
**Input:** CSV vacío o con solo una fila de headers vacíos.
**Esperado:** HTTP 422. Sin débito.

---

## SECCIÓN 7 — Admin Pricing Dashboard (Super Admin)

### TC-49 · Cambiar credit_cost impacta próximas invocaciones ⚠️
**Acción:** `PATCH /admin/ai-credits/pricing/ai_product_description` con `{ tier: "normal", credit_cost: 2 }`.
**Verificar:** La siguiente invocación de `@RequireAiCredits('ai_product_description')` lee el nuevo costo. NO cachear el costo en memoria sin invalidación.

---

### TC-50 · Cambiar model_id cambia el modelo usado en OpenAI ⚠️
**Acción:** `PATCH /admin/ai-credits/pricing/ai_qa_answer` con `{ tier: "pro", model_id: "gpt-4o" }`.
**Verificar:** La siguiente llamada a OpenAI usa `model: "gpt-4o"`, no el anterior.

---

### TC-51 · Cambiar price_cents de un pack no afecta compras pasadas 💸
**Acción:** `PATCH /admin/ai-credits/packs/ai_desc_pack_10` con `{ price_cents: 3990 }`.
**Esperado:** `addon_catalog` actualizado. Compras ya completadas en `account_addons` mantienen el precio original (no hay retroactividad). Solo purchases futuros usan el nuevo precio.

---

### TC-52 · Desactivar pack lo oculta del Addon Store ❌
**Acción:** `PATCH /admin/ai-credits/packs/ai_desc_pack_10` con `{ is_active: false }`.
**Esperado:** `GET /ai-credits/pricing` del tenant NO incluye ese pack. Créditos ya comprados de ese pack permanecen disponibles.

---

### TC-53 · Desactivar feature bloquea su uso en todos los tenants ❌
**Acción:** `PATCH /admin/ai-credits/pricing/ai_photo_product` con `{ tier: "normal", is_active: false }`.
**Esperado:** TODOS los tenants reciben error al intentar usar esa feature. No afecta balances existentes.

---

### TC-54 · Grants manuales registran al super-admin en metadata ✅
**Acción:** Super-admin `d879a6e1` hace grant de 20 créditos.
**Esperado:** Row en ledger con `metadata->>'granted_by' = 'd879a6e1'`, `metadata->>'reason' != NULL`.

---

### TC-55 · Store DNA visible en Client Details ✅
**Acción:** `GET /admin/ai-credits/clients/:accountId/store-dna`.
**Esperado:** Retorna `{ dna_instruction, store_context, generated_at, expires_at, model_used, tokens_used }`.

---

### TC-56 · Regenerar Store DNA desde super-admin ✅
**Acción:** Botón "Regenerar Store DNA" en Client Details.
**Esperado:** `invalidated_at` se setea. DNA regenerado en la próxima llamada. No consume créditos del tenant.

---

## SECCIÓN 8 — Frontend: Interceptor 402 y modales

### TC-57 · HTTP 402 dispara evento custom ✅
**Precondición:** Interceptor configurado en `apps/web/src/api/client.ts`.
**Acción:** Cualquier invocación IA con balance 0.
**Esperado:** `window.dispatchEvent(new CustomEvent('ai-credits-insufficient', { detail: errorData }))` es disparado. `CreditInsufficientModal` aparece con:
- Nombre de la feature afectada (`feature_label`)
- Créditos requeridos vs disponibles
- Botón "Ir al Addon Store" que navega correctamente

---

### TC-58 · Modal no aparece para errores 4xx que no son 402 ⚠️
**Acción:** Request que retorna 401 o 403.
**Esperado:** `CreditInsufficientModal` NO aparece. El interceptor solo actúa sobre `status === 402 && error === 'insufficient_ai_credits'`.

---

### TC-59 · Botón IA deshabilitado visualmente con 0 créditos ✅
**Precondición:** Balance `ai_product_description` = 0.
**Esperado:** Botón "Mejorar descripción con IA" aparece con `disabled=true` + tooltip "Sin créditos — Compra en Addon Store".

---

### TC-60 · Toggle Normal/Pro muestra costo en tiempo real ✅
**Acción:** Seleccionar toggle "Pro" en Product Editor.
**Esperado:** El indicador cambia de "1 cr" a "3 cr" sin delay perceptible (usa `ai_feature_pricing` cargado previamente).

---

### TC-61 · `AiResultPreviewModal` permite editar antes de aceptar ✅
**Flujo:** AI genera descripción → modal aparece con texto → usuario edita → "Usar" → textarea del producto se llena con versión editada.
**Verificar:** Después de editar en el modal, el texto guardado en el producto es la versión editada, no la original de la IA.

---

### TC-62 · "Regenerar" en modal consume un crédito adicional ⚠️
**Precondición:** Balance = 2, costo normal = 1.
**Flujo:** Generar → modal → "Regenerar".
**Esperado:** Balance = 0 (2 consumos de 1 crédito cada uno). Segunda generación llama nuevamente a la API.

---

### TC-63 · Widget "AI" en header suma todos los balances ✅
**Precondición:** Balances: `ai_product_description=5`, `ai_qa_answer=10`, `ai_faq_generation=3`, `ai_photo_product=3`, `ai_column_mapping=2`.
**Esperado:** Badge muestra `23` (suma total).

---

### TC-64 · Tooltip del header muestra desglose por feature ✅
**Acción:** Hover sobre badge AI en header.
**Esperado:** Tooltip lista cada feature con su balance individual.

---

## SECCIÓN 9 — Addon Store: Familia AI

### TC-65 · Pack AI aparece en sección "Inteligencia Artificial" ✅
**Acción:** `GET /addons/catalog?family=ai` o navegar al Addon Store.
**Esperado:** 10 packs listados (5 features × 2 tamaños). Cards con `action_code`, `grants_credits`, `price_cents`.

---

### TC-66 · Compra de pack otorga créditos al completarse webhook MP ✅
**Flujo:** Compra `ai_desc_pack_10` → pago MP → webhook `payment.approved` → `grantConsumableCredits()`.
**Esperado:** Balance `ai_product_description` incrementado en 10. Row en ledger con `addon_key = 'ai_desc_pack_10'`, `credits_delta = +10`.

---

### TC-67 · Doble webhook del mismo pago no duplica créditos 🔁
**Escenario:** MP envía 2 webhooks del mismo `payment_id`.
**Esperado:** Idempotencia por `payment_id`. Solo 1 grant insertado.

---

### TC-68 · Pack desactivado no aparece pero créditos previos permanecen ✅
**Precondición:** Pack `ai_desc_pack_10` desactivado. Usuario tiene 10 créditos de compra anterior.
**Acción:** `GET /ai-credits/balances`.
**Esperado:** Balance 10 visible. Pack no aparece en catálogo para nuevas compras.

---

### TC-69 · Tab "Mis consumibles" muestra balances AI con etiqueta descriptiva ✅
**Esperado:** Cada `action_code` se muestra con label legible (no el código técnico): "Descripciones de Productos", "Respuestas Q&A", etc.

---

## SECCIÓN 10 — Aislamiento Multi-Tenant

### TC-70 · Balance de tenant A es invisible para tenant B 🔒
**Acción:** Tenant B llama `GET /ai-credits/balances` con JWT de Tenant A.
**Esperado:** HTTP 401 o 403. O si usa su propio JWT, solo ve su propio balance.

---

### TC-71 · Consumo de tenant A no afecta balance de tenant B 🔒
**Acción:** Tenant A consume 5 créditos de `ai_product_description`.
**Esperado:** Balance de tenant B sin cambios. `account_action_credit_ledger` filtra por `account_id`.

---

### TC-72 · Store DNA no se comparte entre tenants 🔒
**Acción:** Regenerar DNA de `urbanprint`.
**Esperado:** `store_dna_cache` de `tienda test` intacto.

---

### TC-73 · `file_key` de import es scoped por tenant 🔒
**Esperado:** El `file_key` almacenado en Redis o similar incluye `tenantId` como prefijo o está en scope de sesión del tenant.

---

## SECCIÓN 11 — Concurrencia y Race Conditions

### TC-74 · Dos requests simultáneos no consumen más créditos de los debidos 🔁
**Escenario:** 2 tabs del seller envían simultáneamente `POST /products/:id/ai-description`.
**Precondición:** Balance = 1.
**Esperado:** Solo 1 request exitoso (200), el otro recibe 402 o 429. Balance final = 0, no negativo.
**Mecanismo:** Lock por `(accountId, actionCode)` o transacción serializable en `assertAvailable` + insert.

---

### TC-75 · Provisioning concurrente no duplica welcome credits 🔁
**Escenario:** Job de provisioning ejecutado dos veces en paralelo (fallo de idempotencia upstream).
**Esperado:** Balance final = 1x welcome credits, no 2x.

---

### TC-76 · Store DNA regenerado concurrentemente no genera múltiples llamadas a OpenAI 🔁
**Escenario:** 5 features IA solicitadas al mismo tiempo, todas necesitan el DNA.
**Esperado:** Solo 1 llamada a OpenAI para el DNA. Las otras 4 esperan y usan el resultado cacheado (lock + promise sharing).

---

## SECCIÓN 12 — Expiración de Créditos

### TC-77 · Créditos expirados no suman al balance ⚠️
**Precondición:** Row en ledger: `credits_delta = +10`, `expires_at = NOW() - 1 second`.
**Acción:** `getBalance(accountId, 'ai_product_description')`.
**Esperado:** `0` (no `10`).

---

### TC-78 · Créditos sin `expires_at` nunca expiran ✅
**Precondición:** Row en ledger: `credits_delta = +10`, `expires_at = NULL`.
**Esperado:** Siempre sumados al balance. La vista los incluye indefinidamente.

---

### TC-79 · Créditos comprados (pack) tienen `expires_at = NULL` ✅
**Flujo:** Compra de `ai_desc_pack_10`.
**Validar:** Row insertado por `grantConsumableCredits()` tiene `expires_at = NULL`.

---

### TC-80 · Créditos de bienvenida tienen `expires_at` correcto 💸
**Validar:** Al otorgar welcome credits, `expires_at = provisioning_at + expires_days_from_config`.
**Anti-patrón:** No usar `NOW()` en el cron de reconciliación, sino `provisioning_at` como base.

---

## SECCIÓN 13 — Casos de Datos Edge

### TC-81 · Tienda sin productos genera DNA sin error ⚠️
**Precondición:** `products` table vacía para este `client_id`.
**Esperado:** `buildStoreContext` retorna `price_min = null`, `price_max = null`, `featured_products = []`. DNA generado con datos disponibles.

---

### TC-82 · Tienda sin SEO settings genera DNA sin error ⚠️
**Precondición:** No existe row en `seo_settings` para este `client_id`.
**Esperado:** Campos opcionales vacíos en el contexto. DNA usa nombre desde `nv_accounts`.

---

### TC-83 · Producto con descripción muy larga como input ⚠️
**Acción:** `POST /products/:id/ai-description` donde el producto tiene `description` de 10.000 caracteres.
**Esperado:** El prompt se trunca o resume antes de enviarse a OpenAI. No excede `max_tokens` del modelo. Crédito debitado correctamente.

---

### TC-84 · Preguntas de cliente en idioma distinto al español ⚠️
**Acción:** `POST /questions/:id/ai-suggest` donde la pregunta está en inglés o portugués.
**Esperado:** La respuesta sugerida se genera en español rioplatense (forzado por el sistema de prompt). No crashea.

---

### TC-85 · FAQ generation para producto sin descripción ⚠️
**Precondición:** Producto con `description = NULL`.
**Acción:** `POST /faqs/ai-generate` con `product_ids = [ese_product_id]`.
**Esperado:** Se genera igualmente con nombre y categoría. No crashea.

---

### TC-86 · Column mapping con archivo que tiene más de 100 columnas ⚠️
**Input:** Excel con 120 columnas.
**Esperado:** El servicio procesa las primeras N columnas relevantes (ej: primeras 50) o incluye todas pero el prompt no supera el límite de tokens. No crashea.

---

### TC-87 · `action_code` desconocido en grant manual → error validado ❌
**Acción:** `POST /admin/ai-credits/clients/:accountId/adjust` con `{ action_code: "ai_inexistente", amount: 10 }`.
**Esperado:** HTTP 400 con mensaje claro. No se inserta el row en ledger.

---

### TC-88 · Grant con amount negativo (revocación) funciona ✅
**Precondición:** Balance = 10.
**Acción:** Grant con `amount = -5` y `reason = "revocacion por error"`.
**Esperado:** Balance = 5. Row en ledger con `credits_delta = -5`. Nota: el guard de "no negativo" aplica SOLO al momento de consumo por feature, no a ajustes manuales del super-admin.

---

## SECCIÓN 14 — Smoke Tests de Integración End-to-End

### TC-89 · Flujo completo: cuenta nueva → welcome credits → primera descripción AI ✅
```
1. Provisionar cuenta (plan growth)
2. Verificar balance ai_product_description = 20
3. Crear producto en la tienda
4. POST /products/:id/ai-description (tier normal)
5. Verificar balance = 19
6. Verificar descripción generada y coherente con el DNA
7. Verificar row en account_action_credit_ledger
```

---

### TC-90 · Flujo completo: sin créditos → modal → compra pack → retry ✅
```
1. Forzar balance ai_product_description = 0
2. Intentar generar descripción → 402
3. CreditInsufficientModal aparece
4. Click "Ir al Addon Store"
5. Comprar ai_desc_pack_10 via MP sandbox
6. Webhook recibido → grant +10
7. Balance = 10
8. Retry descripción → 200
9. Balance = 9
```

---

### TC-91 · Flujo completo: import desde TiendaNube → sin créditos ✅
```
1. Subir archivo Excel de TiendaNube
2. POST /import-wizard/analyze-file
3. Verificar platform_detected = "tiendanube", credit_consumed = false
4. Balance ai_column_mapping intacto
5. POST /import-wizard/apply-mapping
6. Productos importados correctamente
```

---

### TC-92 · Flujo completo: import archivo desconocido → con crédito ✅
```
1. Balance ai_column_mapping = 2
2. Subir archivo CSV custom
3. POST /import-wizard/analyze-file (tier normal)
4. platform_detected = null, credit_consumed = true
5. Balance = 1
6. Tabla de mapeo aparece con sugerencias de la IA
7. Ajustar dropdowns
8. POST /import-wizard/apply-mapping
9. Productos importados
```

---

### TC-93 · Flujo completo: super-admin ajusta precios y afecta siguiente request ✅
```
1. credit_cost(ai_product_description, normal) = 1 → Balance = 1 (suficiente)
2. PATCH /admin/ai-credits/pricing → credit_cost = 2
3. Balance = 1 (insuficiente para el nuevo precio)
4. POST /products/:id/ai-description (normal) → 402
5. Cambiar credit_cost = 1 nuevamente
6. Retry → 200
```

---

## Resumen de Cobertura

| Área | TCs | Críticos |
|------|-----|----------|
| Balance y Ledger | TC-01 a TC-06 | TC-04, TC-06 |
| Guard + consumo | TC-07 a TC-16 | TC-09, TC-15, TC-16 |
| Store DNA | TC-17 a TC-26 | TC-22, TC-24, TC-26 |
| Welcome Credits | TC-27 a TC-33 | TC-31, TC-33 |
| Column Mapping | TC-34 a TC-48 | TC-39, TC-44, TC-46 |
| Admin Dashboard | TC-49 a TC-56 | TC-49, TC-53 |
| Frontend | TC-57 a TC-64 | TC-58, TC-62 |
| Addon Store | TC-65 a TC-69 | TC-67 |
| Multi-tenant | TC-70 a TC-73 | TC-70, TC-71, TC-72 |
| Concurrencia | TC-74 a TC-76 | TC-74, TC-76 |
| Expiración | TC-77 a TC-80 | TC-77, TC-80 |
| Datos edge | TC-81 a TC-88 | TC-83, TC-87 |
| E2E Smoke | TC-89 a TC-93 | Todos |
| **Total** | **93** | **~30 críticos** |
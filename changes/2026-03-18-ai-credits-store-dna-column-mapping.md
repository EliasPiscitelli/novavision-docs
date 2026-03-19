# AI Credits + Store DNA + Column Mapping + Admin Pricing

**Fecha:** 2026-03-18
**Alcance:** Admin DB, Backend DB, API (NestJS), Admin Dashboard, Web Storefront
**Branch:** feature/multitenant-storefront
**Estado:** Implementado, pendiente migraciones SQL y testing E2E

---

## Contexto

Sistema integral de IA monetizable para tenants. Incluye créditos por feature con tiers Normal/Pro, Store DNA (contexto IA de tienda), mapeo inteligente de columnas para importación, y dashboard de pricing para super-admin.

**Plan completo:** `novavision-docs/plans/PLAN_AI_CREDITS_STORE_DNA_COLUMN_MAPPING.md`

---

## Migraciones SQL

### Admin DB

**Archivo:** `api/migrations/admin/20260318_ai_credits_system.sql`

**Tablas creadas:**

| Tabla | Columnas clave | RLS |
|-------|---------------|-----|
| `ai_feature_pricing` | action_code, tier, credit_cost, model_id, temperature, max_tokens, label, is_active | service_role |
| `ai_welcome_credit_config` | plan_key, action_code, credits, expires_days, is_active | service_role |
| `store_dna_cache` | client_id, account_id, store_context, dna_instruction, model_used, tokens_used, generated_at, expires_at | service_role |

**Columnas nuevas en `nv_accounts`:**
- `industry TEXT`
- `brand_tone TEXT`
- `target_audience TEXT`
- `value_proposition TEXT`

**Constraints modificados en `addon_catalog`:**
- `family` CHECK: agregado `'ai'`
- `redirect_section` CHECK: agregado `'addonStore'`

**Seed data:**
- 10 rows `ai_feature_pricing` (5 features × 2 tiers)
- 15 rows `ai_welcome_credit_config` (3 planes × 5 features)
- 10 rows `addon_catalog` (packs AI consumibles)

### Backend DB

**Archivo:** `api/migrations/backend/20260318_faqs_add_product_id.sql`
- `faqs.product_id UUID` con FK a `products(id)` + partial index

---

## API (NestJS) — Módulo ai-credits

### Archivos nuevos (7)

| Archivo | Propósito |
|---------|-----------|
| `api/src/ai-credits/ai-credits.module.ts` | Módulo NestJS, exporta service + guard + store-context |
| `api/src/ai-credits/ai-credits.service.ts` | Balance, consumo, grant, pricing CRUD, welcome config |
| `api/src/ai-credits/ai-credits.guard.ts` | Guard HTTP 402 para créditos insuficientes |
| `api/src/ai-credits/ai-credits.decorator.ts` | `@RequireAiCredits(actionCode)` decorator |
| `api/src/ai-credits/ai-credits.controller.ts` | Endpoints tenant: balances, pricing, history, store-dna |
| `api/src/ai-credits/ai-credits.admin.controller.ts` | Endpoints super-admin: CRUD pricing/welcome/packs, client credits |
| `api/src/ai-credits/store-context.service.ts` | Store DNA: build context, generate via OpenAI, cache 24h |

### Endpoints tenant

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/ai-credits/balances` | Balances por feature |
| GET | `/ai-credits/pricing` | Pricing por feature (normal + pro) |
| GET | `/ai-credits/history` | Historial paginado |
| GET | `/ai-credits/store-dna` | Store DNA actual |
| POST | `/ai-credits/store-dna/regenerate` | Forzar regeneración |

### Endpoints super-admin

| Método | Ruta | Descripción |
|--------|------|-------------|
| GET | `/admin/ai-credits/pricing` | Todas las features con tiers |
| PATCH | `/admin/ai-credits/pricing` | Editar pricing |
| POST | `/admin/ai-credits/pricing` | Crear nueva feature |
| GET | `/admin/ai-credits/welcome-config` | Config welcome credits |
| PATCH | `/admin/ai-credits/welcome-config` | Editar welcome config |
| GET | `/admin/ai-credits/packs` | Packs AI del addon_catalog |
| PATCH | `/admin/ai-credits/packs/:addonKey` | Editar pack |
| GET | `/admin/ai-credits/clients/:accountId/balances` | Balances de un cliente |
| POST | `/admin/ai-credits/clients/:accountId/adjust` | Grant/revoke manual |
| GET | `/admin/ai-credits/clients/:accountId/history` | Historial de un cliente |
| GET | `/admin/ai-credits/clients/:accountId/store-dna` | Store DNA de un cliente |

### Archivos modificados (API)

| Archivo | Cambio |
|---------|--------|
| `api/src/app.module.ts` | Import AiCreditsModule |
| `api/src/worker/worker.module.ts` | Import AiCreditsModule |
| `api/src/worker/provisioning-worker.service.ts` | Step `grant_welcome_ai_credits` + Store DNA inicial |
| `api/src/import-wizard/import-wizard.controller.ts` | 2 endpoints: analyze-file, apply-mapping |
| `api/src/import-wizard/import-wizard.module.ts` | Import ConfigModule, AiCreditsModule, ImportMappingService |

### Import Wizard — Column Mapping (2 archivos nuevos)

| Archivo | Propósito |
|---------|-----------|
| `api/src/import-wizard/platform-signatures.ts` | Firmas TiendaNube/WooCommerce/MercadoLibre/Shopify + fuzzy matching |
| `api/src/import-wizard/import-mapping.service.ts` | Pipeline: platform detect → fuzzy → AI mapping, file transform |

---

## Admin Dashboard (Super-Admin)

### Archivos nuevos

| Archivo | Propósito |
|---------|-----------|
| `admin/src/pages/AdminDashboard/AiCreditsPricingView.jsx` | Vista 4-tab: Features, Packs, Welcome Credits, Créditos por Cliente |

### Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `admin/src/pages/AdminDashboard/index.jsx` | Nav item "AI Credits & Pricing" en categoría billing |
| `admin/src/App.jsx` | Route para AiCreditsPricingView |
| `admin/src/services/adminApi.js` | 12 métodos para AI credits API |
| `admin/src/pages/ClientDetails/hooks/useClientConsumables.js` | aiBalances, aiStoreDna, adjustAiCredits, fetchAiStoreDna |

---

## Web Storefront (Tenant Dashboard)

### Archivos nuevos (5)

| Archivo | Propósito |
|---------|-----------|
| `web/src/hooks/useAiCredits.js` | Hook: balances, pricing, getCost, getBalance |
| `web/src/components/admin/_shared/AiTierToggle.jsx` | Toggle pill Normal/Pro con badge de créditos |
| `web/src/components/admin/_shared/AiButton.jsx` | Botón IA con sparkle icon, loading shimmer, credit badge |
| `web/src/components/admin/_shared/CreditInsufficientModal.jsx` | Modal 402 + hook listener |
| `web/src/components/admin/_shared/AiResultPreview.jsx` | Preview/diff de resultados IA |

### Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `web/src/api/client.ts` | Interceptor HTTP 402 → CustomEvent `ai-credits-insufficient` |
| `web/src/components/admin/_shared/index.js` | Barrel exports de componentes AI |
| `web/src/components/admin/ProductDashboard/` | Botón "Mejorar descripción con IA" |
| `web/src/components/admin/QADashboard/index.jsx` | Botón "Sugerir respuesta" en ThreadPanel |
| `web/src/components/admin/ReviewsDashboard/index.jsx` | Botón "Sugerir respuesta" en ReplyForm |
| `web/src/components/admin/FaqSection/index.jsx` | Botón "Generar FAQs" + "Mejorar" |
| `web/src/components/admin/ImportWizard/index.jsx` | Step 0: upload + column mapping |
| `web/src/components/admin/AddonStoreDashboard/index.jsx` | Familia "IA" con packs |
| `web/src/pages/AdminDashboard/index.jsx` | Widget AI credits en header |

---

## Action Codes del sistema

| Action Code | Feature | Normal (créditos) | Pro (créditos) |
|-------------|---------|-------------------|----------------|
| `ai_product_description` | Descripción de producto | 1 | 3 |
| `ai_qa_answer` | Respuesta a preguntas | 1 | 2 |
| `ai_faq_generation` | Generación de FAQs | 1 | 3 |
| `ai_photo_product` | Ficha desde foto | 3 | 5 |
| `ai_column_mapping` | Mapeo de columnas | 1 | 2 |

---

## Welcome Credits por Plan

| Plan | Descripciones | Q&A | FAQs | Foto | Mapeo | Expiración |
|------|--------------|-----|------|------|-------|-----------|
| Starter | 5 | 10 | 3 | 3 | 2 | 90 días |
| Growth | 20 | 50 | 15 | 10 | 5 | 120 días |
| Enterprise | 50 | 200 | 50 | 30 | 10 | 180 días |

---

## Pendiente

- [ ] Ejecutar migraciones SQL en ambas BDs
- [ ] Testing E2E del flujo completo: grant → consume → 402 → addon store → purchase
- [ ] Verificar Store DNA generation con OpenAI key en staging
- [ ] Configurar credenciales OpenAI en variables de entorno de producción
- [ ] `npm run lint && npm run typecheck && npm run build` en api, admin, web

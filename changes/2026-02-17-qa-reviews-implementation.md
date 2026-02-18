# Cambio: Implementación Q&A y Reviews — Backend + E2E

- **Autor:** agente-copilot
- **Fecha:** 2026-02-17
- **Rama:** feature/automatic-multiclient-onboarding
- **Ticket:** N/A (feature new)

## Archivos creados/modificados

### API (apps/api)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `migrations/20260217_qa_reviews_tables.sql` | CREADO | DDL completo: 3 tablas, 12+ índices, RLS, triggers, RPC |
| `src/plans/featureCatalog.ts` | MODIFICADO | Agregados `storefront.product_qa` y `storefront.product_reviews` |
| `src/questions/dto/index.ts` | CREADO | DTOs: Create, Answer, Moderate, List |
| `src/questions/questions.service.ts` | CREADO | Service completo Q&A: CRUD + cursor pagination + moderación |
| `src/questions/questions.controller.ts` | CREADO | 6 endpoints Q&A con PlanAccessGuard |
| `src/questions/questions.module.ts` | CREADO | Módulo NestJS |
| `src/reviews/dto/index.ts` | CREADO | DTOs: Create, Update, AdminReply, Moderate, List |
| `src/reviews/reviews.service.ts` | CREADO | Service completo Reviews: CRUD + verified purchase + aggregates |
| `src/reviews/reviews.controller.ts` | CREADO | 7 endpoints Reviews con PlanAccessGuard |
| `src/reviews/reviews.module.ts` | CREADO | Módulo NestJS |
| `src/app.module.ts` | MODIFICADO | Registrados QuestionsModule + ReviewsModule + exclusiones auth |
| `src/favorites/favorites.controller.ts` | FIX | Eliminada declaración duplicada de `requestClient` (bug preexistente) |

### E2E (novavision-e2e)

| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `fixtures/api-client.fixture.ts` | MODIFICADO | Agregadas rutas Q&A + Reviews en API_ROUTES |
| `tests/12-qa-reviews/qa-reviews.spec.ts` | CREADO | 19 test cases (plan gating, CRUD, moderación, multi-tenant) |

## Resumen del cambio

### Tablas DB (ejecutadas en backend Supabase)
- `product_questions`: preguntas con parent_id (thread), display_name snapshot, moderación
- `product_reviews`: reviews con verified_purchase, rating 1-5, admin_reply, moderación
- `product_review_aggregates`: materialized via trigger (avg, count, distribution)
- `has_purchased_product()` RPC: verifica compra via order_items JSONB
- Todas con RLS estricto: tenant isolation + owner rules + admin write

### API endpoints

**Q&A (plan: growth/enterprise)**
- `GET /products/:productId/questions` — público, cursor pagination
- `POST /products/:productId/questions` — autenticado
- `POST /questions/:questionId/answers` — admin
- `PATCH /questions/:questionId/moderate` — admin (hide/restore/resolve)
- `DELETE /questions/:questionId` — autor (archive)
- `GET /admin/questions` — dashboard admin

**Reviews (plan: growth/enterprise)**
- `GET /products/:productId/reviews` — público, con aggregates + can_review
- `POST /products/:productId/reviews` — autenticado (1 por usuario por producto, 409 en duplicado)
- `PATCH /reviews/:reviewId` — autor edita
- `POST /reviews/:reviewId/reply` — admin
- `PATCH /reviews/:reviewId/moderate` — admin (hide/restore)
- `GET /products/:productId/social-proof` — público (solo aggregates)
- `GET /admin/reviews` — dashboard admin

### Plan gating
- `starter`: bloqueado (403)
- `growth` / `enterprise`: habilitado
- Implementado via `@PlanFeature()` + `PlanAccessGuard`

### Seguridad multi-tenant
- Todas las queries filtran por `client_id` via `getClientId(req)` (resuelto por TenantContextGuard)
- FK compuesta `(user_id, client_id)` → `users(id, client_id)` con `ON DELETE CASCADE`
- RLS policies en las 3 tablas con `server_bypass` + tenant scoping
- E2E tests verifican aislamiento cross-tenant (12.17, 12.18)

## Por qué

Feature nueva según plan arquitectónico aprobado (`novavision-docs/plans/QA_REVIEWS_ARCHITECTURE_PLAN.md`).
Permite a clientes Growth/Enterprise activar Q&A y Reviews en sus tiendas.

## Cómo probar

### Backend local
```bash
cd apps/api
npm run lint       # 0 errores
npm run build      # OK
npm run start:dev  # Levantar localmente
```

### E2E (requiere backend corriendo + tenants provisionados)
```bash
cd novavision-e2e
npx playwright test tests/12-qa-reviews/qa-reviews.spec.ts
```

### Manual (cURL)
```bash
# Listar Q&A público
curl -H "x-tenant-slug: e2e-tienda-b" http://localhost:3000/products/<PRODUCT_ID>/questions

# Crear pregunta (autenticado)
curl -X POST http://localhost:3000/products/<PRODUCT_ID>/questions \
  -H "x-tenant-slug: e2e-tienda-b" \
  -H "Authorization: Bearer <JWT>" \
  -H "Content-Type: application/json" \
  -d '{"body": "¿Viene en talle L?"}'
```

## Notas de seguridad

- FK compuesta a `users(id, client_id)` — descubierto que la tabla users tiene PK compuesta, no solo `(id)`
- `ON DELETE CASCADE` en FKs a users (no SET NULL — incompatible con FK compuesta cuando client_id es NOT NULL)
- Admin reply y moderación requieren `RolesGuard` con `@Roles('admin', 'super_admin')`
- HTML sanitizado en body de preguntas/reviews (strip tags server-side)
- Display_name snapshot evita exponer email real del usuario

## Decisiones técnicas

1. **Cursor pagination** (no offset) para Q&A y Reviews — más eficiente para listas largas
2. **Trigger DB** para aggregates de reviews — evita cálculo on-the-fly en cada GET
3. **display_name snapshot** — se graba al crear, no se actualiza si el usuario cambia nombre
4. **1 review por producto por usuario** — constraint UNIQUE en DB + manejo 409
5. **Verified purchase** vía RPC `has_purchased_product()` — usa GIN index sobre JSONB `order_items`

# Cambio: Frontend Q&A y Reviews — Storefront + Admin Dashboard

- **Autor:** agente-copilot
- **Fecha:** 2026-02-18
- **Rama:** feature/automatic-multiclient-onboarding (API) / develop (Web)

## Archivos creados

### Storefront (componentes públicos para compradores)

| Archivo | Descripción |
|---------|-------------|
| `apps/web/src/hooks/useProductQuestions.js` | Custom hook: fetchQuestions (cursor pagination), createQuestion, loadMore |
| `apps/web/src/hooks/useProductReviews.js` | Custom hook: fetchReviews (cursor pagination, aggregates, userReview), createReview, updateReview, fetchSocialProof, loadMore |
| `apps/web/src/components/product/ProductQA.jsx` | Componente Q&A: formulario de pregunta, tarjetas con estado, respuestas del admin, load more |
| `apps/web/src/components/product/ProductReviews.jsx` | Componente Reviews: resumen de rating (número grande + barras de distribución), formulario con star picker, tarjetas con badge verificado + reply admin |

### Admin Dashboard (gestión para dueños de tienda)

| Archivo | Descripción |
|---------|-------------|
| `apps/web/src/components/admin/QADashboard/index.jsx` | Dashboard admin de preguntas: listar, filtrar por estado, responder inline, moderar (ocultar/restaurar) |
| `apps/web/src/components/admin/QADashboard/style.jsx` | Styled-components del dashboard de preguntas |
| `apps/web/src/components/admin/ReviewsDashboard/index.jsx` | Dashboard admin de reviews: listar, filtrar por estado y rating, responder inline, moderar |
| `apps/web/src/components/admin/ReviewsDashboard/style.jsx` | Styled-components del dashboard de reviews |

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `apps/web/src/pages/ProductPage/ProductTabs.jsx` | Reemplazados tabs comentados (Reviews/FAQ con mock data) por tabs activos "Opiniones" y "Preguntas" conectados a componentes reales |
| `apps/web/src/pages/AdminDashboard/index.jsx` | Agregados imports de QADashboard y ReviewsDashboard, nuevas entradas en SECTION_DETAILS (qaManager, reviewsManager), registrados en SECTION_CATEGORIES (commerce), mapeados en SECTION_FEATURES (storefront.product_qa, storefront.product_reviews), y cases en renderActiveSection |

## Resumen

Implementación completa del frontend para el sistema de Preguntas y Respuestas (Q&A) y Opiniones/Reviews de productos.

### Storefront (público)
- **Tab "Opiniones"**: muestra resumen de rating con número grande y barras de distribución por estrellas, formulario de review con star picker + título + cuerpo, tarjetas de reviews con badge de compra verificada y reply del admin, paginación por cursor.
- **Tab "Preguntas"**: formulario para hacer preguntas (mínimo 10 caracteres), tarjetas con estado (Pendiente/Respondida), respuestas del admin destacadas, paginación por cursor.
- Ambos tabs requieren login para crear contenido (con hint visual para no logueados).

### Admin Dashboard
- **Preguntas de Producto (📬)**: lista con filtro por estado (todas/pendientes/respondidas/ocultas), respuesta inline con Enter, moderación (ocultar/restaurar).
- **Opiniones y Reviews (⭐)**: lista con filtro por estado de moderación y rating, respuesta inline, moderación, badge de compra verificada.
- Ambas secciones gateadas por plan (growth/enterprise) vía feature catalog (`storefront.product_qa`, `storefront.product_reviews`).

## Endpoints consumidos

| Endpoint | Método | Componente |
|----------|--------|------------|
| `/products/:id/questions` | GET | ProductQA (storefront) |
| `/products/:id/questions` | POST | ProductQA (storefront) |
| `/products/:id/reviews` | GET | ProductReviews (storefront) |
| `/products/:id/reviews` | POST | ProductReviews (storefront) |
| `/reviews/:id` | PATCH | ProductReviews (storefront, editar propia) |
| `/admin/questions` | GET | QADashboard (admin) |
| `/questions/:id/answers` | POST | QADashboard (admin) |
| `/questions/:id/moderate` | PATCH | QADashboard (admin) |
| `/admin/reviews` | GET | ReviewsDashboard (admin) |
| `/reviews/:id/reply` | POST | ReviewsDashboard (admin) |
| `/reviews/:id/moderate` | PATCH | ReviewsDashboard (admin) |

## Por qué

El backend ya tenía los endpoints completos (20/20 E2E tests passing). Faltaba la capa de UI para que compradores puedan hacer preguntas/reviews y los dueños de tienda puedan gestionar el contenido desde el admin dashboard.

## Cómo probar

### Storefront
1. Levantar API: `cd apps/api && npm run start:dev`
2. Levantar Web: `cd apps/web && npm run dev`
3. Navegar a un producto → verificar tabs "Opiniones" y "Preguntas"
4. Sin login: verificar que se muestra hint "Iniciá sesión para..."
5. Con login (usuario comprador): crear pregunta, crear review con estrellas
6. Verificar paginación "Cargar más" con muchos registros

### Admin Dashboard
1. Login como admin de tienda
2. Ir a Admin Dashboard → sección "Tienda y Ventas"
3. Verificar cards "Preguntas de Producto" y "Opiniones y Reviews"
4. Abrir cada sección, filtrar, responder, moderar
5. Verificar que plan starter muestra sección bloqueada

## Validaciones ejecutadas

- `npm run lint` → 0 errores, 31 warnings preexistentes
- `npm run typecheck` → Sin errores
- `npm run build` → Exitoso (7.44s)

## Notas de seguridad

- Los hooks de storefront envían auth token automáticamente vía interceptor de axiosConfig
- Los endpoints admin están protegidos por RolesGuard en el backend (admin/super_admin)
- Las secciones admin están gateadas por feature catalog (plan)
- No se exponen secretos ni service role keys

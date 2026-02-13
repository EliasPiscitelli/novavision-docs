# PR6 – Auditoría SEO + Prompt Copiable + SERP Preview

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront

## Archivos modificados

### API (templatetwobe)
- `src/seo-ai/seo-ai.controller.ts` — 3 cambios:
  - `'audit'` agregado a validTypes en createJob
  - `GET /seo-ai/audit` — endpoint gratuito de auditoría SEO
  - `GET /seo-ai/prompt` — prompt copiable para ChatGPT
  - `analyzeEntities()` — helper privado para detección de issues

### Web (templatetwo)
- `src/components/admin/SeoAutopilotDashboard/index.jsx` — refactorizado con 4 tabs
- `src/components/admin/SeoAutopilotDashboard/SeoAuditTab.jsx` — NUEVO
- `src/components/admin/SeoAutopilotDashboard/SeoPromptTab.jsx` — NUEVO
- `src/components/admin/SeoAutopilotDashboard/SeoJobsTab.jsx` — NUEVO
- `src/components/admin/SeoAutopilotDashboard/SerpPreview.jsx` — NUEVO

## Resumen de cambios

### Backend
1. **GET /seo-ai/audit** — Escaneo SEO gratuito (sin AI, sin créditos):
   - Consulta todas las products/categories del tenant
   - Calcula: missing meta_title, missing meta_description, títulos >65 chars, descriptions >160 chars, slugs faltantes, títulos duplicados
   - Retorna `{ summary: { products: {...}, categories: {...} }, issues: [...] }`
   - Cada issue tiene severity (error/warning), entity_type, entity_name, field, value

2. **GET /seo-ai/prompt** — Prompt copiable para Growth plan:
   - Construye un prompt ChatGPT-ready con nombre de tienda, categorías y lista de productos sin SEO (hasta 50)
   - Retorna `{ prompt: string, entity_count: number }`

3. **audit como job_type** — Se puede crear un job de tipo `audit` vía POST /seo-ai/jobs

### Frontend
1. **Tab bar** — SeoAutopilotDashboard ahora tiene 4 pestañas:
   - 🔍 Auditoría SEO (default)
   - 📋 Prompt AI
   - 💳 Créditos & Packs (contenido original)
   - 🤖 Generaciones

2. **SeoAuditTab** — Dashboard completo:
   - Score bar con % de completitud SEO
   - Grid de estadísticas (productos, categorías, sin title, sin desc, largos, AI-generated)
   - Tabla de issues con badges de severidad
   - SERP preview on-demand por entidad problemática

3. **SerpPreview** — Componente Google-like:
   - Snippet con title (azul), URL (verde), description (gris)
   - Indicadores de char count (verde/amarillo/rojo según limites 65/160)

4. **SeoPromptTab** — Prompt copiable:
   - Texto pre-generado con contexto de tienda
   - Botón "Copiar prompt" con feedback visual
   - Contador de entidades sin SEO

5. **SeoJobsTab** — Historial de generaciones:
   - Tabla con tipo, modo, estado (badge coloreado), progreso (barra %), fecha
   - Auto-refresh cada 8s si hay jobs activos

## Cómo probar
1. Levantar API: `npm run start:dev` en terminal back
2. Levantar Web: `npm run dev` en terminal front
3. Ir a Admin Dashboard → SEO AI Autopilot
4. Verificar que aparecen 4 pestañas
5. Tab "Auditoría SEO": debería mostrar score, stats y issues
6. Tab "Prompt AI": debería mostrar prompt copiable
7. Tab "Créditos & Packs": contenido original (balance + packs)
8. Tab "Generaciones": tabla de jobs (vacía si no hay)

## Notas de seguridad
- Los endpoints audit y prompt usan ClientDashboardGuard (requieren JWT válido)
- No se consumen créditos en audit ni prompt (gratuitos)
- El prompt tiene un límite de 50 productos para evitar payloads excesivos

## Validación
- API: lint ✔ (0 errors), typecheck ✔, build ✔
- Web: lint ✔ (0 errors), typecheck ✔, build ✔

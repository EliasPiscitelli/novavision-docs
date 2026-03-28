# 2026-03-27 — AI Coach Card + Locale en Store DNA + FAQ Enrichment

## Resumen

Tres mejoras relacionadas con IA implementadas en paralelo.

## Cambios

### Task 1: AI Coach Card en el dashboard del tenant (Admin)

- **Nuevo componente**: `apps/admin/src/components/AiCoachCard.tsx`
  - Widget que consume `GET /client-dashboard/ai-coach`
  - Muestra recomendacion AI con prioridad, texto motivador y boton de accion
  - Estados de loading (skeleton animado) y error (oculto silenciosamente)
  - Estilo dark theme consistente con el ClientCompletionDashboard
- **Integrado en**: `apps/admin/src/pages/ClientCompletionDashboard/index.tsx`
  - Se muestra entre la barra de progreso y la seccion de revision

### Task 2: Locale del account en Store DNA (API)

- **Archivo**: `apps/api/src/ai-credits/store-context.service.ts`
  - Se agrego `locale` al select de `nv_accounts` como fallback
  - Nuevo metodo `inferLocaleFromCountry()` que mapea AR->es-AR, MX->es-MX, etc.
  - Cadena de resolucion: `clients.locale` > `nv_accounts.locale` > inferido del pais > null
  - Asegura que las respuestas de IA usen el idioma correcto del seller

### Task 3: FAQ prompt enriquecido con contexto completo (API)

- **Archivo**: `apps/api/src/ai-generation/prompts/index.ts`
  - `FaqContextInput` ahora incluye `brandTone`, `targetAudience`, `topProducts`
  - `buildFaqContextPrompt()` incluye tono de marca, audiencia y productos destacados
  - `FAQ_CONTEXT_SYSTEM_PROMPT` actualizado con instrucciones de contexto de marca
  - `FAQ_GENERATION_SYSTEM_PROMPT` indica adaptar tono al Store DNA
- **Archivo**: `apps/api/src/ai-generation/ai-generation.service.ts`
  - `generateFaqsFromContext()` ahora consulta productos destacados (featured)
  - Trae `brand_tone` y `target_audience` de `nv_accounts`

## Validacion

- `npm run typecheck` OK en admin y api

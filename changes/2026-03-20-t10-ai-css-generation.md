# T10 — AI-Generated CSS

**Fecha:** 2026-03-20
**Tickets:** T10
**Ramas:** API `feature/automatic-multiclient-onboarding` (c65ffa1), Web `develop` (04862b7) → cherry-pick a `feature/multitenant-storefront` (fb31a18) + `feature/onboarding-preview-stable` (5e28edc)

## Resumen

Implementacion del sistema de generacion de CSS via IA. Los administradores pueden describir un estilo en lenguaje natural y la IA genera propiedades CSS que se populan en el editor de CssOverrideEditor para revision antes de guardar. Reusa la infraestructura de T9 (sanitizacion, scoping, inyeccion) para el guardado.

## Archivos nuevos

| Archivo | Repo | Descripcion |
|---------|------|-------------|
| `src/ai-generation/prompts/css-generate.ts` | API | System prompt + builder para AI CSS generation |
| `migrations/admin/20260320_t10_ai_css_generation_pricing.sql` | API | Pricing (normal/pro) + welcome credits para ai_css_generation |

## Archivos modificados

| Archivo | Repo | Cambio |
|---------|------|--------|
| `src/ai-generation/ai-generation.service.ts` | API | +generateCssProperties() metodo (seccion 10), import css-generate prompt |
| `src/ai-generation/ai-generation.controller.ts` | API | +POST /design-overrides/ai-generate con AiCreditsGuard + lock |
| `src/api/addons.js` | Web | +generateAiCss() metodo API client |
| `src/components/admin/StoreDesignSection/CssOverrideEditor.jsx` | Web | +AI prompt input, "Generar con IA" boton, handleAiGenerate, error handling (402/429) |
| `src/components/admin/StoreDesignSection/DesignStudio.jsx` | Web | +currentPalette/currentFont props al CssOverrideEditor |

## Flujo end-to-end

1. Admin abre DesignStudio → panel "CSS Personalizado" → input "Describi el estilo..."
2. Escribe descripcion (ej: "elegante y oscuro con bordes redondeados")
3. Click "Generar con IA" → POST /design-overrides/ai-generate
4. Backend: AiCreditsGuard valida creditos → callOpenAI con CSS_GENERATION_SYSTEM_PROMPT + Store DNA
5. AI retorna { properties: { "background-color": "#1a1a2e", "border-radius": "12px", ... } }
6. Frontend puebla el grid de propiedades para revision del admin
7. Admin ajusta si es necesario → "Guardar CSS" (reusa flujo T9: POST /design-overrides)
8. Sanitizacion server-side → scoping → inyeccion en storefront

## Pricing

| Tier | Modelo | Creditos | Max tokens |
|------|--------|----------|------------|
| normal | gpt-4o-mini | 1 | 800 |
| pro | gpt-4o | 2 | 800 |

Welcome credits: starter=3, growth=10, pro=25 (expiran 90 dias)

## Seguridad

- AiCreditsGuard + @RequireAiCredits('ai_css_generation') valida creditos
- Generating lock previene requests concurrentes por cuenta
- Store DNA inyectado para contexto de marca
- Prompt limitado a 500 chars
- Propiedades generadas pasan por sanitizeCssOverrides() al guardar (defensa en profundidad)
- Rate limiting 402 y 429 manejados en frontend

## Validacion

- API: typecheck OK, build OK, pipeline 7 checks passed
- Web: typecheck OK, build OK (6.72s), tests 333/341 (8 pre-existentes), pipeline 6 checks passed x3 ramas

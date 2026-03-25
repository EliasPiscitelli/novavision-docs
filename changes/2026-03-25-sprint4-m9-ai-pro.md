# Sprint 4 AI Pro — M9

**Fecha:** 2026-03-25
**Plan:** `PLAN_AI_PRO.md` Sprint 4
**Estado:** M9 implementado, M10 pendiente (n8n — no es código API)

---

## M9: Parametrizar idioma en prompts según locale del tenant

### Problema
Todos los prompts de IA estaban hardcodeados a "español rioplatense". Un tenant de Brasil o México recibiría contenido en argentino. El Store DNA system prompt decía "tienda de e-commerce argentina" sin importar el locale real.

### Solución
1. **Locale en StoreContext**: Agregado `locale` a la interface `StoreContext`, leído de `clients.locale` (Backend DB).
2. **Mapeo locale → idioma**: `LOCALE_LANGUAGE_MAP` con soporte para es-AR, es-MX, es-CO, es-CL, es-PE, es-UY, pt-BR, en-US.
3. **`resolveLanguageInstruction()`**: Función exportada que resuelve locale a instrucción de idioma (con fallback a es-AR).
4. **Store DNA dinámico**: El system prompt ya no está hardcodeado — `buildStoreDNASystemPrompt(language)` genera el prompt con el idioma correcto.
5. **User message**: Incluye `Idioma/Locale` como dato para que la IA lo considere.
6. **Fallback genérico**: También usa idioma dinámico en lugar de "argentino" hardcodeado.

### Impacto
Como el Store DNA se inyecta como prefijo en **todos** los prompts de IA (`fullSystemPrompt = ${storeDNA}\n\n${systemPrompt}`), este cambio afecta automáticamente a todas las features sin tocar cada prompt individual.

### Archivos modificados
- `api/src/ai-credits/store-context.service.ts` — locale en StoreContext, LOCALE_LANGUAGE_MAP, resolveLanguageInstruction(), prompt dinámico
- `api/src/ai-credits/store-context.service.spec.ts` — actualizado fallback assertion

---

## M10: Workflows n8n (pendiente)
M10 requiere configuración en la instancia n8n (nodos de validación, fallback, activación selectiva). No es código API. Pendiente para configuración manual.

---

## Validación
- TypeScript: `tsc --noEmit` OK
- Build: `npm run build` OK
- Tests: 106/106 suites, 1033/1035 tests OK (2 skipped)

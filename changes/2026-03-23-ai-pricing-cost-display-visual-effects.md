# AI Pricing Restructure + Cost Display Fix + Visual Effects

**Fecha:** 2026-03-23
**Apps:** API, Web
**Ramas:** API `feature/automatic-multiclient-onboarding`, Web `develop` → cherry-pick a ambas prod

## 1. Nuevo action_code `ai_product_full`

### Problema
`ai-fill` (crea producto completo) y `ai-improve` (mejora producto completo) costaban lo mismo que `ai-description` (mejora solo la descripcion): 1 credito normal, 3 pro. No reflejaba la complejidad real de las operaciones.

### Solucion
- Creado `ai_product_full` en `ai_feature_pricing`: **2 cr normal, 5 cr pro**
- `ai_product_description` permanece en 1/3 cr para description-only
- `ai_faq_generation` subio de 1/3 a **2/4 cr** (genera multiples FAQs por operacion)
- Pool universal `ai_universal` no afectado — solo cambia cuanto se descuenta por operacion

## 2. Fix costo dinamico del AiButton

### Problema
El badge del boton "Mejorar con IA" mostraba siempre 0 creditos porque:
1. `useAiCredits` nunca cargaba el pricing al montar (solo balances)
2. `getCost()` buscaba en un array vacio y retornaba 0
3. El costo no sumaba la foto cuando el checkbox "incluir foto" estaba activo

### Solucion
- `useAiCredits.js`: agregado `fetchPricing()` al useEffect de mount
- `ProductModal`: costo calculado como `content_cost + (photo_cost si checkbox activo)`
- El costo se actualiza inmediatamente al cambiar Normal/Pro tier

## 3. Efectos visuales mejorados

### Problema
`MagicShimmer` era un gradiente translucido de 8% opacidad — practicamente invisible durante la generacion.

### Solucion
Reemplazado con `AiGeneratingOverlay`: 10 particulas flotantes, texto pulsante contextual ("Generando producto..." / "Mejorando tu producto..."), barra de progreso animada, backdrop-filter blur.

## Archivos modificados

| Archivo | Cambio |
|---------|--------|
| `apps/api/src/ai-credits/ai-credits.service.ts` | Agregar `ai_product_full` a AI_ACTION_CODES |
| `apps/api/src/ai-credits/ai-credits.service.spec.ts` | Actualizar count de action codes (7→8) |
| `apps/api/src/ai-generation/ai-generation.controller.ts` | Fill/improve usan `ai_product_full` |
| `apps/web/src/hooks/useAiCredits.js` | Auto-cargar pricing al montar |
| `apps/web/src/components/ProductModal/index.jsx` | Costo dinamico, AiGeneratingOverlay, actionCode |
| `apps/web/src/components/admin/AddonStoreDashboard/addonLabels.js` | Label para ai_product_full |
| Admin DB `ai_feature_pricing` | 2 rows INSERT (ai_product_full), 2 rows UPDATE (ai_faq_generation) |

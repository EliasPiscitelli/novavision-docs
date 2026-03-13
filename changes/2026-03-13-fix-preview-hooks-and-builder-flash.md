# Fix: Preview hooks order violation + Builder white flash

- **Autor:** agente-copilot
- **Fecha:** 2026-03-13
- **Rama Web:** develop → cherry-pick a feature/multitenant-storefront + feature/onboarding-preview-stable
- **Rama Admin:** feature/automatic-multiclient-onboarding

## Archivos modificados

### Web (templatetwo)
- `src/pages/PreviewHost/index.tsx` — reordenamiento de hooks

### Admin (novavision)
- `index.html` — script inline para fondo oscuro en ruta /builder

## Resumen

### 1. Fix hooks order violation (Web)
El commit previo `fa0c63d` ("align preview templates 6-8 with storefront") introdujo `useMemo` hooks **después** de un `return` anticipado (`if (!state) return ...`). Esto causaba que en el primer render (sin state) se ejecutaran menos hooks que en renders posteriores (con state) → error de React: "Rendered more hooks than during the previous render" → crash del preview/onboarding Step 4.

**Solución:** Mover los 4 `useMemo`/derivaciones (`canonicalTemplateKey`, `NativeTemplatePreview`, `useNativeTemplatePreview`, `previewHomeData`) **antes** del early return, con defaults seguros para cuando `state` es null.

### 2. Fix white flash en /builder (Admin)
Al acceder a `https://novavision.lat/builder`, el fondo aparecía blanco durante ~200-500ms hasta que React montaba y styled-components inyectaba `GlobalStyle` con el fondo oscuro del tema.

**Solución:** Script inline en `index.html` que detecta la ruta `/builder` y aplica `background-color: #0f172a` al `<html>` y `<body>` inmediatamente, antes de que cargue React.

## Por qué

- El error de hooks rompía completamente el onboarding (Step 4) y la vista de preview del builder
- El flash blanco era un problema visual recurrente reportado por el usuario

## Cómo probar

1. **Onboarding Step 4:** Ir al wizard de onboarding, avanzar hasta Step 4 (selección de template). Los templates 6/7/8 deben renderizar sin errores de consola.
2. **Builder preview:** Abrir `https://novavision.lat/builder` en una nueva pestaña (o incógnito). El fondo debe ser oscuro desde el primer frame, sin flash blanco.
3. **Storefront preview:** Las tiendas publicadas deben seguir funcionando normalmente.

## Commits

| Repo | Hash | Rama | Descripción |
|------|------|------|-------------|
| templatetwo | `f77f573` | develop | fix(web): move preview hooks above early return |
| templatetwo | `ee7b898` | feature/multitenant-storefront | cherry-pick de f77f573 |
| templatetwo | `c3842ad` | feature/onboarding-preview-stable | cherry-pick de f77f573 |
| novavision | `00cb99b` | feature/automatic-multiclient-onboarding | fix(admin): dark background on builder route |

## Notas de seguridad

- Sin impacto en seguridad. El script inline solo modifica estilos CSS del DOM, no ejecuta lógica de negocio.

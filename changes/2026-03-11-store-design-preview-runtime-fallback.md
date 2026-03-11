# Cambio: fallback runtime para preview en Store Design

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: develop

## Archivos modificados

- apps/web/src/components/admin/StoreDesignSection/index.jsx
- apps/web/src/components/admin/StoreDesignSection/resolvePreviewSections.js
- apps/web/src/__tests__/store-design-section.test.jsx
- apps/web/package.json
- apps/web/package-lock.json

## Resumen

Se corrigió el dashboard de `Store Design` para que el preview embebido use la estructura runtime publicada cuando el endpoint editable `/home/sections` responde vacío.

Además, cuando realmente no existen secciones para renderizar, el panel ahora muestra un estado explícito en lugar de quedar en blanco. También se dejaron operativas las pruebas de render del módulo agregando las dependencias de test que el repo ya usaba implícitamente.

## Por qué

El preview podía quedar completamente vacío sin error visible aunque la tienda tuviera una home válida. La causa era que `StoreDesignSection` priorizaba `[]` de `getHomeSections()` por encima de `homeData.config.sections`, anulando la estructura real del storefront.

## Qué se cambió

- Se extrajo `resolvePreviewSections()` como helper dedicado.
- El preview ahora resuelve secciones con esta prioridad:
  1. estructura editable si trae bloques;
  2. estructura runtime publicada;
  3. estructura persistida en settings;
  4. vacío real solo si ninguna fuente tiene secciones.
- El panel de preview muestra un mensaje claro cuando no hay bloques para renderizar.
- Se agregó cobertura puntual en `store-design-section.test.jsx` para el fallback runtime.
- Se agregaron `jsdom`, `@testing-library/react` y `@testing-library/dom` para poder ejecutar las pruebas de render declaradas en el proyecto.

## Cómo probar

En apps/web:

```bash
npx vitest run src/__tests__/store-design-section.test.jsx --reporter=verbose
npm run typecheck
npm run build
```

Smoke manual sugerido:

1. Abrir `https://farma.novavision.lat/admin-dashboard?storeDesign`.
2. Verificar que el preview embebido muestre la home actual si `/home/sections` todavía no tiene estructura editable cargada.
3. Verificar que solo aparezca el estado vacío cuando realmente no existen secciones publicadas ni editables.

## Notas de seguridad

- No se alteró la validación del preview token.
- El cambio solo afecta la selección de la fuente de secciones usada por el preview del panel.
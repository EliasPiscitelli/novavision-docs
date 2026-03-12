# Cambio: pase UX de Store Design y restauración del tenant Addon Store

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable / main
- Repos: apps/web, novavision-docs
- Archivos:
  - apps/web/src/components/admin/StoreDesignSection/index.jsx
  - apps/web/src/components/admin/StoreDesignSection/style.jsx
  - apps/web/src/tour/definitions/storedesign-diseno-tienda.js
  - apps/web/src/components/admin/AddonStoreDashboard/index.jsx
  - apps/web/src/pages/AdminDashboard/index.jsx

## Resumen

Se hizo un segundo pase sobre la experiencia de Store Design para acercarla más al mental model del Step 4 y, en paralelo, se restauró la sección tenant de Addon Store que había quedado fuera del dashboard aunque Store Design ya la usaba como destino comercial.

## Qué cambió

- Store Design ahora muestra una guía visual de 4 pasos arriba del editor:
  - elegir capa
  - armar borrador o seleccionar variante
  - validar preview
  - aplicar o comprar
- El tour interactivo de Store Design se actualizó al flujo real de borrador estructural, preview prioritario y apply diferido.
- Se restauró `AddonStoreDashboard` en web con catálogo, modal de detalle, política de compra y CTA de checkout.
- `AdminDashboard` vuelve a reconocer `?addonStore` como sección válida del tenant, así que los CTAs comerciales desde Store Design ya no aterrizan en una ruta huérfana.

## Por qué

El editor de diseño ya estaba mejor resuelto técnicamente, pero todavía le faltaba una capa más explícita de orientación. Además, el flujo comercial tenía una regresión: el UI mandaba a `?addonStore`, pero la sección ya no estaba presente en el dashboard del tenant.

## Cómo probar

En apps/web:

```bash
npm run test:unit -- src/__tests__/store-design-section.test.jsx src/__tests__/addon-store-dashboard.test.jsx src/__tests__/contact-section-renderer.test.jsx
npm run typecheck
npm run build
```

Prueba manual sugerida:

1. Abrir `/admin-dashboard?storeDesign`.
2. Confirmar que arriba del editor aparezca la guía visual de 4 pasos.
3. Cambiar entre `Estructura`, `Template` y `Theme` y verificar que la guía acompañe el flujo.
4. Forzar un faltante de créditos estructurales y comprobar que el CTA comercial siga llevando a `/admin-dashboard?addonStore`.
5. Abrir `/admin-dashboard?addonStore` y verificar:
   - hero comercial visible
   - cards del catálogo
   - `Ver detalle` abre modal
   - se muestra política de compra e historial

## Notas

- Este cambio no altera contratos de API ni reglas de tenant.
- La restauración de Addon Store en web recompone una regresión del shell tenant y vuelve consistente el flujo comercial desde Store Design.
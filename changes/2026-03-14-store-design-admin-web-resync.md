# Resincronización visual entre Builder Admin y Store Design Web

- Autor: GitHub Copilot
- Fecha: 2026-03-14
- Repos: `apps/admin` y `apps/web`
- Fuente visual de verdad: `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`

## Resumen

Se detectó deriva visual entre el Step 4 real del builder en `apps/admin` y la superficie `DesignStudio` en `apps/web`.

El problema no era que existiera una sola implementación rota, sino dos implementaciones separadas con copy y layout distintos. Para corregirlo, se tomó el builder de `admin` como referencia visual y se re-alineó `DesignStudio` de `web` a esa base, manteniendo la lógica comercial propia del dashboard.

## Qué se ajustó

1. Se removieron bloques visuales agregados sólo en `web` que no existían en el builder real.
2. Se restauró el copy principal de cabecera para que coincida con Step 4.
3. Se volvió a usar la misma convención visual de preview (`Full Preview` / `👀 Preview`).
4. Se devolvió el banner de advertencia de Growth en la vista de presets para mantener la lectura visual del builder.
5. Se mantuvo separado el fix funcional del `PreviewHost`, porque corrige el iframe usado por el builder sin redefinir el layout.

## Cómo probar

### Web

```bash
cd apps/web
npx vitest run src/__tests__/store-design-section.test.jsx src/__tests__/preview-host.test.jsx --reporter=verbose
npm run lint
npm run typecheck
```

### Admin

```bash
cd apps/admin
npm run typecheck
```

## Nota

Este cambio no convierte `apps/web` en fuente de verdad del builder. La referencia del flujo `/builder` sigue estando en `apps/admin` y cualquier ajuste futuro de UX/UI debe evaluarse como cambio dual, no como edición aislada en uno de los repos.
# Cambio: fallback de preview Store Design basado en Step 4

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable, develop, feature/multitenant-storefront
- Archivos: apps/web/src/components/admin/StoreDesignSection/index.jsx, apps/web/src/components/admin/StoreDesignSection/previewPresetSections.js, apps/web/src/__tests__/store-design-section.test.jsx

## Resumen

Se agregó un fallback de preview en Store Design que replica la estrategia del Step 4 del onboarding: cuando el tenant no tiene `home_sections` persistidas ni `config.sections` publicadas, el iframe recibe una estructura sintética basada en presets del template seleccionado.

## Por qué

El `PreviewHost` renderiza únicamente `payload.config.sections`. En tenants como `farma`, el panel cargaba bien pero el preview quedaba vacío porque las fuentes runtime devolvían listas vacías. El Step 4 del onboarding sí funcionaba porque siempre hidrataba un preset concreto antes de enviar el payload.

## Cómo probar

1. En apps/web, ejecutar `npm run test:unit -- src/__tests__/store-design-section.test.jsx`.
2. Abrir Store Design con un tenant sin estructura persistida y verificar que el iframe renderiza el template actual.
3. Confirmar que la lista editable sigue mostrando “No hay secciones estructurales...” hasta que existan secciones reales en backend.

## Notas de seguridad

- El fallback solo se usa para el payload de preview.
- No se persisten IDs sintéticos ni se habilita guardado de props contra secciones inexistentes.
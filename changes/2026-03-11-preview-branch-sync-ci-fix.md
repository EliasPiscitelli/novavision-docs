# Fix de CI y sincronización de ramas para preview Store Design

- Fecha: 2026-03-11
- Autor: GitHub Copilot
- Rama: develop y feature/multitenant-storefront en templatetwo

## Archivos modificados

- apps/web/src/preview/PreviewProviders.tsx
- apps/web/src/components/admin/StoreDesignSection/index.jsx

## Resumen

Se estabilizó el preview de Store Design en las ramas publicadas corrigiendo dos problemas distintos:

1. `develop` tenía marcadores de conflicto remanentes en `StoreDesignSection/index.jsx`.
2. `feature/multitenant-storefront` tenía un `PreviewProviders.tsx` que montaba `styled-components` de forma directa y rompía el typecheck por incompatibilidad con `ThemeArgument`.

## Por qué

El objetivo fue dejar `develop` alineada con las ramas productivas para este flujo y evitar que CI falle por diferencias accidentales entre ramas. En `develop` se aplicó una versión mínima y compatible del provider de preview usando el `ThemeProvider` propio del proyecto, sin depender de providers que no existen en esa rama.

## Cómo probar

En `apps/web`:

```bash
npm run lint
npm run typecheck
npm run build
```

Verificar además que el preview de Store Design renderice sin error de `containerBackground` y que el iframe de preview siga abriendo correctamente con el token generado.

## Notas de seguridad

- No se agregaron secretos ni variables nuevas.
- El cambio mantiene el preview encapsulado y solo ajusta cómo se monta el theme runtime.
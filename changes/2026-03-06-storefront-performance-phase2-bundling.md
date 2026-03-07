# Cambio: storefront performance fase 2 bundling y section renderer

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/registry/sectionComponents.tsx`
  - `apps/web/src/components/SectionRenderer.tsx`
  - `apps/web/src/services/axiosConfig.jsx`
  - `apps/web/vite.config.js`

## Objetivo

Continuar la optimizacion de performance del storefront reduciendo el peso upfront del renderer dinamico de secciones y mejorando el particionado del build para aislar modulos pesados fuera del flujo publico inicial.

## Problemas atacados

1. `SectionRenderer` seguia arrastrando un registro estatico con muchas variantes de componentes de templates.
2. `axiosConfig.jsx` mezclaba imports en una posicion que mantenia ruido estructural en el build.
3. El build no tenia una estrategia concreta de particionado para modulos pesados como `@supabase`, sliders y modulos del admin.

## Cambios aplicados

### `apps/web/src/registry/sectionComponents.tsx`

- Se reemplazaron imports estaticos por `React.lazy` para las variantes de secciones de templates.
- Se agregaron helpers `lazyDefault` y `lazyNamed` para soportar exports default y named sin duplicar logica.
- El registro `SECTION_COMPONENTS` conserva la misma API publica, por lo que no hubo cambios de contrato.

### `apps/web/src/components/SectionRenderer.tsx`

- Se envolvio el render final en `Suspense`.
- Se agrego un fallback liviano para modo `view` y `editor` mientras carga la seccion diferida.
- El error boundary existente se mantuvo para no degradar resiliencia.

### `apps/web/src/services/axiosConfig.jsx`

- Se movio `getTenantSlug` al bloque superior de imports.
- No cambia comportamiento runtime; solo ordena el modulo para evitar warnings estructurales innecesarios.

### `apps/web/vite.config.js`

- Se agrego `optimizeDeps.include` para `react`, `react-dom` y `react-router-dom`.
- Se incorporo `manualChunks` focalizado para:
  - `vendor-supabase`
  - `vendor-ui`
  - `vendor-sliders`
  - `vendor-motion`
  - `admin-dashboard`
  - `section-renderer`
- Se descarto separar `recharts` a un chunk propio porque generaba un ciclo con `admin-dashboard`.

## Resultado tecnico

### Mejoras verificadas

- El home ya no arrastra en el bundle base el registro completo de secciones dinamicas.
- El build ahora genera un chunk dedicado `section-renderer-*`.
- Dependencias pesadas y acotadas quedaron aisladas en chunks dedicados (`vendor-supabase`, `vendor-sliders`, `vendor-ui`, `vendor-motion`).
- Se mantuvo la carga lazy del dashboard admin fuera del storefront publico.

### Riesgo residual conocido

- `admin-dashboard` sigue siendo un chunk grande en build de produccion porque concentra mucho codigo y librerias internas del panel.
- Ese peso no impacta la carga inicial del storefront publico porque la ruta ya entra por `React.lazy`, pero queda como siguiente frente claro de optimizacion.

## Validacion ejecutada

Desde `apps/web`:

```bash
npm run lint
npm run typecheck
npm run build
```

## Resultados de validacion

- `npm run typecheck`: OK
- `npm run build`: OK
- `npm run lint`: OK con warnings preexistentes fuera del alcance de esta fase

## Evidencia de build

- Se genero `dist/assets/section-renderer-*.js`
- Se generaron chunks dedicados:
  - `vendor-supabase-*.js`
  - `vendor-sliders-*.js`
  - `vendor-ui-*.js`
  - `vendor-motion-*.js`
- No quedaron warnings de chunks circulares en el build final.

## Siguiente paso recomendado

Atacar `admin-dashboard` por dentro, separando tabs o dashboards pesados como analytics, import wizard y SEO autopilot con carga diferida interna, ya que hoy concentran la mayor parte del JS del panel.

## Notas de seguridad

- No se modificaron permisos, autenticacion ni contratos con backend.
- El cambio solo reorganiza carga de modulos y orden de imports.

# Cambio: estabilización de build en feature/onboarding-preview-stable

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable
- Archivos: src/App.jsx, src/routes/AppRoutes.jsx, src/pages/AdminDashboard/index.jsx

## Resumen

Se corrigieron desvíos de rama en la storefront de onboarding que estaban rompiendo el build de producción en Netlify.

## Qué se cambió

- Se normalizó el lazy loading en `src/routes/AppRoutes.jsx`, removiendo imports duplicados que redeclaraban páginas ya definidas con `lazy()`.
- Se eliminó un import roto y no utilizado de `SEOHead` en `src/App.jsx`.
- Se limpió `src/pages/AdminDashboard/index.jsx` para alinearlo con los componentes que realmente existen en `feature/onboarding-preview-stable`, removiendo imports duplicados, una definición duplicada de `VALID_SECTIONS` y referencias a módulos ausentes en esta rama.

## Por qué

La rama `feature/onboarding-preview-stable` tenía drift respecto de otras ramas del storefront. Eso dejó combinaciones inválidas de imports eager + lazy y referencias a dashboards que no existen en esta variante, lo que hacía fallar el build de Vite en CI/Netlify.

## Cómo probar

En `apps/web`:

```bash
npm run typecheck
npm run build
```

Resultado esperado:

- `typecheck` sin errores.
- `build` completo y exitoso.

## Notas de seguridad

No se modificaron credenciales, variables de entorno ni flujos de autenticación. El cambio es de estabilización de imports, routing y composición del dashboard.
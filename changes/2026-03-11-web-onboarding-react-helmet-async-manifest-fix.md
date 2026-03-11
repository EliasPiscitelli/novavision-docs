# Cambio: fix de manifiesto para react-helmet-async en onboarding-preview-stable

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: feature/onboarding-preview-stable (apps/web)
- Archivos: apps/web/package.json, apps/web/package-lock.json

## Resumen

Se agregó `react-helmet-async` al manifiesto de la rama `feature/onboarding-preview-stable` y se regeneró el lockfile para que Netlify y GitHub Actions puedan resolver el import usado en `src/main.jsx`.

## Qué se cambió

- Se declaró `react-helmet-async` en `apps/web/package.json`.
- Se actualizó `apps/web/package-lock.json` para reflejar la dependencia real de la rama.

## Por qué

- El código de la rama ya usaba `HelmetProvider`, pero la dependencia no estaba declarada en esa rama específica.
- En local el build podía pasar por arrastre de `node_modules`, pero CI y Netlify hacían instalación limpia y fallaban al resolver el módulo.

## Cómo probar

```bash
cd apps/web
npm run lint
npm run typecheck
npm run build
```

Prueba manual sugerida:

1. Verificar que GitHub Actions `validate` ya no falle por `react-helmet-async`.
2. Verificar que el deploy de Netlify de `feature/onboarding-preview-stable` complete el build.

## Notas de seguridad

Sin impacto en permisos, auth o multi-tenant. El ajuste solo corrige la declaración de dependencias para instalaciones limpias de CI.
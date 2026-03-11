# Cambio: fix de HelmetProvider para admin-dashboard

- Autor: agente-copilot
- Fecha: 2026-03-11
- Rama: feature/multitenant-storefront
- Archivos: apps/web/src/main.jsx

Resumen: se envolvió el árbol principal del storefront con `HelmetProvider` para que `react-helmet-async` tenga contexto válido en las rutas que renderizan `NoIndexMeta`, especialmente `admin-dashboard`.

Por qué: el login de tenants en producción estaba descargando el chunk `admin-dashboard` y fallaba en runtime con `Cannot read properties of undefined (reading 'add')` dentro de `react-helmet-async`, porque `<Helmet>` se estaba usando sin `HelmetProvider`.

Cómo probar:
- En `apps/web`: `npm run lint`
- En `apps/web`: `npm run typecheck`
- En `apps/web`: `npm run build`
- Abrir `https://farma.novavision.lat/login` después del deploy y confirmar que no aparece el error de `admin-dashboard-*.js`.

Notas de seguridad: sin impacto de permisos, auth ni multi-tenant; el cambio solo agrega el provider requerido para metadatos SEO/noindex.
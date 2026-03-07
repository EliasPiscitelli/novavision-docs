# Cambio: shell tenant en Addon Store del dashboard admin

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/src/App.jsx

Resumen: se corrigió la carga directa y el refresh de /admin-dashboard?addonStore y /admin-dashboard?seoAutopilot para que vuelvan a bootstrapear el branding/theme de la tienda y rendericen el header storefront.

Por qué: el dashboard admin estaba marcando todas las rutas admin con shouldSkipHomeData, así que esas vistas quedaban sin homeData, sin DynamicHeader y con el theme fallback en refresh. El bug se veía especialmente en dominios tenant como farma.novavision.lat.

Cómo probar:

1. En apps/web correr npm run ci:storefront.
2. Abrir una tienda tenant autenticada en /admin-dashboard?addonStore.
3. Verificar que aparece el header de la tienda y que el theme coincide con la configuración del tenant.
4. Refrescar la página y validar que se mantiene el mismo theme y header.
5. Repetir en /admin-dashboard?seoAutopilot para confirmar el mismo shell comercial.

Notas de seguridad: sin cambios de credenciales, auth ni contratos API. Solo se ajustó el gating frontend para permitir bootstrap de datos públicos de tienda en secciones admin comerciales.
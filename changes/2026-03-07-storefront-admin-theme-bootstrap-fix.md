# Cambio: corrección del bootstrap de theme y header en admin storefront

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: develop / feature/multitenant-storefront
- Archivos:
  - apps/web/src/App.jsx
  - apps/web/src/theme/resolveEffectiveTheme.ts

Resumen: se corrigió el arranque del theme y del header del storefront dentro del admin para que no caiga en un template fallback incorrecto ni dependa de saltear la carga de homeData.

Por qué: había dos problemas combinados. El admin podía omitir la carga de homeData y dejar el theme en fallback. Además, `resolveEffectiveTheme` reemplazaba indebidamente un tenant con template `first` por `second` si existía dark mode persistido en storage, lo que hacía que algunas tiendas cargaran otro theme al refrescar.

Cómo probar:

1. En apps/web correr npm run ci:storefront.
2. Entrar a /admin-dashboard?addonStore en una tienda con template `first`.
3. Verificar que el header de la tienda aparece correctamente.
4. Refrescar la página y confirmar que el template y la paleta siguen siendo los del tenant.
5. Repetir en /admin-dashboard?seoAutopilot.

Notas de seguridad: sin cambios en auth, tenancy ni contratos API. El ajuste solo corrige bootstrap frontend y resolución de theme respetando la configuración real del tenant.
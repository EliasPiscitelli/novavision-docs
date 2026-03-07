# Cambio: sync selectivo de shell a preview para omitir homeData en admin

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama: feature/onboarding-preview-stable
- Archivos: apps/web/src/App.jsx, apps/web/src/services/homeData/useFetchHomeData.jsx

## Resumen

Se sincronizo a la rama `feature/onboarding-preview-stable` un ajuste puntual del shell para evitar la carga global de `/home/data` cuando la navegacion esta en rutas admin.

## Por que

El paquete grande reciente de `develop` mezcla optimizaciones de storefront, addon store y splitting de templates. Para preview no hacia falta arrastrar todo ese bloque. El ajuste util y compartido era solo impedir que el shell admin dependa de `homeData` cuando no corresponde.

## Como probar

1. En `apps/web`, ejecutar `npm run ci:storefront`.
2. Abrir la rama preview y navegar a rutas admin.
3. Verificar que la app no espere `/home/data` para renderizar esas pantallas.
4. Confirmar que el storefront regular sigue renderizando header, banners y social icons solo cuando hay `homeData`.

## Notas de seguridad

- No se tocaron permisos ni autenticacion.
- El cambio solo evita una carga innecesaria de datos en el shell para rutas admin.
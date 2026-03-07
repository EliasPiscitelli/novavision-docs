# Cambio: fix de inicialización TDZ en AppContent

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama web: `feature/multitenant-storefront`
- Archivo principal: `apps/web/src/App.jsx`

## Resumen

Se corrigió un `ReferenceError: Cannot access 'l' before initialization` en el storefront/admin dashboard moviendo un `useEffect` de debug para que no referencie `homeData` antes de ejecutar `useFetchHomeDataWithOptions`.

## Qué se cambió

- Se reubicó el efecto `[theme:init]` debajo de la destructuración de `homeData`, `error` e `isLoading`.
- No se cambió el comportamiento funcional del fetch ni del tema; sólo se eliminó la lectura en zona temporal muerta (TDZ) que el bundle minificado exponía como `l`.

## Por qué

- El código accedía a `homeData?.config` dentro de un hook declarado antes de `const { homeData, error, isLoading } = useFetchHomeDataWithOptions(...)`.
- En desarrollo esto podía pasar desapercibido, pero en el bundle de producción la referencia quedaba minificada y rompía la carga del dashboard/storefront con `Cannot access 'l' before initialization`.

## Cómo probar

Desde `apps/web`:

```bash
npm run ci:storefront
```

Luego abrir la ruta que cargaba el chunk afectado y verificar que no aparezca el `ReferenceError` en consola.

## Riesgo

- Bajo: el cambio sólo reordena la declaración de un efecto de debug para respetar el orden de inicialización de variables.
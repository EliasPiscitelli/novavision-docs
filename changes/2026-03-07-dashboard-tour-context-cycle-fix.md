# Cambio: dashboard storefront fix de inicialización en sistema de tours

- Autor: GitHub Copilot
- Fecha: 2026-03-07
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `apps/web`, `novavision-docs`

## Archivos modificados

- `apps/web/src/tour/TourContext.js`
- `apps/web/src/tour/TourProvider.jsx`
- `apps/web/src/tour/useTour.js`

## Resumen

Se aplicó un fix adicional al crash del dashboard de tienda en producción (`Cannot access 'l' before initialization`) separando el contexto de tours en un módulo propio.

## Qué se cambió

- Se creó `TourContext.js` como origen único del contexto de tours.
- `TourProvider.jsx` dejó de declarar/exportar el contexto directamente.
- `useTour.js` ahora consume el contexto desde el módulo aislado, evitando el acople directo con `TourProvider`.

## Por qué

- El dashboard importaba simultáneamente `TourProvider` y `useTour`.
- `useTour` importaba `TourContext` desde `TourProvider`, generando un acople de inicialización entre ambos módulos dentro del chunk base del dashboard.
- Separar el contexto en un archivo inerte elimina ese punto de ciclo sin cambiar el contrato público del sistema de tours.

## Cómo probar

Desde `apps/web`:

```bash
npm run ci:storefront
```

## Resultado

- `npm run ci:storefront`: OK

## Riesgos

- Bajo: el cambio sólo reorganiza imports del sistema de tours; no modifica pasos, persistencia ni permisos del dashboard.

## Notas de seguridad

- No se modificaron autenticación, autorización ni llamadas al backend.

# Cambio: deduplicacion de lecturas en PaymentsConfig y ampliacion de layout

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/services/payments.js`
  - `apps/web/src/components/admin/PaymentsConfig/index.jsx`
  - `apps/web/src/components/admin/PaymentsConfig/style.jsx`

## Resumen

Se agrego una deduplicacion corta para las lecturas de configuracion de pagos y estado de Mercado Pago en el panel `PaymentsConfig`, reduciendo requests repetidos provocados por remounts o revalidaciones muy cercanas. Ademas, se amplio el ancho maximo del contenedor principal del panel de `1120px` a `1440px`.

## Por que

La inspeccion de red seguia mostrando llamadas repetidas para `config` y `status` aun despues de corregir la ruta OAuth. Eso no rompía funcionalidad, pero generaba ruido innecesario y contribuia a la sensacion de rerender excesivo. El cambio mantiene refresh forzado cuando realmente hace falta, por ejemplo despues del callback OAuth o una rehidratacion explicita.

## Cambios aplicados

### `apps/web/src/services/payments.js`

- Se agrego cache en memoria de 5 segundos para `getPaymentConfig()`.
- Se agrego cache en memoria por `clientId` para `getMpConnectionStatus()`.
- Se comparte la promesa en vuelo para evitar requests duplicados concurrentes.
- Se invalidan caches al guardar configuracion y al desconectar Mercado Pago.
- Se agrego soporte `force` para saltar cache cuando la UI necesita datos frescos.

### `apps/web/src/components/admin/PaymentsConfig/index.jsx`

- El estado de Mercado Pago ahora usa `force` solo si el usuario vuelve del callback OAuth.
- La funcion `rehydrate()` ahora fuerza recarga real para refrescar datos luego de save/reset.

### `apps/web/src/components/admin/PaymentsConfig/style.jsx`

- `max-width` actualizado de `1120px` a `1440px`.

## Como probar

Desde `apps/web`:

```bash
npm run ci:storefront
```

Prueba manual sugerida:

1. Abrir la pantalla de pagos del admin storefront.
2. Recargar la pagina con DevTools abiertos en Network.
3. Verificar que `config` y `status` no se disparen en rafagas duplicadas para el mismo montaje normal.
4. Conectar Mercado Pago y confirmar que el callback sigue refrescando el estado correctamente.
5. Confirmar visualmente que el contenedor del panel usa el nuevo maximo de `1440px`.

## Resultado de validacion

- `npm run ci:storefront`: OK
- Lint: OK con warnings preexistentes fuera del alcance de este cambio
- Typecheck: OK
- Build: OK

## Notas de seguridad

- No se tocaron credenciales, rutas sensibles ni contratos backend.
- La cache es efimera en memoria del cliente y se invalida en acciones de escritura para evitar stale data persistente.

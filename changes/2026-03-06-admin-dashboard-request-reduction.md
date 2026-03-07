# Cambio: reduccion de requests globales en admin dashboard

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/App.jsx`
  - `apps/web/src/hooks/usePlanLimits.js`
  - `apps/web/src/services/homeData/useFetchHomeData.jsx`

## Resumen

Se redujeron requests innecesarios en la vista `/admin-dashboard` del storefront atacando dos fuentes concretas:

1. `GET /plans/my-limits` se disparaba sin deduplicacion desde `usePlanLimits()`.
2. El shell global del storefront seguia cargando `homeData` y piezas asociadas (`settings/config`, `SEOHead`) aun cuando la ruta activa era administrativa.

## Por que

En la inspeccion de red del panel de pagos todavia aparecian requests repetidos que no pertenecian estrictamente al panel:

- `my-limits` provenia del hook compartido `usePlanLimits()` sin cache corta.
- `settings/config` provenia del arbol global de `App.jsx`, no de `PaymentsConfig`.

## Cambios aplicados

### `apps/web/src/hooks/usePlanLimits.js`

- Cache corta en memoria (`5s`) para reutilizar resultados recientes.
- Reuso de promesa en vuelo para evitar requests concurrentes duplicados.
- Inicializacion del hook desde cache cuando existe.

### `apps/web/src/services/homeData/useFetchHomeData.jsx`

- Se expuso `useFetchHomeDataWithOptions(shouldSkip)` para permitir saltar la carga global en rutas especiales.

### `apps/web/src/App.jsx`

- Se detecta `isAdminRoute` para `/admin-dashboard` y `/admin/*`.
- En rutas admin se evita cargar `homeData` global.
- En rutas admin se evita renderizar `SEOHead`, `AnnouncementBar`, `DynamicHeader` y `SocialIcons`.
- En rutas admin no se bloquea el render del dashboard esperando `homeData`.

## Hallazgos tecnicos

### Origen de `my-limits`

- `src/pages/AdminDashboard/index.jsx`
- `src/components/admin/UsageDashboard/UsageDashboard.jsx`
- `src/components/admin/CouponDashboard/index.jsx`
- `src/components/admin/ImportWizard/index.jsx`

En la vista `payments`, el montaje esperado es el de `AdminDashboard`; cualquier repeticion extra venia del hook sin dedupe o de nuevos montajes.

### Origen de `settings/config`

- `src/App.jsx` llama al hook global de home data.
- `src/services/homeData/useFetchHomeData.base.jsx` incluye `settings` y `config` dentro de `STATIC_KEYS`.
- `src/components/SEOHead/index.jsx` puede disparar `GET /seo/settings` segun el plan.

## Como probar

Desde `apps/web`:

```bash
npm run ci:storefront
```

Prueba manual sugerida:

1. Abrir `/admin-dashboard?payments`.
2. Recargar con DevTools en Network.
3. Verificar que desaparezcan las lecturas globales de `settings/config` ligadas al shell publico.
4. Verificar que `my-limits` no se duplique en rafagas por montajes cercanos.
5. Confirmar que el dashboard admin siga renderizando correctamente sin header publico.

## Resultado de validacion

- `npm run ci:storefront`: OK
- Lint: OK con warnings preexistentes fuera de este cambio
- Typecheck: OK
- Build: OK

## Notas de seguridad

- No se modificaron permisos, autenticacion ni contratos backend.
- El cambio solo evita cargas globales innecesarias en rutas admin y reutiliza datos recientes del mismo tenant.

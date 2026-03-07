# Cambio: storefront performance fase 3 admin dashboard splitting

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/pages/AdminDashboard/index.jsx`
  - `apps/web/src/pages/UserDashboard/index.jsx`
  - `apps/web/vite.config.js`

## Objetivo

Reducir el peso real del panel administrativo del storefront separando internamente sus modulos pesados para que no entren todos juntos en el primer acceso al dashboard.

## Problemas atacados

1. `src/pages/AdminDashboard/index.jsx` cargaba casi todos los modulos del panel con imports estaticos.
2. `src/pages/UserDashboard/index.jsx` seguia importando `OrderDashboard` de forma estatica, lo que anulaba parte del split esperado.
3. `vite.config.js` estaba agrupando demasiado con la regla `src/components/admin/`, recreando un chunk admin monolitico aunque existieran `dynamic import()`.

## Cambios aplicados

### `apps/web/src/pages/AdminDashboard/index.jsx`

- Se reemplazaron imports estaticos por `React.lazy` para los modulos principales del admin.
- Se creo `LAZY_SECTION_COMPONENTS` para centralizar el mapeo de secciones cargadas on demand.
- Se agrego `renderLazySection(sectionKey)` con `Suspense` y fallback liviano.
- Se unifico el `switch(activeSection)` para que reutilice el renderer lazy.

Secciones desacopladas:

- `products`
- `users`
- `logo`
- `banners`
- `services`
- `faqs`
- `orders`
- `contactInfo`
- `socialLinks`
- `payments`
- `shipping`
- `coupons`
- `optionSets`
- `sizeGuides`
- `identity`
- `usage`
- `billing`
- `subscription`
- `seoAutopilot`
- `supportTickets`
- `qaManager`
- `reviewsManager`
- `importWizard`
- `analytics`

### `apps/web/src/pages/UserDashboard/index.jsx`

- `OrderDashboard` paso a cargarse con `React.lazy`.
- Se agrego `Suspense` con fallback local para la seccion `Mis Pedidos`.
- Esto elimino el cruce estatico que Vite reportaba entre `UserDashboard` y `AdminDashboard`.

### `apps/web/vite.config.js`

- Se acoto `manualChunks` para que `admin-dashboard` solo capture la pagina `AdminDashboard`.
- Se dejo de forzar todo `src/components/admin/` dentro del mismo chunk.
- Se mantuvieron los chunks dedicados de vendors y `section-renderer`.

## Resultado tecnico

### Mejora principal

En el build anterior, `admin-dashboard` quedaba en aproximadamente:

- `3256.52 kB` minificado
- `797.22 kB` gzip

Despues del split interno y del ajuste en `manualChunks`, el chunk principal del admin paso a:

- `518.89 kB` minificado
- `163.32 kB` gzip

### Efectos visibles en build

- Desaparecio el warning especifico de Vite sobre `OrderDashboard` importado en forma dinamica y estatica al mismo tiempo.
- El build ahora emite chunks especificos para modulos del admin como:
  - `orders-gestion-pedidos-*.js`
  - `analytics-metricas-*.js`
  - `payments-configurar-pagos-*.js`
  - `usage-consumo-*.js`
  - `coupons-gestionar-cupones-*.js`
  - `seoautopilot-seo-*.js`
  - `importwizard-importacion-ia-*.js`

## Validacion ejecutada

Desde `apps/web`:

```bash
npm run typecheck
npm run build
npm run lint
```

## Resultados de validacion

- `npm run typecheck`: OK
- `npm run build`: OK
- `npm run lint`: OK con los mismos 40 warnings preexistentes

## Riesgos remanentes

- Siguen existiendo chunks grandes de la app fuera del admin (`index-*` mayores a `500 kB`) que todavia merecen una pasada especifica.
- El admin ya no es el principal cuello de botella, pero quedan oportunidades en modulos compartidos, mapas, categorias y checkout.

## Notas de seguridad

- No se modificaron permisos, autenticacion ni contratos backend.
- El cambio solo reorganiza carga de modulos y estrategia de bundling del frontend.

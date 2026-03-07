# Cambio: storefront performance fase 4 product editor lazy loading

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/components/admin/ProductDashboard/index.jsx`

## Objetivo

Diferir la carga del editor pesado de productos para que el dashboard no arrastre el formulario completo de alta y edicion hasta que el usuario realmente abra el modal.

## Problema atacado

`ProductDashboard` importaba `ProductModal` de forma estatica. Ese modal arrastra selects, ayudas, validaciones y componentes pesados del flujo de producto, aunque la mayoria de las visitas al dashboard se quedan en lectura de tabla o acciones simples.

## Cambio aplicado

### `apps/web/src/components/admin/ProductDashboard/index.jsx`

- `ProductModal` paso a cargarse con `React.lazy`.
- Se agrego `Suspense` alrededor del modal de creacion/edicion.
- Se agrego un fallback dentro del overlay para mantener la misma experiencia visual mientras se descarga el editor.

## Resultado tecnico

- El costo del editor de producto queda diferido hasta abrir el modal.
- No hubo errores nuevos de build ni lint.
- El chunk principal `admin-dashboard` practicamente no cambia, lo cual indica que este ajuste impacta sobre codigo del editor y sus dependencias diferidas, no sobre el shell del panel.
- El build sigue mostrando chunks pesados remanentes como `CategoriesSelect-*`, `AddressVerifyMap-*` y varios `index-*`, que quedan como siguientes candidatos.

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

- `CategoryManager` sigue entrando en ProductDashboard por import estatico y puede ser el siguiente corte chico del flujo de catalogo.
- `CategoriesSelect` continua como chunk pesado, por lo que el siguiente paso mas rentable en este subflujo seria revisar si conviene lazy-loadear tambien gestores auxiliares o dividir internamente el editor por tabs/secciones.

## Notas de seguridad

- No se modificaron contratos, autenticacion ni permisos.
- El cambio solo reorganiza la carga del frontend para reducir costo upfront en el dashboard de productos.

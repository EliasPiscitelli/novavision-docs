# Cambio: storefront performance fase 5 catalogo checkout y section registry por template

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`
- Archivos:
  - `apps/web/src/components/admin/ProductDashboard/index.jsx`
  - `apps/web/src/components/checkout/CheckoutStepper/index.jsx`
  - `apps/web/src/registry/sectionComponents.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/first.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/second.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/third.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/fourth.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/fifth.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/sixth.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/seventh.tsx`
  - `apps/web/src/registry/sectionComponentTemplates/eighth.tsx`

## Objetivo

Aplicar tres cortes adicionales de performance sobre los hotspots remanentes del storefront:

1. diferir gestores auxiliares del catalogo,
2. separar el checkout por paso real,
3. dividir el registry de secciones por template real.

## Cambios aplicados

### 1. Catalogo: `CategoryManager` lazy

Archivo:

- `apps/web/src/components/admin/ProductDashboard/index.jsx`

Cambios:

- `CategoryManager` ahora se carga con `React.lazy`.
- El modal de categorias se envuelve en `Suspense` con fallback dentro del overlay.
- Esto deja diferidos tanto el editor de producto como el gestor de categorias, cargando solo la tabla del dashboard al entrar.

### 2. Checkout: carga por paso y modulos diferidos

Archivo:

- `apps/web/src/components/checkout/CheckoutStepper/index.jsx`

Cambios:

- `CartStep`, `ShippingStep`, `PaymentStep` y `ConfirmationStep` pasaron a `React.lazy`.
- `CouponInput` paso a cargarse bajo `Suspense` dentro del resumen lateral.
- `BuyerInfoModal` tambien paso a `React.lazy`.
- `renderStep()` ahora resuelve el paso actual y lo monta con fallback liviano.

Resultado visible en build:

- aparecieron chunks separados:
  - `CartStep-*.js`
  - `ShippingStep-*.js`
  - `PaymentStep-*.js`
  - `ConfirmationStep-*.js`

### 3. Section registry: split por template real

Archivos:

- `apps/web/src/registry/sectionComponents.tsx`
- `apps/web/src/registry/sectionComponentTemplates/*.tsx`

Cambios:

- Se crearon modulos separados por template (`first` a `eighth`).
- `sectionComponents.tsx` dejo de declarar todas las familias de secciones juntas.
- El renderer ahora resuelve exports por `lazyTemplateExport(...)` desde cada modulo de template.
- Esto hace que las familias visuales queden agrupadas por template y no por un unico registry central.

Resultado visible en build:

- aparecieron chunks especificos por template:
  - `first-*.js`
  - `second-*.js`
  - `third-*.js`
  - `fourth-*.js`
  - `fifth-*.js`
  - `sixth-*.js`
  - `seventh-*.js`
  - `eighth-*.js`
- `section-renderer-*` bajo de aproximadamente `57.11 kB` a `53.11 kB` gzip incluido en el reporte minificado.

## Resultado tecnico

### Mejoras verificadas

- El flujo de catalogo ahora difiere tanto el editor de producto como el gestor de categorias.
- El checkout dejo de arrastrar todos los pasos y auxiliares desde el primer render.
- El registry de secciones quedo separado por template real y el build muestra esa particion explicitamente.

### Hallazgos

- `admin-dashboard` se mantiene alrededor de `518.83 kB`; estos cambios ya no atacan el shell del panel sino costo diferido dentro de catalogo y renderer.
- Los siguientes chunks pesados remanentes siguen siendo:
  - `CategoriesSelect-*` alrededor de `121 kB`
  - `AddressVerifyMap-*` alrededor de `160 kB`
  - varios `index-*` compartidos mayores a `500 kB`

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

- El split por template requiere vigilar que nuevos templates futuros se registren tambien en `sectionComponentTemplates/`.
- `CategoriesSelect` y `AddressVerifyMap` siguen siendo buenos candidatos para una siguiente pasada especifica.
- Los chunks `index-*` compartidos indican que todavia hay codigo transversal por desacoplar en rutas publicas o modulos base.

## Notas de seguridad

- No se modificaron contratos, permisos ni autenticacion.
- Todos los cambios son de organizacion de carga y particion del frontend.

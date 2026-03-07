# Cambio: auditoria y ejecucion fase 1 de performance storefront tenant

- Autor: GitHub Copilot
- Fecha: 2026-03-06
- Rama objetivo web: `feature/multitenant-storefront`
- Repositorios: `templatetwo`, `novavision-docs`

## Objetivo

Implementar la Fase 1 de mejoras de performance y navegacion del storefront tenant con foco en quick wins de bajo riesgo y alto impacto, validando cada bloque antes de continuar.

## Hallazgos base que justifican la fase

1. El shell publico del storefront estaba demasiado acoplado a `homeData`.
2. El bundle inicial sigue cargando demasiadas rutas, templates y headers upfront.
3. `useEffectiveTheme` hacia trabajo extra con `JSON.stringify(...)` en dependencias.
4. `AuthProvider` usaba un pseudo-ref no estable para `syncMembershipRef`.
5. El dashboard admin del storefront venia heredando fetches globales innecesarios.

## Alcance ejecutable de esta fase

### Paso 1
- Registrar y conservar el ajuste ya aplicado para evitar fetches globales en admin.
- Validacion: `get_errors` + `npm run ci:storefront`.

### Paso 2
- Lazy load por rutas en `AppRoutes.jsx`.
- Validacion: `get_errors` + `npm run ci:storefront`.

### Paso 3
- Lazy load por templates/home y headers dinamicos.
- Archivos:
  - `src/registry/templatesMap.ts`
  - `src/routes/HomeRouter.jsx`
  - `src/components/DynamicHeader.jsx`
- Validacion: `get_errors` + `npm run ci:storefront`.

### Paso 4
- Estabilizar `AuthProvider` usando `useRef` real.
- Optimizar `useEffectiveTheme` eliminando serializacion pesada en dependencias.
- Validacion: `get_errors` + `npm run ci:storefront`.

## Checklist de ejecucion

- [x] Paso 1: reducir requests globales en admin dashboard
- [x] Paso 2: lazy load por rutas
- [x] Paso 3: lazy load por templates y headers
- [x] Paso 4: estabilizar auth y theme resolver
- [x] Validacion final completa
- [x] Documentacion final actualizada con resultados

## Comandos de validacion

Desde `apps/web`:

```bash
npm run ci:storefront
```

Chequeos focalizados:

```bash
# revisar errores de archivos tocados
# via VS Code Problems / get_errors
```

## Riesgos controlados

- Rutas lazy: riesgo de fallback vacio o flashes si falta `Suspense`.
- Templates lazy: riesgo de default export / named export incorrecto.
- Header lazy: riesgo de mismatch entre template y header fallback.
- Auth refactor: riesgo de stale closure si no se preserva `tenant?.id`.
- Theme refactor: riesgo de no recalcular si cambia config por identidad y no por contenido.

## Evidencias y resultados

### Paso 1
- Ajuste local aplicado en:
  - `src/App.jsx`
  - `src/hooks/usePlanLimits.js`
  - `src/services/homeData/useFetchHomeData.jsx`
- Estado: listo para incluir en el siguiente commit.
- Validacion inicial: `npm run ci:storefront` OK.

### Paso 2
- Ajuste aplicado en `src/routes/AppRoutes.jsx`.
- Se movieron a `React.lazy` las pantallas no-home del router principal para bajar carga upfront del bundle inicial.
- Se agrego `Suspense` por ruta con fallback simple para no romper UX durante la carga diferida.
- Validacion:
  - `get_errors` sobre `src/routes/AppRoutes.jsx`: OK.
  - `npm run typecheck`: OK.
  - `npm run build`: OK.
  - `npm run ci:storefront`: sin errores nuevos; quedaron warnings preexistentes de lint y el warning conocido de chunks grandes en build.

### Paso 3
- Ajustes aplicados en:
  - `src/registry/templatesMap.ts`
  - `src/routes/HomeRouter.jsx`
  - `src/components/DynamicHeader.jsx`
- Se convirtieron los templates del home y los headers dinamicos a `React.lazy`.
- Se agregaron `Suspense` locales en home y header para evitar flashes o pantallas vacias.
- Evidencia de build: aparecieron chunks dedicados como `Home-*`, `Header-*` y mayor particion en assets de rutas/admin.
- Validacion:
  - `get_errors` en los 3 archivos: OK.
  - `npm run ci:storefront`: OK sin errores nuevos; persistieron warnings conocidos de lint y chunks grandes.

### Paso 4
- Ajustes aplicados en:
  - `src/context/AuthProvider.jsx`
  - `src/hooks/useEffectiveTheme.ts`
- `syncMembershipRef` paso a ser un `useRef` real para evitar una referencia nueva por render y cortar warnings asociados.
- Se elimino `JSON.stringify(...)` del memo del theme efectivo para evitar serializacion pesada en cada render.
- Validacion:
  - `get_errors` en ambos archivos: OK.
  - `npm run ci:storefront`: OK.
  - El lint bajo de 42 warnings a 40, sin introducir errores.

## Resultado de la fase

- Fase 1 completada sin errores de compilacion.
- Requests globales innecesarios en admin reducidos por el ajuste previo del shell.
- Router principal con lazy loading para pantallas no-home.
- Home y header ahora se cargan segun el template activo del tenant, no upfront.
- `AuthProvider` y `useEffectiveTheme` quedaron mas estables y livianos.
- Riesgos remanentes principales:
  - chunks todavia grandes en `SectionRenderer` y bundles core,
  - warning estructural por mezcla de import estatico/dinamico en `axiosConfig.jsx`,
  - warnings legacy de lint fuera del alcance de esta fase.

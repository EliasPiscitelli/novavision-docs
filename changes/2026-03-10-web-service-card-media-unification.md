# Cambio: Web service cards media unification

- Fecha: 2026-03-10
- Autor: agente-copilot
- Rama: develop

## Archivos modificados

- `apps/web/src/components/shared/ServiceCardMedia.jsx`
- `apps/web/src/core/schemas/homeData.schema.ts`
- `apps/web/src/templates/first/components/Services/index.jsx`
- `apps/web/src/templates/second/components/ServicesComponent/ServicesContent.jsx`
- `apps/web/src/templates/third/components/Services/index.jsx`
- `apps/web/src/templates/fourth/components/ServicesContent.jsx`
- `apps/web/src/templates/fifth/components/ServicesContent/index.jsx`
- `apps/web/src/templates/sixth/components/ServicesSection/index.jsx`
- `apps/web/src/templates/seventh/components/ServicesSection/index.jsx`
- `apps/web/src/templates/eighth/components/ServicesSection/index.jsx`
- `apps/web/src/sections/features/ServicesGrid/index.jsx`

## Resumen

Se centralizo la resolucion de media para service cards en un componente reutilizable (`ServiceCardMedia`). El helper detecta imagen en `image`, `imageUrl` o `image_url`, resetea el estado cuando cambia la media y hace fallback a icono o variante visual del template si la imagen falta o falla.

En los templates sixth, seventh y eighth se separo el wrapper de imagen del wrapper de icono. Antes la imagen heredaba fondo, borde, padding o forma pensados solo para iconos. Ahora la imagen entra en un bloque de media propio con `object-cover`, mientras que el icono o numero se mantiene solo como fallback.

En los templates first, second, third, fourth, fifth y en `sections/features/ServicesGrid` se reemplazo la logica ad hoc por el helper compartido para que el storefront soporte servicios sin imagen y URLs rotas sin dejar placeholders rotos.

Tambien se flexibilizo el `ServiceSchema` del storefront para aceptar `image_url` vacio y `file_path` opcional, alineando el contrato con el caso funcional de servicios sin imagen.

## Como probar

1. En `apps/web`, correr `npm run lint`.
2. En `apps/web`, correr `npm run typecheck`.
3. En `apps/web`, correr `npm run build`.
4. Validar cada template con:
   - servicio con imagen valida
   - servicio sin imagen
   - servicio con URL rota
   - servicio sin `service.icon`
5. Confirmar visualmente que sixth, seventh y eighth no muestran imagenes dentro del wrapper chico del icono.

## Riesgos

- El schema web ahora tolera `image_url` vacio; si algun flujo dependia implicitamente de URL obligatoria, ese supuesto queda relajado a favor del fallback visual.
- Los templates con fallback iconico ahora pueden mostrar iconos genericos cuando no existe `service.icon` explicito.

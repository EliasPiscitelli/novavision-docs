# Cambio: preview nativo para templates 6-8 y paridad de contacto

- Autor: GitHub Copilot
- Fecha: 2026-03-13
- Rama: develop
- Archivos: apps/web/src/pages/PreviewHost/index.tsx, apps/web/src/registry/sectionComponents.tsx

## Resumen

Se corrigio la divergencia entre el preview del builder/onboarding y la homepage real para los templates 6, 7 y 8.

## Que se cambio

- `PreviewHost` ahora renderiza el page component nativo del template para `template_6`, `template_7` y `template_8`.
- El payload del preview se transforma en `homeData` con `config.sections`, para reutilizar el mismo flujo dinamico que usa produccion.
- Las keys `content.contact.sixth`, `content.contact.seventh` y `content.contact.eighth` dejaron de apuntar al componente legacy `DynamicContactSection` y pasan a usar sus componentes modernos por template.

## Por que

El preview estaba armando la home seccion por seccion con `SectionRenderer`, mientras que la homepage real renderiza page components completos desde `HomeRouter`. Eso permitia que aparezcan headers/contact blocks legacy en el preview aunque no existan en la tienda real. En templates Tailwind, esta diferencia tambien empeoraba la paridad visual del onboarding.

## Como probar

1. En `apps/web`, ejecutar `npm run lint`.
2. En `apps/web`, ejecutar `npm run typecheck`.
3. En `apps/web`, ejecutar `npm run build`.
4. Levantar `apps/web` y `apps/admin` en desarrollo.
5. Abrir el Design Studio o Step 4 del onboarding con template 6, 7 u 8.
6. Verificar que el preview ya no renderice el bloque legacy de contacto ni un header extra distinto del storefront real.
7. Comparar contra la homepage real de una tienda afectada, por ejemplo Farma.

## Notas de seguridad

- No se modificaron permisos, autenticacion ni flujos de datos sensibles.
- El cambio afecta solo al render del preview dentro del iframe y a la seleccion de componentes visuales nativos.

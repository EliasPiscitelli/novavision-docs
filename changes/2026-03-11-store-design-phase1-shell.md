# Cambio: Fase 1 del shell tipo Step 4 para Store Design

- Fecha: 2026-03-11
- Autor: GitHub Copilot
- Rama: develop
- Archivos: apps/web/src/components/admin/StoreDesignSection/index.jsx, apps/web/src/components/admin/StoreDesignSection/style.jsx, apps/web/src/__tests__/store-design-section.test.jsx

## Resumen

Se reorganizo la superficie de Store Design para que funcione como un editor guiado en tres modos: Pagina, Template y Theme. La persistencia y los servicios se mantuvieron intactos; el cambio se concentra en la UX de navegacion, foco y lectura comercial.

## Que cambio

- Se agregaron tabs principales para separar estructura, template y theme.
- La vista Pagina ahora usa un rail de bloques seleccionables y un inspector contextual unico para editar props del bloque activo.
- La vista central mantiene el preview embebido como canvas constante.
- Se agrego una franja superior con metricas rapidas de pagina, template, theme y creditos estructurales.
- El guardado visual ahora se deshabilita cuando hay incompatibilidad, bloqueo comercial o faltan creditos requeridos.
- La barra inferior paso a ser sticky y ahora resume el costo/comportamiento comercial del cambio con CTAs contextuales.
- Los bloqueos de Template y Theme ahora disparan tracking de intencion comercial en analytics del storefront y permiten iniciar upgrade de plan o ir al Addon Store desde el mismo editor.
- Se actualizaron tests unitarios para contemplar la nueva navegacion por tabs.

## Por que

La pantalla anterior mezclaba demasiadas decisiones en una sola superficie. Esta fase busca acercar Store Design a la claridad operativa del Step 4 del onboarding sin esperar todavia cambios de backend sobre componentKey o variantes persistidas.

## Como probar

1. Abrir Store Design en el panel admin.
2. Verificar que existan las tabs Pagina, Template y Theme.
3. En Pagina, seleccionar un bloque y editar props desde el inspector derecho.
4. En Template y Theme, cambiar una opcion y confirmar que el preview se mantenga visible.
5. Verificar que el boton Guardar diseño se bloquee si faltan creditos o hay una seleccion no elegible.
6. Ejecutar: `cd apps/web && npx vitest run src/__tests__/store-design-section.test.jsx src/__tests__/contact-section-renderer.test.jsx`

## Notas de seguridad

- No se tocaron secretos, contratos de API ni reglas de multitenancy.
- El preview sigue operando con datos reales del tenant y token de preview existente.

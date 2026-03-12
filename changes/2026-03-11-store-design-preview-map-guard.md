# Cambio: Guard de mapas externos en preview y aclaración de límite Step 4

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: develop / feature/multitenant-storefront
- Archivos: apps/web/src/preview/PreviewProviders.tsx, apps/web/src/sections/content/ContactInfo/index.jsx, apps/web/src/__tests__/contact-section-renderer.test.jsx

Resumen: El preview embebido ahora propaga explícitamente `mode=editor` dentro del iframe y el bloque de contacto deja de incrustar Google Maps en ese contexto. En lugar del iframe se muestra un estado seguro con CTA al mapa real, evitando errores CSP en consola y manteniendo visibles los datos reales de la tienda.

Por qué: El Store Design ya estaba mostrando contenido real, pero la previsualización intentaba cargar iframes externos bloqueados por CSP. Además, hacía falta una señal de render mode consistente para que los componentes puedan reaccionar distinto en preview. Se documenta también que la paridad completa con Step 4 sigue limitada por el contrato actual de `home_sections`, que persiste `type/new_type` y no variantes `componentKey`.

Cómo probar:

1. En apps/web correr `npm run lint`.
2. En apps/web correr `npm run typecheck`.
3. En apps/web correr `npm run build`.
4. Abrir Store Design con una sección de contacto que tenga `mapUrl` real.
5. Verificar que en el iframe de preview no aparezca el mapa incrustado ni errores CSP de Google Maps, y que sí aparezca el texto de vista previa con el botón para abrir el mapa.

Notas de seguridad: El cambio evita incrustar contenido externo bloqueado por la política del preview. No modifica credenciales ni permisos. La evolución a un editor igual a Step 4 requiere ampliar backend/API para soportar variantes persistidas por `componentKey`.
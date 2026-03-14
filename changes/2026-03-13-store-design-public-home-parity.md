# Fix: Paridad Store Design publicado + template custom como guía

- Fecha: 2026-03-13
- Autor: agente-copilot
- Rama API: feature/automatic-multiclient-onboarding
- Rama Web: feature/multitenant-storefront

## Archivos modificados

- `apps/api/src/home/default-template-sections.ts`
- `apps/api/src/home/home-settings.service.ts`
- `apps/web/src/components/admin/StoreDesignSection/compatibility.js`
- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- `apps/web/src/components/admin/StoreDesignSection/__tests__/compatibility.test.js`

## Resumen

Se corrigieron dos frentes relacionados con Diseño de Tienda:

1. La home pública ya no queda sin estructura cuando el tenant no tiene `home_sections` ni `design_config.sections` persistidos. `HomeSettingsService` ahora devuelve una estructura fallback determinística basada en `template_key`.
2. El template del editor deja de operar como compatibilidad rígida. Si una sección custom ya tiene renderer válido, se considera compatible aunque el template activo sea otro. Esto permite que el diseño final sea realmente custom respetando estructura, límites y plan.

## Motivo

La auditoría de `farma` mostró que:

- `client_home_settings.design_config.sections = 0`
- `home_sections = 0`
- `/home/data` devolvía `config.sections = []`

Además, el editor seguía evaluando compatibilidad por template como si cada cambio de template obligara a reescribir toda la composición visual, cuando el producto necesita que el template sea solo una guía inicial.

## Cómo probar

### API

1. Levantar API.
2. Consultar `GET /home/data` de un tenant sin `home_sections` persistidas.
3. Verificar que `config.sections` ya no llegue vacío.

### Web

1. Abrir `admin-dashboard?storeDesign`.
2. Seleccionar un template distinto.
3. Mantener un componente custom de otro template que sí tenga renderer.
4. Confirmar que el editor siga mostrando preview y no trate esa composición como incompatible.

## Notas

- Este fallback publicado resuelve el caso vacío, pero no reemplaza una estrategia futura de persistencia explícita del último diseño real.
- El próximo paso natural es backfillear tenants ya afectados para que `home_sections` refleje su composición publicada efectiva.
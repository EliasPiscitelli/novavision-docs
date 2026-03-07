# Builder design_config publish sync

- Fecha: 2026-03-06
- Autor: GitHub Copilot
- Rama: feature/multitenant-storefront / feature/automatic-multiclient-onboarding

## Archivos modificados

- apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx
- apps/admin/src/services/builder/designSystem.ts
- apps/api/src/onboarding/onboarding.controller.ts
- apps/api/src/onboarding/onboarding.service.ts
- apps/api/src/worker/provisioning-worker.service.ts
- apps/api/src/home/home-settings.service.ts
- apps/api/src/admin/admin.service.ts
- apps/api/migrations/backend/20260306_add_design_config_to_client_home_settings.sql
- apps/web/src/components/DynamicHeader.jsx

## Resumen

Se alineo el flujo de Step 4 para que la estructura personalizada de la home viaje completa desde el builder hasta la tienda publicada.

Tambien se corrigieron las reglas de validacion para que coincidan con el builder actual, se hicieron visibles los limites de estructura en la UI y se ajusto el header productivo para resolver `componentKey` y aliases actuales del builder.

## Por que se hizo

- Preview y tienda publicada no compartian exactamente la misma fuente de verdad.
- `designConfig` se guardaba en onboarding pero no siempre llegaba a `client_home_settings`.
- El backend validaba un esquema viejo de secciones.
- Los mensajes de limites no eran suficientemente claros para el cliente.

## Como probar

### Admin

1. Ir al Builder Step 4.
2. Cambiar template, personalizar estructura y reemplazar header/footer.
3. Verificar que la tarjeta de reglas muestre limites claros.
4. Confirmar que al publicar no avance si falla la persistencia.

### API

1. Ejecutar la migracion `20260306_add_design_config_to_client_home_settings.sql`.
2. Guardar preferencias con `designConfig` desde onboarding.
3. Confirmar que `nv_onboarding.design_config` y `client_home_settings.design_config` queden sincronizados.
4. Consultar `/home/data` y verificar `config.sections`.

### Web

1. Abrir una tienda con estructura custom publicada.
2. Confirmar que el header publicado respete `componentKey` del builder.
3. Confirmar que el resto de secciones renderice desde `config.sections`.

## Notas de seguridad

- La validacion backend sigue limitando la estructura a tipos y cantidades permitidas.
- Header y footer quedan fijados en posiciones obligatorias.
- La tienda publicada solo consume configuracion persistida en backend.
# Cambio: cobertura de tests para navegación Outreach → inbox

- Autor: GitHub Copilot
- Fecha: 2026-03-10
- Rama: feature/automatic-multiclient-onboarding

## Archivos modificados

- `../NovaVisionRepo/apps/admin/src/pages/AdminInbox/inboxMatching.js`
- `../NovaVisionRepo/apps/admin/src/pages/AdminDashboard/outreachView.helpers.js`
- `../NovaVisionRepo/apps/admin/src/pages/AdminInbox/__tests__/inboxMatching.test.ts`
- `../NovaVisionRepo/apps/admin/src/pages/AdminDashboard/__tests__/outreachView.helpers.test.ts`
- `../NovaVisionRepo/apps/admin/src/pages/AdminInbox/index.jsx`
- `../NovaVisionRepo/apps/admin/src/pages/AdminInstagramInbox/index.jsx`
- `../NovaVisionRepo/apps/admin/src/pages/AdminDashboard/OutreachView.jsx`

## Resumen

Se agregaron tests unitarios para cubrir las últimas mejoras operativas del dashboard multicanal. La lógica de selección automática de conversaciones y el armado de deep links desde Outreach hacia los inboxes de WhatsApp e Instagram quedaron movidos a helpers dedicados y ahora están validados por Vitest.

La cobertura nueva asegura que:

- `leadId` tenga prioridad al abrir un inbox desde Outreach;
- el matching por teléfono y nombre funcione para WhatsApp;
- el matching por email y nombre funcione para Instagram;
- los filtros `days` y `channel` acepten solo valores válidos;
- los links hacia inbox con `q`, `hot` y `leadId` se construyan de forma consistente.

## Por qué

Hasta ahora la funcionalidad estaba validada por lint, typecheck y build, pero faltaba una red de seguridad específica para la lógica más reciente. Esta cobertura reduce regresiones en uno de los puntos más sensibles del flujo operativo: saltar del pipeline a la conversación correcta.

## Cómo probar

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npm test
npm run lint
npm run typecheck
npm run build
```

## Notas de seguridad

- Cambio acotado al frontend admin.
- Sin impacto en credenciales, RLS o contratos de API.
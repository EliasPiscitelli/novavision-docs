# Cambio: badges de canal para diferenciar Instagram y WhatsApp en el inbox admin

- Autor: GitHub Copilot
- Fecha: 2026-03-10
- Rama: feature/automatic-multiclient-onboarding

## Archivos modificados

- `../NovaVisionRepo/apps/admin/src/components/Inbox/ConversationList/index.jsx`
- `../NovaVisionRepo/apps/admin/src/components/Inbox/ConversationList/style.jsx`
- `../NovaVisionRepo/apps/admin/src/components/Inbox/ConversationHeader/index.jsx`
- `../NovaVisionRepo/apps/admin/src/components/Inbox/ConversationHeader/style.jsx`
- `../NovaVisionRepo/apps/admin/src/pages/AdminInbox/index.jsx`
- `../NovaVisionRepo/apps/admin/src/pages/AdminInstagramInbox/index.jsx`

## Resumen

Se agregó diferenciación visual de canal en el inbox del panel admin. Cada conversación ahora muestra un badge con icono y color según su origen:

- `📱 WhatsApp` en verde
- `📸 Instagram` en rosa

Además, el header del inbox de WhatsApp ahora también expone el canal activo para evitar ambigüedad al gestionar conversaciones manuales.

También se extendió la vista unificada de seguimiento (`Outreach Pipeline`) con un filtro por canal que permite alternar entre:

- ambos canales,
- solo WhatsApp,
- solo Instagram.

La selección ahora también persiste en querystring (`days` y `channel`) para compartir links directos a una vista ya segmentada, por ejemplo una revisión rápida de Instagram de los últimos 14 días.

Sobre esa misma base, también se agregaron accesos rápidos con presets operativos para abrir de inmediato vistas frecuentes como `WhatsApp 14d`, `WhatsApp 30d`, `Instagram 7d` e `Instagram 14d`, junto con una acción para copiar la URL exacta de la vista activa y compartirla sin tener que reconfigurar filtros manualmente. Además, esos accesos quedaron expuestos desde la home del dashboard para entrar al pipeline ya segmentado desde el primer nivel, mostrando también contadores resumidos de leads y mensajes antes de navegar. Finalmente, los inboxes de WhatsApp e Instagram quedaron enlazados con Outreach para saltar directamente al pipeline del canal actual, y Outreach ahora puede devolver al inbox correcto con la búsqueda del lead ya cargada e intentando seleccionar automáticamente la conversación más probable.

El filtro opera sobre `outreach_leads.last_channel` para el pipeline y sobre `outreach_logs.channel` para la actividad diaria, manteniendo consistencia con el flujo actual de WhatsApp y con el nuevo ingreso de Instagram.

Por último, se removió el outline visible del botón `x` del popover de Driver.js en el tour del admin.

## Por qué

Después de estabilizar el flujo de Instagram y corregir la deduplicación de leads legacy, quedaba una fricción operativa: en el dashboard las conversaciones seguían viéndose demasiado parecidas y el seguimiento unificado no podía segmentarse rápido por canal. El objetivo de este ajuste es que el operador pueda distinguir y filtrar el origen de los leads a simple vista sin abrir cada conversación.

## Cómo probar

```bash
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/admin
npm run dev
```

Luego:

1. abrir `/dashboard/inbox` y validar badges `📱 WhatsApp` en el listado;
2. abrir `/dashboard/inbox-instagram` y validar badges `📸 Instagram` en el listado;
3. seleccionar una conversación de WhatsApp y verificar el indicador de canal en el header;
4. abrir `/dashboard/outreach` y validar el cambio de KPIs, actividad y hot leads al alternar entre `Todos`, `WhatsApp` e `Instagram`;
5. usar los accesos rápidos y validar que actualicen la vista y la URL con un click;
6. usar `Copiar vista actual`, abrir el link en otra pestaña y verificar que se cargue la misma segmentación;
7. abrir el inbox de WhatsApp y validar el acceso hacia Outreach con `channel=WHATSAPP`;
8. abrir el inbox de Instagram y validar el acceso hacia Outreach con `channel=INSTAGRAM`;
9. desde Outreach, usar `Abrir inbox` sobre un lead y verificar que navegue al inbox correcto con `q`, `hot` y `leadId` cuando exista;
10. verificar que el inbox respete esos query params, deje los filtros aplicados e intente seleccionar automáticamente la conversación correspondiente;
11. volver a `/dashboard` y verificar que existan atajos hacia Outreach ya segmentado por canal con contadores resumidos visibles;
12. confirmar que la URL persista `days` y `channel` y que al refrescar la página se conserve la misma vista;
13. iniciar un tour del admin y verificar que la `x` de cierre no pinte outline al enfocarse.

## Notas de seguridad

- No hay cambios de backend ni base de datos.
- No cambian contratos de API ni permisos.
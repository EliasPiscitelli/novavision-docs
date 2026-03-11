# Cambio: Onboarding “Completá tu tienda” + Import JSON

- Autor: GitHub Copilot
- Fecha: 2026-02-02
- Rama: feature/automatic-multiclient-onboarding
- Archivos:
  - apps/api/src/client-dashboard/client-dashboard.service.ts
  - apps/api/src/client-dashboard/client-dashboard.controller.ts
  - apps/api/src/admin/admin.service.ts
  - src/client-dashboard/client-dashboard.service.ts
  - src/client-dashboard/client-dashboard.controller.ts
  - src/admin/admin.service.ts
  - apps/admin/src/pages/ClientCompletionDashboard/index.tsx
  - apps/admin/src/pages/ClientCompletionDashboard/JsonImportModal.tsx
  - CHANGELOG.md
  - apps/api/CHANGELOG.md

## Resumen de cambios
- Checklist de completitud coherente con requirements efectivos y porcentaje.
- Estado de logo basado en draft (onboarding) o publicado (backend).
- Importación por JSON idempotente con resumen de resultados.
- UX del onboarding: bloque de pendientes, cards con regla + conteo y modal de import.

## Por qué
- Evitar inconsistencias (porcentaje vs “X de Y”).
- Reflejar el estado real del logo durante el draft.
- Acelerar el alta con carga masiva por JSON.

## Cómo probar
1. Abrir “Completá tu tienda”.
2. Verificar que el porcentaje coincide con “X de Y”.
3. Cargar logo draft → card muestra “Logo cargado. Se publicará al aprobar.”
4. Importar JSON desde el modal → no duplica en segunda importación.
5. Confirmar refresh del checklist sin recargar la app.

## Comandos ejecutados
- No ejecutados (pendiente de confirmación del TL).

## Notas de seguridad
- Sin cambios en credenciales ni políticas RLS.

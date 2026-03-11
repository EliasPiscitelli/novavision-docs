# Cambio: Admin palettes con SuperAdminGuard + normalización

- Autor: GitHub Copilot
- Fecha: 2026-01-23
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/palettes/palettes.controller.ts, src/palettes/palettes.service.ts

Resumen: Se corrigieron los guards de endpoints admin (ahora SuperAdmin) y se normaliza `min_plan_key` (pro→enterprise) + `preview` en create/update.

Por qué: El endpoint admin devolvía 401 por requerir builder token y persistía `pro` en datos.

Cómo probar / comandos ejecutados:
- Pendiente de ejecución por el TL.

Notas de seguridad: No aplica.

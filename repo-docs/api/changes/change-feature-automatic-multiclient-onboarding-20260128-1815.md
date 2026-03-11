# Cambio: Ajuste de lint para scripts

- Autor: agente-copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/.eslintignore, apps/api/docs/subscription-system-walkthrough.md, apps/api/docs/subscription-admin-dashboard.md, apps/api/docs/changes/change-role-separation-20260124-0040.md, docs/subscription-system-walkthrough.md, docs/subscription-admin-dashboard.md

Resumen: Se excluyó el script de normalización de paletas del lint tipado y se limpiaron referencias al módulo de revisión admin en documentación.

Por qué: El script es JS y no está incluido en el TSConfig de ESLint; ignorarlo evita falsos positivos sin afectar el build. Además, el módulo de revisión admin está deprecado y se removieron referencias documentales.

Cómo probar / comandos ejecutados:
- npm run lint (apps/api)
- npm run typecheck (apps/api)

Notas de seguridad:
- No aplica.

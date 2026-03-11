# Cambio: validación server-side de plan mínimo en checkout onboarding

- Autor: agente-copilot
- Fecha: 2026-01-23
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/onboarding/onboarding.service.ts, src/onboarding/onboarding.service.ts

Resumen: Se valida el plan mínimo requerido antes de iniciar checkout, bloqueando planes incompatibles con las selecciones del wizard.

Por qué: Evitar pagos con plan inferior a las selecciones (hard-gating server-side).

Cómo probar / comandos ejecutados:
- No se ejecutaron comandos.

Notas de seguridad:
- Sin impacto en credenciales o permisos.

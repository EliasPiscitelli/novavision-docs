# Cambio: Permitir paletas con builder token

- Autor: GitHub Copilot
- Fecha: 2026-01-23
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/auth/auth.middleware.ts

Resumen: Se permite el acceso a rutas de paletas cuando se envía `X-Builder-Token`, evitando 401 sin Authorization.

Por qué: El flujo de onboarding usa builder token y el middleware bloqueaba `/palettes/*`.

Cómo probar / comandos ejecutados:
- Pendiente de ejecución por el TL.

Notas de seguridad: Solo se omite Authorization si existe `X-Builder-Token` y la ruta es `/palettes`.

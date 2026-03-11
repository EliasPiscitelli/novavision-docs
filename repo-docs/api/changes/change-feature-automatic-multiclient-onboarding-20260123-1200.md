# Cambio: Templates públicos sin Authorization

- Autor: GitHub Copilot
- Fecha: 2026-01-23
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/app.module.ts

Resumen: Se excluyó GET /templates del AuthMiddleware para permitir el acceso público según el controlador de templates.

Por qué: El endpoint es público en TemplatesController, pero el middleware requería Authorization y devolvía 401.

Cómo probar / comandos ejecutados:
- Pendiente de ejecución por el TL.

Notas de seguridad: Se mantiene el acceso público solo para GET /templates.

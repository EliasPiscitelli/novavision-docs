# Cambio: Theme unificado en emails de onboarding

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/onboarding/onboarding-notification.service.ts

Resumen: Se unificó el theme de emails al estilo visual de NovaVision y se actualizaron los datos de contacto (email, sitio, Instagram).

Por qué: El preview debía alinearse a la UX/UI de NovaVision y mostrar información de contacto relevante.

Cómo probar / comandos ejecutados:
- No se ejecutaron comandos.
- Usar /admin/clients/:id/review-email/preview y verificar el HTML con el nuevo theme y footer actualizado.

Notas de seguridad: No se expone información sensible; solo se ajusta contenido de emails.

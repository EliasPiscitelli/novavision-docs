# Cambio: Fix envío de email de ajustes

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/admin/admin.service.ts

Resumen: Se agregó fallback de `clientId` al `accountId` cuando no existe cliente backend, evitando error al encolar emails de ajustes.

Por qué: El endpoint /admin/clients/:id/request-changes fallaba con 500 cuando el cliente backend aún no estaba creado.

Cómo probar / comandos ejecutados:
- No se ejecutaron comandos.
- Llamar POST /admin/clients/:id/request-changes con un account sin client backend y verificar respuesta 200 y email encolado.

Notas de seguridad: No se exponen secretos ni se altera RLS.

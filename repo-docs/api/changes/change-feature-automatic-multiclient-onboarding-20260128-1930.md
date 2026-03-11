# Cambio: Flags MercadoPago en checkout/status

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/onboarding/onboarding.service.ts

Resumen: Se extendió la respuesta de checkout/status para incluir datos de conexión a MercadoPago (conectado, modo y fecha).

Por qué: Permitir que el frontend muestre el estado real de credenciales MP en el resumen del onboarding.

Cómo probar / comandos ejecutados:
- No se ejecutaron comandos.
- Consultar GET /onboarding/checkout/status con builder token válido y verificar campos mp_connected, mp_live_mode, mp_connected_at.

Notas de seguridad: No se expone mp_access_token; solo flags y metadatos no sensibles.

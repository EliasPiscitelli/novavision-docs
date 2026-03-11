# Cambio: Fix onboarding platform (membresía + métricas)

- Autor: agente-copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/auth/auth.service.ts, apps/api/src/metrics/metrics.interceptor.ts

## Resumen
Se ajusta el flujo OAuth `platform` para que la membresía se cree con el cliente interno correcto (Admin DB) y se evita enviar `client_id` no-UUID al ledger de métricas.

## Por qué
El callback fallaba al intentar insertar `client_id=platform` en la base multicliente y el ledger de uso rechazaba `platform` por no ser UUID.

## Cambios
- `AuthService` fuerza `platform` al crear membresía cuando el flujo es platform.
- `AuthService` usa `internalClient` al reconciliar ID por email.
- `MetricsInterceptor` filtra `client_id` no-UUID y usa `UNKNOWN_CLIENT`.

## Cómo probar
1. Reintentar OAuth Google con `client_id=platform`.
2. Verificar que el callback responde 200 y redirige al onboarding.
3. Confirmar que `public.users` en Admin DB crea el usuario con `client_id` NULL y sin errores.
4. Revisar logs: no debe aparecer "invalid input syntax for type uuid: \"platform\"" en `usage_ledger`.

## Notas de seguridad
- No se exponen credenciales ni se alteran permisos.

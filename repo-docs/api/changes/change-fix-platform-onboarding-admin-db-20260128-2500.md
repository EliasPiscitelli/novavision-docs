# Cambio: Onboarding platform usa Admin DB

- Autor: GitHub Copilot
- Fecha: 2026-01-28
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/auth/auth.service.ts

## Resumen
Se ajusta el flujo OAuth de `platform` para que las altas y membresías durante onboarding usen la **Admin DB** (control plane), evitando insertar `client_id` UUID en el multicliente antes de la aprobación.

## Por qué
Antes de aprobar la tienda, el usuario opera en la base Admin. El callback intentaba crear membresía en multicliente con `client_id=platform` (string), provocando 500.

## Cambios clave
- `AuthService` detecta `client_id=platform` y usa `SUPABASE_ADMIN_DB_CLIENT`.
- La membresía interna para onboarding se crea con `client_id` `null` (permitido en Admin DB).
- Se evita consultar `clients` para `platform` y se usa `origin/baseUrl` del state o `ADMIN_URL` como fallback.

## Cómo probar
1) OAuth start desde novavision.lat con `client_id=platform`.
2) Completar login Google y validar que `/auth/google/callback` responda 200.
3) Verificar en Admin DB que `public.users` tenga registro con `client_id` `NULL`.

## Notas
- No se cambia el flujo multicliente post-aprobación.
- No se requiere migración.

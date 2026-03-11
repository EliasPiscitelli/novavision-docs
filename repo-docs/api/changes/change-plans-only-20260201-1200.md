# Cambio: Unificar planes en public.plans

- Autor: GitHub Copilot
- Fecha: 2026-02-01 12:00
- Rama: N/A
- Archivos: múltiples (migraciones admin, docs, SQL legacy, scripts)

## Resumen
Se reemplazó el uso de tablas legacy de planes por `public.plans` como única fuente, actualizando migraciones, hardening RLS, seeds y documentación relacionada. Se ajustaron migraciones legacy para operar sobre `plans` o quedar como no-op, y se migraron referencias de `plan_catalog`/`plan_definitions` hacia `plans`.

## Por qué
Unificar el origen de planes evita inconsistencias, reduce deuda técnica y refuerza la regla de usar `public.plans` en todo el stack.

## Cómo probar
- API: ejecutar lint/typecheck/build.
- Migraciones: revisar que los scripts de admin usan `ADMIN_043` + `ADMIN_055` y que `public.plans` queda poblada.

## Notas de seguridad
- No se expusieron credenciales ni se modificaron secretos.
- Se mantiene RLS para `public.plans` con lectura pública y escritura service_role.

# Cambio: Señales de ownership MP en detalle de aprobación

- Autor: GitHub Copilot
- Fecha: 2026-01-27
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/mp-oauth/mp-oauth.service.ts, apps/api/src/admin/admin.service.ts, apps/api/src/admin/admin.module.ts

## Resumen de cambios
Se agregó un método en MpOauthService para consultar `users/me` en Mercado Pago y devolver señales de ownership (match/mismatch/unverified). El detalle de aprobación incluye estas señales para mostrar en el dashboard admin.

## Por qué
Permite validar si la cuenta de Mercado Pago conectada coincide con el titular del onboarding.

## Cómo probar
1. Conectar MP en una cuenta de prueba.
2. Consultar `/admin/pending-approvals/:id` y verificar `mpOwnership`.
3. Validar estados: verified/mismatch/unverified según el email.

## Notas de seguridad
No se exponen tokens; el acceso se realiza server-side con desencriptado local.

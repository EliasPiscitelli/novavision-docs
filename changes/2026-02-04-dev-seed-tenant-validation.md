# Cambio: Validación de payload en /dev/seed-tenant

- Autor: GitHub Copilot
- Fecha: 2026-02-04
- Rama: feature/automatic-multiclient-onboarding
- Archivos: apps/api/src/dev/dto/dev-seed-tenant.dto.ts, apps/api/src/dev/dev-seeding.controller.ts, apps/api/src/dev/dev-seeding.service.ts

## Resumen
Se agregó validación con `class-validator` para el endpoint `POST /dev/seed-tenant`, verificando campos requeridos y mínimos por defecto (`slug`, `email`, `withDemoData`, `planKey`). Además, el seeding ahora resuelve `client_id` desde la tabla `clients` cuando el `slug` ya existe, evitando duplicados por la ausencia de `nv_accounts.client_id`.

## Por qué
Asegurar que el endpoint de seeding reciba datos válidos y consistentes, evitando seeds inválidos por payloads incompletos o malformados.

## Cómo probar
1. Levantar API: `npm run start:dev`
2. Probar un payload válido:
   - `POST /dev/seed-tenant` con `{ "slug": "test-store", "email": "test@demo.com", "withDemoData": true }`
3. Probar payload inválido:
   - `POST /dev/seed-tenant` con `slug` vacío o `email` inválido y verificar error de validación.

## Notas de seguridad
No aplica.

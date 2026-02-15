# Fix: Slug no se promovía de draft-UUID a slug definitivo

- **Autor**: agente-copilot
- **Fecha**: 2025-06-16
- **Rama**: feature/automatic-multiclient-onboarding
- **Archivos modificados**:
  - `apps/api/src/onboarding/onboarding.service.ts`
  - `apps/api/src/admin/admin.service.ts`
  - `migrations/admin/2025-06-16-fix-slug-promotion-trigger.sql`

## Resumen

El slug de las tiendas aprobadas se mostraba como `draft-UUID` en lugar del slug amigable elegido por el usuario (ej: `e2e-alpha`).

## Causa raíz (3 puntos de fallo)

1. **`submitForReview()`** (onboarding.service.ts): Buscaba `desired_slug` en `wizardData?.payload?.desired_slug` y `currentProgress.desired_slug`, pero el slug se guarda en `builder_payload.desired_slug` (columna independiente de `progress`). Nunca lo encontraba → nunca promovía el slug.

2. **`approveClient()`** (admin.service.ts): Solo consultaba `slug_reservations` (tabla vacía) y caía al fallback `account.slug` (el draft). No tenía fallback a `builder_payload`.

3. **Trigger `prevent_slug_change`**: Bloqueaba cambios de slug para cualquier status != `draft`/`awaiting_payment`, incluso cuando el slug era `draft-*` necesitando promoción al definitivo.

## Correcciones

### 1. `submitForReview()` — onboarding.service.ts
- Se cambió la query de `select('progress')` a `select('progress, builder_payload')`
- Se agregó `currentOnboarding?.builder_payload?.desired_slug` como tercer fallback en la resolución de `desiredSlug`

### 2. `approveClient()` — admin.service.ts
- Se agregó un bloque fallback: si `finalSlug` sigue siendo `draft-*` después de buscar en `slug_reservations`, consulta `nv_onboarding.builder_payload.desired_slug`
- Verifica colisión antes de promover el slug

### 3. Trigger `prevent_slug_change` — migración SQL
- Se agregó condición `AND NOT (OLD.slug LIKE 'draft-%')` para permitir la promoción de slugs temporales al definitivo en cualquier status

## Cómo probar

1. Limpiar datos de test y re-ejecutar E2E onboarding wizard
2. Verificar que `nv_onboarding.builder_payload->>'desired_slug'` = slug elegido
3. Aprobar la cuenta desde el dashboard admin
4. Verificar que `nv_accounts.slug` y `clients.slug` (backend) tengan el slug definitivo, no `draft-*`

## Notas de seguridad

- El trigger sigue protegiendo contra cambios de slug indebidos: solo permite cambios cuando el slug actual empieza con `draft-`
- La verificación de colisión previene promoción a un slug ya tomado

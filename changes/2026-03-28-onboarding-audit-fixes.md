# Fix de hallazgos de auditoría del onboarding wizard

**Fecha:** 2026-03-28
**Apps afectadas:** Admin
**Tipo:** fix

## Resumen

Resolución de 6 hallazgos de la auditoría del flujo de onboarding (wizard builder), desde críticos hasta bajos.

## Hallazgos resueltos

### Fix #1 — CRITICAL: Logo no persistido en backend
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step2Logo.tsx`
- `handleUpload()` solo guardaba el logo en localStorage via `updateState()`, sin persistir en `nv_onboarding.progress`
- Agregado `await updateProgress({ logoUrl: logoPreview })` para sincronizar con backend
- Corregido texto inconsistente: "Max 2MB" → "Max 300KB" (el validador real es 300KB)

### Fix #2 — HIGH: MP connected flag no resiliente
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step7MercadoPago.tsx`
- Si el usuario perdía el estado de localStorage post-OAuth, la conexión MP se perdía
- Agregado `useEffect` que consulta `GET /onboarding/mp-status` al montar para recuperar estado desde backend
- Agregado helper `getMpStatus()` en `services/builder/api.ts`

### Fix #3 — HIGH: Preapproval ID resilience
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step5Auth.tsx`
- Ya existía guardado de `preapprovalId` en context (línea 92) — verificado correcto
- Agregada guarda adicional `!state.userId` en el link-user useEffect para prevenir llamadas redundantes

### Fix #4 — MEDIUM: DNI upload sin retry
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step8ClientData.tsx`
- Upload de FormData al endpoint `/accounts/dni/upload` fallaba silenciosamente en redes inestables
- Agregado retry con backoff exponencial (max 3 intentos, 1s/2s delay)
- No retries en errores 4xx (errores de cliente)

### Fix #5 — MEDIUM: Password policy débil
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step8ClientData.tsx`
- Validación anterior: solo `length >= 6`
- Nueva validación: `length >= 8` + al menos 1 mayúscula + al menos 1 número
- Placeholder actualizado para reflejar la nueva política

### Fix #6 — LOW: Race condition en link-user
**Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step5Auth.tsx`
- Guard existente ya prevenía la mayoría de casos (`state.userId !== user.id`)
- Agregada guarda explícita `!state.userId` al check de `link-user` para robustez adicional

## Validación

- Admin: lint ✓, typecheck ✓, build ✓

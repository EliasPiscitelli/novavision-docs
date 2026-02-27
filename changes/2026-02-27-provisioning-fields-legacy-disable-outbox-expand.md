# Cambio: F0.7 + F0.8 + F1.1 — Provisioning fields, legacy removal, outbox expand

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Archivos:**
  - `src/worker/provisioning-worker.service.ts` (-461 líneas)
  - `src/outbox/outbox-worker.service.ts`

---

## F0.7 — Campos faltantes en upsert FROM_ONBOARDING

### Problema
Los dos bloques upsert en `provisionClientFromOnboarding` (saga path y direct path) no escribían 5 campos críticos que sí estaban en el legacy `PROVISION_CLIENT`:

| Campo | Valor |
|-------|-------|
| `plan_key` | `planKey` (variable ya existía pero solo se escribía como `plan`) |
| `billing_period` | `'monthly'` |
| `locale` | Derivado de `country` vía `countryLocaleMap` |
| `timezone` | Derivado de `country` vía `countryLocaleMap` |
| `publication_status` | `'draft'` |

### Fix
- Se duplicó el `countryLocaleMap` del legacy path (AR, MX, CL, CO) para la función `provisionClientFromOnboarding`
- Se agregaron los 5 campos a ambos bloques upsert (saga y direct)
- Ahora el cliente en Backend DB nace con todos los campos necesarios

---

## F0.8 — Eliminar legacy PROVISION_CLIENT (completo)

### Problema
El path `PROVISION_CLIENT` en el switch/case del worker era una versión anterior que no manejaba correctamente:
- Clusters multi-tenant (solo usaba el default)
- Campos de locale/timezone (los tenía pero con lógica diferente)
- Template normalización

Al coexistir dos paths, había riesgo de provisioning inconsistente y ~461 líneas de código muerto.

### Fix
- El `case 'PROVISION_CLIENT'` ahora hace `throw new Error(...)` con mensaje claro de deprecación
- El método `_provisionClient_DEPRECATED` fue **eliminado por completo** (~250 líneas)
- El helper `syncCustomPalette` fue **eliminado** (~100 líneas) — solo era usado por el legacy path; FROM_ONBOARDING tiene su propia lógica de paletas (L1056-1067)
- Los helpers de theme **eliminados** (~115 líneas): `DEFAULT_THEME_VARS`, `REQUIRED_THEME_KEYS`, `normalizeHexColor()`, `rgbaFromHex()`, `getContrastYIQ()`, `normalizeThemeVars()` — solo usados por `syncCustomPalette`
- **Total: -461 líneas de código muerto eliminado** (archivo pasó de 2499 a 2038 líneas)
- Si algún job viejo llega con tipo `PROVISION_CLIENT`, falla explícitamente

---

## F1.1 — Expandir outbox `account.updated` handler

### Problema
El handler `handleAccountUpdated` en `outbox-worker.service.ts` solo mapeaba 5 campos:
- `business_name` → `name`
- `email` → `email_admin`
- `slug` → `slug`
- `is_active` → `is_active`
- `plan_key` → `plan`

Faltaban 11 campos que sí se persistían en el provisioning inicial.

### Fix
Se expandió `allowedFields` con:

| Admin field | Backend field(s) |
|-------------|-----------------|
| `plan_key` | `plan` + `plan_key` (ahora actualiza ambos) |
| `billing_email` | `billing_email` |
| `phone` | `phone` |
| `phone_full` | `phone_full` |
| `country` | `country` |
| `persona_type` | `persona_type` |
| `legal_name` | `legal_name` |
| `fiscal_id` | `fiscal_id` |
| `fiscal_id_type` | `fiscal_id_type` |
| `fiscal_category` | `fiscal_category` |
| `fiscal_address` | `fiscal_address` |
| `subdivision_code` | `subdivision_code` |

El tipo de `allowedFields` se cambió de `Record<string, string>` a `Record<string, string | string[]>` para soportar la actualización de múltiples columnas backend desde un solo campo admin (`plan_key` → `plan` + `plan_key`).

---

## Cómo probar

1. **F0.7**: Provisionar un cliente nuevo vía onboarding. Verificar en Backend DB que `clients` tiene `plan_key`, `billing_period`, `locale`, `timezone`, `publication_status` correctamente poblados.
2. **F0.8**: Intentar crear un job con `job_type = 'PROVISION_CLIENT'`. Debe fallar con mensaje "PROVISION_CLIENT is deprecated".
3. **F1.1**: Actualizar campos fiscales/contacto de una `nv_account` (disparar outbox event `account.updated`). Verificar que los campos se reflejan en `clients` del Backend DB.

## Validación
- `npm run lint` → 0 errores (solo warnings preexistentes)
- `npm run typecheck` → 0 errores
- `npm run build` → exitoso

# Fase 2 — Normalización plan_key

- **Autor:** agente-copilot
- **Fecha:** 2026-02-09
- **Rama:** feature/automatic-multiclient-onboarding
- **Commits:** `daa4b72` (migration + módulo canónico), `9ffd0c5` (consolidación duplicados)

---

## Resumen

Centralización de toda la lógica de normalización de planes en un único módulo canónico (`src/common/plans/plan-keys.ts`), eliminando 7 copias independientes dispersas por el codebase. Además, se agregaron las columnas `plan_key` y `billing_period` a la tabla `clients` (Multi DB) con backfill desde la columna legacy `plan`.

## Problema

Existían **7 definiciones independientes** de `normalizePlanKey` con lógica ligeramente diferente:
- Algunas solo mapeaban `'pro'` → `'enterprise'`
- La versión del guard también mapeaba `'professional'` → `'growth'` y `'premium'` → `'enterprise'`
- Ninguna cubría todos los aliases (`basic`, `professional`, `premium`, `pro`, `scale`)

La columna `plan` en `clients` contenía valores legacy inconsistentes (mezcla de `starter`, `growth`, `professional`).

## Cambios realizados

### Migración: `BACKEND_008_clients_plan_key_billing_period.sql`
- Nuevas columnas: `plan_key` (CHECK: starter/growth/enterprise) y `billing_period` (CHECK: monthly/annual)
- Backfill automático desde `plan`: `basic/starter` → `starter`, `professional/growth` → `growth`, `premium/pro/enterprise/scale` → `enterprise`
- NOT NULL + defaults + índice `idx_clients_plan_key`
- **Ejecutada en producción** — 4 filas correctamente migradas

### Módulo canónico: `src/common/plans/plan-keys.ts`
Exports:
- `PlanKey` type: `'starter' | 'growth' | 'enterprise'`
- `BillingPeriod` type: `'monthly' | 'annual'`
- `PlanKeyInput` type: todos los aliases conocidos
- `PLAN_ORDER`: jerarquía numérica para comparaciones
- `PLAN_KEYS`: array constante
- `normalizePlanKey(plan?)`: mapeo canónico con switch exhaustivo
- `isPlanEligible(current, required)`: comparación de jerarquía
- `parsePlanKeyCompound(key)`: parsea `'growth_annual'` → `{ planKey: 'growth', billingPeriod: 'annual' }`

### Archivos consolidados (7)

| Archivo | Antes | Después |
|---------|-------|---------|
| `plans/featureCatalog.ts` | `export type PlanKey` local | Re-export desde plan-keys |
| `plans/guards/plan-access.guard.ts` | `PLAN_ORDER` + `normalizePlanKey` locales, lee `clients.plan` | Import canónico, dual-read `plan_key ?? plan` |
| `home/registry/sections.ts` | `PlanKey`, `PlanKeyInput`, `normalizePlanKey`, `canAccessPlan` locales | Import + re-export, `canAccessPlan = isPlanEligible` |
| `types/palette.ts` | `PLAN_TIERS`, `normalizePlanKey`, `canAccessPalette` locales | `PLAN_TIERS = PLAN_ORDER`, `canAccessPalette` usa `isPlanEligible` |
| `onboarding/onboarding.service.ts` | `normalizePlanKey` + `PLAN_ORDER` inline en `startCheckout` | Import canónico |
| `onboarding/validators/design.validator.ts` | `normalizePlanKey` inline | Import canónico |
| `palettes/palettes.service.ts` | `normalizePlanKey` local | Import canónico |

**Resultado:** -70 líneas, +20 líneas. Todas las normalizaciones ahora usan la misma lógica exhaustiva.

### Dual-read en PlanAccessGuard
El guard ahora lee `plan_key, plan` de la tabla `clients` y usa `plan_key ?? plan` como fallback. Esto permite una transición gradual donde:
1. Código nuevo escribe en `plan_key` (columna canónica)
2. Código legacy que aún escribe en `plan` sigue funcionando

## Cómo probar

```bash
# Typecheck (debe dar exit 0)
cd apps/api && npx tsc -p tsconfig.json --noEmit

# Verificar que no quedan normalizePlanKey locales
grep -rn "normalizePlanKey" src/ --include="*.ts" | grep -v plan-keys.ts
# Todas las referencias deben ser imports de @/common/plans/plan-keys

# Verificar columnas en DB
psql "$BACKEND_DB_URL" -c "SELECT id, name, plan, plan_key, billing_period FROM clients;"
```

## Notas de seguridad
- La migración es additive (no rompe código existente que lea `plan`)
- `plan_key` tiene CHECK constraint que previene valores inválidos
- El dual-read asegura que aunque un flujo escriba solo en `plan`, el guard sigue funcionando

## Siguiente paso
- Fase 3: Outbox cross-DB (sincronización Admin ↔ Multi)

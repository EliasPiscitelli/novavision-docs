# AI Credits — Pool Universal

**Fecha:** 2026-03-22
**Tipo:** Refactor + Feature
**Impacto:** API, Web, Admin DB

## Resumen

Migración del sistema de créditos IA de **14 pools per-feature aislados** a un **pool único universal**. El usuario compra créditos genéricos y los usa en cualquier función IA.

## Cambios

### Admin DB (migración SQL)

- **Nueva vista** `account_ai_credit_pool_view`: suma TODOS los `action_code LIKE 'ai_%'` del ledger en un solo `available_credits` por `account_id`
- **Nuevo addon** `ai_universal`: addon virtual de referencia para el pool unificado
- **Desactivados** los 10+ packs IA per-feature (`ai_desc_pack_10`, `ai_qa_pack_20`, etc.)
- **3 packs genéricos nuevos**: x50 ($9.90), x200 ($29.90), x500 ($49.90) — pricing competitivo ~$0.10-0.20/crédito
- **Welcome credits unificados**: una sola fila por plan (`ai_universal`) en lugar de 5 filas per-feature

### API (`ai-credits.service.ts`)

- **Nuevo método** `getUniversalBalance()`: consulta `account_ai_credit_pool_view`
- `getBalance()` delega a `getUniversalBalance()`, ignorando `actionCode`
- `getAllAiBalances()` retorna `{ total, balances[] }` (backward compat: cada action_code reporta el total)
- `assertAvailable()` usa pool universal para verificar balance
- `consumeCredit()` usa `addon_key='ai_universal'` fijo (action_code específico sigue grabándose para auditoría)
- `grantWelcomeCredits()` inserta una sola fila universal en el ledger
- `grantPromoCredits()` acepta `actionCode` opcional, default `ai_universal`
- `reserveCredits()` y `refundReservedCredits()` usan `ai_universal`
- `getCreditHistory()` usa `LIKE 'ai_%'` para incluir entradas universales

### Controllers

- `GET /ai-credits/balances` retorna `{ total, balances }` (nuevo campo `total`)
- `GET /admin/ai-credits/clients/:id/balances` retorna `{ total, balances }`
- `POST /admin/ai-credits/clients/:id/adjust` acepta `action_code` opcional (default `ai_universal`)

### Web (`useAiCredits.js`)

- Nuevo state `totalBalance` alimentado por `data.total`
- `getBalance(actionCode)` retorna `totalBalance` ignorando el argumento → zero-impact en componentes existentes

### Activación de Banner IA (DALL-E / gpt-image-1)

- **Pricing insertado** en `ai_feature_pricing` para `ai_banner_generation`:
  - Normal: 5 créditos, `gpt-image-1`, quality `medium` (~$0.057/imagen)
  - Pro: 8 créditos, `gpt-image-1`, quality `high` (~$0.227/imagen)
- **Quality por tier** en `callOpenAIImageGeneration()`: normal→medium, pro→high
  - Aplica solo a modelos `gpt-image-*` (no afecta DALL-E 3 legacy)

## NO se tocan

- `ai-credits.guard.ts`, `ai-credits.decorator.ts` — sin cambios
- `ai_feature_pricing` — el costo por operación sigue definido per-feature
- `account_action_credit_ledger` — ledger intacto, audit trail completo
- `account_action_credit_balance_view` — usada por storefront actions, sin cambios
- Componentes `AiButton`, `AiTierToggle` — sin cambios (consumen `getBalance()`)

## Archivos modificados

| Archivo | Tipo |
|---------|------|
| `api/migrations/admin/20260322_ai_credits_universal_pool.sql` | Nuevo |
| `api/src/ai-credits/ai-credits.service.ts` | Modificado |
| `api/src/ai-credits/ai-credits.service.spec.ts` | Modificado |
| `api/src/ai-credits/ai-credits.controller.ts` | Modificado |
| `api/src/ai-credits/ai-credits.admin.controller.ts` | Modificado |
| `api/src/ai-generation/ai-generation.service.ts` | Modificado |
| `web/src/hooks/useAiCredits.js` | Modificado |

## Validación

- [x] `npm run build` (API) — OK
- [x] `npx tsc --noEmit` (Web) — OK
- [x] Tests ai-credits: 4 suites, 51 tests — OK
- [x] Tests ai-generation: 2 suites, 72 tests — OK
- [x] Total: 6 suites, 123 tests — todos pasando

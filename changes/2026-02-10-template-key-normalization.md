# Cambio: Normalización de template_key a formato template_N

- **Autor:** agente-copilot
- **Fecha:** 2026-02-10
- **Ramas:**
  - Backend (templatetwobe): `feature/automatic-multiclient-onboarding`
  - Web (templatetwo): `feature/multitenant-storefront`, `develop`, `feature/onboarding-preview-stable`

---

## Resumen

Se unificó el formato de `client_home_settings.template_key` a `template_N` (`template_1`..`template_5`) eliminando la dependencia del formato word-based (`first`..`fifth`) que existía en la DB y que complicaba la escalabilidad al agregar nuevos templates.

## Problema

Existían **dos convenciones de naming** en paralelo:

| Lugar | Formato usado | Ejemplo |
|-------|--------------|---------|
| `clients.template_id` | `template_N` | `template_5` |
| `client_home_settings.template_key` | word-based | `fifth` |
| Código backend (normalizeTemplateKey) | `template_N` | `template_5` |
| Frontend (DynamicHeader, ThemeProvider) | word-based | `fifth` |

La DB tenía un **CHECK constraint** (`chk_template_key`) que solo aceptaba: `first, second, thirth (sic), fourth, fifth`. Esto causaba:

1. **Desync**: `clients.template_id = 'template_5'` pero `client_home_settings.template_key = 'first'` (el default del INSERT fallaba silenciosamente al escribir `template_5`)
2. **10 clientes afectados**: template_key mostraba `first` cuando debía ser `fifth`, cargando el header incorrecto
3. **No escalable**: agregar `template_6` requería migración + ALTER TABLE para el CHECK

### Write paths sin validación (antes del fix)

| Archivo | Línea aprox. | Problema |
|---------|-------------|----------|
| `provisioning-worker.service.ts` | L619 | Escribía raw `selected_template_key` sin normalizar |
| `provisioning-worker.service.ts` | L1065 | Escribía `wizard_template_key` raw |
| `outbox-worker.service.ts` | L307 | Escribía `p.template_key` raw del evento |
| `home-settings.service.ts` | L129 | Sin ninguna validación |
| `onboarding.service.ts` | L1866 | Escribía `templateKey` raw |

## Solución aplicada

### 1. DB (Backend Supabase)

- **Eliminado** CHECK constraint `chk_template_key`
- **Migrados** todos los registros de word-based a `template_N`:
  - `first` → `template_1`, `second` → `template_2`, etc.
  - 11 filas con `fifth` → `template_5`, 1 fila con `fourth` → `template_4`
- Sin CHECK constraint: la validación queda 100% en el código (más flexible para nuevos templates)

### 2. Backend — `normalizeTemplateKey()` mejorado

**Archivo:** `src/common/constants/templates.ts`

Ahora mapea word-based → `template_N` automáticamente:

```typescript
const WORD_TO_TEMPLATE = {
  first: 'template_1',
  second: 'template_2',
  third: 'template_3',
  fourth: 'template_4',
  fifth: 'template_5',
};

function normalizeTemplateKey(key) {
  if (!key) return DEFAULT_TEMPLATE_KEY; // 'template_5'
  if (key.startsWith('template_')) return key; // ya canónico
  if (WORD_TO_TEMPLATE[key]) return WORD_TO_TEMPLATE[key]; // legacy → canónico
  return DEFAULT_TEMPLATE_KEY;
}
```

### 3. Backend — Write paths protegidos

Todos los upserts/updates a `client_home_settings.template_key` ahora pasan por `normalizeTemplateKey()`:

- `provisioning-worker.service.ts` (2 upserts)
- `outbox-worker.service.ts` (1 upsert)
- `onboarding.service.ts` (1 update)
- `home-settings.service.ts` (1 upsert + validación `isValidTemplateKey`)
- `admin.service.ts` (ya usaba `normalizeTemplateKey()`, ahora normaliza correctamente)

### 4. Frontend — DynamicHeader compatible con ambos formatos

**Archivo:** `src/components/DynamicHeader.jsx`

`TEMPLATE_HEADER_MAP` ahora acepta ambas convenciones:

```javascript
const TEMPLATE_HEADER_MAP = {
  template_1: HeaderFirst,   template_2: HeaderSecond,
  template_3: HeaderThird,   template_4: HeaderFourth,
  template_5: HeaderFifth,
  // Legacy backward compat
  first: HeaderFirst,  second: HeaderSecond,
  third: HeaderThird,  fourth: HeaderFourth,
  fifth: HeaderFifth,
};
```

`normalizeTemplateKey()` local también acepta ambos formatos.

`ThemeProvider.jsx` ya tenía un `TEMPLATE_KEY_MAP` que convierte `template_N` → word-based para uso interno del sistema de temas — sin cambios necesarios.

## Cómo agregar un nuevo template (template_6, template_7, etc.)

1. **Backend** `templates.ts`: agregar `'template_6'` a `VALID_TEMPLATE_KEYS`
2. **Frontend** `DynamicHeader.jsx`: agregar `template_6: HeaderSixth` a `TEMPLATE_HEADER_MAP`
3. **Frontend** `ThemeProvider.jsx`: agregar `template_6: "sixth"` a `TEMPLATE_KEY_MAP`
4. No requiere migración ni ALTER TABLE

## Archivos modificados

### Backend (templatetwobe)
- `src/common/constants/templates.ts` — `normalizeTemplateKey()` con mapping word→template_N
- `src/worker/provisioning-worker.service.ts` — 2 upserts normalizados
- `src/outbox/outbox-worker.service.ts` — 1 upsert normalizado + import
- `src/home/home-settings.service.ts` — validación + normalización en PUT
- `src/onboarding/onboarding.service.ts` — 1 update normalizado + import

### Frontend (templatetwo)
- `src/components/DynamicHeader.jsx` — TEMPLATE_HEADER_MAP acepta template_N

## Cómo probar

1. Verificar que la DB tiene `template_N` en todos los registros:
   ```sql
   SELECT template_key, count(*) FROM client_home_settings GROUP BY template_key;
   -- Debe mostrar solo template_1..template_5
   ```

2. Abrir una tienda en el storefront y verificar que carga el header correcto según su template

3. Desde admin/onboarding, cambiar template de un cliente y verificar que se persiste como `template_N`

## Notas de seguridad

- Sin CHECK constraint, la validación es código-side. Si se agrega un endpoint nuevo que escriba `template_key`, **debe** usar `normalizeTemplateKey()`.
- El fallback es `template_5` (DEFAULT_TEMPLATE_KEY) — nunca se escribe un valor inválido.

## Commits

| Repo | Commit | Ramas |
|------|--------|-------|
| templatetwobe | `9f7a986` (revert) + `9693f17` (fix) | `feature/automatic-multiclient-onboarding` |
| templatetwo | `cce74e8` | `feature/multitenant-storefront` |
| templatetwo | `e817c02` (cherry-pick) | `develop` |
| templatetwo | `b06696f` (cherry-pick) | `feature/onboarding-preview-stable` |

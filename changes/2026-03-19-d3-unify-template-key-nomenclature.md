# D3 — Unificar nomenclatura template_key cross-BD

**Fecha:** 2026-03-19
**Tipo:** Refactor / Data migration
**Impacto:** API, Web, Backend DB, Admin DB

## Resumen

Unifica el formato de `template_key` en todo el sistema. Antes coexistían dos formatos:
- `template_N` (template_1..template_8) — usado en Backend DB
- Word-based (first..eighth) — usado en Admin DB (`nv_templates`)

**Decisión:** Word-based como formato canónico único.

## Cambios

### Migraciones SQL

| Archivo | BD | Tablas |
|---------|-----|--------|
| `migrations/backend/20260319_d3_normalize_template_keys.sql` | Backend | `clients.template_id`, `client_home_settings.template_key` |
| `migrations/admin/20260319_d3_normalize_onboarding_template_keys.sql` | Admin | `nv_onboarding.selected_template_key`, `nv_onboarding.progress->wizard_template_key` |

### API (1 archivo modificado)

- `src/common/constants/templates.ts`:
  - `DEFAULT_TEMPLATE_KEY` cambia de `'template_5'` a `'fifth'`
  - `normalizeTemplateKey()` ahora retorna word-based (antes retornaba `template_N`)
  - `toLegacyTemplateKey()` marcada como `@deprecated`
  - `isValidTemplateKey()` sigue aceptando ambos formatos

### Web (3 archivos modificados)

- `src/registry/templatesMap.ts`: Keys canónicas ahora word-based, aliases `template_N` para backward compat
- `src/routes/HomeRouter.jsx`: Fallback cambia de `'template_5'` a `'fifth'`
- `src/theme/resolveEffectiveTheme.ts`: Comentarios actualizados, mapping legacy mantenido

## Backward compatibility

- `isValidTemplateKey()` y `normalizeTemplateKey()` siguen aceptando `template_N` como input
- `TEMPLATES` en Web incluye aliases `template_N` → mismo componente
- `resolveEffectiveTheme` sigue convirtiendo `template_N` → word-based

## Orden de ejecución

1. Migración Backend DB
2. Migración Admin DB
3. Deploy API (normalizeTemplateKey invertido)
4. Deploy Web (keys + fallbacks actualizados)

## Verificación

```sql
-- Backend DB
SELECT DISTINCT template_id FROM clients;
SELECT DISTINCT template_key FROM client_home_settings;

-- Admin DB
SELECT DISTINCT selected_template_key FROM nv_onboarding WHERE selected_template_key IS NOT NULL;
```

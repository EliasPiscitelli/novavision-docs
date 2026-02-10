# Cambio: Validación estricta de template_id — nunca "default" en DB

- **Autor:** agente-copilot
- **Fecha:** 2025-07-24
- **Rama:** feature/automatic-multiclient-onboarding

## Archivos modificados

| Archivo | Tipo |
|---------|------|
| `src/common/constants/templates.ts` | **NUEVO** — constante compartida VALID_TEMPLATE_KEYS, normalizeTemplateKey(), isValidTemplateKey() |
| `src/onboarding/dto/submit-wizard-data.dto.ts` | Modificado — agrega @IsIn(VALID_TEMPLATE_KEYS) al campo templateKey |
| `src/onboarding/onboarding.service.ts` | Modificado — valida templateKey en updatePreferences() y saveSession() |
| `src/worker/provisioning-worker.service.ts` | Modificado — normaliza template_id con normalizeTemplateKey() en ambas rutas de escritura |
| `src/admin/admin.service.ts` | Modificado — normaliza template en self-heal del approve |
| `src/home/home-settings.service.ts` | Modificado — reutiliza constante compartida en vez de Set inline |

## Resumen

Se descubrió que el cliente `qa-tienda-ropa` tenía `template_id='default'` en la tabla `clients` del Backend DB. Esto indica que ningún punto de escritura validaba el valor del template antes de persistirlo.

### Problema
- El DTO `SubmitWizardDataDto` solo tenía `@IsOptional() @IsString()` — aceptaba cualquier string incluyendo "default"
- `updatePreferences()` y `saveSession()` escribían el valor recibido sin validación
- `provisioning-worker` usaba `onboarding.selected_template_key || 'template_1'` sin verificar que fuera un key válido
- El self-heal en `admin.service.ts` al aprobar tampoco normalizaba
- Solo `home-settings.service.ts` normalizaba, pero **en lectura** (no prevenía datos inválidos en DB)

### Solución
1. **Constante compartida** (`src/common/constants/templates.ts`): define `VALID_TEMPLATE_KEYS`, `normalizeTemplateKey()` e `isValidTemplateKey()` como fuente única de verdad
2. **DTO con @IsIn**: rechaza valores inválidos en la capa de validación de NestJS
3. **Service-level validation**: `updatePreferences()` y `saveSession()` lanzan `BadRequestException` si el templateKey no es válido
4. **Provisioning normalizado**: las 2 rutas de upsert en `provisioning-worker` ahora pasan por `normalizeTemplateKey()` (si el valor es inválido o null, cae a `template_5`)
5. **Self-heal normalizado**: el approve en `admin.service.ts` normaliza el template al crear `client_home_settings`
6. **Read-time usa constante compartida**: `home-settings.service.ts` reutiliza `VALID_TEMPLATE_KEYS_SET` y `DEFAULT_TEMPLATE_KEY`

### Keys válidos
`template_1`, `template_2`, `template_3`, `template_4`, `template_5`, `first`, `second`, `third`, `fourth`, `fifth`

## Script SQL para fix de datos existentes

```sql
-- Backend DB: Corregir clientes con template_id inválido
UPDATE clients
SET template_id = 'template_5'
WHERE template_id NOT IN (
  'template_1', 'template_2', 'template_3', 'template_4', 'template_5',
  'first', 'second', 'third', 'fourth', 'fifth'
);

-- Backend DB: Corregir client_home_settings con template_key inválido
UPDATE client_home_settings
SET template_key = 'template_5'
WHERE template_key NOT IN (
  'template_1', 'template_2', 'template_3', 'template_4', 'template_5',
  'first', 'second', 'third', 'fourth', 'fifth'
);
```

## Cómo probar

1. `npx tsc --noEmit` → 0 errores
2. `npx eslint src/common/constants/templates.ts src/onboarding/dto/submit-wizard-data.dto.ts` → 0 errores
3. Intentar `PATCH /onboarding/preferences` con `{ "templateKey": "default" }` → debe devolver 400
4. Intentar `POST /onboarding/submit` con `{ "templateKey": "invalid" }` → debe devolver 400
5. Provisioning de nuevo cliente sin template seleccionado → debe usar `template_5` (no "default")

## Notas de seguridad

- No hay impacto en seguridad multi-tenant; solo se agregan validaciones de valor
- El fix SQL debe ejecutarse manualmente contra el Backend DB tras validación del TL

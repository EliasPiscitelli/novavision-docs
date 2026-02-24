# Cambio: T6-T8 template keys en backend + limpieza legacy keys + fix toast stacking

- **Autor:** agente-copilot
- **Fecha:** 2026-02-20
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` (`1d8a04f`)
  - Admin: `develop` (`578f401`)
  - Web: `develop` (`7782c1c`) → cherry-pick a `feature/multitenant-storefront` (`c305477`) y `feature/onboarding-preview-stable` (`73446e7`)

---

## Archivos modificados

### API (templatetwobe)
- `src/common/constants/templates.ts`
- `src/home/home-settings.service.ts`
- `packages/nv-theme/src/types.ts`
- `packages/nv-theme/src/index.ts`

### Admin (novavision)
- `src/context/ToastProvider.jsx`
- `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`

### Web (templatetwo)
- `src/registry/templatesMap.ts`
- `src/routes/HomeRouter.jsx`
- `src/components/DynamicHeader.jsx`
- `src/theme/resolveEffectiveTheme.ts`
- `src/theme/types.ts`
- `src/theme/index.ts`

---

## Resumen de cambios

### 1. Backend no reconocía templates 6/7/8 (CAUSA RAÍZ)

`VALID_TEMPLATE_KEYS` en `src/common/constants/templates.ts` solo contenía `template_1..template_5` y sus aliases `first..fifth`. Cuando un cliente seleccionaba T6/T7/T8 en el wizard, el backend normalizaba a `template_5` (fallback), causando que la tienda siempre renderizara el template 5.

**Fix:** Se agregaron `template_6`, `template_7`, `template_8`, `sixth`, `seventh`, `eighth` a:
- `VALID_TEMPLATE_KEYS` (array + Set)
- `WORD_TO_TEMPLATE` (mapping word → canonical)
- `TemplateKey` type en `nv-theme/types.ts`
- `TEMPLATES` dict en `nv-theme/index.ts`

Esto hace que `normalizeTemplateKey()` e `isValidTemplateKey()` reconozcan correctamente los 8 templates.

### 2. Toast stacking al cambiar templates rápidamente

`ToastProvider` acumulaba toasts indefinidamente sin límite ni dedup. Al hacer clicks rápidos en Step4, se apilaban notificaciones "Preset X seleccionado" + "Requiere Growth plan".

**Fix en ToastProvider:**
- Nuevo prop `key`: si un toast tiene `key`, reemplaza al toast anterior con la misma key (evita duplicados).
- Máximo 3 toasts simultáneos (`MAX_TOASTS = 3`); los más viejos se eliminan.
- Duración reducida de 8000ms → 4000ms.
- Cleanup de timers con `timerMap` ref.
- Expone `removeToast` en el context.

**Fix en Step4TemplateSelector:**
- Toast de selección usa `key: 'template-select'` → se reemplaza al seleccionar otro template.
- Toast de plan requerido usa `key: 'template-plan'` → se reemplaza si se clickea otro template que también requiere plan.

### 3. Eliminación de legacy keys (word-based)

Se eliminaron los mapeos legacy (`first`, `second`, ..., `eighth`) de:
- `templatesMap.ts` — solo quedan keys canónicas `template_N`
- `DynamicHeader.jsx` — `TEMPLATE_HEADER_MAP` solo con `template_N`, `normalizeTemplateKey()` solo valida `template_N`
- `resolveEffectiveTheme.ts` — eliminadas identity mappings redundantes (`first: 'first'`, etc.), solo queda el mapeo `template_N → word` necesario para el theme system

### 4. Theme types actualizados

`TemplateKey` en `src/theme/types.ts` (web) y `packages/nv-theme/src/types.ts` (API) ahora incluyen `"sixth" | "seventh" | "eighth"`.

`TEMPLATES` en `src/theme/index.ts` (web) ahora tiene entradas para `sixth`, `seventh`, `eighth` apuntando a `normalTemplate` (las paletas se aplican dinámicamente).

---

## Por qué

- Los templates 6/7/8 (Drift, Vanguard, Lumina) estaban registrados en el frontend (componentes, PRESET_CONFIGS, sectionComponents, sectionCatalog) pero el backend los rechazaba/normalizaba. Sin esta corrección, ninguna tienda podía usar T6-T8 en producción.
- El toast stacking degradaba la UX del wizard: al probar varios templates rápidamente, se acumulaban 10+ notificaciones.
- Los legacy keys generaban confusión y mantenimiento innecesario. La fuente de verdad es `template_N` (DB).

---

## Cómo probar

### Backend (T6-T8 reconocidos)
```bash
cd apps/api && npm run typecheck && npm run build
# Verificar que normalizeTemplateKey('sixth') retorna 'template_6'
# Verificar que isValidTemplateKey('template_6') retorna true
```

### Admin (toast anti-stacking)
```bash
cd apps/admin && npm run lint && npm run typecheck
# En el wizard Step4: clickear rápidamente 3+ templates → no deben apilarse más de 3 toasts
# Clickear un template Growth → toast success + toast info, NO se apilan al clickear otro
```

### Web (legacy keys removidas)
```bash
cd apps/web && npm run lint && npm run typecheck && npm run build
# Verificar que HomeRouter usa 'template_5' como fallback (no 'fifth')
# Verificar que DynamicHeader.jsx solo tiene template_N en el mapa
# Verificar que TEMPLATES en templatesMap.ts solo tiene template_N keys
```

---

## Riesgos

- **Tiendas existentes con `templateKey: 'fifth'` en DB:** El backend normaliza word → canonical en write paths, pero si hay datos legacy en `client_home_settings.template_key` con valor `fifth`, la web ya no resuelve por word key en `templatesMap`. Sin embargo, `resolveEffectiveTheme` sigue mapeando `template_N → word` para el theme system, y el `HomeRouter` recibe el key del backend que siempre normaliza a `template_N`.
- **`DynamicHeader` fallback:** Si un `templateKey` llega como word-based desde algún path no normalizado, el `normalizeTemplateKey` local ahora retorna `template_5` en lugar de intentar mapear. Esto es correcto porque el backend siempre envía canonical.

## Notas de seguridad

No aplica. Cambios puramente de UI/config, sin impacto en autenticación, RLS ni multi-tenant.

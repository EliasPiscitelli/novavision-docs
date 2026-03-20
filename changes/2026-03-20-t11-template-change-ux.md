# T11 — Template change UX improvements

**Fecha:** 2026-03-20
**Tickets:** T11.1, T11.2, T11.3
**Repos:** Web (`2a53f16`), API (`4c009a5`)
**Ramas:** develop (Web) + cherry-pick a `feature/multitenant-storefront` (`dabae93`) y `feature/onboarding-preview-stable` (`e1e857b`). API en `feature/automatic-multiclient-onboarding`.

## Cambios

### T11.1 — Grandfathering tooltip on plan downgrade
- **DesignStudio.jsx**: Template actual muestra badge "ACTUAL" y warning amber cuando está locked por downgrade de plan
- Permite re-seleccionar el template actual (es el guardado) pero bloquea cambio a otros templates del mismo tier
- Usa `isGrandfathered = locked && t.key === currentTemplate` para distinguir

### T11.2 — Draft stale detection
- **DesignStudio.jsx**: Draft localStorage cambia de array plano a `{ sections, savedAt }` con backward compat
- Al hidratar, compara `savedAt` vs `settings?.updated_at`
- Si el draft es más viejo, muestra warning toast con acción "Descartar borrador"

### T11.3 — CSS overrides warning on template change
- **API**: Nuevo método `suspendOverride(clientId, overrideId)` en `design-overrides.service.ts`
- **API**: Nuevo endpoint `PATCH /design-overrides/:id/suspend` en controller
- **Web**: `addons.js` — nuevo método `suspendDesignOverride(overrideId)`
- **Web**: `DesignStudio.jsx` — carga overrides activos al montar, muestra modal de warning con 3 opciones:
  - **Cancelar**: no guarda
  - **Mantener overrides**: guarda template sin tocar overrides
  - **Suspender overrides**: suspende cada override vía API, luego guarda

## Validación
- API: TypeScript OK, Build OK, 7-check pre-push pipeline passed
- Web: TypeScript OK, Build OK (6.26-6.41s), Tests 333/341 (8 pre-existentes por mock faltante de `getAllPalettes` de D6)
- Cherry-pick limpio a ambas ramas prod, sin archivos dev-only

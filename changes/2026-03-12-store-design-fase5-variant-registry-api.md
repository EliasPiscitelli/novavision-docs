# Fase 5: Paridad real con Step 4 — VARIANT_REGISTRY en API

- **Autor:** agente-copilot
- **Fecha:** 2026-03-12
- **Rama API:** feature/automatic-multiclient-onboarding
- **Plan:** PLAN_STORE_DESIGN_STEP4_SELF_SERVE_EDITOR.md — Fase 5

## Archivos modificados (API)

| Archivo | Cambio |
|---------|--------|
| `src/home/registry/sections.ts` | Nuevo `VARIANT_REGISTRY` (68 variantes), interface `VariantDef`, helpers `getVariantsForType()` y `getVariantDef()` |
| `src/home/home-sections.service.ts` | Validación de `component_key` en `addSection()` y `replaceSection()`: existencia, type match, plan gating |
| `src/home/home.controller.ts` | `GET sections/registry` ahora incluye `variants[]` por tipo; metadata de créditos enriquecida con `component_key` |

## Resumen

Se implementó la capa de validación de variantes concretas (`componentKey`) en el backend, cerrando la brecha entre el REGISTRY API (keyed por `type` genérico) y el catálogo frontend (keyed por `componentKey` específico).

### Qué se hizo

1. **VARIANT_REGISTRY** — mapa de 68 variantes concretas (e.g., `hero.first`, `header.fourth`, `catalog.grid.fifth`), cada una con:
   - `type`: el tipo genérico del REGISTRY al que pertenece
   - `displayName`: nombre para UI
   - `planMin`: plan mínimo requerido para esa variante específica

2. **Validación server-side** en `addSection()` y `replaceSection()`:
   - Si se envía `component_key`, se valida que exista en el VARIANT_REGISTRY
   - Se verifica que el `type` del variant coincida con el `type` de la sección
   - Se gatean variantes por plan (una variante puede requerir `growth` aunque el tipo base sea `starter`)

3. **Endpoint `GET sections/registry` enriquecido** — ahora retorna un array `variants` por cada tipo, con `{ key, displayName, planMin }` para que el frontend pueda renderizar opciones de variante sin hardcodear.

4. **Metadata de créditos** — `addSection` y `replaceSection` ahora incluyen `component_key` en el metadata de consumo de créditos para trazabilidad.

### Compatibilidad retro

- Si `component_key` no se envía, el flujo funciona exactamente igual que antes (solo valida `type`)
- El VARIANT_REGISTRY es adicional al REGISTRY existente, no lo reemplaza
- La migración `BACKEND_051` (columna `component_key` en `home_sections`) ya existía de una fase anterior

## Validación

```
lint:      0 errores (798 warnings preexistentes)
typecheck: 0 errores
build:     ✅ exitoso
tests:     10/10 pasaron (3 suites: home.controller, home.service, home-settings.service)
```

## Riesgos

- La migración `BACKEND_051` debe estar deployada en Supabase antes de que los requests con `component_key` funcionen en producción
- El mapeo variant → type se hardcodea en el API; si se agregan variantes en el frontend sin actualizar el API, la validación las rechazará (comportamiento deseado — fuerza sincronización)

## Cómo probar

1. Levantar API: `npm run start:dev`
2. `GET /home/sections/registry` → verificar que cada tipo incluye `variants[]`
3. `POST /home/sections` con `{ type: "hero", component_key: "hero.fourth" }` en plan `starter` → debe dar 403 `VARIANT_GATED`
4. `POST /home/sections` con `{ type: "hero", component_key: "hero.first" }` en plan `starter` → debe funcionar
5. `POST /home/sections` con `{ type: "hero", component_key: "footer.first" }` → debe dar 400 `COMPONENT_KEY_TYPE_MISMATCH`

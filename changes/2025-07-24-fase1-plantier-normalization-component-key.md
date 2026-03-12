# Fase 1: Normalización planTier + component_key

- **Autor:** agente-copilot
- **Fecha:** 2025-07-24
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding
- **Plan:** PLAN_STORE_DESIGN_PARITY_AND_UNIFICATION.md § Fase 1

## Archivos modificados

### Admin
- `src/registry/sectionCatalog.ts` — Interfaz `SectionMetadata.planTier` cambiada de `"starter"|"growth"|"pro"` a `"starter"|"growth"|"enterprise"`. 32 valores `"pro"` → `"enterprise"`.

### API
- `src/home/dto/section.dto.ts` — Campo opcional `component_key` agregado a `AddSectionDto` y `ReplaceSectionDto`.
- `src/home/home-sections.service.ts` — Interfaz `Section` extendida con `component_key: string | null`. Métodos `addSection` y `replaceSection` ahora persisten `component_key`.
- `migrations/backend/BACKEND_051_home_sections_component_key.sql` — Migración para agregar columna `component_key TEXT` a `home_sections` con índice.

## Resumen

**Problema:** El catálogo admin usaba `"pro"` como planTier mientras que el web y la API usan `"enterprise"`. La tabla `home_sections` no persistía la variante específica de sección (e.g. `hero.fifth`), solo el tipo genérico (`hero`).

**Solución:**
1. Normalización: todas las 32 entradas "pro" del admin ahora usan "enterprise", alineando admin ↔ web ↔ API.
2. Extensión: nuevo campo `component_key` (TEXT, nullable) en home_sections para trackear la variante exacta de sección. Los DTOs de add/replace aceptan el campo opcionalmente.

## Por qué

- Eliminar la discrepancia de nomenclatura que forzaba el uso de `normalizePlanKey()` como workaround runtime.
- Habilitar la persistencia de la variante específica de sección para que el editor "Diseño de Tienda" pueda reconstruir correctamente qué componente visual corresponde a cada sección guardada.

## Cómo probar

```bash
# API
cd apps/api && npm run lint && npm run typecheck && npm run build

# Admin
cd apps/admin && npm run lint && npm run typecheck

# Verificar que no queden "pro" en admin
grep -r 'planTier: "pro"' apps/admin/src/ # debe dar 0 resultados

# Ejecutar migración (requiere acceso a DB)
# psql $DATABASE_URL -f migrations/backend/BACKEND_051_home_sections_component_key.sql
```

## Notas de seguridad

- `component_key` es un campo de texto libre pero validado por Zod como `z.string().optional()`. No se usa en queries dinámicas — solo se persiste y retorna.
- La migración usa `IF NOT EXISTS` para idempotencia.

## Riesgos

- **Bajo:** La migración agrega una columna nullable — no rompe datos existentes ni queries actuales.
- **Pendiente:** Ejecutar la migración en la DB de staging/producción antes del deploy.

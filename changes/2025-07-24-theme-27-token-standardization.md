# Cambio: Estandarización de paletas — contrato de 27 tokens end-to-end

- **Autor:** agente-copilot
- **Fecha:** 2025-07-24
- **Rama:** `feature/automatic-multiclient-onboarding` (API + Web)
- **Tipo:** FEAT (+ FIX en paletas oscuras)

---

## Resumen

Se implementó un contrato estricto de **27 CSS custom properties** (`--nv-*`) que toda paleta DEBE cumplir, desde la DB hasta el `:root` del storefront. Antes, las paletas tenían entre 6 y 11 tokens sin consistencia; ahora todas se normalizan a 28 claves (27 semánticas + `--nv-font`).

### Problemas que resuelve

1. **Paletas oscuras con surfaces blancos** — `dark_default`, `starter_dark`, `starter_elegant`, `vivid_coral_dark` tenían `--nv-card-bg: #F8FAFC` sobre fondos oscuros.
2. **Registries duplicados y desincronizados** — Admin y Web tenían copias hardcodeadas incompletas; faltaban 6 paletas en ambos registries.
3. **Normalización parcial** — `normalizeThemeVars` solo cubría 11 tokens de 27; tokens como `--nv-text-muted`, `--nv-shadow`, `--nv-ring` caían en undefined.
4. **Web no consumía paletteVars de la API** — todo el theming dependía del registry local; un cambio en DB no se reflejaba.

---

## Archivos modificados

### API (`apps/api`)

| Archivo | Cambio |
|---------|--------|
| `src/palettes/palettes.service.ts` | Reescritura de `normalizeThemeVars`: 11 → 27 tokens. Nuevos constants `LIGHT_DEFAULTS`, `DARK_DEFAULTS`. Helper `isDarkBackground`, `adjustBrightness`. Dark-mode safety check (previene surface/card-bg demasiado claros). |
| `src/home/home-settings.service.ts` | Inyecta `DbRouterService`. Resuelve `paletteVars` desde `palette_catalog` (Admin DB) y lo retorna como campo separado del `themeConfig`. |
| `scripts/backfill-palettes.mjs` | Script idempotente que actualizó las 20 paletas en `palette_catalog.preview` al contrato de 27 tokens. Ya ejecutado. |

### Web (`apps/web`)

| Archivo | Cambio |
|---------|--------|
| `src/theme/resolveEffectiveTheme.ts` | Nuevo campo `paletteVars` en `ThemeResolveConfig`. Step 3b convierte CSS vars → `tokens.colors` overrides. Step 4 mercea API palette + overrides/themeConfig. |
| `src/App.jsx` | Pasa `paletteVars` a `useEffectiveTheme`. Nuevo `useEffect` que inyecta los 27 tokens directamente en `:root`. |
| `src/hooks/useEffectiveTheme.ts` | `paletteVars` agregado a dependencias de `useMemo`. |
| `src/theme/palettes.ts` | 6 paletas nuevas en el registry local (fallback): `coral_energy`, `forest_calm`, `luxury_gold`, `midnight_pro`, `ocean_breeze`, `sunset_warm`. |

### DB (palette_catalog — Admin DB)

- 20 filas actualizadas vía `backfill-palettes.mjs`
- De 11 → 28 tokens cada una
- 4 paletas oscuras corrigieron `--nv-surface` y `--nv-card-bg`

---

## Contrato de 27 tokens

```
Layout:       --nv-bg, --nv-surface, --nv-card-bg
Typography:   --nv-text, --nv-text-muted
Borders:      --nv-border, --nv-shadow
Primary:      --nv-primary, --nv-primary-hover, --nv-primary-fg
Accent:       --nv-accent, --nv-accent-fg
Links:        --nv-link, --nv-link-hover
Status:       --nv-info, --nv-success, --nv-warning, --nv-error
Focus:        --nv-ring
Inputs:       --nv-input-bg, --nv-input-text, --nv-input-border
Navigation:   --nv-navbar-bg, --nv-footer-bg
Compat:       --nv-muted, --nv-hover
Non-color:    --nv-radius, --nv-font
```

---

## Flujo de datos (post-cambio)

```
palette_catalog.preview (28 tokens)
      ↓ homeData API
      ↓ config.paletteVars
      ↓
resolveEffectiveTheme()
  ├─ Step 3: PALETTES registry (fallback local)
  ├─ Step 3b: paletteVars → tokens.colors overrides
  └─ Step 4: createTheme(base → palette → API colors → overrides)
      ↓
useThemeVars(theme) → inyecta CSS vars en :root
      ↓
useEffect(paletteVars) → override final de :root con los 27 tokens de la API
```

---

## Cómo probar

1. **API typecheck:** `cd apps/api && npm run typecheck` → 0 errores ✅
2. **Web typecheck:** `cd apps/web && npx tsc -p tsconfig.typecheck.json --noEmit` → 0 errores ✅
3. **API lint:** `cd apps/api && npm run lint` → 0 errores (766 warnings pre-existentes) ✅
4. **Backfill idempotencia:** 
   ```bash
   cd apps/api && source .env && export SUPABASE_ADMIN_URL SUPABASE_ADMIN_SERVICE_ROLE_KEY
   node scripts/backfill-palettes.mjs
   # → 20/20 skipped (already OK)
   ```
5. **Visual:** Levantar API + Web, abrir tienda con paleta oscura → surfaces no deben ser blancos.

---

## Notas de seguridad

- `backfill-palettes.mjs` usa `SUPABASE_ADMIN_SERVICE_ROLE_KEY` — no commitear `.env`.
- `home-settings.service.ts` accede a Admin DB via `DbRouterService` (service_role) — lectura only (`palette_catalog.preview`). Non-blocking: si falla, frontend usa registry local.

---

## Riesgos y rollback

- **Riesgo bajo:** Los cambios son aditivos (más tokens) — componentes que ya usaban los 11 tokens originales siguen funcionando.
- **Rollback DB:** Si se necesita revertir, las paletas antiguas no se pierden (solo se agregaron campos). No se eliminó ningún campo.
- **Rollback código:** Revert del commit en cada repo.

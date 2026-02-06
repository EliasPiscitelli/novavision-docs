# Cambio: Reparación completa del sistema de preview + sincronización de ramas ambiente

- **Autor**: agente-copilot
- **Fecha**: 2026-02-06
- **Ramas afectadas**: `fix/preview-restore`, `feature/onboarding-preview-stable`, `feature/automatic-multiclient-onboarding`
- **Repo**: templatetwo (apps/web)

---

## Resumen

Se reparó el sistema de preview roto y se estableció un workflow limpio de ramas ambiente:

### Parte A — Preview (`feature/onboarding-preview-stable`)

**Problema**: La rama tenía AppRoutes degradado, StoreBootLoader vacío (0 bytes), PreviewProviders era un stub noop, y `src/preview/` no existía.

**Solución**:
1. Creado backup: `backup/onboarding-preview-stable-20260206`
2. Reset de la rama a `develop` (eliminando los 42 archivos divergentes/degradados)
3. Creada rama `fix/preview-restore` desde `develop`
4. Portados y mejorados 5 archivos en `src/preview/`:
   - `PreviewProviders.tsx` — Portado de multiclient, con PreviewNetworkGuard integrado
   - `BuilderDataContext.tsx` — Demo data provider con seed normalization
   - `RenderModeContext.tsx` — Context con hook `useIsPreview()`
   - `previewUtils.js` — Token validation + preview mode detection
   - `PreviewNetworkGuard.tsx` — **NUEVO**: Bloqueo de red (fetch + XMLHttpRequest)
5. Actualizado `PreviewHost/index.tsx`:
   - Importa PreviewProviders real (no stub)
   - Token gate: valida `?token=` contra `VITE_PREVIEW_TOKEN`
   - Sin token → 404
6. Agregada ruta `/preview` en `AppRoutes.jsx`
7. Merge limpio (fast-forward) a la rama ambiente

### Parte B — Multitenant (`feature/automatic-multiclient-onboarding`)

**Problema**: 279 archivos de divergencia con develop, 34 conflictos de merge.

**Solución**:
1. Creado backup: `backup/automatic-multiclient-onboarding-20260206`
2. Análisis de 20 commits únicos → solo 5 eran multiclient-específicos (AuthProvider OAuth handoff)
3. Reset a `develop` + merge `fix/preview-restore`
4. Restaurado `AuthProvider.jsx` (1636 líneas) con:
   - Cross-origin OAuth handoff (HUB_ORIGINS, NV_AUTH_ENVELOPE)
   - Per-tenant token storage (tokenStorageKey)
   - Direct token exchange flow
   - Re-render loop prevention

### Parte C — Documentación

Creado `docs/branch-workflow.md` con:
- Roles de cada rama
- Flujo de propagación develop → ambientes
- Reglas de seguridad del preview
- Checklist de release
- Prohibiciones

---

## Archivos modificados/creados

### Nuevos
- `src/preview/PreviewProviders.tsx` (255 líneas)
- `src/preview/BuilderDataContext.tsx` (182 líneas)
- `src/preview/RenderModeContext.tsx` (34 líneas)
- `src/preview/previewUtils.js` (41 líneas)
- `src/preview/PreviewNetworkGuard.tsx` (131 líneas)
- `docs/branch-workflow.md`

### Modificados
- `src/pages/PreviewHost/index.tsx` — Token gate + import real
- `src/routes/AppRoutes.jsx` — Ruta /preview
- `src/context/AuthProvider.jsx` — OAuth handoff (solo en multiclient)

---

## Medidas de seguridad implementadas

1. **Token Gate**: `/preview` requiere `?token=` válido
2. **Bloqueo de red**: PreviewNetworkGuard bloquea:
   - Todos los métodos no-GET/HEAD
   - URLs con: payments, mercadopago, orders, checkout, cart, preference, webhook, charge, subscribe
3. **Mock Providers**: Auth, Cart, Favorites son mocks sin operaciones reales
4. **Fuente de datos**: Solo demo/mock data, sin API ni DB real

---

## Cómo probar

### Preview
```bash
git checkout feature/onboarding-preview-stable
npm run build  # ✅ OK
# Levantar: npm run dev
# Abrir: http://localhost:5173/preview?token=<VITE_PREVIEW_TOKEN>
# Sin token: http://localhost:5173/preview → 404
```

### Multitenant
```bash
git checkout feature/automatic-multiclient-onboarding
npm run build  # ✅ OK
# Verificar OAuth handoff funciona con admin panel
```

---

## Riesgos y rollback

- **Backups disponibles** si algo falla:
  - `git checkout backup/onboarding-preview-stable-20260206`
  - `git checkout backup/automatic-multiclient-onboarding-20260206`
- **VITE_PREVIEW_TOKEN**: debe configurarse en Netlify del deploy preview
- **AuthProvider multiclient**: si rompe, revertir con `git checkout develop -- src/context/AuthProvider.jsx`

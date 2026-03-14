# Resincronización de `feature/onboarding-preview-stable` con `develop`

- Autor: GitHub Copilot
- Fecha: 2026-03-14
- Repo: templatetwo (`apps/web`)
- Rama objetivo: `feature/onboarding-preview-stable`
- Base estable usada: `develop` en `73a6a89`

## Resumen

Se dejó `feature/onboarding-preview-stable` nuevamente alineada con `develop` para evitar seguir acumulando divergencia en el flujo de preview/store design.

La rama anterior quedó respaldada antes del reseteo y también se preservó un cambio local no commiteado detectado en el worktree de onboarding.

## Backups generados

- Backup remoto de la rama previa: `backup/onboarding-preview-stable-20260314`
- Stash local del worktree onboarding: `backup/onboarding-preview-stable-wip-20260314`
- Patch externo del cambio local detectado:
  `/tmp/novavision-backups/onboarding-preview-stable-wip-20260314-DesignStudio.patch`

## Qué se hizo

1. Se verificó que `develop` estaba más estable y contenía el paquete ya validado de Store Design/preview.
2. Se detectó una modificación local pendiente en `src/components/admin/StoreDesignSection/DesignStudio.jsx` dentro del worktree de onboarding.
3. Se generó backup remoto de la rama previa.
4. Se guardó el WIP local en stash y además en un patch externo.
5. Se reseteó `feature/onboarding-preview-stable` a `origin/develop`.
6. Se ejecutó la validación completa con `bash scripts/pre-push-check.sh` sobre la rama recreada.

## Cómo probar

En el worktree de onboarding o en una nueva copia de la rama:

```bash
git checkout feature/onboarding-preview-stable
bash scripts/pre-push-check.sh
```

Resultado esperado:

- Sin mocks en producción
- Lint sin errores bloqueantes
- TypeScript OK
- Build OK
- Sin imports no usados

## Notas de seguridad

- No se agregaron secretos ni variables nuevas.
- El cambio es de sincronización de ramas; el código publicado proviene del estado ya validado en `develop`.
- El backup remoto y el stash local permiten rollback o rescate puntual del estado previo si hace falta.
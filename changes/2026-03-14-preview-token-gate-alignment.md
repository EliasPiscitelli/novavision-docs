# Alineación del gate de token en PreviewHost

- Autor: GitHub Copilot
- Fecha: 2026-03-14
- Repo: templatetwo (`apps/web`)
- Rama fuente: `feature/multitenant-storefront`

## Resumen

Se corrigió una inconsistencia funcional en `PreviewHost`: el acceso directo a `/preview` ya respetaba la política centralizada de `isValidPreviewToken`, pero el render embebido vía `postMessage` exigía además que existiera `?token=` en la URL.

Eso generaba un comportamiento ambiguo: la pantalla cargaba sin 404 en entornos permisivos, pero el payload del builder quedaba bloqueado como token inválido.

## Qué se cambió

1. Se centralizó el resultado de validación en `hasValidPreviewAccess` dentro de `src/pages/PreviewHost/index.tsx`.
2. El gate de acceso directo y el gate del `postMessage` ahora usan la misma condición.
3. Se agregó cobertura en `src/__tests__/preview-host.test.jsx` para el caso embebido sin token en query cuando la política de preview permite el acceso.

## Cómo probar

En `apps/web`:

```bash
npx vitest run src/__tests__/preview-host.test.jsx --reporter=verbose
node scripts/ensure-no-mocks.mjs
npm run lint
npm run typecheck
```

Smoke manual recomendado:

1. Abrir `/preview` dentro del iframe/builder.
2. Enviar `nv:preview:render` con payload válido.
3. Verificar que el preview renderice sin 404 ni mensaje de token inválido cuando la política centralizada habilita el acceso.

## Notas de seguridad

- No se relajó la validación de origen.
- No se agregaron secretos ni variables nuevas.
- El cambio sólo elimina la discrepancia entre dos decisiones de acceso que antes no estaban alineadas.
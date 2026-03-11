# Cambio: fix de tenant preview token + preview fullscreen en Store Design

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Ramas: feature/automatic-multiclient-onboarding (API), feature/onboarding-preview-stable (web)
- Archivos: apps/api/src/home/home-settings.service.ts, apps/web/src/components/admin/StoreDesignSection/index.jsx, apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx, apps/web/src/components/admin/StoreDesignSection/style.jsx

## Resumen

Se corrigió la generación del preview token del tenant usando el `DbRouterService` para resolver la cuenta admin asociada al `clientId` backend. Además, Store Design ahora muestra el error de token explícitamente, permite reintentar la generación y suma un preview de pantalla completa dentro del panel.

## Qué se cambió

- En API, `generateTenantPreviewToken()` dejó de buscar `nv_accounts` con el cliente backend y ahora resuelve la cuenta admin correcta desde `DbRouterService`.
- En web, el panel Store Design ahora expone:
  - `Reintentar token`
  - `Pantalla completa`
  - `Abrir en pestaña`
- El componente `PreviewFrame` pasó a aceptar ancho configurable y opciones para reutilizarlo en vista embebida o fullscreen.
- Cuando el token no se puede generar, el panel ya no falla silenciosamente: muestra el mensaje recibido del backend.

## Por qué

- El `500` en `POST /settings/home/preview-token` impedía renderizar previews de templates/themes en tenant admin.
- El panel necesitaba una experiencia de preview más útil para validar visualmente templates y combinaciones, alineada con el flujo de onboarding.

## Cómo probar

API:

```bash
cd apps/api
npm run build
```

Web:

```bash
cd apps/web
npm run typecheck
npm run build
```

Prueba manual sugerida:

1. Abrir `Store Design` en tenant admin.
2. Validar que el preview embebido renderiza si el token responde OK.
3. Si el token falla, confirmar que aparece el mensaje de error y el botón `Reintentar token`.
4. Abrir `Pantalla completa` y validar el preview ampliado.
5. Probar `Abrir en pestaña` para cargar `/preview?token=...` directamente.

## Notas de seguridad

No se relajó el token gate del preview. El cambio corrige la fuente del slug/cuenta y mejora el diagnóstico visible cuando el backend no puede emitir el token.
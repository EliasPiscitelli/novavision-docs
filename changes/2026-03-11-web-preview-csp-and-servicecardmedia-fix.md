# Cambio: fix de preview embebido en Store Design y warning de ServiceCardMedia

- Autor: GitHub Copilot
- Fecha: 2026-03-11
- Rama: develop (apps/web)
- Archivos: apps/web/netlify.toml, apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx, apps/web/src/components/shared/ServiceCardMedia.jsx

## Resumen

Se corrigió el bloqueo del preview embebido en Store Design permitiendo iframes same-origin del storefront en la CSP de Netlify. Además, el `PreviewFrame` dejó de intentar enviar `postMessage` antes de que el iframe cargue y `ServiceCardMedia` pasó de `defaultProps` a parámetros por defecto para evitar el warning de React.

## Qué se cambió

- En `apps/web/netlify.toml` se agregó `'self'` y `https://*.novavision.lat` a `frame-src`.
- En `apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx` se esperó a que el iframe esté cargado antes de postear el payload y se agregó tolerancia a errores transitorios de `postMessage`.
- En `apps/web/src/components/shared/ServiceCardMedia.jsx` se reemplazó `defaultProps` por valores por defecto en la firma del componente.

## Por qué

- El preview estaba intentando abrir `https://farma.novavision.lat/preview?...` dentro de un iframe del mismo dominio, pero la CSP vigente no lo permitía.
- Al quedar el iframe bloqueado, el panel mostraba área vacía y además disparaba errores de `postMessage` hacia un frame con origen `null`.
- React advertía sobre el uso de `defaultProps` en un function component que se usa dentro del dashboard y previews de servicios.

## Cómo probar

```bash
cd apps/web
npm run lint
npm run typecheck
npm run build
```

Prueba manual sugerida:

1. Abrir `Diseño de Tienda` en un tenant admin.
2. Confirmar que el preview embebido carga `/preview?token=...` sin errores de CSP.
3. Verificar que se renderiza la configuración default del storefront y los cambios de template/palette.
4. Revisar consola y confirmar que ya no aparece el warning de `ServiceCardMedia.defaultProps`.

## Notas de seguridad

La CSP sigue restringiendo `frame-src` a orígenes controlados. El cambio solo habilita el propio storefront y dominios `*.novavision.lat`, necesarios para el preview interno del producto.
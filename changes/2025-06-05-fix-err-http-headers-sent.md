# Cambio: Fix ERR_HTTP_HEADERS_SENT en endpoints con cache 304

- **Autor:** agente-copilot
- **Fecha:** 2025-06-05
- **Rama:** feature/automatic-multiclient-onboarding
- **Commit:** 2de407c

## Archivos Modificados

- `src/home/home.controller.ts`
- `src/home/home-settings.controller.ts`
- `src/home/settings.controller.ts`
- `src/categories/categories.controller.ts`
- `src/banner/banner.controller.ts`
- `src/products/products.controller.ts`
- `src/orders/orders.controller.ts`
- `src/admin/admin.controller.ts`

## Resumen

Se corrigió el error persistente `ERR_HTTP_HEADERS_SENT: Cannot remove headers after they are sent to the client` que ocurría en múltiples endpoints con implementación de cache 304 (ETag-based).

## Root Cause

El problema estaba en el uso de `@Res({ passthrough: true })` combinado con `res.status(304).end(); return;`:

```typescript
// ANTES (ROTO):
@Get('endpoint')
async handler(@Res({ passthrough: true }) res: Response) {
  if (isNotModified(req, etag)) {
    res.status(304).end();
    return;  // <-- NestJS todavía intenta enviar undefined como respuesta
  }
  return payload;  // <-- NestJS intenta enviar esto después del 304
}
```

Con `passthrough: true`, NestJS permite usar `res` pero también espera que el método retorne un valor para enviar como respuesta. Cuando se llamaba `res.status(304).end()` y luego `return;`, NestJS seguía intentando enviar el valor de retorno (`undefined`), causando el error de doble respuesta.

## Solución

Remover `passthrough: true` y manejar manualmente TODAS las respuestas con `res.json()`:

```typescript
// DESPUÉS (CORRECTO):
@Get('endpoint')
async handler(@Res() res: Response) {
  if (isNotModified(req, etag)) {
    return res.status(304).end();  // return previene cualquier procesamiento adicional
  }
  return res.json(payload);  // manejo manual de la respuesta
}
```

## Endpoints Corregidos

| Controlador | Endpoint | Método |
|-------------|----------|--------|
| HomeController | GET /home/data | getHomeData |
| HomeController | GET /home/navigation | getNavigation |
| HomeSettingsController | GET /settings/home | getSettings |
| SettingsController | GET /settings/identity | getIdentityConfig |
| CategoriesController | GET /categories | getAllCategories |
| CategoriesController | GET /categories/:id | getCategoryById |
| BannerController | GET /banners | getBanners |
| BannerController | GET /banners/all | getAllBanners |
| ProductsController | GET /products | getProducts |
| ProductsController | GET /products/:id | getProductById |
| OrdersController | GET /orders/:id/status-light | getStatusLight |
| AdminController | GET /admin/metrics/top | getTopMetrics |
| AdminController | GET /admin/metrics/:clientId | getClientMetrics |

## Cómo Probar

1. Levantar el API: `npm run start:dev`
2. Hacer request a cualquier endpoint con cache:
   ```bash
   # Primera llamada
   curl -v http://localhost:3000/home/data -H "x-client-id: <uuid>"
   
   # Segunda llamada con ETag del response anterior
   curl -v http://localhost:3000/home/data \
     -H "x-client-id: <uuid>" \
     -H "If-None-Match: <etag-del-response-anterior>"
   ```
3. Verificar que la segunda llamada retorna 304 sin errores en logs

## Notas de Seguridad

- Sin impacto de seguridad
- Los cambios son puramente de corrección de manejo HTTP

## Validación

- ✅ `npm run typecheck` - sin errores
- ✅ `npm run lint` - sin errores nuevos
- ✅ Pusheado a `feature/automatic-multiclient-onboarding`

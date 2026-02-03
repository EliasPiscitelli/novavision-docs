# Cambio: Fix errores en página /enterprise

- **Autor:** agente-copilot
- **Fecha:** 2025-02-01
- **Rama:** feature/automatic-multiclient-onboarding
- **Commits:** 
  - API: `5ab7ce4` - Make /plans/catalog endpoint public
  - Admin: `49e5e47` - Add missing Header import to LeadIntakePage

## Archivos modificados

### API (`apps/api`)
- `src/app.module.ts` - Agregado `/plans/catalog` a la lista de exclusiones de AuthMiddleware

### Admin (`apps/admin`)
- `src/pages/LeadIntakePage/index.jsx` - Agregado import del componente Header

## Resumen

Se corrigieron dos errores en producción en la página `/enterprise`:

### Error 1: GET /plans/catalog 401 (Unauthorized)
**Causa:** El endpoint `/plans/catalog` tiene el decorador `@AllowNoTenant()` pero no estaba en la lista de exclusiones del `AuthMiddleware`, por lo que se rechazaba antes de llegar al controlador.

**Fix:** Se agregó `{ path: '/plans/catalog', method: RequestMethod.GET }` a la lista de exclusiones en `AppModule.configure()`.

### Error 2: ReferenceError: Header is not defined
**Causa:** El componente `LeadIntakePage` usaba `<Header />` en la línea 1629 sin haberlo importado.

**Fix:** Se agregó `import Header from "components/Header";` al inicio del archivo.

## Por qué

Estos errores aparecían en la consola del navegador al acceder a `novavision.lat/enterprise` o a `/onboarding/status` que redirige allí. Impedían la correcta renderización de la página de captación de leads/enterprise.

## Cómo probar

1. Acceder a `novavision.lat/enterprise` 
2. Verificar que:
   - No aparezca error 401 en la consola para `/plans/catalog`
   - No aparezca `ReferenceError: Header is not defined`
   - El header del sitio se muestre correctamente
   - La página cargue con el catálogo de planes

## Notas de seguridad

- El endpoint `/plans/catalog` es **intencionalmente público** - contiene información del catálogo de features disponibles por plan, sin datos sensibles.
- El decorador `@AllowNoTenant()` ya estaba presente, solo faltaba la exclusión del middleware.

# T8 — Tenant locale flattening + pt-BR defaults

**Fecha:** 2026-03-19
**Módulo:** Web (Storefront)
**Commits:** `b9b06c0` (develop) → `460b632` (multitenant-storefront) → `98f0fc2` (onboarding-preview-stable)

## Problema

`tenant?.locale` era `undefined` en todos los consumidores (SectionRenderer, etc.) porque el locale real estaba anidado en `tenant.country_context.locale` pero el `TenantProvider` hacía spread del objeto sin promover `locale` al primer nivel. Esto causaba que `mergeLabels()` siempre cayera al fallback es-AR, incluso para tiendas brasileñas.

## Cambios

### TenantProvider.jsx
- Aplanó `locale` de `country_context.locale` al `contextValue` del Provider
- `tenant?.locale` ahora retorna el valor real (`es-AR`, `pt-BR`, etc.)

### localeDefaults.ts
- Agregó bloque completo `PT_BR` con 32 labels en portugués brasileño
- Registró variantes regionales de español: `es-UY`, `es-CL`, `es-CO`, `es-MX`
- Registró `pt` como fallback genérico para portugués

## Impacto

- Tiendas con `locale: 'pt-BR'` ahora muestran la UI en portugués automáticamente
- El cascade de labels funciona correctamente: `section.props.labels` → locale defaults → fallback
- Sin breaking changes — tiendas existentes siguen funcionando con es-AR

## Validación

- TypeScript: 0 errores
- Build: OK (6.55s)
- Tests: 333/341 pass (8 fallos pre-existentes no relacionados)
- Pre-push: 6/6 checks pasados en las 3 ramas

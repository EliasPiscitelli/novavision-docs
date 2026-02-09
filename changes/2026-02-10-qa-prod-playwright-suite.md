# QA-Prod Playwright Suite — Suite de testing productivo

- **Autor:** agente-copilot
- **Fecha:** 2026-02-10
- **Rama:** feature/automatic-multiclient-onboarding
- **Estado:** Creado, pendiente de ejecución cuando slugs dinámicos estén activos

## Archivos creados/modificados

### Nuevos
| Archivo | Propósito |
|---------|-----------|
| `novavision-e2e/helpers/qa-prod-config.ts` | Config central: URLs prod, tenants QA, credenciales MP sandbox, helpers de URL |
| `novavision-e2e/tests/qa-prod/qa-01-onboarding.spec.ts` | Flujo completo de onboarding (13 pasos seriales) |
| `novavision-e2e/tests/qa-prod/qa-02-storefront.spec.ts` | Navegación y catálogo en ambas tiendas (12 tests) |
| `novavision-e2e/tests/qa-prod/qa-03-auth.spec.ts` | Login, logout, registro, aislamiento de sesión (9 tests) |
| `novavision-e2e/tests/qa-prod/qa-04-cart-checkout-mp.spec.ts` | Carrito + Checkout MP sandbox — aprobado/rechazado (15 tests) |
| `novavision-e2e/tests/qa-prod/qa-05-cross-tenant.spec.ts` | Aislamiento multi-tenant API + visual (8 tests) |
| `novavision-e2e/tests/qa-prod/qa-06-admin.spec.ts` | Panel admin: login, lista clientes, detalle (7 tests) |

### Modificados
| Archivo | Cambio |
|---------|--------|
| `novavision-e2e/playwright.config.ts` | Agregado proyecto `qa-prod` con Desktop Chrome, 180s timeout, 1 retry |
| `novavision-e2e/package.json` | 8 scripts nuevos: `test:qa-prod`, `test:qa-prod:headed`, y uno por suite |
| `novavision-e2e/.env.e2e.example` | Variables `QA_PROD_*` documentadas |

## Resumen

Suite de Playwright diseñada para correr contra **tenants productivos reales** (`qa-tienda-ropa`, `qa-tienda-tech`).

### Características clave
- **MP Sandbox real**: Usa test cards + test buyers de Mercado Pago; genera flujos idénticos a producción sin cargos reales
- **Onboarding end-to-end**: Crea un tenant nuevo vía API (builder token), simula pago, aprueba como admin, verifica storefront
- **Cross-tenant isolation**: Valida que productos, categorías y sesiones NO se filtran entre tenants
- **Dynamic slugs ready**: Flag `useDynamicSlugs` en config; cuando sea `true`, genera URLs con subdominio (`slug.base_domain`) en vez de `?tenant=slug`
- **Sin cleanup destructivo**: `SKIP_CLEANUP=1` en todos los scripts; no modifica datos existentes (excepto onboarding que crea un tenant nuevo)

### Cómo ejecutar

```bash
# Suite completa
npm run test:qa-prod

# Suite completa con browser visible (headed)
npm run test:qa-prod:headed

# Suites individuales
npm run test:qa-prod:onboarding
npm run test:qa-prod:storefront
npm run test:qa-prod:auth
npm run test:qa-prod:checkout
npm run test:qa-prod:cross-tenant
npm run test:qa-prod:admin
```

### Cobertura por suite

| Suite | Tests | Flujos |
|-------|-------|--------|
| qa-01 | 13 | Onboarding completo: planes → builder → draft → template → TyC → pago → review → approve → verify |
| qa-02 | 12 | Home, header, catálogo, producto, footer; ambas tiendas + cross-visual |
| qa-03 | 9 | Login, logout, credenciales inválidas, registro, T&C, aislamiento sesión |
| qa-04 | 15 | Carrito CRUD, checkout MP aprobado (ropa+tech), checkout MP rechazado |
| qa-05 | 8 | Aislamiento API (productos, categorías, settings), visual, slug inválido |
| qa-06 | 7 | Admin login, tabla clientes, búsqueda, detalle, estado activo |
| **Total** | **64** | |

### Validación TypeScript
- 0 errores en archivos qa-prod (verificado con `npx tsc --noEmit`)
- 1 error preexistente en `tests/08-checkout/checkout.spec.ts` (no relacionado)

## Por qué

Se necesitaba una suite de testing que pudiera validar los flujos completos de la plataforma NovaVision contra tenants reales en producción, incluyendo:
- El onboarding de nuevos clientes paso a paso
- El flujo de compra completo con Mercado Pago
- El aislamiento multi-tenant
- El panel de administración

Todo sin generar cargos reales (sandbox de MP) y listo para activarse cuando los slugs dinámicos estén configurados.

## Notas de seguridad

- Las credenciales de Supabase (service role keys) están hardcodeadas en `qa-prod-config.ts` — esto es aceptable para un repo E2E privado, pero se recomienda migrar a variables de entorno para CI
- Los test buyers de MP son de sandbox; no generan transacciones reales
- El super admin password está en el config; rotar si se expone

## Riesgos

- Los tests de checkout dependen de la disponibilidad de MP sandbox (puede haber intermitencia)
- El onboarding test crea un tenant nuevo en cada ejecución; considerar cleanup manual periódico
- Si cambian los Page Objects existentes, los tests qa-prod podrían romperse (mantener sincronizados)

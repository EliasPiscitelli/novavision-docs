# Resumen completo: Shipping V2 — Sesiones 2026-02-11

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Estado:** ✅ TODO COMPLETADO

---

## Alcance total de trabajo

### Sesión 1: SocialIcons + Shipping Fases 1-3

#### SocialIcons Fix
- **Problema:** Mismatch de props (`socialLinks` vs `socials`, `whatsApp` vs `whatsapp`), faltaba TikTok y `wspText`
- **Solución:** Rewrite completo de `SocialIcons.jsx`
- **Commits:** `a77212f` (multitenant), `10ffeb6` (develop)

#### Fase 1 — UX Card Collapse
- **Problema:** Cards de shipping deshabilitadas no se podían expandir
- **Solución:** Desvincular collapse de enabled, campos visibles pero disabled cuando OFF
- **Archivos:** `ShippingConfig.jsx`, `configStyle.jsx`

#### Fase 2 FE — Validaciones pre-save
- **Problema:** Se podía guardar config incompleta (arrange sin WhatsApp, zone sin zonas, etc.)
- **Solución:** 4 validaciones nuevas en `saveSettings()` con mensajes claros
- **Archivo:** `ShippingConfig.jsx`

#### Fase 3 — Lazy fetch addresses
- **Problema:** `useAddresses` se llamaba incondicionalmente para todo user logueado
- **Solución:** Condicionar a `deliveryEnabled`, silenciar 400 en hook
- **Archivos:** `CartProvider.jsx`, `useShipping.js`, `useAddresses.js`

**Commit consolidado:** `ab0d5f3` (multitenant), cherry-pick `667f811` (develop)

---

### Sesión 2: Shipping Fase 4 + Bugfixes

#### Fase 2 BE — Server validations
- **Validaciones nuevas en `upsertSettings()`:**
  - `arrange_enabled && !arrange_whatsapp` → 400
  - WhatsApp formato 8-15 dígitos → 400
  - `free_shipping_enabled && !delivery_enabled` → 400
- **Archivo:** `shipping-settings.service.ts`

#### Fase 4 — Super Admin Provider Control

**Base de datos (Admin DB):**
- Migración `ADMIN_059_platform_shipping_providers.sql`
- Tabla: `platform_shipping_providers` (provider, display_name, is_enabled, requires_plan, config)
- Seed: manual (starter), andreani (growth), oca (growth), correo_argentino (growth), custom (growth, disabled)
- RLS: service_role bypass
- **Ejecutada en Admin DB** ✅

**Backend API:**
- Nuevo servicio: `ShippingProviderCatalogService` (~160 líneas)
  - Cache 5 min, graceful fallback a defaults si tabla no existe
  - Métodos: `listProviders()`, `getProvider()`, `isProviderEnabled()`, `updateProvider()`, `getAvailableProviders(planKey)`
  - Jerarquía de planes: starter < growth < pro < enterprise
- Nuevos endpoints admin: `GET /admin/shipping/providers`, `PUT /admin/shipping/providers/:provider`
- Nuevo endpoint tenant: `GET /shipping/integrations/available-providers`
- `createIntegration()` verifica provider habilitado antes de plan gating
- **Módulo actualizado:** `shipping.module.ts`

**Admin Frontend:**
- Nuevo 5to tab "Providers" en `ShippingView.jsx`
- Toggle habilitado/deshabilitado por provider
- Selector de plan mínimo requerido (starter/growth/pro/enterprise)
- Styled components: ToggleTrack, ProviderRow, etc.
- Optimistic UI updates

**Commit API:** `3bb3371` | **Commit Admin:** `a0faaaf`

#### Bugfixes descubiertos durante implementación

| Bug | Root cause | Fix | Commit |
|-----|-----------|-----|--------|
| `Cannot read properties of null (reading 'deliveryEnabled')` | `settings` es null antes del fetch, `.deliveryEnabled` sin optional chaining | `settings?.deliveryEnabled === true` | Web `32d9ac5` |
| 400 en `/addresses` sigue apareciendo | useAddresses seteaba error state incluso en 400 (estado esperado) | No setear error en catch de 400 | Web `0361478` |
| 400 por tabla inexistente | Backend lanzaba BadRequest para cualquier error Supabase | Retornar [] si error es 42P01/does not exist | API `962107b` |
| `let` → `const` lint warning | Variables no reasignadas en mercadopago.service | Cambiar a const | API `7f9f6f2` |

---

## Todos los commits (orden cronológico)

| # | Repo | Hash | Mensaje | Rama |
|---|------|------|---------|------|
| 1 | Web | `a77212f` | fix(web): SocialIcons rewrite | multitenant-storefront |
| 2 | Web | `10ffeb6` | cherry-pick a develop | develop |
| 3 | Web | `ab0d5f3` | feat(web): shipping Fases 1+2+3 | multitenant-storefront |
| 4 | Web | `667f811` | cherry-pick a develop | develop |
| 5 | API | `3bb3371` | feat(api): shipping Fase 4 + validaciones BE | automatic-multiclient-onboarding |
| 6 | Admin | `a0faaaf` | feat(admin): shipping Fase 4 Providers tab | automatic-multiclient-onboarding |
| 7 | API | `7f9f6f2` | fix(api): let→const mercadopago.service | automatic-multiclient-onboarding |
| 8 | Web | `32d9ac5` | fix(web): guard null settings useShipping | multitenant-storefront |
| 9 | Web | `3b550f2` | cherry-pick a develop | develop |
| 10 | API | `962107b` | fix(api): addresses listByUser resiliente | automatic-multiclient-onboarding |
| 11 | Web | `0361478` | fix(web): useAddresses no error state en 400 | multitenant-storefront |
| 12 | Web | `1fcadfe` | cherry-pick a develop | develop |

## Migraciones ejecutadas

| Migración | Base de datos | Estado |
|-----------|---------------|--------|
| `ADMIN_059_platform_shipping_providers.sql` | Admin DB (erbfzlsznqsmwmjugspo) | ✅ Ejecutada |
| `20260211_user_addresses.sql` | Backend DB (ulndkhijxtxvpmbbfrgp) | ✅ Ya existía |

## Archivos creados

| Archivo | Repo |
|---------|------|
| `migrations/admin/ADMIN_059_platform_shipping_providers.sql` | API |
| `src/shipping/shipping-provider-catalog.service.ts` | API |

## Archivos modificados

| Archivo | Repo | Cambio |
|---------|------|--------|
| `src/shipping/shipping.module.ts` | API | + ShippingProviderCatalogService |
| `src/admin/admin-shipping.controller.ts` | API | + GET/PUT providers endpoints |
| `src/shipping/shipping.service.ts` | API | + provider check en createIntegration |
| `src/shipping/shipping.controller.ts` | API | + GET available-providers |
| `src/shipping/shipping-settings.service.ts` | API | + 3 validaciones server |
| `src/addresses/addresses.service.ts` | API | + graceful fallback tabla inexistente |
| `src/tenant-payments/mercadopago.service.ts` | API | let→const |
| `src/components/SocialIcons.jsx` | Web | Rewrite completo |
| `src/components/admin/ShippingPanel/ShippingConfig.jsx` | Web | UX collapse + validaciones |
| `src/components/admin/ShippingPanel/configStyle.jsx` | Web | DisabledHint + FieldGroup $disabled |
| `src/hooks/cart/useShipping.js` | Web | deliveryEnabled export + null guard |
| `src/hooks/cart/useAddresses.js` | Web | 400 silencing mejorado |
| `src/context/CartProvider.jsx` | Web | conditional addresses fetch |
| `src/pages/AdminDashboard/ShippingView.jsx` | Admin | + Providers tab |

## CI validado

| Repo | lint | typecheck | build |
|------|------|-----------|-------|
| API | ✅ 0 errors | ✅ clean | ✅ |
| Admin | ✅ clean | ✅ clean | ✅ |
| Web | ✅ clean | — | — |

## Cherry-pick a onboarding-preview-stable

**No necesario** — la rama no contiene hooks de shipping/checkout.

## Notas de seguridad
- Endpoints admin protegidos por `SuperAdminGuard` (dual: email en super_admins + x-internal-key)
- Provider catalog service usa graceful fallback si migración no aplicada
- Server validations son defensa en profundidad (FE valida primero)
- Todas las queries filtran por `client_id` (multi-tenant aislamiento)

# SUPPORT_TICKETS_AUDIT.md — Fase 0: Auditoría pre-implementación

> **Fecha:** 2026-02-16  
> **Autor:** agente-copilot  
> **Rama API:** feature/automatic-multiclient-onboarding  
> **Objetivo:** Documentar hallazgos y decisiones antes de implementar el sistema de tickets de soporte.

---

## 1. ¿Dónde vive el "plan" hoy?

### Source of truth

| DB | Tabla | Campos clave | Rol |
|---|---|---|---|
| **Admin DB** | `plans` | `plan_key`, `entitlements` (JSONB), `monthly_fee` | Catálogo canónico de planes |
| **Admin DB** | `subscriptions` | `account_id`, `plan_key`, `status` (pending/active/paused/cancelled/grace_period/suspended) | Estado de suscripción por cuenta |
| **Backend DB** | `clients` | `plan_key`, `billing_period`, `entitlement_overrides` (JSONB), `feature_overrides` (JSONB) | Copia operativa para gating rápido |

### Plan keys canónicos

```typescript
// src/common/plans/plan-keys.ts
type PlanKey = 'starter' | 'growth' | 'enterprise';
```

Normalización legacy: `basic → starter`, `professional → growth`, `premium/pro/scale → enterprise`.

### Gating en Backend

| Guard/Servicio | Archivo | Qué valida |
|---|---|---|
| `PlanAccessGuard` | `src/plans/guards/plan-access.guard.ts` | Feature habilitado para el plan (usa `FEATURE_CATALOG`) |
| `PlanLimitsGuard` | `src/plans/guards/plan-limits.guard.ts` | Límites cuantitativos (productos, storage) |
| `SubscriptionGuard` | `src/guards/subscription.guard.ts` | Suscripción activa (`active` o `past_due`) |
| `PlansService` | `src/plans/plans.service.ts` | `getClientPlanKey(clientId)`, `isPlanEligible()` |
| Feature Catalog | `src/plans/featureCatalog.ts` | 681 líneas con features y a qué plan pertenecen |

**Decoradores existentes:** `@PlanFeature('feature.id')`, `@PlanAction('action')`, `@SkipSubscriptionCheck()`.

### Gating en Frontend (Admin)

- **No hay PlanContext ni hook `usePlan()` centralizado.**
- El plan se obtiene ad-hoc por API call (`getSubscriptionManageStatus()`).
- Componentes existentes: `UpsellModal`, `UpgradePrompt`, `PlanBadge`, `SubscriptionExpiredBanner`.
- El feature catalog se carga dinámicamente: `GET /plans/catalog`.

### DECISIÓN: Para tickets, usaremos `@PlanFeature('support.tickets')` en backend + verificación ad-hoc en frontend.

---

## 2. Arquitectura de DBs

```
┌─────────────────────────────────────────────────┐
│  Admin DB (erbfzlsznqsmwmjugspo.supabase.co)   │
│  - nv_accounts, subscriptions, plans            │
│  - super_admins, nv_onboarding                  │
│  - invoices, payments (NovaVision billing)       │
│  - audit_log                                    │
│  → Propósito: control plane NovaVision          │
└─────────────────────────────────────────────────┘
         │ DbRouterService.getAdminClient()
         │
┌─────────────────────────────────────────────────┐
│  Backend DB (ulndkhijxtxvpmbbfrgp.supabase.co)  │
│  - clients, users, products, orders             │
│  - cart_items, categories, payments (tienda)    │
│  - banners, settings, logos                     │
│  → Propósito: multitenant (datos de tiendas)    │
└─────────────────────────────────────────────────┘
         │ DbRouterService.getBackendClient()
```

### ¿Dónde poner tickets?

| Opción | Pros | Contras |
|---|---|---|
| **Admin DB** ✅ | Centralizado, cross-tenant, soporte opera sobre Admin, no toca datos de tienda | Necesita JOIN con datos de client (nombre, plan) que ya están en Admin (`nv_accounts`) |
| Backend DB | Más cerca de los datos de tienda (orders, products) | Soporte tendría que hacer queries cross-tenant, rompe aislamiento, multi-cluster complica |

### DECISIÓN: Tickets en **Admin DB**. 

**Razones:**
1. Soporte es una función del control plane, no de la tienda.
2. `nv_accounts` ya tiene `plan_key`, `name`, etc. — JOIN directo.
3. Backend DB soporta multi-cluster (clientes en distintos clusters), lo que haría queries cross-cluster imposibles para tickets.
4. El Super Admin ya habla con Admin DB para todo lo demás.
5. RLS de Admin DB ya tiene políticas para super admins.

---

## 3. Autenticación y resolución de identidad

### Flujo actual

```
Request → AuthMiddleware
  ├─ Bearer JWT → validar contra multiclient DB y/o admin DB
  ├─ X-Builder-Token → validar firm JWT propio
  └─ Público → bypass
  
  → Resultado: req.user = { id, email, role, resolvedClientId, project: 'multiclient' | 'admin' }
```

### Guards relevantes para tickets

| Guard | Uso para tickets |
|---|---|
| `PlatformAuthGuard` | Validar JWT contra Admin DB (super admins, soporte) |
| `TenantAuthGuard` | Validar JWT contra multiclient DB (admins de tienda) |
| `ClientDashboardGuard` | Acepta builder token O Supabase JWT — útil para admins de tienda post-onboarding |
| `SuperAdminGuard` | Para endpoints solo de soporte NovaVision |
| `PlanAccessGuard` | Para gatear por plan (Growth/Enterprise) |
| `SubscriptionGuard` | Para verificar suscripción activa |
| `RolesGuard` | Para verificar rol del usuario |

### DECISIÓN: Los endpoints de tickets usarán `ClientDashboardGuard` (para admins de tienda) + `PlanAccessGuard` (Growth/Enterprise). Los endpoints de consola de soporte usarán `SuperAdminGuard`.

### Resolución de client_id para tickets

- **Admin de tienda:** `req.user.resolvedClientId` ya viene del middleware + `nv_accounts.id` se puede resolver vía lookup.
- **Super admin:** puede ver todos — no necesita client_id scope (pero sí lo filtra opcionalmente).
- **ASSUMPTION:** El `client_id` en tickets será el `nv_accounts.id` de Admin DB (NO el `clients.id` de Backend DB), ya que los tickets viven en Admin DB.

> **NOTA:** Hay que mapear `nv_accounts.id` (Admin) ↔ `clients.nv_account_id` (Backend) cuando se necesite contexto de tienda (nombre, plan, etc.).

---

## 4. RLS existente

### Admin DB

- Políticas hardcodeadas a UUID específico (`a1b4ca03-...`) para super admin.
- `service_role` bypass en algunas tablas.
- **Riesgo bajo-medio:** Las políticas de Admin DB son más simples que las de Backend DB. Para tickets, crearemos políticas que usen functions helper (`is_super_admin()`, `current_account_id()`).

### Backend DB

- Patrón sólido: `current_client_id()` + `is_admin()` + `is_super_admin()` como funciones helper.
- `server_bypass` policy en todas las tablas.
- **No se toca:** los tickets no viven en Backend DB.

### DECISIÓN: Para RLS en Admin DB, crearemos funciones helper análogas (`is_nv_admin()`, `current_nv_account_id()`) o usaremos `service_role` bypass dado que el backend siempre usa `SUPABASE_ADMIN_SERVICE_ROLE_KEY`.

> **FACT:** El backend usa `service_role` para Admin DB, lo que bypasea RLS. Esto significa que la validación de permisos es responsabilidad del backend (guards), no de RLS. Sin embargo, crearemos RLS igualmente como **defensa en profundidad**.

---

## 5. Riesgos P0 identificados

| # | Riesgo | Severidad | Mitigación |
|---|---|---|---|
| 1 | Backend usa `service_role` para Admin DB → bypasea RLS | Medio | Guards en NestJS son la primera línea. RLS como defensa en profundidad. |
| 2 | `client_id` del frontend no es confiable | Alto | Derivar `account_id` del JWT / sesión, nunca del body/header del cliente. |
| 3 | No hay `PlanContext` en frontend → gating puede ser inconsistente | Bajo | Verificar plan en backend siempre (`@PlanFeature`). Frontend es UX only. |
| 4 | Admin de tienda podría intentar ver tickets de otra tienda | Alto | Filtrar SIEMPRE por `account_id` derivado del JWT. Guards + RLS doble check. |
| 5 | `is_internal` messages deben ser invisibles para clientes | Alto | Filtrar `is_internal = false` en queries de tenant. Never trust frontend. |
| 6 | Attachments/uploads podrían contener malware | Medio | Validar tipo/tamaño en backend. Usar Supabase Storage con paths scoped por tenant. |

---

## 6. Decisiones resumidas

| # | Decisión | Razón |
|---|---|---|
| D1 | Tickets en **Admin DB** | Centralizado, cross-tenant, JOIN directo con `nv_accounts` |
| D2 | Endpoints en **NestJS** (no Edge Functions) | Auth centralizada, guards existentes, patrón consistente |
| D3 | Plan gating con `@PlanFeature('support.tickets')` | Reutiliza infraestructura existente |
| D4 | `account_id` = `nv_accounts.id` (no `clients.id`) | Coherente con Admin DB como host de tickets |
| D5 | RLS + Guards (defensa en profundidad) | Backend usa service_role, pero RLS como safety net |
| D6 | Módulo nuevo: `src/support/` | Separación limpia, sin contaminar módulos existentes |
| D7 | Emails via `email_jobs` queue (Admin DB) | Consistente con el sistema de notificaciones existente |
| D8 | Feature catalog entry: `support.tickets` | Growth: true, Enterprise: true, Starter: false |

---

## 7. ASSUMPTIONS (decisiones tomadas ante ambigüedad)

- **ASSUMPTION A1:** Los "agentes de soporte" son super admins. No creamos un rol `support` separado por ahora. Si se necesita, se agrega un campo `is_support_agent` en `super_admins` o una tabla `support_agents`.
- **ASSUMPTION A2:** El admin de tienda que crea tickets es el usuario autenticado en el Dashboard (vía Supabase Auth). Puede haber múltiples admins por tienda, todos ven los tickets del mismo `account_id`.
- **ASSUMPTION A3:** Los attachments son opcionales y se guardan en Supabase Storage bajo path `support/{account_id}/{ticket_id}/{filename}`.
- **ASSUMPTION A4:** Si un cliente baja de plan (Growth → Starter), sus tickets existentes quedan en **read-only** (puede verlos pero no crear nuevos ni responder).
- **ASSUMPTION A5:** SLA policies son configurables por plan pero con defaults hardcodeados inicialmente.
- **ASSUMPTION A6:** El sistema de tickets solo se expone en el Admin dashboard (no en la Web storefront).

---

*Fin de auditoría. Proceder a Fase 1: Diseño.*

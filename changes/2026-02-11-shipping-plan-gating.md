# Plan Gating para Shipping — Bloque 1

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront (sin cambios en este bloque)

---

## Objetivo

Integrar el sistema de shipping (PRs 1–7 ya mergeados) con el sistema de plan gating existente
(`FEATURE_CATALOG` + `PlanAccessGuard` + `@PlanFeature()`), de forma que:

| Plan       | Shipping manual | Providers API (Andreani, OCA…) |
|------------|:---------------:|:------------------------------:|
| Starter    | ✅              | ❌ (403 FEATURE_GATED)         |
| Growth     | ✅              | ✅                              |
| Enterprise | ✅              | ✅                              |

---

## Archivos a modificar (API)

| # | Archivo | Cambio |
|---|---------|--------|
| 1 | `src/plans/featureCatalog.ts` | Agregar 2 features: `commerce.shipping`, `commerce.shipping_api_providers` |
| 2 | `src/shipping/shipping.module.ts` | Importar `PlansModule` para acceder a `PlanAccessGuard` y `PlansService` |
| 3 | `src/shipping/shipping.controller.ts` | Agregar `PlanAccessGuard` + `@PlanFeature('commerce.shipping')` a nivel de clase |
| 4 | `src/shipping/shipping.service.ts` | En `createIntegration()`, validar que providers no-manual requieren plan growth+ |

---

## Diseño detallado

### 1. Feature Catalog — Nuevos entries

```typescript
// commerce.shipping → Acceso base al módulo (todas las plans)
{
  id: 'commerce.shipping',
  title: 'Gestión de envíos',
  category: 'commerce',
  surfaces: ['client_dashboard', 'api_only'],
  plans: { starter: true, growth: true, enterprise: true },
  status: 'live',
  evidence: [
    { type: 'endpoint', method: 'GET', path: '/shipping/integrations' },
    { type: 'endpoint', method: 'POST', path: '/shipping/integrations' },
    { type: 'endpoint', method: 'GET', path: '/shipping/orders/:orderId' },
  ],
}

// commerce.shipping_api_providers → Solo growth+ para integraciones API
{
  id: 'commerce.shipping_api_providers',
  title: 'Providers de envío con API (Andreani, OCA, etc.)',
  category: 'commerce',
  surfaces: ['client_dashboard', 'api_only'],
  plans: { starter: false, growth: true, enterprise: true },
  status: 'live',
  evidence: [
    { type: 'endpoint', method: 'POST', path: '/shipping/integrations', note: 'provider != manual' },
    { type: 'endpoint', method: 'POST', path: '/shipping/integrations/:id/test' },
  ],
}
```

### 2. ShippingModule — Importar PlansModule

```typescript
imports: [CommonModule, PlansModule],
```

### 3. ShippingController — Guard a nivel de clase

```typescript
@Controller('shipping')
@UseGuards(ClientContextGuard, PlanAccessGuard)
@PlanFeature('commerce.shipping')
export class ShippingController { ... }
```

El `PlanAccessGuard` resuelve el plan del tenant desde DB y valida contra el catálogo.
`commerce.shipping` es `starter: true` → todos pasan. Esto asegura que el módulo
en sí está dentro del sistema de gating (si mañana queremos bloquear un plan, basta
cambiar el booleano).

### 4. ShippingService — Validación de provider en createIntegration

Dentro de `createIntegration()`, ANTES de insertar:

```typescript
// --- Plan gating: providers API solo para growth+ ---
const API_PROVIDERS = new Set(['andreani', 'oca', 'correo_argentino', 'custom']);
if (API_PROVIDERS.has(dto.provider)) {
  const planKey = await this.plansService.getClientPlanKey(clientId);
  const normalized = normalizePlanKey(planKey);
  const feature = FEATURE_CATALOG.find(f => f.id === 'commerce.shipping_api_providers');
  if (feature && !feature.plans[normalized]) {
    throw new ForbiddenException({
      code: 'FEATURE_GATED',
      required_plan: 'growth',
      message: `Integraciones con API de envío requieren plan Growth o superior.`,
    });
  }
}
```

Esto complementa el guard de clase: el guard bloquea acceso total al módulo por plan;
la validación en service filtra por **tipo de provider**.

---

## Beneficios

- **Sin cambios de DB** — no requiere migración ni nuevo JSONB.
- Todo usa infra existente (`FEATURE_CATALOG`, `PlanAccessGuard`, `PlansService`).
- Starter queda limitado a manual (low cost), Growth desbloquea API providers.
- El catálogo se expone vía `GET /plans/catalog` → el frontend puede ajustar UI.

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| Tenants starter existentes con integración Andreani | No aplica: shipping es nuevo, no hay datos legacy |
| Guard falla si PlansModule no importado | Se verifica importación y compilación TS |
| `getClientPlanKey` devuelve 'starter' por defecto si no hay suscripción | Es correcto — sin suscripción = tier mínimo |

## Cómo probar

1. `npx tsc --noEmit` → 0 errores
2. `npm run lint` → OK
3. Levantar API: `npm run start:dev`
4. Crear tenant starter → `POST /shipping/integrations` con `provider: 'manual'` → 201 OK
5. Mismo tenant → `POST /shipping/integrations` con `provider: 'andreani'` → 403 FEATURE_GATED
6. Crear tenant growth → ambos providers → 201 OK

---

## Checklist

- [ ] Features agregados a `FEATURE_CATALOG`
- [ ] `ShippingModule` importa `PlansModule`
- [ ] `ShippingController` tiene `PlanAccessGuard` + `@PlanFeature`
- [ ] `ShippingService.createIntegration` valida providers API vs plan
- [ ] `npx tsc --noEmit` pasa
- [ ] Commit con formato `feat(api): ...`

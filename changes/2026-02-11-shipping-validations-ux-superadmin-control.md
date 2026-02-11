# Shipping: Validaciones, UX Cards y Super Admin Control de Providers

- **Autor:** agente-copilot
- **Fecha:** 2026-02-11
- **Rama Web:** feature/multitenant-storefront
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding

---

## Diagnóstico

| # | Problema | Impacto | Repos |
|---|---------|---------|-------|
| A | Error 400 en `/addresses` — `useAddresses` se llama incondicionalmente para todo user logueado en `CartProvider`, aun sin shipping configurado | Errores en consola, requests innecesarios | Web |
| B | Validaciones pre-save insuficientes — se puede guardar "Coordinar" sin WhatsApp, delivery zone sin zonas, free shipping sin delivery | Config incompleta rompe checkout | Web + API |
| C | Cards deshabilitadas no expandibles — admin no puede ver qué campos necesita sin activar primero | UX confusa, admin no sabe qué configurar | Web |
| D | Super Admin solo tiene visibilidad, no control — no puede habilitar/deshabilitar providers a nivel plataforma | Sin governance central de providers | Admin + API |
| E | Modal de integraciones llama BE sin validar nombre — error "Por favor ingresá un nombre" | UX confusa | Web |

---

## Fase 1 — UX Card Collapse (Problema C) — Solo FE Web

### Objetivo
Permitir expandir cards de métodos deshabilitados para que el admin vea los campos (readonly) antes de activar.

### Cambios
- **ShippingConfig.jsx:** Desvincular collapse de enabled. `onClick` del header siempre togglea sección.
- **ShippingConfig.jsx:** Renderizar FieldGroup cuando esté expandido, no solo cuando enabled.
- **ShippingConfig.jsx:** Inputs con `disabled` prop cuando el método está OFF.
- **configStyle.jsx:** `DisabledFieldOverlay` semi-transparente con mensaje "Activá este método para configurar".

### Archivos
- `apps/web/src/components/admin/ShippingPanel/ShippingConfig.jsx`
- `apps/web/src/components/admin/ShippingPanel/configStyle.jsx`

### Riesgo
Bajo. Solo UI/UX, no toca API.

---

## Fase 2 — Validaciones pre-save (Problemas B + E) — FE Web + API

### Objetivo
No permitir guardar configuración incompleta ni llamar al backend innecesariamente.

### Validaciones nuevas FE (`saveSettings`)

| Condición | Mensaje |
|---|---|
| `arrangeEnabled && !arrangeWhatsapp` | "Ingresá el número de WhatsApp para coordinar" |
| `deliveryEnabled && mode=zone && zones.length === 0` | "Creá al menos una zona de envío" |
| `freeShippingEnabled && !deliveryEnabled` | "Envío gratis requiere Envío a domicilio activo" |
| Formato WhatsApp inválido | "El número de WhatsApp debe tener entre 8 y 15 dígitos" |

### Validaciones nuevas API (PUT `/shipping/settings`)
- `arrange_enabled && !arrange_whatsapp` → 400
- `free_shipping_enabled && !delivery_enabled` → 400

### Validaciones Tab Integraciones
- Botón "Crear" deshabilitado hasta completar nombre

### Archivos
- `apps/web/src/components/admin/ShippingPanel/ShippingConfig.jsx`
- `apps/web/src/components/admin/ShippingPanel/index.jsx`
- `apps/api/src/shipping/shipping-settings.service.ts`

### Riesgo
Medio. Validaciones no retroactivas (solo nuevos saves).

---

## Fase 3 — Lazy fetch `/addresses` (Problema A) — FE Web

### Objetivo
No llamar `GET /addresses` hasta que sea necesario (checkout con delivery habilitado).

### Cambios
- **CartProvider.jsx:** Condicionar `enabled` de `useAddresses` a `shippingHook.deliveryEnabled`.
- **useShipping.js:** Exponer `deliveryEnabled` explícitamente.
- **useAddresses.js:** Error handling más silencioso para 400.

### Archivos
- `apps/web/src/context/CartProvider.jsx`
- `apps/web/src/hooks/cart/useShipping.js`
- `apps/web/src/hooks/cart/useAddresses.js`

### Riesgo
Bajo. Si delivery se activa después, el `useEffect` re-dispara el fetch.

---

## Fase 4 — Super Admin: Control de Providers (Problema D) — Admin + API + DB

### Objetivo
Super admin puede habilitar/deshabilitar qué providers están disponibles para tenants.

### Modelo de datos (nueva tabla)
```sql
CREATE TABLE platform_shipping_providers (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  provider TEXT NOT NULL UNIQUE,
  display_name TEXT NOT NULL,
  is_enabled BOOLEAN NOT NULL DEFAULT true,
  requires_plan TEXT DEFAULT 'growth',
  config JSONB DEFAULT '{}',
  updated_at TIMESTAMPTZ DEFAULT now(),
  updated_by UUID
);
```

### Endpoints nuevos
- `GET /admin/shipping/providers` — Lista providers con estado
- `PUT /admin/shipping/providers/:provider` — Toggle enabled, cambiar plan requerido

### Backend: Modificar flujo existente
- `createIntegration()` → verificar provider habilitado en `platform_shipping_providers`
- `listIntegrations()` → filtrar providers habilitados
- Nuevo: `GET /shipping/integrations/available-providers`

### Frontend Admin
- Nuevo tab "Providers" en `ShippingView.jsx`
- Tabla con toggle por provider + plan requerido

### Riesgo
Alto. Toca DB + BE + Admin. Requiere migración + seed. Feature flag recomendado.

---

## Orden de ejecución

1. Fase 1 (UX inmediato)
2. Fase 2 (validaciones)
3. Fase 3 (elimina error 400)
4. Fase 4 (feature nueva, branch separada)

## Notas de seguridad
- Fase 4 requiere `SuperAdminGuard` en endpoints nuevos
- Validaciones BE son defensa en profundidad (FE valida primero)
- Tabla `platform_shipping_providers` necesita RLS con `server_bypass` + `is_super_admin()`

# Auditoría — Dashboard Detalle de Cliente (NovaVision Admin)

> **Fecha**: 2026-02-07  
> **Autor**: agente-copilot  
> **Rama**: `feature/automatic-multiclient-onboarding`  
> **Componente**: `src/pages/ClientDetails/index.jsx` (Admin)  
> **Referencia plan**: [client-dashboard-plan.md](./client-dashboard-plan.md)

---

## 1. Resumen ejecutivo

Auditoría completa del dashboard de detalle de cliente en la app Admin de NovaVision. Se identificaron **15 hallazgos** clasificados en 7 categorías, todos resueltos en 7 PRs incrementales.

**Estado final**: ✅ Todos los hallazgos resueltos. Lint 0 errores. Código commiteado y pusheado.

---

## 2. Hallazgos identificados

### 2.1 Imports y código muerto (Severidad: Alta)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H1 | `UsageChart`, `AddClientModal`, `CorsOriginsManager`, `ConfirmDialog` usados pero no importados | Crash si Vite no resuelve por tree-shaking |
| H2 | Tooltip de "Pago Anual" decía "Enviar un email de recordatorio..." (copy del de Recordatorio) | UX confusa para el admin |
| H3 | 4 styled components muertos en `style.jsx`: `EditCard`, `EditForm`, `FormRow`, `DangerZone` | Peso innecesario |

**Resolución**: PR1 (`23f2fa2`)

### 2.2 Componente monolítico (Severidad: Media)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H4 | `index.jsx` tenía **~1478 líneas** con toda la lógica inline | Mantenibilidad baja, testing imposible |

**Resolución**: PR2 (`23f2fa2`) — Se extrajeron 4 hooks: `useClientData`, `useClientPayments`, `useCompletionRequirements`, `useClientMetrics`. El componente bajó a ~1018 líneas (lógica solo UI).

### 2.3 Estados de cuenta sin normalizar (Severidad: Media)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H5 | `account_status`, `subscription_status`, `onboarding_state` renderizados como texto plano | No se distinguen estados ok/warning/danger visualmente |
| H6 | Bug BE: `onboarding_state` siempre `null` — query usaba columna `status` pero la tabla `nv_onboarding` tiene columna `state` | Dato crítico invisible |

**Resolución**: PR3 (admin `8d254fc`, api `be7eb57`) — Creados `normalizeAccountHealth.js` (14+13+13+1 mapeos) y `HealthBadge` con 5 colores semánticos. Fix BE en `admin.service.ts`.

### 2.4 Queries directas a Supabase (Severidad: Alta)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H7 | `useClientPayments` importaba `backendSupabase` para leer pagos | Bypass de API, inconsistente con patrón multi-tenant |
| H8 | `useClientMetrics` importaba `supabase` para leer `client_usage_month` e invoices | Mismo problema |
| H9 | `registerPayment` escribía `plan_paid_until` vía Supabase **redundantemente** — el endpoint ya lo hacía server-side | Doble escritura, posible inconsistencia |

**Resolución**: PR4 (admin `655f5ba`, api `268534c`) — 3 nuevos endpoints GET en `admin-client.controller.ts`, 3 métodos en `adminApi.js`. 0 imports de Supabase en ClientDetails hooks.

### 2.5 Layout y duplicación de secciones (Severidad: Baja)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H10 | ~10 botones de acción en fila plana sin agrupación lógica | Difícil encontrar la acción correcta |
| H11 | Sección "Analítica y facturación" duplicaba datos de "Uso mensual" (~60 líneas) | Confusión, datos redundantes |
| H12 | Emoji 🗑️ para borrar en vez de icono consistente (react-icons) | Inconsistencia visual |

**Resolución**: PR5 (`0017b99`) — Acciones en 3 columnas (Operativas/Billing/Diagnóstico), sección duplicada eliminada, `FaTrash` reemplaza emoji.

### 2.6 Loading/empty/error states (Severidad: Media)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H13 | 5 loading con `<p>Cargando...</p>` texto plano, 3 empty states planos, 3 errores inline con `color: '#ff8686'` hardcodeado | UX inconsistente, no hay retry |

**Resolución**: PR6 (`73c99ba`) — Creados 3 componentes reutilizables: `SectionSkeleton` (shimmer animado), `EmptyState` (ícono + mensaje), `ErrorState` (alerta roja + retry).

### 2.7 Delete sin confirmación fuerte (Severidad: Alta)

| # | Hallazgo | Impacto |
|---|----------|---------|
| H14 | `deleteClientEverywhere` usaba `createRoot` imperativo para montar un modal — anti-patrón React | Memory leaks, testing imposible |
| H15 | Borrado con **doble confirmación** redundante (primero `requestConfirm`, luego `ConfirmPreviewDialog` interno) pero sin protección real (no requería tipear nada) | Operación destructiva sin guardia efectiva |

**Resolución**: PR7 (`334fd98`) — `ConfirmDialog` extendido con `typeToConfirm` (input que requiere nombre del cliente). `createRoot` eliminado. Flujo de confirmación único.

---

## 3. Arquitectura resultante

### Estructura de archivos (ClientDetails)

```
src/pages/ClientDetails/
├── index.jsx              # Componente principal (~1022 líneas, solo UI)
├── style.jsx              # Styled Components (limpio, sin muertos)
└── hooks/
    ├── useClientData.js          # Carga client + settings + theme
    ├── useClientPayments.js      # Pagos vía adminApi (sin Supabase)
    ├── useCompletionRequirements.js  # Checklist de onboarding
    └── useClientMetrics.js       # Uso mensual + invoices vía adminApi
```

### Componentes reutilizables creados

```
src/components/
├── HealthBadge/index.jsx        # Badge semántico 5 colores (ok/warn/danger/info/neutral)
├── SectionSkeleton/index.jsx    # Shimmer animado configurable
├── EmptyState/index.jsx         # FaInbox + mensaje + CTA opcional
├── ErrorState/index.jsx         # FaExclamationTriangle + retry
└── ConfirmDialog/               # Extendido con typeToConfirm
    ├── index.jsx
    └── style.jsx
```

### Utilidades creadas/modificadas

```
src/utils/
├── normalizeAccountHealth.js    # 41 mapeos (account_status, subscription, onboarding, catalog)
└── deleteClientEverywhere.jsx   # Simplificado (sin createRoot)

src/services/
└── adminApi.js                  # +3 métodos: getClientPayments, getClientInvoices, getClientUsageMonths
```

---

## 4. Inventario completo de archivos tocados

| Archivo | PRs | Tipo |
|---------|-----|------|
| `admin/src/pages/ClientDetails/index.jsx` | 1-7 | Modificado |
| `admin/src/pages/ClientDetails/style.jsx` | 1, 5 | Modificado |
| `admin/src/pages/ClientDetails/hooks/useClientData.js` | 2 | Creado |
| `admin/src/pages/ClientDetails/hooks/useClientPayments.js` | 2, 4 | Creado → Modificado |
| `admin/src/pages/ClientDetails/hooks/useCompletionRequirements.js` | 2 | Creado |
| `admin/src/pages/ClientDetails/hooks/useClientMetrics.js` | 2, 4 | Creado → Modificado |
| `admin/src/utils/normalizeAccountHealth.js` | 3 | Creado |
| `admin/src/components/HealthBadge/index.jsx` | 3 | Creado |
| `admin/src/components/SectionSkeleton/index.jsx` | 6 | Creado |
| `admin/src/components/EmptyState/index.jsx` | 6 | Creado |
| `admin/src/components/ErrorState/index.jsx` | 6 | Creado |
| `admin/src/components/ConfirmDialog/index.jsx` | 7 | Modificado |
| `admin/src/components/ConfirmDialog/style.jsx` | 7 | Modificado |
| `admin/src/utils/deleteClientEverywhere.jsx` | 7 | Modificado |
| `admin/src/services/adminApi.js` | 4 | Modificado |
| `api/src/admin/admin.service.ts` | 3 | Modificado |
| `api/src/admin/admin-client.controller.ts` | 4 | Modificado |

---

## 5. Commits de referencia

### Admin repo (`feature/automatic-multiclient-onboarding`)

| Hash | PR | Descripción |
|------|----|-------------|
| `23f2fa2` | 1+2 | Fix imports/tooltip/dead code + extract 4 hooks |
| `8d254fc` | 3 | normalizeAccountHealth + HealthBadge + AccountHealthRow |
| `655f5ba` | 4 | Eliminate Supabase direct queries, use adminApi |
| `0017b99` | 5 | Group actions 3 columns, remove duplicate analytics |
| `73c99ba` | 6 | SectionSkeleton, EmptyState, ErrorState |
| `334fd98` | 7 | type-to-confirm delete, remove createRoot |

### API repo (`feature/automatic-multiclient-onboarding`)

| Hash | PR | Descripción |
|------|----|-------------|
| `be7eb57` | 3 | Fix onboarding_state null (column `state` not `status`) |
| `268534c` | 4 | 3 new GET endpoints (payments, invoices, usage-months) |

---

## 6. Métricas

| Métrica | Antes | Después |
|---------|-------|---------|
| Líneas `index.jsx` | ~1478 | ~1022 (−31%) |
| Imports Supabase en ClientDetails | 2 (backendSupabase + supabase) | 0 |
| Hooks custom | 0 | 4 |
| Componentes reutilizables nuevos | 0 | 4 |
| Loading states planos | 5 | 0 (SectionSkeleton) |
| Empty states planos | 3 | 0 (EmptyState) |
| Error states inline | 3 | 0 (ErrorState) |
| Acciones sin agrupar | ~10 flat | 3 columnas semánticas |
| Mapeos de salud normalizados | 0 | 41 |
| Endpoints BE nuevos | 0 | 3 |
| Lint errors | 0 | 0 |


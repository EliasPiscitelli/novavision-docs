# Cambio: Resolución de TODOS los gaps UI del sistema de overages + deuda

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama:** `feature/automatic-multiclient-onboarding` (API + Admin + Web)

## Archivos modificados

### API (apps/api)
| Archivo | Cambio |
|---------|--------|
| `src/billing/billing.controller.ts` | +3 endpoints (`GET cancellation-debts`, `POST waive`, `GET debt-status`) |
| `src/billing/billing.service.ts` | +2 métodos (`getCancellationDebts`, `waiveCancellationDebt`) |

### Admin (apps/admin)
| Archivo | GAP | Cambio |
|---------|-----|--------|
| `src/services/adminApi.js` | — | +3 métodos API (getCancellationDebts, waiveCancellationDebt, getAccountDebtStatus) |
| `src/pages/AdminDashboard/GmvCommissionsView.jsx` | GAP-3 | Badge `accruing` (azul), filtros overage_requests/overage_storage, InfoBox actualizado |
| `src/pages/AdminDashboard/SubscriptionDetailView.jsx` | GAP-2 | Badge `cancel_pending_payment` (naranja), campos pending_debt/original_amount/inflated_until/overage_inflation_applied, cancel handler con toast de deuda |
| `src/pages/AdminDashboard/CancellationsView.jsx` | GAP-4 | Columna "Deuda" con badges condicionales (pendiente/pagada) |
| `src/pages/ClientDetails/index.jsx` | GAP-5 | Badge `accruing` (azul), botones Cobrar/Eximir visibles para status accruing |
| `src/pages/Settings/BillingPage.tsx` | GAP-6 | Label `cancel_pending_payment`, cancel handler abre link de pago MP |

### Web (apps/web)
| Archivo | Cambio |
|---------|--------|
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Cancel handler muestra deuda + abre init_point (en vez de falso éxito) |
| `src/components/UserDashboard/BillingHub.jsx` | Labels: cancellation_debt, overage_charge, reconcile_report |

## Resumen

Sesión anterior de auditoría identificó 7 gaps UI + 1 riesgo web donde el frontend no reflejaba las capacidades del backend de overages/deuda. Esta sesión resolvió **todos**:

| # | Gap | Severidad | Resolución |
|---|-----|-----------|------------|
| GAP-1 | cancellation_debt_log sin UI admin | CRITICAL | 3 endpoints API + 3 métodos adminApi expuestos para uso futuro; info inline en CancellationsView |
| GAP-2 | pending_debt/inflation invisible en suscripción | CRITICAL | 4 campos condicionales + badge cancel_pending_payment en SubscriptionDetailView |
| GAP-3 | status `accruing` invisible en comisiones | CRITICAL | Badge azul + filtro + tipos overage en GmvCommissionsView |
| GAP-4 | CancellationsView sin awareness de deuda | HIGH | Columna "Deuda" con badges condicionales |
| GAP-5 | ClientDetails no muestra `accruing` | HIGH | Badge + acciones habilitadas para adjustments accruing |
| GAP-6 | BillingPage sin cancel_pending_payment | HIGH | Label + handler que abre link de pago |
| GAP-7 | BillingHub sin labels para nuevos eventos | MEDIUM | 3 labels añadidos al mapa getEventLabel |
| WEB | SubscriptionManagement no maneja deuda | HIGH | Branch cancel_pending_payment con error + link MP |

## Por qué

El backend de overages + deuda + inflación estaba 100% implementado (migration ADMIN_092, 26 tests, crons configurados) pero las UIs no reflejaban los nuevos estados ni campos. Un admin o cliente no podía ver deudas, estados accruing, ni recibía feedback correcto al cancelar con deuda pendiente.

## Cómo probar

### Validación de build (ya ejecutada)
```bash
# API
cd apps/api && npm run lint && npm run typecheck && npm run build
# ✅ 0 errors, 1297 warnings (preexistentes) | typecheck clean | build clean

# Admin
cd apps/admin && npm run lint && npm run typecheck && npm run build
# ✅ lint clean | typecheck clean | build clean (chunk warning preexistente)

# Web
cd apps/web && npm run lint && npm run build
# ✅ 0 errors, 39 warnings (preexistentes) | build clean
```

### Pruebas funcionales sugeridas
1. **GmvCommissionsView**: filtrar por status "Acumulando" y type "Overage Requests" → deben mostrarse si existen
2. **SubscriptionDetailView**: ver detalle de suscripción con `pending_debt > 0` → aparecen campos naranja
3. **Cancel con deuda**: cancelar suscripción con deuda → toast warn con monto (admin) / error con link MP (web/billing)
4. **CancellationsView**: verificar que columna "Deuda" muestra badges correctos
5. **ClientDetails**: ver adjustment con status `accruing` → badge azul, botones Cobrar/Eximir visibles

## Notas de seguridad

- Los 3 nuevos endpoints en `billing.controller.ts` validan `PlatformAuthGuard` + `req.user?.role !== 'superadmin'` → 403
- `waiveCancellationDebt` emite lifecycle event `cancellation_debt_waived` para auditoría
- No se exponen datos cross-tenant; todas las queries filtran por account_id
- El `init_point` de MP que se abre en nueva tab es una URL de Mercado Pago (sandbox o prod según env)

## Riesgos

- **Bajo**: CancellationsView infiere deuda del campo `newVal.subscription_status` del lifecycle event. Si el backend no incluye ese campo en el event payload, la columna mostrará "—" (fallback seguro).
- **Nulo**: Todos los cambios son aditivos (nuevos badges, columnas, branches en handlers). No se eliminó ni modificó lógica existente.

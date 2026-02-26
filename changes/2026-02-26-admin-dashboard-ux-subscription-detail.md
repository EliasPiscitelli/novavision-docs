# Cambio: Admin Dashboard UX + Subscription Detail + PaywallPlans fixes

- **Autor:** agente-copilot
- **Fecha:** 2026-02-26
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Commits:**
  - API (`templatetwobe`): `6e6ee72`
  - Admin (`novavision`): `6fef2b8`

---

## Archivos modificados

### API (templatetwobe)

| Archivo | Cambio |
|---------|--------|
| `src/admin/admin.controller.ts` | Nuevo endpoint `GET /admin/accounts/:id/subscription-detail` (SuperAdminGuard) |
| `src/admin/admin.service.ts` | Método `getSubscriptionDetail()` + fix query `getSubscriptionEvents()` (tipos de eventos corregidos) |
| `src/subscriptions/subscriptions.service.ts` | Emisión de lifecycle events `subscription_created` y `subscription_activated` |

### Admin (novavision)

| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/SubscriptionDetailView.jsx` | **NUEVO** — Vista detallada de suscripción (plan, estado, cupón, lifecycle events, billing events) |
| `src/App.jsx` | Ruta `/dashboard/subscription-detail/:id` |
| `src/pages/AdminDashboard/FinanceView.jsx` | Filas de tabla clickeables → navegan a detalle de suscripción |
| `src/pages/AdminDashboard/SubscriptionEventsView.jsx` | `EVENT_TYPE_OPTIONS` actualizado con tipos reales emitidos por el backend |
| `src/services/adminApi.js` | Método `getSubscriptionDetail(accountId)` |
| `src/pages/AdminDashboard/index.jsx` | Categorías del dashboard desplegables (collapse/expand con chevron) |
| `src/pages/AdminDashboard/style.jsx` | `CategoryHeader` con hover effect para feedback visual |
| `src/pages/AdminDashboard/ClientApprovalDetail.jsx` | Eliminado "Catalog source: none" (sin uso), suscripción clickeable → detalle |
| `src/pages/BuilderWizard/components/PaywallPlans.css` | Eliminado sticky del cupón, grid responsivo mejorado (breakpoint tablet), cards con overflow controlado |
| `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | Auto-select Growth al crear/editar paleta custom (`handleSelectionUpdate` con `requiredPlan: 'growth'`) |
| `src/pages/BuilderWizard/steps/Step11Terms.tsx` | Ajuste CSS clase col |
| `src/pages/BuilderWizard/steps/Step7MercadoPago.tsx` | Ajuste CSS clase col |

---

## Resumen de cambios

### 1. Subscription Detail View (API + Admin)
- **Endpoint nuevo:** `GET /admin/accounts/:id/subscription-detail` retorna account, subscription (plan/status/prices/dates/MP link), coupon (code/discount/redemption/promo_ends_at), lifecycle_events (últimos 50), billing_events (últimos 30).
- **Vista frontend:** `SubscriptionDetailView.jsx` con styled-components dark theme, secciones: cabecera cuenta, card suscripción, cupón/descuento, timeline lifecycle events, tabla billing events.
- **Navegación:** Desde `FinanceView` (click en fila) y desde `ClientApprovalDetail` (click en estado de suscripción).

### 2. Fix panel Eventos de Suscripción
- El panel mostraba vacío porque filtraba por tipos de eventos que el backend nunca emitía.
- Corregido `subEventTypes` en `admin.service.ts` con los tipos reales: `subscription_status_change`, `plan_subscription`, `store_paused`, `store_unpaused`, `desync_fixed`, `cross_db_reconcile_report`.
- Frontend `SubscriptionEventsView.jsx` actualizado con mismos tipos en filtro y variantes de color.
- Agregadas emisiones de `subscription_created` y `subscription_activated` en `subscriptions.service.ts`.

### 3. Dashboard categorías desplegables
- Cada categoría (Métricas, Clientes, Facturación, Operaciones, Infra) tiene un chevron ▶/▼ que togglea la visibilidad del grid de items.
- Accesible con teclado (Enter/Space), `aria-expanded`.
- Hover visual en el header de categoría.

### 4. PaywallPlans UX fixes
- **Sticky eliminado:** `.paywall-sticky` cambió de `position: sticky; top: 14px` a `position: relative` para dar más espacio en pantalla.
- **Grid responsivo mejorado:** Breakpoint intermedio tablet (640-1023px) con `repeat(2, 1fr)`, mobile `1fr`, desktop `repeat(3, 1fr)`.
- **Cards sin overflow:** `min-width: 0` + `overflow: hidden` + padding reducido.

### 5. Auto-select Growth para paletas custom
- Al crear o editar una paleta personalizada en Step4, se registra un `WizardSelection` con `requiredPlan: 'growth'`.
- Esto activa automáticamente el notice-card "Tu selección requiere Growth" en PaywallPlans y bloquea Starter.

### 6. Limpieza
- Eliminado campo "Catalog source: none" de `ClientApprovalDetail` (nunca tenía valor, confundía al usuario).
- Eliminada variable `catalogSource` no usada.

---

## Por qué

- El panel de eventos de suscripción estaba vacío por mismatch de tipos — bloqueaba operaciones de monitoreo.
- No existía vista de detalle de suscripción — el super admin no podía ver cupones, billing events ni lifecycle completo.
- Las categorías del dashboard con 11+ items en "Facturación" necesitaban ser colapsables para mejor navegación.
- Las pricing cards en PaywallPlans rompían layout en algunas resoluciones por el sticky + falta de breakpoint tablet.
- Las paletas custom no registraban requirement de Growth, permitiendo selección inconsistente.

---

## Cómo probar

### Subscription Detail
1. Ir a Dashboard → Facturación Hub (FinanceView)
2. Click en cualquier fila de cuenta → debe navegar a `/dashboard/subscription-detail/:id`
3. Verificar que muestra: plan, estado, cupón (si aplica), lifecycle events, billing events
4. Alternativamente: Dashboard → Aprobación de Clientes → detalle → click en estado de suscripción

### Dashboard desplegable
1. Ir al Dashboard principal
2. Click en el header de cualquier categoría (ej: "💰 Facturación y Planes")
3. El grid de items debe colapsar/expandir
4. Probar con teclado (Tab + Enter)

### PaywallPlans
1. Iniciar wizard de onboarding → llegar a Step 6 (planes)
2. Verificar cards lado a lado en desktop, 2 columnas en tablet, 1 en mobile
3. Verificar que la sección de cupón no es sticky (scroll normal)

### Growth auto-select
1. En Step 4, crear una paleta personalizada
2. Avanzar a Step 6 → debe mostrar "Tu selección requiere Growth" y Starter bloqueado

---

## Notas de seguridad

- Endpoint `subscription-detail` protegido con `SuperAdminGuard`
- No se exponen tokens ni claves
- Navegación a detalle usa `account.id` (UUID), no datos sensibles en URL

---

## Riesgos / Rollback

- **Bajo riesgo:** Cambios de UI/UX sin impacto en datos o flujos de pago
- **Rollback:** Revertir commits `6e6ee72` (API) y `6fef2b8` (Admin)

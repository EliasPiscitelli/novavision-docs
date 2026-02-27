# Auditoría: Flujo de Cancelación de Suscripción (end-to-end)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-26
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding
- **Rama Web:** develop

---

## Resumen

Se implementó la cancelación de suscripción desde el panel de super admin (apps/admin + apps/api) y se auditó el flujo existente en el admin de tiendas (apps/web). El flujo end-to-end está completo en las 3 capas.

---

## 1. Cambios implementados (Super Admin)

### Backend (apps/api)

| Archivo | Cambio |
|---------|--------|
| `src/admin/admin.service.ts` | Inyección de `PlatformMercadoPagoService`. Nuevo método `cancelSubscription(reviewerId, reviewerLabel, reason)` que: busca suscripción, cancela preapproval en MP, actualiza DB a `canceled`, pausa tienda, emite lifecycle event. También se agregó auto-cancel en `rejectFinalClient()` (non-blocking try/catch). |
| `src/admin/admin.controller.ts` | Nuevo endpoint `POST /admin/accounts/:id/cancel-subscription` protegido con `SuperAdminGuard`. Body: `{ reason?: string }` |

### Frontend Admin (apps/admin)

| Archivo | Cambio |
|---------|--------|
| `src/services/adminApi.js` | Nuevo método `cancelSubscription(accountId, payload)` |
| `src/pages/AdminDashboard/SubscriptionDetailView.jsx` | Botón "Dar de baja suscripción" (FaBan), modal de confirmación con textarea de motivo, toast de éxito/error. Visible solo si la suscripción no está en estado `canceled`/`cancelled`/`deactivated`. |
| `src/pages/AdminDashboard/ClientApprovalDetail.jsx` | Botón "Dar de baja" en la fila de suscripción, modal inline con motivo. Mismo criterio de visibilidad. |

### Validación

- API: `npm run lint` → 0 errores, `npm run typecheck` → OK, `npm run build` → OK
- Admin: `npm run lint` → 0 errores, `npm run typecheck` → OK, `npm run build` → OK (4.26s)

---

## 2. Auditoría del flujo en Web Storefront (admin de tiendas)

### Resultado: **Flujo completo, no requiere cambios**

El admin de tiendas (`apps/web`) ya tiene implementada la cancelación de suscripción de forma robusta.

### Componentes auditados

| Capa | Archivo | Funcionalidad |
|------|---------|---------------|
| **Frontend** | `apps/web/src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` (1368 líneas) | Botón "Cancelar suscripción" (BtnDanger), modal de 2 pasos, banner de cancelación programada, botón revertir |
| **Service** | `apps/web/src/services/subscriptionManagement.js` | Métodos `cancel()`, `revertCancel()`, `pauseStore()`, `resumeStore()`, `requestUpgrade()`, `validateCoupon()` |
| **API Controller** | `apps/api/src/subscriptions/subscriptions.controller.ts` | Endpoints tenant-facing: `POST client/manage/cancel`, `POST client/manage/revert-cancel` con `ClientDashboardGuard` |
| **API Service** | `apps/api/src/subscriptions/subscriptions.service.ts` | `requestCancel()` (~170 líneas) con idempotencia, advisory lock, cancel MP, schedule vs inmediata, emails |

### Flujo del dueño de tienda (detallado)

```
┌─────────────────────────────────────────────────────────────┐
│ 1. Botón "Cancelar suscripción" (rojo)                      │
│    Visible si: tiene MP preapproval Y no hay cancel pending │
├─────────────────────────────────────────────────────────────┤
│ 2. Modal Paso 1: "¿Por qué querés cancelar?"               │
│    - Select obligatorio (6 motivos predefinidos)            │
│    - Textarea opcional para detalle                         │
│    - Checkbox "Quiero que me contacten"                     │
├─────────────────────────────────────────────────────────────┤
│ 3. Modal Paso 2: "Confirmar cancelación"                    │
│    - Warning rojo con fecha hasta cuándo sigue activa       │
│    - O aviso de cancelación inmediata si no hay período     │
│    - Info: datos se conservan 60 días                       │
├─────────────────────────────────────────────────────────────┤
│ 4. Backend (requestCancel)                                  │
│    - Valida motivo obligatorio                              │
│    - Advisory lock para evitar race conditions              │
│    - Cancela preapproval en MercadoPago (detiene cobros)    │
│    - Si tiene período pago vigente:                         │
│      → status = cancel_scheduled                            │
│      → Tienda sigue activa hasta fin de período             │
│    - Si no tiene período pago:                              │
│      → status = canceled                                    │
│      → Tienda se pausa inmediatamente                       │
│    - Guarda motivo en metadata                              │
│    - Crea billing event + lifecycle event                   │
│    - Emite outbox para sync cross-DB (si inmediata)         │
│    - Persiste resultado en subscription_cancel_log           │
│    - Envía email de confirmación al tenant                  │
│    - Envía notificación al super admin                      │
├─────────────────────────────────────────────────────────────┤
│ 5. Post-cancelación programada (UI)                         │
│    - Banner amarillo "Cancelación programada"               │
│    - Fecha de baja + fecha de retención de datos            │
│    - Botón "Revertir cancelación" (si can_revert = true)    │
├─────────────────────────────────────────────────────────────┤
│ 6. Revertir cancelación (revertCancel)                      │
│    - Solo si status = cancel_scheduled                      │
│    - Solo si no pasó la fecha de baja                       │
│    - Restaura status = active                               │
│    - Reactiva preapproval en MP (si es posible)             │
└─────────────────────────────────────────────────────────────┘
```

### Motivos de cancelación predefinidos

| Valor | Etiqueta |
|-------|----------|
| `too_expensive` | Es muy caro para mi negocio |
| `not_using` | No estoy usando la tienda |
| `missing_features` | Le faltan funcionalidades que necesito |
| `technical_issues` | Tuve problemas técnicos |
| `moving_platform` | Me cambio a otra plataforma |
| `other` | Otro motivo |

---

## 3. Diferencias entre cancel del Super Admin vs Dueño de tienda

| Aspecto | Super Admin (admin.service) | Dueño de tienda (subscriptions.service) |
|---------|----------------------------|----------------------------------------|
| **Tipo de cancel** | Siempre inmediata | Respeta período pago (schedule vs inmediata) |
| **Motivo** | Opcional (texto libre) | Obligatorio (select + texto libre opcional) |
| **Idempotencia** | No (operación admin puntual) | Sí (idempotency_key + subscription_cancel_log) |
| **Advisory lock** | No | Sí (acquireLock/releaseLock) |
| **Emails** | No | Sí (confirmación tenant + notificación super admin) |
| **Revertir** | No disponible | Sí, si fue programada y no pasó la fecha |
| **Checkbox contacto** | No | Sí ("Quiero que me contacten") |
| **Auto-cancel** | Se ejecuta al rechazar tienda | No aplica |

---

## 4. Observaciones menores (no bloqueantes)

### 4.1 Página Maintenance genérica
**Archivo:** `apps/web/src/pages/Maintenance/index.js`

La página de mantenimiento muestra un mensaje genérico "Sistema en mantenimiento" tanto para mantenimiento real como para tienda pausada/cancelada. No diferencia el motivo.

**Mejora sugerida (baja prioridad):** Recibir un parámetro o query param que indique el motivo y mostrar mensajes diferenciados:
- Mantenimiento: "Estamos en mantenimiento, volvé en unos minutos"
- Tienda pausada: "Esta tienda está temporalmente pausada"
- Tienda cancelada: "Esta tienda ya no está disponible"

### 4.2 Sin reactivación post-cancel inmediata
Si la cancelación fue inmediata (sin período pago vigente), `can_revert = false`. El dueño debe contactar a NovaVision para reactivar. Esto es correcto por diseño ya que no queda período pago.

### 4.3 Retención de datos
Se conservan 60 días (`DATA_RETENTION_DAYS = 60`). Esto está hardcodeado en `requestCancel()`. Considerar hacerlo configurable por plan a futuro.

---

## 5. Endpoints involucrados (referencia rápida)

### Super Admin
```
POST /admin/accounts/:id/cancel-subscription
  Headers: Authorization (super admin JWT)
  Body: { reason?: string }
  → admin.service.cancelSubscription()
```

### Dueño de tienda (tenant)
```
POST /subscriptions/client/manage/cancel
  Guards: ClientDashboardGuard
  Body: { reason: string, reason_text?: string, wants_contact?: boolean, idempotency_key?: string }
  → subscriptions.service.requestClientCancel() → requestCancel()

POST /subscriptions/client/manage/revert-cancel
  Guards: ClientDashboardGuard
  → subscriptions.service.revertClientCancel() → revertCancel()

POST /subscriptions/client/manage/pause-store
  Guards: ClientDashboardGuard
  Body: { reason?: string }

POST /subscriptions/client/manage/resume-store
  Guards: ClientDashboardGuard

GET /subscriptions/client/manage/status
  Guards: ClientDashboardGuard

GET /subscriptions/client/manage/plans
  Guards: ClientDashboardGuard
```

---

## 6. Cómo probar

### Cancel desde Super Admin
1. Ir a Admin → Cuentas → Detalle de suscripción
2. Click "Dar de baja suscripción"
3. Ingresar motivo opcional → Confirmar
4. Verificar: suscripción en estado `canceled`, tienda pausada

### Cancel desde Admin de tienda (web storefront)
1. Login como admin de tienda → Sección "Mi Tienda y Suscripción"
2. Click "Cancelar suscripción"
3. Paso 1: Seleccionar motivo (obligatorio) + detalle opcional
4. Paso 2: Confirmar cancelación
5. Si tiene período pago: verificar banner "Cancelación programada" + botón revertir
6. Si no tiene período: verificar cancelación inmediata + tienda pausada

### Revertir cancelación
1. Con cancelación programada activa → botón "Revertir cancelación"
2. Verificar: status vuelve a `active`, banner desaparece

### Auto-cancel en rechazo
1. Admin → Aprobar cuenta → Rechazar
2. Verificar: si tenía suscripción activa, se cancela automáticamente

---

## 7. Archivos clave modificados/auditados

```
MODIFICADOS (pendientes de commit):
  apps/api/src/admin/admin.service.ts
  apps/api/src/admin/admin.controller.ts
  apps/admin/src/services/adminApi.js
  apps/admin/src/pages/AdminDashboard/SubscriptionDetailView.jsx
  apps/admin/src/pages/AdminDashboard/ClientApprovalDetail.jsx

AUDITADOS (sin cambios necesarios):
  apps/web/src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx
  apps/web/src/services/subscriptionManagement.js
  apps/api/src/subscriptions/subscriptions.controller.ts
  apps/api/src/subscriptions/subscriptions.service.ts (requestCancel, revertCancel)
  apps/web/src/pages/Maintenance/index.js
```

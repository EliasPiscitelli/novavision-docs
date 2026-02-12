# Plan: Baja de Suscripción (Tenant Admin) + Observabilidad (Super Admin)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Ramas:** API `feature/automatic-multiclient-onboarding` · Web `feature/multitenant-storefront` · Admin `feature/automatic-multiclient-onboarding`
- **Estado:** Aprobado para implementación

---

## Contexto y regla de negocio principal

> **Si el tenant ya pagó el período actual, la baja se agenda para el final de ese período.**
> Nunca se cancela inmediatamente un período ya cobrado para evitar solicitudes de devolución.

### Flujo resumido

```
Tenant pide cancelar
  └─ ¿Pagó el período actual? (current_period_end > ahora)
       ├─ SÍ → cancel_scheduled con effective_end_at = current_period_end
       │       La tienda sigue activa hasta esa fecha.
       │       "Tu tienda se dará de baja el {fecha}. Tus datos se guardan 60 días más."
       │       Aparece botón "Revertir cancelación" en ambos dashboards.
       │
       └─ NO → cancel_scheduled con effective_end_at = ahora (o período ya venció)
               La tienda se pausa inmediatamente.
               "Tu tienda fue desactivada. Tus datos se guardan 60 días."
               Aparece botón "Reactivar suscripción" (re-onboarding)
```

### Política de retención de datos
- **60 días** después de `effective_end_at` los datos siguen disponibles (readonly).
- Después de 60 días → estado `purged` (cleanup cron existente).
- Comunicar ambas fechas al tenant: fecha de baja + fecha de borrado de datos.

---

## 1) Alcance: FE + BE + Admin

| Capa | Repo | Archivos afectados |
|------|------|--------------------|
| **Backend** | templatetwobe | `subscriptions.controller.ts`, `subscriptions.service.ts` |
| **Frontend Web** | templatetwo | `subscriptionManagement.js`, `SubscriptionManagement.jsx` |
| **Frontend Admin** | novavision | Nuevo `SubscriptionEventsView.jsx`, `App.jsx`, `AdminDashboard/index.jsx` |

---

## 2) Endpoint Backend — `POST /subscriptions/client/manage/cancel`

### Request Body

```json
{
  "reason": "too_expensive | not_using | missing_features | technical_issues | moving_platform | other",
  "reason_text": "string (obligatorio si reason=other)",
  "wants_contact": true,
  "idempotency_key": "uuid"
}
```

> **No hay campo `mode`**: el backend decide automáticamente si el período está pagado o no.
> Si `current_period_end > now` → `cancel_scheduled` (fin de período).
> Si no hay período vigente → cancelación efectiva inmediata.

### Response (snapshot)

```json
{
  "ok": true,
  "status": "cancel_scheduled",
  "effective_end_at": "2026-03-12T00:00:00Z",
  "data_retention_until": "2026-05-11T00:00:00Z",
  "subscription": {
    "id": "uuid",
    "status": "cancel_scheduled",
    "plan_key": "growth",
    "current_period_end": "2026-03-12T00:00:00Z",
    "cancel_at_period_end": true,
    "cancel_requested_at": "2026-02-12T15:30:00Z",
    "cancellation_reason": "too_expensive"
  },
  "store": {
    "is_active": true,
    "checkout_enabled": true
  },
  "can_revert": true
}
```

### Lógica Backend (pseudocódigo)

```
1. Idempotency check (subscription_cancel_log)
2. Advisory lock (acquireLock)
3. Fetch subscription + account
4. Si ya canceled/cancel_scheduled → retornar estado actual
5. Determinar effective_end_at:
   - Si current_period_end > now → effective_end_at = current_period_end
   - Si no → effective_end_at = now (cancelación inmediata)
6. Cancelar en MP:
   - Si hay período pagado: no cancelar MP ahora (se cancela en cron al llegar effective_end_at)
     O alternativamente: cancelar MP con "pending" y dejar que expire.
   - Si no hay período: cancelar MP inmediatamente
7. Actualizar subscriptions:
   - status = 'cancel_scheduled'
   - cancel_at_period_end = true (si hay período)
   - cancel_requested_at = now
   - deactivate_at = effective_end_at
   - cancellation_reason, cancellation_reason_text, cancellation_wants_contact
8. Actualizar nv_accounts.subscription_status = 'cancel_scheduled'
9. Si effective_end_at <= now:
   - Pausar tienda inmediatamente (pauseStoreIfNeeded)
   - Downgrade entitlements
10. Audit: logSubAction + billingService.createEvent + lifecycleEvents.emit
11. Outbox: subscription.cancel_scheduled (para tracking cross-DB)
12. Persist idempotency log
13. Release lock
14. Retornar snapshot
```

### Nuevo endpoint: `POST /subscriptions/client/manage/revert-cancel`

Permite al tenant revertir una cancelación programada **antes** de que llegue `effective_end_at`.

```
1. Verificar status === 'cancel_scheduled'
2. Reactivar en MP (si fue cancelado en MP)
3. Actualizar subscription: status = 'active', cancel_at_period_end = false, deactivate_at = null
4. Actualizar nv_accounts.subscription_status = 'active'
5. Audit log
6. Retornar snapshot actualizado
```

---

## 3) UI Tenant Admin — Flujo del modal

### Estado: Activa (con suscripción recurrente)

Se muestra el botón **"Cancelar suscripción"** en la sección de acciones.

### Modal Paso 1: Información + Motivo

```
┌─────────────────────────────────────────┐
│  ⚠️  Cancelar suscripción               │
│                                         │
│  Tu plan Growth seguirá activo hasta    │
│  el 12 de marzo de 2026.               │
│                                         │
│  Después de esa fecha:                  │
│  • Tu tienda dejará de ser visible      │
│  • No se procesarán nuevos pedidos      │
│  • Tus datos se conservan 60 días       │
│    (hasta el 11 de mayo de 2026)        │
│                                         │
│  ¿Por qué cancelás?                     │
│  ┌─────────────────────────────────┐    │
│  │ Seleccioná un motivo...     ▼   │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ┌─────────────────────────────────┐    │
│  │ Contanos más (opcional)         │    │
│  └─────────────────────────────────┘    │
│                                         │
│  ☐ Quiero que me contacten para         │
│    ayudarme antes de cancelar           │
│                                         │
│           [Siguiente →]  [Volver]       │
└─────────────────────────────────────────┘
```

**Opciones de motivo:**
- "Es muy caro para mi negocio"
- "No estoy usando la plataforma"
- "Me faltan funcionalidades que necesito"
- "Tuve problemas técnicos"
- "Me voy a otra plataforma"
- "Otro" (hace obligatorio el textarea)

### Modal Paso 2: Confirmación fuerte

```
┌─────────────────────────────────────────┐
│  🔴  Confirmar cancelación              │
│                                         │
│  Resumen:                               │
│  • Plan: Growth                         │
│  • Activo hasta: 12/03/2026             │
│  • Datos guardados hasta: 11/05/2026    │
│  • Motivo: "Es muy caro..."            │
│                                         │
│  Para confirmar, escribí CANCELAR:      │
│  ┌─────────────────────────────────┐    │
│  │                                 │    │
│  └─────────────────────────────────┘    │
│                                         │
│    [Confirmar cancelación]  [Volver]    │
│    (botón disabled hasta escribir       │
│     CANCELAR)                           │
└─────────────────────────────────────────┘
```

### Estado: Cancel Scheduled (cancelación programada)

El summary card muestra:

```
Plan Growth · Cancelación programada
Tu tienda seguirá activa hasta el 12/03/2026.
Después de esa fecha, se pausará automáticamente.
Tus datos se conservan hasta el 11/05/2026.

[Revertir cancelación]  (botón primario)
```

El botón "Cancelar suscripción" desaparece. En su lugar aparece "Revertir cancelación".

### Estado: Canceled (ya cancelada, período terminó)

```
Plan Growth · Cancelada el 12/03/2026
Tu tienda está pausada. Tus datos se conservan hasta el 11/05/2026.

[Contactar soporte]  (link a WhatsApp)
```

---

## 4) Panel Super Admin — Observabilidad (solo lectura)

### Nueva vista: `/dashboard/subscription-events`

**Tabla con columnas:**

| Fecha | Tenant (slug) | Evento | Motivo | Detalle | Estado actual | Acciones |
|-------|---------------|--------|--------|---------|--------------|----------|
| 12/02 14:30 | mitienda | cancel_requested | too_expensive | "Muy caro para..." | cancel_scheduled | [Marcar contactado] |
| 10/02 09:15 | otratienda | cancel_reverted | — | — | active | — |

**Filtros:**
- Tenant (slug/nombre)
- Tipo de evento (cancel_requested, cancel_reverted, canceled, reactivated)
- Motivo (enum)
- Rango de fechas
- "Wants contact" (pendientes de contacto)

**Fuente de datos:** tabla `lifecycle_events` filtrada por `event_type LIKE 'subscription_%'`.

**Acción "Marcar contactado":** agrega metadata `{ contacted_at, contacted_by }` al evento (update en lifecycle_events).

---

## 5) Archivos a modificar

### PR2: Backend

| Archivo | Cambio |
|---------|--------|
| `src/subscriptions/subscriptions.controller.ts` | Actualizar body de `POST cancel`, agregar `POST revert-cancel` (builder + client) |
| `src/subscriptions/subscriptions.service.ts` | Refactorizar `requestCancel()` con lógica de período, agregar `revertCancel()`, agregar `syncEntitlementsAfterCancel()` |

### PR1: Frontend Web

| Archivo | Cambio |
|---------|--------|
| `src/services/subscriptionManagement.js` | Actualizar `cancel()` con body completo, agregar `revertCancel()` |
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Modal 2 pasos, estado cancel_scheduled, botón revertir |

### PR3: Frontend Admin

| Archivo | Cambio |
|---------|--------|
| `src/pages/AdminDashboard/SubscriptionEventsView.jsx` | **Nuevo** |
| `src/App.jsx` | Agregar ruta |
| `src/pages/AdminDashboard/index.jsx` | Agregar NAV_ITEM |

---

## 6) Campos de DB utilizados/agregados

### subscriptions (Admin DB) — campos existentes reutilizados

| Campo | Uso |
|-------|-----|
| `status` | `cancel_scheduled` → `canceled` |
| `cancel_at_period_end` | `true` cuando se agenda |
| `cancel_requested_at` | Timestamp del pedido |
| `cancelled_at` | Timestamp efectivo de la baja |
| `cancellation_reason` | Enum string |
| `deactivate_at` | = effective_end_at (cuándo se desactiva) |
| `current_period_end` | Fin del período pagado |

### subscriptions — campos nuevos (en metadata JSONB)

No se necesitan columnas nuevas — se usa `metadata` JSONB existente para:
- `cancellation_reason_text` (texto libre del motivo)
- `cancellation_wants_contact` (bool)
- `data_retention_until` (effective_end_at + 60 días)

### lifecycle_events (Admin DB) — ya existe

Se insertan eventos con `event_type`:
- `subscription_cancel_requested`
- `subscription_cancel_reverted`
- `subscription_canceled` (cuando el cron ejecuta la baja efectiva)

Los campos `old_value`/`new_value`/`metadata` JSONB guardan motivo, wants_contact, fechas.

---

## 7) Migración SQL sugerida (non-blocking)

```sql
-- Tabla de idempotencia para cancelaciones (optional, try/catch)
CREATE TABLE IF NOT EXISTS subscription_cancel_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  idempotency_key TEXT UNIQUE NOT NULL,
  account_id UUID NOT NULL,
  result JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);
CREATE INDEX idx_cancel_log_key ON subscription_cancel_log(idempotency_key);
```

---

## 8) Validaciones/Comandos

```bash
# API (terminal back)
npm run lint && npm run typecheck && npm run build

# Web (terminal front)
npm run lint && npm run typecheck && npm run build

# Admin 
npm run lint && npm run typecheck
```

---

## 9) Tests sugeridos

### BE unit
- `requestCancel` con período vigente → status `cancel_scheduled`, tienda sigue activa
- `requestCancel` sin período → status `cancel_scheduled` con effective_end_at = now, tienda pausada
- `requestCancel` ya cancelado → retorna sin cambios (idempotente)
- `revertCancel` desde `cancel_scheduled` → status `active`
- `revertCancel` desde `canceled` → error 400
- Idempotencia: misma key → mismo resultado

### FE unit
- Modal paso 1: select motivo, textarea aparece si "Otro"
- Modal paso 2: botón disabled hasta escribir "CANCELAR"
- Estado cancel_scheduled: muestra fecha + botón revertir
- Estado canceled: no muestra botón cancelar

---

## 10) Riesgos y mitigación

| Riesgo | Mitigación |
|--------|-----------|
| MP no soporta "cancel at period end" nativamente | Simulamos con `markCancelScheduled` interno; el cron existente ejecuta la baja real al llegar `deactivate_at` |
| Tabla `subscription_cancel_log` no existe | try/catch non-blocking; la idempotencia se degrada a no-op |
| Campos nuevos en subscriptions | Usamos `metadata` JSONB existente; sin migración de schema |
| Tenant revierte y vuelve a cancelar repetidamente | Idempotency key previene duplicados; cada revert+cancel genera nuevo correlation_id |
| Período ya expirado pero MP sigue cobrando | El cancel en MP se ejecuta inmediatamente en todos los casos; solo la VISIBILIDAD de la tienda se mantiene hasta fin de período |

---

## 11) Orden de implementación

1. **PR2 Backend** → Endpoint cancel refactorizado + revert-cancel + audit
2. **PR1 Frontend Web** → Modal 2 pasos + estado cancel_scheduled + revert
3. **PR3 Admin** → Panel de eventos (follow-up)

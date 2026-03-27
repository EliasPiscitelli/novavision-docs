# Plan: Fix Cancel Subscription Flow

**Fecha:** 2026-03-27
**Prioridad:** ALTA — Afecta experiencia de cancelación de clientes en producción
**Apps:** API, Web, Admin

## Problemas detectados

### P1: Redirect a MercadoPago al intentar cancelar
- **Causa raíz:** `hasOutstandingDebt()` lee `billing_adjustments` con status `pending`/`accruing`. Si hay registros (posiblemente espurios o de montos mínimos), el flujo entra en el path de deuda y redirige a MP para pagar antes de cancelar.
- **Archivo:** `apps/api/src/subscriptions/subscriptions.service.ts` líneas 1300-1375
- **Verificación necesaria:** Consultar `billing_adjustments` en Admin DB para la cuenta de Farma y ver si hay registros pendientes. Si los hay, determinar si son legítimos o falsos positivos.

### P2: No se envían emails al cancelar
- **Causa raíz:** El path de `cancel_pending_payment` hace `return` en línea 1374, **ANTES** de llegar al código de emails (líneas 1579-1615) y lifecycle event (líneas 1501-1520).
- **Impacto:** Ni el super admin ni el cliente reciben notificación de la intención de cancelación.
- **Archivo:** `apps/api/src/subscriptions/subscriptions.service.ts`

### P3: Dashboard de Cancelaciones vacío
- **Causa raíz:** El `lifecycle_events.emit('subscription_cancel_requested')` está en línea 1503, que tampoco se alcanza en el path de deuda.
- **Impacto:** El panel "Cancelaciones & Churn" en Admin no muestra ninguna cancelación.
- **Archivo:** `apps/api/src/admin/admin.service.ts` (consume `lifecycle_events`)

## Solución propuesta

### Fase 1: Fix inmediato en API (backend)

#### 1.1 Emitir lifecycle event y emails TAMBIÉN en el path de deuda

En `subscriptions.service.ts`, antes del `return cancelPendingResult` (línea 1374), agregar:

```typescript
// ── NUEVO: Registrar intención de cancelación incluso con deuda pendiente ──

// Lifecycle event (para que aparezca en dashboard de churn)
try {
  this.lifecycleEvents.emit({
    accountId: account.id,
    eventType: 'subscription_cancel_requested',
    oldValue: { subscription_status: subscription.status },
    newValue: {
      subscription_status: 'cancel_pending_payment',
      reason,
      reason_text: reasonText,
      wants_contact: wantsContact,
      has_outstanding_debt: true,
      debt_amount_usd: debtInfo.totalUsd,
    },
    source: 'api',
  });
} catch (e) {
  console.error(`[requestCancel] Lifecycle event (debt path) failed: ${this.getErrorMessage(e)}`);
}

// Email al super admin (con info de deuda)
try {
  await this.notifications.sendCancellationSuperAdminNotification({
    accountId: account.id,
    email: account.email,
    storeName: account.business_name || account.slug,
    slug: account.slug,
    planKey: subscription.plan_key || 'unknown',
    reason: reason || 'no_reason',
    reasonText: reasonText || undefined,
    wantsContact,
    effectiveEndAt: 'Pendiente de pago de deuda',
    cancelType: 'cancel_immediate',
  });
} catch (e) {
  console.error(`[requestCancel] Super admin email (debt path) failed: ${this.getErrorMessage(e)}`);
}

// Email al cliente informando la situación
try {
  await this.notifications.sendCancellationConfirmationEmail({
    accountId: account.id,
    email: account.email,
    storeName: account.business_name || account.slug,
    slug: account.slug,
    effectiveEndAt: 'Una vez abonado el saldo pendiente',
    cancelType: 'cancel_immediate',
    canRevert: false,
  });
} catch (e) {
  console.error(`[requestCancel] Client email (debt path) failed: ${this.getErrorMessage(e)}`);
}
```

#### 1.2 Mejorar UX del frontend cuando hay deuda

En `SubscriptionManagement.jsx`, el caso `cancel_pending_payment` actualmente:
- Muestra un error genérico
- Abre MP en `window.open` (nueva pestaña)

**Mejora propuesta:**
- Mostrar un modal explicativo con el monto de deuda y por qué no se puede cancelar directamente
- Botón explícito "Pagar saldo pendiente" en vez de abrir automáticamente
- Opción de "Contactar soporte" si el cliente cree que es un error
- NO abrir MP automáticamente — dejar que el usuario decida

```jsx
else if (result?.status === "cancel_pending_payment") {
  // Mostrar modal informativo en vez de error + redirect automático
  setCancelDebtInfo({
    amount: result.debt?.amount_local,
    currency: result.debt?.currency || 'ARS',
    amountUsd: result.debt?.amount_usd,
    paymentLink: result.payment_link || result.sandbox_payment_link,
  });
  // NO abrir MP automáticamente
}
```

### Fase 2: Verificar datos de Farma en producción

#### 2.1 Consultar billing_adjustments
```sql
SELECT id, tenant_id, amount_usd, status, description, created_at
FROM billing_adjustments
WHERE tenant_id = '<farma_account_id>'
AND status IN ('pending', 'accruing')
ORDER BY created_at DESC;
```

#### 2.2 Consultar cancellation_debt_log
```sql
SELECT *
FROM cancellation_debt_log
WHERE account_id = '<farma_account_id>'
ORDER BY created_at DESC;
```

#### 2.3 Si la deuda es espuria, limpiarla
```sql
UPDATE billing_adjustments
SET status = 'voided'
WHERE tenant_id = '<farma_account_id>'
AND status IN ('pending', 'accruing')
AND amount_usd < 0.01;  -- Solo si son montos irrelevantes
```

### Fase 3: Mejoras al Dashboard de Cancelaciones (Admin)

#### 3.1 Mostrar cancelaciones con deuda pendiente
El dashboard de churn filtra por `event_type = 'subscription_cancel_requested'`. Con el fix de Fase 1, estos eventos se emitirán también cuando hay deuda. Agregar columna "Deuda" al dashboard que muestre el status de pago.

#### 3.2 Filtro por status de deuda
Agregar filtro en `CancellationsView.jsx` para distinguir:
- Cancelación completada
- Cancelación pendiente de pago
- Cancelación programada

## Archivos a modificar

| App | Archivo | Cambio |
|-----|---------|--------|
| API | `src/subscriptions/subscriptions.service.ts` | Agregar lifecycle event + emails en path de deuda (líneas ~1370) |
| Web | `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Mejorar UX de deuda pendiente (no auto-redirect) |
| Admin | `src/pages/AdminDashboard/CancellationsView.jsx` | Agregar columna/filtro de status de deuda |

## Orden de implementación

1. **API** — Fix del early return (lo más urgente, elimina los 3 problemas de raíz)
2. **Web** — Mejorar UX del caso deuda pendiente
3. **Admin** — Mejoras al dashboard de churn
4. **Verificación** — Consultar BD de Farma para limpiar datos espurios si los hay

## Riesgos

- Si la deuda de Farma es legítima (overages reales), la solución no es eliminarla sino mejorar la comunicación
- Si `hasOutstandingDebt` está generando falsos positivos por algún bug en billing, hay que investigar más profundo en `billing.service.ts`

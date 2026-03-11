# Admin Dashboard - Subscription Integration

## Overview

El Super Admin Dashboard debe validar el estado de suscripción antes de aprobar tiendas. **NO** se debe aprobar una tienda si la suscripción no está activa y pagada.

---

## Current Admin Approval Flow

### Existing Endpoints

1. **GET `/admin/pending-stores`** - Lista tiendas pendientes
2. **POST `/admin/stores/:accountId/approve`** - Aprueba tienda
3. **POST `/admin/stores/:accountId/reject`** - Rechaza tienda

### Current Issues

❌ No valida estado de suscripción  
❌ No verifica si el pago fue realizado  
❌ No muestra información de billing en el dashboard  
❌ Puede aprobar stores sin pago activo

---

## Enhanced Admin Approval Flow

### Phase 1: Update getPendingStores Query

```typescript
// admin/admin.service.ts
async getPendingStores() {
  const { data, error } = await this.adminClient
    .from('nv_accounts')
    .select(`
      id,
      email,
      slug,
      plan_key,
      status,
      mp_connected,
      client_id_backend,
      completion_notes,
      created_at,
      name,
      subscription:subscriptions!account_id (
        id,
        status,
        mp_preapproval_id,
        last_payment_date,
        next_payment_date,
        last_charged_ars,
        consecutive_failures,
        grace_period_ends_at,
        subscription_payment_failures!subscription_id (
          id,
          attempted_at,
          failure_reason,
          resolved_at
        )
      )
    `)
    .in('status', ['pending_approval', 'incomplete'])
    .order('created_at', { ascending: false });

  if (error) throw error;

  // Enrich with subscription status summary
  return (data || []).map(account => ({
    ...account,
    subscription_summary: this.getSubscriptionSummary(account.subscription),
    can_approve: this.canApproveStore(account),
  }));
}

private getSubscriptionSummary(subscription: any) {
  if (!subscription || subscription.length === 0) {
    return {
      status: 'no_subscription',
      message: 'No subscription found',
      blocking: true,
    };
  }

  const sub = subscription[0];

  // Check for active subscription
  if (sub.status === 'active' && !sub.consecutive_failures) {
    return {
      status: 'ok',
      message: 'Subscription active',
      blocking: false,
      last_payment: sub.last_payment_date,
      next_payment: sub.next_payment_date,
    };
  }

  // Check for pending first payment
  if (sub.status === 'pending') {
    return {
      status: 'pending_payment',
      message: 'Waiting for first payment',
      blocking: true,
    };
  }

  // Check for grace period
  if (sub.status === 'grace_period') {
    return {
      status: 'grace_period',
      message: `Payment failed - Grace period until ${new Date(sub.grace_period_ends_at).toLocaleDateString('es-AR')}`,
      blocking: true,
      failures: sub.consecutive_failures,
    };
  }

  // Check for suspended
  if (sub.status === 'suspended') {
    return {
      status: 'suspended',
      message: 'Subscription suspended - Payment required',
      blocking: true,
    };
  }

  return {
    status: 'unknown',
    message: `Status: ${sub.status}`,
    blocking: true,
  };
}

private canApproveStore(account: any): boolean {
  const summary = this.getSubscriptionSummary(account.subscription);

  // Can only approve if:
  // 1. Has active subscription with no failures
  // 2. Status is pending_approval (not incomplete)
  return !summary.blocking && account.status === 'pending_approval';
}
```

---

### Phase 2: Update approveStore with Validation

```typescript
async approveStore(accountId: string, reviewedBy: string) {
  // 1. Get account with subscription
  const { data: account } = await this.adminClient
    .from('nv_accounts')
    .select(`
      *,
      subscription:subscriptions!account_id (
        id,
        status,
        mp_preapproval_id,
        consecutive_failures
      )
    `)
    .eq('id', accountId)
    .single();

  if (!account) {
    throw new NotFoundException('Account not found');
  }

  // 2. Validate subscription
  const subscription = account.subscription?.[0];

  if (!subscription) {
    throw new BadRequestException(
      'Cannot approve: No subscription found. User must complete payment first.'
    );
  }

  if (subscription.status !== 'active') {
    throw new BadRequestException(
      `Cannot approve: Subscription status is "${subscription.status}". Must be "active".`
    );
  }

  if (subscription.consecutive_failures > 0) {
    throw new BadRequestException(
      `Cannot approve: Subscription has ${subscription.consecutive_failures} payment failure(s). Must be resolved.`
    );
  }

  // 3. Activate client in backend
  await  this.adminClient
    .from('clients')
    .update({ is_active: true })
    .eq('id', account.client_id_backend);

  // 4. Update account status
  await this.adminClient
    .from('nv_accounts')
    .update({
      status: 'approved',
      approved_at: new Date().toISOString(),
    })
    .eq('id', accountId);

  // 5. Send welcome email
  await this.notificationService.sendWelcomeEmail({
    accountId,
    clientId: account.client_id_backend,
    email: account.email,
    storeName: account.name || account.slug,
    slug: account.slug,
    plan: account.plan_key,
  });

  return { success: true, message: 'Client approved and activated' };
}
```

---

### Phase 3: Frontend Dashboard Update

Update admin dashboard UI to show subscription info:

```typescript
// Example admin dashboard component
interface PendingStore {
  id: string;
  slug: string;
  email: string;
  plan_key: string;
  created_at: string;
  subscription_summary: {
    status:
      | "ok"
      | "pending_payment"
      | "grace_period"
      | "suspended"
      | "no_subscription";
    message: string;
    blocking: boolean;
    last_payment?: string;
    next_payment?: string;
    failures?: number;
  };
  can_approve: boolean;
}

function AdminDashboard() {
  const [stores, setStores] = useState<PendingStore[]>([]);

  return (
    <table>
      <thead>
        <tr>
          <th>Slug</th>
          <th>Email</th>
          <th>Plan</th>
          <th>Subscription Status</th>
          <th>Created</th>
          <th>Actions</th>
        </tr>
      </thead>
      <tbody>
        {stores.map((store) => (
          <tr key={store.id}>
            <td>{store.slug}</td>
            <td>{store.email}</td>
            <td>{store.plan_key}</td>
            <td>
              <SubscriptionBadge summary={store.subscription_summary} />
            </td>
            <td>{new Date(store.created_at).toLocaleDateString()}</td>
            <td>
              <button
                onClick={() => approveStore(store.id)}
                disabled={!store.can_approve}
                style={{
                  opacity: store.can_approve ? 1 : 0.5,
                  cursor: store.can_approve ? "pointer" : "not-allowed",
                }}
              >
                {store.can_approve ? "Approve" : "Cannot Approve"}
              </button>
              <button onClick={() => rejectStore(store.id)}>Reject</button>
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

function SubscriptionBadge({ summary }) {
  const statusColors = {
    ok: "green",
    pending_payment: "orange",
    grace_period: "red",
    suspended: "red",
    no_subscription: "gray",
  };

  return (
    <div
      style={{
        padding: "4px 8px",
        borderRadius: "4px",
        backgroundColor: statusColors[summary.status],
        color: "white",
        fontSize: "12px",
      }}
    >
      {summary.message}
      {summary.failures > 0 && ` (${summary.failures} failures)`}
    </div>
  );
}
```

---

## Approval Status Matrix

| Subscription Status    | Account Status     | Can Approve? | Action Required             |
| ---------------------- | ------------------ | ------------ | --------------------------- |
| `active` (no failures) | `pending_approval` | ✅ YES       | None - Ready to approve     |
| `pending`              | `pending_approval` | ❌ NO        | Wait for first payment      |
| `grace_period`         | `pending_approval` | ❌ NO        | Wait for payment retry      |
| `suspended`            | `pending_approval` | ❌ NO        | User must pay outstanding   |
| `cancelled`            | `pending_approval` | ❌ NO        | User must reactivate        |
| `null` (no sub)        | `pending_approval` | ❌ NO        | User must complete checkout |

---

## Error Messages for Admin

When attempting to approve a store that cannot be approved:

```typescript
const ERROR_MESSAGES = {
  no_subscription:
    "Este usuario no ha completado el proceso de pago. No se puede aprobar hasta que haya una suscripción activa.",

  pending_payment:
    "La suscripción está pendiente del primer pago. Esperá a que MercadoPago confirme el pago.",

  grace_period:
    "La suscripción tiene pagos fallidos y está en período de gracia. No se puede aprobar hasta que se resuelva.",

  suspended:
    "La suscripción está suspendida por falta de pago. El usuario debe pagar la deuda pendiente antes de aprobar.",

  cancelled:
    "La suscripción fue cancelada por el usuario. Deben reactivarla antes de aprobar.",

  has_failures:
    "La suscripción tiene intentos de pago fallidos. Verificá que estén resueltos antes de aprobar.",
};
```

---

## Webhook Integration

When a payment succeeds, automatically check if store can be auto-approved:

```typescript
async handlePaymentSuccess(mpPaymentId: string, preapprovalId: string) {
  // ... existing payment handling ...

  // Check if store is pending approval
  const { data: account } = await this.adminClient
    .from('nv_accounts')
    .select('id, status')
    .eq('subscription.mp_preapproval_id', preapprovalId)
    .eq('status', 'pending_approval')
    .single();

  if (account) {
    // Optionally: Auto-approve if all checks pass
    // OR: Send notification to admin that store is ready for approval
    await this.notificationService.sendAdminNotification({
      type: 'store_ready_for_approval',
      accountId: account.id,
      message: `Store ready for approval - payment confirmed`,
    });
  }
}
```

---

## Admin Notifications

Notify admins when stores are ready:

```typescript
@Cron('0 9 * * *') // 9 AM daily
async notifyAdminOfReadyStores() {
  const readyStores = await this.getPendingStores();
  const approvable = readyStores.filter(s => s.can_approve);

  if (approvable.length > 0) {
    await this.notificationService.sendAdminEmail({
      to: process.env.SUPER_ADMIN_EMAIL,
      subject: `${approvable.length} tiendas listas para aprobar`,
      body: `
Las siguientes tiendas tienen suscripciones activas y están listas para ser aprobadas:

${approvable.map(s => `• ${s.slug} (${s.email}) - Plan: ${s.plan_key}`).join('\n')}

Dashboard: ${process.env.ADMIN_URL}/admin/pending
      `,
    });
  }
}
```

---

## Database Views (Optional)

Create a view for easier querying:

```sql
CREATE VIEW admin_pending_stores_with_subscription AS
SELECT
  a.id,
  a.slug,
  a.email,
  a.plan_key,
  a.status as account_status,
  a.created_at,
  s.id as subscription_id,
  s.status as subscription_status,
  s.last_payment_date,
  s.next_payment_date,
  s.consecutive_failures,
  s.grace_period_ends_at,
  CASE
    WHEN s.id IS NULL THEN false
    WHEN s.status != 'active' THEN false
    WHEN s.consecutive_failures > 0 THEN false
    WHEN a.status != 'pending_approval' THEN false
    ELSE true
  END as can_approve
FROM nv_accounts a
LEFT JOIN subscriptions s ON s.account_id = a.id
WHERE a.status IN ('pending_approval', 'incomplete');
```

---

## Testing Checklist

- [ ] Cannot approve store without subscription
- [ ] Cannot approve store with pending payment
- [ ] Cannot approve store with failed payments
- [ ] Can approve store with active subscription
- [ ] UI shows correct subscription status
- [ ] Disabled approve button for blocked stores
- [ ] Error messages are clear and helpful
- [ ] Webhook auto-notifies admin when ready
- [ ] Daily email summary works

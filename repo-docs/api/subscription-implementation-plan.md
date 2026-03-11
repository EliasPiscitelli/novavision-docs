# Recurring Subscriptions with Inflation Adjustment

## Overview

Implementar sistema de suscripciones recurrentes que se ajusta automáticamente a la inflación/variación del dólar, notificando a usuarios 3 días antes cuando el aumento supera un umbral configurable.

## User Review Required

> [!IMPORTANT] > **Breaking Change**: Cambio de modelo de negocio de pago único a suscripción recurrente.
>
> - Los usuarios existentes (si los hay) necesitarán migración manual
> - El flujo de onboarding cambia de Preference a PreApproval
> - Se requiere manejo de webhooks adicionales de MercadoPago

> [!WARNING] > **Configuración Requerida**:
>
> - Variables de entorno nuevas (ver sección Environment Variables)
> - Cron job configurado en el servidor
> - EmailJS o servicio de email configurado

## Proposed Changes

### Phase 1: Database Schema

#### [NEW] Migration: subscriptions table

```sql
CREATE TABLE subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  account_id UUID NOT NULL REFERENCES nv_accounts(id) ON DELETE CASCADE,

  -- MercadoPago PreApproval
  mp_preapproval_id TEXT UNIQUE NOT NULL,
  mp_payer_id TEXT,

  -- Plan info
  plan_key TEXT NOT NULL,
  plan_price_usd NUMERIC NOT NULL, -- Precio base en USD (fijo)

  -- Status
  status TEXT NOT NULL, -- active, paused, cancelled, pending

  -- Billing
  next_payment_date TIMESTAMPTZ,
  last_payment_date TIMESTAMPTZ,
  last_charged_ars NUMERIC,
  next_estimated_ars NUMERIC,

  -- Price adjustment
  price_check_threshold_pct NUMERIC DEFAULT 10, -- Notificar si sube >10%
  last_price_check_at TIMESTAMPTZ,
  last_notification_sent_at TIMESTAMPTZ,

  -- Metadata
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  cancelled_at TIMESTAMPTZ,
  cancellation_reason TEXT,

  CONSTRAINT valid_status CHECK (status IN ('active', 'paused', 'cancelled', 'pending'))
);

CREATE INDEX idx_subscriptions_account ON subscriptions(account_id);
CREATE INDEX idx_subscriptions_mp_preapproval ON subscriptions(mp_preapproval_id);
CREATE INDEX idx_subscriptions_next_payment ON subscriptions(next_payment_date) WHERE status = 'active';
```

---

#### [NEW] Migration: subscription_payment_failures table

```sql
CREATE TABLE subscription_payment_failures (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,

  -- Failure details
  attempted_at TIMESTAMPTZ NOT NULL,
  attempted_amount_ars NUMERIC NOT NULL,
  mp_payment_id TEXT,
  failure_reason TEXT,
  mp_status TEXT, -- rejected, cancelled, etc

  -- Retry tracking
  retry_count INTEGER DEFAULT 0,
  next_retry_at TIMESTAMPTZ,
  max_retries INTEGER DEFAULT 3,

  -- Resolution
  resolved_at TIMESTAMPTZ,
  resolution_type TEXT, -- manual_payment, retry_success, cancelled

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_payment_failures_subscription ON subscription_payment_failures(subscription_id, attempted_at DESC);
CREATE INDEX idx_payment_failures_next_retry ON subscription_payment_failures(next_retry_at) WHERE resolved_at IS NULL;
```

---

#### [MODIFY] subscriptions table - Add failure tracking

```sql
ALTER TABLE subscriptions
ADD COLUMN consecutive_failures INTEGER DEFAULT 0,
ADD COLUMN last_failure_at TIMESTAMPTZ,
ADD COLUMN grace_period_ends_at TIMESTAMPTZ,
ADD COLUMN auto_suspend_at TIMESTAMPTZ;
```

---

#### [NEW] Migration: subscription_price_history table

```sql
CREATE TABLE subscription_price_history (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  subscription_id UUID NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,

  -- Price data
  charged_at TIMESTAMPTZ NOT NULL,
  price_usd NUMERIC NOT NULL,
  price_ars NUMERIC NOT NULL,
  blue_rate NUMERIC NOT NULL,

  -- Variation tracking
  previous_price_ars NUMERIC,
  variation_pct NUMERIC,

  -- Payment outcome
  mp_payment_id TEXT,
  payment_status TEXT, -- approved, rejected, refunded

  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_price_history_subscription ON subscription_price_history(subscription_id, charged_at DESC);
```

---

#### [MODIFY] nv_accounts table

Add subscription tracking:

```sql
ALTER TABLE nv_accounts
ADD COLUMN subscription_id UUID REFERENCES subscriptions(id),
ADD COLUMN subscription_status TEXT, -- Denormalized for quick access
ADD COLUMN subscription_expires_at TIMESTAMPTZ;
```

---

### Phase 2: MercadoPago Integration

#### [MODIFY] platform-mercadopago.service.ts

Add PreApproval methods:

```typescript
import { PreApproval } from "mercadopago";

export class PlatformMercadoPagoService {
  private preApproval: PreApproval;

  constructor(config: ConfigService) {
    // ... existing
    this.preApproval = new PreApproval(this.client);
  }

  /**
   * Create recurring subscription (PreApproval)
   */
  async createSubscription(data: {
    reason: string;
    price_ars: number;
    payer_email: string;
    external_reference: string;
    back_url: string;
  }) {
    const result = await this.preApproval.create({
      body: {
        reason: data.reason,
        auto_recurring: {
          frequency: 1,
          frequency_type: "months",
          transaction_amount: data.price_ars,
          currency_id: "ARS",
        },
        back_url: data.back_url,
        payer_email: data.payer_email,
        external_reference: data.external_reference,
        status: "pending",
      },
    });

    return {
      id: result.id,
      init_point: result.init_point,
      status: result.status,
    };
  }

  /**
   * Update subscription price
   */
  async updateSubscriptionPrice(preapprovalId: string, newPriceArs: number) {
    await this.preApproval.update({
      id: preapprovalId,
      body: {
        auto_recurring: {
          transaction_amount: newPriceArs,
        },
      },
    });
  }

  /**
   * Cancel subscription
   */
  async cancelSubscription(preapprovalId: string) {
    await this.preApproval.update({
      id: preapprovalId,
      body: {
        status: "cancelled",
      },
    });
  }

  /**
   * Get subscription details
   */
  async getSubscription(preapprovalId: string) {
    return await this.preApproval.get({ id: preapprovalId });
  }
}
```

---

### Phase 3: Subscription Service

#### [NEW] subscriptions/subscriptions.service.ts

```typescript
@Injectable()
export class SubscriptionsService {
  constructor(
    private dbRouter: DbRouterService,
    private platformMp: PlatformMercadoPagoService,
    private notifications: OnboardingNotificationService,
    private config: ConfigService,
  ) {}

  /**
   * Create subscription during onboarding
   */
  async createSubscriptionForAccount(
    accountId: string,
    planKey: string,
  ): Promise<{ preapprovalId: string; initPoint: string }> {
    // 1. Get plan price in USD
    const planPriceUsd = await this.getPlanPriceUsd(planKey);

    // 2. Get current blue dollar rate
    const blueRate = await this.getBlueDollarRate();

    // 3. Calculate initial price in ARS
    const initialPriceArs = Math.ceil(planPriceUsd * blueRate);

    // 4. Get account email
    const account = await this.getAccount(accountId);

    // 5. Create preapproval in MP
    const preapproval = await this.platformMp.createSubscription({
      reason: `NovaVision ${planKey}`,
      price_ars: initialPriceArs,
      payer_email: account.email,
      external_reference: `sub_${accountId}_${Date.now()}`,
      back_url: `${this.config.get('ADMIN_URL')}/wizard?status=subscription_created`,
    });

    // 6. Create subscription record
    await this.dbRouter.getAdminClient()
      .from('subscriptions')
      .insert({
        account_id: accountId,
        mp_preapproval_id: preapproval.id,
        plan_key: planKey,
        plan_price_usd: planPriceUsd,
        status: 'pending', // Will update via webhook
        next_estimated_ars: initialPriceArs,
      });

    return {
      preapprovalId: preapproval.id,
      initPoint: preapproval.init_point,
    };
  }

  /**
   * Check and update prices for upcoming payments
   * Called daily by cron job
   */
  @Cron('0 2 * * *') // 2 AM daily
  async checkAndUpdatePrices() {
    const adminClient = this.dbRouter.getAdminClient();
    const daysBeforeNotification = this.config.get<number>('PRICE_CHECK_DAYS_BEFORE') || 3;
    const thresholdPct = this.config.get<number>('PRICE_ADJUSTMENT_THRESHOLD_PCT') || 10;

    // Get subscriptions with payment in N days
    const targetDate = new Date();
    targetDate.setDate(targetDate.getDate() + daysBeforeNotification);

    const { data: subscriptions } = await adminClient
      .from('subscriptions')
      .select('*, nv_accounts(email, slug)')
      .eq('status', 'active')
      .gte('next_payment_date', targetDate.toISOString())
      .lt('next_payment_date', new Date(targetDate.getTime() + 24 * 60 * 60 * 1000).toISOString());

    for (const sub of subscriptions || []) {
      try {
        // Get current rate
        const currentRate = await this.getBlueDollarRate();
        const newPriceArs = Math.ceil(sub.plan_price_usd * currentRate);
        const oldPriceArs = sub.last_charged_ars || sub.next_estimated_ars;

        // Calculate variation
        const variation = ((newPriceArs - oldPriceArs) / oldPriceArs) * 100;

        // Update price in MP
        await this.platformMp.updateSubscriptionPrice(sub.mp_preapproval_id, newPriceArs);

        // Update DB
        await adminClient
          .from('subscriptions')
          .update({
            next_estimated_ars: newPriceArs,
            last_price_check_at: new Date().toISO String(),
          })
          .eq('id', sub.id);

        // Notify if increase is significant
        if (variation > thresholdPct) {
          await this.notifications.sendPriceIncreaseNotification({
            email: sub.nv_accounts.email,
            slug: sub.nv_accounts.slug,
            oldPrice: oldPriceArs,
            newPrice: newPriceArs,
            variation: variation.toFixed(1),
            priceUsd: sub.plan_price_usd,
            blueRate: currentRate,
            nextPaymentDate: sub.next_payment_date,
          });

          await adminClient
            .from('subscriptions')
            .update({ last_notification_sent_at: new Date().toISOString() })
            .eq('id', sub.id);
        }

        this.logger.log(`Updated price for subscription ${sub.id}: ${oldPriceArs} -> ${newPriceArs} ARS (${variation.toFixed(1)}%)`);
      } catch (error) {
        this.logger.error(`Failed to update price for subscription ${sub.id}:`, error);
      }
    }
  }

  private async getBlueDollarRate(): Promise<number> {
    try {
      const res = await fetch('https://dolarapi.com/v1/dolares/blue');
      if (res.ok) {
        const data = await res.json();
        return Number(data.venta) || 1200;
      }
    } catch (error) {
      this.logger.warn('Failed to fetch blue dollar rate, using fallback', error);
    }
    return 1200; // Fallback
  }
}
```

---

### Phase 4: Webhook Handling

#### [MODIFY] subscriptions.controller.ts

Add PreApproval webhook handler:

```typescript
@Post('webhook/preapproval')
async handlePreapprovalWebhook(@Body() payload: any, @Headers() headers: any) {
  // Validate MP signature
  // ...

  const { action, data } = payload;

  switch (action) {
    case 'created':
      await this.subscriptionsService.handleSubscriptionCreated(data.id);
      break;
    case 'updated':
      await this.subscriptionsService.handleSubscriptionUpdated(data.id);
      break;
    case 'payment.created':
      await this.subscriptionsService.handlePaymentCreated(data.id);
      break;
    default:
      this.logger.log(`Unhandled preapproval action: ${action}`);
  }

  return { ok: true };
}
```

---

### Phase 5: Notification Service

#### [MODIFY] onboarding/onboarding-notification.service.ts

Add price increase notification:

```typescript
async sendPriceIncreaseNotification(data: {
  email: string;
  slug: string;
  oldPrice: number;
  newPrice: number;
  variation: string;
  priceUsd: number;
  blueRate: number;
  nextPaymentDate: string;
}) {
  const template = `
Hola,

Tu suscripción de NovaVision (${data.slug}) se renovará en 3 días.

Debido a la variación del dólar blue, el precio mensual será:
━━━━━━━━━━━━━━━━━━━━━━━━━━
• Anterior: $${data.oldPrice.toLocaleString('es-AR')} ARS
• Nuevo: $${data.newPrice.toLocaleString('es-AR')} ARS
• Aumento: +${data.variation}%
━━━━━━━━━━━━━━━━━━━━━━━━━━

Precio base en USD: $${data.priceUsd} (sin cambios)
Dólar Blue hoy: $${data.blueRate.toLocaleString('es-AR')}

Próximo cobro: ${new Date(data.nextPaymentDate).toLocaleDateString('es-AR')}

Si preferís cancelar tu suscripción, podés hacerlo desde tu panel de control.

Saludos,
Equipo NovaVision
  `;

  await this.sendEmail({
    to: data.email,
    subject: `Actualización de precio - NovaVision ${data.slug}`,
    text: template,
  });
}
```

---

### Phase 6: Onboarding Flow Update

#### [MODIFY] onboarding.service.ts - startCheckout

Replace Preference with PreApproval:

```typescript
async startCheckout(accountId: string, planId: string, cycle: string) {
  // 1. Reserve slug
  await this.reserveSlugForCheckout(accountId);

  // 2. Create subscription (NOT one-time payment)
  const { preapprovalId, initPoint } = await this.subscriptionsService
    .createSubscriptionForAccount(accountId, planId);

  // 3. Update onboarding
  await this.dbRouter.getAdminClient()
    .from('nv_onboarding')
    .update({
      plan_key_selected: planId,
      mp_preapproval_id: preapprovalId,
      checkout_created_at: new Date().toISOString(),
    })
    .eq('account_id', accountId);

  return {
    preapproval_id: preapprovalId,
    status: 'pending',
    redirect_url: initPoint,
  };
}
```

---

## Environment Variables

Add to `apps/api/.env`:

```bash
# Subscription Configuration
PRICE_ADJUSTMENT_THRESHOLD_PCT=10  # Notify users if price increases >10%
PRICE_CHECK_DAYS_BEFORE=3          # Check/notify N days before billing
DOLLAR_SOURCE=blue                 # blue | oficial | mep

# Cron Schedule
PRICE_CHECK_CRON=0 2 * * *        # Run daily at 2 AM
```

---

## Verification Plan

### Automated Tests

1. **Unit Tests**

   - `subscription.service.spec.ts` - Price calculation, rate fetching
   - `platform-mercadopago.service.spec.ts` - PreApproval API calls

2. **Integration Tests**
   - Create subscription flow
   - Webhook handling
   - Price update job

### Manual Verification

1. **Happy Path**

   - Complete onboarding → Creates preapproval
   - Approve in MP → Webhook activates subscription
   - Wait for cron → Price gets updated
   - Receive email → Notification sent correctly

2. **Edge Cases**

   - Large price increase (>threshold) → Email sent
   - Small price increase (<threshold) → No email
   - User cancels → Subscription cancelled in MP
   - Payment fails → Handle retry logic

3. **Database Verification**

   ```sql
   -- Check subscription created
   SELECT * FROM subscriptions WHERE account_id = 'xxx';

   -- Check price history
   SELECT * FROM subscription_price_history
   WHERE subscription_id = 'xxx'
   ORDER BY charged_at DESC;
   ```

---

## Migration Strategy for Existing Users

If there are existing users with one-time payments:

1. Create migration script to:

   - Create PreApproval in MP for each active account
   - Insert subscription record
   - Update `nv_accounts.subscription_id`

2. Send email notification:
   ```
   Mejoramos tu experiencia: Ahora con facturación automática mensual.
   Tu siguiente cobro será el DD/MM/YYYY por $XXX ARS.
   ```

---

## Rollback Plan

If issues arise:

1. Pause cron job: Comment out `@Cron` decorator
2. Stop creating new subscriptions: Feature flag in code
3. Revert to Preference: Uncomment old checkout code
4. Manual refunds: Process via MP dashboard

---

## Estimated Timeline

| Phase                 | Tasks                | Effort  | Dependencies |
| --------------------- | -------------------- | ------- | ------------ |
| 1. Database           | Migrations, schemas  | 2h      | None         |
| 2. MP Integration     | PreApproval service  | 3h      | Phase 1      |
| 3. Subscription Logic | Service layer        | 4h      | Phase 2      |
| 4. Webhooks           | Handlers, validation | 2h      | Phase 3      |
| 5. Notifications      | Email templates      | 1h      | Phase 3      |
| 6. Onboarding Update  | Flow changes         | 2h      | All above    |
| 7. Testing            | Unit + Integration   | 3h      | All above    |
| **Total**             |                      | **17h** |              |

---

## Next Steps

1. ✅ Review this plan
2. ⏳ Approve to proceed
3. ⏳ Execute Phase 1 (Migrations)
4. ⏳ Execute Phase 2-6 sequentially
5. ⏳ Run verification tests
6. ⏳ Deploy to staging
7. ⏳ Production rollout

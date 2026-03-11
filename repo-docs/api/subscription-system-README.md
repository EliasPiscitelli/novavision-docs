# Subscription System Documentation

## Overview

Sistema de suscripciones recurrentes con ajuste automático de precios basado en la inflación del dólar blue, diseñado para el mercado argentino.

**Status:** 9/11 Phases Complete - Sistema Funcional End-to-End

---

## 📚 Documentation Files

### 1. [Walkthrough - Implementación Completa](./subscription-system-walkthrough.md)

Documentación completa del sistema implementado:

- Resumen de todas las phases completadas
- Diagramas de arquitectura (Mermaid)
- Flujos de creación de subscripción
- Flujos de ajuste de precios
- Checklist de testing y deployment

### 2. [Implementation Plan](./subscription-implementation-plan.md)

Plan técnico detallado original:

- Propuestas de cambios por componente
- Esquemas de base de datos
- Métodos de servicios
- Plan de verificación
- Estrategia de migración y rollback

### 3. [Payment Failures & Cancellations](./subscription-payment-failures.md)

Manejo completo de fallos de pago:

- Flujo de payment failed con retry logic
- Períodos de gracia y suspensión automática
- Cancelaciones iniciadas por usuario
- Reactivación de suscripciones
- Email templates

### 4. [Admin Dashboard Integration](./subscription-admin-dashboard.md)

Validación de suscripciones en el dashboard admin:

- Integración de subscription status en getPendingStores()
- Validación de pago antes de aprobar tiendas
- Badges de estado para admin UI
- Matriz de estados y acciones
- Mensajes de error específicos

### 5. [Task Checklist](./subscription-task-checklist.md)

Checklist detallado de todas las phases (1-11):

- Database Schema ✅
- MercadoPago Integration ✅
- Subscription Service ✅
- Webhook Handling ✅
- Notifications ⚠️
- Onboarding Flow ✅
- Environment Config ✅
- Testing ⏳
- Admin Dashboard ✅
- Documentation ⏳
- Deployment ⏳

---

## 🚀 Quick Start

### 1. Environment Setup

```bash
# Add to apps/api/.env
PRICE_ADJUSTMENT_THRESHOLD_PCT=10
PRICE_CHECK_DAYS_BEFORE=3
GRACE_PERIOD_DAYS=7
MAX_PAYMENT_RETRIES=3
```

### 2. Database Migrations

```bash
cd apps/api
psql $ADMIN_DB_URL -f migrations/20260111_create_subscriptions.sql
psql $ADMIN_DB_URL -f migrations/20260111_create_payment_failures.sql
psql $ADMIN_DB_URL -f migrations/20260111_create_price_history.sql
psql $ADMIN_DB_URL -f migrations/20260111_alter_nv_accounts.sql
psql $ADMIN_DB_URL -f migrations/20260111_alter_nv_onboarding.sql
```

### 3. Testing

```bash
# Manual test
curl -X POST http://localhost:3001/onboarding/accounts/:id/checkout/start \
  -H "Content-Type: application/json" \
  -d '{"planId": "starter", "cycle": "month"}'

# Verify in DB
psql $ADMIN_DB_URL -c "SELECT * FROM subscriptions ORDER BY created_at DESC LIMIT 5"
```

---

## 🏗️ Architecture

```
┌─────────────┐
│   User      │
└──────┬──────┘
       │ Complete Wizard
       ▼
┌─────────────────┐
│  Onboarding     │──► SubscriptionsService
│  Service        │    └─► createSubscriptionForAccount()
└─────────────────┘        ├─► Fetch blue dollar rate
                           ├─► Calculate ARS price
                           ├─► Create MP PreApproval
                           └─► Store in DB (status=pending)
       │
       ▼
┌─────────────────┐
│  MercadoPago    │
└─────────────────┘
       │ Webhook: preapproval.created
       ▼
┌─────────────────┐
│  Webhooks       │──► handleSubscriptionCreated()
│  Handler        │    └─► Update status = 'active'
└─────────────────┘

Daily Cron Jobs:
┌─────────────────┐
│  2 AM - Check   │──► Update prices based on dollar
│  Prices         │    Notify if increase >10%
└─────────────────┘

┌─────────────────┐
│  3 AM - Reconcile│──► Suspend expired subscriptions
│  Subscriptions  │
└─────────────────┘
```

---

## 📊 Key Components

### Services

- **SubscriptionsService** (612 lines)

  - Subscription creation
  - Price adjustment cron job
  - Payment failure handling
  - 7 webhook handlers

- **PlatformMercadoPagoService** (293 lines)

  - 8 PreApproval methods
  - Payment queries
  - Subscription lifecycle management

- **AdminService** (257 lines - rewritten)
  - Subscription validation before approval
  - getPendingStores with subscription data
  - Approval blocking logic

### Database

- `subscriptions` - Main subscription records
- `subscription_payment_failures` - Retry tracking
- `subscription_price_history` - Price history

---

## 🎯 Next Steps

1. **Testing Exhaustivo** - Phase 8
2. **Deployment to Staging** - Phase 11
3. **Complete Email Templates** - Phase 5 (3 pending)
4. **API Documentation** - Phase 10

---

## 📞 Support

For questions or issues:

- See implementation plan for detailed technical specs
- Check payment failure flows for error handling
- Review admin integration for approval logic

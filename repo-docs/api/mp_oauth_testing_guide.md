# MP OAuth v1.1 - Testing Guide

## 🎯 Objetivo

Validar completamente el sistema MP OAuth multi-tenant antes de deploy a producción.

---

## ✅ Prerequisitos (Setup)

### 1. Mercado Pago Developer App

```bash
# 1. Go to: https://www.mercadopago.com.ar/developers/panel/app
# 2. Create new application
# 3. Get credentials:
MP_CLIENT_ID=APP-xxxxxxxxxxxx
MP_CLIENT_SECRET=xxxxxxxxxxxx

# 4. Configure redirect_uri:
https://admin.novavision.app/mp/oauth/callback
# (or localhost:3001 for local testing)
```

### 2. Redis Setup

```bash
# Local (Docker)
docker run -d --name redis-mp -p 6379:6379 redis:alpine

# Verify
redis-cli ping
# Should return: PONG
```

### 3. Environment Variables

```bash
# apps/api/.env

# Generate encryption key
MP_TOKEN_ENCRYPTION_KEY=$(openssl rand -hex 32)

# MP OAuth
MP_CLIENT_ID=your_app_client_id
MP_CLIENT_SECRET=your_app_client_secret
MP_REDIRECT_URI=http://localhost:3001/mp/oauth/callback

# Redis
REDIS_HOST=localhost
REDIS_PORT=6379
REDIS_PASSWORD=
REDIS_DB=0
REDIS_TLS=false
```

### 4. Database Migration

```bash
# Run migration
psql $ADMIN_DB_URL -f apps/api/migrations/admin/20250102000000_add_mp_oauth_v1.1.sql

# Verify tables created
psql $ADMIN_DB_URL -c "\d mp_connections"
psql $ADMIN_DB_URL -c "SELECT column_name FROM information_schema.columns WHERE table_name='nv_accounts' AND column_name LIKE 'mp_%';"
```

### 5. Install Dependencies

```bash
cd apps/api
npm install ioredis
npm run build

cd ../admin
npm run build
```

---

## 🧪 Test Suite

### Test 1: Smoke Test - Redis Connection

```bash
# Start API
cd apps/api
npm run start:dev

# Check logs for:
✅ Redis connected successfully
🚀 Redis ready for operations

# If error:
❌ Redis connection error: connect ECONNREFUSED
# → Verify Redis is running: docker ps
```

**Expected:** Redis connection successful  
**Status:** [ ]

---

### Test 2: Smoke Test - Modules Loaded

```bash
# Check API logs for:
[NestApplication] Nest application successfully started

# Verify OAuth endpoints registered
curl http://localhost:3000/mp/oauth/status/test-client-id
# Should return: {"connected":false,"status":"not_found"}
```

**Expected:** API starts without errors, endpoints accessible  
**Status:** [ ]

---

### Test 3: Database Schema Validation

```sql
-- Verify mp_connections structure
SELECT
  column_name,
  data_type,
  is_nullable
FROM information_schema.columns
WHERE table_name = 'mp_connections';

-- Check constraints
SELECT constraint_name, constraint_type
FROM information_schema.table_constraints
WHERE table_name = 'mp_connections';

-- Verify trigger exists
SELECT trigger_name
FROM information_schema.triggers
WHERE event_object_table = 'mp_connections';
```

**Expected:**

- `account_id` FK to `nv_accounts(id)` ✓
- `status` CHECK constraint ✓
- `updated_at` trigger ✓

**Status:** [ ]

---

### Test 4: Encryption/Decryption

```typescript
// Create test file: apps/api/test/mp-oauth.encryption.spec.ts

import { MpOauthService } from "../src/mp-oauth/mp-oauth.service";
import { ConfigService } from "@nestjs/config";

describe("MpOauthService - Encryption", () => {
  let service: MpOauthService;

  beforeAll(() => {
    const configService = new ConfigService({
      MP_TOKEN_ENCRYPTION_KEY:
        "3a2f1e9b7c4d8e6f0a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0c1d2e3f",
    });
    // Mock dependencies
    service = new MpOauthService(configService, mockDbRouter, mockRedis);
  });

  it("should encrypt and decrypt token correctly", () => {
    const original = "APP_USR-1234567890-121212-abcdefgh";
    const encrypted = service["encryptToken"](original);
    const decrypted = service["decryptToken"](encrypted);

    expect(decrypted).toBe(original);
    expect(encrypted).not.toBe(original);
    expect(encrypted.length).toBeGreaterThan(original.length);
  });

  it("should fail decryption with wrong key", () => {
    const encrypted = service["encryptToken"]("test");

    // Change key
    service["encryptionKey"] = Buffer.from("wrong_key");

    expect(() => service["decryptToken"](encrypted)).toThrow();
  });
});
```

**Run:** `npm test -- mp-oauth.encryption.spec.ts`  
**Expected:** All tests pass ✅  
**Status:** [ ]

---

### Test 5: E2E OAuth Flow (Manual)

#### 5.1 Create Test Account

```sql
-- Insert test account
INSERT INTO nv_accounts (id, email, plan_key, payment_status)
VALUES (
  '00000000-0000-0000-0000-000000000001',
  'test@novavision.app',
  'growth',
  'approved'
);

-- Insert onboarding
INSERT INTO nv_onboarding (id, account_id, session_id, slug)
VALUES (
  '00000000-0000-0000-0000-000000000002',
  '00000000-0000-0000-0000-000000000001',
  'test_onboarding_token_123',
  'test-store'
);
```

#### 5.2 Start OAuth Flow

```bash
# Get onboarding token
ONBOARDING_TOKEN="test_onboarding_token_123"

# Call start endpoint
curl -X GET \
  "http://localhost:3000/mp/oauth/start" \
  -H "Authorization: Bearer $ONBOARDING_TOKEN" \
  -v

# Should redirect to:
# https://auth.mercadopago.com/authorization?client_id=xxx&state=xxx...

# Copy the redirect URL and open in browser
```

#### 5.3 Authorize in MP

1. Login with your MP sandbox account
2. Click "Autorizar"
3. Should redirect to: `http://localhost:3001/mp/oauth/callback?code=xxx&state=yyy`

#### 5.4 Verify Callback Success

```bash
# Check API logs for:
OAuth completed for account 00000000-0000-0000-0000-000000000001

# Check database
SELECT
  account_id,
  mp_user_id,
  status,
  live_mode,
  expires_at
FROM mp_connections
WHERE account_id = '00000000-0000-0000-0000-000000000001';

# Verify account updated
SELECT mp_connected, mp_user_id
FROM nv_accounts
WHERE id = '00000000-0000-0000-0000-000000000001';

# Verify onboarding updated
SELECT mp_connection_status
FROM nv_onboarding
WHERE account_id = '00000000-0000-0000-0000-000000000001';
```

**Expected:**

- `mp_connections` row created ✓
- `access_token` is encrypted (long hex string) ✓
- `nv_accounts.mp_connected` = true ✓
- `nv_onboarding.mp_connection_status` = 'connected' ✓

**Status:** [ ]

---

### Test 6: Token Retrieval & Decryption

```bash
# Get client_id from account
CLIENT_ID=$(psql $ADMIN_DB_URL -t -c "SELECT client_id_backend FROM nv_accounts WHERE id = '00000000-0000-0000-0000-000000000001';")

# Call service method (via debug endpoint or direct test)
curl "http://localhost:3000/mp/oauth/status/$CLIENT_ID"

# Should return:
{
  "connected": true,
  "live_mode": false,
  "expires_at": "2025-07-02...",
  "status": "connected",
  "mp_user_id": "123456789"
}
```

**Expected:** Status shows connected ✓  
**Status:** [ ]

---

### Test 7: Checkout Integration

```typescript
// Test createPreference with client token

// 1. Update checkout.service.ts to use MP OAuth
// 2. Create test order
const clientId = "client-abc-123";
const items = [{ name: "Test Product", quantity: 1, price: 100 }];

const preference = await checkoutService.createPreference(clientId, items);

console.log("Preference ID:", preference.preference_id);
console.log("Init Point:", preference.init_point);

// 3. Verify preference created with CLIENT's credentials
// Check MP dashboard under the CLIENT's account (not platform)
```

**Expected:**

- Preference created ✓
- Payment goes to CLIENT's MP account (not platform) ✓

**Status:** [ ]

---

### Test 8: Token Refresh (Forced)

```sql
-- Set token to expired
UPDATE mp_connections
SET expires_at = NOW() - INTERVAL '1 day'
WHERE account_id = '00000000-0000-0000-0000-000000000001';
```

```bash
# Trigger refresh via getClientAccessToken
curl "http://localhost:3000/mp/oauth/status/$CLIENT_ID"

# Check logs for:
Token expired for client xxx, refreshing...
Token refreshed for account 00000000-0000-0000-0000-000000000001

# Verify database
SELECT expires_at, last_refresh_at
FROM mp_connections
WHERE account_id = '00000000-0000-0000-0000-000000000001';
# expires_at should be ~180 days in future
# last_refresh_at should be NOW
```

**Expected:** Auto-refresh successful ✓  
**Status:** [ ]

---

### Test 9: Worker Cron Jobs

```bash
# Manually trigger refresh worker
curl -X POST "http://localhost:3000/mp/oauth/refresh/00000000-0000-0000-0000-000000000001"

# Check logs for:
Token refreshed for account 00000000-0000-0000-0000-000000000001

# Or wait for cron (runs every 12h)
# Check logs at :00 of 12h intervals
```

**Expected:** Worker executes without errors ✓  
**Status:** [ ]

---

### Test 10: Distributed Lock (Multi-Instance)

```bash
# Terminal 1: Start API instance 1
PORT=3000 npm run start:dev

# Terminal 2: Start API instance 2
PORT=3001 npm run start:dev

# Terminal 3: Trigger concurrent refresh
curl -X POST "http://localhost:3000/mp/oauth/refresh/00000000-0000-0000-0000-000000000001" &
curl -X POST "http://localhost:3001/mp/oauth/refresh/00000000-0000-0000-0000-000000000001" &

# Check logs - should see:
# Instance 1: "Token refreshed for account..."
# Instance 2: "Refresh already in progress... skipping"
```

**Expected:** Only 1 instance processes refresh ✓  
**Status:** [ ]

---

## 🔒 Security Audit

### State Security

```bash
# 1. Start OAuth flow
# 2. Capture state parameter from redirect URL
STATE="captured_state_value"

# 3. Try to reuse state (replay attack)
curl "http://localhost:3000/mp/oauth/callback?code=fake&state=$STATE"

# Should return error: "Invalid or expired state parameter"
```

**Expected:** State is single-use ✓  
**Status:** [ ]

### Encryption Validation

```sql
-- Verify tokens are encrypted in DB
SELECT
  LEFT(access_token, 20) as token_preview,
  LENGTH(access_token) as token_length
FROM mp_connections;

-- token_preview should be HEX (0-9a-f)
-- token_length should be > 100 (encrypted is longer than plain)
```

**Expected:** Tokens stored encrypted ✓  
**Status:** [ ]

### Ownership Validation

```bash
# Try to start OAuth with invalid token
curl -X GET \
  "http://localhost:3000/mp/oauth/start" \
  -H "Authorization: Bearer fake_token_123"

# Should return: 401 Unauthorized
# "Invalid or expired onboarding token"
```

**Expected:** Ownership enforced ✓  
**Status:** [ ]

---

## 📊 Success Criteria

| Metric               | Target             | Actual | Pass |
| -------------------- | ------------------ | ------ | ---- |
| Redis connection     | Success            |        | [ ]  |
| Migration applied    | No errors          |        | [ ]  |
| Modules load         | Success            |        | [ ]  |
| OAuth flow E2E       | Complete           |        | [ ]  |
| Tokens encrypted     | 100%               |        | [ ]  |
| Auto-refresh         | Works              |        | [ ]  |
| Distributed lock     | No races           |        | [ ]  |
| Checkout integration | Client credentials |        | [ ]  |
| Security audit       | All pass           |        | [ ]  |

---

## 🐛 Troubleshooting

### Error: "Redis connection error"

```bash
# Check Redis running
docker ps | grep redis

# Test connection
redis-cli -h localhost -p 6379 ping

# Check env vars
echo $REDIS_HOST
echo $REDIS_PORT
```

### Error: "MP_TOKEN_ENCRYPTION_KEY must be 32 bytes"

```bash
# Generate new key
openssl rand -hex 32

# Verify length
echo -n "your_key" | wc -c  # Should be 64
```

### Error: "Invalid or expired state"

- State tiene TTL de 10 minutos
- Completar OAuth flow rápido
- No recargar página durante flow

### Error: "MP connection not found"

- Verificar que OAuth flow completó
- Check `mp_connections` table
- Verify `client_id_backend` matches

---

## 📝 Test Results Log

```
Date: ___________
Tester: ___________

[ ] Test 1: Redis Connection
[ ] Test 2: Modules Loaded
[ ] Test 3: Database Schema
[ ] Test 4: Encryption
[ ] Test 5: OAuth E2E
[ ] Test 6: Token Retrieval
[ ] Test 7: Checkout Integration
[ ] Test 8: Token Refresh
[ ] Test 9: Worker Validation
[ ] Test 10: Distributed Lock
[ ] Security Audit

Issues Found:
_______________________________
_______________________________

Overall Status: PASS / FAIL
Notes:
_______________________________
```

---

**Ready for Production:** [ ] YES / [ ] NO  
**Deployment Date:** ****\_\_\_****

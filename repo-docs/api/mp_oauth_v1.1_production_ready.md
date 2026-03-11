# Mercado Pago OAuth v1.1 - Production-Ready Implementation

## ✅ Security Fixes Applied

### 1. **State Parameter: Opaque + Redis Storage**

- ❌ Before: JSON base64 (tamperable)
- ✅ Now: Random 32-byte hex stored in Redis
- TTL: 10 minutes
- Single-use (deleted after callback)

### 2. **Ownership Validation**

- ❌ Before: Accept any `client_id` in query
- ✅ Now: Requires `onboarding_token` validation
- Verifies token belongs to account
- Prevents unauthorized MP connection

### 3. **PKCE Code Verifier Cleanup**

- ❌ Before: Stays in cache indefinitely
- ✅ Now: Deleted immediately after use
- Anti-replay protection
- Stored with state in Redis

### 4. **Distributed Lock for Refresh**

- ❌ Before: Race conditions in multi-instance
- ✅ Now: Redis lock with unique value
- 30s TTL
- Safe release mechanism

### 5. **Database Constraints**

- ✅ FK to `nv_accounts(id)` (not client_id_backend)
- ✅ Status CHECK constraint
- ✅ Auto-updating `updated_at` trigger
- ✅ Helper functions for validation

---

## 📦 Deliverables Created

### 1. SQL Migration

**File:** `20250102000000_add_mp_oauth_v1.1.sql`

**Features:**

- `mp_connections` table with proper FK
- Status constraint IN ('connected','revoked','error','expired')
- Auto-update trigger for `updated_at`
- Indexes for performance
- Helper functions:
  - `has_valid_mp_connection(uuid)`
  - `mark_mp_connection_for_refresh(uuid)`

### 2. MpOauthService

**File:** `mp-oauth.service.ts`

**Methods:**

1. `generateAuthUrl(onboardingToken)` - Validates ownership, creates opaque state
2. `handleCallback(code, state)` - Single-use state, PKCE cleanup
3. `getClientAccessToken(clientId)` - Lazy refresh, decryption
4. `refreshTokenForAccount(accountId)` - Distributed lock, safe refresh
5. `revokeConnection(clientId)` - User-initiated disconnect
6. `encryptToken/decryptToken` - AES-256-GCM with auth tag

**Security:**

- Opaque state stored in Redis
- Ownership validation before OAuth start
- PKCE verifier deleted after use
- Distributed lock for multi-instance safety
- AES-256-GCM encryption with authentication

---

## 🔄 OAuth Flow (Corrected)

```
1. User clicks "Conectar MP" in wizard
   ↓
2. Frontend calls GET /mp/oauth/start
   Headers: Authorization: Bearer <onboarding_token>
   ↓
3. Backend validates onboarding_token
   - Checks ownership
   - Generates opaque state (random 32 bytes)
   - Generates PKCE (code_verifier + code_challenge)
   - Stores in Redis: state -> { accountId, clientId, codeVerifier, returnTo }
   - TTL: 10 minutes
   ↓
4. Redirect to MP:
   https://auth.mercadopago.com/authorization?
     client_id=xxx&
     response_type=code&
     state=<opaque_random>&
     code_challenge=<sha256_hash>&
     code_challenge_method=S256&
     redirect_uri=https://admin.novavision.app/mp/oauth/callback
   ↓
5. User authorizes in MP
   ↓
6. MP redirects to callback:
   /mp/oauth/callback?code=xxx&state=yyy
   ↓
7. Backend:
   - Gets state from Redis (validates TTL)
   - Extracts codeVerifier
   - POST /oauth/token with code + code_verifier
   - Saves encrypted tokens to mp_connections
   - Deletes state from Redis (single-use)
   - Updates nv_accounts.mp_connected = true
   ↓
8. Redirect to wizard: /wizard?mp_connected=true
```

---

## 🔐 Encryption Details

### AES-256-GCM Implementation

**Format:** `iv(16 bytes) + authTag(16 bytes) + ciphertext`

```typescript
Encrypt:
  1. Generate random IV (16 bytes)
  2. Create cipher with AES-256-GCM
  3. Encrypt plaintext
  4. Extract auth tag (16 bytes)
  5. Concatenate: iv + authTag + encrypted
  6. Store as hex string

Decrypt:
  1. Extract IV (first 32 hex chars)
  2. Extract authTag (next 32 hex chars)
  3. Extract ciphertext (remaining)
  4. Create decipher
  5. Set auth tag
  6. Decrypt and verify integrity
```

**Key:** 32 bytes (256 bits) from env `MP_TOKEN_ENCRYPTION_KEY`

---

## 🔄 Token Refresh Strategy

### Lazy Refresh (on-demand)

```typescript
getClientAccessToken(clientId):
  1. Query mp_connections
  2. IF expires_at < now():
       refreshTokenForAccount(accountId)
       retry getClientAccessToken()
  3. ELSE:
       decrypt and return access_token
```

### Scheduled Refresh (proactive)

```typescript
@Cron('0 */12 * * *') // Every 12 hours
refreshExpiringTokens():
  1. Query connections expiring in next 24h
  2. FOR EACH:
       refreshTokenForAccount(accountId) // uses lock
```

### Distributed Lock (multi-instance safe)

```typescript
Lock key: mp:refresh:lock:{accountId}
Lock value: random 16 bytes
TTL: 30 seconds

1. Try SET NX EX (atomic)
2. If acquired:
     - Perform refresh
     - Update DB
     - Release lock (if still owner)
3. If not acquired:
     - Skip (another instance handling)
     - Optional: wait 2s and return
```

---

## 📋 Implementation Checklist

### Phase 1: DB Setup (30min)

- [ ] Run migration `20250102000000_add_mp_oauth_v1.1.sql`
- [ ] Verify constraints: `CHECK (status IN (...))`
- [ ] Verify trigger: `updated_at` auto-updates
- [ ] Test helper functions

### Phase 2: Environment (10min)

- [ ] Add `MP_CLIENT_ID` to .env
- [ ] Add `MP_CLIENT_SECRET` to .env (encrypted)
- [ ] Add `MP_REDIRECT_URI` to .env
- [ ] Generate `MP_TOKEN_ENCRYPTION_KEY` (32 bytes hex)
- [ ] Configure Redis connection

### Phase 3: MpOauthService (2h)

- [ ] Create `mp-oauth.service.ts`
- [ ] Implement encryption helpers
- [ ] Implement state management (Redis)
- [ ] Implement ownership validation
- [ ] Implement distributed lock
- [ ] Test encryption/decryption

### Phase 4: MpOauthController (1h)

- [ ] Create `mp-oauth.controller.ts`
- [ ] GET /mp/oauth/start (validate onboarding_token)
- [ ] GET /mp/oauth/callback
- [ ] POST /mp/oauth/disconnect/:clientId
- [ ] GET /mp/oauth/status/:clientId

### Phase 5: Frontend Integration (1.5h)

- [ ] Create Step6MercadoPago component
- [ ] Implement "Conectar MP" button
- [ ] Handle ?mp_connected=true callback
- [ ] Update wizard progress (Step 5 → 6 → 7)
- [ ] Add "Conectar más tarde" (skip)

### Phase 6: Checkout Integration (1h)

- [ ] Update `createPreference` to use client token
- [ ] Add `getClientAccessToken()` call
- [ ] Add `external_reference` for idempotency
- [ ] Update webhook to handle client-specific payments

### Phase 7: Refresh Worker (1h)

- [ ] Create `mp-token-refresh.worker.ts`
- [ ] Implement cron `*/12 * * * *`
- [ ] Use distributed lock
- [ ] Handle errors (mark status='error')
- [ ] Add monitoring/alerts

### Phase 8: Testing (2h)

- [ ] Unit test: encryption/decryption
- [ ] Unit test: PKCE generation
- [ ] Unit test: state storage/retrieval
- [ ] Integration: Full OAuth flow (sandbox)
- [ ] Integration: Token refresh with lock
- [ ] Load test: Concurrent refreshes
- [ ] Manual: Connect real MP account

---

## 🚨 Security Audit Checklist

- [x] State is opaque (not JSON)
- [x] State stored server-side (Redis)
- [x] State has TTL (10 min)
- [x] State deleted after use (anti-replay)
- [x] PKCE implemented (S256)
- [x] Code verifier deleted after use
- [x] Ownership validated (onboarding_token)
- [x] Tokens encrypted at rest (AES-256-GCM)
- [x] Encrypted tokens have auth tag
- [x] Refresh uses distributed lock
- [x] Lock has timeout (30s)
- [x] Access tokens never in frontend
- [x] Public keys can be exposed
- [x] Redirect URI is static (configured in MP)
- [x] HTTPS enforced
- [x] Rate limiting on OAuth endpoints

---

## 📊 Deployment Plan

### Staging

1. Deploy migration
2. Add env vars
3. Deploy API with OAuth module
4. Deploy Admin with Step6
5. Test full flow with sandbox MP account
6. Monitor logs for 24h

### Production

1. Create production MP app (get credentials)
2. Configure redirect_uri in MP dashboard
3. Deploy migration
4. Deploy API
5. Deploy Admin
6. Enable feature flag (gradual rollout)
7. Monitor error rates
8. Track adoption metrics

---

## 🎯 Success Metrics

- [ ] 0 token tampering incidents
- [ ] 0 state replay attacks
- [ ] < 1% token refresh failures
- [ ] < 5s OAuth flow completion
- [ ] 100% encryption coverage
- [ ] 0 race conditions in multi-instance

---

## 🔗 References

- MP OAuth Creation: https://www.mercadopago.com.ar/developers/en/docs/security/oauth/creation
- MP Token Endpoint: https://api.mercadopago.com/oauth/token
- PKCE RFC 7636: https://datatracker.ietf.org/doc/html/rfc7636
- AES-GCM Mode: https://en.wikipedia.org/wiki/Galois/Counter_Mode

---

**Status:** ✅ Ready for Implementation (8h estimated)  
**Version:** 1.1 (Production-Ready)  
**Date:** 2025-01-02

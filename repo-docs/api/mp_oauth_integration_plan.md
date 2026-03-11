# Plan de Implementación: Mercado Pago OAuth Multi-Tenant

## 🎯 Objetivo

Permitir que cada cliente de NovaVision conecte **su propia cuenta de Mercado Pago** vía OAuth, almacenando credenciales por vendedor y habilitando checkout con tokens del cliente conectado (no credenciales compartidas).

---

## 📋 Contexto Actual

**Estado Actual:**

- Sistema multi-tenant funcional
- Onboarding wizard (5 pasos)
- Payment flow con MP (usando credenciales únicas de plataforma)
- IdentityModal post-payment integrado

**Problema:**

- Todos los clientes usan las mismas credenciales MP de la plataforma
- No hay aislamiento de payments por vendedor
- Cliente no puede gestionar sus propios pagos en MP dashboard

**Solución:**

- OAuth 2.0 + PKCE con Mercado Pago
- Credenciales por cliente (multi-vendor)
- Refresh automático de tokens

---

## 🏗️ Arquitectura Propuesta

```
┌────────────────────────────────────────────┐
│  ONBOARDING WIZARD                         │
│  Paso 6 (nuevo): Conectar Mercado Pago    │
└──────────────┬─────────────────────────────┘
               │
          Click "Conectar MP"
               │
               ↓
┌────────────────────────────────────────────┐
│  OAUTH FLOW (Server-Side)                  │
│  GET /mp/oauth/start                       │
│    → Genera state + PKCE                   │
│    → Redirect a MP authorization           │
└──────────────┬─────────────────────────────┘
               │
        MP Login/Authorize
               │
               ↓
┌────────────────────────────────────────────┐
│  CALLBACK                                  │
│  GET /mp/oauth/callback?code=...           │
│    → Valida state                          │
│    → Canjea code por tokens (server-side)  │
│    → Guarda en mp_connections              │
└──────────────┬─────────────────────────────┘
               │
               ↓
┌────────────────────────────────────────────┐
│  CLIENT CHECKOUT                           │
│  Usa access_token del cliente conectado    │
│  Crea preferencia con credenciales vendor  │
└────────────────────────────────────────────┘
```

---

## 💾 Database Schema

### Nueva Tabla: `mp_connections` (Admin DB)

```sql
CREATE TABLE mp_connections (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Client reference
  client_id uuid NOT NULL REFERENCES nv_accounts(client_id_backend),

  -- MP OAuth tokens (encrypted at rest)
  access_token text NOT NULL,
  public_key text,
  refresh_token text NOT NULL,

  -- MP metadata
  mp_user_id text,
  live_mode boolean DEFAULT false,
  expires_at timestamptz NOT NULL,

  -- Status tracking
  status text NOT NULL DEFAULT 'connected', -- connected | revoked | error | expired
  last_error text,
  last_refresh_at timestamptz,

  -- Audit
  connected_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),

  CONSTRAINT unique_client_mp UNIQUE(client_id)
);

-- RLS Policy
ALTER TABLE mp_connections ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_role_only" ON mp_connections
  FOR ALL USING (auth.role() = 'service_role');

-- Index for lookups
CREATE INDEX idx_mp_connections_client ON mp_connections(client_id);
CREATE INDEX idx_mp_connections_expires ON mp_connections(expires_at) WHERE status = 'connected';
```

### Modificar Tabla: `nv_accounts`

```sql
ALTER TABLE nv_accounts
  ADD COLUMN mp_connected boolean DEFAULT false,
  ADD COLUMN mp_user_id text,
  ADD COLUMN mp_connected_at timestamptz;

-- Index
CREATE INDEX idx_accounts_mp_connected ON nv_accounts(mp_connected) WHERE mp_connected = true;
```

### Modificar Tabla: `nv_onboarding`

```sql
ALTER TABLE nv_onboarding
  ADD COLUMN mp_connection_status text DEFAULT 'pending'; -- pending | connected | error
```

---

## 🔐 Environment Variables

```bash
# apps/api/.env

# Mercado Pago OAuth App Credentials
MP_CLIENT_ID=your_app_client_id
MP_CLIENT_SECRET=your_app_client_secret_encrypted
MP_REDIRECT_URI=https://admin.novavision.app/mp/oauth/callback

# Encryption for tokens at rest
MP_TOKEN_ENCRYPTION_KEY=random_32_byte_key_here
```

---

## 🛠️ Implementation Plan

### Phase 1: Database Setup (30min)

**Files to Create:**

- `apps/api/migrations/admin/20250102000000_add_mp_oauth.sql`

**Implementation:**

```sql
-- Create mp_connections table
-- Add columns to nv_accounts
-- Add RLS policies
-- Create indexes
```

### Phase 2: OAuth Module (NestJS) (2h)

**Files to Create:**

1. `apps/api/src/mp-oauth/mp-oauth.module.ts`
2. `apps/api/src/mp-oauth/mp-oauth.service.ts`
3. `apps/api/src/mp-oauth/mp-oauth.controller.ts`
4. `apps/api/src/mp-oauth/dto/mp-tokens.dto.ts`

**MpOauthService Methods:**

```typescript
// apps/api/src/mp-oauth/mp-oauth.service.ts

@Injectable()
export class MpOauthService {
  /**
   * Generate OAuth authorization URL with PKCE
   */
  generateAuthUrl(clientId: string): {
    authUrl: string;
    state: string;
    codeVerifier: string;
  } {
    const state = this.generateSecureState(clientId);
    const { codeVerifier, codeChallenge } = this.generatePKCE();

    const params = new URLSearchParams({
      client_id: process.env.MP_CLIENT_ID,
      response_type: "code",
      redirect_uri: process.env.MP_REDIRECT_URI,
      state,
      code_challenge: codeChallenge,
      code_challenge_method: "S256",
    });

    return {
      authUrl: `https://auth.mercadopago.com/authorization?${params}`,
      state,
      codeVerifier,
    };
  }

  /**
   * Exchange authorization code for tokens
   */
  async exchangeCodeForTokens(
    code: string,
    codeVerifier: string
  ): Promise<MpTokensDto> {
    const body = new URLSearchParams({
      grant_type: "authorization_code",
      client_secret: process.env.MP_CLIENT_SECRET,
      code,
      code_verifier: codeVerifier,
      redirect_uri: process.env.MP_REDIRECT_URI,
    });

    const { data } = await axios.post(
      "https://api.mercadopago.com/oauth/token",
      body.toString(),
      {
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
      }
    );

    return {
      access_token: data.access_token,
      public_key: data.public_key,
      refresh_token: data.refresh_token,
      expires_in: data.expires_in,
      user_id: data.user_id,
      live_mode: data.live_mode,
    };
  }

  /**
   * Save MP connection to database (encrypted)
   */
  async saveConnection(clientId: string, tokens: MpTokensDto): Promise<void> {
    const expiresAt = new Date(Date.now() + tokens.expires_in * 1000);

    const { error } = await this.adminClient.from("mp_connections").upsert({
      client_id: clientId,
      access_token: this.encryptToken(tokens.access_token),
      public_key: tokens.public_key,
      refresh_token: this.encryptToken(tokens.refresh_token),
      mp_user_id: tokens.user_id,
      live_mode: tokens.live_mode,
      expires_at: expiresAt.toISOString(),
      status: "connected",
      connected_at: new Date().toISOString(),
    });

    if (error) throw new Error("Failed to save MP connection");

    // Update nv_accounts
    await this.adminClient
      .from("nv_accounts")
      .update({
        mp_connected: true,
        mp_user_id: tokens.user_id,
        mp_connected_at: new Date().toISOString(),
      })
      .eq("client_id_backend", clientId);
  }

  /**
   * Get decrypted access token for client
   */
  async getClientAccessToken(clientId: string): Promise<string> {
    const { data, error } = await this.adminClient
      .from("mp_connections")
      .select("access_token, expires_at, status")
      .eq("client_id", clientId)
      .eq("status", "connected")
      .single();

    if (error || !data) {
      throw new NotFoundException("MP connection not found");
    }

    // Check if expired
    if (new Date(data.expires_at) < new Date()) {
      await this.refreshTokenForClient(clientId);
      return this.getClientAccessToken(clientId); // Retry after refresh
    }

    return this.decryptToken(data.access_token);
  }

  /**
   * Refresh access token using refresh_token
   */
  async refreshTokenForClient(clientId: string): Promise<void> {
    const { data: connection } = await this.adminClient
      .from("mp_connections")
      .select("refresh_token")
      .eq("client_id", clientId)
      .single();

    if (!connection) throw new Error("Connection not found");

    const refreshToken = this.decryptToken(connection.refresh_token);

    const body = new URLSearchParams({
      grant_type: "refresh_token",
      client_id: process.env.MP_CLIENT_ID,
      client_secret: process.env.MP_CLIENT_SECRET,
      refresh_token: refreshToken,
    });

    const { data } = await axios.post(
      "https://api.mercadopago.com/oauth/token",
      body.toString()
    );

    const expiresAt = new Date(Date.now() + data.expires_in * 1000);

    await this.adminClient
      .from("mp_connections")
      .update({
        access_token: this.encryptToken(data.access_token),
        refresh_token: this.encryptToken(data.refresh_token),
        expires_at: expiresAt.toISOString(),
        last_refresh_at: new Date().toISOString(),
      })
      .eq("client_id", clientId);
  }

  // Helper methods
  private generateSecureState(clientId: string): string {
    const random = crypto.randomBytes(16).toString("hex");
    return Buffer.from(JSON.stringify({ clientId, random })).toString(
      "base64url"
    );
  }

  private parseState(state: string): { clientId: string } {
    return JSON.parse(Buffer.from(state, "base64url").toString());
  }

  private generatePKCE() {
    const codeVerifier = crypto.randomBytes(32).toString("base64url");
    const codeChallenge = crypto
      .createHash("sha256")
      .update(codeVerifier)
      .digest("base64url");
    return { codeVerifier, codeChallenge };
  }

  private encryptToken(token: string): string {
    // Use AES-256-GCM with MP_TOKEN_ENCRYPTION_KEY
    // Implementation details...
  }

  private decryptToken(encrypted: string): string {
    // Decrypt using same key
    // Implementation details...
  }
}
```

**MpOauthController Endpoints:**

```typescript
// apps/api/src/mp-oauth/mp-oauth.controller.ts

@Controller("mp/oauth")
export class MpOauthController {
  /**
   * GET /mp/oauth/start?client_id=xxx
   *
   * Initiate OAuth flow
   */
  @Get("start")
  async start(@Query("client_id") clientId: string, @Res() res: Response) {
    const { authUrl, state, codeVerifier } =
      await this.mpOauthService.generateAuthUrl(clientId);

    // Store codeVerifier temporarily (Redis or session)
    await this.cacheService.set(`pkce:${state}`, codeVerifier, 600);

    res.redirect(authUrl);
  }

  /**
   * GET /mp/oauth/callback?code=xxx&state=yyy
   *
   * Handle OAuth callback from Mercado Pago
   */
  @Get("callback")
  async callback(
    @Query("code") code: string,
    @Query("state") state: string,
    @Res() res: Response
  ) {
    // 1. Validate state
    const { clientId } = this.mpOauthService.parseState(state);

    // 2. Get code_verifier from cache
    const codeVerifier = await this.cacheService.get(`pkce:${state}`);
    if (!codeVerifier) {
      throw new BadRequestException("Invalid or expired state");
    }

    // 3. Exchange code for tokens
    const tokens = await this.mpOauthService.exchangeCodeForTokens(
      code,
      codeVerifier
    );

    // 4. Save to database
    await this.mpOauthService.saveConnection(clientId, tokens);

    // 5. Update onboarding status
    await this.onboardingService.updateMpStatus(clientId, "connected");

    // 6. Redirect to wizard success
    res.redirect("/wizard?mp_connected=true");
  }

  /**
   * GET /mp/oauth/status/:clientId
   *
   * Check MP connection status
   */
  @Get("status/:clientId")
  async getStatus(@Param("clientId") clientId: string) {
    const connection = await this.mpOauthService.getConnection(clientId);

    return {
      connected: !!connection,
      live_mode: connection?.live_mode,
      expires_at: connection?.expires_at,
      status: connection?.status,
    };
  }

  /**
   * POST /mp/oauth/disconnect/:clientId
   *
   * Revoke MP connection
   */
  @Post("disconnect/:clientId")
  async disconnect(@Param("clientId") clientId: string) {
    await this.mpOauthService.revokeConnection(clientId);
    return { success: true };
  }
}
```

---

### Phase 3: Frontend Integration (1.5h)

**Files to Modify:**

1. `apps/admin/src/pages/BuilderWizard/index.tsx`
2. `apps/admin/src/pages/BuilderWizard/steps/Step6MercadoPago.tsx` (NEW)

**Step6MercadoPago Component:**

```typescript
// apps/admin/src/pages/BuilderWizard/steps/Step6MercadoPago.tsx

export function Step6MercadoPago({ onNext }: { onNext: () => void }) {
  const { state } = useWizard();
  const [mpStatus, setMpStatus] = useState<"pending" | "connected" | "error">(
    "pending"
  );

  const handleConnect = () => {
    // Redirect to OAuth start
    window.location.href = `/api/mp/oauth/start?client_id=${state.clientId}`;
  };

  useEffect(() => {
    // Check if we returned from OAuth callback
    const params = new URLSearchParams(window.location.search);
    if (params.get("mp_connected") === "true") {
      setMpStatus("connected");
    }
  }, []);

  return (
    <div className="step-container">
      <div className="step-header">
        <h1>💳 Conectar Mercado Pago</h1>
        <p>Conectá tu cuenta para recibir pagos</p>
      </div>

      {mpStatus === "pending" && (
        <>
          <div className="mp-info">
            <h3>¿Por qué conectar Mercado Pago?</h3>
            <ul>
              <li>✅ Recibí pagos directamente en tu cuenta</li>
              <li>✅ Gestioná tus ventas desde MP</li>
              <li>✅ Sin comisiones adicionales de NovaVision</li>
            </ul>
          </div>

          <button onClick={handleConnect} className="btn-primary btn-mp">
            <img src="/mp-logo.svg" alt="MP" />
            Conectar con Mercado Pago
          </button>

          <button onClick={onNext} className="btn-secondary">
            Conectar más tarde
          </button>
        </>
      )}

      {mpStatus === "connected" && (
        <>
          <div className="success-message">
            <div className="success-icon">✅</div>
            <h2>¡Mercado Pago Conectado!</h2>
            <p>Ya podés recibir pagos en tu tienda</p>
          </div>

          <button onClick={onNext} className="btn-primary">
            Continuar →
          </button>
        </>
      )}
    </div>
  );
}
```

**Update BuilderWizard:**

```typescript
// apps/admin/src/pages/BuilderWizard/index.tsx

// Add Step 6 (MP Connect) between Step 5 (Payment) and Final
{
  currentStep === 6 && (
    <Step6MercadoPago onNext={() => updateState({ currentStep: 7 })} />
  );
}
```

---

### Phase 4: Checkout Integration (1h)

**Files to Modify:**

1. `apps/api/src/checkout/checkout.service.ts`

**Update createPreference to use client's MP tokens:**

```typescript
// apps/api/src/checkout/checkout.service.ts

async createPreference(clientId: string, items: CartItem[]) {
  // Get client's MP access token (decrypted)
  const accessToken = await this.mpOauthService.getClientAccessToken(clientId);

  // Create preference using CLIENT's credentials
  const { data } = await axios.post(
    'https://api.mercadopago.com/checkout/preferences',
    {
      items: items.map(item => ({
        title: item.name,
        quantity: item.quantity,
        unit_price: item.price,
      })),
      back_urls: {
        success: `https://${clientSlug}.novavision.app/success`,
        failure: `https://${clientSlug}.novavision.app/failure`,
      },
      notification_url: `https://api.novavision.app/webhooks/mp/${clientId}`,
    },
    {
      headers: {
        'Authorization': `Bearer ${accessToken}`,
        'Content-Type': 'application/json',
      },
    },
  );

  return {
    init_point: data.init_point,
    preference_id: data.id,
  };
}
```

---

### Phase 5: Token Refresh Worker (1h)

**Files to Create:**

- `apps/api/src/workers/mp-token-refresh.worker.ts`

**Cron Job (runs every 12h):**

```typescript
// apps/api/src/workers/mp-token-refresh.worker.ts

@Injectable()
export class MpTokenRefreshWorker {
  @Cron("0 */12 * * *") // Every 12 hours
  async refreshExpiringTokens() {
    const threshold = new Date(Date.now() + 24 * 60 * 60 * 1000); // 24h ahead

    const { data: connections } = await this.adminClient
      .from("mp_connections")
      .select("client_id, expires_at")
      .eq("status", "connected")
      .lt("expires_at", threshold.toISOString());

    for (const conn of connections || []) {
      try {
        await this.mpOauthService.refreshTokenForClient(conn.client_id);
        this.logger.log(`Refreshed MP token for client ${conn.client_id}`);
      } catch (error) {
        this.logger.error(
          `Failed to refresh token for ${conn.client_id}`,
          error
        );

        // Mark as error and notify client
        await this.adminClient
          .from("mp_connections")
          .update({ status: "error", last_error: error.message })
          .eq("client_id", conn.client_id);
      }
    }
  }
}
```

---

## 🔒 Security Checklist

- [ ] **Never expose `access_token` in frontend**
- [ ] **Encrypt tokens at rest** (AES-256-GCM)
- [ ] **Use PKCE** (code_challenge + code_verifier)
- [ ] **Validate `state` parameter** (anti-CSRF)
- [ ] **Store `code_verifier` server-side** (Redis/session, NOT localStorage)
- [ ] **HTTPS only** for redirect_uri
- [ ] **Static redirect_uri** configured in MP app
- [ ] **Use `state` to pass client_id** (not in query param)
- [ ] **Implement token refresh** before expiration
- [ ] **Handle revocation** (MP can revoke tokens)
- [ ] **Rate limit** OAuth endpoints

---

## 📊 Migration Strategy

### Step 1: Existing Clients (Backward Compat)

- Keep platform MP credentials as fallback
- Add banner: "Conectá tu Mercado Pago para gestionar tus pagos"
- gradual migration (no force)

### Step 2: New Clients

- Make MP OAuth **mandatory** in onboarding (Step 6)
- Block final publish if not connected

### Step 3: Deprecation

- After 90 days, notify clients still using platform credentials
- Disable platform credentials after 180 days

---

## 🧪 Testing Plan

### Unit Tests

```typescript
describe("MpOauthService", () => {
  it("should generate valid PKCE challenge");
  it("should exchange code for tokens");
  it("should encrypt/decrypt tokens");
  it("should refresh expired tokens");
});
```

### Integration Tests

```typescript
describe("MP OAuth Flow E2E", () => {
  it("should complete full OAuth flow");
  it("should save connection to database");
  it("should create checkout with client token");
  it("should handle token refresh automatically");
});
```

### Manual QA

1. Connect MP account (sandbox)
2. Verify tokens saved encrypted
3. Create test checkout
4. Verify payment goes to client's MP account
5. Wait for token expiry → verify auto-refresh

---

## 📅 Timeline

| Phase             | Tasks                   | Estimate    |
| ----------------- | ----------------------- | ----------- |
| 1. DB Setup       | Migration + RLS         | 30min       |
| 2. OAuth Module   | Service + Controller    | 2h          |
| 3. Frontend       | Step6 Component         | 1.5h        |
| 4. Checkout       | Update createPreference | 1h          |
| 5. Refresh Worker | Cron job                | 1h          |
| 6. Testing        | Unit + Integration      | 2h          |
| **Total**         |                         | **8 hours** |

---

## 🚀 Deployment Checklist

- [ ] Create MP Developer App (get client_id/secret)
- [ ] Configure redirect_uri in MP app settings
- [ ] Add env vars to production
- [ ] Run migration (mp_connections table)
- [ ] Deploy API with OAuth module
- [ ] Deploy Admin with Step6
- [ ] Test in sandbox environment
- [ ] Monitor refresh worker logs
- [ ] Update documentation

---

## 📞 Next Steps

1. **Approve Plan** and estimates
2. **Create MP Developer App** (get credentials)
3. **Run DB Migration** (staging first)
4. **Implement OAuth Module** (Phase 2)
5. **Test E2E** with sandbox account
6. **Deploy to Production**

**Ready to start implementation?** 🚀

# SMTP Diagnostic Tools

This document describes the SMTP diagnostic tools added to help identify and resolve email sending issues, particularly timeout errors commonly caused by platform network restrictions.

## Problem Background

Many PaaS platforms (Railway, Render, Vercel, etc.) block outbound SMTP connections on standard ports (25, 465, 587) for security reasons. This causes connection timeout errors when trying to send emails via traditional SMTP.

## Diagnostic Tools

### 1. Diagnostic Script (`npm run diagnose:smtp`)

Comprehensive SMTP diagnostics that run inside the container/deployment environment:

```bash
npm run diagnose:smtp
```

**What it tests:**
- DNS resolution for SMTP host
- TCP connection attempts on ports 587 and 465
- TLS handshake on port 587
- Nodemailer verify() and sendMail() with actual credentials

**Environment Variables:**
- `SMTP_HOST` or `SUPABASE_SMTP_HOST` - SMTP server hostname (default: smtp.gmail.com)
- `SMTP_PORT` or `SUPABASE_SMTP_PORT` - SMTP port (default: 587)
- `SUPABASE_SMTP_USER` or `SMTP_USER` - SMTP username
- `SUPABASE_SMTP_PASS` or `SMTP_PASS` - SMTP password
- `SMTP_TEST_TO` - Recipient email for test (defaults to SMTP user)
- `SMTP_TIMEOUT_MS` - Timeout in milliseconds (default: 8000)

**Example Output:**
```
[diag] HOST=smtp.gmail.com
[diag] PORT=587
[diag] USER_SET=true
[diag] PASS_SET=true
[diag] DNS_A=[{"address":"142.250.185.109","family":4}]
[diag] TCP_CONNECT_587={"ok":false,"err":"timeout","elapsed":8005}
[diag] TCP_CONNECT_465={"ok":false,"err":"timeout","elapsed":8004}
```

**Interpretation:**
- `TCP_CONNECT_* ok:false err:"timeout"` → Platform blocks SMTP ports (egress blocked)
- `TCP_CONNECT_* ok:true` → Network allows SMTP
- `NODEMAILER_ERROR` with 535/auth → Credentials issue
- `DNS_ERROR` → DNS resolution problem

### 2. Enhanced Service Logging

The `MercadoPagoService.sendEmail()` method now logs:

**At startup:**
```
[env] platform flags {
  vercel: false,
  railway: true,
  render: false,
  nodeEnv: "production"
}
```

**For each email attempt:**
```
[sendEmail] SMTP Candidates smtp.gmail.com:587 (secure=false, requireTLS=true), smtp.gmail.com:465 (secure=true)
[sendEmail] Effective SMTP opts {
  host: "smtp.gmail.com",
  port: 587,
  secure: false,
  requireTLS: true,
  timeoutMs: 15000,
  authUserSet: true
}
[sendEmail] Falló smtp.gmail.com:587 (secure=false, requireTLS=true): Connection timeout
```

### 3. Debug Endpoint (Development/Testing)

**Endpoint:** `GET /mercadopago/debug/smtp?to=email@example.com`

**Security:**
- Only enabled in non-production environments
- In production, requires `X-Debug-Token` header matching `DEBUG_TOKEN` env var

**Response:**
```json
{
  "status": "ready",
  "config": {
    "host": "smtp.gmail.com",
    "port": 587,
    "userSet": true,
    "passSet": true,
    "recipient": "test@example.com",
    "timeout": 15000
  },
  "instructions": [
    "To run full diagnostic, use: npm run diagnose:smtp",
    "To test actual sending, trigger a real order confirmation",
    "Check logs for [sendEmail] entries with detailed SMTP candidate info"
  ]
}
```

## Configuration Options

### SMTP_URL Override (Quick Testing)

For quick testing with alternative providers, set `SMTP_URL`:

```bash
# Mailgun example
SMTP_URL="smtp://username:password@smtp.mailgun.org:587"

# Gmail with SSL
SMTP_URL="smtps://username:password@smtp.gmail.com:465"
```

This bypasses the candidate selection logic and uses exactly what you specify.

### Alternative Port for Blocked Environments

Some providers offer alternative ports that may not be blocked:

**Port 2525** (supported by Mailgun, SendGrid, Postmark, Brevo):
```bash
SMTP_HOST=smtp.mailgun.org
SMTP_PORT=2525
SMTP_USER=your-user
SMTP_PASS=your-pass
```

### Gmail Configuration

**For Gmail personal accounts:**
1. Enable 2FA on your Google account
2. Generate an App Password at https://myaccount.google.com/apppasswords
3. Use the app password (16 characters without spaces) as `SUPABASE_SMTP_PASS`

```bash
SUPABASE_SMTP_HOST=smtp.gmail.com
SUPABASE_SMTP_PORT=587
SUPABASE_SMTP_USER=your-email@gmail.com
SUPABASE_SMTP_PASS=your-app-password
```

## Troubleshooting Steps

### 1. Run Diagnostic Inside Container

```bash
# On your platform (Railway, Render, etc.)
npm run diagnose:smtp
```

Check the output:

**If TCP connections timeout:**
- Your platform blocks SMTP ports
- **Solution:** Use HTTP-based email service (SendGrid, Mailgun, Postmark API)
- **Alternative:** Try port 2525 with a provider that supports it

**If connections succeed but auth fails:**
- Check credentials
- For Gmail, ensure you're using an App Password (not your account password)
- For smtp-relay.gmail.com, verify IP/domain allowlist in Google Admin Console

**If DNS fails:**
- Network/DNS issue
- Check if SMTP_HOST is correct

### 2. Check Platform-Specific Restrictions

The service logs platform flags at startup. Common restrictions:

- **Railway:** Blocks 25, 465, 587 by default
- **Render:** Blocks outbound SMTP
- **Vercel:** Serverless, egress firewalled
- **Fly.io:** Generally allows SMTP

**Recommended:** Use HTTP-based email APIs in production

### 3. Migration to HTTP Email Provider (Recommended)

For production reliability, migrate to HTTP-based providers:

**SendGrid:**
```typescript
// Install: npm install @sendgrid/mail
import sgMail from '@sendgrid/mail';
sgMail.setApiKey(process.env.SENDGRID_API_KEY);
await sgMail.send({
  to,
  from: 'noreply@yourdomain.com',
  subject,
  html: content,
});
```

**Postmark:**
```typescript
// Install: npm install postmark
import postmark from 'postmark';
const client = new postmark.ServerClient(process.env.POSTMARK_API_KEY);
await client.sendEmail({
  From: 'noreply@yourdomain.com',
  To: to,
  Subject: subject,
  HtmlBody: content,
});
```

## Environment Variables Reference

| Variable | Description | Default |
|----------|-------------|---------|
| `SMTP_HOST` | SMTP server hostname | smtp.gmail.com |
| `SMTP_PORT` | SMTP port | 587 |
| `SMTP_USER` | SMTP username | - |
| `SMTP_PASS` | SMTP password | - |
| `SUPABASE_SMTP_HOST` | Alternative SMTP host | - |
| `SUPABASE_SMTP_PORT` | Alternative SMTP port | - |
| `SUPABASE_SMTP_USER` | Alternative SMTP user | - |
| `SUPABASE_SMTP_PASS` | Alternative SMTP pass | - |
| `SMTP_URL` | Full SMTP URL (overrides all) | - |
| `SMTP_TIMEOUT_MS` | Connection timeout | 15000 |
| `SMTP_POOL` | Use connection pooling | false |
| `SMTP_DEBUG` | Enable nodemailer debug logs | false |
| `SMTP_REJECT_UNAUTHORIZED` | Verify TLS certificates | true |
| `MAIL_FROM` | From address | Template NovaVision |
| `SMTP_TEST_TO` | Test email recipient | SMTP_USER |
| `DEBUG_TOKEN` | Token for debug endpoint | - |

## Logs to Look For

Search your logs for these patterns:

```
# Platform detection
[env] platform flags

# SMTP attempt details
[sendEmail] SMTP Candidates
[sendEmail] Effective SMTP opts

# Failures
[sendEmail] Falló smtp.gmail.com:587
[sendEmail] Todos los intentos SMTP fallaron

# Success
Correo enviado a ... via smtp.gmail.com:587
```

## Next Steps

1. **Run diagnostic in your deployment environment**
2. **Check if TCP connections timeout** → Platform blocks SMTP
3. **If blocked:** Migrate to HTTP email API (SendGrid, Mailgun, Postmark)
4. **If not blocked but auth fails:** Fix credentials (use Gmail App Password)
5. **Monitor logs** with enhanced logging from `[sendEmail]` entries

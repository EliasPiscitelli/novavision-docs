# Quick Start: Email Configuration for Railway

This guide helps you quickly configure email delivery for NovaVision on Railway.

## TL;DR

Railway blocks SMTP ports. Use HTTP-based email instead:

```bash
# 1. Choose a provider (Postmark recommended)
EMAIL_PROVIDER=postmark
POSTMARK_API_KEY=your-api-key-here
MAIL_FROM="Your Store <noreply@yourdomain.com>"

# 2. Test it
curl -H "X-Debug-Token: your-token" \
  "https://your-app.railway.app/mercadopago/debug/email?to=test@email.com"
```

## Step-by-Step Setup

### 1. Sign up for Postmark (Recommended)

1. Go to https://postmarkapp.com/
2. Create account (100 emails/month free)
3. Create a new server
4. Get your **Server API Token**

### 2. Configure Railway Environment

In Railway dashboard → Your Project → Variables:

```bash
EMAIL_PROVIDER=postmark
POSTMARK_API_KEY=your-server-api-token-here
MAIL_FROM="Your Store Name <noreply@yourdomain.com>"
DEBUG_TOKEN=any-random-secret-string
```

**Optional:**
```bash
SMTP_TEST_TO=your-test-email@example.com
```

### 3. Test Configuration

```bash
# Replace with your values
curl -H "X-Debug-Token: your-debug-token" \
  "https://your-railway-app.railway.app/mercadopago/debug/email?to=your@email.com"
```

**Expected response:**
```json
{
  "ok": true,
  "message": "Test email sent successfully via postmark",
  "to": "your@email.com",
  "provider": "postmark",
  "platform": "Railway"
}
```

### 4. Verify Sender Domain (Production)

For production use, verify your domain in Postmark:

1. Go to Postmark → Sender Signatures
2. Add your domain (e.g., `yourdomain.com`)
3. Add DNS records (SPF, DKIM) as shown
4. Wait for verification (usually 5-10 minutes)
5. Update `MAIL_FROM` to use verified domain

## Alternative: SendGrid

If you prefer SendGrid:

```bash
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=SG.your-api-key-here
MAIL_FROM="Your Store <noreply@yourdomain.com>"
```

Get API key from: https://app.sendgrid.com/settings/api_keys

## Troubleshooting

### "Invalid signature" error
- Make sure `X-Debug-Token` header matches `DEBUG_TOKEN` env var

### "POSTMARK_API_KEY no está configurado"
- Check that env var is set in Railway dashboard
- Redeploy after adding env vars

### Email not received
1. Check spam/junk folder
2. Verify sender domain in provider dashboard
3. Use sandbox mode for testing (delivers to verified addresses only)

### Railway timeout errors with SMTP
- This is expected - Railway blocks SMTP ports
- Switch to `EMAIL_PROVIDER=postmark` or `sendgrid`

## More Information

- **Full documentation**: [docs/EMAIL_CONFIGURATION.md](./EMAIL_CONFIGURATION.md)
- **Validation script**: Run `npm run validate:email` locally
- **Environment examples**: See `.env.email.example`

## Need Help?

1. Run validation: `npm run validate:email`
2. Check logs in Railway: `railway logs`
3. Test with debug endpoint (see step 3 above)
4. Review full docs: `docs/EMAIL_CONFIGURATION.md`

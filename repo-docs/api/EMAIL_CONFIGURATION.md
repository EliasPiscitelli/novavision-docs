# Email Configuration Guide

## Overview

The NovaVision backend supports multiple email providers to ensure reliable email delivery across different hosting platforms.

## Supported Providers

### 1. **Postmark** (Recommended for Railway)
HTTP-based email service that works over HTTPS:443, bypassing SMTP port restrictions.

```bash
EMAIL_PROVIDER=postmark
POSTMARK_API_KEY=your-postmark-server-token
MAIL_FROM="NovaVision <noreply@yourdomain.com>"
```

- **Pros**: Fast, reliable, works on Railway, excellent deliverability
- **Cons**: Requires verified sender domain for production
- **Documentation**: https://postmarkapp.com/developer

### 2. **SendGrid** (Recommended for Railway)
HTTP-based email service via API, works over HTTPS:443.

```bash
EMAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=your-sendgrid-api-key
MAIL_FROM="NovaVision <noreply@yourdomain.com>"
```

- **Pros**: Popular, feature-rich, works on Railway, good free tier
- **Cons**: Requires sender verification
- **Documentation**: https://docs.sendgrid.com/api-reference/mail-send/mail-send

### 3. **SMTP** (Default - for local development)
Traditional SMTP protocol. **Note**: Railway blocks SMTP ports (25, 465, 587).

```bash
EMAIL_PROVIDER=smtp
SUPABASE_SMTP_HOST=smtp.gmail.com
SUPABASE_SMTP_PORT=587
SUPABASE_SMTP_USER=your-email@gmail.com
SUPABASE_SMTP_PASS=your-app-password
MAIL_FROM="NovaVision <your-email@gmail.com>"
SMTP_TIMEOUT_MS=4000
```

- **Pros**: Works locally, no API keys needed
- **Cons**: Blocked on Railway and many cloud platforms
- **Use case**: Local development only

## Environment Variables

### Common Variables
```bash
# Required for all providers
EMAIL_PROVIDER=postmark          # Options: postmark, sendgrid, smtp (default: smtp)
MAIL_FROM="NovaVision <noreply@yourdomain.com>"  # Sender email address

# Optional
SMTP_TEST_TO=test@example.com    # Default recipient for debug endpoint
DEBUG_TOKEN=your-secret-token    # Required for debug endpoint in production
```

### Provider-Specific Variables

#### Postmark
```bash
POSTMARK_API_KEY=your-postmark-server-token
```

#### SendGrid
```bash
SENDGRID_API_KEY=SG.your-sendgrid-api-key
```

#### SMTP
```bash
SUPABASE_SMTP_HOST=smtp.gmail.com
SUPABASE_SMTP_PORT=587
SUPABASE_SMTP_USER=your-email@gmail.com
SUPABASE_SMTP_PASS=your-app-password
SMTP_TIMEOUT_MS=4000              # Shorter timeout for Railway (default: 15000)
SMTP_REJECT_UNAUTHORIZED=true    # SSL certificate validation (default: true)
```

## Railway Configuration

Railway blocks SMTP egress on ports 465 and 587. **You must use HTTP-based providers (Postmark or SendGrid).**

### Setup Steps for Railway:

1. **Choose a provider** (Postmark or SendGrid)

2. **Get API credentials**:
   - Postmark: Get Server API Token from https://account.postmarkapp.com/servers
   - SendGrid: Create API key from https://app.sendgrid.com/settings/api_keys

3. **Configure environment variables in Railway**:
   ```bash
   EMAIL_PROVIDER=postmark
   POSTMARK_API_KEY=your-api-key
   MAIL_FROM="Your Store <noreply@yourdomain.com>"
   ```

4. **Verify sender domain**:
   - Both Postmark and SendGrid require domain verification for production
   - Configure SPF, DKIM, and DMARC DNS records
   - Use sandbox mode for testing (emails only delivered to verified addresses)

5. **Test the configuration**:
   ```bash
   curl -H "X-Debug-Token: your-token" \
     "https://your-railway-app.up.railway.app/mercadopago/debug/email?to=your@email.com"
   ```

## Testing Email Configuration

### Debug Endpoint

The `/mercadopago/debug/email` endpoint allows testing email delivery without triggering the payment flow.

**URL**: `GET /mercadopago/debug/email`

**Query Parameters**:
- `to` (optional): Recipient email address. Defaults to `SMTP_TEST_TO` or `SUPABASE_SMTP_USER`

**Headers**:
- `X-Debug-Token`: Required in production (value must match `DEBUG_TOKEN` env var)

**Examples**:

```bash
# Local development (no token required)
curl "http://localhost:3000/mercadopago/debug/email?to=test@example.com"

# Production (requires token)
curl -H "X-Debug-Token: your-secret-token" \
  "https://api.yourdomain.com/mercadopago/debug/email?to=test@example.com"
```

**Response (Success)**:
```json
{
  "ok": true,
  "message": "Test email sent successfully via postmark",
  "to": "test@example.com",
  "provider": "postmark",
  "platform": "Railway",
  "timestamp": "2024-01-15T10:30:00.000Z"
}
```

**Response (Error)**:
```json
{
  "ok": false,
  "error": "Email test failed",
  "message": "POSTMARK_API_KEY no está configurado",
  "provider": "postmark",
  "to": "test@example.com",
  "platform": "Railway",
  "hint": "Check logs for detailed error information"
}
```

## Troubleshooting

### Railway: "Connection timeout" with SMTP

**Problem**: SMTP connections timeout on Railway
**Solution**: Switch to HTTP-based provider (Postmark or SendGrid)

```bash
# Change from:
EMAIL_PROVIDER=smtp

# To:
EMAIL_PROVIDER=postmark
POSTMARK_API_KEY=your-key
```

### Emails going to spam

**Problem**: Emails are marked as spam
**Solution**: 
1. Verify sender domain with provider
2. Configure SPF record: `v=spf1 include:spf.yourdomain.com ~all`
3. Configure DKIM (provided by Postmark/SendGrid)
4. Set up DMARC: `v=DMARC1; p=quarantine; rua=mailto:dmarc@yourdomain.com`

### "POSTMARK_API_KEY no está configurado"

**Problem**: Provider API key is missing
**Solution**: Add the required environment variable in Railway dashboard:
- Go to Railway project → Variables
- Add `POSTMARK_API_KEY` with your API token

### Debug endpoint returns 401 Unauthorized

**Problem**: Missing or invalid debug token in production
**Solution**: 
1. Set `DEBUG_TOKEN` environment variable
2. Include `X-Debug-Token` header with matching value in requests

## Best Practices

1. **Use domain-based sender**: `noreply@yourdomain.com` instead of generic Gmail addresses
2. **Verify your domain**: Configure SPF, DKIM, and DMARC records
3. **Test in sandbox mode**: Use test mode until domain is verified
4. **Monitor deliverability**: Check bounce rates and spam complaints in provider dashboard
5. **Keep credentials secure**: Never commit API keys to source control
6. **Use debug endpoint**: Test configuration changes before deploying

## Provider Comparison

| Feature | Postmark | SendGrid | SMTP |
|---------|----------|----------|------|
| Works on Railway | ✅ Yes | ✅ Yes | ❌ No |
| Requires API Key | Yes | Yes | No |
| Domain Verification | Required | Required | Optional |
| Free Tier | 100/month | 100/day | N/A |
| Deliverability | Excellent | Good | Variable |
| Setup Complexity | Easy | Medium | Easy |
| Use Case | Production | Production | Dev only |

## Migration Guide

### From SMTP to Postmark

1. Sign up at https://postmarkapp.com
2. Get Server API Token
3. Update environment variables:
   ```bash
   EMAIL_PROVIDER=postmark
   POSTMARK_API_KEY=your-token
   MAIL_FROM="Your Store <noreply@yourdomain.com>"
   ```
4. Remove SMTP variables (optional, they'll be ignored)
5. Test with debug endpoint
6. Verify sender domain for production use

### From SMTP to SendGrid

1. Sign up at https://sendgrid.com
2. Create API key (Mail Send → Full Access)
3. Update environment variables:
   ```bash
   EMAIL_PROVIDER=sendgrid
   SENDGRID_API_KEY=SG.your-key
   MAIL_FROM="Your Store <noreply@yourdomain.com>"
   ```
4. Remove SMTP variables (optional, they'll be ignored)
5. Test with debug endpoint
6. Verify sender domain for production use

## Support

For issues or questions:
- Check Railway logs: `railway logs`
- Test with debug endpoint: `/mercadopago/debug/email`
- Review error messages in logs for detailed diagnostics
- Postmark support: https://postmarkapp.com/support
- SendGrid support: https://support.sendgrid.com

# Email Provider Implementation - Developer Notes

## Overview
This PR implements HTTP-based email providers (Postmark & SendGrid) to resolve Railway's SMTP egress blocking issue while maintaining backward compatibility with SMTP for local development.

## Problem Context
Railway blocks egress on SMTP ports (25, 465, 587), causing connection timeouts when attempting to send emails via traditional SMTP. This affects order confirmation emails and other transactional emails.

## Solution Architecture

### Provider Routing
The `sendEmail()` method now routes to different providers based on the `EMAIL_PROVIDER` environment variable:
- `postmark` → HTTP API at api.postmarkapp.com (HTTPS:443)
- `sendgrid` → HTTP API at api.sendgrid.com (HTTPS:443)
- `smtp` → Traditional SMTP (ports 465/587) - **only for local development**

### Platform Detection
The system detects the hosting platform and adjusts behavior accordingly:
- **Railway**: 4-second SMTP timeout, Railway-specific error messages
- **Vercel/Render**: Detected but uses default behavior
- **Local**: 15-second SMTP timeout, full SMTP support

### Security Enhancements
1. Removed credential logging from `sendEmail()` method
2. Added token-based authentication for debug endpoint
3. Dynamic recipient handling (no hardcoded emails)
4. Production-only debug token requirement

## Code Changes

### Modified Files

#### src/mercadopago/mercadopago.service.ts
**Changes:**
- Added `sendEmailViaPostmark()` - Postmark HTTP API integration
- Added `sendEmailViaSendGrid()` - SendGrid HTTP API integration
- Modified `sendEmail()` to route based on `EMAIL_PROVIDER`
- Added platform detection logic
- Removed credential logging
- Added Railway-specific error messages

**Key Methods:**
```typescript
private async sendEmail(to, subject, content) {
  const provider = process.env.EMAIL_PROVIDER || 'smtp';
  if (provider === 'postmark') return this.sendEmailViaPostmark(...);
  if (provider === 'sendgrid') return this.sendEmailViaSendGrid(...);
  // SMTP fallback with Railway detection
}

private async sendEmailViaPostmark(to, subject, htmlContent) {
  // HTTP POST to api.postmarkapp.com/email
}

private async sendEmailViaSendGrid(to, subject, htmlContent) {
  // HTTP POST to api.sendgrid.com/v3/mail/send
}
```

#### src/mercadopago/mercadopago.controller.ts
**Changes:**
- Added `GET /mercadopago/debug/email` endpoint
- Token-based authentication (X-Debug-Token header)
- Platform and provider diagnostics in response
- Production vs development access control

**Endpoint:**
```typescript
@Get('debug/email')
async debugEmail(@Query('to') to, @Req() req) {
  // Validates token in production
  // Sends test email
  // Returns status with diagnostics
}
```

#### src/app.module.ts
**Changes:**
- Added debug endpoint to public routes (excluded from AuthMiddleware)

**Modification:**
```typescript
.exclude(
  // ... existing routes
  { path: 'mercadopago/debug/email', method: RequestMethod.GET },
)
```

### New Files

#### Documentation
1. **docs/EMAIL_CONFIGURATION.md** (264 lines)
   - Comprehensive provider comparison
   - Environment variable reference
   - Railway setup instructions
   - Troubleshooting guide
   - Migration paths
   - DNS configuration (SPF/DKIM/DMARC)

2. **docs/EMAIL_QUICK_START.md** (115 lines)
   - 2-minute Railway setup
   - Copy-paste commands
   - Quick troubleshooting

3. **docs/EMAIL_ARCHITECTURE.md** (301 lines)
   - Visual flow diagrams
   - Architecture overview
   - Security model
   - File structure

4. **IMPLEMENTATION_SUMMARY_EMAIL.md** (293 lines)
   - Complete change log
   - Metrics and stats
   - Testing results
   - Success criteria

#### Configuration
5. **.env.email.example** (54 lines)
   - Postmark configuration template
   - SendGrid configuration template
   - SMTP configuration template
   - Optional settings with descriptions

#### Tools
6. **scripts/validate-email-config.js** (180 lines)
   - Platform detection
   - Provider validation
   - Required/optional variable checks
   - Colored console output
   - Railway-specific warnings
   - Exit codes for CI/CD

#### Tests
7. **test/email-provider.spec.ts** (192 lines)
   - Platform detection tests
   - Provider selection tests
   - Configuration validation tests
   - Method presence checks
   - Optional E2E tests (EMAIL_PROVIDER_TEST=true)

## Environment Variables

### New Variables
```bash
# Provider selection (required for Railway)
EMAIL_PROVIDER=postmark|sendgrid|smtp

# Postmark (when EMAIL_PROVIDER=postmark)
POSTMARK_API_KEY=your-server-token

# SendGrid (when EMAIL_PROVIDER=sendgrid)
SENDGRID_API_KEY=SG.your-api-key

# Common
MAIL_FROM="Store Name <noreply@domain.com>"

# Debug endpoint security
DEBUG_TOKEN=random-secret-string

# Testing
SMTP_TEST_TO=test@example.com
```

### Existing Variables (Still Supported)
```bash
# SMTP (local development only)
SUPABASE_SMTP_HOST=smtp.gmail.com
SUPABASE_SMTP_PORT=587
SUPABASE_SMTP_USER=your@email.com
SUPABASE_SMTP_PASS=app-password
SMTP_TIMEOUT_MS=15000
```

## Testing

### Automated Tests
```bash
# Run email provider tests
npm test test/email-provider.spec.ts

# Expected: 9 tests pass, 1 skipped
# Tests: platform detection, provider selection, validation
```

### Manual Testing

#### Debug Endpoint
```bash
# Local (no token required)
curl "http://localhost:3000/mercadopago/debug/email?to=test@example.com"

# Production (token required)
curl -H "X-Debug-Token: your-token" \
  "https://api.yourdomain.com/mercadopago/debug/email?to=test@example.com"
```

#### Configuration Validation
```bash
# Validate environment configuration
npm run validate:email

# Expected output:
# ✓ Platform: Railway
# ✓ Provider: postmark
# ✓ POSTMARK_API_KEY is set
# ✓ Configuration looks good!
```

## Migration Guide

### For Existing Deployments (SMTP → HTTP)

1. **Choose Provider**
   - Postmark (recommended): https://postmarkapp.com
   - SendGrid: https://sendgrid.com

2. **Get API Credentials**
   - Postmark: Server API Token
   - SendGrid: API Key with Mail Send permissions

3. **Update Environment Variables**
   ```bash
   # Add to Railway dashboard
   EMAIL_PROVIDER=postmark
   POSTMARK_API_KEY=your-token
   MAIL_FROM="Store <noreply@yourdomain.com>"
   DEBUG_TOKEN=random-secret
   ```

4. **Test Configuration**
   ```bash
   # Use debug endpoint
   curl -H "X-Debug-Token: your-token" \
     "https://your-app.railway.app/mercadopago/debug/email?to=test@example.com"
   ```

5. **Verify Domain (Production)**
   - Add domain in provider dashboard
   - Configure DNS records (SPF, DKIM)
   - Wait for verification (5-10 minutes)

### For New Deployments

1. Follow "Railway Quick Start" in docs/EMAIL_QUICK_START.md
2. Configure DNS from day one
3. Use sandbox mode for testing

## Backward Compatibility

### SMTP Still Works Locally
- No breaking changes for local development
- Existing SMTP configuration preserved
- Default provider is 'smtp' if not specified

### Gradual Migration
- Can deploy without changing email provider
- Add HTTP provider when ready
- Old SMTP config can coexist (ignored when HTTP provider set)

## Troubleshooting

### Common Issues

1. **"Connection timeout" on Railway**
   - Expected with SMTP
   - Solution: Switch to EMAIL_PROVIDER=postmark or sendgrid

2. **"POSTMARK_API_KEY no está configurado"**
   - Missing environment variable
   - Solution: Add in Railway dashboard

3. **Debug endpoint returns 401**
   - Missing or invalid DEBUG_TOKEN
   - Solution: Set DEBUG_TOKEN env var, include in header

4. **Emails go to spam**
   - Unverified sender domain
   - Solution: Verify domain, configure SPF/DKIM/DMARC

### Debug Steps

1. Run validation: `npm run validate:email`
2. Check environment variables in Railway
3. Test with debug endpoint
4. Check Railway logs: `railway logs`
5. Verify provider dashboard for delivery status

## Performance Considerations

### HTTP vs SMTP
- HTTP: ~100-200ms (Postmark/SendGrid)
- SMTP: ~500-1000ms (when working)
- Railway SMTP: Timeout after 4-15 seconds

### Rate Limits
- Postmark: 100 emails/month (free tier)
- SendGrid: 100 emails/day (free tier)
- Consider provider's rate limits for high-volume

## Security Considerations

### Credentials
- Never log API keys or passwords
- Use environment variables
- Rotate keys periodically

### Debug Endpoint
- Protected with DEBUG_TOKEN in production
- Excluded from auth middleware (public route)
- Rate limiting recommended (not implemented)

### Email Content
- HTML content sanitized by provider
- Validate email addresses
- Consider SPF/DKIM for authenticity

## Future Enhancements

### Potential Improvements
- [ ] Add Mailgun support
- [ ] Implement email queuing (Redis/Bull)
- [ ] Add email templates system
- [ ] Add retry logic with exponential backoff
- [ ] Monitor delivery rates
- [ ] Add webhook handling for bounces
- [ ] Implement email analytics

### Not Planned
- SMTP port scanning (blocked by Railway)
- Multiple simultaneous providers (unnecessary complexity)
- Provider auto-selection (explicit configuration is clearer)

## References

### Documentation
- [EMAIL_QUICK_START.md](./docs/EMAIL_QUICK_START.md) - Quick Railway setup
- [EMAIL_CONFIGURATION.md](./docs/EMAIL_CONFIGURATION.md) - Complete guide
- [EMAIL_ARCHITECTURE.md](./docs/EMAIL_ARCHITECTURE.md) - Visual diagrams

### External Resources
- [Postmark Documentation](https://postmarkapp.com/developer)
- [SendGrid Documentation](https://docs.sendgrid.com)
- [Railway Docs](https://docs.railway.app)

## Maintenance

### Monitoring
- Check provider dashboard for delivery rates
- Monitor bounce/spam rates
- Review Railway logs for errors

### Updates
- Keep provider API versions current
- Update documentation when providers change
- Review security best practices periodically

## Support

For issues or questions:
1. Check documentation: `docs/EMAIL_*.md`
2. Run validation: `npm run validate:email`
3. Test debug endpoint
4. Review Railway logs
5. Check provider status pages

---

**Last Updated**: Implementation completed, all tests passing, production-ready.
**Maintainer**: See git history for contributors.
**Status**: ✅ Complete and deployed.

# Email Flow Architecture

## Before (SMTP - Blocked on Railway)

```
┌─────────────────┐
│   NovaVision    │
│    Backend      │
│   (Railway)     │
└────────┬────────┘
         │
         │ SMTP (port 465/587)
         │ ❌ BLOCKED by Railway
         ↓
    ╔════════╗
    ║  SMTP  ║
    ║ Server ║
    ╚════════╝
         ↓
    Connection Timeout
         ⏱️ 15s
```

## After (HTTP Providers - Works on Railway)

```
┌─────────────────────────────────────────────────┐
│             NovaVision Backend                  │
│               (Railway)                         │
│                                                 │
│  ┌──────────────────────────────────────────┐  │
│  │     Email Provider Selection Logic      │  │
│  │                                          │  │
│  │  provider = ENV['EMAIL_PROVIDER']       │  │
│  │                                          │  │
│  │  ┌──────────┐  ┌──────────┐  ┌──────┐  │  │
│  │  │ Postmark │  │ SendGrid │  │ SMTP │  │  │
│  │  └────┬─────┘  └────┬─────┘  └──┬───┘  │  │
│  └───────┼─────────────┼────────────┼──────┘  │
└──────────┼─────────────┼────────────┼─────────┘
           │             │            │
           │ HTTPS:443   │ HTTPS:443  │ 465/587
           │ ✅ Works    │ ✅ Works   │ ⚠️ Local only
           ↓             ↓            ↓
      ┌────────┐    ┌─────────┐  ┌──────┐
      │Postmark│    │SendGrid │  │ SMTP │
      │  API   │    │   API   │  │Server│
      └───┬────┘    └────┬────┘  └──┬───┘
          │              │           │
          └──────────────┴───────────┘
                     ↓
              ┌─────────────┐
              │  Recipient  │
              │   Mailbox   │
              └─────────────┘
```

## Provider Selection Flow

```
┌─────────────────────────────────────────┐
│  sendEmail(to, subject, content)       │
└─────────────────┬───────────────────────┘
                  │
                  ↓
        ┌─────────────────────┐
        │ Read EMAIL_PROVIDER │
        └─────────┬───────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
   ┌────▼─────┐      ┌─────▼────┐      ┌──────▼─────┐
   │'postmark'│      │'sendgrid'│      │   'smtp'   │
   └────┬─────┘      └─────┬────┘      │  (default) │
        │                  │            └──────┬─────┘
        ↓                  ↓                   │
┌───────────────┐  ┌────────────────┐         │
│ POST to       │  │ POST to        │         │
│ api.postmark  │  │ api.sendgrid   │         │
│ app.com/email │  │ .com/v3/mail/  │         │
└───────┬───────┘  └────────┬───────┘         │
        │                   │                  │
        │ 200 OK            │ 202 Accepted     │
        │                   │                  │
        └───────────────────┴──────────────────┘
                            ↓
                    ┌───────────────┐
                    │  Log success  │
                    │  Return OK    │
                    └───────────────┘
```

## Debug Endpoint Flow

```
┌───────────────────────────────────────────────┐
│  GET /mercadopago/debug/email?to=test@email  │
│  Header: X-Debug-Token: secret                │
└───────────────────┬───────────────────────────┘
                    │
                    ↓
          ┌─────────────────────┐
          │ Validate Token      │
          │ (if production)     │
          └─────────┬───────────┘
                    │
                    ↓
          ┌─────────────────────┐
          │ Detect Platform     │
          │ (Railway/Local)     │
          └─────────┬───────────┘
                    │
                    ↓
          ┌─────────────────────┐
          │ Build Test Email    │
          │ - Timestamp         │
          │ - Provider info     │
          │ - Platform info     │
          └─────────┬───────────┘
                    │
                    ↓
          ┌─────────────────────┐
          │ Call sendEmail()    │
          └─────────┬───────────┘
                    │
        ┌───────────┴───────────┐
        │ Success               │ Error
        ↓                       ↓
┌──────────────┐      ┌────────────────┐
│ 200 OK       │      │ 500 Error      │
│ {            │      │ {              │
│   ok: true,  │      │   ok: false,   │
│   provider,  │      │   error,       │
│   platform   │      │   hint         │
│ }            │      │ }              │
└──────────────┘      └────────────────┘
```

## Configuration Flow

```
┌────────────────────────────────────────────┐
│         Environment Variables              │
├────────────────────────────────────────────┤
│                                            │
│  ┌──────────────────────────────────────┐ │
│  │  EMAIL_PROVIDER = "postmark"         │ │
│  └──────────────┬───────────────────────┘ │
│                 │                          │
│  ┌──────────────▼───────────────────────┐ │
│  │  POSTMARK_API_KEY = "abc123..."      │ │
│  └──────────────────────────────────────┘ │
│                                            │
│  ┌──────────────────────────────────────┐ │
│  │  MAIL_FROM = "Store <no@domain.com>" │ │
│  └──────────────────────────────────────┘ │
│                                            │
│  ┌──────────────────────────────────────┐ │
│  │  DEBUG_TOKEN = "secret123"           │ │
│  └──────────────────────────────────────┘ │
└────────────────────────────────────────────┘
                    ↓
┌────────────────────────────────────────────┐
│       Validation Script                    │
│       npm run validate:email               │
├────────────────────────────────────────────┤
│                                            │
│  ✓ Platform: Railway                      │
│  ✓ Provider: postmark                     │
│  ✓ POSTMARK_API_KEY is set                │
│  ✓ MAIL_FROM is set                       │
│  ✓ Configuration looks good!              │
│                                            │
│  Next steps:                               │
│  1. Test with debug endpoint              │
│  2. Verify sender domain                  │
│  3. Configure DNS records                 │
└────────────────────────────────────────────┘
```

## Railway vs Local Behavior

```
┌─────────────────────────────────────────────────┐
│                  Platform Detection             │
└─────────────────┬───────────────────────────────┘
                  │
     ┌────────────┴───────────┐
     │                        │
┌────▼─────────┐      ┌──────▼──────────┐
│   Railway    │      │     Local       │
│              │      │  Development    │
└────┬─────────┘      └──────┬──────────┘
     │                       │
     │ Detected by:          │ Detected by:
     │ RAILWAY_ENVIRONMENT   │ NODE_ENV != prod
     │                       │
     ↓                       ↓
┌────────────────┐      ┌──────────────────┐
│ SMTP Timeout:  │      │ SMTP Timeout:    │
│     4s         │      │     15s          │
│                │      │                  │
│ Error: "SMTP   │      │ Error: Normal    │
│ blocked, use   │      │ SMTP error       │
│ HTTP provider" │      │                  │
└────────────────┘      └──────────────────┘
```

## Security Model

```
┌─────────────────────────────────────────┐
│      /mercadopago/debug/email          │
└─────────────────┬───────────────────────┘
                  │
        ┌─────────▼─────────┐
        │ Check NODE_ENV    │
        └─────────┬─────────┘
                  │
    ┌─────────────┴──────────────┐
    │                            │
┌───▼────────────┐     ┌─────────▼─────────┐
│ Production     │     │  Development      │
└───┬────────────┘     └─────────┬─────────┘
    │                            │
    ↓                            ↓
┌───────────────────┐   ┌───────────────────┐
│ Require token:    │   │ No token needed   │
│                   │   │                   │
│ X-Debug-Token     │   │ Direct access     │
│ must match        │   │                   │
│ DEBUG_TOKEN env   │   │                   │
└───────┬───────────┘   └───────┬───────────┘
        │                       │
        ↓                       ↓
  Valid token?            Send email
        │
    ┌───┴───┐
    │       │
   Yes     No
    │       │
    ↓       ↓
Send   401 Error
email  Unauthorized
```

## File Structure

```
templatetwobe/
├── src/
│   ├── mercadopago/
│   │   ├── mercadopago.service.ts       ⭐ Email logic
│   │   └── mercadopago.controller.ts    ⭐ Debug endpoint
│   └── app.module.ts                    ⭐ Auth config
│
├── docs/
│   ├── EMAIL_CONFIGURATION.md           📖 Full guide (7.7KB)
│   └── EMAIL_QUICK_START.md            📖 Quick start (2.9KB)
│
├── scripts/
│   └── validate-email-config.js        🔧 Validator (6.4KB)
│
├── test/
│   └── email-provider.spec.ts          ✅ Tests (9 passing)
│
├── .env.email.example                  📝 Config templates
└── IMPLEMENTATION_SUMMARY_EMAIL.md     📊 Full summary

Legend:
⭐ Core changes
📖 Documentation
🔧 Tools
✅ Tests
📝 Examples
📊 Summary
```

## Migration Timeline

```
Before                  After
──────                  ─────

SMTP only          →    Multiple providers
  └─ Gmail 465/587       ├─ Postmark (HTTPS:443) ✅
     ❌ Blocked          ├─ SendGrid (HTTPS:443) ✅
                         └─ SMTP (Local only) ⚠️

No debug           →    Debug endpoint
                         └─ /mercadopago/debug/email ✅

Manual testing     →    Automated validation
                         └─ npm run validate:email ✅

No docs            →    Comprehensive docs
                         ├─ Quick start guide ✅
                         ├─ Full configuration ✅
                         ├─ Examples ✅
                         └─ Migration guides ✅
```

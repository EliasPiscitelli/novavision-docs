# Railway Deployment Guide - Subscription Testing

## Setup Rápido

### 1. Deploy Inicial

En el dashboard de Railway:

1. **Connect Repo**:

   - Conectá tu repo GitHub: `EliasPiscitelli/templaterepo`
   - Branch: `main` (o tu branch de desarrollo)

2. **Root Directory**:

   - Set root: `apps/api`
   - Railway auto-detectará NestJS

3. **Build Command** (si no auto-detecta):

   ```bash
   npm install && npm run build
   ```

4. **Start Command**:
   ```bash
   npm run start:prod
   ```

---

## Variables de Entorno

Copiar desde tu `.env` local:

### 🌍 Core

```bash
NODE_ENV=production
PORT=3000
VERBOSE_LOGS=false
```

### 🔐 Security

```bash
JWT_SECRET=tu-jwt-secret-aqui
# MP_TOKEN_ENCRYPTION_KEY - Railway puede generar uno
```

### 🗄️ Databases

```bash
ADMIN_DB_URL=postgresql://postgres:...@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres
BACKEND_DB_URL=postgresql://postgres:...@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres

SUPABASE_URL=https://ulndkhijxtxvpmbbfrgp.supabase.co
SUPABASE_KEY=eyJhbGci...
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...
```

### 💳 MercadoPago

```bash
MP_ACCESS_TOKEN=TEST-tu-token-aqui  # Usar TEST token
PLATFORM_MP_ACCESS_TOKEN=TEST-tu-token-aqui
```

### 🌐 URLs (IMPORTANTE)

```bash
# Railway te da una URL como: https://confident-appreciation.up.railway.app
ADMIN_URL=https://confident-appreciation.up.railway.app
WEB_URL=https://confident-appreciation.up.railway.app
API_URL=https://confident-appreciation.up.railway.app
```

**⚠️ ACTUALIZAR DESPUÉS DEL PRIMER DEPLOY** con la URL real de Railway.

### 📧 Email (opcional para testing)

```bash
EMAILJS_SERVICE_ID=...
EMAILJS_TEMPLATE_ID=...
EMAILJS_PUBLIC_KEY=...
EMAILJS_PRIVATE_KEY=...
```

### 💰 Subscriptions (usa defaults)

```bash
PRICE_ADJUSTMENT_THRESHOLD_PCT=10
GRACE_PERIOD_DAYS=7
DOLLAR_SOURCE=blue
```

---

## Después del Deploy

### 1. Obtener URL de Railway

Railway asigna algo como:

```
https://confident-appreciation-production.up.railway.app
```

### 2. Actualizar Variables

En Railway dashboard → Variables → Add/Edit:

```bash
ADMIN_URL=https://confident-appreciation-production.up.railway.app
API_URL=https://confident-appreciation-production.up.railway.app
```

Trigger redeploy (Railway lo hace auto al cambiar vars).

### 3. Configurar MercadoPago Webhook

1. Ir a [MercadoPago Dashboard](https://www.mercadopago.com.ar/developers/panel/app)
2. Webhooks → Agregar URL:
   ```
   https://confident-appreciation-production.up.railway.app/subscriptions/webhook
   ```
3. Eventos: `preapproval`, `payment`

### 4. Probar Subscription Flow

#### Desde Localhost

Actualizar `apps/admin/.env.local`:

```bash
VITE_API_URL=https://confident-appreciation-production.up.railway.app
```

Restart admin dev server:

```bash
cd apps/admin
npm run dev
```

#### Flow de Prueba

1. **Wizard**: http://localhost:5174/wizard
2. **Completar steps 1-6**
3. **Select plan** → Growth
4. **Checkout**: Te redirige a MercadoPago
5. **Pagar con tarjeta test**:
   ```
   Número: 5031 7557 3453 0604
   CVV: 123
   Exp: 11/25
   ```
6. **Webhook automático** → DB se actualiza
7. **Verificar en Supabase**:
   ```sql
   SELECT * FROM subscriptions
   WHERE account_id = 'tu-id'
   ORDER BY created_at DESC;
   ```

---

## Monitoreo

### Railway Logs

```bash
# Ver logs en tiempo real
railway logs
```

O en dashboard → Deployments → View Logs

### Buscar Eventos

```bash
# Webhook received
grep "Received webhook" logs

# Subscription created
grep "PreApproval created" logs

# Payment processed
grep "Payment successful" logs
```

---

## Troubleshooting

### Error: Cannot connect to database

**Causa**: DB URL incorrecta o firewall

**Fix**:

- Verificar ADMIN_DB_URL en Railway
- Supabase permite conexiones externas por default

---

### Error: MP webhook not arriving

**Causa**: URL mal configurada en MP dashboard

**Fix**:

1. Verify webhook URL en MP
2. Test manual:
   ```bash
   curl -X POST https://your-railway-url.railway.app/subscriptions/webhook \
     -H "Content-Type: application/json" \
     -d '{"type":"test","action":"ping"}'
   ```

---

### Warning: Using TEST token in production URL

**Esto está OK** para testing. Solo cambiar a `APP_USR-` token cuando vayas a producción real.

---

## Próximos Pasos

1. ✅ Deploy API a Railway
2. ✅ Configurar env vars
3. ✅ Update URLs después del deploy
4. ✅ Configurar MP webhook
5. ✅ Probar flow completo
6. ⏭️ Si todo OK → Deploy admin frontend a Netlify/Vercel
7. ⏭️ Update admin URLs para apuntar a Railway API

---

## Comandos Útiles

```bash
# Deploy desde CLI (opcional)
cd apps/api
railway up

# Ver variables
railway variables

# Logs en tiempo real
railway logs -f

# Restart service
railway restart
```

---

## Costo

Railway free tier:

- ✅ 500 horas/mes
- ✅ $5 de crédito inicial
- ✅ Más que suficiente para testing

Monitoring de uso: Dashboard → Usage

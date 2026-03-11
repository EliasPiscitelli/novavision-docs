# Testing Subscriptions - Setup Guide

## ⚠️ Problemas Conocidos con Ngrok

Si MercadoPago rechaza ngrok (por certificados o políticas de seguridad), usá **Railway** que es gratis y tiene dominio real con SSL válido.

---

## Opción 1: Ngrok (Rápido pero puede fallar)

### Setup Automático

```bash
# Desde la raíz del proyecto
./setup-ngrok.sh
```

Esto:

1. Instala ngrok (si no está)
2. Expone puerto 3000
3. Te muestra la URL pública

### Setup Manual

```bash
# 1. Instalar
brew install ngrok

# 2. Iniciar tunnel
ngrok http 3000

# 3. Copiar la URL https://xxxx.ngrok.io

# 4. Actualizar .env
ADMIN_URL=https://xxxx.ngrok.io

# 5. Reiniciar API
npm run start:dev
```

### Ver requests

http://localhost:4040

---

## Opción 2: Railway (Recomendado - Gratis con SSL)

### Por qué Railway

- ✅ Dominio real con SSL válido
- ✅ Gratis para desarrollo
- ✅ Deploy en 2 minutos
- ✅ MercadoPago lo acepta siempre
- ✅ Base de datos PostgreSQL incluída

### Setup

#### 1. Crear cuenta

https://railway.app (login con GitHub)

#### 2. Deploy API

```bash
# Desde apps/api
railway up

# Railway te da una URL como:
# https://novavision-api-production-xxxx.up.railway.app
```

#### 3. Configurar Variables

En Railway dashboard → Variables:

```bash
ADMIN_DB_URL=tu_supabase_url
MP_ACCESS_TOKEN=tu_token
ADMIN_URL=https://novavision-api-production-xxxx.up.railway.app
WEB_URL=https://novavision-web-xxxx.up.railway.app
# ... resto de env vars
```

#### 4. Usar URL en desarrollo local

```bash
# En tu .env local
ADMIN_URL=https://novavision-api-production-xxxx.up.railway.app
```

Ahora localhost hace checkout → Railway API → MercadoPago ✅

---

## Opción 3: Vercel (Alternativa)

```bash
# Instalar Vercel CLI
npm i -g vercel

# Deploy
cd apps/api
vercel --prod

# Te da URL: https://novavision-api.vercel.app
```

Configurar variables en Vercel dashboard.

---

## Testear Suscripciones

### Con cualquier opción arriba:

1. **Iniciar wizard**: http://localhost:5174/wizard
2. **Completar steps 1-6**
3. **Click en plan** (ej: Growth)
4. **Redirect a MercadoPago**
5. **Pagar con tarjeta test**:
   ```
   Número: 5031 7557 3453 0604
   CVV: 123
   Vencimiento: 11/25
   ```
6. **Webhook automático** → DB actualizada
7. **Verificar**:
   ```sql
   SELECT * FROM subscriptions
   WHERE account_id = 'tu-account-id'
   AND status = 'active';
   ```

---

## Tarjetas de Prueba MercadoPago

### ✅ Aprobadas

```
Mastercard: 5031 7557 3453 0604
Visa: 4509 9535 6623 3704
```

### ❌ Rechazadas

```
Mastercard: 5031 4332 1540 6351
Visa: 4509 9535 6623 3704
```

### Datos adicionales

```
CVV: 123
Vencimiento: 11/25
Nombre: APRO (aprobado) / CONT (rechazado)
DNI: 12345678
```

---

## Debugging

### Ver logs de MercadoPago

```bash
# En API logs
[PlatformMercadoPagoService] [MP] Creating preapproval: {...}
[PlatformMercadoPagoService] [MP] PreApproval created: xxx-yyy-zzz
```

### Ver webhooks

Railway/Vercel dashboard → Logs

### Query subscriptions

```sql
-- Ver todas las suscripciones
SELECT
  s.id,
  s.status,
  s.mp_preapproval_id,
  a.email,
  a.slug
FROM subscriptions s
JOIN nv_accounts a ON a.id = s.account_id
ORDER BY s.created_at DESC;
```

---

## Recomendación Final

**Para desarrollo local**: Usar **Railway** (más confiable)
**Para demo cliente**: Usar production domain
**Para testing rápido**: Probar ngrok, si falla → Railway

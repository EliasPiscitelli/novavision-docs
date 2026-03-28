# Variables de entorno pendientes de configurar

**Fecha**: 2026-03-27
**Estado**: Pendiente de configuración manual
**Contexto**: Estas variables son requeridas por features implementadas en el sprint 13-27 marzo

---

## 1. `MP_TOKEN_POOL` — Railway (API)

**Servicio**: API NestJS (`@nv/api`)
**Dónde configurar**: Railway → Proyecto NovaVision → Service API → Variables

**Qué es**: JSON con tokens de MercadoPago por país/site_id. Permite que la plataforma opere suscripciones con diferentes cuentas MP según el país del tenant.

**Formato**:
```json
{"MLA":"APP_USR-xxxxx-argentina","MLC":"APP_USR-xxxxx-chile","MLM":"APP_USR-xxxxx-mexico"}
```

**Site IDs soportados**:
| Site ID | País | Moneda |
|---------|------|--------|
| MLA | Argentina | ARS |
| MLC | Chile | CLP |
| MLM | México | MXN |
| MCO | Colombia | COP |
| MLU | Uruguay | UYU |
| MPE | Perú | PEN |

**Comportamiento**:
- **Sin esta variable**: Todo sigue funcionando con `PLATFORM_MP_ACCESS_TOKEN` (el token actual de AR). No hay breaking change.
- **Con esta variable**: El sistema usa el token correspondiente al `site_id` de cada cuenta. Si un site_id no tiene token en el pool, cae al `PLATFORM_MP_ACCESS_TOKEN` como fallback.
- En startup, cada token se valida contra `api.mercadopago.com/users/me` para verificar que el site_id coincide.

**Cuándo configurar**: Cuando se activen nuevos países desde el Super Admin dashboard (country_configs). Mientras solo AR esté activo, no es necesario.

**Cómo obtener tokens**: Cada token es un `APP_USR-*` de una aplicación MP creada en el país correspondiente. Se obtienen desde [developers.mercadopago.com](https://developers.mercadopago.com) → Tus aplicaciones → Credenciales de producción.

---

## 2. `TURNSTILE_SECRET_KEY` — Railway (API)

**Servicio**: API NestJS (`@nv/api`)
**Dónde configurar**: Railway → Proyecto NovaVision → Service API → Variables

**Qué es**: Clave secreta de Cloudflare Turnstile (CAPTCHA invisible). Se usa en el backend para verificar que el token enviado desde el frontend es legítimo.

**Formato**: String, ejemplo: `0x4AAAAAABxxxxxxxxxxxxxxxx`

**Comportamiento**:
- **Sin esta variable**: El captcha se degrada gracefully — `CaptchaService.verify()` retorna `true` sin validar. El onboarding funciona sin protección captcha.
- **Con esta variable**: Cada `startBuilder()` (inicio de onboarding) valida el token Turnstile contra la API de Cloudflare.

**Cómo obtener**:
1. Ir a [dash.cloudflare.com](https://dash.cloudflare.com) → Turnstile
2. Click "Add widget"
3. Nombre: "NovaVision Onboarding"
4. Dominio: `novavision.lat`
5. Tipo: "Managed" (invisible cuando puede, challenge cuando sospecha bot)
6. Copiar **Secret Key** → esta va acá

---

## 3. `VITE_TURNSTILE_SITE_KEY` — Netlify (Admin)

**Servicio**: Admin Dashboard (`@nv/admin`)
**Dónde configurar**: Netlify → Site NovaVision Admin → Site configuration → Environment variables

**Qué es**: Clave pública de Cloudflare Turnstile. Se usa en el frontend para renderizar el widget captcha invisible en el formulario de onboarding.

**Formato**: String, ejemplo: `0x4AAAAAABxxxxxxxxxxxxxxxx`

**Comportamiento**:
- **Sin esta variable**: El componente `TurnstileWidget` no renderiza nada (retorna `null`). El onboarding funciona sin captcha visible.
- **Con esta variable**: Se muestra el widget Turnstile en Step1Slug del BuilderWizard. Al verificar, envía el token al backend.

**Cómo obtener**: Mismo widget de Cloudflare que el paso anterior → Copiar **Site Key** (es la clave pública, segura de exponer en frontend).

**IMPORTANTE**: Agregar en AMBOS contextos de Netlify:
- `develop` (preview deploys)
- `main` (producción)

---

## Resumen rápido

| Variable | Servicio | Plataforma | Urgencia | Sin ella... |
|----------|----------|------------|----------|-------------|
| `MP_TOKEN_POOL` | API | Railway | Baja (solo AR activo) | Usa token único actual |
| `TURNSTILE_SECRET_KEY` | API | Railway | Media | Captcha no valida (pasa todo) |
| `VITE_TURNSTILE_SITE_KEY` | Admin | Netlify | Media | Widget no aparece |

---

## Pasos para activar Turnstile (CAPTCHA)

1. Crear cuenta/widget en Cloudflare Turnstile
2. Copiar Site Key → Netlify como `VITE_TURNSTILE_SITE_KEY`
3. Copiar Secret Key → Railway como `TURNSTILE_SECRET_KEY`
4. Redeploy admin (Netlify) y API (Railway)
5. Verificar en onboarding que aparece el widget invisible

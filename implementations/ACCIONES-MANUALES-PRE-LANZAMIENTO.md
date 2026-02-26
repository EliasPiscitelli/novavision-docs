# Acciones Manuales Pre-Lanzamiento — NovaVision

> Este documento lista TODAS las acciones que requieren intervención humana
> para completar el plan de implementación pre-lanzamiento.
> Las tareas de código ya fueron implementadas; lo que sigue son configuraciones,
> cuentas externas y validaciones que no se pueden automatizar.

---

## 1. Google Analytics 4 — Crear Propiedad

| Campo | Valor |
|-------|-------|
| Prioridad | 🔴 Alta |
| Responsable | Elias |
| Tiempo estimado | 10 min |

### Pasos
1. Ir a [analytics.google.com](https://analytics.google.com)
2. Crear Propiedad → nombre: **NovaVision Admin**
3. Seleccionar: Web → URL: `https://novavision.lat`
4. Copiar el **Measurement ID** (formato `G-XXXXXXXXXX`)
5. Configurar en los `.env` locales y de producción:
   - `apps/admin/.env` → `VITE_GA_MEASUREMENT_ID=G-XXXXXXXXXX`
6. En GA4 → Administrar → Data Streams → Verificar que el stream esté activo
7. (Opcional) Configurar conversiones personalizadas:
   - `onboarding_start` — cuando el usuario inicia el wizard
   - `checkout_initiated` — cuando inicia el pago
   - `checkout_completed` — cuando completa el pago

### Verificación
- Abrir el admin en producción
- Aceptar cookies → verificar en GA4 Realtime que aparece el hit
- Si no aparece: verificar que la variable de entorno esté cargada (`console.log(import.meta.env.VITE_GA_MEASUREMENT_ID)`)

---

## 2. Meta Pixel — Crear Pixel ID

| Campo | Valor |
|-------|-------|
| Prioridad | 🔴 Alta |
| Responsable | Elias |
| Tiempo estimado | 15 min |

### Pasos
1. Ir a [Meta Events Manager](https://business.facebook.com/events_manager2)
2. Conectar datos → Web → nombre: **NovaVision**
3. Copiar el **Pixel ID** (número de 15-16 dígitos)
4. Configurar en los `.env`:
   - `apps/admin/.env` → `VITE_META_PIXEL_ID=XXXXXXXXXXXXXXXXX`
   - `apps/api/.env` → `META_PIXEL_ID=XXXXXXXXXXXXXXXXX`

### Verificación
- Instalar la extensión [Meta Pixel Helper](https://chrome.google.com/webstore/detail/meta-pixel-helper/fdgfkebogiimcoedlicjlajpkdmockpc)
- Abrir el admin, aceptar cookies → verificar que el Pixel Helper muestra el PageView
- Si el Pixel ID actual (`1672700600055618`) es el correcto, usar ese mismo

---

## 3. Meta CAPI — Generar Access Token

| Campo | Valor |
|-------|-------|
| Prioridad | 🔴 Alta |
| Responsable | Elias |
| Tiempo estimado | 20 min |

### Pasos
1. Ir a [Meta Events Manager](https://business.facebook.com/events_manager2) → tu Pixel → Settings
2. En la sección **Conversions API**:
   - Generar token vía **"Generate access token"** (System User)
   - O crear un System User en [Business Settings](https://business.facebook.com/settings/system-users) → generar token con scope `ads_management`
3. Copiar el **access token** (string largo)
4. Configurar en el `.env` del API:
   - `apps/api/.env` → `META_ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxx`
5. (Opcional) Para debugging:
   - En Events Manager → Test Events → copiar **Test Event Code**
   - `apps/api/.env` → `META_TEST_EVENT_CODE=TEST12345`

### Verificación
- Hacer un checkout de prueba (sandbox)
- Verificar en Events Manager → Test Events que aparece el evento `Subscribe`
- Remover `META_TEST_EVENT_CODE` antes de ir a producción

---

## 4. Verificar Dominio en Meta Business Manager

| Campo | Valor |
|-------|-------|
| Prioridad | 🟡 Media |
| Responsable | Elias |
| Tiempo estimado | 30 min |

### Pasos
1. Ir a [Meta Business Settings](https://business.facebook.com/settings/owned-domains) → Brand Safety → Domains
2. Agregar dominio: `novavision.lat`
3. Elegir método de verificación: **DNS TXT record** (recomendado)
4. Agregar el registro TXT en el proveedor DNS (Namecheap/Cloudflare)
5. Verificar en Meta que el dominio aparece como "Verified"

### Por qué importa
- Permite configurar Aggregated Events Measurement (iOS 14+)
- Necesario para CAPI con dedup contra pixel del browser
- Mejora el match quality score de los eventos

---

## 5. Llenar Variables de Entorno en Producción

| Campo | Valor |
|-------|-------|
| Prioridad | 🔴 Alta |
| Responsable | Elias |
| Tiempo estimado | 10 min |

### Variables Admin (Netlify → Site settings → Environment)
```
VITE_GA_MEASUREMENT_ID=G-XXXXXXXXXX
VITE_META_PIXEL_ID=XXXXXXXXXXXXXXXXX
```

### Variables API (Railway → Variables)
```
META_PIXEL_ID=XXXXXXXXXXXXXXXXX
META_ACCESS_TOKEN=xxxxxxxxxxxxxxxxxxxx
META_TEST_EVENT_CODE=      # dejar vacío en prod
RECOVERY_ENABLED=true
ADMIN_BASE_URL=https://novavision.lat
```

### Verificación
- Hacer deploy de admin → verificar que GA4/Meta Pixel cargan (con cookies aceptadas)
- Hacer deploy de API → verificar en logs que aparece `Meta CAPI disabled` si falta token, o `Meta CAPI {Event} sent OK` si está configurado

---

## 6. Validar Email SMTP (Recovery Emails)

| Campo | Valor |
|-------|-------|
| Prioridad | 🟡 Media |
| Responsable | Elias |
| Tiempo estimado | 15 min |

### Pasos
1. Verificar que el servicio de email (Postmark/SendGrid) está configurado
2. Ejecutar diagnóstico: `npm run diagnose:smtp` en terminal API
3. Crear una cuenta de prueba en `draft` y esperar 24h (o ajustar la DB para simular)
4. Verificar que el email de recovery se encoló en `email_jobs` (admin DB)
5. Verificar que el worker lo procesó y el email llegó

### Email de prueba manual
```sql
-- En admin DB: insertar job de prueba
INSERT INTO email_jobs (client_id, type, to_email, template, trigger_event, dedupe_key, payload, status, attempts, max_attempts, run_at)
VALUES (
  'system',
  'recovery_24h',
  'tu-email@gmail.com',
  'recovery_24h',
  'test_manual',
  'test_recovery_manual_' || gen_random_uuid(),
  jsonb_build_object(
    'to', 'tu-email@gmail.com',
    'subject', '[TEST] Recovery 24h',
    'html', '<h1>Test recovery email</h1><p>Si llegó, el sistema funciona.</p>'
  ),
  'pending',
  0,
  3,
  NOW()
);
```

---

## 7. Actualizar Pricing Enterprise en BD (si necesario)

| Campo | Valor |
|-------|-------|
| Prioridad | 🟡 Media |
| Responsable | Elias |
| Tiempo estimado | 5 min |

### Verificar
Correr esta query en admin DB para verificar los precios:
```sql
SELECT plan_key, price_usd_monthly, price_usd_annual
FROM plan_catalog
WHERE plan_key IN ('starter', 'growth', 'enterprise');
```

### Precios correctos
| Plan | Mensual USD | Anual USD |
|------|-------------|-----------|
| Starter | 20 | 200 |
| Growth | 60 | 600 |
| Enterprise | 390 | 3,500 |

Si no coinciden, actualizar:
```sql
UPDATE plan_catalog SET
  price_usd_monthly = 390,
  price_usd_annual = 3500
WHERE plan_key = 'enterprise';
```

---

## 8. Grabar Contenido de Marketing

| Campo | Valor |
|-------|-------|
| Prioridad | 🟡 Media |
| Responsable | Elias / Agencia |
| Tiempo estimado | 1-2 días |

### Contenido necesario para ads
- [ ] Video demo del onboarding wizard (screen recording, 30-60 seg)
- [ ] Video del panel admin / dashboard (features)
- [ ] Screenshots de tiendas de ejemplo (3-5 capturas)
- [ ] Testimoniales de early adopters (si hay)
- [ ] Carrusel de features (para Instagram/Meta ads)

### Formato recomendado
- Videos: MP4, 1080x1080 (cuadrado para feed) + 1080x1920 (stories/reels)
- Imágenes: PNG/JPG, 1200x628 (link ads) + 1080x1080 (carrusel)

---

## 9. Configurar Campañas Meta Ads

| Campo | Valor |
|-------|-------|
| Prioridad | 🟡 Media |
| Responsable | Agencia / Elias |
| Tiempo estimado | 2-4 horas |

### Pre-requisitos cumplidos por código
- [x] Meta Pixel instalado (admin frontend)
- [x] CAPI configurado (backend)
- [x] Eventos: `PageView`, `Subscribe` (onboarding completado), `Purchase` (renovación)

### Configuración de campañas
1. **Campaña de Conversión** — Objetivo: Compras/Subscribe
   - Audiencia: Emprendedores Argentina 25-55
   - Formato: Video + Carrusel
   - Eventos de optimización: `Subscribe`
2. **Retargeting** — Audiencia: visitantes que no completaron checkout
   - Pixel audience: PageView últimos 7 días, excluyendo Subscribe
3. **Lookalike** — Cuando haya ≥100 conversiones, crear lookalike 1-3%

### CAPI Server Events disponibles
| Evento | Disparador | Datos enviados |
|--------|-----------|----------------|
| `Subscribe` | Checkout onboarding aprobado | email (hash), plan, monto, moneda |
| `Purchase` | Renovación suscripción aprobada | email (hash), plan, monto, moneda |

---

## 10. Test End-to-End Completo

| Campo | Valor |
|-------|-------|
| Prioridad | 🔴 Alta |
| Responsable | Elias |
| Tiempo estimado | 1 hora |

### Checklist de prueba
- [ ] Abrir `novavision.lat` → landing carga correctamente
- [ ] Verificar banner de cookies → Aceptar → GA4 y Pixel disparan
- [ ] Verificar banner de cookies → Rechazar → NO disparan
- [ ] Navegar a `/terminos` → se muestra TOS completo
- [ ] Navegar a `/privacidad` → se muestra Privacy Policy completa
- [ ] Iniciar onboarding (`/builder`) → completar wizard
- [ ] Pagar con MP sandbox → verificar:
  - [ ] Account queda en `paid`
  - [ ] Evento `Subscribe` aparece en Meta Events Manager (Test Events)
  - [ ] Email de confirmación llega
- [ ] Simular account en `draft` por más de 24h → verificar:
  - [ ] Cron de recovery encola email
  - [ ] Email llega con diseño correcto y CTA funcional
- [ ] (Post-deploy) Renovar suscripción → verificar evento `Purchase` en CAPI

---

## Resumen de Dependencias

```
┌────────────────────────────────────┐
│     ACCIÓN                         │ BLOQUEA A
├────────────────────────────────────┤
│ 1. Crear GA4 Measurement ID       │ → Banner de cookies con analytics
│ 2. Crear/confirmar Meta Pixel ID  │ → Pixel tracking + CAPI
│ 3. Generar CAPI Access Token      │ → Eventos server-side
│ 4. Verificar dominio en Meta      │ → Ads optimization (iOS 14+)
│ 5. Llenar env vars en producción  │ → TODO lo anterior
│ 6. Validar SMTP                   │ → Recovery emails
│ 7. Verificar pricing en DB        │ → Cobros correctos
│ 8. Grabar contenido               │ → Campañas de ads
│ 9. Configurar campañas            │ → Go-to-market
│ 10. Test E2E                      │ → Go-live confidence
└────────────────────────────────────┘
```

**Orden recomendado:** 1 → 2 → 3 → 5 → 4 → 6 → 10 → 7 → 8 → 9

---

*Generado automáticamente por Copilot Agent — 2026-02-25*

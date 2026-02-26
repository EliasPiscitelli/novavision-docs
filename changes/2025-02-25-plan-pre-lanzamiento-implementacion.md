# Cambio: Implementación Plan Pre-Lanzamiento (8 Fases)

- **Autor:** agente-copilot
- **Fecha:** 2025-02-25
- **Rama:** `feature/automatic-multiclient-onboarding` (admin + api)
- **Plan de referencia:** `novavision-docs/plans/PLAN-IMPLEMENTACION-PRE-LANZAMIENTO.md`

---

## Archivos Modificados / Creados

### Admin (novavision)
| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `index.html` | Modificado | Agregados scripts GA4 (deferred) y Meta Pixel (fbq, sin init hasta consent) |
| `src/utils/initTracking.js` | **Nuevo** | Controlador de tracking consent-aware: `initTracking()`, `hasConsent()`, `setConsent()`, `trackMetaEvent()` |
| `src/components/CookieConsent/index.jsx` | **Nuevo** | Banner de cookies (Ley 25.326): Accept/Reject, localStorage, link a /privacidad |
| `src/pages/TermsPage/index.jsx` | **Nuevo** | TOS SaaS completa: 15 secciones, Ley 24.240/Disp. 954/2025, planes, jurisdicción |
| `src/pages/PrivacyPage/index.jsx` | **Nuevo** | Privacy Policy: ARCO, Ley 25.326, DNPDP, cookies, transferencia internacional |
| `src/App.jsx` | Modificado | Imports + rutas `/terminos` y `/privacidad` + CookieConsent + initTracking en RouteChangeHandler |
| `.env.example` | Modificado | Agregadas `VITE_GA_MEASUREMENT_ID`, `VITE_META_PIXEL_ID` |

### API (templatetwobe)
| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `src/meta-capi/meta-capi.service.ts` | **Nuevo** | Meta CAPI service: SHA256 PII hash, fire-and-forget, Graph API v19.0, AbortSignal.timeout |
| `src/meta-capi/meta-capi.module.ts` | **Nuevo** | NestJS module exportando MetaCapiService |
| `src/recovery/recovery.service.ts` | **Nuevo** | Recovery cron cada 30min: 3 milestones (24h/48h/72h), dedupe_key, email_jobs insert |
| `src/recovery/recovery.module.ts` | **Nuevo** | NestJS module importando ConfigModule + DbModule |
| `src/subscriptions/subscriptions.module.ts` | Modificado | Import MetaCapiModule |
| `src/subscriptions/subscriptions.service.ts` | Modificado | DI MetaCapiService + CAPI Purchase event en handlePaymentSuccess + join nv_accounts |
| `src/onboarding/onboarding.module.ts` | Modificado | Import MetaCapiModule |
| `src/onboarding/onboarding.service.ts` | Modificado | DI MetaCapiService + CAPI Subscribe event en handleCheckoutWebhook + account select ampliado |
| `src/app.module.ts` | Modificado | Registro de MetaCapiModule y RecoveryModule en imports |
| `.env.example` | Modificado | Agregadas META_PIXEL_ID, META_ACCESS_TOKEN, META_TEST_EVENT_CODE, RECOVERY_ENABLED, ADMIN_BASE_URL |

### Docs (novavision-docs)
| Archivo | Acción | Descripción |
|---------|--------|-------------|
| `implementations/ACCIONES-MANUALES-PRE-LANZAMIENTO.md` | **Nuevo** | 10 acciones manuales con pasos, verificaciones y orden recomendado |

---

## Resumen de Cambios

### Fase 1 — Tracking + Consent
- GA4 y Meta Pixel se cargan en `index.html` pero **NO se inicializan** hasta que el usuario acepta cookies
- `initTracking.js` lee `localStorage.nv_cookie_consent` para decidir si activar
- `CookieConsent` persiste la decisión y llama `initTracking()` en aceptar

### Fase 2 — TOS / Privacy Policy
- Páginas legales completas para Argentina (Ley 24.240, Ley 25.326)
- Incluyen los planes/precios actuales, categorías prohibidas, derecho de arrepentimiento
- Rutas públicas `/terminos` y `/privacidad` en dark theme

### Fase 3 — Meta CAPI Backend
- `MetaCapiService` envía eventos server-side a Graph API v19.0
- Hashing SHA256 de email, external_id, country
- Fire-and-forget (no bloquea el flujo principal)
- Toggle por presencia de `META_ACCESS_TOKEN`

### Fase 4 — Recovery Emails
- `RecoveryService` cron cada 30 min busca accounts en `draft`/`awaiting_payment`
- 3 templates: 24h (recordatorio), 48h (urgencia), 72h (última oportunidad)
- Idempotente vía `dedupe_key` en `email_jobs`
- Toggle por `RECOVERY_ENABLED` env var

### Fase 5 — Hooks CAPI en flujos de pago
- `Subscribe` se envía cuando un onboarding se aprueba (nuevo cliente)
- `Purchase` se envía cuando una suscripción se renueva

### Fase 6 — Variables de entorno
- Ambos `.env.example` actualizados con todas las variables nuevas

### Fase 7 — Registro de módulos
- `MetaCapiModule` y `RecoveryModule` en `app.module.ts`

---

## Por Qué Se Hizo

Preparar la base técnica para el lanzamiento comercial de NovaVision:
1. **Cumplimiento legal**: TOS + Privacy Policy conformes a normativa argentina
2. **Attribution de ads**: GA4 + Meta Pixel + CAPI para medir conversiones end-to-end
3. **Recuperación**: Emails automáticos para reducir abandono en el onboarding
4. **Consent**: Cumplimiento de ley de protección de datos personales

---

## Cómo Probar

### Admin
```bash
cd apps/admin
npm run lint          # 0 warnings
npm run typecheck     # 0 errores
npm run build         # éxito
npm run dev           # verificar rutas /terminos, /privacidad, banner cookies
```

### API
```bash
cd apps/api
npm run lint          # 0 errores (warnings pre-existentes)
npm run typecheck     # 0 errores (tsc --noEmit)
npm run build         # éxito
npm run start:dev     # verificar logs de recovery cron + CAPI disabled (sin token)
```

### Test Manual CAPI
1. Configurar `META_PIXEL_ID` + `META_ACCESS_TOKEN` + `META_TEST_EVENT_CODE`
2. Hacer un checkout de prueba (sandbox MP)
3. Verificar en Meta Events Manager → Test Events

### Test Manual Recovery
1. Configurar `RECOVERY_ENABLED=true`
2. Crear una cuenta en `draft` con `created_at` > 24h atrás
3. Esperar al cron (o forzar llamando al método directamente)
4. Verificar que se insertó un `email_job` con `type = 'recovery_24h'`

---

## Notas de Seguridad

- `META_ACCESS_TOKEN` es un token de servidor — **NUNCA** exponerlo en frontend
- Los emails de recovery incluyen un `unsubscribe_url` placeholder (requiere implementación futura)
- Los scripts de tracking solo se activan con consentimiento explícito
- El pixel noscript en `index.html` (id `1672700600055618`) debería actualizarse si el Pixel ID es diferente

---

## Riesgos

| Riesgo | Mitigación |
|--------|-----------|
| Pixel ID hardcodeado en noscript | Actualizar si cambia el Pixel ID |
| Recovery emails molestan a usuarios | 3 max por cuenta, configurable con `RECOVERY_ENABLED` |
| CAPI token expira | Generar token de larga duración (System User) o implementar refresh |
| Consent banner no aparece (JS error) | Tracking queda inactivo (fail-safe por diseño) |

---

*Generado por Copilot Agent*

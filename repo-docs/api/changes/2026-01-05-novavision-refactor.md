# NovaVision – Onboarding checkout + Google link (stub)
**Fecha:** 2026-01-05  
**Rama:** chore/nv-refactor/20260105-multiclient  
**Ámbitos:** Backend / Admin / Onboarding

## 1) Resumen
- Se agregan endpoints de checkout en onboarding (builder token) para registrar referencia de pago y estado, en preparación para el flujo pago → login Google.
- El wizard (Paywall) consume `/onboarding/checkout/start` y consulta estado para mostrar feedback post-redirect.
- El checkout ahora crea preferencia de Mercado Pago (plataforma) y redirige a `init_point`, guardando `preference_id` y manejando retorno por query.
- Se agrega webhook firmado (`/onboarding/checkout/webhook`) que verifica el pago en MP (platform token) y marca el onboarding como `paid` de forma idempotente.

## 2) Cambios aplicados
### Backend
- Nuevos endpoints: `POST /onboarding/checkout/start`, `GET /onboarding/checkout/status`, `POST /onboarding/checkout/confirm` (con builder token), `POST /onboarding/link-google` (placeholder de vínculo post-pago).
- Servicio de onboarding persiste progreso de checkout (plan, ciclo, referencia externa, estado) reutilizando `reserveSlugForCheckout` para evitar colisiones de slug al pagar.
- `startCheckout` crea preferencia MP vía `PlatformMercadoPagoService`, guarda `preference_id`, `redirect_url`, incluye `back_urls` hacia el wizard y `notification_url` al webhook.
- Webhook `/onboarding/checkout/webhook` verifica firma (MP_WEBHOOK_SECRET), consulta el pago con `PLATFORM_MP_ACCESS_TOKEN` y marca `checkout_status`=`paid` cuando `status=approved`.

### Frontend (Admin)
- Paywall ahora inicia checkout vía backend con builder token, redirige a MP `init_point` y, al volver con `external_reference`, confirma el pago y muestra CTA para vincular Google.
- Si MP retorna con `external_reference`/`status`, el Paywall confirma contra backend y limpia la URL.

## 3) Migraciones
- No se agregaron migraciones; se reutiliza la columna `progress` de `nv_onboarding`.

## 4) Post-deploy
- Definir integración real de pago (MP/Stripe) que devuelva `redirect_url` y confirme vía webhook → `checkout/confirm`.
- Configurar frontend para redirigir al hub de auth Google tras pago y llamar a `POST /onboarding/link-google` con email/id_token.

## 5) Verificación
- [ ] `POST /onboarding/checkout/start` responde 200 con `external_reference` usando builder token válido.
- [ ] `GET /onboarding/checkout/status` refleja el estado persistido.
- [ ] Paywall muestra estado "Procesando..." al iniciar, refleja confirmación y permite vincular Google.

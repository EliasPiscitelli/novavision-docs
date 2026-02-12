# Cambio: Refactor "Actualizar Suscripción" en Tenant Admin – Cupones + Idempotencia + Modales

- **Autor:** agente-copilot
- **Fecha:** 2026-02-12
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` (`76f6e7f`) → cherry-picked a `develop` (`51fb4f2`)
  - Web: `feature/multitenant-storefront` (`1f7490c`) → cherry-picked a `develop` (`ea4d7c0`)

---

## Archivos modificados

### Backend (API – templatetwobe)

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/subscriptions/subscriptions.controller.ts` | Modificado | Nuevos params `coupon_code` + `idempotency_key` en `POST client/manage/upgrade`; nuevo endpoint `POST client/manage/validate-coupon` |
| `src/subscriptions/subscriptions.service.ts` | Modificado | `requestUpgrade()` mejorado con idempotencia, validación de cupón, descuento, incremento de uso, respuesta enriquecida; nuevo método `validateUpgradeCoupon()` |

### Frontend (Web – templatetwo)

| Archivo | Tipo | Descripción |
|---------|------|-------------|
| `src/services/subscriptionManagement.js` | Modificado | `generateIdempotencyKey()`, `requestUpgrade` con cupón + idempotencia, `validateCoupon()` |
| `src/components/admin/ConfirmModal/index.jsx` | **Nuevo** | Componente modal reutilizable con animaciones, ESC, backdrop, scroll-lock, variantes |
| `src/components/admin/SubscriptionManagement/SubscriptionManagement.jsx` | Modificado | Refactor completo: 0 `window.confirm/prompt`, 3 modales temáticos |

---

## Resumen de cambios

### Backend

1. **Soporte de cupones en upgrade:**
   - `POST client/manage/upgrade` acepta `coupon_code` opcional.
   - Valida cupón vía `CouponsService.validateCoupon()` (existencia, vigencia, límites de uso, planes elegibles).
   - Aplica descuento (`percent` o `fixed`) al precio ARS calculado.
   - Incrementa uso del cupón tras upgrade exitoso.

2. **Idempotencia:**
   - Header `X-Idempotency-Key` (generado en frontend con `crypto.randomUUID()`).
   - Chequeo previo en tabla `subscription_upgrade_log` — si existe, retorna resultado previo sin re-ejecutar.
   - Persiste resultado tras upgrade exitoso (non-critical, try/catch).

3. **Endpoint de validación de cupón:**
   - `POST client/manage/validate-coupon` para pre-validar un cupón sin consumirlo.
   - Retorna `valid`, `discount_type`, `discount_value`, `applicable_plans`.

4. **Respuesta enriquecida:**
   ```json
   {
     "ok": true,
     "status": "upgraded",
     "plan_key": "growth",
     "previous_plan_key": "starter",
     "price_ars": 45000,
     "coupon_applied": { "code": "PROMO20", "discount_type": "percent", "discount_value": 20 },
     "snapshot": { "plan_key": "growth", "billing_cycle": "monthly", "price_usd": 15, "price_ars": 45000, "blue_rate": 1400 }
   }
   ```

5. **Audit log mejorado:** Metadata incluye `coupon_code`, `coupon_discount_type`, `coupon_discount_value`.

6. **Ruta builder actualizada** con paridad de parámetros.

### Frontend

1. **ConfirmModal (nuevo componente):**
   - Overlay con `backdrop-filter: blur(4px)`, fadeIn animation.
   - Card con slideUp animation, responsive (max-width 480px).
   - Cierre con ESC, click en backdrop, body scroll-lock.
   - Estado loading con spinner, variantes `primary` | `danger`.
   - Children opcionales para contenido custom (formularios, inputs).

2. **Refactor SubscriptionManagement.jsx:**
   - **Modal de upgrade:** comparación de plan actual vs destino, input de cupón con validación en vivo (badge "Validando…" → "✓ -20%" o "✗ Cupón inválido"), precio con descuento tachado, idempotency key auto-generado.
   - **Modal de pausa:** textarea opcional para motivo, variante primary.
   - **Modal de cancelación:** variante danger, advertencia irreversible, textarea para motivo.
   - **Mensajes de éxito:** auto-dismiss a 6 segundos.
   - **Zero `window.confirm/prompt`** en todo el componente.

3. **Servicio actualizado:**
   - `generateIdempotencyKey()` con `crypto.randomUUID()`.
   - `requestUpgrade(targetPlanKey, couponCode)` envía `coupon_code` en body + `X-Idempotency-Key` en header.
   - `validateCoupon(code, planKey)` para pre-validación.

---

## Por qué se hizo

- **UX:** Los diálogos nativos del browser (`window.confirm/prompt`) no son consistentes con el design system y no permiten mostrar información contextual (precios, planes, descuentos).
- **Cupones:** El sistema de cupones existía en Admin pero no estaba integrado en el flujo de upgrade del tenant admin.
- **Idempotencia:** Protección contra doble-click o reintentos que podrían causar cobros duplicados en MercadoPago.
- **Auditabilidad:** Enriquecer el audit log con metadata de cupones para análisis financiero.

---

## Cómo probar

### Prerequisites
- API corriendo (`npm run start:dev` en terminal back)
- Web corriendo (`npm run dev` en terminal front)

### Flujo de upgrade con cupón
1. Loguearse como tenant admin (rol `admin`) en una tienda con plan `starter`.
2. Ir a **Panel de administración → Suscripción**.
3. Click en "Cambiar a Growth" → Se abre modal con comparación de planes.
4. Ingresar cupón válido (ej: `PROMO20`) → Debe mostrar badge verde con descuento.
5. Confirmar → Modal muestra spinner → Cierra con mensaje de éxito (auto-dismiss 6s).
6. Verificar en DB: `nv_accounts.plan_key = 'growth'`, `nv_subscriptions.plan_key = 'growth'`, precio actualizado.

### Flujo de upgrade sin cupón
1. Mismo flujo sin ingresar cupón → Debe funcionar normalmente.

### Idempotencia
1. Abrir DevTools → Network.
2. Hacer upgrade → Observar header `X-Idempotency-Key`.
3. Re-enviar el mismo request (copy as cURL) → Debe retornar el mismo resultado sin re-ejecutar.

### Modales de pausa/cancelación
1. Click en "Pausar suscripción" → Modal con textarea → Confirmar.
2. Click en "Cancelar suscripción" → Modal danger con advertencia → Escribir motivo → Confirmar.

### Validación de cupón
- Cupón inválido → Badge rojo "Cupón inválido".
- Cupón vencido → Badge rojo con mensaje.
- Cupón para otro plan → Badge rojo "No aplica a este plan".
- Campo vacío → Sin validación, precio normal.

---

## Validaciones ejecutadas

| Check | Resultado |
|-------|-----------|
| `npm run lint` (API) | ✅ 0 errores |
| `npm run typecheck` (API) | ✅ Clean |
| `npm run build` (API) | ✅ Success |
| `npm run lint` (Web) | ✅ 0 errores |
| `npm run typecheck` (Web) | ✅ Clean |
| `npm run build` (Web) | ✅ Success |
| Pre-push hook API (7/7) | ✅ Passed |
| Pre-push hook Web (6/6) | ✅ Passed |

---

## Notas de seguridad

- **Cupones:** La validación es server-side. El frontend pre-valida para UX pero el backend re-valida en el momento del upgrade (no confía en el frontend).
- **Idempotency key:** Generado con `crypto.randomUUID()` en el frontend, verificado en backend contra `subscription_upgrade_log`. Si la tabla no existe, el check se salta (non-blocking) — es un hardening gradual.
- **Precios:** Calculados en backend vía FxService (dólar blue) y plan config. El descuento se aplica server-side. Nunca se confía en montos enviados por el frontend.
- **Advisory lock:** Protege contra upgrades concurrentes para la misma cuenta (30s TTL).

---

## Riesgos / Rollback

- **Tabla `subscription_upgrade_log`:** Si no existe en el ambiente, la idempotencia se degrada a no-op (try/catch). Para activar completamente, crear la tabla vía migración.
- **Rollback API:** `git revert 51fb4f2` en develop o `76f6e7f` en feature.
- **Rollback Web:** `git revert ea4d7c0` en develop o `1f7490c` en feature.
- **Riesgo bajo:** Los cambios son aditivos (nuevos parámetros opcionales, nuevo componente, nuevo endpoint). El flujo existente sin cupón sigue funcionando idéntico.

---

## Migración SQL sugerida (pendiente)

```sql
-- Tabla de idempotencia para upgrades
CREATE TABLE IF NOT EXISTS subscription_upgrade_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  idempotency_key TEXT UNIQUE NOT NULL,
  account_id UUID NOT NULL REFERENCES nv_accounts(id),
  target_plan_key TEXT NOT NULL,
  result JSONB,
  created_at TIMESTAMPTZ DEFAULT now()
);

CREATE INDEX idx_upgrade_log_key ON subscription_upgrade_log(idempotency_key);
CREATE INDEX idx_upgrade_log_account ON subscription_upgrade_log(account_id);
```

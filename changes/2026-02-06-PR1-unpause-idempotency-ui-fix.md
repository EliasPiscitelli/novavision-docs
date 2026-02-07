# PR#1: Unpause Store + Idempotencia Approve + UI Subscription Fix

- **Autor:** agente-copilot
- **Fecha:** 2026-02-06
- **Rama:** feature/automatic-multiclient-onboarding
- **Prioridad:** P0

---

## Archivos modificados

### Backend (apps/api)
- `src/subscriptions/subscriptions.service.ts`
- `src/admin/admin.service.ts`

### Admin Frontend (apps/admin)
- `src/pages/Settings/BillingPage.tsx`
- `src/components/SubscriptionExpiredBanner.tsx`

---

## Resumen de cambios

### 1. `unpauseStoreIfReactivated()` — NUEVO (subscriptions.service.ts)

**Problema:** Cuando una suscripción se pausa (`suspended`, `canceled`, etc.), `pauseStoreIfNeeded()` pone `publication_status = 'paused'` en la tabla `clients` del backend. Pero NO existía la función inversa: cuando la suscripción se reactiva a `active`/`authorized`/`trialing`, la tienda quedaba pausada permanentemente.

**Fix:** Nueva función `unpauseStoreIfReactivated()` que:
- Se ejecuta automáticamente desde `syncAccountSubscriptionStatus()` (choke-point único).
- Solo despausa si `publication_status === 'paused'` Y `paused_reason` empieza con `subscription_`.
- No toca pausas manuales/admin/mantenimiento.
- Actualiza tanto `clients` (backend DB) como `nv_accounts` (admin DB: `store_paused`, `store_resumed_at`).
- `pauseStoreIfNeeded()` ahora también actualiza `nv_accounts.store_paused*` para consistencia CRM.

**Guard de seguridad:** La función verifica `paused_reason.startsWith('subscription_')` para evitar reactivar tiendas pausadas manualmente por un admin.

### 2. Idempotencia en `approveClient()` — (admin.service.ts)

**Problema:** Si un admin clickea "Aprobar" dos veces (doble-click, retry, etc.), se ejecuta provisioning duplicado, emails duplicados, y potencialmente estados inconsistentes.

**Fix:** Early return si `account.status === 'approved' || account.status === 'live'`:
```typescript
return { success: true, idempotent: true, message: `Account already ${account.status}` };
```

### 3. UI Subscription Status — (BillingPage.tsx + SubscriptionExpiredBanner.tsx)

**Problema:** Si `subscription` es null y `account.subscription_status` es null, `subStatus` queda en `'unknown'` que no tenía label → se mostraba string crudo. Además, estados como `suspended`, `cancel_scheduled`, `deactivated` no tenían label ni cobertura visual.

**Fix:**
- Agregados labels para: `trialing`, `cancel_scheduled`, `deactivated`, `incomplete`, `unknown`.
- `statusTone` ahora cubre `trialing` (success), `grace` (warning), `deactivated/cancel_scheduled` (error).
- `bannerSubscription` ahora se construye incluso cuando `subscription` es null pero hay un status negativo desde `account.subscription_status`.
- `SubscriptionExpiredBanner` expandido con cases para `suspended`, `cancel_scheduled`, `deactivated`, `unknown`.

---

## Cómo probar

### Backend

1. **Unpause automático:** 
   - Simular: cuenta con `publication_status='paused'` y `paused_reason='subscription_suspended'`.
   - Recibir webhook de MP con `authorized` → verificar que `publication_status` vuelve a `published`.
   - Verificar que `nv_accounts.store_paused = false` y `store_resumed_at` tiene fecha.

2. **Unpause NO toca pausas manuales:**
   - Cuenta con `paused_reason='admin_manual'` → recibir webhook `authorized` → verificar que NO se despausa.

3. **Idempotencia approve:**
   - Aprobar una cuenta ya aprobada → debe retornar `{ success: true, idempotent: true }` sin side effects.
   - NO debe enviar email de bienvenida duplicado.
   - NO debe re-ejecutar provisioning.

### Frontend

4. **UI sin subscription:**
   - Cuenta nueva sin subscription → debe mostrar "Sin información" (no string crudo `unknown`).
   - Banner debe mostrar "Sin Información de Suscripción" si status viene de `account.subscription_status` pero no hay objeto subscription.

5. **UI suspended:**
   - Cuenta con `subscription_status='suspended'` → badge rojo "Suspendida" + banner "Tu tienda no está visible".

---

## Validaciones ejecutadas

- `npm run typecheck` (API): ✅ 0 errors
- `npm run typecheck` (Admin): ✅ 0 errors

---

## Notas de seguridad

- `unpauseStoreIfReactivated` verifica `paused_reason` antes de actuar (no overridea pausas admin).
- La función de idempotencia no expone información sensible en la respuesta.
- Ambas funciones (pause/unpause) están en try-catch para no romper el flujo principal.

---

## Riesgos y mitigación

| Riesgo | Mitigación |
|--------|------------|
| In-memory lock (`subLocks`) no funciona multi-instancia Railway | Fuera de scope de este PR — requiere Redis/DB advisory lock (PR futuro) |
| Columnas `paused_reason`, `store_paused*` podrían no existir en algún ambiente | Supabase ignora columnas desconocidas en update — fail silencioso, no rompe |
| Race condition entre pause y unpause simultáneos | Ambas operaciones son idempotentes y la última gana (eventually consistent) |

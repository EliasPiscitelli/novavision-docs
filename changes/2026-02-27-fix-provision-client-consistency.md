# Fix: Consistencia completa de datos en `provisionClient()` + Fix manual Farma

- **Autor:** agente-copilot
- **Fecha:** 2026-02-27
- **Rama:** `feature/automatic-multiclient-onboarding`
- **Archivos modificados:**
  - `apps/api/src/worker/provisioning-worker.service.ts`

---

## Resumen

Se encontraron **5 bugs críticos** en la función `provisionClient()` (path legacy de provisioning) que causaban inconsistencia de datos en la tabla `clients` del Backend DB. La función `provisionClientFromOnboarding()` ya manejaba todos estos campos correctamente.

### Bugs corregidos en `provisionClient()`:

| # | Bug | Antes | Después |
|---|-----|-------|---------|
| 1 | `monthly_fee` hardcodeado | `monthly_fee: 0` siempre | Lee de tabla `plans` vía `plan_key` |
| 2 | `plan_key` nunca escrito | Defaulteaba a `'starter'` (column default) | Escribe `plan_key: account.plan_key` |
| 3 | `billing_period` nunca escrito | null | Escribe `billing_period: 'monthly'` |
| 4 | Campos de contacto faltantes | `legal_name`, `billing_email`, `phone`, `phone_full` no se escribían | Se incluyen en el upsert |
| 5 | MP credentials no se sincronizaban | `syncMpCredentialsToBackend()` nunca se llamaba | Se llama después de crear el client (igual que `provisionClientFromOnboarding`) |

### Mejoras adicionales:

- **`getAccount()`**: Se amplió el `SELECT` para traer los campos faltantes: `status, user_id, mp_connected, legal_name, billing_email, phone, phone_full`
- **Locale/timezone**: Se agrega resolución de `locale` y `timezone` basada en `country` (mapa estático AR/MX/CL/CO)

---

## Fix manual: Farma (client_id: `1fad8213-1d2f-46bb-bae2-24ceb4377c8a`)

Farma fue provisionada por el path legacy `PROVISION_CLIENT` y tenía datos incorrectos. Se ejecutaron 2 fixes manuales:

### 1. UPDATE SQL en Backend DB

```sql
UPDATE clients SET
  plan = 'growth', plan_key = 'growth', monthly_fee = 60.00, billing_period = 'monthly',
  entitlements = '{"is_dedicated": false, "custom_domain": true, "products_limit": 2000, ...}'::jsonb,
  mp_public_key = 'APP_USR-9e1675d3-5b23-4d31-bb96-ea85ac6532b2',
  persona_type = 'natural', legal_name = 'Farma', fiscal_id = '27425874956',
  fiscal_id_type = 'CUIT', fiscal_category = 'monotributista',
  fiscal_address = 'jilguero 30 Barrio Los Sauces Nordelta', subdivision_code = 'BA',
  country = 'AR', locale = 'es-AR', timezone = 'America/Argentina/Buenos_Aires',
  phone = '+54 9 11 3118-1802', phone_full = '+54 9 11 3118-1802',
  billing_email = 'mariabelenlauria@gmail.com'
WHERE id = '1fad8213-1d2f-46bb-bae2-24ceb4377c8a';
```

### 2. Script de desencriptación y sync de `mp_access_token`

Se desencriptó `nv_accounts.mp_access_token_encrypted` usando AES-256-GCM y se escribió el token en texto plano a `clients.mp_access_token`.

---

## Root Cause Analysis

Farma fue creada via `PROVISION_CLIENT` job (payload: `{"trial": true}`) en lugar de `PROVISION_CLIENT_FROM_ONBOARDING`. El path legacy no leía la tabla `plans` para el `monthly_fee`, no escribía `plan_key`, y no sincronizaba credenciales de MP.

### Flujo de MP credentials:
1. El usuario conecta MP durante onboarding → se guarda `mp_access_token_encrypted` y `mp_public_key` en `nv_accounts` (Admin DB)
2. Durante provisioning, `syncMpCredentialsToBackend()` desencripta el token y lo escribe a `clients` (Backend DB)
3. El checkout lee `clients.mp_access_token` del Backend DB para crear preferencias de pago
4. **Bug**: `provisionClient()` no llamaba a `syncMpCredentialsToBackend()`, por lo que `clients.mp_access_token` quedaba null

---

## Cómo probar

1. Crear un nuevo trial account con MP conectado
2. Verificar que el job `PROVISION_CLIENT` se procese correctamente
3. Confirmar en Backend DB que:
   - `plan_key` = valor correcto (no 'starter')
   - `monthly_fee` = valor del plan (no 0)
   - `mp_access_token` y `mp_public_key` están presentes
   - `legal_name`, `phone`, `billing_email` están populados
   - `locale` y `timezone` están seteados

---

## Validación

```bash
npm run lint      # ✅ 0 errors
npm run typecheck  # ✅ 0 errors
npm run build      # ✅ exitoso
```

## Notas de seguridad

- Los tokens de MP se manejan siempre encriptados en Admin DB y en texto plano solo en Backend DB (que no es accesible desde el frontend)
- El script de fix manual (`/tmp/sync_mp_farma.cjs`) fue one-time y debe eliminarse después de uso

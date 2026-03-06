# Fix: Cart "Acceso No Autorizado" + MP Status Labels (farma)

- **Autor:** agente-copilot
- **Fecha:** 2026-03-06
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/multitenant-storefront (→ develop → cherry-pick)

---

## Bug 1: Cart "Acceso No Autorizado" estando logueado

### Problema
Usuarios logueados en la tienda farma veían "Acceso No Autorizado" al intentar acceder al carrito u otras rutas protegidas.

### Causa raíz
Race condition en `AuthProvider.jsx`: `syncMembership` (que resuelve el rol vía `POST /auth/session/sync`) se ejecutaba **sin `await`**, pero `authReady` se seteaba a `true` inmediatamente después. `PrivateRoute` veía `isLoading=false` + `role=null` → redirigía a `/unauthorized` antes de que el sync completara.

### Archivos modificados (Web)

**`src/context/AuthProvider.jsx`**
- Agregado `await` a las 2 llamadas a `syncMembershipRef.current()` (L165 envelope path, L203 getSession path)
- Agregado fallback `setRole(prev => prev ?? 'user')` en el catch de syncMembership para evitar que role quede en null si falla el sync

**`src/routes/PrivateRoute.jsx`**
- Safety net: si `allowedRoles` está definido y `role === null` pero el usuario existe, muestra loading en vez de redirigir a `/unauthorized`

### Cómo probar
1. Loguearse en farma.novavision.lat con un usuario existente
2. Navegar al carrito → no debe mostrar "Acceso No Autorizado"
3. Navegar a rutas protegidas como /admin-dashboard con usuario admin → debe cargar correctamente
4. Con usuario role=user intentar acceder a /admin-dashboard → debe redirigir a /unauthorized (comportamiento correcto)

---

## Bug 2: MP mostraba "Desconectado" pese a estar configurado

### Problema
En el dashboard admin de farma, el widget de Mercado Pago mostraba "Desconectado ❌" a pesar de que MP estaba correctamente configurado con tokens de API directos.

### Causa raíz
El widget solo tenía 2 estados: "Conectado" (OAuth) o "Desconectado". Para tiendas que usan API keys directas (sin OAuth), `nv_accounts.mp_connected = false` (correcto, no usaron OAuth), pero el widget lo interpretaba como "no configurado".

Adicionalmente, si el usuario tenía metadata JWT desactualizada (role=user en JWT, pero role=admin en DB), el endpoint `GET /mp/oauth/status/:clientId` (protegido con `@Roles('admin', 'super_admin')`) retornaba 403, y el frontend silenciosamente mostraba `{ connected: false }`.

### Archivos modificados (API)

**`src/mp-oauth/mp-oauth.service.ts`**
- En `getConnectionStatus`: cuando `mp_connected = false`, ahora también consulta `clients.mp_access_token` en Backend DB
- Retorna nuevo campo `has_api_keys: boolean` indicando si hay tokens de API directos configurados

**`src/mp-oauth/mp-oauth.controller.ts`**
- Expone `has_api_keys` en la respuesta del endpoint status

### Archivos modificados (Web)

**`src/components/admin/PaymentsConfig/index.jsx`**
- Widget de 3 estados:
  - `connected=true` → "Conectado (OAuth) ✅"
  - `connected=false && has_api_keys=true` → "Configurado (API) ✅"
  - `connected=false && !has_api_keys` → "No configurado ❌"

### Cómo probar
1. Acceder al dashboard admin de farma con usuario admin
2. Ir a la sección de pagos → debe mostrar "Configurado (API) ✅" (farma usa API keys directas)
3. Para tiendas con OAuth: debe mostrar "Conectado (OAuth) ✅"
4. Para tiendas sin configuración: debe mostrar "No configurado ❌"

---

## Validación de base de datos realizada

### Admin DB (nv_accounts) - farma
| Campo | Valor | Estado |
|-------|-------|--------|
| mp_connected | true | ✅ |
| allow_mp_reconnect | false | ✅ |
| mp_access_token_encrypted | HAS_TOKEN | ✅ |
| mp_public_key | HAS_KEY | ✅ |
| status | approved | ✅ |
| store_paused | false | ✅ |

### Backend DB (clients) - farma
| Campo | Valor | Estado |
|-------|-------|--------|
| is_active | true | ✅ |
| mp_access_token | HAS | ✅ |
| mp_public_key | HAS | ✅ |
| publication_status | published | ✅ |
| is_published | true | ✅ |
| maintenance_mode | false | ✅ |
| nv_account_id | f6740bf8... (match con Admin DB) | ✅ |

### Sincronización cross-DB: ✅ Correcta

---

## Notas de seguridad
- No se modificaron guards ni permisos de endpoints
- El fix de race condition NO cambia la lógica de autorización, solo asegura que el rol se resuelva ANTES de evaluar acceso
- El campo `has_api_keys` no expone valores de tokens, solo indica si existen

---

## Referencia: Variables de entorno Mercado Pago

### OAuth — Identidad de la aplicación (clientes conectan su MP)

| Variable | Propósito | Dónde se obtiene |
|----------|-----------|-----------------|
| `MP_CLIENT_ID` | ID de la app MP de NovaVision | Panel de desarrolladores MP → tu app → Credenciales de producción |
| `MP_CLIENT_SECRET` | Secreto de la app MP | Mismo panel → Credenciales de producción |
| `MP_REDIRECT_URI` | URL callback OAuth | Debe coincidir con la registrada en la app MP |
| `MP_TOKEN_ENCRYPTION_KEY` | Clave AES-256 para cifrar tokens OAuth de clientes en DB | Se genera una vez, **no cambiar** (rompe tokens existentes) |

### Platform Payments — NovaVision cobra suscripciones

| Variable | Propósito | Dónde se obtiene |
|----------|-----------|-----------------|
| `PLATFORM_MP_ACCESS_TOKEN` | Access token de la cuenta que recibe pagos de suscripciones | Panel de desarrolladores → Credenciales → Access Token |
| `MP_WEBHOOK_SECRET_PLATFORM` | Secreto HMAC para validar webhooks de pagos de plataforma | Panel de desarrolladores → Webhooks → Secret |
| `MP_SANDBOX_MODE` | `true` sandbox / `false` producción | Configuración manual |
| `MP_TEST_PAYER_EMAIL` | Email de test user (solo sandbox) | Panel de test users de MP |

### Webhook Validation — Pagos de tiendas (tenants)

| Variable | Propósito |
|----------|-----------|
| `MP_WEBHOOK_SECRET_TENANT` | Secreto HMAC para webhooks de pagos de tiendas de clientes |

### Escenarios de cambio

- **Cambiar app OAuth** (nueva aplicación MP): actualizar `MP_CLIENT_ID`, `MP_CLIENT_SECRET`, `MP_REDIRECT_URI`
- **Cambiar cuenta receptora** (la que cobra suscripciones): actualizar `PLATFORM_MP_ACCESS_TOKEN`, `MP_WEBHOOK_SECRET_PLATFORM`
- **Cuenta nueva completa**: actualizar los 5 de arriba
- **NUNCA cambiar** `MP_TOKEN_ENCRYPTION_KEY` (los tokens de clientes existentes se vuelven irrecuperables)

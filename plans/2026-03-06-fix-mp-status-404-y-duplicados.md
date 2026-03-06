# Plan Productivo: Fix MP Status 404 + Eliminar Llamados Duplicados + Optimizar Carga

- **Fecha**: 2026-03-06
- **Autor**: agente-copilot
- **Estado**: Pendiente aprobación TL
- **Ramas afectadas**:
  - API: `feature/automatic-multiclient-onboarding` (repo `templatetwobe`)
  - Web: `develop` → cherry-pick a `feature/multitenant-storefront` + `feature/onboarding-preview-stable` (repo `templatetwo`)

## Estado productivo actual validado

Validación hecha contra las bases reales usando `BACKEND_DB_URL` y `ADMIN_DB_URL` desde `apps/api/.env`.

### Backend DB (`clients`)

- Cantidad total de clientes: `1`
- Cliente actual:
  - `clients.id = 1fad8213-1d2f-46bb-bae2-24ceb4377c8a`
  - `clients.slug = farma`
  - `clients.name = Farma`
  - `clients.is_active = true`
  - `clients.nv_account_id = f6740bf8-9a6d-495f-ae61-9e61aeeceea9`
  - `clients.mp_access_token IS NOT NULL = true`
  - `clients.mp_public_key IS NOT NULL = true`
  - `clients.publication_status = published`
  - `clients.maintenance_mode = false`
  - `clients.deleted_at = null`

### Admin DB (`nv_accounts`)

- Cuenta vinculada a `farma`:
  - `nv_accounts.id = f6740bf8-9a6d-495f-ae61-9e61aeeceea9`
  - `nv_accounts.slug = farma`
  - `nv_accounts.mp_connected = true`
  - `nv_accounts.mp_connection_status = connected`
  - `nv_accounts.allow_mp_reconnect = false`
  - `nv_accounts.mp_access_token_encrypted IS NOT NULL = true`

### Conclusión operativa

- Hoy el impacto productivo real está concentrado en una sola tienda: `farma`
- Aunque sea una sola tienda, el plan se deja definido para **estado productivo general**, no solo para entorno de prueba
- La solución elegida debe ser segura para:
  - el estado productivo actual (`farma`)
  - próximos tenants que entren a producción
  - onboarding actual del admin
  - callback OAuth ya registrado en Mercado Pago

---

## Resumen del problema

| # | Bug | Impacto | Severidad |
|---|-----|---------|-----------|
| 1 | El endpoint `GET /api/mp/oauth/status/:clientId` devuelve **404 Not Found** | Widget de MP en panel admin de tiendas muestra "No configurado ❌" aunque MP esté conectado | **P0 — Blocker** |
| 2 | Llamados HTTP duplicados en carga de página (2x `getMpConnectionStatus`, 2x config) | Carga lenta, waste de recursos, UX degradada | **P1** |
| 3 | Carga de página tarda ~18s en reload con ~48 requests | UX inaceptable para tiendas en producción | **P2** |

---

## Checklist Ejecutable Por Archivo

Esta sección reemplaza cualquier lectura ambigua del plan. La implementación recomendada para este incidente se hace archivo por archivo y en este orden.

### Archivo 1: `apps/web/src/services/payments.js`

**Objetivo**: corregir el descalce de rutas MP OAuth en el storefront sin tocar backend, admin ni configuración de Mercado Pago.

#### Cambios exactos a hacer

- Buscar `getMpConnectionStatus(clientId)`
- Reemplazar:
  ```js
  const res = await api.get(`/api/mp/oauth/status/${clientId}`);
  ```
  por:
  ```js
  const res = await api.get(`/mp/oauth/status/${clientId}`);
  ```

- Buscar `getMpOauthStartUrl()`
- Reemplazar:
  ```js
  const res = await api.get("/api/mp/oauth/start-url");
  ```
  por:
  ```js
  const res = await api.get("/mp/oauth/start-url");
  ```

- Buscar `disconnectMp(clientId)`
- Reemplazar:
  ```js
  const res = await api.post(`/api/mp/oauth/disconnect/${clientId}`);
  ```
  por:
  ```js
  const res = await api.post(`/mp/oauth/disconnect/${clientId}`);
  ```

#### Checklist de implementación

- [ ] Confirmar que solo cambian esas 3 rutas
- [ ] No tocar `getPaymentConfig()`
- [ ] No tocar `updatePaymentConfig()`
- [ ] No tocar `quotePayment()`
- [ ] No cambiar otros endpoints que sí dependen de `/api/*`

#### Validación inmediata de este archivo

- [ ] Verificar que el diff solo afecte las 3 rutas MP OAuth
- [ ] Verificar que las funciones exportadas sigan teniendo el mismo nombre
- [ ] Verificar que no cambie ninguna firma pública del service

#### Riesgos específicos de este archivo

- Riesgo: remover `/api/` de endpoints que sí dependen de controllers con prefix `api`
- Mitigación: limitar el cambio solo a `status`, `start-url`, `disconnect`

### Archivo 2: `apps/web/src/components/admin/PaymentsConfig/index.jsx`

**Objetivo**: eliminar llamadas duplicadas al estado MP y hacer robusta la carga en producción con `StrictMode`.

#### Cambios exactos a hacer

1. Agregar un ref nuevo junto a `loadedRef`

```jsx
const mpLoadedRef = useRef(false);
```

2. Eliminar estos dos bloques separados:

- el bloque `/* load mp status */`
- el bloque `/* detect mp_connected param from OAuth callback */`

3. Reemplazarlos por un único bloque consolidado.

#### Implementación objetivo

El bloque nuevo debe cumplir estas reglas:

- ejecutarse solo si `tenant?.id` existe
- leer `window.location.search`
- detectar `mp_connected=true`
- hacer una sola llamada a `getMpConnectionStatus(tenant.id)`
- setear `setMpStatus(status)`
- mostrar `showToast(...)` solo si viene de callback OAuth y `status.connected === true`
- limpiar el query param `mp_connected`
- usar `mpLoadedRef.current` para evitar doble fetch por `StrictMode`
- permitir retry si la request falla

#### Pseudocódigo operativo aceptado

```jsx
const mpLoadedRef = useRef(false);

useEffect(() => {
  if (!tenant?.id) return;

  const params = new URLSearchParams(window.location.search);
  const fromOAuthCallback = params.get("mp_connected") === "true";

  if (mpLoadedRef.current && !fromOAuthCallback) return;
  if (fromOAuthCallback) mpLoadedRef.current = false;

  setLoadingMp(true);
  getMpConnectionStatus(tenant.id)
    .then((status) => {
      setMpStatus(status);
      mpLoadedRef.current = true;
      if (fromOAuthCallback && status?.connected) {
        showToast({
          message: "Mercado Pago conectado correctamente ✅",
          status: "success",
        });
      }
    })
    .catch(() => {
      setMpStatus({ connected: false });
    })
    .finally(() => {
      setLoadingMp(false);
    });

  if (fromOAuthCallback) {
    params.delete("mp_connected");
    const newSearch = params.toString();
    const newUrl = `${window.location.pathname}${newSearch ? `?${newSearch}` : ""}`;
    window.history.replaceState({}, "", newUrl);
  }
}, [tenant?.id]);
```

#### Checklist de implementación

- [ ] Agregar `mpLoadedRef`
- [ ] Eliminar ambos `useEffect` duplicados de MP status
- [ ] Dejar un solo `useEffect` para MP status
- [ ] Mantener el `showToast` de conexión exitosa
- [ ] Mantener la limpieza del query param `mp_connected`
- [ ] No tocar el `useEffect` de `getPaymentConfig()`
- [ ] No tocar `handleDisconnectMp()`
- [ ] No tocar `handleSave()`

#### Validación inmediata de este archivo

- [ ] Verificar que en el diff desaparezcan los dos effects viejos
- [ ] Verificar que exista un solo lugar que llame a `getMpConnectionStatus(tenant.id)` dentro del componente
- [ ] Verificar que el toast de éxito siga existiendo
- [ ] Verificar que `mp_connected` se limpie de la URL después del callback

#### Riesgos específicos de este archivo

- Riesgo: impedir recarga real del estado MP después de volver del OAuth callback
- Mitigación: si `fromOAuthCallback === true`, resetear `mpLoadedRef.current = false` antes del fetch

- Riesgo: perder el mensaje de éxito después de conectar MP
- Mitigación: conservar `showToast` dentro del mismo bloque consolidado

### Archivo 3: `apps/web/src/main.jsx`

**Objetivo**: solo verificación, no cambio funcional en este incidente.

#### Qué verificar

- Existe `StrictMode` en producción:
  ```jsx
  const Root = import.meta.env.DEV ? (
    <App />
  ) : (
    <StrictMode>
      <App />
    </StrictMode>
  );
  ```

#### Checklist de implementación

- [ ] No editar este archivo en este incidente
- [ ] Usarlo solo como evidencia para justificar el guard anti doble-fetch

### Archivo 4: `apps/api/src/mp-oauth/mp-oauth.controller.ts`

**Objetivo**: solo verificación, no cambio funcional en este incidente.

#### Qué verificar

- `@Controller('mp/oauth')` se mantiene sin cambios
- `start()` sigue disponible para admin/onboarding
- `callback()` sigue disponible para `MP_REDIRECT_URI`
- `status/:clientId`, `start-url`, `disconnect/:clientId` siguen en el mismo controller

#### Checklist de implementación

- [ ] No editar este archivo en este incidente
- [ ] No cambiar decorator del controller
- [ ] No agregar prefix `api/`
- [ ] No tocar guards ni cross-tenant checks

### Archivo 5: `apps/admin/src/pages/BuilderWizard/steps/Step7MercadoPago.tsx`

**Objetivo**: verificación de compatibilidad.

#### Qué verificar

- La URL actual siga siendo:
  ```ts
  window.location.href = `${baseUrl}/mp/oauth/start?token=${tokenParam}`;
  ```

#### Checklist de implementación

- [ ] No editar este archivo
- [ ] Confirmar que el plan no rompe esta ruta

### Archivo 6: `apps/admin/src/pages/BuilderWizard/steps/Step9MPCredentials.tsx`

**Objetivo**: verificación de compatibilidad.

#### Qué verificar

- La URL actual siga siendo:
  ```ts
  const authUrl = `${API_URL}/mp/oauth/start?token=${encodeURIComponent(state.builderToken || '')}`;
  ```

#### Checklist de implementación

- [ ] No editar este archivo
- [ ] Confirmar que el plan no rompe esta ruta

### Archivo 7: `apps/api/.env`

**Objetivo**: verificación operativa, no cambio.

#### Qué verificar

- `MP_REDIRECT_URI=https://api.novavision.lat/mp/oauth/callback`

#### Checklist de implementación

- [ ] No editar `.env` para este incidente
- [ ] No cambiar `MP_REDIRECT_URI`
- [ ] No rotar credenciales MP

---

## Paso a Paso de Implementación

### Etapa A — Preparación

- [ ] Abrir `apps/web/src/services/payments.js`
- [ ] Abrir `apps/web/src/components/admin/PaymentsConfig/index.jsx`
- [ ] Tener abierto el plan actual para seguirlo en paralelo

### Etapa B — Cambio de rutas MP OAuth

- [ ] Cambiar `status` a `/mp/oauth/status/${clientId}`
- [ ] Cambiar `start-url` a `/mp/oauth/start-url`
- [ ] Cambiar `disconnect` a `/mp/oauth/disconnect/${clientId}`
- [ ] Guardar archivo

### Etapa C — Eliminación de doble-fetch

- [ ] Agregar `mpLoadedRef`
- [ ] Eliminar effect 1 de MP status
- [ ] Eliminar effect 2 de callback MP
- [ ] Crear effect consolidado
- [ ] Verificar que el query param `mp_connected` se limpia
- [ ] Guardar archivo

### Etapa D — Validación estática

- [ ] Revisar diff completo
- [ ] Confirmar que solo hay cambios en 2 archivos de `apps/web`
- [ ] Confirmar que no hay cambios en `apps/api`
- [ ] Confirmar que no hay cambios en `apps/admin`

### Etapa E — Validación por comandos

En `apps/web`:

```bash
npm run lint
npm run typecheck
npm run build
```

Checklist:

- [ ] `lint` OK
- [ ] `typecheck` OK
- [ ] `build` OK

### Etapa F — Validación funcional local/preview

- [ ] Abrir tab pagos de `farma`
- [ ] Confirmar que no existe request a `/api/mp/oauth/status/...`
- [ ] Confirmar que sí existe request a `/mp/oauth/status/...`
- [ ] Confirmar response 200
- [ ] Confirmar que el widget no muestra `No configurado ❌`
- [ ] Confirmar que no hay doble request de MP status en carga normal

### Etapa G — Validación de compatibilidad cruzada

- [ ] Verificar que onboarding admin sigue redirigiendo a `/mp/oauth/start`
- [ ] Verificar que no cambió `MP_REDIRECT_URI`
- [ ] Verificar que no se tocó el backend

### Etapa H — Rollout productivo

- [ ] Merge/commit en flujo correcto de web
- [ ] Deploy controlado
- [ ] Smoke test sobre `farma`

### Etapa I — Rollback si falla

- [ ] Revertir `apps/web/src/services/payments.js`
- [ ] Revertir `apps/web/src/components/admin/PaymentsConfig/index.jsx`
- [ ] Rebuild/redeploy web
- [ ] Confirmar que onboarding y callback siguen sanos

---

## FASE 1 — Fix 404 en MP Status (P0)

### Causa raíz verificada

El **controller** del backend registra las rutas bajo `mp/oauth`:

```
Archivo: apps/api/src/mp-oauth/mp-oauth.controller.ts (línea 24)
Código:  @Controller('mp/oauth')
```

El **frontend web** (storefront) llama a estas rutas con el prefijo `/api/`:

```
Archivo: apps/web/src/services/payments.js (líneas 192, 201, 206)
Código:
  api.get(`/api/mp/oauth/status/${clientId}`)       → 404
  api.get("/api/mp/oauth/start-url")                → 404
  api.post(`/api/mp/oauth/disconnect/${clientId}`)   → 404
```

El backend **NO tiene** `app.setGlobalPrefix('api')` en `main.ts` (verificado líneas 1-160). Cada controller define su propio prefijo. Los controllers que funcionan bajo `/api/` lo tienen explícito:

| Controller | Decorator | Funciona? |
|------------|-----------|-----------|
| `cart.controller.ts` L29 | `@Controller('api/cart')` | ✅ |
| `payments.controller.ts` L20 | `@Controller('api/payments')` | ✅ |
| `admin-payments.controller.ts` L22 | `@Controller('api/admin/payments')` | ✅ |
| `analytics.controller.ts` L8 | `@Controller('api/analytics')` | ✅ |
| `mp-oauth.controller.ts` L24 | `@Controller('mp/oauth')` | ✅ |

La conclusión correcta no es que al controller de MP OAuth le "falte" `api/`.
La conclusión correcta es que existe un **descalce de rutas**:

- backend real: `mp/oauth/*`
- web storefront actual: `/api/mp/oauth/*`
- admin app actual: `/mp/oauth/*`

### ⚠️ RIESGO CRÍTICO — NO se puede cambiar el controller

Cambiar `@Controller('mp/oauth')` → `@Controller('api/mp/oauth')` **ROMPERÍA**:

1. **Admin App (Builder Wizard)** — llama directo sin prefix `api/`:
   - `apps/admin/src/pages/BuilderWizard/steps/Step9MPCredentials.tsx` L128:
     ```js
     const authUrl = `${API_URL}/mp/oauth/start?token=...`
     ```
   - `apps/admin/src/pages/BuilderWizard/steps/Step7MercadoPago.tsx` L82:
     ```js
     window.location.href = `${baseUrl}/mp/oauth/start?token=${tokenParam}`
     ```

2. **Mercado Pago OAuth Redirect URI** — configurada en `.env` y en la cuenta de MP:
   ```
   MP_REDIRECT_URI=https://api.novavision.lat/mp/oauth/callback
   ```
   Cambiar el controller haría que el callback sea `/api/mp/oauth/callback` pero MercadoPago redirigiría a `/mp/oauth/callback` → **OAuth flow roto para TODOS los clientes**.

3. **Estado productivo actual de `farma`**:
  - hoy `farma` ya tiene `clients.mp_access_token`
  - hoy `farma` ya tiene `nv_accounts.mp_connected = true`
  - hoy `farma` ya tiene `nv_accounts.mp_access_token_encrypted`
  - un cambio de ruta en backend generaría una regresión sobre una tienda ya publicada

### Solución: Corregir rutas en el FRONTEND web

Remover el prefijo `/api/` de las 3 llamadas en `apps/web/src/services/payments.js`:

#### Cambio exacto

**Archivo**: `apps/web/src/services/payments.js`

| Línea | Antes | Después |
|-------|-------|---------|
| 192 | `api.get(\`/api/mp/oauth/status/${clientId}\`)` | `api.get(\`/mp/oauth/status/${clientId}\`)` |
| 201 | `api.get("/api/mp/oauth/start-url")` | `api.get("/mp/oauth/start-url")` |
| 206 | `api.post(\`/api/mp/oauth/disconnect/${clientId}\`)` | `api.post(\`/mp/oauth/disconnect/${clientId}\`)` |

#### Verificación de que las rutas correctas existen en el controller

| Método HTTP | Ruta backend real | Método controller (mp-oauth.controller.ts) |
|-------------|-------------------|--------------------------------------------|
| GET | `/mp/oauth/status/:clientId` | `getStatus()` (L212) |
| GET | `/mp/oauth/start-url` | `startUrl()` (L141) |
| POST | `/mp/oauth/disconnect/:clientId` | `disconnect()` (L244) |
| GET | `/mp/oauth/start` | `start()` (L41) — usado por admin, no por web |
| GET | `/mp/oauth/callback` | `callback()` (L86) — redirect de MP |

#### Impacto de esta solución

- ✅ **Web storefront**: las 3 rutas pasan a funcionar (status, start-url, disconnect)
- ✅ **Admin app**: sin cambios, sigue funcionando como antes
- ✅ **Mercado Pago OAuth**: sin cambios, MP_REDIRECT_URI sigue siendo `/mp/oauth/callback`
- ✅ **Webhooks**: sin cambios, son `@Controller('webhooks/mp')` — ruta completamente diferente
- ✅ **Cliente productivo actual `farma`**: no requiere migración de DB ni cambio de configuración en MP

#### Guards y middleware que aplican

El controller usa:
- `@UseGuards(RolesGuard)` + `@Roles('admin', 'super_admin')` en `status`, `start-url`, y `disconnect`
- Cross-tenant protection: `req.clientId !== clientId` → 403 (L218-L223)
- `@AllowNoTenant()` en `start` y `callback` (OAuth flow no tiene tenant context)

#### Flujo de la request completo (verificado)

```
Web storefront → axios GET /mp/oauth/status/:clientId
  → axiosConfig interceptor agrega:
    - Authorization: Bearer <supabase_jwt>
    - x-tenant-slug: <slug>
  → Backend AuthMiddleware extrae JWT → req.user
  → Backend TenantContextGuard resuelve slug → req.clientId
  → RolesGuard verifica role in ('admin', 'super_admin')
  → MpOauthController.getStatus() verifica req.clientId === param.clientId
  → MpOauthService.getConnectionStatus(clientId)
    → Backend DB: clients.slug, clients.nv_account_id  (tabla clients, campo id = clientId)
    → Admin DB: nv_accounts.mp_connected, mp_live_mode, etc. (tabla nv_accounts, campo id = account.id)
    → Backend DB: clients.mp_access_token (para has_api_keys) (tabla clients, campo id = clientId)
  → Response: { connected, live_mode, expires_at, status, mp_user_id, allow_mp_reconnect, has_api_keys }
```

---

## FASE 2 — Eliminar llamados duplicados (P1)

### 2.1 — Consolidar useEffects duplicados en PaymentsConfig

#### Causa raíz verificada

**Archivo**: `apps/web/src/components/admin/PaymentsConfig/index.jsx`

Hay **2 useEffects** que llaman a `getMpConnectionStatus(tenant.id)`:

**useEffect #1** (línea ~181): Carga MP status al montar
```jsx
useEffect(() => {
  if (!tenant?.id) return;
  setLoadingMp(true);
  getMpConnectionStatus(tenant.id)
    .then(setMpStatus)
    .catch(() => setMpStatus({ connected: false }))
    .finally(() => setLoadingMp(false));
}, [tenant?.id]);
```

**useEffect #2** (línea ~190): Detecta param `mp_connected` del callback OAuth
```jsx
useEffect(() => {
  const params = new URLSearchParams(window.location.search);
  if (params.get("mp_connected") === "true" && tenant?.id) {
    setLoadingMp(true);
    getMpConnectionStatus(tenant.id)
      .then((status) => { ... })
      .catch(() => setMpStatus({ connected: false }))
      .finally(() => setLoadingMp(false));
    // Clean up URL param...
  }
}, [tenant?.id]);
```

**Problema**: Ambos se ejecutan cuando `tenant?.id` cambia. En la carga normal (sin `?mp_connected=true`), el useEffect #2 se ejecuta pero su `if` no entra → no llama a la API. Pero si hay `?mp_connected=true` en la URL, **ambos** llaman a `getMpConnectionStatus` al mismo tiempo → 2 requests iguales.

Sin embargo, **incluso sin** el param, en React 18 StrictMode (que está activo en producción según la investigación previa), los effects se re-ejecutan, causando doble llamada del useEffect #1.

#### Cambio exacto

**Archivo**: `apps/web/src/components/admin/PaymentsConfig/index.jsx`

Consolidar ambos useEffects en **uno solo**:

```jsx
/* load mp status (+ detect mp_connected param from OAuth callback) */
useEffect(() => {
  if (!tenant?.id) return;
  
  const params = new URLSearchParams(window.location.search);
  const fromOAuthCallback = params.get("mp_connected") === "true";
  
  setLoadingMp(true);
  getMpConnectionStatus(tenant.id)
    .then((status) => {
      setMpStatus(status);
      if (fromOAuthCallback && status?.connected) {
        showToast({ message: "Mercado Pago conectado correctamente ✅", status: "success" });
      }
    })
    .catch(() => setMpStatus({ connected: false }))
    .finally(() => setLoadingMp(false));

  // Clean up URL param if present
  if (fromOAuthCallback) {
    params.delete("mp_connected");
    const newSearch = params.toString();
    const newUrl = `${window.location.pathname}${newSearch ? `?${newSearch}` : ""}`;
    window.history.replaceState({}, "", newUrl);
  }
}, [tenant?.id]);
```

**Resultado**: 1 sola llamada a `getMpConnectionStatus` por mount, con o sin `?mp_connected=true`.

#### Riesgo de `showToast` en dependencias

`showToast` viene de `useToast()` hook. Si su identidad cambia entre renders, NO importa aquí porque no está en el array de dependencias — es un patrón de stale closure aceptable dado que `showToast` es estable (context value).

### 2.2 — Guard contra StrictMode en el useEffect de MP status

Para evitar doble-fetch por React StrictMode (que sí está activo en producción, verificado en el build), agregar un `loadedRef` similar al que ya existe para `getPaymentConfig`:

```jsx
const mpLoadedRef = useRef(false);

useEffect(() => {
  if (!tenant?.id) return;
  if (mpLoadedRef.current) return; // guard StrictMode re-mount
  
  const params = new URLSearchParams(window.location.search);
  const fromOAuthCallback = params.get("mp_connected") === "true";
  
  setLoadingMp(true);
  getMpConnectionStatus(tenant.id)
    .then((status) => {
      setMpStatus(status);
      mpLoadedRef.current = true;
      if (fromOAuthCallback && status?.connected) {
        showToast({ message: "Mercado Pago conectado correctamente ✅", status: "success" });
      }
    })
    .catch(() => setMpStatus({ connected: false }))
    .finally(() => setLoadingMp(false));

  if (fromOAuthCallback) {
    params.delete("mp_connected");
    const newSearch = params.toString();
    const newUrl = `${window.location.pathname}${newSearch ? `?${newSearch}` : ""}`;
    window.history.replaceState({}, "", newUrl);
  }
}, [tenant?.id]);
```

**Nota**: `mpLoadedRef.current = true` solo se setea dentro del `.then()` exitoso (no en catch), para permitir retry si falla.

#### Verificación de StrictMode en producción

**Archivo**: `apps/web/src/main.jsx`

Verificado en código real:

```jsx
const Root = import.meta.env.DEV ? (
  <App />
) : (
  <StrictMode>
    <App />
  </StrictMode>
);
```

Conclusión: el doble-mount de efectos en producción es una condición real a contemplar en este componente.

---

## FASE 3 — Estrategia de producción y migración (P1)

### Decisión productiva

Para el estado productivo actual, la estrategia correcta es:

1. **No migrar rutas del backend**
2. **No cambiar `MP_REDIRECT_URI`**
3. **No tocar onboarding admin**
4. **Corregir el consumidor incorrecto en web storefront**

Esto deja el sistema consistente con mínimo riesgo operativo.

### Migración de `farma`

Para este fix, **no hace falta migración de datos** para `farma`.

No se requiere:

- update sobre `clients`
- update sobre `nv_accounts`
- cambio de `slug`
- rotación de tokens MP
- update de redirect URI en Mercado Pago

### Cuándo sí habría que hacer migración

Solo si el producto decidiera normalizar toda la API bajo `/api/*` también para MP OAuth.

En ese escenario, la migración productiva correcta sería:

1. Exponer compatibilidad doble en backend durante una ventana de transición:
   - `/mp/oauth/*`
   - `/api/mp/oauth/*`
2. Actualizar admin app
3. Actualizar web app
4. Actualizar `MP_REDIRECT_URI` en Mercado Pago
5. Validar callback real
6. Recién después retirar la ruta legacy

Ese cambio **no** es el recomendado para este incidente porque aumenta el riesgo sin necesidad.

---

## FASE 4 — Optimización de carga (P2, planificación futura)

> Esta fase se documenta para planificación pero **NO se implementa ahora**.

### 3.1 — Problema: Waterfall secuencial

```
TenantProvider (bloquea ~800ms)
  → AuthProvider (bloquea ~400ms syncMembership)
    → AppContent
      → PaymentsConfig (carga config + MP status ~600ms)
Total: ~1800ms solo de waterfall antes de renderizar datos
```

### 3.2 — Problema: Sin cache in-memory

`fetchWithRateLimitAndEtag.js` usa **localStorage** como cache. Cada request 304 sigue haciendo un round-trip HTTP (~50-100ms cada una). En reload, TODAS las requests se re-hacen aunque la data no cambió.

### 3.3 — Posible mejora futura: React Query

El web app no usa React Query (el admin sí). Migrar a React Query daría:
- Deduplicación automática de requests in-flight
- Cache in-memory con stale-while-revalidate
- Background refetching sin bloquear UI

**Riesgo**: Migración grande, requiere planificación por separado.

---

## Resumen de cambios por archivo

### Repo: `templatetwo` (Web Storefront)

| Archivo | Cambio | Líneas |
|---------|--------|--------|
| `src/services/payments.js` | Remover `/api` prefix de 3 rutas MP OAuth | L192, L201, L206 |
| `src/components/admin/PaymentsConfig/index.jsx` | Consolidar 2 useEffects → 1 + guard StrictMode | L181-L214 |

### Repo: `templatetwobe` (API)

**Sin cambios.** El controller `@Controller('mp/oauth')` es correcto para el estado productivo actual.

### Repo: `novavision` (Admin)

**Sin cambios.** Las llamadas a `mp/oauth/start` no usan prefix `/api/`.

---

## Tablas de DB involucradas (verificadas)

### Backend DB (Supabase Multicliente)

| Tabla | Campos accedidos | Uso |
|-------|-----------------|-----|
| `clients` | `id`, `slug`, `nv_account_id`, `mp_access_token` | `getAccountForClient()` busca slug y account_id. `getConnectionStatus()` verifica `mp_access_token` para `has_api_keys` |

### Admin DB (Supabase Admin)

| Tabla | Campos accedidos | Uso |
|-------|-----------------|-----|
| `nv_accounts` | `id`, `slug`, `backend_cluster_id`, `mp_connected`, `mp_live_mode`, `mp_expires_in`, `mp_connection_status`, `mp_user_id`, `mp_connected_at`, `allow_mp_reconnect` | `getConnectionStatus()` lee estado de conexión MP |

### No se modifican tablas ni esquema

Los cambios son puramente de **routing frontend**. No se tocan:
- Migraciones
- Políticas RLS
- Índices
- Esquema de tablas

---

## Plan de rollout productivo

### Paso 1 — Cambio en web

- Aplicar corrección en `apps/web/src/services/payments.js`
- Aplicar consolidación de effects en `apps/web/src/components/admin/PaymentsConfig/index.jsx`

### Paso 2 — Validación local

- `npm run lint`
- `npm run typecheck`
- `npm run build`

### Paso 3 — Validación funcional sobre `farma`

- Abrir `https://farma.novavision.lat/admin?tab=pagos`
- Verificar que el widget carga estado correcto
- Verificar que no hay 404 de `/api/mp/oauth/*`
- Verificar que sí hay 200 de `/mp/oauth/status/:clientId`
- Verificar reconnect/disconnect solo a nivel UI y respuesta HTTP

### Paso 4 — Despliegue controlado

- Deploy de web a la rama/producto correspondiente
- Smoke test inmediato sobre `farma`
- Confirmar que onboarding admin sigue funcionando

### Paso 5 — Criterio de éxito

- `farma` deja de mostrar "No configurado ❌"
- no hay 404 en rutas MP OAuth del storefront
- no hay incremento de errores en OAuth callback
- no hay regresión en builder wizard

---

## Plan de rollback productivo

Si el cambio genera una regresión en producción:

1. Revertir únicamente el cambio en `apps/web/src/services/payments.js`
2. Revertir el cambio en `apps/web/src/components/admin/PaymentsConfig/index.jsx` si impacta la carga del tab
3. Re-deploy del web storefront

Rollback esperado:

- vuelve el 404 del widget MP en storefront
- pero no se toca onboarding, callback OAuth ni datos de Mercado Pago

Esto hace que el rollback sea seguro y acotado a frontend.

---

## Plan de pruebas

### Test 1: MP Status ya no da 404

```bash
# Desde terminal (simula frontend web):
curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: Bearer <jwt>" \
  -H "x-tenant-slug: farma" \
  "https://api.novavision.lat/mp/oauth/status/1fad8213-1d2f-46bb-bae2-24ceb4377c8a"
# Esperado: 200 (o 403 si el JWT no tiene role admin)
# Antes: 404
```

### Test 2: OAuth flow sigue funcionando (admin)

1. Abrir builder wizard en admin app
2. Llegar al paso de Mercado Pago
3. Click "Conectar"
4. Verificar que redirige a `api.novavision.lat/mp/oauth/start?token=...`
5. Verificar que MP redirige a `api.novavision.lat/mp/oauth/callback?code=...`
6. NO debe cambiar nada en este flujo

### Test 3: Widget MP en storefront admin panel

1. Abrir `https://farma.novavision.lat/admin?tab=pagos`
2. El widget de MP debe mostrar:
   - "Conectado vía OAuth ✅" si `mp_connected=true` en nv_accounts
   - "Conectado vía API Keys ✅" si `mp_access_token` existe en clients
   - "No configurado ❌" solo si ninguna de las dos condiciones se cumple
4. Para el estado real actual de `farma`, el resultado esperado es:
  - `clients.mp_access_token IS NOT NULL = true`
  - `nv_accounts.mp_connected = true`
  - el widget no puede quedar en "No configurado ❌"
3. NO debe haber 404 en Network tab

### Test 4: Llamados no duplicados

1. Abrir Network tab en Chrome DevTools
2. Navegar a `?tab=pagos`
3. Verificar que `GET /mp/oauth/status/:clientId` se llama **1 sola vez** (no 2+)
4. Verificar que `GET /api/admin/payments/config` se llama **1 sola vez**

### Test 5: Disconnect/Reconnect MP

1. En el widget MP del panel admin, click "Desconectar"
2. Verificar que `POST /mp/oauth/disconnect/:clientId` funciona (no 404)
3. El widget cambia a "No configurado"
4. Click "Reconectar" → debe abrir OAuth flow via `GET /mp/oauth/start-url`

---

## Riesgos identificados y mitigaciones

| # | Riesgo | Probabilidad | Mitigación |
|---|--------|-------------|-----------|
| 1 | **Al remover `/api/` del frontend, alguna otra ruta de payments.js que SÍ necesita `api/` se rompe** | Baja | Los otros endpoints (`/api/admin/payments/*`, `/api/payments/*`) tienen controllers con prefix `api/` explícito, verificado en grep. Solo las 3 rutas de mp/oauth necesitan el cambio. |
| 2 | **Caching del browser sirve la respuesta 404 vieja** | Baja | La ruta cambia de path (ya no es `/api/mp/oauth/...` sino `/mp/oauth/...`), así que no hay cache hit posible. |
| 3 | **Guard de StrictMode con `mpLoadedRef` impide re-fetch cuando es necesario** | Media | Se resetea `mpLoadedRef` via `tenant?.id` change. Si el user navega a otra tienda (cambio de tenant), el ref se resetea por el re-mount del componente. Para OAuth callback, agregar `mpLoadedRef.current = false` antes de la llamada si `fromOAuthCallback=true`. |
| 4 | **El consolidar useEffects pierde la lógica de `showToast` en el callback OAuth** | Baja | Verificado que la lógica del toast se preserva en el useEffect consolidado — el flag `fromOAuthCallback` controla cuándo mostrar el toast. |
| 5 | **Cherry-pick a `feature/onboarding-preview-stable` genera conflicto en PaymentsConfig** | Media | PaymentsConfig es un componente de admin que probablemente existe en ambas ramas. Resolver tomando el cambio nuevo (la consolidación de useEffects). |
| 6 | **Railway deploy falla por cambio de API** | Nula | **No hay cambio en el backend**. Solo cambia el frontend (Netlify deploy). |
| 7 | **Se interpreta que, como hoy solo existe `farma`, se puede hacer un cambio destructivo de backend** | Alta si no se documenta | El plan deja explícito que el fix debe quedar seguro para estado productivo general. No se tocan rutas backend ni redirect URI. |
| 8 | **Se decide migrar a `/api/mp/oauth/*` más adelante y se rompe compatibilidad** | Media | Documentar transición con doble ruta y retiro gradual. No hacer esa migración dentro de este incidente. |

---

## Orden de ejecución

1. **Hacer cambios en `apps/web/src/services/payments.js`** (3 rutas)
2. **Hacer cambios en `apps/web/src/components/admin/PaymentsConfig/index.jsx`** (consolidar useEffects)
3. **Lint + typecheck + build** en terminal web
4. **Verificar manualmente** sobre `farma` en local / preview
5. **Commit en `develop`** (siguiendo regla de ramas del web)
6. **Cherry-pick** a `feature/multitenant-storefront` y `feature/onboarding-preview-stable`
7. **Push** (previa confirmación del TL)
8. **Smoke test productivo inmediato en `farma`**

---

## Comandos a ejecutar

### Terminal web (repo templatetwo):

```bash
# Después de hacer los cambios
cd apps/web
npm run lint
npm run typecheck
npm run build
```

### Terminal API (repo templatetwobe):

**No se requiere ningún cambio ni build en el backend.**

---

## Verificación post-deploy

1. Acceder a `https://farma.novavision.lat/admin?tab=pagos`
2. Abrir DevTools → Network
3. Confirmar:
   - `GET /mp/oauth/status/1fad8213-...` → **200** (no 404)
   - Solo **1 llamada** a ese endpoint (no duplicada)
   - Widget muestra estado correcto de MP
4. Probar builder wizard en admin app → OAuth flow inalterado
5. Probar disconnect/reconnect desde storefront admin panel

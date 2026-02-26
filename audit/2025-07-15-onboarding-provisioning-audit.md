# Auditoría Completa: Flujo de Onboarding, Provisioning y Publicación

**Fecha:** 2025-07-15  
**Autor:** agente-copilot  
**Alcance:** Backend NestJS (`apps/api/src/`) — módulos `onboarding`, `worker`, `mp-oauth`, `guards`  
**Archivos auditados:**

| Archivo | Líneas | Módulo |
|---------|--------|--------|
| `src/onboarding/onboarding.controller.ts` | 1–1247 | Controller |
| `src/onboarding/onboarding.service.ts` | 1–3795 | Service |
| `src/onboarding/onboarding-migration.helper.ts` | 1–232 | Migration Helper |
| `src/worker/provisioning-worker.service.ts` | 1–2304 | Worker |
| `src/mp-oauth/mp-oauth.service.ts` | 1–979 | MP OAuth |
| `src/guards/builder-session.guard.ts` | completo | Guard |
| `src/guards/super-admin.guard.ts` | completo | Guard |
| `src/guards/builder-or-supabase.guard.ts` | 1–120 | Guard |

---

## Índice

1. [Diagrama de Estados](#1-diagrama-de-estados)
2. [Diagrama de Flujo de Datos](#2-diagrama-de-flujo-de-datos)
3. [Matriz de Seguridad de Endpoints](#3-matriz-de-seguridad-de-endpoints)
4. [Hallazgos de Seguridad](#4-hallazgos-de-seguridad)
5. [Análisis de Idempotencia](#5-análisis-de-idempotencia)
6. [Análisis de Manejo de Errores](#6-análisis-de-manejo-de-errores)
7. [Flujo Detallado: Publish → Approve](#7-flujo-detallado-publish--approve)
8. [Flujo Detallado: Checkout → Provisioning](#8-flujo-detallado-checkout--provisioning)
9. [Flujo Detallado: MP OAuth y Credenciales](#9-flujo-detallado-mp-oauth-y-credenciales)
10. [Recomendaciones](#10-recomendaciones)

---

## 1. Diagrama de Estados

### 1.1 Estado de `nv_onboarding.state`

```
                    ┌──────────────┐
                    │ draft_builder│ (creado por startDraftBuilder)
                    └──────┬───────┘
                           │
              ┌────────────┼────────────┐
              │            │            │
              ▼            ▼            ▼
     ┌──────────────┐  ┌───────────┐  ┌─────────────────────┐
     │ preview_ready │  │ (queda    │  │ submitted_for_review│
     │ (≥1 product) │  │  draft)   │  │  (submitForReview)  │
     └──────┬───────┘  └───────────┘  └──────────┬──────────┘
            │                                     │
            └──────────┐      ┌───────────────────┘
                       ▼      ▼
              ┌─────────────────────┐
              │   pending_approval  │ (publishStore, ≥10 products)
              │   pending_content   │ (publishStore, <10 products)
              └──────────┬──────────┘
                         │
                         │  BUG: approveOnboarding espera
                         │  'review_pending' (nunca se escribe)
                         │
                         ▼
                 ┌───────────────┐
                 │   approved    │ (approveOnboarding)
                 └───────┬───────┘
                         │
                         ▼
                 ┌───────────────┐
                 │     live      │ (activateStore)
                 └───────────────┘
```

### 1.2 Estado de `nv_accounts.status`

```
  ┌────────┐
  │  draft │ (createDraftAccount / startDraftBuilder)
  └───┬────┘
      │
      ▼
  ┌─────────────────┐
  │ awaiting_payment │ (startCheckout)
  └───────┬─────────┘
          │
          ▼
  ┌────────┐         ┌──────────────┐
  │  paid  │ ◀───────│ free checkout│ (100% coupon)
  └───┬────┘         └──────────────┘
      │
      ▼
  ┌──────────────┐
  │ provisioning │ (handleCheckoutWebhook)
  └──────┬───────┘
         │
         ▼
  ┌──────────────┐
  │  provisioned │ (provisionClientFromOnboarding)
  └──────┬───────┘
         │
         ▼
  ┌────────┐
  │ active │ (approveOnboarding / completeOwnerScaffold ⚠️)
  └────────┘
```

**⚠️ Nota:** `completeOwnerScaffold` (línea ~356 de onboarding.service.ts) setea `status: 'active'` incondicionalmente, independientemente del estado de pago.

### 1.3 Estado de `provisioning_jobs.status`

```
  pending → processing → completed
                      → failed → pending (requeue si attempts < max)
```

---

## 2. Diagrama de Flujo de Datos

### 2.1 Flujo de Provisioning Completo

```
┌───────────────────────────────────────────────────────────────────────────┐
│                           ONBOARDING FLOW                                 │
│                                                                           │
│  1. POST /builder/start                                                  │
│     └─→ nv_accounts (Admin DB): draft account                            │
│     └─→ nv_onboarding (Admin DB): state=draft_builder                    │
│     └─→ provisioning_jobs (Admin DB): PROVISION_CLIENT job               │
│                                                                           │
│  2. Cron (30s) → ProvisioningWorkerService.processJobs()                 │
│     └─→ RPC claim_provisioning_jobs (FOR UPDATE SKIP LOCKED)             │
│     └─→ provisionClient():                                               │
│         ├─→ clients (Backend DB): INSERT (trial store)                   │
│         ├─→ client_home_settings (Backend DB): INSERT                    │
│         ├─→ nv_accounts (Admin DB): UPDATE backend_client_id, status     │
│         └─→ outbox_events (Admin DB): provisioning.completed             │
│                                                                           │
│  3. POST /checkout/start                                                 │
│     └─→ slug_reservations (Admin DB): reserve slug (24h TTL)            │
│     └─→ subscriptions (Admin DB): INSERT with plan_key                   │
│     └─→ MercadoPago API: create subscription                            │
│     └─→ nv_accounts (Admin DB): status=awaiting_payment                  │
│                                                                           │
│  4. POST /checkout/webhook (MP callback)                                 │
│     └─→ webhook_events (Admin DB): idempotency check                    │
│     └─→ subscriptions (Admin DB): UPDATE status=active                   │
│     └─→ nv_accounts (Admin DB): UPDATE status=paid                       │
│     └─→ provisioning_jobs (Admin DB): PROVISION_CLIENT_FROM_ONBOARDING   │
│                                                                           │
│  5. Cron → provisionClientFromOnboarding() [SAGA PATTERN]:               │
│     ├─→ Step: resolve_final_slug (RPC finalizeSlugClaim)                 │
│     ├─→ Step: provision_client                                           │
│     │   ├─→ clients (Backend DB): UPSERT                                │
│     │   └─→ nv_accounts (Admin DB): UPDATE backend_client_id             │
│     ├─→ Step: create_admin_user                                          │
│     │   └─→ users (Backend DB): UPSERT (role=admin)                     │
│     ├─→ Step: sync_mp_credentials                                        │
│     │   └─→ clients (Backend DB): PLAIN TEXT mp_access_token ⚠️          │
│     ├─→ Step: migrate_assets                                             │
│     │   └─→ Storage: onboarding/{accountId}/ → clients/{clientId}/       │
│     ├─→ Step: migrate_logo                                               │
│     ├─→ Step: migrate_catalog                                            │
│     │   ├─→ categories (Backend DB): UPSERT                              │
│     │   ├─→ products (Backend DB): UPSERT                                │
│     │   ├─→ product_categories (Backend DB): UPSERT                      │
│     │   ├─→ faqs (Backend DB): UPSERT                                    │
│     │   ├─→ services (Backend DB): UPSERT                                │
│     │   ├─→ social_links (Backend DB): UPSERT                            │
│     │   └─→ contact_info (Backend DB): INSERT                            │
│     ├─→ Step: seed_default_pages                                         │
│     │   └─→ tenant_pages (Backend DB): INSERT default home/about         │
│     ├─→ Step: sync_template_palette                                      │
│     │   ├─→ client_home_settings (Backend DB): UPSERT                    │
│     │   └─→ custom_palettes (Admin DB): UPSERT (si aplica)              │
│     ├─→ Step: sync_shipping                                              │
│     │   └─→ shipping_settings (Backend DB): INSERT defaults              │
│     └─→ nv_accounts: UPDATE status=provisioned                           │
│                                                                           │
│  6. POST /submit-for-review                                              │
│     └─→ nv_onboarding (Admin DB): state=submitted_for_review             │
│     └─→ nv_accounts (Admin DB): UPDATE mp_connection_status              │
│     └─→ nv_accounts (Admin DB): slug promotion (if draft-)               │
│     └─→ client_completion_checklist (Admin DB): UPSERT                   │
│     └─→ client_completion_events (Admin DB): INSERT                      │
│     └─→ Notification emails (async, non-blocking)                        │
│                                                                           │
│  7. POST /publish                                                        │
│     └─→ clients (Backend DB): publication_status, is_published=false     │
│     └─→ nv_onboarding (Admin DB): state=pending_approval/pending_content │
│                                                                           │
│  8. POST /approve/:accountId (SuperAdminGuard)                           │
│     └─→ nv_onboarding (Admin DB): state=approved                         │
│     └─→ nv_accounts (Admin DB): status=active, is_published=true         │
│     └─→ OnboardingMigrationHelper: products+categories+faqs → Backend    │
│     └─→ users (Backend DB): UPSERT admin user                            │
│     └─→ nv_onboarding (Admin DB): cleanup home_data                      │
└───────────────────────────────────────────────────────────────────────────┘
```

---

## 3. Matriz de Seguridad de Endpoints

| # | Método | Ruta | Guard | Auth | AllowNoTenant | Línea |
|---|--------|------|-------|------|---------------|-------|
| 1 | GET | `/active-countries` | Ninguno | ❌ | ✅ | 66-67 |
| 2 | GET | `/country-config/:countryId` | Ninguno | ❌ | ✅ | 90-91 |
| 3 | POST | `/builder/start` | Ninguno | ❌ | ✅ | 138-139 |
| 4 | POST | `/resolve-link` | Ninguno | ❌ | ✅ | 194-195 |
| 5 | POST | `/complete-owner` | BuilderSessionGuard | ✅ | ✅ | 207-209 |
| 6 | POST | `/import-home-bundle` | BuilderSessionGuard | ✅ | ✅ | 239-241 |
| 7 | GET | `/status` | BuilderSessionGuard | ✅ | ✅ | 280-282 |
| 8 | GET | `/public/status` | Ninguno | ❌ | ✅ | 292-293 |
| 9 | PATCH | `/progress` | BuilderSessionGuard | ✅ | ✅ | 307-309 |
| 10 | PATCH | `/preferences` | BuilderSessionGuard | ✅ | ✅ | 340-342 |
| 11 | PATCH | `/custom-domain` | BuilderSessionGuard | ✅ | ✅ | 367-369 |
| 12 | GET | `/plans` | Ninguno | ❌ | ✅ | 400-401 |
| 13 | GET | `/palettes` | Ninguno (opcional)¹ | ❌/✅ | ✅ | 417-418 |
| 14 | POST | `/preview-token` | BuilderSessionGuard | ✅ | ✅ | 457-459 |
| 15 | POST | `/checkout/start` | BuilderSessionGuard | ✅ | ✅ | 479-481 |
| 16 | GET | `/checkout/status` | BuilderSessionGuard | ✅ | ✅ | 500-502 |
| 17 | POST | `/checkout/confirm` | BuilderSessionGuard | ✅ | ✅ | 511-513 |
| 18 | POST | `/link-google` | BuilderSessionGuard | ✅ | ✅ | 575-577 |
| 19 | POST | `/checkout/webhook` | Ninguno | ❌ | ✅ | 588-589 |
| 20 | POST | `/business-info` | BuilderSessionGuard | ✅ | ✅ | 649-651 |
| 21 | POST | `/mp-credentials` | BuilderSessionGuard | ✅ | ✅ | 802-804 |
| 22 | POST | `/submit-for-review` | BuilderSessionGuard | ✅ | ✅ | 853-855 |
| 23 | POST | `/submit` | BuilderSessionGuard | ✅ | ✅ | 895-897 |
| 24 | POST | `/publish` | BuilderSessionGuard | ✅ | ✅ | 946-948 |
| 25 | POST | `/logo/upload-url` | BuilderSessionGuard | ✅ | ✅ | 986-988 |
| 26 | POST | `/clients/:clientId/mp-secrets` | BuilderSessionGuard | ✅ | ✅ | 1002-1004 |
| 27 | POST | `/session/save` | BuilderSessionGuard | ✅ | ✅ | 1048-1050 |
| 28 | POST | `/session/upload` | BuilderSessionGuard | ✅ | ✅ | 1074-1076 |
| 29 | POST | `/session/link-user` | BuilderSessionGuard | ✅ | ✅ | 1120-1122 |
| 30 | GET | `/mp-status` | BuilderSessionGuard | ✅ | ✅ | 1141-1143 |
| 31 | POST | `/session/accept-terms` | BuilderSessionGuard | ✅ | ✅ | 1158-1160 |
| 32 | GET | `/resume` | BuilderOrSupabaseGuard | ✅ | ✅ | 1211-1213 |
| 33 | POST | `/approve/:accountId` | SuperAdminGuard | ✅ | ✅ | 1230-1232 |

¹ Palettes extrae account_id del JWT si presente, pero no falla sin él.

**Rutas públicas (sin autenticación):** #1, #2, #3, #4, #8, #12, #13, #19  
**Ruta crítica sin auth:** #3 (`builder/start`) — crea cuenta draft, sin captcha ni rate limit  
**Ruta de webhook:** #19 (`checkout/webhook`) — validación de firma parcial (ver hallazgo S-02)

---

## 4. Hallazgos de Seguridad

### S-01 — CRÍTICO: Tokens de MP en texto plano en Backend DB

**Severidad:** 🔴 CRÍTICA  
**Archivo:** `src/mp-oauth/mp-oauth.service.ts` líneas 927–970  
**Impacto:** Compromiso de la Backend DB expone tokens de MP de TODOS los clientes

```typescript
// mp-oauth.service.ts línea ~965
async syncMpCredentialsToBackend(accountId: string, clusterId?: string) {
  // ...
  // Decrypts from AES-256-GCM in Admin DB
  const decryptedToken = this.decryptToken(account.mp_access_token_encrypted);
  
  // Writes PLAIN TEXT to Backend DB 😱
  await backendClient
    .from('clients')
    .update({
      mp_access_token: decryptedToken,    // ← PLAIN TEXT
      mp_public_key: account.mp_public_key,
    })
    .eq('nv_account_id', accountId);
}
```

**Contexto:** Los tokens se almacenan correctamente cifrados con AES-256-GCM en `nv_accounts.mp_access_token_encrypted` (Admin DB). Sin embargo, `syncMpCredentialsToBackend` (llamado durante provisioning y al guardar conexión) los descifra y escribe en texto plano en `clients.mp_access_token` (Backend/Multicliente DB). Si un atacante obtiene acceso a la Backend DB (SQLi, dump, RLS bypass), obtiene todos los access tokens de Mercado Pago.

**Recomendación:**
1. Cifrar tokens en Backend DB con clave distinta a la de Admin DB
2. O eliminar el almacenamiento en Backend DB y siempre resolverla desde Admin DB vía el servicio de MP OAuth
3. Si el backend necesita el token para webhooks/pagos, utilizar el mismo esquema AES-256-GCM con `MP_TOKEN_ENCRYPTION_KEY`

---

### S-02 — ALTO: Bypass de Firma en Webhook de MP

**Severidad:** 🟠 ALTA  
**Archivo:** `src/onboarding/onboarding.controller.ts` líneas ~601–604  
**Impacto:** Un atacante puede enviar webhooks falsos si `MP_WEBHOOK_SECRET` no está configurado

```typescript
// onboarding.controller.ts – checkout/webhook handler
const secret = this.configService.get('MP_WEBHOOK_SECRET');
if (!secret) {
  this.logger.warn('⚠️ MP_WEBHOOK_SECRET not configured — skipping signature');
  // CONTINÚA PROCESANDO SIN VALIDAR FIRMA
}
```

**Contexto:** Si la variable de entorno `MP_WEBHOOK_SECRET` no está seteada (ej. en dev o por error de deploy), el webhook procesa cualquier request sin validar la firma. Un atacante que conozca el endpoint puede forjar un webhook con `external_reference` apuntando a cualquier cuenta y triggear su provisioning.

**Recomendación:**
1. FAIL CLOSED: Si `MP_WEBHOOK_SECRET` no está configurado, rechazar el webhook con 503
2. Agregar allowlist de IPs de Mercado Pago como capa adicional
3. Validar que el `preapproval_id` recibido corresponda a una suscripción real consultando la API de MP

---

### S-03 — ALTO: Sin Captcha ni Rate Limiting en `builder/start`

**Severidad:** 🟠 ALTA  
**Archivo:** `src/onboarding/onboarding.controller.ts` líneas ~150–154  
**Impacto:** Abuso masivo para crear cuentas draft, agotar recursos y slugs

```typescript
// onboarding.controller.ts línea ~150
@AllowNoTenant()
@Post('builder/start')
async startDraftBuilder(@Body() body: any, @Req() req: Request) {
  // TODO: Agregar recaptcha antes de crear draft
  // TODO: Rate limiting por IP
  const { email, businessName, countryCode, wizardFlag } = body;
```

**Contexto:** El endpoint es completamente público, sin captcha, sin rate limiting, sin validación de email. Un script automatizado puede crear miles de cuentas draft, cada una generando un provisioning job y ocupando slugs.

**Recomendación:**
1. Agregar reCAPTCHA v3 o similar
2. Rate limiting por IP (ej. 5 requests/minuto)
3. Validar formato de email (al menos regex)
4. Considerar verificación de email antes de crear el draft

---

### S-04 — ALTO: Bug de Estado — `approveOnboarding` Nunca Puede Ejecutarse

**Severidad:** 🟠 ALTA (bug funcional bloqueante)  
**Archivo:** `src/onboarding/onboarding.service.ts`  
**Líneas afectadas:**
- Línea 2193: `state: 'submitted_for_review'` (en `submitForReview`)
- Línea 2983: `state: status` donde status es `'pending_approval'` o `'pending_content'` (en `publishStore`)
- Línea 3610: `if (!onb || onb.state !== 'review_pending')` (en `approveOnboarding`)

```typescript
// submitForReview (línea 2193) — escribe:
state: 'submitted_for_review'

// publishStore (línea 2983) — escribe:
state: status  // ← 'pending_approval' o 'pending_content'

// approveOnboarding (línea 3610) — lee:
if (!onb || onb.state !== 'review_pending')
  throw new BadRequestException('Not pending');
// ↑ NUNCA se cumple porque nadie escribe 'review_pending'
```

**Contexto:** El valor `'review_pending'` no es escrito por ningún método del servicio. `submitForReview` escribe `'submitted_for_review'` y `publishStore` escribe `'pending_approval'`/`'pending_content'`. Esto significa que `approveOnboarding` **siempre** lanza `BadRequestException('Not pending')`, a menos que un admin modifique el estado directamente en la DB.

Búsqueda exhaustiva en todo `src/`: `'review_pending'` solo aparece en:
1. Comentarios doc de `submitForReview` (2x) — documentación desactualizada
2. Check guard de `approveOnboarding` (1x)
3. Un archivo de test E2E de referencia (1x)

**Recomendación:**
1. Cambiar el check en `approveOnboarding` a:
   ```typescript
   if (!onb || !['submitted_for_review', 'pending_approval', 'pending_content'].includes(onb.state))
   ```
2. O unificar a un solo estado pre-aprobación y actualizar `submitForReview` y `publishStore` para usarlo

---

### S-05 — MEDIO: IDOR en `/clients/:clientId/mp-secrets`

**Severidad:** 🟡 MEDIA  
**Archivo:** `src/onboarding/onboarding.controller.ts` líneas ~1004–1045  
**Impacto:** Un bearer token válido de cuenta A podría escribir MP secrets en la tienda de cuenta B

```typescript
// onboarding.controller.ts línea ~1004
@Post('/clients/:clientId/mp-secrets')
async saveMPSecrets(
  @Param('clientId') clientId: string,
  @Body() body: any,
  @Req() req: any,
) {
  const accountId = req.account_id || req.builderSession?.account_id;
  
  // Weak validation: only checks they're not equal (!)
  if (!accountId || !clientId || clientId === accountId) {
    // TODO: Proper ownership lookup — for now guard ensures JWT is valid
    throw new ForbiddenException('...');
  }
  
  // Proceeds with clientId from URL without ownership verification
  return this.onboardingService.saveMPSecrets(clientId, body.mpAccessToken, body.mpPublicKey);
}
```

**Contexto:** El `clientId` viene del path parameter (controlado por el usuario). No se verifica que ese `clientId` pertenezca al `accountId` del JWT. Cualquier usuario con un builder token válido podría llamar este endpoint con el `clientId` de otra tienda y sobreescribir sus credenciales de MP.

**Recomendación:**
1. Verificar ownership: resolver el `clientId` esperado a partir del `accountId` del JWT
2. Comparar contra el `clientId` recibido en el path parameter

---

### S-06 — MEDIO: `completeOwnerScaffold` Sets `status: 'active'` Incondicionalmente

**Severidad:** 🟡 MEDIA  
**Archivo:** `src/onboarding/onboarding.service.ts` línea ~356  
**Impacto:** Cuenta puede marcar como activa sin haber pagado

```typescript
// onboarding.service.ts ~ línea 356
await adminClient
  .from('nv_accounts')
  .update({
    status: 'active',  // ← Siempre activo, sin verificar pago
    user_id: newUser.id,
    updated_at: new Date().toISOString(),
  })
  .eq('id', accountId);
```

**Contexto:** `completeOwnerScaffold` se llama desde `POST /complete-owner` al crear el usuario propietario de la tienda. Setea `status: 'active'` sin verificar si la cuenta pagó, está en trial, o está en provisioning. Esto puede provocar inconsistencias con la máquina de estados `draft → awaiting_payment → paid → provisioning → provisioned → active`.

**Recomendación:**
1. Conservar el status actual excepto si está en `'draft'`, en cuyo caso pasarlo a `'owner_created'` o similar
2. No tocar `status` si ya está en un estado posterior (paid, provisioning, etc.)

---

### S-07 — MEDIO: Extracción Inconsistente de `account_id`

**Severidad:** 🟡 MEDIA  
**Archivo:** `src/onboarding/onboarding.controller.ts` (múltiples endpoints)  
**Impacto:** Posible null reference o lectura de account_id equivocado

```typescript
// Algunos endpoints usan:
const accountId = req.account_id;

// Otros usan:
const accountId = req.account_id || req.builderSession?.account_id;

// Y otros:
const accountId = req.builderSession?.account_id;
```

**Ejemplos:**
- `business-info` (línea ~682): `req.builderSession?.account_id` — si el guard popula `req.account_id` pero no `req.builderSession`, será `undefined`
- `mp-credentials` (línea ~810): `req.account_id || req.builderSession?.account_id`
- `status` (línea ~284): `req.account_id`

**Recomendación:**
1. Estandarizar a un solo accessor, ej. crear helper `getAccountId(req)`
2. Documentar qué popula cada guard en el request

---

### S-08 — MEDIO: `approveOnboarding` Usa `accountId` como `clusterId` para Backend

**Severidad:** 🟡 MEDIA  
**Archivo:** `src/onboarding/onboarding.service.ts` línea ~3644  
**Impacto:** Podría fallar o conectar a cluster incorrecto

```typescript
// approveOnboarding línea ~3644
const backendClient = this.dbRouter.getBackendClient(accountId);
// ↑ Pasa accountId (UUID) como clusterId, no el backend_cluster_id real
```

**Contexto:** En el método `approveOnboarding`, al crear el admin user en backend, se pasa `accountId` (un UUID de la cuenta) como argumento a `getBackendClient()`, que espera un `clusterId` como `'cluster_shared_01'`. Si `getBackendClient` no tiene fallback, esto conectaría a un cluster inexistente o fallará.

**Recomendación:**
1. Obtener `backend_cluster_id` de `nv_accounts` y pasar ese valor
2. Ya se consulta `nv_accounts` al inicio del método — agregar `backend_cluster_id` al select

---

### S-09 — BAJO: `validatePlanLimits` Fail-Open

**Severidad:** 🟢 BAJA  
**Archivo:** `src/onboarding/onboarding.service.ts` línea ~2075

```typescript
if (!planData?.entitlements) {
  this.logger.warn(`No entitlements found for plan: ${userPlan}`);
  return { valid: true }; // ← Allow if plan data missing (fail open)
}
```

**Contexto:** Si no se encuentran entitlements para un plan (ej. plan_key corrupto o tabla `plans` vacía), la validación retorna `valid: true` permitiendo cualquier configuración.

**Recomendación:** Fail-closed — retornar `valid: false` con mensaje de que debe contactar soporte.

---

### S-10 — BAJO: Doble Migración de Datos en `approveOnboarding`

**Severidad:** 🟢 BAJA  
**Archivo:** `src/onboarding/onboarding.service.ts` línea ~3626  
**Impacto:** Duplicación de productos, FAQs o contact_info

```typescript
// approveOnboarding llama:
await OnboardingMigrationHelper.migrateToBackendDB(accountId, ...);
```

**Contexto:** `OnboardingMigrationHelper.migrateToBackendDB` usa `INSERT` (no upsert) para products, categories, FAQs y contact_info. Si `provisionClientFromOnboarding` ya migró el catálogo (step `migrate_catalog`), `approveOnboarding` duplicará los registros. La helper de migración original (línea ~130) usa `.insert()` vs el worker que usa `.upsert()`.

**Recomendación:**
1. Unificar: usar upsert en `OnboardingMigrationHelper` con el mismo pattern que `migrateCatalog` del worker
2. O verificar si la migración ya fue hecha antes de ejecutarla

---

### S-11 — INFO: `getLogoUploadUrl` Tiene Implementación Mock

**Severidad:** ℹ️ INFO  
**Archivo:** `src/onboarding/onboarding.service.ts` línea ~2578

```typescript
async getLogoUploadUrl(accountId: string) {
  // TODO: Implement with Supabase Storage
  this.logger.warn('TODO: Implement Supabase Storage signed upload URL');
  return {
    path,
    signedUrl: `https://storage.supabase.co/signed-upload-url-placeholder?path=${path}`,
  };
}
```

**Contexto:** Retorna un URL placeholder que no funciona. El upload real se hace via `uploadSessionAsset`.

---

## 5. Análisis de Idempotencia

| Operación | Idempotente | Mecanismo | Observaciones |
|-----------|-------------|-----------|---------------|
| `handleCheckoutWebhook` | ✅ Sí | `webhook_events` table | Deduplica por `data.id` del payment |
| `provisionClientFromOnboarding` | ✅ Sí | Saga `provisioning_job_steps` | Cada step se registra; skip si `done` |
| `startCheckout` | ⚠️ Parcial | Slug reservation con TTL | Múltiples llamadas pueden crear múltiples subscriptions en MP |
| `submitForReview` | ⚠️ Parcial | No check previo | Llamadas repetidas sobreescriben progress |
| `publishStore` | ⚠️ Parcial | No check previo | Llamadas repetidas son seguras (update idempotente) |
| `approveOnboarding` | ✅ Sí | State check | Solo ejecuta si `state === 'review_pending'` |
| `importHomeBundle` | ✅ Sí | Upsert con ON CONFLICT | Products por `client_id,sku`, categories por `client_id,slug` |
| `saveMPSecrets` | ✅ Sí | RPC + update | Sobreescribe token anterior |
| `buildStartDraft` | ❌ No | Ninguno | Cada llamada crea nueva cuenta draft + provisioning job |

### Patrón Saga (provisioning-worker.service.ts)

El worker implementa un patrón saga con resume capability:

```typescript
// provisioning-worker.service.ts línea ~1480
private async runStep(jobId: string, stepName: string, fn: () => Promise<void>) {
  // 1. Check if already done
  const existing = await adminClient.from('provisioning_job_steps')
    .select('status').eq('job_id', jobId).eq('step_name', stepName).maybeSingle();
  
  if (existing?.status === 'done') return; // Skip
  
  // 2. Mark as running
  await adminClient.from('provisioning_job_steps').upsert({
    job_id: jobId, step_name: stepName, status: 'running', started_at: now
  });
  
  // 3. Execute
  await fn();
  
  // 4. Mark as done
  await adminClient.from('provisioning_job_steps').update({ status: 'done' })
    .eq('job_id', jobId).eq('step_name', stepName);
}
```

**Fortaleza:** Si el worker crashea mid-saga, al reintentar saltea los steps ya completados.  
**Debilidad:** Si un step queda en `'running'` (crash exacto entre mark-running y completion), no hay timeout ni recovery automático para ese step.

---

## 6. Análisis de Manejo de Errores

### 6.1 Provisioning Worker (línea ~357)

```typescript
try {
  await this.processJob(job);
  await this.markJobCompleted(job.id);
} catch (error) {
  this.logger.error(`Job ${job.id} failed: ${error.message}`);
  await this.markJobFailed(job.id, error.message);
  
  if (job.attempts < (job.max_attempts || 3)) {
    await this.requeueJob(job.id);
  }
}
```

**Evaluación:** ✅ Bueno — retry con límite de intentos, logs de error, status tracking.

### 6.2 Webhook Handler (controller línea ~589)

```typescript
try {
  await this.onboardingService.handleCheckoutWebhook(body);
  return { received: true };
} catch (err) {
  this.logger.error('Webhook error: ' + err.message);
  return { received: true }; // ← Retorna 200 even on error
}
```

**Evaluación:** ⚠️ Atención — siempre retorna 200 para evitar reintentos de MP por errores internos. Esto es correcto si la idempotencia del `webhook_events` table funciona, pero si el error es en la inserción del webhook_event, se perdería el pago.

### 6.3 submitForReview — Emails (línea ~2410)

```typescript
try {
  await this.notifications.sendSubmissionConfirmationEmail({...});
  await this.notifications.sendAdminPendingNotification({...});
} catch (emailError) {
  this.logger.error(`Failed to send emails: ${emailError.message}`);
  // No throw — non-blocking
}
```

**Evaluación:** ✅ Correcto — emails no bloquean el flujo principal.

### 6.4 approveOnboarding — Migration (línea ~3626)

```typescript
try {
  await OnboardingMigrationHelper.migrateToBackendDB(...);
  await OnboardingMigrationHelper.cleanupAdminData(...);
} catch (e) {
  this.logger.error('Migration: ' + e.message);
  // No throw — state already changed to 'approved'
}
```

**Evaluación:** ⚠️ Atención — si la migración falla, el estado ya fue cambiado a `'approved'` y `is_published = true`. La tienda aparece como publicada pero sin datos migrados. No hay rollback.

---

## 7. Flujo Detallado: Publish → Approve

### Happy Path

```
1. User → POST /submit-for-review
   └─→ onboarding.service.submitForReview(accountId)
       ├─→ Valida plan limits (wizardData)
       ├─→ Safe merge de assets
       ├─→ Reconcilia estado MP (connected/disconnected)
       ├─→ Promueve slug de draft- a final (si disponible)
       ├─→ nv_onboarding.state = 'submitted_for_review'
       ├─→ client_completion_checklist: review_status = 'pending_review'
       ├─→ client_completion_events: type = 'submitted_for_review'
       └─→ Envía emails (confirmación + notificación admin)

2. User → POST /publish (opcional, puede ejecutarse después)
   └─→ onboarding.service.publishStore(accountId)
       ├─→ Verifica suscripción activa (checkCanPublish)
       ├─→ Cuenta productos
       ├─→ clients.publication_status = 'pending_approval'/'pending_content'
       ├─→ clients.is_published = false
       └─→ nv_onboarding.state = 'pending_approval'/'pending_content'

3. Super Admin → POST /approve/:accountId
   └─→ onboarding.service.approveOnboarding(accountId)
       ├─→ CHECK: nv_onboarding.state === 'review_pending' ← 🐛 BUG (ver S-04)
       ├─→ nv_onboarding.state = 'approved'
       ├─→ nv_accounts.status = 'active', is_published = true
       ├─→ OnboardingMigrationHelper.migrateToBackendDB()
       ├─→ OnboardingMigrationHelper.cleanupAdminData()
       └─→ Upsert admin user en Backend DB
```

### Bug en Happy Path

El paso 3 **SIEMPRE FALLA** porque:
- Paso 1 deja `state = 'submitted_for_review'`
- Paso 2 deja `state = 'pending_approval'` o `'pending_content'`
- Paso 3 espera `state = 'review_pending'`

**Ningún path deja el estado en `'review_pending'`.**

---

## 8. Flujo Detallado: Checkout → Provisioning

### Happy Path (pago con MP)

```
1. POST /checkout/start
   └─→ onboarding.service.startCheckout(accountId, planKey, ...)
       ├─→ Valida plan existe y es público
       ├─→ reserveSlugForCheckout(): INSERT en slug_reservations (TTL 24h)
       ├─→ Crea subscription en Admin DB (subscriptions table)
       ├─→ Crea preapproval en MP API
       ├─→ nv_accounts.status = 'awaiting_payment'
       └─→ Retorna { init_point, sandbox_init_point }

2. Usuario paga en MP → MP envía webhook

3. POST /checkout/webhook (MP callback)
   └─→ Controller:
       ├─→ Verifica firma x-signature (⚠️ bypass si no hay secret)
       └─→ onboarding.service.handleCheckoutWebhook(body)
           ├─→ Idempotency check: webhook_events.data_id
           ├─→ Resuelve account via external_reference o preapproval_id
           ├─→ subscriptions.status = 'active'
           ├─→ nv_accounts.status = 'paid'
           ├─→ RPC enqueue_provisioning_job:
           │   type = 'PROVISION_CLIENT_FROM_ONBOARDING'
           │   dedupe_key = onb_{accountId}
           └─→ webhook_events.status = 'processed'

4. Cron (30s) → ProvisioningWorkerService.processJobs()
   └─→ takeJobs() → claim_provisioning_jobs RPC (FOR UPDATE SKIP LOCKED)
   └─→ provisionClientFromOnboarding() [SAGA]:
       ├─→ resolve_final_slug: slug_reservations → nv_accounts.slug
       ├─→ provision_client: INSERT clients (Backend DB)
       ├─→ create_admin_user: UPSERT users (Backend DB, role=admin)
       ├─→ sync_mp_credentials: decrypt Admin → write PLAIN Backend ⚠️
       ├─→ migrate_assets: Storage copy
       ├─→ migrate_logo: Storage + URL rewrite
       ├─→ migrate_catalog: products/categories/faqs/services/social
       ├─→ seed_default_pages: tenant_pages (home, about)
       ├─→ sync_template_palette: client_home_settings + custom_palettes
       ├─→ sync_shipping: shipping_settings defaults
       └─→ nv_accounts.status = 'provisioned'
```

### Happy Path (checkout gratis — 100% cupón)

```
1. POST /checkout/start (con coupon_code que da 100% off)
   └─→ onboarding.service.startCheckout()
       ├─→ Detecta precio final = 0
       ├─→ Skip creación de subscription MP
       ├─→ subscriptions.status = 'active' (directo)
       ├─→ nv_accounts.status = 'paid'
       ├─→ Enqueue PROVISION_CLIENT_FROM_ONBOARDING
       └─→ Retorna { free: true, provisioning: true }
```

---

## 9. Flujo Detallado: MP OAuth y Credenciales

### 9.1 Cifrado de Tokens

```
┌──────────────────────────────────────────────────────────────┐
│              AES-256-GCM ENCRYPTION FLOW                      │
│                                                                │
│  Input: plaintext token                                       │
│  Key: MP_TOKEN_ENCRYPTION_KEY (32 bytes / 64 hex chars)       │
│                                                                │
│  encryptToken():                                              │
│  1. Generate random IV (16 bytes)                             │
│  2. Create AES-256-GCM cipher                                │
│  3. Encrypt → ciphertext + authTag (16 bytes)                │
│  4. Concatenate: IV(32hex) + AuthTag(32hex) + Ciphertext(hex)│
│  5. Store as single hex string in DB                         │
│                                                                │
│  decryptToken():                                              │
│  1. Slice: IV = [0:32], AuthTag = [32:64], Cipher = [64:]   │
│  2. Recreate decipher with same IV + authTag                 │
│  3. Decrypt → plaintext                                      │
└──────────────────────────────────────────────────────────────┘
```

**Evaluación:** ✅ Implementación correcta de AES-256-GCM con IV random y authenticated encryption.

### 9.2 Flujo de Credenciales

```
┌──────────────────────────────────────┐
│         saveConnection() (OAuth)     │
│                                      │
│  MP API response:                    │
│  { access_token, refresh_token, ... }│
│                                      │
│  1. encryptToken(access_token) ──────┼──→ nv_accounts.mp_access_token_encrypted
│  2. encryptToken(refresh_token) ─────┼──→ nv_accounts.mp_refresh_token_encrypted
│  3. mp_public_key (plain) ───────────┼──→ nv_accounts.mp_public_key
│  4. mp_connected = true ─────────────┼──→ nv_accounts.mp_connected
│                                      │
│  IF client provisioned:              │
│  5. syncMpCredentialsToBackend() ────┼──→ clients.mp_access_token = PLAIN TEXT ⚠️
│     └── decryptToken() first         │    clients.mp_public_key = plain
└──────────────────────────────────────┘

┌──────────────────────────────────────┐
│       refreshTokenForAccount()       │
│                                      │
│  1. Redis lock: mp_refresh:{id}      │
│     (30s TTL, prevents race)         │
│  2. decryptToken(refresh_token)      │
│  3. POST MP API /oauth/token         │
│  4. encryptToken(new_access_token)   │
│  5. encryptToken(new_refresh_token)  │
│  6. UPDATE nv_accounts               │
│  7. syncMpCredentialsToBackend()     │
│     → PLAIN TEXT to backend ⚠️       │
│  8. Release Redis lock               │
└──────────────────────────────────────┘
```

---

## 10. Recomendaciones

### Prioridad Inmediata (Sprint actual)

| # | Hallazgo | Acción | Esfuerzo |
|---|----------|--------|----------|
| 1 | S-04 | Fix state check en `approveOnboarding`: aceptar `'submitted_for_review'`, `'pending_approval'`, `'pending_content'` | 15min |
| 2 | S-02 | Fail-closed si `MP_WEBHOOK_SECRET` no está configurado | 15min |
| 3 | S-05 | Agregar ownership validation en `/clients/:clientId/mp-secrets` | 30min |
| 4 | S-08 | Fix `getBackendClient(accountId)` → usar `backend_cluster_id` real | 15min |

### Prioridad Alta (próximo sprint)

| # | Hallazgo | Acción | Esfuerzo |
|---|----------|--------|----------|
| 5 | S-01 | Cifrar tokens en Backend DB (o eliminar almacenamiento plain text) | 2-4h |
| 6 | S-03 | Implementar reCAPTCHA + rate limiting en `builder/start` | 2-3h |
| 7 | S-07 | Estandarizar extracción de `account_id` con helper | 1h |
| 8 | S-10 | Unificar `OnboardingMigrationHelper` con upsert pattern del worker | 1-2h |

### Prioridad Media (backlog)

| # | Hallazgo | Acción | Esfuerzo |
|---|----------|--------|----------|
| 9 | S-06 | Corregir `completeOwnerScaffold` para no forzar `status: 'active'` | 30min |
| 10 | S-09 | Cambiar `validatePlanLimits` a fail-closed | 15min |
| 11 | S-11 | Completar o eliminar `getLogoUploadUrl` mock | 30min |
| 12 | — | Agregar timeout/recovery para saga steps en estado `'running'` | 2h |
| 13 | — | Agregar métricas/alertas para provisioning jobs fallidos | 2h |

---

## Apéndice: Archivos y Líneas de Referencia Rápida

| Concepto | Archivo | Línea(s) |
|----------|---------|----------|
| Builder token JWT creation | onboarding.service.ts | ~191 (resolveOnboardingLink) |
| Provisioning job enqueue | onboarding.service.ts | ~1050 (handleCheckoutWebhook, RPC) |
| Saga runner (runStep) | provisioning-worker.service.ts | ~1480 |
| Job claim (SKIP LOCKED) | provisioning-worker.service.ts | ~340 (takeJobs) |
| AES-256-GCM encrypt | mp-oauth.service.ts | 880–893 |
| AES-256-GCM decrypt | mp-oauth.service.ts | 896–915 |
| PLAIN TEXT sync to backend | mp-oauth.service.ts | 927–970 |
| Redis distributed lock (refresh) | mp-oauth.service.ts | ~530 |
| SuperAdmin guard (timingSafeEquals) | super-admin.guard.ts | completo |
| Builder session guard (JWT) | builder-session.guard.ts | completo |
| State bug: submitted_for_review | onboarding.service.ts | 2193 |
| State bug: review_pending check | onboarding.service.ts | 3610 |
| publishStore | onboarding.service.ts | 2940–2990 |
| approveOnboarding | onboarding.service.ts | 3597–3693 |
| Webhook signature bypass | onboarding.controller.ts | ~601–604 |
| No captcha TODO | onboarding.controller.ts | ~150–154 |
| IDOR mp-secrets | onboarding.controller.ts | ~1004–1045 |
| Wrong clusterId in approve | onboarding.service.ts | 3644 |

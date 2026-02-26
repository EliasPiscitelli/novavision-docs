# Auditoría de Seguridad — Módulo de Onboarding y Publicación de Tienda

**Fecha:** 2025-07-18  
**Autor:** agente-copilot  
**Alcance:** `src/onboarding/`, `src/worker/provisioning-worker.service.ts`, `src/guards/builder-*.guard.ts`, `src/guards/super-admin.guard.ts`  
**Archivos auditados:** 12 archivos, ~10,200 líneas

---

## TABLA DE CONTENIDOS

1. [Tabla de Endpoints](#1-tabla-de-endpoints)
2. [Máquina de Estados](#2-máquina-de-estados)
3. [Flujo de Provisioning / Publish](#3-flujo-de-provisioning--publish)
4. [Hallazgos de Seguridad (P0 / P1 / P2)](#4-hallazgos-de-seguridad)
5. [Resumen Ejecutivo](#5-resumen-ejecutivo)

---

## 1. Tabla de Endpoints

### Onboarding Controller (`src/onboarding/onboarding.controller.ts`)

| # | Método | Ruta | Guard | DTO/Validación | DB Writes | `client_id` check | Notas |
|---|--------|------|-------|----------------|-----------|-------------------|-------|
| 1 | GET | `/onboarding/active-countries` | ❌ Ninguno | — | — | ❌ N/A (catálogo) | Público |
| 2 | GET | `/onboarding/country-config/:countryId` | ❌ Ninguno | Param only | Read | ❌ N/A | Público |
| 3 | **POST** | **`/onboarding/builder/start`** | **❌ Ninguno** | Inline (`email`, `slug` required) | **Admin: nv_accounts, nv_onboarding, provisioning_jobs** | ❌ N/A | **⚠️ P0: Sin captcha, rate-limit específico, ni fingerprinting** |
| 4 | POST | `/onboarding/resolve-link` | ❌ Ninguno | `{ token }` | Admin: onboarding_links (marks used) | ❌ N/A | Valida hash/expiry/revoked |
| 5 | POST | `/onboarding/complete-owner` | BuilderSessionGuard | `{ linkToken, password? }` | Admin: onboarding_links, auth.users, users, nv_accounts | Account-scoped (token) | Consumes link atomically |
| 6 | POST | `/onboarding/import-home-bundle` | BuilderSessionGuard | `{ data }` — **Zod** (`HomeDataLiteSchema`) | Backend: categories, products, services, faqs | ✅ via slug→clientId | Correcta validación Zod |
| 7 | GET | `/onboarding/status` | BuilderSessionGuard | — | Read | Account-scoped | OK |
| 8 | GET | `/onboarding/public/status` | ❌ Ninguno | `?slug=` query param | Read | ❌ Query param | **⚠️ P2: Cualquiera puede consultar estado de cualquier slug** |
| 9 | **PATCH** | **`/onboarding/progress`** | BuilderSessionGuard | **`body: any`** | Admin: nv_onboarding (JSONB merge) | Account-scoped | **⚠️ P1: Sin schema validation — acepta JSON arbitrario** |
| 10 | PATCH | `/onboarding/preferences` | BuilderSessionGuard | Inline types | Admin + Backend | Account-scoped | Válida template/palette keys |
| 11 | PATCH | `/onboarding/custom-domain` | BuilderSessionGuard | `{ domain, mode, details }` | Admin: nv_accounts, nv_onboarding | Account-scoped | Inline format validation |
| 12 | GET | `/onboarding/plans` | ❌ Ninguno | — | Read | ❌ N/A | Público (catálogo) |
| 13 | GET | `/onboarding/palettes` | ❌ (manual token check) | — | Read | Opcional via token | Plan-gated palettes sin auth obligatorio |
| 14 | POST | `/onboarding/preview-token` | BuilderSessionGuard | — | Read (generates HMAC token) | Account-scoped | TTL 1h, HMAC firmado |
| 15 | POST | `/onboarding/checkout/start` | BuilderSessionGuard | `{ planId, cycle?, couponCode? }` | Admin: slug_reservations, subscriptions | Account-scoped | Crea suscripción MP |
| 16 | GET | `/onboarding/checkout/status` | BuilderSessionGuard | — | Read | Account-scoped | OK |
| 17 | **POST** | **`/onboarding/checkout/confirm`** | BuilderSessionGuard | `{ status?, external_reference?, preapproval_id? }` | Admin: nv_accounts, nv_onboarding, subscriptions | Account-scoped | **⚠️ P0: Fallback confía en status del frontend** |
| 18 | **POST** | **`/onboarding/link-google`** | BuilderSessionGuard | `{ email }` | Admin: nv_accounts (overwrites email) | Account-scoped | **⚠️ P1: No valida id_token server-side** |
| 19 | **POST** | **`/onboarding/checkout/webhook`** | **❌ Ninguno** | `body: any` | Admin: webhook_events, nv_accounts, nv_onboarding, subscriptions, provisioning_jobs | Via external_reference lookup | **⚠️ P0: Procede sin firma si MP_WEBHOOK_SECRET no configurado** |
| 20 | POST | `/onboarding/business-info` | BuilderSessionGuard | Inline sanitization (`cleanStr()`) | Admin: nv_accounts, nv_onboarding | Account-scoped (via `req.builderSession?.account_id`) | **⚠️ P2: Inconsistent account_id extraction** |
| 21 | POST | `/onboarding/mp-credentials` | BuilderSessionGuard | `{ accessToken, publicKey }` | Backend: client_secrets (RPC encrypt). Admin: nv_accounts | Account-scoped | Usa RPC `encrypt_mp_token` |
| 22 | POST | `/onboarding/submit-for-review` | BuilderSessionGuard | — | Admin: nv_accounts, nv_onboarding (state→submitted_for_review). Backend: clients | Account-scoped | **⚠️ P1: Slug promotion TOCTOU** |
| 23 | POST | `/onboarding/submit` | BuilderSessionGuard | `SubmitWizardDataDto` (class-validator) | Admin: nv_onboarding | Account-scoped | Correcta validación DTO |
| 24 | POST | `/onboarding/publish` | BuilderSessionGuard | — | Backend: clients. Admin: nv_onboarding | Account-scoped | **No valida subscription.status** |
| 25 | POST | `/onboarding/logo/upload-url` | BuilderSessionGuard | — | — | Account-scoped | **⚠️ P2: Retorna URL placeholder (TODO)** |
| 26 | **POST** | **`/clients/:clientId/mp-secrets`** | BuilderSessionGuard | `{ mpAccessToken, mpPublicKey }` | Backend: client_secrets | **⚠️ P1: Ownership check clientId === accountId (incorrecta)** | IDs son de distintas DBs |
| 27 | POST | `/onboarding/session/save` | BuilderSessionGuard | Inline typed | Admin: nv_onboarding, nv_accounts | Account-scoped | Template key validation |
| 28 | POST | `/onboarding/session/upload` | BuilderSessionGuard | FileInterceptor (5MB) | Admin Storage + nv_onboarding | Account-scoped | **⚠️ P2: No valida Content-Type de archivo** |
| 29 | **POST** | **`/onboarding/session/link-user`** | BuilderSessionGuard | `{ user_id }` | Admin: nv_accounts (clears other user_ids) | Account-scoped | **⚠️ P1: Acepta cualquier user_id, no verifica que sea del caller** |
| 30 | GET | `/onboarding/mp-status` | BuilderSessionGuard | — | Read | Account-scoped | OK |
| 31 | POST | `/onboarding/session/accept-terms` | BuilderSessionGuard | `{ version }` | Admin: nv_accounts + auth.admin.updateUserById | Account-scoped | **⚠️ P2: listUsers() para buscar por email (O(n))** |
| 32 | **GET** | **`/onboarding/resume`** | BuilderOrSupabaseGuard | `?user_id=` query param | Read | **⚠️ P1: user_id de query param, no del JWT** | **IDOR potencial** |
| 33 | POST | `/onboarding/approve/:accountId` | SuperAdminGuard | Param validation | Admin + Backend | N/A (super admin) | OK — usa backendClient con accountId |

---

## 2. Máquina de Estados

### Estados de `nv_onboarding.state`

```
draft
  └── builder/start → draft_builder
                        └── import-home-bundle (si ≥1 producto) → preview_ready
                        └── submit (wizard data) → onboarding_wizard
                                                    └── submit-for-review → submitted_for_review
                                                                              └── (admin action) review_pending
                                                                                                    └── approve → approved → live
                        └── publish → pending_approval | pending_content
                                        └── activateStore → live

  (checkout flow paralelo)
  draft_builder → checkout/start → [MP payment] → provisioned (via worker)
```

### Transiciones observadas en el código

| Desde | Hacia | Trigger | Archivo | Validación de estado previo |
|-------|-------|---------|---------|---------------------------|
| (nuevo) | `draft` | `startDraftBuilder` | service.ts | ❌ Ninguna (crea nuevo) |
| `draft` | `draft_builder` | `startDraftBuilder` | service.ts | Email dedup loose |
| `draft_builder` | `preview_ready` | `importHomeBundle` (≥1 product) | service.ts:2694 | `.eq('state', 'draft_builder')` ✅ |
| `draft_builder` | `onboarding_wizard` | `submitWizardData` | service.ts | **❌ No valida estado previo explícitamente** |
| cualquiera | `submitted_for_review` | `submitForReview` | service.ts | **❌ No hay WHERE state IN (...)** |
| `review_pending` | `approved` | `approveOnboarding` | service.ts:3667 | `onb.state !== 'review_pending'` ✅ |
| cualquiera | `pending_approval`/`pending_content` | `publishStore` | service.ts:2870 | **❌ No valida estado previo** |
| cualquiera | `live` | `activateStore` | service.ts | **❌ No valida estado previo** |
| cualquiera | arbitrary string | `updateOnboardingState` | service.ts:3190 | **❌ Acepta cualquier string** |

### Gaps en la máquina de estados

- **No hay enum de estados válidos** — el campo `state` es un `text` libre.
- **`submitForReview` no valida** que el estado actual sea uno de los prerequisitos (`preview_ready`, `onboarding_wizard`, `draft_builder`).
- **`publishStore` no valida** el estado actual en absoluto.
- **`activateStore` no valida** que esté en `pending_approval` o `approved`.
- **`updateOnboardingState`** es un setter genérico sin validación de transiciones — cualquier llamada interna puede poner cualquier estado.

---

## 3. Flujo de Provisioning / Publish

### Diagrama de flujo completo

```
[Frontend Builder]
      │
      ▼
POST /builder/start ─────────────────────► nv_accounts (draft) + nv_onboarding (draft_builder)
      │                                     + provisioning_job (PROVISION_CLIENT)
      │
   [Usuario diseña su tienda]
      │
      ▼
POST /checkout/start ───────────────────► slug_reservations + subscriptions + MP subscription
      │
   [Pago en MP]
      │
      ├── Webhook llega ──────────────────► webhook_events (idempotent)
      │                                     nv_accounts.status = 'paid'
      │                                     provisioning_job (PROVISION_CLIENT_FROM_ONBOARDING)
      │
      └── POST /checkout/confirm (fallback)─► syncSubscriptionStatus (si MP confirma 'active')
                                              O setCheckoutStatus (trusting frontend ⚠️)
      │
      ▼
[Worker: PROVISION_CLIENT_FROM_ONBOARDING]
      │
      ├── 1. Resolve final slug (from slug_reservations)
      ├── 2. Calculate entitlements (plan + addons)
      ├── 3. Upsert client in Backend DB (clients table)
      ├── 4. Create admin user in Backend DB (users table)
      ├── 5. Update nv_accounts (slug, cluster, status=provisioned)
      ├── 6. Sync MP credentials to Backend
      ├── 7. Update nv_onboarding (client_id, provisioned_at)
      ├── 8. Validate completion + send notifications
      ├── 9. Cleanup slug reservations
      ├── 10. Sync template/palette settings
      ├── 11. Migrate catalog (products, categories, FAQs, services, social, contact)
      ├── 12. Migrate assets (copy from onboarding/ to clients/ in storage)
      ├── 13. Migrate logo (handles base64→storage conversion)
      ├── 14. Seed default pages (home)
      └── 15. Seed shipping defaults
      │
      ▼
POST /submit-for-review ────────────────► state → submitted_for_review
      │                                    slug promotion (TOCTOU race ⚠️)
      │                                    MP status reconciliation
      ▼
POST /approve/:accountId (Super Admin) ─► state → approved
      │                                    is_published = true
      │                                    migrateToBackendDB (legacy)
      │                                    upsert admin user
      ▼
activateStore ──────────────────────────► is_active = true, state → live
```

### Observaciones del flujo

1. **Provisioning es idempotente** gracias al patrón saga (`runStep` con step ledger en `provisioning_job_steps`).
2. **Job claiming** usa `FOR UPDATE SKIP LOCKED` — correcto para concurrencia.
3. **Retry logic**: max 5 attempts con requeue.
4. **Multiple provisioning paths**: `PROVISION_CLIENT` (trial) vs `PROVISION_CLIENT_FROM_ONBOARDING` (post-pago) — lógica duplicada parcialmente.
5. **`approveOnboarding` usa `this.dbRouter.getBackendClient(accountId)`** (línea 3694) — pasando `accountId` como clusterId, lo que probablemente resuelve al cluster default, pero es semánticamente incorrecto.

---

## 4. Hallazgos de Seguridad

---

### 🔴 P0 — Críticos (explotables, impacto alto)

---

#### P0-1: POST `/builder/start` sin captcha ni rate-limit específico

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 147-156  
**Código:**
```typescript
// TODO: Verificar captcha
// if (!captcha_token) {
//   throw new BadRequestException('captcha_token is required');
// }

// TODO: Rate limits multi-factor (IP + email + fingerprint)
```

**Impacto:** Un atacante puede crear miles de cuentas draft automáticamente, consumiendo recursos de DB (nv_accounts, nv_onboarding) y encolando provisioning_jobs que el worker procesa cada 30 segundos.

**Mitigación existente:** Hay rate-limit Express global (in-memory), pero compartido entre todas las rutas, insuficiente para un endpoint de creación de recursos.

**Recomendación:**
1. Integrar `CaptchaService` (ya importado en comments, CommonModule disponible).
2. Agregar rate-limit específico por IP: 5 req/min para este endpoint.
3. Agregar dedup por email con cooldown (ya hay dedup parcial pero permite reintentos inmediatos).

---

#### P0-2: Webhook acepta requests sin firma cuando `MP_WEBHOOK_SECRET` no está configurado

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 592-598  
**Código:**
```typescript
const secret = this.config.get<string>('MP_WEBHOOK_SECRET');
if (secret) {
  const valid = this.verifyWebhookSignature(req, secret);
  if (!valid) throw new UnauthorizedException('Invalid signature');
} else {
  this.logger.warn('[Onboarding MP] MP_WEBHOOK_SECRET no configurado');
}
// ← Continúa procesando sin verificación
await this.onboardingService.handleCheckoutWebhook(body);
```

**Impacto:** Si la variable de entorno `MP_WEBHOOK_SECRET` no está configurada (ej: nuevo deploy, env file incompleto), cualquiera puede enviar webhooks falsos que:
- Marcan cuentas como `paid`
- Enquenan provisioning jobs
- Crean subscripciones activas sin pago real

**Recomendación:**
```typescript
if (!secret) {
  this.logger.error('[CRITICAL] MP_WEBHOOK_SECRET not configured — rejecting webhook');
  throw new InternalServerErrorException('Webhook configuration error');
}
```

---

#### P0-3: `checkout/confirm` fallback confía en status del frontend

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 560-568  
**Código:**
```typescript
// Fallback to legacy behavior (trusting frontend or just setting flag)
await this.onboardingService.assertExternalReference(
  accountId,
  body?.external_reference,
);
await this.onboardingService.setCheckoutStatus(
  accountId,
  body?.status || 'pending',    // ← body.status viene del frontend
);
```

**Impacto:** Si el `preapproval_id` no se envía o falla la verificación MP, el fallback permite que el frontend envíe `status: 'paid'`, lo que potencialmente marca un checkout como pagado sin verificación con MercadoPago.

**Recomendación:**
1. Eliminar el fallback que acepta `body.status`.
2. Si no hay `preapproval_id`, retornar `{ ok: true, status: 'pending' }` siempre.
3. Solo cambiar a `paid` cuando el webhook confirme o se verifique directamente con la API de MP.

---

#### P0-4: `validatePlanLimits()` falla abierto (fail-open)

**Archivo:** `src/onboarding/onboarding.service.ts` ~línea 2100  
**Código:**
```typescript
async validatePlanLimits(accountId: string, ...): Promise<{ valid: boolean; ... }> {
  // ... fetches plan data ...
  if (!planData) {
    return { valid: true };   // ← Fail-open: si no hay plan, todo es válido
  }
}
```

**Impacto:** Si la tabla `plans` no tiene un registro para el `plan_key` de la cuenta (por error de datos, plan eliminado, etc.), las validaciones de límites retornan `valid: true`, permitiendo importar contenido sin restricciones de plan.

**Recomendación:**
```typescript
if (!planData) {
  this.logger.error(`Plan not found for key: ${planKey} — failing closed`);
  return { valid: false, reason: 'Plan configuration not found' };
}
```

---

### 🟠 P1 — Altos (explotables con auth, impacto medio)

---

#### P1-1: IDOR en `GET /onboarding/resume` — `user_id` de query param

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 1213-1222  
**Código:**
```typescript
@UseGuards(BuilderOrSupabaseGuard)
@Get('resume')
async resumeOnboarding(@Query('user_id') userId: string) {
  if (!userId) throw new BadRequestException('user_id is required');
  const result = await this.onboardingService.resumeSession(userId);
  return result;  // ← Retorna: accountId, email, slug, businessName, status
}
```

**Impacto:** Un usuario autenticado (con cualquier builder token o Supabase JWT válido) puede pasar el `user_id` de OTRO usuario en el query param y obtener información de su cuenta de onboarding (email, slug, businessName, status).

**Recomendación:**
```typescript
async resumeOnboarding(@Req() req) {
  // Usar el user_id del JWT, NO del query param
  const userId = req.user?.id || req.builderSession?.user_id;
  if (!userId) throw new UnauthorizedException('No user context');
  return await this.onboardingService.resumeSession(userId);
}
```

---

#### P1-2: `POST /onboarding/session/link-user` acepta cualquier `user_id`

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 1120-1132  
**Código:**
```typescript
@UseGuards(BuilderSessionGuard)
@Post('session/link-user')
async linkUser(@Req() req, @Body() body: { user_id: string }) {
  const accountId = req.account_id;
  if (!body.user_id) throw new BadRequestException('user_id required');
  await this.onboardingService.linkUserToSession(accountId, body.user_id);
  return { ok: true };
}
```

**En el service (`linkUserToSession`)** — desvincula el `user_id` de OTRAS cuentas:
```typescript
const { data: conflicts } = await adminClient
  .from('nv_accounts')
  .select('id, status, email')
  .eq('user_id', userId)
  .neq('id', accountId);
// Clears user_id from all conflicting accounts
```

**Impacto:** Un atacante con un builder_token válido puede:
1. Enviar el `user_id` de la víctima
2. La víctima pierde su `user_id` en `nv_accounts` (se pone NULL)
3. El atacante se vincula a la cuenta de la víctima indirectamente

**Recomendación:** Verificar que el `user_id` corresponde al caller autenticado (verificar contra el JWT de Supabase o requerir una auth adicional).

---

#### P1-3: `PATCH /onboarding/progress` acepta JSON arbitrario sin validación

**Archivo:** `src/onboarding/onboarding.controller.ts` línea ~280, service.ts `updateProgress`  
**Controller:**
```typescript
@Patch('progress')
async updateProgress(@Req() req, @Body() body: any) {
  await this.onboardingService.updateProgress(accountId, body);
}
```
**Service:**
```typescript
async updateProgress(accountId: string, data: any) {
  const merged = { ...currentProgress, ...data }; // ← Shallow merge de lo que sea
  await adminClient.from('nv_onboarding').update({ progress: merged })...
}
```

**Impacto:**
- Inyección de claves arbitrarias en el JSONB `progress` (potential prototype pollution cuando se parsea).
- Sobrescritura de claves críticas internas (`checkout_status`, `checkout_paid_at`, etc.) que usan para tomar decisiones de negocio.
- No hay límite de tamaño del body más allá del body parser global.

**Recomendación:**
1. Crear un Zod schema permitiendo solo claves conocidas.
2. Strip de claves reservadas (`checkout_*`, `wizard_*`, `state_*`).
3. Limitar el tamaño del body para este endpoint.

---

#### P1-4: `POST /onboarding/link-google` no valida `id_token` server-side

**Archivo:** `src/onboarding/onboarding.controller.ts` líneas 573-581  
**Código:**
```typescript
/**
 * TODO: validar id_token server-side cuando se integre el hub de auth.
 */
@Post('link-google')
async linkGoogle(@Req() req, @Body() body: { email: string }) {
  const accountId = req.account_id;
  const email = body?.email;
  await this.onboardingService.linkGoogleAccount(accountId, email);
}
```

**Service `linkGoogleAccount`** sobrescribe `nv_accounts.email` con el email recibido.

**Impacto:** Un atacante con un builder_token puede cambiar el email de la cuenta a cualquier email arbitrario, potencialmente tomando control de la cuenta (el email se usa para generar auth users y como identidad).

**Recomendación:** Validar el `id_token` de Google contra `https://oauth2.googleapis.com/tokeninfo` o `google-auth-library` antes de aceptar el email.

---

#### P1-5: Race condition TOCTOU en slug promotion (`submitForReview`)

**Archivo:** `src/onboarding/onboarding.service.ts` ~líneas 2200-2250  
**Código (simplificado):**
```typescript
// 1. CHECK: ¿Existe otra cuenta con este slug?
const { count } = await adminClient
  .from('nv_accounts')
  .select('id', { count: 'exact', head: true })
  .eq('slug', slug)
  .neq('id', accountId);

// 2. ACT: Si nadie más lo tiene, actualizar
if (count === 0) {
  await adminClient.from('nv_accounts')
    .update({ slug })
    .eq('id', accountId);
}
```

**Impacto:** Dos cuentas podrían reclamar el mismo slug si hacen submit-for-review simultáneamente, porque el check y el update son queries separadas (sin `WHERE slug != slug` atomic constraint).

**Recomendación:** Usar un `UNIQUE INDEX` en `nv_accounts.slug` y un `UPDATE ... WHERE slug IS NULL OR slug = $old_slug` atómico, o usar la RPC `claim_slug_final` que ya existe.

---

#### P1-6: `startDraftBuilder()` — Race conditions en email y slug dedup

**Archivo:** `src/onboarding/onboarding.service.ts` — `startDraftBuilder()`  
**Flujo:**
1. `SELECT ... FROM nv_accounts WHERE email = $email` — check si existe
2. `SELECT ... FROM nv_accounts WHERE slug = $slug` — check colisión
3. `INSERT INTO nv_accounts (email, slug, ...)` — crear

**Impacto:** Dos requests simultáneos con el mismo email o slug pasan ambas verificaciones y crean registros duplicados (si no hay UNIQUE constraint en DB, o generan error 23505 no manejado gracefully).

**Recomendación:** Usar `INSERT ... ON CONFLICT (email) DO UPDATE SET ...` o manejar explícitamente el error de unique constraint con retry.

---

#### P1-7: `completeOwnerScaffold()` — Sin rollback si auth.users falla

**Archivo:** `src/onboarding/onboarding.service.ts` — `completeOwnerScaffold()`  
**Flujo:**
1. Mark link as used (`WHERE used_at IS NULL` — atomic ✅)
2. Create Supabase auth user
3. Create internal user row
4. Update nv_accounts

**Impacto:** Si paso 2 (crear auth user) falla después de que el link fue marcado como usado, el link queda consumido y el usuario no puede reintentarlo. Queda en un estado irrecuperable.

**Recomendación:** Implementar compensación: si auth user creation falla, revertir `used_at` del link, o permitir reutilización con una ventana de tiempo.

---

#### P1-8: `POST /clients/:clientId/mp-secrets` — Ownership check semánticamente incorrecta

**Archivo:** `src/onboarding/onboarding.controller.ts` ~línea 890  
**Código:**
```typescript
@Post('clients/:clientId/mp-secrets')
async saveMPSecrets(@Req() req, @Param('clientId') clientId: string, ...) {
  if (clientId !== req.account_id) {
    throw new ForbiddenException('Not authorized');
  }
}
```

**Impacto:** `clientId` es un UUID del Backend DB (tabla `clients`), mientras que `req.account_id` es un UUID del Admin DB (tabla `nv_accounts`). Estos NUNCA son iguales. Resultado: **el endpoint siempre retorna 403** o, si por algún motivo los IDs coincidieran, no es una validación de ownership real.

**Recomendación:** Resolver ownership via slug: obtener el slug del account, buscar el client con ese slug en backend, comparar el clientId del param con el ID del client encontrado.

---

### 🟡 P2 — Medios (impacto bajo, mejoras necesarias)

---

#### P2-1: `GET /onboarding/public/status` expone información sin auth

**Archivo:** `src/onboarding/onboarding.controller.ts` ~línea 270  
**Impacto:** Cualquiera puede consultar `?slug=X` y obtener si existe una tienda en onboarding, su estado, etc. Permite enumerar slugs y obtener inteligencia sobre cuentas.

**Recomendación:** Limitar la información retournada al mínimo ("exists" / "not found") o requerir un token público del builder.

---

#### P2-2: Inconsistencia en extracción de `account_id`

**Archivo:** `src/onboarding/onboarding.controller.ts` — `business-info` endpoint  
**Código:** Usa `req.builderSession?.account_id` mientras la mayoría de endpoints usan `req.account_id`.

**Impacto:** Si el guard popula uno pero no el otro, el endpoint falla silenciosamente o accede al account incorrecto.

**Recomendación:** Unificar a `req.account_id` en todo el controller.

---

#### P2-3: `getLogoUploadUrl` retorna URL placeholder (no implementado)

**Archivo:** `src/onboarding/onboarding.service.ts` ~línea 2555  
**Código:**
```typescript
this.logger.warn('TODO: Implement Supabase Storage signed upload URL');
return {
  path,
  signedUrl: `https://storage.supabase.co/signed-upload-url-placeholder?path=${path}`,
};
```

**Impacto:** Cualquier cliente que invoque este endpoint recibe una URL inválida. Si algún flujo confía en esta URL para subir logo, el upload falla silenciosamente.

---

#### P2-4: `uploadSessionAsset` no valida Content-Type de archivo

**Archivo:** `src/onboarding/onboarding.service.ts` — `uploadSessionAsset()`  
**Código:**
```typescript
async uploadSessionAsset(accountId: string, file: Express.Multer.File, assetType: ...) {
  const ext = file.originalname.split('.').pop();  // ← Confía en extensión del filename
  // ... uploads to storage with file.mimetype
}
```

**Impacto:** Un atacante podría subir archivos maliciosos con extensión `.png` pero contenido ejecutable. El 5MB limit de FileInterceptor ayuda, pero no hay validación de magic bytes.

**Recomendación:** Validar `file.mimetype` contra una allowlist (`image/png`, `image/jpeg`, `image/webp`) y opcionalmente verificar magic bytes.

---

#### P2-5: `BuilderSessionGuard` usa `console.log` en vez de NestJS Logger

**Archivo:** `src/guards/builder-session.guard.ts`  
**Impacto:** Los logs no pasan por el sistema de logging estructurado de NestJS, perdiendo context metadata y posiblemente no apareciendo en logs de producción.

---

#### P2-6: `acceptTerms` usa `listUsers()` para buscar por email

**Archivo:** `src/onboarding/onboarding.service.ts` — `acceptTerms()`  
**Código:**
```typescript
const { data: usersData } = await adminClient.auth.admin.listUsers();
const authUser = usersData?.users?.find((u: any) => u.email === account.email);
```

**Impacto:** Lista TODOS los auth users del proyecto (O(n)) para buscar uno por email. Con miles de usuarios, esto es lento y consume memoria innecesariamente.

**Recomendación:** Usar `adminClient.auth.admin.getUserByEmail(account.email)` o `listUsers({ filter: email })`.

---

#### P2-7: `updateOnboardingState` es un setter genérico sin validación de transiciones

**Archivo:** `src/onboarding/onboarding.service.ts` línea 3190  
**Código:**
```typescript
async updateOnboardingState(accountId: string, state: string, reason?: string) {
  // Acepta cualquier string como state
  await adminClient.from('nv_onboarding').update({ state, ... })
}
```

**Impacto:** Cualquier código interno puede poner un estado inválido. No hay defensa contra bugs que envíen un estado no reconocido.

**Recomendación:** Crear un enum `OnboardingState` y validar contra él.

---

#### P2-8: `approveOnboarding` pasa `accountId` como clusterId

**Archivo:** `src/onboarding/onboarding.service.ts` línea 3694  
**Código:**
```typescript
const backendClient = this.dbRouter.getBackendClient(accountId);
// ↑ accountId no es un cluster ID válido
```

**Impacto:** `getBackendClient()` probablemente retorna el default cluster si no reconoce el ID, pero esto es un bug semántico que podría causar problemas si la lógica de routing cambia.

**Recomendación:** Resolver `backend_cluster_id` del `nv_accounts` antes de llamar a `getBackendClient()`.

---

#### P2-9: `publishStore` no verifica estado de suscripción

**Archivo:** `src/onboarding/onboarding.service.ts` — `publishStore()` línea 2840  

**Nota:** La misma clase tiene un método `checkCanPublish()` que SÍ verifica la suscripción, pero `publishStore` **no lo invoca**.

**Código:**
```typescript
async publishStore(accountId: string): Promise<void> {
  const account = await this.getAccount(accountId);
  // ... directamente setea publication_status sin verificar subscription
}
```

**Recomendación:** Invocar `checkCanPublish()` al inicio de `publishStore()` y abortar si retorna `can: false`.

---

## 5. Resumen Ejecutivo

### Distribución de hallazgos

| Severidad | Cant. | Descripción |
|-----------|-------|-------------|
| 🔴 P0 | 4 | Vulnerabilidades explotables sin autenticación o con bypass trivial |
| 🟠 P1 | 8 | Vulnerabilidades explotables requiriendo autenticación básica (builder token) |
| 🟡 P2 | 9 | Defectos de calidad y seguridad defense-in-depth |

### Top 3 acciones inmediatas recomendadas

1. **Proteger webhook** (P0-2): Fallar cerrado cuando `MP_WEBHOOK_SECRET` no está configurado. Deploy: 5 minutos.
2. **Eliminar fallback de `checkout/confirm`** (P0-3): No aceptar `body.status` del frontend. Deploy: 15 minutos.
3. **Agregar captcha a `builder/start`** (P0-1): Integrar `CaptchaService` existente. Deploy: ~1 hora.

### Arquitectura positiva observada

- ✅ Provisioning con patrón Saga y step ledger (resumible, idempotente)
- ✅ Job claiming con `FOR UPDATE SKIP LOCKED`
- ✅ Webhook idempotente via `webhook_events` + unique constraint
- ✅ Encriptación AES-256-GCM para MP tokens
- ✅ Timing-safe comparison en SuperAdminGuard
- ✅ Zod validation en `importHomeBundle`
- ✅ HMAC-firmados preview tokens con TTL
- ✅ Rate-limit global Express como baseline
- ✅ `class-validator` en `SubmitWizardDataDto`

---

*Fin de auditoría. Cada hallazgo incluye archivo, línea y snippet para facilitar la remediación.*

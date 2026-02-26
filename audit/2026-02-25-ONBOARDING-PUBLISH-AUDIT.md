# Auditoría de Onboarding y Publicación de Tienda — NovaVision

**Fecha:** 2026-02-25  
**Alcance:** Wizard de onboarding (12 pasos) + Publicación + Aprobación + Provisioning  
**Repos:** API (`onboarding.controller.ts` 1247L, `onboarding.service.ts` 3795L, `mp-oauth.service.ts` 979L) + Admin (WizardContext, Steps, api.ts) + Web (PreviewHost)  
**Metodología:** Inspección estática de código con verificación directa de hallazgos

---

## 1. RESUMEN EJECUTIVO

El flujo de onboarding es **arquitectónicamente sólido** (saga pattern, job steps, idempotency, AES-256-GCM para credenciales MP, JWT builder sessions, slug reservations). Sin embargo, tiene **5 vulnerabilidades P0** y **un bug funcional bloqueante** que impide aprobar tiendas.

### Top 10 Riesgos

| # | Sev | Hallazgo | Impacto |
|---|-----|----------|---------|
| 1 | 🔴 P0 | **Bug de estado:** `submitForReview` escribe `'submitted_for_review'` pero `approveOnboarding` espera `'review_pending'` → **ninguna tienda puede aprobarse** | Bloqueante funcional |
| 2 | 🔴 P0 | **Webhook MP sin firma** si `MP_WEBHOOK_SECRET` no está configurado → pagos falsos | Fraude financiero |
| 3 | 🔴 P0 | **checkout/confirm fallback** confía en `body.status` del frontend → bypass de pago | Tiendas publicadas sin pagar |
| 4 | 🔴 P0 | **link-user IDOR** — acepta cualquier `user_id` sin validar vs JWT → hijack de cuentas | Takeover de sesiones |
| 5 | 🔴 P0 | **MP tokens plain-text** en Backend DB → si se compromete la DB, todos los tokens expuestos | Credential leak masivo |
| 6 | 🟠 P1 | **builder/start sin captcha ni rate limit** (TODO pendiente en código) | Spam de cuentas |
| 7 | 🟠 P1 | **PII en localStorage** (contraseña, DNI, CUIT, builder token) | Exfiltración vía XSS |
| 8 | 🟠 P1 | **PreviewHost sin validación de origen** en postMessage | Inyección de contenido |
| 9 | 🟠 P1 | **link-google no valida id_token** server-side → email spoofing | Account takeover |
| 10 | 🟡 P2 | **validatePlanLimits fail-open** si no encuentra entitlements | Bypass de límites |

---

## 2. MAPA DE ENDPOINTS DEL ONBOARDING

### Verificado directamente del código: [onboarding.controller.ts](apps/api/src/onboarding/onboarding.controller.ts)

| # | Método | Ruta | Auth | Guard | DTO Formal | Validación actual |
|---|--------|------|:----:|-------|:----------:|-------------------|
| 1 | GET | `/active-countries` | ❌ | — | ❌ | Ninguna (read-only) |
| 2 | GET | `/country-config/:countryId` | ❌ | — | ❌ | Solo `:countryId` param |
| 3 | **POST** | **`/builder/start`** | ❌ | — | ❌ | `if (!email \|\| !slug)` — manual, sin DTO | 
| 4 | POST | `/resolve-link` | ❌ | — | ❌ | body.token presencia |
| 5 | POST | `/complete-owner` | 🔑 | BuilderSessionGuard | ❌ | Manual body checks |
| 6 | POST | `/import-home-bundle` | 🔑 | BuilderSessionGuard | ❌ | Manual |
| 7 | GET | `/status` | 🔑 | BuilderSessionGuard | — | — |
| 8 | GET | `/public/status` | ❌ | — | — | Query param `slug` |
| 9 | PATCH | `/progress` | 🔑 | BuilderSessionGuard | ❌ | **JSON arbitrario** — sin schema |
| 10 | PATCH | `/preferences` | 🔑 | BuilderSessionGuard | ❌ | Manual |
| 11 | PATCH | `/custom-domain` | 🔑 | BuilderSessionGuard | ❌ | Manual |
| 12 | GET | `/plans` | ❌ | — | — | Read-only |
| 13 | GET | `/palettes` | ❌ | — | — | Read-only |
| 14 | POST | `/preview-token` | 🔑 | BuilderSessionGuard | ❌ | — |
| 15 | POST | `/checkout/start` | 🔑 | BuilderSessionGuard | ❌ | Manual |
| 16 | GET | `/checkout/status` | 🔑 | BuilderSessionGuard | — | — |
| 17 | **POST** | **`/checkout/confirm`** | 🔑 | BuilderSessionGuard | ❌ | **Fallback: `body.status`** ⚠️ |
| 18 | POST | `/link-google` | 🔑 | BuilderSessionGuard | ❌ | Solo `body.email` presencia |
| 19 | **POST** | **`/checkout/webhook`** | ❌ | — | ❌ | **Firma condicional** ⚠️ |
| 20 | POST | `/business-info` | 🔑 | BuilderSessionGuard | ❌ | Manual |
| 21 | POST | `/mp-credentials` | 🔑 | BuilderSessionGuard | ❌ | — |
| 22 | POST | `/submit-for-review` | 🔑 | BuilderSessionGuard | ❌ | Validación interna |
| 23 | POST | `/submit` | 🔑 | BuilderSessionGuard | ❌ | Validación interna |
| 24 | **POST** | **`/publish`** | 🔑 | BuilderSessionGuard | ❌ | `checkCanPublish()` |
| 25 | POST | `/logo/upload-url` | 🔑 | BuilderSessionGuard | ❌ | — |
| 26 | POST | `/clients/:clientId/mp-secrets` | 🔑 | BuilderSessionGuard | ❌ | **Sin ownership check** ⚠️ |
| 27 | POST | `/session/save` | 🔑 | BuilderSessionGuard | ❌ | — |
| 28 | POST | `/session/upload` | 🔑 | BuilderSessionGuard | ❌ | — |
| 29 | **POST** | **`/session/link-user`** | 🔑 | BuilderSessionGuard | ❌ | **Solo presencia de user_id** ⚠️ |
| 30 | GET | `/mp-status` | 🔑 | BuilderSessionGuard | — | — |
| 31 | POST | `/session/accept-terms` | 🔑 | BuilderSessionGuard | ❌ | `body.version` presencia |
| 32 | GET | `/resume` | 🔑 | BuilderOrSupabaseGuard | ❌ | **IDOR: user_id de query param** ⚠️ |
| 33 | **POST** | **`/approve/:accountId`** | 🔑 | **SuperAdminGuard** | ❌ | Verifica estado |

**Resumen DTOs:** De 33 endpoints, **0 usan DTOs formales** con class-validator. Todo es validación manual inline.

---

## 3. HALLAZGOS P0 — CRÍTICOS

### O-01: Bug de estado bloqueante — `submitForReview` vs `approveOnboarding`

**Archivos:**
- [onboarding.service.ts L2193](apps/api/src/onboarding/onboarding.service.ts#L2193): escribe `state: 'submitted_for_review'`
- [onboarding.service.ts L3610](apps/api/src/onboarding/onboarding.service.ts#L3610): verifica `onb.state !== 'review_pending'`

**Código verificado:**
```typescript
// submitForReview (L2193):
const updatePayload: any = {
  state: 'submitted_for_review',  // ← ESCRIBE ESTE VALOR
  submitted_at: new Date().toISOString(),
};

// approveOnboarding (L3610):
if (!onb || onb.state !== 'review_pending')  // ← ESPERA ESTE OTRO VALOR
  throw new BadRequestException('Not pending');
```

**Impacto:** `approveOnboarding` **siempre falla** porque `submitForReview` nunca escribe `'review_pending'`, escribe `'submitted_for_review'`. El flujo `publishStore` escribe `'pending_approval'`/`'pending_content'` — **tampoco matchea**.

**Rutas posibles de estado:**
```
submitForReview → 'submitted_for_review'  ❌ No matchea
publishStore    → 'pending_approval'      ❌ No matchea  
approve espera  → 'review_pending'        ❌ NUNCA se escribe
```

**Posibilidad:** El admin podría usar un endpoint manual que setee `'review_pending'`, o hay un workaround que no detecté. **Verificar con el equipo**.

**Fix:** Cambiar L3610 a:
```typescript
if (!onb || !['submitted_for_review', 'pending_approval'].includes(onb.state))
```

---

### O-02: Webhook MP procesa sin firma si `MP_WEBHOOK_SECRET` no está configurado

**Archivo:** [onboarding.controller.ts L589-606](apps/api/src/onboarding/onboarding.controller.ts#L589)

**Código verificado:**
```typescript
@Post('checkout/webhook')
@HttpCode(HttpStatus.OK)
async mpWebhook(@Req() req: Request, @Body() body: any) {
  const secret = this.config.get<string>('MP_WEBHOOK_SECRET');
  if (secret) {                                    // ← CONDICIONAL
    const valid = this.verifyWebhookSignature(req, secret);
    if (!valid) throw new UnauthorizedException('Invalid signature');
  } else {
    this.logger.warn('[Onboarding MP] MP_WEBHOOK_SECRET no configurado');
    // ← NO FALLA, CONTINÚA PROCESANDO
  }
  await this.onboardingService.handleCheckoutWebhook(body);
  return { ok: true };
}
```

**Impacto:** Si la env var no está configurada, **cualquiera puede enviar un webhook falso** y marcar cuentas como pagadas.

**Fix (5 min):**
```typescript
if (!secret) throw new InternalServerErrorException('Webhook config missing');
```

---

### O-03: `checkout/confirm` confía en body.status del frontend

**Archivo:** [onboarding.controller.ts L513-574](apps/api/src/onboarding/onboarding.controller.ts#L513)

**Código verificado:**
```typescript
@Post('checkout/confirm')
async confirmCheckout(@Req() req, @Body() body: {
  status?: 'paid' | 'pending' | 'error';
  external_reference?: string;
  preapproval_id?: string;
}) {
  // Si hay preapproval_id → verifica con MP directamente ✅ CORRECTO
  if (body.preapproval_id) {
    const mpSub = await this.onboardingService.getMpSubscription(body.preapproval_id);
    if (mpSub.status === 'authorized' || mpSub.status === 'active') {
      // ... sync legítimo
      return { ok: true, status: 'paid' };
    }
  }
  
  // FALLBACK: confía en body.status del frontend ⚠️ PELIGROSO
  await this.onboardingService.setCheckoutStatus(
    accountId,
    body?.status || 'pending',  // ← body.status = 'paid' → cuenta pagada
  );
  return { ok: true };
}
```

**Impacto:** Un usuario puede enviar `{ status: 'paid' }` sin `preapproval_id` y el endpoint marca la cuenta como pagada.

**Mitigación parcial:** `setCheckoutStatus` solo actualiza `progress.checkout_status`, no directamente `nv_accounts.status`. Pero otros flujos podrían leer `checkout_status === 'paid'` para permitir avance.

**Fix:** Eliminar el fallback de `body.status` y solo aceptar `preapproval_id` verificado:
```typescript
if (!body.preapproval_id) {
  throw new BadRequestException('preapproval_id required');
}
```

---

### O-04: link-user — IDOR sin validación de ownership

**Archivo:** [onboarding.controller.ts L1121-1135](apps/api/src/onboarding/onboarding.controller.ts#L1121)

**Código verificado:**
```typescript
@Post('session/link-user')
async linkUser(@Req() req, @Body() body: { user_id: string }) {
  const accountId = req.account_id;  // del builder JWT
  if (!body.user_id) throw new BadRequestException('user_id required');
  await this.onboardingService.linkUserToSession(accountId, body.user_id);
  return { ok: true };
}
```

**Service (L3348-3386):** Vincula `userId` a la cuenta, Y además **desvincula** ese `userId` de OTRAS cuentas existentes:
```typescript
// ¡TAMBIÉN desvincula de cuentas ajenas!
const { data: conflicts } = await adminClient
  .from('nv_accounts')
  .select('id, status, email')
  .eq('user_id', userId)
  .neq('id', accountId);

for (const conflict of conflicts) {
  await adminClient
    .from('nv_accounts')
    .update({ user_id: null })  // ← Desvincula víctima
    .eq('id', conflict.id);
}
```

**Impacto:** 
1. Atacante crea builder session → obtiene `builder_token`
2. Envía `link-user` con `user_id` de otra persona
3. La víctima queda **desvinculada de su propia cuenta**
4. El atacante queda vinculado a su propia cuenta con el `user_id` robado

**Fix:** Validar que `body.user_id` coincide con el JWT de Supabase del request, o que no esté ya vinculado a una cuenta activa.

---

### O-05: MP tokens desencriptados y guardados en plain text

**Archivo:** [mp-oauth.service.ts L927-970](apps/api/src/mp-oauth/mp-oauth.service.ts#L927)

**Código verificado:**
```typescript
async syncMpCredentialsToBackend(accountId: string, clientId: string) {
  // Lee encrypted del Admin DB
  const { data: account } = await adminClient
    .from('nv_accounts')
    .select('mp_access_token_encrypted, mp_public_key, mp_connected')
    .eq('id', accountId).single();

  // Descifra
  const accessToken = this.decryptToken(account.mp_access_token_encrypted);

  // Guarda en PLAIN TEXT en Backend DB
  const backendPool = this.dbRouter.getBackendPool('cluster_shared_01');
  await backendPool.query(
    'UPDATE clients SET mp_access_token = $1, mp_public_key = $2 WHERE id = $3',
    [accessToken, account.mp_public_key, clientId],  // ← PLAIN TEXT
  );
}
```

**Impacto:** El Admin DB cifra correctamente con AES-256-GCM. Pero el Backend DB (que tiene RLS con anon key visible) guarda todo en texto plano. Si un atacante logra leer la tabla `clients` → obtiene `mp_access_token` de TODOS los sellers.

**Fix:** Cifrar en Backend DB también, o mejor: que el backend nunca almacene el token y siempre lo obtenga del Admin DB on-demand.

---

## 4. HALLAZGOS P1 — ALTO

### O-06: builder/start sin captcha ni rate limiting

**Archivo:** [onboarding.controller.ts L139-156](apps/api/src/onboarding/onboarding.controller.ts#L139)

```typescript
@AllowNoTenant()
@Post('builder/start')
async startBuilder(@Body() body: { email: string; slug: string }) {
  // TODO: Verificar captcha
  // TODO: Rate limits multi-factor (IP + email + fingerprint)
  const result = await this.onboardingService.startDraftBuilder(email, slug);
```

**Impacto:** Un script puede crear miles de cuentas draft/reservar todos los slugs.
**Fix:** Implementar CAPTCHA + rate limiting (3 cuentas/IP/hora).

---

### O-07: PII en localStorage (contraseña incluida)

**Archivo:** [WizardContext.tsx](apps/admin/src/context/WizardContext.tsx)

```tsx
// Estado incluye:
draftOwnerDetails: { password: string }  // ← CONTRASEÑA
dniNumber, dniFrontUrl, dniBackUrl       // ← DOCUMENTOS
fiscalId                                 // ← CUIT
builderToken                             // ← JWT

// Y se persiste en cada cambio:
localStorage.setItem('wizard_state', JSON.stringify(state));
```

**Impacto:** XSS, extensiones, o acceso físico exponen contraseña y docs personales.
**Fix:** No guardar `password` en state. Pedirlo al momento del submit. Mover `builderToken` a `sessionStorage`.

---

### O-08: PreviewHost sin validación de origen

**Archivo:** [PreviewHost/index.tsx](apps/web/src/pages/PreviewHost/index.tsx)

```tsx
window.addEventListener('message', handler);
// handler acepta mensajes de CUALQUIER origen
// isValidPreviewToken importado pero NO usado
```

**Fix:** Validar `event.origin` contra allowlist de dominios admin.

---

### O-09: link-google no valida id_token server-side

**Archivo:** [onboarding.controller.ts L577-586](apps/api/src/onboarding/onboarding.controller.ts#L577)

```typescript
@Post('link-google')
async linkGoogle(@Req() req, @Body() body: { email: string }) {
  // Acepta email del body sin verificar token de Google
  await this.onboardingService.linkGoogleAccount(accountId, email);
}
```

**Impacto:** Un usuario puede cambiar el email de su cuenta a cualquier email de Google sin demostrar que lo posee.
**Fix:** Exigir `id_token` de Google, validar con `google-auth-library` server-side.

---

### O-10: IDOR en GET /resume

**Archivo:** [onboarding.controller.ts L1211-1221](apps/api/src/onboarding/onboarding.controller.ts#L1211)

```typescript
@UseGuards(BuilderOrSupabaseGuard)
@Get('resume')
async resumeOnboarding(@Query('user_id') userId: string) {
  return await this.onboardingService.resumeSession(userId);
}
```

El `user_id` viene de query params. `BuilderOrSupabaseGuard` presenta autenticación pero no verifica que el userId solicitado sea el mismo que el autenticado.

**Fix:** Extraer `user_id` del JWT, no del query param.

---

### O-11: `/clients/:clientId/mp-secrets` sin ownership check

**Archivo:** [onboarding.controller.ts L1004](apps/api/src/onboarding/onboarding.controller.ts#L1004)

```typescript
@Post('/clients/:clientId/mp-secrets')
async syncMpSecrets(@Req() req, @Param('clientId') clientId: string) {
  const accountId = req.account_id;
  // Usa clientId del URL sin verificar que pertenece a accountId
  await this.mpOauthService.syncMpCredentialsToBackend(accountId, clientId);
}
```

**Impacto:** Un builder podría sincronizar sus credenciales MP al `clientId` de **otra tienda**.
**Fix:** Verificar que `clientId` corresponde a `accountId` antes de sincronizar.

---

## 5. HALLAZGOS P2 — MEDIO

| # | Hallazgo | Archivo | Impacto |
|---|----------|---------|---------|
| O-12 | `PATCH /progress` acepta JSON arbitrario — permite sobrescribir claves internas de `nv_onboarding.progress` | controller L309 | Manipulación de estado del wizard |
| O-13 | `validatePlanLimits` retorna `valid: true` si no encuentra entitlements (fail-open) | service L2075 | Bypass de límites de plan |
| O-14 | `publishStore` no verifica suscripción activa (solo `checkCanPublish` del controller valida) | service L2944 | Si se llama directamente, publishStore no chequea pago |
| O-15 | Triple fallback de builder token en localStorage (`wizard_state.builderToken`, `builder_token`, `novavision_builder_token`) | admin api.ts | Surface area multiplicada para token |
| O-16 | Token vacío como fallback (`state.builderToken || ""`) en múltiples steps | admin Steps*.tsx | Requests sin auth que generan errores confusos |
| O-17 | `approveOnboarding` pasa `accountId` como `clusterId` a DB router (funciona por default pero es incorrecto) | service L~3644 | Podría fallar si hay clusters distintos |
| O-18 | `isValidPreviewToken()` solo verifica `typeof string && length >= 8` — no verifica contra backend | web previewUtils.ts | Preview token sin validación real |
| O-19 | `GET /public/status?slug=` no tiene rate limit — permite enumerar slugs | controller L293 | Leak de qué slugs existen |

---

## 6. DIAGRAMA DE ESTADOS (verificado del código)

```
                          ┌──────────────────────────────────┐
                          │                                  │
                          ▼                                  │
  ┌─────────────────┐ POST /builder/start              ┌────┴──────────┐
  │  draft_builder   │─────────────────────────────────▶│   (wizard UI)  │
  └────────┬────────┘                                   └───────────────┘
           │
           │ POST /submit-for-review
           ▼
  ┌──────────────────────┐
  │ submitted_for_review  │ ← submitForReview escribe esto
  └────────┬─────────────┘
           │
           │ POST /publish (si pagó)
           ▼
  ┌──────────────────────┐     ┌────────────────┐
  │  pending_approval     │ o   │ pending_content │  ← publishStore escribe estos
  └────────┬─────────────┘     └───────┬────────┘
           │                           │
           │ POST /approve/:id         │ (admin manual fix?)
           ▼                           │
  ┌──────────────────────────────────────┐
  │   approve FALLA ❌                    │ ← espera 'review_pending'
  │   (nunca nadie escribe ese estado)   │    pero nadie lo escribe
  └──────────────────────────────────────┘

  WORKAROUND POSIBLE:
  - Admin ejecuta SQL directo: UPDATE nv_onboarding SET state='review_pending'
  - O hay un endpoint admin no encontrado en este controller
```

---

## 7. FLUJO DE DATOS: PUBLICACIÓN Y PROVISIONING

```
┌───────────────────────────────────────────────────────────────┐
│  DURANTE ONBOARDING (Steps 1-12)                              │
│                                                                │
│  → Todo se guarda en ADMIN DB                                 │
│    ├─ nv_accounts (email, slug, plan, business data)          │
│    ├─ nv_onboarding (state, progress JSON, design_config)     │
│    └─ nv_accounts (mp_access_token_encrypted — AES-256-GCM)  │
│                                                                │
│  → BACKEND DB NO SE TOCA                                      │
└───────────────────┬───────────────────────────────────────────┘
                    │
                    │ POST /publish (builder token)
                    ▼
┌───────────────────────────────────────────────────────────────┐
│  publishStore()                                                │
│                                                                │
│  1. checkCanPublish() → verifica suscripción activa            │
│  2. Busca client en Backend DB por slug                        │
│  3. Cuenta productos → decide status:                          │
│     ├─ >= 10 productos → 'pending_approval'                    │
│     └─ < 10 productos  → 'pending_content'                    │
│  4. UPDATE clients SET publication_status, is_published=false   │
│  5. UPDATE nv_onboarding SET state = publication_status        │
│                                                                │
│  ⚠️ NO sincroniza productos/diseño aquí                       │
│  ⚠️ NO verifica que client exista en Backend DB antes          │
└───────────────────┬───────────────────────────────────────────┘
                    │
                    │ POST /approve/:accountId (SuperAdmin)
                    ▼
┌───────────────────────────────────────────────────────────────┐
│  approveOnboarding()                                           │
│                                                                │
│  1. ❌ FALLA: espera state='review_pending'                    │
│     (NUNCA se escribe ese valor — ver O-01)                    │
│                                                                │
│  SI FUNCIONARA (post-fix):                                     │
│  2. UPDATE nv_onboarding SET state='approved'                  │
│  3. UPDATE nv_accounts SET status='active', is_published=true   │
│  4. OnboardingMigrationHelper.migrateToBackendDB():            │
│     ├─ Sync productos → Backend DB products table              │
│     ├─ Sync categorías → Backend DB categories table           │
│     ├─ Sync FAQs → Backend DB faqs table                       │
│     ├─ Sync settings (logo, social, contact) → Backend DB      │
│     └─ Sync design_config → client_home_settings               │
│  5. CleanupAdminData():                                        │
│     └─ Borra progress JSON de nv_onboarding (cleanup)          │
│  6. Upsert user en Backend DB users table (admin role)          │
│  7. syncMpCredentialsToBackend():                              │
│     └─ ⚠️ DESCIFRA AES → GUARDA PLAIN TEXT en clients          │
└───────────────────────────────────────────────────────────────┘
```

---

## 8. ASPECTOS POSITIVOS ENCONTRADOS

| # | Feature | Implementación |
|---|---------|---------------|
| ✅ | **AES-256-GCM** para MP tokens en Admin DB | IV random + authenticated encryption, key rotation ready |
| ✅ | **SuperAdminGuard robusto** | `timingSafeEqual` + fail-closed si falta `INTERNAL_ACCESS_KEY` |
| ✅ | **Slug reservations** con TTL 24h | Previene squatting durante onboarding |
| ✅ | **Builder JWT con expiración** | Configurable via env (default 30 días) |
| ✅ | **Saga pattern** en provisioning worker | `runStep()` con `provisioning_job_steps` para recover |
| ✅ | **Job claim con SKIP LOCKED** | Previene doble procesamiento |
| ✅ | **Webhook idempotency** | `webhook_events` table |
| ✅ | **external_reference assertion** | Valida que `external_reference` del callback matchea el stored |
| ✅ | **Legal consent logging** | IP + user-agent (Ley 25.326 / Disp. 954/2025) |
| ✅ | **Subscription-based publish check** | Verifica `current_period_end` y `grace_ends_at` |

---

## 9. PLAN DE CORRECCIONES

### Sprint Inmediato (esta semana)

| # | Fix | Esfuerzo | Archivos |
|---|-----|----------|----------|
| F1 | **Fix estado approve** — aceptar `'submitted_for_review'` y `'pending_approval'` en `approveOnboarding` | 15min | onboarding.service.ts L3610 |
| F2 | **Fail-closed webhook** — `if (!secret) throw` | 5min | onboarding.controller.ts L596 |
| F3 | **Eliminar fallback `body.status`** en checkout/confirm | 15min | onboarding.controller.ts L565 |
| F4 | **Validar user_id** en link-user contra JWT | 30min | onboarding.controller.ts L1122 + service |
| F5 | **No guardar password** en WizardContext/localStorage | 1h | admin WizardContext.tsx |

### Sprint 2 (semana 2)

| # | Fix | Esfuerzo |
|---|-----|----------|
| F6 | Cifrar MP tokens en Backend DB (o no almacenarlos) | 3h |
| F7 | Implementar CAPTCHA en builder/start | 2h |
| F8 | Validar `event.origin` en PreviewHost | 30min |
| F9 | Validar Google `id_token` server-side en link-google | 2h |
| F10 | Extraer `user_id` del JWT en GET /resume (no query param) | 15min |
| F11 | Verificar ownership de clientId en mp-secrets | 30min |
| F12 | Schema validation para PATCH /progress (JSON schema o Zod) | 2h |

### Sprint 3 (semana 3-4)

| # | Fix | Esfuerzo |
|---|-----|----------|
| F13 | Crear DTOs formales para los 33 endpoints del onboarding | 8h |
| F14 | Migrar builderToken a sessionStorage (borrar triple key) | 1h |
| F15 | Rate limiting en builder/start y public/status | 2h |
| F16 | Fail-closed en validatePlanLimits si no hay entitlements | 15min |
| F17 | Auto-save server-side post-pago (checkpoint recovery) | 4h |

---

## 10. CASOS DE PRUEBA RECOMENDADOS

### Security Tests
| # | Test | Escenario | Esperado |
|---|------|-----------|----------|
| T1 | Webhook sin firma | `POST /checkout/webhook` sin `x-signature` y sin `MP_WEBHOOK_SECRET` en env | 500 (fail-closed) |
| T2 | Confirm con status falso | `POST /checkout/confirm` con `{ status: 'paid' }` sin `preapproval_id` | 400 |
| T3 | Link-user ajeno | `POST /session/link-user` con `user_id` de otro usuario | 403 |
| T4 | Resume IDOR | `GET /resume?user_id=<otro>` | 403 (solo propio) |
| T5 | MP secrets cross-tenant | `POST /clients/<otro-client>/mp-secrets` | 403 |
| T6 | Approve con estado incorrecto | `POST /approve/:id` cuando state=`submitted_for_review` | **Actualmente: falla ❌** |
| T7 | Builder start spam | 100x `POST /builder/start` misma IP en 1 min | 429 (rate limit) |
| T8 | Link-google email spoof | `POST /link-google` con email ajeno sin id_token | 400 |

### Happy Path Tests
| # | Test | Pasos |
|---|------|-------|
| T9 | Onboarding completo | Steps 1→12 → submit → approve → store visible |
| T10 | Checkout MP | start → redirect MP → webhook → confirm |
| T11 | Resume tras cierre | Completar hasta step 6 → cerrar → reabrir → resume en step 6 |
| T12 | Publicación con <10 productos | publish → status='pending_content' |
| T13 | Publicación con ≥10 productos | publish → status='pending_approval' |

---

## 11. ITEMS NO VERIFICABLES EN ESTA AUDITORÍA

| # | Item | Cómo verificar |
|---|------|---------------|
| 1 | `BuilderSessionGuard` — ¿valida JWT correctamente o solo existencia del header? | Leer guard completo |
| 2 | `BuilderOrSupabaseGuard` — ¿verifica que el user_id del JWT matchea el query param? | Leer guard |
| 3 | `handleCheckoutWebhook` — ¿qué hace exactamente con el payload? | Service L977+ |
| 4 | `OnboardingMigrationHelper.migrateToBackendDB` — ¿qué tablas sincroniza exactamente? | Helper completo |
| 5 | ProvisioningWorkerService — ¿existe y funciona? | Buscar en codebase |
| 6 | `startDraftBuilder` — ¿dedup de email/slug es atomic? | Service L368+ |

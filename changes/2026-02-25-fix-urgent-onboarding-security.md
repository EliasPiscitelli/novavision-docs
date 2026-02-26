# Fix: 3 Hallazgos Urgentes de Seguridad/Integridad en Onboarding

- **Autor:** agente-copilot
- **Fecha:** 2026-02-25
- **Rama:** feature/automatic-multiclient-onboarding
- **Repo:** templatetwobe (API)

## Archivos modificados

- `src/onboarding/onboarding.service.ts`
- `src/onboarding/onboarding.controller.ts`

---

## O-01: State Machine Bug — BLOQUEANTE EN PRODUCCIÓN

### Problema
`approveOnboarding()` comparaba `onb.state !== 'review_pending'` pero `submitForReview()` escribe `state: 'submitted_for_review'`. El enum `nv_onboarding_state` tiene ambos valores pero nunca se escribía `review_pending`.

**Impacto real:** La cuenta `mariabelenlauria@gmail.com` (slug: `belenlauria`) estaba bloqueada — imposible de aprobar.

**Bug adicional descubierto:** L3619 escribía `is_published: true` en `nv_accounts`, pero esa columna **no existe** en la Admin DB. La columna `is_published` existe en `clients` (Backend DB). Esto causaba un error de Supabase al intentar aprobar.

### Fix aplicado
1. Cambiado check: `'review_pending'` → `'submitted_for_review'`
2. Removido `is_published: true` del update a `nv_accounts`
3. Status se actualiza a `'approved'` (no `'active'` — la publicación la maneja el provisioning)

### Líneas: `onboarding.service.ts` ~L3611-3625

---

## O-03: checkout/confirm Confiaba en Frontend

### Problema
El endpoint `POST /onboarding/checkout/confirm` tenía un fallback que ejecutaba:
```typescript
setCheckoutStatus(accountId, body?.status || 'pending')
```
Un atacante con builder_token podía enviar `{ status: "paid" }` para falsificar el estado de checkout.

### Fix aplicado
El fallback **siempre** setea `'pending'`. Si el frontend envía `status: 'paid'`, se loguea un warning y se ignora. Solo el webhook de MP (con firma verificada) puede setear `'paid'`.

### Líneas: `onboarding.controller.ts` ~L559-573

---

## O-04: IDOR en link-user (Account Takeover)

### Problema
`POST /onboarding/session/link-user` aceptaba cualquier `user_id` del body sin validar que perteneciera al holder de la sesión. Un atacante podía:
1. Iniciar onboarding → obtener builder_token
2. Enviar `user_id` de una víctima
3. La víctima perdía su vinculación (dedup clearing)
4. El atacante se vinculaba a la cuenta de la víctima

### Fix aplicado
1. Se valida que `user_id` exista en Supabase Auth (`auth.admin.getUserById`)
2. Se valida que el email del auth user coincida con el email de la cuenta O el email del builder session JWT
3. Si no matchea → `400 Bad Request` y se loguea el intento bloqueado
4. Se pasa `sessionEmail` desde el controller (del JWT decodificado por BuilderSessionGuard)

### Líneas: `onboarding.service.ts` ~L3348-3440, `onboarding.controller.ts` ~L1142-1155

---

## Validación

| Check | Resultado |
|-------|-----------|
| `npm run lint` | ✅ 0 errores |
| `npm run typecheck` | ✅ ok |
| `npm run build` | ✅ ok |

## Cómo probar

### O-01
1. Buscar cuenta en estado `submitted_for_review` en Admin DB
2. Llamar endpoint de approve → debe funcionar (antes tiraba "Not pending")

### O-03
```bash
curl -X POST https://api.novavision.lat/onboarding/checkout/confirm \
  -H "X-Builder-Token: <token>" \
  -H "Content-Type: application/json" \
  -d '{"status": "paid"}'
```
→ Debe setear `checkout_status: 'pending'` (no `'paid'`)

### O-04
```bash
curl -X POST https://api.novavision.lat/onboarding/session/link-user \
  -H "X-Builder-Token: <token_A>" \
  -d '{"user_id": "<uuid_de_otro_usuario>"}'
```
→ Debe devolver `400` con "user_id email does not match account email"

## Notas de seguridad

- O-04 es la más crítica: prevenía account takeover vía IDOR
- O-01 bloqueaba la aprobación de cuentas reales (impacto directo en negocio)
- O-03 era cosmético (no bypasseaba provisioning) pero rompía integridad de datos
- La Admin DB (Supabase) usa `auth.admin.getUserById` — opera con service_role, no expone nada al frontend

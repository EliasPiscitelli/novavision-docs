# Fix: Inicialización de Metadata en Signup con Google OAuth

## Problema

Cuando un usuario nuevo hace signup con Google OAuth, Supabase Auth genera un JWT que contiene solo los campos que provee Google (`email`, `name`, `picture`, etc.). Los campos específicos de la aplicación (`client_id`, `role`, `terms_accepted`) **no están presentes** en el primer JWT.

El backend tiene el método `syncUserMetadataWithInternal()` que actualiza el `user_metadata`, pero se ejecuta en `handleSessionAndUser()`, que se llama **después** de que el JWT ya fue generado y enviado al cliente.

## Flujo Actual (con bug)

```
1. Usuario hace clic en "Login with Google" → frontend
2. Redirige a Google OAuth → Google
3. Google devuelve code → Supabase Auth
4. Supabase Auth crea usuario con user_metadata={email, name, picture} → JWT generado
5. Backend recibe callback → auth.service.ts::handleGoogleCallback()
6. Backend llama handleSessionAndUser() → syncUserMetadataWithInternal()
7. Backend actualiza auth.users.raw_user_meta_data con {client_id, role, terms_accepted}
8. ❌ PERO el JWT del paso 4 ya fue enviado al cliente sin estos campos
```

## Flujo Corregido

```
1. Usuario hace clic en "Login with Google" → frontend
2. Redirige a Google OAuth → Google
3. Google devuelve code → Supabase Auth
4. Supabase Auth crea usuario con user_metadata={email, name, picture} → JWT generado
5. Backend recibe callback → auth.service.ts::handleGoogleCallback()
6. Backend llama handleSessionAndUser() → ensureMembership() SI es usuario nuevo
7. ✅ ensureMembership() actualiza INMEDIATAMENTE auth.users.raw_user_meta_data
8. Backend llama syncUserMetadataWithInternal() para sincronizar con tabla users
9. ✅ Frontend recibe JWT con {client_id, role, terms_accepted} ya presentes
```

## Solución

Actualizar `ensureMembership()` en `auth.service.ts` para que **inmediatamente después** de crear el registro en la tabla `users`, también actualice el `raw_user_meta_data` de Supabase Auth.

### Código a Modificar

**Archivo:** `apps/api/src/auth/auth.service.ts`

**Método:** `ensureMembership()`

**Líneas:** Aproximadamente 1200-1290

### Cambios Necesarios

1. Después de insertar el usuario en la tabla `users` (tanto para platform como tenant)
2. Llamar a `adminClient.auth.admin.updateUserById()` con los valores iniciales:
   - `client_id`: 'platform' o el clientId del tenant
   - `role`: defaultRole ('client' para platform, 'user' para tenant)
   - `terms_accepted`: false
   - `personal_info`: el objeto personal_info (solo tenant)

### Implementación

```typescript
// Después de const { data: inserted, error: insErr } = await internalClient.from('users').insert(insertObj)...

// NUEVO: Sincronizar metadata inmediatamente en Supabase Auth
const metadataToSync = {
  client_id: this.isPlatformClientId(clientId) ? 'platform' : normalizedClientId,
  role: defaultRole,
  terms_accepted: false,
};

// Solo incluir personal_info si NO es platform (Admin DB no tiene este campo)
if (!this.isPlatformClientId(clientId)) {
  metadataToSync.personal_info = personal_info;
}

await this.adminClient.auth.admin.updateUserById(userId, {
  user_metadata: metadataToSync,
});

this.logger.log(`[ensureMembership] Metadata inicializado para nuevo usuario ${userId}`);
```

## Cobertura

Este fix asegura que:

1. ✅ **Signup con Google** → metadata inicializado correctamente en primer JWT
2. ✅ **Login con Google** → syncUserMetadataWithInternal() mantiene sincronización
3. ✅ **Aceptar términos** → acceptTerms() actualiza terms_accepted (fix previo)
4. ✅ **OAuth callback frontend** → ClientAuthCallback sincroniza JWT → localStorage (fix previo)
5. ✅ **Hook useTermsAccepted** → lee de JWT + localStorage bidireccional (fix previo)

## Testing

1. Crear un usuario nuevo con Google OAuth desde el wizard
2. Verificar que el JWT contenga `client_id: "platform"`, `role: "client"`, `terms_accepted: false`
3. Consultar `auth.users.raw_user_meta_data` y verificar que los campos estén presentes
4. Verificar que el frontend no redirija al wizard si el usuario ha completado onboarding

## Deployment

- **Branch:** `feature/automatic-multiclient-onboarding`
- **Archivo:** `apps/api/src/auth/auth.service.ts`
- **Método:** `ensureMembership()`
- **Impacto:** Solo afecta a usuarios **nuevos** que hacen signup por primera vez
- **Rollback:** Si hay problemas, revertir el commit de este cambio

---

**Autor:** GitHub Copilot Agent
**Fecha:** 2026-01-28
**Issue:** Terms accepted bug - metadata no inicializado en signup

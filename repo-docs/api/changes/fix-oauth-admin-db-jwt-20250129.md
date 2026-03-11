# Fix OAuth JWT Generation - Admin DB vs Backend DB

- **Autor**: GitHub Copilot Agent
- **Fecha**: 2025-01-29
- **Rama**: main (hotfix requerido)
- **Prioridad**: CRÍTICA (bloqueador de producción)

---

## Resumen

Fix crítico en el flujo OAuth de Google que genera JWT desde la base de datos incorrecta. El backend estaba siempre usando **Backend DB (ulndkhijxtxvpmbbfrgp)** para generar tokens OAuth, causando que usuarios del wizard (que pertenecen a **Admin DB erbfzlsznqsmwmjugspo**) recibieran JWT inválidos.

---

## Problema Identificado

### Síntomas
- Usuario **kaddocpendragon@gmail.com** (ID: 935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0) era redirigido al wizard repetidamente a pesar de haber completado 71% y aceptado términos dos veces
- Error en consola: `invalid JWT: unable to parse or verify signature, token signature is invalid`
- Error en consola: `GET https://erbfzlsznqsmwmjugspo.supabase.co/auth/v1/user 403 (Forbidden)`
- Problema persistía incluso en modo incógnito (descartando cache/sesión local)

### Causa Raíz

Arquitectura de dos bases de datos Supabase:
- **Admin DB** (erbfzlsznqsmwmjugspo): usuarios del wizard/plataforma (pre-aprobación)
- **Backend DB** (ulndkhijxtxvpmbbfrgp): tiendas tenant (post-aprobación)

Cada Supabase project tiene **secreto JWT único**. Un JWT firmado por Backend DB **NO puede validarse** contra Admin DB.

#### Flujo Incorrecto (ANTES del fix)
1. Usuario hace clic en "Login with Google" en wizard
2. Frontend llama `POST /auth/start-google-oauth` con `client_id: "platform"`
3. Backend `auth.service.ts` línea 1991: `this.supabase.auth.signInWithOAuth()` → usa Backend DB
4. Google redirige al callback OAuth
5. Backend `auth.service.ts` línea 2027/2031: `this.supabase.auth.setSession()` / `exchangeCodeForSession()` → usa Backend DB
6. JWT generado está firmado por **Backend DB secret**
7. Frontend intenta validar JWT contra **Admin DB** → 403 Forbidden, signature invalid
8. Loop infinito: sesión inválida → redirect a wizard → login → JWT inválido → ...

---

## Solución Implementada

### Cambios en `apps/api/src/auth/auth.service.ts`

#### 1. Método `startGoogleOAuth()` (línea ~1991)

**ANTES:**
```typescript
const { data, error } = await this.supabase.auth.signInWithOAuth({
  provider: 'google',
  options: { redirectTo, skipBrowserRedirect: true, scopes: 'email profile' },
});
```

**DESPUÉS:**
```typescript
// CRITICAL FIX: Use Admin DB for platform/wizard users, Backend DB for tenant stores
const oauthClient = this.getInternalClient(trimmedClientId);

const { data, error } = await oauthClient.auth.signInWithOAuth({
  provider: 'google',
  options: { redirectTo, skipBrowserRedirect: true, scopes: 'email profile' },
});
```

#### 2. Método `handleGoogleCallback()` (línea ~2020-2050)

**ANTES:**
```typescript
if (accessToken) {
  const { data, error } = await this.supabase.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken || accessToken,
  });
  sessionResponse = data;
  sessionError = error as Error | null;
} else if (code) {
  const { data, error } = await this.supabase.auth.exchangeCodeForSession(code);
  sessionResponse = data;
  sessionError = error as Error | null;
}
```

**DESPUÉS:**
```typescript
// CRITICAL FIX: Determine which Supabase client to use BEFORE session exchange
let clientIdForAuth: string | undefined = clientIdHint;

if (state && !clientIdForAuth) {
  try {
    const payload = await this.parseOAuthStateToken(state, clientIdHint);
    clientIdForAuth = payload.clientId;
  } catch (err) {
    this.logger.warn('[handleGoogleCallback] Could not parse state for client detection', err);
  }
}

// Use Admin DB for platform/wizard, Backend DB for tenant stores
const authClient = this.getInternalClient(clientIdForAuth);

if (accessToken) {
  const { data, error } = await authClient.auth.setSession({
    access_token: accessToken,
    refresh_token: refreshToken || accessToken,
  });
  sessionResponse = data;
  sessionError = error as Error | null;
} else if (code) {
  const { data, error } = await authClient.auth.exchangeCodeForSession(code);
  sessionResponse = data;
  sessionError = error as Error | null;
}
```

### Método Helper Utilizado

```typescript
private getInternalClient(clientId?: string | null): SupabaseClient {
  return this.isPlatformClientId(clientId)
    ? this.adminDbClient  // Admin DB para wizard/platform
    : this.adminClient;   // Backend DB para tenant stores
}

private isPlatformClientId(clientId?: string | null): boolean {
  return (clientId ?? '').trim().toLowerCase() === 'platform';
}
```

---

## Arquitectura de Clientes Supabase en Backend

El backend inyecta **tres clientes** Supabase en `AuthService`:

```typescript
constructor(
  @Inject('SUPABASE_CLIENT') private readonly supabase: SupabaseClient,
  @Inject('SUPABASE_ADMIN_CLIENT') private readonly adminClient: SupabaseClient,
  @Inject('SUPABASE_ADMIN_DB_CLIENT') private readonly adminDbClient: SupabaseClient,
  private readonly corsRegistry: CorsRegistryService,
) {}
```

- `supabase` (SUPABASE_CLIENT): Backend DB para operaciones de tenant stores
- `adminClient` (SUPABASE_ADMIN_CLIENT): Admin DB para operaciones admin (confuso, revisar nomenclatura)
- `adminDbClient` (SUPABASE_ADMIN_DB_CLIENT): Admin DB específico para platform

El método `getInternalClient()` **abstrae esta complejidad** y devuelve el cliente correcto basándose en si el `clientId === "platform"`.

---

## Testing

### Pasos de Validación Manual

1. **Limpiar sesión local** (modo incógnito o limpiar localStorage):
   ```js
   localStorage.clear();
   sessionStorage.clear();
   ```

2. **Acceder al wizard**:
   ```
   https://novavision-admin.netlify.app/wizard
   ```

3. **Hacer clic en "Crear Cuenta con Google"**

4. **Verificar en consola del navegador**:
   - No debe haber error `403 Forbidden` en `/auth/v1/user`
   - No debe haber error `invalid JWT: signature is invalid`
   - JWT issuer debe ser: `https://erbfzlsznqsmwmjugspo.supabase.co/auth/v1` (Admin DB)

5. **Verificar en DevTools > Application > Local Storage**:
   ```
   nv_admin_auth_platform → debe contener JWT válido de Admin DB
   ```

6. **Verificar que NO hay redirect loop**:
   - Usuario debe permanecer en wizard después de login
   - Progreso debe recuperarse correctamente
   - No debe redirigir a wizard si ya aceptó términos

### Logs de Backend a Revisar

```bash
# Railway logs o logs locales
[startGoogleOAuth] redirect { clientId: 'platform', ... }
[handleGoogleCallback] Could not parse state for client detection (esperado si viene accessToken directo)
```

### Casos de Prueba

| Usuario | Client ID | DB Esperada | Issuer JWT Esperado |
|---------|-----------|-------------|---------------------|
| Wizard nuevo | `"platform"` | Admin DB | erbfzlsznqsmwmjugspo |
| Wizard existente | `"platform"` | Admin DB | erbfzlsznqsmwmjugspo |
| Tienda tenant | UUID real | Backend DB | ulndkhijxtxvpmbbfrgp |
| Super Admin | `"platform"` o UUID | Admin DB | erbfzlsznqsmwmjugspo |

---

## Riesgos y Mitigación

### Riesgos

1. **Usuarios con sesión activa del Backend DB**: 
   - Tendrán que hacer logout/login nuevamente
   - Mitigación: Frontend ya detecta JWT inválido y redirige a login

2. **Sesiones OAuth en progreso durante deploy**:
   - Podrían fallar si el callback llega después del deploy
   - Mitigación: Usuarios verán error y reiniciarán flujo (idempotente)

3. **Super admin cambiando de tenant**:
   - Depende de que `clientIdHint` se pase correctamente
   - Mitigación: Ya funciona (no se modificó lógica de super admin)

### Validación de Rollback

Si hay problemas críticos, revertir commits:
```bash
git revert <commit-hash>
git push
```

Backend en Railway auto-deployará versión anterior.

---

## Lecciones Aprendidas

1. **OAuth debe usar el mismo Supabase project que valida**:
   - JWT signing secret es único por proyecto Supabase
   - No se puede "cross-validate" JWT entre proyectos

2. **Dual-database architecture requiere routing explícito**:
   - Cada operación de auth debe saber qué DB usar
   - Métodos helper como `getInternalClient()` son críticos

3. **Frontend fix solo no es suficiente**:
   - Cambiar prioridad de clientes Supabase en frontend ayuda
   - Pero si backend genera JWT incorrecto, frontend no puede arreglarlo

4. **Testing de incógnito es crítico**:
   - Descarta problemas de cache/sesión local
   - Prueba el flujo completo "end-to-end"

---

## Próximos Pasos

1. ✅ **Deploy a Railway** (auto-deploy desde main)
2. ⚠️ **Validar en producción** con usuario de prueba
3. 📝 **Documentar arquitectura de dual-DB** en `docs/AUTH_ARCHITECTURE.md`
4. 🔍 **Revisar nomenclatura de clientes Supabase** (adminClient vs adminDbClient confuso)
5. 🧪 **Agregar tests unitarios** para `getInternalClient()` routing logic
6. 📊 **Monitorear logs de Railway** para errores de OAuth en las próximas 24h

---

## Referencias

- Usuario afectado: kaddocpendragon@gmail.com (ID: 935e7be8-4cdd-44b0-890b-c7bcfc8ca3d0)
- Frontend fix previo: `apps/admin/src/services/supabase/index.js` línea 88
- Migration script: `apps/admin/docs/sql/migrate-user-backend-to-admin.sql`
- Documentación OAuth: `apps/admin/docs/AUTH_FLOW.md`
- Supabase Admin DB: https://erbfzlsznqsmwmjugspo.supabase.co
- Supabase Backend DB: https://ulndkhijxtxvpmbbfrgp.supabase.co

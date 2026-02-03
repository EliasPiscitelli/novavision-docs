# Fix Definitivo: Redirects de Onboarding en Producción (V2)

- **Autor:** agente-copilot
- **Fecha:** 2026-02-01 (documento actualizado; fecha original 2025-01-29)
- **Rama:** feature/onboarding-redirect-fix-v2
- **Aplica a:** apps/admin (novavision.lat)

---

## Resumen Ejecutivo

Se implementaron 6 mejoras críticas para resolver definitivamente los problemas de redirects de onboarding en producción:

1. **BuildStamp** - Componente de diagnóstico para confirmar qué build está desplegado
2. **Normalización de Estados** - Soporte para 20+ alias de estados (submitted, in_review, etc.)
3. **Decodificación robusta de `next`** - Manejo de parámetros double-encoded (%252F)
4. **Prevención de double-redirect** - Sistema de claim para evitar race conditions
5. **Confirmación de app** - Verificado que `apps/admin` sirve `novavision.lat`
6. **Logs estructurados** - Sistema de debugging con historial persistente

---

## Archivos Modificados

### Nuevos Archivos

| Archivo | Propósito |
|---------|-----------|
| `src/utils/onboarding/statusNormalizer.ts` | Normaliza 20+ alias de estado a 6 estados canónicos |
| `src/utils/onboarding/decodeReturnPath.ts` | Decodifica parámetros `next` double-encoded |
| `src/utils/onboarding/redirectLogger.ts` | Sistema de logging estructurado con historial |
| `src/utils/onboarding/redirectGuard.ts` | Sistema de claim para prevenir double-redirect + `clearClaimOnArrival()` |
| `src/utils/onboarding/useClaimCleanup.ts` | Hook React para limpiar claims automáticamente al llegar a destino |
| `src/components/BuildStamp.tsx` | Componente de diagnóstico (solo DEV o ?debug=build) |

### Archivos Actualizados

| Archivo | Cambios |
|---------|---------|
| `src/utils/onboarding/index.ts` | Barrel exports para todos los módulos V2 (incluye useClaimCleanup) |
| `src/utils/onboarding/onboardingRouteResolver.ts` | Integración con V2: normalización, logging, source tracking |
| `src/context/AuthContext.jsx` | Usa claim system y decodificación robusta |
| `src/pages/OAuthCallback/index.jsx` | Usa claim system y decodificación robusta |
| `src/App.jsx` | Agrega BuildStamp + RouteChangeHandler (claim cleanup) |
| `vite.config.js` | Inyecta VITE_COMMIT_HASH y VITE_BUILD_TIMESTAMP |

---

## Detalle Técnico

### 1. Normalización de Estados (`statusNormalizer.ts`)

**Problema:** El backend podía enviar diferentes variantes del mismo estado lógico:
- `in_review`, `IN_REVIEW`, `submitted`, `pending_review`, `awaiting_approval`

**Solución:** Mapeo exhaustivo a 6 estados canónicos:

```typescript
const STATUS_ALIASES = {
  // IN_REVIEW covers all review-pending states
  'submitted': 'IN_REVIEW',
  'in_review': 'IN_REVIEW',
  'pending_review': 'IN_REVIEW',
  'pending_approval': 'IN_REVIEW',
  'awaiting_review': 'IN_REVIEW',
  // ... 20+ aliases total
};
```

**Fix Crítico:** Estado `UNKNOWN` ahora redirige a `/onboarding/status` (NO a `/builder` como antes).

### 2. Decodificación Robusta (`decodeReturnPath.ts`)

**Problema:** Email tracking services (MailerLite, etc.) double-encode los links:
- Original: `/complete`
- En email: `%2Fcomplete`  
- Después de tracking: `%252Fcomplete`

**Solución:** Aplicar `decodeURIComponent` hasta que no cambie (máx 2x):

```typescript
export function getDecodedPath(raw: string | null): string | null {
  if (!raw) return null;
  let decoded = raw;
  for (let i = 0; i < 2; i++) {
    const next = decodeURIComponent(decoded);
    if (next === decoded) break;
    decoded = next;
  }
  return isValidReturnPath(decoded) ? decoded : null;
}
```

### 3. Sistema de Claim (`redirectGuard.ts`)

**Problema:** Múltiples componentes (AuthContext, OAuthCallback) intentaban hacer redirect simultáneamente, causando race conditions.

**Solución:** Sistema de claim con TTL de 10 segundos:

```typescript
// OAuthCallback claims the redirect
claimRedirect('OAuthCallback', '/onboarding/status', userId);
// AuthContext checks before redirecting
if (hasActiveRedirectClaim()) return; // Don't override
```

### 4. BuildStamp (`BuildStamp.tsx`)

**Propósito:** Confirmar qué build está corriendo en producción.

**Visibilidad:**
- Siempre visible en `import.meta.env.DEV`
- Visible con `?debug=build` en URL
- Visible si `sessionStorage.nvBuildStampVisible === 'true'`

**Muestra:**
- App name (`admin`)
- Commit hash (short)
- Build timestamp
- Environment (development/production)

### 5. Logging Estructurado (`redirectLogger.ts`)

**Formato de logs:**
```
[onboarding-redirect] source=AuthContext normalized_status=IN_REVIEW → /onboarding/status
```

**Persistencia:** Últimos 50 eventos en `sessionStorage.__nvRedirectLog`

**Debug en consola:**
```javascript
window.__nvRedirectDebug(); // Ver historial
```

---

## Criterios de Aceptación (Verificados)

| Criterio | Estado |
|----------|--------|
| Usuario con `IN_REVIEW` nunca termina en `/builder` | ✅ |
| Parámetro `next` double-encoded termina en `/complete` | ✅ |
| Estado no reconocido va a `/onboarding/status` (no builder) | ✅ |
| BuildStamp visible en DEV o con `?debug=build` | ✅ |
| Logs con prefijo `[onboarding-redirect]` | ✅ |
| Sin double-redirects (claim system) | ✅ |

---

## Cómo Probar

### 1. Verificar BuildStamp
```
1. Ir a https://novavision.lat?debug=build
2. Ver stamp en esquina inferior izquierda
3. Confirmar que commit hash coincide con deploy
```

### 2. Verificar Normalización
```
1. Login con usuario cuyo status sea "submitted" o "pending_review"
2. Verificar que termina en /onboarding/status
3. En consola: window.__nvRedirectDebug()
4. Confirmar log muestra: normalized_status=IN_REVIEW → /onboarding/status
```

### 3. Verificar Double-encode
```
1. Simular link de email con next=%252Fcomplete
2. Completar OAuth flow
3. Verificar que termina en /complete
```

### 4. Debug en Producción
```javascript
// En consola del navegador:
window.__nvRedirectDebug(); // Ver historial de redirects
sessionStorage.__nvRedirectLog; // Ver JSON crudo
```

---

## Riesgos y Mitigación

| Riesgo | Mitigación |
|--------|------------|
| BuildStamp visible en prod por error | Solo visible con ?debug=build o flag explícito |
| Claim system causa timeout | TTL de 10s, auto-limpieza en page load |
| Normalización pierde estados nuevos | Fallback a UNKNOWN → /onboarding/status (safe) |

---

## Actualización 2026-02-01: Claim Cleanup Automático

### Problema Detectado
El sistema de claims tiene un TTL de 10 segundos. Si un usuario llegaba a su destino pero el claim no se liberaba explícitamente, durante esos 10s otras navegaciones podían ser bloqueadas incorrectamente.

### Solución Implementada

1. **Nueva función `clearClaimOnArrival(currentPath)`** en `redirectGuard.ts`:
   - Compara la ruta actual con el destino del claim
   - Si coinciden, libera el claim inmediatamente
   - Normaliza paths (quita trailing slashes) para comparación robusta

2. **Nuevo hook `useClaimCleanup()`** en `useClaimCleanup.ts`:
   - Se ejecuta en cada cambio de ruta
   - Llama a `clearClaimOnArrival(location.pathname)`

3. **Integración en `App.jsx`**:
   - Nuevo componente `RouteChangeHandler` que usa el hook
   - Se monta dentro de `<Router>` para acceder a `useLocation`

### Verificación
- Cuando un usuario llega a `/hub`, `/builder`, `/complete`, etc., el claim se libera inmediatamente
- Las navegaciones subsecuentes no quedan bloqueadas por el TTL

---

## Comandos de Verificación

```bash
# Typecheck
npm run typecheck -w apps/admin

# Lint
npm run lint -w apps/admin

# Build local
npm run build -w apps/admin
```

---

## Notas de Seguridad

- `decodeReturnPath` rechaza URLs externas, protocol-relative, y path traversal
- BuildStamp NO expone información sensible (solo commit hash y timestamp)
- Logs en sessionStorage se limpian al cerrar sesión del navegador

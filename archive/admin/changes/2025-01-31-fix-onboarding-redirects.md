# Cambio: Fix Inconsistent Onboarding Redirects

- **Autor**: Copilot Agent
- **Fecha**: 2025-01-31
- **Rama**: feature/fix-onboarding-redirects
- **Ticket**: N/A (solicitud directa)

---

## Resumen

Se implementó un sistema centralizado de resolución de rutas para onboarding que corrige:

1. **Problema Principal**: Usuarios con estado "submitted" (En Revisión) podían acceder a `/builder` cuando deberían ir a `/onboarding/status`.

2. **Problema Secundario**: El parámetro `next=/complete` del email de "Ajustes Requeridos" no se respetaba después del login.

---

## Archivos Modificados

### Nuevos Archivos Creados

| Archivo | Propósito |
|---------|-----------|
| [src/utils/onboarding/onboardingRoutesMap.ts](apps/admin/src/utils/onboarding/onboardingRoutesMap.ts) | Single source of truth para mapeo estado→ruta |
| [src/utils/onboarding/onboardingRouteResolver.ts](apps/admin/src/utils/onboarding/onboardingRouteResolver.ts) | Resolver centralizado con sanitización de `next` param |
| [src/utils/onboarding/useOnboardingGuard.ts](apps/admin/src/utils/onboarding/useOnboardingGuard.ts) | Hook para aplicar guardias en componentes |
| [src/utils/onboarding/index.ts](apps/admin/src/utils/onboarding/index.ts) | Barrel export del módulo |
| [src/utils/OnboardingGuardedRoute.jsx](apps/admin/src/utils/OnboardingGuardedRoute.jsx) | Route wrapper para React Router |
| [src/utils/onboarding/__tests__/onboardingRouteResolver.spec.ts](apps/admin/src/utils/onboarding/__tests__/onboardingRouteResolver.spec.ts) | Tests unitarios |

### Archivos Modificados

| Archivo | Cambio |
|---------|--------|
| [src/utils/resolvePostLoginRoute.js](apps/admin/src/utils/resolvePostLoginRoute.js) | Convertido a wrapper de compatibilidad que delega al nuevo resolver |
| [src/context/AuthContext.jsx](apps/admin/src/context/AuthContext.jsx) | Import actualizado para usar nuevo resolver |
| [src/pages/ClientLogin/index.jsx](apps/admin/src/pages/ClientLogin/index.jsx) | Usa resolver centralizado + sanitizeReturnPath |
| [src/pages/OAuthCallback/index.jsx](apps/admin/src/pages/OAuthCallback/index.jsx) | Usa resolver centralizado |
| [src/components/Header/index.jsx](apps/admin/src/components/Header/index.jsx) | Botón "Mi Cuenta" usa `getCanonicalRoute()` |
| [src/App.jsx](apps/admin/src/App.jsx) | Rutas de onboarding ahora usan `OnboardingGuardedRoute` |

---

## Arquitectura de la Solución

### Mapeo de Estados → Rutas

```typescript
// Definición en onboardingRoutesMap.ts
const ONBOARDING_STATUS_TO_ROUTE = {
  unknown: ROUTES.BUILDER,
  not_started: ROUTES.BUILDER,
  in_progress: ROUTES.BUILDER,
  submitted: ROUTES.ONBOARDING_STATUS,  // ← FIX CRÍTICO
  completed: ROUTES.HUB,
  live: ROUTES.HUB,
};
```

### Paths Permitidos por Estado

```typescript
const ALLOWED_PATHS_BY_STATUS = {
  unknown: ['/builder', '/onboarding/status'],
  not_started: ['/builder', '/onboarding/status'],
  in_progress: ['/builder', '/onboarding/status', '/complete'],
  submitted: ['/onboarding/status', '/complete'],  // ← /builder EXCLUIDO
  completed: ['/hub', '/onboarding/status', '/complete', '/client/'],
  live: ['/hub', '/onboarding/status', '/complete', '/client/'],
};
```

### Sanitización de `next` Parameter

```typescript
// Se rechazan:
// - URLs externas (http://, https://, //)
// - Caracteres peligrosos (.., \, %2f%2f)
// - Paths de auth (/login, /oauth/callback, /auth-callback)
// - Paths no whitelisteados (en modo estricto)
```

---

## Flujos Corregidos

### 1. Usuario "En Revisión" hace click en "Mi Cuenta"

**Antes**: Iba a `/builder` (podía modificar datos ya enviados)  
**Después**: Va a `/onboarding/status` (solo puede ver estado)

### 2. Usuario recibe email "Ajustes Requeridos" con link `?next=/complete`

**Antes**: Ignoraba el `next` param, iba a `/builder`  
**Después**: 
- Hace login
- Se procesa `next=/complete`
- Se valida que `/complete` está permitido para su estado (`submitted`)
- Navega a `/complete` correctamente

### 3. Usuario intenta acceder directamente a `/builder` estando "submitted"

**Antes**: Accedía sin problemas  
**Después**: `OnboardingGuardedRoute` detecta estado y redirige a `/onboarding/status`

---

## Cómo Probar

### Test Case 1: Usuario "En Revisión" → Mi Cuenta

1. Login con usuario que tiene `onboarding_status = 'submitted'`
2. Click en "Mi Cuenta" en el Header
3. **Esperado**: Navega a `/onboarding/status`

### Test Case 2: Deep Link desde Email

1. Abrir URL: `/login?next=%2Fcomplete`
2. Completar login con OAuth
3. **Esperado**: Navega a `/complete` (no a `/builder`)

### Test Case 3: Acceso Directo Bloqueado

1. Login con usuario `submitted`
2. Navegar manualmente a `/builder`
3. **Esperado**: Redirige automáticamente a `/onboarding/status`

### Test Case 4: Loop Prevention

1. Usuario `submitted` está en `/onboarding/status`
2. No debe haber redirecciones infinitas
3. **Esperado**: Se queda en `/onboarding/status` sin loops

---

## Comandos para Validar

```bash
# Correr tests unitarios
cd apps/admin
npm test -- --testPathPattern=onboardingRouteResolver

# Verificar tipos
npm run typecheck

# Lint
npm run lint
```

---

## Notas de Seguridad

- ✅ Sanitización estricta del parámetro `next` (previene open redirect)
- ✅ Whitelist de paths permitidos por estado
- ✅ Validación doble: en login page + en route guard
- ✅ Logs de debugging solo en desarrollo

---

## Riesgos y Rollback

**Riesgo**: Si el backend retorna un `onboarding_status` incorrecto, el usuario puede quedar en un estado inconsistente.

**Mitigación**: El resolver usa `unknown` como fallback que envía a `/builder`, permitiendo al usuario reiniciar el flujo.

**Rollback**: Revertir los cambios en `resolvePostLoginRoute.js` al código original (disponible en git history).

---

## TODO / Mejoras Futuras

- [ ] Migrar imports directos a `@/utils/onboarding` (path alias)
- [ ] Agregar telemetría de redirecciones para detectar anomalías
- [ ] Implementar "changes_requested" como estado separado de "submitted"
- [ ] Agregar E2E tests con Playwright

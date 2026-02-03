# Cambio: respetar accountStatus en redirecciones de onboarding

- Autor: agente-copilot
- Fecha: 2026-02-02
- Rama: feature/automatic-multiclient-onboarding
- Archivos: src/context/AuthContext.jsx, src/pages/ClientCompletionDashboard/index.tsx, src/pages/ClientLogin/index.jsx, src/pages/OAuthCallback/index.jsx, src/utils/onboarding/__tests__/onboardingRouteResolver.spec.ts, src/utils/onboarding/onboardingRouteResolver.ts, src/utils/onboarding/onboardingRoutesMap.ts, src/utils/resolvePostLoginRoute.js

## Resumen de cambios
- Se incorporó `accountStatus` en el resolver post-login y se respeta el override de cuenta.
- Se agregó override para `account_status=incomplete` hacia /complete.
- Se mejoró la UI del dashboard de completado (layout, colores, badges y tarjetas).
- Se removió el banner del checklist de completado (solo se cargará post-aprobación).
- `ClientLogin` usa return path decodificado y evita pisar redirects con `redirectGuard`.
- Se actualizó OAuth callback y AuthContext para pasar `accountStatus`.
- Se agregó test de `changes_requested` → /complete.

## Por qué
Evitar que usuarios con `accountStatus=changes_requested` sean redirigidos a /onboarding/status cuando el correo solicita completar tareas en /complete, y evitar que `ClientLogin` sobrescriba el redirect legítimo.

## Cómo probar / comandos ejecutados
- npm run lint
- npm run build
- npm run typecheck

## Notas de seguridad
Sin impacto en credenciales ni permisos; solo ajuste de enrutamiento en frontend.

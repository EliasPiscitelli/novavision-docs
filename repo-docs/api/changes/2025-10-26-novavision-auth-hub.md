# NovaVision – Refactor multicliente + pagos + imágenes
**Fecha:** 2025-10-26  
**Rama:** chore/nv-refactor/20251026-multiclient-hub  
**Ámbitos:** Backend / Auth / DB / Hub

## 1) Resumen
Centralizamos el flujo de autenticación en el hub `novavision.lat`, implementando protección de estado con nonces firmados y preparando la base para callbacks seguros de Google OAuth.

## 2) Cambios aplicados
### Backend
- Nuevos endpoints `POST /auth/google/start` y `POST /auth/google/callback` que controlan el Option B (server side exchange) para Google OAuth.
- Servicio de auth genera tokens de estado firmados (`AUTH_STATE_SECRET`) y valida el retorno, forzando redirección al tenant correcto.
- Persistencia y revocación de nonces en Supabase (`oauth_state_nonces`), limpieza de expirados y verificación `timingSafeEqual`.
- Reutilizamos `handleSessionAndUser` para el login Google y reforzamos membresía de super-admin por tienda.
### Frontend / Hub
- Ajustes pendientes: hub debe consumir el nuevo flujo (`/auth/google/start` → redirigir a Supabase → enviar `state`+`code` al backend); Web/Admin deben respetar los nuevos redirects.
### DB/RLS
- Tabla `oauth_state_nonces` con índices por `client_id` y `expires_at`, RLS restringida a `service_role`.
### Storage/CDN
- Sin cambios.

## 3) Migraciones
- Archivos: `backend/migrations/20251026_create_oauth_state_nonces.sql`
- Rollback: eliminar tabla `oauth_state_nonces` y sus índices/políticas.

## 4) Post-deploy
- Variables nuevas: `PUBLIC_BASE_URL`, `AUTH_STATE_SECRET` (backend).  
- Ejecutar `npm run migrate` en el backend.  
- Configurar el hub para reenviar callbacks a `/auth/google/callback` con `state` y `code`.

## 5) Verificación
- [ ] `POST /auth/google/start` devuelve URL de Google con `redirectTo` del hub.  
- [ ] Callback con `state` válido crea sesión y redirige al tenant correcto.  
- [ ] Nonce reutilizado => `STATE_ALREADY_USED`.  
- [ ] Nonce expirado => `STATE_EXPIRED`.  
- [ ] Super admin mantiene acceso cross-tenant.

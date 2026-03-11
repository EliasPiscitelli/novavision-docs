# NovaVision – Auth multicliente con memberships por tienda
**Fecha:** 2025-11-08  
**Rama:** multiclient  
**Ámbitos:** Backend / Auth / Supabase

## 1) Resumen
El middleware de autenticación ahora permite que un usuario final autenticado en Supabase opere sobre varias tiendas sin necesitar cuentas separadas. Se normalizó el uso de `x-client-id` para seleccionar la tienda activa y se agregó una consulta a la tabla `users` para cargar todas las membresías asociadas.

## 2) Flujo actualizado
1. El usuario se autentica una sola vez en el proyecto multicliente de Supabase (`auth.users`). La sesión devuelve un JWT válido para `multiclient` o, si corresponde, para el proyecto `admin`.
2. Durante el alta, se crea al menos un registro en la tabla `public.users` por cada tienda donde tiene permisos. Cada registro comparte el `id` de Supabase pero usa un `client_id` distinto.
3. El `client_id` principal se sigue guardando en `user_metadata` cuando existe un único tenant. Si el header `x-client-id` llega vacío, se usa este valor como fallback.
4. El middleware (`AuthMiddleware.use`) valida el token contra los proyectos `multiclient` y `admin`. Si no es `super_admin`, construye un set de tenants permitidos:
   - agrega el `client_id` de metadata (si existe);
   - consulta `public.users` para traer todos los `client_id` asociados al `user.id` (función `fetchUserClientIds`).
5. Si el request trae `x-client-id`, se valida que pertenezca al set permitido. Si no es válido se registra en logs y se usa el primer tenant disponible como predeterminado.
6. El tenant resuelto se reinyecta en `req.headers['x-client-id']` y se construye un `SupabaseClient` por request vía `makeRequestSupabaseClient`, garantizando que las políticas RLS utilicen el tenant correcto.
7. Los `super_admin` mantienen la posibilidad de operar en cualquier tenant pasando `x-client-id` explícito. En el proyecto `admin` se respeta el `client_id` del header o el de metadata sin consultar memberships, y si no hay `client_id` se permite continuar para endpoints globales (p. ej. métricas).

## 3) Consideraciones operativas
- El onboarding debe asegurar que, al asignar un usuario a una tienda adicional, se inserte un nuevo registro en `public.users` con el mismo `id` pero `client_id` distinto.
- Cuando se deshabilita el acceso a una tienda, hay que eliminar o desactivar el registro correspondiente para que deje de aparecer en `fetchUserClientIds`.
- Las llamadas del front deben enviar `x-client-id` al cambiar de tienda; si no se envía, el backend usará el primer tenant disponible.
- El `SUPABASE_SERVICE_ROLE_KEY` sigue siendo obligatorio para que el middleware pueda consultar memberships adicionales.

## 4) Impacto
- No se realizaron migraciones adicionales: la tabla `public.users` ya soportaba múltiples registros por `id`.
- Los tests de integración de auth deben validar tanto el caso de usuario con una sola tienda como el de múltiples tiendas, asegurando que la selección por header respeta RLS.
- Se debe actualizar la documentación funcional del hub para reflejar que los usuarios comparten credenciales pero tienen memberships por tienda.

## 5) Pendientes
- Agregar pruebas E2E que cambien el `x-client-id` desde el panel admin y verifiquen que los datos retornados corresponden al tenant esperado.
- Documentar en el onboarding del hub cómo sincronizar memberships cuando se crea una tienda nueva para un usuario existente.

# NovaVision – Uso y costos inicial
**Fecha:** 2025-11-07  
**Rama:** multiclient  
**Ámbitos:** Backend / Frontend / DB

## 1) Resumen
- Se instrumenta metering por `client_id` guardando cada request y generando agregados diarios.
- Se expone una vista de administración "Uso y costos" para monitorear requests, errores y storage por cliente.
- Se incorporan tablas de precios/extra costos para futuros cálculos de márgenes.

## 2) Cambios aplicados
### Backend
- Nuevo módulo `metrics` con interceptor global (`usage_event`) y cron nocturno que consolida en `usage_daily`.
- El interceptor ahora escribe mediante un cliente dedicado `SUPABASE_METERING_CLIENT` que apunta a la BD Admin.
- El cron sincroniza órdenes desde la multicliente hacia `orders_bridge` y luego ejecuta los RPC `usage_api_daily` + `orders_daily` sobre la BD Admin.

### Frontend
- Pantalla `Dashboard > Uso y costos` con cards, tabla por cliente y manejo de estados (loading/error/vacío).

### DB/RLS
- Tablas `usage_event`, `usage_daily`, `metering_prices`, `client_extra_costs` con índices y policies RLS (admins + service_role).

## 3) Migraciones
- `backend/migrations/20251107_usage_metering.sql`

## 4) Post-deploy
- Ejecutar migraciones (`npm run migrate`).
- Configurar en Railway las variables `SUPABASE_ADMIN_URL` y `SUPABASE_ADMIN_SERVICE_ROLE_KEY` apuntando a la BD Admin (además de las existentes para la multicliente).
- Validar que `SUPABASE_SERVICE_ROLE_KEY` siga apuntando a la multicliente (se usa para leer órdenes).
- Verificar en logs que el cron sincroniza `orders_bridge` y ejecuta los RPC a las 03:15 ART.

## 5) Verificación
- [ ] Requests crean filas en `usage_event`.
- [ ] Cron genera registros en `usage_daily`.
- [ ] Vista admin carga datos consolidados sin errores.

# Rate Limiting & Protección de Rutas

Fecha: 2025-08-15
Implementado en rama: `multiclient`

## Objetivo
Mitigar abuso (flooding, scraping, brute force) en rutas sensibles sin afectar flujos transaccionales de Mercado Pago (notificaciones y redirecciones).

## Librería
Se utilizó [`rate-limiter-flexible`](https://github.com/animir/node-rate-limiter-flexible) en memoria para la primera iteración.

> Nota: Para producción a escala se recomienda backend persistente (Redis / Postgres). In-memory se reinicia con el proceso.

## Implementación
Archivo: `src/common/middleware/rate-limit.middleware.ts`

### Configuraciones
| Tipo | Límite | Ventana |
|------|--------|---------|
| Auth | 10 req | 60 s |
| Genérico | 60 req | 60 s |
| Admin | 120 req | 300 s |

Selección automática según:
- Rutas que comienzan con `/auth` → `authLimiter`.
- Rutas `/admin*` o rol `admin/super_admin` → `adminLimiter`.
- Resto → `genericLimiter`.

### Exclusiones (no se limita)
Se excluyen rutas de Mercado Pago para permitir reintentos legítimos:
- `/mercadopago/notification`
- `/mercadopago/success`
- `/mercadopago/failure`
- `/mercadopago/pending`

Estas rutas deben tener protecciones adicionales (ver sección Futuras Mejoras).

### Integración Global
En `main.ts` se añadió:
```ts
import { rateLimit } from '@/common/middleware/rate-limit.middleware';
// ...
app.use(rateLimit());
```

### Respuesta ante límite excedido
`HTTP 429` con body JSON:
```json
{ "code": "RATE_LIMITED", "message": "Too many requests" }
```
Para auth:
```json
{ "code": "RATE_LIMITED", "message": "Too many auth requests" }
```

## Uso Granular Opcional
Se expone también `authRateLimit()` para aplicar específicamente a un router/controlador de autenticación si se requiere:
```ts
// Ejemplo en un módulo de auth
app.use('/auth/login', authRateLimit());
```
(Currentemente no aplicado; solo ejemplo.)

## Extender / Migrar a Redis
Cuando se despliegue multi-instancia Railway / contenedores:
1. Instalar cliente Redis.
2. Reemplazar `RateLimiterMemory` por `RateLimiterRedis`.
3. Configurar TTL y cluster aware.

Ejemplo:
```ts
import { RateLimiterRedis } from 'rate-limiter-flexible';
const redisClient = new Redis(process.env.REDIS_URL);
const authLimiter = new RateLimiterRedis({ storeClient: redisClient, points: 10, duration: 60 });
```

## Logging / Observabilidad (Pendiente)
Agregar hook para loggear eventos de bloqueo:
```ts
catch (rej) {
  logger.warn({ event: 'rate_limited', ip, path: req.path, ...rej });
  res.status(429).json(...)
}
```

## Futuras Mejoras Recomendadas
- Verificación de firma + allowlist IP en `/mercadopago/notification`.
- Tokens bucket diferenciados por `client_id` además de IP (multi-tenant equidad).
- Cabecera `Retry-After` en respuestas 429.
- Métricas Prometheus: contadores de bloqueos por ruta.
- Circuit breaker ante picos globales.

## Checklist de Implementación
- [x] Dependencia agregada en `package.json`.
- [x] Middleware creado y versionado.
- [x] Integrado globalmente en `main.ts`.
- [x] Exclusiones de rutas Mercado Pago.
- [x] Documentación inicial (este archivo).
- [ ] Logging estructurado de eventos 429.
- [ ] Test e2e simulando saturación (pendiente).
- [ ] Migración a store persistente para HA.

## Riesgos
- In-memory reset → contador vuelve a cero tras restart.
- Posible bypass si se accede vía múltiples IP (botnet).
- Admin limiter podría ser todavía bajo en operaciones batch; monitorear.

## Cómo Ajustar Límites
Editar valores en `rate-limit.middleware.ts`:
```ts
const authLimiter = new RateLimiterMemory({ points: 10, duration: 60 });
```
`points`: cantidad de solicitudes.
`duration`: ventana en segundos.

---
Documento generado automáticamente.

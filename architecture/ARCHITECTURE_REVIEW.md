# Revisión Arquitectura Backend NovaVision (Multicliente)

Fecha: 2025-08-15
Rama analizada: `multiclient`

## 1. Alcance de la revisión
Se evaluaron aspectos de multi‑tenant (aislamiento por `client_id`), seguridad, estructura de servicios, manejo de pagos (Mercado Pago), patrón de acceso a Supabase, almacenamiento y consistencia general. Archivos inspeccionados: `main.ts`, `auth/auth.middleware.ts`, `supabase.module.ts`, services y controllers de `products`, `orders`, `cart`, `banners`, `social-links`, y utilitario `client-id.helper.ts`.

## 2. Fortalezas observadas
- Middleware de autenticación calcula `resolvedClientId` y soporta lógica especial para `super_admin`.
- Consistencia en filtrado explícito por `client_id` en la mayoría de los services (products, orders, cart, banners, categories, social-links).
- Uso de helper centralizado `getClientId(req)` para reducir repetición y errores.
- Paginación implementada con `range()` en productos y órdenes filtradas (`getFilteredOrders`).
- Validaciones de stock y cantidades antes de actualizar carrito/pedidos.
- Separación de clientes Supabase: `SUPABASE_CLIENT` (anon) y `SUPABASE_ADMIN_CLIENT` (service role) disponible para inyección.
- CORS dinámico validando orígenes contra tabla `cors_origins` + lista blanca local, minimizando exposición.
- Protección básica de actualización de estado de órdenes solo para roles admin (consulta a tabla `users`).
- Subida de imágenes con generación de nombres únicos (`uuid`) y limpieza selectiva en banners.

## 3. Riesgos y brechas detectadas
| Área | Observación | Riesgo | Severidad |
|------|-------------|--------|----------|
| Autenticación / Contexto | `AuthMiddleware` usa siempre `SERVICE_ROLE_KEY` para obtener usuario (`anon` variable pero con service role) — RLS puede quedar bypass si no hay políticas. | Posible acceso más amplio si RLS se relaja por error. | Alta |
| Multi‑tenant | No se observaron (en código revisado) validaciones de que un `super_admin` cambie tenant con auditoría; sólo permite header. | Acciones cross‑tenant sin trazabilidad. | Alta |
| Auditoría | No existe (en archivos vistos) tabla o service de audit log para: cambios críticos (productos, órdenes, cambio de tenant). | Dificultad para investigar incidentes. | Media |
| Paginación | En `ProductsService.getAllProducts` y búsqueda se usa paginación 1‑based (page default 1) mientras especificación recomendaba 0‑based consistente; `OrdersService.getFilteredOrders` ya es 0‑based. | Inconsistencia front/back; off-by-one en integraciones. | Media |
| Índices DB | Código asume consultas frecuentes por `client_id`, pero no se evidencia (aquí) creación de índices; riesgo si faltan: `products(client_id)`, `orders(client_id, created_at)`, etc. | Degradación de performance en escala. | Alta |
| Mercado Pago | Falta validación explícita de firma Webhook (`x-signature`) y endpoint idempotente (no hallado código de webhook en `mercadopago.service.ts` inspeccionado). | Riesgo de spoofing / doble procesamiento. | Alta |
| Pagos | Cálculo de impuestos y totales se hace en backend pero no se valida contra una orden preexistente (no se vio persistencia previa de `order.total` antes de preference). | Divergencia monto pagado vs registrado. | Media |
| Consistencia stock | `validateStock` lee cada producto individualmente (N queries). | Latencia / race conditions en alta concurrencia. | Media |
| Upload imágenes | No hay validación de tamaño/mimetype (solo se pasa `file.mimetype` al storage). | Riesgo de subir tipos no permitidos, posibles vectores XSS (SVG malicioso). | Media |
| Banners orden | Recalculo de `order` se hace cliente-side con consulta previa; condiciones de carrera si dos uploads simultáneos. | Orden inconsistente / duplicados. | Baja |
| Products update | No se eliminan archivos huérfanos cuando se retiran imágenes (solo `removeImage` explícito). | Acumulación de basura en storage. | Baja |
| Carrito | No hay bloqueo transaccional al confirmar pago (stock puede cambiar entre validate y checkout externo). | Overselling en escenarios de concurrencia. | Media |
| Errores | Muchos services lanzan `new Error()` genérico; no se usan HttpExceptions específicas (excepto en algunos). | Respuestas 500 no diferenciadas → mala DX y observabilidad. | Media |
| Observabilidad | Falta correlación `requestId` y logs estructurados JSON (logger usa strings). | Dificulta tracing y monitoreo. | Media |
| Seguridad CORS | Callback de CORS hace query a supabase por request (potencial overhead) sin caching. | Impacto performance bajo alta QPS. | Baja |
| Validación entrada | Falta DTOs + class-validator en varios endpoints (products upload, banners, social links). | Entrada no saneada, potenciales errores silenciosos. | Media |
| Roles | Validación de rol repetida manualmente (orders). No existe guard centralizado (RoleGuard) reutilizable. | Posible inconsistencia nuevos endpoints. | Media |
| Cliente Supabase | Servicios usan siempre `SUPABASE_ADMIN_CLIENT` (service role) incluso para operaciones de lectura del usuario autenticado. | Exceso de privilegios si RLS falla. | Alta |

## 4. Recomendaciones priorizadas
### Alta Prioridad
1. Implementar tabla `audit_logs` (id, client_id, user_id, action, entity, entity_id, diff JSONB, created_at) y util service para registrar eventos clave (login, cambio tenant, CRUD productos, update estado orden, creación preferencia MP, webhook pago).
2. Crear `TenantContextGuard` + `RolesGuard` unificados; extraer lógica de `assertAdmin` y reutilizar con metadata (`@Roles('admin','super_admin')`).
3. Introducir capa de Repositorio con métodos siempre obligando `clientId` (ej. `ProductRepository.findById(id, clientId)`), evitando filtrado manual repetitivo.
4. Implementar webhook Mercado Pago:
   - Verificación de firma (`x-signature` + secret compartido).
   - Idempotencia (tabla `payments` con constraint unique `provider_payment_id`).
   - Validar monto vs snapshot de orden; si mismatch → marcar `signature_valid = false`.
5. Ajustar paginación a convención única (preferible 0‑based). Añadir metadatos en respuesta: `{ items, page, limit, total }`.
6. Reducir privilegios: usar cliente per-request con JWT (sin service role) para operaciones que se beneficien de RLS, reservando `adminClient` solo para acciones internas.
7. Añadir validación de inputs con DTO + `class-validator` en endpoints sin tipado (productos excel, banners, social links) y retornar errores 400/422 consistentes.
8. Agregar validaciones de mimetype y tamaño máximo (ej: <= 2MB) para uploads; rechazar tipos no permitidos.
9. Índices críticos (si no existen):
   - `CREATE INDEX IF NOT EXISTS idx_products_client ON products(client_id);`
   - `CREATE INDEX IF NOT EXISTS idx_orders_client_created ON orders(client_id, created_at DESC);`
   - `CREATE INDEX IF NOT EXISTS idx_cart_items_user_client ON cart_items(user_id, client_id);`
   - `CREATE INDEX IF NOT EXISTS idx_product_categories_product ON product_categories(product_id);`
   - `CREATE INDEX IF NOT EXISTS idx_product_categories_category ON product_categories(category_id);`

### Media Prioridad
10. Caching ligero para CORS origins (in-memory TTL 5m) para evitar query por request.
11. Refactor `validateStock` para usar un solo `IN` y devolver mapa; aplicar `FOR UPDATE` en transacción simulada (o lock optimista) al confirmar pago.
12. Introducir `order_items` y persistir snapshot de precio antes de crear preferencia; luego comparar en webhook.
13. Incluir `requestId` (uuid v4) middleware y logger estructurado (JSON) con contexto (clientId, userId, role, path, latency).
14. Normalizar manejo de errores con filtros de excepción global (transformar `Error` genérico en 500, mapear validaciones a 400/422).
15. Implementar limpieza asíncrona de imágenes huérfanas (job diario): listar URLs en storage no referenciadas en `products.imageUrl`.
16. Soft delete (campo `deleted_at`) para productos/órdenes críticos si se requiere auditoría histórica.
17. Configurar rate limiting (Nest rate-limiter o gateway proxy) para endpoints sensibles (auth, pagos, webhook).

### Baja Prioridad / Mejora continua
18. Extraer configuración Helmet/CSP a módulo config central; permitir overrides por tenant (p.ej. dominios de analytics permitidos).
19. Implementar health endpoint (`/health`) con chequeos a Supabase y latencia.
20. Agregar pruebas e2e de aislamiento multi‑tenant (usuario A no puede acceder a recursos B) con datasets sintéticos.
21. Añadir feature flags por tenant (tabla `tenant_features`).
22. Versionar API (`/v1`) preparando futuros breaking changes.

## 5. Ejemplo de guard unificado (propuesta)
```ts
// roles.guard.ts
@Injectable()
export class RolesGuard implements CanActivate {
  constructor(private reflector: Reflector) {}
  canActivate(ctx: ExecutionContext): boolean {
    const roles = this.reflector.get<string[]>('roles', ctx.getHandler()) || [];
    if (!roles.length) return true;
    const req = ctx.switchToHttp().getRequest<Request>();
    const role = req.user?.role;
    return roles.includes(role);
  }
}

export const Roles = (...roles: string[]) => SetMetadata('roles', roles);
```

## 6. Esquema sugerido `audit_logs`
```sql
CREATE TABLE IF NOT EXISTS audit_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL,
  user_id uuid,
  action text NOT NULL,
  entity text,
  entity_id text,
  diff jsonb,
  meta jsonb,
  created_at timestamptz NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_audit_logs_client_created ON audit_logs(client_id, created_at DESC);
```
Uso: `AuditService.log({clientId, userId, action: 'product.update', entity: 'product', entityId: product.id, diff, meta})`.

## 7. Lista de chequeo para cierre de mejoras
- [ ] Webhook MP con firma + idempotencia.
- [ ] Indices críticos creados.
- [ ] Guard de roles + guard de tenant implementados.
- [ ] Cliente Supabase por request sin service role adoptado en lectura estándar.
- [ ] Audit log operativo en cambios CRUD y pagos.
- [ ] Paginación homogenizada (0-based) y documentada.
- [ ] DTOs + validation pipe para inputs abiertos (excel, banners, social links, products search).
- [ ] Validación uploads (mime/size) + limpieza huérfanos.
- [ ] Logger estructurado con requestId.
- [ ] Endpoints e2e multi‑tenant test (aislamiento verificado).

## 8. Próximos pasos sugeridos (plan incremental)
1. Infra/DB: crear índices + tabla audit_logs.
2. Seguridad: guards centralizados + ajustes cliente Supabase.
3. Pagos: webhook completo + order snapshot.
4. Observabilidad: logger estructurado + requestId + healthcheck.
5. Refactor performance: stock batch + caching CORS.
6. Limpieza y mantenimiento: validaciones upload + garbage collector imágenes.

## 9. Notas finales
El núcleo multi‑tenant está encaminado (uso consistente de `client_id`). El mayor riesgo reside en uso extendido del service role y ausencia de auditoría/firma/idempotencia en el flujo de pagos. Priorizar fortalecer frontera de seguridad y trazabilidad antes de expandir funcionalidad.

---
Documento generado automáticamente como base de mejora continua.

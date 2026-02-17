# Cambio: Remediación de seguridad — Fase 1 (CRÍTICOS + MEJORAS)

- **Autor:** agente-copilot
- **Fecha:** 2025-07-15
- **Rama:** feature/automatic-multiclient-onboarding (API) + feature/automatic-multiclient-onboarding (Admin)
- **Referencia:** novavision-docs/audit/SECURITY_AUDIT_2025-07-14.md + REMEDIATION_PLAN_DETAILED.md

---

## Archivos modificados

### Backend (apps/api)
1. `src/common/utils/storage-path.helper.ts`
2. `src/common/utils/client-id.helper.ts`
3. `src/observability/system.controller.ts`
4. `src/admin/admin.controller.ts`
5. `src/guards/roles.guard.ts`
6. `src/auth/auth.middleware.ts`
7. `src/products/products.controller.ts`

### Admin Frontend (apps/admin)
8. `src/services/api/nestjs.js`

---

## Resumen de cambios

### 🔴 CRÍTICOS

**C-1: Path Traversal en Storage (storage-path.helper.ts)**
- Se agregó `path.basename()` para eliminar componentes de directorio (previene `../../etc/passwd`)
- Se aplica regex `[^a-zA-Z0-9._-]` para sanitizar caracteres peligrosos
- Se impone límite de 100 caracteres al nombre de archivo
- Fallback a `'file'` si el nombre queda vacío o es `.`/`..`

**C-2: Inyección de Tenant via x-client-id (client-id.helper.ts)**
- Se eliminó el fallback a `req.headers['x-client-id']` — la fuente única es `req.clientId` seteado por `TenantContextGuard`
- Un atacante ya NO puede inyectar un `client_id` arbitrario vía header

**C-4: Endpoints sin SuperAdminGuard (system.controller.ts + admin.controller.ts)**
- `GET /admin/system/health` y `GET /admin/system/audit/recent` ahora protegidos con `@UseGuards(SuperAdminGuard)` a nivel de clase
- `POST /admin/stats` ahora tiene `@UseGuards(SuperAdminGuard)` — antes cualquier usuario autenticado podía ver stats de admin

### 🟠 MEJORAS

**M-1: Escalación admin → super_admin (roles.guard.ts)**
- Un usuario `admin` sin `client_id` del proyecto `admin` ya no puede pasar `@Roles('super_admin')` implícitamente
- Ahora lanza `ForbiddenException` con mensaje claro

**M-2: Bypass de Auth via substring (auth.middleware.ts)**
- Se reemplazó `url.includes('/onboarding/')` (y las otras 19 rutas) por `url.startsWith(prefix)`
- Previene bypass con URLs como `/evil?redirect=/onboarding/`
- Los prefijos se definen en un array `PUBLIC_PATH_PREFIXES` para mantenimiento limpio

**M-5: File Upload sin límites (products.controller.ts)**
- `AnyFilesInterceptor()` en `POST /products` y `PUT /products/:id` ahora tiene:
  - `limits: { fileSize: 5 MB, files: 10 }`
  - `fileFilter` que solo acepta `image/*`
- Los endpoints de Excel y optimized image ya tenían límites correctos

**M-8: Log de JWT parcial en producción (nestjs.js)**
- Se eliminó el log de los primeros 10 caracteres del JWT en producción
- Solo se logea `hasSession` y `hasToken` (booleanos) y solo en modo `DEV`

---

## Por qué

Estas vulnerabilidades fueron identificadas en la auditoría de seguridad de 7 capas del 14/07/2025 (32 findings, 9 P0). Los cambios aplicados cubren los findings de menor riesgo de regresión pero mayor impacto de seguridad.

---

## Cómo probar

### Validación automática (ya ejecutada ✅)
```bash
cd apps/api
npm run lint       # ✅ 0 errores
npm run typecheck  # ✅ Sin errores de tipos
npm run build      # ✅ Build exitoso, dist/main.js generado
```

### Tests manuales recomendados

1. **C-1 (Path Traversal):** Subir producto con imagen cuyo nombre sea `../../etc/passwd` — debe guardarse como `{uuid}_______etc_passwd`
2. **C-2 (x-client-id):** Hacer request con `x-client-id: <uuid-ajeno>` sin `x-tenant-slug` — debe devolver 400
3. **C-4 (Guards):** `GET /admin/system/health` sin JWT → debe devolver 403
4. **M-1 (Escalación):** Usuario `admin` sin clientId intentando acceder a ruta `@Roles('super_admin')` → debe devolver 403
5. **M-2 (Auth bypass):** `GET /products?foo=/onboarding/` con token → NO debe bypassear auth
6. **M-5 (Upload):** Subir archivo `.exe` como imagen de producto → debe devolver error
7. **M-8 (JWT log):** En producción, verificar que la consola del admin NO muestra caracteres del JWT

---

## Notas de seguridad

- **Riesgo de regresión: BAJO** — todos los cambios son restrictivos (agregan validaciones), no cambian lógica de negocio
- **Impacto:** Cierra 7 de los 32 findings de la auditoría (3 P0 + 4 P1)
- **Pendientes (Fase 2):** DNI `getPublicUrl()` → signed URLs, migración de `internal_key` a httpOnly cookie, CSP headers, ngrok en prod CORS, RLS en `auth_bridge_codes` + `provisioning_job_steps`

---

## Validaciones ejecutadas

| Check | Resultado |
|-------|-----------|
| `npm run lint` | ✅ 0 errores, 1111 warnings (preexistentes) |
| `npm run typecheck` | ✅ Sin errores |
| `npm run build` | ✅ dist/main.js generado |
| `ls dist/main.js` | ✅ 10580 bytes |

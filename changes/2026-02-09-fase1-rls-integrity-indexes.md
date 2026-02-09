# Fase 1: RLS + Integridad + Storage + Índices

- **Autor:** copilot-agent
- **Fecha:** 2026-02-09
- **Rama API:** `feature/automatic-multiclient-onboarding` (commit `1fb2ef7`)
- **DB ejecutadas:** Multicliente + Admin (ambas en vivo)

---

## Resumen

Fase 1 del plan de seguridad: cerrar brechas de RLS restantes, reforzar integridad referencial en `tenant_payment_events`, y agregar índices faltantes en `order_items`.

## Estado previo encontrado

| Tabla | DB | RLS | server_bypass | Problema |
|-------|-----|-----|---------------|----------|
| `client_home_settings` | Multi | ON | NO | Solo policy "Super Admin Bulk Access" |
| `home_sections` | Multi | ON | NO | Idem |
| `client_assets` | Multi | ON | NO | Idem |
| `order_items` | Multi | ON | NO | Idem + sin índices en FKs |
| `auth_handoff` | Admin | **OFF** | NO | RLS completamente deshabilitado |
| `tenant_payment_events` | Multi | ON | SI | `tenant_id` nullable, sin FK |
| Storage `product-images` | Multi | ON | SI | Policies correctas (ya OK) |

## Migraciones aplicadas

### BACKEND_005_fase1_rls_server_bypass.sql (Multi DB)
- Agrega `server_bypass` (FOR ALL, `auth.role() = 'service_role'`) a: `client_home_settings`, `home_sections`, `client_assets`, `order_items`
- Idempotente con `IF NOT EXISTS`
- Riesgo: BAJO — `relforcerowsecurity=f`, service_role ya bypasea; es defensa en profundidad

### ADMIN_056_auth_handoff_rls.sql (Admin DB)
- `ALTER TABLE auth_handoff ENABLE ROW LEVEL SECURITY`
- Agrega `server_bypass` policy
- `REVOKE ALL ON auth_handoff FROM anon, authenticated`
- Riesgo: BAJO — tabla solo accedida via service_role desde backend

### BACKEND_006_tenant_payment_events_not_null.sql (Multi DB)
- `ALTER COLUMN tenant_id SET NOT NULL` (0 NULLs existentes)
- `ADD CONSTRAINT fk_tpe_tenant_id FOREIGN KEY (tenant_id) REFERENCES clients(id) ON DELETE CASCADE`
- Riesgo: BAJO — 1 fila, sin NULLs

### BACKEND_007_order_items_indexes.sql (Multi DB)
- `CREATE INDEX CONCURRENTLY idx_order_items_order_id ON order_items (order_id)`
- `CREATE INDEX CONCURRENTLY idx_order_items_product_id ON order_items (product_id)`
- Riesgo: BAJO — CONCURRENTLY, tabla pequeña

## Item 1.4 (Storage): Ya resuelto
Las políticas de `storage.objects` ya estaban correctamente configuradas:
- `service_role_bypass`: acceso total para backend
- `client_media_insert/update/delete`: scoped a `clients/{client_id}/` via JWT
- `public_read_client_media`: lectura pública con validación de path UUID

## Verificación post-ejecución

```
-- Multi DB: 4 server_bypass creadas
client_assets        | server_bypass ✅
client_home_settings | server_bypass ✅
home_sections        | server_bypass ✅
order_items          | server_bypass ✅

-- tenant_payment_events.tenant_id: NOT NULL ✅, FK fk_tpe_tenant_id ✅

-- order_items indexes:
idx_order_items_order_id   ✅
idx_order_items_product_id ✅

-- Admin DB: auth_handoff
rowsecurity: t ✅
server_bypass policy: ALL ✅
```

## Impacto en frontends

**Ninguno.** Estos cambios son puramente de DB (RLS, índices, constraints). No cambian contratos de API ni comportamiento de endpoints. El backend usa `service_role` para todo acceso a estas tablas.

## Notas de seguridad
- `auth_handoff` almacena tokens de handoff encriptados (AES). Ahora protegida con RLS.
- `tenant_payment_events` ahora garantiza integridad referencial con `clients.id`.
- Los 4 `server_bypass` son consistentes con la convención del proyecto en las demás tablas.

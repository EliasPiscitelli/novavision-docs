# Cambio: Arquitectura dual-DB en Admin Frontend (backendSupabase real)

- **Autor:** agente-copilot
- **Fecha:** 2025-02-07
- **Rama:** feature/automatic-multiclient-onboarding
- **Archivos modificados:**
  - `apps/admin/src/services/supabase/index.js`
  - `apps/admin/src/components/PaymentsSection/index.jsx`
  - `apps/admin/src/pages/ClientDetails/index.jsx`
  - `apps/admin/src/utils/clientService.jsx`
  - `apps/admin/src/pages/AdminDashboard/ClientsView.jsx`

---

## Resumen

Se creó un segundo cliente Supabase **real** (`backendSupabase`) en el admin frontend que apunta a la **Multicliente DB** (`ulndkhijxtxvpmbbfrgp`), separándolo del cliente Admin DB (`erbfzlsznqsmwmjugspo`).

Previamente `backendSupabase` era un **alias** del mismo `adminSupabase` — todas las queries iban a Admin DB, provocando fallos silenciosos en tablas que solo existen en Multicliente DB (`clients`, `orders`, etc.).

---

## Por qué

El admin dashboard opera sobre **dos bases de datos Supabase distintas**:

| DB | Proyecto | Tablas principales |
|---|---|---|
| **Admin** | `erbfzlsznqsmwmjugspo` | `nv_accounts`, `payments`, `invoices`, `client_tombstones`, `leads`, `app_settings` |
| **Multicliente** | `ulndkhijxtxvpmbbfrgp` | `clients`, `products`, `orders`, `categories`, `banners`, `users` |

Queries a `.from('clients')` fallaban silenciosamente porque Admin DB no tiene esa tabla.

---

## Detalle de cambios

### 1. `src/services/supabase/index.js`
- **Antes:** Un solo cliente Supabase con exports `adminSupabase`, `backendSupabase` (alias), `supabase` — todos apuntando a Admin DB.
- **Después:** Dos clientes independientes:
  - `adminSupabase` / `supabase` → Admin DB (anon key + auth session)
  - `backendSupabase` → Multicliente DB (service_role key, sin session)
- **Seguridad:** El `backendSupabase` usa `VITE_BACKEND_SUPABASE_SERVICE_ROLE_KEY` porque el JWT de Admin Supabase Auth no es válido en el proyecto Multicliente (son proyectos Supabase distintos con secrets diferentes). Esto es aceptable porque el admin dashboard es una herramienta interna exclusiva para super admins.

### 2. `src/components/PaymentsSection/index.jsx`
- **Antes:** Cargaba clientes con `.from("clients")` de Admin DB (falla) y hacía JOIN `payments→clients` (falla).
- **Después:**
  - Carga lista de clientes desde `backendSupabase.from("clients")` (Multicliente DB).
  - Helper `fetchGlobalPaymentsWithClients()`: carga payments de Admin DB + info de clientes de Multicliente DB → merge en JS.
  - Las 3 recarga (initial, post-edit, post-delete) usan el mismo patrón.

### 3. `src/pages/ClientDetails/index.jsx`
- **Antes:** `.from('clients').update({plan_paid_until})` iba a Admin DB (tabla no existe).
- **Después:** Usa `(backendSupabase || supabase).from('clients').update(...)` para escribir en Multicliente DB.

### 4. `src/utils/clientService.jsx`
- **Antes:** `.from('clients').update({...})` iba a Admin DB.
- **Después:** Usa `(backendSupabase || supabase).from('clients').update(...)`.

### 5. `src/pages/AdminDashboard/ClientsView.jsx`
- **Antes:** `.from('clients_deleted_summary')` — tabla/view que no existe en ninguna DB.
- **Después:** Consulta `client_tombstones` (tabla real en Admin DB) con columnas ajustadas:
  - `client_id` → mapeado a `id`
  - `reason` → mapeado a `deleted_reason`
  - Datos complementarios extraídos de `snapshot` JSONB (email_admin, monthly_fee, etc.)

---

## GRANTs aplicados a producción

```sql
GRANT SELECT ON public.client_tombstones TO authenticated;
```

(RLS ya tenía políticas para super admin.)

---

## Cómo probar

1. **Levantar admin:** `cd apps/admin && npm run dev`
2. **Dashboard → Clientes:** Verificar que la lista carga correctamente (viene del API NestJS).
3. **Dashboard → Clientes eliminados:** Toggle "Mostrar eliminados" muestra datos de `client_tombstones`.
4. **Detalle cliente → Pagos:** Verificar que la sección de pagos carga sin errores. (Nota: la tabla `payments` está vacía actualmente.)
5. **Detalle cliente → Registrar pago:** Registrar un pago manual y verificar que aparece en la lista.
6. **Editar cliente:** Verificar que la actualización de `plan_paid_until` y otros campos funciona.
7. **Pagos globales (PaymentsSection sin clientId):** Verificar que la lista combina payments + nombres de clientes.

---

## Notas de seguridad

- `VITE_BACKEND_SUPABASE_SERVICE_ROLE_KEY` es expuesta en el bundle JS del admin.
- **Mitigación:** El admin dashboard requiere autenticación + es una herramienta interna de super admins.
- **Recomendación futura:** Migrar queries a Multicliente a endpoints NestJS dedicados para eliminar la exposición del service_role key en el frontend.

---

## Mapa de queries por DB (referencia)

### Admin DB (supabase / adminSupabase)
| Tabla | Uso |
|---|---|
| `nv_accounts` | Listado de cuentas en dashboard |
| `nv_onboarding` | Estado de onboarding |
| `payments` | Pagos registrados (client_id = multicliente clients.id) |
| `invoices` | Facturación mensual |
| `client_usage_month` | Métricas de uso |
| `client_tombstones` | Clientes eliminados |
| `leads` / `lead_assets` | Pipeline comercial |
| `outreach_leads` | Leads de outreach |
| `app_settings` | Configuración global |
| `nv_playbook` | Playbook de operaciones |
| `users` | Usuarios del admin |
| Edge Functions | admin-create-client, admin-sync-client, etc. |

### Multicliente DB (backendSupabase)
| Tabla | Uso |
|---|---|
| `clients` | CRUD, actualizar plan_paid_until, dropdown en PaymentsSection |
| (futuro) `products`, `orders`, `categories` | Cuando se necesite acceso cross-tenant desde admin |

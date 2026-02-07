# Hotfix: Permisos Admin Dashboard + FinanceModule faltante

- **Autor:** agente-copilot
- **Fecha:** 2026-02-07
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Admin:** feature/automatic-multiclient-onboarding

---

## Problema reportado

El Super Dashboard Admin (novavision.lat) presentaba 3 errores simultáneos:

| Error | Endpoint / Tabla | Código |
|-------|-----------------|--------|
| `permission denied for table nv_playbook` | `GET /rest/v1/nv_playbook` (Supabase REST) | 42501 |
| `permission denied for table leads` | `GET /rest/v1/leads?select=*,meetings(...)` (Supabase REST) | 42501 |
| `Cannot GET /admin/finance/summary` | `GET /admin/finance/summary` (API NestJS) | 404 |

---

## Causa raíz

### Errores 42501 (permission denied) — `nv_playbook`, `leads`, `meetings`

Las tablas tenían:
- ✅ RLS habilitado (`ALTER TABLE ... ENABLE ROW LEVEL SECURITY`)
- ✅ Políticas RLS correctas (admin_all por UUID, service_all, anon_insert)
- ❌ **Sin `GRANT` a nivel de tabla** para los roles de Supabase (`anon`, `authenticated`, `service_role`)

En Postgres, **RLS y GRANTs son capas independientes**. Sin GRANT, el motor rechaza el acceso **antes** de evaluar las políticas RLS, emitiendo error `42501`.

La tabla `app_settings` (creada en `10_app_settings.sql`) ya incluía GRANTs y funcionaba correctamente, lo que confirmó que era un patrón faltante en las tablas más nuevas.

### Error 404 — `/admin/finance/summary`

- `FinanceModule` existía con controller (`@Controller('admin/finance')`) y service
- El módulo **nunca fue importado en `AppModule`** (`app.module.ts`)
- NestJS no registraba el endpoint → 404

---

## Archivos modificados

### SQL (Admin DB - Supabase `erbfzlsznqsmwmjugspo`)

| Archivo | Cambio |
|---------|--------|
| `apps/admin/supabase/sql/07_leads_rls.sql` | Agregados GRANTs para `leads`, `lead_assets`, `meetings` |
| `apps/admin/supabase/sql/14_nv_playbook_rls.sql` | Agregados GRANTs para `nv_playbook` |
| `apps/admin/supabase/sql/12_outreach_leads.sql` | Agregados GRANTs para `outreach_leads` |
| `apps/admin/supabase/sql/hotfix_grants_2026-02-07.sql` | Script de hotfix ejecutable (referencia) |

### API (NestJS - templatetwobe)

| Archivo | Cambio |
|---------|--------|
| `apps/api/src/app.module.ts` | Importado `FinanceModule` en el array de imports de `AppModule` |

---

## GRANTs aplicados (detalle)

```sql
-- leads
GRANT SELECT, INSERT ON public.leads TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.leads TO authenticated;
GRANT ALL ON public.leads TO service_role;

-- lead_assets
GRANT INSERT ON public.lead_assets TO anon;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.lead_assets TO authenticated;
GRANT ALL ON public.lead_assets TO service_role;

-- meetings
GRANT SELECT ON public.meetings TO authenticated;
GRANT ALL ON public.meetings TO service_role;

-- nv_playbook
GRANT SELECT ON public.nv_playbook TO authenticated;
GRANT ALL ON public.nv_playbook TO service_role;

-- outreach_leads
GRANT SELECT, INSERT, UPDATE, DELETE ON public.outreach_leads TO authenticated;
GRANT ALL ON public.outreach_leads TO service_role;
```

---

## Acciones ejecutadas

1. **GRANTs aplicados en producción** vía `psql` directo contra `ADMIN_DB_URL` — **efectivo inmediatamente**
2. **Verificación post-apply** con query a `information_schema.role_table_grants` — todos los grants confirmados
3. **`FinanceModule` registrado** en `app.module.ts` — requiere **deploy de la API** para tomar efecto

---

## Cómo probar

### Tablas (ya deberían funcionar):
1. Ir a https://novavision.lat (dashboard admin)
2. Verificar que la sección de Leads carga sin error
3. Verificar que el Playbook (nv_playbook) carga sin error
4. Verificar que las meetings asociadas a leads aparecen

### Finance endpoint (post-deploy):
1. Hacer deploy de la API (Railway)
2. Verificar `GET /admin/finance/summary?range_start=...&range_end=...` responde 200
3. Verificar que el dashboard de finanzas muestra datos

---

## Notas de seguridad

- Los GRANTs siguen el principio de mínimo privilegio:
  - `anon` solo recibe INSERT en leads/lead_assets (para el quiz público)
  - `authenticated` recibe CRUD completo (protegido por RLS policies que limitan a `auth.uid() = <admin_uuid>`)
  - `service_role` recibe ALL (para Edge Functions y backend)
- Las políticas RLS existentes **no se modificaron** — siguen activas y restringiendo acceso
- El `FinanceModule` está protegido con `SuperAdminGuard` + `@AllowNoTenant()`

---

## Riesgos / Rollback

- **GRANTs:** Bajo riesgo. Las políticas RLS siguen activas como segunda capa. Para rollback: `REVOKE ... FROM <role>`
- **FinanceModule:** Bajo riesgo. Solo agrega un endpoint nuevo, no modifica existentes. Para rollback: quitar el import de `app.module.ts`

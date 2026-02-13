# NovaVision — Limpieza de Bases de Datos (Pre-E2E)

**Fecha:** 2026-07-14  
**Autor:** agente-copilot  
**Propósito:** Eliminar todos los datos demo/test de ambas DBs para ejecutar el suite E2E completo desde cero.

---

## Resumen de estado actual

### Multicliente DB (`db.ulndkhijxtxvpmbbfrgp`)

| Tabla | Registros | Acción |
|-------|-----------|--------|
| clients | 28 | 🗑️ TRUNCAR TODO |
| products | 28 | 🗑️ TRUNCAR |
| categories | 13 | 🗑️ TRUNCAR |
| users | 11 | 🗑️ TRUNCAR |
| orders | 19 | 🗑️ TRUNCAR |
| cart_items | 2 | 🗑️ TRUNCAR |
| email_jobs | 5 | 🗑️ TRUNCAR |
| mp_idempotency | 60 | 🗑️ TRUNCAR |
| mp_fee_table | 10 | ✅ PRESERVAR (config sistema) |
| auth.users | 6 | 🗑️ DELETE ALL |

### Admin DB (`db.erbfzlsznqsmwmjugspo`)

| Tabla | Registros | Acción |
|-------|-----------|--------|
| nv_accounts | 15 | 🗑️ TRUNCAR (todas QA) |
| nv_onboarding | 15 | 🗑️ TRUNCAR |
| provisioning_jobs | 15 | 🗑️ TRUNCAR |
| usage_ledger | 7,800 | 🗑️ TRUNCAR |
| account_sync_outbox | 13 | 🗑️ TRUNCAR |
| plans | 6 | ✅ PRESERVAR |
| super_admins | 2 | ✅ PRESERVAR |
| app_settings | 7 | ✅ PRESERVAR |
| nv_playbook | 85 | ✅ PRESERVAR |
| nv_templates | 5 | ✅ PRESERVAR |
| palette_catalog | 20 | ✅ PRESERVAR |
| outreach_leads | 47,403 | ✅ PRESERVAR |
| auth.users | 2 | ✅ PRESERVAR |

---

## Archivos SQL

1. **`cleanup-multicliente.sql`** → Trunca TODAS las tablas de negocio en orden FK correcto + DELETE auth.users
2. **`cleanup-admin.sql`** → Trunca nv_accounts y data derivada; preserva catálogos/planes/super_admins

---

## Cómo ejecutar

```bash
# 1. Multicliente DB
psql "postgresql://postgres:Novavision_39628997_2025@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres" -f cleanup-multicliente.sql

# 2. Admin DB
psql "postgresql://postgres:Novavision_39628997_2025@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres" -f cleanup-admin.sql

# 3. Verificación (correr las queries comentadas al final de cada .sql)
```

---

## Después de la limpieza

1. **Re-ejecutar E2E completo:** Los tests QA-01 (onboarding) recrean los tenants QA automáticamente
2. **Re-registrar admin users:** Los tests QA-03 (auth) recrean buyers
3. Los tenants `qa-tienda-ropa` y `qa-tienda-tech` se crean en QA-01

---

## Riesgos

- **Irreversible:** No hay backup automático. Si se necesita rollback, se requiere restaurar desde snapshot de Supabase.
- **UrbanPrint:** Se elimina el único cliente real (8 productos, 3 categorías, 3 users, 0 orders). Fue confirmado por el TL.
- **Auth tokens:** Los usuarios logueados con JWT existentes van a recibir 401 después de la limpieza. Deben re-loguearse.

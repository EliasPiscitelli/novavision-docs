# PGSQL Extension – Servidores registrados

> Última actualización: 2026-02-07

## Servidores en la extensión PGSQL de VS Code

| Server ID | Nombre | Host | Default DB |
|-----------|--------|------|------------|
| BED9611A-344C-4A94-B43A-13D2F8179177 | prd | dev.db.miescuela2.phinxlab.com | prd |

## NovaVision – Conexiones directas (NO registradas en PGSQL ext)

Las DBs de NovaVision se acceden via connection string (Supabase):

| DB | Alias | Host | Puerto | User | Database |
|----|-------|------|--------|------|----------|
| Admin | ADMIN_DB_URL | db.erbfzlsznqsmwmjugspo.supabase.co | 5432 | postgres | postgres |
| Multicliente | BACKEND_DB_URL | db.ulndkhijxtxvpmbbfrgp.supabase.co | 5432 | postgres | postgres |

### Cómo conectar via psql

```bash
# Admin DB
psql "postgresql://postgres:<password>@db.erbfzlsznqsmwmjugspo.supabase.co:5432/postgres"

# Multicliente DB (Backend)
psql "postgresql://postgres:<password>@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres"
```

### Supabase SDK URLs

| Proyecto | URL | Rol |
|----------|-----|-----|
| Multicliente | https://ulndkhijxtxvpmbbfrgp.supabase.co | anon + service_role |
| Admin | https://erbfzlsznqsmwmjugspo.supabase.co | service_role |

> **Nota:** Las passwords están en el `.env` de la API (`apps/api/.env`). No commitear este archivo con credenciales reales.

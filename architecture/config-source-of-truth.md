# 🎯 Fuente Única de Verdad: Configuración de Storefront

> **Fecha:** 2026-02-04  
> **Estado:** APROBADO  
> **Owner:** API Team (provisioning-worker)

---

## Decisión Arquitectónica

### Tabla Elegida: `client_home_settings` (Backend DB)

La configuración de render del storefront (template, palette, theme overrides, identity) se lee **exclusivamente** de la tabla `client_home_settings` en Backend DB.

**Cualquier otra tabla es upstream** (fuente de datos que alimenta a `client_home_settings`, pero no es leída directamente por el storefront).

---

## Schema Oficial

```sql
-- Backend DB: ulndkhijxtxvpmbbfrgp
-- Tabla: public.client_home_settings

CREATE TABLE IF NOT EXISTS client_home_settings (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id UUID NOT NULL UNIQUE REFERENCES clients(id) ON DELETE CASCADE,
  template_key TEXT NOT NULL DEFAULT 'first',
  palette_key TEXT NOT NULL DEFAULT 'starter_default',
  identity_config JSONB DEFAULT '{}',
  theme_config JSONB DEFAULT '{}',
  identity_version INT DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);

-- Índice para búsquedas rápidas
CREATE INDEX IF NOT EXISTS idx_client_home_settings_client_id 
ON client_home_settings(client_id);
```

### Campos

| Campo | Tipo | Requerido | Descripción |
|-------|------|-----------|-------------|
| `id` | UUID | ✅ | PK auto-generada |
| `client_id` | UUID | ✅ | FK a `clients.id`, UNIQUE |
| `template_key` | TEXT | ✅ | Ej: `first`, `second`, `fourth`, `fifth` |
| `palette_key` | TEXT | ✅ | Ej: `starter_default`, `starter_elegant`, `starter_bold` |
| `identity_config` | JSONB | ❌ | Logo, favicon, colores custom del cliente |
| `theme_config` | JSONB | ❌ | Overrides de secciones (header, footer, pdp, etc.) |
| `identity_version` | INT | ❌ | Versión para cache-busting |
| `created_at` | TIMESTAMPTZ | ✅ | Timestamp de creación |
| `updated_at` | TIMESTAMPTZ | ✅ | Timestamp de última actualización |

---

## Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────┐
│                         UPSTREAM                                 │
│                                                                  │
│  nv_onboarding (Admin DB)                                       │
│  ├── selected_template_key                                       │
│  ├── selected_palette_key                                        │
│  ├── selected_theme_override                                     │
│  └── design_config                                               │
│                                                                  │
└─────────────────────────────┬────────────────────────────────────┘
                              │
                              │ PROVISIONING
                              │ (Al aprobar/publicar)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│               FUENTE ÚNICA DE VERDAD                             │
│                                                                  │
│  client_home_settings (Backend DB)                               │
│  ├── template_key ← nv_onboarding.selected_template_key         │
│  ├── palette_key ← nv_onboarding.selected_palette_key           │
│  ├── theme_config ← nv_onboarding.selected_theme_override       │
│  └── identity_config ← nv_onboarding.design_config.identity     │
│                                                                  │
└─────────────────────────────┬────────────────────────────────────┘
                              │
                              │ LECTURA
                              │ (Storefront render)
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                      STOREFRONT                                  │
│                                                                  │
│  HomeSettingsService.getSettings(clientId)                       │
│  StorefrontAssembler.buildBootstrap()                            │
│  → GET /home/data                                                │
│  → GET /storefront/bootstrap                                     │
│                                                                  │
│  App.jsx → useEffectiveTheme({                                   │
│    templateKey: config.templateKey,                              │
│    paletteKey: config.paletteKey,                                │
│    themeConfig: config.themeConfig                               │
│  })                                                              │
│                                                                  │
└─────────────────────────────────────────────────────────────────┘
```

---

## Ownership

### Escritura (Owner: Provisioning Worker)

**Archivo:** `apps/api/src/worker/provisioning-worker.service.ts`

**Responsabilidad:**
- Al aprobar/publicar un cliente, copiar datos de `nv_onboarding` a `client_home_settings`
- Upsert idempotente (ON CONFLICT DO UPDATE)
- Loggear resultado del upsert

**Código de referencia:**
```typescript
// provisioning-worker.service.ts
const { error } = await backendClient
  .from('client_home_settings')
  .upsert({
    client_id: clientId,
    template_key: onboarding.selected_template_key || 'first',
    palette_key: onboarding.selected_palette_key || 'starter_default',
    theme_config: onboarding.selected_theme_override || {},
    identity_config: onboarding.design_config?.identity || {},
    updated_at: new Date().toISOString(),
  }, { onConflict: 'client_id' });

if (error) {
  this.logger.error(`Failed to upsert client_home_settings: ${error.message}`);
  throw error;
}
this.logger.log(`Upserted client_home_settings for client ${clientId}`);
```

### Lectura (Owner: HomeSettingsService)

**Archivo:** `apps/api/src/home/home-settings.service.ts`

**Responsabilidad:**
- Leer de `client_home_settings` usando **Backend DB client** (no Admin)
- Si no hay row, loggear WARNING y usar defaults
- Normalizar snake_case → camelCase para el frontend

**Código de referencia:**
```typescript
// home-settings.service.ts
async getSettings(clientId: string, cli?: SupabaseClient): Promise<HomeSettings> {
  const client = cli || this.supabaseClient; // DEBE ser Backend client
  
  const { data, error } = await client
    .from('client_home_settings')
    .select('template_key, palette_key, identity_config, theme_config')
    .eq('client_id', clientId)
    .single();

  if (error || !data) {
    this.logger.warn(`Using default settings for client ${clientId}`);
    return {
      templateKey: 'first',
      paletteKey: 'starter_default',
      identityConfig: {},
      themeConfig: {},
    };
  }

  return {
    templateKey: data.template_key,
    paletteKey: data.palette_key,
    identityConfig: data.identity_config,
    themeConfig: data.theme_config,
  };
}
```

---

## Reglas de Consistencia

### ✅ DEBE cumplirse

1. **Una sola fuente:** El storefront SOLO lee de `client_home_settings`
2. **Provisioning completo:** Al publicar, SIEMPRE escribir a `client_home_settings`
3. **Logs obligatorios:** Todo fallback debe loggear WARNING
4. **Backend DB:** HomeSettingsService usa `SUPABASE_CLIENT`, no `SUPABASE_ADMIN_CLIENT`

### ❌ PROHIBIDO

1. Leer config de storefront desde `clients.template_id` o `clients.theme_config`
2. Leer config de storefront desde `nv_onboarding` directamente
3. Publicar una tienda sin row en `client_home_settings`
4. Fallbacks silenciosos sin logging

---

## Queries de Verificación

### Verificar que no hay tiendas huérfanas
```sql
-- Debe retornar 0 rows
SELECT c.id, c.slug 
FROM clients c 
LEFT JOIN client_home_settings chs ON c.id = chs.client_id
WHERE chs.id IS NULL AND c.publication_status = 'published';
```

### Verificar config de una tienda específica
```sql
SELECT 
  c.slug,
  chs.template_key,
  chs.palette_key,
  chs.theme_config IS NOT NULL as has_theme_config
FROM clients c
JOIN client_home_settings chs ON c.id = chs.client_id
WHERE c.slug = '<SLUG>';
```

### Comparar con upstream (debugging)
```sql
-- Admin DB
SELECT 
  na.slug,
  no.selected_template_key,
  no.selected_palette_key
FROM nv_accounts na
JOIN nv_onboarding no ON na.id = no.account_id
WHERE na.slug = '<SLUG>';
```

---

## Historial de Cambios

| Fecha | Cambio | Autor |
|-------|--------|-------|
| 2026-02-04 | Documento inicial, decisión aprobada | Principal Engineer Audit |

---

## Referencias

- [Informe de Inconsistencias](../changes/2026-02-04-sync-approval-audit.md)
- [Theme System Docs](../THEME_DOCUMENTATION_INDEX.md)
- [Onboarding Guide](../runbooks/onboarding_complete_guide.md)

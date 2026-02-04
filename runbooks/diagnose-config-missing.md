# Runbook: Diagnóstico de Configuración Faltante

## Síntoma
- Storefront muestra error "Tienda en mantenimiento"
- Theme no carga correctamente
- Colores/fuentes no se aplican

## Herramientas de Diagnóstico

### 1. Health Check Endpoint

```bash
# Verificar configuración de un cliente por slug
curl https://api.novavision.com/health/config/{slug}
```

**Respuesta esperada (OK):**
```json
{
  "status": "ok",
  "slug": "demo-store",
  "checks": {
    "client_exists": true,
    "home_settings_exists": true,
    "has_template_key": true,
    "has_palette_key": true,
    "has_theme_config": true
  }
}
```

**Respuesta con problema:**
```json
{
  "status": "incomplete",
  "slug": "demo-store",
  "checks": {
    "client_exists": true,
    "home_settings_exists": false,
    "has_template_key": false,
    "has_palette_key": false,
    "has_theme_config": false
  },
  "missing": ["client_home_settings row"]
}
```

### 2. Query Directa en Backend DB

```sql
-- Verificar cliente existe
SELECT id, slug, name, is_active 
FROM clients 
WHERE slug = 'SLUG_AQUI';

-- Verificar home_settings
SELECT * 
FROM client_home_settings 
WHERE client_id = 'CLIENT_ID_AQUI';
```

### 3. Script de Backfill (si falta registro)

```bash
cd apps/api
npx ts-node scripts/backfill-home-settings.ts
```

Este script:
- Encuentra clientes sin `client_home_settings`
- Crea el registro con valores por defecto
- Migra `theme_config` desde `clients` si existe

## Causas Comunes

### 1. Provisioning Falló Silenciosamente (FIXED)
- **Antes:** El upsert en provisioning no tenía error handling
- **Ahora:** Error handling agregado en `provisioning-worker.service.ts`

### 2. Columna `theme_config` No Existía
- **Migración:** `20260204000001_add_theme_config_to_home_settings.sql`
- **Verificar:** `\d client_home_settings` en psql

### 3. Cliente Creado Antes del Sistema de Home Settings
- **Solución:** Ejecutar backfill script

## Pasos de Resolución

1. **Verificar con health check:**
   ```bash
   curl https://api.novavision.com/health/config/{slug}
   ```

2. **Si falta `client_home_settings`:**
   - Opción A: Re-ejecutar provisioning desde Admin
   - Opción B: Ejecutar backfill script

3. **Si falta `theme_config`:**
   - Verificar migración ejecutada
   - Ejecutar backfill para migrar datos desde `clients.theme_config`

4. **Validar fix:**
   ```bash
   curl https://api.novavision.com/health/config/{slug}
   # Debe retornar status: "ok"
   ```

## Preview de Tienda No Publicada

Si la tienda no está publicada pero querés previsualizarla:

1. **Generar preview token desde Admin**
2. **Acceder con token:**
   ```
   https://{slug}.novavision.store?preview={token}
   ```

El token permite acceder aunque `is_published = false`.

## Contacto de Escalación

- **L1:** Runbook + health check
- **L2:** Backfill script / query directa
- **L3:** Review de logs de provisioning-worker

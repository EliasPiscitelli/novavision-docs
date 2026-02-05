# 🎨 SQLs para Parchar Usuario Test con Diferentes Templates y Themes

> **Fecha:** 2026-02-05  
> **Base de datos target:** Backend DB (Multicliente) - `ulndkhijxtxvpmbbfrgp`

---

## 📋 Pre-requisitos

1. Conectar a Backend DB:
```bash
# Variables de entorno (reemplazar con valores reales)
export BACKEND_DB_URL="postgresql://postgres:***@db.ulndkhijxtxvpmbbfrgp.supabase.co:5432/postgres"
psql "$BACKEND_DB_URL"
```

2. Obtener el `client_id` del usuario de test:
```sql
-- Buscar por slug
SELECT id, slug, name FROM clients WHERE slug = 'demo-store';
-- O buscar todos
SELECT id, slug, name, is_active FROM clients ORDER BY created_at DESC LIMIT 10;
```

---

## 🏗️ Estructura de Tablas Relevantes

### `client_home_settings` (Fuente de verdad para storefront)
```sql
-- Schema
-- client_id UUID PRIMARY KEY
-- template_key TEXT (first, second, third, fourth, fifth)
-- palette_key TEXT (starter_default, ocean_breeze, forest_calm, etc.)
-- theme_config JSONB (overrides custom)
-- identity_config JSONB (logo, banners, etc.)
```

### Templates Disponibles
| Key | Nombre | Descripción |
|-----|--------|-------------|
| `first` | Minimal Store | Diseño limpio y ordenado |
| `second` | Modern Dark | Estilo audaz con modo oscuro |
| `third` | Boutique Elegant | Sofisticado con tipografías clásicas |
| `fourth` | Tech Startup | Dinámico y tecnológico |
| `fifth` | Premium Lifestyle | Layout premium full-featured |

### Palettes del Catálogo (min_plan_key)
| Key | Nombre | Plan Mínimo |
|-----|--------|-------------|
| `starter_default` | Default Blue | starter |
| `ocean_breeze` | Ocean Breeze | starter |
| `forest_calm` | Forest Calm | starter |
| `sunset_warm` | Sunset Warm | starter |
| `midnight_pro` | Midnight Pro (dark) | growth |
| `coral_energy` | Coral Energy | growth |
| `luxury_gold` | Luxury Gold | pro |

---

## 🔧 SQLs de Parcheo

### ⚠️ ANTES: Verificar estado actual
```sql
-- Ver configuración actual del cliente
SELECT 
  c.id,
  c.slug,
  c.name,
  chs.template_key,
  chs.palette_key,
  chs.theme_config
FROM clients c
LEFT JOIN client_home_settings chs ON c.id = chs.client_id
WHERE c.slug = 'demo-store';  -- Cambiar por tu slug
```

---

### 🎯 OPCIÓN 1: Template "First" (Minimal) + Palette Default
```sql
-- Variables: Reemplazar CLIENT_ID
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'first',
    'starter_default',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'first',
    palette_key = 'starter_default',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 2: Template "Fifth" (Premium) + Ocean Breeze
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fifth',
    'ocean_breeze',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fifth',
    palette_key = 'ocean_breeze',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 3: Template "Fourth" (Tech) + Forest Calm
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fourth',
    'forest_calm',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fourth',
    palette_key = 'forest_calm',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 4: Template "Second" (Dark) + Midnight Pro
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'second',
    'midnight_pro',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'second',
    palette_key = 'midnight_pro',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 5: Template "Third" (Boutique) + Sunset Warm
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'third',
    'sunset_warm',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'third',
    palette_key = 'sunset_warm',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 6: Template "Fifth" + Coral Energy (Growth)
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fifth',
    'coral_energy',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fifth',
    palette_key = 'coral_energy',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

### 🎯 OPCIÓN 7: Template "Fourth" + Luxury Gold (Pro)
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fourth',
    'luxury_gold',
    '{}'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fourth',
    palette_key = 'luxury_gold',
    theme_config = '{}'::jsonb,
    updated_at = now();
END $$;
```

---

## 🔥 Con Theme Config Custom (Overrides)

### Template Fifth + Colores Personalizados
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fifth',
    'starter_default',
    '{
      "--nv-primary": "#FF6B6B",
      "--nv-primary-hover": "#EE5A5A",
      "--nv-accent": "#4ECDC4",
      "--nv-bg": "#FFFFFF",
      "--nv-surface": "#F7F9FC",
      "--nv-text": "#2D3436",
      "--nv-text-muted": "#636E72",
      "--nv-border": "#DFE6E9",
      "--nv-card-bg": "#FFFFFF",
      "--nv-success": "#00B894",
      "--nv-warning": "#FDCB6E",
      "--nv-error": "#E17055"
    }'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fifth',
    palette_key = 'starter_default',
    theme_config = EXCLUDED.theme_config,
    updated_at = now();
END $$;
```

### Template Fourth + Dark Mode Custom
```sql
DO $$
DECLARE
  v_client_id UUID := 'TU_CLIENT_ID_AQUI';
BEGIN
  INSERT INTO client_home_settings (client_id, template_key, palette_key, theme_config)
  VALUES (
    v_client_id,
    'fourth',
    'midnight_pro',
    '{
      "--nv-primary": "#00D9FF",
      "--nv-primary-hover": "#00B8D9",
      "--nv-accent": "#FF0080",
      "--nv-bg": "#0A0A0A",
      "--nv-surface": "#1A1A2E",
      "--nv-text": "#EAEAEA",
      "--nv-text-muted": "#888888",
      "--nv-border": "#2D2D44",
      "--nv-card-bg": "#16213E",
      "--nv-success": "#00FF88",
      "--nv-warning": "#FFD93D",
      "--nv-error": "#FF4757"
    }'::jsonb
  )
  ON CONFLICT (client_id) DO UPDATE SET
    template_key = 'fourth',
    palette_key = 'midnight_pro',
    theme_config = EXCLUDED.theme_config,
    updated_at = now();
END $$;
```

---

## 🔄 Script Rápido: Cambiar Solo Template (mantener palette)
```sql
UPDATE client_home_settings
SET 
  template_key = 'fifth',  -- Cambiar aquí: first, second, third, fourth, fifth
  updated_at = now()
WHERE client_id = 'TU_CLIENT_ID_AQUI';
```

## 🔄 Script Rápido: Cambiar Solo Palette (mantener template)
```sql
UPDATE client_home_settings
SET 
  palette_key = 'ocean_breeze',  -- Cambiar aquí
  updated_at = now()
WHERE client_id = 'TU_CLIENT_ID_AQUI';
```

## 🔄 Script Rápido: Reset a Defaults
```sql
UPDATE client_home_settings
SET 
  template_key = 'first',
  palette_key = 'starter_default',
  theme_config = '{}'::jsonb,
  updated_at = now()
WHERE client_id = 'TU_CLIENT_ID_AQUI';
```

---

## ✅ Verificación Post-Parche

```sql
-- 1. Verificar que se guardó
SELECT 
  c.slug,
  chs.template_key,
  chs.palette_key,
  chs.theme_config,
  chs.updated_at
FROM client_home_settings chs
JOIN clients c ON c.id = chs.client_id
WHERE c.slug = 'demo-store';

-- 2. Ver todas las configuraciones
SELECT 
  c.slug,
  chs.template_key,
  chs.palette_key
FROM client_home_settings chs
JOIN clients c ON c.id = chs.client_id
ORDER BY chs.updated_at DESC;
```

---

## 🌐 Probar en Browser

Después de aplicar el SQL:

1. Abrir la tienda: `https://{slug}.novavision.app` o `http://localhost:5173?tenant={slug}`
2. **Hard refresh:** `Cmd+Shift+R` (Mac) o `Ctrl+Shift+R` (Windows)
3. El template y colores deberían reflejarse

Si no funciona:
- Verificar que el endpoint `/home/data` devuelve el `templateKey` correcto
- Revisar console del browser por errores
- El storefront puede tener cache de config

---

## 📝 Referencia Rápida de CSS Variables

```css
/* Variables principales del theme */
--nv-primary        /* Color principal (botones, links) */
--nv-primary-hover  /* Hover del color principal */
--nv-primary-fg     /* Texto sobre primary (auto-calculado) */
--nv-accent         /* Color de acento secundario */
--nv-bg             /* Background general */
--nv-surface        /* Background de superficies/cards */
--nv-text           /* Color de texto principal */
--nv-text-muted     /* Color de texto secundario */
--nv-border         /* Color de bordes */
--nv-card-bg        /* Background de cards */
--nv-success        /* Color de éxito (verde) */
--nv-warning        /* Color de advertencia (amarillo) */
--nv-error          /* Color de error (rojo) */
--nv-info           /* Color informativo (azul) */
--nv-shadow         /* Sombra (rgba) */
```

---

## ⚡ One-liner para Demo Rápido

```sql
-- Cambiar demo-store a Fifth + Ocean Breeze
UPDATE client_home_settings SET template_key = 'fifth', palette_key = 'ocean_breeze', updated_at = now() WHERE client_id = (SELECT id FROM clients WHERE slug = 'demo-store');
```

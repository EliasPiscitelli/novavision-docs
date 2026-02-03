# Sistema NovaVision - Flujos y Persistencia

## 📋 Resumen de Implementaciones

Esta sesión implementó 3 sistemas principales:

1. **Theme System** - Schema normalizado con templates + overrides
2. **Security Hardening** - RLS, MaintenanceGuard, IdentityModal
3. **Design Studio** - Section management con plan gating

---

## 1️⃣ THEME SYSTEM - Flujo Completo

### 🎯 Objetivo

Refactorizar themes de objetos monolíticos a sistema normalizado con template base + client overrides (delta storage).

### 📊 Data Flow

```
┌─────────────────────────────────────────────────────────────┐
│ CREACIÓN DE THEME                                           │
└─────────────────────────────────────────────────────────────┘

Admin Panel (Onboarding)
  ↓
Usuario selecciona template: "normal"
  ↓
Usuario personaliza colores (Growth+)
  ↓
POST /themes/:clientId
  {
    template_key: "normal",
    overrides: {
      tokens: {
        colors: {
          primary: "#FF00AA"  // Solo lo que cambió
        }
      }
    }
  }
  ↓
Backend: ThemesService.updateClientTheme()
  ↓
Sanitiza overrides (remueve 'meta' si existe)
  ↓
UPSERT en client_themes:
  - client_id
  - template_key = "normal"
  - template_version = NULL (usa latest)
  - overrides = { tokens: { colors: {...} } }
  ↓
Guardado exitoso


┌─────────────────────────────────────────────────────────────┐
│ APLICACIÓN DE THEME EN FRONTEND                             │
└─────────────────────────────────────────────────────────────┘

Web App Start (apps/web)
  ↓
GET /themes/:clientId
  ↓
Backend retorna:
  {
    template_key: "normal",
    template_version: null,
    overrides: { tokens: { colors: { primary: "#FF00AA" } } }
  }
  ↓
Frontend: createTheme(template_key, overrides)
  ↓
1. Load normalTemplate from templates/normal.ts
2. Deep merge: template + overrides
3. Deep freeze (immutability)
  ↓
normalizedTheme: {
  meta: { key: "normal", version: 1, mode: "light" },
  tokens: { colors: { primary: "#FF00AA", ... }, ... },
  components: { header: {...}, button: {...}, ... }
}
  ↓
toLegacyTheme(normalizedTheme)
  ↓
legacyTheme: {
  header: {...},
  button: {...},
  colors: {...},
  typography: {...}
}
  ↓
<ThemeProvider theme={legacyTheme}>
  <App />
</ThemeProvider>
  ↓
Componentes acceden via props.theme.header.background
```

### 💾 Persistencia - Theme System

**Tabla:** `client_themes` (Admin DB)

```sql
CREATE TABLE public.client_themes (
  client_id uuid PRIMARY KEY REFERENCES public.clients(id),
  template_key text NOT NULL DEFAULT 'normal',
  template_version int NULL,  -- NULL = latest
  overrides jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);
```

**Datos Guardados:**

| Campo              | Ejemplo                                       | Descripción                      |
| ------------------ | --------------------------------------------- | -------------------------------- |
| `client_id`        | `550e8400-...`                                | UUID del cliente                 |
| `template_key`     | `"normal"`                                    | Template base a usar             |
| `template_version` | `null` o `1`                                  | Versión pinneada (null = latest) |
| `overrides`        | `{"tokens":{"colors":{"primary":"#FF00AA"}}}` | Solo deltas del template         |
| `updated_at`       | `2025-12-31 15:00:00`                         | Última modificación              |

**Ejemplo Real:**

```json
{
  "client_id": "abc-123",
  "template_key": "normal",
  "template_version": null,
  "overrides": {
    "tokens": {
      "colors": {
        "primary": "#6E72B5",
        "secondary": "#8E9BDE"
      }
    },
    "components": {
      "button": {
        "primary": "#custom-color"
      }
    }
  }
}
```

**RLS Policies:**

- Clients can read/update own theme
- Admins can manage all themes
- Service role full access

---

## 2️⃣ SECURITY HARDENING - Flujos

### 🔐 RLS (Row Level Security)

**Flujo de Ejecución:**

```
Scripts SQL → Supabase Admin DB
  ↓
20250101000001_hardening_admin_tables.sql
  - ALTER TABLE account_addons ENABLE ROW LEVEL SECURITY
  - CREATE POLICY account_addons_service_role
  - [repeat for 9+ tables]
  ↓
Tablas Aseguradas:
  ✓ account_addons
  ✓ account_entitlements
  ✓ nv_accounts
  ✓ nv_onboarding
  ✓ backend_clusters
  ✓ provisioning_jobs
  ✓ mp_events
  ↓
Resultado: Solo service_role puede acceder
```

**Persistencia:** Policies en database metadata (pg_policies)

---

### 🛡️ MaintenanceGuard

**Flujo de Request:**

```
HTTP Request → NestJS
  ↓
APP_GUARD: MaintenanceGuard.canActivate()
  ↓
1. Extract client_id (from user, params, headers)
  ↓
2. Query Admin DB:
   SELECT maintenance_mode FROM backend_clusters
   WHERE client_id = ?
  ↓
3. IF maintenance_mode = true:
     throw HttpException(503, 'Service Unavailable')
   ELSE:
     return true (allow request)
  ↓
Controller ejecuta normalmente
```

**Datos Consultados:**

**Tabla:** `backend_clusters` (Admin DB)

```sql
CREATE TABLE public.backend_clusters (
  client_id uuid PRIMARY KEY,
  cluster_id text NOT NULL DEFAULT 'cluster_shared_01',
  maintenance_mode boolean NOT NULL DEFAULT false,
  ...
);
```

| Campo              | Ejemplo             | Uso                      |
| ------------------ | ------------------- | ------------------------ |
| `client_id`        | `abc-123`           | Identificador único      |
| `maintenance_mode` | `false`             | true = bloquear requests |
| `cluster_id`       | `cluster_shared_01` | Para routing             |

**Activar Mantenimiento:**

```sql
UPDATE backend_clusters
SET maintenance_mode = true
WHERE client_id = 'abc-123';
```

---

### 🪪 IdentityModal (DNI Collection)

**Flujo Post-Payment:**

```
Payment Success (Mercado Pago)
  ↓
Admin Panel Check:
  IF nv_accounts.identity_verified = false:
    → Show IdentityModal (blocking)
  ELSE:
    → Skip, allow access
  ↓
Usuario ingresa DNI: "12345678"
  ↓
Validación Frontend:
  - Regex: /^\d{7,8}$/
  - Required field
  ↓
POST /accounts/identity
  {
    session_id: "session-abc",
    dni: "12345678"
  }
  ↓
Backend: AccountsService.saveIdentity()
  ↓
1. Lookup account_id from session_id:
   SELECT account_id FROM nv_onboarding
   WHERE session_id = ?
  ↓
2. Update nv_accounts:
   UPDATE nv_accounts SET
     dni = '12345678',
     identity_verified = true
   WHERE account_id = ?
  ↓
Guardado exitoso → Modal cierra
  ↓
Future logins: identity_verified = true → No modal
```

**Persistencia - IdentityModal:**

**Tabla:** `nv_accounts` (Admin DB)

| Campo               | Tipo    | Ejemplo            | Descripción   |
| ------------------- | ------- | ------------------ | ------------- |
| `account_id`        | uuid    | `abc-123`          | PK            |
| `dni`               | text    | `"12345678"`       | DNI Argentina |
| `identity_verified` | boolean | `true`             | Completado?   |
| `email`             | text    | `user@example.com` | Email         |
| `plan_key`          | text    | `"starter"`        | Plan actual   |

---

## 3️⃣ DESIGN STUDIO - Flujos

### 🎨 Agregar Sección

**Flujo Frontend:**

```
Usuario en Step5TemplateSelector
  ↓
Click "Add Section" → Selecciona "hero-advanced"
  ↓
Frontend: addSection()
  {
    config: currentDesignConfig,
    type: "hero-advanced",
    position: 2,
    planKey: "starter",  // User's current plan
    defaultProps: { title: "Hero", ... },
    minPlan: "growth"    // Section requires Growth+
  }
  ↓
Plan Validation:
  - Current sections: 3
  - Plan limit (starter): 5
  - 3 < 5 ✓ Count OK
  ↓
  - minPlan: "growth"
  - canAccessFeature("starter", "growth")?
  - starter < growth ✗ LOCKED
  ↓
Return: { error: "Esta sección requiere plan growth+..." }
  ↓
UI: Show UpsellModal
  - Feature: "hero-advanced"
  - Current: "starter"
  - Required: "growth"
  - Benefits list
  - CTA: "Actualizar a growth →"
```

**Sin Upgrade:**
Usuario cierra modal, sección no agregada

**Con Upgrade:**

```
Usuario hace upgrade → Plan becomes "growth"
  ↓
Retry addSection() con planKey = "growth"
  ↓
canAccessFeature("growth", "growth") ✓
  ↓
New section created:
  {
    id: "section-1735679234-x7k2m",
    type: "hero-advanced",
    props: { title: "Hero", subtitle: "...", ... }
  }
  ↓
designConfig.sections.splice(2, 0, newSection)
  ↓
State updated → UI rerenders con nueva sección
```

---

### 🔄 Reemplazar Sección

**Flujo:**

```
Usuario selecciona section "header-1"
  ↓
Click "Replace" → Selecciona "header-2"
  ↓
Frontend: replaceSection()
  {
    config: currentDesignConfig,
    sectionId: "section-123",
    newType: "header-2",
    defaultProps: { brandName: "", navigation: [] }
  }
  ↓
Prop Migration:
  - Old props: { title: "Mi Tienda", links: [...] }
  - Migration key: "header-2_from_header-1"
  - Mapping:
      brandName ← title
      navigation ← links
  ↓
Migrated props:
  {
    brandName: "Mi Tienda",    // From title
    navigation: [              // From links
      { label: "Inicio", href: "/" },
      ...
    ]
  }
  ↓
New section:
  {
    id: "section-123",         // Same ID
    type: "header-2",          // New type
    props: { brandName: "Mi Tienda", navigation: [...] }
  }
  ↓
Replace in config.sections array
  ↓
State updated → UI shows new header with migrated data
```

---

### 💾 Guardar Design Config

**Flujo Completo:**

```
Usuario edita design en Step5
  ↓
Click "Guardar" o "Siguiente"
  ↓
Frontend: api.updatePreferences(sessionId, {...})
  {
    design_config: {
      version: 1,
      page: "home",
      sections: [
        { id: "header-1", type: "header", props: {...} },
        { id: "hero-1", type: "hero", props: {...} },
        ...
      ]
    }
  }
  ↓
POST /onboarding/:sessionId/preferences
  ↓
Backend: OnboardingService.updatePreferences()
  ↓
1. Get account plan_key:
   SELECT plan_key FROM nv_accounts WHERE id = ?
   → planKey = "starter"
  ↓
2. Validate design_config:
   validateDesignConfigOrThrow(design_config, "starter")

   Checks:
   ✓ Structure: sections array exists
   ✓ Section count: 5 <= 5 (starter limit)
   ✓ Section types: all accessible for starter
   ✓ Section IDs: all present

   IF invalid → throw 400 Bad Request
   IF valid → continue
  ↓
3. Save to nv_onboarding:
   UPDATE nv_onboarding SET
     design_config = {...},
     selected_template_key = "normal",
     selected_palette_key = "sunset"
   WHERE account_id = ?
  ↓
Guardado exitoso → 200 OK
```

**Persistencia - Design Studio:**

**Tabla:** `nv_onboarding` (Admin DB)

```sql
CREATE TABLE public.nv_onboarding (
  account_id uuid PRIMARY KEY,
  state text,
  design_config jsonb,
  selected_template_key text,
  selected_palette_key text,
  selected_theme_override jsonb,
  progress jsonb,
  ...
);
```

**Datos Guardados:**

| Campo                     | Ejemplo                                        | Descripción                       |
| ------------------------- | ---------------------------------------------- | --------------------------------- |
| `account_id`              | `abc-123`                                      | PK                                |
| `design_config`           | `{"version":1,"page":"home","sections":[...]}` | Configuración completa del diseño |
| `selected_template_key`   | `"normal"`                                     | Template elegido                  |
| `selected_palette_key`    | `"sunset"`                                     | Paleta elegida                    |
| `selected_theme_override` | `{"--nv-primary":"#FF00AA"}`                   | Overrides de colores (Growth+)    |

**Ejemplo design_config:**

```json
{
  "version": 1,
  "page": "home",
  "sections": [
    {
      "id": "section-header-1",
      "type": "header",
      "props": {
        "title": "Mi Tienda",
        "links": [
          { "label": "Inicio", "href": "/" },
          { "label": "Productos", "href": "/products" }
        ],
        "logoUrl": "https://..."
      }
    },
    {
      "id": "section-hero-1",
      "type": "hero",
      "props": {
        "title": "Bienvenido",
        "subtitle": "Los mejores productos",
        "ctaText": "Ver Productos",
        "ctaHref": "/products",
        "backgroundImage": "https://..."
      }
    }
  ]
}
```

---

### 📤 Publicar Store

**Flujo:**

```
Usuario click "Publicar"
  ↓
POST /onboarding/:sessionId/publish
  ↓
Backend: OnboardingService.publishStore()
  ↓
1. Get onboarding data:
   SELECT * FROM nv_onboarding WHERE account_id = ?
  ↓
2. Final validation:
   validateDesignConfigOrThrow(design_config, plan_key)
  ↓
3. Create provisioning job:
   INSERT INTO provisioning_jobs
   (account_id, type, payload, status)
   VALUES (?, 'PUBLISH_STORE', {...}, 'pending')
  ↓
4. Worker picks up job:
   ProvisioningWorkerService.processJob()

   a) Sync to client_home_settings:
      INSERT INTO client_home_settings
      (client_id, template_key, design_config)
      VALUES (?, 'normal', {...})

   b) Sync to client_themes:
      INSERT INTO client_themes
      (client_id, template_key, overrides)
      VALUES (?, 'normal', theme_override)

   c) Persist custom palette (if exists):
      Check localStorage draft
      → INSERT INTO custom_palettes
        (client_id, palette_name, theme_vars)
  ↓
5. Mark job complete:
   UPDATE provisioning_jobs SET status = 'completed'
  ↓
6. Update account:
   UPDATE nv_accounts SET published = true
  ↓
Store live at: https://{slug}.novavision.app
```

**Persistencia Final:**

Datos distribuidos en 3 tablas:

**1. client_home_settings (Backend DB)**

```json
{
  "client_id": "abc-123",
  "template_key": "normal",
  "design_config": {
    "sections": [...]  // Full design
  }
}
```

**2. client_themes (Admin DB)**

```json
{
  "client_id": "abc-123",
  "template_key": "normal",
  "overrides": {
    "tokens": { "colors": {...} }
  }
}
```

**3. custom_palettes (Admin DB)** _(si aplica)_

```json
{
  "client_id": "abc-123",
  "palette_name": "Mi Paleta",
  "based_on_key": "sunset",
  "theme_vars": {
    "--nv-primary": "#FF00AA",
    "--nv-secondary": "#00AAFF"
  }
}
```

---

## 📊 Diagrama de Arquitectura Global

```
┌─────────────────────────────────────────────────────────────┐
│                    ADMIN PANEL (apps/admin)                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Step1: Slug Selection                                     │
│  Step2: Logo Upload                                        │
│  Step3: Catalog (Products)                                 │
│  Step4: Design Studio                                      │
│    └─ Template Selector                                    │
│    └─ Palette Selector                                     │
│    └─ Custom Palette Editor (Growth+)                      │
│    └─ Section Manager (Add/Replace/Remove)                 │
│  Step5: Publish                                            │
│                                                             │
└────────────┬────────────────────────────────────────────────┘
             │
             │ POST /onboarding/:id/preferences
             │ POST /themes/:clientId
             │ POST /palettes/custom
             │ POST /onboarding/:id/publish
             │
             ↓
┌─────────────────────────────────────────────────────────────┐
│                    API (apps/api - NestJS)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Guards:                                                    │
│    - TenantContextGuard                                    │
│    - MaintenanceGuard (503 if maintenance_mode=true)       │
│                                                             │
│  Services:                                                  │
│    - OnboardingService (design validation)                 │
│    - ThemesService (theme CRUD)                            │
│    - PalettesService (palette CRUD)                        │
│    - AccountsService (identity verification)               │
│                                                             │
│  Validators:                                               │
│    - design.validator (plan limits, section types)         │
│                                                             │
└────────────┬────────────────────────────────────────────────┘
             │
             │ Supabase Client (service_role)
             │
             ↓
┌─────────────────────────────────────────────────────────────┐
│                 ADMIN DB (Supabase Admin)                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Tables:                                                    │
│    - nv_accounts (user data, dni, plan_key)               │
│    - nv_onboarding (design_config, preferences)           │
│    - client_themes (template_key, overrides)              │
│    - backend_clusters (maintenance_mode, cluster_id)       │
│    - custom_palettes (Growth+ user palettes)              │
│    - palette_catalog (6 standard palettes)                │
│    - provisioning_jobs (async tasks)                       │
│                                                             │
│  RLS: Service role only for system tables                  │
│                                                             │
└────────────┬────────────────────────────────────────────────┘
             │
             │ Provisioning Worker
             │
             ↓
┌─────────────────────────────────────────────────────────────┐
│              BACKEND DB (Supabase Backend)                  │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Tables:                                                    │
│    - clients (client metadata)                             │
│    - client_home_settings (template_key, design_config)   │
│    - products (catalog)                                    │
│    - orders (transactions)                                 │
│    - cart (shopping cart)                                  │
│                                                             │
└────────────┬────────────────────────────────────────────────┘
             │
             │ Theme + Design data
             │
             ↓
┌─────────────────────────────────────────────────────────────┐
│                  WEB APP (apps/web - React)                 │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GET /themes/:clientId                                     │
│  GET /settings/home (template_key, design_config)         │
│    ↓                                                        │
│  createTheme(template_key, overrides)                      │
│    ↓                                                        │
│  toLegacyTheme(normalizedTheme)                            │
│    ↓                                                        │
│  <ThemeProvider theme={legacyTheme}>                       │
│    <HomeRouter> (renders based on template_key)           │
│      → TemplateFirst | TemplateFifth | ...                │
│  </ThemeProvider>                                          │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔑 Puntos Clave de Persistencia

### Theme System

- **Admin DB:** `client_themes` (template_key + overrides)
- **Patrón:** Delta storage (solo cambios del template)
- **Inmutabilidad:** Deep freeze en runtime

### Security

- **Admin DB:** `backend_clusters` (maintenance_mode)
- **Admin DB:** `nv_accounts` (dni, identity_verified)
- **Metadata:** pg_policies (RLS rules)

### Design Studio

- **Admin DB:** `nv_onboarding` (design_config durante wizard)
- **Backend DB:** `client_home_settings` (design_config post-publish)
- **Admin DB:** `custom_palettes` (paletas personalizadas Growth+)
- **Validación:** Server-side en cada save/publish

---

## 📈 Plan Limits Summary

| Feature         | Starter | Growth   | Pro |
| --------------- | ------- | -------- | --- |
| Sections        | 5       | 10       | 15  |
| Custom Palettes | 0       | 3        | ∞   |
| Theme Override  | ❌      | ✅       | ✅  |
| Pro Sections    | ❌      | Advanced | All |

---

## ✅ Checklist de Implementación

**Theme System:**

- [x] Normalized schema (types.ts)
- [x] Deep merge + freeze utilities
- [x] Templates (normal.ts)
- [x] Legacy adapter
- [x] ThemeProvider integration
- [x] Database schema (client_themes)
- [x] API endpoints (ThemesModule)

**Security:**

- [x] RLS scripts (admin + backend)
- [x] MaintenanceGuard implementation
- [x] backend_clusters routing
- [x] IdentityModal component
- [x] Identity API endpoints

**Design Studio:**

- [x] Section management utilities
- [x] UpsellModal component
- [x] Design validator
- [x] Backend validation integration
- [ ] Frontend integration (Step5)
- [ ] Custom palette publish hook
- [ ] QA hard path testing

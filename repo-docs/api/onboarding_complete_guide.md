# NovaVision Onboarding - Guía Completa

## 📋 Flujo de Onboarding Completo

### Paso a Paso

```
1. Usuario visita admin.novavision.app
   ↓
2. Email + Desired Slug
   POST /onboarding/start-draft
   → Crea nv_account (trial entitlements)
   → Crea nv_onboarding (state: draft_builder)
   → Guarda desired_slug en progress
   ↓
3. Logo Upload (opcional)
   POST /logo
   → S3 upload
   → URL en nv_onboarding.logo_url
   ↓
4. Catalog (productos)
   Opción A: AI Import (CSV)
   Opción B: Manual
   → Guarda en localStorage (draft)
   ↓
5. Design Studio
   - Template selection
   - Palette selection
   - Section management
   POST /onboarding/:id/preferences
   → design_config en nv_onboarding
   ↓
6. Checkout (Mercado Pago)
   POST /onboarding/:id/reserve-slug
   → Intenta reservar slug
   → Redirige a MP
   ↓
7. Payment Success
   Webhook MP → POST /mercadopago/webhook
   → Marca account.paid = true
   → Crea provisioning_job
   ↓
8. Identity Collection (DNI)
   IF identity_verified = false:
     → IdentityModal blocking
     → POST /accounts/identity
   ↓
9. Provisioning Worker
   → Sync design_config → client_home_settings
   → Sync theme → client_themes
   → Sync catalog → products table
   → Assign slug definitivo
   ↓
10. Store LIVE
    https://{slug}.novavision.app
```

---

## 🧪 Probar una tienda en local (sin Netlify Pro)

**Objetivo:** validar que una tienda resuelve por `slug` y/o `preview` en ambiente local, sin depender de dominios wildcard pagos en Netlify.

### ✅ Qué sí funciona en local

- Resolver por slug usando query param en localhost.
- Validar acceso `live` o `preview` contra la API.

### ❌ Qué no funciona en local

- `novavision-test.netlify.app` **no** resuelve slug ni custom domain sin Netlify Pro (no hay wildcard).

### 1) Configurar variables locales

**apps/web/.env.local**

- `VITE_API_URL_LOCAL=http://localhost:3000`

**apps/api/.env**

- `SUPABASE_URL=...`
- `SUPABASE_SERVICE_ROLE_KEY=...`

### 2) Levantar servicios

- API (apps/api): `npm run start:dev`
- Storefront (apps/web): `npm run dev`

### 3) Abrir tienda local por slug

- `http://localhost:5173?tenant={slug}`

> El storefront agrega el header `X-Tenant-Slug` automáticamente.

### 4) Si la tienda está en draft (no publicada)

- usar preview:
  `http://localhost:5173?tenant={slug}&preview={preview_token}`

> El `preview_token` se obtiene desde el Admin (vista previa / onboarding).

#### Obtener preview desde el dashboard

1. Ir al Dashboard Admin → ficha del cliente.
2. Usar el botón **Vista previa**.
3. Copiar el `preview_token` desde el link generado.

### 5) Verificación rápida

- `GET /store/config/{slug}` → 200 si está publicada.
- `GET /store/config/{slug}?preview=...` → 200 si preview válido.

## 👥 Roles y Capacidades

### 🔵 Cliente (Tenant Owner)

**Durante Onboarding:**

- ✅ Crear account
- ✅ Configurar design (dentro de plan limits)
- ✅ Seleccionar template/palette según plan
- ✅ Agregar productos
- ❌ No puede acceder a otras cuentas
- ❌ No puede modificar plan limits
- ❌ No puede ver datos de plataforma

**Post-Publicación:**

- ✅ Ver analytics (su tienda)
- ✅ Gestionar productos
- ✅ Ver órdenes
- ✅ Actualizar design (dentro de limits)
- ❌ No puede cambiar slug
- ❌ No puede acceder admin DB

**RLS:** Solo ve sus datos via `auth.uid()`

---

### 🔴 Admin (Platform Owner)

**Panel Admin:**

- ✅ Ver todas las cuentas
- ✅ Modificar plan de cualquier cuenta
- ✅ Activar/desactivar maintenance_mode
- ✅ Ver métricas globales
- ✅ Gestionar palette_catalog
- ✅ Crear/editar templates
- ✅ Asignar clusters
- ✅ Ver provisioning_jobs
- ✅ Ejecutar migraciones

**Configuración Premium:**

**1. Marcar Componente como Premium:**

```typescript
// apps/admin/src/utils/sectionRegistry.ts
export const SECTION_REGISTRY = {
  'hero-advanced': {
    name: 'Hero Avanzado',
    minPlan: 'growth',  // ← Aquí se define
    defaultProps: {...},
  },
  'analytics-dashboard': {
    name: 'Analytics',
    minPlan: 'pro',  // Solo Pro+
    defaultProps: {...},
  },
}
```

**2. Backend Validation:**

```typescript
// apps/api/src/onboarding/validators/design.validator.ts
const SECTION_PLAN_REQUIREMENTS = {
  'hero-advanced': 'growth',
  'analytics-dashboard': 'pro',
  // Agregar nuevos aquí
};
```

**3. Frontend Gating:**

```tsx
// Step5TemplateSelector.tsx
{
  sections.map((section) => {
    const locked =
      section.minPlan && !canAccessFeature(planKey, section.minPlan);

    return (
      <SectionCard locked={locked}>
        {locked && <LockIcon />}
        {locked && <Badge>{section.minPlan}+</Badge>}
      </SectionCard>
    );
  });
}
```

---

## 🎨 Configuración de Templates

### Template Existentes

```
apps/web/src/templates/
├── first/     (Template Classic)
├── fifth/     (Template Modern)
├── third/     (Template Business)
└── fourth/    (Template Minimal)
```

### Agregar Nuevo Template

**1. Crear Estructura:**

```bash
cd apps/web/src/templates
mkdir sixth
cd sixth
mkdir components pages
touch index.jsx
```

**2. Definir Theme Base:**

```typescript
// apps/web/src/theme/templates/sixth.ts
import type { Theme } from '../types';

export const sixthTemplate: Theme = {
  meta: {
    key: 'sixth',
    name: 'Template Elegant',
    version: 1,
    mode: 'light',
  },
  tokens: {
    colors: {
      primary: '#2C3E50',
      secondary: '#E74C3C',
      // ... resto
    },
    // ... typography, spacing, etc.
  },
  components: {
    header: { background: '#fff', ... },
    // ... 20+ componentes
  },
};
```

**3. Registrar en Index:**

```typescript
// apps/web/src/theme/index.ts
import { sixthTemplate } from './templates/sixth';

export const TEMPLATES = {
  normal: normalTemplate,
  fifth: fifthTemplate,
  sixth: sixthTemplate, // ← Nuevo
};

export type TemplateKey = keyof typeof TEMPLATES;
```

**4. Crear Preset:**

```typescript
// apps/admin/src/presets/presets.ts
export const TEMPLATE_PRESETS = {
  // ... existing
  elegant: {
    templateKey: 'sixth',
    paletteKey: 'midnight',
    sections: [
      { type: 'header', props: {...} },
      { type: 'hero', props: {...} },
      // Default layout
    ],
  },
};
```

**5. Migración DB:**

```sql
-- Agregar a allowed values
UPDATE palette_catalog
SET allowed_templates = array_append(allowed_templates, 'sixth')
WHERE palette_key IN ('sunset', 'ocean', 'forest');

-- Opcional: Template específico
INSERT INTO template_catalog (
  template_key,
  name,
  description,
  min_plan_key,
  is_active
) VALUES (
  'sixth',
  'Template Elegant',
  'Diseño elegante y sofisticado',
  'growth',  -- Requiere Growth+
  true
);
```

**6. Validación Backend:**

```typescript
// apps/api/src/onboarding/validators/design.validator.ts
const ALLOWED_TEMPLATES = [
  'normal',
  'fifth',
  'sixth', // ← Agregar
];
```

**7. HomeRouter Integration:**

```jsx
// apps/web/src/pages/HomeRouter.jsx
import TemplateSixth from '../templates/sixth';

const TEMPLATE_MAP = {
  normal: TemplateFirst,
  fifth: TemplateFifth,
  sixth: TemplateSixth, // ← Mapear
};
```

---

## 🔄 Proceso de Integración (CI/CD)

### Git Workflow

```bash
# 1. Crear feature branch
git checkout -b feature/template-sixth

# 2. Implementar (pasos anteriores)
# - Crear template files
# - Agregar theme definition
# - Actualizar registry
# - Tests

# 3. Commit
git add .
git commit -m "feat: add Template Sixth (Elegant design)"

# 4. Push
git push origin feature/template-sixth

# 5. Pull Request → main
# → CI ejecuta tests
# → Review code
# → Merge
```

### CI/CD Pipeline

```yaml
# .github/workflows/deploy.yml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - Checkout code
      - npm install
      - npm run lint
      - npm run test
      - npm run build # Verifica que compile

  deploy-admin:
    needs: test
    steps:
      - Deploy to Vercel (admin.novavision.app)
      - Invalidate CDN cache

  deploy-web:
    needs: test
    steps:
      - Deploy to Vercel (*.novavision.app)
      - Warm up cache

  migrate-db:
    needs: test
    steps:
      - Run migrations (if any)
      - Update configs
```

### Impacto en Rama Principal

**Archivos Modificados:**

```
apps/web/src/
  ├── theme/
  │   ├── templates/sixth.ts       [NEW]
  │   └── index.ts                 [MODIFIED]
  ├── templates/sixth/             [NEW DIR]
  └── pages/HomeRouter.jsx         [MODIFIED]

apps/admin/src/
  ├── presets/presets.ts           [MODIFIED]
  └── utils/sectionRegistry.ts     [MODIFIED]

apps/api/src/
  └── onboarding/validators/
      └── design.validator.ts      [MODIFIED]

apps/api/migrations/admin/
  └── ADMIN_XXX_template_sixth.sql [NEW]
```

**Zero Downtime:**

- Nuevos templates se agregan, no reemplazan
- Clientes existentes no afectados
- Rollback simple (revert commit)

---

## 🗄️ Datos en DB

### Durante Onboarding (Admin DB)

**nv_onboarding:**

```json
{
  "account_id": "abc-123",
  "state": "draft_builder",
  "design_config": {
    "version": 1,
    "page": "home",
    "sections": [...]
  },
  "selected_template_key": "sixth",
  "selected_palette_key": "midnight",
  "selected_theme_override": { "--nv-primary": "#custom" },
  "progress": {
    "desired_slug": "mi-tienda",
    "completed_steps": ["slug", "logo", "catalog"]
  }
}
```

### Post-Publicación

**client_home_settings (Backend DB):**

```json
{
  "client_id": "abc-123",
  "template_key": "sixth",
  "design_config": {...}  // Full config
}
```

**client_themes (Admin DB):**

```json
{
  "client_id": "abc-123",
  "template_key": "sixth",
  "overrides": {
    "tokens": { "colors": {...} }
  }
}
```

---

## 🛠️ Configuración Admin Panel

### 1. Plan Limits

**Tabla:** `plans`

```sql
UPDATE plans
SET features = jsonb_set(
  features,
  '{design, maxSections}',
  '15'
)
WHERE plan_key = 'pro';
```

**Frontend Mirror:** `sectionMigration.ts`

```typescript
export const PLAN_LIMITS = {
  pro: {
    maxSections: 15, // Sincronizar con DB
  },
};
```

### 2. Palette Gating

```sql
UPDATE palette_catalog
SET min_plan_key = 'growth'
WHERE palette_key = 'luxury';
```

### 3. Maintenance Mode

```sql
UPDATE backend_clusters
SET maintenance_mode = true
WHERE client_id = 'abc-123';
-- Bloquea todos los requests del cliente
```

### 4. Template Versioning

```sql
-- Pin client to specific version
UPDATE client_themes
SET template_version = 1
WHERE client_id = 'abc-123';

-- NULL = always latest
```

---

## 📊 Monitoreo

### Métricas Admin

```sql
-- Total accounts por plan
SELECT plan_key, COUNT(*)
FROM nv_accounts
GROUP BY plan_key;

-- Templates más usados
SELECT template_key, COUNT(*)
FROM client_home_settings
GROUP BY template_key;

-- Palettes más usadas
SELECT selected_palette_key, COUNT(*)
FROM nv_onboarding
WHERE state = 'published'
GROUP BY selected_palette_key;
```

---

## ✅ Checklist Nuevo Template

- [ ] Crear estructura de archivos
- [ ] Definir theme en templates/
- [ ] Registrar en TEMPLATES index
- [ ] Crear preset por defecto
- [ ] Migración DB (si requiere premium)
- [ ] Actualizar validators
- [ ] Integrar en HomeRouter
- [ ] Tests visuales (Chromatic/Percy)
- [ ] Documentar en README
- [ ] PR review
- [ ] Deploy a staging
- [ ] QA manual
- [ ] Merge a main
- [ ] Monitor analytics

---

## 🔐 Seguridad

**RLS Policies:**

- Cliente solo ve sus datos
- Admin ve todo
- Service role bypass RLS

**Validation:**

- Frontend: UX guidance
- Backend: Enforcement (can't bypass)

**Audit:**

```sql
-- Ver cambios de un cliente
SELECT * FROM audit_log
WHERE account_id = 'abc-123'
ORDER BY created_at DESC;
```

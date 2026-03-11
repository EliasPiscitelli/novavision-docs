# Plan de Validación y Tareas Pendientes - Completo

## 🎯 Objetivos

1. Validar flujos end-to-end (onboarding → publish)
2. Auditar localStorage vs DB persistence
3. Identificar y completar tareas pendientes
4. Garantizar integridad de datos

---

## 📋 TAREAS PENDIENTES

### Alta Prioridad (Debe Completarse)

#### 1. Step5 Section Management UI Integration

**Status:** Backend completo, frontend pendiente

**Archivos a Modificar:**

- `apps/admin/src/pages/BuilderWizard/steps/Step5TemplateSelector.tsx`

**Implementación Requerida:**

```tsx
// Import utilities
import { addSection, replaceSection, canAccessFeature } from '../../../utils/sectionMigration';
import { UpsellModal } from '../../../components/UpsellModal';

// Add state
const [showUpsell, setShowUpsell] = useState(false);
const [requiredPlan, setRequiredPlan] = useState('');
const [designConfig, setDesignConfig] = useState(initialConfig);

// Wire up handlers
const handleAddSection = (type, position) => {
  const result = addSection(designConfig, type, position, state.planKey, ...);
  if ('error' in result) {
    setShowUpsell(true);
  } else {
    setDesignConfig(result);
  }
};

// Render section library with lock icons
{sections.map(section => (
  <SectionCard locked={!canAccessFeature(planKey, section.minPlan)}>
    {locked && <LockIcon />}
  </SectionCard>
))}

// Upsell modal
{showUpsell && <UpsellModal ... />}
```

**Testing:**

- [ ] Starter: Ve solo sections básicas
- [ ] Intenta agregar 6ta sección → Bloqueado
- [ ] Growth: Ve sections avanzadas
- [ ] Pro: Ve todas las sections

**Estimado:** 2 horas

---

#### 2. Lint Errors Cleanup

**Error Principal:** CatalogLoader imageUrl type mismatch

```typescript
// apps/admin/src/pages/BuilderWizard/components/CatalogLoader.tsx:356
// Problem: imageUrl expects string[] but receives {url, order}[]

// Fix:
const product = {
  ...productData,
  imageUrl: productData.imageUrl.map((img) =>
    typeof img === "string" ? img : img.url
  ),
};
```

**Testing:**

- [ ] Catalog load sin errores TypeScript
- [ ] Images display correctamente

**Estimado:** 30 minutos

---

#### 3. AccountsService Import Fix

**Error:** Cannot find module './accounts.service'

**Fix:** Ya creado el archivo, verificar import path

```typescript
// apps/api/src/accounts/accounts.controller.ts
import { AccountsService } from './accounts.service'; // Verificar

path correcto
```

**Testing:**

- [ ] API compila sin errores
- [ ] GET /accounts/me retorna datos

**Estimado:** 15 minutos

---

### Media Prioridad (Mejoras)

#### 4. QA Hard Path - Plan Gating

**Scenarios:**

**Starter Plan:**

```
1. Create account con plan Starter
2. Access Step5 Template Selector
3. Intentar agregar 6ta sección
   Expected: Modal upsell aparece
4. Click section premium (analytics-dashboard)
   Expected: Lock icon visible + upsell
5. Save design con 5 sections
   Expected: 200 OK
6. Intentar save con 6 sections (via API bypass)
   Expected: 400 Bad Request "Max 5 sections"
```

**Growth Plan:**

```
1. Create account con plan Growth
2. Crear custom palette
   Expected: Editor disponible
3. Save custom palette
   Expected: Draft en localStorage
4. Publish store
   Expected: Palette persiste en custom_palettes table
5. Verificar max 3 custom palettes
   Expected: 4ta rechazada
6. Add 10 sections
   Expected: OK
7. Add 11th section
   Expected: Bloqueado
```

**Pro Plan:**

```
1. Create account con plan Pro
2. Create unlimited custom palettes
   Expected: Sin límite
3. Add 15 sections
   Expected: OK
4. Access all Pro sections
   Expected: Sin locks
```

**Estimado:** 2 horas testing

---

#### 5. Identity Modal Testing

**Flow:**

```
1. New user completes payment
2. publishStore() success
3. GET /accounts/me → identity_verified = false
4. IdentityModal appears (blocking)
5. User enters DNI: "12345678"
6. POST /accounts/identity
7. DB update: identity_verified = true
8. Modal closes
9. Second login
   Expected: Modal NOT shown
```

**Edge Cases:**

- [ ] Invalid DNI (6 digits) → Error message
- [ ] Already verified → Skip modal
- [ ] API error → Retry logic

**Estimado:** 1 hora

---

## 🔍 VALIDACIÓN DE FLUJOS COMPLETOS

### Flujo 1: Onboarding Draft → Publish (Completo)

```
┌─────────────────────────────────────────────────────────┐
│ PASO 1: EMAIL + SLUG                                   │
└─────────────────────────────────────────────────────────┘

User Input:
  - email: "test@example.com"
  - slug: "mi-tienda"

Frontend (BuilderWizard Step1):
  POST /onboarding/start-draft
  Body: { email, desired_slug: "mi-tienda" }

Backend (OnboardingService):
  1. Create nv_account (Supabase Auth)
  2. Create nv_onboarding:
     - state: 'draft_builder'
     - progress: { desired_slug: "mi-tienda" }
  3. Return session_id + builderToken

localStorage:
  wizard_state: {
    sessionId: "abc-123",
    builderToken: "token...",
    slug: "mi-tienda",
    currentStep: 2
  }

Database (Admin):
  nv_accounts:
    - id: uuid
    - email: "test@example.com"
    - slug: null (aún no asignado)

  nv_onboarding:
    - account_id: uuid
    - state: "draft_builder"
    - progress: { desired_slug: "mi-tienda" }

✅ VERIFICAR:
  - sessionId en localStorage
  - nv_onboarding row existe
  - desired_slug guardado en progress


┌─────────────────────────────────────────────────────────┐
│ PASO 2: LOGO UPLOAD (OPCIONAL)                         │
└─────────────────────────────────────────────────────────┘

User Action:
  - Upload logo.png
  - OR Click "Saltar"

Frontend (Step2Logo):
  IF upload:
    POST /logo
    FormData: { file: logo.png }

  updateState({ logoUrl: uploadedUrl, currentStep: 3 })

localStorage:
  wizard_state: {
    ...prev,
    logoUrl: "https://storage.../logo.png",
    currentStep: 3
  }

Database:
  nv_onboarding:
    - logo_url: "https://storage.../logo.png"

✅ VERIFICAR:
  - Logo visible en preview
  - URL en localStorage + DB match


┌─────────────────────────────────────────────────────────┐
│ PASO 3: CATALOG (AI o Manual)                          │
└─────────────────────────────────────────────────────────┘

User Action:
  - Opción A: Upload CSV → AI import
  - Opción B: Manual product loader

Frontend (CatalogLoader):
  AI Import:
    POST /products/ai-import
    FormData: { csv: file }

  Manual:
    Local state: products = [...]

localStorage:
  products_draft: [
    {
      name: "Producto 1",
      price: 1000,
      imageUrl: ["url1", "url2"],
      ...
    },
    ...
  ]

Database:
  ❌ NOT saved yet (draft only)

updateState({ currentStep: 4 })

✅ VERIFICAR:
  - products_draft en localStorage
  - Preview muestra productos
  - Longitud > 0


┌─────────────────────────────────────────────────────────┐
│ PASO 4: DESIGN (Template + Palette + Sections)         │
└─────────────────────────────────────────────────────────┘

User Actions:
  1. Select templateKey: "normal"
  2. Select paletteKey: "sunset"
  3. (Growth+) Customize colors → theme_override
  4. (Pro) Add/Remove sections → design_config

Frontend (Step5TemplateSelector):
  POST /onboarding/:id/preferences
  Body: {
    selected_template_key: "normal",
    selected_palette_key: "sunset",
    selected_theme_override: { "--nv-primary": "#FF00AA" },
    design_config: {
      version: 1,
      page: "home",
      sections: [...]
    }
  }

Backend Validation:
  validateDesignConfigOrThrow(design_config, plan_key)
  - Check section count <= plan limit
  - Check section types accessible

localStorage:
  wizard_state: {
    ...prev,
    selectedTemplate: "normal",
    selectedPalette: "sunset",
    themeOverride: {...},
    designConfig: {...},
    currentStep: 5
  }

Database (Admin):
  nv_onboarding:
    - selected_template_key: "normal"
    - selected_palette_key: "sunset"
    - selected_theme_override: {...}
    - design_config: {...}

✅ VERIFICAR:
  - Validation pasa (no 400 error)
  - design_config en DB
  - localStorage sync


┌─────────────────────────────────────────────────────────┐
│ PASO 5: PAYMENT + PUBLISH                              │
└─────────────────────────────────────────────────────────┘

User Action:
  1. Select plan (Starter/Growth/Pro)
  2. Click "Pagar con Mercado Pago"

Frontend:
  POST /onboarding/:id/reserve-slug
    → Returns MP checkout URL

  Redirect to Mercado Pago

  MP Payment Success
    → Webhook: POST /mercadopago/webhook

  POST /onboarding/:id/publish

Backend (publishStore):
  1. Mark job: PROVISION_CLIENT
  2. Worker processes:
     a) Create client in backend DB
     b) Sync design_config → client_home_settings
     c) Sync theme → client_themes
     d) syncCustomPalette() if custom-*
     e) Assign slug definitivo
  3. Mark identity check needed

Frontend (BuilderWizard):
  GET /accounts/me
    → identity_verified = false?
    → Show IdentityModal

User Input: DNI "12345678"
  POST /accounts/identity

  Modal closes
  Redirect to dashboard

localStorage:
  ❌ wizard_state cleared (localStorage.removeItem)

Database (Admin):
  nv_accounts:
    - slug: "mi-tienda" (assigned)
    - dni: "12345678"
    - identity_verified: true
    - client_id_backend: uuid

  nv_onboarding:
    - state: "published"

  custom_palettes (if Growth+):
    - client_id: uuid
    - palette_name: "Mi Paleta"
    - theme_vars: {...}

Database (Backend):
  clients:
    - id: uuid
    - slug: "mi-tienda"

  client_home_settings:
    - client_id: uuid
    - template_key: "normal"
    - design_config: {...}

  client_themes:
    - client_id: uuid
    - template_key: "normal"
    - overrides: {...}

✅ VERIFICAR:
  - Slug asignado definitivo
  - Store accesible: https://mi-tienda.novavision.app
  - Theme CSS vars aplicadas
  - Sections renderizadas
  - Products visibles
  - custom_palettes row (si Growth+)
  - identity_verified = true
```

---

## 💾 AUDIT localStorage vs Database

### localStorage Keys Usados

```javascript
// apps/admin/src/context/WizardContext.tsx

localStorage Keys:
1. "wizard_state" - Estado completo del wizard
   {
     sessionId: string,
     builderToken: string,
     slug: string,
     logo Url: string?,
     currentStep: number,
     selectedTemplate: string?,
     selectedPalette: string?,
     themeOverride: object?,
     designConfig: object?,
     planKey: string?,
     selectedPlan: string?,
     selectedCycle: string?
   }

2. "products_draft" - Productos en borrador
   Product[]

3. "custom_palette_draft" - Paleta personalizada temporal
   {
     palette_name: string,
     based_on_key: string,
     theme_vars: object
   }
```

### Persistencia Strategy

| Dato             | localStorage | nv_onboarding (DB)         | Cuándo Sync   | Post-Publish              |
| ---------------- | ------------ | -------------------------- | ------------- | ------------------------- |
| sessionId        | ✅           | ✅ (column: session_id)    | Inmediato     | Clear                     |
| builderToken     | ✅           | ❌                         | N/A           | Clear                     |
| slug             | ✅           | ✅ (progress.desired_slug) | Inmediato     | Clear                     |
| logoUrl          | ✅           | ✅ (logo_url)              | On upload     | → clients.logo            |
| selectedTemplate | ✅           | ✅                         | On Step4 save | → client_home_settings    |
| selectedPalette  | ✅           | ✅                         | On Step4 save | → client_home_settings    |
| themeOverride    | ✅           | ✅                         | On Step4 save | → client_themes.overrides |
| designConfig     | ✅           | ✅                         | On Step4 save | → client_home_settings    |
| products_draft   | ✅           | ❌                         | Never         | → products table          |
| custom_palette   | ✅           | ❌                         | Never         | → custom_palettes         |

**Limpieza Post-Publish:**

```typescript
// BuilderWizard/index.tsx línea 154
localStorage.removeItem("wizard_state");
localStorage.removeItem("products_draft");
localStorage.removeItem("custom_palette_draft");
```

---

## 🧪 TESTING CHECKLIST

### Pre-Deploy Validation

**Backend:**

- [ ] npm run lint (0 errors)
- [ ] npm run build (success)
- [ ] All migrations applied
- [ ] RLS policies active
- [ ] MaintenanceGuard registered

**Frontend (Admin):**

- [ ] npm run lint (resolve imageUrl type)
- [ ] npm run build
- [ ] localStorage audit passed
- [ ] All steps functional

**Frontend (Web):**

- [ ] npm run lint
- [ ] npm run build
- [ ] Theme system backward compat
- [ ] Templates render correctly

---

### Manual Testing Flows

**Flow A: Starter Plan - Happy Path**

```
1. Start onboarding
2. Enter email + slug
3. Skip logo
4. Manual catalog (3 products)
5. Select template "normal" + palette "ocean"
6. Add 5 sections (max)
7. Try add 6th → BLOCKED ✓
8. Proceed to payment
9. Pay (Starter $20)
10. Check identity_verified prompt
11. Enter DNI
12. Visit store URL
    Expected: functional store
```

**Flow B: Growth Plan - Custom Palette**

```
1-6. Same as Flow A
7. Open custom palette editor
8. Modify colors
9. Save draft (localStorage)
10. Publish
11. Verify custom_palettes table
    Expected: Row exists with theme_vars
12. Reload wizard
    Expected: Custom palette available
```

**Flow C: Pro Plan - Max Sections**

```
1-6. Same as Flow A
7. Add 15 sections
8. Verify all pro sections unlocked
9. Publish
10. Check client_home_settings.design_config
    Expected: 15 sections saved
```

---

## 📊 Success Criteria

### Phase 1: Backend Integrity

- [ ] All lint errors resolved
- [ ] All modules import correctly
- [ ] API endpoints return expected responses
- [ ] Database constraints enforced
- [ ] RLS policies block unauthorized access

### Phase 2: Flow Completion

- [ ] Onboarding completes without errors
- [ ] Data persists correctly (localStorage → DB)
- [ ] Payment integration functional
- [ ] Worker provisions successfully
- [ ] Identity collection works

### Phase 3: Plan Gating

- [ ] Starter blocked at 5 sections
- [ ] Growth can create 3 custom palettes
- [ ] Pro has unlimited access
- [ ] Backend validation prevents bypass

### Phase 4: Data Integrity

- [ ] localStorage cleared post-publish
- [ ] All draft data migrated to DB
- [ ] Custom palettes persisted
- [ ] Theme overrides applied
- [ ] Store accessible and functional

---

## 🚀 Implementation Order

1. **Fix Lint Errors** (30 min)

   - CatalogLoader imageUrl type
   - AccountsService import path

2. **Complete Step5 UI** (2h)

   - Section management integration
   - Upsell modal wiring
   - Lock icons

3. **Manual QA** (2h)

   - Test all three plans
   - Validate localStorage cleanup
   - Verify DB persistence

4. **Staging Deploy** (1h)

   - Deploy API
   - Deploy Admin
   - Deploy Web
   - Run smoke tests

5. **Production Monitor** (ongoing)
   - Watch provisioning logs
   - Monitor error rates
   - Track feature adoption

---

## 📝 Post-Completion Tasks

- [ ] Update task.md con estado final
- [ ] Crear migration guide para users existentes
- [ ] Documentar troubleshooting común
- [ ] Setup monitoring alerts (Sentry/LogRocket)
- [ ] Performance profiling (Lighthouse)

---

**Total Estimado:** 6-8 horas adicionales  
**Prioridad:** Alta (bloquea staging deployment)  
**Owner:** TBD  
**Target Date:** 2025-01-02

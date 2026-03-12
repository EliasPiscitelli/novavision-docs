# Plan: Paridad y Unificación — Diseño de Tienda ↔ Onboarding Step 4

- Fecha: 2026-03-11
- Autor: GitHub Copilot (Principal Frontend/Fullstack Architect)
- Rama base: feature/automatic-multiclient-onboarding
- Repos: Web (templatetwo), API (templatetwobe), Admin (novavision), Docs
- Estado: diagnóstico completo + implementación por fases
- Precursor: PLAN_STORE_DESIGN_STEP4_SELF_SERVE_EDITOR.md (contexto UX)

---

## 1. Diagnóstico real (Fase 1 — Auditoría)

### 1.1 Inventario de registries y catálogos

El sistema tiene **cuatro capas** que definen qué templates y secciones existen:

| Capa | Archivo | Alcance | Plan keys |
|------|---------|---------|-----------|
| Web sectionCatalog | `apps/web/src/registry/sectionCatalog.ts` | 69 secciones, 8 templates | `starter / growth / enterprise` |
| Admin sectionCatalog | `apps/admin/src/registry/sectionCatalog.ts` | 69 secciones, 8 templates | `starter / growth / pro` |
| API registry | `apps/api/src/home/registry/sections.ts` | ~8 tipos genéricos (sin variantes) | `starter / growth / enterprise` |
| API featureCatalog | `apps/api/src/plans/featureCatalog.ts` | Features de alto nivel por plan | `starter / growth / enterprise` |

**Fuentes adicionales:**

| Artefacto | Archivo | Función |
|-----------|---------|---------|
| Template manifest | `apps/web/src/templates/manifest.js` | Metadata de 8 templates (nombre, status, features) |
| Templates lazy map | `apps/web/src/registry/templatesMap.ts` | Lazy imports de componentes React para 8 templates |
| Section components | `apps/web/src/registry/sectionComponents.tsx` | Imports React de secciones para render |
| Onboarding presets | `apps/admin/src/services/builder/designSystem.ts` | PRESET_CONFIGS por template, SECTION_CONSTRAINTS, validateInsert |
| Web presets | `apps/web/src/components/admin/StoreDesignSection/previewPresetSections.js` | Presets demo para cada template |
| Compatibilidad | `apps/web/src/components/admin/StoreDesignSection/compatibility.js` | resolveTargetKey, evaluateTemplateCompatibility |
| Plan gating | `apps/admin/src/pages/BuilderWizard/utils/planGating.ts` | canAccessPlanTier, getIncompatibilities |
| Credit service | `apps/api/src/storefront-actions/storefront-action-credits.service.ts` | Consumo idempotente de créditos on_save |
| Home settings | `apps/api/src/home/home-settings.service.ts` | upsertTemplate, updateIdentity con créditos |

### 1.2 Diferencias concretas entre catálogos

#### A) Plan tier naming inconsistency (32 keys afectados)

**Admin usa `"pro"` donde Web usa `"enterprise"`.**

Ejemplo: `header.fifth` → Web: `enterprise`, Admin: `pro`.

Impacto: la normalización se hace runtime vía `normalizePlanKey()` en frontend, pero genera confusión en:
- Step 4 usa `"pro"` del admin sectionCatalog
- Store Design usa `"enterprise"` del web sectionCatalog
- API usa `"enterprise"`

**Esto NO causa bugs de runtime** (el normalizer los unifica), pero sí dificulta mantenimiento y genera discrepancias al agregar features nuevas.

#### B) API registry incompleto — solo `type`, no `componentKey`

| Aspecto | API (home_sections) | Onboarding (Step 4) | Store Design (Web) |
|---------|--------------------|--------------------|-------------------|
| Clave de sección | `type` (genérico: "hero", "faq") | `componentKey` ("hero.second", "content.faq.third") | `componentKey` (igual que Step 4) |
| Variantes | `new_type` (parcial) | Completo con variantes | Completo con variantes |
| Persistencia | `home_sections` table (type + props JSONB) | localStorage / API state (designConfig) | home_sections + draft local |
| Gating | Por `type` + plan limits count | Por `componentKey` + planTier metadata | Mixto: registry API + sectionCatalog FE |

**Consecuencia:** cuando Store Design persiste una sección, pierde la información de variante (`componentKey`). Al recargar, se resuelve por fallback y puede mostrar la variante `.first` en lugar de la elegida.

#### C) Catálogo de keys idéntico en conteo

Los 69 section keys son idénticos entre Web y Admin. **No faltan keys en ningún catálogo.** El problema real es:

1. La **presentación** en Store Design no muestra todas las secciones de forma explorable (las muestra filtradas por compatibilidad con template actual)
2. La **persistencia** pierde variante al guardar via API

### 1.3 Causa raíz concreta de cada problema reportado

| # | Problema reportado | Causa raíz | Archivo(s) |
|---|-------------------|------------|------------|
| 1 | "Catálogo incompleto de componentes" | Store Design filtra secciones por template actual; no muestra catálogo exploratorio de TODOS los templates | `StoreDesignSection/index.jsx` → `structureCatalog` useMemo |
| 2 | "No refleja todos los componentes de todos los templates" | El filtro de compatibilidad (`evaluateTemplateCompatibility`) oculta secciones de otros templates | `compatibility.js` → `resolveSectionTargetKey()` |
| 3 | "No permite intercambiar estructura como onboarding" | API persiste por `type` no por `componentKey`; variante se pierde al guardar | `home-sections.service.ts`, DTO sin `componentKey` |
| 4 | "Separación plan/addon/bloqueado confusa" | La UI tiene la lógica pero el copy/UX no distingue claramente las 3 rutas (plan, crédito, compra) | `StoreDesignSection/index.jsx` → `missingRequiredAddons` |
| 5 | "Video aparece como Enterprise" | **FALSO** — video está correctamente como `growth` en ambos catálogos. Si aparece como Enterprise, es un bug de presentación o confusión con `"pro"` del admin sectionCatalog que no se normaliza visualmente | Admin sectionCatalog usa `"pro"` |
| 6 | "Maps deben estar disponibles para todos" | Maps no es sección standalone; está embebido en `content.contact.*` con `showMap: true`. Todas las variantes starter incluyen mapUrl | Correcto: `content.contact.first/second/third` son starter |
| 7 | "No hay CTA contextual al addon correcto" | La lógica de `missingRequiredAddons` existe pero el UI la presenta como banner genérico, no como CTA específico por acción | `StoreDesignSection/index.jsx` → `commercialSummary` |

### 1.4 Conclusión diagnóstica

**No hay componentes faltantes en los catálogos.** Los 69 keys son consistentes.

Los problemas reales son:

1. **UX de exploración**: Store Design solo muestra secciones compatibles con el template actual, no un catálogo completo cross-template
2. **Persistencia parcial**: API no soporta `componentKey` → variante se pierde → fallback a `.first`
3. **Naming inconsistente**: `"pro"` vs `"enterprise"` dificulta comunicación visual
4. **CTA comercial genérico**: la lógica existe pero el copy/UX no es contextual por acción específica
5. **Ausencia de sección Maps standalone**: está embebido en contact (es decisión de diseño, no bug)

---

## 2. Diseño objetivo (Fase 2 — Arquitectura)

### 2.1 Fuente única de verdad: Unified Section Registry

Propuesta: un módulo compartido que ambos (Web y Admin) importen, eliminando duplicación.

#### Ubicación propuesta

```
apps/web/src/registry/
├── sectionCatalog.ts          ← FUENTE DE VERDAD (ya existente, se refactoriza)
├── sectionComponents.tsx      ← imports React (sin cambios)
├── templatesMap.ts            ← lazy imports (sin cambios)
└── types.ts                   ← NUEVO: tipos compartidos
```

Admin deja de mantener su propia copia y la importa (o se genera un paquete NPM interno, pero dado que los repos son independientes, la regla es **copiar** — se implementa un script de sync).

#### Normalización de plan keys

**Decisión: usar `"enterprise"` como valor canónico.** Eliminar `"pro"` de Admin.

### 2.2 Tipos e interfaces propuestos

```typescript
// ══════════════════════════════════════════════
// FILE: apps/web/src/registry/types.ts (NUEVO)
// ══════════════════════════════════════════════

// ── Plan hierarchy ──
export type PlanTier = 'starter' | 'growth' | 'enterprise';

export const PLAN_HIERARCHY: Record<PlanTier, number> = {
  starter: 1,
  growth: 2,
  enterprise: 3,
};

// ── Section types ──
export type SectionType =
  | 'header' | 'hero' | 'banner' | 'catalog'
  | 'features' | 'faq' | 'contact' | 'footer'
  | 'testimonials' | 'marquee' | 'newsletter';

// ── Template Manifest ──
export interface TemplateManifest {
  id: string;                          // 'first', 'second', ..., 'eighth'
  templateKey: string;                  // 'template_1', ..., 'template_8'
  name: string;                         // 'Classic Store', 'Drift Premium'
  description: string;
  status: 'stable' | 'beta' | 'deprecated';
  minPlan: PlanTier;
  features: string[];                   // ['sticky-header', 'video-support', ...]
  supportsSections: boolean;
  thumbnailUrl: string;
  defaultSections: SectionSlot[];       // preset sections for this template
  compatibleSectionFamilies: string[];  // keys of section families this template supports
}

// ── Section Definition ──
export interface SectionDefinition {
  key: string;                          // 'hero.video.background', 'content.faq.third'
  name: string;                         // 'Hero Video Inmersivo'
  type: SectionType;                    // 'hero'
  family: string;                       // 'hero.video' (grouping key)
  planTier: PlanTier;                   // 'growth'
  templateAffinity: string[];           // ['fourth', 'fifth'] — templates donde encaja nativamente
  thumbnailUrl: string;
  defaultProps: Record<string, unknown>;
  capabilities: SectionCapability[];    // ['video', 'map', 'carousel', 'grid']
  describe?: (props: Record<string, unknown>) => string;
}

export type SectionCapability = 
  | 'video' | 'map' | 'carousel' | 'grid' 
  | 'parallax' | 'animation' | 'newsletter'
  | 'testimonials' | 'marquee';

// ── Section Variant (within a family) ──
export interface SectionVariant {
  key: string;                          // 'hero.second'
  familyKey: string;                    // 'hero'
  variantId: string;                    // 'second'
  name: string;                         // 'Hero Moderno'
  planTier: PlanTier;
  thumbnailUrl: string;
}

// ── Section Slot (persisted instance) ──
export interface SectionSlot {
  id: string;                           // UUID
  type: SectionType;
  componentKey: string;                 // 'hero.video.background'
  props: Record<string, unknown>;
  sortIndex: number;
  hidden?: boolean;
}

// ── Design Action (consumable action) ──
export type DesignActionCode =
  | 'template_change'
  | 'theme_change'
  | 'structure_edit'
  | 'component_change'
  | 'tier_surcharge_growth'
  | 'tier_surcharge_enterprise';

export interface DesignAction {
  code: DesignActionCode;
  addonKey: string;                     // 'ws_action_template_change'
  name: string;                         // 'Cambio de Template'
  description: string;
  consumptionStrategy: 'on_save';       // siempre on_save
  targetResourceType: 'template' | 'theme' | 'structure' | 'component';
  priceDisplay?: string;                // '$29 USD' (from addon catalog)
}

// ── Design Entitlement (resolved state) ──
export type EntitlementStatus =
  | 'included_in_plan'                  // Incluido en tu plan
  | 'requires_plan_upgrade'             // Requiere upgrade de plan
  | 'requires_purchase'                 // Requiere compra única
  | 'already_purchased'                 // Ya desbloqueado por compra
  | 'not_compatible'                    // No compatible con este template
  | 'preview_only';                     // Disponible en preview pero no aplicable

export interface DesignEntitlement {
  targetKey: string;                    // section key, template key, o palette key
  status: EntitlementStatus;
  requiredPlan?: PlanTier;              // si status es 'requires_plan_upgrade'
  requiredAddonKey?: string;            // si status es 'requires_purchase'
  requiredAddonName?: string;           // 'Cambio de Template'
  requiredAddonPrice?: string;          // '$29 USD'
  availableCredits?: number;            // créditos disponibles para esta acción
  ctaLabel?: string;                    // 'Comprá un cambio de template'
  ctaAction?: 'open_addon_store' | 'upgrade_plan' | 'purchase_addon';
  ctaTarget?: string;                   // addon_key o plan_key
}

// ── Addon ↔ Design Action Mapping ──
export interface AddonConsumableMapping {
  addonKey: string;                     // 'ws_action_template_change'
  actionCode: DesignActionCode;         // 'template_change'
  editorAction: string;                 // 'Cambiar template completo'
  grantsCredits: number;                // 1
  description: string;                  // 'Permite seleccionar y aplicar otro template'
  isPermanent: boolean;                 // false (consumable)
  affectedSurface: 'store_design';
}

// ── Resolver de entitlement ──
export interface EntitlementResolver {
  canAccessSection(sectionKey: string, currentPlan: PlanTier, purchasedAddons: string[]): DesignEntitlement;
  canChangeTemplate(currentPlan: PlanTier, targetTemplatePlan: PlanTier, credits: CreditBalance): DesignEntitlement;
  canChangeTheme(currentPlan: PlanTier, targetPalettePlan: PlanTier, credits: CreditBalance): DesignEntitlement;
  canAddSlot(currentPlan: PlanTier, currentSlotCount: number, credits: CreditBalance): DesignEntitlement;
  canEditStructure(credits: CreditBalance): DesignEntitlement;
}

export interface CreditBalance {
  [addonKey: string]: number;           // { 'ws_action_template_change': 2 }
}

// ── Section Constraints (shared) ──
export interface SectionConstraint {
  type: SectionType;
  min: number;
  max: number;
  fixed?: 'first' | 'last';
}

export const SECTION_CONSTRAINTS: Record<SectionType, SectionConstraint> = {
  header:       { type: 'header',       min: 1, max: 1, fixed: 'first' },
  footer:       { type: 'footer',       min: 1, max: 1, fixed: 'last' },
  hero:         { type: 'hero',         min: 0, max: 1 },
  banner:       { type: 'banner',       min: 0, max: 3 },
  catalog:      { type: 'catalog',      min: 0, max: 3 },
  faq:          { type: 'faq',          min: 0, max: 1 },
  contact:      { type: 'contact',      min: 0, max: 2 },
  features:     { type: 'features',     min: 0, max: 3 },
  testimonials: { type: 'testimonials', min: 0, max: 1 },
  marquee:      { type: 'marquee',      min: 0, max: 1 },
  newsletter:   { type: 'newsletter',   min: 0, max: 1 },
};
```

### 2.3 Addon ↔ Action mapping canónico

```typescript
// ══════════════════════════════════════════════
// MAPPING CANÓNICO: 1 addon = 1 acción del editor
// ══════════════════════════════════════════════

export const ADDON_ACTION_MAP: AddonConsumableMapping[] = [
  {
    addonKey: 'ws_action_template_change',
    actionCode: 'template_change',
    editorAction: 'Cambiar template completo',
    grantsCredits: 1,
    description: 'Permite seleccionar y aplicar otro template completo a la tienda',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
  {
    addonKey: 'ws_action_theme_change',
    actionCode: 'theme_change',
    editorAction: 'Cambiar/personalizar theme',
    grantsCredits: 1,
    description: 'Permite cambiar la paleta de colores o personalizar el theme actual',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
  {
    addonKey: 'ws_action_structure_edit',
    actionCode: 'structure_edit',
    editorAction: 'Agregar slot / nueva sección',
    grantsCredits: 1,
    description: 'Permite insertar una nueva sección en la home de la tienda',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
  {
    addonKey: 'ws_action_component_change',
    actionCode: 'component_change',
    editorAction: 'Cambiar estructura de sección existente',
    grantsCredits: 1,
    description: 'Permite reemplazar el tipo/layout de una sección ya existente',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
  {
    addonKey: 'ws_extra_growth_visual_asset',
    actionCode: 'tier_surcharge_growth',
    editorAction: 'Recargo visual Growth',
    grantsCredits: 1,
    description: 'Permite usar un asset visual de tier Growth desde plan Starter',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
  {
    addonKey: 'ws_extra_enterprise_visual_asset',
    actionCode: 'tier_surcharge_enterprise',
    editorAction: 'Recargo visual Enterprise',
    grantsCredits: 1,
    description: 'Permite usar un asset visual de tier Enterprise desde un plan inferior',
    isPermanent: false,
    affectedSurface: 'store_design',
  },
];
```

---

## 3. Reglas de plan validadas

### 3.1 Templates por plan

| Template | ID | Plan mínimo |
|----------|-----|------------|
| Classic Store | first / template_1 | starter |
| Modern Grid | second / template_2 | starter |
| Boutique | third / template_3 | starter |
| Startup | fourth / template_4 | growth |
| Industrial | fifth / template_5 | enterprise |
| Drift Premium | sixth / template_6 | enterprise |
| Vanguard | seventh / template_7 | enterprise |
| Lumina | eighth / template_8 | enterprise |

### 3.2 Secciones por plan (resumen)

| Sección | Starter | Growth | Enterprise |
|---------|---------|--------|-----------|
| Headers 1–3 | ✅ | ✅ | ✅ |
| Header 4 | — | ✅ | ✅ |
| Header 5+ | — | — | ✅ |
| Heroes 1–3 | ✅ | ✅ | ✅ |
| Hero Video Background | — | ✅ | ✅ |
| Hero 4+ | — | ✅/✅ | ✅ |
| Banner Video Spotlight | — | ✅ | ✅ |
| Catalog Carousels (básicos) | ✅ | ✅ | ✅ |
| Catalog Grids | — | ✅ | ✅ |
| Catalog Showcase 6–8 | — | — | ✅ |
| Features/Services (todas) | ✅ | ✅ | ✅ |
| FAQ (todas variantes) | ✅ | ✅ | ✅ |
| Contact (todas + mapa) | ✅ | ✅ | ✅ |
| Footer (todas variantes) | ✅ | ✅ | ✅ |
| Testimonials | — | — | ✅ |
| Marquee | — | — | ✅ |
| Newsletter | — | — | ✅ |

### 3.3 Reglas específicas validadas

- **Maps**: embebidos en contact sections. Disponibles desde **starter** (correcto).
- **Video**: `hero.video.background` y `banner.video.spotlight` → **growth** (correcto, no enterprise).
- **Testimonials, Marquee, Newsletter**: **enterprise only** (correcto).

---

## 4. Fases de implementación

### Fase 1 — Unificación de catálogos y normalización (BE + FE)

**Objetivo:** fuente única de verdad para secciones y plan tiers.

#### 4.1.1 Normalizar admin sectionCatalog

**Archivo:** `apps/admin/src/registry/sectionCatalog.ts`
**Cambio:** reemplazar `"pro"` → `"enterprise"` en 32 entries.

```diff
- planTier: "pro",
+ planTier: "enterprise",
```

**Archivos afectados:**
- `apps/admin/src/registry/sectionCatalog.ts`
- `apps/admin/src/pages/BuilderWizard/utils/planGating.ts` (ya maneja enterprise, verificar)

**Riesgo:** bajo — el normalizer ya convierte "pro" a "enterprise", pero eliminar la divergencia previene bugs futuros.

#### 4.1.2 Script de sync entre catálogos

**Crear:** `scripts/sync-section-catalog.sh`

Script que copia `apps/web/src/registry/sectionCatalog.ts` a `apps/admin/src/registry/sectionCatalog.ts` y verifica paridad. Se ejecuta como pre-commit hook o CI check.

#### 4.1.3 Crear types.ts compartido

**Crear:** `apps/web/src/registry/types.ts` (definiciones de §2.2)
**Copiar a:** `apps/admin/src/registry/types.ts` (mismas interfaces)

#### 4.1.4 Extender API para componentKey

**Archivos:**
- `apps/api/src/home/dto/section.dto.ts` — agregar `componentKey?: string` al DTO
- `apps/api/src/home/home-sections.service.ts` — persistir y retornar `componentKey`
- `apps/api/src/home/registry/sections.ts` — agregar mapeo type ↔ componentKey

**Migración SQL:**
```sql
-- Agregar columna componentKey a home_sections
ALTER TABLE home_sections
  ADD COLUMN component_key VARCHAR(128);
  
-- Índice para queries de búsqueda
CREATE INDEX idx_home_sections_component_key 
  ON home_sections(component_key) 
  WHERE component_key IS NOT NULL;

-- Backfill: mapear type existente a componentKey default
UPDATE home_sections 
SET component_key = type || '.first' 
WHERE component_key IS NULL AND type IS NOT NULL;
```

**Riesgo:** medio — requiere backfill cuidadoso para no romper stores existentes.
**Mitigación:** el renderer ya tiene fallback a `.first` variant, así que el backfill es compatible.

**Entregables:**
- [ ] PR 1: normalizar planTier admin (`"pro"` → `"enterprise"`)
- [ ] PR 2: crear `types.ts` en web y admin
- [ ] PR 3: migración SQL + DTO + service para componentKey
- [ ] PR 4: script de sync de catálogos

---

### Fase 2 — Explorador completo de secciones cross-template

**Objetivo:** Store Design muestra TODAS las secciones de TODOS los templates, con estado visual de disponibilidad.

#### 4.2.1 Galería exploratoria en Store Design

**Archivo principal:** `apps/web/src/components/admin/StoreDesignSection/index.jsx`

**Cambio:** el `structureCatalog` actual filtra por template seleccionado. Se debe agregar un modo "Explorar todos" que muestre las 69 secciones agrupadas por tipo y template affinity.

**Implementación:**

```jsx
// NUEVO: SectionExplorer component
// Muestra TODOS los sections de sectionCatalog, agrupados por SectionType
// Cada card muestra:
//   - thumbnail
//   - nombre
//   - badge de plan mínimo
//   - badge de template nativo
//   - estado: DesignEntitlement (included / locked / purchasable)
//   - CTA contextual si locked
```

#### 4.2.2 EntitlementResolver (nuevo servicio FE)

**Crear:** `apps/web/src/services/designEntitlementResolver.js`

Implementa la interfaz `EntitlementResolver` de types.ts:

```javascript
export function resolveEntitlement({
  sectionKey,
  currentPlan,
  targetTemplate,
  creditBalance,
  purchasedAddons
}) {
  const section = getSectionMetadata(sectionKey);
  if (!section) return { status: 'not_compatible' };

  // 1. Check template compatibility
  if (!isSectionCompatibleWithTemplate(sectionKey, targetTemplate)) {
    return {
      status: 'not_compatible',
      ctaLabel: `No disponible para ${templateName}`,
    };
  }

  // 2. Check plan access
  if (!canAccessPlanTier(currentPlan, section.planTier)) {
    // Can they buy a surcharge?
    const surchargeKey = buildTierSurchargeAddonKey(section.planTier);
    const hasSurchargeCredits = (creditBalance[surchargeKey] || 0) >= 1;

    if (hasSurchargeCredits) {
      return { status: 'already_purchased', ... };
    }

    return {
      status: 'requires_plan_upgrade',
      requiredPlan: section.planTier,
      ctaLabel: `Requiere plan ${section.planTier}`,
      ctaAction: 'upgrade_plan',
      // Alternative: offer surcharge addon
      alternativeCta: {
        label: `O comprá recargo visual (${surchargePrice})`,
        action: 'purchase_addon',
        target: surchargeKey,
      },
    };
  }

  // 3. Included in plan
  return { status: 'included_in_plan' };
}
```

#### 4.2.3 UI de estados visuales en cards

Cada card de sección en el explorador debe mostrar uno de estos estados:

| Estado | Visual | CTA |
|--------|--------|-----|
| `included_in_plan` | Badge verde "Incluido" | Botón "Agregar" |
| `requires_plan_upgrade` | Badge naranja "Plan Growth+" | "Subir de plan" o "Comprar recargo" |
| `requires_purchase` | Badge azul "1 crédito" | "Comprar crédito" → Addon Store |
| `already_purchased` | Badge verde "Desbloqueado" | Botón "Agregar" |
| `not_compatible` | Badge gris "No compatible" | "Cambiar a template X" |
| `preview_only` | Badge lila "Preview" | "Aplicar requiere crédito" |

**Archivos:**
- `apps/web/src/components/admin/StoreDesignSection/SectionExplorer.jsx` (NUEVO)
- `apps/web/src/components/admin/StoreDesignSection/SectionCard.jsx` (NUEVO)
- `apps/web/src/components/admin/StoreDesignSection/EntitlementBadge.jsx` (NUEVO)
- `apps/web/src/services/designEntitlementResolver.js` (NUEVO)

**Entregables:**
- [ ] PR 5: SectionExplorer + SectionCard + EntitlementBadge
- [ ] PR 6: EntitlementResolver service
- [ ] PR 7: Integrar en StoreDesignSection tabs

---

### Fase 3 — CTA contextual y upsell por acción

**Objetivo:** cada bloqueo tiene salida comercial inmediata y clara.

#### 4.3.1 CTA por tipo de acción

**Cuando el admin intenta...** → **Mostrar:**

| Acción | Addon requerido | CTA | Copy |
|--------|----------------|-----|------|
| Cambiar template | `ws_action_template_change` | "Comprá un cambio de template" | "Este cambio consume 1 crédito de Template ($X)" |
| Cambiar palette | `ws_action_theme_change` | "Comprá un cambio de theme" | "Este cambio consume 1 crédito de Theme ($X)" |
| Agregar sección | `ws_action_structure_edit` | "Comprá un slot extra" | "Agregar una nueva sección consume 1 crédito de Estructura ($X)" |
| Reemplazar sección | `ws_action_component_change` | "Comprá una edición estructural" | "Reemplazar el tipo de sección consume 1 crédito ($X)" |
| Usar asset Growth sin plan Growth | `ws_extra_growth_visual_asset` | "Recargo visual Growth" | "Este asset es Growth. Comprá el recargo o subite de plan ($X)" |
| Usar asset Enterprise sin plan Enterprise | `ws_extra_enterprise_visual_asset` | "Recargo visual Enterprise" | "Este asset es Enterprise. Comprá el recargo o subite de plan ($X)" |

#### 4.3.2 Drawer contextual de compra

**Crear:** `apps/web/src/components/admin/StoreDesignSection/AddonPurchaseDrawer.jsx`

Se abre inline en el editor cuando se necesita un addon. Muestra:
- Nombre del addon
- Precio
- Descripción de qué habilita
- CTA "Comprar ahora" → Mercado Pago
- Alternativa "Ver todos los addons" → Addon Store

#### 4.3.3 Barra sticky de costos

Integrar la barra de costos persistente (ya descripta en PLAN_STORE_DESIGN_STEP4):
- Créditos disponibles
- Créditos a consumir por cambios pendientes
- Subtotal/recargos
- CTA principal de aplicar o comprar

**Archivos:**
- `apps/web/src/components/admin/StoreDesignSection/AddonPurchaseDrawer.jsx` (NUEVO)
- `apps/web/src/components/admin/StoreDesignSection/CostSummaryBar.jsx` (NUEVO)
- Modificar: `apps/web/src/components/admin/StoreDesignSection/index.jsx`

**Entregables:**
- [ ] PR 8: AddonPurchaseDrawer
- [ ] PR 9: CostSummaryBar
- [ ] PR 10: Integración en StoreDesignSection

---

### Fase 4 — Addon Store alineado con editor

**Objetivo:** cada card de Addon Store mapea 1:1 con una acción del editor.

#### 4.4.1 Refactorizar AddonPurchasesView

**Archivo:** `apps/admin/src/pages/AdminDashboard/AddonPurchasesView.jsx`

Cada addon debe mostrar:
- Nombre claro de la acción del editor que habilita
- Descripción precisa: "Permite [acción] una vez"
- Precio
- Stock de créditos actuales
- Estado: comprado / disponible / agotado

**No debe haber addons ambiguos.** Cada card es una acción concreta del editor de Diseño de Tienda.

#### 4.4.2 API: endpoint de mapping addon → action

**Crear:** `GET /addons/design-actions`

Retorna el mapping canónico ADDON_ACTION_MAP para que el frontend pueda mostrar las cards correctas sin hardcodear.

**Archivos:**
- `apps/api/src/addons/addons.controller.ts` — nuevo endpoint
- `apps/api/src/addons/addons.service.ts` — resolver mapping

**Entregables:**
- [ ] PR 11: Endpoint /addons/design-actions
- [ ] PR 12: Refactorizar AddonPurchasesView con mapping 1:1

---

### Fase 5 — Reglas de aplicación y consumo

**Objetivo:** flujo idempotente de compra → acreditación → uso → consumo.

#### 4.5.1 Flujo completo

```
1. Admin intenta acción en editor
2. Editor calcula requiredAddonKeys
3. Si faltan créditos:
   a. Muestra CTA contextual → Addon Store
   b. Admin compra addon → Mercado Pago
   c. Webhook idempotente → acredita créditos en account_action_credit_ledger
   d. Editor refresca creditBalance (polling o push)
4. Editor marca acción como disponible
5. Admin aplica cambios → "Guardar"
6. Backend:
   a. assertCreditsAvailable() → valida
   b. Persiste cambio (home_settings / home_sections)
   c. consumeCredits() → solo si diff real (hash comparison)
   d. Retorna consumedCredits[]
7. Frontend actualiza saldos locales
8. Si falla la persistencia → NO consume créditos
9. Si el admin cancela antes de guardar → NO consume
```

#### 4.5.2 Validaciones ya existentes (no tocar)

El flow de consumo ya es idempotente en `storefront-action-credits.service.ts`:
- Hash comparison (`buildDraftHash`) evita consumo sin cambio real
- Ledger entries con event_type `'consume'` y credits_delta `-1`
- Execution record con status `'applied'`

**Solo agregar:**
- Refresh automático de credits post-compra (polling cada 5s mientras drawer abierto)
- UI que muestre "Crédito acreditado exitosamente" en real-time

**Entregables:**
- [ ] PR 13: Polling de credits post-compra en editor
- [ ] PR 14: UI de acreditación en tiempo real

---

### Fase 6 — QA y tests

**Objetivo:** cobertura completa de paridad y flujos comerciales.

#### 4.6.1 Tests de paridad catálogos

```typescript
// test: catalog-parity.test.ts
describe('Section catalog parity', () => {
  it('web and admin have identical section keys', () => {
    expect(Object.keys(WEB_CATALOG).sort()).toEqual(Object.keys(ADMIN_CATALOG).sort());
  });
  
  it('all planTier values use "enterprise" not "pro"', () => {
    Object.values(ADMIN_CATALOG).forEach(section => {
      expect(section.planTier).not.toBe('pro');
    });
  });
  
  it('all 8 templates are visible in Store Design', () => {
    const templates = getVisibleTemplates();
    expect(templates).toHaveLength(8);
  });
  
  it('all 69 sections are visible in explorer', () => {
    const sections = getAllExplorableSections();
    expect(sections).toHaveLength(69);
  });
});
```

#### 4.6.2 Tests de gating correcto

```typescript
describe('Plan gating', () => {
  it('maps are available for starter', () => {
    // contact sections with showMap are starter tier
    const contacts = getSectionsByType('contact');
    const starterContacts = contacts.filter(s => s.planTier === 'starter');
    expect(starterContacts.length).toBeGreaterThan(0);
    starterContacts.forEach(c => expect(c.defaultProps?.showMap).toBeDefined());
  });
  
  it('video sections are growth, not enterprise', () => {
    expect(getSectionMetadata('hero.video.background')?.planTier).toBe('growth');
    expect(getSectionMetadata('banner.video.spotlight')?.planTier).toBe('growth');
  });
  
  it('testimonials are enterprise only', () => {
    getSectionsByType('testimonials').forEach(s => {
      expect(s.planTier).toBe('enterprise');
    });
  });
});
```

#### 4.6.3 Tests de consumo de créditos

```typescript
describe('Credit consumption', () => {
  it('does not consume if no diff', async () => {
    const before = { templateKey: 'first', paletteKey: 'starter_default' };
    const result = await consumeCredits({ before, after: before });
    expect(result.consumedCredits).toEqual([]);
  });
  
  it('does not consume if save fails', async () => {
    // Mock save to throw
    // Verify ledger has no new entries
  });
  
  it('consumes exactly 1 credit per action', async () => {
    const before = { templateKey: 'first' };
    const after = { templateKey: 'second' };
    const result = await consumeCredits({ before, after });
    expect(result.consumedCredits).toEqual(['ws_action_template_change']);
  });
});
```

#### 4.6.4 Tests E2E (novavision-e2e)

```typescript
// test: store-design-parity.spec.ts
test('all templates visible in store design editor', async ({ page }) => { ... });
test('all sections visible with correct plan badges', async ({ page }) => { ... });
test('CTA shows correct addon for locked section', async ({ page }) => { ... });
test('credit consumed only on successful save', async ({ page }) => { ... });
test('preview reflects persisted structure', async ({ page }) => { ... });
```

**Entregables:**
- [ ] PR 15: Tests unitarios de paridad y gating
- [ ] PR 16: Tests E2E de flujo completo

---

## 5. Resumen de archivos impactados

### 5.1 Web (templatetwo)

| Archivo | Acción |
|---------|--------|
| `src/registry/types.ts` | **CREAR** — tipos compartidos |
| `src/registry/sectionCatalog.ts` | **VERIFICAR** — ya es la fuente de verdad |
| `src/components/admin/StoreDesignSection/index.jsx` | **MODIFICAR** — integrar SectionExplorer, CostSummaryBar |
| `src/components/admin/StoreDesignSection/SectionExplorer.jsx` | **CREAR** — galería cross-template |
| `src/components/admin/StoreDesignSection/SectionCard.jsx` | **CREAR** — card con entitlement badge |
| `src/components/admin/StoreDesignSection/EntitlementBadge.jsx` | **CREAR** — badge de estado |
| `src/components/admin/StoreDesignSection/CostSummaryBar.jsx` | **CREAR** — barra sticky de costos |
| `src/components/admin/StoreDesignSection/AddonPurchaseDrawer.jsx` | **CREAR** — drawer contextual de compra |
| `src/services/designEntitlementResolver.js` | **CREAR** — resolver de disponibilidad |

### 5.2 Admin (novavision)

| Archivo | Acción |
|---------|--------|
| `src/registry/sectionCatalog.ts` | **MODIFICAR** — `"pro"` → `"enterprise"` |
| `src/registry/types.ts` | **CREAR** — copia de web/types.ts |
| `src/pages/AdminDashboard/AddonPurchasesView.jsx` | **MODIFICAR** — mapping 1:1 con acciones |

### 5.3 API (templatetwobe)

| Archivo | Acción |
|---------|--------|
| `src/home/dto/section.dto.ts` | **MODIFICAR** — agregar componentKey |
| `src/home/home-sections.service.ts` | **MODIFICAR** — persistir/retornar componentKey |
| `src/home/home.controller.ts` | **VERIFICAR** — DTO actualizado |
| `src/addons/addons.controller.ts` | **MODIFICAR** — agregar GET /addons/design-actions |
| `src/addons/addons.service.ts` | **MODIFICAR** — agregar design-actions mapping |
| `migrations/backend/XXXX_add_component_key_to_home_sections.sql` | **CREAR** |

### 5.4 E2E (novavision-e2e)

| Archivo | Acción |
|---------|--------|
| `tests/qa-v2/store-design-parity.spec.ts` | **CREAR** |
| `tests/qa-v2/22-store-design.spec.ts` | **MODIFICAR** — agregar tests de galería |

### 5.5 Docs (novavision-docs)

| Archivo | Acción |
|---------|--------|
| `plans/PLAN_STORE_DESIGN_PARITY_AND_UNIFICATION.md` | **ESTE DOCUMENTO** |
| `changes/YYYY-MM-DD-store-design-parity.md` | **CREAR** — al implementar |

---

## 6. Estrategia de rollout

### Orden seguro de deploy

```
1. [BE] Migración SQL: componentKey en home_sections (retrocompatible, nullable)
2. [BE] DTO + Service: aceptar y retornar componentKey
3. [Admin] Normalizar planTier "pro" → "enterprise"
4. [Web] Crear types.ts, SectionExplorer, EntitlementResolver
5. [Web] Integrar SectionExplorer en StoreDesignSection
6. [Web] CostSummaryBar + AddonPurchaseDrawer
7. [BE] Endpoint /addons/design-actions
8. [Admin] Refactorizar AddonPurchasesView
9. [E2E] Tests de paridad y flujo completo
```

### Feature flag

Opción: usar feature flag `store_design_v2` para activar la nueva galería progresivamente.

```javascript
const showSectionExplorer = useFeatureFlag('store_design_v2');
```

Esto permite:
- Deploy gradual sin romper el editor actual
- A/B testing de la nueva UX
- Rollback instantáneo si hay problemas

---

## 7. Riesgos y mitigaciones

| Riesgo | Severidad | Mitigación |
|--------|-----------|------------|
| Backfill de componentKey rompe stores existentes | Alta | Renderer ya tiene fallback a `.first`; backfill usa `.first` como default |
| Normalización `"pro"` → `"enterprise"` rompe planGating admin | Baja | planGating.ts ya maneja ambos; verificar en tests |
| Doble consumo de créditos en error de red | Media | `consumeCredits()` ya usa hash comparison; agregar retry-safe en FE |
| Preview desincronizado del nuevo catálogo | Media | SectionRenderer no cambia; solo cambia la UI de selección |
| Divergencia si se agrega sección sin actualizar ambos catálogos | Media | Script de sync + CI check de paridad |
| Store Design nuevo es significativamente diferente a la UX actual | Baja | Feature flag para rollout gradual |

---

## 8. Checklist QA

### Paridad de catálogos
- [ ] Web y Admin tienen las mismas 69 section keys
- [ ] Todos los planTier usan "enterprise" (no "pro")
- [ ] Los 8 templates son visibles en Store Design
- [ ] Los 69 secciones aparecen en el explorador

### Gating correcto
- [ ] Maps visible para starter (embebido en contact)
- [ ] Video visible para growth+ (hero.video.background, banner.video.spotlight)
- [ ] Testimonials, Marquee, Newsletter solo para enterprise
- [ ] Templates 1–3: starter, Template 4: growth, Templates 5–8: enterprise

### CTA correcto
- [ ] Sección bloqueada por plan → CTA "Subir de plan" + alternativa "Recargo visual"
- [ ] Sección sin créditos → CTA "Comprar crédito" → Addon Store
- [ ] Template locked → CTA "Comprá cambio de template ($X)"
- [ ] Theme locked → CTA "Comprá cambio de theme ($X)"
- [ ] Estructura sin créditos → "Comprá X crédito(s) de estructura"

### Consumo de créditos
- [ ] No consume si no hay diff real (hash comparison)
- [ ] No consume si el save falla
- [ ] No consume si el admin cancela
- [ ] Consume exactamente 1 crédito por acción exitosa
- [ ] Saldo actualizado inmediatamente post-consumo
- [ ] Saldo actualizado post-compra (polling o push)

### Preview y storefront
- [ ] Preview refleja la estructura persistida
- [ ] Storefront renderiza la misma estructura
- [ ] componentKey persiste y se recupera correctamente
- [ ] Fallback a `.first` si componentKey no se encuentra

---

## 9. Relación con plan existente

Este plan **extiende y complementa** `PLAN_STORE_DESIGN_STEP4_SELF_SERVE_EDITOR.md`:

- **Step4 plan** define la visión UX/producto (cómo se ve y se siente el editor).
- **Este plan** (PARITY) define la implementación técnica (qué cambiar, dónde, con qué tipos e interfaces).

Las fases de Step4 mapean a las fases de Parity así:

| Step4 Fase | Parity Fase | Descripción |
|-----------|-------------|-------------|
| Fase 1 (UX shell) | Fases 1 + 2 | Unificar catálogos + galería exploratoria |
| Fase 2 (costos visibles) | Fase 3 | CTA contextual + CostSummaryBar + Drawer |
| Fase 3 (editor props) | — (ya existe SectionPropsEditor) | Mejoras incrementales sobre lo existente |
| Fase 4 (preview resiliente) | — (ya existe) | Mejoras incrementales |
| Fase 5 (componentKey backend) | Fase 1.4 | Migración + DTO extends |

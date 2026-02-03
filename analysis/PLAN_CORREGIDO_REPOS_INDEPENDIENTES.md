# Plan Corregido: Repos Independientes (NO Monorepo)

> **Fecha:** 2026-02-03  
> **Contexto:** Se detectó que el plan anterior asumía monorepo con packages compartidos. Los 3 repos son **independientes**.

---

## 🚨 Error del Plan Anterior

El agente asumió que podía crear:
- `packages/theme/` compartido
- `packages/ai/prompts/` centralizado
- `packages/contracts/` con Zod schemas
- CI centralizado con workflows compartidos

**Realidad:** Son 3 repos Git independientes:
1. **templatetwobe** → API NestJS (Railway)
2. **novavision** → Admin Dashboard (Netlify)
3. **templatetwo** → Web Storefront (Netlify)
4. **novavision-docs** → Documentación (GitHub Pages o privado)

---

## ✅ Plan Corregido por Repo

### 1. Branching Strategy (Aplica a CADA repo)

**Estado actual:**
- `feature/automatic-multiclient-onboarding` (API + Admin)
- `feature/multitenant-storefront` (Web)

**Plan corregido:**

```
Por cada repo:
┌─────────────────────────────────────────┐
│  main                                   │ ← producción
│    ↑                                    │
│  develop                                │ ← integración (CI valida)
│    ↑                                    │
│  feature/*                              │ ← features nuevas
│    ↑                                    │
│  fix/*                                  │ ← hotfixes
└─────────────────────────────────────────┘
```

**Pasos inmediatos:**
1. En cada repo, crear `develop` desde la rama de deploy activa
2. Configurar branch protection: PR obligatorio a `develop` y `main`
3. CI por repo (lint + typecheck + build) en `.github/workflows/`

---

### 2. Sistema de Theme/Tokens

**Problema detectado:**
- Admin usa: `lightTheme.bgPrimary`, `darkTheme.accent`, etc. (objetos JS)
- Web usa: `--nv-primary`, `--nv-bg`, etc. (CSS variables)
- Hay variables mixtas: `--color-primary` y `--nv-primary` en mismo archivo

**Solución (sin packages compartidos):**

```
Cada repo mantiene SU PROPIA copia de tokens,
pero seguimos un CONTRATO de naming documentado.
```

**Contrato de CSS Variables (documentar en novavision-docs):**

```css
/* ===== OBLIGATORIAS (todos los repos) ===== */
--nv-primary       /* color principal de marca */
--nv-primary-fg    /* texto sobre primary */
--nv-secondary     /* color secundario */
--nv-secondary-fg  /* texto sobre secondary */
--nv-accent        /* color de acento/CTA */
--nv-bg            /* fondo principal */
--nv-surface       /* fondo de cards/modales */
--nv-text          /* texto principal */
--nv-muted         /* texto secundario/disabled */
--nv-border        /* bordes */

/* ===== OPCIONALES (derivadas) ===== */
--nv-hover         /* hover states */
--nv-card-bg       /* fondo específico de cards */
--nv-text-muted    /* alias de muted */
--nv-primary-hover /* hover de primary */
--nv-accent-fg     /* texto sobre accent */
```

**Migración en Admin:**
1. Crear `src/theme/nvVariables.js` con mapeo de tokens legacy → `--nv-*`
2. GlobalStyle aplica CSS vars al `:root`
3. Componentes nuevos usan `var(--nv-*)`, legacy sigue funcionando

**Migración en Web:**
Ya usa `--nv-*`, solo limpiar variables obsoletas como `--color-primary`.

---

### 3. Templates Manifest (Solo en Web)

**Estado actual:**
```
apps/web/src/templates/
├── first/
├── second/
├── third/
├── fourth/
└── fifth/
```

**Problema:** Nadie sabe qué template es cuál sin abrir código.

**Solución en Web (templatetwo):**

```javascript
// src/templates/manifest.js
export const TEMPLATES = {
  first: {
    id: 'first',
    name: 'Classic Store',
    description: 'Layout clásico con header fijo y sidebar de filtros',
    status: 'stable',
    preview: '/demo/first-preview.png',
    features: ['header-sticky', 'sidebar-filters', 'mega-menu'],
  },
  second: {
    id: 'second',
    name: 'Modern Grid',
    description: 'Grid responsive con cards flotantes',
    status: 'stable',
    preview: '/demo/second-preview.png',
    features: ['masonry-grid', 'infinite-scroll'],
  },
  third: {
    id: 'third',
    name: 'Minimal',
    description: 'Diseño minimalista para productos de lujo',
    status: 'stable',
    preview: '/demo/third-preview.png',
    features: ['full-width', 'parallax'],
  },
  fourth: {
    id: 'fourth',
    name: 'Boutique',
    description: 'Estilo boutique con animaciones suaves',
    status: 'beta',
    preview: '/demo/fourth-preview.png',
    features: ['animations', 'transitions'],
  },
  fifth: {
    id: 'fifth',
    name: 'Bold',
    description: 'Colores vibrantes y tipografía grande',
    status: 'beta',
    preview: '/demo/fifth-preview.png',
    features: ['bold-typography', 'vibrant-colors'],
  },
};

export const getTemplate = (id) => TEMPLATES[id] || TEMPLATES.first;
export const listTemplates = () => Object.values(TEMPLATES);
```

**No crear package compartido**, el manifest vive en Web porque ahí están los templates.

---

### 4. Dev Portal (Solo en Admin)

**Donde implementarlo:** `apps/admin/src/pages/DevPortal/`

**Guard de acceso:**
```javascript
// Solo visible en desarrollo
const isDevMode = import.meta.env.DEV && 
                  import.meta.env.VITE_ENABLE_DEV_PORTAL === 'true';
```

**Features del portal:**
1. **Docs Viewer** - Lee markdown de `novavision-docs` (fetch a GitHub raw)
2. **Theme Playground** - Preview de paletas y tokens
3. **Component Catalog** - Showcase de componentes MUI customizados
4. **Onboarding Test** - Simular flujo de onboarding sin crear datos reales

**NO incluir:**
- Templates playground (eso va en Web, no Admin)
- Prompts IA versionados (innecesario, usar `.github/copilot-instructions.md`)

---

### 5. IA/Prompts

**Error anterior:** Crear `packages/ai/prompts/` compartido.

**Solución correcta:** Cada repo tiene su propio `.github/copilot-instructions.md` (ya creado).

**Adicional para Admin:**
Si se necesita prompt library para el Design Studio / Builder:

```javascript
// apps/admin/src/utils/builder/prompts.js
export const BUILDER_PROMPTS = {
  generateHeroSection: {
    name: 'Generate Hero Section',
    description: 'Genera una sección hero para landing page',
    template: `...`,
    inputs: ['businessType', 'tone', 'language'],
    constraints: ['Max 150 caracteres título', 'Incluir CTA'],
  },
  // ... más prompts
};
```

Esto NO se comparte entre repos, cada uno tiene sus prompts específicos.

---

### 6. CI/CD por Repo

Cada repo tiene su propio `.github/workflows/ci.yml`:

**templatetwobe (API):**
```yaml
name: CI
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run build
```

**novavision (Admin):**
```yaml
name: CI
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run build
```

**templatetwo (Web):**
```yaml
name: CI
on: [push, pull_request]
jobs:
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with: { node-version: '20' }
      - run: npm ci
      - run: npm run lint
      - run: npm run typecheck
      - run: npm run ci:storefront
```

---

## 📋 Tareas Ordenadas por Prioridad

### Sprint 1 (Estabilizar)

| # | Repo | Tarea | Esfuerzo |
|---|------|-------|----------|
| 1 | Todos | Crear rama `develop` desde rama de deploy activa | 30 min |
| 2 | Todos | Crear `.github/workflows/ci.yml` básico | 1 hora |
| 3 | Admin | Unificar naming a `--nv-*` en GlobalStyle | 2 horas |
| 4 | Web | Crear `src/templates/manifest.js` | 1 hora |
| 5 | Docs | Documentar contrato de CSS variables | 1 hora |

### Sprint 2 (Mejorar DX)

| # | Repo | Tarea | Esfuerzo |
|---|------|-------|----------|
| 6 | Admin | Dev Portal básico (docs viewer + theme playground) | 8 horas |
| 7 | Web | Limpiar warnings de lint (variables no usadas) | 4 horas |
| 8 | API | Agregar tests e2e de onboarding | 6 horas |

### Sprint 3 (Opcional)

| # | Repo | Tarea | Esfuerzo |
|---|------|-------|----------|
| 9 | Admin | Prompts library para Builder | 4 horas |
| 10 | Web | Preview de templates en selector | 4 horas |

---

## ⚠️ Lo que NO hacer

1. ❌ Crear `packages/` compartidos entre repos
2. ❌ Importar código de un repo en otro
3. ❌ CI centralizado que dependa de múltiples repos
4. ❌ Symlinks entre repos
5. ❌ Git submodules

## ✅ Lo que SÍ hacer

1. ✅ Documentar contratos (APIs, tokens, schemas) en `novavision-docs`
2. ✅ Copiar código común cuando sea necesario (cada repo es autónomo)
3. ✅ CI independiente por repo
4. ✅ PRs que referencian issues/docs compartidos

---

## Referencias

- [REPO_STRUCTURE.md](../rules/REPO_STRUCTURE.md)
- [Copilot Instructions API](../../apps/api/.github/copilot-instructions.md)
- [Copilot Instructions Admin](../../apps/admin/.github/copilot-instructions.md)
- [Copilot Instructions Web](../../apps/web/.github/copilot-instructions.md)

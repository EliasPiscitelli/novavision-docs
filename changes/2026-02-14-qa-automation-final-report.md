# Informe Final — QA Automation: Templates, Themes & Visual Regression

**Fecha:** 2026-02-14  
**Autor:** agente-copilot  
**Ramas afectadas:**
- **E2E repo (novavision-e2e):** `main` — commits `33ed282`, `5c50567`, `f903fe9`
- **Web repo (templatetwo):** `develop` → cherry-pick a `feature/multitenant-storefront` + `feature/onboarding-preview-stable`

---

## 1. Resumen Ejecutivo

Se completó un overhaul de 5 fases del sistema de testing E2E, partiendo de un score de 3/10 en la auditoría inicial hasta alcanzar cobertura completa de templates, paletas, visual regression y accesibilidad.

### Métricas Clave

| Métrica | Antes | Después |
|---------|-------|---------|
| Tests template/theme | 0 | 162 |
| Templates cubiertos | 0/5 | 5/5 |
| Paletas verificadas | 0/20 | 20/20 |
| Visual regression baselines | 0 | 30 screenshots |
| Hallazgos a11y detectados | 0 | 17 |
| Preview render timeouts | N/A → 23/23 | 0 |
| Tiempo ejecución CAPA H | ~16 min (timeouts) | 3.4 min |

---

## 2. Fases Completadas

### Fase 0 — Auditoría (sesión previa)
- Score inicial: **3/10**
- Zero tests de template/theme
- Solo template 5 tenía demo data fallback
- [Documento de auditoría](docs/e2e/AUDIT_playwright_theme_template.md)

### Fase 1 — data-testid + Fixtures + Specs 11-14 (sesión previa)
- **9 componentes** con `data-testid` agregado en 3 ramas del web repo
- Fixtures extendidos, seed functions, contrast helper
- **46 tests** en specs 11-14 (autenticación, navegación, cart, permisos)

### Fase 2 — Template × Palette Matrix (Spec 15)
- `palette-registry.ts`: registro de 20 paletas con tokens completos
- `preview.ts`: helper de renderizado via postMessage + PreviewHost
- **103 tests**: 5 templates × 4 paletas representativas + WCAG contrast 20 paletas + dark mode stress
- Commit: `33ed282`

### Fase 3 — Visual Regression + A11y (Specs 16-17)
- **Spec 16**: 30 tests de screenshot comparison (desktop, mobile, hero, footer)
- **Spec 17**: 29 tests de accesibilidad (section completeness, focus nav, ARIA landmarks, contraste)
- Config Playwright: CAPA H con projects dedicados `v2-15`, `v2-16`, `v2-17`
- Commit: `5c50567`

### Fase 4 — Bug Fixes + Validación Final (esta sesión)

#### 4a. Fix del Banner (BannerHomeSecond)
**Problema:** El banner compartido por los 5 templates ocupaba ~65vh de altura + 6vh de margin acumulado (3vh de CarouselContainer + 3vh de BannerCtn).

**Fix aplicado:**

| Propiedad | Antes | Después |
|-----------|-------|---------|
| CarouselContainer height | 65vh | 50vh |
| CarouselContainer max-height | — | 500px |
| CarouselContainer margin-bottom | 3vh | 1rem |
| Mobile height | 50vh | 40vh |
| Mobile max-height | — | 350px |
| BannerCtn margin (global + local) | 3vh | 0 |
| imageContainer height | 65vh (hardcoded) | 100% (inherits) |

**Archivos:** `BannerHome/style.jsx`, `globalStyles.jsx`, `HomePageFirst/index.jsx`

#### 4b. Demo Data Fallback (Templates 1-4)
**Problema:** Solo template 5 tenía fallback con datos demo. Templates 1-4 mostraban "Cargando datos..." indefinidamente cuando no había datos de la API.

**Fix:** Patrón `rawHomeData || DEMO_HOME_DATA` aplicado a:
- Template 1 (First): `HomePageFirst/index.jsx`
- Template 2 (Second): `HomePage/index.jsx`
- Template 3 (Third): `HomePageThird/index.jsx`
- Template 4 (Fourth): `Home.jsx`

**Datos demo:** 8 productos, 3 servicios, 2 banners, 4 FAQs, 3 contactInfo, socialLinks, logo.

#### 4c. Fix del Preview Helper (E2E)

**Problema:** `renderPreview()` esperaba un ACK `nv:preview:ready` vía `postMessage`, pero PreviewHost envía ese ACK con `window.parent.postMessage()` que es un no-op cuando la página se abre directamente (no en iframe). **Todos los render tests daban timeout de 20s.**

**Causa raíz:**
```
Test → page.goto('/preview') → window.postMessage(render)
PreviewHost recibe → setState → intenta ACK via window.parent.postMessage()
                                ↓
                    window.parent === window → return (no-op)
                                ↓
                    Test nunca recibe ACK → timeout 20s
```

**Fix:** Reemplazar el mecanismo de ACK por detección DOM:
```typescript
// Antes: esperaba postMessage ACK (nunca llega fuera de iframe)
// Después: espera la aparición de .nv-preview-scope en el DOM
await page.waitForSelector('.nv-preview-scope', { state: 'attached', timeout });
```

**Impacto:** 23 tests que daban timeout → todos pasan en ~2s cada uno.

#### 4d. Fix de countRenderedSections

**Problema:** `countRenderedSections()` buscaba `data-testid$="-section"` / `data-section` / `section[id]`, pero SectionRenderer no agrega esos atributos.

**Fix:** Fallback que busca el contenedor dentro de `.nv-preview-scope` con más hijos directos (= secciones renderizadas).

- Commit E2E: `f903fe9`

---

## 3. Resultados de Tests — CAPA H Completa

### Spec 15 — Template × Palette Matrix (103 tests)
| Grupo | Tests | Pasaron | Fallaron |
|-------|-------|---------|----------|
| Render Matrix (5 tpl × 4 pal) | 20 | **20** | 0 |
| WCAG Contrast (20 paletas × 4 checks) | 80 | 65 | **15** |
| Dark Mode Stress (5 tpl × 3 dark pal) | 3 | **3** | 0 |
| **Total** | **103** | **88** | **15** |

### Spec 16 — Visual Regression (30 tests)
| Grupo | Tests | Pasaron | Fallaron |
|-------|-------|---------|----------|
| Desktop Full Page (5 tpl × 2 pal) | 10 | **10** | 0 |
| Mobile Full Page (5 tpl × 2 pal) | 10 | **10** | 0 |
| Hero Close-up (5 tpl) | 5 | **5** | 0 |
| Footer Close-up (5 tpl) | 5 | **5** | 0 |
| **Total** | **30** | **30** | **0** |

### Spec 17 — A11y Sections (29 tests)
| Grupo | Tests | Pasaron | Fallaron |
|-------|-------|---------|----------|
| Section Completeness (5 tpl) | 5 | **5** | 0 |
| Focus Navigation (5 tpl) | 5 | **5** | 0 |
| ARIA Landmarks (5 tpl × 2 checks) | 10 | 9 | **1** |
| Image Alt Text (5 tpl) | 5 | **5** | 0 |
| Interactive Contrast (4 pal × 2 checks) | 4 | 3 | **1** |
| **Total** | **29** | **27** | **2** |

### Resumen Global CAPA H
| | Pasaron | Fallaron | Total |
|--|---------|----------|-------|
| **Specs 15-17** | **145** | **17** | **162** |
| **Ratio** | **89.5%** | 10.5% (todos hallazgos reales) | |

---

## 4. Hallazgos de Accesibilidad (17 issues reales)

### 4.1 WCAG Contrast — Paletas con ratio insuficiente (15 issues)

Threshold: AA Large Text ≥ 3.0:1

| Paleta | Check | Ratio | Veredicto |
|--------|-------|-------|-----------|
| boutique_default | accent/bg | < 3.0 | ⚠️ |
| starter_default | accent/bg | < 3.0 | ⚠️ |
| startup_default | primary/bg | < 3.0 | ⚠️ |
| blue_tech | primary/bg | < 3.0 | ⚠️ |
| blue_tech | accent/bg | < 3.0 | ⚠️ |
| classic_white | primary/bg | < 3.0 | ⚠️ |
| elegant_purple | accent/bg | < 3.0 | ⚠️ |
| organic_walnut | accent/bg | < 3.0 | ⚠️ |
| standard_blue | primary/bg | < 3.0 | ⚠️ |
| standard_blue | accent/bg | < 3.0 | ⚠️ |
| vivid_coral | primary/bg | < 3.0 | ⚠️ |
| forest_calm | primary/bg | < 3.0 | ⚠️ |
| ocean_breeze | primary/bg | < 3.0 | ⚠️ |
| ocean_breeze | accent/bg | < 3.0 | ⚠️ |
| sunset_warm | primary/bg | < 3.0 | ⚠️ |

**Recomendación:** Ajustar los valores de `primary` y `accent` en estas paletas para cumplir WCAG AA (oscurecer colores claros sobre fondo blanco, o viceversa).

### 4.2 ARIA Landmarks (1 issue)
- **Boutique (template 4):** No tiene elemento `<nav>` ni `role="navigation"`. El header (`header.fourth`) no usa semántica de navegación.

### 4.3 Interactive Element Contrast (1 issue)
- **ocean_breeze:** link color (`#0EA5E9`) vs bg (`#FFFFFF`) = **2.77:1** (requiere ≥ 3.0:1)

---

## 5. Archivos Modificados

### Web Repo (templatetwo)
| Archivo | Cambio |
|---------|--------|
| `src/templates/second/components/BannerHome/style.jsx` | Height 65vh→50vh, max-height, margin fix |
| `src/globalStyles.jsx` | BannerCtn margin-bottom 3vh→0 |
| `src/templates/first/pages/HomePageFirst/index.jsx` | BannerCtn fix + DEMO_HOME_DATA fallback |
| `src/templates/second/pages/HomePage/index.jsx` | DEMO_HOME_DATA fallback |
| `src/templates/third/pages/HomePageThird/index.jsx` | DEMO_HOME_DATA fallback |
| `src/templates/fourth/pages/Home.jsx` | DEMO_HOME_DATA fallback |

### E2E Repo (novavision-e2e)
| Archivo | Cambio |
|---------|--------|
| `helpers/preview.ts` | ACK→DOM detection, countRenderedSections fallback |
| `helpers/palette-registry.ts` | 20 paletas registradas (fase previa) |
| `helpers/contrast.ts` | WCAG contrast ratio calculator (fase previa) |
| `tests/qa-v2/15-template-palette-matrix.spec.ts` | 103 tests (fase previa) |
| `tests/qa-v2/16-visual-regression.spec.ts` | 30 tests + 30 baselines PNG |
| `tests/qa-v2/17-a11y-sections.spec.ts` | 29 tests, countRenderedSections fix |
| `playwright.config.ts` | CAPA H projects (v2-15, v2-16, v2-17) |

---

## 6. Cómo Ejecutar

```bash
# Requisito: web dev server corriendo
cd apps/web && npm run dev

# E2E — CAPA H completa
cd novavision-e2e
SKIP_CLEANUP=1 npx playwright test tests/qa-v2/15-template-palette-matrix.spec.ts \
  tests/qa-v2/16-visual-regression.spec.ts \
  tests/qa-v2/17-a11y-sections.spec.ts \
  --reporter=list

# Solo un spec
SKIP_CLEANUP=1 npx playwright test tests/qa-v2/15-template-palette-matrix.spec.ts

# Actualizar baselines de visual regression
SKIP_CLEANUP=1 npx playwright test tests/qa-v2/16-visual-regression.spec.ts --update-snapshots
```

**Nota:** `SKIP_CLEANUP=1` es necesario para bypassear global setup (seed/cleanup) que requiere API + DB. Los specs 15-17 solo necesitan el storefront web corriendo.

---

## 7. Próximos Pasos Recomendados

1. **Corregir 15 paletas con contrast insuficiente** — ajustar `primary`/`accent` en `palette-registry` y en el Design Studio del admin
2. **Agregar `<nav>` a header.fourth** (Boutique) para cumplir con ARIA landmarks
3. **Oscurecer `ocean_breeze.primary`** (#0EA5E9 → algo con ratio ≥ 3.0 vs blanco)
4. **Agregar `data-testid` a SectionRenderer** para eliminar la heurística de conteo por DOM
5. **CI Integration** — agregar specs 15-17 al pipeline de CI con el storefront como servicio
6. **Cross-browser baselines** — los snapshots actuales son darwin-only; generar para linux (CI)

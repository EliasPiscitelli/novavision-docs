# Plan: Fix Regresiones Design Studio — Step 4 / Admin Dashboard

- Fecha: 2026-07-18
- Autor: GitHub Copilot (Staff Frontend)
- Repos: Web (templatetwo), Admin (novavision)
- Ramas: Web → `develop`, Admin → `feature/automatic-multiclient-onboarding`
- Precursor: `PLAN_STORE_DESIGN_PARITY_AND_UNIFICATION.md`

---

## 1. Diagnóstico completado

### 1.1 Inventario de componentes auditados

| Componente | Repo | Ubicación | Líneas | Rol |
|---|---|---|---|---|
| StoreDesignSection | Web | `src/components/admin/StoreDesignSection/index.jsx` | ~1400 | Design Studio del admin dashboard |
| PreviewFrame (web) | Web | `src/components/admin/StoreDesignSection/PreviewFrame.jsx` | ~130 | Iframe preview para web dashboard |
| PreviewHost | Web | `src/pages/PreviewHost/index.tsx` | ~370 | Destino del iframe, recibe postMessage |
| SectionRenderer | Web | `src/components/SectionRenderer.tsx` | ~370 | Resuelve props → renderiza secciones |
| variables.css | Web | `src/styles/variables.css` | ~80 | CSS vars default (light theme) |
| netlify.toml | Web | `netlify.toml` | ~80 | CSP headers |
| Step4TemplateSelector | Admin | `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | 2102 | Design Studio del onboarding |
| PreviewFrame (admin) | Admin | `src/components/PreviewFrame.tsx` | ~120 | Iframe preview para admin |
| previewDemoSeed | Admin | `src/services/builder/previewDemoSeed.ts` | ~200 | Seed data para preview |
| designSystem | Admin | `src/services/builder/designSystem.ts` | ~500 | PRESET_CONFIGS, SECTION_CONSTRAINTS |

### 1.2 Causa raíz por problema

| # | Problema | Causa raíz | Severidad |
|---|---|---|---|
| 1 | First-paint background blanco | `variables.css` default `--nv-background: #ffffff`. PreviewHost inyecta palette CSS vars via `:root` SOLO DESPUÉS de recibir postMessage. Entre carga y primer message → fondo blanco | Alta |
| 2 | Banners prop warnings | Template 2/6/8 esperan `banners: {desktop:[], mobile:[]}` (objeto). Template 5/FullHero esperan `desktop:[]`, `mobile:[]` (props separados). SectionRenderer pasa AMBOS formatos simultáneamente pero no normaliza consistentemente | Media |
| 3 | CSP bloqueando imágenes | `img-src` en netlify.toml incluye `images.unsplash.com` y `*.supabase.co`. Las imágenes del seed demo (unsplash) SÍ están permitidas. El problema puede ser imágenes custom de Storage con paths no cubiertos → verificar | Baja |
| 4 | Admin cards clipped | NO encontrado en estilos de Step4TemplateSelector.css. Las cards tienen `border-radius: 16px` sin `overflow:hidden` problemático. Posible causa: contenedor padre con `overflow:hidden` + transform scale del PreviewFrame | Baja |
| 5 | Preview no carga en onboarding | PreviewFrame envía postMessage correctamente. PreviewHost valida origin + preview token. Si el token no tiene `clientSlug` que matchee el payload → bloquea con "El token no corresponde" | Alta |

### 1.3 Propiedades del PreviewHost iframe background

```
Estado inicial:  → variables.css carga → :root { --nv-background: #ffffff }
                 → PreviewHost muestra "Conectando con el editor…" (bg: #111827 hardcoded)
                 → Pero :root mantiene --nv-bg: #ffffff → cualquier elemento usando var(--nv-bg) = blanco

Después de nv:preview:render:
                 → rootCssVarsBlock se genera de paletteToCssVars()
                 → Se inyecta en <style> tag dentro del render
                 → :root recibe las vars del palette (ej: --nv-bg: #111827 para dark)
                 → Todo se pinta correctamente
```

**Fix**: Inyectar inmediatamente CSS vars de dark theme default en PreviewHost ANTES de que state llegue.

---

## 2. Fixes planificados

### Fix A: First-paint dark background (PreviewHost)

**Archivo**: `apps/web/src/pages/PreviewHost/index.tsx`

**Cambio**: Agregar un bloque CSS estático con valores dark default que se apliquen ANTES de recibir payload. El `rootCssVarsBlock` dinámico los sobrescribirá cuando llegue.

```css
/* Initial dark defaults — overwritten by palette CSS vars on nv:preview:render */
:root {
  --nv-background: #111827;
  --nv-bg: #111827;
  --nv-text: #FAFAF9;
  --nv-surface: #1f2937;
  --nv-primary: #3b82f6;
  --nv-border: #374151;
  --nv-muted: #9ca3af;
}
html, body { background-color: #111827; color: #FAFAF9; }
```

### Fix B: Banners prop normalization (SectionRenderer)

**Archivo**: `apps/web/src/components/SectionRenderer.tsx`

**Cambio**: En el bloque `hero`/`banner`, normalizar `banners` siempre a objeto `{desktop:[], mobile:[]}`:

```typescript
// Antes:
banners: finalProps.banners || heroBanners,
desktop: finalProps.desktop || heroBanners?.desktop || [],
mobile: finalProps.mobile || heroBanners?.mobile || [],

// Después: normalizar + pasar ambos shapes
const normalizedBanners = {
  desktop: finalProps.desktop || heroBanners?.desktop || (Array.isArray(heroBanners) ? heroBanners : []),
  mobile: finalProps.mobile || heroBanners?.mobile || [],
};
// ... pasar:
banners: normalizedBanners,
desktop: normalizedBanners.desktop,
mobile: normalizedBanners.mobile,
```

### Fix C: CSP img-src ampliar (netlify.toml)

**Verificar** si hay dominios faltantes. Si el Storage de Supabase usa un dominio específico no cubierto por `*.supabase.co`, agregarlo.

### Fix D: PreviewHost inline background (eliminar flash)

**Archivo**: `apps/web/src/pages/PreviewHost/index.tsx`

**Cambio**: En el div `nv-preview-scope`, el style ya usa `backgroundColor: "var(--nv-bg)"`. Si el Fix A inyecta `--nv-bg: #111827` como default, esto se resuelve automáticamente.

---

## 3. Riesgos

| Riesgo | Mitigación |
|---|---|
| Fix A rompe light-theme storefronts en producción | Los CSS vars del Fix A solo se inyectan en PreviewHost (ruta `/preview`), NO en la tienda real |
| Fix B rompe componentes que esperan shape específico | Pasamos AMBOS shapes (objeto + props separados) — retrocompatible |
| CSP muy permisivo | Solo agregar dominios estrictamente necesarios |

---

## 4. Orden de implementación

1. Fix A → First-paint dark background en PreviewHost
2. Fix B → Banners prop normalization en SectionRenderer  
3. Fix C → CSP (si se confirma necesario)
4. Validar compilación (lint + typecheck + build)

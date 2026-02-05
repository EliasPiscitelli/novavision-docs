# Theme System Audit: Comparing Branches

**Date**: 2026-02-04  
**Goal**: Understand how theming worked in `feature/automatic-multiclient-onboarding` (stable) vs current branch `feature/multitenant-storefront` (broken)

---

## 📊 AUDIT FINDINGS

### Branch: `feature/automatic-multiclient-onboarding` (STABLE ✅)

**Theme System Architecture:**
```
globalStyles.jsx (hardcoded themes per template)
├── novaVisionTheme1 (template 1)
├── novaVisionThemeFifth (template 5 - light)
├── novaVisionThemeFifthDark (template 5 - dark)
└── ... other variants

App.jsx
├── ThemeProvider (styled-components)
└── useThemeVars() hook
    └── applies CSS vars to root
```

**How it worked**:
1. `App.jsx` reads `isDarkTheme` state
2. Selects theme: `theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth`
3. Wraps app in `<ThemeProvider theme={theme}>`
4. `useThemeVars(theme)` injects theme colors as CSS variables
5. Components read from `props.theme` or `var(--nv-*)`

**Palette/Template Support**:
- NO `paletteKey` parameter
- NO dynamic resolution based on `tenant.config.paletteKey`
- Theme was FULLY hardcoded per template
- Only supports: dark/light toggle, not arbitrary palette swaps

**Preview System**:
- NO preview components found in this branch
- Probably handled in separate `feature/onboarding-preview-stable` branch

---

### Branch: `feature/multitenant-storefront` (CURRENT - BROKEN ❌)

**Theme System Architecture:**

**NEW** directory structure exists:
```
apps/web/src/theme/
├── index.ts ← createTheme() factory
├── palettes.ts ← PALETTES registry with paletteKey support
├── ThemeProvider.jsx ← NEW React wrapper (unused?)
├── legacyAdapter.ts ← Converts normalized theme to old shape
├── merge.ts ← deepMerge utility
├── types.ts ← Theme type definitions
├── templates/
│   ├── normal.ts
│   ├── ... other template files
└── tokens.js
```

**Functions available**:
- `createTheme(templateKey, overrides, opts: {paletteKey})` ✅ EXISTS
- `resolvePalette(paletteKey)` ✅ EXISTS
- `paletteToThemeColors(palette)` ✅ EXISTS (renames `bg` → `background`)
- `toLegacyTheme(theme)` ✅ EXISTS
- `ThemeProvider` component ✅ EXISTS (but not used in App.jsx)

**Problem**: App.jsx IGNORES this new system!
```jsx
// App.jsx still uses OLD hardcoded themes
import { novaVisionThemeFifth, novaVisionThemeFifthDark } from './globalStyles';

const theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth;
<ThemeProvider theme={theme}>  // ← styled-components ThemeProvider, not the new one!
```

**Result**:
- New `createTheme()` + `resolvePalette()` + `paletteKey` support **NOT USED**
- Themes are still HARDCODED
- Palette swaps (starter_default, dark_default, etc.) are **IGNORED**
- `tenant.config.paletteKey` from API is **NEVER CONSULTED**

---

## 🔍 ROOT CAUSES

### **Issue #1: Dead Code Path**
New theme system exists (`/src/theme/`) but **never called**:
```typescript
export function createTheme(templateKey, overrides, opts?: {paletteKey}) { ... }
export function resolvePalette(paletteKey?: string) { ... }
```
App.jsx doesn't use these.

### **Issue #2: App.jsx Hardcoded Dark/Light Toggle**
```jsx
const [isDarkTheme, setIsDarkTheme] = useState(resolveInitialTheme);
const theme = isDarkTheme ? novaVisionThemeFifthDark : novaVisionThemeFifth;
```
This toggles between 2 hardcoded themes. Doesn't read:
- `homeData.config.templateKey`
- `homeData.config.paletteKey`
- `client_home_settings.template_key` / `palette_key`

### **Issue #3: globalStyles Still Exports Per-Template Hardcoded Themes**
`globalStyles.jsx` has ~3000 lines of hardcoded theme objects:
```jsx
export const novaVisionThemeFifth = { ... };
export const novaVisionThemeFifthDark = { ... };
export const novaVisionTheme1 = { ... };
```
These bypass the new `createTheme()` factory.

### **Issue #4: ThemeProvider Component Unused**
New `/theme/ThemeProvider.jsx` exists but **never imported** in `App.jsx`. It has logic to:
- Normalize templateKey
- Resolve paletteKey
- Call `createTheme()`
- Call `toLegacyTheme()`
- Inject CSS vars
But **NOTHING is using it**.

### **Issue #5: New ThemeProvider Compatibility Issues**
Even if we switch to the new `ThemeProvider.jsx`:
- Field name mismatch: palettes use `bg`, but `paletteToThemeColors()` converts to `background`
- `legacyAdapter.ts` doesn't include `bg` alias (you already fixed this in previous work)
- CSS var injection might be incomplete

---

## 📋 WHAT NEEDS TO BE DONE

### Phase 1: Unified Theme Resolution
Create a **single resolver function** that both storefront and onboarding preview use:

```typescript
// apps/web/src/theme/resolveEffectiveTheme.ts
export interface ThemeResolveInput {
  templateKey?: string;        // e.g., 'template_1', 'first'
  paletteKey?: string;         // e.g., 'starter_default', 'dark_default'
  tenantThemeConfig?: object;  // DB overrides
  isDarkMode?: boolean;        // fallback for dark/light toggle
  defaults?: {
    templateKey?: string;
    paletteKey?: string;
  };
}

export function resolveEffectiveTheme(input: ThemeResolveInput): Theme {
  // Normalize templateKey (template_1 → first, etc.)
  // Resolve paletteKey (fallback to starter_default)
  // Resolve palette colors
  // Inject into createTheme()
  // Return legacyAdapter-formatted theme ready for styled-components
}
```

### Phase 2: App.jsx Refactor
Replace hardcoded theme selection with:
```jsx
// In App.jsx or new useEffectiveTheme() hook
const { homeData } = useFetchHomeData();
const effectiveTheme = resolveEffectiveTheme({
  templateKey: homeData?.config?.templateKey,
  paletteKey: homeData?.config?.paletteKey,
  tenantThemeConfig: homeData?.config?.themeConfig,
  isDarkMode: isDarkTheme, // fallback if API data missing
  defaults: {
    templateKey: 'first',
    paletteKey: 'starter_default'
  }
});

<ThemeProvider theme={effectiveTheme}>
```

### Phase 3: Onboarding Preview Integration
In admin's `PreviewFrame`, use the SAME resolver:
```jsx
// admin/src/components/PreviewFrame.tsx
const effectiveTheme = resolveEffectiveTheme({
  templateKey: previewState.templateKey,
  paletteKey: previewState.paletteKey,
  themeOverride: previewState.themeVars,
});
```

### Phase 4: Guardrails & Debugging
- Add `ThemeDebugPanel` (DEV only) showing effective theme values
- Validate contrasts (warn if text/bg are too similar)
- Warn if palette/template keys are undefined
- Log theme resolution steps

---

## 🎯 ACCEPTANCE CRITERIA MAPPING

| Criterion | Status | File/Component | Note |
|-----------|--------|---|---|
| **Dynamic preview updates** | ❌ | Admin `PreviewFrame` | Need unified resolver |
| **Contrast legibility** | ❌ | `resolveEffectiveTheme` | Add validation |
| **Same logic for both** | ❌ | New resolver function | Create single source of truth |
| **No duplicate sources** | ❌ | App.jsx + Admin | Both should use resolver |
| **Debug panel** | ❌ | `ThemeDebugPanel.jsx` | Create DEV-only component |
| **Palette/template support** | ⚠️ | New system exists | But not wired up |

---

## 📦 FILES TO MODIFY/CREATE

### New Files
- `apps/web/src/theme/resolveEffectiveTheme.ts` - MAIN RESOLVER
- `apps/web/src/hooks/useEffectiveTheme.ts` - Hook wrapper
- `apps/web/src/components/ThemeDebugPanel.jsx` - DEV-only debugging
- `apps/web/src/theme/README.md` - Documentation

### Modified Files
- `apps/web/src/App.jsx` - Use new resolver
- `apps/web/src/theme/index.ts` - Expose resolver, add normalization
- `apps/web/src/theme/legacyAdapter.ts` - Add `bg` alias (already done?)
- `apps/admin/src/components/PreviewFrame.tsx` - Use resolver for preview
- `apps/web/src/globalStyles.jsx` - Keep for backward compat, but mark as deprecated

### Potentially Delete
- Old hardcoded theme exports from `globalStyles.jsx` (after refactor complete)

---

## 🔗 COMPARISON TABLE

| Aspect | `feature/automatic-multiclient-onboarding` | `feature/multitenant-storefront` |
|--------|---|---|
| **Theme system** | Hardcoded per template | Hardcoded (NEW system exists but unused) |
| **Palette support** | ❌ No | ✅ YES (not wired) |
| **Template resolution** | Manual dark/light toggle | Manual dark/light toggle (same bug) |
| **Preview support** | Separate branch? | Exists in admin, not integrated |
| **Token names** | Varies by template object | Normalized (bg, surface, text, etc.) |
| **CSS vars injection** | Via `useThemeVars()` | Same `useThemeVars()` |
| **GlobalStyle usage** | Direct hardcoded imports | Same (not using new system) |

---

## 💡 KEY INSIGHT

**The new theme system is 80% built, but wiring is missing:**
- ✅ Palette registry with 15+ hardcoded palettes
- ✅ `createTheme()` factory that merges template + palette + overrides
- ✅ `toLegacyTheme()` adapter for styled-components compatibility
- ✅ `ThemeProvider` component (React wrapper)
- ✅ Type definitions for Theme shape

**But**:
- ❌ Never called from App.jsx
- ❌ Onboarding doesn't use it for preview
- ❌ `homeData.config.paletteKey` from API is ignored
- ❌ No unified resolver that both storefront and preview share

**Solution**: Create `resolveEffectiveTheme()` function that:
1. Normalizes inputs (template_1 → first)
2. Falls back to defaults
3. Calls `createTheme()`
4. Calls `toLegacyTheme()`
5. Returns ready-to-use theme object

Then wire it in:
- App.jsx for storefront
- PreviewFrame for onboarding
- Both use **exactly the same logic** ← Prevents divergence

---

## 📝 NEXT STEP

Implement Phase 1: `resolveEffectiveTheme.ts` with full logic and documentation.

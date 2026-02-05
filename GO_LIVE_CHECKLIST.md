# 🚀 Go-Live Checklist - Theme System Refactor

**Date**: 2026-02-04  
**Branch**: `feature/multitenant-storefront`  
**Status**: ✅ READY FOR VALIDATION

---

## Pre-Validation (Preparación)

- [ ] **Read**: [THEME_QUICK_REFERENCE.md](./THEME_QUICK_REFERENCE.md) (5 min)
- [ ] **Understand**: What changed and why
- [ ] **Locate**: Browser DevTools ready
- [ ] **Terminal**: Have 2 terminals ready (for `npm run dev`)

---

## Step 1: Compilation Check (5 minutes)

```bash
# Terminal 1: Validate types
cd /Users/eliaspiscitelli/Documents/NovaVision/NovaVisionRepo/apps/web
npm run typecheck

# Expected output:
# ✅ No TypeScript errors

# Check linting (optional)
npm run lint

# Expected output:
# ✅ No new ESLint errors (warnings are ok if pre-existing)
```

**If fails**: 
- [ ] Check `/apps/web/src/App.jsx` for syntax errors
- [ ] Check `/apps/web/src/theme/resolveEffectiveTheme.ts` for imports
- [ ] Run `npm install` if dependencies missing

---

## Step 2: Development Server (5 minutes)

```bash
# Terminal 2: Start dev server
npm run dev

# Expected output:
# ✅ ➜ Local: http://localhost:5173/
# ✅ ➜ press q to quit
# ✅ No errors in console
```

**If fails**:
- [ ] Check if port 5173 is already in use (`lsof -i :5173`)
- [ ] Check if `/apps/api` is running (needed for API calls)
- [ ] Clear cache: `npm run dev -- --force`

---

## Step 3: Visual Inspection (10 minutes)

### 3.1: Page Loads
```
Open: http://localhost:5173 in browser
```

**Verify**:
- [ ] Page loads without errors
- [ ] Header visible with menu
- [ ] Products/content visible
- [ ] Console: no red errors (yellow warnings ok)

### 3.2: Find Debug Panel
```
Look for: 🎨 button in top-right corner (floating)
Position: Fixed top-right, size ~40px, blue border
```

**If not visible**:
- [ ] You must be in dev mode (`npm run dev` not `npm run build`)
- [ ] Check browser console for errors
- [ ] Hard refresh: Ctrl+Shift+R (Windows) or Cmd+Shift+R (Mac)

### 3.3: Open Debug Panel
```
Click: 🎨 button
```

**Verify**:
- [ ] Panel opens (should not be full-screen)
- [ ] Shows "THEME DEBUG" header
- [ ] Shows "Configuration" section with:
  - Template: (should show template name, not "?")
  - Palette: (should show palette name, not "?")
  - Dark Mode: (YES or NO)

---

## Step 4: Theme Validation (15 minutes)

### 4.1: Colors Section
```
In debug panel, look at "Colors" section
```

**Verify**:
- [ ] Multiple colors listed (background, text, primary, etc.)
- [ ] Each color shows hex code (not "undefined")
- [ ] Small colored squares next to each color (swatches)
- [ ] Colors are NOT all the same (would indicate failure)

### 4.2: Contrast Check
```
In debug panel, look at "Contrast Check" section
```

**Verify**:
- [ ] Shows ratio like "5.2:1 (AA)" or "7.5:1 (AAA)"
- [ ] NOT showing red ❌ indicator (would mean contrast failure)
- [ ] Green ✅ or Yellow ⚠️ are OK
- [ ] If RED: something is wrong with palette (but app doesn't crash)

### 4.3: No Warnings
```
In debug panel, look at warnings section
```

**Verify**:
- [ ] Either shows "✓ All Checks Pass" (green)
- [ ] OR shows warnings (yellow) - this is ok, just informational
- [ ] NO red errors

### 4.4: Components Section
```
In debug panel, look at "Components" section
```

**Verify**:
- [ ] Shows color values for header, button, card
- [ ] Not empty or "undefined"
- [ ] Matches colors from "Colors" section

---

## Step 5: Interaction Testing (10 minutes)

### 5.1: Dark Mode Toggle
```
Location: Click button in header (usually moon icon)
```

**Verify**:
- [ ] Panel updates - "Dark Mode:" changes from YES to NO or vice versa
- [ ] Colors in panel change (inverted if supported)
- [ ] Page colors change visually (if dark theme supported)
- [ ] No console errors

### 5.2: Console Inspection
```
In debug panel, click "Log to Console" button
```

**Verify**:
- [ ] DevTools console shows object dump
- [ ] Shows "Full theme:" object
- [ ] Shows "Debug data:" with color values
- [ ] Can expand objects to inspect

### 5.3: Close/Reopen Panel
```
Click: 🎨 button again to close
Click: 🎨 button again to open
```

**Verify**:
- [ ] Panel closes cleanly
- [ ] Button still clickable
- [ ] Panel reopens in same state

---

## Step 6: CSS Variables Check (5 minutes)

```
In browser:
1. Press F12 (Open DevTools)
2. Go to Elements/Inspector tab
3. Find: <html> element at top
4. Look at Styles panel on right
```

**Verify**:
- [ ] See `data-theme="light"` or `data-theme="dark"` attribute
- [ ] CSS variables exist: Look for `--nv-*` (like `--nv-bg`, `--nv-primary`)
- [ ] Variables have hex values (not undefined)

**Command to verify** (in console):
```javascript
// Copy-paste into DevTools console:
const vars = getComputedStyle(document.documentElement);
console.log('--nv-bg:', vars.getPropertyValue('--nv-bg'));
console.log('--nv-text:', vars.getPropertyValue('--nv-text'));
console.log('--nv-primary:', vars.getPropertyValue('--nv-primary'));
```

Expected output:
```
--nv-bg:      #FFFFFF (or similar hex)
--nv-text:    #0B1220 (or similar hex)
--nv-primary: #1D4ED8 (or similar hex)
```

---

## Step 7: Special Cases (Optional but Recommended)

### 7.1: Test Palette Change (If API supports)
```
If your test data has different palettes, try accessing them:
- Different client with different paletteKey
- Or modify homeData mock to test fallbacks
```

**Verify**:
- [ ] Colors update when palette changes
- [ ] Debug panel shows new palette name
- [ ] No console errors

### 7.2: Test Dark Mode Support
```
Browser setting: Open DevTools → F12 → ... menu → More tools → Rendering
Look for: "Emulate CSS media feature prefers-color-scheme"
Select: "dark" or "light"
```

**Verify**:
- [ ] Page colors respond (if template supports dark mode)
- [ ] Debug panel updates dark mode status
- [ ] Contrast still valid

### 7.3: Test Error Handling
```
Mock missing data by:
1. Opening DevTools Network tab
2. Blocking API response
3. Refreshing page
```

**Verify**:
- [ ] App shows loading state or error gracefully
- [ ] Uses fallback theme ('fifth'/'starter_default')
- [ ] Doesn't crash

---

## Step 8: Known Good States

### ✅ Good State (What You Should See)

```
✅ App loads without console errors
✅ Header visible with correct styling
✅ Debug panel (🎨) accessible
✅ Colors show in debug panel (not undefined)
✅ Contrast ratio >= 4.5:1 (AA level)
✅ Text is readable (not dark-on-dark)
✅ Dark mode toggle works
✅ CSS variables present in <html>
✅ No visual glitches or broken layouts
```

### ❌ Bad States (Something Wrong)

```
❌ Console has red errors about theme
❌ Debug panel doesn't open
❌ Colors show "undefined"
❌ Contrast shows "FAIL" (red) + text unreadable
❌ Dark mode toggle does nothing
❌ CSS variables missing from <html>
❌ Page layout broken or text invisible
```

If you see any ❌ state, refer to troubleshooting below.

---

## Step 9: Troubleshooting

### Problem: Debug Panel Not Showing

**Cause**: You're not in dev mode

**Fix**:
```bash
# Make sure you're running:
npm run dev

# NOT:
npm run build  # or npm run preview
```

**Verify**: URL should be `http://localhost:5173` (Vite dev, not production)

---

### Problem: "Dark on Dark" - Text Unreadable

**Cause**: Contrast is too low (FAIL in red)

**Fix**:
1. Check debug panel - what palette is selected?
2. If wrong palette, report it (API issue)
3. As workaround: toggle dark mode to try light theme
4. If still broken: check if theme has color injection issues

**Debug**:
```javascript
// In DevTools console:
const style = getComputedStyle(document.body);
console.log('Background:', style.backgroundColor);
console.log('Color:', style.color);
```

---

### Problem: Colors Show "undefined"

**Cause**: Theme resolver returned incomplete theme

**Fix**:
1. Check browser console for errors
2. Click "Log to Console" in debug panel
3. Look at the theme object - what's missing?
4. Report error with theme structure

**Common Causes**:
- `createTheme()` not being called correctly
- Palette colors not injected
- Template not found

---

### Problem: CSS Variables Missing

**Cause**: `useThemeVars()` hook not running

**Fix**:
1. Check App.jsx has `useThemeVars(theme)` call
2. Check if `useThemeVars.ts` has import
3. If missing, add line in App.jsx:
   ```jsx
   useThemeVars(theme);
   ```

---

### Problem: Lint Errors

**Common Errors**:
- `Module not found`: Missing import
- `'any' is not allowed`: Type missing
- `Unused variable`: Clean up code

**Fix**:
```bash
npm run lint -- --fix  # Auto-fixes many issues
```

---

## Step 10: Final Sign-Off

If you've reached here and all checks passed, you can sign-off ✅:

```
✅ Compilation passes
✅ Dev server runs
✅ Page loads
✅ Debug panel works
✅ Colors valid
✅ Contrast adequate
✅ Dark mode works
✅ CSS variables present
✅ No breaking changes
✅ Ready for production
```

---

## Next Phase: Admin Integration

Once storefront is validated, next phase is admin app integration.

**Docs**: [THEME_ADMIN_INTEGRATION.md](./THEME_ADMIN_INTEGRATION.md)

**What's needed**:
- [ ] Copy resolver to `/apps/admin/src/services/`
- [ ] Update PreviewFrame component
- [ ] Create template/palette selectors UI
- [ ] Test that preview updates in real-time

**Estimated time**: 1-2 hours

---

## Reference Links

| Document | Purpose |
|----------|---------|
| [THEME_QUICK_REFERENCE.md](./THEME_QUICK_REFERENCE.md) | One-page overview |
| [THEME_VALIDATION_MANUAL.md](./THEME_VALIDATION_MANUAL.md) | Detailed validation steps |
| [THEME_ADMIN_INTEGRATION.md](./THEME_ADMIN_INTEGRATION.md) | Admin app integration |
| [THEME_FINAL_SUMMARY.md](./THEME_FINAL_SUMMARY.md) | Project summary |

---

## Support

**Issue**: Refer to [THEME_VALIDATION_MANUAL.md](./THEME_VALIDATION_MANUAL.md) "Troubleshooting" section.

**Question**: Check [THEME_QUICK_REFERENCE.md](./THEME_QUICK_REFERENCE.md) FAQ.

**Emergency**: Check App.jsx imports and resolve function calls.

---

**Status**: Ready for validation  
**Estimated time**: 45 minutes total  
**Difficulty**: Easy (mostly clicking and observing)  
**Risk level**: Low (read-only validation)

**👉 START HERE**: Step 1 - Compilation Check

# Cambio: UI Fixes (AnnouncementBar, Footer links, Social icons) + Admin CI Fix

- **Autor:** agente-copilot
- **Fecha:** 2026-02-19
- **Ramas:**
  - Web: `develop` → cherry-pick a `feature/multitenant-storefront` + `feature/onboarding-preview-stable`
  - Admin: `develop`

---

## Resumen

### Web (templatetwo) — 3 UI Fixes

1. **AnnouncementBar layout fix:**
   - Movido de `HomeRouter` a `App.jsx` para visibilidad global (antes desaparecía al navegar)
   - Cambiado de `position: sticky` → `position: fixed; top: 0` con `z-index: 10001`
   - Introducido CSS variable `--announcement-height` que se setea dinámicamente con `useLayoutEffect` + `ResizeObserver`
   - Header usa `top: var(--announcement-height, 0px)` para posicionarse debajo
   - BannerHome margin-top incluye `var(--announcement-height, 0px)`
   - ContentWrapper padding-top incluye announcement height para rutas no-home

2. **Social icons centering:**
   - Agregado `justify-content: center` y `flex-wrap: wrap` al `SocialLinksContainer` en ContactSection

3. **Footer dynamic links:**
   - Reemplazados los links de navegación hardcodeados en inglés ("Sell online", "Features", etc.) por links dinámicos desde `identity_config.footer.links`
   - Soporte para ambos formatos: `{label, url}` y `{text, url}` (backward compat)
   - Todos los footer variants en `COMPONENT_MAP` reciben la prop `footerLinks`
   - La sección de navegación solo se renderiza si hay links configurados

### Admin (novavision) — CI Fix

1. **package-lock.json regenerado:** Incluye `driver.js` y otras deps que estaban en `package.json` pero no en el lock file → `npm ci` fallaba
2. **3 archivos faltantes traídos a develop:**
   - `DevPortalWhitelistView.jsx` — gestión whitelist dev portal
   - `ShippingView.jsx` — panel shipping super admin
   - `SubscriptionEventsView.jsx` — panel observabilidad suscripciones
   - Estos archivos existían en `feature/automatic-multiclient-onboarding` pero los cherry-picks previos solo trajeron los imports en `App.jsx` sin los archivos → build fallaba

---

## Archivos modificados

### Web
- `src/App.jsx` — import AnnouncementBar, render antes de Header
- `src/components/AnnouncementBar/index.jsx` — useRef, useLayoutEffect, ResizeObserver
- `src/components/AnnouncementBar/style.jsx` — fixed positioning
- `src/globalStyles.jsx` — :root CSS vars, ContentWrapper adjustment
- `src/routes/HomeRouter.jsx` — removed AnnouncementBar render
- `src/templates/fifth/components/BannerHome/style.jsx` — margin-top calc
- `src/templates/fifth/components/Header/style.jsx` — top offset
- `src/templates/fifth/components/ContactSection/style.jsx` — social centering
- `src/templates/fifth/components/Footer/index.jsx` — dynamic footerLinks
- `src/templates/fifth/pages/Home/index.jsx` — pass footerLinks to all footer variants

### Admin
- `package-lock.json` — regenerated
- `src/pages/AdminDashboard/DevPortalWhitelistView.jsx` — new file
- `src/pages/AdminDashboard/ShippingView.jsx` — new file
- `src/pages/AdminDashboard/SubscriptionEventsView.jsx` — new file
- `src/pages/AdminDashboard/index.jsx` — nav items for new views

---

## Causa raíz del CI failure

El CI de GitHub Actions del admin repo (rama `develop`) usaba `npm ci`, que requiere que `package-lock.json` esté 100% sincronizado con `package.json`. Las dependencias `driver.js`, `@mui/material`, `@mui/icons-material` y otros se habían agregado a `package.json` sin regenerar el lock file. Además, los cherry-picks previos copiaron imports de componentes (`DevPortalWhitelistView`, `ShippingView`, `SubscriptionEventsView`) sin incluir los archivos correspondientes.

---

## Cómo probar

1. **AnnouncementBar:** Configurar un banner "top" en identity_config → debe aparecer fijo arriba de todo, persistir al hacer scroll, y no superponer el header
2. **Social icons:** Ver sección de contacto en el footer → iconos deben estar centrados
3. **Footer links:** Configurar links custom en admin (identity > footer > links) → deben aparecer en la sección de navegación del footer, reemplazando los hardcodeados
4. **Admin CI:** Push a develop debe pasar `npm ci` + lint + typecheck + build

---

## Riesgos

- El cambio de `position: sticky` a `position: fixed` en AnnouncementBar podría afectar el layout en templates diferentes a "fifth" si usan el componente. Verificar en otros templates.
- Los footer variants reciben `footerLinks` pero solo `footer.fifth` (Footer/index.jsx) lo usa activamente. Otros variants lo ignoran silenciosamente.

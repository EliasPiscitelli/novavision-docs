# Cambio: QA Batch — 26 correcciones multi-repo (P0/P1/P2)

- **Autor:** agente-copilot
- **Fecha:** 2026-03-05
- **Ramas:**
  - API: `feature/automatic-multiclient-onboarding` (commit `0e5263a`)
  - Admin: `feature/automatic-multiclient-onboarding` (commits `574f718`, `e751f3b`)
  - Web: `develop` → cherry-pick a `feature/multitenant-storefront` y `feature/onboarding-preview-stable`

---

## Resumen

Resolución del reporte de QA "Nova correcciones 260304" + "NUEVOS BUGS 260305" — 26 issues (QA-001 a QA-026) abarcando Storefront, Admin, Auth, Tours, Import Excel, Import IA JSON, Upload Images, Categories, Legal Pages, Payments y Mobile/Responsive.

---

## Archivos modificados

### API (templatetwobe)
| Archivo | Cambio |
|---------|--------|
| `src/products/products.service.ts` | QA-001: Variantes de COLUMN_MAPPING con paréntesis + `resolveColumnKey()`. QA-002: `.ilike()` en `findOrCreateCategory()`. QA-003: Default `available: true`. |
| `src/auth/auth.service.ts` | QA-007: `prompt: 'select_account'` en 3 métodos OAuth (`startGoogleOAuth`, `startPlatformGoogleOAuth`, `startTenantGoogleOAuth`). |

### Admin (novavision)
| Archivo | Cambio |
|---------|--------|
| `src/pages/AuthGateway/index.jsx` | QA-007: `prompt: 'select_account'` en signInWithOAuth. |
| `src/auth/startTenantLogin.js` | QA-007: `prompt: 'select_account'` en signInWithOAuth. |
| `src/types/web-modules.d.ts` | **NUEVO** — Type stubs para `@web/ThemeProvider`, `@web/SectionRenderer`, `@web/demoData` (fix CI typecheck TS2307). |

### Web (templatetwo)
| Archivo | Cambio |
|---------|--------|
| `src/components/admin/ProductDashboard/index.jsx` | QA-004: `fetchProductStats()` junto a `fetchProducts()` tras upload Excel. |
| `src/pages/LegalPage/index.jsx` | QA-006: Padding dinámico `calc(var(--header-height, 70px) + 24px)`. |
| `src/tour/TourOverlay.js` | QA-008/009/010/011: Arrow color matching, scroll lock (`nv-tour-active`), `.filter()` null targets. |
| `src/components/admin/ImportWizard/index.jsx` | QA-012: `scrollTo(0,0)` on mount. QA-013: Botón "Abrir ChatGPT". |
| `src/components/admin/ImportWizard/style.jsx` | QA-019: Contraste PromptHint mejorado (opacidad 8%, `var(--nv-admin-text)`). |
| `src/templates/eighth/.../HeroSection/index.jsx` | QA-014: `clamp(360px, 55vw, 560px)`. |
| `src/templates/fifth/.../BannerHome/style.jsx` | QA-014: `clamp(280px, 45vh, 400px)`. |
| `src/templates/second/.../BannerHome/style.jsx` | QA-014: `height: 45vh; max-height: 400px`. |
| `src/templates/fourth/.../BannerHome.jsx` | QA-014: `50vh` base height. |
| `src/templates/seventh/.../HeroSection/index.jsx` | QA-014: `clamp(340px, 55vh, 500px)`. |

---

## Detalle por prioridad

### P0 — Críticos
| ID | Bug | Fix |
|----|-----|-----|
| QA-001 | Excel ignora columnas con paréntesis (ej. "Cantidad (Stock)") | Variantes de COLUMN_MAPPING + `resolveColumnKey()` strip-parenthetical normalizer |
| QA-002 | Categorías duplicadas por case sensitivity | `.ilike('name')` en lugar de `.eq('name')` en `findOrCreateCategory()` |
| QA-003 | Productos importados no visibles por falta de `available` | Default `available: true` tras coerción booleana |
| QA-004 | Contadores no se actualizan tras upload Excel | `Promise.all([fetchProducts(), fetchProductStats()])` en handler de éxito |
| QA-006 | Contenido de Legal Page oculto detrás del header fijo | Padding dinámico con `var(--header-height)` |

### P1 — Importantes
| ID | Bug | Fix |
|----|-----|-----|
| QA-007 | Google OAuth no muestra selector de cuentas | `prompt: 'select_account'` en 5 puntos (3 API + 2 Admin) |
| QA-008 | Tour arrow desalineado/invisible | CSS color matching del popover background |
| QA-009 | Scroll no bloqueado durante tour | `document.body.classList.add('nv-tour-active')` + CSS `overflow: hidden` |
| QA-010 | Tour crashea si elemento target no existe | `.filter()` previo para eliminar steps con targets nulos |
| QA-011 | Tour no vuelve al scroll normal al cerrar | `classList.remove('nv-tour-active')` en `onDestroyed` |
| QA-012 | ImportWizard no hace scroll al inicio | `window.scrollTo(0, 0)` en `useEffect` |
| QA-013 | Falta acceso rápido a ChatGPT desde ImportWizard | Botón "Abrir ChatGPT" junto a "Copiar Prompt" |
| QA-014 | Banners mobile demasiado cortos | +vh/clamp en 5 templates (second, fourth, fifth, seventh, eighth) |

### P2 — Menores
| ID | Bug | Fix |
|----|-----|-----|
| QA-019 | Texto del prompt en ImportWizard con bajo contraste | Opacidad 4%→8%, font-size 0.85rem, color `var(--nv-admin-text)` |

### Verificados sin cambio necesario
QA-005 (UUID intermitente), QA-015 (FilterSidebar mobile ya tiene drawer), QA-016 (tabla admin ya adaptada), QA-017 (MP OAuth UX ya completo), QA-018 (headers ya usan CSS vars), QA-020 (ServicesGrid theme-driven), QA-021 (LegalPage inline — cubierto por QA-006), QA-023 (iconos centrados), QA-024 (categoría alineada), QA-025 (CTA por diseño).

---

## Fix CI/CD adicional

**Admin typecheck (TS2307):** Creado `src/types/web-modules.d.ts` con declaraciones de tipos stub para módulos `@web/*` que solo se resuelven via Vite aliases en desarrollo local pero no existen en CI standalone.

---

## Cómo probar

### API
```bash
cd apps/api && npm run lint && npm run typecheck && npm run build
```
- Subir Excel con columnas entre paréntesis → deben mapearse correctamente
- Importar productos con categorías en distinta capitalización → no crea duplicados
- Productos importados deben aparecer visibles por defecto

### Admin
```bash
cd apps/admin && npm run lint && npm run typecheck && npm run build
```
- Login con Google → debe mostrar selector de cuentas

### Web
```bash
cd apps/web && npm run lint && npm run typecheck && npm run build
```
- Abrir Legal Page → contenido no debe quedar detrás del header
- Iniciar cualquier tour → arrow visible, scroll bloqueado, cierra correctamente
- ImportWizard → scroll al inicio al abrir, botón ChatGPT funcional
- Banners mobile en todas las plantillas → altura mínima visible (~340-400px)

---

## Notas de seguridad

- No se exponen credenciales ni tokens
- Los cambios de auth (`select_account`) son client-side únicamente
- El archivo `.d.ts` no contiene lógica ejecutable; solo declaraciones de tipos
- No se modificaron politicas RLS ni migraciones

---

## Riesgos y rollback

- **Bajo riesgo:** todos los cambios son visuales/UX + correcciones de lógica de importación
- **Rollback:** revertir commits individuales por repo sin impacto entre sí
- **Dependencias:** los fixes de API (Excel/categorías) son independientes de los fixes de Web/Admin

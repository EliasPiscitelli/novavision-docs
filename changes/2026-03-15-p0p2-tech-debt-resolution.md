# P0–P2 Tech Debt Resolution + Test Fixes

**Fecha:** 2026-03-15
**Rama:** develop
**Alcance:** Web, Admin, API

---

## Resumen

Resolución de deuda técnica P0–P2, corrección de 6 tests pre-existentes, e implementación de features pendientes del roadmap técnico.

---

## Cambios implementados

### Tests corregidos (6/6)

| Test | Archivo | Causa raíz | Fix |
|------|---------|-----------|-----|
| contact legacy fallback | `contact-section-renderer.test.jsx` | `sectionCatalog` default `showMap: false` | Agregado `showMap: true` al props legacy |
| preview native render (×2) | `preview-host.test.jsx` | PreviewHost requiere `sections.length > 1` para native template | Agregada segunda sección (footer) al payload |
| store design heading (×2) | `store-design-section.test.jsx` | Heading renombrado a español | `Design Studio` → `Diseño de Tienda` |
| store design save button | `store-design-section.test.jsx` | Botón renombrado | `Guardar y aplicar diseño` → `Guardar diseño`, `Aplicar estructura` → `Aplicar cambios` |

### P0 — MP redirect dinámico

- **Archivo:** `apps/admin/src/pages/BuilderWizard/steps/Step7MercadoPago.tsx`
- **Problema:** Fallback hardcodeado `https://novavision-production.up.railway.app` cuando `VITE_BACKEND_API_URL` no estaba definido
- **Fix:** Eliminado fallback hardcodeado. Si la URL no se resuelve, muestra error al usuario en vez de redirigir al servidor incorrecto

### P1 — FiscalIdValidator para Brasil (CNPJ/CPF)

- **Archivo:** `apps/api/src/common/fiscal-id-validator.service.ts`
- **Agregado:** Validación check digit para Brasil
  - CPF: 11 dígitos, 2 dígitos verificadores Mod 11, pesos crecientes
  - CNPJ: 14 dígitos, 2 dígitos verificadores Mod 11, pesos [5,4,3,2,9,8,7,6,5,4,3,2] y [6,5,4,3,2,9,8,7,6,5,4,3,2]
  - Rechaza secuencias inválidas (todos dígitos iguales)
  - Despacha por longitud: 11 → CPF, 14 → CNPJ

### P1 — runStep wrapping para jobs secundarios

- **Archivo:** `apps/api/src/worker/provisioning-worker.service.ts`
- `SEED_TEMPLATE`: 2 pasos envueltos (`seed_home_page`, `seed_contact_page`)
- `SYNC_ENTITLEMENTS`: 3 pasos envueltos (`calculate_entitlements`, `sync_admin_entitlements`, `sync_backend_entitlements`)
- Beneficio: Idempotencia, resumibilidad y trazabilidad auditables

### P2 — Logo dual source of truth

- **Archivos:** `provisioning-worker.service.ts`, `logo.service.ts`
- **Fix provisioning:** Después de insertar en `logos` table, ahora también sincroniza a `client_home_settings.identity_config.logo`
- **Fix upload:** Cambiado catch silencioso por `console.warn` con contexto del error
- **Resultado:** Stores recién provisionados tienen logo sincronizado en ambas fuentes desde el inicio

### P2 — Entitlements recalculation (ya implementado)

- Verificado: `syncEntitlementsAfterUpgrade()` ya existía en `subscriptions.service.ts:4891`
- Incluye: upgrade, cancel, outbox events (`plan.changed`, `entitlements.synced`)
- No requirió cambios

---

## Validación

- ✅ 87/87 tests pasando (web)
- ✅ API typecheck limpio
- ✅ Build web: 7.72s OK
- ✅ Build admin: 5.09s OK
- ✅ Lint: 0 errores

---

## Items P3 — Roadmap futuro

Los siguientes items se documentan como mejoras para versiones futuras, no prioritarios para el MVP/lanzamiento:

| # | Feature | Descripción | Complejidad |
|---|---------|-------------|-------------|
| 1 | Blog/CMS por tenant | Sistema de blog integrado en cada tienda | Alta |
| 2 | Email marketing integrado | Campañas email desde el admin con templates | Alta |
| 3 | Marketplace multi-seller | Modelo marketplace donde varios sellers publican en una tienda | Muy alta |
| 4 | AI Chat / Chatbot | Asistente inteligente para compradores | Media |
| 5 | Multi-idioma (i18n) | Storefront traducible a múltiples idiomas | Alta |
| 6 | Stripe / PayPal | Pasarelas de pago alternativas a MercadoPago | Media |
| 7 | POS integrado | Punto de venta físico sincronizado con el e-commerce | Alta |
| 8 | API pública para integradores | REST/GraphQL abierto para que terceros integren | Media |
| 9 | Inventario multi-sucursal | Stock por ubicación física | Alta |
| 10 | Search Console integration | Indexación automática y sitemap dinámico | Baja |
| 11 | Google Ads integration | Conversiones y remarketing | Baja |
| 12 | CAPI server-side (Meta) | Conversion API server-side por tenant | Media |
| 13 | Dashboard analytics por tenant | Panel de métricas individual para cada tienda | Media |
| 14 | Exportación de productos (CSV) | Bulk export del catálogo | Baja |
| 15 | Categorías jerárquicas | Árbol de categorías con subcategorías | Media |
| 16 | Carriers internacionales | DHL, FedEx, UPS para envíos cross-border | Alta |

**Criterio de priorización:** Estos items no bloquean el lanzamiento y se implementarán según demanda del mercado post-launch.

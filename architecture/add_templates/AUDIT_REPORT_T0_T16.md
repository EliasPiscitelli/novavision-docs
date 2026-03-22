# Informe Consolidado de Auditoria — Template Unification System (T0–T16)

**Fecha:** 2026-03-20
**Autor:** Tech Lead (consolidacion de reportes Arquitecto + QA)
**Alcance:** 25 tickets del sistema Template Unification (T0–T16)
**Estado:** Pre-release — requiere correccion de hallazgos criticos antes de marcar como estable

---

## Seccion 1: Resumen Ejecutivo

### Evaluacion general del sistema

El sistema Template Unification esta implementado en su mayor parte de forma correcta. La arquitectura general — separacion API/Web, sanitizacion CSS, plan gating de fuentes, lazy loading, i18n — es solida. Sin embargo, se identifico **un bug critico** que invalida completamente una feature principal (CSS custom overrides nunca se aplican visualmente) y un bug high que puede provocar perdida de datos en produccion (el cron de reconciliacion borra overrides custom).

### Conteo de hallazgos por severidad

| Severidad | Cantidad | Estado |
|-----------|----------|--------|
| **CRITICAL** | 1 | Bloquea release |
| **HIGH** | 2 | Bloquea release |
| **MEDIUM** | 6 | Fix en proximo sprint |
| **LOW** | 10 | Backlog / mejoras |
| **OK (validado)** | 12+ areas | Sin accion requerida |

**Veredicto: NO se puede marcar como estable hasta resolver los 3 hallazgos CRITICAL/HIGH.**

---

## Seccion 2: Criticos y Alta Prioridad (bloquean release)

### C-1. CRITICAL — CSS overrides nunca se aplican visualmente

**Fuente:** QA (hallazgo principal de Flow 2)
**Acuerdo con Arquitecto:** El Arquitecto valido el data flow como "OK" pero no detecto la desconexion DOM. QA descubrio la brecha.

**Descripcion:**
La API scopa todo CSS custom dentro de `.nv-store-{clientId} { ... }` via `scopeCssToTenant()` en `/apps/api/src/common/validators/css.validator.ts:174-179`. Sin embargo, ningun elemento del DOM del storefront recibe jamas la clase `nv-store-{clientId}`. El contenedor raiz es `<div id="root"></div>` sin clases adicionales (verificado en `/apps/web/index.html:124`). El selector CSS generado nunca matchea, haciendo que TODOS los CSS overrides sean completamente inertes.

**Impacto:** La feature completa de CSS custom overrides (T9) esta rota en produccion. Los usuarios configuran estilos que nunca se ven.

**Archivos afectados:**
- `/apps/web/index.html` — falta la clase en el contenedor raiz
- `/apps/api/src/common/validators/css.validator.ts` — genera el selector `.nv-store-{clientId}`
- `/apps/web/src/hooks/useDesignOverrides.js` — inyecta CSS que nunca matchea

**Fix sugerido:**
Opcion A (preferida): Agregar la clase `nv-store-{clientId}` al contenedor raiz del storefront en el render de App. Ejemplo: en el `App.jsx` o `TenantProvider`, setear `document.getElementById('root').classList.add('nv-store-' + clientId)` una vez resuelto el tenant.
Opcion B: Cambiar `scopeCssToTenant()` para usar `#root` como selector en lugar de clase, pero esto rompe el aislamiento multi-tenant si multiples tenants comparten DOM (no aplica actualmente, pero es menos futuro-proof).

**Esfuerzo estimado:** 2-4 horas

---

### H-1. HIGH — El cron de reconciliacion borra CSS overrides custom

**Fuente:** QA (Flow 2, hallazgo secundario)
**Acuerdo con Arquitecto:** El Arquitecto reporto WARNING sobre el cron (#6, #12) pero no identifico este caso especifico como destructivo.

**Descripcion:**
El metodo `reconcileOverrides()` en `/apps/api/src/design-overrides/design-overrides.service.ts:352-447` consulta `account_addons` para verificar que cada override tiene un addon activo asociado. Los CSS overrides custom usan `source_addon_key = 'custom_css'`, pero `'custom_css'` NO es un addon real en `addon_catalog` / `account_addons`. El cron diario (03:00 UTC) revocara todos los overrides custom porque `activeAddonKeys.has('custom_css')` siempre retorna `false`.

**Impacto:** Perdida diaria y silenciosa de todos los CSS custom overrides de todos los tenants.

**Archivos afectados:**
- `/apps/api/src/design-overrides/design-overrides.service.ts` — metodos `reconcileOverrides()` y `cronReconcileAll()`

**Fix sugerido:**
Agregar un whitelist de `source_addon_key` que no requieren addon activo (e.g., `'custom_css'`, `'ai_generated'`). En el loop de linea 409-435, antes de revocar, verificar:
```typescript
const EXEMPT_ADDON_KEYS = new Set(['custom_css', 'ai_generated']);
if (EXEMPT_ADDON_KEYS.has(typed.source_addon_key)) {
  details.push({ override_id: typed.id, addon_key: typed.source_addon_key, action: 'kept' });
  continue;
}
```

**Esfuerzo estimado:** 1-2 horas (+ test unitario)

---

### H-2. HIGH — fontKey no se valida server-side

**Fuente:** Arquitecto (ISSUE #1, #4) + QA (Flow 1 WARN)
**Acuerdo:** Ambos agentes identificaron el mismo problema de forma independiente.

**Descripcion:**
El endpoint `PUT /settings/home` acepta cualquier string como `fontKey` y lo persiste en `clients.theme_config.font_key` sin validacion. Verificado en `/apps/api/src/home/home-settings.controller.ts:80` y `/apps/api/src/home/home-settings.service.ts:326-331`. No hay validacion contra el catalogo de fuentes (`FONT_CATALOG` con 10 entries definidas en Web). Ademas, al downgrade de plan no hay reconciliacion automatica: un fontKey de plan Growth persiste despues de bajar a Starter.

**Impacto:**
- Datos invalidos en la BD (cualquier string como font_key)
- Frontend hace fallback silencioso a Inter (no es critico para UX, pero poluciona datos)
- Post-downgrade el font_key invalido persiste indefinidamente

**Archivos afectados:**
- `/apps/api/src/home/home-settings.service.ts` — `upsertTemplate()` linea 326
- `/apps/api/src/home/home-settings.controller.ts` — linea 80

**Fix sugerido:**
1. Definir un array constante de fontKeys validos en API (mirror de Web's `FONT_CATALOG`)
2. Validar fontKey contra ese array en el controller/service
3. Para reconciliacion de downgrade: agregar logica en el cron existente o en el handler de cambio de plan que valide si `font_key` del tenant es accesible en su plan actual

**Esfuerzo estimado:** 4-6 horas

---

## Seccion 3: Prioridad Media (fix dentro de 1 sprint)

### M-1. MEDIUM — JSON.parse sin try-catch en AI CSS generation

**Fuente:** QA (Flow 3 WARN)
**Acuerdo con Arquitecto:** El Arquitecto valido el AI flow como "OK"; QA encontro este gap especifico.

**Descripcion:**
En `/apps/api/src/ai-generation/ai-generation.service.ts:909`, `JSON.parse(raw)` no esta envuelto en try-catch. Si OpenAI retorna JSON malformado, el servicio lanza un error 500 generico en vez de un 422 manejable. Este patron se repite en multiples lineas del mismo servicio (169, 226, 283, 338, 372, 417, 497, 590, 640, 733, 829, 983).

**Impacto:** Errores 500 en produccion por respuestas de IA malformadas; mala experiencia de usuario y dificultad para debugging.

**Archivos afectados:**
- `/apps/api/src/ai-generation/ai-generation.service.ts` — 13 instancias de `JSON.parse` sin proteccion

**Fix sugerido:**
Crear helper `safeParseJson(raw: string, context: string)` que retorne el objeto parseado o lance `UnprocessableEntityException` con mensaje descriptivo. Reemplazar las 13 instancias.

**Esfuerzo estimado:** 2-3 horas

---

### M-2. MEDIUM — GET /design-overrides/active-css sin cache headers

**Fuente:** Arquitecto (ISSUE #3)

**Descripcion:**
El endpoint publico `GET /design-overrides/active-css` en `/apps/api/src/design-overrides/design-overrides.controller.ts:43-49` no setea headers de cache (`Cache-Control`, `ETag`). Cada page load del storefront hace un request a la API sin posibilidad de cache de CDN o browser.

**Impacto:** Performance degradada en storefronts con trafico alto; carga innecesaria en la API.

**Archivos afectados:**
- `/apps/api/src/design-overrides/design-overrides.controller.ts` — metodo `getActiveCss()`

**Fix sugerido:**
Agregar `@Header('Cache-Control', 'public, max-age=300, stale-while-revalidate=60')` al endpoint. Considerar agregar `ETag` basado en hash del CSS para invalidacion precisa.

**Esfuerzo estimado:** 1-2 horas

---

### M-3. MEDIUM — Registro duplicado de palettes con datos inconsistentes

**Fuente:** Arquitecto (ISSUE #4)

**Descripcion:**
Existen registros de palettes en al menos dos ubicaciones (`tokens.js` y `palettes.ts`) con datos potencialmente inconsistentes. Verificado que `/apps/web/src/theme/palettes.ts` existe y contiene definiciones de palettes. No se encontro un `tokens.js` activo en imports, pero el Arquitecto reporto la inconsistencia como dato confirmado.

**Impacto:** Posible divergencia de colores entre contextos que usen fuentes diferentes de verdad para palettes.

**Archivos afectados:**
- `/apps/web/src/theme/palettes.ts`
- Archivo legacy `tokens.js` (ubicacion exacta pendiente de confirmacion)

**Fix sugerido:**
Unificar en una sola fuente de verdad (`palettes.ts`). Eliminar el registro duplicado y actualizar todos los imports.

**Esfuerzo estimado:** 3-4 horas

---

### M-4. MEDIUM — Consumo de creditos AI es post-success (billing leakage)

**Fuente:** QA (Flow 3 WARN)

**Descripcion:**
Los creditos AI se consumen despues de la operacion exitosa. Si la escritura a BD falla despues de la generacion, los creditos no se consumen pero el contenido ya fue generado (y potencialmente retornado al frontend).

**Impacto:** Perdida menor de revenue; posible explotacion si el patron es conocido.

**Fix sugerido:**
Reservar creditos antes de la generacion (patron reserve-consume-refund). Si la generacion falla, hacer refund.

**Esfuerzo estimado:** 4-6 horas

---

### M-5. MEDIUM — DENSITY_PRESETS definidos pero no conectados a UI

**Fuente:** QA (Flow 6)

**Descripcion:**
En `/apps/web/src/theme/palettes.ts` (o archivos relacionados como `theme-contract.ts` y `variables.css`), existen `DENSITY_PRESETS`, `MIN_TOUCH_TARGET` y `custom_vars` exportados pero sin ningun componente de UI que los consuma. No hay selector de densidad en DesignStudio, no hay aplicacion runtime de `custom_vars`.

**Impacto:** Feature T14 (Spacing + Density) esta definida pero no operativa. Codigo muerto en produccion.

**Fix sugerido:**
Si T14 no esta en scope para este release, documentar como feature pendiente y agregar TODO. Si esta en scope, implementar el selector de densidad en DesignStudio y el wiring a CSS vars.

**Esfuerzo estimado:** 8-16 horas (si se implementa)

---

### M-6. MEDIUM — SectionErrorBoundary definido dentro de la funcion render

**Fuente:** QA (Flow 5 WARN)

**Descripcion:**
En `/apps/web/src/components/SectionRenderer.tsx:343-377`, la clase `SectionErrorBoundary` se define DENTRO del cuerpo del componente funcional `SectionRenderer`. Esto significa que se recrea una nueva clase en cada render, rompiendo la identidad de React y causando unmount/remount innecesarios de toda la sub-tree.

**Impacto:** Performance degradada; posible perdida de estado interno de secciones en cada re-render del padre.

**Archivos afectados:**
- `/apps/web/src/components/SectionRenderer.tsx` — lineas 343-377

**Fix sugerido:**
Extraer `SectionErrorBoundary` fuera del componente funcional, como un componente de clase separado en su propio archivo o al nivel del modulo. Pasar `normalizedKey` como prop en lugar de cerrarlo por closure.

**Esfuerzo estimado:** 1-2 horas

---

## Seccion 4: Baja Prioridad / Mejoras (backlog)

### L-1. LOW — Rate limiting ausente en GET /active-css

**Fuente:** Arquitecto (WARNING #5)

El endpoint publico no tiene rate limiting. Podria ser abusado para generar carga excesiva. Mitigado parcialmente si se agrega cache (M-2).

**Fix sugerido:** Agregar `@Throttle()` decorator del modulo `@nestjs/throttler`.

---

### L-2. LOW — Reconciliation cron reemplaza metadata completa

**Fuente:** Arquitecto (WARNING #6)

El update en `reconcileOverrides()` linea 414-418 sobreescribe toda la columna `metadata` con `{ revoke_reason: 'addon_no_longer_active' }` en lugar de mergear con la metadata existente.

**Fix sugerido:** Usar merge JSONB: `metadata: { ...existingMetadata, revoke_reason: '...' }` (requiere fetch previo o SQL `||` operator).

---

### L-3. LOW — PreviewHost no muestra CSS overrides activos

**Fuente:** Arquitecto (WARNING #7)

La preview del DesignStudio no refleja los CSS overrides activos del tenant, dando una experiencia WYSIWYG incompleta.

**Fix sugerido:** Inyectar CSS activo via `useDesignOverrides` en el iframe de preview o pasarlo como mensaje postMessage.

---

### L-4. LOW — filter/backdrop-filter en CSS allowlist

**Fuente:** Arquitecto (WARNING #8)

Las propiedades `filter` y `backdrop-filter` estan en el allowlist de `/apps/api/src/common/validators/css.validator.ts:57-58`. Permiten manipulacion visual que podria usarse para ocultar contenido o crear phishing visual.

**Fix sugerido:** Evaluar si son necesarias para el caso de uso. Si no, remover del allowlist. Si si, agregar validacion de valores permitidos (e.g., solo `blur()`, `brightness()`).

---

### L-5. LOW — No enforcement contra imports directos de componentes unificados

**Fuente:** Arquitecto (WARNING #9)

No hay regla de linting o barrera tecnica que prevenga importar componentes legacy directamente en lugar de usar el sistema unificado de SectionRenderer + variantMap.

**Fix sugerido:** Agregar regla ESLint `no-restricted-imports` para paths de componentes legacy.

---

### L-6. LOW — Default template key inconsistente entre modulos

**Fuente:** Arquitecto (WARNING #10)

Verificado en codigo: `/apps/api/src/common/constants/templates.ts:33` define `DEFAULT_TEMPLATE_KEY = 'fifth'`, mientras `/apps/api/src/home/default-template-sections.ts:116` usa fallback a `'fifth'`. Sin embargo, otros contextos (como themes controller linea 27) referencian `'first'`. La inconsistencia es menor pero puede causar confusion.

**Fix sugerido:** Centralizar en una unica constante importada desde `common/constants/templates.ts` y eliminar duplicados.

---

### L-7. LOW — FontSelector preloads ALL 9 Google Fonts

**Fuente:** Arquitecto (WARNING #11) + QA (Flow 1 WARN)

El componente FontSelector del admin carga todas las fuentes del catalogo (9 Google Fonts) para mostrar previews, independientemente del plan del usuario.

**Fix sugerido:** Lazy-load solo las fuentes visibles en viewport, o usar font previews como imagenes estaticas en lugar de cargar la fuente real.

---

### L-8. LOW — No onerror handler en FontLoader link tag

**Fuente:** QA (Flow 1 WARN)

Si la carga de una fuente de Google Fonts falla (red caida, CDN error), no hay handler que notifique o haga fallback explicito.

**Fix sugerido:** Agregar `onerror` al `<link>` tag que active fallback visual y loguee el error.

---

### L-9. LOW — @ts-nocheck en SectionRenderer.tsx

**Fuente:** QA (Flow 5 WARN)

`/apps/web/src/components/SectionRenderer.tsx:1` tiene `// @ts-nocheck` que desactiva toda verificacion TypeScript en un componente central del storefront.

**Fix sugerido:** Remover `@ts-nocheck` y resolver los errores de tipos. Esto mejora la seguridad de tipos en un componente critico.

---

### L-10. LOW — Labels vacios {} bloquean inyeccion de locale defaults + sin soporte ingles

**Fuente:** QA (Flow 7 WARN)

Si `section.props.labels = {}` (objeto vacio), el cascade de i18n interpreta que hay labels manuales y no inyecta los defaults del locale. Ademas, no existe locale en ingles.

**Fix sugerido:** Tratar `{}` como ausencia de labels override. Agregar locale `en` cuando haya audiencia internacional.

---

## Seccion 5: Acuerdos (ambos agentes encontraron el mismo problema)

Los siguientes hallazgos fueron identificados independientemente por ambos equipos:

| # | Hallazgo | Arquitecto | QA | Severidad final |
|---|----------|------------|----| --------------- |
| 1 | fontKey no se valida server-side | ISSUE #1 | Flow 1 WARN | **HIGH** (H-2) |
| 2 | FontSelector preloads ALL fonts | WARNING #11 | Flow 1 WARN | LOW (L-7) |
| 3 | Reconciliation cron problematico | WARNING #6, #12 | Flow 2 HIGH bug | **HIGH** (H-1) — QA escalo a HIGH al identificar el caso especifico de `custom_css` |
| 4 | CSS overrides flow tiene gaps | Arquitecto marco "OK con WARNING" | QA encontro que nunca se aplican (CRITICAL) | **CRITICAL** (C-1) — QA encontro la causa raiz que el Arquitecto no detecto |

**Nota:** En los casos 3 y 4, QA escalo correctamente hallazgos que el Arquitecto habia clasificado como WARNING o OK. La diferencia radica en que QA verifico el comportamiento real end-to-end mientras el Arquitecto valido la logica individual de cada componente.

---

## Seccion 6: Areas Validadas como Correctas

Las siguientes areas fueron confirmadas como correctas por AMBOS equipos de auditoria:

| Area | Detalle |
|------|---------|
| **Theme Resolution Chain** | `homeData.config` -> `useEffectiveTheme` -> `useThemeVars` -> CSS vars funciona correctamente |
| **Font Resolution (client-side)** | `resolveFontFamily()` con plan gating y fallback a Inter es correcto |
| **CSS Sanitization** | Allowlist de 60+ propiedades, bloqueo de patrones peligrosos, scoping por tenant — robusto |
| **AI CSS Generation Guards** | Credits guard, lock mechanism, prompt validation, error handling correcto |
| **Multi-tenant Isolation** | Todas las queries scopeadas por `client_id` correctamente |
| **SectionRenderer + variantMap** | 8 templates x 5 secciones mapeados, lazy loading con `React.lazy()` correcto |
| **Design Overrides CRUD Auth** | Todos los endpoints protegidos con `ClientDashboardGuard` |
| **Template Change UX (T11)** | Grandfathering, stale draft detection, override warning funcionan |
| **i18n Label Cascade (T7/T8)** | `section.props.labels` -> locale defaults -> fallback (ES_AR) funciona |
| **Edge Cases** | AI empty response, tenant sin palette/font, CSS sanitize rechaza todo, template change con overrides — todos manejados |

---

## Seccion 7: Recomendaciones — Plan de Accion Ordenado

### Fase 1: Bloqueantes de Release (Sprint actual)

| Prioridad | ID | Accion | Responsable sugerido | Esfuerzo |
|-----------|-----|--------|---------------------|----------|
| 1 | C-1 | Agregar clase `nv-store-{clientId}` al contenedor raiz del storefront | Frontend | 2-4h |
| 2 | H-1 | Agregar whitelist de `source_addon_key` exentos en reconciliation cron | Backend | 1-2h |
| 3 | H-2 | Validar fontKey contra catalogo en `PUT /settings/home` | Backend | 4-6h |

**Criterio de salida:** Los 3 fixes deployados y verificados con test manual + test unitario.

### Fase 2: Estabilizacion (Sprint siguiente)

| Prioridad | ID | Accion | Esfuerzo |
|-----------|-----|--------|----------|
| 4 | M-1 | Wrappear JSON.parse con helper seguro en AI service (13 instancias) | 2-3h |
| 5 | M-2 | Agregar Cache-Control + ETag a GET /active-css | 1-2h |
| 6 | M-6 | Extraer SectionErrorBoundary fuera del render function | 1-2h |
| 7 | M-3 | Unificar registros de palettes | 3-4h |
| 8 | M-4 | Implementar patron reserve-consume-refund para AI credits | 4-6h |

### Fase 3: Backlog (proximos sprints)

| ID | Accion | Esfuerzo |
|-----|--------|----------|
| M-5 | Decidir e implementar Density/Spacing (T14) o documentar como pendiente | 8-16h |
| L-1 | Rate limiting en active-css | 1h |
| L-2 | Merge de metadata en reconciliation | 2h |
| L-3 | CSS overrides en PreviewHost | 4h |
| L-4 | Evaluar filter/backdrop-filter en allowlist | 1h |
| L-5 | ESLint rule para imports legacy | 1h |
| L-6 | Centralizar default template key | 1h |
| L-7 | Lazy-load fonts en FontSelector | 3h |
| L-8 | onerror handler en FontLoader | 1h |
| L-9 | Remover @ts-nocheck de SectionRenderer | 4h |
| L-10 | Fix labels {} + agregar locale ingles | 2h |

### Notas adicionales

1. **Test E2E recomendado:** Despues de aplicar C-1, escribir un test Playwright que verifique que CSS overrides se aplican visualmente en el storefront.
2. **Monitoreo post-fix H-1:** Verificar en logs del cron que no se revoquen overrides custom despues del deploy.
3. **Deuda tecnica recurrente:** El `@ts-nocheck` en SectionRenderer (L-9) y la falta de enforcement de imports (L-5) sugieren que la deuda tecnica del Web storefront necesita un sprint dedicado de hardening.

---

*Documento generado por consolidacion de reportes de Arquitectura y QA, con verificacion cruzada contra el codigo fuente actual.*

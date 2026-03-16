# Plan: Hardening del Contrato Compartido Step 4 ↔ Store Design

- Fecha: 2026-03-14
- Autor: GitHub Copilot
- Repos: novavision, templatetwo, novavision-docs
- Estado: fase 1 relevada
- Plan relacionado: `PLAN_STORE_DESIGN_STEP4_ALIGNMENT_EXECUTION.md`

## Objetivo

Evitar nuevas derivas entre el builder de onboarding y el dashboard de Store Design sin fusionar sus responsabilidades de negocio. El foco no es compartir código entre repos independientes, sino fijar un contrato técnico y visual estable, validable y auditable.

## Contexto del incidente que motiva este plan

1. El builder real vive en `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`.
2. El dashboard de diseño vive en `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`.
3. Ambos flujos dependen del mismo runtime de preview en `apps/web/src/pages/PreviewHost/index.tsx`.
4. Una corrección aplicada solo sobre Web generó dos problemas distintos:
   - corte funcional del preview embebido que consume Admin
   - deriva visual y de copy del dashboard respecto del Step 4
5. La causa raíz no fue un bug aislado, sino la falta de un contrato explícito entre:
   - payload `nv:preview:render`
   - política de acceso del preview embebido
   - UX base compartida entre Step 4 y Store Design

## Decisiones de arquitectura

### Se mantiene separado

- Onboarding Step 4: flujo de sesión y persistencia de onboarding.
- Store Design dashboard: flujo post-provisión, entitlements, créditos y addon store.

### Se endurece como contrato común

- `PreviewFrame` -> `/preview` -> `PreviewHost` -> `SectionRenderer`
- esquema mínimo del payload de preview
- reglas de acceso para preview embebido vs acceso directo
- matriz de labels/acciones que deben conservar equivalencia funcional
- resolución canónica de secciones para preview

## Contrato objetivo

### 1. Contrato de preview

El preview embebido debe aceptar `postMessage` cuando la política central de acceso lo permita, aun si no hay token en query string. El acceso directo a `/preview` debe seguir validando token.

Superficies afectadas:

- `apps/web/src/pages/PreviewHost/index.tsx`
- `apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx`
- `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`

### 2. Contrato de payload

El payload de `nv:preview:render` debe mantener como mínimo:

- `requestId`
- `templateKey`
- `paletteKey`
- `config.sections`
- `seed`
- `mode`

No se deben introducir campos obligatorios nuevos en un flujo sin validar el otro.

### 3. Contrato de UX funcional

Debe existir equivalencia funcional entre Admin Step 4 y Web Store Design en estos puntos:

- pestañas base: presets y edición de estructura
- affordance de preview lateral y preview completo
- labels de guardado/aplicación que afectan tests y tours
- alertas de gating de plan
- fallback visual cuando no hay secciones persistidas

No es obligatorio que el copy sea idéntico palabra por palabra en todo el flujo, pero sí que:

- no rompa tests existentes de la superficie propietaria
- no cambie affordances claves sin actualizar la otra superficie y su suite asociada

## Alcance técnico

### Admin

Archivos a revisar en implementación:

- `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
- `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.css`
- `apps/admin/src/services/builder/designSystem.ts`
- tests del builder si faltan asserts sobre labels/preview

### Web

Archivos a revisar en implementación:

- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- `apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx`
- `apps/web/src/components/admin/StoreDesignSection/resolvePreviewSections.js`
- `apps/web/src/pages/PreviewHost/index.tsx`
- `apps/web/src/__tests__/store-design-section.test.jsx`
- `apps/web/src/__tests__/preview-host.test.jsx`

### Docs

Artefactos a mantener:

- este plan
- `architecture/add_templates/ADDING_TEMPLATES_AND_COMPONENTS.md`
- changelog por cada corrección funcional futura

## Plan de trabajo

## Snapshot Fase 1 — Contrato actual relevado

### Ownership actual

| Superficie | Repo | Archivo principal | Rol real |
|---|---|---|---|
| Builder Step 4 | `novavision` | `apps/admin/src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` | UX fuente para onboarding |
| Store Design dashboard | `templatetwo` | `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx` | UX fuente para dashboard post-provisión |
| Preview runtime compartido | `templatetwo` | `apps/web/src/pages/PreviewHost/index.tsx` | Runtime transversal consumido por Admin y Web |
| Preview bridge dashboard | `templatetwo` | `apps/web/src/components/admin/StoreDesignSection/PreviewFrame.jsx` | Emisor embebido del dashboard |

### Matriz de contrato UX funcional

| Punto | Admin Step 4 | Web Store Design | Estado actual |
|---|---|---|---|
| Heading principal | `Design Studio` | `Design Studio` | alineado |
| Tab presets | `✨ Elegí base` | `✨ Elegí base` | alineado |
| Tab estructura | `🛠️ Editar estructura` | `🛠️ Editar estructura` | alineado |
| Template selector | `🧩 Elegí tu template` | `🧩 Elegí tu template` | alineado |
| Disclaimer visual | texto ilustrativo y panel azul | mismo disclaimer | alineado |
| Warning Growth | banner cuando Starter | banner cuando plan no accede a Growth | equivalente |
| Preview principal | `Full Preview` | `Full Preview` | alineado |
| CTA preview footer | `👀 Preview` | `👀 Preview` | alineado |
| Guardado de props sección | `Guardar borrador` | `Guardar borrador` | alineado |
| Aplicación de estructura | Admin conserva flujo propio de paso/publicación | `Aplicar estructura` | equivalente funcional, no idéntico de persistencia |
| Guardado visual de preset/template | Admin continúa flujo del wizard | `Guardar y aplicar diseño` | distinto por responsabilidad, aceptado |
| Catálogo de componentes | onboarding puro | dashboard + créditos/addon store | distinto por negocio, aceptado |

### Matriz de contrato de preview

| Punto | Comportamiento esperado | Estado actual |
|---|---|---|
| Acceso directo a `/preview` | requiere token válido | cubierto en Web |
| Render embebido por `postMessage` | debe aceptar payload si la política central habilita acceso, aun sin token en query | cubierto en Web |
| Payload mínimo | `requestId`, `templateKey`, `paletteKey`, `config.sections`, `seed`, `mode` | vigente |
| Parent origin | validar contra `document.referrer` o allowlist en prod | vigente en `PreviewHost` |
| Slug claim | rechazar mismatch entre token y `clientSlug` | vigente en `PreviewHost` |

### Cobertura actual relevada

| Superficie | Archivo de test | Qué cubre | Gap |
|---|---|---|---|
| Web | `apps/web/src/__tests__/preview-host.test.jsx` | acceso directo inválido, render embebido, template nativo, ready handshake | no cubre matriz completa de origins/slug mismatch |
| Web | `apps/web/src/__tests__/store-design-section.test.jsx` | tabs base, edición, guardado, upgrade, fallback runtime, preset preview | no compara contra Admin, solo contrato local del dashboard |
| Admin | `apps/admin/src/pages/BuilderWizard/steps/__tests__/Step4TemplateSelector.gating.test.tsx` | gating de componentes y salto a upgrade | no cubre preview runtime ni labels/acciones base completas |
| Admin | `apps/admin/src/pages/BuilderWizard/steps/__tests__/step4TourConfig.test.ts` | targets del tour y presencia del paso preview | no cubre render real ni CTA/footer |
| E2E | `novavision-e2e/tests/qa-v2/25-preview-parity.spec.ts` | builder preview y parity general de preview | no cubre explícitamente la matriz completa de labels/acciones |

### Gaps concretos detectados en Fase 1

1. Admin no tiene una suite que congele el contrato visual mínimo de Step 4.
2. Web sí congela parte del contrato del dashboard, pero no existe una matriz espejo para comparar con Admin.
3. El runtime de preview está bien cubierto desde Web, pero no desde Admin como consumidor.
4. La equivalencia funcional entre `Step4TemplateSelector` y `DesignStudio` hoy depende de revisión manual y changelog, no de un artefacto testable compartido.

### Acciones directas habilitadas por este snapshot

1. Agregar test de Admin que verifique heading, tabs y CTA de preview base.
2. Agregar test de Admin que verifique que Step 4 emite payload de preview con el shape mínimo esperado.
3. Mantener esta tabla como checklist obligatoria cuando se toque `Step4TemplateSelector.tsx`, `DesignStudio.jsx` o `PreviewHost/index.tsx`.

### Fase 1. Snapshot del contrato actual

Entregables:

- matriz Admin/Web con:
  - labels críticos
  - acciones críticas
  - estructura del payload de preview
  - reglas de acceso directo vs embebido
- listado de tests que cubren cada punto del contrato

Resultado esperado:

- saber exactamente qué cambios requieren actualización dual y cuáles son locales.

### Fase 2. Endurecer el contrato de preview

Tareas:

- encapsular en Web la política de acceso del preview en una helper única
- evitar condiciones duplicadas entre acceso directo y embebido
- documentar explícitamente el comportamiento esperado en tests

Resultado esperado:

- ninguna corrección de preview vuelve a romper onboarding por cambios solo en Web.

### Fase 3. Endurecer el contrato de UX funcional

Tareas:

- definir un set mínimo de labels/acciones que se consideran contrato
- marcar qué labels pertenecen a la superficie propietaria y cuáles deben mantenerse alineados
- evitar refactors visuales en Web que cambien acciones base sin pasar por comparación con Step 4

Resultado esperado:

- la paridad funcional deja de depender de memoria manual o revisión visual informal.

### Fase 4. Suite espejo mínima

Tareas:

- mantener en Web:
  - tests de preview embebido
  - tests de Store Design sobre acciones base
- agregar en Admin una suite mínima que verifique:
  - render del preview frame
  - labels/acciones del Step 4 considerados contrato
  - emisión del payload base al preview

Resultado esperado:

- una regresión en cualquiera de las dos superficies se detecta antes del push.

### Fase 5. Gate operativo de cambios duales

Tareas:

- cada cambio que toque alguno de estos archivos debe revisar explícitamente impacto cruzado:
  - `Step4TemplateSelector.tsx`
  - `DesignStudio.jsx`
  - `PreviewFrame.jsx`
  - `PreviewHost/index.tsx`
- documentar en el changelog si el cambio es:
  - solo Admin
  - solo Web
  - dual

Resultado esperado:

- menor probabilidad de cambios correctos localmente pero regresivos en la otra superficie.

## Validación obligatoria cuando se implemente

### Web

- `node scripts/ensure-no-mocks.mjs`
- `npm run lint`
- `npm run typecheck`
- `npm run build`
- `npx vitest run src/__tests__/store-design-section.test.jsx src/__tests__/preview-host.test.jsx --reporter=verbose`

### Admin

- `npm run lint`
- `npm run typecheck`
- tests del builder si se agregan en esta fase

### Smoke funcional manual

- onboarding `/builder` con preview embebido
- dashboard Store Design con preview lateral y preview completo
- cambio de template/palette
- edición de estructura y guardado

## Riesgos

1. Copys demasiado rígidos pueden volver frágiles los tests.
2. Copys demasiado laxos dejan pasar nuevas derivas.
3. Como Admin y Web son repos independientes, cualquier “shared contract” debe vivir en docs y tests espejo, no en packages compartidos.
4. El preview es dependencia transversal: un cambio pequeño ahí puede romper onboarding y dashboard al mismo tiempo.

## Criterio de salida

Se considera completado cuando:

1. exista una matriz explícita de contrato Admin/Web
2. haya cobertura mínima en ambos repos para preview y acciones base
3. el comportamiento embebido/directo del preview quede documentado y testeado
4. cualquier cambio futuro en Step 4 o Design Studio obligue a revisar impacto cruzado
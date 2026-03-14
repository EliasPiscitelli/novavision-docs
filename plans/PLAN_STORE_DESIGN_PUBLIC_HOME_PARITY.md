# Plan: Paridad Store Design Preview vs Home Pública

- Fecha: 2026-03-13
- Autor: GitHub Copilot
- Estado: Propuesta lista para validación
- Repos involucrados: templatetwobe (API), templatetwo (Web), novavision-docs
- Rama API/Admin: feature/automatic-multiclient-onboarding
- Rama Web objetivo: develop -> cherry-pick a feature/multitenant-storefront si el cambio aplica a la tienda publicada

---

## 1. Objetivo

Corregir la divergencia entre:

1. El preview del editor de Diseño de Tienda, que hoy renderiza con `previewSections` construidas desde fuentes autenticadas y fallbacks del editor.
2. La tienda publicada, que hoy renderiza desde `GET /home/data` y en el caso del tenant `farma` devuelve `config.sections: []`.

Resultado esperado:

- Lo que el usuario arma y ve en el preview del editor debe coincidir con la estructura que consume la home pública publicada.
- La fuente de verdad publicada debe respetar la arquitectura aprobada: storefront publicado -> `GET /home/data` -> `client_home_settings` + `home_sections`.

---

## 2. Hechos verificados

### 2.1 Deploy y entorno

- `farma.novavision.lat` y `app.novavision.lat` están sirviendo el mismo build de Netlify en la revisión actual.
- El deploy publicado del 2026-03-13 incluye el fix de race condition de preview, pero ese cambio no modifica el shell visible de `DesignStudio.jsx`.

### 2.2 Diferencia funcional real

- El preview del editor usa `/preview` + `postMessage`, no usa `GET /home/data` para renderizar la estructura en edición.
- La tienda publicada sí usa `GET /home/data` y depende de `homeData.config.sections`.
- En el tenant `farma`, `GET /home/data` devuelve `templateKey` y `paletteKey`, pero `config.sections` llega vacío.

### 2.3 Fuente de verdad documentada

Según `architecture/config-source-of-truth.md`:

- La configuración publicada del storefront debe salir de `client_home_settings`.
- `home_sections` es parte del contrato efectivo que termina llegando al storefront vía `GET /home/data`.
- El storefront publicado no debe depender de seeds de preview ni de lógica específica del editor.

### 2.4 Código actual relevante

#### Web

- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
  - arma `previewSections`
  - usa `identityService.getHomeSections()`
  - usa fallback `buildDefaultTemplateSections(selectedTemplate, homeData)`
- `apps/web/src/services/homeData/homeService.jsx`
  - storefront publicado consume `GET /home/data`
- `apps/web/src/pages/PreviewHost/index.tsx`
  - renderiza el iframe del preview, pero no resuelve la publicación real

#### API

- `apps/api/src/home/home-settings.service.ts`
  - lee `client_home_settings`
  - intenta poblar `sections` desde `design_config.sections` o `home_sections`
- El comportamiento observado indica que para algunos tenants la capa publicada no está resolviendo la misma estructura efectiva que usa el editor.

---

## 3. Diagnóstico

### Causa raíz principal

Hoy existen dos pipelines distintos para la estructura del home:

1. Pipeline del editor:
   - `identityService.getHomeSections()`
   - drafts locales
   - `resolvePreviewSections(...)`
   - fallback `buildDefaultTemplateSections(...)`

2. Pipeline de la tienda publicada:
   - `GET /home/data`
   - `HomeSettingsService.getSettings()`
   - `homeData.config.sections`

Cuando el pipeline publicado no devuelve secciones efectivas, el preview puede verse correcto y la home pública seguir vacía o distinta.

### Hipótesis técnica prioritaria

La discrepancia no está en el iframe ni en el deploy actual, sino en una de estas capas:

1. `home_sections` no refleja correctamente la estructura publicada del tenant.
2. `client_home_settings.design_config.sections` no está sincronizado con la estructura real.
3. `HomeSettingsService.getSettings()` no está construyendo `sections` con la misma lógica efectiva que el editor.
4. Existe una brecha entre estructura publicada persistida y fallback visual del editor.

---

## 4. Alcance

### Alcance principal: Ambos

#### API

- Unificar la resolución de `sections` efectivas para `GET /home/data`.
- Garantizar que la publicación exponga la misma estructura que el editor considera vigente.

#### Web

- Validar que el editor use la misma semántica de estructura efectiva que la home publicada.
- Agregar prueba de paridad para evitar regresiones futuras.

#### Docs

- Registrar la decisión final y la estrategia de validación en `novavision-docs/changes/` cuando se implemente.

---

## 5. Plan de trabajo

### Fase 1. Auditoría de persistencia publicada

Objetivo: identificar cuál es la fuente efectiva real del tenant afectado.

Tareas:

1. Verificar para el tenant afectado el contenido de:
   - `client_home_settings`
   - `home_sections`
   - `clients.template_id`
2. Confirmar si el editor está leyendo estructura publicada real o estructura enriquecida por fallback local.
3. Confirmar si `design_config.sections` existe y si está obsoleta respecto de `home_sections`.

Entregable:

- Matriz de diagnóstico por tenant con fuente real de `templateKey`, `paletteKey` y `sections`.

Riesgo:

- Diagnosticar solo con frontend puede ocultar un problema de sincronización en DB.

### Fase 2. Definir fuente única de `sections` publicadas

Objetivo: eliminar la ambigüedad de resolución para la home publicada.

Decisión recomendada:

1. `GET /home/data` debe devolver `config.sections` desde una única resolución server-side.
2. El orden de resolución debe quedar explícito y documentado.
3. Si no hay estructura persistida válida, el fallback debe ser controlado y consistente, no implícito ni solo del editor.

Propuesta técnica inicial:

1. Priorizar `home_sections` activas y ordenadas.
2. Si no existen, usar `client_home_settings.design_config.sections` solo como respaldo explícito y auditado.
3. Si tampoco existen, devolver fallback server-side determinístico basado en template activo y datos reales del tenant.
4. Loggear cuándo se activa el fallback para detectar tiendas mal provisionadas.

Entregable:

- Contrato único de resolución de `config.sections` publicado.

Riesgo:

- Si se cambia el fallback sin cubrir casos legacy, algunas tiendas pueden cambiar visualmente al publicar.

### Fase 3. Alinear el editor con la resolución publicada

Objetivo: que el preview y la publicación compartan la misma semántica de estructura efectiva.

Tareas:

1. Revisar si el editor debe seguir armando `previewSections` con lógica propia o consumir una versión server-side de estructura efectiva.
2. Minimizar divergencias entre:
   - `resolvePreviewSections(...)`
   - la resolución de `GET /home/data`
3. Mantener el preview de draft sin romper la edición no publicada.

Decisión recomendada:

1. Mantener preview de draft para cambios locales.
2. Separar explícitamente:
   - `publishedSections`
   - `draftSections`
   - `effectivePublishedSections`
3. Mostrar en UI cuando el preview corresponde a draft no publicado.

Entregable:

- Semántica clara entre preview de edición y home publicada.

### Fase 4. Pruebas de regresión y paridad

Objetivo: evitar volver a romper la coincidencia entre editor y publicación.

Tareas:

1. Test unit/integration en API para `HomeSettingsService.getSettings()`:
   - con `home_sections`
   - con `design_config.sections`
   - con fallback server-side
2. Test frontend para normalización y consumo de `homeData.config.sections`.
3. Test E2E o smoke test que compare:
   - estructura publicada en `/home/data`
   - estructura efectiva mostrada como publicada en el editor

Entregable:

- Suite mínima que detecte `config.sections: []` cuando el tenant sí tiene una estructura efectiva esperable.

---

## 6. Archivos a tocar

### API

- `apps/api/src/home/home-settings.service.ts`
- `apps/api/src/home/home.service.ts`
- `apps/api/src/home/home.controller.ts`
- tests asociados en `apps/api/src/home/**/*.spec.ts` o `apps/api/test/**`

### Web

- `apps/web/src/components/admin/StoreDesignSection/DesignStudio.jsx`
- `apps/web/src/services/homeData/homeService.jsx`
- `apps/web/src/services/identity.js`
- tests en `apps/web/src/**/__tests__/**`

### Docs

- `novavision-docs/changes/YYYY-MM-DD-store-design-public-home-parity.md`

---

## 7. Validaciones requeridas

### API

- `npm run lint`
- `npm run typecheck`
- `npm run build`

### Web

- `node scripts/ensure-no-mocks.mjs`
- `npm run lint`
- `npm run typecheck`
- `npm run build`

### Validación funcional mínima

1. Abrir `admin-dashboard?storeDesign` en un tenant real.
2. Identificar estructura publicada efectiva en el editor.
3. Consultar `GET /home/data` del mismo tenant.
4. Verificar que `config.sections` coincide con la estructura publicada esperada.
5. Verificar que el preview draft sigue funcionando sin bloquear la edición.

---

## 8. Riesgos

### Riesgo 1. Cambiar la publicación de tenants legacy

Si algunos tenants dependían sin saberlo del fallback local del editor, al mover el fallback al server podrían aparecer cambios visuales al publicar.

Mitigación:

- activar logs de fallback
- validar primero con tenants reales representativos
- documentar cualquier tenant que requiera backfill de `home_sections`

### Riesgo 2. Confundir draft con publicado

Si el editor muestra cambios locales y el usuario interpreta que ya están publicados, seguirá habiendo tickets de “se ve distinto”.

Mitigación:

- distinguir visualmente draft vs publicado
- no reutilizar la misma etiqueta para ambos estados

### Riesgo 3. Resolver paridad desde frontend en lugar de corregir la fuente

Parchear solo `DesignStudio.jsx` no corrige la home publicada.

Mitigación:

- atacar primero la resolución server-side de `GET /home/data`
- usar frontend solo para representar mejor el estado real

---

## 9. Criterios de aceptación

1. Para un tenant con estructura publicada válida, `GET /home/data` no devuelve `config.sections: []`.
2. La home publicada renderiza la misma estructura efectiva que el editor considera publicada.
3. El preview draft sigue permitiendo cambios no publicados sin romper el flujo actual.
4. La lógica de resolución de `sections` queda documentada y testeada.
5. Si se aplica fallback, queda trazado por logs y con comportamiento determinístico.

---

## 10. Recomendación ejecutiva

La prioridad correcta no es seguir tocando el iframe del preview. La prioridad es cerrar el contrato server-side de `GET /home/data` para que la publicación tenga una fuente efectiva de `sections` consistente.

Orden recomendado de ejecución:

1. corregir API y contrato publicado
2. agregar tests de paridad
3. recién después ajustar la UX del editor para representar mejor draft vs publicado

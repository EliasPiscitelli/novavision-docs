# Plan: Store Design Self-Serve Editor estilo Step 4

- Fecha: 2026-03-11
- Autor: GitHub Copilot
- Rama base: feature/automatic-multiclient-onboarding / develop / feature/multitenant-storefront
- Repos involucrados: Web (templatetwo), API (templatetwobe), Admin (novavision), Docs
- Estado: planificación funcional y técnica previa a implementación

## 1. Objetivo

Rediseñar Store Design para que editar templates, estructura visual y theme sea tan claro y guiado como el Step 4 del onboarding, pero operando sobre la data real de la tienda.

El objetivo no es priorizar configuraciones técnicas sino una experiencia self-serve entendible para admins no técnicos, con tres principios obligatorios:

1. La edición debe sentirse visual, guiada y reversible.
2. El costo de cada acción debe ser visible antes de guardar.
3. Si falta un token, crédito o plan, la UI debe empujar la compra o upgrade de forma clara y accionable.

## 2. Problema actual

## 2.1 Problema de UX

Hoy Store Design funciona, pero la experiencia no tiene la claridad mental del Step 4.

Problemas detectados:

- la edición mezcla template, palette, estructura y props en una misma superficie;
- la estructura se percibe como una lista técnica, no como un canvas de página;
- el reemplazo de componentes no se entiende como una biblioteca visual;
- el usuario no sabe con claridad qué está pagando, qué consume créditos y qué requiere upgrade;
- el bloqueo por plan o por falta de créditos no se convierte en una acción comercial clara;
- los props se pueden editar, pero la experiencia no parece un editor de storefront sino un panel de configuración.

## 2.2 Problema técnico

Hay una restricción estructural importante:

- Step 4 trabaja sobre `componentKey` y variantes concretas;
- Store Design hoy persiste estructura mediante `home_sections` usando `type` y `new_type`;
- por eso hoy se puede lograr una UX mucho mejor en frontend, pero la paridad total con Step 4 requiere extender el contrato backend para soportar variantes persistidas.

## 3. Estado actual reutilizable

## 3.1 Web Store Design

Ya existen piezas aprovechables en:

- `src/components/admin/StoreDesignSection/index.jsx`
- `src/components/admin/StoreDesignSection/SectionPropsEditor.jsx`
- `src/components/admin/StoreDesignSection/resolvePreviewSections.js`
- `src/components/admin/StoreDesignSection/previewPresetSections.js`

Capacidades ya disponibles:

- cargar template y palette actuales;
- cargar `home_sections` y registry;
- agregar, reemplazar, reordenar, editar props y borrar secciones;
- preview embebido con seed real de la tienda;
- cálculo de créditos necesarios para cambios visuales;
- detección de addons requeridos y saldos disponibles.

## 3.2 Onboarding Step 4

En `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx` ya existe el estándar UX de referencia.

Capacidades ya probadas:

- biblioteca visual de componentes;
- estructura editable con mental model claro;
- gating por plan;
- `trackUpgradeIntent()` ante intentos bloqueados;
- flujo de selección mucho más entendible para usuario final.

## 3.3 Comercial / Addon Store

Ya hay contratos comerciales concretos que deben reutilizarse y no rediseñarse desde cero:

- `ws_action_template_change`
- `ws_action_theme_change`
- `ws_action_structure_edit`
- `ws_extra_growth_visual_asset`

También existe la ruta de upgrade de plan y tracking de intención:

- `requestPlanUpgrade(...)`
- `trackUpgradeIntent(...)`

## 4. Visión de producto objetivo

La experiencia final debe sentirse como un editor visual en tres pasos persistentes y simples:

1. `Página`
   Admin edita estructura, orden y bloques visibles.
2. `Template`
   Admin cambia base visual / layout general.
3. `Theme`
   Admin cambia paleta, tono, estilo y detalles visuales.

La pantalla debe responder tres preguntas sin esfuerzo:

1. Qué estoy editando.
2. Qué impacto visual tiene.
3. Cuánto cuesta aplicarlo y qué necesito comprar si no me alcanza.

## 5. Principios UX/UI obligatorios

## 5.1 Claridad de navegación

- No mezclar estructura con colores ni con detalles finos de props.
- Mantener un layout estable de editor.
- Evitar formularios largos y técnicos a primera vista.

## 5.2 Visual-first

- Toda opción importante debe representarse por cards, thumbnails, badges y preview.
- El admin debe elegir visualmente, no leyendo claves técnicas.

## 5.3 Costos siempre visibles

- Cada cambio debe indicar si consume crédito, genera recargo o exige upgrade.
- El resumen económico debe estar presente antes del guardado.

## 5.4 Bloqueo comercial accionable

- Si no puede usar algo, la UI no debe solo decir “no disponible”.
- Debe decir qué falta, cuánto cuesta y ofrecer CTA.

## 5.5 Preview útil incluso con límites

- Si un recurso premium no puede renderizarse completo, la UI debe mostrar placeholder comercial y no error técnico.

## 6. Alcance funcional del rediseño

## 6.1 Superficie principal del editor

La nueva pantalla de Store Design debe estructurarse en tres columnas o tres áreas fuertes:

- izquierda: biblioteca / navegación;
- centro: canvas y preview de la página;
- derecha: panel contextual del elemento seleccionado.

### Columna izquierda: Biblioteca y navegación

Debe contener:

- tabs `Página`, `Template`, `Theme`;
- categorías visuales de bloques;
- cards de templates;
- cards de themes/palettes;
- badges de plan mínimo y costo por acción;
- estado de bloqueo con CTA.

### Centro: Canvas de página

Debe contener:

- lista visual de secciones reales de la página;
- handle de drag & drop;
- inserciones “Agregar bloque acá”;
- preview sincronizado con la data real;
- skeletons/placeholders cuando algo no se puede incrustar.

### Derecha: Inspector contextual

Debe contener:

- datos del bloque seleccionado;
- acciones de `Editar`, `Reemplazar`, `Duplicar`, `Mover`, `Eliminar`;
- props agrupados por “Contenido”, “Layout”, “Estilo”, “Acciones”;
- modo avanzado opcional, colapsado.

## 6.2 Barra económica persistente

Debe existir una barra sticky o footer comercial con:

- cambios pendientes;
- créditos disponibles;
- costo único estimado;
- impacto mensual si aplica;
- recargo de tier si aplica;
- CTA principal de guardado o compra.

Ejemplos de copy esperados:

- `Este cambio consume 1 crédito de Template Change`.
- `Te falta 1 crédito para guardar este theme`.
- `Este asset requiere Growth. Podés subirte de plan o comprar el recargo visual.`
- `Total a aplicar ahora: USD 34`.

## 6.3 Gating comercial dentro del editor

Todo bloqueo debe resolver una de estas rutas:

### Ruta A: crédito faltante

- mostrar precio;
- mostrar saldo actual;
- CTA `Comprar crédito`.

### Ruta B: plan insuficiente

- mostrar plan requerido;
- mostrar beneficio del upgrade;
- CTA `Subirme a Growth` o `Ver planes`.

### Ruta C: recargo por tier superior

- mostrar costo base + surcharge;
- explicar por qué aplica;
- CTA `Comprar recargo` o `Upgrade completo`.

## 7. Fases de implementación

## Fase 1: UX shell tipo Step 4 sobre contrato actual

Objetivo: rehacer Store Design visualmente sin esperar cambios backend.

### Entregables

1. Reorganizar `StoreDesignSection` en tabs `Página`, `Template`, `Theme`.
2. Reemplazar selects y listas técnicas por cards y biblioteca visual.
3. Convertir la estructura actual en un canvas entendible con acciones inline.
4. Mantener el contrato actual de `home_sections` (`type/new_type`).
5. Unificar copy, badges y jerarquía visual.

### Resultado esperado

Aunque internamente siga usando `type`, el admin ya percibe una experiencia tipo Step 4.

## Fase 2: Costos visibles y upsell contextual

Objetivo: integrar la lógica comercial al editor como parte de la experiencia.

### Entregables

1. Barra sticky de costos y cambios pendientes.
2. Cards con precio, plan mínimo y consumo esperado.
3. Drawer/modal de compra contextual desde el editor.
4. Integración explícita con:
   - `ws_action_template_change`
   - `ws_action_theme_change`
   - `ws_action_structure_edit`
   - `ws_extra_growth_visual_asset`
5. Eventos de tracking con `trackUpgradeIntent()`.

### Resultado esperado

No hay bloqueos mudos: toda fricción tiene salida comercial inmediata.

## Fase 3: Editor de props visual y simplificado

Objetivo: convertir el panel derecho en un verdadero customizer.

### Entregables

1. Reordenar `SectionPropsEditor` en grupos de campos.
2. Dar prioridad a toggles, presets y controles visuales.
3. Dejar JSON/raw como modo experto colapsado.
4. Sincronizar preview en tiempo real.

### Resultado esperado

Editar una sección deja de sentirse como tocar configuración interna.

## Fase 4: Preview resiliente y comercialmente útil

Objetivo: que el preview siempre ayude a vender o decidir.

### Entregables

1. Placeholders elegantes para contenido bloqueado por CSP o plan.
2. Estados seguros para mapas, videos o embeds externos.
3. Mensajes accionables dentro del preview.
4. Consistencia entre canvas y preview embebido.

### Resultado esperado

El preview nunca queda “roto”; siempre comunica valor o próximo paso.

## Fase 5: Paridad real con Step 4 vía `componentKey` ✅ COMPLETADA

Objetivo: habilitar reemplazo real de variantes, no solo por `type`.

### Entregables backend

1. ✅ Extender DTOs de `home_sections` para aceptar `componentKey`.
2. ✅ Extender persistencia y registry para variantes concretas (`VARIANT_REGISTRY` con 68 variantes).
3. ✅ Mantener compatibilidad retro con `type`.
4. ✅ Exponer al frontend qué variantes son válidas por familia y plan (`GET sections/registry` → `variants[]`).

### Resultado esperado

Store Design queda equivalente a Step 4 en capacidad estructural, pero con datos reales del tenant.

## 8. Repos y archivos impactados

## 8.1 Web

### Editor principal

- `src/components/admin/StoreDesignSection/index.jsx`
- `src/components/admin/StoreDesignSection/style.js` o equivalente

### Editor contextual

- `src/components/admin/StoreDesignSection/SectionPropsEditor.jsx`

### Preview y resolución

- `src/components/admin/StoreDesignSection/resolvePreviewSections.js`
- `src/components/admin/StoreDesignSection/previewPresetSections.js`
- `src/preview/PreviewProviders.tsx`
- `src/pages/PreviewHost/index.tsx`

### Servicios

- `src/services/identity.js`
- `src/services/subscriptionManagement.js`

### Tests

- `src/__tests__/store-design-section.test.jsx`
- tests nuevos de gating comercial y barra de costos

## 8.2 Admin

### Referencia funcional y patrones a reutilizar

- `src/pages/BuilderWizard/steps/Step4TemplateSelector.tsx`
- `src/services/builder/api.ts`

## 8.3 API

### Etapa posterior para paridad real

- `src/home/dto/section.dto.ts`
- `src/home/home-sections.service.ts`
- `src/home/home.controller.ts`

## 9. Contrato comercial que se debe respetar

## 9.1 Créditos / acciones ya existentes

El rediseño debe reutilizar y visibilizar:

- `ws_action_template_change`
- `ws_action_theme_change`
- `ws_action_structure_edit`
- `ws_extra_growth_visual_asset`

## 9.2 Copy comercial requerido

Toda UI bloqueada debe responder:

- qué cambio intentó hacer el admin;
- qué le falta para aplicarlo;
- cuánto cuesta;
- qué consigue si compra;
- cuál es el CTA directo.

## 9.3 Motivación / persuasión esperada

La UI debe motivar compra o upgrade sin sentirse agresiva.

Ejemplos:

- `Desbloqueá esta base visual para elevar la percepción premium de tu tienda.`
- `Con 1 crédito más podés aplicar este cambio ahora mismo.`
- `Growth te habilita este componente y además evita recargos unitarios futuros.`

## 10. Métricas de éxito

## 10.1 UX

- reducción del tiempo para completar un cambio visual simple;
- reducción de errores o abandonos al editar estructura;
- menor dependencia de soporte para cambios de template/theme.

## 10.2 Negocio

- aumento en compra de `template_change` y `theme_change`;
- aumento en conversión de upgrade desde intents bloqueados;
- mayor uso de créditos de estructura cuando la experiencia sea clara.

## 10.3 Técnica

- sin degradar preview;
- sin dobles consumos de créditos;
- sin desacople entre `home_sections` y storefront runtime.

## 11. Riesgos y mitigaciones

## 11.1 Riesgo: prometer Step 4 completo sin soporte backend

Mitigación:

- dejar explícito que Fase 1 a 4 mejoran UX fuerte pero no resuelven persistencia por variante;
- planificar Fase 5 como trabajo de API.

## 11.2 Riesgo: exceso de complejidad comercial en pantalla

Mitigación:

- mostrar costo resumido en la barra sticky;
- llevar el detalle a drawer/modal contextual;
- evitar saturar cada card con texto largo.

## 11.3 Riesgo: doble cobro o consumo confuso

Mitigación:

- usar mensajes pre-save y post-save consistentes;
- mantener hash de cambios para no consumir sin diff real;
- testear explícitamente consumos `before/after`.

## 11.4 Riesgo: divergencia entre editor y runtime

Mitigación:

- seguir priorizando `home_sections` donde corresponda;
- validar preview y storefront real sobre la misma fuente de verdad.

## 12. Orden recomendado de ejecución

1. Fase 1: UX shell tipo Step 4.
2. Fase 2: costos visibles y upsell contextual.
3. Fase 3: simplificación del inspector de props.
4. Fase 4: preview resiliente y placeholders comerciales.
5. Fase 5: backend con `componentKey` y variantes reales.

## 13. Recomendación ejecutiva

No esperar al backend para mejorar la experiencia.

Se recomienda avanzar ya con Fase 1 a 4 en Web, porque el dolor principal hoy es de UX/comprensión y de visibilidad comercial. Eso debería resolver la mayor parte de la fricción percibida por el admin.

La Fase 5 debe tratarse como una expansión explícita del contrato de `home_sections` para alcanzar paridad real con Step 4.

Mientras esa fase no exista, el objetivo correcto no es “copiar Step 4 1:1”, sino construir una experiencia igual de clara y vendible usando el contrato actual.
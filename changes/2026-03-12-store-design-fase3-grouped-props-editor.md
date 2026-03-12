# Cambio: Fase 3 – Editor de props visual con grupos y modo experto

- **Autor:** agente-copilot
- **Fecha:** 2026-03-12
- **Rama API:** feature/automatic-multiclient-onboarding
- **Rama Web:** feature/onboarding-preview-stable

## Archivos modificados

### API (templatetwobe)
- `src/home/registry/sections.ts` — Nuevo tipo `EditorFieldGroup`, propiedad `group` en `SectionEditorField`, asignación de grupo a los ~50 campos de las 8 secciones

### Web (templatetwo)
- `src/components/admin/StoreDesignSection/SectionPropsEditor.jsx` — Refactor completo: grupos colapsables, modo experto JSON, presets arriba
- `src/components/admin/StoreDesignSection/style.jsx` — 5 nuevos styled components para grupos y panel experto

## Resumen del cambio

Implementación de la **Fase 3 del plan PLAN_STORE_DESIGN_STEP4_SELF_SERVE_EDITOR**: "Editor de props visual y simplificado".

### Entregables completados

1. **Agrupamiento de campos por categoría** — Los `editorFields` ahora soportan una propiedad `group` con valores: `content`, `layout`, `style`, `actions`, `data`. El editor renderiza cada grupo en un panel colapsable con ícono y label descriptivo.

2. **Prioridad visual a presets y toggles** — Los presets se renderizan primero (antes de los grupos). Los toggles/acciones tienen su propio grupo visual separado de contenido, evitando que se pierdan entre campos de texto.

3. **Modo experto JSON colapsado** — Un toggle "Modo experto (JSON)" al final del editor muestra el JSON completo de las props en formato read-only, como referencia técnica. Ya no es el fallback principal.

4. **Retrocompatibilidad total** — Si los campos no tienen `group`, el editor se comporta idéntico al anterior (flat grid). El agrupamiento es opt-in.

### Asignación de grupos por sección

| Sección | content | layout | style | actions | data |
|---------|---------|--------|-------|---------|------|
| hero | título, bajada, CTA | — | background_image | — | — |
| video_banner | URL video, título, bajada | — | — | autoplay, silenciado | — |
| product_carousel | título | max_items | — | show_price | — |
| product_grid | título | columnas, max_items | — | — | — |
| testimonials | título | — | — | — | items (lista) |
| team_gallery | título | — | — | — | members (lista) |
| services_grid | título | — | — | — | services (lista) |
| contact_form | título, bajada, desc, CTA | layout, align, spacing | — | enabled, showMap, showContact, showSocial | mapa, dirección, tel, WA, email, horarios, redes |

## Cómo probar

1. Levantar API: `npm run start:dev` (terminal back)
2. Levantar Web: `npm run dev` (terminal front)
3. Ir a Admin → Store Design → seleccionar cualquier sección
4. Verificar que el inspector derecho muestre los campos organizados en grupos colapsables
5. Verificar que el toggle "Modo experto (JSON)" aparezca abajo y muestre el JSON
6. Verificar que secciones sin `group` en sus fields (si las hubiera) se muestren flat

## Notas de seguridad

- Sin impacto en seguridad. Los cambios son puramente de presentación/UX.
- La propiedad `group` es metadata de display, no afecta validación ni persistencia.
